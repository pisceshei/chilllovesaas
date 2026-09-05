# frozen_string_literal: true

module Storefront
  # 店面 Storefront API 端點（E18 第一片：`cartCreate`）——本尊 `POST /api/unstable/graphql.json?operation_name=cartCreate`。
  #
  # ①這是什麼：portable-wallets（動態結帳「立即購買」鈕）按下後不碰買家的 Ajax 購物車，而是用 Storefront API
  #   **另建一個 cart**，再導向該 cart 的 `checkoutUrl`（`/cart/c/{token}?key=…` ⇒ 302 結帳頁）。hoko.vip 2026-09-05
  #   抓包（external-facts §G26）：標頭 `X-Shopify-Storefront-Access-Token`／`X-SDK-Variant: portable-wallets`／
  #   `X-Wallet-Name: BuyItNow`／`X-Start-Wallet-Checkout: true`；變數
  #   `{"input":{"lines":[{"merchandiseId":"gid://shopify/ProductVariant/{id}","quantity":1,"attributes":[]}],"discountCodes":[]},"country":"TW","language":"ZH_CN"}`；
  #   回應 `{"data":{"result":{"cart":{…CartParts…},"errors":[],"warnings":[]}},"extensions":{"context":{…},"cart_changelog":"…"}}`。
  # ②怎麼做：**不是** GraphQL 執行器——只認 `operation_name=cartCreate`（query 內含 `cartCreate(`），依 portable-wallets
  #   固定的 `CartParts` fragment 逐鍵回同形 JSON；其餘 operation 一律回 top-level `errors`（鐵律 4 分層：非認證錯用 200）。
  #   完整 Storefront API（任意 query）＝日後獨立包（路線圖），本檔只保證這一支形同、且 URL／標頭／版本段可延展。
  # ③跨功能：`Storefront::AccessToken`（標頭驗證）、`Storefront::CartKeys`（id key／checkout key）、`CartWriter.add`
  #   （`allow_sold_out: true`——本尊對售罄變體照樣建 cart）、`CartController#checkout_link`（`/cart/c/:token` 落地）、
  #   `Checkouts::CreateFromCart`（結帳快照）、`config/routes.rb`（`api/:version/graphql.json`）。
  class ApiController < BaseController
    # 主題 JS 的跨頁 fetch 無 CSRF token（同 CartController；寫入面靠 access token＋限流）。
    skip_forgery_protection

    VARIANT_GID_RE = %r{\Agid://[^/]+/ProductVariant/(\d+)\z}

    rescue_from Storefront::CartError do |e|
      # Storefront API 的業務錯誤走 `userErrors`（本尊 `CartUserError{message field code}`）；HTTP 200（鐵律 4 ①）
      render json: { "data" => { "result" => { "cart" => nil,
                                               "errors" => [ { "message" => e.message, "field" => [ "input", "lines" ], "code" => "INVALID" } ],
                                               "warnings" => [] } } }
    end

    # POST /api/:version/graphql.json
    def graphql
      unless AccessToken.valid?(current_shop.id, request.headers["X-Shopify-Storefront-Access-Token"])
        # 🔴 本尊對錯誤 token 的回應形未取得（91 §3.87）；先照鐵律 4 ③：認證失敗＝非 200
        return render json: { "errors" => [ { "message" => "Invalid Storefront API access token" } ] }, status: :unauthorized
      end

      query = params[:query].to_s
      unless params[:operation_name].to_s == "cartCreate" && query.include?("cartCreate(")
        return render json: { "errors" => [ { "message" => "E18 只實作 cartCreate；其餘 Storefront API operation 尚未支援。" } ] }
      end

      variables = params[:variables].respond_to?(:to_unsafe_h) ? params[:variables].to_unsafe_h : params[:variables].to_h
      render json: cart_create(variables.deep_stringify_keys)
    end

    private

    def cart_create(variables)
      input = variables.fetch("input", {}) || {}
      lines_in = Array(input["lines"])
      raise Storefront::CartError, "至少需要一行商品。" if lines_in.empty?

      cart = ActsAsTenant.with_tenant(current_shop) do
        cart = Cart.create!(shop_id: current_shop.id, attributes_json: {}) # 🔴 獨立於 `_cl_buyer` 的 Ajax 車：不設 cookie
        lines_in.each do |line|
          variant_id = line["merchandiseId"].to_s[VARIANT_GID_RE, 1]
          raise Storefront::CartError, "merchandiseId 格式不正確。" if variant_id.nil?

          properties = Array(line["attributes"]).to_h { |a| [ a["key"].to_s, a["value"].to_s ] }
          CartWriter.add(cart:, variant_id: variant_id.to_i, quantity: line.fetch("quantity", 1), properties:,
                         locale: effective_hit&.locale_tag, allow_sold_out: true)
        end
        cart.reload
      end

      country = variables["country"].presence || input.dig("buyerIdentity", "countryCode").presence || primary_country_code
      language = variables["language"].presence || ThemeEngine::LocaleTags.shopify_code(effective_hit&.locale_tag).tr("-", "_").upcase
      {
        "data" => { "result" => { "cart" => cart_parts(cart), "errors" => [], "warnings" => [] } },
        "extensions" => { "context" => { "country" => country, "language" => language },
                          "cart_changelog" => cart_changelog(cart) }
      }
    end

    # portable-wallets 的 `fragment CartParts on Cart` 逐鍵（鍵序＝抓包回應）。
    def cart_parts(cart)
      currency = current_shop.store_currency
      lines = cart.cart_line_items.includes(product_variant: :product).order(:id).to_a
      subtotal = lines.sum { |l| l.product_variant.price_cents * l.quantity }
      {
        "id" => "gid://chilllove/Cart/#{cart.token}?key=#{CartKeys.id_key(cart.token)}",
        "checkoutUrl" => checkout_url(cart),
        "deliveryGroups" => { "edges" => [] }, # 尚無地址 ⇒ 空（本尊 cartCreate 回應同形）
        "cost" => { "subtotalAmount" => money(subtotal, currency), "totalAmount" => money(subtotal, currency),
                    "totalTaxAmount" => nil, "totalDutyAmount" => nil },
        "discountAllocations" => [],
        "discountCodes" => [], # 🔴 input.discountCodes 非空時的回應形未取得（91 §3.87）：先不套碼
        "lines" => { "edges" => lines.map { |l| { "node" => line_node(l, currency) } } }
      }
    end

    def line_node(line, currency)
      variant = line.product_variant
      total = variant.price_cents * line.quantity
      {
        "parentRelationship" => nil,
        "quantity" => line.quantity,
        "cost" => { "subtotalAmount" => money(total, currency), "totalAmount" => money(total, currency) },
        "discountAllocations" => [],
        "merchandise" => { "requiresShipping" => variant.requires_shipping, "title" => variant.title,
                           "product" => { "title" => variant.product.title } },
        "sellingPlanAllocation" => nil
      }
    end

    # MoneyV2：`amount` 十進位字串（抓包 `"188.0"`——HKD 188.00 ⇒ 去尾零、至少一位小數；🔴 只實測 HKD，
    # zero-decimal 幣別形未取得，91 §3.87）。鐵律 3：儲存 cents ⇒ 序列化層才轉十進位。
    def money(cents, currency)
      { "amount" => (BigDecimal(cents.to_i) / 100).to_s("F"), "currencyCode" => currency }
    end

    def checkout_url(cart)
      "#{request.protocol}#{request.host_with_port}/cart/c/#{cart.token}?key=#{CGI.escape(CartKeys.checkout_key(cart.token))}"
    end

    # 本尊 `extensions.cart_changelog`＝base64（Rails `Base64.encode64` 形：每 60 字元換行）的 JSON
    # `{"items_added":[{"product_id":…,"variant_id":…,"id":"{uuid}","image":null,…}]}`——抓包只見前四鍵（後段截斷，91 §3.87）。
    def cart_changelog(cart)
      items = cart.cart_line_items.includes(:product_variant).map do |l|
        { "product_id" => l.product_variant.product_id, "variant_id" => l.product_variant_id, "id" => SecureRandom.uuid, "image" => nil }
      end
      Base64.encode64(JSON.generate("items_added" => items))
    end

    def primary_country_code
      ActsAsTenant.with_tenant(current_shop) { Market.find_by(is_primary: true)&.primary_country_code }.presence || "HK"
    end
  end
end
