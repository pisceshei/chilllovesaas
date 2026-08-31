# frozen_string_literal: true

module Types
  # 退款（G6-8；對位本尊 Refund——ord-4 §8 官方句「The Refund object represents a
  # financial record of money returned to a customer from an order.」）。
  class RefundType < BaseObject
    graphql_name "Refund"
    description "訂單的一筆退款紀錄"

    field :id, GraphQL::Types::ID, null: false
    field :legacy_resource_id, ID, null: false, method: :id
    field :status, String, null: false, description: "pending/success/failure（金流終態）"
    field :note, String, null: true, method: :reason
    field :total_refunded_set, MoneyBagType, null: false
    field :refund_line_items, [ RefundLineItemType ], null: false
    field :processed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def id
      "gid://chilllove/Refund/#{object.id}"
    end

    def total_refunded_set
      { cents: object.total_cents, currency: object.currency }
    end

    def refund_line_items
      object.refund_line_items.order(:id)
    end
  end
end
