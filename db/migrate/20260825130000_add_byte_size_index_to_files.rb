# frozen_string_literal: true

# D48（檔案庫排序跟本尊）：`files(sortKey: ORIGINAL_UPLOAD_SIZE)` 的 keyset 索引。
#
# 三個排序鍵各自的索引落點（🔴 **逐鍵列舉**，不寫「只有 X 需要」那種窮舉句）：
#   - `filename`   → 已有 `ix_files_filename (shop_id, filename)`。InnoDB 二級索引
#                    隱含帶主鍵，等效 `(shop_id, filename, id)`，剛好覆蓋 keyset。
#   - `byte_size`  → **本支新增**（原本沒有任何索引，缺它就是每次排序全表掃）。
#   - `created_at` → 也沒有可用索引（`ix_files_status_created_at` 前綴是 status，
#                    沒有 status 條件時對不上）。⚠️ **本支漏了它**，
#                    由 `20260825140000_add_created_at_index_to_files` 補上——
#                    原註釋寫成「只有 byte_size 需要」是被對抗審查證偽的窮舉句
#                    （鐵律 20.2③：全稱句要嘛列舉要嘛附查法）。
class AddByteSizeIndexToFiles < ActiveRecord::Migration[8.1]
  def change
    add_index :files, [ :shop_id, :byte_size ], name: "ix_files_byte_size"
  end
end
