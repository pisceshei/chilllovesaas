# frozen_string_literal: true

module Checkouts
  # cart → checkout 快照建立（結帳線第一包；15 F1 #3／F3）。
  #
  # 🔴 進入結帳＝**重新快照價格**：行單價取**即時** variant 價（cart 的
  #   unit_price_cents 是加入當下快照、只承載合併鍵——F1 #3 雙層語義），
  #   此後價格變動不再影響本結帳。
  # 🔴 不扣庫存（15 F5：訂單成立事件才扣）；售罄行照樣進結帳，擋在訂單成立閘。
  # 金額＝`Checkouts::Calculator`（四處重用的同一 Result——15 F2-2）。
  module CreateFromCart
    Error = Class.new(StandardError)

    module_function

    # @param cart [Cart] 需已載入行（空車 ⇒ raise Error）
    # @return [Checkout]
    def call(cart:)
      lines = cart.cart_line_items.includes(product_variant: :product).order(:id).to_a
      raise Error, "購物車是空的。" if lines.empty?

      shop = Shop.find(cart.shop_id)
      snapshot = lines.map do |line|
        variant = line.product_variant
        {
          "key" => "#{variant.id}:#{line.merge_key_hash}",
          "variant_id" => variant.id,
          "quantity" => line.quantity,
          "title" => variant.product.title,
          "variant_title" => variant.title,
          "unit_price_cents" => variant.price_cents, # 🔴 即時價定格（F1 #3）
          # 運送解析輸入（第二包）：重量／是否需運送／設定檔歸屬（nil＝General 補集）
          # 一起定格——結帳中商家改歸屬不重分組（85 §5.3 的「options have changed」
          # 警示走重選閘，不走快照漂移）。
          "weight_grams" => variant.weight_grams,
          "requires_shipping" => variant.requires_shipping,
          "shipping_profile_id" => variant.product.shipping_profile_id,
          "properties" => line.properties
        }
      end

      result = Calculator.call(
        lines: snapshot.map { |row|
          { key: row["key"], quantity: row["quantity"], unit_price_cents: row["unit_price_cents"] }
        },
        currency: shop.store_currency
      )

      Checkout.create!(
        shop_id: cart.shop_id,
        currency: result.currency,
        presentment_currency: result.currency, # v1 同店幣；多幣別隨 markets 幣別包
        line_items_snapshot: snapshot,
        subtotal_cents: result.subtotal_cents,
        discount_cents: result.discount_total_cents,
        shipping_cents: result.shipping_cents,
        tax_cents: result.tax_total_cents,
        total_cents: result.total_cents,
        presentment_total_cents: result.total_cents,
        status: "open" # 三值 enum（90-blueprint/03 §B.2）；第一包誤寫 active 已更正
      )
    end
  end
end
