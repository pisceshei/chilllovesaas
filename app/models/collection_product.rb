# frozen_string_literal: true

# 手動系列 × 商品的 join（ML-3）。
#
# 🔴 **只用於手動系列**：智慧系列的成員是規則的**函數**（`collection_rules`），
# 不是一張成員表——把智慧系列的結果物化進這張表會產生兩個真相（規則說 A、表說 B），
# 而規則一改就對不上（13 §F4）。智慧系列的 `products_count` 在規則引擎落地前回 null。
#
# `position` 是手動排序（前台顯示序，67 §C.8 同一條紀律：商家唯一能控制順序的地方）。
class CollectionProduct < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :collection
  belongs_to :product

  validates :position, presence: true
  validates :product_id, uniqueness: { scope: %i[shop_id collection_id] }

  scope :ordered, -> { order(:position, :id) }
end
