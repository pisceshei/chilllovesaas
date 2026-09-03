# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260903140000_add_money_formats_to_shops.rb")

# D81：貨幣顯示格式跟隨本尊（店級 money_format／money_with_currency_format）。
# 證據：官方 help "currency-formatting" 八佔位符與例值（external-facts §G15）、filters/money 族官方例、
# 真店 pnrjnw-sy admin 四欄實讀（HTML without `${{amount}}`／with `HK${{amount}} HKD`）、真店探針（§G16）。
RSpec.describe ThemeEngine::MoneyFormat do
  let(:harness) do
    h = Class.new { include ThemeEngine::Filters }.new
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    h
  end

  def with_registers(regs)
    harness.instance_variable_get(:@context).registers.replace(regs)
    harness
  end

  it "MF1 🔴 官方八佔位符（例值 1,134.65）逐一對位；佔位符外文字（含 HTML）原樣" do
    pattern = "<span>{{amount}}</span>|{{amount_no_decimals}}|{{amount_with_comma_separator}}|" \
              "{{amount_no_decimals_with_comma_separator}}|{{amount_with_apostrophe_separator}}|" \
              "{{amount_no_decimals_with_space_separator}}|{{amount_with_space_separator}}|" \
              "{{amount_with_period_and_space_separator}}"
    expect(described_class.render(113_465, pattern))
      .to eq("<span>1,134.65</span>|1,135|1.134,65|1.135|1'134.65|1 135|1 134,65|1 134.65")
  end

  it "MF2 🔴 佔位符容許大括號內空白（help 頁形 `{{ amount }}`）；未知佔位符原樣保留；千分位多組" do
    expect(described_class.render(100, "HK${{ amount }} HKD")).to eq("HK$1.00 HKD")
    expect(described_class.render(100, "{{amount_x}}|{{ amount }}")).to eq("{{amount_x}}|1.00")
    expect(described_class.render(123_456_789, "{{amount}}|{{amount_with_space_separator}}"))
      .to eq("1,234,567.89|1 234 567,89")
    expect(described_class.render(5, "{{amount}}|{{amount_no_decimals}}")).to eq("0.05|0")
  end

  it "MF3 🔴 過濾器族＝官方例（1000 ⇒ $10.00／$10.00 CAD／10.00／$10）；nil／空字串 ⇒ 空；無 registers ⇒ ${{amount}}" do
    f = with_registers(money_format: "${{amount}}", money_with_currency_format: "${{amount}} CAD")
    expect(f.money(1000)).to eq("$10.00")
    expect(f.money_with_currency(1000)).to eq("$10.00 CAD")
    expect(f.money_without_currency(1000)).to eq("10.00")
    expect(f.money_without_trailing_zeros(1000)).to eq("$10")
    expect(f.money(nil)).to eq("")
    expect(f.money("")).to eq("")
    expect(f.money_with_currency(nil)).to eq("")

    bare = with_registers({})
    expect(bare.money(1000)).to eq("$10.00")
    expect(bare.money_with_currency(1000)).to eq("$10.00") # with-currency 缺 ⇒ 退 money_format
  end

  it "MF4 🔴 真店格式（HTML without `${{amount}}`／with `HK${{amount}} HKD`）：money 無 HK$、money_with_currency 有" do
    f = with_registers(money_format: "${{amount}}", money_with_currency_format: "HK${{amount}} HKD")
    expect(f.money(1999)).to eq("$19.99")                    # hoko.vip 商品卡
    expect(f.money_with_currency(0)).to eq("HK$0.00 HKD")    # hoko.vip 購物車抽屜總額
  end

  it "MF5 money_without_currency 沿用第一個佔位符的分隔風格；money_without_trailing_zeros 只在小數全零時去分隔符" do
    f = with_registers(money_format: "€{{amount_with_comma_separator}}")
    expect(f.money_without_currency(148_000)).to eq("1.480,00")
    expect(f.money_without_trailing_zeros(148_000)).to eq("€1.480")
    expect(f.money_without_trailing_zeros(148_050)).to eq("€1.480,50")
    expect(with_registers(money_format: "{{amount_no_decimals}} kr").money_without_trailing_zeros(1000)).to eq("10 kr")
  end

  it "MF6 🔴 輸入強制：整數字串照整數；float／小數字串四捨五入到 cents；非數字 ⇒ 0；不經 float 路徑算千分位" do
    f = with_registers(money_format: "${{amount}}")
    expect(f.money("1000")).to eq("$10.00")
    expect(f.money(1000.4)).to eq("$10.00")
    expect(f.money("abc")).to eq("$0.00")
    # 大數（2^53 以上）整數算術不失真——float 路徑會在此出錯
    expect(f.money(9_007_199_254_740_993)).to eq("$90,071,992,547,409.93")
  end

  describe Shop::MoneyFormatDefaults do
    it "MF7 🔴 種子表：HKD＝真店實讀值；官方 amount_no_decimals 清單 ⇒ 無小數佔位符；其餘通用形" do
      expect(described_class.for("HKD")).to eq([ "${{amount}}", "HK${{amount}} HKD" ])
      expect(described_class.for("hkd")).to eq([ "${{amount}}", "HK${{amount}} HKD" ])
      expect(described_class.for("JPY")).to eq([ "JPY {{amount_no_decimals}}", "{{amount_no_decimals}} JPY" ])
      expect(described_class.for("USD")).to eq([ "USD {{amount}}", "{{amount}} USD" ])
    end

    it "MF8 🔴 migration 回填 SQL 的幣別集合與 Ruby 表同源（雙向相等，避免兩份清單各跑各的）" do
      expect(AddMoneyFormatsToShops::NO_DECIMALS.sort).to eq(described_class::NO_DECIMALS_CURRENCIES.sort)
      expect(described_class::NO_DECIMALS_CURRENCIES.size).to eq(17) # 官方 help 列 17 個
    end
  end

  describe "Shop 種子與執行期" do
    it "MF9 🔴 新店依幣別種子兩欄；呼叫端明給者不覆寫" do
      hk = create(:shop, subdomain: "mf-hk", store_currency: "HKD")
      expect([ hk.money_format, hk.money_with_currency_format ]).to eq([ "${{amount}}", "HK${{amount}} HKD" ])

      jp = create(:shop, subdomain: "mf-jp", store_currency: "JPY")
      expect(jp.money_format).to eq("JPY {{amount_no_decimals}}")

      custom = create(:shop, subdomain: "mf-custom", store_currency: "HKD", money_format: "HK${{amount}}")
      expect(custom.money_format).to eq("HK${{amount}}")
      expect(custom.money_with_currency_format).to eq("HK${{amount}} HKD")
    end

    it "MF10 🔴 ShopDrop 兩欄直出店級值；permanent_domain＝subdomain.base_host（不再硬編 chilllove.example）" do
      shop = create(:shop, subdomain: "mf-drop", store_currency: "HKD",
                    money_format: "€{{amount_with_comma_separator}}", money_with_currency_format: "€{{amount}} EUR")
      drop = ThemeEngine::ShopDrop.new(shop)
      expect(drop.money_format).to eq("€{{amount_with_comma_separator}}")
      expect(drop.money_with_currency_format).to eq("€{{amount}} EUR")
      expect(drop.permanent_domain).to eq("mf-drop.#{Chilllove::TenantResolver.base_host}")
      expect(drop.permanent_domain).not_to include("chilllove.example")
    end
  end
end
