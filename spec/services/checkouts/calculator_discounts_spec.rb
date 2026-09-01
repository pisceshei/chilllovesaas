# frozen_string_literal: true

require "rails_helper"

# G6 步 9a：Calculator 多級折扣管線（17-F2/F2.1 的金額正確性核心）。
#
# 🔴 假綠殺手（鐵律 20.2⑤；F2.1「本次新增」逐條）：
#   D1 同基數不複利（殺：序列複利——10%+20% 算成 28000；官方逐字 "both
#      percentages are calculated on the original subtotal"）
#   D2 可交換律（殺：順序相依實作）
#   D3 鉗制（殺：60%+60% 打成負數）
#   D5 跨級序列（殺：order 級基數用原始小計而非 product 折後）
#   D7 運費不可疊運費（殺：兩張 shipping 直接相加）
RSpec.describe Checkouts::Calculator, "discounts pipeline" do
  def order_pct(id, bp)
    { id:, title: "O#{id}", discount_class: "order", value_type: "percentage",
      basis_points: bp, value_cents: nil, entitled_line_keys: nil }
  end

  def call!(discounts:, lines: nil, shipping: 0)
    lines ||= [ { key: "a", quantity: 1, unit_price_cents: 60_000 },
                { key: "b", quantity: 1, unit_price_cents: 40_000 } ]
    described_class.call(lines:, currency: "HKD", shipping_cents: shipping, discounts:)
  end

  it "🔴 D1 F2.1 算例：S₀=100000、10%＋20% ⇒ 折 30000 付 70000（不是複利 28000）" do
    result = call!(discounts: [ order_pct(1, 1000), order_pct(2, 2000) ])
    expect(result.discount_total_cents).to eq(30_000),
      "官方逐字：各以原始小計計——序列複利＝少折 NT$20 級別的金額錯"
    expect(result.total_cents).to eq(70_000)
  end

  it "🔴 D2 可交換律：order 級任意排列結果相同（property；20 次隨機排列）" do
    discounts = [ order_pct(1, 700), order_pct(2, 1300), order_pct(3, 2900) ]
    baseline = call!(discounts:).total_cents
    20.times do |seed|
      shuffled = discounts.shuffle(random: Random.new(seed))
      expect(call!(discounts: shuffled).total_cents).to eq(baseline)
    end
  end

  it "🔴 D3 鉗制：60%＋60% ⇒ 折 100000 付 0（不為負）；行分攤 Σ==折扣額且行不為負" do
    result = call!(discounts: [ order_pct(1, 6000), order_pct(2, 6000) ])
    expect(result.discount_total_cents).to eq(100_000)
    expect(result.total_cents).to eq(0)
    expect(result.discount_allocations.values.sum).to eq(100_000)
    result.lines.each do |line|
      expect(line.line_total_cents - result.discount_allocations.fetch(line.key)).to be >= 0
    end
  end

  it "D4 逐筆 floor：S₀=100000、333bp ⇒ 3330（整數除法；bp 制無 Float）" do
    result = call!(discounts: [ order_pct(1, 333) ])
    expect(result.discount_total_cents).to eq(3330)
  end

  it "🔴 D5 跨級序列：product 級折後才是 order 級基數（46c:720 官方句）" do
    product = { id: 9, title: "P", discount_class: "product", value_type: "fixed_amount",
                basis_points: nil, value_cents: 20_000, entitled_line_keys: nil }
    result = call!(discounts: [ product, order_pct(1, 1000) ])
    # product 折 20000 ⇒ S₀=80000；order 10% ⇒ 8000（不是 10000）
    expect(result.discount_total_cents).to eq(28_000)
    expect(result.total_cents).to eq(72_000)
  end

  it "D6 entitled 限定：product 折扣只打指定行；該行分攤 == 全額" do
    product = { id: 9, title: "P", discount_class: "product", value_type: "percentage",
                basis_points: 5000, value_cents: nil, entitled_line_keys: [ "a" ] }
    result = call!(discounts: [ product ])
    expect(result.discount_total_cents).to eq(30_000) # 60000 的 50%
    app = result.discount_applications.first
    expect(app.line_allocations).to eq({ "a" => 30_000 })
  end

  it "🔴 D7 兩張 shipping ⇒ ArgumentError（引擎硬規則的縱深防禦）" do
    ship = ->(id) { { id:, title: "S#{id}", discount_class: "shipping",
                      value_type: "percentage", basis_points: 10_000, value_cents: nil,
                      entitled_line_keys: nil } }
    expect { call!(discounts: [ ship.call(1), ship.call(2) ], shipping: 2000) }
      .to raise_error(ArgumentError, /運費折扣不可疊/)
  end

  it "D8 shipping 折扣只打運費；免運＝shipping_discount==shipping、貨側不動" do
    ship = { id: 1, title: "免運", discount_class: "shipping", value_type: "percentage",
             basis_points: 10_000, value_cents: nil, entitled_line_keys: nil }
    result = call!(discounts: [ ship ], shipping: 2000)
    expect(result.shipping_discount_cents).to eq(2000)
    expect(result.discount_total_cents).to eq(0)
    expect(result.total_cents).to eq(100_000)
  end

  it "D9 稅在折後（F2-4 先折後稅）：taxable＝行金額−分攤" do
    result = described_class.call(
      lines: [ { key: "a", quantity: 1, unit_price_cents: 100_000 } ],
      currency: "HKD", discounts: [ order_pct(1, 1000) ],
      tax: { rate: Rational(1, 10), included: false }
    )
    expect(result.tax_total_cents).to eq(9000) # (100000−10000)×10%
  end

  it "legacy discount: 照舊；與 discounts: 同給 ⇒ ArgumentError（互斥）" do
    legacy = described_class.call(
      lines: [ { key: "a", quantity: 1, unit_price_cents: 10_000 } ],
      currency: "HKD", discount: { type: "percentage", value: 10 }
    )
    expect(legacy.discount_total_cents).to eq(1000)

    expect do
      described_class.call(
        lines: [ { key: "a", quantity: 1, unit_price_cents: 10_000 } ],
        currency: "HKD", discount: { type: "percentage", value: 10 },
        discounts: []
      )
    end.to raise_error(ArgumentError, /互斥/)
  end
end
