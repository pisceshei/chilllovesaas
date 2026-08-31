# frozen_string_literal: true

require "rails_helper"

# 結帳線第三包：前台顯示對接的 Liquid 面（86 §7 差距清單的收口格）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   W1 `cart.duties_included` 必須**顯式 false**：Ella tax-note 四分支用 `== false`
#      顯式比較，`nil == false` 為假 ⇒ 缺鍵時整段稅注（含「未含稅」文案）靜默空白。
#      本格直接寫 Ella 分支形——把顯式鍵改回 miss-nil 即轉紅。
#   W4 all_country_option_tags 與結帳頁國家下拉同源（鐵律 7）——值域是
#      market ∩ 有費率 zone，砍掉 assigns 佈線即轉紅。
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

  it "W4 🔴 all_country_option_tags＝market ∩ 有費率 zone 的 <option> 串（與結帳頁同源）" do
    # 建店 provision＝HK market＋HK zone＋費率 ⇒ 恰一個 option
    expect(render_liquid("{{ all_country_option_tags }}")).to eq('<option value="HK">HK</option>')
    # 加一個不在 market 的 zone（有費率）⇒ 不出現（交集語義，殺「只查 zone」）
    ActsAsTenant.with_tenant(shop) do
      zone = ShippingZone.create!(shop_id: shop.id, shipping_profile: ShippingProfile.general.sole,
                                  name: "US zone", country_codes: [ "US" ])
      ShippingRate.create!(shop_id: shop.id, shipping_zone: zone, name: "美國線",
                           price_cents: 1_000, rate_type: "flat", currency: "HKD")
    end
    fresh = ActsAsTenant.with_tenant(shop) { ThemeEngine::Runtime.new(theme:, shop:, source:) }
    expect(Liquid::Template.parse("{{ all_country_option_tags }}").render(fresh.global_assigns))
      .to eq('<option value="HK">HK</option>')
  end
end
