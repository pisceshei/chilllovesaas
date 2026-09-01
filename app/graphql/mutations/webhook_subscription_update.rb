# frozen_string_literal: true

module Mutations
  # webhook 訂閱更新（步 20a）：改 URL 必重驗紅線；re-enable 歸零 failure_count。
  class WebhookSubscriptionUpdate < BaseMutation
    graphql_name "WebhookSubscriptionUpdate"
    description "更新 webhook 訂閱（URL 重驗紅線；重新啟用歸零失敗計數）。"

    user_errors_type Types::Errors::WebhookUserErrorType

    argument :callback_url, String, required: false
    argument :id, ID, required: true
    argument :status, String, required: false

    field :webhook_subscription, Types::WebhookSubscriptionType, null: true

    def resolve(id:, callback_url: nil, status: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        row = find_row(id, shop)
        return failure("id", "找不到訂閱。", "NOT_FOUND") if row.nil?

        if callback_url
          begin
            Webhooks::UrlGuard.vet!(callback_url) # 🔴 改 URL 必重驗（18 F4）
          rescue Webhooks::UrlGuard::GuardError => e
            return failure("callbackUrl", e.message, "URL_NOT_ALLOWED")
          end
          row.url = callback_url
        end
        if status
          return failure("status", "status 只接受 active/disabled。", "INVALID") unless WebhookSubscription::STATUSES.include?(status)

          row.failure_count = 0 if status == "active" && row.status == "disabled" # re-enable 歸零
          row.status = status
        end
        row.save!
        { webhook_subscription: row, user_errors: [] }
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
      { webhook_subscription: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
