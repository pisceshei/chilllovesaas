# frozen_string_literal: true

# 部落格文章（步 14a；98 §1/§4）。
#
# 可見性＝`published_at ≤ now` 單閘（Page 同紀律；NULL＝Hidden、未來＝排程——
# admin Visibility 二態＋排程實測形）。handle 唯一域＝(shop, blog)：URL 是
# `/blogs/{blog}/{article}` 複合形（98 §1——Liquid article.handle 官方範例即複合）。
class Article < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :blog
  has_many :article_comments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :handle, presence: true, length: { maximum: 255 },
                     uniqueness: { scope: [ :shop_id, :blog_id ], case_sensitive: false }
  validates :body_html, presence: true, allow_blank: true

  scope :visible, ->(at: Time.current) { where(published_at: ..at) }

  def visible?(at: Time.current) = published_at.present? && published_at <= at

  # Liquid 只見已發布留言（官方 comment.status 恆 published——98 §1）。
  def published_comments = article_comments.where(status: "published")
end
