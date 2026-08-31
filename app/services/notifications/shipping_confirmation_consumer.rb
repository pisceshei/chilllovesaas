# frozen_string_literal: true

module Notifications
  # 出貨通知消費者（G6 步 6；order.fulfilled → 信）。
  #
  # ①觸發＝outbox topic order.fulfilled（Fulfillments::Create 發布）。
  # ②🔴 notify 旗標：payload["notify"] 是出貨 dialog 的「通知顧客」勾選
  #   （fulfillmentCreate notifyCustomer）——false ⇒ 不寄（本尊同語義：
  #   Send shipment details to your customer now）。
  class ShippingConfirmationConsumer
    def self.name = "notifications.shipping_confirmation"

    def self.call(event)
      return unless event.payload["notify"]

      order_id = event.payload["order_id"]
      fulfillment_id = event.payload["fulfillment_id"]
      return if order_id.nil? || fulfillment_id.nil?

      DeliverJob.perform_later(shop_id: event.shop_id, kind: "shipping_confirmation",
                               order_id:, fulfillment_id:)
    end
  end
end
