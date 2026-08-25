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
end
