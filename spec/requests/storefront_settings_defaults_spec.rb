# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-3：settings 無 `default` 時的官方預設語義（shopify.dev settings/input-settings，取證 2026-09-02）：
#   checkbox "If `default` is unspecified, then the value is `false` by default."
#   select／radio "If `default` is unspecified, then the first option is selected by default."
#   color_scheme "If no value was entered, or the value was invalid, then the default value from `color_scheme`
#   is returned. If the default value is also invalid, then the first `color_scheme` from `color_scheme_group`
#   is returned."
# D78 triage（gap-triage-m59 ＋ settings_preclassify ENGINE-GAP?）：Minimog／Kalles 的 checkbox／color_scheme
# 無 default 鍵曾被計成 miss、模板拿到 nil／空字串。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   S1 checkbox 無 default ⇒ false（殺：nil——`== false` 分支與 `{% unless %}` 兩形都會錯）
#   S2 select／radio 無 default ⇒ 第一個 option 的 value（殺：nil）
#   S3 color_scheme：無 default ⇒ 第一組；有 default ⇒ default；default 無效 ⇒ 第一組；
#      存值空字串 ⇒ default（殺：回傳原字串／nil）
#   S4 section 本地 block 的 settings 同語義（殺：只修 section 層）
RSpec.describe "Storefront settings default semantics", type: :request do
  let(:shop) { create(:shop, subdomain: "sdef-shop") }

  before do
    host! "sdef-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    get "/en-hk/"
    expect(response).to have_http_status(:ok)
  end

  it "S1 🔴 checkbox 無 default ⇒ false（可與 false 比較、不進真值分支）" do
    expect(response.body).to include('<span id="sdf">F</span>')
  end

  it "S2 🔴 select／radio 無 default ⇒ 第一個 option；S3 🔴 color_scheme 三段退回" do
    expect(response.body).to include('<span id="sd">false|grid|left|scheme-1|scheme-2|scheme-1|scheme-2</span>')
  end

  it "S4 section 本地 block 的 checkbox／select 同語義" do
    expect(response.body).to include('<span id="sdb">false|a;true|b;</span>')
  end

  # 真主題證明：theme 層 settings（settings_schema 無 default）走同一條 schema_defaults——
  # 修前 preclassify 標 ENGINE-GAP? 的鍵（`tools/theme-conformance/evidence/preclassify-*.json`）
  # 不得再出現在 conformance miss 報告。
  it "S5 🔴 Minimog 6.0.0 theme 層：loading_design_mode（checkbox）／drawer_popup_color_scheme 不再計 miss" do
    ThemeEngine::MISSES.clear
    m6_shop = create(:shop, subdomain: "sdef-m6") # 獨立店：harness 自建 published theme
    report = conformance_render_all(theme_dir: Rails.root.join("test/fixtures/themes/minimog-6.0.0"),
                                    theme_name: "Minimog", theme_version: "6.0.0", shop: m6_shop)
    expect(report[:pages].filter_map { |p| p[:exception] }).to eq([])
    expect(report[:misses].keys).not_to include("settings.loading_design_mode", "settings.drawer_popup_color_scheme")
  end
end
