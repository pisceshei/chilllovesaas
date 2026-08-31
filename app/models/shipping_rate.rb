# frozen_string_literal: true

# 運費費率（15 §F2.1；85 §3 實測正典）。
#
# ①這是什麼：zone 下的一個可選運送選項列。85 §3 的 2026 費率編輯器 Rate type
#   原生 select 恰四值 `flat_rate`／`carrier`／`order_amount`／`weight`——我方內部名
#   對映：flat＝flat_rate（schema 既有預設）；carrier 隨 58 物流商對接包，本包
#   RateResolver 不產出 carrier 選項（enum 先收全值域，鐵律 12.4②）。
# ②條件值域：order_amount 型＝[minimum_order_cents, maximum_order_cents] 級距列
#   （85 §3：分級列 Minimum／Maximum「No limit」＝NULL；🔴 雙端**含**——語義見
#   within_band? 註釋）；weight 型同構取 [minimum_weight_grams, maximum_weight_grams]。
#   **滿 X 免運＝price 0 的 order_amount 級距列**（85 §2 General Standard
#   「Free $70.00 and up」的資料形）。
# ③🔴 幣別：費率自帶 currency（85 §3「Amounts set in US dollars」＋免運門檻以
#   **費率自身幣別**比較——85 §5.2 的 $62.73 否證了 presentment 數字面比較）。
#   v1 單店幣：RateResolver 只考慮 currency＝結帳幣的費率（換匯隨 markets 幣別包）。
# ④transit：秒制區間（85 §3 base64 JSON {min,max}）；雙 NULL＝None。
class ShippingRate < ApplicationRecord
  RATE_TYPES = %w[flat order_amount weight carrier].freeze

  acts_as_tenant :shop

  belongs_to :shipping_zone

  validates :name, presence: true
  validates :rate_type, inclusion: { in: RATE_TYPES }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validate :condition_band_coherent
  validate :transit_band_coherent

  scope :active, -> { where(active: true) }

  # 條件是否命中（RateResolver 的判準；basis 一律 Integer——鐵律 3 無隱式轉型）。
  #
  # @param order_subtotal_cents [Integer] participant 行小計（基數之爭見 85 §5.3 V）
  # @param weight_grams [Integer] participant 總重（含店預設包裹重，加項在解析器）
  def condition_holds?(order_subtotal_cents:, weight_grams:)
    case rate_type
    when "flat" then true
    when "order_amount" then within_band?(order_subtotal_cents, minimum_order_cents, maximum_order_cents)
    when "weight" then within_band?(weight_grams, minimum_weight_grams, maximum_weight_grams)
    else false # carrier：本包不產出（58 對接包接手）
    end
  end

  private

  # [min, max]——🔴 **雙端含**：15 F2.1 算例 4 的 2000g 必須落「1–2kg」級距（上界含）；
  # 85 §3 分級列相鄰列共享邊界值（Minimum＝上一列 Maximum）⇒ 邊界值同名雙命中，
  # 由 RateResolver 的「同名取最便宜」收斂——「滿 X 免運」在門檻值上因此正確取免運側
  # （85 §2「Free $70.00 and up」：7000 同時命中付費列與免運列 ⇒ 0）。
  def within_band?(value, min, max)
    (min.nil? || value >= min) && (max.nil? || value <= max)
  end

  def condition_band_coherent
    if rate_type == "order_amount" && minimum_order_cents && maximum_order_cents &&
       minimum_order_cents > maximum_order_cents
      errors.add(:maximum_order_cents, "上界不得小於下界")
    end
    if rate_type == "weight" && minimum_weight_grams && maximum_weight_grams &&
       minimum_weight_grams > maximum_weight_grams
      errors.add(:maximum_weight_grams, "上界不得小於下界")
    end
  end

  def transit_band_coherent
    if min_transit_seconds.nil? ^ max_transit_seconds.nil?
      errors.add(:max_transit_seconds, "transit 區間必須成對（None＝兩者皆空）")
    elsif min_transit_seconds && min_transit_seconds > max_transit_seconds
      errors.add(:max_transit_seconds, "transit 上界必須不小於下界")
    end
  end
end
