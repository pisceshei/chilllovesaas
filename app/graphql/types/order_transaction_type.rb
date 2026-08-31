# frozen_string_literal: true

module Types
  # 金流交易（G6-6a）。不可變事件列——修正一律追加新列以 parentTransaction 串鏈
  # （90-blueprint/05 §A.2），API 面因此只有讀出沒有 update。
  class OrderTransactionType < BaseObject
    graphql_name "OrderTransaction"
    description "訂單的金流交易（append-only）"

    field :id, GraphQL::Types::ID, null: false
    field :kind, OrderTransactionKindEnum, null: false
    field :status, OrderTransactionStatusEnum, null: false
    field :gateway, String, null: false
    field :amount_set, MoneyBagType, null: false
    field :processed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :error_code, String, null: true
    field :provider_reference, String, null: true,
          description: "PSP 側參照（如 payment intent id；對帳用）"
    field :parent_transaction_id, GraphQL::Types::ID, null: true

    def id
      "gid://chilllove/OrderTransaction/#{object.id}"
    end

    def amount_set
      { cents: object.amount_cents, currency: object.currency }
    end

    def parent_transaction_id
      object.parent_transaction_id && "gid://chilllove/OrderTransaction/#{object.parent_transaction_id}"
    end
  end
end
