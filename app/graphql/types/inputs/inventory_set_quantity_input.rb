# frozen_string_literal: true

module Types
  module Inputs
    # 單筆絕對值設定。
    class InventorySetQuantityInput < GraphQL::Schema::InputObject
      graphql_name "InventorySetQuantityInput"

      argument :inventory_item_id, ID, required: true
      argument :location_id, ID, required: true
      argument :quantity, Integer, required: true
      argument :compare_quantity, Integer, required: false,
        description: "CAS：與現值不符回 COMPARE_QUANTITY_STALE。"
      argument :ignore_compare_quantity, Boolean, required: false,
        description: "顯式跳過 CAS（併發下有覆蓋風險，本尊原文警告）。與 compareQuantity 二選一必填。"
      argument :ledger_document_uri, String, required: false
    end
  end
end
