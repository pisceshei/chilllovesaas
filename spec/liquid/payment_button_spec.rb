# frozen_string_literal: true

require "rails_helper"

# E18（T4）：`{{ form | payment_button }}` 出本尊同形的動態結帳骨架（hoko.vip 2026-09-05 商品頁 main 逐字；external-facts §G26）。
#   P1 有 product 脈絡 ⇒ 完整骨架（fallback JSON 跳脫形、buyer-*／currency 來自 registers、variant-params 帶選中變體 id 與 requiresShipping、
#      access-token 為店 id 導出的 32 hex、shop-id＝店 id、enabled-flags 本尊值、disabled 與 aria-hidden 骨架）
#   P2 無 product 脈絡 ⇒ 空字串（不出骨架）
#   P3 Normalizer 抹 access-token／shop-id（身分值）
RSpec.describe "payment_button（動態結帳骨架）" do
  let(:shop) { create(:shop, subdomain: "pb-shop") }

  def render(src, assigns, registers)
    Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT).render(assigns, registers:)
  end

  it "P1 🔴 商品表單內出本尊同形骨架" do
    product, variant = ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      v = create(:product_variant, shop:, product: p, price_cents: 18800)
      [ p, v ]
    end
    drop = ActsAsTenant.with_tenant(shop) { ThemeEngine::ProductDrop.new(product, url_prefix: "", publication: Publication.online_store!) }
    out = ActsAsTenant.with_tenant(shop) do
      render("{% form 'product', product %}{{ form | payment_button }}{% endform %}", { "product" => drop },
             { request_path: "/products/acme-tee", shop_id: shop.id, buyer_country: "TW", buyer_locale: "zh-CN", currency: "HKD" })
    end
    token = Storefront::AccessToken.for(shop.id)
    expect(token).to match(/\A[0-9a-f]{32}\z/)
    expect(out).to include(
      %(<div data-shopify="payment-button" class="shopify-payment-button"> <shopify-accelerated-checkout recommended="null" ) +
      %(fallback="{&quot;supports_subs&quot;:true,&quot;supports_def_opts&quot;:true,&quot;name&quot;:&quot;buy_it_now&quot;,&quot;wallet_params&quot;:{}}" ) +
      %(access-token="#{token}" buyer-country="TW" buyer-locale="zh-CN" buyer-currency="HKD" ) +
      %(variant-params="[{&quot;id&quot;:#{variant.id},&quot;requiresShipping&quot;:true}]" shop-id="#{shop.id}" enabled-flags="[&quot;a1d1f9a1&quot;]" disabled > ) +
      %(<div class="shopify-payment-button__button" role="button" disabled aria-hidden="true" style="background-color: transparent; border: none"> ) +
      %(<div class="shopify-payment-button__skeleton">&nbsp;</div> </div> </shopify-accelerated-checkout> </div>)
    )
  end

  it "P2 無 product 脈絡 ⇒ 空字串" do
    out = render("{% form 'product' %}[{{ form | payment_button }}]{% endform %}", {}, { request_path: "/", shop_id: 1 })
    expect(out).to include("[]")
  end

  it "P3 Normalizer 抹 access-token 與 shop-id" do
    n = RenderParity::Normalizer.new(host: "x.example")
    expect(n.call('<x access-token="4b93ca42cf1c603811a75df17e412e8f" shop-id="68893507687">')).to eq('<x access-token="TOKEN" shop-id="ID">')
  end
end
