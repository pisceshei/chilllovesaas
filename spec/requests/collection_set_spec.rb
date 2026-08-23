# frozen_string_literal: true

require "rails_helper"

# ML-3：商品系列（含多語言）。與 productSet 對稱——建立與更新同一支、全樹、lockVersion 涵蓋譯文。
RSpec.describe "Admin GraphQL collectionSet", type: :request do
  let(:shop) { create(:shop, subdomain: "collection-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let!(:product_a) { ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "Alpha") } }
  let!(:product_b) { ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "Beta") } }

  let(:mutation) { <<~GRAPHQL }
    mutation collectionSet($input: CollectionSetInput!) {
      collectionSet(input: $input) {
        collection {
          id title handle collectionType sortOrder lockVersion productsCount productIds
          descriptionHtml
          seo { title description }
          translations { locale field value outdated }
          translationStatus { locale translatedFields requiredFields complete }
        }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "collection-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def create_collection(overrides = {})
    post_graphql(mutation, variables: { input: {
      title: "Spring Picks", descriptionHtml: "<p>Fresh</p>"
    }.merge(overrides) })
    response.parsed_body.dig("data", "collectionSet")
  end

  it "建立手動系列：handle 由英文標題生成、成員照陣列順序、譯文一次寫入" do
    data = create_collection(
      productIds: [ "gid://chilllove/Product/#{product_b.id}", "gid://chilllove/Product/#{product_a.id}" ],
      seo: { title: "Spring", description: "Picks for spring" },
      translations: [
        { locale: "zh-Hant", field: "title", value: "春季精選" },
        { locale: "ja", field: "title", value: "春のおすすめ" }
      ]
    )

    expect(data["userErrors"]).to eq([])
    collection = data["collection"]
    expect(collection["handle"]).to eq("spring-picks")
    expect(collection["collectionType"]).to eq("manual")
    expect(collection["productsCount"]).to eq(2)
    # 宣告式：順序＝陣列順序（B 在前）
    expect(collection["productIds"]).to eq([
      "gid://chilllove/Product/#{product_b.id}", "gid://chilllove/Product/#{product_a.id}"
    ])
    expect(collection["translations"].map { |row| row["value"] }).to contain_exactly("春季精選", "春のおすすめ")
    status = collection["translationStatus"].index_by { |row| row["locale"] }
    expect(status["zh-Hant"]).to include("translatedFields" => 1, "requiredFields" => 2, "complete" => false)
  end

  it "更新：宣告式成員同步（未列出＝移除）、lockVersion 遞增" do
    created = create_collection(productIds: [
      "gid://chilllove/Product/#{product_a.id}", "gid://chilllove/Product/#{product_b.id}"
    ])["collection"]

    post_graphql(mutation, variables: { input: {
      id: created["id"], lockVersion: created["lockVersion"],
      title: "Spring Picks", descriptionHtml: "<p>Fresh</p>",
      productIds: [ "gid://chilllove/Product/#{product_a.id}" ]
    } })
    data = response.parsed_body.dig("data", "collectionSet")

    expect(data["userErrors"]).to eq([])
    expect(data.dig("collection", "productIds")).to eq([ "gid://chilllove/Product/#{product_a.id}" ])
    expect(data.dig("collection", "lockVersion")).to be > created["lockVersion"]
    ActsAsTenant.with_tenant(shop) { expect(CollectionProduct.count).to eq(1) }
  end

  it "過期 lockVersion ⇒ STALE_OBJECT，資料不動" do
    created = create_collection["collection"]
    post_graphql(mutation, variables: { input: { id: created["id"], lockVersion: created["lockVersion"], title: "第一次改" } })
    expect(response.parsed_body.dig("data", "collectionSet", "userErrors")).to eq([])

    post_graphql(mutation, variables: { input: { id: created["id"], lockVersion: created["lockVersion"], title: "第二次改" } })
    data = response.parsed_body.dig("data", "collectionSet")
    expect(data["userErrors"]).to contain_exactly(a_hash_including("code" => "STALE_OBJECT"))
    ActsAsTenant.with_tenant(shop) { expect(Collection.sole.title).to eq("第一次改") }
  end

  it "🔴 智慧系列忽略 productIds（成員是規則的函數，不得製造第二個真相）" do
    data = create_collection(
      collectionType: "smart",
      productIds: [ "gid://chilllove/Product/#{product_a.id}" ]
    )
    expect(data["userErrors"]).to eq([])
    expect(data.dig("collection", "collectionType")).to eq("smart")
    expect(data.dig("collection", "productIds")).to eq([])
    # productsCount 對智慧系列回 null（規則引擎落地前不假裝知道）
    expect(data.dig("collection", "productsCount")).to be_nil
    ActsAsTenant.with_tenant(shop) { expect(CollectionProduct.count).to eq(0) }
  end

  it "譯文語義與商品一致：來源語言 reject、空字串刪列、改來源標過期" do
    created = create_collection(translations: [ { locale: "ja", field: "title", value: "春" } ])["collection"]

    post_graphql(mutation, variables: { input: {
      id: created["id"], lockVersion: created["lockVersion"], title: "Spring Picks",
      translations: [ { locale: "en", field: "title", value: "X" } ]
    } })
    expect(response.parsed_body.dig("data", "collectionSet", "userErrors"))
      .to contain_exactly(a_hash_including("code" => "INVALID"))

    # 改來源標題（譯文原值一起送回，與前端形態相同）⇒ 標過期
    post_graphql(mutation, variables: { input: {
      id: created["id"], lockVersion: created["lockVersion"], title: "Spring Picks 2026",
      translations: [ { locale: "ja", field: "title", value: "春" } ]
    } })
    data = response.parsed_body.dig("data", "collectionSet")
    expect(data.dig("collection", "translations").first).to include("outdated" => true, "value" => "春")

    # 空字串刪列
    post_graphql(mutation, variables: { input: {
      id: created["id"], lockVersion: data.dig("collection", "lockVersion"), title: "Spring Picks 2026",
      translations: [ { locale: "ja", field: "title", value: "" } ]
    } })
    expect(response.parsed_body.dig("data", "collectionSet", "collection", "translations")).to eq([])
  end

  it "驗證：標題必填、型別與排序值域封閉、handle 衝突" do
    expect(create_collection(title: "")["userErrors"]).to contain_exactly(a_hash_including("code" => "BLANK"))
    expect(create_collection(collectionType: "hybrid")["userErrors"]).to contain_exactly(a_hash_including("code" => "INVALID"))
    expect(create_collection(sortOrder: "random")["userErrors"]).to contain_exactly(a_hash_including("code" => "INVALID"))

    create_collection(handle: "taken-handle")
    expect(create_collection(title: "Another", handle: "taken-handle")["userErrors"])
      .to contain_exactly(a_hash_including("code" => "HANDLE_TAKEN"))
  end

  it "collections 列表與 collection(id:) 讀取面；租戶隔離" do
    created = create_collection["collection"]

    post_graphql("query { collections(first: 10) { nodes { id title handle } pageInfo { hasNextPage } } }")
    nodes = response.parsed_body.dig("data", "collections", "nodes")
    expect(nodes.map { |row| row["title"] }).to eq([ "Spring Picks" ])

    post_graphql("query($id: ID!) { collection(id: $id) { title productsCount } }", variables: { id: created["id"] })
    expect(response.parsed_body.dig("data", "collection", "title")).to eq("Spring Picks")

    other = create(:shop, subdomain: "other-collection-shop")
    ActsAsTenant.with_tenant(other) { expect(Collection.count).to eq(0) }
  end

  # 🔴 列表的成員數不得逐列 COUNT：上限 250（limits.yml）⇒ 單一請求 250 次 DB。
  # 斷言方式是「數 SQL」而不是「看回傳值」——回傳值正確的 N+1 一樣是 N+1。
  it "collections 列表用單一子查詢帶出成員數，不逐列 COUNT" do
    3.times do |index|
      create_collection(title: "Batch #{index}", handle: "batch-#{index}", productIds: [ "gid://chilllove/Product/#{product_a.id}" ])
    end

    counts = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      counts << payload[:sql] if payload[:sql].to_s.match?(/\ASELECT COUNT\(\*\)\s+FROM\s+`?collection_products/i)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      post_graphql("query { collections(first: 10) { nodes { title productsCount } } }")
    end

    nodes = response.parsed_body.dig("data", "collections", "nodes")
    expect(nodes.length).to eq(3)
    expect(nodes.map { |row| row["productsCount"] }).to all(eq(1))
    expect(counts).to be_empty
  end

  # 🔴 宣告式 API 的靜默丟棄是最糟的失敗形態：存檔回「成功」，成員卻少一個。
  # 兩種來源都要報錯——格式不對（客戶端 bug）與查無此商品（已刪除／別店 GID）。
  it "成員 ID 格式錯誤或查無此商品時報錯，不靜默丟棄" do
    post_graphql(mutation, variables: { input: {
      title: "Bad Ids", productIds: [ "12", "gid://chilllove/Product/#{product_a.id}" ]
    } })
    payload = response.parsed_body.dig("data", "collectionSet")
    expect(payload["collection"]).to be_nil
    expect(payload["userErrors"].map { |row| row["code"] }).to eq([ "INVALID" ])
    expect(payload.dig("userErrors", 0, "field")).to eq([ "productIds" ])
    # 沒有半成品系列留下。（注意：**這裡驗不到巢狀交易**——RSpec 的測試交易是
    #  `joinable: false`，所以有沒有 `requires_new:` 在這支都是綠的。
    #  生產形態的巢狀回滾由 `spec/services/catalog/save_collection_spec.rb` 守。）
    expect(ActsAsTenant.with_tenant(shop) { Collection.where(shop_id: shop.id, title: "Bad Ids").count }).to eq(0)

    other_shop = create(:shop, subdomain: "foreign-shop")
    foreign = ActsAsTenant.with_tenant(other_shop) { create(:product, shop: other_shop, title: "Foreign") }
    post_graphql(mutation, variables: { input: {
      title: "Foreign Member", productIds: [ "gid://chilllove/Product/#{foreign.id}" ]
    } })
    payload = response.parsed_body.dig("data", "collectionSet")
    expect(payload["collection"]).to be_nil
    expect(payload.dig("userErrors", 0, "code")).to eq("NOT_FOUND")
    # 🔴 跨店 GID 不得靜默成功建立一個空系列。
    expect(ActsAsTenant.with_tenant(shop) { Collection.where(shop_id: shop.id, title: "Foreign Member").count }).to eq(0)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
