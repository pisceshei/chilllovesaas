# frozen_string_literal: true

# 系列來源（sources 模型；limits `collection.source_types`，95 §1.1 修正形）。
#
# 🔴 兩型不是四型：`conditions`（帶 target_type products/variants）／`sub_collections`
#   （帶 referenced_collection_id）。include/exclude 是本列**內部的兩個區塊**
#   （rules 的 `block` 欄＋本列的 `inclusion_match`/`exclusion_match`），不是 source 極性。
# 🔴 v1 射程（第 11 包）：只收 `conditions`×`products`；`sub_collections`／`variants`／
#   `app_id`／`shareable` 欄位就位但寫入端拒收（值域白名單在 SaveCollection），
#   展開屬後續包（13 §F4.5 的巢狀機制）。
class CollectionSource < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :collection
  has_many :rules, -> { order(:position) }, class_name: "CollectionSourceRule",
           foreign_key: :collection_source_id, inverse_of: :source, dependent: :delete_all

  validates :source_type, inclusion: { in: %w[conditions sub_collections] }
  validates :inclusion_match, inclusion: { in: %w[all any] }
  validates :exclusion_match, inclusion: { in: %w[all any] }, allow_nil: true

  scope :conditions_type, -> { where(source_type: "conditions") }
end
