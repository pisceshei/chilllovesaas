# frozen_string_literal: true

module Mutations
  # 建立退款（G6-8 步 5；對位本尊 refundCreate——官方句「Creates a refund for an
  # order, allowing you to process returns and issue payments back to customers.」，
  # 取證 2026-09-01）。
  #
  # 冪等：官方 2026-04 起 refundCreate 強制 @idempotent（ord-2 §4.1 逐字「the
  # idempotency key is required」）；我方 idempotencyKey 必帶
  # （limits idempotency.required_for 既列 refundCreate）。
  #
  # 🔴 超額退款的權限閘：allowOverRefunding=true 需 `orders.over_refund` 權限
  # （limits.refund.over_refund_requires_permission；16 §F5.1——二次確認在 UI 層）。
  class RefundCreate < BaseMutation
    graphql_name "RefundCreate"
    description "建立退款（軟上限＋restock；預覽用 Order.suggestedRefund）。"

    user_errors_type Types::Errors::RefundCreateUserErrorType

    argument :input, Types::Inputs::RefundCreateInput, required: true
    argument :idempotency_key, String, required: false

    field :refund, Types::RefundType, null: true
    field :order, Types::OrderType, null: true

    def resolve(input:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      shop = authorized_shop!
      staff = context[:current_staff]

      numeric = input[:order_id].to_s[%r{\Agid://chilllove/Order/(\d+)\z}, 1]
      if numeric.nil?
        return { refund: nil, order: nil,
                 user_errors: [ { field: [ "orderId" ], message: "訂單 GID 格式錯誤。", code: "INVALID" } ] }
      end

      if input[:allow_over_refunding] && !staff.can?(Limits.fetch(:refund, :over_refund_requires_permission))
        return { refund: nil, order: nil,
                 user_errors: [ { field: [ "allowOverRefunding" ],
                                  message: "你沒有超額退款的權限。", code: "MISSING_PERMISSION" } ] }
      end

      lines = Array(input[:refund_line_items]).map do |li|
        line_numeric = li[:line_item_id].to_s[%r{\Agid://chilllove/LineItem/(\d+)\z}, 1]
        if line_numeric.nil?
          return { refund: nil, order: nil,
                   user_errors: [ { field: [ "refundLineItems" ],
                                    message: "行項 GID 格式錯誤。", code: "INVALID" } ] }
        end
        unless RefundLineItem::RESTOCK_TYPES.include?(li[:restock_type].to_s)
          return { refund: nil, order: nil,
                   user_errors: [ { field: [ "refundLineItems" ],
                                    message: "restockType 不在允許值域內。", code: "INCLUSION" } ] }
        end

        { line_item_id: line_numeric.to_i, quantity: li[:quantity], restock_type: li[:restock_type] }
      end

      result = ActsAsTenant.with_tenant(shop) do
        Refunds::Create.call(
          shop:, order_id: numeric.to_i, refund_line_items: lines,
          shipping_cents: input[:shipping] && input[:shipping][:amount_cents],
          full_shipping: (input[:shipping] && input[:shipping][:full_refund]) || false,
          note: input[:note], notify_customer: input[:notify],
          idempotency_key: idempotency_key.to_s,
          allow_over_refund: input[:allow_over_refunding], staff: staff
        )
      end
      if result.error
        field, message, code = result.error
        { refund: nil, order: nil, user_errors: [ { field: [ field ], message:, code: } ] }
      else
        order = ActsAsTenant.with_tenant(shop) { Order.find_by(id: numeric.to_i) }
        { refund: result.refund, order:, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && OrderPolicy.new(staff, Order).create?
        raise GraphQL::ExecutionError.new(
          I18n.t("errors.orders.access_denied"),
          extensions: { "code" => "ACCESS_DENIED" }
        )
      end

      context.fetch(:current_shop)
    end
  end
end
