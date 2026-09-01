# frozen_string_literal: true

require "rails_helper"

# 步 20c：F5 併發壓測欠帳（20 步方案步 20 原文：「50 執行緒同 checkout：
# 訂單恰一＋顧客統計不漂」）。
#
# 🔴 use_transactional_tests = false：跨連線列鎖／條件式 UPDATE／唯一索引
# 三層互斥是被測物，transactional fixtures 下其他執行緒看不到未 commit 資料
# （同 inventory/adjust_concurrency_spec 骨架）。
#
# 🔴 防線分層誠實登記（mutation-not-red-triage 紀律）：三層各自可獨立擋住
# 本情境（FOR UPDATE／open→completed 條件轉移／uq_orders_checkout_id），
# 單層突變會被其餘層接住＝預期內殺不掉（defense-in-depth）；壓測輪的
# 複合突變（鎖＋條件轉移同時退化）見 worklog MS-1 紀錄。
RSpec.describe "Order creation stress (F5)", type: :request do
  self.use_transactional_tests = false

  def purge!
    WebhookDelivery.unscoped.delete_all
    WebhookSubscription.unscoped.delete_all
    EventDelivery.unscoped.delete_all
    EventOutbox.unscoped.delete_all
    Event.unscoped.delete_all
    RefundLineItem.unscoped.delete_all
    Refund.unscoped.delete_all
    Fulfillment.unscoped.delete_all
    FulfillmentOrder.unscoped.delete_all
    OrderTransaction.unscoped.delete_all
    LineItem.unscoped.delete_all
    Order.unscoped.delete_all
    Checkout.unscoped.delete_all
    CartLineItem.unscoped.delete_all
    Cart.unscoped.delete_all
    CustomerMarketingConsent.unscoped.delete_all
    CustomerAddress.unscoped.delete_all
    Customer.unscoped.delete_all
    ShopPaymentMethod.unscoped.delete_all
    DiscountRedemption.unscoped.delete_all if defined?(DiscountRedemption)
    IdempotencyKey.unscoped.delete_all
    InventoryAdjustment.unscoped.delete_all
    InventoryAdjustmentGroup.unscoped.delete_all
    InventoryLevel.unscoped.delete_all
    InventoryItem.unscoped.delete_all
    ProductVariant.unscoped.delete_all
    Product.unscoped.delete_all
    ResourcePublication.unscoped.delete_all
    Channel.unscoped.delete_all
    Publication.unscoped.delete_all
    SalesCatalog.unscoped.delete_all
    AppInstallation.unscoped.delete_all
    Translation.unscoped.delete_all
    TranslationStatus.unscoped.delete_all
    Market.unscoped.delete_all
    Domain.unscoped.delete_all
    ShopLocale.unscoped.delete_all
    ShippingRate.unscoped.delete_all
    ShippingZone.unscoped.delete_all
    ShippingProfile.unscoped.delete_all
    Location.unscoped.delete_all
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "stress-shop") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit",
                                additional_details: "轉帳到 000-000",
                                payment_instructions: "回傳收據後 1 個工作天內確認。")
    end
  end
  let!(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000, requires_shipping: true,
                 inventory_policy: "deny",
                 product: create(:product, shop:, status: "active", title: "壓測商品"))
      v.inventory_item.update!(tracked: true)
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      v
    end
  end

  before do
    host! "stress-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  # 走真 storefront 流建 checkout（單執行緒前置；同 storefront_order_creation_spec 形）
  def ready_checkout!
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 2 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment", params: { payment_method_id: pay_method.id }
    ActsAsTenant.with_tenant(shop) do
      checkout = Checkout.find_by!(token:)
      checkout.update!(email: "stress@example.com") # 顧客統計軸需要 email
      checkout
    end
  end

  def in_threads(count)
    barrier = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        barrier.pop
        yield(index)
      rescue StandardError => e
        e
      end
    end
    count.times { barrier << true }
    threads.map(&:value)
  end

  it "ST1 🔴 50 執行緒同 checkout（相異冪等鍵）：訂單恰一、統計不漂、庫存/計數器單次" do
    checkout = ready_checkout!
    counter_before = shop.reload.order_counter
    level = ActsAsTenant.with_tenant(shop) { variant.inventory_item.inventory_levels.order(:id).first }

    results = in_threads(50) do |index|
      Orders::CreateFromCheckout.call(
        shop:, checkout_token: checkout.token,
        idempotency_key: "stress-#{index}", cart: nil)
    end

    # 恰一張訂單；每個「成功形」結果都指向同一張（completed 分支回放既有單）
    orders = Order.unscoped.where(shop_id: shop.id)
    expect(orders.count).to eq(1)
    order = orders.first
    winner_ids = results.filter_map { |r| r.is_a?(Hash) ? r[:resource]&.id : nil }.uniq
    expect(winner_ids).to eq([ order.id ])
    # 其餘一律是已定義的輸家形：CHECKOUT_NOT_OPEN 或 Guard 併發衝突（無未知例外）
    losers = results.reject { |r| r.is_a?(Hash) }
    expect(losers).to all(
      satisfy do |e|
        (e.is_a?(Orders::CreateFromCheckout::Failure) && e.code == "CHECKOUT_NOT_OPEN") ||
          e.is_a?(Idempotency::Guard::Conflict)
      end
    )

    # 顧客統計不漂（16 §F6.1 原子增量恰一次）
    customer = Customer.unscoped.find_by(shop_id: shop.id, email: "stress@example.com")
    expect(customer.orders_count).to eq(1)
    expect(customer.total_spent_cents).to eq(order.total_cents)

    # 庫存單次（qty 2）：committed +2、available −2——不隨 50 執行緒翻倍
    expect(level.reload.committed).to eq(2)
    expect(level.available).to eq(3)

    # 計數器單次＋outbox 恰一顆 orders/create
    expect(shop.reload.order_counter).to eq(counter_before + 1)
    expect(EventOutbox.unscoped.where(shop_id: shop.id, topic: "orders/create").count).to eq(1)
  end
end
