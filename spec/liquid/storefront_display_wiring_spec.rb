# frozen_string_literal: true

require "rails_helper"

# 結帳線第三包：前台顯示對接的 Liquid 面（86 §7 差距清單的收口格）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   W1 `cart.duties_included` 必須**顯式 false**：Ella tax-note 四分支用 `== false`
#      顯式比較，`nil == false` 為假 ⇒ 缺鍵時整段稅注（含「未含稅」文案）靜默空白。
#      本格直接寫 Ella 分支形——把顯式鍵改回 miss-nil 即轉紅。
#   W4 all_country_option_tags＝全部國家（本尊 A′ 實測 238 option，E14 更正）；country_option_tags 才是
#      market ∩ 有費率 zone（與結帳頁國家下拉同源，鐵律 7）——砍掉 assigns 佈線或混用語義即轉紅。W4b 鎖在地名與排序。
RSpec.describe "Storefront 顯示對接（Liquid 面）" do
  let(:shop) { create(:shop, subdomain: "lw-shop") }
  let(:source) { ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")) }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let(:runtime) { ActsAsTenant.with_tenant(shop) { ThemeEngine::Runtime.new(theme:, shop:, source:) } }

  def render_liquid(src)
    ActsAsTenant.with_tenant(shop) { Liquid::Template.parse(src).render(runtime.global_assigns) }
  end

  it "W1 🔴 Ella tax-note 四分支形：duties_included/taxes_included 顯式 false ⇒ 「皆未含」分支命中" do
    out = render_liquid(<<~LIQUID)
      {%- if cart.duties_included and cart.taxes_included -%}BOTH
      {%- elsif cart.duties_included == false and cart.taxes_included -%}TAXES_ONLY
      {%- elsif cart.duties_included and cart.taxes_included == false -%}DUTIES_ONLY
      {%- elsif cart.duties_included == false and cart.taxes_included == false -%}NEITHER
      {%- endif -%}
    LIQUID
    expect(out).to eq("NEITHER") # miss-nil 時四分支全不命中 ⇒ 空字串 ⇒ 本格紅
  end

  it "W2 shop.enabled_payment_types＝顯式空集合（86 §5：無信用卡 provider；manual 不進圖示列）" do
    expect(render_liquid("{% for t in shop.enabled_payment_types %}{{ t }}{% endfor %}#end")).to eq("#end")
    expect(runtime.global_assigns["shop"].enabled_payment_types).to eq([])
  end

  it "W3 快捷結帳鈕顯式 stub（26 行 48/647 契約）：additional_checkout_buttons=false、content 空" do
    out = render_liquid("{% if additional_checkout_buttons %}BTN{% endif %}[{{ content_for_additional_checkout_buttons }}]")
    expect(out).to eq("[]")
    expect(runtime.global_assigns.fetch("additional_checkout_buttons")).to be(false)
  end

  it "W4 🔴 all_country_option_tags＝`---`＋全部國家（本尊形：英文 value、data-provinces、與運送區域無關）；country_option_tags＝market ∩ 有費率 zone" do
    all = render_liquid("{{ all_country_option_tags }}")
    expect(all).to start_with('<option value="---" data-provinces="[]">---</option>')
    expect(all.scan("<option ").size).to eq(238) # 本尊 A′ 實測 238（含 ---）；集合＝config/country_option_tags.json
    expect(all).to include('<option value="Hong Kong" data-provinces="[[&quot;Hong Kong Island&quot;,&quot;Hong Kong Island&quot;],[&quot;Kowloon&quot;,&quot;Kowloon&quot;],[&quot;New Territories&quot;,&quot;New Territories&quot;]]">Hong Kong</option>')
    expect(all).to include(%(<option value="Côte d'Ivoire" data-provinces="[]">Côte d'Ivoire</option>)) # value 保留 '
    # country_option_tags：建店 provision＝HK market＋HK zone＋費率 ⇒ 恰一個 option（本尊形）
    only = render_liquid("{{ country_option_tags }}")
    expect(only).to eq('<option value="Hong Kong" data-provinces="[[&quot;Hong Kong Island&quot;,&quot;Hong Kong Island&quot;],[&quot;Kowloon&quot;,&quot;Kowloon&quot;],[&quot;New Territories&quot;,&quot;New Territories&quot;]]">Hong Kong</option>')
    # 加一個不在 market 的 zone（有費率）⇒ country_option_tags 不出現（交集語義，殺「只查 zone」）；all 不受運送區域影響
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingZone.create!(shop_id: shop.id, shipping_profile: ShippingProfile.general.sole,
                                  name: "US zone", country_codes: [ "US" ])
      ShippingRate.create!(shop_id: shop.id, shipping_zone: zone, name: "美國線",
                           price_cents: 1_000, rate_type: "flat", currency: "HKD")
    end
    fresh = ActsAsTenant.with_tenant(shop) { ThemeEngine::Runtime.new(theme:, shop:, source:) }
    expect(Liquid::Template.parse("{{ country_option_tags }}").render(fresh.global_assigns)).to eq(only)
    expect(Liquid::Template.parse("{{ all_country_option_tags }}").render(fresh.global_assigns)).to eq(all)
  end

  it "W4b 🔴 在地名：locale zh-Hans ⇒ 文字與 data-provinces 第二欄用 zh-CN 名、順序依在地名碼位（首國「不丹」）；無在地名的語言退英文" do
    zh = ActsAsTenant.with_tenant(shop) { ThemeEngine::Runtime.new(theme:, shop:, source:, locale: "zh-Hans") }
    out = Liquid::Template.parse("{{ all_country_option_tags }}").render(zh.global_assigns)
    expect(out).to start_with('<option value="---" data-provinces="[]">---</option><option value="Bhutan" data-provinces="[]">不丹</option>')
    expect(out).to include('<option value="Hong Kong" data-provinces="[[&quot;Hong Kong Island&quot;,&quot;香港岛&quot;],[&quot;Kowloon&quot;,&quot;九龙&quot;],[&quot;New Territories&quot;,&quot;新界&quot;]]">香港特别行政区</option>')
    fr = ActsAsTenant.with_tenant(shop) { ThemeEngine::Runtime.new(theme:, shop:, source:, locale: "fr") }
    expect(Liquid::Template.parse("{{ all_country_option_tags }}").render(fr.global_assigns)).to include('>Hong Kong</option>')
  end
end
