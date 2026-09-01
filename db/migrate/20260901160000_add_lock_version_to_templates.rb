# frozen_string_literal: true

# G4 步 16b（14 §F3）：templates 樂觀鎖——兩個 staff 同時編輯同一模板，
# 後存者收衝突（editor 提示重載），不靜默互蓋。
class AddLockVersionToTemplates < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:templates, :lock_version)
      add_column :templates, :lock_version, :integer, default: 0, null: false
    end
  end
end
