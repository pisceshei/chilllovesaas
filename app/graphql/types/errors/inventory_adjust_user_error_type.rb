# frozen_string_literal: true

module Types
  module Errors
    # 庫存 mutation 的業務錯誤。
    class InventoryAdjustUserErrorType < Types::BaseObject
      graphql_name "InventoryAdjustUserError"
      description "inventoryAdjustQuantities／inventorySetQuantities 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, InventoryAdjustUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
