# frozen_string_literal: true

require "rails_helper"

# 包 30（D77）：CacheStampBumper——商品資料變動 → 所在系列頁 stamp。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   B1 SaveProduct 更新 ⇒ 內部 product.updated 事件存在（拿掉產生端 ⇒ 轉紅）
#   B2 registry 接線斷言＋行為隔離（拆 registry ⇒ B2 轉紅；bump 全店 ⇒ B2b 轉紅）
#      ⚠️ 2026-08-30 兩輪突變實跑的教訓：走 `drain!` 的端到端格**殺不死** registry
#      突變——SaveProduct 恆發 products/update（外部）⇒ ResyncConsumer 重算成員
#      也會 bump 同一欄 ⇒ 冗餘路徑遮蔽。故接線與行為分開釘。
#   B3 變體事件經父商品解析 ⇒ 同 bump（解析函式壞 ⇒ 轉紅）
RSpec.describe Catalog::CacheStampBumper do
  let(:shop) { create(:shop) }

  def collection!(handle, product: nil)
    ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "系列 #{handle}", handle:,
                             description_html: "", collection_type: "manual", sort_order: "manual")
      if product
        CollectionProduct.create!(shop_id: shop.id, collection: c, product:, position: 1)
        CollectionMembership.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id,
                                     variant_key: 0, position: 1)
      end
      c
    end
  end

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "stamp 測試")
      create(:product_variant, product: p)
      p
    end
  end
  let!(:member_collection) { collection!("with-product", product:) }
  let!(:other_collection) { collection!("without-product") }

  def stamp(collection)
    ActsAsTenant.without_tenant do
      Collection.where(id: collection.id).pick(:products_updated_at)
    end
  end

  # SaveProduct 契約：無選項商品必須帶恰一個變體列（cache_stamps_spec 同款 fixture）。
  def save_title!(title)
    result = ActsAsTenant.with_tenant(shop) do
      variant = product.product_variants.sole
      Catalog::SaveProduct.call(shop:, input: {
        id: "gid://chilllove/Product/#{product.id}", title: title,
        lock_version: product.reload.lock_version,
        variants: [ { id: "gid://chilllove/ProductVariant/#{variant.id}", price: "128.00" } ]
      })
    end
    expect(result.user_errors).to be_empty
    result
  end

  it "B1 🔴 SaveProduct 更新 ⇒ 同交易落一筆內部 product.updated（topics.rb ③留位結清）" do
    save_title!("改名了")
    count = ActsAsTenant.without_tenant do
      EventOutbox.where(shop_id: shop.id, topic: Events::Topics::PRODUCT_UPDATED).count
    end
    expect(count).to eq(1)
  end

  it "B2 🔴 registry：兩個內部 topic 都掛著本消費者（拆線即紅）" do
    expect(Events::Consumers.for(Events::Topics::PRODUCT_UPDATED)).to include(described_class)
    expect(Events::Consumers.for(Events::Topics::PRODUCT_VARIANT_UPDATED)).to include(described_class)
  end

  it "B2c 🔴 行為隔離：product.updated 事件 ⇒ 所在系列 stamp 前進；B2b 無關系列不動" do
    event = ActsAsTenant.without_tenant do
      EventOutbox.create!(shop_id: shop.id, event_id: SecureRandom.uuid,
                          topic: Events::Topics::PRODUCT_UPDATED,
                          aggregate_type: "Product", aggregate_id: product.id,
                          payload: { product_id: product.id },
                          available_at: Time.current, status: "pending")
    end
    before_other = stamp(other_collection)
    travel 2.seconds do
      described_class.call(event)
    end
    expect(stamp(member_collection)).to be_present
    expect(stamp(other_collection)).to eq(before_other)
  end

  it "B3 🔴 變體事件經父商品解析 ⇒ 同 bump；孤兒 variant_id ⇒ no-op 不 raise" do
    variant_id = ActsAsTenant.with_tenant(shop) { product.product_variants.sole.id }
    event = ActsAsTenant.without_tenant do
      EventOutbox.create!(shop_id: shop.id, event_id: SecureRandom.uuid,
                          topic: Events::Topics::PRODUCT_VARIANT_UPDATED,
                          aggregate_type: "ProductVariant", aggregate_id: variant_id,
                          payload: { product_variant_id: variant_id },
                          available_at: Time.current, status: "pending")
    end
    before_member = stamp(member_collection)
    travel 2.seconds do
      described_class.call(event)
    end
    expect(stamp(member_collection)).to be_present
    expect(stamp(member_collection)).to be > before_member if before_member

    ghost = ActsAsTenant.without_tenant do
      EventOutbox.create!(shop_id: shop.id, event_id: SecureRandom.uuid,
                          topic: Events::Topics::PRODUCT_VARIANT_UPDATED,
                          aggregate_type: "ProductVariant", aggregate_id: 0,
                          payload: { product_variant_id: 999_999_999 },
                          available_at: Time.current, status: "pending")
    end
    expect { described_class.call(ghost) }.not_to raise_error
  end
end
