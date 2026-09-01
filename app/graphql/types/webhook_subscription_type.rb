# frozen_string_literal: true

module Types
  # webhook 訂閱（步 20a；28 §15）。secret 不在讀面（建立時一次性回傳）。
  class WebhookSubscriptionType < BaseObject
    graphql_name "WebhookSubscription"
    description "對外 webhook 訂閱。"

    field :callback_url, String, null: false, method: :url
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :failure_count, Integer, null: false
    field :format, String, null: false, description: "固定 json（28 §15 已知差異註記）。"
    field :id, ID, null: false
    field :status, String, null: false
    field :topic, String, null: false

    def id = "gid://chilllove/WebhookSubscription/#{object.id}"
    def format = "json"
  end
end
