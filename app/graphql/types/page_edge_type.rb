# frozen_string_literal: true

module Types
  # Page 分頁邊（keyset connection；UrlRedirectEdgeType 同構）。
  class PageEdgeType < BaseObject
    graphql_name "PageEdge"
    description "Page 分頁邊。"

    field :cursor, String, null: false
    field :node, PageType, null: false
  end
end
