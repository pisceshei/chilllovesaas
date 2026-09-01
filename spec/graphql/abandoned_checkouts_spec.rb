# frozen_string_literal: true

require "rails_helper"

# G6 步 7：棄單 GraphQL（89 §8 列表七欄的資料面＋手動寄挽回信）。
#
# 🔴 假綠殺手：
#   Q2 未達判定不可寄（殺：拿掉 abandoned_at 前置——任何 open 結帳都能寄）
#   Q3 已成單不可寄（殺：拿掉成單檢查——已購買顧客收到「你沒買完」）
#   Q4 寄出鏈端到端＋sent_at 回填（殺：不回填——Email status 恆 Not sent、
#      admin 重複狂寄；殺：RecoveryUrl 不帶 token——信裡連結廢的）
RSpec.describe "abandoned checkouts GraphQL", type: :request do
  include ActiveJob::TestHelper

  let(:shop) { create(:shop, subdomain: "abgql") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  def build_checkout(email: "x@example.com", abandoned: true, total: 111_900)
    ActsAsTenant.with_tenant(shop) do
      Checkout.create!(shop_id: shop.id, token: SecureRandom.hex(24), status: "open",
                       currency: "HKD", email:, abandoned_at: abandoned ? Time.current : nil,
                       subtotal_cents: total, total_cents: total,
                       billing_address: { "first_name" => "Probe", "last_name" => "Buyer",
                                          "country" => "United States" },
                       line_items_snapshot: [ { "title" => "POLA 乳液", "quantity" => 1,
                                                "unit_price_cents" => total } ])
    end
  end

  before do
    host! "abgql.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    post login_path, params: { email: owner.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  after { clear_enqueued_jobs }

  def gql!(query, variables = {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  ABND_LIST_GQL = <<~GQL
    query {
      abandonedCheckouts(first: 10) {
        nodes {
          id email customerName region abandonedAt
          totalPriceSet { shopMoney { amount currencyCode } }
          lineItemsCount recoveryEmailSentAt recovered abandonedCheckoutUrl
        }
        pageInfo { hasNextPage }
      }
    }
  GQL

  ABND_SEND_GQL = <<~GQL
    mutation($id: ID!) {
      abandonedCheckoutSendRecovery(id: $id) {
        abandonedCheckout { id }
        userErrors { field message code }
      }
    }
  GQL

  it "Q1 只列已標棄單；欄位形＝89 §8（姓名/地區/金額/計數/兩狀態/挽回連結）" do
    abandoned = build_checkout
    build_checkout(abandoned: false) # 不該出現

    payload = gql!(ABND_LIST_GQL)
    nodes = payload.dig("data", "abandonedCheckouts", "nodes")
    expect(nodes.size).to eq(1)
    node = nodes.first
    expect(node["customerName"]).to eq("Probe Buyer")
    expect(node["region"]).to eq("United States")
    expect(node["totalPriceSet"]).to eq({ "shopMoney" => { "amount" => "1119.00", "currencyCode" => "HKD" } })
    expect(node["lineItemsCount"]).to eq(1)
    expect(node["recoveryEmailSentAt"]).to be_nil
    expect(node["recovered"]).to be(false)
    expect(node["abandonedCheckoutUrl"]).to include("/checkouts/recover/#{abandoned.recovery_token}")
  end

  it "🔴 Q2 未達棄單判定 ⇒ INVALID_STATE 且不入列 job" do
    fresh = build_checkout(abandoned: false)
    payload = gql!(ABND_SEND_GQL, { id: "gid://chilllove/AbandonedCheckout/#{fresh.id}" })
    expect(payload.dig("data", "abandonedCheckoutSendRecovery", "userErrors", 0, "code"))
      .to eq("INVALID_STATE")
    expect(Notifications::DeliverJob).not_to have_been_enqueued
  end

  it "🔴 Q3 已成單 ⇒ INVALID_STATE（不對已購買顧客寄挽回信）" do
    checkout = build_checkout
    ActsAsTenant.with_tenant(shop) do
      Order.create!(
        shop_id: shop.id, checkout_id: checkout.id, name: "#9701", order_number: 9701,
        currency: "HKD", presentment_currency: "HKD", subtotal_cents: 111_900,
        total_cents: 111_900, presentment_total_cents: 111_900, financial_status: "pending",
        fulfillment_status: "unfulfilled", status: "open", email: checkout.email,
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
    end

    payload = gql!(ABND_SEND_GQL, { id: "gid://chilllove/AbandonedCheckout/#{checkout.id}" })
    expect(payload.dig("data", "abandonedCheckoutSendRecovery", "userErrors", 0, "code"))
      .to eq("INVALID_STATE")
  end

  it "🔴 Q4 合法寄送：job 入列 → 執行 ⇒ 信含挽回連結、sent_at 回填" do
    checkout = build_checkout
    payload = gql!(ABND_SEND_GQL, { id: "gid://chilllove/AbandonedCheckout/#{checkout.id}" })
    expect(payload.dig("data", "abandonedCheckoutSendRecovery", "userErrors")).to eq([])
    expect(Notifications::DeliverJob)
      .to have_been_enqueued.with(shop_id: shop.id, kind: "abandoned_checkout",
                                  checkout_id: checkout.id)

    expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.size }.by(1)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "x@example.com" ])
    expect(mail.subject).to eq("Complete your Purchase")
    body = mail.html_part&.body&.to_s || mail.body.to_s
    expect(body).to include("/checkouts/recover/#{checkout.recovery_token}")
    expect(ActsAsTenant.without_tenant { checkout.reload.recovery_email_sent_at }).to be_present
  end

  it "不存在的 id ⇒ NOT_FOUND" do
    payload = gql!(ABND_SEND_GQL, { id: "gid://chilllove/AbandonedCheckout/999999" })
    expect(payload.dig("data", "abandonedCheckoutSendRecovery", "userErrors", 0, "code"))
      .to eq("NOT_FOUND")
  end
end
