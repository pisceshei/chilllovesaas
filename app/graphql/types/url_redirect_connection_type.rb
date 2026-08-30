# frozen_string_literal: true

module Types
  # 重導 keyset connection（D5 分頁鐵律；與 CollectionConnectionType 同構）。
  class UrlRedirectConnectionType < BaseObject
    graphql_name "UrlRedirectConnection"
    description "重導分頁。"

    field :edges, [ UrlRedirectEdgeType ], null: false
    field :nodes, [ UrlRedirectType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
