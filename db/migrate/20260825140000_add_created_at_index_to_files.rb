# frozen_string_literal: true

# D48 對抗審查 S2：**預設排序鍵**沒有索引。
#
# 🔴 前一支（`20260825130000`）的註釋寫「為什麼只有 `byte_size` 需要加索引」——
#   那句窮舉漏了第三個鍵，而且漏的正是 `files(sortKey:)` 不指定時用的 `created_at`
#   （`QueryType#file_order` 的 `else` 分支）。`ix_files_status_created_at` 是
#   `(shop_id, status, created_at)`，沒有 status 等值條件時**前綴對不上**，派不上用場。
#
# 審查方在 50,000 檔的複刻資料上量到（MySQL 8.4.9，ANALYZE 後 EXPLAIN ANALYZE）：
#   - 不給 sortKey（＝CREATED_AT desc，也就是使用者第一次進檔案庫看到的那一頁）：
#     `Sort: files.created_at DESC …` 讀滿 50,000 列再排序，**95.2 ms**
#   - `sortKey: FILENAME` 走 `ix_files_filename`：**0.143 ms**
#   - `sortKey: ORIGINAL_UPLOAD_SIZE` 走 `ix_files_byte_size`：**0.098 ms**
#   ⇒ 預設鍵比兩個新鍵慢約 670 倍，而且是唯一隨店內檔數線性成長的一條。
#   同輪新增的「載入更多」把「一次 filesort」變成「每翻一頁一次 filesort」。
#
# 🔴 `(shop_id, created_at)` 就夠：InnoDB 二級索引隱含帶主鍵，等效
#   `(shop_id, created_at, id)`，正好覆蓋 keyset 的 `(排序鍵, id)` 字典序——
#   與 byte_size 同理。
class AddCreatedAtIndexToFiles < ActiveRecord::Migration[8.1]
  def change
    add_index :files, [ :shop_id, :created_at ], name: "ix_files_created_at"
  end
end
