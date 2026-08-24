# frozen_string_literal: true

# 一次庫存異動呼叫的批次頭（排程第 16 包；＝本尊 InventoryAdjustmentGroup；總裁定 §一）。
#
# ①這是什麼：一次呼叫＝一把 idempotencyKey＝一列 group＝N 列 ledger 子行。
#   呼叫層欄位（reason／mutation_kind／參考文件／actor 兩欄）都在這層。
# ②值域：`reason` ∈ limits.inventory.adjustment_reasons（API 17 值）；
#   `mutation_kind` ∈ adjust|move|set|activate；`quantity_name` ∈ limits.inventory.quantity_names。
# ③怎麼做：由 `Inventory::Adjust`（第 17 包）建立；本模型只承載驗證與關聯。
#   actor 兩欄分開不用多型（本尊 staffMember 與 app 是兩個欄位、可同時存在）；
#   `client_source` 是 app 欄位的過渡承載（V-96.2，M5 apps 落地後補 app_id）。
# ④跨功能影響：`Idempotency::Guard` 的 result resource 就是本列（Guard 不必改）；
#   調整記錄頁（第 18 包）一列＝一個 group；`changes_count` 是 GraphQL 分頁計數快取，
#   Reconcile 八式之一驗它（總裁定 §四-2）。
class InventoryAdjustmentGroup < ApplicationRecord
  acts_as_tenant :shop

  MUTATION_KINDS = %w[adjust move set activate].freeze
  # 值域引 limits.yml（鐵律 6）；與 Product::STATUSES 同構的常數形。
  REASONS = Limits.enum(:inventory, :adjustment_reasons).map { |v| v.to_s.downcase }.freeze
  QUANTITY_NAMES = Limits.enum(:inventory, :quantity_names).map { |v| v.to_s.downcase }.freeze

  has_many :inventory_adjustments, dependent: :delete_all

  validates :idempotency_key, presence: true, uniqueness: { scope: :shop_id }
  validates :reason, inclusion: { in: REASONS }
  validates :quantity_name, inclusion: { in: QUANTITY_NAMES }
  validates :mutation_kind, inclusion: { in: MUTATION_KINDS }
end
