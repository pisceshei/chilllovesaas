# frozen_string_literal: true

# G3 步 15a（99 §5）：
# ①themes.content_checksum——匯入主題的內容定址鍵（storage/themes/{checksum}
#   不可變目錄；🔴 AST cache 跨租戶汙染的根治前置——同鍵恆同內容）。
# ②theme_import_reports——匯入結果與相容掃描報告（成功/失敗都留痕）。
class AddThemeImportSupport < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:themes, :content_checksum)
      add_column :themes, :content_checksum, :string, limit: 64,
                 comment: "匯入主題的內容 SHA-256（storage/themes/{checksum}；first_party 為 NULL）"
    end

    unless table_exists?(:theme_import_reports)
      create_table :theme_import_reports, comment: "主題 zip 匯入報告（99 §5；含相容掃描）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :theme_id, comment: "成功建立的主題；失敗為 NULL"
        t.string :zip_filename, null: false
        t.string :status, limit: 12, null: false, comment: "ok / failed"
        t.string :error_code, limit: 40, comment: "失敗碼（INVALID_ZIP 等——對齊官方碼形）"
        t.json :report, null: false, comment: "相容掃描（檔數/警告/未知 tag/Liquid 錯誤）"
        t.datetime :created_at, null: false

        t.index [ :shop_id, :created_at ], name: "ix_theme_import_reports_created"
        t.index [ :shop_id, :id ], unique: true, name: "uq_theme_import_reports_tenant_id"
      end
    end
  end
end
