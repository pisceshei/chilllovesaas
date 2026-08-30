# frozen_string_literal: true

# 市場（docs/research/29 §1.1；包 32）。
#
# ①這是什麼：以 conditions 決定買家命中的市場實體；本尊 Markets 導航區的資料層。
# ②值域（實測 2026-08-31，store chill-love-u5q5mnzq）：
#   - status：New market 表單原生 select 恰兩值 `DRAFT`／`ACTIVE`（DOM 收割）；存小寫，序列化層升大寫。
#   - market_type：Market conditions 的條件類型恰四值 Regions／POS locations／Company locations／
#     Channels（popover 逐字），加上「無條件市場」＝`none`（29 §1.1 MarketType 五值）。
# ③父子關係：**推導不是欄位**（29 §1.5(a)）——`derived_parent_market_id` 是物化快取，
#   conditions 變更時重算（重算器隨 lineage 消費者包；v1 單市場恆 NULL）。
# ④跨功能影響：url_prefix 的 region 來源（Markets::UrlPrefix）；hreflang 逐國展開
#   （Markets::HreflangCodes）；catalogs／web_presences 沿 lineage 累加（limits
#   `market.inheritance_additive`）；shops.catalog_version 由市場變動 bump（步 2 快取 key）。
class Market < ApplicationRecord
  STATUSES = %w[active draft].freeze
  MARKET_TYPES = %w[region company_location location channel none].freeze

  acts_as_tenant :shop

  has_many :market_regions, dependent: :delete_all
  has_many :market_web_presences, dependent: :destroy

  validates :name, presence: true
  validates :handle, presence: true, uniqueness: { scope: :shop_id }
  validates :status, inclusion: { in: STATUSES }
  validates :market_type, inclusion: { in: MARKET_TYPES }
  validate :primary_must_be_region
  validate :activation_must_not_overlap_regions

  before_destroy :forbid_destroying_primary

  scope :active, -> { where(status: "active") }

  # @return [Array<String>] 本市場的 region 國碼（大寫；region 型以外恆空）
  def region_country_codes
    market_regions.order(:country_code).pluck(:country_code)
  end

  private

  # primary market 恰含一個國家（29 §1.1）⇒ 它必然是 region 型；單國約束在 MarketRegion 擋。
  def primary_must_be_region
    return unless is_primary && market_type != "region"

    errors.add(:market_type, "primary market 必須是 region 型（29 §1.1：恰含一個國家）")
  end

  # 29 §1.1：「同一組 regions 只能屬於一個 active market（不可重疊；draft 可）」。
  # MarketRegion 擋「往 active 市場加重疊國家」；這裡擋另一半——draft 轉 active 時帶著重疊國家。
  def activation_must_not_overlap_regions
    return unless status == "active" && persisted? && status_changed?

    overlapping = MarketRegion.where(shop_id:, country_code: region_country_codes)
                              .where.not(market_id: id)
                              .joins(:market).merge(Market.active)
    return unless overlapping.exists?

    errors.add(:status, "region 與其他 active 市場重疊（29 §1.1：active 不可重疊）")
  end

  def forbid_destroying_primary
    return unless is_primary

    errors.add(:base, "primary market 不可刪除（29 §1.1）")
    throw :abort
  end
end
