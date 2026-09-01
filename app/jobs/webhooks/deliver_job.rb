# frozen_string_literal: true

module Webhooks
  # webhook 投遞 job（步 20a）。重試＝指數退避 re-enqueue（demo 3 次——limits
  # webhook.delivery_max_attempts；規格目標 8 次/4h 見 28 §15 註記）；
  # 連續失敗達門檻 ⇒ 訂閱 disabled（18 F4 的 demo 折算；成功即歸零）。
  class DeliverJob < ApplicationJob
    queue_as :default

    # @param attempt [Integer] 1-based
    def perform(subscription_id, event_id, shop_id, attempt)
      subscription, event, shop = ActsAsTenant.without_tenant do
        [
          WebhookSubscription.find_by(shop_id:, id: subscription_id),
          EventOutbox.find_by(shop_id:, event_id:),
          Shop.find_by(id: shop_id)
        ]
      end
      return if subscription.nil? || event.nil? || shop.nil?
      return if subscription.status != "active"

      result = Deliver.call(subscription:, event:, shop:)
      ActsAsTenant.without_tenant do
        if result.ok?
          subscription.update!(failure_count: 0)
        else
          handle_failure!(subscription, event, attempt)
        end
      end
    end

    private

    def handle_failure!(subscription, event, attempt)
      subscription.increment!(:failure_count)
      if subscription.failure_count >= Limits.fetch(:webhook, :disable_after_failures)
        subscription.update!(status: "disabled") # 18 F4：持續失敗 ⇒ disabled（通知商家＝91 登記）
      elsif attempt < Limits.fetch(:webhook, :delivery_max_attempts)
        # 指數退避：2^attempt 分鐘（demo 尺度）
        self.class.set(wait: (2**attempt).minutes)
            .perform_later(subscription.id, event.event_id, subscription.shop_id, attempt + 1)
      end
    end
  end
end
