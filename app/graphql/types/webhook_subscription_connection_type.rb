# frozen_string_literal: true

module Types
  # WebhookSubscription 的 keyset connection（28 §0.3 分頁慣例）。
  class WebhookSubscriptionConnectionType < BaseObject
    graphql_name "WebhookSubscriptionConnection"
    field :edges, [ WebhookSubscriptionEdgeType ], null: false
    field :nodes, [ WebhookSubscriptionType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
