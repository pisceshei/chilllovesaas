# frozen_string_literal: true

# G6 步 8a（顧客模組全量·資料層）：
# ①customer_marketing_consents——**append-only 同意事件表**（08 §C.4；G6-7 的
#   boolean 欄自此降級為快取層）。official 狀態機取證 2026-09-01（shopify.dev
#   CustomerEmailMarketingState 六值／CustomerSmsMarketingState 五值）。
# ②customers 狀態快取欄（email/sms_marketing_state）＋redaction_scheduled_at
#   （官方抹除＝排程制，10 天可取消——help 逐字＋測試店 modal 實測同值）。
# ③phone 唯一索引（步 8 роadmap 遺留：ix → uq）。
class CreateCustomerMarketingConsents < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:customer_marketing_consents)
      create_table :customer_marketing_consents,
                   comment: "行銷同意事件（append-only；快取在 customers 狀態欄）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :customer_id, null: false
        t.string :channel, limit: 16, null: false, comment: "email/sms（WhatsApp 隨後續）"
        t.string :state, limit: 32, null: false,
                 comment: "官方 enum 小寫形（subscribed/unsubscribed/pending/not_subscribed/redacted/invalid）"
        t.string :opt_in_level, limit: 32, comment: "single_opt_in/confirmed_opt_in/unknown（官方三值）"
        t.datetime :consent_updated_at, null: false,
                   comment: "官方 latest-wins 合併鍵（缺值時＝寫入當下，官方同規則）"
        t.string :source, limit: 32, null: false, comment: "checkout/admin/api（08 §C.4）"
        t.datetime :created_at, null: false

        t.index [ :shop_id, :customer_id, :channel, :consent_updated_at ],
                name: "ix_cmc_customer_channel_time"
      end
    end

    # 🔴 FK 獨立成步＋自己的守衛（本檔首版把它放在 table_exists? 塊內，
    # strong_migrations 擋下 add_foreign_key 後，重跑被守衛整塊跳過 ⇒ FK 靜默缺席。
    # 教訓：re-entry 守衛的粒度必須＝語句，不是區塊。）
    fk_missing = table_exists?(:customer_marketing_consents) &&
                 foreign_keys(:customer_marketing_consents).none? { |fk| fk.to_table == "customers" }
    if fk_missing
      safety_assured { add_foreign_key :customer_marketing_consents, :customers }
    end

    unless column_exists?(:customers, :email_marketing_state)
      add_column :customers, :email_marketing_state, :string, limit: 32,
                 null: false, default: "not_subscribed",
                 comment: "email 同意狀態快取（事件表 latest-wins 投影；官方六值）"
      add_column :customers, :sms_marketing_state, :string, limit: 32,
                 null: false, default: "not_subscribed",
                 comment: "SMS 同意狀態快取（官方五值）"
      add_column :customers, :redaction_scheduled_at, :datetime,
                 comment: "個資抹除排程時點（官方 10 天可取消；RedactDueJob 到點執行）"

      # 既有 boolean 快取回填成狀態值（true→subscribed；false 維持 not_subscribed——
      # 無法區分「從未訂閱」與「退訂」，取保守值；官方 UNSUBSCRIBED 需歷史證據）。
      safety_assured do
        execute <<~SQL.squish
          UPDATE customers SET email_marketing_state = 'subscribed'
          WHERE email_marketing_consent = TRUE
        SQL
        execute <<~SQL.squish
          UPDATE customers SET sms_marketing_state = 'subscribed'
          WHERE sms_marketing_consent = TRUE
        SQL
      end
    end

    if index_exists?(:customers, [ :shop_id, :phone ], name: "ix_customers_phone")
      remove_index :customers, name: "ix_customers_phone"
    end
    unless index_exists?(:customers, [ :shop_id, :phone ], name: "uq_customers_phone")
      add_index :customers, [ :shop_id, :phone ], unique: true, name: "uq_customers_phone"
    end
  end
end
