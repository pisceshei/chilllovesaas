# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-5：Shop 欄位（money_with_currency_format／description／features）＋字型庫補家族與顯示名推導。
# 官方：shopify.dev objects/shop、filters/money_with_currency（例輸出 `$10.00 CAD`＝"HTML with currency"
# 形＝money_format＋空白＋幣別碼）、themes/architecture/settings/fonts（handle 形 family_style_weight、
# 字庫表列與 deprecated Helvetica `helvetica_n3 helvetica_o3 …`、system fonts 表）——取證 2026-09-02。
# D78 triage：ShopDrop.money_with_currency_format／description／features、font_library.roboto_condensed
# （顯示名誤為 "Roboto"）／libre_baskerville／helvetica。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   H1 money_with_currency_format＝money_format＋" "＋幣別碼（殺：nil／漏幣別碼）
#   H2 description 宣告 nil、features 兩旗標 false，皆不計 miss（殺：liquid_method_missing 回 nil＋miss）
#   H3 字庫家族（Assistant／Karla／Lora／Roboto Condensed／Libre Baskerville／Arial／Times New Roman／
#      Helvetica）依官方 handle 表解析：家族名、style（n／i／o）、weight、fallback、system?=false、不計 miss
#      （殺：未收錄 ⇒ system fallback＋miss；`o` 不認）
#   H4 未知 handle 仍 system fallback，顯示名逐字 titleize（殺：`split("_").first` 把 Roboto Condensed 切成 Roboto）
#   H5 無自 host 檔的字庫家族：font_face／font_url 空輸出（登記形，殺：對 nil file 拼 URL）
#   H6 真主題：Kalles 5.4.2 conformance 不再出現 `font_library.helvetica`
RSpec.describe "ThemeEngine shop fields & font library gaps" do
  let(:shop) { create(:shop, subdomain: "sf-shop", store_currency: "HKD") }

  before { ThemeEngine::MISSES.clear }

  def render(src, assigns = {})
    Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT).render(assigns, registers: {})
  end

  it "H1 🔴 shop.money_format／money_with_currency_format＝店級兩欄直出（HKD 種子＝真店實讀值；D81）" do
    out = render("{{ shop.money_format }}|{{ shop.money_with_currency_format }}", "shop" => ThemeEngine::ShopDrop.new(shop))
    expect(out).to eq("${{amount}}|HK${{amount}} HKD")
  end

  it "H2 🔴 shop.description 宣告 nil；shop.features 兩旗標 false；皆不計 miss" do
    out = render("[{{ shop.description }}]|{{ shop.features.login_with_shop_classic_customer_accounts? }}|" \
                 "{{ shop.features.follow_on_shop? }}|{% if shop.features.login_with_shop_classic_customer_accounts? %}ON{% else %}OFF{% endif %}",
                 "shop" => ThemeEngine::ShopDrop.new(shop))
    expect(out).to eq("[]|false|false|OFF")
    expect(ThemeEngine::MISSES.keys.grep(/\AShopDrop\.(description|features)\z/)).to eq([])
  end

  it "H3 🔴 字庫家族依官方 handle 表解析（含 Helvetica 的 o＝oblique）" do
    cases = {
      "roboto_condensed_n4" => [ "Roboto Condensed", "normal", 400, "sans-serif" ],
      "libre_baskerville_i4" => [ "Libre Baskerville", "italic", 400, "serif" ],
      "helvetica_o7" => [ "Helvetica", "oblique", 700, "sans-serif" ],
      "assistant_n4" => [ "Assistant", "normal", 400, "sans-serif" ],
      "karla_i5" => [ "Karla", "italic", 500, "sans-serif" ],
      "lora_n6" => [ "Lora", "normal", 600, "serif" ],
      "arial_n7" => [ "Arial", "normal", 700, "sans-serif" ],
      "times_new_roman_i4" => [ "Times New Roman", "italic", 400, "serif" ]
    }
    cases.each do |handle, (family, style, weight, fallback)|
      drop = ThemeEngine::FontLibrary.drop(handle)
      expect([ drop.family, drop.style, drop.weight, drop.fallback_families, drop.system? ])
        .to eq([ family, style, weight, fallback, false ]), "handle #{handle}"
    end
    expect(ThemeEngine::MISSES.keys.grep(/\Afont_library\./)).to eq([])
    # 官方表列外的變體（Libre Baskerville 無 n5）⇒ 同未知處置（system fallback＋miss）
    expect(ThemeEngine::FontLibrary.drop("libre_baskerville_n5").system?).to be(true)
  end

  it "H4 🔴 未知 handle：system fallback＋顯示名 titleize＋miss" do
    drop = ThemeEngine::FontLibrary.drop("nope_font_n4")
    expect([ drop.family, drop.system?, drop.fallback_families ]).to eq([ "Nope Font", true, "sans-serif" ])
    expect(ThemeEngine::MISSES.keys).to include("font_library.nope_font")
  end

  it "H5 無自 host 檔的字庫家族：font_face／font_url 空輸出（登記形）" do
    drop = ThemeEngine::FontLibrary.drop("roboto_condensed_n4")
    out = render("[{{ font | font_face }}]|[{{ font | font_url }}]|{{ font.variants.size }}", "font" => drop)
    expect(out).to eq("[]|[]|18")
  end

  it "H6 🔴 Kalles 5.4.2 真主題：conformance 不再出現 font_library.helvetica" do
    k_shop = create(:shop, subdomain: "sf-k1")
    report = conformance_render_all(theme_dir: Rails.root.join("test/fixtures/themes/kalles-5.4.2"),
                                    theme_name: "Kalles", theme_version: "5.4.2", shop: k_shop)
    expect(report[:pages].filter_map { |p| p[:exception] }).to eq([])
    expect(report[:misses].keys.grep(/\Afont_library\.helvetica/)).to eq([])
  end
end
