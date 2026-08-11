# GraphQL schema type 的 namespace。
module Types
  # tenant products 的 bounded、offset-free connection type。
  #
  # 最大 page size 由 `config/limits.yml` 控制，materialization 交給
  # Products::KeysetConnection。見 docs/research/28 §0.3。
  class ProductConnectionType < BaseObject
    field :nodes, [ ProductType ], null: false
    field :edges, [ ProductEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
