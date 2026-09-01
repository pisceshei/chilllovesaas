# frozen_string_literal: true

module Types
  module Errors
    # webhook 訂閱 mutation 的錯誤碼（鐵律 4）。
    class WebhookUserErrorCode < BaseCodeEnum
      graphql_name "WebhookUserErrorCode"
      description "webhook 訂閱 mutation 可能回傳的錯誤碼。"

      from_pools
      own_value :URL_NOT_ALLOWED,
                "URL 未過紅線：HTTPS only＋SSRF resolve 層防護（specs/18 F4）。"
      own_value :TOPIC_NOT_SUBSCRIBABLE,
                "topic 不在可訂閱白名單（內部 topic 永不可訂閱——28 §15）。"
      own_value :LIMIT_REACHED,
                "每店訂閱數上限（limits webhook.max_subscriptions_per_shop）。"
    end
  end
end
