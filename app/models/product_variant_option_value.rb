# 變體 × 選項的一個座標：「這個變體在這個選項上取了這個值」。
#
# 每個變體對每個選項**恰好一列**（DB 層由 `uq_pvov_variant_option` 擋住）。
#
# ## 為什麼有兩個看似冗餘的欄位
#
# 🔴 `product_id`：唯一的手段來用**複合外鍵**擋住「同店內把 A 商品的變體掛上 B 商品的選項」
# ——MySQL 的 CHECK **不能跨表**（子查詢 ⇒ ERROR 3815），沒有第二條路。
#
# 🔴 `product_option_id`：唯一索引**只能跨本表欄位** ⇒ 不存它就無法用索引表達
# 「一個變體在一個選項上只能有一個值」。它自己的正確性由 `fk_pvov_value`
# （三欄歸屬外鍵）保證——少了那支外鍵，寫入端把 option_id 寫錯就能讓
# **同一個變體同時掛「顏色=紅」與「顏色=藍」**。
#
# ⚠️ 兩個欄位都是**約束載體**不是指標。不要因為「可以由 variant／value 推導出來」
# 就把它們拿掉——推導得出來不代表 DB 擋得住。
#
# @see docs/DECISIONS.md D12
# @see db/migrate/20260816000000_create_product_variant_option_values.rb
class ProductVariantOptionValue < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product
  belongs_to :product_variant
  belongs_to :product_option
  belongs_to :option_value

  # 🔴 model 層的同名守衛。DB 的 `uq_pvov_variant_option` 是最後防線，
  # 但它拋的是 `RecordNotUnique`（例外），而寫入路徑要的是 `userErrors`
  # ——在這裡先擋一次，讓正常路徑拿得到可讀的驗證訊息。
  validates :product_option_id,
    uniqueness: { scope: %i[shop_id product_variant_id],
                  message: "在這個變體上已經有值了（一個變體在一個選項上只能有一個值）" }
end
