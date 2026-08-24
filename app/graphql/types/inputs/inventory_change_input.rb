# frozen_string_literal: true

module Types
  module Inputs
    # 單筆差額變更。
    class InventoryChangeInput < GraphQL::Schema::InputObject
      graphql_name "InventoryChangeInput"

      argument :inventory_item_id, ID, required: true
      argument :location_id, ID, required: true
      argument :delta, Integer, required: true
      argument :change_from_quantity, Integer, required: false,
        description: "CAS：與現值不符回 CHANGE_FROM_QUANTITY_STALE；nil＝跳過檢查。"
      argument :ledger_document_uri, String, required: false,
        description: "available 不得帶、其他 name 必帶；禁 gid://shopify/*；同呼叫必須相同。"
    end
  end
end
