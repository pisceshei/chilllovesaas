# frozen_string_literal: true

require "rails_helper"

# G6-8（步 5）：出貨線三支 mutation（fulfillmentCreate／TrackingInfoUpdate／Cancel）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   F1 全量出貨（殺：fulfillable 不遞減／FO 不 closed／badge 不推導）
#   F2 部分出貨（殺：partially_fulfilled 推導）
#   F3 超量 INVALID（殺：可出量上界拔除）
#   F4 出貨釋放 committed（殺：庫存承諾洩漏——16 驗收「cancel 後庫存恆等式」的正向半邊）
#   F5 cancel 全反向（殺：回加缺一樣）
#   F6 已取消訂單不能出貨
#   F7 跨店 NOT_FOUND
RSpec.describe "fulfillment lifecycle", type: :request do
  let(:shop) { create(:shop, subdomain: "fful" ) }
  let!(:staff) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }

  before do
    host! "fful.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  # 帶行項＋tracked 庫存＋FO 的訂單（模擬建單後狀態：available 已扣、committed 已加）。
  def build_order(number:, quantities: [ 2, 1 ])
    ActsAsTenant.with_tenant(shop) do
      order = Order.create!(
        shop_id: shop.id, name: "##{number}", order_number: number, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 10_000, total_cents: 10_000,
        presentment_total_cents: 10_000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current,
        captured_total_cents: 10_000
      )
      quantities.each_with_index do |qty, i|
        variant = create(:product_variant, shop:)
        level = variant.inventory_item.inventory_levels.first!
        ActsAsTenant.without_tenant do
          InventoryLevel.where(id: level.id)
                        .update_all([ "committed = committed + ?, available = available - ?", qty, qty ])
        end
        LineItem.create!(shop_id: shop.id, order_id: order.id, title: "行#{i + 1}",
                         product_variant_id: variant.id, quantity: qty, fulfillable_quantity: qty,
                         unit_price_cents: 1000, total_cents: 1000 * qty, currency: "HKD")
      end
      location = Location.where(shop_id: shop.id).order(priority: :desc, id: :asc).first!
      FulfillmentOrder.create!(shop_id: shop.id, order_id: order.id, location_id: location.id,
                               status: "open", request_status: "unsubmitted")
      order
    end
  end

  def fo_gid(order)
    fo = ActsAsTenant.without_tenant { order.fulfillment_orders.order(:id).first! }
    "gid://chilllove/FulfillmentOrder/#{fo.id}"
  end

  def gql(query, variables)
    post admin_graphql_path, params: { query:, variables: }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  # 🔴 常數名帶檔案前綴：RSpec.describe 的 block 沒有 lexical class scope，
  #   這裡的常數定義落在 Object 頂層——與 external_video_media_spec 的 CREATE
  #   撞名時後載入者覆蓋先載入者，兩檔變成雙向順序依賴（全套紅、單獨綠）。
  #   本包實踩：data.fulfillmentCreate 恆 nil（送出去的是別檔的 mediaCreate query）。
  FULFILL_CREATE_GQL = <<~GQL
    mutation($fulfillment: FulfillmentInput!) {
      fulfillmentCreate(fulfillment: $fulfillment) {
        fulfillment { id status trackingCompany trackingInfo { number url } lineItems { quantity } }
        userErrors { field message code }
      }
    }
  GQL

  def create_fulfillment(order, line_items: nil, tracking: nil, notify: false)
    input = { lineItemsByFulfillmentOrder: [ { fulfillmentOrderId: fo_gid(order) } ], notifyCustomer: notify }
    input[:lineItemsByFulfillmentOrder][0][:fulfillmentOrderLineItems] = line_items if line_items
    input[:trackingInfo] = tracking if tracking
    gql(FULFILL_CREATE_GQL, { fulfillment: input })
  end

  def committed_sum(order)
    ActsAsTenant.without_tenant do
      variant_ids = order.line_items.pluck(:product_variant_id).compact
      item_ids = InventoryItem.where(product_variant_id: variant_ids).pluck(:id)
      InventoryLevel.where(inventory_item_id: item_ids).sum(:committed)
    end
  end

  it "F1 全量出貨：fulfillable 歸零、FO closed、badge FULFILLED、committed 釋放、event＋outbox" do
    order = build_order(number: 8001)
    expect(committed_sum(order)).to eq(3)

    payload = create_fulfillment(order, tracking: { company: "SF Express", number: "SF123", url: "https://sf.example/123" })
    expect(payload.dig("data", "fulfillmentCreate", "userErrors")).to eq([])
    f = payload.dig("data", "fulfillmentCreate", "fulfillment")
    expect(f["status"]).to eq("success")
    expect(f["trackingCompany"]).to eq("SF Express")
    expect(f["trackingInfo"]).to eq([ { "number" => "SF123", "url" => "https://sf.example/123" } ])

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.fulfillment_status).to eq("fulfilled")
      expect(order.line_items.sum(:fulfillable_quantity)).to eq(0)
      expect(order.fulfillment_orders.sole.status).to eq("closed")
      expect(Event.where(order_id: order.id, kind: "order.fulfilled").count).to eq(1)
      expect(EventOutbox.where(aggregate_id: order.id, topic: Events::Topics::ORDER_FULFILLED).count).to eq(1)
    end
    expect(committed_sum(order)).to eq(0)
  end

  it "F2 部分出貨 ⇒ partially_fulfilled、FO 留 open" do
    order = build_order(number: 8002)
    line = ActsAsTenant.without_tenant { order.line_items.order(:id).first! }

    payload = create_fulfillment(order,
      line_items: [ { id: "gid://chilllove/LineItem/#{line.id}", quantity: 1 } ])
    expect(payload.dig("data", "fulfillmentCreate", "userErrors")).to eq([])

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.fulfillment_status).to eq("partially_fulfilled")
      expect(order.fulfillment_orders.sole.status).to eq("open")
      expect(line.reload.fulfillable_quantity).to eq(1)
    end
    expect(committed_sum(order)).to eq(2)
  end

  it "F3 超量 ⇒ INVALID 且整批不寫（第二行也不動）" do
    order = build_order(number: 8003)
    l1, l2 = ActsAsTenant.without_tenant { order.line_items.order(:id).to_a }

    payload = create_fulfillment(order, line_items: [
      { id: "gid://chilllove/LineItem/#{l2.id}", quantity: 1 },
      { id: "gid://chilllove/LineItem/#{l1.id}", quantity: 3 }
    ])
    expect(payload.dig("data", "fulfillmentCreate", "userErrors", 0, "code")).to eq("INVALID")

    ActsAsTenant.with_tenant(shop) do
      expect(order.line_items.sum(:fulfillable_quantity)).to eq(3)
      expect(Fulfillment.joins(:fulfillment_order)
                        .where(fulfillment_orders: { order_id: order.id }).count).to eq(0)
    end
    expect(committed_sum(order)).to eq(3)
  end

  it "F5 cancel 全反向：fulfillable 回加、committed 回加、FO 翻回 open、badge 回 unfulfilled" do
    order = build_order(number: 8004)
    payload = create_fulfillment(order)
    fid = payload.dig("data", "fulfillmentCreate", "fulfillment", "id")
    expect(committed_sum(order)).to eq(0)

    cancel = gql(<<~GQL, { id: fid })
      mutation($id: ID!) {
        fulfillmentCancel(id: $id) {
          fulfillment { status }
          userErrors { field message code }
        }
      }
    GQL
    expect(cancel.dig("data", "fulfillmentCancel", "userErrors")).to eq([])
    expect(cancel.dig("data", "fulfillmentCancel", "fulfillment", "status")).to eq("cancelled")

    ActsAsTenant.with_tenant(shop) do
      expect(order.reload.fulfillment_status).to eq("unfulfilled")
      expect(order.line_items.sum(:fulfillable_quantity)).to eq(3)
      expect(order.fulfillment_orders.sole.status).to eq("open")
    end
    expect(committed_sum(order)).to eq(3)

    again = gql(<<~GQL, { id: fid })
      mutation($id: ID!) {
        fulfillmentCancel(id: $id) { userErrors { code } }
      }
    GQL
    expect(again.dig("data", "fulfillmentCancel", "userErrors", 0, "code")).to eq("INVALID_STATE")
  end

  it "F5b trackingInfoUpdate 整組取代" do
    order = build_order(number: 8005)
    payload = create_fulfillment(order, tracking: { company: "SF Express", number: "OLD-1" })
    fid = payload.dig("data", "fulfillmentCreate", "fulfillment", "id")

    updated = gql(<<~GQL, { fulfillmentId: fid, trackingInfoInput: { company: "HKPost", numbers: [ "NEW-1", "NEW-2" ], urls: [ "https://hkpost.example/1" ] } })
      mutation($fulfillmentId: ID!, $trackingInfoInput: FulfillmentTrackingInput!) {
        fulfillmentTrackingInfoUpdate(fulfillmentId: $fulfillmentId, trackingInfoInput: $trackingInfoInput) {
          fulfillment { trackingCompany trackingInfo { number url } }
          userErrors { field message code }
        }
      }
    GQL
    expect(updated.dig("data", "fulfillmentTrackingInfoUpdate", "userErrors")).to eq([])
    f = updated.dig("data", "fulfillmentTrackingInfoUpdate", "fulfillment")
    expect(f["trackingCompany"]).to eq("HKPost")
    expect(f["trackingInfo"]).to eq([
      { "number" => "NEW-1", "url" => "https://hkpost.example/1" },
      { "number" => "NEW-2", "url" => nil }
    ])
  end

  it "F6 已取消的訂單不能出貨" do
    order = build_order(number: 8006)
    ActsAsTenant.without_tenant { Order.where(id: order.id).update_all(status: "cancelled") }

    payload = create_fulfillment(order)
    expect(payload.dig("data", "fulfillmentCreate", "userErrors", 0, "code")).to eq("INVALID_STATE")
  end

  it "F7 跨店 FO ⇒ NOT_FOUND（鐵律 2）" do
    other = create(:shop, subdomain: "fful-other")
    other_order = ActsAsTenant.with_tenant(other) do
      o = Order.create!(
        shop_id: other.id, name: "#1", order_number: 1, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 100, total_cents: 100,
        presentment_total_cents: 100, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {}, processed_at: Time.current
      )
      location = Location.where(shop_id: other.id).first!
      FulfillmentOrder.create!(shop_id: other.id, order_id: o.id, location_id: location.id,
                               status: "open", request_status: "unsubmitted")
      o
    end

    payload = create_fulfillment(other_order)
    expect(payload.dig("data", "fulfillmentCreate", "userErrors", 0, "code")).to eq("NOT_FOUND")
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  it "F8 on_hold 的 FO 不能出貨（官方 ON_HOLD 語義）" do
    order = build_order(number: 8008)
    ActsAsTenant.without_tenant do
      FulfillmentOrder.where(order_id: order.id).update_all(status: "on_hold")
    end

    payload = create_fulfillment(order)
    expect(payload.dig("data", "fulfillmentCreate", "userErrors", 0, "code")).to eq("INVALID_STATE")
  end
end
