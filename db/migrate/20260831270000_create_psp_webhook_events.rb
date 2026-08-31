# frozen_string_literal: true

# PSP webhook 事件收件匣（G6-1a）。
#
# ①event_id 唯一＝**冪等的承載**（digest §H：Airwallex webhook 可重送、可亂序——
#   重複投遞以 (shop_id, provider, event_id) UNIQUE 擋在 INSERT）。
# ②本包只「驗簽＋收錄」；消費（payment_intent.succeeded → 訂單入帳）＝G6-1b，
#   吃 F5 的冪等入口。status 值域由 model 驗（received|processed|failed）。
class CreatePspWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:psp_webhook_events)
      create_table :psp_webhook_events,
                   comment: "PSP webhook 收件匣（驗簽後收錄；event_id 冪等；消費在 G6-1b）" do |t|
        t.bigint :shop_id, null: false
        t.string :provider, null: false, comment: "pack 代碼（airwallex／paypal）"
        t.string :event_id, null: false, comment: "PSP 側事件 id（冪等鍵；重複投遞被 UNIQUE 擋）"
        t.string :event_type, null: false, comment: "如 payment_intent.succeeded（值域＝PSP 側，不做 enum）"
        t.json :payload, null: false, comment: "原始事件 JSON（🔴 金額欄位消費時走 Money.from_psp_amount）"
        t.string :status, null: false, default: "received", comment: "received|processed|failed（model 驗）"
        t.datetime :processed_at
        t.timestamps
        t.index [ :shop_id, :provider, :event_id ], unique: true, name: "uq_psp_webhook_events_event"
        t.index [ :shop_id, :id ], unique: true, name: "uq_psp_webhook_events_tenant_id"
        t.index [ :shop_id, :status ], name: "ix_psp_webhook_events_status"
      end
    end

    unless foreign_key_exists?(:psp_webhook_events, :shops)
      safety_assured do
        add_foreign_key :psp_webhook_events, :shops, name: "fk_psp_webhook_events_shop"
      end
    end
  end
end
