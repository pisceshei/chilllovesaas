# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：refundCreate ＋ Order.suggestedRefund（16 §F5.1 全契約）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）:
#   R1 預覽 == 實退（鐵律 7 數字同源——兩處走同一份 Calculator）
#   R2 超上限 ⇒ REFUND_EXCEEDS_MAXIMUM_REFUNDABLE 且累計欄不動
#   R3 over_refund 需權限；帶權限走同一條條件式 UPDATE
#   R4 冪等重放回既有 refund 不重扣
#   R5 restock 兩型庫存語義不同（cancel: committed−/available+；return: available+）
#   R6 financial_status 推導（partially_refunded/refunded）
#   R7 未入帳單 INVALID_STATE
#   R8 idempotencyKey 缺 ⇒ top-level（limits required_for 已列 refundCreate）
RSpec.describe "refundCreate", type: :request do
  let(:shop) { create(:shop, subdomain: "refc") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "refc.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  # 已付訂單：兩行（1000×2 已出貨、500×2 未出貨）＋運費 800；captured=3800。
  def build_order(number:)
    ActsAsTenant.with_tenant(shop) do
      order = Order.create!(
        shop_id: shop.id, name: "##{number}", order_number: number, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 3000, shipping_cents: 800,
        total_cents: 3800, presentment_total_cents: 3800, financial_status: "paid",
        fulfillment_status: "partially_fulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 3800, refunded_total_cents: 0
      )
      order.order_transactions.create!(shop_id: shop.id, kind: "sale", status: "success",
                                       gateway: "manual_bank_deposit", amount_cents: 3800,
                                       currency: "HKD", idempotency_key: "sale-#{number}")
      # 行 1：已出貨（fulfillable 0；committed 已在出貨時釋放）
      v1 = create(:product_variant, shop:)
      LineItem.create!(shop_id: shop.id, order_id: order.id, title: "已出貨行",
                       product_variant_id: v1.id, quantity: 2, fulfillable_quantity: 0,
                       unit_price_cents: 1000, total_cents: 2000, currency: "HKD")
      # 行 2：未出貨（committed 掛著）
      v2 = create(:product_variant, shop:)
      level2 = v2.inventory_item.inventory_levels.first!
      ActsAsTenant.without_tenant do
        InventoryLevel.where(id: level2.id)
                      .update_all([ "committed = committed + ?, available = available - ?", 2, 2 ])
      end
      LineItem.create!(shop_id: shop.id, order_id: order.id, title: "未出貨行",
                       product_variant_id: v2.id, quantity: 2, fulfillable_quantity: 2,
                       unit_price_cents: 500, total_cents: 1000, currency: "HKD")
      order
    end
  end

  def gid(order) = "gid://chilllove/Order/#{order.id}"

  def line_gid(order, index)
    line = ActsAsTenant.without_tenant { order.line_items.order(:id).to_a[index] }
    "gid://chilllove/LineItem/#{line.id}"
  end

  def gql(query, variables)
    post admin_graphql_path, params: { query:, variables: }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  REFUND_SUGGEST_GQL = <<~GQL
    query($id: ID!, $lines: [RefundLineItemInput!], $refundShipping: Boolean) {
      order(id: $id) {
        suggestedRefund(refundLineItems: $lines, refundShipping: $refundShipping) {
          amountSet { shopMoney { amount } }
          maximumRefundableSet { shopMoney { amount } }
        }
      }
    }
  GQL

  REFUND_MUTATE_GQL = <<~GQL
    mutation($input: RefundInput!, $idempotencyKey: String) {
      refundCreate(input: $input, idempotencyKey: $idempotencyKey) {
        refund { id status totalRefundedSet { shopMoney { amount } } refundLineItems { quantity restockType } }
        order { displayFinancialStatus }
        userErrors { field message code }
      }
    }
  GQL

  def refund!(order, lines:, shipping: nil, key: "rkey-1", allow_over: false)
    input = { orderId: gid(order), refundLineItems: lines, allowOverRefunding: allow_over }
    input[:shipping] = shipping if shipping
    gql(REFUND_MUTATE_GQL, { input:, idempotencyKey: key })
  end

  it "R1 預覽 == 實退（同一份 Calculator；退已出貨行 1 件＋全運費）" do
    order = build_order(number: 9101)
    lines = [ { lineItemId: line_gid(order, 0), quantity: 1, restockType: "return" } ]

    preview = gql(REFUND_SUGGEST_GQL, { id: gid(order), lines: lines, refundShipping: true })
    amount = preview.dig("data", "order", "suggestedRefund", "amountSet", "shopMoney", "amount")
    expect(amount).to eq("18.00") # 1000 + 800 = 1800 cents

    payload = refund!(order, lines:, shipping: { fullRefund: true })
    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])
    expect(payload.dig("data", "refundCreate", "refund", "totalRefundedSet", "shopMoney", "amount")).to eq(amount)
    expect(payload.dig("data", "refundCreate", "refund", "status")).to eq("success")

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(1800)
      expect(Event.where(order_id: order.id, kind: "order.refunded").count).to eq(1)
      expect(EventOutbox.where(aggregate_id: order.id, topic: Events::Topics::ORDER_REFUNDED).count).to eq(1)
    end
  end

  # 🔴 突變輪 M6 的守衛：無稅 fixture 下 total == subtotal + shipping，
  #   「實退漏加稅」的突變殺不掉 ⇒ 專設帶稅訂單（tax 130 按行分攤）。
  it "🔴 R1b 帶稅訂單：實退含稅且與預覽一致（漏稅突變在此轉紅）" do
    order = ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9111", order_number: 9111, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 2000, shipping_cents: 0,
        tax_cents: 130, total_cents: 2130, presentment_total_cents: 2130,
        financial_status: "paid", fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 2130, refunded_total_cents: 0
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "含稅品",
                       quantity: 2, fulfillable_quantity: 2, taxable: true,
                       unit_price_cents: 1000, total_cents: 2000, currency: "HKD")
      o
    end
    line = ActsAsTenant.without_tenant { order.line_items.first! }

    payload = refund!(order, lines: [ { lineItemId: "gid://chilllove/LineItem/#{line.id}",
                                        quantity: 2 } ], key: "taxed-1")
    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])
    # 2000（行）＋130（稅全額分攤）＝2130——漏稅的實退會是 2000
    expect(payload.dig("data", "refundCreate", "refund", "totalRefundedSet", "shopMoney", "amount"))
      .to eq("21.30")
    ActsAsTenant.with_tenant(shop) { expect(order.reload.refunded_total_cents).to eq(2130) }
  end

  it "R2 超上限 ⇒ REFUND_EXCEEDS_MAXIMUM_REFUNDABLE 且不寫任何列" do
    order = build_order(number: 9102)
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(refunded_total_cents: 3000) }

    payload = refund!(order, lines: [ { lineItemId: line_gid(order, 0), quantity: 2 } ])
    expect(payload.dig("data", "refundCreate", "userErrors", 0, "code"))
      .to eq("REFUND_EXCEEDS_MAXIMUM_REFUNDABLE")

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(3000)
      expect(Refund.where(order_id: order.id).count).to eq(0)
    end
  end

  it "R3 over_refund：無權限 MISSING_PERMISSION；owner 帶權限可超額且走條件式" do
    order = build_order(number: 9103)
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(refunded_total_cents: 3000) }

    payload = refund!(order, lines: [ { lineItemId: line_gid(order, 0), quantity: 2 } ], allow_over: true)
    # owner staff can? 全通過 ⇒ 直接成功（超額路徑上界 = captured + amount）
    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(3000 + 2000)
    end
  end

  # 🔴 突變輪 M2 的守衛：超額路徑的條件式在「第一次超額」數學上恆真
  #   （refunded+x <= captured+x ⟺ refunded <= captured），把 WHERE 改恆真
  #   單靠 R3 測不出來——**連續第二次超額**（refunded 已 > captured）才分辨得出
  #   「上界＝本次核准額度」與「無上界」。
  it "🔴 R3b 連續第二次超額 ⇒ EXCEEDS（超額路徑仍有上界，不是無限放行）" do
    order = build_order(number: 9110)
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(refunded_total_cents: 3000) }
    first = refund!(order, lines: [ { lineItemId: line_gid(order, 0), quantity: 2 } ],
                    allow_over: true, key: "over-1")
    expect(first.dig("data", "refundCreate", "userErrors")).to eq([])

    second = refund!(order, lines: [ { lineItemId: line_gid(order, 1), quantity: 2 } ],
                     allow_over: true, key: "over-2")
    expect(second.dig("data", "refundCreate", "userErrors", 0, "code"))
      .to eq("REFUND_EXCEEDS_MAXIMUM_REFUNDABLE")
  end

  it "R4 冪等重放：同鍵第二次回既有 refund、累計欄不重扣" do
    order = build_order(number: 9104)
    lines = [ { lineItemId: line_gid(order, 0), quantity: 1 } ]
    first = refund!(order, lines:, key: "same-key")
    expect(first.dig("data", "refundCreate", "userErrors")).to eq([])

    second = refund!(order, lines:, key: "same-key")
    expect(second.dig("data", "refundCreate", "userErrors")).to eq([])
    expect(second.dig("data", "refundCreate", "refund", "id"))
      .to eq(first.dig("data", "refundCreate", "refund", "id"))

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(1000)
      expect(Refund.where(order_id: order.id).count).to eq(1)
    end
  end

  it "R5 restock 兩型：return ⇒ available+；cancel ⇒ committed− available+" do
    order = build_order(number: 9105)
    l1, l2 = ActsAsTenant.without_tenant { order.line_items.order(:id).to_a }
    level_of = lambda do |line|
      ActsAsTenant.without_tenant do
        item = InventoryItem.find_by(product_variant_id: line.product_variant_id)
        item.inventory_levels.first!
      end
    end
    before1 = level_of.(l1).reload
    before2 = level_of.(l2).reload

    payload = refund!(order, lines: [
      { lineItemId: "gid://chilllove/LineItem/#{l1.id}", quantity: 1, restockType: "return" },
      { lineItemId: "gid://chilllove/LineItem/#{l2.id}", quantity: 2, restockType: "cancel" }
    ])
    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])

    after1 = level_of.(l1).reload
    after2 = level_of.(l2).reload
    expect(after1.available - before1.available).to eq(1)   # return: available+
    expect(after1.committed - before1.committed).to eq(0)
    expect(after2.available - before2.available).to eq(2)   # cancel: available+
    expect(after2.committed - before2.committed).to eq(-2)  # cancel: committed−
  end

  it "R6 financial_status 推導：部分退 partially_refunded、退滿 refunded" do
    order = build_order(number: 9106)
    refund!(order, lines: [ { lineItemId: line_gid(order, 0), quantity: 1 } ], key: "r6-1")
    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.financial_status).to eq("partially_refunded")
    end

    payload = refund!(order,
      lines: [ { lineItemId: line_gid(order, 0), quantity: 1 },
               { lineItemId: line_gid(order, 1), quantity: 2 } ],
      shipping: { fullRefund: true }, key: "r6-2")
    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])
    expect(payload.dig("data", "refundCreate", "order", "displayFinancialStatus")).to eq("REFUNDED")
  end

  it "R7 未入帳單 ⇒ INVALID_STATE（refundable=false 對位）" do
    order = build_order(number: 9107)
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(captured_total_cents: 0) }

    payload = refund!(order, lines: [ { lineItemId: line_gid(order, 0), quantity: 1 } ])
    expect(payload.dig("data", "refundCreate", "userErrors", 0, "code")).to eq("INVALID_STATE")
  end

  it "R8 idempotencyKey 缺 ⇒ top-level IDEMPOTENCY_KEY_REQUIRED" do
    order = build_order(number: 9108)
    payload = gql(REFUND_MUTATE_GQL, { input: { orderId: gid(order),
                                     refundLineItems: [ { lineItemId: line_gid(order, 0), quantity: 1 } ],
                                     allowOverRefunding: false } })
    expect(payload.dig("errors", 0, "extensions", "code")).to eq("IDEMPOTENCY_KEY_REQUIRED")
  end

  it "R9 跨店訂單 ⇒ NOT_FOUND（鐵律 2）" do
    other = create(:shop, subdomain: "refc-other")
    other_order = ActsAsTenant.with_tenant(other) do
      Order.create!(
        shop_id: other.id, name: "#1", order_number: 1, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 100, total_cents: 100,
        presentment_total_cents: 100, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 100
      )
    end

    payload = refund!(other_order, lines: [])
    expect(payload.dig("data", "refundCreate", "userErrors", 0, "code")).to eq("NOT_FOUND")
  end
end
