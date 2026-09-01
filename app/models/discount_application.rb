# frozen_string_literal: true

# 折扣分攤快照（G6 步 9a；表＝M0 既有；17-F2.5）。
#
# 一列＝一折扣對一 scope 的落帳：line_item_id NULL＝order/shipping 級整單列，
# 非 NULL＝該行分攤。退款（16-F5）與報表（17-F4.3）都讀本表，不反推現行設定。
class DiscountApplication < ApplicationRecord
  ALLOCATION_METHODS = %w[across each one].freeze

  acts_as_tenant :shop
  belongs_to :discount
  belongs_to :order

  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :allocation_method, inclusion: { in: ALLOCATION_METHODS }
end
