# frozen_string_literal: true

require "rails_helper"

# 步 20a：webhook 投遞（28 §15 headers＋HMAC）＋rebinding 防線＋fanout＋失敗停用。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   D2 投遞時 DNS rebinding 再驗（殺：建立時驗過就信一輩子——18 F4 點名）
#   D1 HMAC/headers（殺：簽章鍵錯位＝消費端全部驗不過或可偽造）
#   D5 fanout 只投同 topic（殺：訂 orders/create 卻收到全店事件）
RSpec.describe Webhooks::Deliver do
  include ActiveJob::TestHelper
  let(:shop) { create(:shop, subdomain: "whd-shop") }
  let(:subscription) do
    ActsAsTenant.with_tenant(shop) do
      WebhookSubscription.create!(shop_id: shop.id, topic: "orders/create",
                                  url: "https://hook.example.com/a", secret: "s" * 48)
    end
  end
  let(:event) do
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(event_id: SecureRandom.uuid, topic: "orders/create",
                          aggregate_type: "Order", aggregate_id: 1,
                          payload: { "id" => 1001, "admin_graphql_api_id" => "gid://chilllove/Order/1001" },
                          available_at: Time.current)
    end
  end

  def fake_http(code: "200", body: "ok")
    captured = {}
    response = instance_double(Net::HTTPResponse, code:, body:)
    http = double("http")
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:ipaddr=) { |ip| captured[:ipaddr] = ip }
    allow(http).to receive(:open_timeout=) { |t| captured[:open_timeout] = t }
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start) do |&blk|
      conn = double("conn")
      allow(conn).to receive(:request) { |req| captured[:request] = req; response }
      blk.call(conn)
    end
    allow(Net::HTTP).to receive(:new).and_return(http)
    captured
  end

  before do
    allow(Resolv).to receive(:getaddresses).with("hook.example.com").and_return([ "93.184.216.34" ])
    clear_enqueued_jobs # 測試 adapter 不跨例清佇列（D5 首輪吃到 D4 殘留實錘）
  end

  it "D1 🔴 成功投遞：七 header＋HMAC=base64(HMAC-SHA256(raw body, secret))＋vetted IP 直連＋sent 紀錄" do
    captured = fake_http
    result = described_class.call(subscription:, event:, shop:)
    expect(result.ok?).to be(true)

    request = captured[:request]
    body = request.body
    expect(JSON.parse(body)["id"]).to eq(1001)
    expect(request["X-CL-Topic"]).to eq("orders/create")
    expect(request["X-CL-Event-Id"]).to eq(event.event_id)
    expect(request["X-CL-Shop-Domain"]).to eq("whd-shop")
    expect(request["X-CL-API-Version"]).to eq("2026-08")
    expect(request["X-CL-Webhook-Id"]).to be_present
    expect(request["X-CL-Triggered-At"]).to be_present
    expected_hmac = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "s" * 48, body))
    expect(request["X-CL-Hmac-Sha256"]).to eq(expected_hmac)

    expect(captured[:ipaddr]).to eq("93.184.216.34") # 🔴 rebinding 窗：直連 vetted IP
    expect(captured[:open_timeout]).to eq(5)          # 28 §15「5 秒內」

    log = ActsAsTenant.with_tenant(shop) { WebhookDelivery.last }
    expect(log.state).to eq("sent")
    expect(log.status_code).to eq(200)
  end

  it "D2 🔴 投遞時 DNS rebinding 再驗：resolve 變 127.0.0.1 ⇒ 不發請求、failed 紀錄" do
    subscription # 先建（建立時是公網）
    allow(Resolv).to receive(:getaddresses).with("hook.example.com").and_return([ "127.0.0.1" ])
    expect(Net::HTTP).not_to receive(:new)
    result = described_class.call(subscription:, event:, shop:)
    expect(result.ok?).to be(false)
    expect(ActsAsTenant.with_tenant(shop) { WebhookDelivery.last.state }).to eq("failed")
  end

  it "D3 非 2xx＝failed（3xx 不跟隨也算失敗）＋回應截 1KB" do
    fake_http(code: "302", body: "x" * 5000)
    result = described_class.call(subscription:, event:, shop:)
    expect(result.ok?).to be(false)
    log = ActsAsTenant.with_tenant(shop) { WebhookDelivery.last }
    expect(log.state).to eq("failed")
    expect(log.response_excerpt.bytesize).to be <= 1024
  end

  describe Webhooks::DeliverJob do
    it "D4 失敗 ⇒ failure_count++＋退避重排；達門檻 ⇒ disabled；成功 ⇒ 歸零" do
      fake_http(code: "500", body: "err")
      described_class.perform_now(subscription.id, event.event_id, shop.id, 1)
      expect(subscription.reload.failure_count).to eq(1)
      expect(Webhooks::DeliverJob).to have_been_enqueued.with(subscription.id, event.event_id, shop.id, 2)

      ActsAsTenant.with_tenant(shop) do
        subscription.update!(failure_count: Limits.fetch(:webhook, :disable_after_failures) - 1)
      end
      described_class.perform_now(subscription.id, event.event_id, shop.id, 1)
      expect(subscription.reload.status).to eq("disabled")

      ActsAsTenant.with_tenant(shop) { subscription.update!(status: "active", failure_count: 3) }
      fake_http(code: "200")
      described_class.perform_now(subscription.id, event.event_id, shop.id, 1)
      expect(subscription.reload.failure_count).to eq(0)
    end
  end

  describe Webhooks::FanoutConsumer do
    it "D5 🔴 掛載縫：EXTERNAL topic 才有 fanout；只投同 topic 的 active 訂閱" do
      expect(Events::Consumers.for("orders/create")).to include(described_class)
      expect(Events::Consumers.for(Events::Topics::PRODUCT_UPDATED)).not_to include(described_class)

      other = ActsAsTenant.with_tenant(shop) do
        WebhookSubscription.create!(shop_id: shop.id, topic: "products/update",
                                    url: "https://hook.example.com/b", secret: "t" * 48)
      end
      disabled = ActsAsTenant.with_tenant(shop) do
        WebhookSubscription.create!(shop_id: shop.id, topic: "orders/create",
                                    url: "https://hook.example.com/c", secret: "u" * 48,
                                    status: "disabled")
      end

      subscription # 🔴 lazy let：不先 force，fanout 跑的時候列還不存在
      described_class.call(event)
      expect(Webhooks::DeliverJob).to have_been_enqueued.with(subscription.id, event.event_id, shop.id, 1)
      expect(Webhooks::DeliverJob).not_to have_been_enqueued.with(other.id, event.event_id, shop.id, 1)
      expect(Webhooks::DeliverJob).not_to have_been_enqueued.with(disabled.id, event.event_id, shop.id, 1)
    end
  end
end
