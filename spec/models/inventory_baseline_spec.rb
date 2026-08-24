# frozen_string_literal: true

require "rails_helper"

# 排程第 16 包的三個自動化機制（全部是 callback ＝ 機制，不是服務層紀律）。
# 不變量：每店 ≥1 地點；每變體恰一 item；每 (item × 同店地點) 恰一列 level。
RSpec.describe "inventory baseline mechanisms", type: :model do
  let(:shop) { create(:shop, subdomain: "inv-baseline-shop") }

  it "建店即建預設地點，名稱引 limits（鐵律 6），且同店重名被唯一索引擋" do
    location = ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).first! }
    expect(location.name).to eq(Limits.fetch(:inventory, :default_location_name))

    expect {
      ActsAsTenant.with_tenant(shop) { Location.create!(shop_id: shop.id, name: location.name) }
    }.to raise_error(ActiveRecord::RecordInvalid, /taken|已經被使用/i)
  end

  it "變體出生即建 inventory_item（63 §B.5 身分同生）＋ 每地點一列 0 量 level" do
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }

    ActsAsTenant.with_tenant(shop) do
      item = variant.inventory_item
      expect(item).to be_present
      expect(item.tracked).to be(true)
      expect(item.sku).to eq(variant.sku)

      levels = item.inventory_levels
      expect(levels.count).to eq(Location.where(shop_id: shop.id).count)
      expect(levels.map(&:available)).to all(eq(0))
      expect(levels.map(&:on_hand)).to all(eq(0))
    end
  end

  it "新地點建立即為既有品項補 level（反方向機制）；兩方向合起來不變量完整" do
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }

    ActsAsTenant.with_tenant(shop) do
      second = Location.create!(shop_id: shop.id, name: "Warehouse B")
      item = variant.inventory_item

      expect(item.inventory_levels.where(location_id: second.id).count).to eq(1)
      # 不變量全稱式：item × 同店地點 的每一格都有恰一列
      expect(item.inventory_levels.count).to eq(Location.where(shop_id: shop.id).count)
    end
  end

  it "ledger 子行 append-only：持久列的 update 與 destroy 一律 ReadOnlyRecord" do
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }
    ActsAsTenant.with_tenant(shop) do
      level = variant.inventory_item.inventory_levels.first!
      group = InventoryAdjustmentGroup.create!(
        shop_id: shop.id, idempotency_key: "ro-test", quantity_name: "available",
        reason: "received", mutation_kind: "adjust"
      )
      row = InventoryAdjustment.create!(
        shop_id: shop.id, inventory_adjustment_group_id: group.id,
        inventory_level_id: level.id, available_delta: 1
      )
      expect { row.update!(available_delta: 2) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { row.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  # 🔴 刪除語義的現況釘板（2026-08-24 對抗審查後裁定；三選一屬排程第 20 包）：
  # ledger 是 append-only 稽核資料，FK RESTRICT＝fail-closed——有 ledger 歷史的商品／地點
  # **刻意刪不掉**。這條測試把現況釘住：第 20 包裁定改變行為時它會轉紅，逼人回來讀這段。
  it "有 ledger 歷史時 product.destroy 與 location.destroy 被 FK 擋下（fail-closed 至第 20 包）" do
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) }
    ActsAsTenant.with_tenant(shop) do
      level = variant.inventory_item.inventory_levels.first!
      group = InventoryAdjustmentGroup.create!(
        shop_id: shop.id, idempotency_key: "restrict-test", quantity_name: "available",
        reason: "received", mutation_kind: "adjust"
      )
      InventoryAdjustment.create!(
        shop_id: shop.id, inventory_adjustment_group_id: group.id,
        inventory_level_id: level.id, available_delta: 1
      )
      expect { variant.product.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
      expect { level.location.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
      # 沒有 ledger 歷史的可以刪（對照組）——證明擋的是稽核資料，不是刪除本身
      clean = create(:product_variant, shop:)
      expect { clean.product.destroy! }.not_to raise_error
    end
  end

  it "group 的 reason／quantity_name 值域引 limits（鐵律 6）：非法值被模型層擋" do
    ActsAsTenant.with_tenant(shop) do
      group = InventoryAdjustmentGroup.new(
        shop_id: shop.id, idempotency_key: "enum-test", quantity_name: "bogus",
        reason: "not_a_reason", mutation_kind: "adjust"
      )
      expect(group).not_to be_valid
      expect(group.errors.attribute_names).to include(:reason, :quantity_name)
      # 17 值全集與 UI 7 值子集是同一份值域的兩個投影（95 §3）
      expect(InventoryAdjustmentGroup::REASONS).to include("movement_canceled", "cycle_count_available")
    end
  end
end
