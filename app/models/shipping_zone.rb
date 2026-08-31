# frozen_string_literal: true

# 運送區域（15 §F2.2；85 §4 實測正典）。
#
# ①這是什麼：設定檔內的國家集合，費率掛在 zone 上。country_codes＝ISO 3166-1
#   alpha-2 大寫陣列（美國州級粒度 85 §4 記過，v1 只做國級——V 登記）。
# ②🔴 同一設定檔內國家不得跨 zone 重疊：本尊 UI 以「國家在 zone 間搬移」隱含此
#   不變量；RateResolver 靠它才能把「國家→zone」當函數用（多命中＝資料壞）。
# ③zone ≠ market（limits shipping.zone_requires_market；85 §2 警示橫幅＋§4 建立面
#   只列 market 內國家）：guard 在 RateResolver 的 :not_sellable 分支，不在本 model
#   ——歷史資料可以違反（本尊同樣只警示不阻擋），賣不賣得掉是解析時判的。
class ShippingZone < ApplicationRecord
  COUNTRY_CODE_FORMAT = /\A[A-Z]{2}\z/

  acts_as_tenant :shop

  belongs_to :shipping_profile
  has_many :shipping_rates, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: %i[shop_id shipping_profile_id] }
  validate :country_codes_shape
  validate :no_overlap_within_profile

  # @param country_code [String] 大寫 ISO alpha-2
  def covers?(country_code)
    country_codes.include?(country_code)
  end

  private

  def country_codes_shape
    unless country_codes.is_a?(Array) && country_codes.all? { |c| c.is_a?(String) && c.match?(COUNTRY_CODE_FORMAT) }
      errors.add(:country_codes, "必須是大寫 ISO 3166-1 alpha-2 字串陣列")
      return
    end
    errors.add(:country_codes, "國家重複") if country_codes.uniq.size != country_codes.size
  end

  def no_overlap_within_profile
    return if country_codes.blank? || shipping_profile_id.nil?

    siblings = ShippingZone.where(shop_id:, shipping_profile_id:).where.not(id:)
    taken = siblings.pluck(:country_codes).flatten
    overlap = country_codes & taken
    return if overlap.empty?

    errors.add(:country_codes, "與同設定檔其他 zone 重疊：#{overlap.join(', ')}")
  end
end
