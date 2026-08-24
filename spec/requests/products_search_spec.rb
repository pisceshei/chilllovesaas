# frozen_string_literal: true

require "rails_helper"

# 排程第 1 包：products(query:) 伺服器端搜尋（28 §1）。
# 🔴 核心斷言形態：搜尋結果**不受分頁窗限制**——舊實作是前端對已載入的一頁做記憶體過濾，
# 第 51 筆之後的商品永遠搜不到。所以每條測試都用 first: 1 或小頁量證明過濾發生在伺服器。
RSpec.describe "Admin GraphQL products search", type: :request do
  let(:shop) { create(:shop, subdomain: "search-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "search-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def make(title, **attrs)
    ActsAsTenant.with_tenant(shop) { create(:product, shop:, title:, **attrs) }
  end

  def search(query, first: 10)
    post_graphql(
      "query($q: String, $first: Int) { products(first: $first, query: $q) { nodes { title } } }",
      variables: { q: query, first: }
    )
    response.parsed_body.dig("data", "products", "nodes").map { |row| row.fetch("title") }
  end

  it "自由文字打在伺服器：即使不在未過濾的第一頁窗內也搜得到" do
    make("針線盒", created_at: 3.minutes.ago)
    make("毛線球", created_at: 2.minutes.ago)
    make("最新商品", created_at: 1.minute.ago)

    # first: 1 未過濾只會回「最新商品」；帶 query 仍能拿到最舊的「針線盒」＝過濾在伺服器。
    expect(search("針線", first: 1)).to eq([ "針線盒" ])
  end

  it "多詞 AND；引號片語（單雙皆可）整段比對" do
    make("Rose Tonnerre EDP 100ml")
    make("Rose Garden Soap")

    expect(search("Rose Tonnerre")).to eq([ "Rose Tonnerre EDP 100ml" ])
    expect(search(%q("Garden Soap"))).to eq([ "Rose Garden Soap" ])
    expect(search(%q('Garden Soap'))).to eq([ "Rose Garden Soap" ])
  end

  it "status: 等值過濾；非法值回空集而不是錯資料" do
    make("草稿商品", status: "draft", created_at: 2.minutes.ago)
    make("上架商品", status: "active", created_at: 1.minute.ago)

    expect(search("status:draft")).to eq([ "草稿商品" ])
    expect(search("status:DRAFT")).to eq([ "草稿商品" ])
    expect(search("status:bogus")).to eq([])
    # 同欄位兩次＝AND（本尊語義）⇒ 恆空
    expect(search("status:active status:draft")).to eq([])
  end

  it "vendor: 與 product_type: 等值；帶空白的值用引號" do
    make("A", vendor: "Maison Margiela", product_type: "Fragrance")
    make("B", vendor: "Aesop", product_type: "Skincare")

    expect(search(%q(vendor:"Maison Margiela"))).to eq([ "A" ])
    expect(search("product_type:Skincare")).to eq([ "B" ])
    expect(search(%q(vendor:Aesop product_type:Skincare))).to eq([ "B" ])
    expect(search(%q(vendor:Aesop product_type:Fragrance))).to eq([])
  end

  it "未知 prefix 當字面文字，不猜、不半支援" do
    make("tag:red 標題剛好長這樣")
    make("紅色商品")

    # v1 未支援 tag:（等值集合運算屬第 9 包）⇒ 整個 token 對 title 做字面搜尋
    expect(search("tag:red")).to eq([ "tag:red 標題剛好長這樣" ])
  end

  it "🔴 LIKE 萬用字元跳脫：使用者輸入的 % 與 _ 是字面字元" do
    make("100% cotton tee", created_at: 2.minutes.ago)
    make("wool sweater", created_at: 1.minute.ago)

    expect(search("0%")).to eq([ "100% cotton tee" ])   # 不跳脫的話 %0%% 會兩件都中
    expect(search("w_ol")).to eq([])                     # _ 不是單字元萬用
  end

  it "租戶隔離：query 搜不到別店的商品" do
    other = create(:shop, subdomain: "other-search-shop")
    ActsAsTenant.with_tenant(other) { create(:product, shop: other, title: "獨家針線盒") }
    make("本店商品")

    expect(search("針線")).to eq([])
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
