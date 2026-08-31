# frozen_string_literal: true

require "rails_helper"

# G6 步 6：通知設定 GraphQL（89 §4 編輯器語義）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   G3 Liquid 語法錯誤儲存時擋（殺：拿掉 strict parse——壞模板落庫、寄信時 :lax 靜默吞）
#   G4 revert＝刪列回預設（殺：revert 改成 no-op——「還原」變裝飾）
RSpec.describe "notification settings GraphQL", type: :request do
  let(:shop) { create(:shop, subdomain: "notifg") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "notifg.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    post login_path, params: { email: owner.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def gql!(query, variables = {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  NOTIF_UPDATE_GQL = <<~GQL
    mutation($key: String!, $subject: String, $bodyLiquid: String, $revertToDefault: Boolean) {
      notificationTemplateUpdate(key: $key, subject: $subject, bodyLiquid: $bodyLiquid, revertToDefault: $revertToDefault) {
        notificationTemplate { key subject isDefault }
        userErrors { field message code }
      }
    }
  GQL

  it "query：三支模板、初始皆 isDefault=true 且 subject＝平台預設" do
    payload = gql!("query { notificationTemplates { key subject isDefault } }")
    rows = payload.dig("data", "notificationTemplates")
    expect(rows.map { |row| row["key"] })
      .to eq(%w[order_confirmation shipping_confirmation abandoned_checkout])
    expect(rows.map { |row| row["isDefault"] }).to all(be(true))
    expect(rows.first["subject"]).to eq("Order {{ name }} confirmed")
  end

  it "update：覆寫 subject ⇒ isDefault=false；省略 bodyLiquid＝內文維持預設" do
    payload = gql!(NOTIF_UPDATE_GQL, { key: "order_confirmation", subject: "你的訂單 {{ name }}" })
    view = payload.dig("data", "notificationTemplateUpdate", "notificationTemplate")
    expect(payload.dig("data", "notificationTemplateUpdate", "userErrors")).to eq([])
    expect(view["subject"]).to eq("你的訂單 {{ name }}")
    expect(view["isDefault"]).to be(false)
  end

  it "🔴 G3 Liquid 語法錯誤 ⇒ INVALID 且不落庫" do
    payload = gql!(NOTIF_UPDATE_GQL, { key: "order_confirmation",
                                       bodyLiquid: "{% if broken %}沒關 endif" })
    expect(payload.dig("data", "notificationTemplateUpdate", "userErrors", 0, "code")).to eq("INVALID")
    count = ActsAsTenant.with_tenant(shop) { NotificationTemplate.count }
    expect(count).to eq(0)
  end

  it "🔴 G4 revertToDefault ⇒ 刪列、isDefault 回 true" do
    gql!(NOTIF_UPDATE_GQL, { key: "order_confirmation", subject: "自訂" })
    payload = gql!(NOTIF_UPDATE_GQL, { key: "order_confirmation", revertToDefault: true })
    view = payload.dig("data", "notificationTemplateUpdate", "notificationTemplate")
    expect(view["isDefault"]).to be(true)
    expect(view["subject"]).to eq("Order {{ name }} confirmed")
    count = ActsAsTenant.with_tenant(shop) { NotificationTemplate.count }
    expect(count).to eq(0)
  end

  it "未知 kind ⇒ NOT_FOUND" do
    payload = gql!(NOTIF_UPDATE_GQL, { key: "carrier_pigeon", subject: "x" })
    expect(payload.dig("data", "notificationTemplateUpdate", "userErrors", 0, "code")).to eq("NOT_FOUND")
  end

  it "sender email：合法值落庫；壞格式 INVALID；空字串清空" do
    m = <<~GQL
      mutation($senderEmail: String!) {
        notificationSenderEmailUpdate(senderEmail: $senderEmail) {
          senderEmail
          userErrors { field message code }
        }
      }
    GQL
    ok = gql!(m, { senderEmail: "eshop@chilling.example" })
    expect(ok.dig("data", "notificationSenderEmailUpdate", "userErrors")).to eq([])
    expect(shop.reload.sender_email).to eq("eshop@chilling.example")

    bad = gql!(m, { senderEmail: "not-an-email" })
    expect(bad.dig("data", "notificationSenderEmailUpdate", "userErrors", 0, "code")).to eq("INVALID")
    expect(shop.reload.sender_email).to eq("eshop@chilling.example")

    cleared = gql!(m, { senderEmail: "" })
    expect(cleared.dig("data", "notificationSenderEmailUpdate", "userErrors")).to eq([])
    expect(shop.reload.sender_email).to be_nil
  end
end
