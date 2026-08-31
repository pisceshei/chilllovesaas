# frozen_string_literal: true

# 運送設定檔（15 §F2.1；85 §1–§2 實測正典）。
#
# ①這是什麼：費率的分組容器——General 恰一個＋自訂 ≤99（limits shipping.*）。
# ②🔴 General＝**補集**：商品不掛任何自訂檔（products.shipping_profile_id IS NULL）
#   就屬 General（85 §2 逐字「All products not in other profiles」＋建第二檔後
#   措辭變「All other products」）。⇒ General 不需要、也不得有商品正向關聯；
#   `products` 關聯只對自訂檔有意義。
# ③刪除語義（85 §5.4 對話逐字）：刪自訂檔 ⇒ 商品回落 General——由 FK
#   `on_delete: :nullify` 承載，**不是** dependent 回呼（批次 SQL 也不會漏）。
# ④跨功能影響：RateResolver 的 participant 分組鍵；checkout 的 split shipping
#   （85 §5.3：多檔 ⇒ 多 shipment）；未來 admin 運送設定頁的聚合根。
class ShippingProfile < ApplicationRecord
  acts_as_tenant :shop

  has_many :shipping_zones, dependent: :destroy
  # 自訂檔的商品集合；General 檔此關聯恆空（補集不落表——見②）。
  has_many :products, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :shop_id }
  validate :single_general_per_shop
  before_destroy :forbid_destroying_general

  scope :general, -> { where(general: true) }

  private

  # General 每店恰一（limits shipping.general_profiles: 1）。
  def single_general_per_shop
    return unless general
    return unless ShippingProfile.where(shop_id:, general: true).where.not(id:).exists?

    errors.add(:general, "General 設定檔每店只能有一個（limits shipping.general_profiles）")
  end

  # General 是補集的承載者：刪掉它，「回落 General」語義（85 §5.4）就沒有落點。
  def forbid_destroying_general
    return unless general

    errors.add(:base, "General 設定檔不可刪除")
    throw :abort
  end
end
