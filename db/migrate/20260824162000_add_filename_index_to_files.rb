# frozen_string_literal: true

# 第 25 包：檔名以店為界索引（12 §C.7 業務規則；91 §3 曾登記缺口）。
#
# ①這是什麼：`files(shop_id, filename)` 非唯一索引——append_uuid 撞名解法
#   （limits `media.duplicate_resolution_modes`）要以店為界查同名檔，沒有索引
#   ＝每次 fileCreate 全表掃。
# ②為什麼非唯一：append_uuid 語義下同名檔本來就允許並存（改名後綴 UUID）；
#   唯一的是 storage_key（既有 uq_files_storage_key）。
class AddFilenameIndexToFiles < ActiveRecord::Migration[8.1]
  def change
    add_index :files, [ :shop_id, :filename ], name: "ix_files_filename"
  end
end
