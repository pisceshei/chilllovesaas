# frozen_string_literal: true

require "rails_helper"

# 步 20c：products sortKey V 項收口（官方 ProductSortKeys 值域，取證 2026-09-01）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   SK2 reverse 反轉（殺：reverse 被吞＝升冪恆定）
#   SK3 未支援鍵 fail-closed（殺：靜默退回預設＝呼叫端以為已排序）
#   SK4 cursor 續頁帶排序鍵（殺：第二頁退回預設鍵＝跨頁順序斷裂）
RSpec.describe "Admin GraphQL products sortKey", type: :request do
  let(:shop) { create(:shop, subdomain: "sort-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "sort-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  def make(title, created_at: Time.current)
    ActsAsTenant.with_tenant(shop) { create(:product, shop:, title:, created_at:) }
  end

  def titles(sort_key: nil, reverse: false, first: 10, after: nil)
    post_graphql(<<~GQL, variables: { sortKey: sort_key, reverse:, first:, after: })
      query($sortKey: ProductSortKeys, $reverse: Boolean, $first: Int, $after: String) {
        products(first: $first, after: $after, sortKey: $sortKey, reverse: $reverse) {
          nodes { title }
          pageInfo { endCursor hasNextPage }
        }
      }
    GQL
    body = response.parsed_body.dig("data", "products")
    [ body&.dig("nodes")&.map { |row| row.fetch("title") }, body&.dig("pageInfo") ]
  end

  before do
    make("Cherry", created_at: 3.minutes.ago)
    make("Apple", created_at: 2.minutes.ago)
    make("Banana", created_at: 1.minute.ago)
  end

  it "SK1 TITLE 升冪為底；不帶 sortKey＝既有預設（created_at desc）零回歸" do
    expect(titles(sort_key: "TITLE").first).to eq(%w[Apple Banana Cherry])
    expect(titles.first).to eq(%w[Banana Apple Cherry]) # created_at desc 原行為
  end

  it "SK2 🔴 reverse 反轉（官方語義：sortKey 升冪為底、reverse 反轉）" do
    expect(titles(sort_key: "TITLE", reverse: true).first).to eq(%w[Cherry Banana Apple])
    expect(titles(sort_key: "CREATED_AT").first).to eq(%w[Cherry Apple Banana]) # 升冪＝舊到新
  end

  it "SK3 🔴 未支援鍵 fail-closed（不得靜默退回預設）" do
    post_graphql(<<~GQL, variables: {})
      query { products(first: 5, sortKey: INVENTORY_TOTAL) { nodes { title } } }
    GQL
    errors = response.parsed_body["errors"]
    expect(errors).to be_present
    expect(errors.first.dig("extensions", "code")).to eq("SORT_KEY_NOT_SUPPORTED")
  end

  it "SK4 🔴 cursor 續頁沿用排序鍵：TITLE first:1 三連頁＝字母序無斷裂" do
    page1, info1 = titles(sort_key: "TITLE", first: 1)
    expect(page1).to eq([ "Apple" ])
    page2, info2 = titles(sort_key: "TITLE", first: 1, after: info1.fetch("endCursor"))
    expect(page2).to eq([ "Banana" ])
    page3, = titles(sort_key: "TITLE", first: 1, after: info2.fetch("endCursor"))
    expect(page3).to eq([ "Cherry" ])
  end
end
