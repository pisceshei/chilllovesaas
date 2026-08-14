# Publishable 與 Publication 的發布關聯（對應本尊的 `ResourcePublication`）。
#
# 命名為 `resource_*` 而非 `product_*`：它是**多型**的——本尊的 Publishable 介面由
# Product、Collection、ProductVariant 三者實作（82 §0.2），叫 product_* 會讓後兩者
# 看起來像硬塞進來的。
#
# 🔴 `published_at` 的三種語義（88 §2.2）：
#   - NULL        ⇒ 尚未發布到本管道
#   - 過去時間    ⇒ 已發布
#   - **未來時間** ⇒ **排程發布**（future publishing）
#
# @see docs/specs/88-publication-model.md
class ResourcePublication < ApplicationRecord
  PUBLISHABLE_TYPES = %w[Product Collection ProductVariant].freeze

  acts_as_tenant :shop

  belongs_to :publication
  belongs_to :publishable, polymorphic: true

  validates :publishable_type, inclusion: { in: PUBLISHABLE_TYPES }
  validates :publishable_id, uniqueness: {
    scope: %i[shop_id publication_id publishable_type]
  }

  validate :future_publishing_supported_by_channel
  validate :variant_cannot_be_scheduled

  # 此關聯在指定時點是否算「已上架到本管道」。
  #
  # 🔴 注意這只是**三層 AND 的第二層**——完整的上架判定還要加上 catalog 條件（88 §1）。
  # 只用這個方法當「商品是否可購買」會漏掉市場目錄那一層。
  #
  # @param at [Time] 判定時點，預設現在
  # @return [Boolean] 已發布且發布時間已到時為 true
  # @note 副作用：無。
  # @see docs/specs/88-publication-model.md §1
  def published?(at: Time.current)
    published_at.present? && published_at <= at
  end

  private

  # 本尊：Shop 管道不支援排程發布（82 §0.2）——能力旗標在 publication 上。
  def future_publishing_supported_by_channel
    return if published_at.nil? || published_at <= Time.current
    return if publication.nil? || publication.supports_future_publishing

    errors.add(:published_at, "此銷售管道不支援排程發布")
  end

  # 本尊：不能為單一 variant 排程發布（82 §0.2）。
  def variant_cannot_be_scheduled
    return unless publishable_type == "ProductVariant"
    return if published_at.nil? || published_at <= Time.current

    errors.add(:published_at, "不支援為單一子類選項排程發布")
  end
end
