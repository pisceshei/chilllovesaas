# frozen_string_literal: true

module Types
  # PSP provider 的租戶側設定（G6-3 前半）。
  #
  # 🔴 **沒有任何祕密欄**（37 §6.3「UI 永不回傳明文」）：`api_secret`／`webhook_secret`
  # 不存在於本 type，只出 SHA-256 前 16 hex 指紋——**這不是漏做，是防線**。
  class ShopPaymentProviderType < Types::BaseObject
    graphql_name "ShopPaymentProvider"
    description "PSP provider 的租戶側憑證狀態與偏好（祕密欄永不回讀，只回指紋）。"

    field :id, ID, null: false
    field :provider, String, null: false, description: "pack 代碼（airwallex／paypal…＝psp_packs 字典）。"
    field :environment, String, null: false, description: "sandbox|production。"
    field :status, String, null: false, description: "inactive|active（activation 狀態機隨 G6-3）。"
    field :client_id, String, null: true, description: "非祕密識別；可回讀。"
    field :webhook_id, String, null: true, description: "非祕密識別（PayPal webhook_id）；可回讀。"
    field :api_secret_fingerprint, String, null: true,
      description: "已儲存祕密的 SHA-256 前 16 hex；未設定＝null（37 §6.3）。"
    field :webhook_secret_fingerprint, String, null: true, description: "同上。"
    field :enabled_methods, [ String ], null: false,
      description: "商家 method 白名單（結帳顯示＝白名單 ∩ PSP capability，15-F4.2）。"
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
