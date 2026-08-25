# frozen_string_literal: true

module Types
  # 一個變體在**某一個地點**的庫存列（第 29 包變體子頁的庫存卡）。
  #
  # 🔴 **為什麼另立這個 type 而不是複用 `InventoryItemType`**：後者是「單一地點視角」
  #   的列表列（`inventoryItems(locationId:)` 一次只回一個地點），商品頁庫存卡因此
  #   有個地點選擇器。變體子頁要的是**同一個變體的全部地點一次看完**（93 §2 實測
  #   「庫存卡（per-location 表）」）——形狀不同，硬套會逼出 N 次查詢（每地點一次）。
  # 🔴 數量一律走 `InventoryQuantities`（unavailable／onHand 是 DB generated 欄）
  #   ——前端不得自行相加，兩處算式遲早漂移（鐵律 7）。
  class VariantInventoryLevelType < BaseObject
    graphql_name "VariantInventoryLevel"
    description "變體在某地點的庫存數量。"

    field :location, Types::LocationType, null: false
    field :quantities, Types::InventoryQuantitiesType, null: false
    field :inventory_item_id, ID, null: false,
      description: "調整用的品項 GID（inventoryAdjustQuantities 的 inventoryItemId）。"

    def inventory_item_id = "gid://chilllove/InventoryItem/#{object.inventory_item_id}"

    def quantities = object
  end
end
