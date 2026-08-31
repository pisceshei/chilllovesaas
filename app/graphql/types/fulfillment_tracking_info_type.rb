# frozen_string_literal: true

module Types
  # 追蹤資訊（G6-8；對位本尊 FulfillmentTrackingInfo）。
  # 解析輸入＝{ "number" => …, "url" => … } Hash（fulfillments.tracking_numbers
  # json 物件陣列的元素——官方 numbers/urls 平行陣列按位對應的等價儲存形）。
  class FulfillmentTrackingInfoType < BaseObject
    graphql_name "FulfillmentTrackingInfo"
    description "出貨的追蹤號與追蹤連結"

    field :number, String, null: true
    field :url, String, null: true

    def number = object["number"]
    def url = object["url"]
  end
end
