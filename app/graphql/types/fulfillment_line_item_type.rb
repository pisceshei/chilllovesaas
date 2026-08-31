# frozen_string_literal: true

module Types
  # 出貨行項（G6-8；v1 由 fulfillments.line_items_snapshot 解析——本尊
  # FulfillmentLineItem 是子表，我方 v1 json 快照，欄位面對位）。
  # 解析輸入＝{ "line_item_id" => …, "quantity" => … } Hash。
  class FulfillmentLineItemType < BaseObject
    graphql_name "FulfillmentLineItem"
    description "這筆出貨包含的行項與數量"

    field :line_item, LineItemType, null: true,
          description: "對應的訂單行項（行項被刪時為 null——快照仍保 quantity）"
    field :quantity, Integer, null: false

    def line_item
      LineItem.find_by(shop_id: context.fetch(:current_shop).id, id: object["line_item_id"])
    end

    def quantity = object["quantity"].to_i
  end
end
