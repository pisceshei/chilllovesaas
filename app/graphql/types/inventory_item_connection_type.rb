# frozen_string_literal: true

module Types
  # 庫存品項的 keyset connection。
  class InventoryItemConnectionType < BaseObject
    graphql_name "InventoryItemConnection"
    description "庫存品項分頁。"

    field :edges, [ Types::InventoryItemEdgeType ], null: false
    field :nodes, [ Types::InventoryItemType ], null: false
    field :page_info, Types::PageInfoType, null: false
  end
end
