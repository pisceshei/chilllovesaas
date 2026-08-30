# frozen_string_literal: true

require "rails_helper"

# A3：90 天未動 cart 清理（specs/15 F1 #4）。
RSpec.describe Storefront::CartPurgeJob do
  let(:shop) { create(:shop) }

  it "刪 purge_days 前未動的車（行隨 FK cascade）；新車保留；門檻讀 limits" do
    ActsAsTenant.with_tenant(shop) do
      variant = create(:product_variant, shop:, product: create(:product, shop:, status: "active"))
      variant.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      stale = Cart.create!(shop_id: shop.id, attributes_json: {})
      Storefront::CartWriter.add(cart: stale, variant_id: variant.id)
      fresh = Cart.create!(shop_id: shop.id, attributes_json: {})

      cutoff = Limits.fetch(:cart, :purge_days)
      stale.update_column(:updated_at, (cutoff + 1).days.ago)

      described_class.perform_now
      expect(Cart.exists?(stale.id)).to be(false)
      expect(CartLineItem.where(cart_id: stale.id).count).to eq(0)
      expect(Cart.exists?(fresh.id)).to be(true)
    end
  end
end
