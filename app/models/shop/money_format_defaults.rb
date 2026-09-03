# frozen_string_literal: true

class Shop
  # 新店的貨幣格式種子（D81）。本尊建店時依店幣別給定「HTML with／without currency」預設，
  # 商家可在 Settings › General › Change currency formatting 改成任意含官方佔位符的字串。
  #
  # ①這是什麼：`for(currency)` ⇒ `[money_format, money_with_currency_format]`，只在 Shop 建立時
  #   （`before_validation on: :create`）與 migration 回填時使用；執行期一律讀 `shops` 兩欄。
  # ②值域：
  #   - HKD：真店 hoko.vip 實測（2026-09-03，店主未改設定）`money_format = "${{amount}}"`、
  #     `money_with_currency` 輸出 `HK$0.00 HKD` ⇒ `HK${{amount}} HKD`。
  #   - 官方 help 逐字 "The following currencies start with the formatting option amount_no_decimals by default"
  #     的 17 個幣別 ⇒ `{{amount_no_decimals}}`（符號官方未逐字 ⇒ 幣別碼前綴，V）。
  #   - 其餘 ⇒ `CODE {{amount}}`／`{{amount}} CODE`（本尊各幣別預設表官方未公開 ⇒ 通用形，V；
  #     91 §3.77 登記；商家可改）。
  # ③怎麼做：純表查詢；與 migration 20260903140000 的 SQL CASE 同源（spec MF-D 雙向核對）。
  # ④影響面：Shop 建立、`ThemeEngine::MoneyFormat`（消費端）、`RenderParity::Mirror.ensure_shop`（可覆寫）。
  module MoneyFormatDefaults
    HKD = [ "${{amount}}", "HK${{amount}} HKD" ].freeze

    # 官方 help.shopify.com/en/manual/international/pricing/currency-formatting（取證 2026-09-03）。
    NO_DECIMALS_CURRENCIES = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF].freeze

    # @param currency [String] ISO 4217 三碼
    # @return [Array(String, String)] `[money_format, money_with_currency_format]`
    def self.for(currency)
      code = currency.to_s.upcase
      return HKD if code == "HKD"

      placeholder = NO_DECIMALS_CURRENCIES.include?(code) ? "{{amount_no_decimals}}" : "{{amount}}"
      [ "#{code} #{placeholder}", "#{placeholder} #{code}" ]
    end
  end
end
