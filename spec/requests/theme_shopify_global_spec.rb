# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-3：window.Shopify bootstrap＋section 資產聚合＋coverage 批。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   SG1 Shopify 全域注入（殺：主題 JS「Shopify is not defined」連鎖崩復發）
#   SG2 {% javascript %}/{% stylesheet %} 聚合＋去重（殺：回退整塊吞掉／
#       同型 section 重複輸出）
#   SG3 color_modify alpha（殺：回退回原值 stub＝overlay 漸層全滅）
RSpec.describe "Theme Shopify global & section assets", type: :request do
  let(:shop) { create(:shop, subdomain: "sg-shop") }
  let!(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  before do
    allow(ThemeEngine::Sources).to receive(:base_resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    host! "sg-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
  end

  def render_home(design_mode: false)
    ActsAsTenant.with_tenant(shop) do
      ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!,
                                    url_prefix: "en-hk", design_mode:).render("/").html
    end
  end

  it "SG1 🔴 window.Shopify 注入：designMode 依語境、routes.root 帶前綴、theme/currency 齊" do
    html = render_home
    expect(html).to include("window.Shopify = window.Shopify || {}")
    expect(html).to include('Shopify.designMode = false')
    expect(html).to include('Shopify.routes = { root: "/en-hk/" }')
    expect(html).to include(%(Shopify.currency = { active: "HKD"))
    expect(html).to include("Shopify.formatMoney = function")
    expect(html).to include("Shopify.CountryProvinceSelector = function")

    expect(render_home(design_mode: true)).to include("Shopify.designMode = true")
  end

  it "SG2 🔴 section 資產聚合：同型兩實例只出一份、輸出在頁尾" do
    ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "sections/asseted.liquid", content: <<~LIQUID)
                                 <div>asseted</div>
                                 {% stylesheet %}.asseted { color: teal }{% endstylesheet %}
                                 {% javascript %}console.log("asseted-js");{% endjavascript %}
                                 {% schema %}{ "name": "Asseted", "settings": [] }{% endschema %}
                               LIQUID
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "sections" => {
                         "a1" => { "type" => "asseted", "settings" => {} },
                         "a2" => { "type" => "asseted", "settings" => {} }
                       }, "order" => %w[a1 a2] })
    end
    html = render_home
    expect(html.scan("asseted-js").size).to eq(1)               # 🔴 去重
    expect(html.scan(".asseted { color: teal }").size).to eq(1)
    expect(html.index("asseted-js")).to be > html.index("<div>asseted</div>") # 頁尾輸出
    expect(html).not_to include("{% javascript %}")
  end

  it "SG3 🔴 color_modify alpha ⇒ rgba；SG4 time_tag format／item_count_for_variant 加總" do
    filters = Class.new { include ThemeEngine::Filters }.new
    expect(filters.color_modify("#336699", "alpha", 0.35)).to eq("rgba(51, 102, 153, 0.35)")
    expect(filters.color_modify("#336699", "saturation", 50)).to eq("#336699") # 其餘鍵原樣

    tag = filters.time_tag(Time.utc(2026, 9, 1, 12), "%Y/%m/%d")
    expect(tag).to include(">2026/09/01<")
    expect(tag).to include('datetime="2026-09-01T12:00:00Z"')

    cart = { "items" => [ { "variant_id" => 7, "quantity" => 2 },
                          { "variant_id" => 9, "quantity" => 5 },
                          { "variant_id" => 7, "quantity" => 1 } ] }
    expect(filters.item_count_for_variant(cart, 7)).to eq(3)
    expect(filters.item_count_for_variant(cart, 99)).to eq(0)
  end
end
