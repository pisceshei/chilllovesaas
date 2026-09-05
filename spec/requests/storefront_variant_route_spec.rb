# frozen_string_literal: true

require "rails_helper"

# T15 `/variants/{id}` 路由（docs/dev/t15-variant-route.md；external-facts §G31，hoko.vip 2026-09-05 實測）——
# Ella／Dawn 的 `assets/pickup-availability.js` 逐字用 `${rootUrl}variants/${variantId}/?section_id=pickup-availability`：
#   VR1 🔴 裸形 302 到 `/products/{handle}?variant={id}`（本尊實測形）
#   VR2 🔴 帶 `section_id` ⇒ 200 HTML，只回該 section（語境＝該變體被選取的商品頁）
#   VR3 語言前綴保留；尾斜線同形
#   VR4 查無變體 ⇒ 404；非數字 id 不吃這條路由
RSpec.describe "Storefront /variants/{id} route (T15)", type: :request do
  let(:shop) { create(:shop, subdomain: "t15-shop") }

  before do
    host! "t15-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published", source: "first_party", license_attested: true)
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      Market.find_by!(is_primary: true).market_web_presences.sole.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  let!(:variant) do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      v = create(:product_variant, shop:, product: p, price_cents: 18_800, position: 1)
      v.inventory_item.inventory_levels.order(:id).first&.update!(available: 5)
      v
    end
  end

  it "VR1 🔴 裸形 302 到商品頁帶 ?variant=（本尊實測形）" do
    get "/variants/#{variant.id}"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/products/acme-tee?variant=#{variant.id}")

    get "/variants/#{variant.id}/" # Ella 的 fetch 帶尾斜線
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/products/acme-tee?variant=#{variant.id}")
  end

  it "VR2 🔴 帶 section_id ⇒ 200 只回該 section（語境＝該變體被選取的商品頁）" do
    get "/variants/#{variant.id}/?section_id=js-probe"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/html")
    expect(response.body).to include('id="shopify-section-js-probe"')
    expect(response.body).not_to include("<html") # 只回 section，不是整頁
  end

  it "VR3 語言前綴保留" do
    get "/zh-hant/variants/#{variant.id}"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/zh-hant/products/acme-tee?variant=#{variant.id}")
  end

  it "VR4 查無變體 ⇒ 404；非數字不吃這條路由" do
    get "/variants/999999999"
    expect(response).to have_http_status(:not_found)
    get "/variants/abc"
    expect(response).to have_http_status(:not_found)
  end
end
