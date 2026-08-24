# frozen_string_literal: true

# 變體對應的一對一庫存品項（排程第 16 包；13 §F5、63 §B.5）。
#
# ①這是什麼：庫存身分的載體——數量掛在 (item, location) 的 level 上，item 掛在變體上。
# ②值域：`tracked` 布林（false＝不追蹤庫存，列表顯示「未追蹤」）；`sku`／HS code／原產地屬運送面。
# ③怎麼做：**變體建立即建**（ProductVariant after_create）＋ 既有變體由 migration backfill——
#   63 §B.5 的驗收條是「加選項後原 variant.id 與 inventory_item.id 完全相同」，
#   item 必須在變體出生那一刻就存在，否則身分保持無從談起。
# ④跨功能影響：`Product.totalInventory`（第 16 包）、庫存調整入口（第 17 包）、
#   /admin/inventory 列表（第 18 包）。⚠️ `sku` 的權威表（本欄 vs product_variants.sku）
#   是排程 §6 的待裁定第 17 條——建立時鏡射一次、**不雙向同步**，裁定前不加機制。
class InventoryItem < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product_variant
  has_many :inventory_levels, dependent: :delete_all

  validates :product_variant_id, uniqueness: { scope: :shop_id }
end
