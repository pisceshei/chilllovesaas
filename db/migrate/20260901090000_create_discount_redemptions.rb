# frozen_string_literal: true

# G6 步 9a（折扣引擎·資料層補完；17-F3）：
# ①discount_redemptions——once_per_customer 的唯一索引硬保證（17-F3.2；
#   customer_key＝customer_id 或正規化 email hash——大小寫繞不過）。
# ②checkouts.discount_code——結帳輸入的碼快照（正規化 upcase+trim 後存）。
# 🔴 discounts／discount_applications＝M0 既有表採用（91 §3.50 規則；
#   守衛粒度＝語句——8a FK 事故家族）。
class CreateDiscountRedemptions < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:discount_redemptions)
      create_table :discount_redemptions,
                   comment: "折扣兌換帳（once_per_customer 唯一索引硬保證；17-F3）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :discount_id, null: false
        t.string :customer_key, limit: 128, null: false,
                 comment: "customer_id 或正規化 email 的 sha256（17-F3：正規化後再 hash）"
        t.bigint :order_id, null: false
        t.datetime :created_at, null: false

        t.index [ :shop_id, :discount_id, :customer_key ],
                unique: true, name: "uq_discount_redemptions_customer"
        t.index [ :shop_id, :order_id ], name: "ix_discount_redemptions_order"
      end
    end

    fk_missing = table_exists?(:discount_redemptions) &&
                 foreign_keys(:discount_redemptions).none? { |fk| fk.to_table == "discounts" }
    if fk_missing
      safety_assured { add_foreign_key :discount_redemptions, :discounts }
    end

    unless column_exists?(:checkouts, :discount_code)
      add_column :checkouts, :discount_code, :string, limit: 64,
                 comment: "結帳輸入的折扣碼（正規化後快照；NULL＝未輸入）"
    end

    unless column_exists?(:checkouts, :discount_applications_snapshot)
      add_column :checkouts, :discount_applications_snapshot, :json,
                 comment: "求值結果快照 [{discount_id,title,class,amount_cents,allocations}]（成單時回放成 discount_applications 列）"
    end
  end
end
