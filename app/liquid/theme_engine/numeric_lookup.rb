# frozen_string_literal: true

module ThemeEngine
  # 對**字串**做屬性查找回空字串（渲染 1:1，2026-09-03）。
  #
  # ①這是什麼：本尊對空字串（資源型 setting 的「blank」實測形）取屬性得到**空字串**而非 nil。證據（hoko.vip 首頁原始位元組）：
  #   Ella `blocks/product-grid.liquid` 無集合時以整數當 `closest.product`，靜態商品卡 `card-product-flex` 的
  #   `card_product = block.settings.product`（動態來源 `{{ closest.product }}` 解成非商品 ⇒ blank ⇒ 空字串）⇒ 本尊輸出
  #   `card--media`（`{% if card_product.featured_media %}` 為真——Liquid 只有 nil／false 為假）、`"id": ,`
  #   （`{{ card_product.id }}` 空）、`"media": &quot;&quot;`（`| json` ⇒ `""`）。gem 原生回 nil ⇒ 我方 `card--text`／`null`。
  #   🔴 整數**不在此列**：同一張卡的子 block `_card-product-media-flex` 以 `closest.product`（整數 1）取 `featured_media`
  #   走**佔位**分支（本尊 `group-block media-block card__inner … placeholder-svg`），即整數取屬性仍是 nil（gem 原生）；
  #   同日曾誤把整數也納入，令該子 block 走真實媒體分支（`card-media`＋除零錯），對表報告抓回。
  #   nil 亦不在此列——`{% if nothing.foo %}` 必須為假（主題通用形）。
  # ②怎麼做：prepend 覆寫 `Liquid::VariableLookup#evaluate`（liquid 5.13.0 原文逐行搬入，只加一個分支：
  #   object 為 String 且非命令鍵（first／last／size 仍走原生）⇒ 換成 ""）。其餘查找語義原樣。
  # ③跨功能：全引擎變數查找；只影響「對字串取屬性」這一格（正常主題只在資源型 setting 空值時踩到）。
  #   gem 升版時須對照 variable_lookup.rb 重搬（版本釘在 Gemfile.lock）。
  module NumericLookup
    def evaluate(context)
      name   = context.evaluate(@name)
      object = context.find_variable(name)

      @lookups.each_index do |i|
        key = context.evaluate(@lookups[i])
        key = Liquid::Utils.to_liquid_value(key)

        if object.respond_to?(:[]) &&
           ((object.respond_to?(:key?) && object.key?(key)) ||
            (object.respond_to?(:fetch) && key.is_a?(Integer)))
          res    = context.lookup_and_evaluate(object, key)
          object = res.to_liquid
        elsif lookup_command?(i) && object.respond_to?(key)
          object = object.send(key).to_liquid
        elsif lookup_command?(i) && object.is_a?(String) && (key == "first" || key == "last")
          object = key == "first" ? (object[0] || "") : (object[-1] || "")
        elsif object.is_a?(String)
          object = "" # 本尊形（見檔頭）
        else
          return nil unless context.strict_variables

          raise Liquid::UndefinedVariable, "undefined variable #{key}"
        end

        object.context = context if object.respond_to?(:context=)
      end

      object
    end
  end
end

Liquid::VariableLookup.prepend(ThemeEngine::NumericLookup)
