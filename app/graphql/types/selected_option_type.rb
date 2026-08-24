# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # 變體的選中選項（本尊 SelectedOption 形：name/value 扁平對）。
  # object＝{ name:, value:, option_value: } 由 ProductVariantType#selected_options 組裝。
  class SelectedOptionType < BaseObject
    field :name, String, null: false, description: "選項名（如「尺寸」）。"
    field :value, String, null: false, description: "選中的值（如「M」）。"
  end
end
