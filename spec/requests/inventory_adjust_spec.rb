# frozen_string_literal: true

require "rails_helper"

# 排程第 17 包：庫存唯一寫入入口的 GraphQL 面（G28／D41／95 §4 的語義逐條驗）。
RSpec.describe "Admin GraphQL inventory mutations", type: :request do
  let(:shop) { create(:shop, subdomain: "inv-adjust-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
  let(:item) { ActsAsTenant.with_tenant(shop) { variant.inventory_item } }
  let(:location) { ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).first! } }
  let(:level) { ActsAsTenant.with_tenant(shop) { item.inventory_levels.first! } }

  ADJUST = <<~GRAPHQL
    mutation adj($key: String!, $input: InventoryAdjustQuantitiesInput!) {
      inventoryAdjustQuantities(idempotencyKey: $key, input: $input) {
        inventoryAdjustmentGroup { id reason changesCount changes { name delta } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  SET = <<~GRAPHQL
    mutation set($key: String!, $input: InventorySetQuantitiesInput!) {
      inventorySetQuantities(idempotencyKey: $key, input: $input) {
        inventoryAdjustmentGroup { id changesCount changes { name delta } }
        userErrors { field message code }
      }
    }
  GRAPHQL

  before do
    host! "inv-adjust-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def gid_item = "gid://chilllove/InventoryItem/#{item.id}"
  def gid_loc = "gid://chilllove/Location/#{location.id}"

  def adjust(key:, **input_overrides)
    input = {
      reason: "received", name: "available",
      changes: [ { inventoryItemId: gid_item, locationId: gid_loc, delta: 5 } ]
    }.merge(input_overrides)
    post_graphql(ADJUST, variables: { key:, input: })
    response.parsed_body.dig("data", "inventoryAdjustQuantities")
  end

  it "adjust 走通：ledger 落列、level 現值更新、changes 投影含衍生的 on_hand" do
    payload = adjust(key: "k1")
    expect(payload["userErrors"]).to eq([])
    group = payload["inventoryAdjustmentGroup"]
    expect(group["reason"]).to eq("received")
    expect(group["changesCount"]).to eq(1)
    # 🔴 本尊語義：調 available 回兩筆（available＋on_hand）——儲存一列、讀取投影兩筆
    expect(group["changes"]).to contain_exactly(
      { "name" => "available", "delta" => 5 },
      { "name" => "on_hand", "delta" => 5 }
    )
    expect(level.reload.available).to eq(5)
    expect(level.on_hand).to eq(5)
    expect(InventoryAdjustment.unscoped.where(shop_id: shop.id).count).to eq(1)
  end

  it "冪等重放（D41：同 key 回同一個 group、不重複落列）；同 key 不同參數回 mismatch" do
    first = adjust(key: "k2")
    replay = adjust(key: "k2")
    expect(replay.dig("inventoryAdjustmentGroup", "id")).to eq(first.dig("inventoryAdjustmentGroup", "id"))
    expect(level.reload.available).to eq(5)   # 只加一次
    expect(InventoryAdjustment.unscoped.where(shop_id: shop.id).count).to eq(1)

    mismatch = adjust(key: "k2", reason: "correction")
    expect(mismatch.dig("userErrors", 0, "code")).to eq("IDEMPOTENCY_KEY_PARAMETER_MISMATCH")
  end

  it "G28：idempotencyKey 是契約層必填——缺鍵連 resolver 都進不去" do
    post_graphql(
      "mutation($input: InventoryAdjustQuantitiesInput!) { inventoryAdjustQuantities(input: $input) { userErrors { code } } }",
      variables: { input: { reason: "received", name: "available", changes: [] } }
    )
    expect(response.parsed_body["errors"]).to be_present
    expect(response.parsed_body["data"]).to be_nil
  end

  it "值域與文件規則逐條擋：reason／name／重複 (item,location)／available 帶文件／非 available 缺文件" do
    bad_reason = adjust(key: "k3", reason: "bogus")
    expect(bad_reason.dig("userErrors", 0, "code")).to eq("INVALID_REASON")

    bad_name = adjust(key: "k4", name: "committed")
    expect(bad_name.dig("userErrors", 0, "code")).to eq("INVALID_QUANTITY_NAME")

    dup = adjust(key: "k5", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 1 },
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 2 }
    ])
    expect(dup["userErrors"].map { |e| e["code"] }).to include("DUPLICATE_INVENTORY_ITEM")

    with_doc = adjust(key: "k6", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 1, ledgerDocumentUri: "app://doc/1" }
    ])
    expect(with_doc.dig("userErrors", 0, "code")).to eq("INVALID_AVAILABLE_DOCUMENT")

    no_doc = adjust(key: "k7", name: "damaged", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 1 }
    ])
    expect(no_doc.dig("userErrors", 0, "code")).to eq("INVALID_QUANTITY_DOCUMENT")

    shopify_ns = adjust(key: "k8", name: "damaged", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 1, ledgerDocumentUri: "gid://shopify/X/1" }
    ])
    expect(shopify_ns["userErrors"].map { |e| e["code"] }).to include("INVALID")

    # 兩支邊界不同：adjust 2e9 過、set 1e9 擋（95 §5）——這裡驗 adjust 超界
    too_high = adjust(key: "k9", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 2_000_000_001 }
    ])
    expect(too_high.dig("userErrors", 0, "code")).to eq("INVALID_QUANTITY_TOO_HIGH")
  end

  it "on_hand 的寫入語義＝翻譯成 available（衍生量永不直寫）；且 on_hand 屬「非 available」要帶 ledger 文件（95 §4）" do
    payload = adjust(key: "k10", name: "on_hand", changes: [
      { inventoryItemId: gid_item, locationId: gid_loc, delta: 3, ledgerDocumentUri: "app://adjustment/onhand-1" }
    ])
    expect(payload["userErrors"]).to eq([])
    expect(level.reload.available).to eq(3)
    expect(level.on_hand).to eq(3)
    row = InventoryAdjustment.unscoped.where(shop_id: shop.id).first!
    expect(row.available_delta).to eq(3)   # 落在 leaf，不是 on_hand 欄
    expect(row.ledger_document_uri).to eq("app://adjustment/onhand-1")
  end

  it "set：CAS 必須表態；stale 擋下且不落列；正確 compare 走通（delta＝目標−現值）" do
    adjust(key: "seed", changes: [ { inventoryItemId: gid_item, locationId: gid_loc, delta: 10 } ])

    post_graphql(SET, variables: { key: "s1", input: {
      reason: "cycle_count_available", name: "available",
      changes: [ { inventoryItemId: gid_item, locationId: gid_loc, quantity: 7 } ]
    } })
    payload = response.parsed_body.dig("data", "inventorySetQuantities")
    expect(payload.dig("userErrors", 0, "code")).to eq("COMPARE_QUANTITY_REQUIRED")

    post_graphql(SET, variables: { key: "s2", input: {
      reason: "cycle_count_available", name: "available",
      changes: [ { inventoryItemId: gid_item, locationId: gid_loc, quantity: 7, compareQuantity: 99 } ]
    } })
    payload = response.parsed_body.dig("data", "inventorySetQuantities")
    expect(payload.dig("userErrors", 0, "code")).to eq("COMPARE_QUANTITY_STALE")
    expect(level.reload.available).to eq(10)
    expect(InventoryAdjustment.unscoped.where(shop_id: shop.id).count).to eq(1)  # stale 不落列

    post_graphql(SET, variables: { key: "s3", input: {
      reason: "cycle_count_available", name: "available",
      changes: [ { inventoryItemId: gid_item, locationId: gid_loc, quantity: 7, compareQuantity: 10 } ]
    } })
    payload = response.parsed_body.dig("data", "inventorySetQuantities")
    expect(payload["userErrors"]).to eq([])
    expect(payload.dig("inventoryAdjustmentGroup", "changes")).to contain_exactly(
      { "name" => "available", "delta" => -3 },
      { "name" => "on_hand", "delta" => -3 }
    )
    expect(level.reload.available).to eq(7)
  end

  it "租戶隔離：別店的 item GID 回 NOT_FOUND，不落任何列" do
    other = create(:shop, subdomain: "other-inv-shop")
    foreign_variant = ActsAsTenant.with_tenant(other) { create(:product_variant, shop: other) }
    foreign_item = ActsAsTenant.with_tenant(other) { foreign_variant.inventory_item }

    payload = adjust(key: "k11", changes: [
      { inventoryItemId: "gid://chilllove/InventoryItem/#{foreign_item.id}", locationId: gid_loc, delta: 1 }
    ])
    expect(payload.dig("userErrors", 0, "code")).to eq("NOT_FOUND")
    expect(InventoryAdjustment.unscoped.where(shop_id: shop.id).count).to eq(0)
  end

  # ── 對抗審查後補的四條守衛 ─────────────────────────────────────
  it "D44：Guard TTL 過期後同 key 重用 ⇒ 200 userError（不是 5xx 毒化）" do
    adjust(key: "ttl-key")
    ActsAsTenant.with_tenant(shop) { IdempotencyKey.find_by!(key: "ttl-key").update!(expires_at: 25.hours.ago) }
    replay = adjust(key: "ttl-key")
    expect(replay.dig("userErrors", 0, "code")).to eq("IDEMPOTENCY_KEY_ALREADY_USED")
    expect(level.reload.available).to eq(5)   # 不重複套用
    # 再試第三次也是同樣的 userError，不是升級成 5xx（毒化循環已斷）
    third = adjust(key: "ttl-key")
    expect(third.dig("userErrors", 0, "code")).to eq("IDEMPOTENCY_KEY_ALREADY_USED")
  end

  it "結果值邊界：兩次各 +1.5e9 單獨合法、第二次超過結果上限 ⇒ userError 不是 500" do
    adjust(key: "big-1", changes: [ { inventoryItemId: gid_item, locationId: gid_loc, delta: 1_500_000_000 } ])
    expect(level.reload.available).to eq(1_500_000_000)
    second = adjust(key: "big-2", changes: [ { inventoryItemId: gid_item, locationId: gid_loc, delta: 1_500_000_000 } ])
    expect(second.dig("userErrors", 0, "code")).to eq("INVALID_QUANTITY_TOO_HIGH")
    expect(level.reload.available).to eq(1_500_000_000)   # 未套用、未落列
  end

  it "set 到相同值：group 回執存在但 changesCount=0、changes 空、不落 ledger 列" do
    adjust(key: "same-seed", changes: [ { inventoryItemId: gid_item, locationId: gid_loc, delta: 4 } ])
    post_graphql(SET, variables: { key: "same-set", input: {
      reason: "cycle_count_available", name: "available",
      changes: [ { inventoryItemId: gid_item, locationId: gid_loc, quantity: 4, compareQuantity: 4 } ]
    } })
    payload = response.parsed_body.dig("data", "inventorySetQuantities")
    expect(payload["userErrors"]).to eq([])
    group = payload["inventoryAdjustmentGroup"]
    expect(group["changesCount"]).to eq(0)
    expect(group["changes"]).to eq([])
    expect(InventoryAdjustment.unscoped.where(shop_id: shop.id).count).to eq(1)  # 只有 seed 那列
  end

  it "RequiredMutations 大小寫正規化（平台級修）：PascalCase 的 graphql_name 也命中清單" do
    expect(Idempotency::RequiredMutations.required?("InventoryAdjustQuantities")).to be(true)
    expect(Idempotency::RequiredMutations.required?("inventoryAdjustQuantities")).to be(true)
    expect(Idempotency::RequiredMutations.required?("ProductSet")).to be(false)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
