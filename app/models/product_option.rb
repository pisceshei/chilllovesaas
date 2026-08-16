# 商品的一個選項（Size／Color／材質…）。
#
# ⚠️ **表在 M0 就建好了，但 model 到 D12（2026-08-15）才第一次出現**——
# 在此之前 `app/` 對 `product_options` 是**零讀寫**（無 model、無 GraphQL type、
# 無 factory、seeds 也沒有）。D12 是它的第一次上線。
#
# 🔴 **`position` 是可拖曳的顯示順序，不是身分**（本尊有 `productOptionsReorder`）。
# 任何需要穩定鍵的地方一律用 `id`——`Catalog::OptionValuesDigest` 的排序基準即為此。
#
# @see docs/DECISIONS.md D12
# @see docs/specs/13-spec-products-inventory-media.md §F1-2
class ProductOption < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  # 🔴 **`dependent: :destroy` 而不是 `restrict_with_error`**：選項是商品的**組成部分**，
  # 商品沒了它沒有意義。擋刪商品的責任屬於 `order_line_items` 那一層，不屬於這裡。
  has_many :option_values, dependent: :destroy
  has_many :product_variant_option_values, dependent: :destroy

  validates :name, presence: true
  validates :position, presence: true

  # 🔴 **選項值一律照 `position` 排序取「第一個」**。`docs/specs/63` §B.5 的身分保持
  # 演算法要「既有變體補上新選項的**第一個值**」——若不指定排序，
  # 「第一個」就變成 DB 的回傳順序，那是**不決定性**的。
  # `uq_option_values_product_option_id_position` 保證了 position 在選項內唯一。
  #
  # @return [OptionValue, nil]
  # @note 副作用：無（可能觸發一次查詢）。
  # @see docs/specs/63-product-data-flow.md §B.5
  def first_value
    option_values.order(:position).first
  end
end
