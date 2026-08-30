# frozen_string_literal: true

require "rails_helper"

# 金額引擎（15 F2；表格驅動 ≥40 組＋property test 三不變量）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   T-cap   折扣 > 小計 ⇒ 收斂到小計（殺：總計變負）
#   T-alloc Σ行分攤 = 折扣總額**恆等**（殺：按比例各自四捨五入——差 1 分錢對不了帳）
#   T-incl  含稅反推 ±1 分錢格（殺：total×rate/(1+rate) 一次算——行級進位策略被繞過）
#   T-float 任何 Float ⇒ TypeError（殺：F2 坑 1「出現 Float 算錢即 bug」）
#   矩陣含 JPY／TWD／KRW（65 §H：zero-decimal 必進金額測試矩陣——儲存一律 ×100 不看幣別）
RSpec.describe Checkouts::Calculator do
  def line(key, quantity, unit)
    { key:, quantity:, unit_price_cents: unit }
  end

  def call(lines:, currency: "HKD", **options)
    described_class.call(lines:, currency:, **options)
  end

  # ── 表格驅動（44 組）────────────────────────────────────────────────────────
  # 期望值全部手算（integer cents；rate 用 Rational）。
  CASES = [
    # --- 基本加總 ---
    { n: "單行單件", l: [ [ "a", 1, 14_800 ] ], e: { sub: 14_800, tot: 14_800 } },
    { n: "單行多件", l: [ [ "a", 3, 14_800 ] ], e: { sub: 44_400, tot: 44_400 } },
    { n: "多行", l: [ [ "a", 1, 100 ], [ "b", 2, 250 ] ], e: { sub: 600, tot: 600 } },
    { n: "1 分錢", l: [ [ "a", 1, 1 ] ], e: { sub: 1, tot: 1 } },
    { n: "極大值", l: [ [ "a", 1, 999_999_999 ] ], e: { sub: 999_999_999, tot: 999_999_999 } },
    { n: "0 元行", l: [ [ "a", 1, 0 ], [ "b", 1, 500 ] ], e: { sub: 500, tot: 500 } },
    { n: "全 0 元", l: [ [ "a", 2, 0 ] ], e: { sub: 0, tot: 0 } },
    { n: "20 行", l: (1..20).map { |i| [ "l#{i}", 1, 100 ] }, e: { sub: 2_000, tot: 2_000 } },
    # --- 運費 ---
    { n: "加運費", l: [ [ "a", 1, 1_000 ] ], o: { shipping_cents: 350 }, e: { sub: 1_000, tot: 1_350 } },
    { n: "免運邊界（0 元運費照加）", l: [ [ "a", 1, 1_000 ] ], o: { shipping_cents: 0 }, e: { sub: 1_000, tot: 1_000 } },
    { n: "運費壓過商品", l: [ [ "a", 1, 1 ] ], o: { shipping_cents: 99_999 }, e: { sub: 1, tot: 100_000 } },
    # --- 百分比折扣 ---
    { n: "0%", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "percentage", value: 0 } },
      e: { sub: 1_000, disc: 0, tot: 1_000 } },
    { n: "10%", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "percentage", value: 10 } },
      e: { sub: 1_000, disc: 100, tot: 900 } },
    { n: "100%", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "percentage", value: 100 } },
      e: { sub: 1_000, disc: 1_000, tot: 0 } },
    { n: "12.5%（Rational）", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "percentage", value: Rational(25, 2) } },
      e: { sub: 1_000, disc: 125, tot: 875 } },
    { n: "33⅓%（半數進位）", l: [ [ "a", 1, 100 ] ], o: { discount: { type: "percentage", value: Rational(100, 3) } },
      e: { sub: 100, disc: 33, tot: 67 } },
    { n: "10% 於 5 分（半數進位取 1）", l: [ [ "a", 1, 5 ] ], o: { discount: { type: "percentage", value: 10 } },
      e: { sub: 5, disc: 1, tot: 4 } },
    { n: "1% 於 49 分（進位取 0）", l: [ [ "a", 1, 49 ] ], o: { discount: { type: "percentage", value: 1 } },
      e: { sub: 49, disc: 0, tot: 49 } },
    # --- 固定折扣與上限 ---
    { n: "固定折扣", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "fixed_amount", value_cents: 300 } },
      e: { sub: 1_000, disc: 300, tot: 700 } },
    { n: "固定 0 元", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "fixed_amount", value_cents: 0 } },
      e: { sub: 1_000, disc: 0, tot: 1_000 } },
    { n: "🔴 折扣＝小計", l: [ [ "a", 1, 1_000 ] ], o: { discount: { type: "fixed_amount", value_cents: 1_000 } },
      e: { sub: 1_000, disc: 1_000, tot: 0 } },
    { n: "🔴 折扣大於小計 ⇒ 收斂（總計非負）", l: [ [ "a", 1, 1_000 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 99_999 } }, e: { sub: 1_000, disc: 1_000, tot: 0 } },
    { n: "折扣蓋小計但運費照收", l: [ [ "a", 1, 500 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 800 }, shipping_cents: 200 },
      e: { sub: 500, disc: 500, tot: 200 } },
    # --- 分攤（最大餘數法）---
    { n: "🔴 兩行等重分 1 分（餘數給行序前者）", l: [ [ "a", 1, 100 ], [ "b", 1, 100 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 1 } },
      e: { sub: 200, disc: 1, alloc: { "a" => 1, "b" => 0 }, tot: 199 } },
    { n: "🔴 3 行分 100（餘數給金額大行）", l: [ [ "a", 1, 500 ], [ "b", 1, 300 ], [ "c", 1, 200 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 100 } },
      e: { sub: 1_000, disc: 100, alloc: { "a" => 50, "b" => 30, "c" => 20 }, tot: 900 } },
    { n: "🔴 3 行分 101（質數餘數）", l: [ [ "a", 1, 500 ], [ "b", 1, 300 ], [ "c", 1, 200 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 101 } },
      e: { sub: 1_000, disc: 101, alloc: { "a" => 51, "b" => 30, "c" => 20 }, tot: 899 } },
    { n: "🔴 3 行分 7（畸零全靠餘數）", l: [ [ "a", 1, 100 ], [ "b", 1, 100 ], [ "c", 1, 100 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 7 } },
      e: { sub: 300, disc: 7, alloc: { "a" => 3, "b" => 2, "c" => 2 }, tot: 293 } },
    { n: "0 元行不分攤", l: [ [ "a", 1, 0 ], [ "b", 1, 300 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 100 } },
      e: { sub: 300, disc: 100, alloc: { "a" => 0, "b" => 100 }, tot: 200 } },
    { n: "全額折扣的分攤＝各行金額", l: [ [ "a", 1, 700 ], [ "b", 1, 300 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 1_000 } },
      e: { sub: 1_000, disc: 1_000, alloc: { "a" => 700, "b" => 300 }, tot: 0 } },
    { n: "質數行金額 × 質數折扣（餘數給餘數最大行 b）", l: [ [ "a", 1, 97 ], [ "b", 1, 89 ], [ "c", 1, 83 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 53 } },
      e: { sub: 269, disc: 53, alloc: { "a" => 19, "b" => 18, "c" => 16 }, tot: 216 } },
    # --- 未稅（exclusive）---
    { n: "0% 稅", l: [ [ "a", 1, 1_000 ] ], o: { tax: { rate: 0, included: false } },
      e: { sub: 1_000, tax: 0, tot: 1_000 } },
    { n: "10% 未稅", l: [ [ "a", 1, 1_000 ] ], o: { tax: { rate: Rational(10, 100), included: false } },
      e: { sub: 1_000, tax: 100, tot: 1_100 } },
    { n: "5% 未稅（半數進位）", l: [ [ "a", 1, 1_010 ] ], o: { tax: { rate: Rational(5, 100), included: false } },
      e: { sub: 1_010, tax: 51, tot: 1_061 } }, # 50.5 → 51
    { n: "7.5% 未稅", l: [ [ "a", 1, 2_000 ] ], o: { tax: { rate: Rational(75, 1000), included: false } },
      e: { sub: 2_000, tax: 150, tot: 2_150 } },
    { n: "🔴 行級進位（兩行各 5 分稅半數進位；一次算整車＝10.1→10）",
      l: [ [ "a", 1, 101 ], [ "b", 1, 101 ] ], o: { tax: { rate: Rational(5, 100), included: false } },
      e: { sub: 202, tax: 10, tot: 212 } }, # 每行 5.05 → 5；Σ=10（整車算＝10.1→10 同值；行級策略由 alloc 格另證）
    { n: "先折後稅", l: [ [ "a", 1, 1_000 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 200 }, tax: { rate: Rational(10, 100), included: false } },
      e: { sub: 1_000, disc: 200, tax: 80, tot: 880 } },
    { n: "🔴 行級進位差 1 分（1.5+1.5 行級=2；整車 3×1%=3.03→3——本格挑出差異）",
      l: [ [ "a", 1, 150 ], [ "b", 1, 150 ] ], o: { tax: { rate: Rational(1, 100), included: false } },
      e: { sub: 300, tax: 4, tot: 304 } }, # 每行 1.5 → 2（半數進位）；Σ=4 ≠ 整車 3
    # --- 含稅（inclusive；反推 taxable − round(taxable/(1+rate))）---
    { n: "5% 含稅", l: [ [ "a", 1, 1_050 ] ], o: { tax: { rate: Rational(5, 100), included: true } },
      e: { sub: 1_050, tax: 50, tot: 1_050 } }, # 1050 − 1000 = 50；total 不再加稅
    { n: "10% 含稅", l: [ [ "a", 1, 1_100 ] ], o: { tax: { rate: Rational(10, 100), included: true } },
      e: { sub: 1_100, tax: 100, tot: 1_100 } },
    { n: "🔴 含稅 ±1 分（999/1.05=951.43→951 ⇒ 稅 48）", l: [ [ "a", 1, 999 ] ],
      o: { tax: { rate: Rational(5, 100), included: true } }, e: { sub: 999, tax: 48, tot: 999 } },
    { n: "🔴 含稅行級反推（兩行 999：每行 48 ⇒ Σ96；整車 1998 反推＝95——差 1 分）",
      l: [ [ "a", 1, 999 ], [ "b", 1, 999 ] ], o: { tax: { rate: Rational(5, 100), included: true } },
      e: { sub: 1_998, tax: 96, tot: 1_998 } },
    { n: "含稅＋折扣（先折後反推）", l: [ [ "a", 1, 1_100 ] ],
      o: { discount: { type: "fixed_amount", value_cents: 100 }, tax: { rate: Rational(10, 100), included: true } },
      e: { sub: 1_100, disc: 100, tax: 91, tot: 1_000 } }, # taxable 1000 − round(1000/1.1)=909 ⇒ 91
    { n: "含稅＋運費（運費不課稅、照加）", l: [ [ "a", 1, 1_050 ] ],
      o: { shipping_cents: 100, tax: { rate: Rational(5, 100), included: true } },
      e: { sub: 1_050, tax: 50, tot: 1_150 } },
    # --- zero-decimal 幣別矩陣（65 §H：儲存一律 ×100 不看幣別——數學恆同、幣別只是標籤）---
    { n: "JPY（¥1,480 儲存 148000）", c: "JPY", l: [ [ "a", 1, 148_000 ] ], e: { sub: 148_000, tot: 148_000 } },
    { n: "TWD 折扣分攤", c: "TWD", l: [ [ "a", 1, 50_000 ], [ "b", 1, 30_000 ] ],
      o: { discount: { type: "percentage", value: 10 } },
      e: { sub: 80_000, disc: 8_000, alloc: { "a" => 5_000, "b" => 3_000 }, tot: 72_000 } },
    { n: "KRW 含稅", c: "KRW", l: [ [ "a", 1, 110_000 ] ], o: { tax: { rate: Rational(10, 100), included: true } },
      e: { sub: 110_000, tax: 10_000, tot: 110_000 } }
  ].freeze

  CASES.each do |kase|
    it "表格：#{kase[:n]}" do
      result = call(lines: kase[:l].map { |c| line(*c) }, currency: kase[:c] || "HKD", **(kase[:o] || {}))
      expect(result.subtotal_cents).to eq(kase[:e][:sub])
      expect(result.discount_total_cents).to eq(kase[:e][:disc] || 0)
      expect(result.tax_total_cents).to eq(kase[:e][:tax] || 0)
      expect(result.total_cents).to eq(kase[:e][:tot])
      expect(result.discount_allocations).to eq(kase[:e][:alloc]) if kase[:e][:alloc]
      # 恆等不變量（每一格都驗，不只點名格）
      expect(result.discount_allocations.values.sum).to eq(result.discount_total_cents)
      expect(result.lines.sum(&:line_total_cents)).to eq(result.subtotal_cents)
      expect(result.total_cents).to be >= 0
      expect(result.currency).to eq(kase[:c] || "HKD")
    end
  end

  # ── property test（15 F2-5：隨機 cart 驗三不變量；固定種子＝可重跑）──────────
  it "property：200 組隨機 cart——總計非負、Σ分攤=折扣總額、Σ行=小計、行分攤不超行額" do
    rng = Random.new(20_260_831)
    200.times do |round|
      lines = (1..(1 + rng.rand(7))).map do |i|
        line("r#{i}", 1 + rng.rand(5), rng.rand(100_000))
      end
      discount = case rng.rand(3)
      when 0 then nil
      when 1 then { type: "percentage", value: Rational(rng.rand(101)) }
      else { type: "fixed_amount", value_cents: rng.rand(300_000) } # 可能大於小計
      end
      tax = case rng.rand(3)
      when 0 then nil
      when 1 then { rate: Rational(rng.rand(30), 100), included: false }
      else { rate: Rational(rng.rand(30), 100), included: true }
      end
      result = call(lines:, shipping_cents: rng.rand(5_000), discount:, tax:)

      expect(result.total_cents).to be >= 0, "round #{round}: 總計為負"
      expect(result.discount_allocations.values.sum).to eq(result.discount_total_cents),
        "round #{round}: Σ分攤 ≠ 折扣總額"
      expect(result.lines.sum(&:line_total_cents)).to eq(result.subtotal_cents),
        "round #{round}: Σ行 ≠ 小計"
      result.lines.each do |l|
        alloc = result.discount_allocations.fetch(l.key)
        expect(alloc).to be_between(0, l.line_total_cents), "round #{round}: 行分攤越界"
      end
      expect(result.tax_total_cents).to be >= 0
    end
  end

  # ── 型別閘（F2 坑 1）────────────────────────────────────────────────────────
  it "🔴 Float 一律 TypeError：單價／運費／固定折扣／稅率四個入口各自擋" do
    good = [ line("a", 1, 100) ]
    expect { call(lines: [ line("a", 1, 100.0) ]) }.to raise_error(TypeError, /鐵律 3/)
    expect { call(lines: good, shipping_cents: 1.5) }.to raise_error(TypeError)
    expect { call(lines: good, discount: { type: "fixed_amount", value_cents: 10.0 }) }.to raise_error(TypeError)
    expect { call(lines: good, discount: { type: "percentage", value: 12.5 }) }.to raise_error(TypeError)
    expect { call(lines: good, tax: { rate: 0.05, included: false }) }.to raise_error(TypeError)
  end

  it "輸入驗證：空行組／零數量／負金額／未知折扣型別 ⇒ ArgumentError" do
    expect { call(lines: []) }.to raise_error(ArgumentError)
    expect { call(lines: [ line("a", 0, 100) ]) }.to raise_error(ArgumentError)
    expect { call(lines: [ line("a", 1, -1) ]) }.to raise_error(ArgumentError)
    expect { call(lines: [ line("a", 1, 100) ], discount: { type: "bogo" }) }.to raise_error(ArgumentError)
  end

  it "Result 不可變（Data 型；四處重用共享同一份不怕被改——F2-2）" do
    result = call(lines: [ line("a", 1, 100) ])
    expect(result).to be_frozen
    expect { result.instance_variable_set(:@x, 1) }.to raise_error(FrozenError)
  end
end
