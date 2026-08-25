# frozen_string_literal: true

require "rails_helper"

# 第 11 包：collectionSet 的 sources／rules 契約（request 層）＋觸發鏈。
RSpec.describe "Admin GraphQL smart collection sources", type: :request do
  let(:shop) { create(:shop, subdomain: "smart-api") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  let(:mutation) { <<~GRAPHQL }
    mutation collectionSet($input: CollectionSetInput!) {
      collectionSet(input: $input) {
        collection { id lockVersion collectionType rebuildStatus productsCount }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "smart-api.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def set!(input)
    post_graphql(mutation, variables: { input: })
    response.parsed_body.dig("data", "collectionSet")
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
  end

  def smart_input(rules:, extra: {})
    { title: "夏季精選", collectionType: "smart",
      sources: [ { rules: } ] }.merge(extra)
  end

  it "建立智慧系列：sources 落列、rebuild_status=PENDING、RebuildJob 已排" do
    login!
    expect {
      data = set!(smart_input(rules: [
        { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "夏季" },
        { block: "inclusion", conditionType: "variant_price", relation: "lt", valueMoney: "200.00" }
      ]))
      expect(data["userErrors"]).to eq([])
      expect(data.dig("collection", "rebuildStatus")).to eq("PENDING")
      expect(data.dig("collection", "productsCount")).to be_nil   # 未 rebuild ⇒ null 不是 0
    }.to have_enqueued_job(Collections::RebuildJob)

    ActsAsTenant.with_tenant(shop) do
      rule_rows = CollectionSourceRule.order(:position)
      expect(rule_rows.map(&:condition_type)).to eq(%w[product_tag variant_price])
      # 🔴 金額落 value_cents（鐵律 3）：字串只活在序列化邊界。
      expect(rule_rows.last.value_cents).to eq(20_000)
      expect(rule_rows.last.value_text).to be_nil
    end
  end

  it "🔴 exclusion 區塊拒收價格條件（值域是「哪個區塊有哪些欄位」）" do
    login!
    data = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "a" },
      { block: "exclusion", conditionType: "variant_price", relation: "gt", valueMoney: "10.00" }
    ]))

    expect(data["userErrors"].map { |e| e["code"] }).to eq([ "INVALID" ])
    expect(data["userErrors"].first["field"]).to include("conditionType")
    ActsAsTenant.with_tenant(shop) { expect(Collection.count).to eq(0) }
  end

  it "🔴 contains 值不足 3 字元 ⇒ TOO_SHORT（官方下限）" do
    login!
    data = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_title", relation: "contains", valueText: "ab" }
    ]))

    expect(data["userErrors"].map { |e| e["code"] }).to eq([ "TOO_SHORT" ])
  end

  it "🔴 60 條上限（per-collection，fail-closed 口徑）" do
    login!
    rules = Array.new(61) { |i| { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "t#{i}" } }
    data = set!(smart_input(rules:))

    expect(data["userErrors"].map { |e| e["code"] }).to eq([ "TOO_LONG" ])
  end

  it "manual 系列帶 sources ⇒ INVALID（條件只屬智慧系列）" do
    login!
    data = set!({ title: "手動", collectionType: "manual",
                  sources: [ { rules: [ { block: "inclusion", conditionType: "product_tag",
                                          relation: "includes", valueText: "x" } ] } ] })

    expect(data["userErrors"].map { |e| e["code"] }).to eq([ "INVALID" ])
  end

  it "relation 不在該型別的白名單 ⇒ INVALID（寫入層先擋，不留給 rebuild 才炸）" do
    login!
    data = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_tag", relation: "contains", valueText: "red" }
    ]))

    expect(data["userErrors"].map { |e| e["code"] }).to eq([ "INVALID" ])
    expect(data["userErrors"].first["field"]).to include("relation")
  end

  it "更新時缺席 sources＝保持現值；帶空陣列＝清掉全部來源" do
    login!
    created = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "red" }
    ]))
    id = created.dig("collection", "id")
    lock = created.dig("collection", "lockVersion")

    kept = set!({ id:, lockVersion: lock, title: "夏季精選改", collectionType: "smart" })
    expect(kept["userErrors"]).to eq([])
    ActsAsTenant.with_tenant(shop) { expect(CollectionSourceRule.count).to eq(1) }

    updated = set!({ id:, lockVersion: kept.dig("collection", "lockVersion"),
                     title: "夏季精選改", collectionType: "smart", sources: [] })
    expect(updated["userErrors"]).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(CollectionSource.count).to eq(0)
      expect(CollectionSourceRule.count).to eq(0)
    end
  end

  it "🔴 F3（2026-08-26 審查）：宣告式契約——更新缺席 collectionType／sortOrder＝保持現值" do
    login!
    created = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "red" }
    ], extra: { sortOrder: "best_selling" }))
    expect(created["userErrors"]).to eq([])
    id = created.dig("collection", "id")

    # 初版 `input[:collection_type] || "manual"` 在這裡把智慧系列**靜默改成手動**、
    # sortOrder 重置回 manual——與 SaveProduct 的 status 語義（保持現值）相反。
    kept = set!({ id:, lockVersion: created.dig("collection", "lockVersion"), title: "改名" })
    expect(kept["userErrors"]).to eq([])
    expect(kept.dig("collection", "collectionType")).to eq("smart")
    ActsAsTenant.with_tenant(shop) do
      row = Collection.sole
      expect(row.collection_type).to eq("smart")
      expect(row.sort_order).to eq("best_selling")
      expect(CollectionSourceRule.count).to eq(1)   # sources 也原封不動
    end

    # 缺席 collectionType＋帶 sources：更新智慧系列的正常形，不得誤殺成 sources_manual。
    resourced = set!({ id:, lockVersion: kept.dig("collection", "lockVersion"),
                       title: "改名", sources: [ { rules: [
                         { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "blue" }
                       ] } ] })
    expect(resourced["userErrors"]).to eq([])
    ActsAsTenant.with_tenant(shop) do
      expect(CollectionSourceRule.sole.value_text).to eq("blue")
    end
  end

  it "🔴 F3 連動：型別建立後不可變——顯式 smart→manual 一律 INVALID（本尊官方語義）" do
    login!
    created = set!(smart_input(rules: [
      { block: "inclusion", conditionType: "product_tag", relation: "includes", valueText: "red" }
    ]))
    id = created.dig("collection", "id")

    flipped = set!({ id:, lockVersion: created.dig("collection", "lockVersion"),
                     title: "夏季精選", collectionType: "manual" })
    expect(flipped["userErrors"].map { |e| [ e["field"], e["code"] ] })
      .to eq([ [ [ "collectionType" ], "INVALID" ] ])
    ActsAsTenant.with_tenant(shop) do
      row = Collection.sole
      expect(row.collection_type).to eq("smart")
      expect(CollectionSourceRule.count).to eq(1)   # 整棵樹回滾，sources 沒被動
    end
    # 同值重送＝no-op（既有更新測試都帶 collectionType: "smart"，那條路必須續通）。
    same = set!({ id:, lockVersion: created.dig("collection", "lockVersion"),
                  title: "夏季精選", collectionType: "smart" })
    expect(same["userErrors"]).to eq([])
  end

  it "collectionRuleConditions：執行期 relation 對照（前端不得硬編的那張表）" do
    login!
    post_graphql("query { collectionRuleConditions { ruleType allowedRelations defaultRelation allowedInExclusion } }")
    rows = response.parsed_body.dig("data", "collectionRuleConditions")

    expect(rows.map { |r| r["ruleType"] }).to match_array(Collections::RuleCompiler::INCLUSION_TYPES)
    tag_row = rows.find { |r| r["ruleType"] == "product_tag" }
    expect(tag_row["allowedRelations"]).to eq(%w[includes does_not_include])
    expect(tag_row["allowedInExclusion"]).to be(true)
    price_row = rows.find { |r| r["ruleType"] == "variant_price" }
    expect(price_row["allowedInExclusion"]).to be(false)
  end

  it "productSet 的 tags 變更同 tx 維護 product_tags（引擎 tag 條件的載體）" do
    login!
    post_graphql(<<~GRAPHQL, variables: { input: { title: "紅玫瑰", tags: [ "Red_New", "夏季" ], variants: [ { price: "128.00" } ] }, key: SecureRandom.uuid })
      mutation productSet($input: ProductSetInput!, $key: String) {
        productSet(input: $input, idempotencyKey: $key) { product { id } userErrors { code } }
      }
    GRAPHQL
    expect(response.parsed_body.dig("data", "productSet", "userErrors")).to eq([]),
      response.parsed_body.inspect[0, 400]

    ActsAsTenant.with_tenant(shop) do
      expect(ProductTag.pluck(:tag_key)).to contain_exactly("red-new", "夏季")
      expect(ProductTag.find_by(tag_key: "red-new").tag_display).to eq("Red_New")
    end
  end
end
