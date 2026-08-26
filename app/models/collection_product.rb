# frozen_string_literal: true

# 手動系列 × 商品的 join（ML-3）。
#
# 🔴 **只用於手動系列**：智慧系列的成員自第 11 包（D50）起**物化在
# `collection_memberships`**（前台唯一查詢對象，13 §F4.6-1），由引擎（Rebuild／
# ResyncProduct）維護——寫進**本表**才是「兩個真相」（同一系列兩張成員表）。
# 🔴 本註釋首版寫「成員是規則的函數，不是一張成員表」——那句話把「不物化」當結論，
#   與 13 §F4.6-1 相反（第 11 包工作卡點名的改寫）；正解＝物化，但物化在專屬表。
# 智慧系列的 `products_count` 在首次成功 rebuild 前回 null（「未求值」≠ 0）。
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
