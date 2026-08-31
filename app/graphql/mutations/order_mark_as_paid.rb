# frozen_string_literal: true

module Mutations
  # 標記訂單為已付款（G6-6 步 4；對位 Admin API orderMarkAsPaid——28 §4 名冊、
  # 88 號實測「Mark as paid」動作對位）。
  #
  # 語義＝Orders::MarkAsPaid：pending sale 交易翻 success → financial_status paid
  # → orders/paid outbox。已取消／已入帳回 INVALID_STATE（管理員顯式動作不靜默吞，
  # 服務檔頭同記）。idempotencyKey 必帶（limits idempotency.required_for；
  # 本尊 orderMarkAsPaid(idempotencyKey!) 同形）。
  class OrderMarkAsPaid < BaseMutation
    graphql_name "OrderMarkAsPaid"
    description "把待付款訂單標記為已付款（manual 收款確認）。"

    user_errors_type Types::Errors::OrderMarkAsPaidUserErrorType

    argument :id, GraphQL::Types::ID, required: true, description: "訂單 GID。"
    argument :idempotency_key, String, required: false

    field :order, Types::OrderType, null: true, description: "更新後的訂單；失敗時為 null。"

    def resolve(id:, idempotency_key: nil)
      enforce_idempotency_contract!(idempotency_key)
      shop = authorized_shop!

      numeric = id.to_s[%r{\Agid://chilllove/Order/(\d+)\z}, 1]
      if numeric.nil?
        return { order: nil,
                 user_errors: [ { field: [ "id" ], message: "訂單 GID 格式錯誤。", code: "INVALID" } ] }
      end

      result = ActsAsTenant.with_tenant(shop) do
        Orders::MarkAsPaid.call(shop:, order_id: numeric.to_i)
      end
      if result.error
        field, message, code = result.error
        { order: nil, user_errors: [ { field: [ field ], message:, code: } ] }
      else
        { order: result.order, user_errors: [] }
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
