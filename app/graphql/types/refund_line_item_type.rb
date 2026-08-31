# frozen_string_literal: true

module Types
  # 退款行項（G6-8；對位本尊 RefundLineItem）。
  class RefundLineItemType < BaseObject
    graphql_name "RefundLineItem"
    description "退款包含的行項、數量與 restock 決策"

    field :line_item, LineItemType, null: false
    field :quantity, Integer, null: false
    field :restock_type, String, null: false, description: "no_restock/cancel/return"
    field :subtotal_set, MoneyBagType, null: false
    field :total_tax_set, MoneyBagType, null: false

    def subtotal_set
      { cents: object.subtotal_cents, currency: object.currency }
    end

    def total_tax_set
      { cents: object.tax_cents, currency: object.currency }
    end
  end
end
