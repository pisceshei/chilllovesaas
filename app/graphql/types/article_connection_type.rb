# frozen_string_literal: true

module Types
  # Article keyset connection（D5 分頁鐵律）。
  class ArticleConnectionType < BaseObject
    graphql_name "ArticleConnection"
    description "Article 分頁。"

    field :edges, [ ArticleEdgeType ], null: false
    field :nodes, [ ArticleType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
