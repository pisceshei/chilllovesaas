# frozen_string_literal: true

module Psp
  module Airwallex
    # payment_intents 的服務面（G6-1a：create／get／sandbox 測試卡 confirm）。
    #
    # 🔴 金額出向唯一路徑：`Money::Storage#to_psp_amount(psp: :airwallex)` →
    # `Psp::BaseAdapter#to_payload`（L3 型別閘門）→ `Client#post_json(amount_psp_number:)`
    # 原文注入。回應／webhook 的金額入向走 `Money.from_psp_amount`（65 §E X8c）。
    #
    # ⚠️ 本層不落訂單、不碰 checkout——回呼→訂單的接線是 G6-1b（吃 F5 的
    # `Orders::CreateFromCheckout` 冪等入口）。
    class PaymentIntents
      # @param provider [ShopPaymentProvider]
      # @param transport [#call, nil] 注入給 Client（specs 用）
      def initialize(provider, transport: nil)
        @provider = provider
        @client = Client.new(provider, transport:)
        @adapter = Psp::BaseAdapter.new(:airwallex)
      end

      # 建立 payment intent（digest §H：必填 amount／currency／request_id≤64／
      # merchant_order_id≤64；request_id＝Airwallex 側冪等鍵）。
      #
      # @param amount [Money::Storage]
      # @param request_id [String]
      # @param merchant_order_id [String]
      # @return [Hash] intent（含 id／client_secret／status）
      def create(amount:, request_id:, merchant_order_id:)
        amount_psp_number = @adapter.to_payload(amount.to_psp_amount(psp: :airwallex))
        @client.post_json(
          "#{base_path}/create",
          { request_id:, currency: amount.currency, merchant_order_id: },
          amount_psp_number:
        )
      end

      # @param intent_id [String]
      # @return [Hash]
      def get(intent_id)
        @client.get_json("#{base_path}/#{intent_id}")
      end

      # 🔴 **sandbox 專用**：以官方測試卡直接 confirm（走 API 送 PAN）。
      # production 一律 raise——真卡號只能走前端 Element（PCI 面），本方法存在的唯一
      # 理由是 sandbox 端到端實測（G6-1 enable 前置）。
      #
      # @param intent_id [String]
      # @param card [Hash] number/expiry_month/expiry_year/cvc/name
      # @return [Hash] confirm 後的 intent
      def confirm_with_test_card(intent_id, card:)
        unless @provider.environment == "sandbox"
          raise Client::Error, "confirm_with_test_card 只准 sandbox（production 卡號只能走前端 Element）"
        end

        @client.post_json(
          "#{base_path}/#{intent_id}/confirm",
          { request_id: SecureRandom.uuid, payment_method: { type: "card", card: } }
        )
      end

      private

      def base_path
        Limits.fetch(:psp_integration, :airwallex, :payment_intents_path)
      end
    end
  end
end
