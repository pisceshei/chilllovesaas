# frozen_string_literal: true

module Types
  # 折扣 keyset connection（orders/customers 同形）。
  class DiscountConnectionType < BaseObject
    field :nodes, [ DiscountType ], null: false
    field :edges, [ DiscountEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
