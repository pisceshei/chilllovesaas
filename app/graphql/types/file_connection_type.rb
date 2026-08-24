# frozen_string_literal: true

module Types
  # files 的 keyset connection（與 ProductConnectionType 同構，D5 分頁鐵律）。
  class FileConnectionType < BaseObject
    graphql_name "FileConnection"
    description "檔案庫分頁。"

    field :edges, [ Types::FileEdgeType ], null: false
    field :nodes, [ Types::FileType ], null: false
    field :page_info, Types::PageInfoType, null: false
  end
end
