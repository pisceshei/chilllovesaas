# frozen_string_literal: true

require "rails_helper"

# E12：Section Rendering API 在任何頁面（官方 ajax/section-rendering，取證 2026-09-04：section_id 回該段 HTML、sections 回 JSON、
# 可加在任何頁面 URL；不存在 ⇒ 404）。先前只有 search/suggest／recommendations／cart POST 走 renderer 的 section 分支。
#   SR1 `/?section_id=hero` 只回該段 wrapper（無 <html>）
#   SR2 `/search?section_id=header`：非首頁 URL 也可（Ella recently-viewed 打 `/search?section_id=…&q=`）
#   SR3 `/?sections=hero,header` 回 JSON（兩鍵）；陣列形 `sections[]=` 同義
#   SR4 不存在的 section ⇒ 404；`Cache-Control: no-store`
RSpec.describe "Storefront Section Rendering API on any page", type: :request do
  let(:shop) { create(:shop, subdomain: "sra-shop") }

  before do
    host! "sra-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  it "SR1 🔴 section_id 回單段 HTML（無版面）" do
    get "/en-hk/?section_id=hero"
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with('<div id="shopify-section-template--index__hero" class="shopify-section">')
    expect(response.body).not_to include("<html")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "SR2 🔴 任何頁面 URL 都可：/search?section_id=header 回群組段" do
    get "/en-hk/search?section_id=header"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="shopify-section-sections--header-group__header"')
    expect(response.body).not_to include("<html")
  end

  it "SR3 🔴 sections 回 JSON（逗號與陣列形同義）" do
    get "/en-hk/?sections=hero,header"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    json = response.parsed_body
    expect(json.keys).to match_array(%w[hero header])
    expect(json["hero"]).to include("shopify-section-template--index__hero")

    get "/en-hk/?sections[]=hero&sections[]=header"
    expect(response.parsed_body.keys).to match_array(%w[hero header])
  end

  it "SR5 🔴 完整 id 帶宿主模板：在 /search 上請求 template--index__hero 也回該段（Ella recently-viewed 打 /search 取商品頁段）" do
    get "/en-hk/search?section_id=template--index__hero"
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with('<div id="shopify-section-template--index__hero" class="shopify-section">')
    get "/en-hk/search?section_id=sections--header-group__header"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="shopify-section-sections--header-group__header"')
  end

  it "SR4 🔴 不存在的 section ⇒ 404" do
    get "/en-hk/?section_id=zzz-none"
    expect(response).to have_http_status(:not_found)
  end
end
