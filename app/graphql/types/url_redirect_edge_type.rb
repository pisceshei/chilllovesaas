# frozen_string_literal: true

module Types
  # 重導分頁邊（keyset connection；與 CollectionEdgeType 同構）。
  class UrlRedirectEdgeType < BaseObject
    graphql_name "UrlRedirectEdge"
    description "重導分頁邊。"

    field :cursor, String, null: false
    field :node, UrlRedirectType, null: false
  end
end
