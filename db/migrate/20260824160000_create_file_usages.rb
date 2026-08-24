# frozen_string_literal: true

# 第 25 包（整合規格 §1.4／§4-25）：檔案引用計數表。
#
# ①這是什麼：file × 擁有者（media／theme setting／…）的引用關聯——「這個檔被幾個
#   商品用」與檔案庫刪除確認（第 28 包）的同一份計數來源（排程 §四.28：兩套計數＝事故）。
# ②具體行為：附掛時 create、卸載時 delete（第 27 包 productCreateMedia 起寫入；
#   本包只立表＋model）。同一 (file, owner) 恰一列（唯一鍵防重複計數）。
# ③多租戶：業務資料表，帶 shop_id 且複合索引以 shop_id 開頭（鐵律 2；
#   scripts/check-tenant-isolation.rb 規則 1 掃）。
# ④跨功能影響：第 27 包（media 附掛寫入）、第 28 包（刪除確認「哪些檔一併刪、
#   共用檔保留」讀本表）、fileDelete 的 in-use 擋刪。
class CreateFileUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :file_usages, comment: "檔案引用（file × owner 恰一列；引用計數的唯一來源）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :file_id, null: false
      t.string :owner_type, limit: 64, null: false
      t.bigint :owner_id, null: false
      t.timestamps

      t.index [ :shop_id, :id ], unique: true, name: "uq_file_usages_tenant_id"
      t.index [ :shop_id, :file_id, :owner_type, :owner_id ], unique: true, name: "uq_file_usages_file_owner"
      t.index [ :shop_id, :owner_type, :owner_id ], name: "ix_file_usages_owner"
    end
    # 新建空表加 FK：strong_migrations 的鎖表顧慮不適用（零列）；M0 同型先例
    safety_assured do
      add_foreign_key :file_usages, :shops, name: "fk_file_usages_shop"
      add_foreign_key :file_usages, :files, column: [ :shop_id, :file_id ],
                      primary_key: [ :shop_id, :id ], name: "fk_file_usages_file_id"
    end
  end
end
