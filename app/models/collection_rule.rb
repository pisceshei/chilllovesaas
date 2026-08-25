# frozen_string_literal: true

# ⚠️ **Legacy——第 11 包（D50）起停止寫入，讀取面亦無消費者。**
#
# 智慧系列的條件自 D50 起存 `collection_source_rules`（typed value：金額走 value_cents，
# 鐵律 3；本表的 `condition_value` 字串存 `'148.00'` 正是被 D50 點名的十進位字串入口）。
# 求值引擎＝`Collections::RuleCompiler`＋`Rebuild`／`ResyncProduct`，成員**物化**進
# `collection_memberships`（13 §F4.6-1）——
# 🔴 本註釋首版寫「成員資格＝規則的函數，不物化成 join 列」，那句話會把人導向
#   即時求值；正解＝物化表是前台唯一查詢對象（第 11 包工作卡點名的改寫）。
# 本表保留只因 schema drift 最小化（正式環境 0 列，2026-08-25 實查）；刪表另立遷移包。
class CollectionRule < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :collection

  validates :column_name, :relation, :condition_value, :position, presence: true

  scope :ordered, -> { order(:position, :id) }
end
