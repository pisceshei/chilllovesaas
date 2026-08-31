# frozen_string_literal: true

module Orders
  # PSP 付款成功回呼的統一終點（G6-1c；15-F4 雙路徑）：webhook consumer 與
  # 輪詢端點**都**走本服務——先到先贏、全程冪等。
  #
  # ①🔴 金額比對先化到 R1（65 §E：`Money.from_psp_amount` 入向 ⇒ 與 checkout 應收
  #   同表示法再比；金額不符 ⇒ **不建單**，記 P1 事件由人工看——自動退款隨 G6-3）。
  # ②成單＝`CreateFromCheckout`（key `order-<token>`——與買家 manual 完成鈕同一把，
  #   Guard replay 保恰一單）；入帳＝`MarkPaidFromPsp`（已 paid no-op）。
  # ③🔴 外部 IO 不在本服務內（金額由呼叫端從 webhook payload／intent GET 取得）。
  module FinalizePspPayment
    Result = Data.define(:order, :status, :message)
    AmountMismatch = Class.new(StandardError)

    module_function

    # @param shop [Shop]
    # @param checkout_token [String] ＝Airwallex merchant_order_id
    # @param provider [String]
    # @param psp_reference [String] intent id
    # @param amount_storage [Money::Storage] PSP 回報金額（已經 from_psp_amount 入向）
    # @return [Result]
    # @raise [AmountMismatch] 金額不符（呼叫端記 P1；不建單）
    def call(shop:, checkout_token:, provider:, psp_reference:, amount_storage:)
      # checkout 完成後列仍在（completed；刪的是 cart）⇒ 應收基準恆取自 checkout。
      expected = ActsAsTenant.with_tenant(shop) do
        Checkout.find_by(token: checkout_token)&.total_cents
      end
      if expected.nil?
        return Result.new(order: nil, status: :not_found, message: "找不到 checkout #{checkout_token}")
      end

      expected_storage = Money::Storage.from_cents(expected, amount_storage.currency)
      unless amount_storage == expected_storage
        raise AmountMismatch,
          "PSP 回報 #{amount_storage.inspect} ≠ 應收 #{expected_storage.inspect}" \
          "（checkout #{checkout_token}；65 §E：不建單、進人工）"
      end

      outcome = CreateFromCheckout.call(
        shop:, checkout_token:, idempotency_key: "order-#{checkout_token}"
      )
      order = outcome[:resource]
      return Result.new(order: nil, status: :failed, message: "成單失敗") if order.nil?

      ActsAsTenant.with_tenant(shop) do
        MarkPaidFromPsp.call(order:, provider:, provider_reference: psp_reference)
      end
      Result.new(order:, status: :paid, message: nil)
    end
  end
end
