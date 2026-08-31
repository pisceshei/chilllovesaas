# frozen_string_literal: true

# 退款逐行（G6-8 步 5；對位本尊 RefundLineItem）。
#
# ①restock_type 值域＝官方 RefundLineItemRestockType 去掉 deprecated：官方 4 值
#   CANCEL/LEGACY_RESTOCK/NO_RESTOCK/RETURN，LEGACY_RESTOCK 官方逐字 "This value
#   is not accepted when creating new refunds."（ord-2 §5，2026-09-01）⇒ 不落。
#   語義（官方逐字）：cancel＝"Use this when restocking unfulfilled line items."／
#   return＝"Use this when restocking line items that were fulfilled."／no_restock。
# ②subtotal_cents/tax_cents＝該行退款額的折後小計與稅（Refunds::Calculator 產出，
#   最大餘數法分攤——16 §F5.1 三個捨入點之一）。
# ③quantity 上界＝該行 quantity − 已退量（Refunds::Create 收集階段驗證；
#   uq_refund_line_items_refund_id_line_item_id 唯一鍵擋同一退款單重複行）。
class RefundLineItem < ApplicationRecord
  RESTOCK_TYPES = %w[no_restock cancel return].freeze

  acts_as_tenant :shop

  belongs_to :refund
  belongs_to :line_item

  validates :restock_type, inclusion: { in: RESTOCK_TYPES }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :subtotal_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :tax_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
