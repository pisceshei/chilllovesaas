# 集中讀取 `config/limits.yml` 內 GraphQL 上限的服務類別。
#
# 所有 API 上限都從單一設定來源取得，避免 resolver 出現不同常數。讀取
# 不會修改設定或資料庫。見 CLAUDE.md 鐵律 6、docs/research/28 §0.4。
#
# 鍵名一律用 limits.yml `api:` 區塊的正典名（2026-08-13 骨架移植裁定：
# 以 main 的 limits.yml 為正典；原骨架的 `api.graphql.*` 別名層已廢棄——
# 同一上限兩個鍵名＝鐵律 7 要防的漂移形態）：
#   pagination_max_page_size / pagination_default_page_size /
#   array_input_max_items / max_query_cost_points / object_cost_points /
#   cost_bucket_capacity / cost_restore_points_per_sec
class GraphqlLimits
  class << self
    # 取得一個必要的整數 API 上限。
    #
    # @param key [Symbol, String] `api` 區塊下的正典鍵名
    # @return [Integer] 設定的上限值
    # @raise [KeyError, TypeError] 設定缺少或不是整數時拋出
    # @note 副作用：無；只讀取 Rails configuration。
    # @see docs/research/28-api-contract.md §0.4
    def fetch(key)
      limits = Rails.configuration.x.limits
      api = limits[:api] || limits["api"]
      value = api && (api[key.to_sym] || api[key.to_s])
      raise KeyError, "缺少 api.#{key} 設定" if value.nil?

      Integer(value)
    end
  end
end
