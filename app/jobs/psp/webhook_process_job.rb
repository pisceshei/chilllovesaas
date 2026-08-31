# frozen_string_literal: true

module Psp
  # webhook 收件匣消費（G6-1c；G6-1a 只收錄、本 job 補上消費半邊）。
  #
  # ①只處理 `payment_intent.succeeded`；其他事件標 processed（收錄已完成其用途）。
  # ②🔴 金額**不信 webhook payload**（json 欄回讀是 Float——X8c 禁）：以 intent GET
  #   權威重取（client 已 decimal_class: BigDecimal），`Money.from_psp_amount` 入向
  #   後交 `Orders::FinalizePspPayment`（雙路徑冪等；金額不符＝failed＋P1 事件）。
  # ③job payload 只帶 id（limits `psp_credentials.job_payload_forbidden_keys`）。
  # ④無全域 retry_on（application_job 現況）：失敗標 failed 留人工／後續重掃——
  #   fail-visible 而不是無限重試打 PSP。
  class WebhookProcessJob < ApplicationJob
    queue_as :default

    # @param shop_id [Integer]
    # @param webhook_event_id [Integer] psp_webhook_events 主鍵
    def perform(shop_id, webhook_event_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      event = ActsAsTenant.with_tenant(shop) { PspWebhookEvent.find_by(id: webhook_event_id) }
      return if event.nil? || event.status != "received"

      unless event.event_type == "payment_intent.succeeded"
        return ActsAsTenant.with_tenant(shop) { event.update!(status: "processed", processed_at: Time.current) }
      end

      intent_id = event.payload.dig("data", "object", "id")
      provider_row = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.find_by(provider: event.provider) }
      if intent_id.blank? || provider_row.nil?
        return ActsAsTenant.with_tenant(shop) { event.update!(status: "failed", processed_at: Time.current) }
      end

      intent = Airwallex::PaymentIntents.new(provider_row).get(intent_id)
      token = intent["merchant_order_id"].to_s
      amount_storage = Money.from_psp_amount(intent.fetch("amount"),
                                             currency: intent.fetch("currency"), psp: event.provider)

      result = Orders::FinalizePspPayment.call(
        shop:, checkout_token: token, provider: event.provider,
        psp_reference: intent_id, amount_storage:
      )
      ActsAsTenant.with_tenant(shop) do
        event.update!(status: result.status == :paid ? "processed" : "failed",
                      processed_at: Time.current)
      end
    rescue Orders::FinalizePspPayment::AmountMismatch => error
      Money.instrument_failure(direction: :inbound, psp: event.provider, currency: "?", error:)
      ActsAsTenant.with_tenant(shop) { event.update!(status: "failed", processed_at: Time.current) }
    end
  end
end
