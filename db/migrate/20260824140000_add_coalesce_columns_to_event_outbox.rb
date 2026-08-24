# frozen_string_literal: true

# 第 19 包（docs/plans/2026-08-24-第19包執行規格.md §4.2）：合併窗兩欄。
#
# ①這是什麼：event_outbox 的 dedupe_key（合併窗 upsert 鍵）與 coalesced_count（被併筆數）。
# ②具體行為：合併型庫存事件 dedupe_key 有值；豁免筆（availability_flipped）與全部商品事件
#   為 NULL——🔴 依賴 MySQL「唯一索引允許多列 NULL」（官方 8.4 Reference "This constraint
#   does not apply to NULL values"），NULL 列天生不碰撞，由 spec/models/event_outbox_spec 釘住。
# ③終態時（published/failed/dead）relay 把 dedupe_key 清成 NULL（release-on-terminal）
#   ＝「合併窗只在 pending 內」（63 §C.6）的機械保證。
# ④跨功能影響：Inventory::Adjust 的事件寫入用 (shop_id, dedupe_key) 唯一鍵 upsert；
#   Events::Relay 終態清鍵；既有 8 筆 bt3 pending 列（products/*）dedupe_key 為 NULL 不受影響。
class AddCoalesceColumnsToEventOutbox < ActiveRecord::Migration[8.1]
  def change
    add_column :event_outbox, :dedupe_key, :string, limit: 191, null: true
    add_column :event_outbox, :coalesced_count, :integer, null: false, default: 1
    add_index :event_outbox, [ :shop_id, :dedupe_key ], unique: true, name: "uq_event_outbox_dedupe_key"
  end
end
