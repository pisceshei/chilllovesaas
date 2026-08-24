# frozen_string_literal: true

# 檔案引用（第 25 包立表；寫入端＝第 27 包 media 附掛）。
# (file, owner) 恰一列＝引用計數的唯一來源（uq_file_usages_file_owner）。
class FileUsage < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :stored_file, foreign_key: :file_id, inverse_of: :file_usages

  validates :owner_type, presence: true
  validates :owner_id, presence: true
  validates :file_id, uniqueness: { scope: [ :shop_id, :owner_type, :owner_id ] }
end
