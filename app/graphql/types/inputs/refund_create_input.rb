# frozen_string_literal: true

module Types
  module Inputs
    # 退款輸入（G6-8；對位本尊 RefundInput 的 v1 子集——官方 12 欄中落 orderId!/
    # note/notify/refundLineItems/shipping/allowOverRefunding；currency/duties/
    # refundMethods/transactions/processedAt/discrepancyReason v1 無資料來源不落，
    # dev doc 逐欄登記。取證 2026-09-01）。
    class RefundCreateInput < GraphQL::Schema::InputObject
      graphql_name "RefundInput"
      description "建立退款的輸入"

      argument :order_id, GraphQL::Types::ID, required: true
      argument :note, String, required: false, description: "退款原因（僅 staff 可見）"
      argument :notify, Boolean, required: false, default_value: true,
               description: "是否通知顧客"
      argument :refund_line_items, [ RefundLineItemInput ], required: false
      argument :shipping, ShippingRefundInput, required: false
      argument :allow_over_refunding, Boolean, required: false, default_value: false,
               description: "允許超額退款（官方 Default: false；需 orders.over_refund 權限）"
    end
  end
end
