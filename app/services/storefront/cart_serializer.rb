# frozen_string_literal: true

module Storefront
  # cart JSON（Ajax 契約；真店對照 83 §3.3：`/cart.js` ≡ `/cart.json` 同形、
  # 頂層 14 鍵含 `discount_codes`、item key＝"variant_id:hash"、金額全 integer
  # cents——鐵律 3 與 blueprint 03 C.6 的儲存尺度直通）。
  #
  # 🔴 顯示價＝即時 variant 現價（F1 #3）；`unit_price_cents` 快照只當合併鍵。
  # 🔴 item 欄位＝live 30+ 欄的核心子集（缺的逐項登記於 worklog；未實作功能
  #   （折扣／selling plan）出常數空形，與 drop stub 同策略）。
  module CartSerializer
    module_function

    # @param cart [Cart] 需已 preload cart_line_items → product_variant → product
    # @return [Hash]
    def cart_json(cart)
      items = cart.cart_line_items.sort_by(&:id).map { |line| item_json(line) }
      subtotal = items.sum { |i| i["final_line_price"] }
      {
        "token" => cart.token, "note" => cart.note,
        "attributes" => cart.attributes_json,
        "original_total_price" => subtotal, "total_price" => subtotal,
        "total_discount" => 0, "total_weight" => total_weight(cart),
        "item_count" => items.sum { |i| i["quantity"] }, "items" => items,
        "requires_shipping" => cart.cart_line_items.any? { |l| l.product_variant.requires_shipping },
        "currency" => cart.shop.store_currency,
        "items_subtotal_price" => subtotal,
        "cart_level_discount_applications" => [], "discount_codes" => []
      }
    end

    def item_json(line)
      variant = line.product_variant
      product = variant.product
      price = variant.price_cents
      named = variant.title != "Default Title"
      {
        "id" => variant.id,
        "key" => "#{variant.id}:#{line.merge_key_hash}",
        "quantity" => line.quantity,
        "variant_id" => variant.id,
        "product_id" => product.id,
        "title" => named ? "#{product.title} - #{variant.title}" : product.title,
        "product_title" => product.title,
        "variant_title" => named ? variant.title : nil,
        "handle" => product.handle,
        "url" => "/products/#{product.handle}?variant=#{variant.id}",
        "price" => price,
        "original_price" => price,
        "final_price" => price,
        "line_price" => price * line.quantity,
        "original_line_price" => price * line.quantity,
        "final_line_price" => price * line.quantity,
        "total_discount" => 0, "discounts" => [],
        "properties" => line.properties,
        "grams" => variant.weight_grams * line.quantity,
        "requires_shipping" => variant.requires_shipping,
        "taxable" => variant.taxable,
        "sku" => variant.sku,
        "vendor" => product.vendor
      }
    end

    def total_weight(cart)
      cart.cart_line_items.sum { |l| l.product_variant.weight_grams * l.quantity }
    end
  end
end
