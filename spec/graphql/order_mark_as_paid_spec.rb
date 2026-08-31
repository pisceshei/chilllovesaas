# frozen_string_literal: true

require "rails_helper"

# G6-6 步 4：orderMarkAsPaid（16 §F4.3 manual 入帳入口）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   M1 happy path（殺：交易不翻 success／financial_status 不推進／outbox 不發）
#   M2 已入帳 INVALID_STATE（殺：重複標記二次入帳）
#   M3 已取消 INVALID_STATE（殺：取消單被標記）
#   M4 idempotencyKey 缺 ⇒ top-level IDEMPOTENCY_KEY_REQUIRED（殺：契約拔除）
#   M5 跨店 NOT_FOUND（殺：跨店標記）
RSpec.describe "orderMarkAsPaid", type: :request do
  let(:shop) { create(:shop, subdomain: "omap") }
  let(:other_shop) { create(:shop, subdomain: "omap-other") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "omap.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def build_order(owner_shop, number:, financial: "pending", status: "open")
    ActsAsTenant.with_tenant(owner_shop) do
      order = Order.create!(
        shop_id: owner_shop.id, name: "##{number}", order_number: number,
        currency: "HKD", presentment_currency: "HKD",
        subtotal_cents: 10_000, total_cents: 10_000, presentment_total_cents: 10_000,
        financial_status: financial, fulfillment_status: "unfulfilled", status:,
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        canceled_at: status == "cancelled" ? Time.current : nil
      )
      order.order_transactions.create!(shop_id: owner_shop.id, kind: "sale", status: "pending",
                                       gateway: "manual_bank_deposit", amount_cents: 10_000,
                                       currency: "HKD", idempotency_key: "sale-#{number}")
      order
    end
  end

  def mutate(order, key: "key-1")
    variables = { id: "gid://chilllove/Order/#{order.id}" }
    variables[:idempotencyKey] = key if key
    post admin_graphql_path,
      params: {
        query: <<~GQL, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
          mutation($id: ID!, $idempotencyKey: String) {
            orderMarkAsPaid(id: $id, idempotencyKey: $idempotencyKey) {
              order { displayFinancialStatus }
              userErrors { field message code }
            }
          }
        GQL
    response.parsed_body
  end

  it "M1 happy path：pending sale 翻 success、financial paid、event＋orders/paid outbox" do
    order = build_order(shop, number: 7001)
    payload = mutate(order)
    expect(payload.dig("data", "orderMarkAsPaid", "userErrors")).to eq([])
    expect(payload.dig("data", "orderMarkAsPaid", "order", "displayFinancialStatus")).to eq("PAID")

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.financial_status).to eq("paid")
      expect(order.order_transactions.sole.status).to eq("success")
      expect(Event.where(order_id: order.id, kind: "order.paid").count).to eq(1)
      expect(EventOutbox.where(aggregate_id: order.id, topic: Events::Topics::ORDERS_PAID).count).to eq(1)
    end
  end

  it "M2 已入帳 ⇒ INVALID_STATE 且不二次入帳" do
    order = build_order(shop, number: 7002)
    mutate(order)
    payload = mutate(order, key: "key-2")
    expect(payload.dig("data", "orderMarkAsPaid", "userErrors", 0, "code")).to eq("INVALID_STATE")
    ActsAsTenant.with_tenant(shop) do
      expect(EventOutbox.where(aggregate_id: order.id, topic: Events::Topics::ORDERS_PAID).count).to eq(1)
    end
  end

  it "M3 已取消 ⇒ INVALID_STATE" do
    order = build_order(shop, number: 7003, status: "cancelled")
    payload = mutate(order)
    expect(payload.dig("data", "orderMarkAsPaid", "userErrors", 0, "code")).to eq("INVALID_STATE")
    ActsAsTenant.with_tenant(shop) { expect(order.reload.financial_status).to eq("pending") }
  end

  it "M4 idempotencyKey 缺 ⇒ top-level IDEMPOTENCY_KEY_REQUIRED（limits 登記生效）" do
    order = build_order(shop, number: 7004)
    payload = mutate(order, key: nil)
    expect(payload.dig("errors", 0, "extensions", "code")).to eq("IDEMPOTENCY_KEY_REQUIRED")
    ActsAsTenant.with_tenant(shop) { expect(order.reload.financial_status).to eq("pending") }
  end

  it "M5 跨店 ⇒ NOT_FOUND（不洩他店訂單存在性）" do
    leak = build_order(other_shop, number: 7005)
    payload = mutate(leak)
    expect(payload.dig("data", "orderMarkAsPaid", "userErrors", 0, "code")).to eq("NOT_FOUND")
    ActsAsTenant.with_tenant(other_shop) { expect(leak.reload.financial_status).to eq("pending") }
  end

  it "itemCount：行項數量合計（列表 Items 欄——88 §2）" do
    order = build_order(shop, number: 7006)
    ActsAsTenant.with_tenant(shop) do
      order.line_items.create!(shop_id: shop.id, title: "A", quantity: 2,
                               unit_price_cents: 100, total_cents: 200, currency: "HKD")
      order.line_items.create!(shop_id: shop.id, title: "B", quantity: 3,
                               unit_price_cents: 100, total_cents: 300, currency: "HKD")
    end
    post admin_graphql_path,
      params: { query: %({ order(id: "gid://chilllove/Order/#{order.id}") { itemCount } }) }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.parsed_body.dig("data", "order", "itemCount")).to eq(5)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end
end
