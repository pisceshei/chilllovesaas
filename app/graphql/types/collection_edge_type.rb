# frozen_string_literal: true

module Types
  # collections connection 的 edge。
  class CollectionEdgeType < BaseObject
    graphql_name "CollectionEdge"
    description "系列分頁邊。"

    field :cursor, String, null: false
    field :node, Types::CollectionType, null: false
  end
end
