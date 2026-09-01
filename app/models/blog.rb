# frozen_string_literal: true

# 部落格（步 14a；98 §3——官方 CommentPolicy 三值、admin 預設 Disabled＝closed）。
class Blog < ApplicationRecord
  # 官方 enum（AUTO_PUBLISHED/CLOSED/MODERATED）的內部小寫形；98 §4 admin 逐字
  # 對映：Disabled=closed／Allowed, pending moderation=moderated／Allowed=auto_published。
  COMMENT_POLICIES = %w[closed moderated auto_published].freeze

  acts_as_tenant :shop

  has_many :articles, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :handle, presence: true, length: { maximum: 255 },
                     uniqueness: { scope: :shop_id, case_sensitive: false }
  validates :comment_policy, inclusion: { in: COMMENT_POLICIES }

  def comments_enabled? = comment_policy != "closed"
  def moderated? = comment_policy == "moderated"
end
