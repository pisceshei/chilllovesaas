# frozen_string_literal: true

# 購物車資料層（specs/15 F1；blueprint 03 B.1）。
# 裁定重點：DB-backed（非 session blob）；token 進簽名 cookie `_cl_buyer`
# （host-only——坑：設在主網域會跨店共享）；行合併鍵唯一索引以 shop_id 開頭
# （鐵律 2）；變體刪除 ⇒ 行 CASCADE（F1 ⚠️坑 的裁定選項）。
class CreateCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :carts, comment: "買家購物車（specs/15 F1；token 進 _cl_buyer 簽名 cookie）" do |t|
      t.bigint :shop_id, null: false
      t.string :token, limit: 64, null: false, comment: "cookie 攜帶的識別（SecureRandom；不可枚舉）"
      t.text :note, comment: "Ajax cart 契約的 note（clear 不清除——官方語義）"
      t.json :attributes_json, null: false, comment: "Ajax cart 契約的 attributes（clear 不清除）"
      t.timestamps

      t.index %i[shop_id token], unique: true, name: "uq_carts_token"
      t.index %i[shop_id id], unique: true, name: "uq_carts_tenant_id"
      t.index %i[shop_id updated_at], name: "ix_carts_updated_at", comment: "90 天未動 purge job 的掃描鍵（F1 #4）"
    end
    # 新建空表上的 FK：無既有列可驗（倉內慣例同 price_lists 遷移）。
    safety_assured { add_foreign_key :carts, :shops, name: "fk_carts_shop" }

    create_table :cart_line_items, comment: "購物車行（specs/15 F1 #1/#5；merge_key_hash 承重合併）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :cart_id, null: false
      t.bigint :product_variant_id, null: false
      t.integer :quantity, null: false, default: 1
      t.json :properties, null: false, comment: "客製屬性（合併鍵承重輸入；同 variant 不同屬性＝合法多行）"
      t.bigint :selling_plan_id, comment: "訂閱方案（功能未落地；合併鍵承重輸入，恆 NULL）"
      t.bigint :unit_price_cents, null: false, comment: "加入當下價（合併鍵承重輸入；顯示用即時價另查——F1 #3）"
      t.bigint :parent_id, comment: "bundle 父行（Q-44 未決前暫定入鍵；v1 恆 NULL）"
      t.string :merge_key_hash, limit: 64, null: false,
               comment: "SHA-256(variant＋properties＋selling_plan＋單價＋parent)——全同才併行"
      t.timestamps

      t.index %i[shop_id cart_id merge_key_hash], unique: true, name: "uq_cart_line_items_merge_key"
      t.index %i[shop_id cart_id], name: "ix_cart_line_items_cart"
      t.index %i[shop_id product_variant_id], name: "ix_cart_line_items_variant"
      t.index %i[shop_id id], unique: true, name: "uq_cart_line_items_tenant_id"
    end
    safety_assured do
      add_foreign_key :cart_line_items, :carts, column: :cart_id,
                                                name: "fk_cart_line_items_cart", on_delete: :cascade
      # 變體刪除 ⇒ 行 CASCADE（F1 ⚠️坑 的裁定選項：不留殘行）。
      add_foreign_key :cart_line_items, :product_variants, column: :product_variant_id,
                                                           name: "fk_cart_line_items_variant", on_delete: :cascade
    end
  end
end
