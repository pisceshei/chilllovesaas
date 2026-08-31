# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：超額退款的權限閘（limits.refund.over_refund_requires_permission）。
#
# 🔴 拿「什麼權限都沒有」的員工測不出這道閘（variant_subpage 同款教訓——上游
#   OrderPolicy.create? 就擋掉了）⇒ 角色組成＝**有** orders.view/orders.edit、
#   **沒有** orders.over_refund，恰好只缺被測的那一格。
RSpec.describe "refundCreate over_refund permission", type: :request do
  let(:shop) { create(:shop, subdomain: "refperm") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  let!(:editor) do
    ActsAsTenant.with_tenant(shop) do
      staff_member = create(:staff_member, shop:, owner: false)
      role = Role.create!(name: "orders-editor-#{SecureRandom.hex(4)}")
      RolePermission.create!(role:, permission_key: "orders.view")
      RolePermission.create!(role:, permission_key: "orders.edit")
      UserStoreAssignment.find_or_initialize_by(staff_member_id: staff_member.id, shop_id: shop.id)
                         .update!(role_id: role.id)
      staff_member
    end
  end

  let!(:order) do
    ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#9301", order_number: 9301, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 2000, total_cents: 2000,
        presentment_total_cents: 2000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 1000, refunded_total_cents: 0
      )
      LineItem.create!(shop_id: shop.id, order_id: o.id, title: "品",
                       quantity: 2, fulfillable_quantity: 2,
                       unit_price_cents: 1000, total_cents: 2000, currency: "HKD")
      o
    end
  end

  before do
    host! "refperm.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def login_as!(staff)
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  # 🔴 前綴防頂層常數撞名（與 product_set_spec 的 MUTATION 撞——同 fulfillment 檔註記）。
  REFUND_PERM_MUTATION_GQL = <<~GQL
    mutation($input: RefundInput!, $idempotencyKey: String!) {
      refundCreate(input: $input, idempotencyKey: $idempotencyKey) {
        refund { id }
        userErrors { field message code }
      }
    }
  GQL

  def over_refund!(key:)
    line = ActsAsTenant.without_tenant { order.line_items.first! }
    post admin_graphql_path, params: {
      query: REFUND_PERM_MUTATION_GQL,
      variables: { input: { orderId: "gid://chilllove/Order/#{order.id}",
                            refundLineItems: [ { lineItemId: "gid://chilllove/LineItem/#{line.id}",
                                                 quantity: 2 } ],
                            allowOverRefunding: true },
                   idempotencyKey: key }
    }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  it "🔴 有 orders.edit 但無 orders.over_refund ⇒ MISSING_PERMISSION 且不寫任何列" do
    login_as!(editor)
    payload = over_refund!(key: "perm-1")

    expect(payload.dig("data", "refundCreate", "userErrors", 0, "code")).to eq("MISSING_PERMISSION")
    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(0)
      expect(Refund.where(order_id: order.id).count).to eq(0)
    end
  end

  it "owner（隱含全權限）可超額（對照組：證明擋的是權限不是超額本身）" do
    login_as!(owner)
    payload = over_refund!(key: "perm-2")

    expect(payload.dig("data", "refundCreate", "userErrors")).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.refunded_total_cents).to eq(2000)
    end
  end
end
