# frozen_string_literal: true

# G6-3 前半切片：PSP provider 憑證層（總方案 G6-3 資料層既定形＝
# provider＋憑證引用〔金鑰不明文入庫，37 §6.3〕＋enabled_methods JSON 白名單）。
#
# ①與 `shop_payment_methods` 是**兩張不同的表**（第三包 worklog 明文：該表只承載
#   manual 四型）；本表承載 PSP 直連 provider（airwallex／paypal）的租戶側憑證與偏好。
# ②秘密欄（api_secret／webhook_secret）＝Active Record encryption **密文**
#   （non-deterministic；37 §6.3 最低標）；UI 只回 SHA-256 前 16 hex 指紋，write-only。
# ③`enabled_methods`＝商家白名單（15-F4.2 三條件交集的商家側一半）；**不是**可用方式
#   的真相來源——結帳顯示＝白名單 ∩ PSP capability（G6-1 接 capability API 與 webhook
#   type∈白名單雙防線）。字典層（有哪些 method code）＝平台 pack 宣告，隨 G6-3 全量入。
# ④activation 狀態機（86 §1「一次只能一家 credit-card provider」）隨 G6-3 落；
#   本切片 status 恆 inactive，結帳線**零讀取**本表——pack `enabled: false` 的
#   fail-closed 閘門不受影響。
class CreateShopPaymentProviders < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:shop_payment_providers)
      create_table :shop_payment_providers,
                   comment: "PSP provider 的租戶側憑證與偏好（G6-3 前半；祕密欄一律 AR encryption 密文，37 §6.3）" do |t|
        t.bigint :shop_id, null: false
        t.string :provider, null: false,
                 comment: "pack 代碼（值域＝config/limits.yml psp_packs 的鍵；model 驗 inclusion）"
        t.string :environment, null: false, default: "sandbox",
                 comment: "sandbox|production（limits psp_credentials.environment_enum；跨環境禁用同 carrier 慣例）"
        t.string :status, null: false, default: "inactive",
                 comment: "inactive|active；本切片恆 inactive——activation 狀態機（86 §1 一家 credit-card provider）隨 G6-3"
        t.string :client_id, comment: "非祕密識別（Airwallex x-client-id／PayPal client_id）；明文可回讀"
        t.text :api_secret, comment: "🔴 AR encryption 密文（Airwallex API key／PayPal client secret）；UI 永不回讀明文"
        t.text :webhook_secret, comment: "🔴 AR encryption 密文（Airwallex webhook HMAC secret；PayPal 不用，留空）"
        t.string :webhook_id, comment: "非祕密識別（PayPal webhook_id，驗簽輸入之一；Airwallex 不用）"
        t.string :api_secret_fingerprint, limit: 16,
                 comment: "SHA-256 前 16 hex（37 §6.3：UI 只顯示指紋）；祕密未設時 NULL"
        t.string :webhook_secret_fingerprint, limit: 16, comment: "同上"
        t.json :enabled_methods, null: false, default: -> { "(json_array())" },
               comment: "商家啟用的 method code 白名單（86 詳情頁逐方法 toggle 的落點；空陣列＝尚未挑選）"
        t.timestamps
        t.index [ :shop_id, :provider ], unique: true, name: "uq_shop_payment_providers_provider"
        t.index [ :shop_id, :id ], unique: true, name: "uq_shop_payment_providers_tenant_id"
      end
    end

    # 外鍵補在建表後：strong_migrations 對 create_table 內聯 FK 與既有大表加 FK 的
    # 鎖行為有別；shops 是小表、本表是新空表 ⇒ 即刻校驗安全。
    unless foreign_key_exists?(:shop_payment_providers, :shops)
      safety_assured do
        add_foreign_key :shop_payment_providers, :shops, name: "fk_shop_payment_providers_shop"
      end
    end
  end
end
