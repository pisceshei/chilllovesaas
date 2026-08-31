# frozen_string_literal: true

require "rails_helper"

# G6-1b：capability 端點（官方 schema 取證 2026-08-31：{has_more, items:[{active,
# name, transaction_mode, …}]}；同名可因 transaction_mode 重複）。
RSpec.describe Psp::Airwallex::PaymentMethodTypes do
  let!(:shop) { create(:shop) }
  let(:provider) do
    ActsAsTenant.with_tenant(shop) do
      ShopPaymentProvider.create!(provider: "airwallex", client_id: "cid", api_secret: "key")
    end
  end

  def response_stub(body)
    instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(body))
  end

  it "分頁跟到 has_more 結束；oneoff＋active 過濾；同名去重、字母序" do
    calls = []
    pages = [
      response_stub({ token: "t", expires_at: 25.minutes.from_now.iso8601 }), # login（缺 expires_at 會每請求重登）
      response_stub({ has_more: true, items: [
        { "active" => true, "name" => "card", "transaction_mode" => "oneoff" },
        { "active" => true, "name" => "card", "transaction_mode" => "recurring" },
        { "active" => false, "name" => "fps", "transaction_mode" => "oneoff" }
      ] }),
      response_stub({ has_more: false, items: [
        { "active" => true, "name" => "alipayhk", "transaction_mode" => "oneoff" }
      ] })
    ]
    transport = ->(req, _uri) { calls << req.path; pages.shift }

    names = described_class.fetch(provider, transport:)
    expect(names).to eq(%w[alipayhk card])
    expect(calls[1]).to include("active=true").and include("transaction_mode=oneoff").and include("page_num=0")
    expect(calls[2]).to include("page_num=1")
  end
end
