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
    # @param value [BigDecimal] 主單位金額
    # @param digits [Integer] 小數位數
    # @return [String] 定位數、無幣別符號、無千分位、小數點為 `.`
    # @note 副作用：無。
    # @see docs/specs/65-money-unit-boundary.md §H.2 T10
    def fixed_string(value, digits)
      rounded = value.round(digits)
      sign = rounded.negative? ? "-" : ""
      abs = rounded.abs
      whole = abs.to_i
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
    # @return [Money::PspMinor, Money::PspDecimal] 依 pack 宣告的格式
    # @raise [Psp::AmountFormatUndeclared] pack 未宣告格式（A0；不得預設）
    # @raise [Psp::MinorUnitUndeclared] 該幣別的 minor unit 未宣告（A1）
    # @raise [Psp::UnsupportedCurrencyExponent] exponent > 2（A2）
    # @raise [Money::NonIntegralConversion] 換算有餘數（A3；不四捨五入）
    # @raise [Psp::DivisibilityViolation] 違反整除約束（A5；不自動湊整）
    # @note 副作用：無；只讀 pack 宣告。
    # @see docs/specs/65-money-unit-boundary.md §D.1、§D.2
    def to_psp_amount(psp:)
      pack = Psp.registry.fetch(psp)
      case pack.amount_format
      when :minor_units    then to_psp_minor(pack)
      when :decimal_string then to_psp_decimal(pack)
      end
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

    # X7b：十進位主單位字串（Airwallex 型）。
    def to_psp_decimal(pack)
      major = BigDecimal(cents).div(BigDecimal(Money.storage_scale), 40)               # 🔴 全程 BigDecimal
      Money.check_divisibility!(pack, currency, major)                                 # A5
      string = Money.fixed_string(major, pack.decimal_places)                          # A6
      PspDecimal.__build(string:, currency:, psp: pack.code)                           # A4
    end

    # 🔴 **相同幣別才可比較**。跨幣別比較恆為 false 會讓「兩筆金額不同」
    # 與「兩筆金額不可比」變成同一件事——而後者是必須讓呼叫端知道的。
    #
    # @param other [Money::Storage]
    # @return [Integer] -1／0／1
    # @raise [Money::CurrencyMismatch] 幣別不同
    # @raise [TypeError] 型別不同
    # @note 副作用：無。
    def <=>(other)
      raise TypeError, "只能與 Money::Storage 比較，實得 #{other.class}" unless other.is_a?(Storage)
      raise CurrencyMismatch, "#{currency} vs #{other.currency}（65 §F.3）" unless currency == other.currency

      cents <=> other.cents
    end
    include Comparable
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
      decimals = string.split(".").last.to_s.length
      if decimals > pack.decimal_places
        raise ExcessPrecision, "#{string} 小數 #{decimals} 位 > pack 宣告的 #{pack.decimal_places}（不得 round）"
      end

      Storage.from_cents((BigDecimal(string) * Money.storage_scale).to_i, currency)
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
  [ Storage, Decimal, PspMinor, PspDecimal ].each do |klass|
    klass.singleton_class.send(:private, :[])
    klass.singleton_class.send(:private, :allocate)
    klass.send(:undef_method, :with)
  end

  # 🔴 R5／R6 另外把 `.new` 也設 private（65 §C L2：**唯一建構路徑**）。
  # R1／R4 的 `.new` 保持可用——它們是入口（從 DB／從外部字串建），
  # 而 R5／R6 只能由 `Money::Storage#to_psp_amount` 產生，
  # 因為那條路徑上掛著 A0–A5 五條斷言。
  [ PspMinor, PspDecimal ].each { |klass| klass.singleton_class.send(:private, :new) }
end
