# frozen_string_literal: true

module Orders
  # 後台「標記為已付款」（G6-6 步 4；16 §F4.3——financial_status 只可由交易聚合
  # 推導，本服務即那條推導的 manual 入口：pending sale 交易翻 success ⇒ paid）。
  #
  # 與 `MarkPaidFromPsp` 的分工：PSP 路徑帶 provider_reference、由 webhook/輪詢
  # 觸發、已 paid 時靜默 no-op（雙路徑先到先贏）；本服務是**管理員顯式動作**——
  # 已 paid／已取消回明確錯誤（UI 該把鈕藏掉，殘留點擊要可解釋），不靜默吞。
  #
  # 冪等：lock! ＋ 狀態前置檢查＝條件轉移；mutation 層另有 idempotencyKey
  # presence 契約（limits idempotency.required_for）。純 DB、無外部 IO（鐵律 5）。
  module MarkAsPaid
    Result = Data.define(:order, :error) # error = [field, message, code] | nil

    module_function

    # @param shop [Shop]
    # @param order_id [Integer]
    # @return [Result]
    def call(shop:, order_id:)
      ActiveRecord::Base.transaction do
        order = Order.lock.find_by(shop_id: shop.id, id: order_id)
        next Result.new(order: nil, error: [ "id", "找不到這張訂單。", "NOT_FOUND" ]) if order.nil?
        if order.status == "cancelled"
          next Result.new(order:, error: [ "id", "已取消的訂單不能標記為已付款。", "INVALID_STATE" ])
        end
        if order.financial_status == "paid"
          next Result.new(order:, error: [ "id", "這張訂單已入帳。", "INVALID_STATE" ])
        end

        transaction = order.order_transactions.where(kind: "sale", status: "pending").order(:id).first
        if transaction
          transaction.update!(status: "success")
        else
          order.order_transactions.create!(
            shop_id: order.shop_id, kind: "sale", status: "success",
            gateway: "manual", amount_cents: order.total_cents, currency: order.currency,
            idempotency_key: "sale-marked-paid-#{order.id}"
          )
        end

        order.update!(financial_status: "paid")
        Event.create!(shop_id: order.shop_id, order_id: order.id, kind: "order.paid",
                      happened_at: Time.current, metadata: { "source" => "mark_as_paid" })
        EventOutbox.create!(
          event_id: SecureRandom.uuid,
          topic: Events::Topics::ORDERS_PAID,
          aggregate_type: "Order", aggregate_id: order.id,
          payload: { order_id: order.id, order_number: order.order_number,
                     total_cents: order.total_cents, currency: order.currency,
                     source: "mark_as_paid" },
          available_at: Time.current, status: "pending"
        )
        Result.new(order:, error: nil)
      end
    end
  end
end
