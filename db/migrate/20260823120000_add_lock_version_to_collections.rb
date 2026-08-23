# frozen_string_literal: true

# 商品系列的全樹樂觀鎖（ML-3；63 §A.4 與商品同一條紀律）。
#
# 🔴 缺它的後果與商品一模一樣：兩個人同時編輯同一個系列，「最後寫入者贏」會**靜默**蓋掉
# 另一個人的變更（含譯文）。SaveBar 的儲存必須能偵測到並回 STALE_OBJECT。
class AddLockVersionToCollections < ActiveRecord::Migration[8.1]
  def change
    add_column :collections, :lock_version, :integer, default: 0, null: false
  end
end
