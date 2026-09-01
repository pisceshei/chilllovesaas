# frozen_string_literal: true

module Types
  # Discount connection 的 edge。
  class DiscountEdgeType < BaseObject
    field :cursor, String, null: false
    field :node, DiscountType, null: false
  end
end
