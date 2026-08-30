# frozen_string_literal: true

# 前台自訂頁面（包 30／D77；表＝M0 既建）。
# `published_at` 語義與商品發布同軸：NULL＝草稿、未來＝排程、過去＝已發布。
# 前台直連判準（specs/93 §C 同款）：published_at 有值 ∧ ≤ 判定時點。
class Page < ApplicationRecord
  acts_as_tenant :shop

  validates :title, presence: true, length: { maximum: 255 }
  validates :handle, presence: true, length: { maximum: 255 },
                     uniqueness: { scope: :shop_id, case_sensitive: false }

  # 前台可見集合（單閘：頁面無 status 欄，與 Collection 同型——specs/93 §C）。
  scope :visible, ->(at: Time.current) { where(published_at: ..at) }
end
