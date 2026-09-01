# frozen_string_literal: true

module Types
  # Article 分頁邊（keyset connection；UrlRedirectEdgeType 同構）。
  class ArticleEdgeType < BaseObject
    graphql_name "ArticleEdge"
    description "Article 分頁邊。"

    field :cursor, String, null: false
    field :node, ArticleType, null: false
  end
end
