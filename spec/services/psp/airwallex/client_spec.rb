# frozen_string_literal: true

require "rails_helper"

# G6-1a：Airwallex client。
#
# 🔴 假綠殺手：「amount 原文注入」格斷言 body 含 **無引號** 的 `"amount":14.8`——
# `BigDecimal#to_json` 預設吐字串（"14.8"），只斷言「body 有 14.8」殺不掉字串形。
RSpec.describe Psp::Airwallex::Client do
  let!(:shop) { create(:shop) }
  let(:provider) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.create!(provider: "airwallex", client_id: "cid_test",
                                  api_secret: "key_test", webhook_secret: "whsec")
    end
  end

  def response_stub(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: JSON.generate(body))
  end

  def transport_recording(into, responses)
    lambda do |req, uri|
      into << { path: req.path, body: req.body, headers: req.to_hash, host: uri.host }
      responses.shift or raise "transport 沒有更多回應"
    end
  end

  it "登入用列上憑證、host 依 environment（sandbox ⇒ api-demo）、token 進後續請求" do
    calls = []
    transport = transport_recording(calls, [
      response_stub(201, { token: "tok_1", expires_at: 25.minutes.from_now.iso8601 }),
      response_stub(200, { id: "int_1" })
    ])
    client = described_class.new(provider, transport:)
    client.get_json("/api/v1/pa/payment_intents/int_1")

    expect(calls[0][:host]).to eq("api-demo.airwallex.com")
    expect(calls[0][:headers]["x-client-id"]).to eq([ "cid_test" ])
    expect(calls[0][:headers]["x-api-key"]).to eq([ "key_test" ])
    expect(calls[1][:headers]["authorization"]).to eq([ "Bearer tok_1" ])
    expect(calls[1][:headers]["x-api-version"])
      .to eq([ Limits.fetch(:psp_integration, :airwallex, :api_version) ])
  end

  it "🔴 amount 以 JSON number 原文注入（無引號；BigDecimal#to_json 的字串形被殺）" do
    calls = []
    transport = transport_recording(calls, [
      response_stub(201, { token: "tok_1" }),
      response_stub(201, { id: "int_1", status: "REQUIRES_PAYMENT_METHOD" })
    ])
    client = described_class.new(provider, transport:)
    client.post_json("/x/create", { request_id: "r1", currency: "HKD" },
                     amount_psp_number: BigDecimal("14.8"))

    expect(calls[1][:body]).to include('"amount":14.8')
    expect(calls[1][:body]).not_to include('"amount":"14.8"')
  end

  it "amount_psp_number 收到非 BigDecimal ⇒ TypeError（Float 即 bug）" do
    client = described_class.new(provider, transport: ->(*) { raise "不該打到" })
    expect { client.post_json("/x", {}, amount_psp_number: 14.8) }
      .to raise_error(TypeError, /Float 即 bug/)
  end

  it "401 ⇒ Unauthorized（訊息帶 Airwallex code、不帶祕密）" do
    transport = transport_recording([], [ response_stub(401, { code: "credentials_invalid" }) ])
    client = described_class.new(provider, transport:)
    expect { client.get_json("/x") }.to raise_error(described_class::Unauthorized, /credentials_invalid/)
  end

  it "token 在 expires_at 內快取（第二個請求不重登）" do
    calls = []
    transport = transport_recording(calls, [
      response_stub(201, { token: "tok_1", expires_at: 25.minutes.from_now.iso8601 }),
      response_stub(200, { id: "a" }),
      response_stub(200, { id: "b" })
    ])
    client = described_class.new(provider, transport:)
    client.get_json("/a")
    client.get_json("/b")
    login_calls = calls.count { |c| c[:path].include?("authentication/login") }
    expect(login_calls).to eq(1)
  end
end
