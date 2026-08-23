# frozen_string_literal: true

module Types
  # collections 的 keyset connection（與 ProductConnectionType 同構，D5 分頁鐵律）。
  class CollectionConnectionType < BaseObject
    graphql_name "CollectionConnection"
    description "商品系列分頁。"

    field :edges, [ Types::CollectionEdgeType ], null: false
    field :nodes, [ Types::CollectionType ], null: false
    field :page_info, Types::PageInfoType, null: false
  end
end
