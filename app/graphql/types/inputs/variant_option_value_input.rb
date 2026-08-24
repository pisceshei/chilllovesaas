# frozen_string_literal: true

module Types
  module Inputs
    # 變體的選項座標宣告（本尊 variants[].optionValues 的 {optionName, name} 形）。
    class VariantOptionValueInput < GraphQL::Schema::InputObject
      argument :option_name, String, required: true, description: "選項名（須在 options 樹內）。"
      argument :value, String, required: true, description: "選中的值（須在該選項 values 內）。"
    end
  end
end
