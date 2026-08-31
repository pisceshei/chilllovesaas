# frozen_string_literal: true

module Types
  module Inputs
    # 運費退款輸入（G6-8；對位本尊 ShippingRefundInput——官方 amount: Money／
    # fullRefund: Boolean，取證 2026-09-01。amount 我方以 cents 承載——鐵律 3
    # 內部全程 integer cents，Decimal 字串只在序列化層）。
    class ShippingRefundInput < GraphQL::Schema::InputObject
      graphql_name "ShippingRefundInput"
      description "運費退款（amountCents 與 fullRefund 二選一）"

      argument :amount_cents, Integer, required: false,
               description: "指定退運費額（integer cents；鐵律 3）"
      argument :full_refund, Boolean, required: false, default_value: false,
               description: "全退剩餘可退運費"
    end
  end
end
