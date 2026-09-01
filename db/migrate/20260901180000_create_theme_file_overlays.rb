# frozen_string_literal: true

# 步 16e1：code editor 的主題檔案 DB 覆寫層（D77 架構補完：storage 目錄不可變
# ——匯入主題內容定址、first_party 隨版本部署——一切編輯走 DB overlay）。
#
# 🔴 守衛粒度＝語句（91 §3.52 家族）：首輪 add_foreign_key 被 strong_migrations
# 擋下後 create_table 已落地，塊級守衛會吞掉 FK ⇒ 逐語句 guard＋safety_assured。
class CreateThemeFileOverlays < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:theme_file_overlays)
      create_table :theme_file_overlays, comment: "主題檔案 DB 覆寫層（code editor）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :theme_id, null: false
        t.string :path, null: false, limit: 512, comment: "主題相對路徑（top_dir/檔名）"
        t.integer :lock_version, null: false, default: 0
        # mediumtext（16MB 型上限）；業務上限由 limits theme_editor 逐型把守。
        t.text :content, null: false, size: :medium
        t.timestamps
        t.index [ :shop_id, :theme_id, :path ], unique: true, name: "uq_theme_file_overlays_path"
        t.index [ :shop_id, :id ], unique: true, name: "uq_theme_file_overlays_tenant_id"
      end
    end

    if table_exists?(:theme_file_overlays) &&
       foreign_keys(:theme_file_overlays).none? { |fk| fk.to_table == "themes" }
      safety_assured { add_foreign_key :theme_file_overlays, :themes }
    end
  end
end
