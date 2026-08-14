# 一個銷售管道在本店的發布容器（對應本尊的 `Publication`）。
#
# 發布模型是**三層 AND**（docs/specs/88 §1，help 原文）：
#   Publishable（Product／Collection／ProductVariant）
#     × Publication（本類別，綁一個管道）
#     × Catalog（該管道市場的目錄；M5 才建）
# 三個條件**缺一不可上架**——「已發布到該管道」與「在該管道市場的目錄內」是兩件獨立的事。
#
# 🔴 這是業務資料，受 `acts_as_tenant` fail-closed 隔離（鐵律 2；G24 的豁免只給身分表）。
#
# @see docs/specs/88-publication-model.md
# @see docs/research/82-admin-channels.md §0.2
class Publication < ApplicationRecord
  acts_as_tenant :shop

  has_many :resource_publications, dependent: :destroy

  validates :name, :channel_handle, presence: true
  validates :channel_handle, uniqueness: { scope: :shop_id }

  # 本店預設的線上商店 publication。
  #
  # M1 階段只有這一個管道；建立商店時必須連帶建立它（見 88 §4）。
  #
  # @return [Publication, nil] 線上商店管道；尚未建立時為 nil
  # @note 副作用：一次 tenant-scoped SELECT。
  # @see docs/specs/88-publication-model.md §4
  def self.online_store
    find_by(channel_handle: "online_store")
  end
end
