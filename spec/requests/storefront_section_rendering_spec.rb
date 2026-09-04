# frozen_string_literal: true

require "rails_helper"

# E12：Section Rendering API 在任何頁面（官方 ajax/section-rendering，取證 2026-09-04：section_id 回該段 HTML、sections 回 JSON、
# 可加在任何頁面 URL；不存在 ⇒ 404）。先前只有 search/suggest／recommendations／cart POST 走 renderer 的 section 分支。
#   SR1 `/?section_id=hero` 只回該段 wrapper（無 <html>）
#   SR2 `/search?section_id=header`：非首頁 URL 也可（Ella recently-viewed 打 `/search?section_id=…&q=`）
#   SR3 `/?sections=hero,header` 回 JSON（兩鍵）；陣列形 `sections[]=` 同義
#   SR4 不存在的 section ⇒ 404；`Cache-Control: no-store`
#   SR6 E16：section 形**繼承請求頁**（本尊 hoko.vip 2026-09-04 `/collections/all?section_id=…__header_default`：主選單「目錄」
#       `aria-current="page"`、`return_to` 帶 `/collections/all?…`；external-facts §G24）——`request.path`／`link.current`／
#       `{% form 'localization' %}` 預設 `return_to`＝路徑＋原始 query（`&` 不轉義、原順序）。殺：`build_runtime` 的 `path: nil`
#       （首頁項誤標 current、return_to 只剩前綴）與「return_to 只有路徑」。
#   SR7 E16：進頁快取的整頁只餵進快取鍵的 query 對（`utm_source` 不進 `return_to`、順序照請求）；`/search` 不快取 ⇒ 原樣。
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
    get "/?section_id=hero"
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with('<div id="shopify-section-template--index__hero" class="shopify-section">')
    expect(response.body).not_to include("<html")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "SR2 🔴 任何頁面 URL 都可：/search?section_id=header 回群組段" do
    get "/search?section_id=header"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="shopify-section-sections--header-group__header"')
    expect(response.body).not_to include("<html")
  end

  it "SR3 🔴 sections 回 JSON（逗號與陣列形同義）" do
    get "/?sections=hero,header"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    json = response.parsed_body
    expect(json.keys).to match_array(%w[hero header])
    expect(json["hero"]).to include("shopify-section-template--index__hero")

    get "/?sections[]=hero&sections[]=header"
    expect(response.parsed_body.keys).to match_array(%w[hero header])
  end

  it "SR5 🔴 完整 id 帶宿主模板：在 /search 上請求 template--index__hero 也回該段（Ella recently-viewed 打 /search 取商品頁段）" do
    get "/search?section_id=template--index__hero"
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with('<div id="shopify-section-template--index__hero" class="shopify-section">')
    get "/search?section_id=sections--header-group__header"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="shopify-section-sections--header-group__header"')
  end

  it "SR4 🔴 不存在的 section ⇒ 404" do
    get "/?section_id=zzz-none"
    expect(response).to have_http_status(:not_found)
  end

  def main_menu!
    ActsAsTenant.with_tenant(shop) do
      menu = Menu.create!(shop_id: shop.id, handle: "main-menu", title: "Main menu")
      MenuItem.create!(shop_id: shop.id, menu:, title: "首頁", item_type: "http", url: "/", position: 0)
      MenuItem.create!(shop_id: shop.id, menu:, title: "目錄", item_type: "http", url: "/collections/all", position: 1)
    end
  end

  it "SR6 🔴 section 形繼承請求頁：request.path／link.current／return_to＝路徑＋原始 query（& 不轉義、原順序）" do
    main_menu!
    get "/collections/all?sort_by=price-ascending&section_id=sra-probe&page=2"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<p id="sra-path">/collections/all</p>')
    expect(response.body).to include("<lk>首頁=false</lk><lk>目錄=true</lk>")
    expect(response.body).to include('<input type="hidden" name="return_to" value="/collections/all?sort_by=price-ascending&section_id=sra-probe&page=2" />')

    get "/?section_id=sra-probe"
    expect(response.body).to include('<p id="sra-path">/</p>')
    expect(response.body).to include("<lk>首頁=true</lk><lk>目錄=false</lk>")
    expect(response.body).to include('<input type="hidden" name="return_to" value="/?section_id=sra-probe" />')
  end

  it "SR7 🔴 整頁（進頁快取）的 return_to 只帶進快取鍵的 query 對；/search（不快取）原樣" do
    main_menu!
    get "/collections/all?utm_source=x&view=sra&sort_by=price-ascending"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<input type="hidden" name="return_to" value="/collections/all?view=sra&sort_by=price-ascending" />')
    expect(response.body).not_to include("utm_source")

    get "/search?q=rose&utm_source=x&section_id=sra-probe"
    expect(response.body).to include('<input type="hidden" name="return_to" value="/search?q=rose&utm_source=x&section_id=sra-probe" />')
  end
end
