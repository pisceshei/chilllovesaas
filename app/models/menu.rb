# frozen_string_literal: true

# 前台導覽選單（本尊 LinkList；包 30／D77；表＝M0 既建）。
class Menu < ApplicationRecord
  acts_as_tenant :shop

  has_many :menu_items, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :handle, presence: true, length: { maximum: 255 },
                     uniqueness: { scope: :shop_id, case_sensitive: false }
end
