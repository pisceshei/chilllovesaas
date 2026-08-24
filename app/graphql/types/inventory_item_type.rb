# frozen_string_literal: true

module Types
  # 庫存列表的一列（排程第 18 包）。
  #
  # 資料來自 `Inventory::ItemsQuery` 的 JOIN 別名——**不要在這裡另發查詢**
  # （那就是 N+1；別名不存在時是呼叫端漏了 select，應該讓它炸而不是靜默補查）。
  class InventoryItemType < BaseObject
    graphql_name "InventoryItem"
    description "變體對應的庫存品項（單一地點視角）。"

    field :id, ID, null: false
    field :sku, String, null: true
    field :tracked, Boolean, null: false,
      description: "false＝不追蹤庫存（列表顯示「未追蹤」；與數量 0 是兩個真相）。"
    field :product_title, String, null: false
    field :variant_title, String, null: false
    field :product_id, ID, null: false, description: "供列表列連到商品編輯頁。"
    field :location_id, ID, null: false, description: "本列數量所屬地點。"
    field :quantities, Types::InventoryQuantitiesType, null: false

    def id = "gid://chilllove/InventoryItem/#{object.id}"
    def product_id = "gid://chilllove/Product/#{object.read_attribute('variant_product_id')}"
    def location_id = "gid://chilllove/Location/#{context[:inventory_location_id]}"
    def product_title = object.read_attribute("product_title")
    def variant_title = object.read_attribute("variant_title")

    def quantities
      {
        unavailable: object.read_attribute("level_unavailable").to_i,
        committed: object.read_attribute("level_committed").to_i,
        available: object.read_attribute("level_available").to_i,
        on_hand: object.read_attribute("level_on_hand").to_i,
        incoming: object.read_attribute("level_incoming").to_i
      }
    end
  end
end
