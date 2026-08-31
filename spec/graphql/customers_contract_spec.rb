# frozen_string_literal: true

require "rails_helper"

# G6-7 customers query 契約（28 §7 最小集＋§0.3 分頁/GID）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   G1 租戶隔離（殺：跨店顧客洩漏／customer(id) 跨店回資料）
#   G2 MoneyV2 序列化（殺：amount 裸出 cents 整數或 Float）
#   G3 搜尋（殺：LIKE 未跳脫——`0%` 萬用匹配；搜尋恆回全集）
#   G4 預設序（殺：不是 updated_at desc）
#   G5 未認證（殺：回資料而不是 ACCESS_DENIED）
RSpec.describe "Admin GraphQL customers contract", type: :request do
  let(:shop) { create(:shop, subdomain: "cust-gql") }
  let(:other_shop) { create(:shop, subdomain: "cust-other") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "cust-gql.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def create_customer(owner_shop, **attributes)
    ActsAsTenant.with_tenant(owner_shop) do
      Customer.create!(shop_id: owner_shop.id, currency: "HKD", **attributes)
    end
  end

  it "G5 未認證 ⇒ HTTP 200 ACCESS_DENIED（鐵律 4 第②層形）" do
    post admin_graphql_path, params: { query: "{ customers(first: 1) { nodes { id } } }" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  it "G1+G2+G4 列表：GID／MoneyV2 字串金額／預設序 updated_at desc／跨店不洩漏" do
    # 🔴 G4 殺手格前置：updated_at 序必須與 created_at 序**反向**——old_one 先建
    # （created_at 較舊）但其後被 touch（updated_at 較新）。若兩序同向，
    # 「掉回 created_at 預設鍵」的突變殺不動斷言（本輪實紅過的教訓）。
    old_one = create_customer(shop, email: "old@example.com", total_spent_cents: 148_000,
                                    orders_count: 2, created_at: 3.hours.ago, updated_at: 3.hours.ago)
    new_one = create_customer(shop, email: "new@example.com", first_name: "新", last_name: "客",
                                    created_at: 2.hours.ago, updated_at: 2.hours.ago)
    ActsAsTenant.with_tenant(shop) { old_one.update!(note: "touched") } # updated_at 推到最新
    create_customer(other_shop, email: "leak@example.com")
    login!

    post_graphql(<<~GQL)
      { customers(first: 10) {
          nodes { id legacyResourceId email displayName ordersCount
                  amountSpent { amount currencyCode } emailMarketingConsent }
          pageInfo { hasNextPage endCursor } } }
    GQL
    data = response.parsed_body.dig("data", "customers")
    emails = data.fetch("nodes").map { |n| n.fetch("email") }
    # updated_at desc：old_one 剛被 touch ⇒ 排最前（created_at desc 會反過來——G4 殺手格）
    expect(emails).to eq([ "old@example.com", "new@example.com" ])
    expect(emails).not_to include("leak@example.com")

    node = data.fetch("nodes").first # = old_one
    expect(node.fetch("id")).to eq("gid://chilllove/Customer/#{old_one.id}")
    expect(node.dig("amountSpent", "amount")).to eq("1480.00") # 🔴 字串、兩位小數、非裸 cents
    expect(node.dig("amountSpent", "currencyCode")).to eq("HKD")
    expect(node.fetch("displayName")).to eq("old@example.com") # 姓名缺項回落 email
    expect(data.fetch("nodes").last.fetch("displayName")).to eq("新 客")

    # customer(id) 單抓＋跨店 null
    post_graphql(%({ customer(id: "gid://chilllove/Customer/#{new_one.id}") { email } }))
    expect(response.parsed_body.dig("data", "customer", "email")).to eq("new@example.com")
    leak = ActsAsTenant.with_tenant(other_shop) { Customer.find_by!(shop_id: other_shop.id, email: "leak@example.com") }
    post_graphql(%({ customer(id: "gid://chilllove/Customer/#{leak.id}") { email } }))
    expect(response.parsed_body.dig("data", "customer")).to be_nil
  end

  it "G3 搜尋：姓名/email/電話 CONTAINS、多詞 AND；`%` 經跳脫不得萬用匹配" do
    create_customer(shop, email: "chan.tai@example.com", first_name: "大文", last_name: "陳")
    create_customer(shop, email: "wong@example.com", first_name: "小明", phone: "+85291234567")
    # 🔴 G3 殺手格前置：必須有「含 0 但不含字面 0%」的列——未跳脫的 `%0%%`＝
    # 含 0 即中，會撈到它；跳脫後找字面「0%」＝空。沒有這列，殺手殺不動（本輪實紅過）。
    create_customer(shop, email: "zero0@example.com")
    login!

    post_graphql(%({ customers(first: 10, query: "chan.tai") { nodes { email } } }))
    expect(response.parsed_body.dig("data", "customers", "nodes").map { |n| n["email"] })
      .to eq([ "chan.tai@example.com" ])

    post_graphql(%({ customers(first: 10, query: "9123") { nodes { email } } }))
    expect(response.parsed_body.dig("data", "customers", "nodes").map { |n| n["email"] })
      .to eq([ "wong@example.com" ])

    post_graphql(%({ customers(first: 10, query: "0%") { nodes { email } } }))
    expect(response.parsed_body.dig("data", "customers", "nodes")).to eq([]) # 跳脫後無命中

    post_graphql(%({ customers(first: 10, query: "大文 陳") { nodes { email } } }))
    expect(response.parsed_body.dig("data", "customers", "nodes").map { |n| n["email"] })
      .to eq([ "chan.tai@example.com" ])
  end

  it "分頁契約：first 上限 250（BAD_USER_INPUT）；cursor 翻頁銜接不重不漏" do
    5.times { |i| create_customer(shop, email: "page#{i}@example.com", updated_at: i.minutes.ago) }
    login!

    post_graphql("{ customers(first: 251) { nodes { id } } }")
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

    post_graphql("{ customers(first: 3) { nodes { email } pageInfo { hasNextPage endCursor } } }")
    page1 = response.parsed_body.dig("data", "customers")
    expect(page1.dig("pageInfo", "hasNextPage")).to be(true)

    post_graphql(
      "query($c: String!) { customers(first: 3, after: $c) { nodes { email } pageInfo { hasNextPage } } }",
      variables: { c: page1.dig("pageInfo", "endCursor") }
    )
    page2 = response.parsed_body.dig("data", "customers")
    all_emails = page1.fetch("nodes").map { |n| n["email"] } + page2.fetch("nodes").map { |n| n["email"] }
    expect(all_emails).to match_array((0..4).map { |i| "page#{i}@example.com" })
    expect(page2.dig("pageInfo", "hasNextPage")).to be(false)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path,
      params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
