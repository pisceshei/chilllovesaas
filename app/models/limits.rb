# `config/limits.yml` 的通用讀取入口（鐵律 6：上限值一律引用，不得硬編碼）。
#
# 與 `GraphqlLimits` 的分工：後者只讀 `api:` 區塊、只回 Integer，是 GraphQL 專用的
# 窄入口；本類別讀**任意區塊、任意型別**（陣列、布林、字串、null），供 model 與
# service 使用。刻意不把 `GraphqlLimits` 併進來——它的 `Integer(value)` 強制轉型是
# 那一層要的防呆（cost point 不是整數就是設定寫錯），本類別若沿用會讓
# `status_values` 這種陣列取不出來。
#
# 🔴 **鍵一律用 Symbol**：`config/application.rb:48-50` 以 `deep_symbolize_keys` 載入
# `limits.yml`，所以 `Rails.configuration.x.limits` 的鍵全是 Symbol。傳 String 會
# 靜默拿到 nil——而 `nil` 在很多判斷裡讀起來跟「宣告為 false／空」一樣
# （2026-08-15 實例：`limits.dig("product", "sku_unique_per_shop")` 猜錯區塊拿到 nil，
#  而 nil 與 false 在「不是唯一」這件事上看起來一樣）。⇒ 本類別**缺鍵一律 raise**。
#
# @see CLAUDE.md 鐵律 6
# @see config/limits.yml
class Limits
  class << self
    # 依路徑取出一個上限值。
    #
    # @param path [Array<Symbol>] 由頂層區塊開始的鍵路徑，例如 `:product, :status_values`
    # @return [Object] 設定值（可能是 Array／Hash／String／Integer／Boolean）
    # @raise [KeyError] 路徑上任一層缺鍵時拋出，訊息帶完整路徑
    # @note 副作用：無；只讀取已載入的 Rails configuration。
    # @see CLAUDE.md 鐵律 6
    def fetch(*path)
      path.reduce(Rails.configuration.x.limits) do |node, key|
        unless node.is_a?(Hash) && node.key?(key)
          raise KeyError, "缺少 limits.#{path.join('.')} 設定（斷在 #{key}）"
        end

        node[key]
      end
    end

    # 取出一組 enum 值並正規化成大寫字串陣列。
    #
    # 為什麼要這一支：`limits.yml` 的 `status_values: [ACTIVE, DRAFT, ...]` 在 YAML 裡
    # 是**裸字**，載入後是 String；但同一份清單在別處（例如 `purchasable_statuses`）
    # 若有人寫成引號字串或小寫，就會出現「兩份清單看起來一樣、比對卻不相等」。
    # 統一在入口正規化，比在每個呼叫端各自 `.map(&:to_s)` 可靠。
    #
    # @param path [Array<Symbol>] 鍵路徑
    # @return [Array<String>] 大寫字串陣列
    # @raise [KeyError] 路徑缺鍵
    # @raise [TypeError] 該鍵不是陣列
    # @note 副作用：無。
    def enum(*path)
      value = fetch(*path)
      raise TypeError, "limits.#{path.join('.')} 不是陣列（實得 #{value.class}）" unless value.is_a?(Array)

      value.map { |item| item.to_s.upcase }
    end
  end
end
