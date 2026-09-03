# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-8：JS runtime 熱修批（chill.deals 對表軸 js-runtime 實錘五格）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   JS1 全域 settings 套 schema defaults（殺：缺 defaults ⇒ Ella inline
#       theme.config 塊 `show: ,` SyntaxError ⇒ 整站 JS 停 no-js——真兇）
#   JS2 formatMoney 正則反斜線（殺：heredoc 插值吃一層 ⇒ 金額永不替換）
#   JS5 t filter 佔位空白寬容（殺：Ella `{{ inventory}}` 無尾空格不插值）
RSpec.describe "Theme JS runtime batch", type: :request do
  let(:shop) { create(:shop, subdomain: "jsr-shop") }
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
  end

  def render_home
    ActsAsTenant.with_tenant(shop) do
      ThemeEngine::PageRenderer.new(theme:, shop:, publication: Publication.online_store!,
                                    url_prefix: "en-hk").render("/").html
    end
  end

  it "JS1 🔴 全域 settings 三層解析：schema-default-only 鍵有值（不再吐空）" do
    ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "snippets/cl-probe-settings.liquid",
                               content: "GLOBAL[{{ settings.brand_color }}|{{ settings.show_probe }}]")
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "sections/cl-probe.liquid", content: <<~LIQUID)
                                 {% render 'cl-probe-settings' %}
                                 {% schema %}{ "name": "Probe", "settings": [] }{% endschema %}
                               LIQUID
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "sections" => { "p" => { "type" => "cl-probe", "settings" => {} } },
                                  "order" => [ "p" ] })
    end
    html = render_home
    # settings_data.json current 有 brand_color=#a9502c ⇒ 檔案層蓋 schema default
    # brand_color＝檔案 current 蓋 default；show_probe＝schema-default-only 鍵
    expect(html).to include("GLOBAL[#a9502c|true]")
    expect(html).not_to include("|]") # 🔴 default-only 鍵吐空＝三層解析斷（no-js 殺手形）
  end

  it "JS2 🔴 formatMoney 正則單反斜線落地；JS3 money_format 真值" do
    html = render_home
    expect(html).to include('replace(/\B(?=(\d{3})+(?!\d))/g, ",")')   # 一層反斜線（JS 正則形）
    expect(html).to include('replace(/\{\{\s*(\w+)\s*\}\}/, amount)')
    expect(html).not_to include('\\\\B') # 雙反斜線＝heredoc 又吃回去

    drop = ThemeEngine::ShopDrop.new(shop)
    expect(drop.money_format).to eq("${{amount}}")
  end

  it "JS4 request.locale 物件化（iso_code 可取）；JS5 🔴 t 佔位無尾空格插值" do
    drop = ThemeEngine::RequestDrop.new(locale: "zh-hant-hk")
    expect(drop["locale"]["iso_code"]).to eq("zh-hant-hk")

    # 真渲染路徑：locale 檔 probe.tight＝"Only {{ n}} left"（無尾空格＝Ella 實形）
    ActsAsTenant.with_tenant(shop) do
      ThemeFileOverlay.create!(shop_id: shop.id, theme_id: theme.id,
                               path: "sections/cl-t-probe.liquid", content: <<~LIQUID)
                                 T[{{ 'probe.tight' | t: n: 3 }}]
                                 {% schema %}{ "name": "TProbe", "settings": [] }{% endschema %}
                               LIQUID
      Template.create!(shop_id: shop.id, theme_id: theme.id, key: "index", template_type: "index",
                       content: { "sections" => { "tp" => { "type" => "cl-t-probe", "settings" => {} } },
                                  "order" => [ "tp" ] })
    end
    expect(render_home).to include("T[Only 3 left]") # 🔴 無尾空格佔位插值（真 filter）
  end
end
