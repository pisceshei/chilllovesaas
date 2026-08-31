# frozen_string_literal: true

module Types
  module Inputs
    # FO × 行項配對輸入（G6-8；對位本尊 FulfillmentOrderLineItemsInput——官方逐字
    # 「If left blank, all line items of the fulfillment order will be fulfilled.」）。
    class FulfillmentOrderLineItemsInput < GraphQL::Schema::InputObject
      graphql_name "FulfillmentOrderLineItemsInput"
      description "指定某張履約工作單要出貨的行項（缺席＝全部）"

      argument :fulfillment_order_id, GraphQL::Types::ID, required: true
      argument :fulfillment_order_line_items, [ FulfillmentOrderLineItemInput ],
               required: false, description: "缺席＝該工作單全部可出貨行項"
    end
  end
end
