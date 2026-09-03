# frozen_string_literal: true

module ThemeEngine
  # `nil == empty` 為真（渲染 1:1，2026-09-03）。
  #
  # ①這是什麼：本尊 Liquid 把 nil 視為 empty——Ella `snippets/card-lookbook.liquid` 的
  #   `{% if card_product != empty %}…{% else %}No product selected for this dot{% endif %}` 在 hoko.vip
  #   （點位未選商品 ⇒ card_product 為 nil）走 **else** 分支；gem 原生（liquid 5.13.0 `call_method_literal`）
  #   對 nil 的 `empty?` 回假 ⇒ 我方走 if 分支、輸出空的商品資訊框。`blank` 不受影響（nil.blank? 本就為真）。
  # ②怎麼做：prepend 覆寫 `Liquid::Condition#call_method_literal`，只加「value 為 nil 且 literal 為 empty? ⇒ true」一格。
  # ③跨功能：全引擎 `== empty`／`!= empty` 比較；與 NumericLookup 同在 Runtime 顯式掛載（autoload 不 eager）。
  module NilEmpty
    def call_method_literal(literal, value)
      return true if value.nil? && literal.method_name == :empty?

      super
    end
  end
end

Liquid::Condition.prepend(ThemeEngine::NilEmpty)
