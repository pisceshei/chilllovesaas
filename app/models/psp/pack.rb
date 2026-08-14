# PSP 的宣告（65 §D.3）。
#
# 🔴 **空表 ≠ 缺鍵**，這條在 65 §D.3 出現三次
# （`minor_unit_overrides`／`divisibility`／`enable_gate`）：
# **明文空表是「已查證、無例外」，沒有這個鍵是「沒人查過」⇒ 不得 enable。**
# 58 §A.3 已經吃過一次虧，此處沿用。
# ⇒ 驗證一律用 `Hash#key?`，**禁止** `|| {}` 與 `dig(...).to_h`——
# 那兩種寫法會把「缺鍵」靜默變成「空表」，正好抹掉這個區分。
class Psp::Pack
  # 兩種格式都必填的鍵（`limits.money_boundary.psp_pack_required_keys`）。
  # 逐鍵語義見 65 §D.3。
  def self.required_keys
    Limits.enum(:money_boundary, :psp_pack_required_keys).map { |k| k.downcase.to_sym }
  end

  # `minor_units` 專用的必填鍵。
  def self.required_keys_for_minor_units
    Limits.enum(:money_boundary, :psp_pack_required_keys_when_minor_units).map { |k| k.downcase.to_sym }
  end

  # `decimal_string` 專用的必填鍵。
  def self.required_keys_for_decimal_string
    Limits.enum(:money_boundary, :psp_pack_required_keys_when_decimal_string).map { |k| k.downcase.to_sym }
  end

  attr_reader :code, :raw

  # @param code [Symbol] pack 代碼（例：`:stripe`）
  # @param raw [Hash{Symbol=>Object}] **已正規化為 Symbol 鍵**的宣告內容
  #   （正規化由 `Psp::Registry` 負責，見該類別的說明）
  def initialize(code, raw)
    @code = code.to_sym
    @raw = upcase_currency_keys(raw)
    validate!
  end

  # 金額格式。
  #
  # @return [Symbol] `:minor_units` 或 `:decimal_string`
  # @raise [Psp::AmountFormatUndeclared] 未宣告（A0；🔴 不得預設）
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §D.2 A0
  def amount_format
    raw.fetch(:amount_format).to_sym
  end

  # 該 pack 對應的值物件類別（L3 的 adapter 用它做型別斷言）。
  #
  # @return [Class] `Money::PspMinor` 或 `Money::PspDecimal`
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §C.1 L3
  def amount_value_class
    amount_format == :minor_units ? Money::PspMinor : Money::PspDecimal
  end

  # 該幣別的 minor unit exponent。
  #
  # 解析順序：**pack 的 `minor_unit_overrides` 優先於底表**——
  # Adyen 明文說自家表覆蓋 ISO，所以覆蓋必須贏。
  #
  # @param currency [String, Symbol] ISO 4217 代碼
  # @return [Integer, nil] exponent；查不到時為 `nil`（呼叫端負責 raise A1）
  # @raise [Psp::PackInvalid] 對 `decimal_string` 型 pack 呼叫本方法
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §D.2 A1
  def minor_unit_exponent(currency)
    # 🔴 對 `decimal_string` 型 pack 問 minor unit 是**呼叫端的錯**——那家根本不用 minor unit。
    # 不加這一條的話會拋 `KeyError: key not found: :minor_unit_overrides`，
    # 而那個訊息會讓人以為是 pack 宣告漏了鍵，於是去補一個**不該存在**的鍵。
    unless amount_format == :minor_units
      raise Psp::PackInvalid,
        "pack #{code} 的 amount_format 是 #{amount_format}，它不用 minor unit——" \
        "問錯問題了（65 §D.4：Airwallex 型 PSP 收的是十進位主單位字串）"
    end

    key = currency.to_s.upcase.to_sym
    overrides = raw.fetch(:minor_unit_overrides)
    return overrides[key] if overrides.key?(key)
    return nil unless raw.fetch(:minor_unit_source).to_sym == :iso4217

    Psp.iso4217_exponents[key]
  end

  # `decimal_string` 格式的小數位數。
  #
  # @return [Integer]
  # @note 副作用：無。
  def decimal_places
    raw.fetch(:decimal_places)
  end

  # 該幣別的整除約束（A5）。
  #
  # @param currency [String, Symbol]
  # @return [Integer, nil] 倍數；無約束時為 `nil`
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §D.2 A5
  def divisibility_for(currency)
    raw.fetch(:divisibility)[currency.to_s.upcase.to_sym]
  end

  # 這個 pack 可不可以被啟用。
  #
  # @return [Boolean]
  # @note 副作用：無。
  def enabled?
    raw[:enabled] == true
  end

  private

  # 把**幣別對照表**的鍵一律轉成大寫 Symbol。
  #
  # 只動 `minor_unit_overrides` 與 `divisibility` 兩個鍵——**這裡才知道它們的值是幣別表**。
  # pack 是人手寫的 YAML，`jpy:` 與 `JPY:` 遲早會同時出現；而查表端一律 `upcase`，
  # 不在這裡收斂的話，`jpy: 0` 這個宣告會被**靜默忽略**，
  # 然後對 JPY raise「該幣別未宣告」——**而 pack 裡逐字寫著 jpy: 0**。
  def upcase_currency_keys(raw)
    %i[minor_unit_overrides divisibility].each_with_object(raw.dup) do |key, result|
      next unless result[key].is_a?(Hash)

      result[key] = result[key].to_h { |code, value| [ code.to_s.upcase.to_sym, value ] }
    end
  end

  # 宣告完整性驗證。缺任一必填鍵 ⇒ 不得 enable（65 §D.3）。
  def validate!
    missing = self.class.required_keys.reject { |key| raw.key?(key) }
    raise Psp::PackInvalid, "pack #{code} 缺必填鍵：#{missing.join(', ')}" if missing.any?

    format_key = raw[:amount_format]
    raise Psp::AmountFormatUndeclared, "pack #{code} 未宣告 amount_format（A0，不得預設）" if format_key.nil?

    allowed = Limits.enum(:money_boundary, :psp_amount_formats).map(&:downcase)
    unless allowed.include?(format_key.to_s.downcase)
      raise Psp::PackInvalid, "pack #{code} 的 amount_format #{format_key.inspect} 不在 #{allowed.inspect} 內"
    end

    case amount_format
    when :minor_units    then validate_minor_units!
    when :decimal_string then validate_decimal_string!
    end

    validate_enable_gate!
  end

  def validate_minor_units!
    missing = self.class.required_keys_for_minor_units.reject { |key| raw.key?(key) }
    raise Psp::PackInvalid, "pack #{code}（minor_units）缺鍵：#{missing.join(', ')}" if missing.any?
  end

  def validate_decimal_string!
    missing = self.class.required_keys_for_decimal_string.reject { |key| raw.key?(key) }
    raise Psp::PackInvalid, "pack #{code}（decimal_string）缺鍵：#{missing.join(', ')}" if missing.any?

    # A6：我方儲存尺度 ×100 只能無損表達 2 位。宣告 3 位卻只給得出 2 位
    # ＝**靜默的精度謊報**（我方送 `"2.90"`，PSP 以為那是 `"2.900"`）。
    max = Limits.fetch(:money_boundary, :psp_decimal_max_places)
    if decimal_places > max
      raise Psp::PackInvalid,
        "pack #{code} 宣告 decimal_places=#{decimal_places} > #{max}（A6：不得 enable）"
    end

    # A6b：**位數下限**（2026-08-15，PR #29 驗收指出的缺口）。
    #
    # 🔴 只有上限時，`decimal_places: 0` 或 `1` 是完全合法的宣告，而
    # `Money::Storage#to_psp_decimal` 走 `Money.fixed_string(major, decimal_places)`，
    # 它會 `value.round(digits)` **靜默四捨五入**：
    #   decimal_places=1 ＋ HKD 14.85（儲存 `1485`）⇒ 送出 `"14.9"`
    #   ＝**帳上 14.85、送款 14.90，差額 0.05 沒有任何一張表記得住**。
    # 這正是 65 §D.2 A5 逐字說的「自動湊整是最壞的處置」。
    #
    # 🔴 **這條缺口與 `minor_units` 側不對稱**：那一側有 A3 的餘數 raise
    # （`cents % divisor != 0` ⇒ `NonIntegralConversion`）順手擋住，
    # `decimal_string` 側**沒有等價物**——A3 是 minor_units 專用。
    # ⚠️ 而且它**在 HKD 這個基準法域上就會發生**，不像 exponent 的錯只在
    # zero-decimal 幣別現形 ⇒ 現有 §H 矩陣（全部宣告 2 位）測不到。
    #
    # 🔴 **為什麼是 reject 而不是支援 sub-2 位**：至今沒有任何一家真的用 sub-2 位的 PSP
    # （65 §D 無出處），要「支援」得先發明湊整規則（進位方向？差額記哪張表？）
    # ——那是憑空造規則。fail-closed 的代價是「真出現時第一次呼叫就 raise」，
    # 那是**看得見**的失敗；不擋的代價是**靜默送錯金額**。
    # 全文與裁定：`docs/specs/65` §D.4、`docs/DECISIONS.md` D16。
    min = Limits.fetch(:money_boundary, :psp_decimal_min_places)
    return if decimal_places >= min

    raise Psp::PackInvalid,
      "pack #{code} 宣告 decimal_places=#{decimal_places} < #{min}（A6b：不得 enable）——" \
      "位數不足會讓 `fixed_string` 靜默四捨五入，🔴 不得自動湊整（65 §D.2 A5）"
  end

  # 🔴 `enable_gate` 非空 ⇒ `enabled` 必為 false。
  # 這一條把「V 編號還沒結案」變成一個**機械**限制，而不是一句備忘。
  def validate_enable_gate!
    gates = raw.fetch(:enable_gate)
    return if gates.empty? || !enabled?

    raise Psp::PackInvalid,
      "pack #{code} 的 enable_gate #{gates.inspect} 未結案，不得 enabled: true（65 §D.3）"
  end
end
