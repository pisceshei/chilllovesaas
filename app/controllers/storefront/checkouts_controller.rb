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

      raw_id = params[:payment_method_id].to_s
      snapshot =
        if raw_id.start_with?("psp:")
          psp_method_snapshot(raw_id) # G6-1c：server 重驗三層交集（F4.2）
        else
          method = ActsAsTenant.with_tenant(current_shop) do
            ShopPaymentMethod.where(shop_id: current_shop.id).active.find_by(id: raw_id)
          end
          method&.snapshot
        end
      if snapshot.nil?
        return render_page(checkout, error: "付款方式已變更，請重新選擇。",
                                     status: :unprocessable_content)
      end

      billing_mode = params[:billing_mode].to_s
      billing_mode = "same_as_shipping" unless %w[same_as_shipping different].include?(billing_mode)
      ActsAsTenant.with_tenant(current_shop) do
        checkout.update!(
          payment_method_snapshot: snapshot,
          billing_address: checkout.billing_address.merge("mode" => billing_mode)
        )
      end
      redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
    end

    # POST /checkouts/:token/pay——PSP 線上付款起手（G6-1c：QR 原生流）。
    # 建 intent（request_id="pi-<token>-<total_cents>"＝Airwallex 側冪等，15-F4-1；
    # 同 checkout 重按恆同 intent）→ confirm(flow: qrcode) → 渲染 QR＋輪詢頁。
    # 🔴 外部 IO 全在 DB 交易外（鐵律 5）；金額走 Money 契約唯一出口。
    def pay
      checkout = find_checkout
      return head :not_found if checkout.nil?

      snapshot = checkout.payment_method_snapshot
      # 🔴 server 重驗＝與渲染同一個三層交集（enabled ∩ available ∩ 平台已實作）：
      # 快照殘留（商家事後關閉該方式）不得起付（F3-3 同紀律；Q7 實紅過）。
      still_offered = snapshot["kind"] == "psp" &&
                      psp_payment_options.any? { |value, _| value == snapshot["id"] }
      unless still_offered
        return render_page(checkout, error: "此付款方式不支援線上付款，請重新選擇。",
                                     status: :unprocessable_content)
      end

      provider_row = configured_provider(snapshot["provider"].to_s)
      if provider_row.nil?
        return render_page(checkout, error: "付款服務暫時無法使用，請稍後再試。",
                                     status: :unprocessable_content)
      end

      intents = Psp::Airwallex::PaymentIntents.new(provider_row)
      amount = Money::Storage.from_cents(checkout.total_cents, checkout.currency)
      begin
        intent = intents.create(
          amount:, request_id: "pi-#{checkout.token}-#{checkout.total_cents}",
          merchant_order_id: checkout.token
        )
        ActsAsTenant.with_tenant(current_shop) { checkout.update!(psp_intent_id: intent.fetch("id")) }
        confirmed = intents.confirm_qr(intent.fetch("id"), method: snapshot["method_type"])
      rescue Psp::Airwallex::Client::Error => error
        return render_page(checkout, error: "付款服務回應異常：#{ERB::Util.html_escape(error.message)}",
                                     status: :unprocessable_content)
      end

      qrcode = confirmed.dig("next_action", "qrcode").to_s
      if confirmed["status"] == "SUCCEEDED"
        return redirect_to "/checkouts/#{checkout.token}/pay/status?html=1", status: :see_other,
                           allow_other_host: false
      end
      if qrcode.blank?
        return render_page(checkout, error: "未取得付款 QR code，請重試或換一種付款方式。",
                                     status: :unprocessable_content)
      end

      render html: qr_page_html(checkout, snapshot["name"].to_s, qrcode).html_safe, layout: false
    end

    # GET /checkouts/:token/pay/status——輪詢終點（JSON；?html=1 供無 JS 後備導轉）。
    # SUCCEEDED ⇒ FinalizePspPayment（與 webhook 消費同終點、同冪等鍵——先到先贏）。
    # 🔴 intent status 官方明言 not exhaustive ⇒ 未知值一律當 pending，不 raise。
    def pay_status
      checkout = find_checkout
      checkout ||= ActsAsTenant.with_tenant(current_shop) { Checkout.find_by(token: params[:token].to_s) }
      return head :not_found if checkout.nil? || checkout.psp_intent_id.blank?

      snapshot = checkout.payment_method_snapshot
      provider_row = configured_provider(snapshot["provider"].to_s)
      return head :not_found if provider_row.nil?

      intent = Psp::Airwallex::PaymentIntents.new(provider_row).get(checkout.psp_intent_id)
      status = intent["status"].to_s
      if status == "SUCCEEDED"
        amount_storage = Money.from_psp_amount(intent.fetch("amount"),
                                               currency: intent.fetch("currency"),
                                               psp: snapshot["provider"])
        begin
          Orders::FinalizePspPayment.call(
            shop: current_shop, checkout_token: checkout.token,
            provider: snapshot["provider"], psp_reference: checkout.psp_intent_id,
            amount_storage:
          )
        rescue Orders::FinalizePspPayment::AmountMismatch => error
          Money.instrument_failure(direction: :inbound, psp: snapshot["provider"],
                                   currency: checkout.currency, error:)
          return render json: { status: "amount_mismatch" }, status: :unprocessable_content
        end
        target = "/checkouts/#{checkout.token}/complete"
        return redirect_to target, status: :see_other, allow_other_host: false if params[:html].present?

        return render json: { status: "succeeded", redirect: target }
      end

      attempt = intent.dig("latest_payment_attempt", "status").to_s
      mapped =
        if status == "CANCELLED" then "cancelled"
        elsif attempt == "EXPIRED" then "expired"
        else "pending"
        end
      return redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false if params[:html].present?

      render json: { status: mapped }
    rescue Psp::Airwallex::Client::Error
      render json: { status: "pending" } # 上游暫時異常 ⇒ 客戶端續輪詢
    end

    # POST /checkouts/:token/complete——訂單成立（G6-0(a)；15-F5 manual 形）。
    # 冪等鍵＝per-checkout 穩定派生（雙擊/重試同 key ⇒ Guard replay 回同一張單）。
    def complete
      checkout = find_checkout
      return head :not_found if checkout.nil? && completed_order_for(params[:token].to_s).nil?
      # 已完成（重整/回上一頁再提交）⇒ 直接進 thank-you
      return redirect_to "/checkouts/#{params[:token]}/complete", status: :see_other if checkout.nil?

      # 🔴 G6-1c：PSP 快照不得走 manual 成單——沒付錢就出單。線上付款一律 /pay。
      if checkout.payment_method_snapshot["kind"] == "psp"
        return render_page(checkout, error: "此付款方式需完成線上付款。",
                                     status: :unprocessable_content)
      end

      outcome = Orders::CreateFromCheckout.call(
        shop: current_shop, checkout_token: checkout.token,
        idempotency_key: "order-#{checkout.token}", cart: current_cart
      )
      if outcome[:resource]
        redirect_to "/checkouts/#{checkout.token}/complete", status: :see_other,
                    allow_other_host: false
      else
        # replay 命中但訂單其後被刪（11 §2.1(b) 末列）：回結帳頁重走
        redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
      end
    rescue Orders::CreateFromCheckout::Failure => e
      render_page(checkout, error: e.message, status: :unprocessable_content)
    rescue Idempotency::Guard::Conflict
      # 另一個提交進行中：導回結帳頁，讓買家稍後重試（同 key）
      redirect_to "/checkouts/#{params[:token]}", status: :see_other, allow_other_host: false
    end

    # GET /checkouts/:token/complete——thank-you 頁（15-F6：單號＋摘要＋付款指示）。
    def thank_you
      order = completed_order_for(params[:token].to_s)
      return redirect_to "/checkouts/#{params[:token]}", status: :see_other, allow_other_host: false if order.nil?

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: thank_you_html(order).html_safe, layout: false
    end

    private

    COOKIE = "_cl_buyer"

    def completed_order_for(token)
      ActsAsTenant.with_tenant(current_shop) do
        checkout = Checkout.find_by(shop_id: current_shop.id, token:, status: "completed")
        checkout && Order.find_by(shop_id: current_shop.id, checkout_id: checkout.id)
      end
    end

    # thank-you（非主題化；86 §3 helper②：payment_instructions 顯示在下單確認頁）。
    def thank_you_html(order)
      checkout = ActsAsTenant.with_tenant(current_shop) { Checkout.find(order.checkout_id) }
      instructions = checkout.payment_method_snapshot["payment_instructions"]
      method_name = checkout.payment_method_snapshot["name"]
      total = Money::Display.call(Money::Storage.from_cents(order.total_cents, order.currency))
      rows = ActsAsTenant.with_tenant(current_shop) do
        order.line_items.order(:id).map do |li|
          amount = Money::Display.call(Money::Storage.from_cents(li.total_cents, order.currency))
          "<tr><td>#{ERB::Util.html_escape(li.title)} × #{li.quantity}</td>" \
            "<td>#{order.currency} #{amount}</td></tr>"
        end.join
      end
      <<~HTML
        <!doctype html><html><head><title>Order #{ERB::Util.html_escape(order.name)}</title>
        <meta name="robots" content="noindex"></head>
        <body><h1>感謝你的訂購！</h1>
        <p data-order-name>訂單編號：#{ERB::Util.html_escape(order.name)}</p>
        <table>#{rows}</table>
        <p data-order-total>合計：#{order.currency} #{total}</p>
        <section data-payment-instructions><h2>付款方式：#{ERB::Util.html_escape(method_name.to_s)}</h2>
        #{instructions.present? ? "<p>#{ERB::Util.html_escape(instructions)}</p>" : ''}</section>
        <p>訂單確認信與後續出貨通知隨對應功能包接上。</p></body></html>
      HTML
    end

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
      # G6-1c：PSP 選項＝enabled ∩ available ∩ 平台已實作（F4.2：不可用＝**不出現**）。
      psp_options = psp_payment_options
      if methods.empty? && psp_options.empty?
        return "<section data-payment><h2>付款</h2>" \
               "<p data-payment-unavailable>此商店目前無法接受付款。</p></section>"
      end

      chosen_id = checkout.payment_method_snapshot["id"]
      total_options = methods.size + psp_options.size
      first_value = psp_options.first&.first || methods.first&.id
      rows = psp_options.map do |value, label|
        selected = chosen_id ? chosen_id == value : value == first_value
        radio = total_options > 1 ?
                  "<input type=\"radio\" name=\"payment_method_id\" value=\"#{value}\"#{' checked' if selected}>" : ""
        "<label data-psp-method>#{radio}#{ERB::Util.html_escape(label)}</label>"
      end.join
      rows += methods.map do |m|
        selected = chosen_id ? chosen_id == m.id : (psp_options.empty? && m == methods.first)
        details = selected && m.additional_details.present? ?
                    "<p data-payment-details>#{ERB::Util.html_escape(m.additional_details)}</p>" : ""
        radio = total_options > 1 ?
                  "<input type=\"radio\" name=\"payment_method_id\" value=\"#{m.id}\"#{' checked' if selected}>" : ""
        "<label>#{radio}#{ERB::Util.html_escape(m.name)}</label>#{details}"
      end.join
      billing_mode = checkout.billing_address["mode"] || "same_as_shipping"
      <<~HTML
        <section data-payment><h2>付款</h2>
        <p>所有交易均經安全加密。</p>
        <form method="post" action="/checkouts/#{checkout.token}/payment">
        #{total_options == 1 ? "<input type=\"hidden\" name=\"payment_method_id\" value=\"#{first_value}\">" : ''}
        <fieldset data-payment-methods>#{rows}</fieldset>
        <fieldset data-billing-address><legend>帳單地址</legend>
        <label><input type="radio" name="billing_mode" value="same_as_shipping"#{' checked' if billing_mode == 'same_as_shipping'}>與收貨地址相同</label>
        <label><input type="radio" name="billing_mode" value="different"#{' checked' if billing_mode == 'different'}>使用不同的帳單地址</label>
        </fieldset>
        <button type="submit">更新付款方式</button>
        </form>
        #{complete_button_html(checkout)}
        </section>
      HTML
    end

    # 完成訂單鈕（G6-0(a) 點亮）：運送（需運送時）與付款方式都已選才可提交；
    # 未就緒＝disabled＋原因（本尊同型：結帳鈕依前置灰化）。
    def complete_button_html(checkout)
      requires_shipping = checkout.line_items_snapshot.any? { |l| l.fetch("requires_shipping", true) }
      missing =
        if requires_shipping && checkout.shipping_lines.blank?
          "請先選擇運送方式"
        elsif checkout.payment_method_snapshot["method_type"].blank?
          "請先選擇付款方式"
        end
      if missing
        "<button type=\"button\" data-complete-order disabled>完成訂單</button>" \
          "<p data-complete-note>#{missing}。</p>"
      elsif checkout.payment_method_snapshot["kind"] == "psp"
        # G6-1c：PSP 方式的完成鈕走 /pay（線上付款起手），文案帶方式名。
        name = ERB::Util.html_escape(checkout.payment_method_snapshot["name"].to_s)
        <<~HTML
          <form method="post" action="/checkouts/#{checkout.token}/pay" data-pay-form>
          <button type="submit" data-complete-order>以 #{name} 付款</button>
          </form>
        HTML
      else
        <<~HTML
          <form method="post" action="/checkouts/#{checkout.token}/complete" data-complete-form>
          <button type="submit" data-complete-order>完成訂單</button>
          </form>
        HTML
      end
    end

    # PSP 可下單選項（G6-1c）：[["psp:airwallex:alipayhk", "AlipayHK"], …]。
    # 三層交集（F4.2）：商家白名單 enabled ∩ 帳號能力 available ∩ 平台已實作
    # checkout_supported_methods；provider 未存憑證（無指紋）＝未配置 ⇒ 空集合。
    # ⚠️ status 欄不參與（activation 狀態機隨 G6-3——本階段以「憑證已配置」為門）。
    def psp_payment_options
      row = configured_provider("airwallex")
      return [] if row.nil?

      supported = supported_psp_codes
      labels = ShopPaymentProvider.method_dictionary("airwallex").to_h { |m| [ m[:code].to_s, m[:label].to_s ] }
      (row.enabled_methods & row.available_methods & supported).filter_map do |code|
        label = labels[code]
        label && [ "psp:airwallex:#{code}", label ]
      end
    end

    def supported_psp_codes
      Limits.enum(:psp_integration, :airwallex, :checkout_supported_methods).map(&:downcase)
    end

    def configured_provider(provider)
      return nil if provider.blank?

      row = ActsAsTenant.with_tenant(current_shop) do
        ShopPaymentProvider.find_by(provider:)
      end
      row&.api_secret_fingerprint.present? ? row : nil
    end

    # psp:<provider>:<code> → 快照（server 重驗三層交集；殘留 radio 不得落庫）。
    def psp_method_snapshot(raw_id)
      _, provider, code = raw_id.split(":", 3)
      option = psp_payment_options.find { |value, _| value == "psp:#{provider}:#{code}" }
      return nil if option.nil?

      { "id" => option.first, "kind" => "psp", "provider" => provider,
        "method_type" => code, "name" => option.last }
    end

    # QR 付款頁（G6-1c）：伺服端 rqrcode 出 SVG；輪詢 GET /pay/status（🔴 GET 不吃
    # storefront-cart/ip 的 POST throttle——輪詢 3 秒一發、QR 十分鐘）。
    # 🔴 本頁 inline <script> 是 storefront 第一個第一方 JS（先例登記於 worklog）。
    def qr_page_html(checkout, method_name, qrcode)
      svg = RQRCode::QRCode.new(qrcode).as_svg(module_size: 5, viewbox: true)
      poll_ms = Limits.fetch(:psp_integration, :airwallex, :status_poll_interval_seconds) * 1000
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      <<~HTML
        <!DOCTYPE html><html lang="zh-Hant"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex">
        <title>以 #{ERB::Util.html_escape(method_name)} 付款</title></head><body>
        <main data-psp-qr style="max-width:420px;margin:40px auto;text-align:center;font-family:system-ui">
        <h1>以 #{ERB::Util.html_escape(method_name)} 付款</h1>
        <p>應付金額：#{checkout.currency} #{total}</p>
        <div data-qrcode style="max-width:280px;margin:0 auto">#{svg}</div>
        <p>請以 #{ERB::Util.html_escape(method_name)} App 掃描上方 QR code 完成付款。</p>
        <p data-pay-state>等待付款中…（QR code 十分鐘內有效）</p>
        <p><a href="/checkouts/#{checkout.token}">返回結帳頁</a></p>
        <script>
        (function () {
          var url = "/checkouts/#{checkout.token}/pay/status";
          var state = document.querySelector("[data-pay-state]");
          function tick() {
            fetch(url, { headers: { "Accept": "application/json" } })
              .then(function (r) { return r.json(); })
              .then(function (d) {
                if (d.status === "succeeded" && d.redirect) { window.location = d.redirect; return; }
                if (d.status === "cancelled") { state.textContent = "付款已取消。"; return; }
                if (d.status === "expired") { state.textContent = "QR code 已過期，請返回結帳頁重試。"; return; }
                setTimeout(tick, #{poll_ms});
              })
              .catch(function () { setTimeout(tick, #{poll_ms}); });
          }
          setTimeout(tick, #{poll_ms});
        })();
        </script>
        </main></body></html>
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
