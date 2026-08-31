# frozen_string_literal: true

module Refunds
  # PSP 退款的出帳半邊（G6-8 步 5）。
  #
  # ①分工：`Refunds::Create` 在交易內落 refund＋refund 交易列（皆 pending）；
  #   本 job 在**交易外**打 Airwallex `/api/v1/pa/refunds/create`（鐵律 5：
  #   transaction 內禁外部 IO）並依回應翻終態。
  # ②冪等：refund 已終結（success/failure）直接 return——`Refunds::Create` 的
  #   冪等重放路徑會重複 enqueue，本檢查是那條路的收口；Airwallex 側另有
  #   request_id（＝我方 refund 冪等鍵）雙保險。
  # ③失敗語義（同 WebhookProcessJob 紀律）：無全域 retry_on——API 錯誤標 failure
  #   留 last_error 人工可見，不無限重試打 PSP；**不回滾**已寫的退款業務列
  #  （軟上限累計已佔用；業務決議與金流結果分離——refund.status 承載金流終態）。
  # ④status 對映（ord-4 §9 官方 4 值）：RECEIVED＝受理中維持 pending（等 webhook／
  #   後續輪詢——v1 無退款 webhook 消費者，登記）；ACCEPTED/SETTLED → success；
  #   FAILED → failure。
  class ProcessPspRefundJob < ApplicationJob
    queue_as :default

    # @param shop_id [Integer]
    # @param refund_id [Integer]
    def perform(shop_id, refund_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      refund = ActsAsTenant.with_tenant(shop) { Refund.find_by(id: refund_id) }
      return if refund.nil? || refund.status != "pending"

      transaction = ActsAsTenant.with_tenant(shop) do
        OrderTransaction.find_by(id: refund.order_transaction_id)
      end
      intent_id = ActsAsTenant.with_tenant(shop) do
        OrderTransaction.where(order_id: refund.order_id, kind: %w[sale capture], status: "success")
                        .where.not(provider_reference: nil).order(:id).last&.provider_reference
      end
      provider_row = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.find_by(provider: "airwallex") }

      if intent_id.blank? || provider_row.nil?
        return mark_failure!(shop, refund, transaction, "缺少原收款 intent 或 provider 設定")
      end

      amount = Money::Storage.from_cents(refund.total_cents, refund.currency)
      response = Psp::Airwallex::Refunds.new(provider_row)
                                        .create(amount:, payment_intent_id: intent_id,
                                                request_id: refund.idempotency_key,
                                                reason: refund.reason)
      apply_status!(shop, refund, transaction, response)
    rescue StandardError => e
      mark_failure!(shop, refund, transaction, e.message.to_s.first(200)) if refund
    end

    private

    # @note 副作用：UPDATE refunds／order_transactions。
    def apply_status!(shop, refund, transaction, response)
      status = response["status"].to_s
      provider_reference = response["id"].to_s.presence
      ActsAsTenant.with_tenant(shop) do
        case status
        when "ACCEPTED", "SETTLED"
          refund.update!(status: "success")
          transaction&.update!(status: "success", provider_reference:, processed_at: Time.current)
        when "FAILED"
          release_cumulative_cap!(refund)
          refund.update!(status: "failure")
          transaction&.update!(status: "failure", provider_reference:)
        else # RECEIVED＝受理中：留 pending，記 provider_reference 供後續對帳
          transaction&.update!(provider_reference:)
        end
      end
    end

    # @note 副作用：UPDATE refunds／order_transactions（error_code 承載訊息摘要）
    #   ＋補償 orders.refunded_total_cents。
    def mark_failure!(shop, refund, transaction, message)
      ActsAsTenant.with_tenant(shop) do
        release_cumulative_cap!(refund)
        refund.update!(status: "failure")
        transaction&.update!(status: "error", error_code: message.to_s.first(64))
      end
    end

    # 🔴 退款失敗＝錢沒出去 ⇒ 累計欄必須補償回來，否則可退額度被永久佔用
    #（Calculator 的行可退量已依 status=failure 排除——兩處同步恢復才一致）。
    # 條件式 UPDATE 防負值（同一筆 refund 不會被補償兩次：呼叫端先驗 pending）。
    #
    # @note 副作用：UPDATE orders.refunded_total_cents。
    def release_cumulative_cap!(refund)
      Order.where(shop_id: refund.shop_id, id: refund.order_id)
           .where("refunded_total_cents >= ?", refund.total_cents)
           .update_all([ "refunded_total_cents = refunded_total_cents - ?", refund.total_cents ])
    end
  end
end
