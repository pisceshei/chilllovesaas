# frozen_string_literal: true

module Types
  # 庫存品項的 keyset edge（與 Product／Collection 同構，D5 分頁鐵律）。
  class InventoryItemEdgeType < BaseObject
    graphql_name "InventoryItemEdge"
    description "庫存品項 edge。"

    field :cursor, String, null: false
    field :node, Types::InventoryItemType, null: false
  end
end
