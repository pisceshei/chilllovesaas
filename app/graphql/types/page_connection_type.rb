# frozen_string_literal: true

module Types
  # Page keyset connection（D5 分頁鐵律）。
  class PageConnectionType < BaseObject
    graphql_name "PageConnection"
    description "Page 分頁。"

    field :edges, [ PageEdgeType ], null: false
    field :nodes, [ PageType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
