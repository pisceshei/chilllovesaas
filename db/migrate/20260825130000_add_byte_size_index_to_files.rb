# frozen_string_literal: true

# D48（檔案庫排序跟本尊）：`files(sortKey: ORIGINAL_UPLOAD_SIZE)` 的 keyset 索引。
#
# 🔴 為什麼只有 `byte_size` 需要加索引、`filename` 不用：
#   keyset 分頁的條件是 `(排序鍵, id)` 的字典序，所以索引要能覆蓋這兩欄。
#   `filename` 已有 `ix_files_filename (shop_id, filename)`——InnoDB 的二級索引
#   **隱含帶上主鍵**，等效於 `(shop_id, filename, id)`，剛好夠用。
#   `byte_size` 沒有任何索引，缺它就是每次排序全表掃。
class AddByteSizeIndexToFiles < ActiveRecord::Migration[8.1]
  def change
    add_index :files, [ :shop_id, :byte_size ], name: "ix_files_byte_size"
  end
end
