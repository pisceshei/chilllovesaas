# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-7：section 包裝三件——id 來源前綴（`template--{template}__{key}`／`sections--{group}__{key}`）、
# 群組 class `shopify-section-group-{group}`、群組 BEGIN／END 註解。證據＝真店 hoko.vip 三套主題金標本逐字
# （`tools/theme-conformance/golden/{kalles-5.4.2,minimog-6.0.0,ella-7.2.0-products}/index.html`，2026-09-03）：
# `id="shopify-section-template--19765269299303__main"`、`id="shopify-section-sections--19765270577255__header_default"`、
# `class="shopify-section shopify-section-group-header-group …"`、`<!-- BEGIN sections: header-group -->`。
# 官方 sections 頁對此無逐字 ⇒ 數字段（本尊內部 id）以模板鍵／群組名代之（形同值 ours，登記）。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   SW1 JSON 模板 section：wrapper id＝`template--index__hero`；Liquid `section.id` 同值（殺：wrapper 加前綴但
#       section.id 仍裸 key ⇒ 主題 `#shopify-section-{{ section.id }}` 選擇器全失效）
#   SW2 群組 section：`sections--header-group__header` 前綴＋`shopify-section-group-header-group` class＋
#       BEGIN／END 註解（殺：三件任一漏）
#   SW3 SRA 收裸 key 與完整 id：`?section_id=hero` 與 `?section_id=template--index__hero` 同輸出、
#       `?sections=` map 鍵照請求原樣（殺：完整 id 404）
#   SW4 靜態／檔名直渲染的 section 無前綴（殺：一律加 template 前綴）
RSpec.describe "Storefront section wrapper (id scope / group class / group comments)", type: :request do
  let(:shop) { create(:shop, subdomain: "sw-shop") }

  before do
    host! "sw-shop.lvh.me"
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

  it "SW1 🔴 模板 section 的 wrapper id 帶 template 前綴，且 section.id 同值" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<div id="shopify-section-template--index__hero" class="shopify-section">')
    expect(response.body).to include('<div id="shopify-section-template--index__probe" class="shopify-section"><span id="sidp">template--index__probe</span>')
  end

  it "SW2 🔴 群組 section：sections 前綴＋群組 class＋BEGIN／END 註解" do
    get "/"
    expect(response.body).to include("<!-- BEGIN sections: header-group -->")
    expect(response.body).to include('<div id="shopify-section-sections--header-group__header" class="shopify-section shopify-section-group-header-group">')
    expect(response.body).to include("<!-- END sections: header-group -->")
    expect(response.body).to match(%r{<!-- BEGIN sections: header-group -->.*?群組頁首.*?<!-- END sections: header-group -->}m)
  end

  # SRA 端點（search/suggest、recommendations、cart POST）都經 PageRenderer 的 section_id／sections
  # 參數（page_renderer_spec E11–E13 同一介面），這裡直接打 renderer。
  def renderer
    theme = ActsAsTenant.with_tenant(shop) { Theme.find_by!(shop_id: shop.id, role: "published") }
    pub = ActsAsTenant.with_tenant(shop) { Publication.online_store! }
    ThemeEngine::PageRenderer.new(theme:, shop:, publication: pub,
                                  source: ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")))
  end

  it "SW3 🔴 Section Rendering API 收裸 key 與完整 id，輸出同形；map 鍵照請求原樣" do
    bare = renderer.render("/", params: { "section_id" => "hero" })
    expect(bare.status).to eq(200)
    expect(bare.html).to start_with('<div id="shopify-section-template--index__hero"')
    full = renderer.render("/", params: { "section_id" => "template--index__hero" })
    expect(full.status).to eq(200)
    expect(full.html).to eq(bare.html)

    map = JSON.parse(renderer.render("/", params: { "sections" => "hero,template--index__hero,no-such" }).html)
    expect(map.keys).to eq(%w[hero template--index__hero no-such])
    expect(map["hero"]).to eq(map["template--index__hero"])
    expect(map["no-such"]).to be_nil
  end

  it "SW4 檔名直渲染（無模板／群組 entry）的 section 無前綴；群組 section 經 SRA 帶 sections 前綴" do
    probe = renderer.render("/", params: { "section_id" => "sid-probe" })
    expect(probe.html).to start_with('<div id="shopify-section-sid-probe" class="shopify-section"><span id="sidp">sid-probe</span>')
    header = renderer.render("/", params: { "section_id" => "header" })
    expect(header.html).to start_with('<div id="shopify-section-sections--header-group__header" class="shopify-section shopify-section-group-header-group">')
  end
end
