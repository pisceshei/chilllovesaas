# frozen_string_literal: true

module Types
  # 棄單 keyset connection（orders/customers 同形；28 §0.3）。
  class AbandonedCheckoutConnectionType < BaseObject
    field :nodes, [ AbandonedCheckoutType ], null: false
    field :edges, [ AbandonedCheckoutEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
