# frozen_string_literal: true

require "rails_helper"

# G6-1a：payment_intents 服務（Money 契約全鏈：Storage→PspNumber→原文注入）。
RSpec.describe Psp::Airwallex::PaymentIntents do
  let!(:shop) { create(:shop) }

  def provider_for(environment)
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.find_by(provider: "airwallex")&.destroy!
      ShopPaymentProvider.create!(provider: "airwallex", environment:,
                                  client_id: "cid", api_secret: "key")
    end
  end

  def response_stub(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: JSON.generate(body))
  end

  it "create：HKD 14.80（儲存 1480）⇒ body `\"amount\":14.8`＋currency／request_id 透傳" do
    calls = []
    transport = lambda do |req, _uri|
      calls << { path: req.path, body: req.body }
      calls.length == 1 ? response_stub(201, { token: "t" }) : response_stub(201, { id: "int_9", status: "REQUIRES_PAYMENT_METHOD" })
    end
    service = described_class.new(provider_for("sandbox"), transport:)
    result = service.create(amount: Money::Storage.from_cents(1_480, "HKD"),
                            request_id: "req-1", merchant_order_id: "order-1")

    expect(result["id"]).to eq("int_9")
    create_call = calls.last
    expect(create_call[:path]).to end_with("/payment_intents/create")
    expect(create_call[:body]).to include('"amount":14.8')
    expect(create_call[:body]).to include('"currency":"HKD"').and include('"request_id":"req-1"')
  end

  it "🔴 JPY 零小數（Airwallex 覆蓋表）：¥1,480 ⇒ `\"amount\":1480`；¥1,480.50 ⇒ raise 不送出" do
    calls = []
    transport = lambda do |req, _uri|
      calls << req.body
      calls.length == 1 ? response_stub(201, { token: "t" }) : response_stub(201, { id: "i" })
    end
    service = described_class.new(provider_for("sandbox"), transport:)
    service.create(amount: Money::Storage.from_cents(148_000, "JPY"),
                   request_id: "r", merchant_order_id: "m")
    expect(calls.last).to include('"amount":1480,')       # 🔴 無 .0 尾、無引號
    expect(calls.last).not_to include('"amount":1480.0')

    expect {
      service.create(amount: Money::Storage.from_cents(148_050, "JPY"),
                     request_id: "r2", merchant_order_id: "m2")
    }.to raise_error(Money::NonIntegralConversion)
  end

  it "🔴 confirm_with_test_card 在 production ⇒ raise（PAN 只准 sandbox 走 API）" do
    service = described_class.new(provider_for("production"), transport: ->(*) { raise "不該連線" })
    expect { service.confirm_with_test_card("int_1", card: { number: "4" }) }
      .to raise_error(Psp::Airwallex::Client::Error, /只准 sandbox/)
  end
end
