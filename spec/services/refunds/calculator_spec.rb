# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：退款計算的純函式矩陣（16 §F5.1 v1 子集）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   K1 最大餘數分攤 Σ == 原始總額（殺：floor 分攤丟餘數）
#   K2 多次部分退款無殘差（殺：每次獨立 round 累積誤差）
#   K3 上限＝captured − refunded（殺：讀 total_cents 當上限）
#   K4 超量退款拒絕（殺：可退量不含既有退款）
#   K5 運費上限（殺：重複全退運費）
RSpec.describe Refunds::Calculator do
  let(:shop) { create(:shop, subdomain: "refcalc") }

  # 三行訂單：1000×3、700×1、500×2；訂單折扣 250、稅 130、運費 3620。
  # 折扣/稅按行 total（3000/700/1000）最大餘數分攤——手算：
  #   折扣 250 → 3000/4700、700/4700、1000/4700 ⇒ 159.57→159、37.23→37、53.19→53
  #   餘 1 給餘數最大者（.57 行1）⇒ [160, 37, 53]（Σ=250）
  #   稅 130 ⇒ 82.97→82、19.36→19、27.65→27 餘 2 給 .97 與 .65 ⇒ [83, 19, 28]（Σ=130）
  let(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9001", order_number: 9001, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 4700, discount_cents: 250,
        shipping_cents: 3620, tax_cents: 130, total_cents: 8200, presentment_total_cents: 8200,
        financial_status: "paid", fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 8200, refunded_total_cents: 0
      )
      [ [ 1000, 3 ], [ 700, 1 ], [ 500, 2 ] ].each_with_index do |(unit, qty), i|
        LineItem.create!(shop_id: shop.id, order_id: o.id, title: "行#{i + 1}",
                         quantity: qty, fulfillable_quantity: qty,
                         unit_price_cents: unit, total_cents: unit * qty,
                         currency: "HKD", taxable: true)
      end
      o
    end
  end

  def lines = ActsAsTenant.without_tenant { order.line_items.order(:id).to_a }

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  it "K1 全退時 Σ(行小計) == subtotal − discount 且 Σ(稅) == tax（最大餘數，無殘差）" do
    reqs = lines.map { |l| { line_item_id: l.id, quantity: l.quantity } }
    s = described_class.suggest(order:, refund_line_items: reqs, full_shipping: true)

    expect(s.error).to be_nil
    expect(s.subtotal_cents).to eq(4700 - 250)
    expect(s.tax_cents).to eq(130)
    expect(s.shipping_cents).to eq(3620)
    expect(s.total_cents).to eq(4450 + 130 + 3620)
  end

  it "K1b 單行分攤值符合手算（行1 折 160 稅 83）" do
    l1 = lines[0]
    s = described_class.suggest(order:, refund_line_items: [ { line_item_id: l1.id, quantity: 3 } ])
    expect(s.subtotal_cents).to eq(3000 - 160)
    expect(s.tax_cents).to eq(83)
  end

  # 🔴 K2：行1（3 件、折 160 稅 83）分兩次退（2+1），Σ 兩次 == 一次退完。
  #   per-unit 切分：折 160/3 ⇒ [54,53,53]；稅 83/3 ⇒ [28,28,27]。
  it "🔴 K2 多次部分退款的分攤和 == 一次退完（per-unit 游標，無殘差）" do
    l1 = lines[0]
    first = described_class.suggest(order:, refund_line_items: [ { line_item_id: l1.id, quantity: 2 } ])
    expect(first.subtotal_cents).to eq(2000 - 54 - 53)
    expect(first.tax_cents).to eq(28 + 28)

    # 落一筆已退（status success）讓游標前進
    refund = Refund.create!(shop_id: shop.id, order_id: order.id, status: "success",
                            total_cents: first.total_cents, shipping_cents: 0, currency: "HKD",
                            idempotency_key: "k2-1", processed_at: Time.current)
    RefundLineItem.create!(shop_id: shop.id, refund_id: refund.id, line_item_id: l1.id,
                           quantity: 2, restock_type: "no_restock",
                           subtotal_cents: first.subtotal_cents, tax_cents: first.tax_cents,
                           currency: "HKD")

    second = described_class.suggest(order:, refund_line_items: [ { line_item_id: l1.id, quantity: 1 } ])
    expect(second.subtotal_cents).to eq(1000 - 53)
    expect(second.tax_cents).to eq(27)
    expect(first.subtotal_cents + second.subtotal_cents).to eq(3000 - 160)
    expect(first.tax_cents + second.tax_cents).to eq(83)
  end

  it "K3 maximum_refundable = captured − refunded（不是 total_cents）" do
    ActsAsTenant.without_tenant do
      Order.where(id: order.id).update_all(captured_total_cents: 5000, refunded_total_cents: 1200)
    end
    s = described_class.suggest(order: order.reload, refund_line_items: [])
    expect(s.maximum_refundable_cents).to eq(3800)
  end

  it "K4 數量超過可退量（含既有成功退款）⇒ INVALID" do
    l2 = lines[1] # qty 1
    refund = Refund.create!(shop_id: shop.id, order_id: order.id, status: "success",
                            total_cents: 700, shipping_cents: 0, currency: "HKD",
                            idempotency_key: "k4", processed_at: Time.current)
    RefundLineItem.create!(shop_id: shop.id, refund_id: refund.id, line_item_id: l2.id,
                           quantity: 1, restock_type: "no_restock",
                           subtotal_cents: 663, tax_cents: 19, currency: "HKD")

    s = described_class.suggest(order:, refund_line_items: [ { line_item_id: l2.id, quantity: 1 } ])
    expect(s.error&.last).to eq("INVALID")
  end

  it "K4b 失敗退款不佔可退量（status failure 排除）" do
    l2 = lines[1]
    refund = Refund.create!(shop_id: shop.id, order_id: order.id, status: "failure",
                            total_cents: 700, shipping_cents: 0, currency: "HKD",
                            idempotency_key: "k4b", processed_at: Time.current)
    RefundLineItem.create!(shop_id: shop.id, refund_id: refund.id, line_item_id: l2.id,
                           quantity: 1, restock_type: "no_restock",
                           subtotal_cents: 663, tax_cents: 19, currency: "HKD")

    s = described_class.suggest(order:, refund_line_items: [ { line_item_id: l2.id, quantity: 1 } ])
    expect(s.error).to be_nil
  end

  it "K5 運費：指定額超過剩餘可退運費 ⇒ INVALID；full_shipping 只退剩餘" do
    Refund.create!(shop_id: shop.id, order_id: order.id, status: "success",
                   total_cents: 2000, shipping_cents: 2000, currency: "HKD",
                   idempotency_key: "k5", processed_at: Time.current)

    over = described_class.suggest(order:, shipping_cents: 1621)
    expect(over.error&.last).to eq("INVALID")

    full = described_class.suggest(order:, full_shipping: true)
    expect(full.error).to be_nil
    expect(full.shipping_cents).to eq(1620)
  end

  it "零金額行（免費品）分攤為 0 且不炸（除零防護）" do
    free = ActsAsTenant.without_tenant do
      LineItem.create!(shop_id: shop.id, order_id: order.id, title: "贈品",
                       quantity: 1, fulfillable_quantity: 1, unit_price_cents: 0,
                       total_cents: 0, currency: "HKD", taxable: false)
    end
    s = described_class.suggest(order:, refund_line_items: [ { line_item_id: free.id, quantity: 1 } ])
    expect(s.error).to be_nil
    expect(s.total_cents).to eq(0)
  end
end
