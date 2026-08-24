# frozen_string_literal: true

# 庫存地基 backfill（排程第 16 包）：既有商店補預設地點、既有變體補 inventory_item ＋
# 每地點一列 0 量 level。
#
# 🔴 為什麼是 migration 而不是 rake：90 藍圖 §9.1.4——「任何『先做商品、之後再補庫存』
#    的排法都會產生一次資料回填」，這次就是那一次回填；做成 migration 讓 deploy 的
#    db:prepare 自動、冪等地把 bt3 上既有的變體接上庫存鏈，不依賴人記得跑 rake。
# 🔴 純 SQL（INSERT…SELECT ＋ NOT EXISTS）不經 model：migration 引用 model 會隨
#    model 演化而腐爛；且 NOT EXISTS 讓整支冪等（重跑不重複插列）。
# 🔴 與 callback 的分工：本 migration 管「已存在的」，Shop／ProductVariant／Location 的
#    after_create 管「之後新建的」——兩邊合起來不變量才完整（每變體一 item、每 item×地點一 level）。
class BackfillInventoryBaseline < ActiveRecord::Migration[8.1]
  def up
    default_name = Limits.fetch(:inventory, :default_location_name)

    safety_assured do
      # ① 沒有任何地點的商店 ⇒ 建預設地點
      execute(<<~SQL.squish)
        INSERT INTO locations (shop_id, name, address, created_at, updated_at)
        SELECT s.id, #{connection.quote(default_name)}, JSON_OBJECT(), NOW(6), NOW(6)
        FROM shops s
        WHERE NOT EXISTS (SELECT 1 FROM locations l WHERE l.shop_id = s.id)
      SQL

      # ② 沒有 inventory_item 的變體 ⇒ 建 item（tracked 預設 true；sku 鏡射一次，D-待裁定 17 前不同步）
      execute(<<~SQL.squish)
        INSERT INTO inventory_items (shop_id, product_variant_id, sku, tracked, requires_shipping, created_at, updated_at)
        SELECT pv.shop_id, pv.id, pv.sku, TRUE, TRUE, NOW(6), NOW(6)
        FROM product_variants pv
        WHERE NOT EXISTS (
          SELECT 1 FROM inventory_items ii
          WHERE ii.shop_id = pv.shop_id AND ii.product_variant_id = pv.id
        )
      SQL

      # ③ item × 同店地點 的笛卡兒積缺列 ⇒ 補 0 量 level
      execute(<<~SQL.squish)
        INSERT INTO inventory_levels
          (shop_id, inventory_item_id, location_id, available, committed,
           reserved, damaged, safety_stock, quality_control, incoming, lock_version, created_at, updated_at)
        SELECT ii.shop_id, ii.id, l.id, 0, 0, 0, 0, 0, 0, 0, 0, NOW(6), NOW(6)
        FROM inventory_items ii
        JOIN locations l ON l.shop_id = ii.shop_id
        WHERE NOT EXISTS (
          SELECT 1 FROM inventory_levels il
          WHERE il.shop_id = ii.shop_id
            AND il.inventory_item_id = ii.id
            AND il.location_id = l.id
        )
      SQL
    end
  end

  # 資料回填不可逆轉（down 不刪資料——刪了會把使用者手動建的地點一併帶走）。
  def down; end
end
