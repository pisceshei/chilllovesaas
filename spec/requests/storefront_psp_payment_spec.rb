# frozen_string_literal: true

require "rails_helper"

# G6-1c：結帳頁 PSP（Airwallex QR 原生流）端到端。
#
# 🔴 假綠殺手（20.2⑤）：
#   Q2 殺「PSP 快照走 manual 成單」（沒付錢就出單）；
#   Q4 殺「輪詢成功不冪等」（雙路徑重複入帳／重複 outbox）；
#   Q5 殺「金額不比對就成單」（65 §E）；
#   Q1 殺「不可用方式仍出現」（F4.2 hide 語義）。
RSpec.describe "Storefront PSP payment（G6-1c）", type: :request do
  let!(:shop) { create(:shop, subdomain: "psp-pay-shop") }
  let!(:manual) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentMethod.create!(shop_id: shop.id, method_type: "bank_deposit")
    end
  end
  let!(:provider) do
    ActsAsTenant.with_tenant(shop) do
      # G6-3 步 2 起 status 是唯一啟用真相（configured_provider 改讀它）⇒ 顯式 active。
      ShopPaymentProvider.create!(
        provider: "airwallex", client_id: "cid", api_secret: "key", webhook_secret: "whsec",
        status: "active",
        enabled_methods: %w[card alipayhk fps], available_methods: %w[card alipayhk fps],
        capabilities_synced_at: Time.current
      )
    end
  end
  let(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 10_000,
                 product: create(:product, shop:, status: "active", title: "PSP 測品"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      v
    end
  end
  let(:intents) { instance_double(Psp::Airwallex::PaymentIntents) }

  before do
    host! "psp-pay-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    allow(Psp::Airwallex::PaymentIntents).to receive(:new).and_return(intents)
  end

  def ready_checkout!(psp: true)
    post "/cart/add.js", params: { items: [ { id: variant.id, quantity: 2 } ] }.to_json,
                         headers: { "CONTENT_TYPE" => "application/json" }
    post "/checkout"
    token = response.headers["Location"][%r{/checkouts/(\h{48})}, 1]
    post "/checkouts/#{token}/delivery", params: { country_code: "HK" }
    post "/checkouts/#{token}/payment",
         params: { payment_method_id: psp ? "psp:airwallex:alipayhk" : manual.id }
    ActsAsTenant.with_tenant(shop) { Checkout.find_by!(token:) }
  end

  it "Q1 🔴 付款段三層交集：AlipayHK/FPS/Credit Card 出現；白名單外**不出現**（hide 非 disable）" do
    checkout = ready_checkout!(psp: false)
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("psp:airwallex:alipayhk").and include("psp:airwallex:fps")
    expect(response.body).to include("psp:airwallex:card") # G6-1d 起平台已實作
    expect(response.body).to include("Bank Deposit") # manual 共存

    ActsAsTenant.with_tenant(shop) { provider.update!(enabled_methods: %w[fps]) }
    get "/checkouts/#{checkout.token}"
    expect(response.body).not_to include("psp:airwallex:alipayhk") # hide，不是 disable
    expect(response.body).not_to include("psp:airwallex:card")
  end

  it "Q8 card ⇒ SDK 卡片頁：CDN script＋config（client_secret／env=demo）＋mount 容器；不打 confirm" do
    checkout = ready_checkout!(psp: false)
    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: "psp:airwallex:card" }
    expect(intents).to receive(:create)
      .with(hash_including(request_id: "pi-#{checkout.token}-20000"))
      .and_return({ "id" => "int_c1", "client_secret" => "cs_abc", "status" => "REQUIRES_PAYMENT_METHOD" })
    expect(intents).not_to receive(:confirm_qr)

    post "/checkouts/#{checkout.token}/pay"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("static.airwallex.com/components/sdk/v1/index.js")
    expect(response.body).to include('"client_secret":"cs_abc"').and include('"env":"demo"')
    expect(response.body).to include("data-card-mount").and include("data-card-pay")
    expect(ActsAsTenant.with_tenant(shop) { checkout.reload.psp_intent_id }).to eq("int_c1")
  end

  it "Q9 googlepay ⇒ wallet 頁：element 名＋amount JSON number（無引號）＋countryCode" do
    ActsAsTenant.with_tenant(shop) do
      provider.update!(enabled_methods: %w[card alipayhk fps googlepay],
                       available_methods: %w[card alipayhk fps googlepay])
    end
    checkout = ready_checkout!(psp: false)
    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: "psp:airwallex:googlepay" }
    allow(intents).to receive(:create)
      .and_return({ "id" => "int_w1", "client_secret" => "cs_w", "status" => "REQUIRES_PAYMENT_METHOD" })

    post "/checkouts/#{checkout.token}/pay"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"element":"googlePayButton"')
    expect(response.body).to include('"amount_value":200').and satisfy { |b| !b.include?('"amount_value":"200"') }
    expect(response.body).to include('"country_code":"HK"')
    expect(response.body).to include("data-wallet-mount")
  end

  it "Q10 production 環境 ⇒ SDK env=prod（環境映射殺手格）" do
    ActsAsTenant.with_tenant(shop) { provider.update!(environment: "production") }
    checkout = ready_checkout!(psp: false)
    post "/checkouts/#{checkout.token}/payment", params: { payment_method_id: "psp:airwallex:card" }
    allow(intents).to receive(:create)
      .and_return({ "id" => "int_c2", "client_secret" => "cs2", "status" => "REQUIRES_PAYMENT_METHOD" })
    post "/checkouts/#{checkout.token}/pay"
    expect(response.body).to include('"env":"prod"')
  end

  it "Q2 🔴 PSP 快照走 manual complete ⇒ 422 且不建單；完成鈕改「以 X 付款」指向 /pay" do
    checkout = ready_checkout!
    get "/checkouts/#{checkout.token}"
    expect(response.body).to include("data-ck-form").and include("Pay now")
    expect(response.body).not_to include("data-complete-form")

    post "/checkouts/#{checkout.token}/complete"
    expect(response).to have_http_status(:unprocessable_content)
    expect(ActsAsTenant.with_tenant(shop) { Order.count }).to eq(0)
  end

  it "Q3 /pay：建 intent（request_id=pi-<token>-<cents> 冪等）→ confirm(qrcode) → QR 頁＋輪詢" do
    checkout = ready_checkout!
    expect(intents).to receive(:create)
      .with(hash_including(request_id: "pi-#{checkout.token}-20000", merchant_order_id: checkout.token))
      .and_return({ "id" => "int_1", "status" => "REQUIRES_PAYMENT_METHOD" })
    expect(intents).to receive(:confirm_qr).with("int_1", method: "alipayhk")
      .and_return({ "status" => "REQUIRES_CUSTOMER_ACTION",
                    "next_action" => { "type" => "render_qrcode", "qrcode" => "awx://pay/abc" } })

    post "/checkouts/#{checkout.token}/pay"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<svg") # rqrcode 伺服端 SVG
    expect(response.body).to include("/checkouts/#{checkout.token}/pay/status")
    expect(ActsAsTenant.with_tenant(shop) { checkout.reload.psp_intent_id }).to eq("int_1")
  end

  it "Q4 🔴 輪詢 SUCCEEDED ⇒ 成單＋入帳恰一次（tx success/gateway=airwallex/provider_reference；orders/create＋orders/paid 各一）" do
    checkout = ready_checkout!
    ActsAsTenant.with_tenant(shop) { checkout.update!(psp_intent_id: "int_9") }
    allow(intents).to receive(:get).with("int_9").and_return(
      { "id" => "int_9", "status" => "SUCCEEDED", "merchant_order_id" => checkout.token,
        "amount" => BigDecimal("200"), "currency" => "HKD" }
    )

    2.times { get "/checkouts/#{checkout.token}/pay/status" }
    expect(response.parsed_body).to include("status" => "succeeded",
                                            "redirect" => "/checkouts/#{checkout.token}/complete")

    ActsAsTenant.with_tenant(shop) do
      order = Order.sole
      expect(order.financial_status).to eq("paid")
      tx = order.order_transactions.sole
      expect(tx).to have_attributes(kind: "sale", status: "success", gateway: "airwallex",
                                    provider_reference: "int_9", amount_cents: 20_000)
    end
    topics = ActsAsTenant.without_tenant { EventOutbox.where("topic LIKE 'orders/%'").pluck(:topic).sort }
    expect(topics).to eq([ "orders/create", "orders/paid" ]) # 各恰一，重複輪詢不加發

    get "/checkouts/#{checkout.token}/complete" # thank-you 可看
    expect(response).to have_http_status(:ok)
  end

  it "Q5 🔴 金額不符 ⇒ 不建單、422 amount_mismatch（65 §E）" do
    checkout = ready_checkout!
    ActsAsTenant.with_tenant(shop) { checkout.update!(psp_intent_id: "int_bad") }
    allow(intents).to receive(:get).with("int_bad").and_return(
      { "id" => "int_bad", "status" => "SUCCEEDED", "merchant_order_id" => checkout.token,
        "amount" => BigDecimal("2"), "currency" => "HKD" } # 應收 200.00
    )
    get "/checkouts/#{checkout.token}/pay/status"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["status"]).to eq("amount_mismatch")
    expect(ActsAsTenant.with_tenant(shop) { Order.count }).to eq(0)
  end

  it "Q6 webhook 消費：簽名事件 → job → 權威重取 intent → 成單入帳；重複投遞單一結果" do
    checkout = ready_checkout!
    ActsAsTenant.with_tenant(shop) { checkout.update!(psp_intent_id: "int_wh") }
    allow(intents).to receive(:get).with("int_wh").and_return(
      { "id" => "int_wh", "status" => "SUCCEEDED", "merchant_order_id" => checkout.token,
        "amount" => BigDecimal("200"), "currency" => "HKD" }
    )
    event = { id: "evt_pay_1", name: "payment_intent.succeeded",
              data: { object: { id: "int_wh" } } }
    body = JSON.generate(event)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{timestamp}#{body}")

    perform_enqueued_jobs do
      2.times do
        post "/webhooks/airwallex", params: body,
             headers: { "CONTENT_TYPE" => "application/json",
                        "x-timestamp" => timestamp, "x-signature" => signature }
      end
    end

    ActsAsTenant.with_tenant(shop) do
      expect(Order.sole.financial_status).to eq("paid")
      expect(PspWebhookEvent.sole).to have_attributes(status: "processed")
    end
  end

  it "Q7 快照殘留但白名單已移除 ⇒ /pay 422（server 重驗）" do
    checkout = ready_checkout!
    ActsAsTenant.with_tenant(shop) { provider.update!(enabled_methods: %w[fps]) }
    post "/checkouts/#{checkout.token}/pay"
    expect(response).to have_http_status(:unprocessable_content)
  end
  # 🔴 G6-3 步 2 的 M4 守衛：憑證在但 status=inactive ⇒ PSP 選項不出現在付款段
  #   （殺：configured_provider 退回「有指紋即啟用」——admin 的停用鈕變成裝飾）。
  it "🔴 M4 provider 停用（status=inactive）⇒ 付款段不出 PSP 選項；manual 不受影響" do
    checkout = ready_checkout!(psp: false)
    ActsAsTenant.with_tenant(shop) { provider.update!(status: "inactive") }
    get "/checkouts/#{checkout.token}"
    expect(response.body).not_to include("psp:airwallex:")
    expect(response.body).to include("Bank Deposit")
  end
end
