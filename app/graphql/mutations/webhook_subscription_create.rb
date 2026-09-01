# frozen_string_literal: true

module Mutations
  # webhook 訂閱建立（步 20a；28 §15 契約）。
  # ①🔴 topic 白名單＝Events::Topics::EXTERNAL（內部 topic 永不可訂閱）。
  # ②🔴 URL 紅線＝Webhooks::UrlGuard（HTTPS＋SSRF resolve 層；specs/18 F4）。
  # ③secret 伺服端生成、**只在本回應一次性回傳**（讀面不再露出）。
  class WebhookSubscriptionCreate < BaseMutation
    graphql_name "WebhookSubscriptionCreate"
    description "建立 webhook 訂閱（topic 白名單＋URL SSRF 紅線；secret 一次性回傳）。"

    user_errors_type Types::Errors::WebhookUserErrorType

    argument :callback_url, String, required: true
    argument :topic, String, required: true

    field :secret, String, null: true, description: "簽章密鑰——僅本回應一次性可見。"
    field :webhook_subscription, Types::WebhookSubscriptionType, null: true

    def resolve(topic:, callback_url:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      ActsAsTenant.with_tenant(shop) do
        unless Events::Topics::EXTERNAL.include?(topic)
          return failure("topic", "topic 不可訂閱（內部 topic 或未知值）。", "TOPIC_NOT_SUBSCRIBABLE")
        end
        if WebhookSubscription.where(shop_id: shop.id).count >= Limits.fetch(:webhook, :max_subscriptions_per_shop)
          return failure("base", "訂閱數已達上限。", "LIMIT_REACHED")
        end


        begin
          Webhooks::UrlGuard.vet!(callback_url)
        rescue Webhooks::UrlGuard::GuardError => e
          return failure("callbackUrl", e.message, "URL_NOT_ALLOWED")
        end

        row = WebhookSubscription.create!(shop_id: shop.id, topic:, url: callback_url,
                                          secret: SecureRandom.hex(24))
        { webhook_subscription: row, secret: row.secret, user_errors: [] }
      end
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def failure(field, message, code)
      { webhook_subscription: nil, secret: nil,
        user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
