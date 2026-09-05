# frozen_string_literal: true

require "rails_helper"

# E18 動態結帳（本尊 portable-wallets）逐字對表（docs/dev/e18-dynamic-checkout.md；取證 external-facts §G26，hoko.vip 2026-09-05）——請求格：
#   H1 商品頁 head：dynamic.init／buyer_consent／cleanup 三支 script、語言別 module script（zh-Hant 頁 ⇒ `portable-wallets.zh-tw.js`）、
#      nomodule、`link#shopify-accelerated-checkout-styles`、`style#shopify-accelerated-checkout-cart`；順序同本尊；body 有骨架
#   H2 模組路由：五語言各回 200 text/javascript 且文案逐字（en／zh-cn／zh-tw／fr／ja）；未知語言 ⇒ en 文案；樣式表 200 text/css
#   H3 `POST /api/unstable/graphql.json?operation_name=cartCreate`：回應鍵序＝抓包（data.result.cart{id,checkoutUrl,deliveryGroups,cost,
#      discountAllocations,discountCodes,lines}、errors、warnings、extensions{context,cart_changelog}）；amount 十進位字串 `"188.0"`；
#      cart id `gid://chilllove/Cart/{token}?key={32hex}`；checkoutUrl `{origin}/cart/c/{token}?key=…%3D%3D`；不動 `_cl_buyer` cookie
#   H4 售罄變體照建（本尊 errors 空）；token 錯 ⇒ 401；非 cartCreate ⇒ top-level errors
#   H5 `GET /cart/c/{token}?key=…` ⇒ 302 `/checkouts/{token}` 且結帳快照含該行；key 錯 ⇒ 404
#   H6 版本段 `2025-07` 同義；Normalizer 把 bootstrap script 本體視為替身
RSpec.describe "Storefront dynamic checkout (E18)", type: :request do
  let(:shop) { create(:shop, subdomain: "e18-shop") }

  before do
    host! "e18-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def presence
    Market.find_by!(is_primary: true).market_web_presences.sole
  end

  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      create(:product_variant, shop:, product: p, price_cents: 18800)
      p
    end
  end
  let(:variant) { ActsAsTenant.with_tenant(shop) { product.product_variants.first } }
  let(:token) { Storefront::AccessToken.for(shop.id) }

  def cart_create(lines:, headers: {}, version: "unstable", country: "TW", language: "ZH_CN")
    body = { query: "mutation cartCreate($input:CartInput!$country:CountryCode$language:LanguageCode)@inContext(country:$country language:$language){result:cartCreate(input:$input){cart{...CartParts}errors:userErrors{...on CartUserError{message field code}}warnings:warnings{...on CartWarning{code}}}}fragment CartParts on Cart{id checkoutUrl}",
             variables: { input: { lines:, discountCodes: [] }, country:, language: } }
    post "/api/#{version}/graphql.json?operation_name=cartCreate", params: body.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json",
                    "X-Shopify-Storefront-Access-Token" => token, "X-SDK-Variant" => "portable-wallets",
                    "X-Wallet-Name" => "BuyItNow", "X-Start-Wallet-Checkout" => "true" }.merge(headers)
    response
  end

  it "H1 🔴 商品頁 head 帶本尊順序的動態結帳 bootstrap；zh-Hant 頁載 zh-tw bundle；body 有骨架" do
    get "/zh-hant/products/acme-tee?view=e18" # fixture `product.e18.json`：帶 {% form 'product' %}＋payment_button
    expect(response).to have_http_status(:ok)
    html = response.body
    order = [
      '<script data-source-attribution="shopify.dynamic_checkout.dynamic.init">',
      '<script data-source-attribution="shopify.dynamic_checkout.buyer_consent">',
      "function portableWalletsCleanup(e)",
      '<script type="module" src="https://e18-shop.lvh.me/cdn/shopifycloud/portable-wallets/latest/portable-wallets.zh-tw.js" onError="portableWalletsCleanup(this)" crossorigin="anonymous"></script>',
      "<script nomodule>",
      '<link id="shopify-accelerated-checkout-styles" rel="stylesheet" media="screen" href="https://e18-shop.lvh.me/cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css" crossorigin="anonymous">',
      '<style id="shopify-accelerated-checkout-cart">'
    ]
    positions = order.map { |needle| html.index(needle) || raise("缺 #{needle[0, 60]}") }
    expect(positions).to eq(positions.sort)
    expect(html).to include('t.src="https://e18-shop.lvh.me/cdn/shopifycloud/portable-wallets/latest/portable-wallets.zh-tw.js",t.type="module"')
    expect(html.scan("shopify.dynamic_checkout.dynamic.init").size).to eq(1)
    expect(html).to include('<shopify-accelerated-checkout recommended="null"')
    expect(html).to include(%(access-token="#{token}" buyer-country="HK" buyer-locale="zh-TW" buyer-currency="HKD"))
    expect(html).to include(%(variant-params="[{&quot;id&quot;:#{variant.id},&quot;requiresShipping&quot;:true}]" shop-id="#{shop.id}"))
  end

  it "H2 模組五語言文案逐字（各語言 bundle 的 instruments_copy.checkout.buy_now）；未知語言 ⇒ en；樣式表 200" do
    { "en" => "Buy it now", "zh-cn" => "立即购买", "zh-tw" => "立即購買", "fr" => "Acheter maintenant", "ja" => "今すぐ購入", "de" => "Buy it now" }.each do |lang, label|
      get "/cdn/shopifycloud/portable-wallets/latest/portable-wallets.#{lang}.js"
      expect(response).to have_http_status(:ok), lang
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include(%(const BUY_NOW = #{label.to_json};)), lang
      expect(response.body).not_to include("__BUY_NOW_LABEL__")
    end
    expect(response.body).to include('customElements.define(tag, klass)')
    get "/cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/css")
    expect(response.body).to include("height: clamp(25px, var(--shopify-accelerated-checkout-button-block-size, 44px), 55px);")
  end

  it "H3 🔴 cartCreate：抓包同形（鍵序、amount 十進位字串、id key、checkoutUrl 形、extensions）；不動 _cl_buyer" do
    cart_create(lines: [ { merchandiseId: "gid://chilllove/ProductVariant/#{variant.id}", quantity: 2, attributes: [] } ])
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.cookies["_cl_buyer"]).to be_nil
    j = JSON.parse(response.body)
    expect(j.keys).to eq(%w[data extensions])
    expect(j["data"]["result"].keys).to eq(%w[cart errors warnings])
    cart = j["data"]["result"]["cart"]
    expect(cart.keys).to eq(%w[id checkoutUrl deliveryGroups cost discountAllocations discountCodes lines])
    record = ActsAsTenant.with_tenant(shop) { Cart.order(:id).last }
    expect(cart["id"]).to eq("gid://chilllove/Cart/#{record.token}?key=#{Storefront::CartKeys.id_key(record.token)}")
    expect(cart["id"]).to match(%r{\?key=[0-9a-f]{32}\z})
    expect(cart["checkoutUrl"]).to start_with("https://e18-shop.lvh.me/cart/c/#{record.token}?key=")
    expect(cart["checkoutUrl"]).to end_with("%3D%3D")
    expect(cart["deliveryGroups"]).to eq("edges" => [])
    expect(cart["cost"]).to eq("subtotalAmount" => { "amount" => "376.0", "currencyCode" => "HKD" },
                               "totalAmount" => { "amount" => "376.0", "currencyCode" => "HKD" },
                               "totalTaxAmount" => nil, "totalDutyAmount" => nil)
    expect(cart["discountAllocations"]).to eq([])
    expect(cart["discountCodes"]).to eq([])
    node = cart["lines"]["edges"].sole["node"]
    expect(node.keys).to eq(%w[parentRelationship quantity cost discountAllocations merchandise sellingPlanAllocation])
    expect(node["quantity"]).to eq(2)
    expect(node["merchandise"]).to eq("requiresShipping" => true, "title" => variant.title, "product" => { "title" => "Acme Tee" })
    expect(node["sellingPlanAllocation"]).to be_nil
    expect(j["data"]["result"]["errors"]).to eq([])
    expect(j["extensions"]["context"]).to eq("country" => "TW", "language" => "ZH_CN")
    changelog = JSON.parse(Base64.decode64(j["extensions"]["cart_changelog"]))
    expect(changelog["items_added"].sole).to include("product_id" => product.id, "variant_id" => variant.id, "image" => nil)
    expect(j["extensions"]["cart_changelog"]).to include("\n") # Rails Base64.encode64 形（每 60 字元換行）
    expect(ActsAsTenant.with_tenant(shop) { record.cart_line_items.sole.quantity }).to eq(2)
  end

  it "H4 售罄變體照建（本尊 errors 空）；token 錯 ⇒ 401；非 cartCreate ⇒ top-level errors" do
    allow(Storefront::CartWriter).to receive(:sellable?).and_return(false)
    cart_create(lines: [ { merchandiseId: "gid://chilllove/ProductVariant/#{variant.id}", quantity: 1, attributes: [] } ])
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["result"]["errors"]).to eq([])
    expect(JSON.parse(response.body)["data"]["result"]["cart"]["lines"]["edges"].size).to eq(1)

    cart_create(lines: [ { merchandiseId: "gid://chilllove/ProductVariant/#{variant.id}", quantity: 1 } ], headers: { "X-Shopify-Storefront-Access-Token" => "bad" })
    expect(response).to have_http_status(:unauthorized)

    post "/api/unstable/graphql.json?operation_name=productByHandle", params: { query: "query { product(handle: \"x\") { id } }" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "X-Shopify-Storefront-Access-Token" => token }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to have_key("errors")

    cart_create(lines: [ { merchandiseId: "gid://chilllove/ProductVariant/999999", quantity: 1 } ])
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["result"]["errors"].sole).to include("field" => [ "input", "lines" ], "code" => "INVALID")
  end

  it "H5 🔴 /cart/c/{token}?key= ⇒ 302 結帳頁且快照含該行；key 錯 ⇒ 404；版本段 2025-07 同義" do
    cart_create(lines: [ { merchandiseId: "gid://chilllove/ProductVariant/#{variant.id}", quantity: 3, attributes: [] } ], version: "2025-07")
    url = JSON.parse(response.body)["data"]["result"]["cart"]["checkoutUrl"]
    get URI.parse(url).request_uri
    expect(response).to have_http_status(:found)
    expect(response.location).to match(%r{\Ahttps://e18-shop.lvh.me/checkouts/[0-9a-f]{48}\z})
    checkout = ActsAsTenant.with_tenant(shop) { Checkout.order(:id).last }
    expect(checkout.line_items_snapshot.sole).to include("variant_id" => variant.id, "quantity" => 3, "unit_price_cents" => 18800)
    expect(response.cookies["_cl_buyer"]).to be_nil

    get "/cart/c/#{URI.parse(url).path.split('/').last}?key=nope"
    expect(response).to have_http_status(:not_found)
    get "/cart/c/#{URI.parse(url).path.split('/').last}"
    expect(response).to have_http_status(:not_found)
  end

  it "H6 Normalizer：bootstrap script 本體＝替身、bundle 語言檔名抹成 LANG" do
    n = RenderParity::Normalizer.new(host: "x.example")
    out = n.call(Storefront::DynamicCheckoutHead.build(origin: "https://x.example", locale_tag: "zh-Hant"))
    expect(out).to include('<script data-source-attribution="shopify.dynamic_checkout.dynamic.init">[platform]</script>')
    expect(out).to include('<script data-source-attribution="shopify.dynamic_checkout.buyer_consent">[platform]</script>')
    expect(out).to include("<script>[platform]</script>")
    expect(out).to include('src="/cdn/shopifycloud/portable-wallets/latest/portable-wallets.LANG.js"')
    expect(out).not_to include("portableWalletsHideBuyerConsent")
  end
end
