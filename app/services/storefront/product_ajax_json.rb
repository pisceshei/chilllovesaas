# frozen_string_literal: true

module Storefront
  # `/products/{handle}.js`（與 recommendations JSON）的商品形（E17；hoko.vip 2026-09-05 逐字）——**不是** Liquid `product | json`：
  #   ① 無 `content`；`url` 緊接 `options` 之後（…options, url, requires_selling_plan, selling_plan_groups）
  #   ② 時戳＝店時區 ISO 8601 帶偏移（`"published_at":"2026-09-03T02:27:08+08:00"`）
  #   ③ 變體 22 鍵：…barcode, quantity_rule, quantity_price_breaks（[]）, requires_selling_plan, selling_plan_allocations
  # Liquid `product | json`／`variant | json`（Ella 商品卡 `data-json-product`，同日複驗）仍是 83 §12.2 形（含 content 無 url；21 鍵變體）。
  # recommendations JSON 的商品形＝V（本尊對此三商品回 `products: []`，只能以官方例〔url 在 options 後〕與 .js 同形推定；91 §3.86）。
  module ProductAjaxJson
    VARIANT_KEYS = %w[id title option1 option2 option3 sku requires_shipping taxable featured_image available name
                      public_title options price weight compare_at_price inventory_management barcode quantity_rule
                      quantity_price_breaks requires_selling_plan selling_plan_allocations].freeze

    module_function

    # @param drop [ThemeEngine::ProductDrop]
    # @param product [Product] drop 的來源列（created_at）
    # @param zone [ActiveSupport::TimeZone] 店時區
    def js_form(drop, product:, zone:)
      base = drop.as_storefront_json
      out = {}
      base.each do |key, value|
        next if key == "content"

        out[key] = case key
        when "published_at" then zoned(drop.published_at, zone)
        when "created_at" then zoned(product.created_at, zone)
        when "variants" then drop.variants.map { |v| variant_form(v) }
        when "options" then value.presence || default_title_option(base)
        else value
        end
        out["url"] = drop.url if key == "options"
      end
      out
    end

    # 本尊 `.js` 對只有預設變體的商品仍出 `[{"name":"Title","position":1,"values":["Default Title"]}]`（hoko acme-tee 逐字）；
    # 我方無 option 列時同形（Liquid `options_with_values` 是否同樣合成＝V，91 §3.86）。
    def default_title_option(base)
      return [] if Array(base["variants"]).empty?

      [ { "name" => "Title", "position" => 1, "values" => [ "Default Title" ] } ]
    end

    def variant_form(variant_drop)
      h = ThemeEngine::JsonSerializer.coerce(variant_drop.as_storefront_json).merge("quantity_price_breaks" => [])
      VARIANT_KEYS.to_h { |k| [ k, h[k] ] }
    end

    def zoned(t, zone) = t&.in_time_zone(zone)&.iso8601
  end
end
