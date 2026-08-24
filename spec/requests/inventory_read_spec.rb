# frozen_string_literal: true

require "rails_helper"

# 排程第 18 包的讀取面（`docs/plans/2026-08-24-第18包執行規格.md` §4a／§6-1）。
RSpec.describe "Admin GraphQL inventory read surface", type: :request do
  let(:shop) { create(:shop, subdomain: "inv-read-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "帆布托特包") } }
  let(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product:, sku: "TOTE-01") } }
  let(:item) { ActsAsTenant.with_tenant(shop) { variant.inventory_item } }
  let(:main) { ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).order(:priority, :id).first! } }
  let(:level) { ActsAsTenant.with_tenant(shop) { item.inventory_levels.find_by!(location_id: main.id) } }

  LIST = <<~GRAPHQL
    query list($loc: ID, $q: String) {
      inventoryItems(first: 10, locationId: $loc, query: $q) {
        nodes {
          id sku tracked productTitle variantTitle locationId
          quantities { unavailable committed available onHand incoming }
        }
        pageInfo { hasNextPage }
      }
    }
  GRAPHQL

  HISTORY = <<~GRAPHQL
    query hist($item: ID!, $loc: ID) {
      inventoryHistory(inventoryItemId: $item, locationId: $loc) {
        id reason mutationKind createdBy referenceDocumentUri ledgerDocumentUri
        changes { name delta quantityAfterChange }
      }
    }
  GRAPHQL

  before do
    host! "inv-read-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def adjust!(delta:, key:, reason: "received", name: "available")
    result = Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: key, reason:, name:,
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{main.id}", delta: } ]
    }, staff:)
    expect(result.user_errors).to eq([])
    result
  end

  def list(**vars)
    post_graphql(LIST, variables: vars)
    response.parsed_body.dig("data", "inventoryItems", "nodes")
  end

  it "列表：五個數量欄一次帶出；unavailable 與 onHand 是 DB 導出值" do
    adjust!(delta: 12, key: "l1")
    Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: "l2", reason: "damaged", name: "damaged",
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{main.id}", delta: 3,
                   ledger_document_uri: "app://damage/1" } ]
    }, staff:)

    node = list.first
    expect(node["sku"]).to eq("TOTE-01")
    expect(node["productTitle"]).to eq("帆布托特包")
    expect(node["tracked"]).to be(true)
    expect(node["locationId"]).to eq("gid://chilllove/Location/#{main.id}")
    expect(node["quantities"]).to eq(
      "unavailable" => 3, "committed" => 0, "available" => 12, "onHand" => 15, "incoming" => 0
    )
  end

  it "🔴 列表不逐列查 level：JOIN 指紋的查詢恰一次（正向計數，不是空集斷言）" do
    item   # 顯式實例化（let 是 lazy 的；不碰它列數就只有下面那三筆）
    3.times do |index|
      p = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "P#{index}") }
      ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product: p) }
    end

    joins = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      joins << payload[:sql] if payload[:sql].to_s.match?(/level_available/i)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { list }
    expect(response.parsed_body.dig("data", "inventoryItems", "nodes").length).to eq(4)
    expect(joins.length).to eq(1)
  end

  it "地點：省略＝預設地點；指定第二地點回該地點數量；跨店 GID 回空集" do
    adjust!(delta: 5, key: "loc1")
    second = ActsAsTenant.with_tenant(shop) { Location.create!(shop_id: shop.id, name: "Warehouse B") }

    expect(list.first.dig("quantities", "available")).to eq(5)
    other_rows = list(loc: "gid://chilllove/Location/#{second.id}")
    expect(other_rows.first.dig("quantities", "available")).to eq(0)   # 新地點是 0，不是 5

    foreign = create(:shop, subdomain: "other-read-shop")
    foreign_loc = ActsAsTenant.with_tenant(foreign) { Location.where(shop_id: foreign.id).first! }
    expect(list(loc: "gid://chilllove/Location/#{foreign_loc.id}")).to eq([])
  end

  it "搜尋：商品標題／SKU 命中；LIKE 萬用字元跳脫" do
    variant
    other = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "100% cotton tee") }
    ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product: other, sku: "TEE-01") }

    expect(list(q: "托特").map { |n| n["productTitle"] }).to eq([ "帆布托特包" ])
    expect(list(q: "TOTE").map { |n| n["sku"] }).to eq([ "TOTE-01" ])
    expect(list(q: "0%").map { |n| n["productTitle"] }).to eq([ "100% cotton tee" ])
  end

  it "🔴 第八式：歷程的 quantityAfterChange 逐列正確，最後一列＝levels 現值" do
    adjust!(delta: 10, key: "h1")
    adjust!(delta: -4, key: "h2")
    adjust!(delta: 7, key: "h3")

    post_graphql(HISTORY, variables: { item: "gid://chilllove/InventoryItem/#{item.id}" })
    rows = response.parsed_body.dig("data", "inventoryHistory")
    expect(rows.length).to eq(3)

    # 新→舊；available 的 running total 應為 13 / 6 / 10
    available_after = rows.map { |row| row.fetch("changes").find { |c| c["name"] == "available" }["quantityAfterChange"] }
    expect(available_after).to eq([ 13, 6, 10 ])
    # 最新一列的期後值＝現值（第八式的本體）
    expect(available_after.first).to eq(level.reload.available)
    # 調 available 同時投影 on_hand（本尊語義）
    expect(rows.first.fetch("changes").map { |c| c["name"] }).to contain_exactly("available", "on_hand")
  end

  it "歷程列的稽核欄：reason 回識別字（非翻譯）、createdBy、參考文件" do
    Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: "aud1", reason: "cycle_count_available", name: "damaged",
      reference_document_uri: "app://count/2026-08",
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{main.id}", delta: 2,
                   ledger_document_uri: "app://ledger/9" } ]
    }, staff:)

    post_graphql(HISTORY, variables: { item: "gid://chilllove/InventoryItem/#{item.id}" })
    row = response.parsed_body.dig("data", "inventoryHistory", 0)
    expect(row["reason"]).to eq("cycle_count_available")   # 識別字，標籤由前端 i18n
    expect(row["mutationKind"]).to eq("adjust")
    expect(row["createdBy"]).to eq(staff.email)
    expect(row["referenceDocumentUri"]).to eq("app://count/2026-08")
    expect(row["ledgerDocumentUri"]).to eq("app://ledger/9")
    # damaged 調整同時投影 unavailable 與 on_hand
    expect(row.fetch("changes").map { |c| c["name"] }).to contain_exactly("unavailable", "on_hand")
  end

  it "歷程：保留窗外的列不回，但期後值仍以全期 running sum 計（開窗在過濾之前）" do
    adjust!(delta: 100, key: "old1")
    # 把第一列推到保留窗之外
    retention = Limits.fetch(:inventory, :adjustment_history_retention_days).to_i
    ActiveRecord::Base.connection.execute(
      "UPDATE inventory_adjustments SET created_at = NOW(6) - INTERVAL #{retention + 5} DAY WHERE shop_id = #{shop.id}"
    )
    adjust!(delta: 5, key: "new1")

    post_graphql(HISTORY, variables: { item: "gid://chilllove/InventoryItem/#{item.id}" })
    rows = response.parsed_body.dig("data", "inventoryHistory")
    expect(rows.length).to eq(1)   # 窗外那列不回
    after = rows.first.fetch("changes").find { |c| c["name"] == "available" }["quantityAfterChange"]
    # 🔴 105 而不是 5——running sum 含窗外的歷史。若開窗在過濾之後，這裡會是 5（每列偏移）
    expect(after).to eq(105)
    expect(after).to eq(level.reload.available)
  end

  it "locations：priority 序；租戶隔離" do
    ActsAsTenant.with_tenant(shop) { Location.create!(shop_id: shop.id, name: "Z 倉", priority: 5) }
    foreign = create(:shop, subdomain: "loc-other-shop")
    ActsAsTenant.with_tenant(foreign) { Location.create!(shop_id: foreign.id, name: "別店倉") }

    post_graphql("{ locations { id name active } }")
    names = response.parsed_body.dig("data", "locations").map { |l| l["name"] }
    expect(names).to eq([ Limits.fetch(:inventory, :default_location_name), "Z 倉" ])
    expect(names).not_to include("別店倉")
  end

  # ── 對抗式複查（2026-08-24）補的守衛 ─────────────────────────────────
  #
  # 🔴 這三條都是「**缺席的測試**」，不是既有測試的加強。
  # 複查指出：整份 spec 全程以 owner 登入，`authorize_inventory!` 的**拒絕分支
  # 零覆蓋**——把整個授權閘刪掉，原本的測試會全綠。

  it "authorize_inventory!：無 inventory.view 的員工三支查詢全部被拒（拒絕分支存在）" do
    # 非 owner 且無指派 ⇒ `can?` 回 false（見 StaffMember#can?）
    weak = ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: false) }
    delete logout_path
    post login_path, params: { email: weak.email, password: "long-password-123" }

    [ [ LIST, {} ],
      [ HISTORY, { item: "gid://chilllove/InventoryItem/#{item.id}" } ],
      [ "{ locations { id } }", {} ] ].each do |query, vars|
      post_graphql(query, variables: vars)
      codes = response.parsed_body["errors"].to_a.map { |e| e.dig("extensions", "code") }
      expect(codes).to include("ACCESS_DENIED"), "查詢未被拒：#{query[0, 40]}"
    end
  end

  it "🔴 on_hand 調整免附 ledgerDocumentUri（2026-08-24 裁定的 ours 放寬）" do
    # 本尊語義是「除 available 外全部必填」（95 §4）。我方對 on_hand 刻意放寬，
    # 理由：on_hand 在我方模型翻譯成 available leaf，且手動盤點沒有文件可附。
    # 放寬前這個入口 100% 失敗（實測回 INVALID_QUANTITY_DOCUMENT）。
    result = Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: "onhand-nodoc", reason: "correction", name: "on_hand",
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{main.id}", delta: 4 } ]
    }, staff:)
    expect(result.user_errors).to eq([])

    # 🔴 放寬只給 on_hand：其餘 name 仍必附，否則這條測試就變成「全部放寬」的橡皮圖章
    strict = Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: "damaged-nodoc", reason: "damaged", name: "damaged",
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{main.id}", delta: 1 } ]
    }, staff:)
    expect(strict.user_errors.map { |e| e[:code] }).to eq([ "INVALID_QUANTITY_DOCUMENT" ])
  end

  it "歷程的 createdBy 批次查 email：整頁只打一次 staff_members" do
    3.times { |i| adjust!(delta: 1, key: "batch-#{i}") }

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] if payload[:sql].include?("staff_members")
    end
    post_graphql(HISTORY, variables: { item: "gid://chilllove/InventoryItem/#{item.id}" })
    ActiveSupport::Notifications.unsubscribe(subscriber)

    rows = response.parsed_body.dig("data", "inventoryHistory")
    expect(rows.length).to be >= 3
    # 正向計數：撈 email 的那一句恰好一次（不是「沒有 N+1」這種空集斷言）
    email_selects = queries.count { |q| q.match?(/SELECT.*staff_members.*email|email.*FROM .staff_members./i) }
    expect(email_selects).to eq(1), "staff_members email 查了 #{email_selects} 次：#{queries.inspect}"
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def post_graphql(query, variables: {})
    post admin_graphql_path, params: { query:, variables: }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
