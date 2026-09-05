# frozen_string_literal: true

require "rails_helper"

# E19 content_for_header 完整本尊形（docs/dev/e19-content-for-header.md；取證 external-facts §G27，hoko.vip 74 頁 2026-09-05）——請求格：
#   C1 商品頁（有 payment_button）：節點序＝本尊商品頁 38 節點序（x-default 首、oembed、模組形、accelerated 樣式、sections-script／snippets-script）
#   C2 集合頁：atom link 首（自閉合）、無 oembed、cart.bootstrap 形、無 accelerated 樣式；分頁第 2 頁多 `rel="prev"`
#   C3 404 頁：無 hreflang／oembed；`__st` 只有 a／offset／reqid／pageurl／u；shop-js-analytics `{"pageType":"404"}`
#   C4 資料節點（商品頁）：shopify-features、`Shopify.*` 全域逐字、`__st`（p／rtyp／rid）、ShopifyAnalytics.meta（product／page）、trekkie track、perf-kit 屬性
#   C5 每請求值：placeholder 全部代入；`_shopify_y`（1 年）／`_shopify_s`（30 分鐘）cookie；meta 與 cookie 同值；再訪沿用 y
#   C6 平台端點：stub 資產 200 JS（雜湊不符 404）、preloads、sf_private_access_tokens 401、POST /api/collect 200、digital_wallets/dialog 200
#   C7 編譯資產：`compiled_assets/scripts.js` 門控函式（section＋其 schema blocks 的 JS）、`snippet-scripts.js`；`data-sections`／`data-snippets` 只列本頁渲染到的
#   C8 oEmbed（抓包形、`\/` 跳脫、price 數值）與 Atom（集合 entries／空部落格無 updated）
#   C9 Normalizer：本尊 head 片段與我方片段正規化後相等（身分／雜湊／每請求值／我方自寫本體）
RSpec.describe "Storefront content_for_header (E19)", type: :request do
  let(:shop) { create(:shop, subdomain: "e19-shop") }

  before do
    host! "e19-shop.lvh.me"
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
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee", vendor: "Acme", product_type: "Tee")
      create(:product_variant, shop:, product: p, price_cents: 18800)
      p
    end
  end
  let(:variant) { ActsAsTenant.with_tenant(shop) { product.product_variants.first } }
  let(:theme) { ActsAsTenant.with_tenant(shop) { Theme.published.first } }

  def st_of(html)
    JSON.parse(html[/var __st=(\{.*?\});/, 1].gsub("\\/", "/"))
  end

  # head 內 content_for_header 節點鍵序（同 scratchpad t10 的分類法）
  def node_keys(html)
    head = html[%r{<head\b.*?</head>}m]
    mark = head.index("shopify.content_for_header.start") or return []
    stop = head.index('name="new-cookie-storage-activated"', mark) or return []
    seg = head[head.rindex("<script", mark)..head.index(">", stop)]
    seg.scan(/<(script|link|style|meta)\b([^>]*)>/).map do |tag, attrs|
      a = attrs.squish
      key = a[/(?:\A|\s)(?:id|data-source-attribution|name|rel|class)=["']?([^"'\s>]+)/, 1]
      key = "hreflang:#{a[/hreflang="([^"]+)"/, 1]}" if key == "alternate" && a.include?("hreflang=")
      key = "atom" if key == "alternate" && a.include?("atom+xml")
      key = "oembed" if key == "alternate" && a.include?("oembed")
      key = "stylesheet:accelerated" if key == "shopify-accelerated-checkout-styles"
      key = "module:#{a[/src="[^"]*\/([^\/"?]+)(?:\?[^"]*)?"/, 1]}" if key.nil? && a.include?('type="module"') && a.include?("src=")
      key = "script-src:#{a[/src="[^"]*\/([^\/"?]+)(?:\?[^"]*)?"/, 1]}" if key.nil? && a.include?("src=")
      key = "script:#{tag}:#{a[0, 20]}" if key.nil?
      key
    end
  end

  it "C1 🔴 商品頁節點序＝本尊商品頁（x-default 首、oembed、模組形、accelerated 樣式、sections／snippets-script、analytics 尾段）" do
    get "/products/acme-tee?view=e19"
    expect(response).to have_http_status(:ok)
    keys = node_keys(response.body)
    expect(keys.first(11)).to eq([ "script:script:", "shopify-digital-wallet", "hreflang:x-default", "hreflang:en", "hreflang:zh-Hant", "oembed",
                                  "script-src:preloads.js", "shopify-features", "script:script:", "script:script:type=\"module\"", "script:script:" ])
    expect(keys).to include("shop-js-analytics", "__st", "captcha-bootstrap", "shopify.loadfeatures", "shopify-origin-trials",
                            "shopify.dynamic_checkout.dynamic.init", "shopify.dynamic_checkout.buyer_consent", "scb4127",
                            "stylesheet:accelerated", "shopify-accelerated-checkout-cart", "sections-script", "snippets-script", "shopify-cfh-end",
                            "dns-prefetch", "analytics", "shopify-y", "shopify-s", "new-cookie-storage-activated")
    expect(keys).not_to include("shopify.dynamic_checkout.cart.bootstrap")
    i = keys.index("shopify.dynamic_checkout.buyer_consent")
    expect(keys[i + 1]).to eq("script:script:") # portableWalletsCleanup
    expect(keys[i + 2]).to start_with("module:portable-wallets.zh-cn.js").or start_with("module:portable-wallets.")
    expect(keys[i + 3]).to eq("script:script:nomodule")
    expect(keys[i + 4]).to eq("scb4127")
    expect(keys[i + 5..i + 8]).to eq([ "stylesheet:accelerated", "shopify-accelerated-checkout-cart", "sections-script", "snippets-script" ])
    expect(keys.last(4)).to eq([ "script-src:shopify-perf-kit-#{Storefront::PlatformAssets::PERF_KIT_VERSION}.min.js", "shopify-y", "shopify-s", "new-cookie-storage-activated" ])
    expect(response.body).not_to include("application/ld+json") # 平台不注 JSON-LD（主題自出）
    expect(response.body.scan('rel="canonical"').size).to eq(1) # 只有主題的一個
  end

  it "C2 集合頁：atom link 首（自閉合）、無 oembed、cart.bootstrap 形；第 2 頁多 rel=prev；查詢頁 hreflang 帶 q／type、去 sort_by" do
    collection = ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "All", handle: "all", description_html: "")
      CollectionProduct.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id)
      c
    end
    get "/collections/all"
    expect(response).to have_http_status(:ok)
    keys = node_keys(response.body)
    expect(keys.first(4)).to eq([ "script:script:", "shopify-digital-wallet", "atom", "hreflang:x-default" ])
    expect(response.body).to include(%(<link rel="alternate" type="application/atom+xml" title="Feed" href="/collections/all.atom" />))
    expect(keys).not_to include("oembed", "stylesheet:accelerated", "nomodule")
    expect(keys).to include("shopify.dynamic_checkout.cart.bootstrap")
    expect(response.body).to include(%({"pageType":"collection"}))
    st = st_of(response.body)
    expect(st.keys).to eq(%w[a offset reqid pageurl u p])
    expect(st.values_at("a", "offset", "pageurl", "p")).to eq([ shop.id, 28800, "e19-shop.lvh.me/collections/all", "collection" ])
    expect(st["u"]).to match(/\A[0-9a-f]{12}\z/)
    expect(response.body).to include(%("category":"Collection: all","collectionName":"all"))
    get "/collections/all?page=2&sort_by=price-ascending"
    expect(response.body).to include(%(<link rel="prev" href="/collections/all?page=1">))
    expect(response.body).to include(%(<link rel="alternate" hreflang="x-default" href="https://e19-shop.lvh.me/collections/all?page=2">))
    hrefs = response.body.scan(/hreflang="[^"]+" href="([^"]+)"/).flatten
    expect(hrefs).to all(end_with("/collections/all?page=2")) # sort_by 不進 hreflang（本尊 §G27）
    expect(collection).to be_present
  end

  it "C3 404 頁：無 hreflang／oembed；__st 精簡；pageType 404；仍有 cfh 節點" do
    get "/products/nope"
    expect(response).to have_http_status(:not_found)
    keys = node_keys(response.body)
    expect(keys).to include("shopify-digital-wallet", "shopify-features", "__st", "shopify-cfh-end", "shopify-y")
    expect(keys.grep(/hreflang|oembed|atom/)).to eq([])
    st = st_of(response.body)
    expect(st.keys).to eq(%w[a offset reqid pageurl u])
    expect(st["pageurl"]).to eq("e19-shop.lvh.me/404") # 本尊 404 頁 pageurl 改寫成 /404（§G27）
    expect(response.body).to include(%(<script id="shop-js-analytics" type="application/json">{"pageType":"404"}</script>))
    expect(response.body).to include(%(var meta = {"page":{"requestId":"))
  end

  it "C4 🔴 資料節點（商品頁）：shopify-features、Shopify.* 逐字、__st、ShopifyAnalytics.meta、trekkie track、perf-kit 屬性" do
    get "/zh-hant/products/acme-tee?view=e19"
    body = response.body
    token = Storefront::AccessToken.for(shop.id)
    expect(body).to include(%(<script id="shopify-features" type="application/json">\n{"accessToken":"#{token}","betas":["rich-media-storefront-analytics"],"domain":"e19-shop.lvh.me","predictiveSearch":false,"shopId":#{shop.id},"locale":"zh-tw"}\n</script>))
    expect(body).to include(%(<script>var Shopify = Shopify || {};\nShopify.shop = "e19-shop.lvh.me";\nShopify.locale = "zh-TW";\nShopify.currency = {"active":"HKD","rate":"1.0"};\nShopify.country = "HK";\nShopify.theme = {"name":"Minimal","id":#{theme.id},))
    expect(body).to include(%(Shopify.cdnHost = "e19-shop.lvh.me/cdn";\nShopify.routes = Shopify.routes || {};\nShopify.routes.root = "/zh-hant/";\nShopify.shopJsCdnBaseUrl = "https://e19-shop.lvh.me/cdn/shopifycloud/shop-js";\nShopify.SignInWithShop = Shopify.SignInWithShop || {};\nShopify.SignInWithShop.User = Shopify.SignInWithShop.User || {};\nShopify.SignInWithShop.User.recognized = false;\n</script>))
    expect(body).not_to include("Shopify.formatMoney") # 主題自定義，平台不出
    st = st_of(body)
    expect(st.keys).to eq(%w[a offset reqid pageurl u p rtyp rid])
    expect(st.values_at("a", "offset", "pageurl", "p", "rtyp", "rid")).to eq([ shop.id, 28800, "e19-shop.lvh.me/zh-hant/products/acme-tee?view=e19", "product", "product", product.id ])
    expect(body).to include(%(src="/checkouts/internal/preloads.js?locale=zh-HK&default_configuration_id=#{shop.id}"))
    vname = variant.title == "Default Title" ? "Acme Tee" : "Acme Tee - #{variant.title}"
    vpublic = variant.title == "Default Title" ? "null" : variant.title.to_json
    expect(body).to include(%(var meta = {"product":{"id":#{product.id},"gid":"gid:\\/\\/chilllove\\/Product\\/#{product.id}","vendor":"Acme","type":"Tee","handle":"acme-tee","variants":[{"id":#{variant.id},"price":18800,"name":"#{vname}","public_title":#{vpublic},"sku":null}],"remote":false},"page":{"pageType":"product","resourceType":"product","resourceId":#{product.id},"requestId":"))
    expect(body).to include(%(window.ShopifyAnalytics.lib.track("Viewed Product",{"currency":"HKD","variantId":#{variant.id},"productId":#{product.id},"productGid":"gid:\\/\\/chilllove\\/Product\\/#{product.id}","name":"Acme Tee","price":"188.00","sku":null,"brand":"Acme","variant":#{vpublic},"category":"Tee","nonInteraction":true,"remote":false,"available":#{ActsAsTenant.with_tenant(shop) { Storefront::CartWriter.sellable?(variant) }}},undefined,undefined,{"shopifyEmitted":true});))
    expect(body).to include(%(data-application="storefront-renderer" data-shop-id="#{shop.id}" data-render-region="chilllove-hk-1" data-page-type="product" data-theme-instance-id="#{theme.id}"))
    expect(body).to include(%(<script id="shop-js-analytics" type="application/json">{"pageType":"product"}</script>))
    expect(body).to include(%(loader.init-shop-cart-sync.zh-TW.esm.js))
    expect(body).to include(%(<meta id="shopify-digital-wallet" name="shopify-digital-wallet" content="/#{shop.id}/digital_wallets/dialog">))
  end

  it "C5 每請求值：placeholder 全代入；_shopify_y／_shopify_s cookie 與 meta 同值；再訪沿用 y" do
    get "/products/acme-tee?view=e19"
    expect(response.body).not_to include("__CL_")
    y = response.cookies["_shopify_y"]
    s = response.cookies["_shopify_s"]
    expect(y).to match(/\A[0-9a-f-]{36}\z/)
    expect(s).to match(/\A[0-9a-f-]{36}\z/)
    expect(response.body).to include(%(<meta name="shopify-y" content="#{y}" data-expiration="))
    expect(response.body).to include(%(<meta name="shopify-s" content="#{s}" data-expiration="))
    reqid = response.body[/"reqid":"([^"]+)"/, 1]
    expect(reqid).to match(/\A[0-9a-f-]{36}-\d{10}\z/)
    expect(response.body.scan(reqid).size).to be >= 3 # __st、meta.page.requestId、lib.page
    get "/products/acme-tee?view=e19"
    expect(response.body).to include(%(<meta name="shopify-y" content="#{y}" data-expiration="))
    expect(response.body[/"reqid":"([^"]+)"/, 1]).not_to eq(reqid)
  end

  it "C6 平台端點：stub 資產 200／雜湊不符 404；preloads；sf_private_access_tokens 401；POST /api/collect 200；digital_wallets/dialog 200" do
    lf = Storefront::PlatformAssets::FILES[:load_feature]
    get "/cdn/shopifycloud/storefront/assets/storefront/#{lf[:name]}"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to include("S.loadFeatures = load")
    get "/cdn/shopifycloud/storefront/assets/storefront/load_feature-00000000.js"
    expect(response).to have_http_status(:not_found)
    get "/cdn/s/#{Storefront::PlatformAssets::FILES[:trekkie][:name]}"
    expect(response).to have_http_status(:ok)
    get "/cdn/shopifycloud/perf-kit/shopify-perf-kit-#{Storefront::PlatformAssets::PERF_KIT_VERSION}.min.js"
    expect(response).to have_http_status(:ok)
    get "/cdn/shopifycloud/privacy-banner/storefront-banner.js"
    expect(response).to have_http_status(:ok)
    get "/cdn/shopifycloud/shop-js/modules/v2/loader.init-shop-cart-sync.zh-TW.esm.js"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("export default")
    get "/cdn/storefront/webmcp/webmcp-0.1.1.js"
    expect(response).to have_http_status(:ok)
    get "/checkouts/internal/preloads.js?locale=zh-HK&default_configuration_id=#{shop.id}"
    expect(response).to have_http_status(:ok)
    get "/sf_private_access_tokens"
    expect(response).to have_http_status(:unauthorized)
    post "/api/collect", params: "{}", headers: { "CONTENT_TYPE" => "text/plain" }
    expect(response).to have_http_status(:ok)
    get "/#{shop.id}/digital_wallets/dialog"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="dialog"')
    get "/999999/digital_wallets/dialog"
    expect(response).to have_http_status(:not_found)
  end

  it "C7 🔴 編譯資產：sections-script／snippets-script 只列本頁渲染到的檔；scripts.js 門控函式含 section＋schema block 的 JS；snippet-scripts.js 同形" do
    get "/products/acme-tee?view=e19"
    # T12：`?v=`＝每檔摘要（≤20 位）＋主題版本秒（hoko 29 位形）
    expect(response.body).to match(%r{<script id="sections-script" data-sections="js-probe" defer="defer" src="//e19-shop\.lvh\.me/cdn/shop/t/#{theme.id}/compiled_assets/scripts\.js\?v=\d{1,20}#{theme.updated_at.to_i}"></script>})
    expect(response.body).to match(%r{<script id="snippets-script" data-snippets="js-snippet" defer="defer" src="//e19-shop\.lvh\.me/cdn/shop/t/#{theme.id}/compiled_assets/snippet-scripts\.js\?v=\d{1,20}#{theme.updated_at.to_i}"></script>})
    get "/products/acme-tee?view=e18" # 無 {% javascript %} 的頁 ⇒ 兩個節點都不出
    expect(response.body).not_to include('id="sections-script"')
    expect(response.body).not_to include('id="snippets-script"')
    get "/cdn/shop/t/#{theme.id}/compiled_assets/scripts.js?v=1"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
    expect(response.body).to start_with(%[(function(){var __sections__={};(function(){for(var i=0,s=document.getElementById("sections-script").getAttribute("data-sections").split(",");i<s.length;i++)__sections__[s[i]]=!0})(),])
    expect(response.body).to include(%[(function(){if(!(!__sections__["js-probe"]&&!Shopify.designMode))try{\nwindow.__jsProbeSection = true;\nwindow.__jsProbeBlock = true;\n}catch(e){console.error(e)}})()])
    expect(response.body).to end_with("})();\n")
    get "/cdn/shop/t/#{theme.id}/compiled_assets/snippet-scripts.js?v=1"
    expect(response.body).to include(%[(function(){var __snippets__={};(function(){for(var element=document.getElementById("snippets-script"),attribute=element?element.getAttribute("data-snippets"):"",snippets=attribute.split(",").filter(Boolean),i=0;i<snippets.length;i++)__snippets__[snippets[i]]=!0})(),])
    expect(response.body).to include(%[if(!(!__snippets__["js-snippet"]&&!Shopify.designMode))try{\nwindow.__jsProbeSnippet = true;\n}])
    get "/cdn/shop/t/999999/compiled_assets/scripts.js"
    expect(response).to have_http_status(:not_found)
  end

  it "C8 oEmbed（抓包形、\\/ 跳脫、price 數值）與 Atom（集合 entries；空部落格無 updated）" do
    get "/products/acme-tee.oembed"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json+oembed")
    expect(response.body).to eq(%({"product_id":"acme-tee","title":"Acme Tee","description":"","brand":"Acme","offers":[{"title":"#{variant.title}","offer_id":#{variant.id},"sku":null,"price":188.0,"currency_code":"HKD","in_stock":true}],"url":"https:\\/\\/e19-shop.lvh.me\\/products\\/acme-tee","provider":"#{shop.name}","version":"1.0","type":"link"}))
    ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "All", handle: "all", description_html: "")
      CollectionProduct.create!(shop_id: shop.id, collection_id: c.id, product_id: product.id)
      Blog.create!(shop_id: shop.id, title: "最新消息", handle: "news")
    end
    get "/collections/all.atom"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/atom+xml")
    xml = response.body
    expect(xml).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>\n<feed xml:lang="en" xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" xmlns:s="http://jadedpixel.com/-/spec/shopify">\n  <id>https://e19-shop.lvh.me/collections/all.atom</id>\n))
    expect(xml).to include(%(<link rel="alternate" type="text/html" href="https://e19-shop.lvh.me/collections/all"/>))
    expect(xml).to include(%(<title>#{shop.name}</title>))
    expect(xml).to include(%(<id>https://e19-shop.lvh.me/products/#{product.id}</id>))
    flat = xml.gsub(/\s+/, " ")
    expect(flat).to include(%(<s:type>Tee</s:type> <s:vendor>Acme</s:vendor>))
    expect(flat).to include(%(<strong>Vendor: </strong>Acme<br> <strong>Type: </strong>Tee<br> <strong>Price: </strong> 188.00))
    expect(flat).to include(%(<s:price currency="HKD">188.00</s:price> <s:sku/> <s:grams>0</s:grams>))
    get "/zh-hant/collections/all.atom"
    expect(response.body).to include(%(<feed xml:lang="zh-TW"))
    expect(response.body).to include("<strong>廠商： </strong>Acme<br>")
    expect(response.body).to include(%(<link rel="alternate" type="text/html" href="https://e19-shop.lvh.me/zh-hant/collections/all"/>))
    get "/blogs/news.atom"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(<title>#{shop.name} - 最新消息</title>))
    expect(response.body).not_to include("<updated>")
    expect(response.body).to end_with("  </author>\n</feed>\n")
  end

  it "C9 Normalizer：本尊 head 片段與我方片段正規化後相等（身分／雜湊／每請求值／自寫本體）" do
    n = RenderParity::Normalizer.new(host: "x.example")
    hoko = %(<script integrity="sha256-JjoPp5ZfB1sSAs5SQaol1x1GgvveM+BgmRzyDexInEQ=" data-source-attribution="shopify.loadfeatures" defer="defer" src="//hoko.vip/cdn/shopifycloud/storefront/assets/storefront/load_feature-1bd60354.js" crossorigin="anonymous"></script>) +
           %(<script id="__st">var __st={"a":68893507687,"offset":28800,"reqid":"7f7a37d5-6f49-4b6d-ab58-b4e610b10cd4-1788574966","pageurl":"hoko.vip\\/products\\/acme-tee","u":"c5ec37a2b792","p":"product","rtyp":"product","rid":7771796897895};</script>) +
           %(<script defer="defer" async type="module" src="https://cdn.shopify.com/shopifycloud/shop-js/modules/v2/loader.init-shop-cart-sync.zh-CN.esm.js"></script>) +
           %(<meta name="shopify-y" content="20b4842b-b6a1-4240-849f-e225cf3fac61" data-expiration="1820132567000">) +
           %(<script id="captcha-bootstrap">!function(){'use strict';const t='contact'}();</script>)
    ours = %(<script integrity="sha256-abc" data-source-attribution="shopify.loadfeatures" defer="defer" src="//x.example/cdn/shopifycloud/storefront/assets/storefront/load_feature-0badf00d.js" crossorigin="anonymous"></script>) +
           %(<script id="__st">var __st={"a":5,"offset":28800,"reqid":"00000000-0000-4000-8000-000000000000-1700000000","pageurl":"x.example\\/products\\/acme-tee","u":"000000000000","p":"product","rtyp":"product","rid":29};</script>) +
           %(<script defer="defer" async type="module" src="https://x.example/cdn/shopifycloud/shop-js/modules/v2/loader.init-shop-cart-sync.zh-CN.esm.js"></script>) +
           %(<meta name="shopify-y" content="11111111-1111-4111-8111-111111111111" data-expiration="1">) +
           %(<script id="captcha-bootstrap">!function(){var w=window}();</script>)
    expect(n.call(ours)).to eq(RenderParity::Normalizer.new(host: "hoko.vip").call(hoko))
  end
end
