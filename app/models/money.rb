# 金額的表示法邊界（鐵律 3 的執行期落點；契約全文＝`docs/specs/65`）。
#
# ## 為什麼需要值物件而不是註釋
#
# 這個 bug 有三種形態，**同一個根因**：
#   - 把儲存值直接送 PSP ＝ **收款 100 倍**（JPY ¥1,480 儲存 `148000`，送出必須是 `1480`）
#   - 把 PSP 回報值直接落庫 ＝ **少記 99%**
#   - 拿 PSP 金額直接比對 checkout 金額 ＝ **每張 JPY 訂單被判成金額不符而自動退款**
#
# 🔴 **三者在 HKD／USD 這些 exponent=2 的幣別下測試全綠**——`divisor` 是 1，
# 錯誤實作與正確實作的輸出**完全相同**。這就是為什麼註釋擋不住它：
# 註釋唯一能起作用的時機是「有人心裡有疑問而去查」，而這個 bug
# **不會讓任何人產生疑問**（65 §C.4）。
#
# ## Zeitwerk 形狀約束
#
# 🔴 本檔以**單一檔案**定義 `Money` 與其全部巢狀常數。
# 日後若有人新增 `app/models/money/` 目錄（例如 `money/display.rb`），
# Zeitwerk 會同時期待單檔與目錄，容易出現「改了沒生效」的難查問題。
# **要拆就整檔一起拆。**
#
# @see docs/specs/65-money-unit-boundary.md
# @see CLAUDE.md 鐵律 3
module Money
  # 本模組所有例外的共同祖先，方便呼叫端一次 rescue。
  Error = Class.new(StandardError)

  # A3：`cents % divisor != 0`——上游的湊整規則沒套用。
  # 🔴 **不四捨五入**：悄悄抹掉 50 分會讓對帳永遠差幾分錢卻查不出來。
  NonIntegralConversion = Class.new(Error)

  # 解析外部十進位字串時小數超過宣告位數。🔴 不 round（58 §G.3 規則 2）。
  ExcessPrecision = Class.new(Error)

  # 跨幣別操作（相加、比較、轉換）。65 §F.3：跨幣別不得直接相加。
  CurrencyMismatch = Class.new(Error)

  class << self
    # 儲存尺度乘數（一律 ×100，**不看幣別**）。
    #
    # 🔴 讀 `limits.yml` 而不是硬編 `100`（鐵律 6）。
    # `docs/specs/65` §A 第 2 點明說「日後要支援 exponent=3，改的是
    # `storage_scale_multiplier`，不是轉換函式」——硬編就讓那句話變成謊話。
    #
    # ⚠️ **與 `max_supported_iso_exponent` 是兩個不同的鍵**：
    # 前者是**儲存尺度**（本方法），後者是**PSP 換算時我方能表達的最大 exponent**。
    # 65 §D.1 的 divisor 公式用的是後者。兩者目前數值相容（100 ＝ 10²）但語義不同，
    # 不得互相代用。
    #
    # @return [Integer] 儲存尺度乘數
    # @note 副作用：無；只讀已載入的 limits 設定。
    # @see docs/specs/65-money-unit-boundary.md §A
    def storage_scale
      Limits.fetch(:money_boundary, :storage_scale_multiplier)
    end

    # R4 十進位字串的小數位數。
    #
    # @return [Integer]
    # @note 副作用：無。
    def decimal_digits
      Limits.fetch(:money_boundary, :decimal_string_digits)
    end

    # 把 `BigDecimal` render 成固定位數的十進位字串。
    #
    # 🔴 **不得用 `format("%.2f", big_decimal)`**——`Kernel#format` 的 `%f`
    # **內部會先轉成 Float**，於是在大數上失真：
    # `9_223_372_036_854_775_807`（BIGINT max）會變成 `…76000`，
    # 往返後與原值不等。
    # ⚠️ 這個 bug **只在極大值現形**，一般金額測試全綠——與 65 §0.2 描述的
    # 「exponent=2 幣別下測試全綠」是同一種病：**測試選的樣本決定了看不看得到**。
    # T10（USD 邊界值 `0` / `1` / BIGINT max）就是為此存在的。
    #
    # 🔴 **`digits` 為 0 時原本輸出 `"1480.0"`**（2026-08-15 修，PR #29 驗收指出）。
    # `"0".rjust(0, "0")` 回 `"0"`，而小數點是無條件接上去的
    # ⇒ 宣告 0 位卻吐出一位小數，**連它自己的 `@return` 契約（「定位數」）都不符**。
    # ⚠️ 這個 bug 走不到生產路徑（唯二呼叫端一個傳 `Money.decimal_digits`＝2、
    # 另一個傳 `pack.decimal_places` 而 pack 已被 A6b 擋在 2 位），
    # 但**低階格式化函式對任意 `digits` 都該是對的**——留著就是下一個呼叫端的地雷。
    #
    # 🔴 **分層刻意如此**：本函式**不做**「幾位才合法」的政策判斷，
    # 那是 `Psp::Pack#validate_decimal_string!`（A6／A6b）的事。
    # 低階格式化器管「怎麼 render」，政策層管「准不准 render」——
    # 把政策塞進這裡會讓 `Money::Decimal`（恆 2 位，與 PSP 無關）也被 PSP 規則綁住。
    #
    # @param value [BigDecimal] 主單位金額
    # @param digits [Integer] 小數位數（非負；0 表示不帶小數點）
    # @return [String] 定位數、無幣別符號、無千分位、小數點為 `.`
    # @raise [ArgumentError] `digits` 為負
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §H.2 T10、§D.5
    def fixed_string(value, digits)
      raise ArgumentError, "digits 不得為負（實得 #{digits}）" if digits.negative?

      rounded = value.round(digits)
      sign = rounded.negative? ? "-" : ""
      abs = rounded.abs
      whole = abs.to_i
      return "#{sign}#{whole}" if digits.zero?

      frac = ((abs - whole) * (10**digits)).round.to_i
      "#{sign}#{whole}.#{frac.to_s.rjust(digits, '0')}"
    end

    # A5：pack 宣告的整除約束。
    #
    # 🔴 **基準一律是「即將送出去的那個值，用該 PSP 自己的單位」**——
    # `minor_units` 檢查 minor 整數，`decimal_string` 檢查主單位的 `BigDecimal`。
    # **為什麼不統一成以 cents 為基準**：那樣 pack 作者就得把 PSP 文檔上的數字
    # **自己換算一次**再填進 pack（「minor 須整除 100」要填成「cents 須整除 10000」）
    # ——**而那個換算就是本篇從頭到尾在防的那一類手工換算**。
    # 宣告值必須能與來源文件**逐字對照**，否則 pack 就成了下一個出錯的地方。
    #
    # 🔴 **違反時不得自動湊整**：湊整會讓「送出去的錢」與「帳上記的錢」不同，
    # 而差額沒有任何一張表記得住。
    #
    # ⚠️ **`divisibility_scope` 目前被忽略**：V-206（該約束在 charge／refund／payout
    # 哪些操作上成立）未結案，65 §L 的當前處置是「已宣告者以**最嚴格**解讀
    # （charge 亦套用）」⇒ 一律檢查。scope 現在只用於錯誤訊息。
    #
    # @param pack [Psp::Pack]
    # @param currency [String]
    # @param value [Integer, BigDecimal] 即將送出的值，用該 PSP 自己的單位
    # @return [void]
    # @raise [Psp::DivisibilityViolation]
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §D.2 A5、§H.2 T16
    def check_divisibility!(pack, currency, value)
      multiple = pack.divisibility_for(currency)
      return if multiple.nil?
      return if (value % multiple).zero?

      raise Psp::DivisibilityViolation,
        "#{currency} 金額 #{value} 不是 #{multiple} 的倍數（pack #{pack.code}，" \
        "scope=#{pack.raw[:divisibility_scope].inspect}）——🔴 不得自動湊整"
    end

    # 🔴 **PSP 回應／webhook 金額的唯一入向閘門**（65 §E X8）：
    # 原始值先依 pack 宣告的 `amount_format` 包成對應值物件，再轉 R1。
    # **包不出來就不准進**——形態與宣告不符（宣告 number 卻收到字串…）代表
    # pack 宣告錯了或對方改了 API，呼叫端（webhook consumer）收到 raise 後進死信，
    # 不得就地猜一個轉換。
    #
    # 🔴 `decimal_number` 側的 Float 陷阱：`JSON.parse` 預設把 JSON number 解成
    # **Float**——adapter 解析 webhook body 必須 `JSON.parse(raw, decimal_class: BigDecimal)`，
    # 本方法對 Float 一律 `TypeError`（鐵律 3：出現 float 即 bug），把這個約定變成機械限制。
    #
    # @param raw [Integer, String, BigDecimal] PSP 給的原始金額值
    # @param currency [String, Symbol]
    # @param psp [String, Symbol] pack 代碼
    # @return [Money::Storage]
    # @raise [TypeError] 形態與 pack 宣告的 `amount_format` 不符（Float 恆拒）
    # @raise [Money::ExcessPrecision] 小數超過該幣別生效位數（🔴 不 round）
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §E
    def from_psp_amount(raw, currency:, psp:)
      pack = Psp.registry.fetch(psp)
      value =
        case pack.amount_format
        when :minor_units
          unless raw.is_a?(Integer)
            raise TypeError, "pack #{pack.code} 宣告 minor_units，只收 Integer，實得 #{raw.class}"
          end

          PspMinor.__build(minor: raw, currency: currency.to_s.upcase, psp: pack.code)
        when :decimal_string
          unless raw.is_a?(String)
            raise TypeError, "pack #{pack.code} 宣告 decimal_string，只收 String，實得 #{raw.class}"
          end

          PspDecimal.__build(string: raw, currency: currency.to_s.upcase, psp: pack.code)
        when :decimal_number
          # Integer 也收：JSON number `1480` 即使帶 decimal_class 也解成 Integer。
          unless raw.is_a?(BigDecimal) || raw.is_a?(Integer)
            raise TypeError,
              "pack #{pack.code} 宣告 decimal_number，只收 BigDecimal／Integer，實得 #{raw.class}" \
              "（Float 即 bug——webhook 解析要 `JSON.parse(raw, decimal_class: BigDecimal)`）"
          end

          PspNumber.__build(number: BigDecimal(raw), currency: currency.to_s.upcase, psp: pack.code)
        end
      storage = value.to_storage
      instrument_conversion(direction: :inbound, pack:, currency: storage.currency,
                            storage_cents: storage.cents, value:)
      storage
    rescue Psp::Error, Money::Error, TypeError => error
      instrument_failure(direction: :inbound, psp:, currency:, error:)
      raise
    end

    # 65 §K.8：每次 X7／X8 轉換落結構化事件（subscriber 在
    # config/initializers/money_conversion_logging.rb 寫 JSON 日誌；G6-1a 落地）。
    # 對帳事故時這些欄位就是完整還原資訊；欄位集依 §K.8 逐項。
    def instrument_conversion(direction:, pack:, currency:, storage_cents:, value:)
      wire = case value
      when PspMinor   then value.minor
      when PspDecimal then value.string
      when PspNumber  then value.number.to_s("F")
      end
      payload = { direction:, psp: pack.code, amount_format: pack.amount_format,
                  currency:, storage_cents:, wire_value: wire,
                  divisibility: pack.divisibility_for(currency) }
      if pack.amount_format == :minor_units
        payload[:exponent] = pack.minor_unit_exponent(currency)
      else
        payload[:decimal_places] = pack.decimal_places_for(currency)
      end
      ActiveSupport::Notifications.instrument("money.psp_conversion", payload)
    end

    # 65 §K.9：轉換失敗＝P1 級（代表上游算錯或 pack 沒宣告，不是使用者輸入錯）。
    def instrument_failure(direction:, psp:, currency:, error:)
      ActiveSupport::Notifications.instrument(
        "money.psp_conversion_failure",
        direction:, psp: psp.to_s, currency: currency.to_s,
        error_class: error.class.name, error_message: error.message, severity: "P1"
      )
    end
  end

  # ── R1：儲存 cents ─────────────────────────────────────────────────────────
  #
  # 所有 DB 金額欄位（後綴 `_cents`）、全部業務層運算、冪等鍵、會計分錄。
  # **一律 ×100，不看幣別。**
  #
  # 🔴 **不實作 `to_i` / `to_int` / `coerce`**。一旦有隱式轉換，
  # `Integer()`、多數序列化器、字串插值都會自動呼叫它，**四層防呆全部失效**。
  # `Data` 預設就沒有這四個方法，本檔也不得補上——`money_spec` 有反射斷言守住。
  #
  # 🔴 **正負皆合法**（65 §A.7）：`Order.totalOutstandingSet` 與
  # `refundDiscrepancySet` 官方明文可為負，退款差額與撤銷也需要。
  # 正負的業務規則驗在**寫入端與 PSP adapter**，不在型別層——
  # 在值物件上驗非負，等於用型別系統表達一個只在某些路徑成立的業務規則。
  Storage = Data.define(:cents, :currency) do
    # 從 DB 的整數欄位建一個儲存金額。
    #
    # @param cents [Integer] 儲存尺度的整數（一律 ×100）
    # @param currency [String, Symbol] ISO 4217 代碼
    # @return [Money::Storage]
    # @raise [TypeError] cents 不是 Integer 時拋出（float 即 bug，鐵律 3）
    # @note 副作用：無。
    def self.from_cents(cents, currency)
      unless cents.is_a?(Integer)
        raise TypeError, "cents 必須是 Integer，實得 #{cents.class}（鐵律 3：出現 float 即 bug）"
      end

      new(cents:, currency: currency.to_s.upcase)
    end

    # 轉成 R4 十進位字串（JSON-LD／feed／CSV／MoneyV2／物流商）。
    #
    # 🔴 **全程 BigDecimal，禁 float**：float 的十進位表示不穩定，
    # 而這個字串會直接進 JSON-LD 的 `Offer.price` 與物流商 payload。
    #
    # @return [Money::Decimal]
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §A R4
    def to_decimal
      major = BigDecimal(cents).div(BigDecimal(Money.storage_scale), 40)
      Decimal.from_string(Money.fixed_string(major, Money.decimal_digits), currency)
    end

    # 🔴 **送 PSP／任何外部收款系統前的唯一出口**（65 §D.1，X7）。
    #
    # 儲存尺度與該 PSP 要的單位是兩件事，而**「單位」本身又有兩個維度**：
    #   顯示 → `currency_display.force_minor_unit_digits` = 2（裁定二）
    #   儲存 → `money_boundary.storage_scale_multiplier` = 100（不看幣別）
    #   對外 → ①格式 `amount_format` ②該格式下的參數
    #
    # 🔴 **舊名 `to_psp_minor` 不保留為別名**——留著別名等於留著一條
    # 「不看 `amount_format`」的路徑，而那正是 Airwallex 型 PSP 出事的形狀。
    #
    # @param psp [String, Symbol] pack 代碼
    # @return [Money::PspMinor, Money::PspDecimal, Money::PspNumber] 依 pack 宣告的格式
    # @raise [Psp::AmountFormatUndeclared] pack 未宣告格式（A0；不得預設）
    # @raise [Psp::MinorUnitUndeclared] 該幣別的 minor unit 未宣告（A1）
    # @raise [Psp::UnsupportedCurrencyExponent] exponent > 2（A2）
    # @raise [Money::NonIntegralConversion] 換算有餘數（A3／A6c；不四捨五入）
    # @raise [Psp::DivisibilityViolation] 違反整除約束（A5；不自動湊整）
    # @note 副作用：無；只讀 pack 宣告。
    # @see docs/specs/65-money-unit-boundary.md §D.1、§D.2
    def to_psp_amount(psp:)
      pack = Psp.registry.fetch(psp)
      value = case pack.amount_format
      when :minor_units    then to_psp_minor(pack)
      when :decimal_string then to_psp_decimal(pack)
      when :decimal_number then to_psp_number(pack)
      end
      roundtrip_selfcheck!(value)
      Money.instrument_conversion(direction: :outbound, pack:, currency:,
                                  storage_cents: cents, value:)
      value
    rescue Psp::Error, Money::Error => error
      Money.instrument_failure(direction: :outbound, psp:, currency:, error:)
      raise
    end

    private

    # X7a：整數 minor unit（Stripe／Adyen／Datatrans 型）。
    def to_psp_minor(pack)
      exponent = pack.minor_unit_exponent(currency)                                    # A1
      if exponent.nil?
        raise Psp::MinorUnitUndeclared,
          "pack #{pack.code} 未宣告 #{currency} 的 minor unit（A1：未宣告 ≠ 預設 ISO）"
      end

      max = Limits.fetch(:money_boundary, :max_supported_iso_exponent)                 # A2
      if exponent > max
        raise Psp::UnsupportedCurrencyExponent,
          "#{currency} exponent=#{exponent} > #{max}——我方儲存尺度（×#{Money.storage_scale}）表達不了"
      end

      divisor = 10**(max - exponent)                                                   # JPY⇒100、HKD⇒1
      unless (cents % divisor).zero?                                                   # A3
        raise Money::NonIntegralConversion,
          "#{cents} 無法無損換成 #{currency} 的 minor unit（餘 #{cents % divisor}）——" \
          "🔴 上游的湊整規則沒套用，不得四捨五入抹掉"
      end

      minor = cents / divisor
      Money.check_divisibility!(pack, currency, minor)                                 # A5
      PspMinor.__build(minor:, currency:, psp: pack.code)                              # A4
    end

    # X7b：十進位主單位字串（PayPal 型）。
    # <!-- 2026-08-31 更正：本分支的實證代表原寫 Airwallex——69 號 2026-08-12 的結論。
    #      2026-08-31 一手複驗推翻：Airwallex amount 是 JSON **number**（走 X7c），
    #      decimal_string 的現任實證代表＝PayPal（value 官方 pattern 是字串）。65 §D.4。-->
    def to_psp_decimal(pack)
      places = declared_places_with_guard!(pack)                                       # A7＋A6c
      major = BigDecimal(cents).div(BigDecimal(Money.storage_scale), 40)               # 🔴 全程 BigDecimal
      Money.check_divisibility!(pack, currency, major)                                 # A5
      string = Money.fixed_string(major, places)                                       # A6
      PspDecimal.__build(string:, currency:, psp: pack.code)                           # A4
    end

    # X7c：十進位主單位「數」（Airwallex 型；wire form＝JSON number）。
    # 🔴 與 X7b 的差別只有線上形態（number vs string）——單位語義相同（主單位），
    #    但兩者不得共用型別：共用會讓「宣告 number 的 pack 收到字串」這種
    #    **宣告錯誤**在我方側靜默通過、留給對方 API 決定收不收。
    def to_psp_number(pack)
      places = declared_places_with_guard!(pack)                                       # A7＋A6c
      major = BigDecimal(cents).div(BigDecimal(Money.storage_scale), 40)               # 🔴 全程 BigDecimal
      Money.check_divisibility!(pack, currency, major)                                 # A5
      PspNumber.__build(number: major, currency:, psp: pack.code)                      # A4
    end

    # A7：該幣別的生效位數（pack 基準位數＋per-currency 覆蓋，覆蓋優先——
    #     PayPal 官方逐字「This currency does not support decimals.」對 HUF/JPY/TWD、
    #     Airwallex payments 側零小數 20 幣，兩家都以逐幣別表覆蓋基準 2 位）。
    # A6c：儲存 cents 無法無損表達為生效位數 ⇒ raise，🔴 **不得 round**——
    #     這是 A3 在 decimal 兩格式下的等價物，補上 A6b 註明過的那條不對稱
    #     （「decimal 側沒有 A3 等價物」自本條起不再成立）。
    #     JPY 儲存 148050（¥1,480.50）對 0 位幣別 ⇒ raise；靜默湊成 1481 會讓
    #     送款與帳上差 0.50 而沒有任何一張表記得住（65 §D.2 A5 同理由）。
    def declared_places_with_guard!(pack)
      places = pack.decimal_places_for(currency)
      step = Money.storage_scale / (10**places)
      unless (cents % step).zero?
        raise Money::NonIntegralConversion,
          "#{cents} 無法無損表達為 #{currency} 的 #{places} 位小數（pack #{pack.code}，"           "餘 #{cents % step}）——🔴 不得四捨五入抹掉（A6c）"
      end

      places
    end

    # 往返自檢（65 §D.1 末段；`limits.money_boundary.roundtrip_selfcheck_envs`）：
    # 非生產環境每次轉換都驗 `from(to(x)) == x`。它不是防線本體（防線是 A 系斷言），
    # 是「三種格式的出向與入向不成對」這一類實作腐壞的煙霧偵測器。
    def roundtrip_selfcheck!(value)
      return unless Limits.enum(:money_boundary, :roundtrip_selfcheck_envs).include?(Rails.env)
      return if value.to_storage == self

      raise Money::Error,
        "往返自檢失敗：#{self.inspect} → #{value.inspect} → #{value.to_storage.inspect}"         "（65 §D.1：出向與入向不成對＝其中一側在湊整或掉位）"
    end

    # 🔴 **相同幣別才可比較**。跨幣別比較恆為 false 會讓「兩筆金額不同」
    # 與「兩筆金額不可比」變成同一件事——而後者是必須讓呼叫端知道的。
    #
    # ## 兩種「不可比」要分開處置（2026-08-15 修，PR #29 驗收 🟡 指出）
    #
    # | 對象 | 回傳 | `==` 的結果 | `<` 的結果 |
    # |---|---|---|---|
    # | 不是 `Storage`（`nil`／`Integer`／字串…） | `nil` | `false` | `ArgumentError`（Comparable 給的） |
    # | 是 `Storage` 但幣別不同 | — | 🔴 `CurrencyMismatch` | 🔴 `CurrencyMismatch` |
    #
    # 🔴 **原本對非 `Storage` 也 `raise TypeError`，那是 bug**：`include Comparable` 之後
    # `==` 是由 `<=>` 實作的 ⇒ `money == nil` **會拋例外而不是回 `false`**。
    # 而 `==` 回 false 是 Ruby 全域的約定，`Array#include?`／`uniq`／`-`／`Hash` 查找
    # 全都靠它——一個會拋例外的 `==` 會在**完全無關的地方**炸開，
    # 且堆疊指向 `money.rb`，看不出根因。實測：`a == nil` ⇒ `TypeError`。
    # ⇒ 型別不同回 `nil`（Ruby 慣例，`1 <=> "a"` 就是 `nil`）；
    #   **幣別不同仍然 raise**，因為那是本專案刻意加嚴的那一條，不是型別問題。
    #
    # 🔴 **必須是 public**：原本它落在 `private` 區塊裡 ⇒ 直接呼叫 `a <=> b`
    # 得到 `NoMethodError`（而文檔註釋宣稱它 raise `TypeError`／`CurrencyMismatch`）。
    # `a < b` 之所以還能動，是因為 `Comparable#<` 是**內部**呼叫，不受 private 限制
    # ——所以既有測試（只用 `a < b`）**證明不了 `<=>` 本身可用**。
    #
    # @param other [Object]
    # @return [Integer, nil] -1／0／1；`other` 不是 `Money::Storage` 時為 `nil`
    # @raise [Money::CurrencyMismatch] 同為 `Storage` 但幣別不同
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §F.3
    def <=>(other)
      return nil unless other.is_a?(Storage)
      raise CurrencyMismatch, "#{currency} vs #{other.currency}（65 §F.3）" unless currency == other.currency

      cents <=> other.cents
    end
    include Comparable
    public :<=>
  end

  # ── R4：十進位字串 ─────────────────────────────────────────────────────────
  #
  # 主單位、恆兩位小數、**無幣別符號、無千分位**、小數點為 `.`。
  #
  # 🔴 **沒有 `:psp` 欄位——它不是對 PSP 的表示法。**
  # 它與 R6（`Money::PspDecimal`）的**線上形態完全相同**（都是 `"1480.00"` 這種字串），
  # 差別只在有沒有 `:psp`。沒有 `:psp` 就無法在 adapter 端斷言
  # 「這個值是為這一家算的」，而那正是型別防線存在的全部理由。
  # **任何人不得把兩者合併成一個型別。**
  Decimal = Data.define(:string, :currency) do
    # @param string [String] 十進位字串
    # @param currency [String, Symbol] ISO 4217 代碼
    # @return [Money::Decimal]
    # @raise [ArgumentError] 不符 `limits.yml` 的 `decimal_string_regex`
    # @note 副作用：無。
    def self.from_string(string, currency)
      pattern = Regexp.new(Limits.fetch(:money_boundary, :decimal_string_regex))
      unless pattern.match?(string.to_s)
        raise ArgumentError, "#{string.inspect} 不符 decimal_string_regex（65 §A R4）"
      end

      new(string: string.to_s, currency: currency.to_s.upcase)
    end

    # 轉回 R1。
    #
    # @return [Money::Storage]
    # @raise [Money::ExcessPrecision] 小數超過宣告位數（🔴 不 round）
    # @note 副作用：無。
    def to_storage
      decimals = string.split(".").last.to_s.length
      if decimals > Money.decimal_digits
        raise ExcessPrecision, "#{string} 小數 #{decimals} 位 > #{Money.decimal_digits}（不得 round）"
      end

      Storage.from_cents((BigDecimal(string) * Money.storage_scale).to_i, currency)
    end
  end

  # ── R5：PSP minor unit（`amount_format: minor_units`）──────────────────────
  #
  # 🔴 **唯一建構路徑是 `Money::Storage#to_psp_amount`**（65 §C L2）。
  # 不存在「手工湊一個 PspMinor」的路徑 ⇒ §D 的 A0–A5 斷言**無法被繞過**。
  #
  # ⚠️ **`__build` 是 public——Ruby 表達不了「friend class」**。
  # `Money::Storage` 與本類別是兩個不同的類別，private class method 呼叫不到。
  # ⇒ 這條限制靠**命名（`__` 前綴）＋ CI 檢查**執行：
  # `scripts/check-money-boundary.rb` 的 C5 斷言 `app/` 下除了 `app/models/money.rb`
  # 以外**不得出現 `__build`**。這是本檔唯一一處「型別擋不住、只能靠 CI 擋」的地方，
  # 寫在這裡以免被誤讀成防線完整。
  PspMinor = Data.define(:minor, :currency, :psp) do
    # @api private 只給 `Money::Storage#to_psp_amount` 用（見類別註釋）
    def self.__build(minor:, currency:, psp:)
      new(minor:, currency:, psp:)
    end

    # 轉回 R1（入向 X8）。
    #
    # 🔴 **入向的錯不是 100 倍，是 1/100，而且更難發現**——
    # 訂單金額看起來「只是小一點」，不會觸發任何金額上限告警。
    #
    # @return [Money::Storage]
    # @raise [Psp::MinorUnitUndeclared] 該幣別未宣告
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §E
    def to_storage
      pack = Psp.registry.fetch(psp)
      exponent = pack.minor_unit_exponent(currency)
      raise Psp::MinorUnitUndeclared, "pack #{psp} 未宣告 #{currency} 的 minor unit" if exponent.nil?

      max = Limits.fetch(:money_boundary, :max_supported_iso_exponent)
      Storage.from_cents(minor * (10**(max - exponent)), currency)
    end
  end

  # ── R6：PSP 十進位主單位字串（`amount_format: decimal_string`）─────────────
  #
  # 🔴 **與 R4（`Money::Decimal`）的線上形態完全相同**，差別只有 `:psp` 欄位。
  # 那不是冗餘：沒有 `:psp` 就無法在 adapter 端斷言「這個值是為這一家算的」。
  #
  # 🔴 **R6 的等價陷阱是 `to_s`／`to_str`**（不是 `to_i`）：它內含字串，
  # `"#{amount}"` 在組 JSON body 時到處都是——一旦 `to_s` 回傳裸金額字串，
  # R6 的型別防線就跟不存在一樣。`Data` 預設的 `to_s` 回傳 inspect 形式，
  # **本檔不得覆寫它**，`money_spec` 有斷言守住。
  PspDecimal = Data.define(:string, :currency, :psp) do
    # @api private 只給 `Money::Storage#to_psp_amount` 用
    def self.__build(string:, currency:, psp:)
      new(string:, currency:, psp:)
    end

    # 轉回 R1（入向 X8）。
    #
    # 🔴 `decimal_string` 入向錯（把 `"14.80"` 當 cents 直接落庫）＝
    # **少記 99%，且在所有幣別上都成立**——不像 minor_units 只在 zero-decimal 幣別現形。
    #
    # @return [Money::Storage]
    # @raise [Money::ExcessPrecision] 小數超過 pack 宣告位數（不 round）
    # @note 副作用：無。
    def to_storage
      pack = Psp.registry.fetch(psp)
      # 🔴 無小數點的字串（PayPal 對 JPY/TWD/HUF 的合法形態，如 `"1480"`）＝0 位小數。
      #    原寫法 `string.split(".").last` 對 `"1480"` 會回整串（長度 4 被當 4 位小數）
      #    ——修於 2026-08-31（per-currency 位數落地時發現）。
      decimals = string.include?(".") ? string.split(".").last.length : 0
      places = pack.decimal_places_for(currency)
      if decimals > places
        raise ExcessPrecision,
          "#{string} 小數 #{decimals} 位 > #{currency} 生效位數 #{places}（pack #{psp}；不得 round）"
      end

      Storage.from_cents((BigDecimal(string) * Money.storage_scale).to_i, currency)
    end
  end

  # ── R7：PSP 十進位主單位「數」（`amount_format: decimal_number`）─────────────
  #
  # 🔴 **與 R6 的單位語義相同（主單位）、線上形態不同**：R6 是 JSON string、
  # R7 是 JSON **number**（Airwallex 官方逐字 "$9.99 is represented as `9.99`"，
  # schema `amount: number`，取證 2026-08-31）。兩者不得共用型別——共用會讓
  # 「宣告與實際 wire form 不符」在我方側靜默通過。
  #
  # 🔴 R7 的等價陷阱是**算術**：它內含 `BigDecimal`，`+`／`*` 若被隱式參與
  # 業務運算，就繞過了「運算一律在 R1」的鐵律。`Data` 沒有 `coerce`，
  # 本檔不得補上（與 R1 不補 `to_i` 同一條理由）。
  #
  # ⚠️ 序列化成 JSON number 是 adapter `#to_payload` 之後的事——
  # `BigDecimal#to_json` 預設吐**字串**，G6-1 的 adapter 必須自行以原文注入
  # 數字字面（65 §E X8c 註記）；本類別只保證數值無損。
  PspNumber = Data.define(:number, :currency, :psp) do
    # @api private 只給 `Money::Storage#to_psp_amount`／`Money.from_psp_amount` 用
    def self.__build(number:, currency:, psp:)
      new(number:, currency:, psp:)
    end

    # 轉回 R1（入向 X8c）。
    #
    # @return [Money::Storage]
    # @raise [Money::ExcessPrecision] 小數超過該幣別生效位數（不 round）
    # @note 副作用：無。
    def to_storage
      pack = Psp.registry.fetch(psp)
      scaled = number * Money.storage_scale
      places = pack.decimal_places_for(currency)
      step = Money.storage_scale / (10**places)
      unless scaled.frac.zero? && (scaled.to_i % step).zero?
        raise ExcessPrecision,
          "#{number.to_s('F')} 超過 #{currency} 生效位數 #{places}（pack #{psp}；不得 round）"
      end

      Storage.from_cents(scaled.to_i, currency)
    end
  end

  # ── R3：顯示字串 ───────────────────────────────────────────────────────────
  #
  # ⚠️ **本輪只做骨架**：恆兩位小數（2026-08-12 裁定二）。
  # 幣別符號與千分位由**市場的 locale** 決定（鐵律 10），而 markets 是 M5——
  # 在這裡硬編 `HK$` 就是把一個 per-market 的決定寫死成全域常數。
  module Display
    class << self
      # 把儲存金額格式化成顯示字串。
      #
      # @param storage [Money::Storage]
      # @return [String] 恆兩位小數、**不帶幣別符號**（符號待 M5 的 markets）
      # @raise [TypeError] 傳的不是 `Money::Storage`
      # @note 副作用：無。
      # @see docs/specs/65-money-unit-boundary.md §A R3
      def call(storage)
        raise TypeError, "只接受 Money::Storage，實得 #{storage.class}" unless storage.is_a?(Storage)

        storage.to_decimal.string
      end
    end
  end

  # 🔴 **關掉 `Data` 的所有再造路徑**（`docs/specs/65` §C L2）。
  #
  # `Data.define` 除了 `.new` 之外還給了**三條**公開建構路徑：
  #   - `Money::Storage[cents: 1, currency: "HKD"]` 與 `.new` 等價；
  #   - `existing.with(currency: "JPY")` 產生一個**沒有跑過任何檢查**的同型別實例；
  #   - 🔴 `Money::Storage.allocate` 產生一個 `cents` 為 `nil` 的實例，
  #     而它 **`is_a?(Money::Storage)` 為 true**——L3 的 adapter 斷言只看這個，
  #     所以一個全 nil 的假金額可以直接穿過型別防線。
  # 只把 `.new` 設 private 是**擋不住的**——而測試若只斷言 `.new`，它會全綠交付。
  # （三條都在 Ruby 3.4.10 上實測過：`.[]` 與 `#with` 建得出完整實例，
  #  `allocate` 建得出 `cents=nil` 但 `is_a?` 為真的實例。）
  #
  # `#with` 對金額特別危險：它讓「換一個幣別、保留同一個數字」變成一行程式碼，
  # 而那正是跨幣別事故的形狀。
  # 🔴 **五個型別的 `.new` 全部設 private**，唯一入口是各自的 factory
  # （`Storage.from_cents`／`Decimal.from_string`／R5・R6・R7 的 `__build`）。
  #
  # ⚠️ **第一版只關了 R5／R6 的 `.new`**，理由是「R1／R4 是入口，要留著可建」
  # ——那個理由是錯的：**入口是 `from_cents`，不是 `.new`**。
  # Codex 在 PR #29 的 review 指出這個洞，實測比他描述的更嚴重：
  #
  #     Money::Storage.new(cents: 1.5, currency: "hkd")   # 建得起來
  #       → currency 是 "hkd" 沒被正規化 ⇒ pack 的 minor_unit_overrides[:HKD] 查不到
  #       → to_decimal 回 "0.02" ⇒ float 已經進了金額路徑
  #       → minor_units 路徑被 A3 擋下（1.5 % 1 = 0.5 ≠ 0）✅
  #       → 🔴 **decimal_string 路徑沒有那道閘門，"0.02" 一路送到 PSP**
  #
  # ⇒ `from_cents` 的 Integer 閘門與 `upcase` 正規化只有在 `.new` 也關掉之後才是**閘門**；
  #   在那之前它只是「建議走的那條路」。
  [ Storage, Decimal, PspMinor, PspDecimal, PspNumber ].each do |klass|
    klass.singleton_class.send(:private, :new)
    klass.singleton_class.send(:private, :[])
    klass.singleton_class.send(:private, :allocate)
    klass.send(:undef_method, :with)
  end
end
