# frozen_string_literal: true

require "rails_helper"

# 結帳線第二包：建店預設運送鏈（General＋primary market zone＋免運費率）。
RSpec.describe Shipping::ProvisionDefaults do
  it "P1 建店即有 General 檔＋HK zone＋免運 flat 費率（店幣）——新店開箱可過運送段" do
    shop = create(:shop, subdomain: "ship-prov")
    ActsAsTenant.with_tenant(shop) do
      profile = ShippingProfile.general.sole
      expect(profile.name).to eq("General")
      zone = profile.shipping_zones.sole
      expect(zone.country_codes).to eq([ "HK" ]) # primary market（Markets::ProvisionDefaults）的國家
      rate = zone.shipping_rates.sole
      expect(rate).to have_attributes(rate_type: "flat", price_cents: 0, currency: shop.store_currency)
    end
  end

  it "P2 冪等：重複呼叫不疊第二套" do
    shop = create(:shop, subdomain: "ship-idem")
    expect { described_class.call(shop:) }.not_to change {
      ActsAsTenant.with_tenant(shop) { [ ShippingProfile.count, ShippingZone.count, ShippingRate.count ] }
    }
  end

  it "P3 🔴 General 不可刪；空店整店刪除仍可行（delete_all 繞守門——同 primary market 紀律）" do
    shop = create(:shop, subdomain: "ship-del")
    ActsAsTenant.with_tenant(shop) do
      profile = ShippingProfile.general.sole
      expect(profile.destroy).to be(false)
      expect(profile.errors[:base]).to be_present
    end
    expect { shop.destroy! }.to change { Shop.exists?(shop.id) }.to(false)
  end

  it "P4 刪自訂檔 ⇒ 商品回落 General（FK nullify——85 §5.4 對話語義）" do
    shop = create(:shop, subdomain: "ship-fall")
    ActsAsTenant.with_tenant(shop) do
      custom = ShippingProfile.create!(shop_id: shop.id, name: "Probe")
      product = create(:product, shop:, status: "active", title: "回落測品", shipping_profile: custom)
      custom.destroy!
      expect(product.reload.shipping_profile_id).to be_nil
    end
  end
end
