# frozen_string_literal: true

module ThemeEngine
  # 店級金額格式（D81：貨幣顯示格式跟隨本尊）。
  #
  # ①這是什麼：把 **integer cents**（鐵律 3 儲存尺度）依店家的 `money_format`／`money_with_currency_format`
  #   字串渲染成顯示字串。格式字串＝任意文字＋官方八個佔位符（help "currency-formatting"，
  #   `docs/dev/external-facts.md` §G15 逐字）；佔位符以外的文字原樣輸出（含 HTML）。
  # ②值域（官方例 1,134.65）：
  #   `{{amount}}` 1,134.65／`{{amount_no_decimals}}` 1,135／`{{amount_with_comma_separator}}` 1.134,65／
  #   `{{amount_no_decimals_with_comma_separator}}` 1.135／`{{amount_with_apostrophe_separator}}` 1'134.65／
  #   `{{amount_no_decimals_with_space_separator}}` 1 135／`{{amount_with_space_separator}}` 1 134,65／
  #   `{{amount_with_period_and_space_separator}}` 1 134.65。
  #   未知佔位符原樣保留（本尊行為未取得，登記 V）。
  # ③怎麼做：整數算術（不經 float）：`abs.divmod(100)` 拆整數／分；無小數形四捨五入（官方例 .65 進位；
  #   恰 .50 的捨入模式未取得，V）；千分位用 lookahead 正則；負數在數字前加 `-`（本尊負值形未取得，V；91 §3.77）。
  # ④影響面：`Filters#money`／`money_with_currency`／`money_without_currency`／`money_without_trailing_zeros`、
  #   `ShopDrop#money_format`（Ella JS `window.money_format` 直接吃同一字串做前端 formatMoney）、
  #   `Notifications::Renderer`（信件金額）、`RenderParity::Mirror`（鏡像店的格式對齊）。
  module MoneyFormat
    PLACEHOLDER_RE = /\{\{\s*(amount(?:_[a-z_]+)?)\s*\}\}/

    # 佔位符 ⇒ [千分位符, 小數點符或 nil（無小數）]
    STYLES = {
      "amount" => [ ",", "." ],
      "amount_no_decimals" => [ ",", nil ],
      "amount_with_comma_separator" => [ ".", "," ],
      "amount_no_decimals_with_comma_separator" => [ ".", nil ],
      "amount_with_apostrophe_separator" => [ "'", "." ],
      "amount_no_decimals_with_space_separator" => [ " ", nil ],
      "amount_with_space_separator" => [ " ", "," ],
      "amount_with_period_and_space_separator" => [ " ", "." ]
    }.freeze

    module_function

    # 依格式字串渲染。
    # @param cents [Integer] 儲存尺度金額
    # @param pattern [String] 店級格式字串
    # @return [String]
    def render(cents, pattern)
      pattern.to_s.gsub(PLACEHOLDER_RE) { STYLES.key?(Regexp.last_match(1)) ? number(cents, Regexp.last_match(1)) : Regexp.last_match(0) }
    end

    # 只出數字（`money_without_currency`）：沿用格式字串第一個佔位符的分隔風格，去掉符號與其他文字。
    # @return [String]
    def amount_only(cents, pattern)
      style = pattern.to_s[PLACEHOLDER_RE, 1]
      number(cents, STYLES.key?(style) ? style : "amount")
    end

    # `money_without_trailing_zeros`：官方逐字 "excluding the decimal separator and trailing zeros"，
    # 官方例 1000 ⇒ `$10`。我方：小數全零才去掉「分隔符＋零」（10.50 ⇒ 保留；本尊對非全零小數的輸出未取得，V；91 §3.77）。
    # @return [String]
    def strip_trailing_zeros(rendered)
      rendered.sub(/([.,])00(?!\d)/, "")
    end

    # 單一佔位符的數字形。
    # @param style [String] STYLES 鍵
    # @return [String]
    def number(cents, style)
      thousands, decimal = STYLES.fetch(style)
      abs = cents.abs
      whole, frac = decimal ? abs.divmod(100) : [ (abs + 50) / 100, nil ]
      grouped = whole.to_s.gsub(/\B(?=(\d{3})+(?!\d))/, thousands)
      out = decimal ? "#{grouped}#{decimal}#{format('%02d', frac)}" : grouped
      cents.negative? ? "-#{out}" : out
    end

    # 過濾器輸入 ⇒ cents。nil／空字串 ⇒ nil（呼叫端輸出空字串；hoko.vip 佔位商品卡 `<s …> </s>` 形）；
    # 數字字串照整數解析；小數（float）四捨五入到整數 cents；非數字 ⇒ 0（本尊對非整數／非數字輸入的行為未取得，V；91 §3.77）。
    # @return [Integer, nil]
    def coerce(input)
      case input
      when nil then nil
      when Integer then input
      when Float, BigDecimal, Rational then input.round
      else
        s = input.to_s.strip
        return nil if s.empty?

        Integer(s, exception: false) || (Float(s, exception: false)&.round) || 0
      end
    end
  end
end
