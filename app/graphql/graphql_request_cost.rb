# M0 使用的輕量 GraphQL cost estimator 與 response envelope builder。
#
# 目前 schema 只公開 products connection，因此 requested page size 就是主要
# 查詢成本；完整 AST analyzer 與共享 leaky bucket 屬 M8 營運範圍。此類別
# 不持久化 bucket 狀態。見 docs/research/28 §0.4、HANDOFF.md M8。
class GraphqlRequestCost
  DEFAULT_PAGE_SIZE = 50

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
      product_fields = document.scan(/\bproducts\b\s*(?:\(([^)]*)\))?/)
      return GraphqlLimits.fetch(:object_cost) if product_fields.empty?

      product_fields.sum do |arguments|
        GraphqlLimits.fetch(:object_cost) + requested_page_size(arguments.first.to_s, variables)
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
      capacity = GraphqlLimits.fetch(:bucket_capacity)
      {
        "requestedQueryCost" => requested,
        "actualQueryCost" => actual,
        "throttleStatus" => {
          "maximumAvailable" => capacity,
          "currentlyAvailable" => [ capacity - actual, 0 ].max,
          "restoreRate" => GraphqlLimits.fetch(:restore_rate_per_second)
        }
      }
    end

    private

    def requested_page_size(arguments, variables)
      match = arguments.match(/\b(?:first|last)\s*:\s*(\$[A-Za-z_]\w*|\d+)/)
      return DEFAULT_PAGE_SIZE unless match

      token = match[1]
      value = if token.start_with?("$")
        variables[token.delete_prefix("$")] || variables[token.delete_prefix("$").to_sym]
      else
        token
      end
      Integer(value || DEFAULT_PAGE_SIZE)
    rescue ArgumentError, TypeError
      DEFAULT_PAGE_SIZE
    end
  end
end
