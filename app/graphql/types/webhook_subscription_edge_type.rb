# frozen_string_literal: true

module Types
  # WebhookSubscription connection 的 edge。
  class WebhookSubscriptionEdgeType < BaseObject
    graphql_name "WebhookSubscriptionEdge"
    field :cursor, String, null: false
    field :node, WebhookSubscriptionType, null: false
  end
end
