# frozen_string_literal: true

require "rails_helper"

# G6 步 9b：折扣 CRUD（官方 Basic 四支同名＋lifecycle 三支）。
#
# 🔴 假綠殺手：
#   C2 code 撞名 ⇒ TAKEN（殺：唯一索引錯誤沒翻譯——500）
#   C4 有 applications 不可刪（殺：照刪——17-F4.4 報表斷根）
#   C5 shipping 類 combines_shipping ⇒ INVALID（17-F1.4 官方旗標形）
RSpec.describe "discount mutations", type: :request do
  let(:shop) { create(:shop, subdomain: "dmut") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "dmut.lvh.me"
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

  DMUT_CODE_CREATE_GQL = <<~GQL
    mutation($input: DiscountBasicInput!) {
      discountCodeBasicCreate(input: $input) {
        discount { id title code method discountClass basisPoints status }
        userErrors { field message code }
      }
    }
  GQL

  it "C1 建碼：正規化 upcase、預設 active、basisPoints 落庫" do
    payload = gql!(DMUT_CODE_CREATE_GQL, { input: {
      title: "夏季九折", code: " summer10 ", discountClass: "order",
      valueType: "percentage", basisPoints: 1000 } })
    discount = payload.dig("data", "discountCodeBasicCreate", "discount")
    expect(payload.dig("data", "discountCodeBasicCreate", "userErrors")).to eq([])
    expect(discount["code"]).to eq("SUMMER10")
    expect(discount["status"]).to eq("active")
    expect(discount["basisPoints"]).to eq(1000)
  end

  it "🔴 C2 同 code 再建 ⇒ TAKEN" do
    gql!(DMUT_CODE_CREATE_GQL, { input: { title: "一", code: "DUP", basisPoints: 500 } })
    payload = gql!(DMUT_CODE_CREATE_GQL, { input: { title: "二", code: "dup", basisPoints: 500 } })
    expect(payload.dig("data", "discountCodeBasicCreate", "userErrors", 0, "code")).to eq("TAKEN")
  end

  it "C3 automatic 建立＋update 改 min 條件；lifecycle activate/deactivate" do
    created = gql!(<<~GQL, { input: { title: "自動折", discountClass: "order", basisPoints: 500 } })
      mutation($input: DiscountBasicInput!) {
        discountAutomaticBasicCreate(input: $input) {
          discount { id status }
          userErrors { field message code }
        }
      }
    GQL
    gid = created.dig("data", "discountAutomaticBasicCreate", "discount", "id")

    updated = gql!(<<~GQL, { id: gid, input: { minSubtotalCents: 50_000 } })
      mutation($id: ID!, $input: DiscountBasicInput!) {
        discountAutomaticBasicUpdate(id: $id, input: $input) {
          discount { conditions }
          userErrors { field message code }
        }
      }
    GQL
    expect(updated.dig("data", "discountAutomaticBasicUpdate", "discount", "conditions", "min_subtotal_cents")).to eq(50_000)

    off = gql!(<<~GQL, { id: gid })
      mutation($id: ID!) {
        discountDeactivate(id: $id) { discount { status } userErrors { code } }
      }
    GQL
    expect(off.dig("data", "discountDeactivate", "discount", "status")).to eq("archived")

    on = gql!(<<~GQL, { id: gid })
      mutation($id: ID!) {
        discountActivate(id: $id) { discount { status } userErrors { code } }
      }
    GQL
    expect(on.dig("data", "discountActivate", "discount", "status")).to eq("active")
  end

  it "🔴 C4 有 applications 的折扣 ⇒ 不可刪（INVALID_STATE）；乾淨者可刪" do
    created = gql!(DMUT_CODE_CREATE_GQL, { input: { title: "用過", code: "USED", basisPoints: 500 } })
    gid = created.dig("data", "discountCodeBasicCreate", "discount", "id")
    numeric = gid[%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.with_tenant(shop) do
      order = Order.create!(
        shop_id: shop.id, name: "#D1", order_number: 7001, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 1000, total_cents: 1000,
        presentment_total_cents: 1000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
      DiscountApplication.create!(shop_id: shop.id, order_id: order.id, discount_id: numeric,
                                  amount_cents: 100, allocation_method: "across", currency: "HKD")
    end

    del = <<~GQL
      mutation($id: ID!) {
        discountDelete(id: $id) { deletedDiscountId userErrors { field message code } }
      }
    GQL
    blocked = gql!(del, { id: gid })
    expect(blocked.dig("data", "discountDelete", "userErrors", 0, "code")).to eq("INVALID_STATE")

    clean = gql!(DMUT_CODE_CREATE_GQL, { input: { title: "乾淨", code: "CLEAN", basisPoints: 500 } })
    clean_gid = clean.dig("data", "discountCodeBasicCreate", "discount", "id")
    ok = gql!(del, { id: clean_gid })
    expect(ok.dig("data", "discountDelete", "deletedDiscountId")).to eq(clean_gid)
  end

  it "🔴 C5 shipping 類開 combinesShipping ⇒ INVALID（官方無此旗標）" do
    payload = gql!(DMUT_CODE_CREATE_GQL, { input: {
      title: "免運", code: "FREESHIP", discountClass: "shipping",
      basisPoints: 10_000, combinesShipping: true } })
    expect(payload.dig("data", "discountCodeBasicCreate", "userErrors", 0, "code")).to eq("INVALID")
  end

  it "discounts query：keyset 列表帶狀態推導" do
    gql!(DMUT_CODE_CREATE_GQL, { input: { title: "過期", code: "OLD", basisPoints: 500,
                                          endsAt: 1.day.ago.iso8601 } })
    payload = gql!("query { discounts(first: 10) { nodes { code status } } }")
    node = payload.dig("data", "discounts", "nodes").find { |row| row["code"] == "OLD" }
    expect(node["status"]).to eq("expired")
  end
end
