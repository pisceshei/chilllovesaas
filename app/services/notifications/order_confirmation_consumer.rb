# frozen_string_literal: true

module Notifications
  # 訂單確認信消費者（G6 步 6；orders/create → 信）。
  #
  # ①觸發＝outbox topic orders/create（G6-0a 唯一發布點）。
  # ②契約：只入列 DeliverJob（快、無外部 IO）；資料驗證在 job 內做。
  # ③冪等：at-least-once 語義下重複 call ⇒ 重複入列——job 端資料缺席跳過＋
  #   deliveries done 帳（見 DeliverJob 檔頭②的誠實登記）。
  class OrderConfirmationConsumer
    def self.name = "notifications.order_confirmation"

    def self.call(event)
      order_id = event.payload["order_id"]
      return if order_id.nil?

      DeliverJob.perform_later(shop_id: event.shop_id, kind: "order_confirmation", order_id:)
    end
  end
end
