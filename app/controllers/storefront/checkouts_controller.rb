# frozen_string_literal: true

module Storefront
  # 結帳入口（結帳線第一包；15 F3 的 token URL 面——one-page UI 隨後續包）。
  #
  # ①POST /checkout：從 `_cl_buyer` cookie 的 cart 建立結帳快照（重新快照價格
  #   ——F1 #3；🔴 不扣庫存）⇒ 302 /checkouts/<token>。
  # ②GET /checkouts/:token：極簡摘要頁（v1 佔位；本尊結帳不吃主題——非主題化頁）。
  #   token 64 hex＝不可枚舉；查無 ⇒ 404。
  # ③限流沿 storefront-cart/ip（rack_attack 路徑清單含 /checkout——建立結帳是寫入）。
  class CheckoutsController < BaseController
    skip_forgery_protection

    # POST /checkout
    def create
      cart = current_cart
      return redirect_to_cart if cart.nil? || cart.cart_line_items.none?

      checkout = ActsAsTenant.with_tenant(current_shop) { Checkouts::CreateFromCart.call(cart:) }
      redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
    rescue Checkouts::CreateFromCart::Error
      redirect_to_cart
    end

    # GET /checkouts/:token
    def show
      checkout = ActsAsTenant.with_tenant(current_shop) do
        Checkout.find_by(shop_id: current_shop.id, token: params[:token].to_s)
      end
      return head :not_found if checkout.nil?

      response.headers["X-Robots-Tag"] = "noindex, nofollow" # 結帳頁永不索引（62 §D.2 disallow 同軸）
      render html: summary_html(checkout).html_safe, layout: false
    end

    private

    COOKIE = "_cl_buyer"

    def current_cart
      token = cookies.signed[COOKIE]
      return nil if token.blank?

      ActsAsTenant.with_tenant(current_shop) do
        Cart.includes(cart_line_items: { product_variant: :product })
            .find_by(shop_id: current_shop.id, token: token)
      end
    end

    def redirect_to_cart
      redirect_to "/cart", status: :see_other, allow_other_host: false
    end

    # v1 佔位摘要（非主題化；金額字串＝Money::Display 同一 cents 來源——鐵律 7）。
    def summary_html(checkout)
      rows = checkout.line_items_snapshot.map do |line|
        amount = Money::Display.call(
          Money::Storage.from_cents(line["unit_price_cents"] * line["quantity"], checkout.currency)
        )
        "<tr><td>#{ERB::Util.html_escape(line['title'])} × #{line['quantity']}</td>" \
          "<td>#{checkout.currency} #{amount}</td></tr>"
      end.join
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      <<~HTML
        <!doctype html><html><head><title>Checkout</title><meta name="robots" content="noindex"></head>
        <body><h1>結帳</h1><table>#{rows}</table>
        <p data-checkout-total>#{checkout.currency} #{total}</p>
        <p>付款與配送步驟隨後續結帳包接上。</p></body></html>
      HTML
    end
  end
end
