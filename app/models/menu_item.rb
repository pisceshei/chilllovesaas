# frozen_string_literal: true

# 選單項（可巢狀；包 30／D77；表＝M0 既建）。
#
# `item_type`＝http（自由 URL）或資源參照（product／collection／page——
# `resource_type`＋`resource_id`，渲染期解析成當下 URL，handle 改名不斷鏈）。
# 巢狀深度上限走 limits `max_menu_depth`（本尊選單 ≤3 層）。
class MenuItem < ApplicationRecord
  ITEM_TYPES = %w[http product collection page].freeze

  acts_as_tenant :shop

  belongs_to :menu
  belongs_to :parent_menu_item, class_name: "MenuItem", optional: true
  has_many :children, class_name: "MenuItem", foreign_key: :parent_menu_item_id,
                      inverse_of: :parent_menu_item, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :url, presence: true, if: -> { item_type == "http" }
  validates :resource_type, :resource_id, presence: true, if: -> { item_type != "http" }
end
