# frozen_string_literal: true

# 庫存與出貨地點（排程第 16 包；13 §F5）。
#
# ①這是什麼：庫存數量的空間軸——每個 (inventory_item, location) 一列 level。
# ②值域：`name` 每店唯一（DB 唯一索引 uq_locations_name）；`active`／`fulfills_online_orders`
#   布林；`priority` 供履行路由排序（M3 展開）。
# ③怎麼做：建店即建預設地點（Shop#create_default_location，名稱同本尊「Shop location」）；
#   **新地點建立即為既有的每個 inventory_item 補一列 level**（after_create）——
#   反方向的機制在 ProductVariant（新變體為每個地點補 level），兩個方向都是 callback
#   而不是服務層紀律，因為 level 缺列的症狀是「該地點的庫存頁少一列」且無錯誤訊息。
# ④跨功能影響：/admin/inventory 的地點選擇器（第 18 包）、履行路由（M3）、
#   多地點 per-location 數量（本尊變體子頁的庫存卡）。
class Location < ApplicationRecord
  acts_as_tenant :shop

  has_many :inventory_levels, dependent: :delete_all

  validates :name, presence: true, uniqueness: { scope: :shop_id }

  # T14：門市取貨（本尊 Settings › Shipping and delivery › Pickup in store，每地點一組設定）。
  # 只有 `pick_up_enabled` 的 active 地點進 `variant.store_availabilities`
  # （官方 location 物件 "only available when one or more locations have local pickup enabled"）。
  scope :pickup_enabled, -> { where(active: true, pick_up_enabled: true) }

  validates :pick_up_time, length: { maximum: 64 }, allow_nil: true

  after_create :seed_levels_for_existing_items

  private

  # 新地點 × 既有品項 ⇒ 逐列補 0 量 level（冪等：唯一索引擋重複，find_or_create）。
  def seed_levels_for_existing_items
    InventoryItem.where(shop_id: shop_id).find_each do |item|
      InventoryLevel.find_or_create_by!(shop_id: shop_id, inventory_item_id: item.id, location_id: id)
    end
  end
end
