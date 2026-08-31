# frozen_string_literal: true

require "rails_helper"

# G6-1a：Airwallex webhook 端點（驗簽 fail-closed＋event_id 冪等）。
#
# 🔴 假綠殺手：W2 殺「拔掉 secure_compare／簽章驗證」；W4 殺「重複投遞落兩列」。
RSpec.describe "Airwallex webhook", type: :request do
  let!(:shop) { create(:shop, subdomain: "awx-hook-shop") }
  let!(:provider) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.create!(provider: "airwallex", client_id: "cid",
                                  api_secret: "key", webhook_secret: "whsec_test")
    end
  end

  let(:event) do
    { id: "evt_001", name: "payment_intent.succeeded",
      data: { object: { id: "int_1", amount: 16.66, currency: "HKD" } } }
  end

  before do
    host! "awx-hook-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def post_event(body, secret: "whsec_test", timestamp: Time.current.to_i.to_s, signature: nil)
    signature ||= OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}#{body}")
    post "/webhooks/airwallex", params: body,
         headers: { "CONTENT_TYPE" => "application/json",
                    "x-timestamp" => timestamp, "x-signature" => signature }
  end

  it "W1 合法簽章 ⇒ 200＋收錄一列（status=received、payload 原樣）" do
    post_event(JSON.generate(event))
    expect(response).to have_http_status(:ok)
    row = ActsAsTenant.with_tenant(shop) { PspWebhookEvent.sole }
    expect(row).to have_attributes(provider: "airwallex", event_id: "evt_001",
                                   event_type: "payment_intent.succeeded", status: "received")
    expect(row.payload.dig("data", "object", "amount")).to eq(16.66)
  end

  it "W2 🔴 壞簽章 ⇒ 401、零落庫（fail-closed）" do
    post_event(JSON.generate(event), signature: "0" * 64)
    expect(response).to have_http_status(:unauthorized)
    expect(ActsAsTenant.with_tenant(shop) { PspWebhookEvent.count }).to eq(0)
  end

  it "W3 缺 timestamp／signature header ⇒ 401" do
    post "/webhooks/airwallex", params: JSON.generate(event),
         headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "W4 🔴 重複投遞（同 event_id）⇒ 200 且只有一列" do
    2.times { post_event(JSON.generate(event)) }
    expect(response).to have_http_status(:ok)
    expect(ActsAsTenant.with_tenant(shop) { PspWebhookEvent.count }).to eq(1)
  end

  it "W5 沒有 provider 列（或無 webhook_secret）⇒ 401" do
    ActsAsTenant.with_tenant(shop) { provider.destroy! }
    post_event(JSON.generate(event))
    expect(response).to have_http_status(:unauthorized)
  end

  it "W6 簽章蓋的是 raw body：body 被竄改一個字元 ⇒ 401" do
    body = JSON.generate(event)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{timestamp}#{body}")
    post "/webhooks/airwallex", params: body.sub("16.66", "16.67"),
         headers: { "CONTENT_TYPE" => "application/json",
                    "x-timestamp" => timestamp, "x-signature" => signature }
    expect(response).to have_http_status(:unauthorized)
  end
end
