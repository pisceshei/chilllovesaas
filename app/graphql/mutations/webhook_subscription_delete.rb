# frozen_string_literal: true

module Mutations
  # webhook 訂閱刪除（步 20a）。投遞紀錄隨列（FK cascade）。
  class WebhookSubscriptionDelete < BaseMutation
    graphql_name "WebhookSubscriptionDelete"
    description "刪除 webhook 訂閱。"

    user_errors_type Types::Errors::WebhookUserErrorType

    argument :id, ID, required: true

    field :deleted_id, ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        row = find_row(id, shop)
        return failure("id", "找不到訂閱。", "NOT_FOUND") if row.nil?

        row.destroy!
        { deleted_id: id, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def find_row(gid, shop)
      numeric = gid.to_s[%r{\Agid://chilllove/WebhookSubscription/(\d+)\z}, 1]
      numeric && WebhookSubscription.find_by(shop_id: shop.id, id: numeric)
    end

    def failure(field, message, code)
      { deleted_id: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
