# frozen_string_literal: true

# 訂單（15-F5；表建於 M0，第一個消費者＝G6-0(a) 訂單成立包）。
#
# ①三軸狀態彼此獨立（表註「彼此獨立的狀態機」）：`status`（open/closed/cancelled）
#   ／`financial_status`（90-blueprint/05 §A.6 八值的儲存子集；manual 付款下單＝
#   **pending**——86 §3 官方句「the order is marked as Pending」）／
#   `fulfillment_status`（unfulfilled 起）。
# ②金額全 integer cents（鐵律 3）；快照原則：line_items 與金額欄在成立當下定格，
#   商品後續改動不回寫。
# ③`checkout_id` 唯一索引＝冪等第二層（15-F5 步 1：漏帶 key 的併發雙擊由 DB 兜底）。
# ④`order_number` 每店連號（shops.order_counter）；`name`＝顯示形「#1001」。
# ⑤跨功能影響：付款線（order_transactions 聚合出 financial_status——16 §F4.3
#   displayFinancialStatus 推導、不可直接寫）、庫存（成立扣 available−/committed+，
#   出貨再 committed−）、admin 訂單列表（G6-6 API 對位）、webhook orders/create。
class Order < ApplicationRecord
  STATUSES = %w[open closed cancelled].freeze
  FINANCIAL_STATUSES = %w[pending authorized paid partially_paid partially_refunded
                          refunded voided expired].freeze
  FULFILLMENT_STATUSES = %w[unfulfilled partially_fulfilled fulfilled].freeze

  acts_as_tenant :shop

  has_many :line_items, dependent: :destroy
  has_many :order_transactions, dependent: :destroy
  has_many :events, dependent: :destroy

  validates :name, presence: true
  validates :order_number, presence: true, uniqueness: { scope: :shop_id }
  validates :status, inclusion: { in: STATUSES }
  validates :financial_status, inclusion: { in: FINANCIAL_STATUSES }
  validates :fulfillment_status, inclusion: { in: FULFILLMENT_STATUSES }
  validates :currency, presence: true
end
