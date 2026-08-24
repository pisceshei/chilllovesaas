# frozen_string_literal: true

# 第 20 包（整合規格 §4-20／裁定 B1 方案②）：變體刪除的庫存側前提。
#
# ①這是什麼：inventory_items.product_variant_id 可空化＋variant_deleted_at 稽核欄。
# ②為什麼：ledger（inventory_adjustments）是 append-only 稽核帳，其 FK 鏈
#   （adjustments→levels→items）要求 item 列在變體刪除後**保留**；
#   複合 FK (shop_id, product_variant_id) 帶 NULL 欄依 MySQL MATCH SIMPLE 不檢查
#   ⇒ 置 NULL 即合法孤兒，FK 本身不必動。
# ③唯一索引 uq_inventory_items_product_variant_id：多個孤兒同為 NULL——
#   依賴 MySQL「唯一索引允許多列 NULL」（與 event_outbox.dedupe_key 同一依賴，
#   官方逐字出處見 docs/worklog/2026-08-24-第19包事件與outbox轉發.md）。
# ④跨功能影響：Catalog::DeleteVariant（唯一寫入方）；對帳（Inventory::Reconcile）
#   讀 ledger 不讀 variant，不受影響；第 22 包宣告式 diff 的刪除分支呼叫本路徑。
class AllowOrphanInventoryItems < ActiveRecord::Migration[8.1]
  def change
    change_column_null :inventory_items, :product_variant_id, true
    add_column :inventory_items, :variant_deleted_at, :datetime, null: true,
      comment: "變體被刪除的時點（B1 稽核欄；NULL＝變體仍在）"
  end
end
