# frozen_string_literal: true

# T13：商店政策（官方 Settings › Policies：Return／Privacy／Terms of service／Shipping／Legal notice／Subscription，
# 另有 contact-information 路徑——help.shopify.com/en/manual/checkout-settings/refund-privacy-tos，取證 2026-09-05）。
# Liquid：`shop.policies`／`shop.privacy_policy` 等五個具名（objects/shop）、`policy` 物件（body／id／title／url）。
# 前台 `/policies/{kind}` 本尊形（hoko.vip 2026-09-05）：只有設了內容的政策存在（privacy-policy 200），其餘 404。
# kind＝URL handle（固定集合，模型 KINDS）；title＝平台依語言給定的名稱（本尊不可改名；先落欄位，字典＝A1 admin 包）；
# body＝HTML（本尊 rte 內容，Shopify 範本產生或商家自填）。
class CreateShopPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_policies, comment: "商店政策（Settings › Policies；前台 /policies/{kind}）" do |t|
      t.bigint :shop_id, null: false
      t.string :kind, limit: 32, null: false,
               comment: "privacy-policy / refund-policy / terms-of-service / shipping-policy / subscription-policy / legal-notice / contact-information（＝URL handle）"
      t.string :title, null: false, comment: "平台依語言給定的政策名稱（本尊不可改名）"
      t.text :body, size: :medium, comment: "HTML；NULL／空＝未設定 ⇒ 前台 404、shop.*_policy 為 nil"
      t.timestamps
    end
    add_index :shop_policies, [ :shop_id, :kind ], unique: true, name: "uq_shop_policies_kind"
  end
end
