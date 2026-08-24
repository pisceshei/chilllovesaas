# frozen_string_literal: true

# 庫存列表的 keyset 分頁索引。
#
# 🔴 為什麼要這個：`Inventory::ItemsQuery` 的排序是 `created_at DESC, id DESC`
# （keyset 分頁的游標順序），但 `inventory_items` 上只有
# `(shop_id, id)` / `(shop_id, product_variant_id)` / `(shop_id, sku)` 三個索引，
# 沒有一個能供這個排序。實測 bt3 `EXPLAIN` ⇒ `Using filesort`：
# 每翻一頁都得把該租戶**全部**庫存品項讀出來排一次。
# demo 店只有 3 筆看不出來，商品上千就是每頁一次全表排序。
#
# 索引以 `shop_id` 開頭（鐵律 2），其後接排序鍵，讓 MySQL 直接走索引序取前 N 筆。
class AddInventoryItemsKeysetIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :inventory_items, %i[shop_id created_at id],
              name: "ix_inventory_items_keyset"
  end
end
