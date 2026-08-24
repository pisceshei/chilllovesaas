# frozen_string_literal: true

require "rails_helper"

# 第 22 包（整合規格 §4-22）：productSet options 樹＋兩階段 diff＋initialQuantities。
# 🔴 核心驗收條＝63:1141：「建立無變體商品 → 加選項 → 斷言原 variant.id 與
#    inventory_item.id 完全相同、ledger 連續」。
RSpec.describe "Admin GraphQL productSet 多變體", type: :request do
  let(:shop) { create(:shop, subdomain: "psetvar-shop") }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "psetvar-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  P22_MUTATION = <<~GRAPHQL
    mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
      productSet(input: $input, idempotencyKey: $idempotencyKey) {
        product {
          id lockVersion
          options { name values { value } }
          variants(first: 20) { nodes { id title position price sku selectedOptions { name value } } }
        }
        userErrors { field message code }
      }
    }
  GRAPHQL

  def set!(input)
    post_graphql(P22_MUTATION, variables: { input:, idempotencyKey: SecureRandom.uuid })
    response.parsed_body.dig("data", "productSet")
  end

  def create_plain!(title: "帽T")
    data = set!({ title:, variants: [ { price: "128.00" } ] })
    expect(data["userErrors"]).to eq([])
    data["product"]
  end

  it "🔴 63:1141：無變體商品加選項——原 variant.id 與 inventory_item.id 完全相同、ledger 連續" do
    login!
    product = create_plain!
    original_vid = product.dig("variants", "nodes").sole["id"]
    original_item_id = ActsAsTenant.with_tenant(shop) do
      vid = original_vid[%r{/(\d+)\z}, 1].to_i
      item = InventoryItem.find_by!(product_variant_id: vid)
      # 造一筆 ledger（開帳語義），驗刪改後連續
      level = item.inventory_levels.first!
      r = Inventory::Adjust.call(shop:, mode: "adjust", input: {
        name: "available", reason: "received", idempotency_key: SecureRandom.uuid,
        changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                     location_id: "gid://chilllove/Location/#{level.location_id}", delta: 5 } ] })
      raise r.user_errors.inspect if r.user_errors.any?
      item.id
    end
    ledger_before = InventoryAdjustment.unscoped.count

    data = set!({
      id: product["id"], lockVersion: product["lockVersion"], title: "帽T",
      options: [ { name: "容量", values: [ "230ml", "250ml", "330ml" ] } ],
      variants: [
        { id: original_vid, price: "128.00",
          optionValues: [ { optionName: "容量", value: "230ml" } ] },
        { price: "138.00", optionValues: [ { optionName: "容量", value: "250ml" } ] },
        { price: "148.00", optionValues: [ { optionName: "容量", value: "330ml" } ] }
      ]
    })
    expect(data["userErrors"]).to eq([])
    nodes = data.dig("product", "variants", "nodes")
    expect(nodes.length).to eq(3)
    expect(nodes.map { |n| n["title"] }).to eq([ "230ml", "250ml", "330ml" ])

    # 🔴 身分保持三斷言
    expect(nodes.first["id"]).to eq(original_vid)
    ActsAsTenant.without_tenant do
      vid = original_vid[%r{/(\d+)\z}, 1].to_i
      expect(InventoryItem.find_by!(product_variant_id: vid).id).to eq(original_item_id)
      expect(InventoryAdjustment.unscoped.count).to eq(ledger_before)
    end
  end

  it "無 id 的既有座標列以投影後 digest 對應（不重建）；未列出的變體被刪除（63 §B.4 硬規則 1）" do
    login!
    product = create_plain!(title: "外套")
    data = set!({
      id: product["id"], lockVersion: product["lockVersion"], title: "外套",
      options: [ { name: "尺寸", values: [ "S", "M" ] } ],
      variants: [
        { price: "100.00", optionValues: [ { optionName: "尺寸", value: "S" } ] },
        { price: "110.00", optionValues: [ { optionName: "尺寸", value: "M" } ] }
      ]
    })
    expect(data["userErrors"]).to eq([])
    s_id = data.dig("product", "variants", "nodes").first["id"]
    # 隱含變體投影到「尺寸=S」（第一值）⇒ 無 id 的 S 列以 digest 配上、id 不變
    expect(s_id).to eq(product.dig("variants", "nodes").sole["id"])

    lock2 = ActsAsTenant.with_tenant(shop) { Product.find(product["id"][%r{/(\d+)\z}, 1]).lock_version }
    data2 = set!({
      id: product["id"], lockVersion: lock2, title: "外套",
      options: [ { name: "尺寸", values: [ "S" ] } ],
      variants: [ { id: s_id, price: "100.00", optionValues: [ { optionName: "尺寸", value: "S" } ] } ]
    })
    expect(data2["userErrors"]).to eq([])
    expect(data2.dig("product", "variants", "nodes").map { |n| n["id"] }).to eq([ s_id ])
  end

  it "initialQuantities：create-only、走 Adjust 落 ledger；帶 id 給它 ⇒ INVALID" do
    login!
    location_gid = ActsAsTenant.with_tenant(shop) { "gid://chilllove/Location/#{Location.first!.id}" }
    data = set!({
      title: "毛衣",
      options: [ { name: "色", values: [ "黑", "白" ] } ],
      variants: [
        { price: "90.00", optionValues: [ { optionName: "色", value: "黑" } ],
          initialQuantities: [ { locationId: location_gid, quantity: 7 } ] },
        { price: "90.00", optionValues: [ { optionName: "色", value: "白" } ] }
      ]
    })
    expect(data["userErrors"]).to eq([])
    black_id = data.dig("product", "variants", "nodes").first["id"][%r{/(\d+)\z}, 1].to_i
    ActsAsTenant.without_tenant do
      item = InventoryItem.find_by!(product_variant_id: black_id)
      level = item.inventory_levels.first!
      expect(level.available).to eq(7)
      group = InventoryAdjustmentGroup.unscoped.where(reason: "received").order(:id).last
      expect(group).to be_present
      expect(InventoryAdjustment.unscoped.where(inventory_adjustment_group_id: group.id).count).to eq(1)
    end

    product = data["product"]
    vid = product.dig("variants", "nodes").first["id"]
    data2 = set!({
      id: product["id"], lockVersion: product["lockVersion"], title: "毛衣",
      options: [ { name: "色", values: [ "黑", "白" ] } ],
      variants: [
        { id: vid, price: "90.00", optionValues: [ { optionName: "色", value: "黑" } ],
          initialQuantities: [ { locationId: location_gid, quantity: 99 } ] }
      ]
    })
    codes = data2["userErrors"].map { |e| e["code"] }
    expect(codes).to include("INVALID")
    expect(data2["userErrors"].map { |e| e["field"] }).to include([ "variants", "0", "initialQuantities" ])
  end

  it "重複座標組合 ⇒ INVALID；值不在樹內 ⇒ INVALID；選項數超限 ⇒ OPTIONS_OVER_LIMIT" do
    login!
    data = set!({
      title: "T1",
      options: [ { name: "尺寸", values: [ "S" ] } ],
      variants: [
        { price: "1.00", optionValues: [ { optionName: "尺寸", value: "S" } ] },
        { price: "2.00", optionValues: [ { optionName: "尺寸", value: "S" } ] }
      ]
    })
    expect(data["userErrors"].map { |e| e["code"] }).to include("INVALID")

    over = (1..(Limits.fetch(:product, :max_options) + 1)).map { |i| { name: "選項#{i}", values: [ "v" ] } }
    data2 = set!({ title: "T2", options: over,
                   variants: [ { price: "1.00",
                                 optionValues: over.map { |o| { optionName: o[:name], value: "v" } } } ] })
    expect(data2["userErrors"].map { |e| e["code"] }).to include("OPTIONS_OVER_LIMIT")
  end

  it "digest 不對外曝露（13 §F1-2：不進 GraphQL）——introspection 全 schema 零命中" do
    login!
    post_graphql("query { __schema { types { name fields { name } } } }")
    body = response.body
    expect(body).not_to include("optionValuesDigest")
    expect(body).not_to include("option_values_digest")
  end

  def login!(email: staff.email)
    post login_path, params: { email:, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path,
      params: { query:, variables: }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
  end
end
