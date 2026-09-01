# frozen_string_literal: true

# 選單項（可巢狀；包 30／D77；表＝M0 既建）。
#
# `item_type`＝http（自由 URL）或資源參照（product／collection／page——
# `resource_type`＋`resource_id`，渲染期解析成當下 URL，handle 改名不斷鏈）。
# 巢狀深度上限走 limits `max_menu_depth`（本尊選單 ≤3 層）。
class MenuItem < ApplicationRecord
  # 步 14a 擴充（98 §3 官方 MenuItemType 子集）：資源型需 resource_id、靜態型
  # （frontpage/search/catalog/collections）免 url 免 resource——渲染期由 RoutesDrop
  # 對映固定路徑。METAOBJECT/SHOP_POLICY/CUSTOMER_ACCOUNT_PAGE 延後（91 §3.64）。
  RESOURCE_TYPES = %w[product collection page blog article].freeze
  STATIC_TYPES = %w[frontpage search catalog collections].freeze
  ITEM_TYPES = ([ "http" ] + RESOURCE_TYPES + STATIC_TYPES).freeze

  acts_as_tenant :shop

  belongs_to :menu
  belongs_to :parent_menu_item, class_name: "MenuItem", optional: true
  has_many :children, class_name: "MenuItem", foreign_key: :parent_menu_item_id,
                      inverse_of: :parent_menu_item, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :url, presence: true, if: -> { item_type == "http" }
  validates :resource_type, :resource_id, presence: true,
            if: -> { RESOURCE_TYPES.include?(item_type) }
end
