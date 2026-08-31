# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：退款軟上限的**併發**測試（16 §F5.1(d) 的 C1 情境）。
#
# 🔴 存在理由：軟上限的執行方式＝條件式 UPDATE（先 SELECT 再判斷會有 TOCTOU 窗）。
#   本檔證明兩個並發退款不能合計突破 captured；把 apply_cumulative_cap! 改成
#   先讀後寫（mutation 輪 M-C1）必須讓本檔轉紅。
#
# 🔴 MRI GIL 下單純開兩執行緒會自然序列化（handle_change_concurrency_spec 檔頭
#   實踩教訓）⇒ 用 gate 把 B 卡在條件式 UPDATE 之前、讓 A 先完成——這正是
#   TOCTOU 攻擊的到達順序。
RSpec.describe Refunds::Create, "concurrency" do
  self.use_transactional_tests = false

  # 🔴 purge 順序由外鍵決定（six-purge 家族第七份；本包新增訂單/退款鏈在最前——
  # 子先於父：refund_line_items → refunds → events → transactions → line_items →
  # fulfillments → fulfillment_orders → orders）。其餘照 handle_change 現行版。
  def purge!
    EventOutbox.unscoped.delete_all
    RefundLineItem.unscoped.delete_all
    Refund.unscoped.delete_all
    Event.unscoped.delete_all
    OrderTransaction.unscoped.delete_all
    LineItem.unscoped.delete_all
    Fulfillment.unscoped.delete_all
    FulfillmentOrder.unscoped.delete_all
    Order.unscoped.delete_all
    UrlRedirect.unscoped.delete_all
    IdempotencyKey.unscoped.delete_all
    InventoryLevel.unscoped.delete_all
    InventoryItem.unscoped.delete_all
    Location.unscoped.delete_all
    ProductVariantOptionValue.unscoped.delete_all
    OptionValue.unscoped.delete_all
    ProductOption.unscoped.delete_all
    ProductVariant.unscoped.delete_all
    Media.unscoped.delete_all
    CollectionProduct.unscoped.delete_all
    Collection.unscoped.delete_all
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
    UserStoreAssignment.unscoped.delete_all
    StaffMember.unscoped.delete_all
    Shop.delete_all
  end

  before { purge! }
  after { purge! }

  let!(:shop) { create(:shop, subdomain: "refconc") }

  # captured 100000、單行 unit 60000×2 件 ⇒ 兩個併發各退 1 件（60000）
  # 合計 120000 > 100000 ⇒ 恰一筆成功。
  let!(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9201", order_number: 9201, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 120_000, total_cents: 120_000,
        presentment_total_cents: 120_000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 100_000, refunded_total_cents: 0
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "高價品",
                       quantity: 2, fulfillable_quantity: 2,
                       unit_price_cents: 60_000, total_cents: 120_000, currency: "HKD")
      o
    end
  end

  # 執行緒無 tenant context ⇒ 顯式 with_tenant（Order 的 acts_as_tenant require_tenant）。
  def refund(key)
    ActiveRecord::Base.connection_pool.with_connection do
      ActsAsTenant.with_tenant(shop) do
        line = LineItem.unscoped.where(order_id: order.id).first!
        described_class.call(
          shop:, order_id: order.id,
          refund_line_items: [ { line_item_id: line.id, quantity: 1, restock_type: "no_restock" } ],
          idempotency_key: key
        )
      end
    end
  end

  # 🔴 突變輪 M3 的守衛（故障注入——CONCURRENT 分支自然觸發不了：order lock
  #   已序列化同單退款，重讀時上限「其實夠」只發生在 capture 併發上升的窗，
  #   MRI 下無法穩定重現）。注入：條件式 UPDATE 回 0 但重讀顯示上限足夠
  #   ⇒ 必須回 REFUND_CONCURRENT_MODIFIED（不是 EXCEEDS）——兩碼合一時前端
  #   無從判斷要不要顯示超額二次確認（16 §F5.1(c)）。
  it "🔴 M3 守衛：affected==0 且重讀上限足夠 ⇒ CONCURRENT（分類分支走真程式碼）" do
    line = ActsAsTenant.without_tenant { LineItem.where(order_id: order.id).first! }
    # 只注入 UPDATE 步（回 0＝沒搶到），分類邏輯（重讀＋兩碼分流）走真實路徑。
    # 此時列上額度充足（refunded 0 < captured 100000）⇒ 真分類必回 CONCURRENT。
    allow(Refunds::Create).to receive(:conditional_cap_update!).and_return(0)

    result = ActsAsTenant.with_tenant(shop) do
      Refunds::Create.call(
        shop:, order_id: order.id,
        refund_line_items: [ { line_item_id: line.id, quantity: 1, restock_type: "no_restock" } ],
        idempotency_key: "m3-guard"
      )
    end
    expect(result.error[2]).to eq("REFUND_CONCURRENT_MODIFIED"),
      "上限足夠時回 EXCEEDS 會讓前端誤彈超額二次確認（16 F5.1(c) 兩碼必須分開）"
  end

  # 🔴 gate 版第一稿死鎖實錄（誠實登記）：把 B 卡在 apply_cumulative_cap! 之前
  # 時 B 已持 order 行鎖，A 卡在 Order.lock 等 B ⇒ 三方互等超時。
  # 正確的理解：**order lock 已把兩筆退款序列化**，條件式 UPDATE 是序列化之後的
  # 守衛（B 必然看到 A 已提交的累計值）⇒ 直接雙執行緒即可，第二筆在條件式
  # UPDATE 撞 cap。把 apply_cumulative_cap! 改成先 SELECT 再判斷（TOCTOU 形）
  # 在「order lock 被繞過／未持鎖路徑」時才會出事——條件式是縱深防禦，
  # 本格證明的是「序列化後第二筆被正確拒絕且累計精確」。
  it "🔴 C1 兩個並發退 60000（captured 100000）⇒ 恰一成功、另一筆 EXCEEDS、累計恰 60000" do
    threads = [ "conc-a", "conc-b" ].map { |key| Thread.new { refund(key) } }
    results = threads.map(&:value)

    successes = results.count { |r| r.error.nil? }
    failures = results.select { |r| r.error }
    expect(successes).to eq(1)
    expect(failures.size).to eq(1)
    expect(failures.first.error[2]).to eq("REFUND_EXCEEDS_MAXIMUM_REFUNDABLE")

    ActsAsTenant.without_tenant do
      expect(Order.find(order.id).refunded_total_cents).to eq(60_000)
      expect(Refund.where(order_id: order.id).count).to eq(1)
    end
  end
end
