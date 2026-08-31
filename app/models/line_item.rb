# frozen_string_literal: true

# 訂單行（15-F5；表註「下單當下不可回溯改寫的商品與金額快照」）。
#
# ①快照語義：title/variant_title/sku/vendor/product_type/unit_price_cents 全在
#   成立當下定格——商品改名改價不回寫（退款、對帳、發票都要能回放當時的事實）。
# ②`product_variant_id` 可 NULL（變體其後被刪，快照仍完整——與 85 §5.4 刪檔
#   回落同一哲學：快照不是外鍵）。
# ③金額不變量：`total_cents = unit_price_cents × quantity − total_discount_cents`
#   （v1 無行級折扣 ⇒ discount 0）。
class LineItem < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :order
  belongs_to :product_variant, optional: true

  validates :title, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, :total_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
