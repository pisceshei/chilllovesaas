# PSP pack 的查詢入口。
#
# ## 🔴 為什麼入口一定要做「鍵型別正規化」
#
# 這個類別有**兩個來源，而它們的鍵型別不同**：
#
# | 來源 | 載入方式 | 鍵型別 |
# |---|---|---|
# | 生產 | `config/limits.yml` 經 `config/application.rb` 的 `deep_symbolize_keys` | **Symbol** |
# | 測試 | `YAML.safe_load_file(spec/fixtures/psp_packs/*.yml)` | **String** |
#
# 而 65 §D.3 的「空表 ≠ 缺鍵」又逼實作必須用 `Hash#key?`——**它對 Symbol/String 不通用**。
#
# 🔴 **不正規化的後果是「整個 §H 測試矩陣證明不了生產路徑」**：
#   - 若實作照 fixture 寫成 String 鍵 ⇒ 第一個真 pack 進 `limits.yml` 時，
#     `pack.key?("amount_format")` 回 false ⇒ **每一個生產 pack 都被判成缺必填鍵、
#     永遠不得 enable**，而錯誤訊息會說「缺 amount_format」——**YAML 裡明明逐字寫著**。
#   - 中間形態最糟：必填鍵用 Symbol、幣別查表用 String ⇒
#     `minor_unit_overrides["JPY"]` 回 nil ⇒ 對 JPY raise「該幣別未宣告」，
#     而 pack 裡逐字寫著 `JPY: 0`。
#
# ⇒ **在這裡收斂一次，並把它做成契約的一部分**。
# `spec/models/psp/registry_spec.rb` 有一條 example **同時**用兩種來源餵同一份 pack，
# 斷言兩者行為完全一致——那是這段註釋的可執行版本。
#
# @see docs/specs/65-money-unit-boundary.md §D.3
class Psp::Registry
  # `psp_packs` 區塊裡**不是 pack** 的鍵。
  #
  # 🔴 `enable_gates_registered` 是「已登記但 pack 本體還沒建」的閘門清單
  # （`limits.yml` 逐字：「先把閘門記著，免得日後有人直接開」），
  # 把它當成一個 pack 會在啟動時就炸掉。
  NON_PACK_KEYS = %i[enable_gates_registered].freeze

  # @param raw [Hash] pack 宣告；鍵可以是 String 或 Symbol（本類別統一）
  def initialize(raw)
    @packs = normalize(raw)
      .except(*NON_PACK_KEYS)
      .to_h { |code, declaration| [ code, Psp::Pack.new(code, declaration) ] }
      .freeze
  end

  # 取一個 pack。
  #
  # @param code [String, Symbol] pack 代碼
  # @return [Psp::Pack]
  # @raise [Psp::PackNotFound] 沒有這個 pack
  # @note 副作用：無。
  def fetch(code)
    @packs.fetch(code.to_s.downcase.to_sym) do
      raise Psp::PackNotFound, "沒有 PSP pack #{code.inspect}（已宣告：#{@packs.keys.inspect}）"
    end
  end

  # @return [Array<Symbol>] 所有 pack 代碼
  # @note 副作用：無。
  def codes
    @packs.keys
  end

  # @return [Array<Psp::Pack>] 已啟用的 pack
  # @note 副作用：無。
  def enabled
    @packs.values.select(&:enabled?)
  end

  private

  # 遞迴把鍵轉成 Symbol。
  #
  # ⚠️ **本方法是泛型的，不知道哪些鍵是幣別** ⇒ 它**不做**大小寫正規化。
  # 幣別鍵的大寫由 `Psp::Pack` 處理——那裡才知道 `minor_unit_overrides` 與
  # `divisibility` 的鍵是幣別而不是別的東西。
  # （寫在這裡當路障：不要因為「順手」而在這個泛型方法裡 upcase，
  #   那會把 `amount_format` 這種鍵也變成 `:AMOUNT_FORMAT`。）
  def normalize(value)
    case value
    when Hash then value.to_h { |key, val| [ key.to_s.to_sym, normalize(val) ] }
    when Array then value.map { |item| normalize(item) }
    else value
    end
  end
end
