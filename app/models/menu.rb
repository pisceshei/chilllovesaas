# frozen_string_literal: true

# 前台導覽選單（本尊 LinkList；包 30／D77；表＝M0 既建）。
class Menu < ApplicationRecord
  # 預設選單（98 §4 實測三個：main-menu／footer／customer account main menu）——
  # 官方語義：handle 不可改、不可刪。footer 的 handle 本尊值未逐字取證 ⇒ 兩形都收。
  DEFAULT_HANDLES = %w[main-menu footer footer-menu customer-account-main-menu].freeze

  acts_as_tenant :shop

  has_many :menu_items, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :handle, presence: true, length: { maximum: 255 },
                     uniqueness: { scope: :shop_id, case_sensitive: false }
end
