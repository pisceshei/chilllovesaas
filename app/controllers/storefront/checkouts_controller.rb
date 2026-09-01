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
      # 步 9b：/discount/:code 分享連結落的 cookie 在此兌現（官方同形：進站帶碼）。
      if (pending = Discount.normalize_code(cookies[:pending_discount_code]))
        ActsAsTenant.with_tenant(current_shop) { checkout.update!(discount_code: pending) }
        cookies.delete(:pending_discount_code)
        refresh_discounts!(checkout.reload)
      end
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
        return render_page(checkout, error: "We can't ship to this region.", status: :unprocessable_content)
      end

      result = resolve_rates(checkout, country)
      case result.status
      when :not_sellable
        return render_page(checkout, error: "We can't ship to this region.", status: :unprocessable_content)
      when :undeliverable
        return render_page(checkout, error: "Some items can't be shipped to this region.", status: :unprocessable_content)
      end

      if result.shipments.empty? # 全數位車：無運送段，運費 0（85 §5.1 無 Shipping method 區塊的對位）
        persist_delivery!(checkout, country, result, [])
        return redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
      end

      chosen = pick_options(checkout, result)
      if chosen.nil? # 提交的選項已不在當前集合，或價格已變（F3-3 重驗失敗）
        persist_delivery!(checkout, country, result, default_selection(checkout, result))
        return render_page(checkout, error: "The shipping options have changed. Please review your selection.",
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
        return render_page(checkout, error: "The payment methods have changed. Please choose again.",
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

    # POST /checkouts/:token/submit——G6-4 整頁單表單提交（87 號實測：本尊
    # Pay now＝一次送出全部欄位；欄位變更的 JS 自動儲存也走本路、帶 refresh=1）。
    # 順序：contact → delivery（沿用 F3-3 重驗）→ payment（沿用 active 重驗）→
    # refresh ⇒ 303 回頁；否則必填檢查 ⇒ 307 保 POST 接 /pay（psp）或 /complete（manual）。
    def submit
      checkout = find_checkout
      return head :not_found if checkout.nil?

      persist_contact!(checkout)

      country = params[:country_code].to_s.upcase
      if country.present?
        unless sellable_countries.include?(country)
          return render_page(checkout, error: "We can't ship to this region.", status: :unprocessable_content)
        end

        result = resolve_rates(checkout, country)
        case result.status
        when :not_sellable
          return render_page(checkout, error: "We can't ship to this region.", status: :unprocessable_content)
        when :undeliverable
          return render_page(checkout, error: "Some items can't be shipped to this region.",
                                       status: :unprocessable_content)
        end
        picks = result.shipments.empty? ? [] : (pick_options(checkout, result) || default_selection(checkout, result))
        persist_delivery!(checkout, country, result, picks, address: address_params)
      end

      if params[:payment_method_id].present?
        raw_id = params[:payment_method_id].to_s
        snapshot =
          if raw_id.start_with?("psp:")
            psp_method_snapshot(raw_id)
          else
            method = ActsAsTenant.with_tenant(current_shop) do
              ShopPaymentMethod.where(shop_id: current_shop.id).active.find_by(id: raw_id)
            end
            method&.snapshot
          end
        if snapshot.nil?
          return render_page(checkout, error: "The payment methods have changed. Please choose again.",
                                       status: :unprocessable_content)
        end
        ActsAsTenant.with_tenant(current_shop) { checkout.update!(payment_method_snapshot: snapshot) }
      end
      persist_billing!(checkout)

      if params[:refresh].present? # JS 自動儲存：只落庫，不前進
        return redirect_to "/checkouts/#{checkout.token}", status: :see_other, allow_other_host: false
      end

      checkout.reload
      missing = missing_required_fields(checkout)
      if missing.any?
        return render_page(checkout, error: "Please fill in the required fields: #{missing.join(', ')}.",
                                     status: :unprocessable_content)
      end

      # 307＝保 POST（Rails 官方 status 支援）：/pay 與 /complete 的既有重驗與冪等原樣生效。
      target = checkout.payment_method_snapshot["kind"] == "psp" ? "pay" : "complete"
      redirect_to "/checkouts/#{checkout.token}/#{target}", status: :temporary_redirect,
                  allow_other_host: false
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
        return render_page(checkout, error: "This payment method is no longer available. Please choose again.",
                                     status: :unprocessable_content)
      end

      provider_row = configured_provider(snapshot["provider"].to_s)
      if provider_row.nil?
        return render_page(checkout, error: "The payment service is temporarily unavailable. Please try again later.",
                                     status: :unprocessable_content)
      end

      # card／wallets ⇒ SDK 頁（confirm 在瀏覽器）；alipayhk/fps ⇒ server confirm 出 QR。
      return pay_sdk(checkout, snapshot, provider_row) if %w[card applepay googlepay].include?(snapshot["method_type"])

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
        return render_page(checkout, error: "The payment service returned an error: #{ERB::Util.html_escape(error.message)}",
                                     status: :unprocessable_content)
      end

      qrcode = confirmed.dig("next_action", "qrcode").to_s
      if confirmed["status"] == "SUCCEEDED"
        return redirect_to "/checkouts/#{checkout.token}/pay/status?html=1", status: :see_other,
                           allow_other_host: false
      end
      if qrcode.blank?
        return render_page(checkout, error: "We couldn't get a payment QR code. Please retry or choose another payment method.",
                                     status: :unprocessable_content)
      end

      render html: qr_page_html(checkout, snapshot["name"].to_s, qrcode).html_safe, layout: false
    end

    # G6-1d：card／wallet 走 components-sdk（confirm 在瀏覽器；QR 雙式走上面的
    # server confirm）。intent 建立同一把 request_id ⇒ 兩型重按恆同 intent。
    def pay_sdk(checkout, snapshot, provider_row)
      intents = Psp::Airwallex::PaymentIntents.new(provider_row)
      amount = Money::Storage.from_cents(checkout.total_cents, checkout.currency)
      begin
        intent = intents.create(
          amount:, request_id: "pi-#{checkout.token}-#{checkout.total_cents}",
          merchant_order_id: checkout.token
        )
      rescue Psp::Airwallex::Client::Error => error
        return render_page(checkout, error: "The payment service returned an error: #{ERB::Util.html_escape(error.message)}",
                                     status: :unprocessable_content)
      end
      ActsAsTenant.with_tenant(current_shop) { checkout.update!(psp_intent_id: intent.fetch("id")) }

      html =
        if snapshot["method_type"] == "card"
          card_pay_page_html(checkout, intent, provider_row)
        else
          wallet_pay_page_html(checkout, intent, provider_row, snapshot)
        end
      render html: html.html_safe, layout: false
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
        return render_page(checkout, error: "This payment method requires completing payment online.",
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

    # G6 步 9b：折扣碼套用/移除（結帳頁輸入欄；17-F4.1 統一錯誤文案）。
    # 空 code＝移除。重算走 refresh_discounts!（delivery 重算的同一條 Engine→
    # Calculator 鏈——鐵律 7 不開第二條）。
    def apply_discount
      checkout = find_checkout
      return head :not_found if checkout.nil? || checkout.status != "open"

      code = Discount.normalize_code(params[:code])
      ActsAsTenant.with_tenant(current_shop) { checkout.update!(discount_code: code) }
      error = refresh_discounts!(checkout.reload)
      if error
        ActsAsTenant.with_tenant(current_shop) { checkout.update!(discount_code: nil) }
        refresh_discounts!(checkout.reload)
        return render_page(checkout, error:, status: :unprocessable_content)
      end

      redirect_to storefront_checkout_show_path(token: checkout.token)
    end

    # G6 步 9b：/discount/:code 分享連結——碼落 cookie，結帳建立時套用
    # （官方同形：連結進站 → 結帳自動帶碼）。
    def discount_link
      code = Discount.normalize_code(params[:code])
      cookies[:pending_discount_code] = { value: code, expires: 1.day } if code
      redirect_to "/"
    end

    # G6 步 7：挽回連結（89 §8）。token 不存在 ⇒ 404；已成單 ⇒ thank-you 頁
    # （官方 recovered 後連結仍可看訂單狀態）；活單 ⇒ 302 回結帳頁續走。
    def recover
      checkout = ActsAsTenant.with_tenant(current_shop) do
        Checkout.find_by(recovery_token: params[:recovery_token].to_s)
      end
      return head :not_found if checkout.nil?

      if ActsAsTenant.with_tenant(current_shop) { Order.where(checkout_id: checkout.id).exists? }
        redirect_to storefront_checkout_thank_you_path(token: checkout.token)
      else
        redirect_to storefront_checkout_show_path(token: checkout.token)
      end
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
        <!doctype html><html lang="zh-Hant"><head><title>Order #{ERB::Util.html_escape(order.name)}</title>
        #{checkout_head}</head>
        <body class="ck">
        <header class="ck-header"><a class="ck-brand" href="/">#{ERB::Util.html_escape(current_shop.name)}</a></header>
        <main class="ck-thanks"><div class="ck-card">
        <h1>感謝你的訂購！</h1>
        <p data-order-name>訂單編號：#{ERB::Util.html_escape(order.name)}</p>
        <table>#{rows}</table>
        <p data-order-total>合計：#{order.currency} #{total}</p>
        <section data-payment-instructions><h2>付款方式：#{ERB::Util.html_escape(method_name.to_s)}</h2>
        #{instructions.present? ? "<p>#{ERB::Util.html_escape(instructions)}</p>" : ''}</section>
        <p>訂單確認信與後續出貨通知隨對應功能包接上。</p>
        <p><a href="/">繼續購物</a></p>
        </div></main></body></html>
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
    # address:（G6-4）＝整頁提交帶進來的收貨地址欄（87 §3），與國碼一起 merge。
    def persist_delivery!(checkout, country, result, picks, address: {})
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

      lines = checkout.line_items_snapshot.map { |l|
        { key: l["key"], quantity: l["quantity"], unit_price_cents: l["unit_price_cents"],
          variant_id: l["variant_id"] }
      }
      # 步 9a：折扣求值（Engine 解析 → Calculator 算錢＝鐵律 7 唯一金額計算點）。
      evaluation = ActsAsTenant.with_tenant(current_shop) do
        Discounts::Engine.evaluate(shop: current_shop, lines:,
                                   code: checkout.discount_code,
                                   customer_key: checkout.customer_id&.to_s)
      end
      calc = Checkouts::Calculator.call(
        lines:, currency: checkout.currency, shipping_cents: shipping_cents,
        discounts: evaluation.discounts
      )
      snapshot = calc.discount_applications.map do |app|
        { "discount_id" => app.id, "title" => app.title, "class" => app.discount_class,
          "amount_cents" => app.amount_cents, "allocations" => app.line_allocations }
      end
      ActsAsTenant.with_tenant(current_shop) do
        checkout.update!(
          shipping_address: checkout.shipping_address.merge(address).merge("country_code" => country),
          shipping_lines: shipping_lines, shipping_cents: shipping_cents,
          subtotal_cents: calc.subtotal_cents, tax_cents: calc.tax_total_cents,
          discount_cents: calc.discount_total_cents + calc.shipping_discount_cents,
          discount_applications_snapshot: snapshot,
          total_cents: calc.total_cents, presentment_total_cents: calc.total_cents
        )
      end
    end

    # 折扣重算（步 9b；delivery 重算之外的第二個呼叫點——同一條鏈）。
    # @return [String, nil] code 錯誤文案（統一句）；nil＝成功
    def refresh_discounts!(checkout)
      lines = checkout.line_items_snapshot.map { |l|
        { key: l["key"], quantity: l["quantity"], unit_price_cents: l["unit_price_cents"],
          variant_id: l["variant_id"] }
      }
      evaluation = ActsAsTenant.with_tenant(current_shop) do
        Discounts::Engine.evaluate(shop: current_shop, lines:,
                                   code: checkout.discount_code,
                                   customer_key: checkout.customer_id&.to_s)
      end
      return evaluation.code_error if evaluation.code_error

      calc = Checkouts::Calculator.call(
        lines:, currency: checkout.currency, shipping_cents: checkout.shipping_cents,
        discounts: evaluation.discounts
      )
      snapshot = calc.discount_applications.map do |app|
        { "discount_id" => app.id, "title" => app.title, "class" => app.discount_class,
          "amount_cents" => app.amount_cents, "allocations" => app.line_allocations }
      end
      ActsAsTenant.with_tenant(current_shop) do
        checkout.update!(
          discount_cents: calc.discount_total_cents + calc.shipping_discount_cents,
          discount_applications_snapshot: snapshot,
          subtotal_cents: calc.subtotal_cents,
          total_cents: calc.total_cents, presentment_total_cents: calc.total_cents
        )
      end
      nil
    end

    def render_page(checkout, error: nil, status: :ok)
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render html: page_html(checkout.reload, error:).html_safe, layout: false, status:
    end

    # 非主題化結帳頁（85 §6；G6-4 起 1:1 對位 87 號實測骨架：header 髮絲線＋
    # 手機 accordion 摘要＋雙欄殼〔≥1006 分欄、左白右 #f5f5f5〕＋單表單主流程＋
    # 側欄摘要）。文案＝英文字面對齊（2026-08-31 使用者裁定，登記 worklog）。
    # 金額字串＝Money::Display 同一 cents 來源（鐵律 7）。
    def page_html(checkout, error: nil)
      shop_name = ERB::Util.html_escape(current_shop.name)
      <<~HTML
        <!doctype html><html lang="en"><head><title>Checkout - #{shop_name}</title>
        #{checkout_head}</head>
        <body class="ck">
        <header class="ck-header"><div class="ck-hgrid"><div class="ck-hcell">
        <a class="ck-brand" href="/">#{shop_name}</a>
        <h1 class="ck-sr">#{shop_name} Checkout</h1>
        </div></div></header>
        <details class="ck-acc" data-summary-accordion>
        <summary><span class="ck-acc-label">Order summary #{chevron_svg}</span>
        <span class="ck-acc-total">#{money_str(checkout.total_cents, checkout.currency)}</span></summary>
        <div class="ck-acc-panel">#{summary_html(checkout)}</div>
        </details>
        <div class="ck-shell">
        <main class="ck-col-main"><div class="ck-colin ck-colin-main">
        #{error ? "<p class=\"ck-banner\" data-delivery-error>#{ERB::Util.html_escape(error)}</p>" : ''}
        <form method="post" action="/checkouts/#{checkout.token}/submit" data-ck-form>
        #{contact_html(checkout)}
        #{delivery_form_html(checkout)}
        #{shipping_method_html(checkout)}
        #{payment_html(checkout)}
        #{billing_html(checkout)}
        #{pay_button_html(checkout)}
        </form>
        <footer class="ck-footer">#{footer_links_html}</footer>
        </div></main>
        <div class="ck-col-aside"><div class="ck-colin ck-colin-aside">
        <aside class="ck-aside"><h2 class="ck-sr">Order summary</h2>#{summary_html(checkout)}</aside>
        </div></div>
        </div>
        #{autosave_js}
        </body></html>
      HTML
    end

    # 結帳線三頁共用 head（viewport＋noindex＋tokens/checkout 樣式——propshaft digest 路徑）。
    def checkout_head
      <<~HTML
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex">
        #{view_context.stylesheet_link_tag("tokens", "stylesheets/checkout")}
      HTML
    end

    # 付款段（87 §1/§4 實測形）：h2＋「All transactions are secure and encrypted.」
    # 副標＋方法盒（選中列藍環＋#f5f6ff、選中方法下掛面板：psp＝redirect 句、
    # manual＝additional_details）；單一方法無可見 radio（87 實測——僅一組時本尊
    # 不出 radio，值以 hidden input 傳遞）；零方法＝無法接受付款。
    # F4.2 三層交集不變：PSP 選項＝enabled ∩ available ∩ 平台已實作（hide 非 disable）。
    def payment_html(checkout)
      methods = manual_methods
      psp_options = psp_payment_options
      if methods.empty? && psp_options.empty?
        return "<section class=\"ck-sec\" data-payment><h2 class=\"ck-h2\">Payment</h2>" \
               "<p class=\"ck-sub\" data-payment-unavailable>This store can't accept payments right now.</p></section>"
      end

      chosen_id = checkout.payment_method_snapshot["id"]
      total_options = methods.size + psp_options.size
      first_value = psp_options.first&.first || methods.first&.id
      rows = psp_options.map do |value, label|
        selected = chosen_id ? chosen_id == value : value == first_value
        panel = selected ?
                  "<div class=\"ck-opt-panel\" data-psp-redirect>You'll be redirected to " \
                  "#{ERB::Util.html_escape(label)} to complete your purchase.</div>" : ""
        payment_option_row(value:, label:, selected:, radio: total_options > 1, panel:,
                           extra_attr: " data-psp-method")
      end.join
      rows += methods.map do |m|
        selected = chosen_id ? chosen_id == m.id : (psp_options.empty? && m == methods.first)
        panel = selected && m.additional_details.present? ?
                  "<div class=\"ck-opt-panel\" data-payment-details>#{ERB::Util.html_escape(m.additional_details)}</div>" : ""
        payment_option_row(value: m.id, label: m.name, selected:, radio: total_options > 1, panel:)
      end.join
      <<~HTML
        <section class="ck-sec" data-payment><h2 class="ck-h2">Payment</h2>
        <p class="ck-sub">All transactions are secure and encrypted.</p>
        #{total_options == 1 ? "<input type=\"hidden\" name=\"payment_method_id\" value=\"#{first_value}\">" : ''}
        <div class="ck-optbox" data-payment-methods>#{rows}</div>
        </section>
      HTML
    end

    # 方法盒單列（87 §4：列 h50 pad14；選中＝.is-sel 藍環＋淺藍底；品牌 icon
    # 資產待品牌包＝V-87-4，本輪純文字）。radio=false（單一方法）時不出圈。
    def payment_option_row(value:, label:, selected:, radio:, panel:, extra_attr: "")
      input = radio ?
                "<input class=\"ck-radio\" type=\"radio\" name=\"payment_method_id\" " \
                "value=\"#{value}\"#{' checked' if selected} data-ck-refresh>" : ""
      "<div class=\"ck-opt#{' is-sel' if selected}\"#{extra_attr}>" \
        "<label class=\"ck-opt-row\">#{input}<span class=\"ck-opt-name\">" \
        "#{ERB::Util.html_escape(label)}</span></label>#{panel}</div>"
    end

    # 帳單段（87 §1/§4）：h3 16/600＋兩列組；different ⇒ 展開帳單地址表單
    # （灰面板；欄位組同 Delivery，落 billing_address json）。
    # 零付款方式 ⇒ 整段不渲染（沒有可付的東西就沒有帳單地址可談——與 pay 鈕同 gate）。
    def billing_html(checkout)
      return "" if manual_methods.empty? && psp_payment_options.empty?

      billing = checkout.billing_address
      mode = billing["mode"] || "same_as_shipping"
      different = mode == "different"
      form = different ? "<div class=\"ck-opt-panel ck-billing-form\">#{address_fields_html(billing, prefix: 'billing_')}</div>" : ""
      <<~HTML
        <section class="ck-sec" data-billing-address><h3 class="ck-h3">Billing address</h3>
        <div class="ck-optbox">
        <div class="ck-opt#{different ? '' : ' is-sel'}"><label class="ck-opt-row">
        <input class="ck-radio" type="radio" name="billing_mode" value="same_as_shipping"#{different ? '' : ' checked'} data-ck-refresh>
        <span class="ck-opt-name">Same as shipping address</span></label></div>
        <div class="ck-opt#{different ? ' is-sel' : ''}"><label class="ck-opt-row">
        <input class="ck-radio" type="radio" name="billing_mode" value="different"#{different ? ' checked' : ''} data-ck-refresh>
        <span class="ck-opt-name">Use a different billing address</span></label>#{form}</div>
        </div></section>
      HTML
    end

    # 主提交鈕（87 §4：全寬 h50 藍 #005bd1 r12）。psp＝Pay now／manual＝Complete order
    # （本尊字面：直連付「Pay now」、線下方式「Complete order」）；零方法不出鈕。
    # 落庫與前進都在 /submit——missing 檢查移到 server（V-87-2：本尊行內錯誤態未測）。
    def pay_button_html(checkout)
      return "" if manual_methods.empty? && psp_payment_options.empty?

      chosen = checkout.payment_method_snapshot
      kind = chosen["kind"] || (psp_payment_options.any? ? "psp" : "manual")
      text = kind == "psp" ? "Pay now" : "Complete order"
      "<h2 class=\"ck-sr\">Finalize order</h2>" \
        "<button type=\"submit\" class=\"ck-paybtn\" data-complete-order>#{text}</button>"
    end

    def manual_methods
      @manual_methods ||= ActsAsTenant.with_tenant(current_shop) do
        ShopPaymentMethod.where(shop_id: current_shop.id).active.ordered.to_a
      end
    end

    # PSP 可下單選項（G6-1c）：[["psp:airwallex:alipayhk", "AlipayHK"], …]。
    # 三層交集（F4.2）：商家白名單 enabled ∩ 帳號能力 available ∩ 平台已實作
    # checkout_supported_methods；provider 未啟用（status != active）⇒ 空集合。
    # 🔴 G6-3 步 2 起 status 欄是唯一啟用真相（activate 的前置已驗過憑證指紋）。
    def psp_payment_options
      @psp_payment_options ||= begin
        row = configured_provider("airwallex")
        if row.nil?
          []
        else
          supported = supported_psp_codes
          labels = ShopPaymentProvider.method_dictionary("airwallex").to_h { |m| [ m[:code].to_s, m[:label].to_s ] }
          (row.enabled_methods & row.available_methods & supported).filter_map do |code|
            label = labels[code]
            label && [ "psp:airwallex:#{code}", label ]
          end
        end
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
      # G6-3（步 2）：activation 狀態機取代「有指紋即啟用」——status 是唯一啟用
      # 真相（指紋只證明憑證存在；activate mutation 的前置已驗過指紋）。
      # ⚠️ 遷移相容：既有已設憑證的店在 activate 補跑前 status 仍 inactive ⇒
      # 部署後需一次性把「有指紋的列」翻 active（deploy 後生產腳本，worklog 記）。
      row && row.status == "active" ? row : nil
    end

    # psp:<provider>:<code> → 快照（server 重驗三層交集；殘留 radio 不得落庫）。
    def psp_method_snapshot(raw_id)
      _, provider, code = raw_id.split(":", 3)
      option = psp_payment_options.find { |value, _| value == "psp:#{provider}:#{code}" }
      return nil if option.nil?

      { "id" => option.first, "kind" => "psp", "provider" => provider,
        "method_type" => code, "name" => option.last }
    end

    # SDK 環境值（取證 2026-08-31：quickstart 逐字 env: 'demo'；bundle enum 同時認
    # demo/sandbox——文檔三源矛盾以 quickstart＋bundle 實物為準，登記於 limits 註）。
    def sdk_env(provider_row)
      key = provider_row.environment == "production" ? :sdk_env_production : :sdk_env_sandbox
      Limits.fetch(:psp_integration, :airwallex, key)
    end

    def sdk_cdn_url
      Limits.fetch(:psp_integration, :airwallex, :sdk_cdn_url)
    end

    # 卡片付款頁（G6-1d；官方 guest-user-checkout quickstart 逐字形：
    # init → createElement('card', {intent_id, client_secret, currency}) →
    # mount('card') → card.confirm({intent_id, client_secret})）。
    # 🔴 confirm resolve 後**不信客戶端結果**：導向 /pay/status?html=1，由 server
    # 權威重取 intent → Finalize（與 QR／webhook 同終點）。
    def card_pay_page_html(checkout, intent, provider_row)
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      config = JSON.generate(
        env: sdk_env(provider_row), intent_id: intent.fetch("id"),
        client_secret: intent.fetch("client_secret"), currency: checkout.currency,
        status_html_url: "/checkouts/#{checkout.token}/pay/status?html=1"
      )
      <<~HTML
        <!DOCTYPE html><html lang="zh-Hant"><head>
        <title>信用卡付款</title>#{checkout_head}
        <script src="#{sdk_cdn_url}"></script></head><body class="ck">
        <header class="ck-header"><a class="ck-brand" href="/">#{ERB::Util.html_escape(current_shop.name)}</a></header>
        <main data-psp-card class="ck-card">
        <h1>信用卡付款</h1>
        <p>應付金額：#{checkout.currency} #{total}</p>
        <div id="card" data-card-mount></div>
        <div id="awx-auth"></div>
        <button type="button" data-card-pay class="ck-pay-btn">確認付款</button>
        <p data-pay-state></p>
        <p><a href="/checkouts/#{checkout.token}">返回結帳頁</a></p>
        <script type="application/json" data-awx-config>#{config}</script>
        <script>
        (async function () {
          var cfg = JSON.parse(document.querySelector("[data-awx-config]").textContent);
          var state = document.querySelector("[data-pay-state]");
          var btn = document.querySelector("[data-card-pay]");
          try {
            await window.AirwallexComponentsSDK.init({ env: cfg.env, enabledElements: ["payments"] });
            var card = await window.AirwallexComponentsSDK.createElement("card", {
              intent_id: cfg.intent_id, client_secret: cfg.client_secret, currency: cfg.currency,
              authFormContainer: "awx-auth"
            });
            card.mount("card");
          } catch (e) {
            state.textContent = "付款元件載入失敗，請重新整理或換一種付款方式。";
            btn.disabled = true;
            return;
          }
          btn.addEventListener("click", function () {
            btn.disabled = true;
            state.textContent = "處理中…";
            card.confirm({ intent_id: cfg.intent_id, client_secret: cfg.client_secret })
              .then(function () { window.location = cfg.status_html_url; })
              .catch(function (err) {
                state.textContent = (err && err.message) ? err.message : "付款未完成，請確認卡片資訊後重試。";
                btn.disabled = false;
              });
          });
        })();
        </script>
        </main></body></html>
      HTML
    end

    # 錢包付款頁（Apple Pay／Google Pay；SDK 參考頁：amount{currency, value:number}＋
    # countryCode 必填；成功/失敗走 on('success')/on('error') 事件）。
    # ⚠️ 端到端驗證留 sandbox（Apple Pay 另需網域註冊——well-known 檔已隨本包上線）。
    def wallet_pay_page_html(checkout, intent, provider_row, snapshot)
      element = snapshot["method_type"] == "applepay" ? "applePayButton" : "googlePayButton"
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      amount_literal = Money::Storage.from_cents(checkout.total_cents, checkout.currency)
                                     .to_psp_amount(psp: :airwallex).number
                                     .then { |n| n.frac.zero? ? n.to_i.to_s : n.to_s("F") }
      country = checkout.shipping_address["country_code"].presence || "HK"
      config = JSON.generate(
        env: sdk_env(provider_row), element:, intent_id: intent.fetch("id"),
        client_secret: intent.fetch("client_secret"), currency: checkout.currency,
        country_code: country,
        status_html_url: "/checkouts/#{checkout.token}/pay/status?html=1"
      ).sub(/\}\z/, %(,"amount_value":#{amount_literal}\}))
      <<~HTML
        <!DOCTYPE html><html lang="zh-Hant"><head>
        <title>以 #{ERB::Util.html_escape(snapshot["name"].to_s)} 付款</title>#{checkout_head}
        <script src="#{sdk_cdn_url}"></script></head><body class="ck">
        <header class="ck-header"><a class="ck-brand" href="/">#{ERB::Util.html_escape(current_shop.name)}</a></header>
        <main data-psp-wallet class="ck-card">
        <h1>以 #{ERB::Util.html_escape(snapshot["name"].to_s)} 付款</h1>
        <p>應付金額：#{checkout.currency} #{total}</p>
        <div id="wallet" data-wallet-mount></div>
        <p data-pay-state></p>
        <p><a href="/checkouts/#{checkout.token}">返回結帳頁</a></p>
        <script type="application/json" data-awx-config>#{config}</script>
        <script>
        (async function () {
          var cfg = JSON.parse(document.querySelector("[data-awx-config]").textContent);
          var state = document.querySelector("[data-pay-state]");
          try {
            await window.AirwallexComponentsSDK.init({ env: cfg.env, enabledElements: ["payments"] });
            var el = await window.AirwallexComponentsSDK.createElement(cfg.element, {
              intent_id: cfg.intent_id, client_secret: cfg.client_secret,
              amount: { currency: cfg.currency, value: cfg.amount_value },
              countryCode: cfg.country_code, autoCapture: true
            });
            el.mount("wallet");
            el.on("success", function () { window.location = cfg.status_html_url; });
            el.on("error", function (e) {
              var err = e && e.detail && e.detail.error;
              state.textContent = (err && err.message) ? err.message : "付款未完成，請重試或換一種付款方式。";
            });
          } catch (e) {
            state.textContent = "此裝置或瀏覽器不支援這種付款方式，請換一種付款方式。";
          }
        })();
        </script>
        </main></body></html>
      HTML
    end

    # QR 付款頁（G6-1c）：伺服端 rqrcode 出 SVG；輪詢 GET /pay/status（🔴 GET 不吃
    # storefront-cart/ip 的 POST throttle——輪詢 3 秒一發、QR 十分鐘）。
    # 🔴 本頁 inline <script> 是 storefront 第一個第一方 JS（先例登記於 worklog）。
    def qr_page_html(checkout, method_name, qrcode)
      svg = RQRCode::QRCode.new(qrcode).as_svg(module_size: 5, viewbox: true)
      poll_ms = Limits.fetch(:psp_integration, :airwallex, :status_poll_interval_seconds) * 1000
      total = Money::Display.call(Money::Storage.from_cents(checkout.total_cents, checkout.currency))
      <<~HTML
        <!DOCTYPE html><html lang="zh-Hant"><head>
        <title>以 #{ERB::Util.html_escape(method_name)} 付款</title>#{checkout_head}</head><body class="ck">
        <header class="ck-header"><a class="ck-brand" href="/">#{ERB::Util.html_escape(current_shop.name)}</a></header>
        <main data-psp-qr class="ck-card">
        <h1>以 #{ERB::Util.html_escape(method_name)} 付款</h1>
        <p>應付金額：#{checkout.currency} #{total}</p>
        <div data-qrcode>#{svg}</div>
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

    # 側欄摘要（87 §4 側欄量測；手機 accordion 面板共用同一份）。
    # 幣別符號＝display 層字典（鐵律 10：符號歸 locale——markets 幣別包接手前的
    # 店幣最小集）；code 只在 Total 前綴出現（實測「HKD $188.00」形）。
    def summary_html(checkout)
      items = checkout.line_items_snapshot.map do |line|
        amount = money_str(line["unit_price_cents"] * line["quantity"], checkout.currency)
        thumb = line["image_url"].present? ?
                  "<img src=\"#{ERB::Util.html_escape(line['image_url'])}\" alt=\"\" loading=\"lazy\">" : ""
        variant = line["variant_title"].present? && line["variant_title"] != "Default Title" ?
                    "<span class=\"ck-line-variant\">#{ERB::Util.html_escape(line['variant_title'])}</span>" : ""
        <<~ROW
          <div class="ck-line">
          <div class="ck-thumb">#{thumb}<span class="ck-qty" aria-label="Quantity">#{line['quantity']}</span></div>
          <div class="ck-line-title">#{ERB::Util.html_escape(line['title'])}#{variant}</div>
          <div class="ck-line-price">#{amount}</div>
          </div>
        ROW
      end.join
      shipping_value =
        if checkout.shipping_address["country_code"].blank? || checkout.shipping_lines.blank?
          "<span class=\"ck-cost-muted\" data-checkout-shipping>Enter shipping address</span>"
        else
          "<span data-checkout-shipping>#{money_str(checkout.shipping_cents, checkout.currency)}</span>"
        end
      <<~HTML
        <section class="ck-cart" aria-label="Shopping cart"><h3 class="ck-sr">Shopping cart</h3>#{items}</section>
        <section class="ck-costs" aria-label="Cost summary"><h3 class="ck-sr">Cost summary</h3>
        <form class="ck-discount-form" method="post" action="/checkouts/#{checkout.token}/discount">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
        <input class="ck-input ck-discount-input" type="text" name="code" placeholder="Discount code"
               value="#{ERB::Util.html_escape(checkout.discount_code.to_s)}" aria-label="Discount code">
        <button class="ck-btn-secondary" type="submit">Apply</button>
        </form>
        <div class="ck-cost-row"><span>Subtotal</span><span>#{money_str(checkout.subtotal_cents, checkout.currency)}</span></div>
        #{if checkout.discount_cents.positive?
            label = checkout.discount_code.present? ? "Discount (#{ERB::Util.html_escape(checkout.discount_code)})" : "Discount"
            "<div class=\"ck-cost-row\"><span>#{label}</span><span>−#{money_str(checkout.discount_cents, checkout.currency)}</span></div>"
          end}
        <div class="ck-cost-row"><span>Shipping</span>#{shipping_value}</div>
        <div class="ck-total-row"><span class="ck-total-label">Total</span>
        <span class="ck-total-val" data-checkout-total><span class="ck-total-ccy">#{checkout.currency}</span> #{money_str(checkout.total_cents, checkout.currency)}</span></div>
        </section>
      HTML
    end

    # 幣別符號最小集（display 層；符號未收錄回落「CODE 」前綴——鐵律 10 的
    # locale 全表隨 markets 幣別包）。
    CURRENCY_SYMBOLS = {
      "HKD" => "$", "USD" => "$", "AUD" => "$", "CAD" => "$", "SGD" => "$", "TWD" => "$",
      "EUR" => "€", "GBP" => "£", "JPY" => "¥", "CNY" => "¥", "KRW" => "₩"
    }.freeze

    def money_str(cents, currency)
      "#{CURRENCY_SYMBOLS.fetch(currency) { "#{currency} " }}" \
        "#{Money::Display.call(Money::Storage.from_cents(cents, currency))}"
    end

    # US 州值域（87 §3 實測 63 項：空白占位＋62 值；value=二碼、text=全名）。
    US_ZONES = [
      %w[AL Alabama], %w[AK Alaska], [ "AS", "American Samoa" ], %w[AZ Arizona],
      %w[AR Arkansas], %w[CA California], %w[CO Colorado], %w[CT Connecticut],
      %w[DE Delaware], %w[FM Micronesia], %w[FL Florida], %w[GA Georgia], %w[GU Guam],
      %w[HI Hawaii], %w[ID Idaho], %w[IL Illinois], %w[IN Indiana], %w[IA Iowa],
      %w[KS Kansas], %w[KY Kentucky], %w[LA Louisiana], %w[ME Maine],
      [ "MH", "Marshall Islands" ], %w[MD Maryland], %w[MA Massachusetts], %w[MI Michigan],
      %w[MN Minnesota], %w[MS Mississippi], %w[MO Missouri], %w[MT Montana],
      %w[NE Nebraska], %w[NV Nevada], [ "NH", "New Hampshire" ], [ "NJ", "New Jersey" ],
      [ "NM", "New Mexico" ], [ "NY", "New York" ], [ "NC", "North Carolina" ],
      [ "ND", "North Dakota" ], [ "MP", "Northern Mariana Islands" ], %w[OH Ohio],
      %w[OK Oklahoma], %w[OR Oregon], %w[PW Palau], %w[PA Pennsylvania],
      [ "PR", "Puerto Rico" ], [ "RI", "Rhode Island" ], [ "SC", "South Carolina" ],
      [ "SD", "South Dakota" ], %w[TN Tennessee], %w[TX Texas], %w[UT Utah],
      %w[VT Vermont], %w[VA Virginia], %w[WA Washington], [ "DC", "Washington DC" ],
      [ "WV", "West Virginia" ], %w[WI Wisconsin], %w[WY Wyoming],
      [ "VI", "U.S. Virgin Islands" ], [ "AA", "Armed Forces Americas" ],
      [ "AE", "Armed Forces Europe" ], [ "AP", "Armed Forces Pacific" ]
    ].freeze

    # 浮動 label 文字欄（87 §4：空值＝placeholder 形、填值＝12px 浮標；CSS 靠
    # :placeholder-shown 切換——placeholder 恆設 label 字面）。
    def text_field_html(name:, label:, value:, type: "text", autocomplete: nil, required: false, icon: nil)
      esc_label = ERB::Util.html_escape(label)
      "<div class=\"ck-field\">" \
        "<input class=\"ck-input\" type=\"#{type}\" name=\"#{name}\" value=\"#{ERB::Util.html_escape(value.to_s)}\"" \
        " placeholder=\"#{esc_label}\" aria-label=\"#{esc_label}\"" \
        "#{autocomplete ? " autocomplete=\"#{autocomplete}\"" : ''}#{' required' if required}>" \
        "<span class=\"ck-flabel\" aria-hidden=\"true\">#{esc_label}</span>#{icon}</div>"
    end

    def country_select_html(selected, prefix: "")
      options = sellable_countries.map do |code|
        label = ERB::Util.html_escape(Checkouts::CountryNames.label(code))
        %(<option value="#{code}"#{' selected' if code == selected}>#{label}</option>)
      end.join
      "<div class=\"ck-field ck-field--select\">" \
        "<select class=\"ck-select\" name=\"#{prefix.empty? ? 'country_code' : "#{prefix}country_code"}\"" \
        " autocomplete=\"country\" required data-ck-refresh>#{options}</select>" \
        "<span class=\"ck-flabel is-float\" aria-hidden=\"true\">Country/Region</span>#{chevron_svg}</div>"
    end

    def zone_select_html(selected, prefix: "")
      options = [ %(<option value="">&nbsp;</option>) ] + US_ZONES.map do |code, label|
        %(<option value="#{code}"#{' selected' if code == selected}>#{label}</option>)
      end
      "<div class=\"ck-field ck-field--select\">" \
        "<select class=\"ck-select\" name=\"#{prefix}zone\" autocomplete=\"address-level1\" required>#{options.join}</select>" \
        "<span class=\"ck-flabel is-float\" aria-hidden=\"true\">State</span>#{chevron_svg}</div>"
    end

    # 行內 svg 三枚（自繪；87 §4 的 ? 18×18／放大鏡／chevron 10×10 對位）。
    def info_icon_svg(label)
      "<button type=\"button\" class=\"ck-info\" aria-label=\"#{ERB::Util.html_escape(label)}\">" \
        "<svg viewBox=\"0 0 18 18\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\">" \
        "<circle cx=\"9\" cy=\"9\" r=\"7.5\" stroke-width=\"1.2\"/>" \
        "<path d=\"M7.2 6.8a1.8 1.8 0 1 1 2.7 1.6c-.6.4-.9.7-.9 1.4v.4\" stroke-width=\"1.2\" stroke-linecap=\"round\"/>" \
        "<circle cx=\"9\" cy=\"12.8\" r=\".9\" fill=\"currentColor\" stroke=\"none\"/></svg></button>"
    end

    def search_icon_svg
      "<span class=\"ck-info\" aria-hidden=\"true\">" \
        "<svg viewBox=\"0 0 18 18\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\">" \
        "<circle cx=\"8\" cy=\"8\" r=\"5.5\" stroke-width=\"1.4\"/>" \
        "<path d=\"M12.2 12.2 16 16\" stroke-width=\"1.4\" stroke-linecap=\"round\"/></svg></span>"
    end

    def chevron_svg
      "<svg class=\"ck-chevron\" viewBox=\"0 0 10 10\" width=\"10\" height=\"10\" fill=\"none\" " \
        "stroke=\"currentColor\" aria-hidden=\"true\"><path d=\"M1.5 3.5 5 7l3.5-3.5\" " \
        "stroke-width=\"1.4\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"
    end

    def footer_links_html
      page = ActsAsTenant.with_tenant(current_shop) do
        defined?(Page) ? Page.find_by(shop_id: current_shop.id, handle: "privacy-policy") : nil
      end
      page ? "<a class=\"ck-link\" href=\"/pages/privacy-policy\">Privacy policy</a>" : ""
    end

    # 欄位變更自動儲存（87 §7 對位：本尊欄位變更即協商；我方＝select/radio 變更
    # 就以 refresh=1 送同一個表單重渲染。文字欄不自動送——整頁 POST 會打斷輸入）。
    def autosave_js
      <<~HTML
        <script>
        (function () {
          var form = document.querySelector("[data-ck-form]");
          if (!form) return;
          form.addEventListener("change", function (e) {
            if (!e.target.matches("[data-ck-refresh]")) return;
            var flag = document.createElement("input");
            flag.type = "hidden"; flag.name = "refresh"; flag.value = "1";
            form.appendChild(flag);
            form.submit();
          });
        })();
        </script>
      HTML
    end

    # /submit 的落庫三兄弟。
    def persist_contact!(checkout)
      updates = {}
      updates[:email] = params[:email].to_s.strip.presence if params.key?(:email)
      updates[:buyer_accepts_marketing] = params[:buyer_accepts_marketing].present? if params.key?(:email)
      return if updates.empty?

      ActsAsTenant.with_tenant(current_shop) { checkout.update!(**updates) }
    end

    ADDRESS_KEYS = %w[first_name last_name address1 address2 city zone postal_code phone].freeze

    def address_params(prefix = "")
      ADDRESS_KEYS.index_with { |k| params["#{prefix}#{k}"].to_s.strip }
                  .select { |k, _| params.key?("#{prefix}#{k}") }
    end

    def persist_billing!(checkout)
      mode = params[:billing_mode].to_s
      return unless %w[same_as_shipping different].include?(mode)

      merged = checkout.billing_address.merge("mode" => mode)
      if mode == "different"
        merged = merged.merge(address_params("billing_"))
        country = params[:billing_country_code].to_s.upcase
        merged = merged.merge("country_code" => country) if country.present?
      end
      ActsAsTenant.with_tenant(current_shop) { checkout.update!(billing_address: merged) }
    end

    # 前進閘（87 §3 required 欄；V-87-2：本尊行內錯誤態未測 ⇒ 本輪 banner 形）。
    def missing_required_fields(checkout)
      addr = checkout.shipping_address
      requires_shipping = checkout.line_items_snapshot.any? { |l| l.fetch("requires_shipping", true) }
      missing = []
      missing << "Email" if checkout.email.blank?
      if requires_shipping
        missing << "Country/Region" if addr["country_code"].blank?
        missing << "First name" if addr["first_name"].blank?
        missing << "Last name" if addr["last_name"].blank?
        missing << "Address" if addr["address1"].blank?
        missing << "City" if addr["city"].blank?
        if addr["country_code"].to_s.upcase == "US"
          missing << "State" if addr["zone"].blank?
          missing << "ZIP code" if addr["postal_code"].blank?
        end
        missing << "Shipping method" if checkout.shipping_lines.blank?
      end
      missing << "Payment" if checkout.payment_method_snapshot["method_type"].blank?
      missing
    end

    # Contact 段（87 §1）：h2＋右側 Sign in 同列、email 浮標欄（? icon）、行銷勾選。
    # ⚠ Sign in 連結對位視覺；買家帳戶線未建（點擊 404）——登記 worklog Pending。
    def contact_html(checkout)
      <<~HTML
        <section class="ck-sec" data-contact>
        <div class="ck-h2row"><h2 class="ck-h2">Contact</h2><a class="ck-link" href="/account/login">Sign in</a></div>
        #{text_field_html(name: 'email', label: 'Email', value: checkout.email, type: 'email',
                          autocomplete: 'shipping email', required: true, icon: info_icon_svg('More information about how your contact info is used'))}
        <label class="ck-check"><input class="ck-checkbox" type="checkbox" name="buyer_accepts_marketing" value="1"#{' checked' if checkout.buyer_accepts_marketing}>
        <span>Email me with news and offers</span></label>
        </section>
      HTML
    end

    # Delivery 段（87 §1/§3）：國家 select（值域＝sellable_countries、顯示名＝
    # CountryNames）＋地址全欄位（US 格式有實測：State+ZIP；其他國家 V-87-1，
    # 回落 City+Postal code 通用形）。
    def delivery_form_html(checkout)
      addr = checkout.shipping_address
      <<~HTML
        <section class="ck-sec" data-delivery><h2 class="ck-h2">Delivery</h2>
        <div class="ck-fields">
        #{country_select_html(addr['country_code'])}
        #{address_fields_html(addr)}
        </div>
        <label class="ck-check"><input class="ck-checkbox" type="checkbox" name="save_shipping_information" value="1">
        <span>Save this information for next time</span></label>
        <noscript><button type="submit" name="refresh" value="1" class="ck-refreshbtn">Update</button></noscript>
        </section>
      HTML
    end

    # 地址欄位組（Delivery 與 Billing different 共用；prefix 區分參數命名空間）。
    def address_fields_html(addr, prefix: "")
      zone_row =
        if addr["country_code"].to_s.upcase == "US"
          "<div class=\"ck-row3\">" \
            "#{text_field_html(name: "#{prefix}city", label: 'City', value: addr['city'], autocomplete: 'address-level2', required: true)}" \
            "#{zone_select_html(addr['zone'], prefix:)}" \
            "#{text_field_html(name: "#{prefix}postal_code", label: 'ZIP code', value: addr['postal_code'], autocomplete: 'postal-code', required: true)}</div>"
        else
          "<div class=\"ck-row2\">" \
            "#{text_field_html(name: "#{prefix}city", label: 'City', value: addr['city'], autocomplete: 'address-level2', required: true)}" \
            "#{text_field_html(name: "#{prefix}postal_code", label: 'Postal code', value: addr['postal_code'], autocomplete: 'postal-code')}</div>"
        end
      country = prefix.empty? ? "" : country_select_html(addr["country_code"], prefix:)
      <<~HTML
        #{country}
        <div class="ck-row2">
        #{text_field_html(name: "#{prefix}first_name", label: 'First name', value: addr['first_name'], autocomplete: 'given-name', required: true)}
        #{text_field_html(name: "#{prefix}last_name", label: 'Last name', value: addr['last_name'], autocomplete: 'family-name', required: true)}
        </div>
        #{text_field_html(name: "#{prefix}address1", label: 'Address', value: addr['address1'], autocomplete: 'address-line1', required: true, icon: search_icon_svg)}
        #{text_field_html(name: "#{prefix}address2", label: 'Apartment, suite, etc. (optional)', value: addr['address2'], autocomplete: 'address-line2')}
        #{zone_row}
        #{text_field_html(name: "#{prefix}phone", label: 'Phone (optional)', value: addr['phone'], type: 'tel', autocomplete: 'tel-national', icon: info_icon_svg('More information about Phone'))}
      HTML
    end

    # Shipping method 段（87 §1/§4）：未選國＝灰盒占位（實測字面）；已選國＝
    # 選項盒（選中列藍環；價格靠右；split 分組）。radio 值仍＝"name|price"（F3-3）。
    def shipping_method_html(checkout)
      country = checkout.shipping_address["country_code"]
      body =
        if country.blank?
          "<div class=\"ck-placeholder\" data-shipping-hint>" \
            "Enter your shipping address to view available shipping methods.</div>"
        else
          result = resolve_rates(checkout, country)
          rates_box_html(checkout, result)
        end
      return "" if body.empty?

      "<section class=\"ck-sec\" data-shipping-method><h2 class=\"ck-h2\">Shipping method</h2>#{body}</section>"
    end

    def rates_box_html(checkout, result)
      unless result.ok?
        return "<div class=\"ck-placeholder\" data-shipping-unavailable>" \
               "Some items can't be shipped to this region.</div>"
      end
      return "" if result.shipments.empty? # 全數位商品：本尊無 Shipping method 區（85 §5.1）

      chosen = checkout.shipping_lines.to_h { |l| [ l["shipment_index"], l["name"] ] }
      if split?(result)
        note = "<p class=\"ck-sub\" data-split-note>Your order ships in #{result.shipments.size} " \
               "packages. Choose a shipping method for each.</p>"
        note + result.shipments.each_with_index.map do |shipment, index|
          rows = shipment.options.map do |option|
            rate_row(name: "selections[#{index}]", option:, checkout:,
                     checked: chosen[index] ? chosen[index] == option.name : option == shipment.options.first)
          end.join
          "<div class=\"ck-optbox\" data-shipment=\"#{index}\"><div class=\"ck-opt-grouphead\">" \
            "Package #{index + 1} (#{shipment.line_keys.size} items)</div>#{rows}</div>"
        end.join
      else
        rows = result.merged_options.map do |option|
          rate_row(name: "option", option:, checkout:,
                   checked: chosen[0] ? chosen[0] == option.name : option == result.merged_options.first)
        end.join
        "<div class=\"ck-optbox\" data-shipping-options>#{rows}</div>"
      end
    end

    # 運送選項單列：radio＋名稱（＋transit 小字）左、價格右（Free＝免運對位字面）。
    def rate_row(name:, option:, checkout:, checked:)
      price = option.price_cents.zero? ? "Free" : money_str(option.price_cents, checkout.currency)
      value = ERB::Util.html_escape("#{option.name}|#{option.price_cents}")
      transit = transit_label(option)
      sub = transit.empty? ? "" : "<span class=\"ck-opt-sub\">#{transit}</span>"
      "<div class=\"ck-opt#{' is-sel' if checked}\"><label class=\"ck-opt-row\">" \
        "<input class=\"ck-radio\" type=\"radio\" name=\"#{name}\" value=\"#{value}\"#{' checked' if checked} data-ck-refresh>" \
        "<span class=\"ck-opt-name\">#{ERB::Util.html_escape(option.name)}#{sub}</span>" \
        "<span class=\"ck-opt-price\">#{price}</span></label></div>"
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
