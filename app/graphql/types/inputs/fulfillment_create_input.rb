# frozen_string_literal: true

module Types
  module Inputs
    # 出貨輸入（G6-8；對位本尊 FulfillmentInput——官方欄
    # lineItemsByFulfillmentOrder!/notifyCustomer/originAddress/trackingInfo，
    # 取證 2026-09-01。originAddress v1 不實作——單地點形無來源地址語義，登記）。
    class FulfillmentCreateInput < GraphQL::Schema::InputObject
      graphql_name "FulfillmentInput"
      description "建立出貨的輸入"

      argument :line_items_by_fulfillment_order, [ FulfillmentOrderLineItemsInput ],
               required: true,
               description: "FO × 行項配對（v1 恰一組——每單一張工作單）"
      argument :notify_customer, Boolean, required: false, default_value: false,
               description: "是否通知顧客（官方 Default: false）"
      argument :tracking_info, FulfillmentTrackingInput, required: false
    end
  end
end
