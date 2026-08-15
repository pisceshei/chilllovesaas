# M0 使用的輕量 GraphQL cost estimator 與 response envelope builder。
#
# 目前 schema 只公開 products connection，因此 requested page size 就是主要
# 查詢成本；完整 AST analyzer 與共享 leaky bucket 屬 M8 營運範圍。此類別
# 不持久化 bucket 狀態。見 docs/research/28 §0.4、HANDOFF.md M8。
class GraphqlRequestCost
  class << self
    # 從 GraphQL document 與 variables 計算 requested cost。
    #
    # @param query [String] GraphQL source text
    # @param variables [Hash] 已正規化的 variable 值
    # @return [Integer] request 預扣的 query points
    # @note 副作用：無；只解析輸入字串並讀取 limits 設定。
    # @see docs/research/28-api-contract.md §0.4
    def calculate(query:, variables:)
      document = query.to_s
      base = mutation?(document) ? GraphqlLimits.fetch(:mutation_base_cost_points) : 0
      product_fields = document.scan(/\bproducts\b\s*(?:\(([^)]*)\))?/)
      return base + GraphqlLimits.fetch(:object_cost_points) if product_fields.empty?

      base + product_fields.sum do |arguments|
        GraphqlLimits.fetch(:object_cost_points) + requested_page_size(arguments.first.to_s, variables)
      end
    end

    # 建立必要的 `extensions.cost` payload。
    #
    # @param requested [Integer] request 預扣點數
    # @param actual [Integer] 執行後實際消耗點數
    # @return [Hash] camelCase GraphQL cost envelope
    # @note 副作用：無；只讀取 bucket 設定並組合回傳值。
    # @see docs/research/28-api-contract.md §0.4
    def envelope(requested:, actual: requested)
      capacity = GraphqlLimits.fetch(:cost_bucket_capacity)
      {
        "requestedQueryCost" => requested,
        "actualQueryCost" => actual,
        "throttleStatus" => {
          "maximumAvailable" => capacity,
          "currentlyAvailable" => [ capacity - actual, 0 ].max,
          "restoreRate" => GraphqlLimits.fetch(:cost_restore_points_per_sec)
        }
      }
    end

    private

    # document 是不是 mutation。
    #
    # ⚠️ **這是刻意的低精度實作，限度寫在這裡以免被當成完整解**：
    # 它掃的是「有沒有一個 `mutation` 關鍵字出現在 operation 位置」，
    # 因此在 ①一份 document 含多個 operation（只有部分是 mutation）
    # ②`mutation` 出現在註釋或字串裡 ③fragment 內
    # 這三種情形下會**高估或低估**。
    # 精確做法是解析 AST 取 `operation_name` 對應的 operation type——
    # 那要等 M8 的完整 cost analyzer（本檔檔頭已登記）。
    # 🔴 現階段的取捨方向是**寧可高估**（多扣點數比放行超額請求安全），
    # 所以用「出現即算」而不是「只算第一個」。
    def mutation?(document)
      document.match?(/(\A|[}\s])mutation\b/)
    end

    # 未指定 first/last 時的預設頁大小；一律讀 limits.yml（鐵律 6，
    # 原骨架硬編碼 50 於 2026-08-13 移植時外移，與 KeysetConnection 同源）。
    #
    # @return [Integer]
    def default_page_size
      GraphqlLimits.fetch(:pagination_default_page_size)
    end

    def requested_page_size(arguments, variables)
      match = arguments.match(/\b(?:first|last)\s*:\s*(\$[A-Za-z_]\w*|\d+)/)
      return default_page_size unless match

      token = match[1]
      value = if token.start_with?("$")
        variables[token.delete_prefix("$")] || variables[token.delete_prefix("$").to_sym]
      else
        token
      end
      Integer(value || default_page_size)
    rescue ArgumentError, TypeError
      default_page_size
    end
  end
end
