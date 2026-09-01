# frozen_string_literal: true

module Webhooks
  # outbox → webhook 訂閱扇出（步 20a；28 §15「outbox 驅動」）。
  # 只對 **EXTERNAL** topic 掛載（Events::Consumers.for 的判準）；每個 active
  # 訂閱一顆 DeliverJob（逐訂閱重試隔離——一個壞 endpoint 不連累其他）。
  class FanoutConsumer
    def self.name = "webhooks.fanout"

    def self.call(event)
      ActsAsTenant.without_tenant do
        WebhookSubscription.where(shop_id: event.shop_id, topic: event.topic,
                                  status: "active").pluck(:id).each do |subscription_id|
          Webhooks::DeliverJob.perform_later(subscription_id, event.event_id, event.shop_id, 1)
        end
      end
    end
  end
end
