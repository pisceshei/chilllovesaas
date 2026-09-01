# frozen_string_literal: true

module Types
  # AbandonedCheckout connection 的 edge。
  class AbandonedCheckoutEdgeType < BaseObject
    field :cursor, String, null: false
    field :node, AbandonedCheckoutType, null: false
  end
end
