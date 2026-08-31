# frozen_string_literal: true

module Types
  module Inputs
    # 出貨行項輸入（G6-8；對位本尊 FulfillmentOrderLineItemInput——官方 id: ID!／
    # quantity: Int!，取證 2026-09-01）。
    # 🔴 我方 v1 無 FulfillmentOrderLineItem 子表 ⇒ id 收 **LineItem GID**
    #（ours 對映：v1 FO 行＝訂單行 1:1；dev doc 登記）。
    class FulfillmentOrderLineItemInput < GraphQL::Schema::InputObject
      graphql_name "FulfillmentOrderLineItemInput"
      description "要出貨的行項與數量（id＝LineItem GID——v1 對映，見 dev doc）"

      argument :id, GraphQL::Types::ID, required: true
      argument :quantity, Integer, required: true
    end
  end
end
