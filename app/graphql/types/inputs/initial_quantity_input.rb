# frozen_string_literal: true

module Types
  module Inputs
    # 建立態變體的初始可售量（create-only：帶 id 的變體給它一律 INVALID；
    # limits.catalog_flow.initial_quantity_allowed_on_create_only）。
    # 🔴 寫入走 Inventory::Adjust（D43 唯一入口、無豁免口）——不是本 input 直寫。
    class InitialQuantityInput < GraphQL::Schema::InputObject
      argument :location_id, ID, required: true, description: "GID：gid://chilllove/Location/{id}"
      argument :quantity, Integer, required: true, description: "初始 available（≥0）。"
    end
  end
end
