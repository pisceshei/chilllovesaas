# frozen_string_literal: true

module Psp
  module Airwallex
    # 退款端點（G6-8 步 5；官方 `POST /api/v1/pa/refunds/create`——ord-4 §9 取證
    # 2026-09-01：request_id 必填 ≤64／payment_intent_id 與 payment_attempt_id
    # 二選一／amount 選填（缺席＝退剩餘已收未退額）／reason ≤128）。
    #
    # 🔴 金額出向唯一路徑（鐵律 3＋65 §D）：`Money::Storage#to_psp_amount(psp: :airwallex)`
    # → `Psp::BaseAdapter#to_payload` → `Client#post_json(amount_psp_number:)` 原文注入
    # ——與 PaymentIntents#create 同一條管道，零 float。
    #
    # 🔴 回應 status 官方 4 值（逐字）：RECEIVED／ACCEPTED／SETTLED／FAILED。
    # 我方對映（dev doc 登記）：RECEIVED＝受理中（refund.status 維持 pending）；
    # ACCEPTED/SETTLED＝完成（→ success）；FAILED＝失敗（→ failure）。
    # ⚠️ 缺口研究確認**沒有** SUCCEEDED 值——不得憑直覺寫。
    class Refunds
      # @param provider [ShopPaymentProvider]
      # @param transport [#call, nil] 注入給 Client（specs 用）
      def initialize(provider, transport: nil)
        @client = Client.new(provider, transport:)
        @adapter = Psp::BaseAdapter.new(:airwallex)
      end

      # 建立退款。
      #
      # @param amount [Money::Storage]
      # @param payment_intent_id [String] 原收款 intent（provider_reference）
      # @param request_id [String] Airwallex 側冪等鍵（≤64）
      # @param reason [String, nil] ≤128（官方上限；超長由呼叫端截斷）
      # @return [Hash] refund（含 id／status）
      # @note 副作用：一次外部 HTTP POST。
      def create(amount:, payment_intent_id:, request_id:, reason: nil)
        amount_psp_number = @adapter.to_payload(amount.to_psp_amount(psp: :airwallex))
        payload = { request_id:, payment_intent_id:, currency: amount.currency }
        payload[:reason] = reason.to_s.slice(0, 128) if reason.present?
        @client.post_json("/api/v1/pa/refunds/create", payload, amount_psp_number:)
      end
    end
  end
end
