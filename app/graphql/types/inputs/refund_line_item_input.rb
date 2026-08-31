# frozen_string_literal: true

module Types
  module Inputs
    # 退款行項輸入（G6-8；對位本尊 RefundLineItemInput——官方欄 lineItemId!/
    # quantity!/restockType/locationId，取證 2026-09-01。locationId v1 不實作
    # ——單地點形，restock 一律回 priority 最高地點）。
    class RefundLineItemInput < GraphQL::Schema::InputObject
      graphql_name "RefundLineItemInput"
      description "要退款的行項、數量與 restock 決策"

      argument :line_item_id, GraphQL::Types::ID, required: true
      argument :quantity, Integer, required: true
      argument :restock_type, String, required: false, default_value: "no_restock",
               description: "no_restock/cancel/return（官方 enum 去掉 deprecated 的 LEGACY_RESTOCK）"
    end
  end
end
