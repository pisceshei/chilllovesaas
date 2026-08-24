# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # variant keyset connection 的 edge（cursor 編 (position, id)，第 21 包）。
  class ProductVariantEdgeType < BaseObject
    field :cursor, String, null: false
    field :node, ProductVariantType, null: false
  end
end
