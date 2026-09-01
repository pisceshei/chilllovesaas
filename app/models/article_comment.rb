# frozen_string_literal: true

# 文章留言（步 14a；98 §4——admin 三態 Approved/Not approved/Spam）。
#
# status 對映：published=Approved／pending=Not approved（moderated 進站預設）／
# spam=Spam。auto_published blog 的新留言直接 published；closed blog 不收
# （storefront 端點擋，不在 model 層）。
class ArticleComment < ApplicationRecord
  STATUSES = %w[pending published spam].freeze

  acts_as_tenant :shop

  belongs_to :article

  validates :author_name, presence: true, length: { maximum: 255 }
  validates :email, presence: true, length: { maximum: 320 }
  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
end
