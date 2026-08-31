# frozen_string_literal: true

module Storefront
  # 結帳入口（結帳線第一＋二包；15 F3 的 token URL 面）。
  #
  # ①POST /checkout：從 `_cl_buyer` cookie 的 cart 建立結帳快照（重新快照價格
  #   ——F1 #3；🔴 不扣庫存）⇒ 303 /checkouts/<token>。
  # ②GET /checkouts/:token：非主題化結帳頁（85 §6：本尊 checkout 不吃主題）。
  #   第二包接上運送段：國家下拉值域＝active market ∩ 有費率的 zone（85 §6 官方
  #   交集句）；選國後即出運送選項——split On 且多 shipment ⇒ per-shipment 獨立
  #   radio（85 §5.3 實測形）；否則 46c 合併單列。預設選各組最便宜（85 §5.2：
  #   本尊地址填畢即預選最低價並計入 Total）。
  # ③POST /checkouts/:token/delivery：選國＋選費率。🔴 提交＝**server 重驗**
  #   （F3-3）：重新解析當前費率集合，名稱或價格對不上 ⇒ 422＋重選警示
  #   （85 §5.3「The shipping options have changed…」的我方形），絕不收客戶端價。
  #   通過 ⇒ shipping_lines 快照＋shipping_cents ⇒ Calculator 重算 total（鐵律 7
  #   同源：頁面顯示與落庫金額同一個 Result）。
  # ④限流沿 storefront-cart/ip（rack_attack 路徑清單含 /checkout 與 /checkouts/）。
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
      checkout = find_checkout
      return head :not_found if checkout.nil?

      response.headers["X-Robots-Tag"] = "noindex, nofollow" # 結帳頁永不索引（62 §D.2 disallow 同軸）
      render html: page_html(checkout).html_safe, layout: false
    end

    # POST /checkouts/:token/delivery——選國家／選運送方式（③）。
    def delivery
      checkout = find_checkout
      return head :not_found if checkout.nil?

      country = params[:country_code].to_s.upcase
      unless sellable_countries.include?(country)
        return render_page(checkout, error: "此地區目前無法配送。", status: :unprocessable_content)
      end

      result = resolve_rates(checkout, country)
      case result.status
      when :not_sellable
        return render_page(checkout, error: "此地區目前無法配送。", status: :unprocessable_content)
      when :undeliverable
        return render_page(checkout, error: "部分商品目前無法配送到此地區。", status: :unprocessable_content)
      end

      if result.shipments.empty? # 全數位車：無運送段，運費 0（85 §5.1 無 Shipping method 區塊的對位）
        persist_delivery!(checkout, country, result, [])
        return redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
      end

      chosen = pick_options(checkout, result)
      if chosen.nil? # 提交的選項已不在當前集合，或價格已變（F3-3 重驗失敗）
        persist_delivery!(checkout, country, result, default_selection(checkout, result))
        return render_page(checkout, error: "運送選項已變更，請重新確認你的選擇。",
                                     status: :unprocessable_content)
      end

      persist_delivery!(checkout, country, result, chosen)
      redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
    end

    # POST /checkouts/:token/payment——選付款方式＋帳單地址模式（第三包；86 §4）。
    # 🔴 server 重驗：提交的 method id 必須是本店**現行 active** 的方法（商家停用後
    #   客戶端殘留的 radio 不得落庫——與 delivery 的 F3-3 重驗同一紀律）。
    def payment
      checkout = find_checkout
      return head :not_found if checkout.nil?

      method = ActsAsTenant.with_tenant(current_shop) do
        ShopPaymentMethod.where(shop_id: current_shop.id).active
                         .find_by(id: params[:payment_method_id].to_s)
      end
      if method.nil?
        return render_page(checkout, error: "付款方式已變更，請重新選擇。",
                                     status: :unprocessable_content)
      end

      billing_mode = params[:billing_mode].to_s
      billing_mode = "same_as_shipping" unless %w[same_as_shipping different].include?(billing_mode)
      ActsAsTenant.with_tenant(current_shop) do
        checkout.update!(
          payment_method_snapshot: method.snapshot,
          billing_address: checkout.billing_address.merge("mode" => billing_mode)
        )
      end
      redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
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

    def find_checkout
      ActsAsTenant.with_tenant(current_shop) do
        Checkout.find_by(shop_id: current_shop.id, token: params[:token].to_s, status: "open")
      end
    end

    def redirect_to_cart
      redirect_to "/cart", status: :see_other, allow_other_host: false
    end

    def sellable_countries
      @sellable_countries ||= ActsAsTenant.with_tenant(current_shop) do
        Checkouts::RateResolver.sellable_countries(shop: current_shop)
      end
    end

    def resolve_rates(checkout, country)
      ActsAsTenant.with_tenant(current_shop) do
        Checkouts::RateResolver.call(
          shop: current_shop, country_code: country, currency: checkout.currency,
          lines: checkout.line_items_snapshot.map { |l| resolver_line(l) }
        )
      end
    end

    def resolver_line(row)
      {
        key: row["key"], quantity: row["quantity"], unit_price_cents: row["unit_price_cents"],
        # 第一包建立的舊快照缺運送欄：重量當 0、視為需運送、General 歸屬（保守側）
        weight_grams: row.fetch("weight_grams", 0),
        requires_shipping: row.fetch("requires_shipping", true),
        shipping_profile_id: row["shipping_profile_id"]
      }
    end

    # split 形＝shop 開關 On 且多 shipment（85 §5.3：單 shipment 沒有 split 呈現）。
    def split?(result)
      current_shop.split_shipping_enabled && result.shipments.size > 1
    end

    # 提交的選擇 → [{shipment_index:, option:}]；任一格重驗失敗 ⇒ nil（③）。
    # 無選擇參數（只選國家）⇒ 預設選各組最便宜（85 §5.2 本尊行為）。
    def pick_options(_checkout, result)
      if split?(result)
        raw = params[:selections]
        return default_selection(nil, result) if raw.blank?

        picks = result.shipments.each_with_index.map do |shipment, index|
          verify_pick(shipment.options, raw[index.to_s]) || (return nil)
        end
        picks.each_with_index.map { |option, shipment_index| { shipment_index:, option: } }
      else
        raw = params[:option]
        return default_selection(nil, result) if raw.blank?

        option = verify_pick(result.merged_options, raw)
        option ? [ { shipment_index: 0, option: } ] : nil
      end
    end

    # 重驗一格：提交形＝"<name>|<price_cents>"——名稱找得到且價格一致才算數。
    def verify_pick(options, submitted)
      name, price = submitted.to_s.split("|", 2)
      option = options.find { |o| o.name == name }
      return nil if option.nil? || option.price_cents != price.to_i

      option
    end

    def default_selection(_checkout, result)
      if split?(result)
        result.shipments.each_with_index.map do |shipment, shipment_index|
          { shipment_index:, option: shipment.options.first } # options 已按價升冪
        end
      else
        [ { shipment_index: 0, option: result.merged_options.first } ]
      end
    end

    # 落庫＋重算（③後半）：shipping_lines 快照可回放（訂單成立／棄單挽回都要）。
    def persist_delivery!(checkout, country, result, picks)
      shipping_lines = picks.map do |pick|
        shipment = split?(result) ? result.shipments[pick[:shipment_index]] : nil
        {
          "shipment_index" => pick[:shipment_index],
          "shipping_profile_id" => shipment&.shipping_profile_id,
          "line_keys" => shipment ? shipment.line_keys : result.shipments.flat_map(&:line_keys),
          "rate_id" => pick[:option].rate_id,
          "name" => pick[:option].name,
          "price_cents" => pick[:option].price_cents
        }
      end
      shipping_cents = shipping_lines.sum { |l| l["price_cents"] }

      calc = Checkouts::Calculator.call(
        lines: checkout.line_items_snapshot.map { |l|
          { key: l["key"], quantity: l["quantity"], unit_price_cents: l["unit_price_cents"] }
        },
        currency: checkout.currency, shipping_cents: shipping_cents
      )
      ActsAsTenant.with_tenant(current_shop) do
        checkout.update!(
          shipping_address: checkout.shipping_address.merge("country_code" => country),
          shipping_lines: shipping_lines, shipping_cents: shipping_cents,
          subtotal_cents: calc.subtotal_cents, tax_cents: calc.tax_total_cents,
          total_cents: calc.total_cents, presentment_total_cents: calc.total_cents
        )
      end
    end

    def render_page(checkout, error: nil, status: :ok)
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: page_html(checkout.reload, error:).html_safe, layout: false, status:
    end

    # 非主題化結帳頁（85 §6；金額字串＝Money::Display 同一 cents 來源——鐵律 7）。
    def page_html(checkout, error: nil)
      country = checkout.shipping_address["country_code"]
      delivery = delivery_html(checkout, country, error)
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      <<~HTML
        <!doctype html><html><head><title>Checkout</title><meta name="robots" content="noindex"></head>
        <body><h1>結帳</h1><table>#{line_rows(checkout)}</table>
        #{delivery}
        <p data-checkout-shipping>運費：#{checkout.currency} #{Money::Display.call(Money::Storage.from_cents(checkout.shipping_cents, checkout.currency))}</p>
        <p data-checkout-total>#{checkout.currency} #{total}</p>
        #{payment_html(checkout)}</body></html>
      HTML
    end

    # 付款段（第三包；86 §4 實測形）：單一方法無 radio、多方法手風琴、
    # 零方法＝無法接受付款（86 §4 官方字面的我方文案）；帳單地址 radio 恰兩值。
    # 「完成訂單」鈕＝佔位 disabled（訂單成立走 F5 包——按鈕先立形，不接假流程）。
    def payment_html(checkout)
      methods = ActsAsTenant.with_tenant(current_shop) do
        ShopPaymentMethod.where(shop_id: current_shop.id).active.ordered.to_a
      end
      if methods.empty?
        return "<section data-payment><h2>付款</h2>" \
               "<p data-payment-unavailable>此商店目前無法接受付款。</p></section>"
      end

      chosen_id = checkout.payment_method_snapshot["id"]
      rows = methods.map do |m|
        selected = chosen_id ? chosen_id == m.id : m == methods.first
        details = selected && m.additional_details.present? ?
                    "<p data-payment-details>#{ERB::Util.html_escape(m.additional_details)}</p>" : ""
        radio = methods.size > 1 ?
                  "<input type=\"radio\" name=\"payment_method_id\" value=\"#{m.id}\"#{' checked' if selected}>" : ""
        "<label>#{radio}#{ERB::Util.html_escape(m.name)}</label>#{details}"
      end.join
      billing_mode = checkout.billing_address["mode"] || "same_as_shipping"
      <<~HTML
        <section data-payment><h2>付款</h2>
        <p>所有交易均經安全加密。</p>
        <form method="post" action="/checkouts/#{checkout.token}/payment">
        #{methods.size == 1 ? "<input type=\"hidden\" name=\"payment_method_id\" value=\"#{methods.first.id}\">" : ''}
        <fieldset data-payment-methods>#{rows}</fieldset>
        <fieldset data-billing-address><legend>帳單地址</legend>
        <label><input type="radio" name="billing_mode" value="same_as_shipping"#{' checked' if billing_mode == 'same_as_shipping'}>與收貨地址相同</label>
        <label><input type="radio" name="billing_mode" value="different"#{' checked' if billing_mode == 'different'}>使用不同的帳單地址</label>
        </fieldset>
        <button type="submit">更新付款方式</button>
        </form>
        <button type="button" data-complete-order disabled>完成訂單</button>
        <p data-complete-note>訂單成立隨後續結帳包接上。</p>
        </section>
      HTML
    end

    def line_rows(checkout)
      checkout.line_items_snapshot.map do |line|
        amount = Money::Display.call(
          Money::Storage.from_cents(line["unit_price_cents"] * line["quantity"], checkout.currency)
        )
        "<tr><td>#{ERB::Util.html_escape(line['title'])} × #{line['quantity']}</td>" \
          "<td>#{checkout.currency} #{amount}</td></tr>"
      end.join
    end

    # 運送段：國家表單＋（已選國時）選項清單。
    def delivery_html(checkout, country, error)
      options_html =
        if country.present?
          result = resolve_rates(checkout, country)
          rates_html(checkout, result)
        else
          # 85 §5.1 本尊逐字語義的我方文案（地址未齊 ⇒ 不出費率）
          "<p data-shipping-hint>請先選擇配送地區以查看可用的運送方式。</p>"
        end
      <<~HTML
        <section data-delivery>
        #{error ? "<p data-delivery-error>#{ERB::Util.html_escape(error)}</p>" : ''}
        <form method="post" action="/checkouts/#{checkout.token}/delivery">
        <label>配送地區
        <select name="country_code">#{country_options(country)}</select></label>
        #{options_html}
        <button type="submit">更新運送方式</button>
        </form></section>
      HTML
    end

    def country_options(selected)
      sellable_countries.map do |code|
        %(<option value="#{code}"#{' selected' if code == selected}>#{code}</option>)
      end.join
    end

    def rates_html(checkout, result)
      return "<p data-shipping-unavailable>部分商品目前無法配送到此地區。</p>" unless result.ok?
      return "" if result.shipments.empty? # 全數位商品：無運送段

      chosen = checkout.shipping_lines.to_h { |l| [ l["shipment_index"], l["name"] ] }
      if split?(result)
        heading = "<p data-split-note>你的訂單將分 #{result.shipments.size} 件出貨，" \
                  "每件可分別選擇運送方式。</p>"
        heading + result.shipments.each_with_index.map do |shipment, index|
          rows = shipment.options.map do |option|
            radio(name: "selections[#{index}]", option:, checkout:,
                  checked: chosen[index] ? chosen[index] == option.name : option == shipment.options.first)
          end.join
          "<fieldset data-shipment=\"#{index}\"><legend>第 #{index + 1} 件（#{shipment.line_keys.size} 項商品）</legend>#{rows}</fieldset>"
        end.join
      else
        rows = result.merged_options.map do |option|
          radio(name: "option", option:, checkout:,
                checked: chosen[0] ? chosen[0] == option.name : option == result.merged_options.first)
        end.join
        "<fieldset data-shipping-options>#{rows}</fieldset>"
      end
    end

    def radio(name:, option:, checkout:, checked:)
      price = option.price_cents.zero? ? "免運" :
                "#{checkout.currency} #{Money::Display.call(Money::Storage.from_cents(option.price_cents, checkout.currency))}"
      value = ERB::Util.html_escape("#{option.name}|#{option.price_cents}")
      "<label><input type=\"radio\" name=\"#{name}\" value=\"#{value}\"#{' checked' if checked}>" \
        "#{ERB::Util.html_escape(option.name)}（#{price}）#{transit_label(option)}</label>"
    end

    # transit 秒制區間 → 「N–M 個工作天」；None ⇒ 不顯示（85 §3）。
    def transit_label(option)
      return "" if option.min_transit_seconds.nil?

      min_days = option.min_transit_seconds / 86_400
      max_days = option.max_transit_seconds / 86_400
      "（#{min_days}–#{max_days} 個工作天）"
    end
  end
end
