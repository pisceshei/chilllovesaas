# frozen_string_literal: true

# 商品媒體 metadata（第 25 包薄版；表＝`media`，本體在物件儲存）。
#
# ①這是什麼：商品 × 媒體的一列（position 排序、可掛 variant）。
# ②狀態：四態起點＝`uploaded`（第 26 包 migration 已把 schema default 從 "ready"
#   改過來——原值是 M0 建表佔位、與 90-blueprint/01 §B.3 G22 狀態機矛盾）。
# ③跨功能影響：第 27 包媒體卡 mutations、`uq_media_product_id_position` 是 unique
#   ——重排要兩階段落位（整合規格 §1.4；variant_sync `apply_matched!` 同型）。
class Media < ApplicationRecord
  self.table_name = "media"

  STATUSES = Limits.enum(:media, :statuses).map { |v| v.to_s.downcase }.freeze

  acts_as_tenant :shop

  belongs_to :product
  belongs_to :product_variant, optional: true
  # 檔案本體（第 26 包加欄）；nullable 因寫入端＝第 27 包 productCreateMedia。
  belongs_to :stored_file, foreign_key: :file_id, optional: true, inverse_of: false

  validates :media_type, presence: true
  validates :position, presence: true
  validates :source_url, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :alt_text, length: { maximum: 512 }, allow_nil: true
end
