# frozen_string_literal: true

module Storefront
  # 買家帳戶（G6 步 11；74 §7 新版帳號形＝passwordless OTP）。
  #
  # ①流程：GET /account/login（email 表單）→ POST /account/login（發碼——OTP 信
  #   走步 6 通知鏈）→ POST /account/verify（驗碼；未註冊 email **自動建 profile**
  #   ——74 §7「刪除後同 email 再登入自動重建」的同構）→ 簽名 host-only cookie
  #   `_cl_customer`（365 天）→ /account。
  # ②🔴 發碼回應不洩漏 email 是否存在（一律「已寄出」句——與折扣碼枚舉防護同軸）。
  # ③/account 家族＝非主題化頁（checkout 同法）：訂單史＋地址簿（唯讀 v1）。
  class AccountsController < BaseController
    include CustomerAuth
    COOKIE = CUSTOMER_COOKIE

    def login_form
      render html: login_html.html_safe, layout: false
    end

    def send_code
      email = Customer.normalize_email(params[:email])
      if email.nil?
        return render html: login_html(error: "請輸入有效的 email。").html_safe,
                      layout: false, status: :unprocessable_content
      end
      if ActsAsTenant.with_tenant(current_shop) { CustomerOtp.cooldown_active?(shop: current_shop, email:) }
        return render html: login_html(error: "驗證碼剛寄出，請稍候再試。").html_safe,
                      layout: false, status: :too_many_requests
      end

      _row, code = ActsAsTenant.with_tenant(current_shop) do
        CustomerOtp.issue!(shop: current_shop, email:)
      end
      Notifications::DeliverJob.perform_later(shop_id: current_shop.id, kind: "customer_otp",
                                              otp_email: email, otp_code: code)
      render html: verify_html(email:).html_safe, layout: false
    end

    def verify
      email = Customer.normalize_email(params[:email])
      result = ActsAsTenant.with_tenant(current_shop) do
        CustomerOtp.verify!(shop: current_shop, email:, code: params[:code])
      end
      unless result == :ok
        message = result == :too_many_attempts ? "嘗試次數過多，請重新取得驗證碼。" : "驗證碼錯誤或已過期。"
        return render html: verify_html(email:, error: message).html_safe,
                      layout: false, status: :unprocessable_content
      end

      customer = ActsAsTenant.with_tenant(current_shop) do
        Customer.find_by(shop_id: current_shop.id, email:) ||
          Customer.create!(shop_id: current_shop.id, email:, currency: current_shop.store_currency)
      end
      _session, token = ActsAsTenant.with_tenant(current_shop) do
        CustomerSession.issue!(shop: current_shop, customer:)
      end
      cookies.signed[COOKIE] = {
        value: token, httponly: true, same_site: :lax, secure: request.ssl?,
        expires: Limits.fetch(:customer, :session_days).to_i.days
      }
      redirect_to "/account"
    end

    def logout
      token = cookies.signed[COOKIE]
      if token.present?
        ActsAsTenant.with_tenant(current_shop) do
          CustomerSession.where(shop_id: current_shop.id,
                                token_digest: CustomerSession.digest(token)).delete_all
        end
      end
      cookies.delete(COOKIE)
      redirect_to "/account/login"
    end

    def show
      customer = current_customer
      return redirect_to "/account/login" if customer.nil?

      orders = ActsAsTenant.with_tenant(current_shop) do
        Order.where(shop_id: current_shop.id, customer_id: customer.id)
             .order(processed_at: :desc).limit(50).to_a
      end
      render html: account_html(customer, orders).html_safe, layout: false
    end

    def addresses
      customer = current_customer
      return redirect_to "/account/login" if customer.nil?

      rows = ActsAsTenant.with_tenant(current_shop) do
        CustomerAddress.where(shop_id: current_shop.id, customer_id: customer.id)
                       .order(default_address: :desc, id: :asc).to_a
      end
      render html: addresses_html(customer, rows).html_safe, layout: false
    end

    private

    def shell(title, body)
      shop_name = ERB::Util.html_escape(current_shop.name)
      <<~HTML
        <!doctype html><html lang="en"><head><title>#{title} - #{shop_name}</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, "Segoe UI", Roboto, "Noto Sans TC", sans-serif;
                 max-width: 560px; margin: 0 auto; padding: 24px 16px; color: #1a1a1a; }
          h1 { font-size: 22px; } .err { color: #d72c0d; }
          input { width: 100%; padding: 10px; margin: 6px 0 12px; font-size: 16px;
                  border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; }
          button { background: #1a73e8; color: #fff; border: 0; padding: 10px 22px;
                   border-radius: 6px; font-size: 14px; cursor: pointer; }
          table { width: 100%; border-collapse: collapse; font-size: 14px; }
          td, th { padding: 8px 4px; border-bottom: 1px solid #eee; text-align: left; }
          nav a { margin-right: 12px; }
        </style></head><body>
        <p><a href="/">#{shop_name}</a></p>
        #{body}
        </body></html>
      HTML
    end

    def csrf_input
      %(<input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">)
    end

    def login_html(error: nil)
      shell("Sign in", <<~BODY)
        <h1>Sign in</h1>
        <p>Enter your email and we'll send you a 6-digit code. No password needed.</p>
        #{error ? %(<p class="err">#{ERB::Util.html_escape(error)}</p>) : ""}
        <form method="post" action="/account/login">#{csrf_input}
          <label>Email<input type="email" name="email" required autofocus></label>
          <button type="submit">Continue</button>
        </form>
      BODY
    end

    def verify_html(email:, error: nil)
      shell("Enter code", <<~BODY)
        <h1>Enter code</h1>
        <p>We sent a 6-digit code to #{ERB::Util.html_escape(email.to_s)}.</p>
        #{error ? %(<p class="err">#{ERB::Util.html_escape(error)}</p>) : ""}
        <form method="post" action="/account/verify">#{csrf_input}
          <input type="hidden" name="email" value="#{ERB::Util.html_escape(email.to_s)}">
          <label>Code<input type="text" name="code" inputmode="numeric" pattern="[0-9]{6}"
                 maxlength="6" required autofocus></label>
          <button type="submit">Sign in</button>
        </form>
        <form method="post" action="/account/login">#{csrf_input}
          <input type="hidden" name="email" value="#{ERB::Util.html_escape(email.to_s)}">
          <button type="submit">Resend code</button>
        </form>
      BODY
    end

    def account_html(customer, orders)
      rows = orders.map do |order|
        checkout_token = Checkout.where(shop_id: current_shop.id, id: order.checkout_id).pick(:token)
        link = checkout_token ? %(<a href="/checkouts/#{checkout_token}/complete">#{order.name}</a>) : order.name
        "<tr><td>#{link}</td><td>#{order.processed_at&.strftime('%Y-%m-%d')}</td>" \
        "<td>#{order.financial_status}</td><td>#{order.fulfillment_status}</td>" \
        "<td>#{format('%s %d.%02d', order.currency, order.total_cents / 100, order.total_cents % 100)}</td></tr>"
      end.join
      shell("Account", <<~BODY)
        <h1>Account</h1>
        <nav><a href="/account">Orders</a><a href="/account/addresses">Addresses</a></nav>
        <p>#{ERB::Util.html_escape(customer.email.to_s)}</p>
        <h2>Order history</h2>
        #{orders.empty? ? "<p>No orders yet.</p>" : "<table><tr><th>Order</th><th>Date</th><th>Payment</th><th>Fulfillment</th><th>Total</th></tr>#{rows}</table>"}
        <form method="post" action="/account/logout">#{csrf_input}<button type="submit">Log out</button></form>
      BODY
    end

    def addresses_html(customer, rows)
      list = rows.map do |address|
        name = [ address.first_name, address.last_name ].compact.join(" ")
        badge = address.default_address ? " <strong>(default)</strong>" : ""
        "<p>#{ERB::Util.html_escape(name)}#{badge}<br>" \
        "#{ERB::Util.html_escape(address.address1)}<br>" \
        "#{ERB::Util.html_escape(address.city)} #{ERB::Util.html_escape(address.province.to_s)} " \
        "#{ERB::Util.html_escape(address.postal_code.to_s)}<br>#{address.country_code}</p>"
      end.join
      shell("Addresses", <<~BODY)
        <h1>Addresses</h1>
        <nav><a href="/account">Orders</a><a href="/account/addresses">Addresses</a></nav>
        #{rows.empty? ? "<p>No addresses saved.</p>" : list}
        <p>#{ERB::Util.html_escape(customer.email.to_s)}</p>
      BODY
    end
  end
end
