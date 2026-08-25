# frozen_string_literal: true

require "rails_helper"

# 第 11 包：outbox 消費者接線（P11-U17 的 ours 裁定）。
RSpec.describe Collections::ResyncConsumer do
  let(:shop) { create(:shop, subdomain: "resync-consumer") }

  def event!(topic:, payload:)
    ActsAsTenant.with_tenant(shop) do
      EventOutbox.create!(event_id: SecureRandom.uuid, topic:, aggregate_type: "Product",
                          aggregate_id: 1, shop_id: shop.id, available_at: Time.current,
                          payload:)
    end
  end

  it "tripwire：三個 topic 都掛了本消費者（註冊表）" do
    [ Events::Topics::PRODUCTS_CREATE, Events::Topics::PRODUCTS_UPDATE,
      Events::Topics::INVENTORY_ADJUSTED ].each do |topic|
      expect(Events::Consumers.for(topic)).to include(described_class), topic
    end
  end

  it "product 事件：payload 的 product_id 直達 ResyncProduct" do
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: 42)

    described_class.call(event!(topic: Events::Topics::PRODUCTS_UPDATE, payload: { product_id: 42 }))
  end

  it "inventory 事件：product_variant_id 經變體反查商品" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    variant = ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:, product:) }
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: product.id)

    described_class.call(event!(topic: Events::Topics::INVENTORY_ADJUSTED,
                                payload: { product_variant_id: variant.id }))
  end

  it "變體已刪 ⇒ 靜默返回（商品層事件會另行到達，不是錯誤）" do
    expect(Collections::ResyncProduct).not_to receive(:call)

    described_class.call(event!(topic: Events::Topics::INVENTORY_ADJUSTED,
                                payload: { product_variant_id: 999_999 }))
  end

  it "🔴 商品已刪的 product 事件**仍要跑**（刪除＝從所有系列移出的觸發源）" do
    expect(Collections::ResyncProduct).to receive(:call).with(shop: shop, product_id: 999_999)

    described_class.call(event!(topic: Events::Topics::PRODUCTS_UPDATE, payload: { product_id: 999_999 }))
  end

  it "🔴 G4（2026-08-26 收斂輪）：A 排除 B 且 A.id < B.id 時，單次 resync 也要收斂" do
    shop = create(:shop, subdomain: "resync-order")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end

    # 先建 A（id 較小），再建 B；A 的規則＝tag red 排除 B 的成員，B＝tag red。
    a = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "A", handle: "col-a",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    b = ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "B", handle: "col-b",
                         collection_type: "smart", sort_order: "manual", description_html: "")
    end
    expect(a.id).to be < b.id

    ActsAsTenant.with_tenant(shop) do
      sa = CollectionSource.create!(shop_id: shop.id, collection_id: a.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sa.id, block: "exclusion",
                                   condition_type: "collection", relation: "includes",
                                   value_int: b.id, position: 1)
      sb = CollectionSource.create!(shop_id: shop.id, collection_id: b.id, source_type: "conditions",
                                    target_type: "products", inclusion_match: "all", position: 0)
      CollectionSourceRule.create!(shop_id: shop.id, collection_source_id: sb.id, block: "inclusion",
                                   condition_type: "product_tag", relation: "includes",
                                   value_text: "red", position: 0)
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    members = ->(c) { ActsAsTenant.with_tenant(shop) { CollectionMembership.where(collection_id: c.id).pluck(:product_id) } }
    expect(members.call(b)).to eq([ product.id ])
    expect(members.call(a)).to be_empty,
      "第一趟算 A 時商品還沒進 B ⇒ A 誤留；引用其他系列的必須再算一次"
  end

  it "🔴 G1 自癒面：resync 的工作清單＝全部智慧系列，零 source 的殘留成員也要被移出" do
    shop = create(:shop, subdomain: "resync-orphan")
    product = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, title: "紅", tags: [ "red" ])
      create(:product_variant, shop:, product: p, price_cents: 100)
      ProductTag.create!(shop_id: shop.id, product_id: p.id, tag_key: "red", tag_display: "red")
      p
    end
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "孤兒", handle: "orphan",
                             collection_type: "smart", sort_order: "manual", description_html: "")
      # 物化列還在，但條件已被清空（G1 的殘留形態）。
      CollectionMembership.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id,
                                   origin: "conditions", rebuilt_at: Time.current)
      c
    end

    Collections::ResyncProduct.call(shop:, product_id: product.id)

    remaining = ActsAsTenant.with_tenant(shop) do
      CollectionMembership.where(collection_id: collection.id).pluck(:product_id)
    end
    expect(remaining).to be_empty,
      "工作清單從 collection_sources 導出 ⇒ 條件被清空的系列從所有清理路徑消失，殘留成員無自癒"
  end
end
