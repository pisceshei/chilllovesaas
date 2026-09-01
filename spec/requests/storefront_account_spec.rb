# frozen_string_literal: true

require "rails_helper"

# G6 步 11：買家帳戶線（74 §7 passwordless OTP）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   T2 嘗試上限（殺：無上限——6 位碼可枚舉爆破）
#   T3 重發冷卻（殺：無冷卻——寄信轟炸）
#   T4 過期碼拒收（殺：不看 expires_at）
#   T5 已用碼拒收（殺：consumed_at 不落——碼可重放）
#   T7 預填不覆蓋手動輸入（殺：登入態蓋掉買家改過的 email）
RSpec.describe "storefront customer account", type: :request do
  include ActiveJob::TestHelper

  let!(:shop) { create(:shop, subdomain: "acct") }

  before do
    host! "acct.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
  end

  # 發碼 → 從寄出的信抽 6 位碼（端到端走通知鏈——不摸 digest）
  def request_code!(email)
    post "/account/login", params: { email: }
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    body = mail.html_part&.body&.to_s || mail.body.to_s
    body[/\b(\d{6})\b/, 1]
  end

  def sign_in!(email)
    code = request_code!(email)
    post "/account/verify", params: { email:, code: }
    expect(response).to redirect_to("/account")
    code
  end

  it "T1 端到端：發碼信（走 customer_otp 模板）→ 驗碼 → 自動建 profile（normalize）→ /account" do
    sign_in!("  New.Buyer@Example.COM ")

    customer = ActsAsTenant.without_tenant { Customer.find_by(shop_id: shop.id, email: "new.buyer@example.com") }
    expect(customer).to be_present, "未註冊 email 首登應自動建 profile（74 §7）"

    get "/account"
    expect(response.body).to include("new.buyer@example.com")
    expect(response.body).to include("Order history")
  end

  it "🔴 T2 嘗試上限：連錯 5 次 ⇒ 之後連對碼也拒（重新取碼才行）" do
    code = request_code!("cap@example.com")
    5.times { post "/account/verify", params: { email: "cap@example.com", code: "000000" } }
    post "/account/verify", params: { email: "cap@example.com", code: }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("嘗試次數過多")
  end

  it "🔴 T3 重發冷卻：60 秒內第二次發碼 ⇒ 429" do
    request_code!("cool@example.com")
    post "/account/login", params: { email: "cool@example.com" }
    expect(response).to have_http_status(:too_many_requests)
  end

  it "🔴 T4 過期碼 ⇒ 拒收（limits customer.otp_expiry_minutes）" do
    code = request_code!("exp@example.com")
    minutes = Limits.fetch(:customer, :otp_expiry_minutes).to_i
    travel_to((minutes + 1).minutes.from_now) do
      post "/account/verify", params: { email: "exp@example.com", code: }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "🔴 T5 已用碼 ⇒ 二次驗證拒收（防重放）" do
    email = "reuse@example.com"
    code = sign_in!(email)
    post "/account/logout"
    post "/account/verify", params: { email:, code: }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "T6 /account 未登入 ⇒ 轉 /account/login；logout 清 session" do
    get "/account"
    expect(response).to redirect_to("/account/login")

    sign_in!("sess@example.com")
    post "/account/logout"
    get "/account"
    expect(response).to redirect_to("/account/login")
  end

  it "🔴 T6b session 逾期（365 天上限）⇒ /account 轉登入頁（cookie 還在也沒用）" do
    sign_in!("expire-sess@example.com")
    days = Limits.fetch(:customer, :session_days).to_i
    travel_to((days + 1).days.from_now) do
      get "/account"
      expect(response).to redirect_to("/account/login"),
        "session 過期不驗＝永久 cookie（74 §7 的 365 天上限破約）"
    end
  end

  # T6b 的 travel 會讓 rack-test 的 cookie 先過期（雙防線的客戶端層）⇒ DB 層
  # expires_at 檢查在 request 面測不到——直接打 model（重放窗＝cookie 被竊時
  # 只剩這道）。
  it "🔴 T6c authenticate 拒過期列（DB 端防線；MO5 的殺點）" do
    customer = ActsAsTenant.with_tenant(shop) do
      Customer.create!(shop_id: shop.id, email: "stale-sess@example.com")
    end
    _row, token = ActsAsTenant.with_tenant(shop) do
      CustomerSession.issue!(shop:, customer:)
    end
    ActsAsTenant.without_tenant do
      CustomerSession.where(customer_id: customer.id).update_all(expires_at: 1.day.ago)
    end
    result = ActsAsTenant.with_tenant(shop) { CustomerSession.authenticate(shop:, token:) }
    expect(result).to be_nil, "過期列仍驗過＝被竊 token 永久有效"
  end

  it "🔴 T7 結帳預填：email 空才填＋掛 customer_id；已有 email 不覆蓋" do
    email = "prefill@example.com"
    sign_in!(email)
    customer = ActsAsTenant.without_tenant { Customer.find_by(shop_id: shop.id, email:) }
    ActsAsTenant.with_tenant(shop) do
      CustomerAddress.create!(shop_id: shop.id, customer_id: customer.id,
                              first_name: "Pre", last_name: "Fill", address1: "9 Fill Rd",
                              city: "HK", country_code: "HK", default_address: true)
    end

    variant = ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 5000,
                 product: create(:product, shop:, status: "active", title: "預填測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      v
    end
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 1 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    get "/checkouts/#{token}"

    checkout = ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
    expect(checkout.email).to eq(email)
    expect(checkout.customer_id).to eq(customer.id)
    expect(checkout.shipping_address["address1"]).to eq("9 Fill Rd") # 預設地址預填

    # 買家手動改 email 後再訪 ⇒ 不覆蓋
    ActsAsTenant.with_tenant(shop) { checkout.update!(email: "manual@example.com") }
    get "/checkouts/#{token}"
    expect(checkout.reload.email).to eq("manual@example.com"),
      "登入態蓋掉手動輸入＝買家改單失效"
  end

  it "結帳頁 Sign in 連結接通（死鏈收口）" do
    get "/account/login"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("6-digit code")
  end
end
