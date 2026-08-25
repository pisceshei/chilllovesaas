# frozen_string_literal: true

# 第 6 包：url_redirects（62 §B.5 的表形狀）。
#
# ①這是什麼：路徑級 301／410 重導表。第一個寫入者＝handle 變更掛鉤（本包）；
#   讀取者＝第 36 包的 301 引擎（掛在前台 404/410 handler 之前）與後台自訂重導管理。
# ②🔴 **路徑存正規形（無 locale 前綴）**：62 §F.3——路由層命中 404 前先剝前綴
#   → 查表 → 把前綴加回去再 301（`/en/products/舊` → `/en/products/新`）。
#   存帶前綴的路徑＝每語言一列＝新增語言時全表補列。
# ③🔴 **舊 handle 永不回收**（62 §F.3）：唯一性檢查因此要比對本表——
#   `Catalog::HandleChange.path_reserved?` 是唯一判準入口。
class CreateUrlRedirects < ActiveRecord::Migration[8.1]
  def change
    create_table :url_redirects, comment: "路徑級重導（62 §B.5）；from/to 為無前綴正規路徑" do |t|
      t.bigint :shop_id, null: false
      t.string :from_path, limit: 512, null: false
      t.string :to_path, limit: 512, null: false
      t.integer :status_code, null: false, default: 301
      t.string :source, limit: 32, null: false
      t.timestamps

      # 鐵律 2：複合索引以 shop_id 開頭。
      t.index [ :shop_id, :from_path ], unique: true, name: "uq_url_redirects_from_path"
      # 鏈坍縮要按 to_path 反查（A→B 存在、B 改名 C 時把 A→B 改成 A→C）。
      t.index [ :shop_id, :to_path ], name: "ix_url_redirects_to_path"
    end
  end
end
