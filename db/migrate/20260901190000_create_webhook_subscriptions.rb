# frozen_string_literal: true

# 步 20a：對外 webhooks 資料層（specs/18 F4 逐字表設計＋投遞紀錄 7 天）。
# 🔴 守衛粒度＝語句（91 §3.52 家族）。
class CreateWebhookSubscriptions < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:webhook_subscriptions)
      create_table :webhook_subscriptions, comment: "對外 webhook 訂閱（28 §15／18 F4）" do |t|
        t.bigint :shop_id, null: false
        t.string :topic, null: false, limit: 100
        t.string :url, null: false, limit: 1024
        t.string :secret, null: false, limit: 64, comment: "per-subscription HMAC 簽章密鑰"
        t.string :status, null: false, limit: 16, default: "active"
        t.integer :failure_count, null: false, default: 0
        t.integer :lock_version, null: false, default: 0
        t.timestamps
        t.index [ :shop_id, :id ], unique: true, name: "uq_webhook_subscriptions_tenant_id"
        t.index [ :shop_id, :topic, :status ], name: "ix_webhook_subscriptions_topic"
      end
    end

    unless table_exists?(:webhook_deliveries)
      create_table :webhook_deliveries, comment: "webhook 投遞紀錄（7 天除錯窗——18 F4）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :webhook_subscription_id, null: false
        t.string :event_id, null: false, limit: 36
        t.string :state, null: false, limit: 16, comment: "sent | failed"
        t.integer :status_code
        t.integer :duration_ms
        t.string :response_excerpt, limit: 1024, comment: "截斷回應（讀取上限 64KB、存 1KB）"
        t.datetime :created_at, null: false
        t.index [ :shop_id, :id ], unique: true, name: "uq_webhook_deliveries_tenant_id"
        t.index [ :shop_id, :webhook_subscription_id, :created_at ], name: "ix_webhook_deliveries_sub"
        t.index [ :created_at ], name: "ix_webhook_deliveries_purge"
      end
    end

    if table_exists?(:webhook_deliveries) &&
       foreign_keys(:webhook_deliveries).none? { |fk| fk.to_table == "webhook_subscriptions" }
      safety_assured { add_foreign_key :webhook_deliveries, :webhook_subscriptions, on_delete: :cascade }
    end
  end
end
