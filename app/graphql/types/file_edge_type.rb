# frozen_string_literal: true

module Types
  # files connection 的 edge。
  class FileEdgeType < BaseObject
    graphql_name "FileEdge"
    description "檔案分頁邊。"

    field :cursor, String, null: false
    field :node, Types::FileType, null: false
  end
end
