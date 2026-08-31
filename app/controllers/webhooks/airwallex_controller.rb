# frozen_string_literal: true

module Webhooks
  # Airwallex webhook 接收端（G6-1a；URL＝租戶店面網域 /webhooks/airwallex——
  # 使用者已在 Airwallex 後台以此 URL 建立訂閱，2026-08-31）。
  #
  # ①租戶由 host 解析（TenantResolver → Current.shop，同 storefront）。
  # ②🔴 驗簽 fail-closed（digest §H，官方 webhook 文檔）：
  #   expected = HMAC-SHA256(webhook_secret, x-timestamp + raw_body) 的 hex，
  #   與 x-signature 做 secure_compare；缺 header／缺 provider 列／缺 secret／不符
  #   一律 401，**不落任何資料**。
  # ③冪等：event_id UNIQUE；重複投遞回 200（已收＝成功，Airwallex 才不重試）。
  # ④本包只收錄（status=received）；消費＝G6-1b。**不在請求內做任何外部 IO**（鐵律 5）。
  class AirwallexController < ActionController::Base
    skip_forgery_protection
    before_action :require_shop!

    def receive
      raw = request.raw_post
      timestamp = request.headers[Limits.fetch(:psp_integration, :airwallex, :webhook_timestamp_header)].to_s
      signature = request.headers[Limits.fetch(:psp_integration, :airwallex, :webhook_signature_header)].to_s
      return head :unauthorized unless verified?(raw, timestamp, signature)

      event = JSON.parse(raw)
      row = ActsAsTenant.with_tenant(Current.shop) do
        PspWebhookEvent.create!(
          provider: "airwallex",
          event_id: event.fetch("id"),
          event_type: event.fetch("name"),
          payload: event
        )
      end
      # 消費走 job（G6-1c）：只帶 id（憑證不進 job payload——limits）；enqueue 在
      # create 之後、無包裹交易 ⇒ 不違鐵律 5。
      Psp::WebhookProcessJob.perform_later(Current.shop.id, row.id)
      head :ok
    rescue ActiveRecord::RecordNotUnique
      head :ok # 重複投遞＝已收（DB 兜底層）
    rescue ActiveRecord::RecordInvalid => error
      # 模型層 uniqueness 先於 DB 兜底命中重複 ⇒ 同樣是「已收」；其他驗證錯＝形不對。
      error.record.errors.of_kind?(:event_id, :taken) ? head(:ok) : head(:internal_server_error)
    rescue JSON::ParserError, KeyError
      # 簽章合法但形不對＝對方改了 payload 形或訂閱設錯——記 500 讓其重試並可觀測。
      head :internal_server_error
    end

    private

    def require_shop!
      head :not_found unless Current.shop
    end

    # 🔴 secure_compare 防 timing；任何前置缺失都是 false（fail-closed，不是例外）。
    def verified?(raw, timestamp, signature)
      return false if timestamp.blank? || signature.blank?

      secret = ActsAsTenant.with_tenant(Current.shop) do
        ShopPaymentProvider.find_by(provider: "airwallex")&.webhook_secret
      end
      return false if secret.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}#{raw}")
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end
  end
end
