# frozen_string_literal: true

require "rails_helper"

# G6-6a orders query 契約（28 §4 最小集＋88 號實測＋90-blueprint/04/05 正典）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   O-G1 租戶隔離（殺：跨店訂單洩漏／order(id) 跨店回資料）
#   O-G2 MoneyBag 序列化（殺：金額裸 cents／Float）
#   O-G3 預設序 processed_at desc（殺：掉回 created_at——88 §1 實測鍵）
#   O-G4 搜尋（殺：# 前綴不剝／非法 enum 值回全集不回空集）
#   O-G5 未認證（殺：回資料不回 ACCESS_DENIED）
#   O-G6 billing same_as_shipping 回落（殺：same 模式回 null 或回 mode 鍵）
RSpec.describe "Admin GraphQL orders contract", type: :request do
  let(:shop) { create(:shop, subdomain: "ord-gql") }
  let(:other_shop) { create(:shop, subdomain: "ord-other") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "ord-gql.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def create_order(owner_shop, number:, processed_at: Time.current, **attributes)
    ActsAsTenant.with_tenant(owner_shop) do
      order = Order.create!(
        shop_id: owner_shop.id, name: "##{number}", order_number: number,
        currency: "HKD", presentment_currency: "HKD",
        subtotal_cents: 14_800, shipping_cents: 2_000, total_cents: 16_800,
        presentment_total_cents: 16_800,
        financial_status: "pending", fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: { "first_name" => "測", "city" => "Central", "zone" => "HK-i",
                            "country_code" => "HK" },
        billing_address: {}, processed_at:, **attributes
      )
      order.line_items.create!(shop_id: owner_shop.id, title: "測品", quantity: 2,
                               unit_price_cents: 7_400, total_cents: 14_800, currency: "HKD")
      order.order_transactions.create!(shop_id: owner_shop.id, kind: "sale", status: "pending",
                                       gateway: "manual_bank_deposit", amount_cents: 16_800,
                                       currency: "HKD", idempotency_key: "sale-#{number}")
      order
    end
  end

  it "O-G5 未認證 ⇒ HTTP 200 ACCESS_DENIED" do
    post admin_graphql_path, params: { query: "{ orders(first: 1) { nodes { id } } }" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("ACCESS_DENIED")
  end

  it "O-G1+O-G2+O-G3 列表：GID／MoneyBag 字串金額／enum 大寫值／" \
     "預設序 processed_at desc／跨店不洩漏／行項與交易齊出" do
    older = create_order(shop, number: 2001, processed_at: 2.hours.ago, created_at: 1.minute.ago)
    newer = create_order(shop, number: 2002, processed_at: 1.hour.ago, created_at: 2.hours.ago)
    create_order(other_shop, number: 9001)
    login!

    post_graphql(<<~GQL)
      { orders(first: 10) {
          nodes { id name orderNumber status displayFinancialStatus displayFulfillmentStatus
                  totalPriceSet { shopMoney { amount currencyCode } presentmentMoney { amount } }
                  lineItems { title quantity unitPriceSet { shopMoney { amount } } }
                  transactions { kind status gateway amountSet { shopMoney { amount } } }
                  shippingAddress { city province countryCode }
                  customer { id } }
          pageInfo { hasNextPage endCursor } } }
    GQL
    data = response.parsed_body.dig("data", "orders")
    names = data.fetch("nodes").map { |n| n.fetch("name") }
    # processed_at desc：newer 在前（created_at 序相反——O-G3 殺手前置）
    expect(names).to eq([ "#2002", "#2001" ])
    expect(names).not_to include("#9001")

    node = data.fetch("nodes").first
    expect(node.fetch("id")).to eq("gid://chilllove/Order/#{newer.id}")
    expect(node.fetch("displayFinancialStatus")).to eq("PENDING")
    expect(node.fetch("displayFulfillmentStatus")).to eq("UNFULFILLED")
    expect(node.dig("totalPriceSet", "shopMoney", "amount")).to eq("168.00") # 🔴 字串非裸 cents
    expect(node.dig("totalPriceSet", "shopMoney", "currencyCode")).to eq("HKD")
    expect(node.dig("totalPriceSet", "presentmentMoney", "amount")).to eq("168.00")
    expect(node.fetch("lineItems").sole).to include("title" => "測品", "quantity" => 2)
    expect(node.fetch("lineItems").sole.dig("unitPriceSet", "shopMoney", "amount")).to eq("74.00")
    expect(node.fetch("transactions").sole)
      .to include("kind" => "SALE", "status" => "PENDING", "gateway" => "manual_bank_deposit")
    expect(node.dig("shippingAddress", "city")).to eq("Central")
    expect(node.dig("shippingAddress", "province")).to eq("HK-i") # zone→province 對映
    expect(node.fetch("customer")).to be_nil # guest 單

    # order(id) 單抓＋跨店 null
    post_graphql(%({ order(id: "gid://chilllove/Order/#{older.id}") { name } }))
    expect(response.parsed_body.dig("data", "order", "name")).to eq("#2001")
    leak = ActsAsTenant.with_tenant(other_shop) { Order.find_by!(shop_id: other_shop.id, order_number: 9001) }
    post_graphql(%({ order(id: "gid://chilllove/Order/#{leak.id}") { name } }))
    expect(response.parsed_body.dig("data", "order")).to be_nil
  end

  it "O-G4 搜尋：#1001 剝前綴命中單號；status:/financial_status: 白名單；非法值空集" do
    create_order(shop, number: 3001, status: "open")
    ActsAsTenant.with_tenant(shop) do
      Order.find_by!(order_number: 3001).update!(email: "buyer@example.com")
    end
    create_order(shop, number: 3002, status: "cancelled", canceled_at: Time.current)
    login!

    post_graphql(%({ orders(first: 10, query: "#3001") { nodes { name } } }))
    expect(response.parsed_body.dig("data", "orders", "nodes").map { |n| n["name"] }).to eq([ "#3001" ])

    post_graphql(%({ orders(first: 10, query: "status:cancelled") { nodes { name } } }))
    expect(response.parsed_body.dig("data", "orders", "nodes").map { |n| n["name"] }).to eq([ "#3002" ])

    post_graphql(%({ orders(first: 10, query: "financial_status:bogus") { nodes { name } } }))
    expect(response.parsed_body.dig("data", "orders", "nodes")).to eq([]) # 非法值＝空集

    post_graphql(%({ orders(first: 10, query: "buyer@example") { nodes { name } } }))
    expect(response.parsed_body.dig("data", "orders", "nodes").map { |n| n["name"] }).to eq([ "#3001" ])
  end

  it "O-G6 帳單地址：same_as_shipping ⇒ 回落出貨快照；different ⇒ 剝 billing_ 前綴且不洩 mode" do
    same = create_order(shop, number: 4001,
                        billing_address: { "mode" => "same_as_shipping" })
    diff = create_order(shop, number: 4002,
                        billing_address: { "mode" => "different", "billing_city" => "Kowloon",
                                           "billing_country_code" => "HK" })
    login!

    post_graphql(%({ order(id: "gid://chilllove/Order/#{same.id}") { billingAddress { city } } }))
    expect(response.parsed_body.dig("data", "order", "billingAddress", "city")).to eq("Central")

    post_graphql(%({ order(id: "gid://chilllove/Order/#{diff.id}") { billingAddress { city countryCode } } }))
    billing = response.parsed_body.dig("data", "order", "billingAddress")
    expect(billing).to eq({ "city" => "Kowloon", "countryCode" => "HK" })
  end

  it "分頁契約：first 上限 250；cursor 翻頁銜接" do
    4.times { |i| create_order(shop, number: 5000 + i, processed_at: i.minutes.ago) }
    login!

    post_graphql("{ orders(first: 251) { nodes { id } } }")
    expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

    post_graphql("{ orders(first: 3) { nodes { name } pageInfo { hasNextPage endCursor } } }")
    page1 = response.parsed_body.dig("data", "orders")
    expect(page1.dig("pageInfo", "hasNextPage")).to be(true)
    post_graphql(
      "query($c: String!) { orders(first: 3, after: $c) { nodes { name } pageInfo { hasNextPage } } }",
      variables: { c: page1.dig("pageInfo", "endCursor") }
    )
    page2 = response.parsed_body.dig("data", "orders")
    all_names = page1.fetch("nodes").map { |n| n["name"] } + page2.fetch("nodes").map { |n| n["name"] }
    expect(all_names).to match_array((0..3).map { |i| "##{5000 + i}" })
  end

  it "customer.lastOrder：歸戶單可從顧客反查（G6-7 管線互證）" do
    customer = ActsAsTenant.with_tenant(shop) do
      Customer.create!(shop_id: shop.id, email: "buyer@example.com", currency: "HKD")
    end
    create_order(shop, number: 6001, customer_id: customer.id, processed_at: 2.hours.ago)
    create_order(shop, number: 6002, customer_id: customer.id, processed_at: 1.hour.ago)
    login!

    post_graphql(%({ customer(id: "gid://chilllove/Customer/#{customer.id}") { lastOrder { name } } }))
    expect(response.parsed_body.dig("data", "customer", "lastOrder", "name")).to eq("#6002")
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
