# frozen_string_literal: true

# 商品標籤正規化列（13 §F4.4）：`tag_display` 顯示、`tag_key` 比對（`Tags::Normalize` 唯一實作）。
#
# 🔴 寫入面只有兩個：`Catalog::SaveProduct`（tags 變更同 tx 同步）與 migration 回填。
#   `products.tags`（JSON 欄）仍是**顯示順序**的權威；本表是**比對**的權威——兩者由
#   同一個 tx 內的同步保持一致，出現分岔＝SaveProduct 的同步壞了，不是本表該修。
class ProductTag < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  validates :tag_display, presence: true, length: { maximum: 255 }
  validates :tag_key, presence: true, uniqueness: { scope: [ :shop_id, :product_id ] }
end
