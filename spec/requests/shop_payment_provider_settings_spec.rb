# frozen_string_literal: true

require "rails_helper"

# G6-3 前半：設定 › 付款的 provider 憑證層（37 §6.3 write-only＋只回指紋）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   P3 殺「省略祕密參數把既有 key 清掉」（write-only 的核心約定）；
#   P5 殺「type 上不小心長出祕密欄」（introspection 斷言——比「query 沒選它」強）。
RSpec.describe "Admin GraphQL shop payment provider settings", type: :request do
  let(:shop) { create(:shop, subdomain: "psp-settings-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  let(:list_query) { <<~GRAPHQL }
    query shopPaymentProviderList {
      shopPaymentProviders {
        provider environment status clientId webhookId
        apiSecretFingerprint webhookSecretFingerprint enabledMethods
      }
    }
  GRAPHQL

  let(:set_mutation) { <<~GRAPHQL }
    mutation shopPaymentProviderSet($provider: String!, $environment: String,
        $clientId: String, $apiSecret: String, $webhookSecret: String, $webhookId: String) {
      shopPaymentProviderSet(provider: $provider, environment: $environment,
          clientId: $clientId, apiSecret: $apiSecret, webhookSecret: $webhookSecret, webhookId: $webhookId) {
        shopPaymentProvider { provider environment apiSecretFingerprint }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "psp-settings-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  it "P1 建立＋回讀：祕密只回指紋；DB 落密文" do
    post_graphql(set_mutation, variables: { provider: "airwallex", clientId: "cid_1", apiSecret: "sk_test_9" })
    payload = response.parsed_body.dig("data", "shopPaymentProviderSet")
    expect(payload["userErrors"]).to eq([])
    expect(payload.dig("shopPaymentProvider", "apiSecretFingerprint"))
      .to eq(Digest::SHA256.hexdigest("sk_test_9").first(16))

    raw = ActiveRecord::Base.connection.select_value("SELECT api_secret FROM shop_payment_providers LIMIT 1")
    expect(raw).not_to include("sk_test_9")

    post_graphql(list_query)
    rows = response.parsed_body.dig("data", "shopPaymentProviders")
    expect(rows.length).to eq(1)
    expect(rows.first).to include("provider" => "airwallex", "environment" => "sandbox", "clientId" => "cid_1")
  end

  it "P2 upsert：同 provider 第二次寫入更新既有列（不增殖）" do
    2.times { |i| post_graphql(set_mutation, variables: { provider: "paypal", clientId: "cid_#{i}" }) }
    ActsAsTenant.with_tenant(shop) do
      expect(ShopPaymentProvider.count).to eq(1)
      expect(ShopPaymentProvider.sole.client_id).to eq("cid_1")
    end
  end

  it "P3 🔴 write-only：省略 apiSecret ⇒ 既有祕密保持不變；空字串 ⇒ 清空" do
    post_graphql(set_mutation, variables: { provider: "airwallex", apiSecret: "sk_keep_me" })
    post_graphql(set_mutation, variables: { provider: "airwallex", clientId: "cid_2" }) # 省略祕密
    ActsAsTenant.with_tenant(shop) do
      expect(ShopPaymentProvider.sole.api_secret).to eq("sk_keep_me")
    end

    post_graphql(set_mutation, variables: { provider: "airwallex", apiSecret: "" })    # 清空協定
    ActsAsTenant.with_tenant(shop) do
      expect(ShopPaymentProvider.sole.api_secret).to be_nil
      expect(ShopPaymentProvider.sole.api_secret_fingerprint).to be_nil
    end
  end

  it "P4 provider 域外 ⇒ userErrors PROVIDER_UNKNOWN（HTTP 200，鐵律 4 ①）" do
    post_graphql(set_mutation, variables: { provider: "stripe" })
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.dig("data", "shopPaymentProviderSet")
    expect(payload["shopPaymentProvider"]).to be_nil
    expect(payload["userErrors"]).to contain_exactly(
      a_hash_including("field" => [ "provider" ], "code" => "PROVIDER_UNKNOWN")
    )
  end

  it "P5 🔴 ShopPaymentProvider type 上不存在任何祕密欄（introspection；37 §6.3）" do
    post_graphql(<<~GRAPHQL)
      query { __type(name: "ShopPaymentProvider") { fields { name } } }
    GRAPHQL
    names = response.parsed_body.dig("data", "__type", "fields").map { |f| f["name"] }
    expect(names).to include("apiSecretFingerprint", "webhookSecretFingerprint")
    expect(names).not_to include("apiSecret", "webhookSecret")
  end

  it "P6 environment 域外 ⇒ userErrors INVALID（model 驗證上浮）" do
    post_graphql(set_mutation, variables: { provider: "airwallex", environment: "demo" })
    payload = response.parsed_body.dig("data", "shopPaymentProviderSet")
    expect(payload["userErrors"]).to contain_exactly(
      a_hash_including("field" => [ "environment" ], "code" => "INVALID")
    )
  end

  it "P7 租戶隔離：另一店看不到本店的 provider 列" do
    post_graphql(set_mutation, variables: { provider: "airwallex", apiSecret: "sk_shop_a" })

    other = create(:shop, subdomain: "psp-other-shop")
    ActsAsTenant.with_tenant(other) { create(:staff_member, shop: other, owner: true, email: "o2@x.test") }
    host! "psp-other-shop.lvh.me"
    post login_path, params: { email: "o2@x.test", password: "long-password-123" }
    post_graphql(list_query)
    expect(response.parsed_body.dig("data", "shopPaymentProviders")).to eq([])
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
