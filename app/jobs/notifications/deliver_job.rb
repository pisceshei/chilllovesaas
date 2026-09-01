# frozen_string_literal: true

module Notifications
  # 通知寄送 job（G6 步 6；Solid Queue）。
  #
  # ①這是什麼：outbox 消費者 → 本 job → mailer 的中段。只帶 id 不帶 payload
  #   （寄送時點重讀資料＝寄出的是最新事實；序列化面也小）。
  # ②冪等性誠實登記：outbox 至少一次投遞 ⇒ 本 job 可能重複入列；
  #   event_deliveries 的 done 帳擋住 relay 層重放，但「job 已寄成功、
  #   done 未落」的窗仍在 ⇒ **極端情況同一封信可能寄兩次**（89 §7；
  #   郵件業界通行取捨，v1 不建 per-mail 冪等表）。
  # ③資料缺席（訂單已刪／email 空）＝靜默跳過（通知不是帳務，不重試到死信）。
  class DeliverJob < ApplicationJob
    queue_as :default

    # @param shop_id [Integer]
    # @param kind [String]
    # @param order_id [Integer, nil]
    # @param fulfillment_id [Integer, nil]
    # @param checkout_id [Integer, nil] abandoned_checkout 分支（步 7）
    def perform(shop_id:, kind:, order_id: nil, fulfillment_id: nil, checkout_id: nil)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      ActsAsTenant.with_tenant(shop) do
        case kind
        when "order_confirmation" then deliver_order_confirmation(shop, order_id)
        when "shipping_confirmation" then deliver_shipping_confirmation(shop, order_id, fulfillment_id)
        when "abandoned_checkout" then deliver_abandoned_checkout(shop, checkout_id)
        else
          raise ArgumentError, "unknown notification kind: #{kind}"
        end
      end
    end

    private

    def deliver_order_confirmation(shop, order_id)
      order = Order.find_by(id: order_id)
      return if order.nil? || order.email.blank?

      payload = Payloads.order_confirmation(order:)
      NotificationMailer.notify(shop_id: shop.id, kind: "order_confirmation",
                                to: order.email, payload:).deliver_now
    end

    # 挽回信（步 7）：寄出後回填 recovery_email_sent_at（列表 Email status 的
    # 唯一寫入者）。寄送在前、回填在後——crash 窗偏「已寄未記」＝重寄風險
    # 與檔頭②同型（誠實登記，方向選「寧多寄不漏記寄過」的反向：漏記→可再手動寄，
    # 比記了沒寄（顧客永遠收不到）安全）。
    def deliver_abandoned_checkout(shop, checkout_id)
      checkout = Checkout.find_by(id: checkout_id)
      return if checkout.nil? || checkout.email.blank?

      payload = Payloads.abandoned_checkout(
        checkout:, url: Notifications::RecoveryUrl.for(checkout)
      )
      NotificationMailer.notify(shop_id: shop.id, kind: "abandoned_checkout",
                                to: checkout.email, payload:).deliver_now
      checkout.update_column(:recovery_email_sent_at, Time.current)
    end

    def deliver_shipping_confirmation(shop, order_id, fulfillment_id)
      order = Order.find_by(id: order_id)
      fulfillment = Fulfillment.find_by(id: fulfillment_id)
      return if order.nil? || fulfillment.nil? || order.email.blank?

      payload = Payloads.shipping_confirmation(order:, fulfillment:)
      NotificationMailer.notify(shop_id: shop.id, kind: "shipping_confirmation",
                                to: order.email, payload:).deliver_now
    end
  end
end
