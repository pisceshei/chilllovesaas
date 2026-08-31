# frozen_string_literal: true

module Types
  # 出貨（G6-8；對位本尊 Fulfillment——ord-4 §7 官方句「Fulfillments represent the
  # physical shipment of products to customers.」）。
  #
  # status 值域＝我方 v1 兩值（success/cancelled；官方 FulfillmentStatus 現行 4 值
  # 中 ERROR/FAILURE 屬 3PL 請求形無路徑不出——Fulfillment model 檔頭同記）。
  class FulfillmentType < BaseObject
    graphql_name "Fulfillment"
    description "訂單的一筆實際出貨（包裹）"

    field :id, GraphQL::Types::ID, null: false
    field :legacy_resource_id, ID, null: false, method: :id
    field :status, String, null: false, description: "success/cancelled"
    field :tracking_company, String, null: true
    field :tracking_info, [ FulfillmentTrackingInfoType ], null: false,
          description: "追蹤號清單（號＋連結成對）"
    field :line_items, [ FulfillmentLineItemType ], null: false
    field :shipped_at, GraphQL::Types::ISO8601DateTime, null: true
    field :delivered_at, GraphQL::Types::ISO8601DateTime, null: true,
          description: "送達時刻（v1 恆 null——寫入入口隨物流事件線；誠實登記）"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def id
      "gid://chilllove/Fulfillment/#{object.id}"
    end

    def tracking_info = Array(object.tracking_numbers)
    def line_items = Array(object.line_items_snapshot)
  end
end
