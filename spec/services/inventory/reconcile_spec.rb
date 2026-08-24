# frozen_string_literal: true

require "rails_helper"

# 排程第 17 包：對帳＝漂移偵測（cop 擋新增的繞過、對帳抓歷史的與 SQL 層的）。
RSpec.describe Inventory::Reconcile do
  let(:shop) { create(:shop, subdomain: "reconcile-shop") }
  let(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
  let(:item) { ActsAsTenant.with_tenant(shop) { variant.inventory_item } }
  let(:location) { ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).first! } }
  let(:level) { ActsAsTenant.with_tenant(shop) { item.inventory_levels.first! } }

  def adjust!(key:, delta:)
    result = Inventory::Adjust.call(shop:, mode: "adjust", input: {
      idempotency_key: key, reason: "received", name: "available",
      changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                   location_id: "gid://chilllove/Location/#{location.id}", delta: } ]
    })
    expect(result.user_errors).to eq([])
    result
  end

  it "走唯一入口的帳恆平；SQL 層直寫的漂移被逐欄抓出" do
    adjust!(key: "r1", delta: 7)
    adjust!(key: "r2", delta: -2)
    expect(described_class.call(shop:)).to eq([])

    # 模擬繞過入口的直寫（spec 不在 cop 掃描範圍——cop 守生產代碼，這裡正是要製造事故）
    ActiveRecord::Base.connection.execute("UPDATE inventory_levels SET available = 99 WHERE id = #{level.id}")
    discrepancies = described_class.call(shop:)
    expect(discrepancies.length).to eq(1)
    expect(discrepancies.first.kind).to eq("leaf_mismatch")
    expect(discrepancies.first.detail).to include("current=99").and include("ledger_sum=5")
  end

  it "changes_count 快取欄與實際子行數不符時被抓出" do
    adjust!(key: "r3", delta: 1)
    group = InventoryAdjustmentGroup.unscoped.where(shop_id: shop.id).first!
    ActiveRecord::Base.connection.execute("UPDATE inventory_adjustment_groups SET changes_count = 5 WHERE id = #{group.id}")
    discrepancies = described_class.call(shop:)
    expect(discrepancies.map(&:kind)).to include("changes_count_mismatch")
  end
end
