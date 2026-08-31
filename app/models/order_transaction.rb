# frozen_string_literal: true

# 金流交易列（90-blueprint/05 §A.2/§A.3；表註「authorization/capture/refund 的
# 不可變交易鏈」）。
#
# ①kind 儲存子集（藍圖 §A.3 八值中 v1 先落四值；POS 專屬的 CHANGE/EMV 與
#   非落庫的 SUGGESTED_REFUND 不建列）；status 六值（§A.4）。
# ②🔴 manual 形（15-F5 步 2）：kind=sale、gateway=manual/bank_deposit/
#   cash_on_delivery/money_order、status=**pending**、金額＝checkout 應收——
#   商家收到款後走 orderMarkAsPaid 翻 success（16 §F4.4／90-05 §C.12）。
# ③金額恆正（藍圖 §C.4：方向由 kind 表達，不用負數）；integer cents（鐵律 3）；
#   PSP 形的入向金額必經 to_storage 轉 R1（15-F5 步 2 🔴——G6-1/G6-2 接上）。
# ④`idempotency_key` 每列必帶（鐵律 5）＋ (shop, key) 唯一。
class OrderTransaction < ApplicationRecord
  KINDS = %w[sale authorization capture void refund].freeze
  STATUSES = %w[pending success failure error awaiting_response unknown].freeze

  acts_as_tenant :shop

  belongs_to :order
  belongs_to :parent_transaction, class_name: "OrderTransaction", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :gateway, presence: true
  validates :idempotency_key, presence: true, uniqueness: { scope: :shop_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
