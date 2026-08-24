# frozen_string_literal: true

require "rails_helper"

# 排程第 16 包：商品列表的 totalInventory（鐵律 7 同源 rollup ＋ 不逐列 SUM）。
RSpec.describe "Admin GraphQL products totalInventory", type: :request do
  let(:shop) { create(:shop, subdomain: "total-inv-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end

  before do
    host! "total-inv-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  def list_totals
    post admin_graphql_path,
         params: { query: "{ products(first: 10) { nodes { title totalInventory } } }" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("data", "products", "nodes").to_h { |row| [ row["title"], row["totalInventory"] ] }
  end

  it "真實件數：跨變體、跨地點加總；未追蹤回 null 而不是 0（兩個真相不得合併）" do
    tracked = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "有貨品", created_at: 3.minutes.ago) }
    untracked = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "未追蹤品", created_at: 2.minutes.ago) }
    zero = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "零庫存品", created_at: 1.minute.ago) }

    ActsAsTenant.with_tenant(shop) do
      v1 = create(:product_variant, shop:, product: tracked)
      second_loc = Location.create!(shop_id: shop.id, name: "Warehouse B")
      v1.inventory_item.inventory_levels.order(:id).first!.update_columns(available: 5)
      v1.inventory_item.inventory_levels.find_by!(location_id: second_loc.id).update_columns(available: 4)

      v2 = create(:product_variant, shop:, product: untracked)
      v2.inventory_item.update!(tracked: false)
      v2.inventory_item.inventory_levels.order(:id).first!.update_columns(available: 88) # 未追蹤 ⇒ 不得計入

      create(:product_variant, shop:, product: zero) # 全 0
    end

    totals = list_totals
    # 隱含變體（factory product 自帶？）——斷言以顯式建立的為準
    expect(totals.fetch("有貨品")).to eq(9)
    expect(totals.fetch("未追蹤品")).to be_nil
    expect(totals.fetch("零庫存品")).to eq(0)
  end

  it "🔴 列表不逐列 SUM：本功能的 SUM 子查詢恰好一次（select 一次帶出；回歸時=列數）" do
    3.times do |index|
      product = ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "P#{index}") }
      ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product:) }
    end

    # 🔴 正向計數而不是空集斷言（2026-08-24 對抗審查抓到：舊謂詞 /\ASELECT SUM\(/
    # 錨定行首，列表主查詢與逐列 fallback 的 SQL 都不以它開頭 ⇒ 有無回歸兩態恆綠。
    # 驗證方把回歸真的注入（移除 query_type 的 .select）測試仍綠——空集斷言測不到缺席。
    # 改成：含本功能子查詢指紋的 SQL 恰好 1 次（列表主查詢一次帶出）；
    # 回歸時 fallback 逐列跑 ⇒ 計數＝列數 ⇒ 紅。
    sums = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      sums << payload[:sql] if payload[:sql].to_s.match?(/SUM\(il\.available\)/i)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      post admin_graphql_path,
           params: { query: "{ products(first: 10) { nodes { title totalInventory } } }" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end
    expect(response.parsed_body.dig("data", "products", "nodes").length).to eq(3)
    expect(sums.length).to eq(1)
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end
end
