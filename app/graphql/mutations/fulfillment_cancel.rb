# frozen_string_literal: true

module Mutations
  # 取消出貨（G6-8 步 5；對位本尊 fulfillmentCancel——官方句「Cancels an existing
  # Fulfillment and reverses its effects on associated FulfillmentOrder objects.」，
  # 取證 2026-09-01。v1 單 FO 對映見 Fulfillments::Cancel 檔頭）。
  class FulfillmentCancel < BaseMutation
    graphql_name "FulfillmentCancel"
    description "取消一筆出貨（品項回到可出貨狀態、庫存承諾回加）。"

    user_errors_type Types::Errors::FulfillmentCancelUserErrorType

    argument :id, GraphQL::Types::ID, required: true, description: "出貨 GID。"

    field :fulfillment, Types::FulfillmentType, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      numeric = id.to_s[%r{\Agid://chilllove/Fulfillment/(\d+)\z}, 1]
      if numeric.nil?
        return { fulfillment: nil,
                 user_errors: [ { field: [ "id" ], message: "出貨 GID 格式錯誤。", code: "INVALID" } ] }
      end

      result = ActsAsTenant.with_tenant(shop) do
        Fulfillments::Cancel.call(shop:, fulfillment_id: numeric.to_i)
      end
      if result.error
        field, message, code = result.error
        { fulfillment: nil, user_errors: [ { field: [ field ], message:, code: } ] }
      else
        { fulfillment: result.fulfillment, user_errors: [] }
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
