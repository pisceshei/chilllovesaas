# frozen_string_literal: true

# 市場的 region condition（docs/research/29 §1.4 `market_regions`）。
#
# 兩條 29 §1.1 的應用層不變量都在這裡擋（DB 唯一索引只擋「同市場重複國家」）：
#   - **active 市場的國家不得重疊**（draft 可以重疊——所以不能做成 DB 唯一索引）；
#   - **primary market 恰含一個國家**（第二個國家一律拒絕）。
class MarketRegion < ApplicationRecord
  COUNTRY_CODE_FORMAT = /\A[A-Z]{2}\z/

  acts_as_tenant :shop

  # touch：region 是繼承解析的輸入 ⇒ bump markets.updated_at（cache stamp，limits
  # `catalog_flow.cache_stamp_sources` 的 markets.updated_at 條目；63 §G.5）。
  belongs_to :market, touch: true

  validates :country_code, presence: true, format: { with: COUNTRY_CODE_FORMAT },
                           uniqueness: { scope: %i[shop_id market_id] }
  validate :no_overlap_between_active_markets
  validate :primary_market_single_country

  before_validation { self.country_code = country_code.to_s.strip.upcase if country_code.present? }

  private

  def no_overlap_between_active_markets
    return if market.nil? || market.status != "active" || country_code.blank?

    taken = self.class.where(shop_id:, country_code:).where.not(market_id:)
                .joins(:market).merge(Market.active)
    return unless taken.exists?

    errors.add(:country_code, "已屬於另一個 active 市場（29 §1.1：active 不可重疊）")
  end

  def primary_market_single_country
    return unless market&.is_primary

    siblings = self.class.where(shop_id:, market_id:).where.not(id:)
    return unless siblings.exists?

    errors.add(:base, "primary market 恰含一個國家（29 §1.1），不得再加")
  end
end
