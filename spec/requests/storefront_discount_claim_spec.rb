# frozen_string_literal: true

require "rails_helper"

# G6 步 9a：折扣認領（17-F3——成立期原子操作才是真相）。
#
# 🔴 假綠殺手：
#   U1 usage_limit 條件式 UPDATE（殺：先讀後判——超發；WHERE 缺 times_used<limit）
#   U2 once_per_customer 唯一索引（殺：大小寫變體繞過——email 未正規化就 hash）
#   U3 applications 快照回放（殺：漏寫——退款 16-F5 與報表斷糧）
RSpec.describe "storefront discount claim", type: :request do
  let!(:shop) { create(:shop, subdomain: "dclaim") }
  let!(:pay_method) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit")
    end
  end
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000,
                 product: create(:product, shop:, status: "active", title: "折扣測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 50)
      v
    end
  end

  before do
    host! "dclaim.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def build_discount(**attrs)
    defaults = { shop_id: shop.id, title: "九折碼", discount_class: "order", method: "code",
                 code: "SAVE10", value_type: "percentage", percentage_basis_points: 1000,
                 status: "active" }
    ActsAsTenant.with_tenant(shop) { Discount.create!(defaults.merge(attrs)) }
  end

  # 建 checkout → 掛碼 → delivery 重算（折扣求值點）→ payment。
  def ready_checkout_with_code!(code:, email: "buyer@example.com")
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 2 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    ActsAsTenant.with_tenant(shop) do
      Checkout.find_by!(token:).update!(discount_code: Discount.normalize_code(code), email:)
    end
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment", params: { payment_method_id: pay_method.id }
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  def complete!(checkout)
    post "/checkouts/#{checkout.token}/complete"
    ActsAsTenant.with_tenant(shop) { Order.find_by(checkout_id: checkout.id) }
  end

  it "🔴 U3 求值→快照→成單回放：折 2000、applications 列齊、times_used+1" do
    discount = build_discount
    checkout = ready_checkout_with_code!(code: "save10")
    expect(checkout.discount_cents).to eq(2000) # 20000 的 10%
    expect(checkout.discount_applications_snapshot.size).to eq(1)

    order = complete!(checkout)
    expect(order).to be_present
    expect(order.discount_cents).to eq(2000)
    ActsAsTenant.without_tenant do
      apps = DiscountApplication.where(order_id: order.id)
      expect(apps.where(line_item_id: nil).sum(:amount_cents)).to eq(2000)
      expect(apps.where.not(line_item_id: nil).sum(:amount_cents)).to eq(2000) # 行級 Σ 同額
      expect(discount.reload.times_used).to eq(1)
    end
  end

  it "🔴 U1 usage_limit=1：第二單在成立期被擋（rollback 無訂單列）" do
    build_discount(usage_limit: 1)
    first = ready_checkout_with_code!(code: "SAVE10", email: "a@example.com")
    expect(complete!(first)).to be_present

    # 第二張 checkout 在求值期軟檢會擋——繞過軟檢模擬 TOCTOU（快照已含折扣、
    # 但成立前額度被搶走）：手工把快照塞回
    second = ready_checkout_with_code!(code: "SAVE10", email: "b@example.com")
    ActsAsTenant.with_tenant(shop) do
      second.update!(discount_applications_snapshot: first.discount_applications_snapshot,
                     discount_cents: 2000)
    end
    order2 = complete!(second)
    expect(order2).to be_nil, "條件式 UPDATE 沒擋住＝超發（17-F3 經典事故）"
  end

  it "🔴 U2 once_per_customer：同 email 大小寫變體第二單被擋" do
    build_discount(once_per_customer: true)
    first = ready_checkout_with_code!(code: "SAVE10", email: "Same@Example.com")
    expect(complete!(first)).to be_present

    second = ready_checkout_with_code!(code: "SAVE10", email: "same@EXAMPLE.com")
    # 求值期軟檢靠 customer_key（未登入拿不到）⇒ 這正是唯一索引要接住的窗
    order2 = complete!(second)
    expect(order2).to be_nil, "email 變體繞過 once_per_customer＝正規化後 hash 沒做"
  end

  it "無碼結帳不受影響（discounts 空清單走原路）" do
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment", params: { payment_method_id: pay_method.id }
    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.discount_cents).to eq(0)
    expect(complete!(checkout)).to be_present
  end
end
