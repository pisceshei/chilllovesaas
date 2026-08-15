# mutation user error 的輔助工具 namespace。
module UserErrors
  # 組出 `userErrors.field` 的路徑陣列。
  #
  # 規則**逐條照抄本尊**（Admin API 2026-07 逐頁考掘，見 `docs/research/28` §0.3.1）：
  #
  # 1. **`input:` 這層外殼要剝掉**。`productDelete(input: ProductDeleteInput!)` 的
  #    id 住在 `input.id`，而官方錯誤範例回的是 `["id"]` 而**不是** `["input","id"]`。
  # 2. **其他具名參數會進 path**。`productVariantsBulkCreate(productId:, variants:)`
  #    的錯誤回 `["productId"]`、`["variants","0","optionValues","0"]`。
  # 3. **陣列索引是十進位裸字串段**，與其他段平鋪在同一個一維陣列；
  #    不用括號、不用 JSONPath、不用 `$` 前綴。path 也允許終止於索引段。
  # 4. **欄位名用 camelCase**（GraphQL 慣例；Ruby 端的 `lock_version` → `lockVersion`）。
  # 5. **無法歸屬到任何欄位時回 `nil`**（不是 `[]`）——官方 `draftOrderComplete`
  #    的錯誤範例逐字 `"field": null`，全站查不到任何 `"field": []`。
  #
  # 🔴 **不得**與 Checkout Validation Function 的 `target: "$.cart.deliveryGroups[0]..."`
  # 混用——那是另一個介面的另一套語法。
  #
  # ⚠️ **一條假設**：規則 1 的「剝殼」到底只針對名為 `input` 的參數，還是針對所有
  # 「單一資料本體參數」，**沒有官方範例可證**（官方只有單段 `["productId"]`、
  # 剝殼後的 `["id"]`、以及 `["variants","0",...]`）。我方採**只剝 `input`**
  # ——三個官方實例都相容。補證方式見 `docs/research/28` §0.3.6。
  #
  # @see docs/research/28-api-contract.md §0.3.1、§0.3.6
  # @see docs/DECISIONS.md D14
  module Path
    # 名為這個的根參數不進 path（本尊會剝掉這層外殼）。
    STRIPPED_ROOT = "input"

    # 路徑段不得出現的字元——出現代表有人混進了 JSONPath 風格的寫法。
    FORBIDDEN = /[\[\]$.]/

    class << self
      # 組一條欄位路徑。
      #
      # @param segments [Array<Symbol, String, Integer>] 由 mutation 參數根開始的各段；
      #   `Integer` 視為陣列索引，會轉成十進位裸字串
      # @return [Array<String>, nil] camelCase 的路徑陣列；沒有任何段時為 `nil`
      # @raise [ArgumentError] 任一段含 `[`、`]`、`$`、`.`，或為空字串
      # @note 副作用：無。
      # @see docs/research/28-api-contract.md §0.3.1
      def build(*segments)
        parts = segments.flatten.compact
        # 🔴 只剝**第一段**且只在它逐字等於 "input" 時剝。
        # 巢狀的 `input` 欄位名（例如某個 input object 真的有個欄位叫 input）不受影響。
        parts = parts.drop(1) if parts.first.to_s == STRIPPED_ROOT
        return nil if parts.empty?

        parts.map { |segment| normalize(segment) }
      end

      private

      def normalize(segment)
        return segment.to_s if segment.is_a?(Integer)

        token = segment.to_s
        raise ArgumentError, "路徑段不得為空" if token.empty?
        if token.match?(FORBIDDEN)
          raise ArgumentError,
            "路徑段 #{token.inspect} 含 [ ] $ . —— 這是 JSONPath 風格，" \
            "本尊的 userErrors.field 是平鋪的一維陣列（28 §0.3.1）"
        end

        camelize(token)
      end

      # `lock_version` → `lockVersion`。
      #
      # 🔴 **判準是「有沒有底線」，不是大小寫**（2026-08-15 修；原文寫成
      # 「已經是 camelCase 或全大寫的原樣保留」）。實際行為：
      # `"lockVersion"` 無底線 ⇒ 原樣（碰巧與原文相符）；
      # 但 `"FOO_BAR"` **有**底線 ⇒ 會被轉成 `"FOOBar"`，**不是原樣保留**。
      # ⚠️ 差別在「全大寫帶底線」這一類 token 上會現形——把判準寫成大小寫，
      # 讀的人會以為丟一個 SCREAMING_CASE 進來是安全的。
      def camelize(token)
        return token unless token.include?("_")

        head, *rest = token.split("_")
        head + rest.map(&:capitalize).join
      end
    end
  end
end
