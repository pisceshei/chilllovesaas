# 商品系列（collection）。
#
# ⚠️ **M1 尚未展開**：本類別目前只有租戶隔離與最基本的驗證。
# 手動/智慧系列的規則引擎、排序、成員關聯屬 M1 的主體工作。
# 🔴 建立式的概念差已登記（71-R8-V4）：本尊 2026 改為「來源」卡（新增條件與新增商品同卡混用
# ＋排除 negative 條件＋多來源組），與我方 13-F4 的「手動/智慧二分不可互轉」不同——**未裁定**。
#
# 為什麼現在就建：`ResourcePublication` 的 `publishable` 是多型關聯，
# Publishable 介面由 Product／Collection／ProductVariant 三者實作（82 §0.2）。
#
# @see docs/specs/88-publication-model.md
class Collection < ApplicationRecord
  acts_as_tenant :shop

  has_many :resource_publications, as: :publishable, dependent: :destroy

  validates :title, :handle, presence: true
  # DB 已有 uq_collections_handle (shop_id, handle) 唯一索引；沒有 model validation
  # 的話重複 handle 會拋 RecordNotUnique 而不是乾淨的驗證錯誤，
  # 與 Product 的處理不一致（PR #24 的 Claude 驗收 🟡 建議）。
  validates :handle, uniqueness: { scope: :shop_id, case_sensitive: false }
end
