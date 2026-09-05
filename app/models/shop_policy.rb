# frozen_string_literal: true

# 商店政策（T13；表＝20260905120000）。官方 Settings › Policies 六種＋contact-information 路徑（external-facts §G29）。
# 前台判準（hoko.vip 2026-09-05）：只有 body 有內容的政策存在——`/policies/{kind}` 200、`shop.{kind}_policy` 非 nil、
# `shop.policies` 收錄；未設者 404／nil／不收錄。kind 同時是 URL handle（本尊 `/policies/refund-policy` 等，help 取證）。
class ShopPolicy < ApplicationRecord
  acts_as_tenant :shop

  # 序＝官方 help 頁列出順序（Return／Privacy／Terms／Shipping／Legal notice／Subscription）＋contact-information；
  # `shop.policies` 陣列序本尊未觀測（91 §3.90 V）——先照此序。
  KINDS = %w[refund-policy privacy-policy terms-of-service shipping-policy legal-notice subscription-policy contact-information].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }, uniqueness: { scope: :shop_id }
  validates :title, presence: true, length: { maximum: 255 }

  scope :present_body, -> { where.not(body: [ nil, "" ]) }

  def handle = kind
  def body_present? = body.present?
end
