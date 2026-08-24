# frozen_string_literal: true

require "rails_helper"

# 第 20 包（整合規格 §4-20／B1 方案②）：變體刪除唯一路徑。
# 13:64-72 T-1 語義：刪被訂單引用的變體成功、訂單快照不變；ledger 列數不減。
RSpec.describe Catalog::DeleteVariant do
  let!(:shop) { create(:shop, subdomain: "delvar-shop") }
  let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
  let!(:product) { ActsAsTenant.without_tenant { variant.product } }
  # 多變體必有選項座標（D12 不變量；digest 由 before_validation 從座標重算，
  # 直接塞 digest 會被覆蓋）——setup 造「尺寸／S·M·L」三值，逐變體掛真座標。
  let!(:size_option) do
    ActsAsTenant.with_tenant(shop) do
      ProductOption.create!(shop_id: shop.id, product_id: product.id, name: "尺寸", position: 1)
    end
  end
  let!(:size_values) do
    ActsAsTenant.with_tenant(shop) do
      %w[S M L].each_with_index.map do |v, i|
        OptionValue.create!(shop_id: shop.id, product_option_id: size_option.id, value: v, position: i + 1)
      end
    end
  end
  def coordinate!(target, value)
    ActsAsTenant.with_tenant(shop) do
      target.product_variant_option_values.build(
        shop_id: shop.id, product_id: product.id,
        product_option_id: size_option.id, option_value_id: value.id)
      target.save!
    end
  end
  let!(:second) do
    ActsAsTenant.with_tenant(shop) do
      coordinate!(variant, size_values[0])
      v = ProductVariant.new(shop_id: shop.id, product_id: product.id,
                             title: "第二變體", position: 902, currency: shop.store_currency)
      v.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
        product_option_id: size_option.id, option_value_id: size_values[1].id)
      v.save!
      v
    end
  end

  def call!(target) = ActsAsTenant.with_tenant(shop) { described_class.call(shop:, variant: target) }

  it "商品只剩最低變體數時拒刪（LAST_VARIANT_REQUIRED；引 limits 不硬編）" do
    expect(call!(second).deleted).to be true
    result = call!(variant.reload)
    expect(result.deleted).to be false
    expect(result.user_errors.sole[:code]).to eq("LAST_VARIANT_REQUIRED")
    expect(ProductVariant.unscoped.where(product_id: product.id).count)
      .to eq(Limits.fetch(:catalog_flow, :product_min_variants))
  end

  it "刪被 line_items 引用的變體成功、訂單快照不變（13 T-1）" do
    order_id, li_id = ActsAsTenant.without_tenant do
      conn = ActiveRecord::Base.connection
      conn.exec_insert(ActiveRecord::Base.sanitize_sql([
        "INSERT INTO orders (shop_id, name, order_number, buyer_jurisdiction, seller_jurisdiction, created_at, updated_at) VALUES (?, 'T-1', 1, 'HK', 'HK', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))", shop.id ]))
      oid = conn.select_value("SELECT LAST_INSERT_ID()")
      conn.exec_insert(ActiveRecord::Base.sanitize_sql([
        "INSERT INTO line_items (shop_id, order_id, product_variant_id, title, variant_title, sku, unit_price_cents, quantity, total_cents, created_at, updated_at)
         VALUES (?, ?, ?, '帽T', '第二變體', 'SKU-X', 12800, 1, 12800, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))", shop.id, oid, second.id ]))
      [ oid, conn.select_value("SELECT LAST_INSERT_ID()") ]
    end

    expect(call!(second).deleted).to be true

    row = ActsAsTenant.without_tenant do
      ActiveRecord::Base.connection.select_one(
        "SELECT product_variant_id, title, variant_title, sku, unit_price_cents FROM line_items WHERE id = #{li_id.to_i}")
    end
    expect(row["product_variant_id"]).to be_nil
    expect(row.values_at("title", "variant_title", "sku", "unit_price_cents"))
      .to eq([ "帽T", "第二變體", "SKU-X", 12800 ])
  end

  it "🔴 ledger／levels／item 全部保留：item 置 NULL＋variant_deleted_at 蓋章（B1）" do
    item = ActsAsTenant.without_tenant { second.inventory_item }
    level = ActsAsTenant.without_tenant { item.inventory_levels.first! }
    ActsAsTenant.with_tenant(shop) do
      r = Inventory::Adjust.call(shop:, mode: "adjust", input: {
        name: "available", reason: "correction", idempotency_key: SecureRandom.uuid,
        changes: [ { inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
                     location_id: "gid://chilllove/Location/#{level.location_id}", delta: 3 } ] })
      raise r.user_errors.inspect if r.user_errors.any?
    end
    ledger_before = InventoryAdjustment.unscoped.count

    expect(call!(second).deleted).to be true

    ActsAsTenant.without_tenant do
      expect(InventoryAdjustment.unscoped.count).to eq(ledger_before)
      expect(InventoryLevel.unscoped.where(inventory_item_id: item.id).count).to be >= 1
      orphan = InventoryItem.unscoped.find(item.id)
      expect(orphan.product_variant_id).to be_nil
      expect(orphan.variant_deleted_at).to be_present
      expect(ProductVariant.unscoped.exists?(second.id)).to be false
    end
  end

  it "兩個孤兒 item 並存（唯一索引多 NULL；與 dedupe_key 同一 MySQL 依賴）" do
    third = ActsAsTenant.with_tenant(shop) do
      v = ProductVariant.new(shop_id: shop.id, product_id: product.id,
                             title: "第三變體", position: 903, currency: shop.store_currency)
      v.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
        product_option_id: size_option.id, option_value_id: size_values[2].id)
      v.save!
      v
    end
    expect(call!(second).deleted).to be true
    expect(call!(third).deleted).to be true
    expect(InventoryItem.unscoped.where(shop_id: shop.id, product_variant_id: nil).count).to eq(2)
  end

  it "選項座標同 transaction 刪除；variant destroy 不觸發 item 連鎖（順序契約）" do
    ov_id = ActsAsTenant.without_tenant do
      ProductVariantOptionValue.unscoped.where(product_variant_id: second.id).sole.id
    end
    item_id = ActsAsTenant.without_tenant { second.inventory_item.id }
    expect(call!(second).deleted).to be true
    ActsAsTenant.without_tenant do
      expect(ProductVariantOptionValue.unscoped.exists?(ov_id)).to be false
      expect(InventoryItem.unscoped.exists?(item_id)).to be true
    end
  end
end
