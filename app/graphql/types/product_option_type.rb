# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # 商品選項（第 21 包讀取面）。上限走 limits.product.max_options（鐵律 6），
  # 讀取面不驗——寫入面（第 22 包 productSet options 樹）才驗。
  class ProductOptionType < BaseObject
    field :id, ID, null: false, description: "GID：gid://chilllove/ProductOption/{id}"
    field :name, String, null: false
    field :position, Integer, null: false
    field :values, [ OptionValueType ], null: false, description: "選項值（position 序）。"

    def id = "gid://chilllove/ProductOption/#{object.id}"

    # @return [Array<OptionValue>] position 序（resolver 端已 preload，不再查）
    def values
      object.option_values.sort_by(&:position)
    end
  end
end
