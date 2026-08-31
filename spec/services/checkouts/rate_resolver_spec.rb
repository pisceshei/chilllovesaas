# frozen_string_literal: true

require "rails_helper"

# 結帳線第二包：運送費率解析（15 §F2.1 算例 1–5＋必測性質；85 §5.2–§5.3 實測格）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）——每格點名它要殺的錯誤實作：
#   R3  對照組（必測 3/4）：殺「交集語義退化成 per-name 部分相加」與「順手優化掉名稱敏感性」
#   R4  算例 4 的 13000（必測 7）：殺「把 per-participant 包裹重『修正』成整車一次」
#   R6  Rates(p)=∅ 整車擋（必測 5）：殺「缺費率的組當 0 元靜默跳過」
#   R9  免運門檻格：殺「門檻用 presentment 數字面比較」（85 §5.2 的 $62.73 實錘）
RSpec.describe Checkouts::RateResolver do
  let(:shop) { create(:shop, subdomain: "rr-shop") } # 建店即有 General＋HK zone＋免運費率

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  # ---- 建材 helpers（全部走真 model，驗證一起吃）----
  def general = ShippingProfile.general.first!

  def general_zone = general.shipping_zones.first!

  # 把建店預設的免運費率換成本格自己的費率集合
  def reset_general_rates!(*rates)
    general_zone.shipping_rates.delete_all
    rates.map { |attrs| rate!(general_zone, **attrs) }
  end

  def profile!(name)
    ShippingProfile.create!(shop_id: shop.id, name:)
  end

  def zone!(profile, countries, name: "Zone-#{countries.join}")
    ShippingZone.create!(shop_id: shop.id, shipping_profile: profile, name:, country_codes: countries)
  end

  def rate!(zone, name:, price:, type: "flat", currency: "HKD", **bands)
    ShippingRate.create!(
      shop_id: shop.id, shipping_zone: zone, name:, price_cents: price,
      rate_type: type, currency:, **bands
    )
  end

  def line(key, profile: nil, qty: 1, price: 10_000, grams: 0, ship: true)
    { key:, quantity: qty, unit_price_cents: price, weight_grams: grams,
      requires_shipping: ship, shipping_profile_id: profile&.id }
  end

  def resolve(lines, country: "HK")
    described_class.call(shop:, country_code: country, lines:)
  end

  describe "算例 1——兩檔同名 → 相加（分支 1）" do
    it "CommonNames={標準宅配} ⇒ 合併單選項 8000+12000=20000；split 形＝兩 shipment 各自選項" do
      reset_general_rates!({ name: "標準宅配", price: 8_000 })
      p2 = profile!("大型商品")
      rate!(zone!(p2, [ "HK" ]), name: "標準宅配", price: 12_000)

      result = resolve([ line("a"), line("b", profile: p2) ])
      expect(result.status).to eq(:ok)
      expect(result.merged_options.map { |o| [ o.name, o.price_cents ] }).to eq([ [ "標準宅配", 20_000 ] ])
      # split 形（85 §5.3）：per-shipment 選項獨立；聚合最低價＝各組最便宜相加
      expect(result.shipments.size).to eq(2)
      expect(result.shipments.map { |s| s.options.sole.price_cents }).to contain_exactly(8_000, 12_000)
      expect(result.shipments.sum { |s| s.options.first.price_cents }).to eq(20_000)
    end
  end

  describe "算例 2——三檔名稱全不同 → 各取最便宜相加（分支 2）" do
    it "交集空 ⇒ 單一選項 8000+18000+35000=61000，名稱＝limits fallback 文案" do
      reset_general_rates!({ name: "標準宅配", price: 8_000 }, { name: "快遞", price: 15_000 })
      cold = profile!("冷凍")
      rate!(zone!(cold, [ "HK" ]), name: "低溫宅配", price: 18_000)
      big = profile!("大型商品")
      big_zone = zone!(big, [ "HK" ])
      rate!(big_zone, name: "大型物流", price: 35_000)
      rate!(big_zone, name: "大型物流-偏遠", price: 45_000)

      result = resolve([ line("a"), line("b", profile: cold), line("c", profile: big) ])
      expect(result.merged_options.map { |o| [ o.name, o.price_cents ] })
        .to eq([ [ Limits.fetch(:shipping, :merged_option_fallback_label), 61_000 ] ])
    end
  end

  describe "算例 3——部分同名（合併鍵踩雷點）＋🔴 對照組（必測 3/4）" do
    def build_case3(p2_second_rate_name)
      reset_general_rates!({ name: "標準宅配", price: 8_000 }, { name: "快遞", price: 15_000 })
      p2 = profile!("P2")
      p2_zone = zone!(p2, [ "HK" ])
      rate!(p2_zone, name: "標準宅配", price: 6_000)
      rate!(p2_zone, name: p2_second_rate_name, price: 9_000)
      p3 = profile!("P3")
      p3_zone = zone!(p3, [ "HK" ])
      rate!(p3_zone, name: "標準宅配", price: 5_000)
      rate!(p3_zone, name: "快遞", price: 12_000)
      [ line("a"), line("b", profile: p2), line("c", profile: p3) ]
    end

    it "快遞只在 P1/P3 有 ⇒ 丟棄（不得退化為部分相加）；唯一選項 標準宅配 19000" do
      result = resolve(build_case3("貨到付款專用"))
      expect(result.merged_options.map { |o| [ o.name, o.price_cents ] }).to eq([ [ "標準宅配", 19_000 ] ])
    end

    it "🔴 對照組：P2 改名 貨到付款專用→快遞（價格不變）⇒ 多出選項 快遞 36000" do
      result = resolve(build_case3("快遞"))
      expect(result.merged_options.map { |o| [ o.name, o.price_cents ] })
        .to eq([ [ "標準宅配", 19_000 ], [ "快遞", 36_000 ] ])
    end
  end

  describe "算例 4——重量制 per-participant 包裹重（必測 7）" do
    before do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:shipping, :default_package_weight_grams).and_return(500)
    end

    def weight_bands!(zone)
      rate!(zone, name: "標準宅配", price: 5_000, type: "weight",
                  minimum_weight_grams: 0, maximum_weight_grams: 1_000)
      rate!(zone, name: "標準宅配", price: 8_000, type: "weight",
                  minimum_weight_grams: 1_000, maximum_weight_grams: 2_000)
    end

    it "P1 1200g→1700g→8000；P2 300g→800g→5000；合併＝13000（🔴 不是 8000——46c 官方語義）" do
      general_zone.shipping_rates.delete_all
      weight_bands!(general_zone)
      p2 = profile!("P2")
      weight_bands!(zone!(p2, [ "HK" ]))

      result = resolve([ line("a", grams: 1_200), line("b", profile: p2, grams: 300) ])
      expect(result.merged_options.sole.price_cents).to eq(13_000)
    end

    it "對照：同批商品全落單一設定檔 ⇒ 1500g+500g=2000g（上界含）→ 8000" do
      general_zone.shipping_rates.delete_all
      weight_bands!(general_zone)

      result = resolve([ line("a", grams: 1_200), line("b", grams: 300) ])
      expect(result.merged_options.sole.price_cents).to eq(8_000)
    end

    it "🔴 包裹重是承重項（殺「拿掉 +package」的突變——算例 4 的向量殺不死它）：" \
       "700g＋500g=1200g → 級距 2（8000）；不加包裹重會落級距 1（5000）" do
      general_zone.shipping_rates.delete_all
      weight_bands!(general_zone)
      expect(resolve([ line("a", grams: 700) ]).merged_options.sole.price_cents).to eq(8_000)
    end
  end

  describe "算例 5 的 v1 形——同 participant 多行只收一次" do
    it "兩行同屬 General ⇒ 1 個 shipment、費率只收一次（不是逐行相加）" do
      reset_general_rates!({ name: "標準宅配", price: 8_000 })
      result = resolve([ line("x"), line("y") ])
      expect(result.shipments.sole.line_keys).to contain_exactly("x", "y")
      expect(result.merged_options.sole.price_cents).to eq(8_000)
    end
  end

  describe "免運級距（85 §2「Free $70.00 and up」的資料形＝同名兩列）" do
    before do
      reset_general_rates!(
        { name: "標準", price: 800, type: "order_amount", maximum_order_cents: 7_000 },
        { name: "標準", price: 0, type: "order_amount", minimum_order_cents: 7_000 }
      )
    end

    it "小計 6999 ⇒ 收 800；恰 7000（邊界雙命中）⇒ 同名取最便宜＝免運；7001 ⇒ 免運" do
      expect(resolve([ line("a", price: 6_999) ]).merged_options.sole.price_cents).to eq(800)
      expect(resolve([ line("a", price: 7_000) ]).merged_options.sole.price_cents).to eq(0)
      expect(resolve([ line("a", price: 7_001) ]).merged_options.sole.price_cents).to eq(0)
    end

    it "🔴 門檻以**費率自身幣別**的級距欄比較（85 §5.2 實錘）：異幣費率不參與解析" do
      general_zone.shipping_rates.delete_all
      rate!(general_zone, name: "USD 費率", price: 500, currency: "USD")
      # 唯一費率是 USD、結帳幣 HKD ⇒ 該 participant 無可用費率 ⇒ 整車擋（v1 未接匯率）
      expect(resolve([ line("a", price: 26_650) ]).status).to eq(:undeliverable)
    end
  end

  describe "Rates(p)=∅ ⇒ 整車擋（必測 5）／market guard（F2.2）" do
    it "任一 participant 無 zone 覆蓋 ⇒ :undeliverable（🔴 不得把該檔當 0 元）" do
      p2 = profile!("孤檔") # 無 zone
      result = resolve([ line("a"), line("b", profile: p2) ])
      expect(result.status).to eq(:undeliverable)
      expect(result.shipments).to be_empty
      expect(result.merged_options).to be_empty
    end

    it "zone 覆蓋但零費率 ⇒ 一樣 :undeliverable（85 §4 零費率 zone 警示的執行面）" do
      general_zone.shipping_rates.delete_all
      expect(resolve([ line("a") ]).status).to eq(:undeliverable)
    end

    it "國家不在 active market ⇒ :not_sellable——即使 zone 有費率（zone ≠ market）" do
      zone2 = zone!(general, [ "US" ], name: "US zone")
      rate!(zone2, name: "美國線", price: 9_000)
      expect(resolve([ line("a") ], country: "US").status).to eq(:not_sellable)
    end
  end

  describe "requires_shipping 與快照過期" do
    it "全數位商品 ⇒ :ok＋零 shipment（無運送段，不是 undeliverable）" do
      result = resolve([ line("a", ship: false) ])
      expect(result.status).to eq(:ok)
      expect(result.shipments).to be_empty
    end

    it "混合車：數位行不進任何 shipment 的 line_keys" do
      reset_general_rates!({ name: "標準宅配", price: 8_000 })
      result = resolve([ line("a"), line("d", ship: false) ])
      expect(result.shipments.sole.line_keys).to eq([ "a" ])
    end

    it "快照指向已刪 profile（FK 已 nullify 商品、快照仍留舊 id）⇒ 擋下重選，不炸" do
      dead_id = profile!("將刪").id
      ShippingProfile.find(dead_id).destroy!
      result = resolve([ line("a", profile: nil), { key: "b", quantity: 1, unit_price_cents: 100,
                                                   weight_grams: 0, requires_shipping: true,
                                                   shipping_profile_id: dead_id } ])
      expect(result.status).to eq(:undeliverable)
    end
  end

  describe "sellable_countries（85 §6 官方交集句：active market ∩ 有費率的 zone）" do
    it "market 有 HK；zone 有 HK（有費率）＋US（有費率但不在 market）＋MO（在 zone 無費率）⇒ 只回 HK" do
      us_zone = zone!(general, [ "US" ], name: "US zone")
      rate!(us_zone, name: "美國線", price: 9_000)
      zone!(general, [ "MO" ], name: "MO zone") # 零費率
      expect(described_class.sellable_countries(shop:)).to eq([ "HK" ])
    end
  end

  describe "必測性質 1／2——順序不變性與整數封閉" do
    it "行順序打亂 ⇒ merged 結果完全相同；全程 Integer" do
      reset_general_rates!({ name: "標準宅配", price: 8_000 }, { name: "快遞", price: 15_000 })
      p2 = profile!("P2")
      p2_zone = zone!(p2, [ "HK" ])
      rate!(p2_zone, name: "標準宅配", price: 6_000)
      lines = [ line("a", price: 3_000), line("b", profile: p2, price: 4_000), line("c", price: 5_000) ]

      base = resolve(lines).merged_options
      rng = Random.new(20_260_831)
      5.times do
        shuffled = resolve(lines.shuffle(random: rng)).merged_options
        expect(shuffled.map { |o| [ o.name, o.price_cents ] }).to eq(base.map { |o| [ o.name, o.price_cents ] })
      end
      base.each { |o| expect(o.price_cents).to be_a(Integer) }
    end

    it "🔴 Float 金額／重量 ⇒ TypeError（鐵律 3：不是靜默取整）" do
      expect { resolve([ line("a").merge(unit_price_cents: 100.0) ]) }.to raise_error(TypeError)
      expect { resolve([ line("a").merge(weight_grams: 10.5) ]) }.to raise_error(TypeError)
    end
  end

  describe "合併鍵正規化（limits nfc_trim_case_sensitive；V-15）" do
    it "前後空白 trim 後同名 ⇒ 相加；大小寫不同 ⇒ 不同名（分支 2）" do
      reset_general_rates!({ name: "Express ", price: 8_000 })
      p2 = profile!("P2")
      rate!(zone!(p2, [ "HK" ]), name: "Express", price: 12_000)
      expect(resolve([ line("a"), line("b", profile: p2) ]).merged_options.sole.price_cents).to eq(20_000)

      general_zone.shipping_rates.sole.update!(name: "EXPRESS")
      merged = resolve([ line("a"), line("b", profile: p2) ]).merged_options
      expect(merged.sole.name).to eq(Limits.fetch(:shipping, :merged_option_fallback_label))
    end
  end
end
