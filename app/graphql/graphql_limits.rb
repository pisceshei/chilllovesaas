# 集中讀取 `config/limits.yml` 內 GraphQL 上限的服務類別。
#
# 所有 API 上限都從單一設定來源取得，避免 resolver 出現不同常數。讀取
# 不會修改設定或資料庫。見 AGENTS.md 技術鐵律 2、docs/research/28 §0.4。
class GraphqlLimits
  class << self
    # 取得一個必要的整數 GraphQL 上限。
    #
    # @param key [Symbol, String] `api.graphql` 下的 key
    # @return [Integer] 設定的上限值
    # @raise [KeyError, TypeError] 設定缺少或不是整數時拋出
    # @note 副作用：無；只讀取 Rails configuration。
    # @see docs/research/28-api-contract.md §0.4
    def fetch(key)
      limits = Rails.configuration.x.limits
      api = limits[:api] || limits["api"]
      graphql = api && (api[:graphql] || api["graphql"])
      value = graphql && (graphql[key.to_sym] || graphql[key.to_s])
      raise KeyError, "缺少 api.graphql.#{key} 設定" if value.nil?

      Integer(value)
    end
  end
end
