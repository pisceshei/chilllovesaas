# frozen_string_literal: true

# S10（D76）：`price_lists`——catalog 三件組（catalog × publication × price list）的最後一張表。
#
# 本尊結構（82 §9.5b 抓包）：建立 market catalog 時第二支 operation 就是
# `CatalogPriceListCreate`，payload 逐字（節錄）：
#   `{"input":{"currency":"HKD","parent":{"adjustment":{"value":0,"type":"PERCENTAGE_DECREASE"},
#     "settings":{"compareAtMode":"ADJUSTED"}},"catalogId":"gid://shopify/MarketCatalog/…","name":"…"}}`
# 官方輸入形（priceListCreate，取證 2026-08-30）：name!／currency!／parent!（adjustment
# type+value）；`PriceListAdjustmentType` 恰二值（PERCENTAGE_DECREASE／PERCENTAGE_INCREASE，
# 逐字 "Prices will have a lower value."／"Prices will have a higher value."）；
# `PriceListCompareAtMode` 恰二值（ADJUSTED 逐字 "The compare at price is adjusted based on
# percentage specified in price list."／NULLIFY "The compare at prices are set to `null`
# unless explicitly defined by a fixed price value."）。
#
# 🔴 **`adjustment_percentage` 是百分比不是金額**（鐵律 3 的識別字紀律反向適用：
#   不帶 `*_cents` 後綴、不進金額型別系統）。**變體級固定價**（82 §9.5c 實測
#   catalog 成員表每列可編輯 Price／Compare-at）是另一張表（`price_list_prices`，
#   **金額欄位、必須 `*_cents`**）——那張表隨 M5 成員模型一起建，本支不建。
#
# 🔴 一個 catalog 至多一個 price list（本尊 catalogDelete 文檔逐字
#   "the price list and the publication owned by the catalog"——單數所有格；
#   §9.5b 亦只有一支 CatalogPriceListCreate）⇒ uq_price_lists_catalog。
#
# @see docs/research/82-admin-channels.md §9.5b、§21
# @see docs/specs/88-publication-model.md §3.2
class CreatePriceLists < ActiveRecord::Migration[8.1]
  def up
    # MySQL DDL 非交易 ⇒ if_not_exists，半途死掉可重跑（S0 同款）。
    create_table :price_lists, if_not_exists: true,
                 comment: "catalog 的價格表（本尊 PriceList；百分比層，變體固定價隨 M5 另表）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :sales_catalog_id, null: false
      t.string :name, null: false, limit: 255, comment: "顯示名（官方 priceListCreate name!）"
      # ISO 4217 代碼——只是**識別字**不是金額（鐵律 3 的單位邊界在 price_list_prices 才出現）。
      t.string :currency, limit: 3, null: false, comment: "固定價所用幣別（官方 currency!）"
      t.string :adjustment_type, limit: 24, null: false,
               comment: "percentage_decrease／percentage_increase（本尊 PriceListAdjustmentType 恰二值）"
      # 🔴 百分比，非金額——但用**整數 basis points**（1bp＝0.01%；100%＝10000）：
      #   ①C3 判準（check-money-boundary）對 migration 全面禁 decimal/float，百分比
      #     不必為了小數表示去挑戰它；②整數無累積誤差，兩位小數百分比精確覆蓋。
      t.integer :adjustment_basis_points, null: false, default: 0,
                comment: "調整幅度（basis points，1bp=0.01%）；decrease 側數學上限 10000（低於零價不存在）"
      t.string :compare_at_mode, limit: 16, null: false, default: "adjusted",
               comment: "adjusted／nullify（本尊 PriceListCompareAtMode；admin 預設開 Include compare-at price ⇒ adjusted，82 §9.5c）"
      t.timestamps
    end

    add_index :price_lists, %i[shop_id id], unique: true,
              name: "uq_price_lists_tenant_id", if_not_exists: true
    # 一個 catalog 至多一個 price list（檔頭理由）。
    add_index :price_lists, %i[shop_id sales_catalog_id], unique: true,
              name: "uq_price_lists_catalog", if_not_exists: true

    # 新建空表加 FK：strong_migrations 鎖表顧慮不適用（零列；S0 同型先例）。
    unless foreign_key_exists?(:price_lists, :shops)
      safety_assured { add_foreign_key :price_lists, :shops, name: "fk_price_lists_shop" }
    end
    unless foreign_key_exists?(:price_lists, :sales_catalogs)
      safety_assured do
        add_foreign_key :price_lists, :sales_catalogs,
                        column: %i[shop_id sales_catalog_id], primary_key: %i[shop_id id],
                        name: "fk_price_lists_sales_catalog"
      end
    end
  end

  def down
    drop_table :price_lists, if_exists: true
  end
end
