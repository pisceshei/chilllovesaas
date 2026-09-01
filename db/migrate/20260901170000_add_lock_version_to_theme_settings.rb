# frozen_string_literal: true

# 步 16d2：佈景設定樂觀鎖底版（與 templates.lock_version 同語義——editor
# 帶 client 底版顯式比對；AR 原生鎖保並發寫者雙層）。
class AddLockVersionToThemeSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :theme_settings, :lock_version, :integer, default: 0, null: false
  end
end
