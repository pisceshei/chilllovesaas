# frozen_string_literal: true

require "rails_helper"

# G6 步 10：日聚合（19-F2＋80 §3 紅線）。
#
# 🔴 假綠殺手：
#   A1 時區日界線（殺：用 UTC 切日——HK 23:30 的單掉到隔天）
#   A2 upsert 覆蓋制（殺：累加制——重跑翻倍）
#   A3 AOV 分子排除退款（殺：分子扣退款——與官方口徑相反；G25 具名例外）
#   A4 total_sales 可為負（殺：clamp 非負——撤銷日數字造假）
RSpec.describe Analytics::RollupDaily do
  let(:shop) { create(:shop, subdomain: "roll", timezone: "Asia/Hong_Kong") }
  let(:tz) { ActiveSupport::TimeZone["Asia/Hong_Kong"] }

  def build_order(processed_at:, total: 10_000, subtotal: 9000, discount: 1000,
                  shipping: 800, tax: 200)
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#A#{SecureRandom.hex(3)}", order_number: rand(100_000..999_999),
        currency: "HKD", presentment_currency: "HKD",
        subtotal_cents: subtotal, discount_cents: discount, shipping_cents: shipping,
        tax_cents: tax, total_cents: total, presentment_total_cents: total,
        financial_status: "paid", fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at:
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "品", quantity: 2,
                       fulfillable_quantity: 2, unit_price_cents: subtotal / 2,
                       total_cents: subtotal, currency: "HKD")
      o
    end
  end

  it "🔴 A1 日界線＝shop 時區：HK 9/1 23:59:59 歸 9/1；9/2 00:00:01 歸 9/2" do
    build_order(processed_at: tz.parse("2026-09-01 23:59:59"))
    build_order(processed_at: tz.parse("2026-09-02 00:00:01"))

    d1 = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 1)) }
    d2 = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 2)) }
    expect(d1["orders_count"]).to eq(1)
    expect(d2["orders_count"]).to eq(1)
  end

  it "🔴 A2 冪等：同日重跑三次 ⇒ rollup 值不變（覆蓋制非累加）" do
    build_order(processed_at: tz.parse("2026-09-03 12:00"))
    3.times { ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 3)) } }

    value = ActsAsTenant.without_tenant do
      DailyRollup.find_by(shop_id: shop.id, date: Date.new(2026, 9, 3), metric: "orders_count").value
    end
    expect(value).to eq(1)
  end

  it "🔴 A3/A4 退款日：returns 落當日、total_sales 可為負；AOV 分子不動" do
    order = build_order(processed_at: tz.parse("2026-09-04 10:00"), total: 10_000)
    ActsAsTenant.with_tenant(shop) do
      Refund.create!(shop_id: shop.id, order_id: order.id, status: "success",
                     total_cents: 50_000, shipping_cents: 0, currency: "HKD",
                     idempotency_key: "a3", processed_at: tz.parse("2026-09-05 10:00"))
    end

    day4 = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 4)) }
    day5 = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 5)) }

    expect(day4["aov_numerator"]).to eq(10_000) # 分子＝成立時 total，退款不回改（官方紅線①）
    # 🔴 equality-trap 補格：**同日**退款才分得出「分子扣退款」的突變——
    # 隔日案例裡 returns=0，錯實作與對實作同值（MA3 首輪存活的原因）。
    same_day_order = build_order(processed_at: tz.parse("2026-09-07 09:00"), total: 20_000)
    ActsAsTenant.with_tenant(shop) do
      Refund.create!(shop_id: shop.id, order_id: same_day_order.id, status: "success",
                     total_cents: 8000, shipping_cents: 0, currency: "HKD",
                     idempotency_key: "a3same", processed_at: tz.parse("2026-09-07 18:00"))
    end
    day7 = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 7)) }
    expect(day7["aov_numerator"]).to eq(20_000),
      "同日退款扣進分子＝官方口徑反向（80 §3 紅線①）"
    expect(day7["returns"]).to eq(8000)
    expect(day4["total_sales"]).to eq(10_000)
    expect(day5["returns"]).to eq(50_000)
    expect(day5["total_sales"]).to eq(-50_000), "撤銷 > 銷售的日子就是負數（80 §3 紅線②）"
  end

  it "口徑恆等式：total_sales = net + shipping + taxes；gross = subtotal + discounts" do
    build_order(processed_at: tz.parse("2026-09-06 10:00"),
                subtotal: 9000, discount: 1000, shipping: 800, tax: 200, total: 10_000)
    day = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, date: Date.new(2026, 9, 6)) }
    expect(day["gross_sales"]).to eq(10_000)
    expect(day["net_sales"]).to eq(9000)
    expect(day["total_sales"]).to eq(day["net_sales"] + day["shipping_charges"] + day["taxes"])
  end
end
