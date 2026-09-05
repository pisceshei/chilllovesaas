# frozen_string_literal: true

require "rails_helper"

# T13 政策頁本尊形（docs/dev/t13-policy-pages.md；external-facts §G29，hoko.vip /policies/privacy-policy 快照 2026-09-05＋官方 objects/policy／shop）——格：
#   PL1 🔴 `/policies/{kind}` 200：平台自產容器逐字（title h1／rte 內 body 縮排）、page_title＝政策標題、`shop-js-analytics` pageType policy、
#       `__st` 無 p／rtyp／rid、analytics meta page 只有 requestId、hreflang 有、無 atom／oembed；首節點＝平台樣式表 policy-{hash}.css（我方自寫本體）
#   PL2 🔴 未設或空 body 的政策 ⇒ 404（本尊 refund／terms／shipping／contact 皆 404）
#   PL3 語言前綴形 `/zh-hant/policies/{kind}` 200；`policy.url` 帶前綴
#   PL4 `shop.*_policy`／`shop.policies`：只含有內容者、序固定、未設者 nil（Kalles `shop.shipping_policy.body != blank` 判空）
#   PL5 頁級快取：政策改內容後頁面即更新（resource stamp）
#   PL6 🔴 content_for_header 空白骨架照 hoko 位元組（T13 一併更正 E19a 的節點間換行／JSON 貼合／perf-kit 逐行屬性等 15 處）
RSpec.describe "Storefront policy pages (T13)", type: :request do
  let(:shop) { create(:shop, subdomain: "pl-shop") }
  let(:body_html) { "<div>\n  <p>最后更新时间：2026年9月4日</p>\n  <h2>联系方式</h2>\n  <p>正文</p>\n</div>" }

  before do
    host! "pl-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published", source: "first_party", license_attested: true)
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      Market.find_by!(is_primary: true).market_web_presences.sole.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      ShopPolicy.create!(shop_id: shop.id, kind: "privacy-policy", title: "隐私政策", body: body_html)
      ShopPolicy.create!(shop_id: shop.id, kind: "terms-of-service", title: "服务条款", body: "")
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def container(title, body)
    "<div class=\"shopify-policy__container\">\n  <div class=\"shopify-policy__title\">\n    <h1>#{title}</h1>\n  </div>\n\n" \
      "  <div class=\"shopify-policy__body\">\n    <div class=\"rte\">\n        #{body}\n    </div>\n  </div>\n</div>\n"
  end

  it "PL1 🔴 /policies/privacy-policy：本尊容器逐字＋head 資料形（pageType policy、__st 無 p、analytics page 只有 requestId、hreflang 有、無 atom／oembed）＋首節點樣式表" do
    get "/policies/privacy-policy"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(container("隐私政策", body_html))
    expect(response.body).to include("<title>隐私政策</title>")
    expect(response.body).to include(%(<script id="shop-js-analytics" type="application/json">{"pageType":"policy"}</script>))
    st = JSON.parse(response.body[/var __st=(\{.*?\});/, 1].gsub("\\/", "/"))
    expect(st.keys).to match_array(%w[a offset reqid pageurl u])
    expect(st["pageurl"]).to eq("pl-shop.lvh.me/policies/privacy-policy")
    meta = JSON.parse(response.body[/var meta = (\{.*?\});\n/, 1])
    expect(meta).to eq("page" => { "requestId" => meta.dig("page", "requestId") })
    expect(response.body).to include(%(hreflang="x-default"))
    expect(response.body).to include(%(hreflang="zh-Hant" href="https://pl-shop.lvh.me/zh-hant/policies/privacy-policy"))
    expect(response.body).not_to include("application/atom+xml")
    expect(response.body).not_to include("json+oembed")
    expect(response.body).not_to include("shopify-section-template--") # 無主題模板：容器直出，不經 sections
    # 首節點＝平台樣式表（緊接 perf mark、無換行，再換行接 digital-wallet）；本體我方自寫、雜湊檔名＋SRI；供給端 200 text/css
    link_re = %r{content_for_header\.start'\);</script>(<link rel="stylesheet" media="all" integrity="sha256-[^"]+" crossorigin="anonymous" href="//pl-shop\.lvh\.me/cdn/shopifycloud/storefront/assets/storefront/policy-[0-9a-f]{8}\.css">)\n<meta id="shopify-digital-wallet"}
    link = response.body[link_re, 1]
    expect(link).to be_present
    get link[%r{href="//pl-shop\.lvh\.me(/[^"]+)"}, 1]
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("text/css")
    expect(response.body).to include(".shopify-policy__container")
  end

  it "PL2 🔴 未設（refund-policy）與空 body（terms-of-service）的政策 ⇒ 404；未知 handle ⇒ 404" do
    get "/policies/refund-policy"
    expect(response).to have_http_status(:not_found)
    get "/policies/terms-of-service"
    expect(response).to have_http_status(:not_found)
    get "/policies/whatever"
    expect(response).to have_http_status(:not_found)
  end

  it "PL3 語言前綴形 200，policy.url 帶前綴" do
    get "/zh-hant/policies/privacy-policy"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(container("隐私政策", body_html))
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      create(:product_variant, shop:, product: p, price_cents: 18800)
    end
    get "/zh-hant/products/acme-tee?view=t13"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-t13-privacy-url>/zh-hant/policies/privacy-policy<))
  end

  it "PL4 shop.*_policy／shop.policies：只含有內容者、未設者 nil、序固定" do
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      create(:product_variant, shop:, product: p, price_cents: 18800)
      ShopPolicy.create!(shop_id: shop.id, kind: "refund-policy", title: "退款政策", body: "<p>退</p>")
    end
    get "/products/acme-tee?view=t13"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-t13-privacy-url>/policies/privacy-policy<))
    expect(response.body).to include(%(data-t13-privacy-title>隐私政策<))
    expect(response.body).to include(%(data-t13-shipping-blank>blank<))
    expect(response.body).to include(%(data-t13-count>2<))
    expect(response.body).to include(%(data-t13-kinds>/policies/refund-policy;/policies/privacy-policy;<)) # terms 空 body 不收錄
  end

  it "PL5 頁級快取隨政策內容更新（resource stamp：key 在政策 updated_at 變動後不同；test 環境 null_store 看不到命中，故直接鎖 key）" do
    get "/policies/privacy-policy"
    expect(response.body).to include("<p>正文</p>")
    key_args = ActsAsTenant.with_tenant(shop) do
      { shop: shop, theme: Theme.published.first, market: Market.find_by!(is_primary: true), locale_tag: "zh-Hans", path: "/policies/privacy-policy", params: {} }
    end
    before_key = Storefront::PageCache.key_for(**key_args)
    ActsAsTenant.with_tenant(shop) { ShopPolicy.find_by!(kind: "privacy-policy").update!(body: "<div>\n  <p>新正文</p>\n</div>", updated_at: 1.minute.from_now) }
    after_key = Storefront::PageCache.key_for(**key_args)
    expect(after_key).not_to eq(before_key)
    expect(after_key).to include("/policy/")
    get "/policies/privacy-policy"
    expect(response.body).to include("<p>新正文</p>")
    expect(response.body).not_to include("<p>正文</p>")
  end

  it "PL6 🔴 content_for_header 空白骨架照 hoko 位元組：features JSON 緊貼標籤；globals `false;</script>`；modules 單行；shop-js import 結尾空行；" \
     "UA 偵測緊接 origin-trials；dns-prefetch 前特定空白；TREKKIE shim 三行；analytics meta 緊接 web pixels；perf-kit 逐行屬性；shopify-s／new-cookie 緊接" do
    get "/policies/privacy-policy"
    b = response.body
    nl = "\n"
    expect(b).to include(%(<script id="shopify-features" type="application/json">{"accessToken"))
    expect(b).to match(/,"locale":"[a-z-]+"\}<\/script>\n<script>var Shopify = Shopify \|\| \{\};/)
    expect(b).to include("Shopify.SignInWithShop.User.recognized = false;</script>#{nl}<script type=\"module\">!function(o){(o.Shopify=o.Shopify||{}).modules=!0}(window);</script>#{nl}")
    expect(b).to include("initShopCartSync?.({\"fedCMEnabled\":true,\"windoidEnabled\":true});#{nl}#{nl}</script>")
    expect(b).to match(/\}\)\(\);<\/script><script id="shopify-origin-trials"/)
    expect(b).to include("shopify.content_for_header.end');</script>#{nl}#{nl}    #{nl}  <link href=\"https://pl-shop.lvh.me\" rel=\"dns-prefetch\">#{nl}<script>(function(){if(\"sendBeacon\"")
    expect(b).to include("<script>#{nl}  window.__TREKKIE_SHIM_QUEUE = window.__TREKKIE_SHIM_QUEUE || [];#{nl}</script>#{nl}<script>(function(){var cfg=")
    expect(b).to match(/\}\)\(\);<\/script><script>\n  window\.ShopifyAnalytics = window\.ShopifyAnalytics \|\| \{\};/)
    expect(b).to include("<script#{nl}  defer#{nl}  src=\"https://pl-shop.lvh.me/cdn/shopifycloud/perf-kit/shopify-perf-kit-3.8.9.min.js\"#{nl}  data-application=\"storefront-renderer\"#{nl}  data-shop-id=\"#{shop.id}\"#{nl}")
    expect(b).to include("data-shs-beacon-endpoint=\"https://pl-shop.lvh.me/api/collect\"#{nl}></script>#{nl}<meta name=\"shopify-y\"")
    expect(b).to match(/data-expiration="\d+"><meta name="shopify-s" content="[^"]+" data-expiration="\d+"><meta name="new-cookie-storage-activated" content="f">/)
  end
end
