# frozen_string_literal: true

require "rails_helper"

# G6 步 10：analyticsOverview（19-F2.3；G25 例外的查詢端釘子）。
#
# 🔴 假綠殺手：
#   O2 AOV 獨立分子（殺：用 total_sales/orders 反推——退款日兩者背離；
#      19-F1 必測⑤明文「不得斷言相等」——本格反向斷言「就是不等」）
RSpec.describe "analyticsOverview", type: :request do
  let(:shop) { create(:shop, subdomain: "aovq", timezone: "Asia/Hong_Kong") }
  let!(:owner) { ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) } }
  let(:tz) { ActiveSupport::TimeZone["Asia/Hong_Kong"] }

  before do
    host! "aovq.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    post login_path, params: { email: owner.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end

  def gql!(query, variables = {})
    post admin_graphql_path, params: { query:, variables: }.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  AOVQ_GQL = <<~GQL
    query($from: ISO8601Date!, $to: ISO8601Date!) {
      analyticsOverview(from: $from, to: $to) {
        totalSalesCents netSalesCents ordersCount aovCents returnsCents
        series { date totalSalesCents }
      }
    }
  GQL

  it "🔴 O1/O2 卡片聚合＋退款期間 AOV×Orders ≠ Total sales（官方例外成立）" do
    order = ActsAsTenant.with_tenant(shop) do
      o = Order.create!(
        shop_id: shop.id, name: "#Q1", order_number: 8801, currency: "HKD",
        presentment_currency: "HKD", subtotal_cents: 10_000, total_cents: 10_000,
        presentment_total_cents: 10_000, financial_status: "paid",
        fulfillment_status: "unfulfilled", status: "open",
        seller_jurisdiction: "hk", buyer_jurisdiction: "hk",
        shipping_address: {}, billing_address: {},
        processed_at: tz.parse("2026-09-10 12:00")
      )
      Refund.create!(shop_id: shop.id, order_id: o.id, status: "success",
                     total_cents: 4000, shipping_cents: 0, currency: "HKD",
                     idempotency_key: "q1", processed_at: tz.parse("2026-09-10 15:00"))
      o
    end
    ActsAsTenant.with_tenant(shop) do
      Analytics::RollupDaily.call(shop:, date: Date.new(2026, 9, 10))
    end

    payload = gql!(AOVQ_GQL, { from: "2026-09-10", to: "2026-09-10" })
    data = payload.dig("data", "analyticsOverview")
    expect(data["ordersCount"]).to eq(1)
    expect(data["returnsCents"]).to eq(4000)
    expect(data["totalSalesCents"]).to eq(6000) # 10000 − 4000
    expect(data["aovCents"]).to eq(10_000)      # 分子＝subtotal（此單無運無稅 ⇒ 同 total）；不含退款
    expect(data["aovCents"] * data["ordersCount"]).not_to eq(data["totalSalesCents"]),
      "兩者相等＝AOV 被反推——G25 例外崩了"
    expect(data["series"]).to eq([ { "date" => "2026-09-10", "totalSalesCents" => 6000 } ])
    _ = order
  end

  it "空期間 ⇒ 全 0＋空 series（不給 0 假線——19-F2.3）" do
    payload = gql!(AOVQ_GQL, { from: "2025-01-01", to: "2025-01-07" })
    data = payload.dig("data", "analyticsOverview")
    expect(data["totalSalesCents"]).to eq(0)
    expect(data["aovCents"]).to eq(0)
    expect(data["series"]).to eq([])
  end
end
