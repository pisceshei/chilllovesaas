# frozen_string_literal: true

module ThemeEngine
  # `currency` 物件的資料面（官方 objects/currency，取證 2026-09-04："Information about a currency, like the ISO code and symbol."；
  # iso_code＝"The ISO code of the currency."／name＝"The name of the currency."／symbol＝"The symbol of the currency."；例 CAD／Canadian Dollar／$）。
  #
  # ①用處：`cart.currency`（Ella price-facet `{{ cart.currency.symbol }}`：hoko.vip HKD 店輸出 `$`）、`localization.*.currency`。
  # ②符號證據：HKD＝`$`（hoko.vip 2026-09-03 快照）、CAD＝`$`（官方例）；其餘符號與名稱＝ISO 4217 通用值，本尊逐字未取得（V，91 §3.75b）。
  #   查無者：符號退店級 `money_format` 佔位符前的字面（`${{amount}}` ⇒ `$`），再退 ISO 碼；名稱退 ISO 碼。
  # ③影響面：CartDrop／LocalizationContext 的 currency 物件；不影響金額格式（MoneyFormat 只讀 money_format）。
  module Currencies
    TABLE = {
      "HKD" => [ "$", "Hong Kong Dollar" ], "CAD" => [ "$", "Canadian Dollar" ], "USD" => [ "$", "US Dollar" ],
      "TWD" => [ "$", "New Taiwan Dollar" ], "EUR" => [ "€", "Euro" ], "GBP" => [ "£", "British Pound" ],
      "JPY" => [ "¥", "Japanese Yen" ], "CNY" => [ "¥", "Chinese Yuan" ], "KRW" => [ "₩", "South Korean Won" ],
      "AUD" => [ "$", "Australian Dollar" ], "SGD" => [ "$", "Singapore Dollar" ], "MYR" => [ "RM", "Malaysian Ringgit" ]
    }.freeze

    module_function

    # @param iso [String] ISO 4217
    # @param money_format [String, nil] 店級格式（退路）
    # @return [String]
    def symbol(iso, money_format: nil)
      code = iso.to_s.upcase
      return TABLE[code][0] if TABLE.key?(code)

      literal = money_format.to_s[/\A([^{]*)\{\{/, 1].to_s.strip
      literal.presence || code
    end

    # @return [String]
    def name(iso) = TABLE.fetch(iso.to_s.upcase, [ nil, iso.to_s.upcase ])[1]

    # @return [Hash] `{ "iso_code", "name", "symbol" }`
    def drop_hash(iso, money_format: nil)
      { "iso_code" => iso.to_s.upcase, "name" => name(iso), "symbol" => symbol(iso, money_format: money_format) }
    end
  end
end
