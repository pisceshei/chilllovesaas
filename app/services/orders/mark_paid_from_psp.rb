# frozen_string_literal: true

module Orders
  # PSP 付款成功 → 訂單入帳（G6-1c；16 §F4.4 的 markAsPaid 對位＋F5 步 2 補發）。
  #
  # ①單一 transaction：pending sale 交易翻 success＋記 provider_reference →
  #   order.financial_status → paid → timeline event → 🔴 outbox **orders/paid**
  #   （F5 manual 形刻意不發的那一發，在這裡補）。
  # ②冪等：已 paid ⇒ no-op（webhook 與輪詢雙路徑先到先贏；後到者看到 paid 直接回）。
  # ③🔴 金額不在此驗——驗在 `FinalizePspPayment`（成單前；65 §E 比對一律化到 R1）。
  module MarkPaidFromPsp
    module_function

    # @param order [Order]
    # @param provider [String] pack 代碼（寫進 gateway 的實際承作方）
    # @param provider_reference [String] PSP 側引用（Airwallex intent id）
    # @return [Order]
    def call(order:, provider:, provider_reference:)
      ActiveRecord::Base.transaction do
        order.lock!
        next order if order.financial_status == "paid" # 冪等：雙路徑後到者

        transaction = order.order_transactions.where(kind: "sale", status: "pending").first
        if transaction
          transaction.update!(status: "success", gateway: provider, provider_reference:)
        else
          order.order_transactions.create!(
            shop_id: order.shop_id, kind: "sale", status: "success", gateway: provider,
            amount_cents: order.total_cents, currency: order.currency,
            provider_reference:, idempotency_key: "sale-paid-#{provider_reference}"
          )
        end

        order.update!(financial_status: "paid")
        Event.create!(shop_id: order.shop_id, order_id: order.id, kind: "order.paid",
                      happened_at: Time.current,
                      metadata: { "provider" => provider, "provider_reference" => provider_reference })
        EventOutbox.create!(
          event_id: SecureRandom.uuid,
          topic: Events::Topics::ORDERS_PAID,
          aggregate_type: "Order", aggregate_id: order.id,
          payload: { order_id: order.id, order_number: order.order_number,
                     total_cents: order.total_cents, currency: order.currency,
                     provider:, provider_reference: },
          available_at: Time.current, status: "pending"
        )
        order
      end
    end
  end
end
