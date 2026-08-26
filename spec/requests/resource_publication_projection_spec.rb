# frozen_string_literal: true

require "rails_helper"

# S2：`resourcePublicationsV2` 讀出投影 ＋ publication 的兩個計數。
#
# 🔴 本檔的每一格都刻意落在**「已排程未到點」**那個狀態——那是本尊兩種投影
#   語義相反的**唯一**分歧點，也是沒有它就會 100% 全綠的那個維度。
#
# @see docs/dev/m2-resource-publication-semantics.md
RSpec.describe "Admin GraphQL resource publication projection", type: :request do
  let(:shop) { create(:shop, subdomain: "respub-proj") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:future) { 3.days.from_now }

  let(:product_query) { <<~GRAPHQL }
    query products($onlyPublished: Boolean) {
      products(first: 10) {
        edges { node {
          id
          resourcePublicationsV2(onlyPublished: $onlyPublished) {
            isPublished
            publishDate
            publication { id title handle }
          }
        } }
      }
    }
  GRAPHQL

  let(:counts_query) { <<~GRAPHQL }
    query publications {
      publications { id publishedResourceCount stagedResourceCount }
    }
  GRAPHQL

  before do
    host! "respub-proj.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
  end

  def json = response.parsed_body

  def online_store = ActsAsTenant.with_tenant(shop) { Publication.online_store! }

  def schedule!(record, at: future)
    ActsAsTenant.without_tenant do
      ResourcePublication
        .where(shop_id: shop.id, publication_id: online_store.id,
               publishable_type: record.class.name, publishable_id: record.id)
        .update_all(published_at: at)
    end
  end

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      record = create(:product, shop:)
      create(:product_variant, product: record)
      record
    end
  end

  def rows_from_response
    json.dig("data", "products", "edges", 0, "node", "resourcePublicationsV2")
  end

  # ── 投影本體 ─────────────────────────────────────────────────────────────

  it "已發布的資源回一列，isPublished=true 且 publishDate 是過去" do
    login!
    post_graphql(product_query)

    rows = rows_from_response
    expect(rows.size).to eq(1)
    expect(rows.first["isPublished"]).to be(true)
    expect(Time.iso8601(rows.first["publishDate"])).to be <= Time.current
    expect(rows.first.dig("publication", "handle")).to eq(Shop::DEFAULT_CHANNEL_HANDLE)
  end

  # 🔴 本尊 `onlyPublished` 官方 default **true**（逐字 `Whether to return only the
  #   resources that are currently published`）。我方照抄名稱、型別與預設值。
  it "🔴 預設 onlyPublished=true ⇒ 排程中的資源**不出現**" do
    schedule!(product)
    login!
    post_graphql(product_query)

    expect(rows_from_response).to eq([])
  end

  # 🔴 這一格是 V2 語義的定義性斷言：排程中 ⇒ 列**存在**且 `isPublished` 是 **false**。
  #   若照 V1 語義實作（排程也算 true），這一格會紅。
  it "🔴 onlyPublished=false ⇒ 排程中的資源出現，且 isPublished 是 **false**（staged）" do
    schedule!(product)
    login!
    post_graphql(product_query, variables: { onlyPublished: false })

    rows = rows_from_response
    expect(rows.size).to eq(1)
    expect(rows.first["isPublished"]).to be(false),
      "排程中回 true 是本尊 V1 的語義；我方明文只實作 V2"
    expect(Time.iso8601(rows.first["publishDate"])).to be > Time.current
  end

  # 🔴 V2 的定義性質：`published_at IS NULL` 的列不屬於 V2。
  #   官方逐字 `an instance of ResourcePublicationV2 can't be unpublished.`
  it "🔴 published_at 為 NULL 的列在兩種 onlyPublished 下都不出現" do
    ActsAsTenant.without_tenant do
      ResourcePublication.where(shop_id: shop.id, publishable_type: "Product",
                                publishable_id: product.id).update_all(published_at: nil)
    end
    login!

    post_graphql(product_query)
    expect(rows_from_response).to eq([])

    post_graphql(product_query, variables: { onlyPublished: false })
    expect(rows_from_response).to eq([])
  end

  it "看不到別間店的發布列（鐵律 2）" do
    other = create(:shop, subdomain: "respub-proj-other")
    ActsAsTenant.with_tenant(other) { create(:product, shop: other) }
    login!
    post_graphql(product_query, variables: { onlyPublished: false })

    edges = json.dig("data", "products", "edges")
    expect(edges.size).to eq(1)
  end

  # ── C-10：publication 的兩個計數 ─────────────────────────────────────────

  describe "publication 的計數（S2 修正的 S1 bug）" do
    # 🔴 S1 交付的 `publishedResourceCount` 是 `resource_publications.count`
    #   ——**完全不看 `published_at`**。排程一存在就把「排程中」算成「已發布」。
    #   這一格就是那個 bug 的守衛。
    it "🔴 publishedResourceCount **不含**排程中的；stagedResourceCount 才算它" do
      variant = ActsAsTenant.without_tenant { product.product_variants.first }
      schedule!(product)
      schedule!(variant)
      login!

      post_graphql(counts_query)
      row = json.dig("data", "publications", 0)

      expect(row["publishedResourceCount"]).to eq(0),
        "排程中的資源被算成已發布了——那正是 S1 的 bug"
      expect(row["stagedResourceCount"]).to eq(2)
    end

    it "全部到點時 published 全收、staged 為 0" do
      login!
      post_graphql(counts_query)
      row = json.dig("data", "publications", 0)

      expect(row["publishedResourceCount"]).to be_positive
      expect(row["stagedResourceCount"]).to eq(0)
    end

    # `published_at IS NULL` 兩邊都不算——它既不是已發布也不是已排程。
    it "🔴 published_at 為 NULL 的列兩個計數都不算" do
      ActsAsTenant.without_tenant do
        ResourcePublication.where(shop_id: shop.id).update_all(published_at: nil)
      end
      login!

      post_graphql(counts_query)
      row = json.dig("data", "publications", 0)
      expect(row["publishedResourceCount"]).to eq(0)
      expect(row["stagedResourceCount"]).to eq(0)
    end
  end
end
