# frozen_string_literal: true

module Types
  # 履約工作單（G6-8；對位本尊 FulfillmentOrder——官方句「represents either an item
  # or a group of items in an Order that are expected to be fulfilled from the same
  # location」，取證 2026-09-01）。
  #
  # v1 精簡讀出：status/requestStatus/assignedLocation 名。官方的 lineItems
  # connection／supportedActions v1 不出（前端由 order.lineItems 的
  # fulfillableQuantity 導出可出貨行；supportedActions 需要完整狀態機才不誤導）。
  class FulfillmentOrderType < BaseObject
    graphql_name "FulfillmentOrder"
    description "訂單的履約工作單（v1 每單一張、單地點）"

    field :id, GraphQL::Types::ID, null: false
    field :legacy_resource_id, ID, null: false, method: :id
    field :status, String, null: false,
          description: "open/in_progress/on_hold/scheduled/closed/cancelled/incomplete"
    field :request_status, String, null: false, description: "v1 恆 unsubmitted（無 3PL）"
    field :assigned_location_name, String, null: true,
          description: "指派地點名（官方 assignedLocation 的 v1 精簡形）"

    def id
      "gid://chilllove/FulfillmentOrder/#{object.id}"
    end

    def assigned_location_name
      Location.find_by(shop_id: object.shop_id, id: object.location_id)&.name
    end
  end
end
