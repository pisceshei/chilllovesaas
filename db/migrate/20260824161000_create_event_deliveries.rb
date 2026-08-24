# frozen_string_literal: true

# 第 25 包（整合規格 §1.3／§4-25；63 §L-4 門檻在此結清）：逐消費者投遞帳。
#
# ①這是什麼：event × consumer 的投遞狀態——outbox 從「整筆事件標 published」升級成
#   「每個消費者各自記帳」的那張帳（P19 relay.rb 檔頭③預告的開工前置）。
# ②具體行為：Relay 對每個註冊消費者 find_or_create 一列；成功＝done、失敗＝attempts++
#   ＋last_error 留在 pending。事件重試時 done 列跳過——**一個消費者失敗不連累
#   另一個重放**（本包判準）。全部 done ⇒ 事件 published。
# ③生命週期：FK (shop_id, event_id) → event_outbox 帶 ON DELETE CASCADE——
#   outbox purge!（published/dead 逾 30 天 delete_all）時投遞帳同批消失，
#   不留孤兒也不擋 purge。
# ④跨功能影響：Events::Relay#deliver（本包改寫）、Events::Consumers 註冊表（本包新增）、
#   第 26 包媒體處理消費者、第 30 包 CacheStampBumper——接消費者只動註冊表，不動 relay。
class CreateEventDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :event_deliveries, comment: "event × consumer 投遞帳（逐消費者重放隔離）" do |t|
      t.bigint :shop_id, null: false
      t.string :event_id, limit: 36, null: false
      t.string :consumer, limit: 100, null: false
      t.string :state, limit: 32, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps

      t.index [ :shop_id, :id ], unique: true, name: "uq_event_deliveries_tenant_id"
      t.index [ :shop_id, :event_id, :consumer ], unique: true, name: "uq_event_deliveries_event_consumer"
      t.index [ :shop_id, :state ], name: "ix_event_deliveries_state"
    end
    # 新建空表加 FK：strong_migrations 的鎖表顧慮不適用（零列）；M0 同型先例
    safety_assured do
      add_foreign_key :event_deliveries, :shops, name: "fk_event_deliveries_shop"
      add_foreign_key :event_deliveries, :event_outbox, column: [ :shop_id, :event_id ],
                      primary_key: [ :shop_id, :event_id ], name: "fk_event_deliveries_event",
                      on_delete: :cascade
    end
  end
end
