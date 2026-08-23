# frozen_string_literal: true

# 智慧系列的一條條件（ML-3；13 §F4）。
#
# 成員資格＝規則的函數，不物化成 join 列（見 CollectionProduct 註釋）。
# `column_name`／`relation`／`condition_value` 三元組對齊本尊條件形態（92-D 分冊有完整矩陣）；
# v1 只建模與讀取面，規則求值引擎屬後續包。
class CollectionRule < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :collection

  validates :column_name, :relation, :condition_value, :position, presence: true

  scope :ordered, -> { order(:position, :id) }
end
