# frozen_string_literal: true

module Types
  module Inputs
    # inventorySetQuantities 的輸入（絕對值＋CAS 模式）。
    class InventorySetQuantitiesInput < GraphQL::Schema::InputObject
      graphql_name "InventorySetQuantitiesInput"

      argument :reason, String, required: true
      argument :name, String, required: true,
        description: "只接受 available 或 on_hand（本尊明文）。"
      argument :reference_document_uri, String, required: false
      argument :changes, [ Types::Inputs::InventorySetQuantityInput ], required: true
    end
  end
end
