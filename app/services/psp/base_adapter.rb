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

  # 把金額值物件變回線上形態——**這是唯一變回 `Integer`／`String` 的地方**。
  #
  # @param amount [Money::PspMinor, Money::PspDecimal] 該 pack 宣告格式對應的值物件
  # @return [Integer, String] 線上形態
  # @raise [TypeError] 型別不符該 pack 宣告的格式，或 `psp` 不相符
  # @note 副作用：無。
  # @see docs/specs/65-money-unit-boundary.md §C.1 L3
  def to_payload(amount)
    assert_amount!(amount)
    amount.is_a?(Money::PspMinor) ? amount.minor : amount.string
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
end
