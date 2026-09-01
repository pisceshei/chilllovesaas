# frozen_string_literal: true

require "rails_helper"

# 步 20a：webhook 訂閱 CRUD（28 §15）＋SSRF 紅線（specs/18 F4）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   W2 SSRF 矩陣（殺：防護退回字串黑名單／整段消失——18 F4 頭號安全風險：
#      商家填 169.254.169.254 偷雲憑證）
#   W1b topic 白名單（殺：內部 topic 外洩訂閱面——28 §15）
RSpec.describe "Webhook subscriptions", type: :request do
  let(:shop) { create(:shop, subdomain: "wh-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "wh-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ]) # 公網（預設樁）
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def gql(query, variables = {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  def create_sub(topic: "orders/create", url: "https://hook.example.com/a")
    gql(<<~GQL, { topic:, callbackUrl: url }).dig("data", "webhookSubscriptionCreate")
      mutation($topic: String!, $callbackUrl: String!) {
        webhookSubscriptionCreate(topic: $topic, callbackUrl: $callbackUrl) {
          secret webhookSubscription { id topic callbackUrl status failureCount format }
          userErrors { field message code }
        }
      }
    GQL
  end

  it "W1 建立：白名單 topic＋公網 HTTPS 過；secret 一次性回傳（讀面無此欄）" do
    result = create_sub
    expect(result["userErrors"]).to eq([])
    expect(result["secret"]).to match(/\A[0-9a-f]{48}\z/)
    expect(result.dig("webhookSubscription", "status")).to eq("active")
    expect(result.dig("webhookSubscription", "format")).to eq("json")

    fields = gql(<<~GQL).dig("data", "__type", "fields").map { |f| f["name"] }
      query { __type(name: "WebhookSubscription") { fields { name } } }
    GQL
    expect(fields).not_to include("secret") # 一次性：讀面不露出
  end

  it "W1b 🔴 topic 白名單：內部 topic 與未知 topic 一律拒" do
    [ Events::Topics::PRODUCT_UPDATED, "einvoice/issue_requested", "nope/nope" ].each do |bad|
      result = create_sub(topic: bad)
      expect(result.dig("userErrors", 0, "code")).to eq("TOPIC_NOT_SUBSCRIBABLE"), "topic #{bad} 應被拒"
    end
    expect(ActsAsTenant.with_tenant(shop) { WebhookSubscription.count }).to eq(0)
  end

  it "W2 🔴 SSRF 矩陣：私網/loopback/雲 metadata/IPv6 ULA/字面 IP/HTTP 全拒（resolve 層）" do
    {
      "10.0.0.5" => "私網", "127.0.0.1" => "loopback",
      "169.254.169.254" => "雲 metadata", "192.168.1.9" => "私網 C", "fd00::1" => "IPv6 ULA"
    }.each do |ip, label|
      allow(Resolv).to receive(:getaddresses).with("hook.example.com").and_return([ ip ])
      result = create_sub
      expect(result.dig("userErrors", 0, "code")).to eq("URL_NOT_ALLOWED"), "#{label}（#{ip}）應被拒"
    end

    literal = create_sub(url: "https://169.254.169.254/steal") # 字面 IP 不經 DNS 也要擋
    expect(literal.dig("userErrors", 0, "code")).to eq("URL_NOT_ALLOWED")

    http = create_sub(url: "http://hook.example.com/a") # HTTPS only
    expect(http.dig("userErrors", 0, "code")).to eq("URL_NOT_ALLOWED")
    expect(ActsAsTenant.with_tenant(shop) { WebhookSubscription.count }).to eq(0)
  end

  it "W3 清單 connection＋W4 update（URL 重驗紅線；re-enable 歸零）＋W5 delete" do
    created = create_sub
    gid = created.dig("webhookSubscription", "id")

    topics = gql("query { webhookTopics }").dig("data", "webhookTopics")
    expect(topics).to eq(Events::Topics::EXTERNAL) # UI select 資料源＝白名單同源

    listing = gql("query { webhookSubscriptions(first: 10) { nodes { id topic } } }")
    expect(listing.dig("data", "webhookSubscriptions", "nodes").map { |n| n["topic"] }).to eq([ "orders/create" ])

    # W4a：改 URL 到私網 ⇒ 拒且不落
    allow(Resolv).to receive(:getaddresses).with("evil.example.com").and_return([ "10.1.1.1" ])
    bad = gql(<<~GQL, { id: gid, callbackUrl: "https://evil.example.com/b" }).dig("data", "webhookSubscriptionUpdate")
      mutation($id: ID!, $callbackUrl: String) {
        webhookSubscriptionUpdate(id: $id, callbackUrl: $callbackUrl) {
          webhookSubscription { callbackUrl } userErrors { code }
        }
      }
    GQL
    expect(bad.dig("userErrors", 0, "code")).to eq("URL_NOT_ALLOWED")
    row = ActsAsTenant.with_tenant(shop) { WebhookSubscription.first }
    expect(row.url).to eq("https://hook.example.com/a")

    # W4b：disabled → active 歸零 failure_count
    ActsAsTenant.with_tenant(shop) { row.update!(status: "disabled", failure_count: 9) }
    good = gql(<<~GQL, { id: gid, status: "active" }).dig("data", "webhookSubscriptionUpdate")
      mutation($id: ID!, $status: String) {
        webhookSubscriptionUpdate(id: $id, status: $status) {
          webhookSubscription { status failureCount } userErrors { code }
        }
      }
    GQL
    expect(good.dig("webhookSubscription", "status")).to eq("active")
    expect(good.dig("webhookSubscription", "failureCount")).to eq(0)

    deleted = gql(<<~GQL, { id: gid }).dig("data", "webhookSubscriptionDelete")
      mutation($id: ID!) { webhookSubscriptionDelete(id: $id) { deletedId userErrors { code } } }
    GQL
    expect(deleted["deletedId"]).to eq(gid)
    expect(ActsAsTenant.with_tenant(shop) { WebhookSubscription.count }).to eq(0)
  end
end
