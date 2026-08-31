# PSP adapter 的抽象基底——**L3 型別閘門**（`docs/specs/65` §C.1）。
#
# 🔴 **這是「傳裸值」與「傳錯型別」的唯一攔截點**。四層防呆裡：
#   L1（值物件無隱式轉換）擋住 `to_i` 被自動呼叫；
#   L2（唯一建構路徑）擋住手工湊一個值物件；
#   **L3（本類別）擋住「值物件是對的，但不是為這一家／這個格式算的」**；
#   L4（命名 ＋ CI）擋住還沒寫出來的路徑。
#
# 本類別攔下的三種誤用（65 §H.2 T14／T17／T18）：
#
# | 誤用 | 為什麼型別擋得住而字串擋不住 |
# |---|---|
# | 傳裸 `Integer`／裸 `String` | 沒有 `psp` 欄位可驗 |
# | 傳 `Money::Decimal`（R4，物流商／JSON-LD 用的那個） | 🔴 **它與 R6 的字串內容可能一模一樣**——`"1480.00"` 對 `"1480.00"`。**這條是唯一能證明「型別而非字串」真的在守門的測試** |
# | A 家的值送去 B 家、或格式對了家別錯了 | `psp` 欄位不符／`amount_value_class` 不符 |
#
# ⚠️ **本類別刻意做得極薄**：只做兩段斷言 ＋ 一個 `#to_payload`。
# `Psp::Registry`／`Psp::Pack`／本類別是 65 號**只有呼叫端、沒有定義端**的三個類別
# ——它們有真實的設計自由度，因此有真實的走錯風險。
# **第一家真 PSP 進來時，預期本檔會被改寫。**
#
# @see docs/specs/65-money-unit-boundary.md §C.1 L3、§H.2 T14／T17／T18
class Psp::BaseAdapter
  attr_reader :psp, :pack

  # @param psp [String, Symbol] pack 代碼
  def initialize(psp)
    @psp = psp.to_s.downcase.to_sym
    @pack = Psp.registry.fetch(@psp)
  end

  # 把金額值物件變回線上形態——**這裡應該是唯一變回 `Integer`／`String` 的地方**。
  #
  # ⚠️ **「唯一」是設計意圖，不是被機制保障的事實**（2026-08-15 修；原文寫成斷言）。
  # 任何人都可以在別處直接讀 `amount.minor` / `amount.string` 繞過本方法，
  # 而**沒有任何 CI 規則在擋**——`check-money-boundary.rb` 的 C5 守的是
  # `__build`（建構側），出向這一側目前沒有對應的執法點。
  # 🔴 要讓「唯一」成真，該加的是一條「`.minor`／`.string` 的讀取只准出現在本檔」
  # 的掃描（比照 C5 的形態）。**在那之前，讀到「唯一」請理解成「請只從這裡走」。**
  #
  # @param amount [Money::PspMinor, Money::PspDecimal, Money::PspNumber] 該 pack 宣告格式對應的值物件
  # @return [Integer, String, BigDecimal] 線上形態
  #   🔴 `decimal_number`（R7）回 `BigDecimal`——序列化成 JSON **number** 是
  #   adapter 的責任且 `BigDecimal#to_json` 預設吐字串，G6-1 落地時必須以
  #   原文注入數字字面（65 §E X8c 註記），不得經 `to_f`。
  # @raise [TypeError] 型別不符該 pack 宣告的格式，或 `psp` 不相符
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §C.1 L3
  def to_payload(amount)
    assert_amount!(amount)
    assert_sign!(amount)
    case amount
    when Money::PspMinor  then amount.minor
    when Money::PspNumber then amount.number
    else amount.string
    end
  end

  # 兩段斷言（65 §C.1 L3 逐字）。
  #
  # @param amount [Object] 待驗的值
  # @return [void]
  # @raise [TypeError]
  # @note 副作用：無。
  def assert_amount!(amount)
    expected = pack.amount_value_class
    unless amount.is_a?(expected)
      # 🔴 訊息刻意**不逐字寫出 R4 的類別名**：`scripts/check-money-boundary.rb` 的 C4
      # 掃的就是「PSP 目錄裡出現 R4 的類別名」，而它只跳過整行註釋、不跳行尾與字串
      # （那個取捨的理由見該腳本）。⇒ 在這裡寫出來會讓**唯一正確實作 C4 的檔案
      # 被 C4 判成違規**。用「R4」這個代號表達同樣的意思。
      raise TypeError,
        "#{psp} 宣告 amount_format=#{pack.amount_format}，只收 #{expected}，實得 #{amount.class}" \
        "——傳裸 Integer／裸 String／R4（物流商與 JSON-LD 用的十進位字串）一律拒收（65 §C.1 L3）"
    end

    return if amount.psp == psp

    raise TypeError,
      "這個金額是為 #{amount.psp} 算的，不是 #{psp}（A4：擋住「A 家的值送去 B 家」）"
  end

  # 🔴 **負值一律拒收**（`docs/specs/65` §A.7「送 PSP」列，2026-08-15 補實作）。
  #
  # §A.7 的表格逐字寫「PSP adapter **驗正數**，負值一律 raise」，
  # 本尊依據是 Stripe `POST /v1/refunds` 的 amount 官方逐字「A positive integer…」。
  # ⚠️ **本條在 2026-08-15 之前是「規格有、代碼零落點」**：
  # 型別層（`Money::Storage`）依 §A.7 **刻意不驗**正負（退款差額與撤銷需要負值），
  # 而「寫入端與 PSP adapter」這兩個該驗的地方**一個都沒實作**
  # ⇒ `Money::Storage.from_cents(-50_000, "HKD")` 可以一路走到線上形態
  # （`minor_units` 得 `-50000`、`decimal_string` 得 `"-500.00"`）。
  # 🔴 **退款方向由 `kind` 承載，不由符號承載**——送一個負的 charge 金額，
  # 各家 PSP 的行為從「400」到「當成正數收款」都有，而後者是靜默事故。
  #
  # ⚠️ **`== 0` 刻意放行**：§A.7 引到的官方證據只證明「負值不可送」，
  # 而 $0 auth（卡片驗證）是真實形態。§A.7 末段自己的紀律就是「沒有官方依據，不得硬寫」
  # ⇒ 零值留給第一家真 PSP 的 pack 裁定，**不在這裡發明規則**。
  #
  # @param amount [Money::PspMinor, Money::PspDecimal, Money::PspNumber]
  # @return [void]
  # @raise [TypeError] 金額為負
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §A.7
  def assert_sign!(amount)
    # 🔴 用數值判，不看字串前置的 `-`：`decimal_string` 側拿到的是字串，
    # 而 `"-0.00"` 這種形態（極小負值捨入到零）**不是負值**，看前綴會誤擋。
    value = case amount
    when Money::PspMinor  then amount.minor
    when Money::PspNumber then amount.number
    else BigDecimal(amount.string)
    end
    return unless value.negative?

    raise TypeError,
      "送 PSP 的金額不得為負（實得 #{value}）——退款方向走 kind 不走負號（65 §A.7）"
  end
end
