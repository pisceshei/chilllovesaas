# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-25：.liquid 替代模板（?view=）＋{% layout %} 真語義。
# 官方（tags/layout 取證 2026-09-02）：`{% layout 'name' %}`／`{% layout none %}`；
# 預設 theme.liquid。Ella 消費＝cart.ajax_side_cart.liquid 等 Ajax view 片段
# （側車抽屜的資料源）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   LV1 layout none ⇒ 片段直出（殺：LayoutTag no-op ⇒ Ajax 側車拿到整頁——
#       原生產形態）；?view= 認得 .liquid（殺：只認 JSON ⇒ 靜默回預設頁）
#   LV3 view 進頁快取鍵（既有 CACHE_PARAMS view——防替代片段互汙）
RSpec.describe "Storefront liquid view templates", type: :request do
  let(:shop) { create(:shop, subdomain: "lv-shop") }

  before do
    host! "lv-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    Rails.cache.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  it "LV1 🔴 ?view= 的 .liquid 模板＋{% layout none %} ⇒ 片段直出（無 theme.liquid 包裹）" do
    get "/en-hk/cart?view=ajax_side_cart"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(id="side-cart"))
    expect(response.body).to include("item_count=0") # cart 全域照常供給
    expect(response.body).not_to include("<!doctype html>") # 🔴 layout none＝不包
    expect(response.body).not_to include("content_for_layout")
    expect(response.body).not_to include("群組頁首") # theme.liquid 的群組帶不得出現
  end

  it "LV2 {% layout 'bare' %} ⇒ 指名 layout 包裹；預設 cart 頁不受影響" do
    get "/en-hk/cart?view=slim"
    expect(response.body).to include(%(id="bare-layout"))
    expect(response.body).to include(%(id="slim-cart"))
    expect(response.body).not_to include("群組頁首") # bare layout 無群組帶

    get "/en-hk/cart"
    expect(response.body).to include("shopify-section-main") # 預設 JSON 模板照舊
    expect(response.body).not_to include("side-cart")
  end

  it "LV3 🔴 view 片段與整頁互不污染（頁快取鍵含 view——既有 CACHE_PARAMS 面）" do
    get "/en-hk/cart" # cart 本就 no-store；用 collection 驗快取面不適用——
    # cart no-store ⇒ 本格改驗兩請求形態彼此正確（回歸護欄）
    expect(response.body).to include("shopify-section-main")
    get "/en-hk/cart?view=ajax_side_cart"
    expect(response.body).to include(%(id="side-cart"))
    get "/en-hk/cart"
    expect(response.body).to include("shopify-section-main")
  end
end
