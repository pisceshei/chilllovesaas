# frozen_string_literal: true

# 退款業務紀錄（G6-8 步 5；對位本尊 Refund——ord-4 §8 官方句 "The Refund object
# represents a financial record of money returned to a customer from an order."）。
#
# ①表註「金流結果仍由 transaction 推導」：本表是**業務決議**（退哪些行、退多少、
#   restock 與否），金流終態在 order_transactions（kind=refund 的列，status 由
#   gateway 路徑決定：manual＝建立即 success；PSP＝pending → webhook/輪詢翻面）。
# ②status 值域：pending（PSP 退款已受理未終結——Airwallex RECEIVED/ACCEPTED 對映）
#   /success/failure。⚠️ Airwallex 官方 status 4 值 RECEIVED/ACCEPTED/SETTLED/FAILED
#  （ord-4 §9 逐字）——SETTLED 屬對帳報表面，我方以 success 承載 ACCEPTED 起的
#   完成態；對映登記 dev doc。
# ③🔴 金額欄與 orders.refunded_total_cents 的關係：本表 total_cents 是明細，
#   orders 上的累計欄是 16 §F5.1 條件式 UPDATE 的物化值——兩者 nightly 對帳
#  （limits.refund.cumulative_cap_column 註）。寫入順序＝先條件式 UPDATE 累計欄
#  （軟上限檢查）成功才 INSERT 本表（Refunds::Create 唯一入口）。
class Refund < ApplicationRecord
  STATUSES = %w[pending success failure].freeze

  acts_as_tenant :shop

  belongs_to :order
  belongs_to :order_transaction, optional: true # 金流列（manual 立即有；PSP 受理後掛）
  has_many :refund_line_items, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :shipping_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :idempotency_key, presence: true, uniqueness: { scope: :shop_id }
end
