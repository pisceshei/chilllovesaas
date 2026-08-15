FactoryBot.define do
  # 🔴 這個 factory 刻意**要求呼叫端把四個關聯都給對**，不自動生成
  # product／option／value——自動生成會產出「變體屬於 A 商品、選項屬於 B 商品」
  # 這種被 `fk_pvov_option` 擋掉的組合，而錯誤訊息是外鍵違反，看不出根因。
  # 正常用法是走 `product_variant` factory 的 `option_values:` transient。
  factory :product_variant_option_value do
    shop { product_variant.shop }
    product { product_variant.product }
    product_option { option_value.product_option }
  end
end
