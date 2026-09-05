# frozen_string_literal: true

module Storefront
  # 商品 JSON 端點（E17；本尊 hoko.vip 2026-09-05 逐字）：
  #   GET /products/{handle}.js   ⇒ 店面商品 JSON（同 `product | json`／recommendations 形；`url` 在 options 之後、無 content；
  #                                  時戳店時區帶偏移）
  #   GET /products/{handle}.json ⇒ REST 形 `{"product":{…}}`：price 十進位字串、compare_at_price 無值＝`""`、sku／barcode 無值＝null、
  #                                  grams／weight（kg）／weight_unit、fulfillment_service "manual"、price_currency、quantity_rule…
  # 裸與帶語言前綴兩形都收（主題 JS 以 `routes`／location 組 URL）。查無 handle ⇒ 404 空 body（本尊未取得，91 §3.86 V）。
  # 先前兩形都落到 catch-all ⇒ 主題 404 頁（mirror 店 `/products/acme-tee.js` 404 333KB）。
  class ProductsController < BaseController
    skip_forgery_protection

    def ajax_js
      product = find_product or return head(:not_found)
      drop = ThemeEngine::ProductDrop.new(product, url_prefix:, publication: Publication.online_store!)
      render json: Storefront::AjaxJson.dump(Storefront::ProductAjaxJson.js_form(drop, product:, zone:))
    end

    def rest_json
      product = find_product or return head(:not_found)
      render json: Storefront::AjaxJson.dump({ "product" => rest_product(product) })
    end

    private

    def find_product
      ActsAsTenant.with_tenant(current_shop) do
        Storefront::Lookup.product_by_handle(publication: Publication.online_store!, handle: params[:handle].to_s)
      end
    end

    def url_prefix
      hit = effective_hit
      hit ? Markets::UrlPrefix.for(hit.web_presence, hit.locale_tag) : ""
    rescue Markets::UrlPrefix::Error
      ""
    end

    def zone
      @zone ||= ActiveSupport::TimeZone[current_shop.timezone.to_s] || Time.zone
    end

    def ts(t) = t&.in_time_zone(zone)&.iso8601

    # 鐵律 3：cents ⇒ 十進位字串只在此序列化層（兩位小數；零小數幣別＝V）
    def money_string(cents) = format("%d.%02d", cents.to_i / 100, cents.to_i % 100)

    # REST 形（hoko.vip `/products/acme-tee.json` 2026-09-05 逐字鍵序）。images 本尊例為 `[]`（無圖商品）；有圖時的元素形＝V。
    def rest_product(product)
      drop = ThemeEngine::ProductDrop.new(product, url_prefix:, publication: Publication.online_store!)
      option_rows = product.product_options.sort_by(&:position)
      option_jsons = drop.options_with_values.map { |o| ThemeEngine::JsonSerializer.coerce(o.as_storefront_json) }
      option_jsons = Storefront::ProductAjaxJson.default_title_option({ "variants" => drop.variants }) if option_jsons.empty?
      images = drop.images.map { |i| ThemeEngine::JsonSerializer.coerce(i.as_storefront_json) }
      {
        "id" => product.id, "title" => product.title, "body_html" => product.description_html.to_s,
        "vendor" => product.vendor, "product_type" => product.product_type.to_s,
        "created_at" => ts(product.created_at), "handle" => product.handle, "updated_at" => ts(product.updated_at),
        "published_at" => ts(drop.published_at), "template_suffix" => "", "published_scope" => "global",
        "tags" => Array(product.tags).join(", "),
        "variants" => drop.variants.each_with_index.map { |v, i| rest_variant(product, v, i + 1) },
        "options" => option_jsons.each_with_index.map do |o, i|
          { "id" => option_rows[i]&.id, "product_id" => product.id, "name" => o["name"],
            "position" => o["position"], "values" => o["values"] }
        end,
        "images" => images.map do |img|
          { "id" => img["id"], "product_id" => product.id, "position" => img["position"], "created_at" => ts(product.created_at),
            "updated_at" => ts(product.updated_at), "alt" => img["alt"], "width" => img["width"], "height" => img["height"],
            "src" => img["src"], "variant_ids" => [] }
        end,
        "image" => images.first && { "id" => images.first["id"], "product_id" => product.id, "position" => images.first["position"],
                                     "created_at" => ts(product.created_at), "updated_at" => ts(product.updated_at),
                                     "alt" => images.first["alt"], "width" => images.first["width"],
                                     "height" => images.first["height"], "src" => images.first["src"], "variant_ids" => [] }
      }
    end

    def rest_variant(product, v, position)
      currency = current_shop.store_currency
      record = product.product_variants.find { |pv| pv.id == v.id }
      { "id" => v.id, "product_id" => product.id, "title" => v.title, "price" => money_string(v.price),
        "sku" => v.sku.presence, "position" => position,
        "compare_at_price" => v.compare_at_price ? money_string(v.compare_at_price) : "",
        "fulfillment_service" => "manual", "inventory_management" => v.inventory_management,
        "option1" => v.option1, "option2" => v.option2, "option3" => v.option3,
        "created_at" => ts(record&.created_at), "updated_at" => ts(record&.updated_at),
        "taxable" => v.taxable, "barcode" => v.barcode.presence, "grams" => v.weight.to_i, "image_id" => nil,
        "weight" => (v.weight.to_i / 1000.0), "weight_unit" => "kg", "requires_shipping" => v.requires_shipping,
        "quantity_rule" => v.quantity_rule, "price_currency" => currency,
        "compare_at_price_currency" => (v.compare_at_price ? currency : ""), "quantity_price_breaks" => [] }
    end
  end
end
