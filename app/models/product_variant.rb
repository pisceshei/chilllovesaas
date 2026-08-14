# 商品的子類選項（variant）。
#
# ⚠️ **M1 尚未展開**：本類別目前只有租戶隔離、關聯與最基本的驗證。
# 變體 diff 更新、價格/成本、庫存連動、選項組合等屬 M1 商品線的主體工作
# （HANDOFF §5：「Products CRUD＋變體 diff 更新＋媒體＋系列＋庫存 ledger」）。
#
# 為什麼現在就建：`ResourcePublication` 的 `publishable` 是**多型**關聯，
# 而本尊的 Publishable 介面由 Product／Collection／ProductVariant 三者實作
# （docs/research/82 §0.2）——三個類別缺一個，多型關聯就無法驗證。
#
# @see docs/specs/88-publication-model.md
class ProductVariant < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  has_many :resource_publications, as: :publishable, dependent: :destroy

  validates :title, presence: true
end
