# frozen_string_literal: true

# catalog 的價格表（本尊 `PriceList` 的我方對位；S10／D76）。
#
# 三件組定位（88 §3.2）：Catalog ── has one ──> PriceList（本類）
#                              └── has one ──> Publication
# 百分比層先行；**變體級固定價**（本尊 PriceListPrice；82 §9.5c 實測成員表逐列
# 可編輯 Price／Compare-at）＝`price_list_prices` 表，隨 M5 成員模型一起建——
# 那張表是金額欄（`*_cents`，鐵律 3），本類的 `adjustment_basis_points` 是百分比（整數 bp），
# **兩者不得混用同一套欄位**。
#
# 官方錨（取證 2026-08-30，migration 檔頭有逐字）：
#   - `PriceListAdjustmentType` 恰二值：PERCENTAGE_DECREASE／PERCENTAGE_INCREASE
#   - `PriceListCompareAtMode` 恰二值：ADJUSTED／NULLIFY
#   - priceListCreate：name!／currency!／parent!(adjustment type+value)
#
# 🔴 業務資料，受 `acts_as_tenant` fail-closed 隔離（鐵律 2）。
#
# @see docs/research/82-admin-channels.md §9.5b、§21
class PriceList < ApplicationRecord
  # 本尊 enum 的我方小寫對位（存庫小寫、序列化層轉大寫，與 SalesCatalog::STATUSES 同紀律）。
  ADJUSTMENT_TYPES = %w[percentage_decrease percentage_increase].freeze
  COMPARE_AT_MODES = %w[adjusted nullify].freeze

  acts_as_tenant :shop

  belongs_to :sales_catalog

  validates :name, presence: true, length: { maximum: 255 }
  validates :currency, presence: true, length: { is: 3 }
  validates :adjustment_type, inclusion: { in: ADJUSTMENT_TYPES }
  validates :compare_at_mode, inclusion: { in: COMPARE_AT_MODES }
  validates :adjustment_basis_points,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # 🔴 只有 decrease 側有 10000bp（=100%）上限——這不是抄來的規則，是數學必然：
  #   降幅超過 100% ⇒ 負價格。increase 側官方上限**未取得**，不發明（鐵律 19）。
  validates :adjustment_basis_points,
            numericality: { less_than_or_equal_to: 10_000 },
            if: -> { adjustment_type == "percentage_decrease" }
  # 一個 catalog 至多一個 price list（migration 檔頭引官方單數所有格）。
  validates :sales_catalog_id, uniqueness: { scope: :shop_id }
end
