# frozen_string_literal: true

# 商品媒體 metadata（第 25 包薄版；表＝`media`，本體在物件儲存）。
#
# ①這是什麼：商品 × 媒體的一列（position 排序、可掛 variant）。
# ②🔴 已知矛盾（第 24 包登記）：schema `status` default `"ready"` 與四態起點
#   `uploaded` 不符——**第 26 包 migration 修**（整合規格 §4-26）；本 model 先以
#   limits 四態驗證，寫入端（第 27 包 productCreateMedia）落地前不受影響。
# ③跨功能影響：第 27 包媒體卡 mutations、`uq_media_product_id_position` 是 unique
#   ——重排要兩階段落位（整合規格 §1.4；variant_sync `apply_matched!` 同型）。
class Media < ApplicationRecord
  self.table_name = "media"

  STATUSES = Limits.enum(:media, :statuses).map { |v| v.to_s.downcase }.freeze

  acts_as_tenant :shop

  belongs_to :product
  belongs_to :product_variant, optional: true

  validates :media_type, presence: true
  validates :position, presence: true
  validates :source_url, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :alt_text, length: { maximum: 512 }, allow_nil: true
end
