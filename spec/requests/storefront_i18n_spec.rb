# frozen_string_literal: true

require "rails_helper"

# i18n 前台（包 34；67 §F.2/F.3/F.4；驗收 §K SF 系列——SF-8 歸結帳線、SF-4 已由
# storefront_pages S4 覆蓋、SF-9③④ 已由 markets specs H5/U7 覆蓋，其餘在此）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   SF-1/SF-10 同 URL 恆同體（殺：Accept-Language／cookie 滲進渲染或快取 key）
#   SF-5 三層字串（殺：平台層沒接——主題缺 key 直接吐 key 名）
#   SF-6 JSONC（殺：BOM／尾逗號讓 zh-Hant 檔靜默解析失敗、整頁退回英文）
#   SF-7 連結帶前綴（殺：routes drop 丟前綴——切語言點一下就被踢回預設語言）
#   SF-11⑤ 關語言不刪譯文（殺：close 做成 delete）
#   L2  /localization 剝舊前綴（殺：前綴疊加 /zh-hant/...）
RSpec.describe "Storefront i18n", type: :request do
  let(:shop) { create(:shop, subdomain: "i18n-shop") }
  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 14_800,
                 product: create(:product, shop:, status: "active", title: "Rose Serum", handle: "rose"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      v.product
    end
  end

  before do
    host! "i18n-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
      # 發布 zh-Hant 並開進 primary presence 白名單（67 §C.8）。
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      # 內容翻譯（走正典 Upsert，不手捏列）。
      result = Translations::Upsert.call(
        shop:, resource_type: "PRODUCT", resource_id: product.id,
        source_locale: "en",
        source_values: { "title" => "Rose Serum", "body_html" => "" },
        translations: [ { locale: "zh-Hant", field: "title", value: "玫瑰精華" } ]
      )
      raise result.user_errors.inspect if result.user_errors.any?
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def presence
    Market.find_by!(is_primary: true).market_web_presences.sole
  end

  # E19：content_for_header 的每請求值（`__st.reqid`／`u`、`requestId`、`eventMetadataId`、shopify-y／s meta）本尊每次請求也不同 ⇒ 遮罩後比對
  def stable(body)
    body.gsub(/"reqid":"[^"]*"/, '"reqid":"R"').gsub(/"u":"[0-9a-f]{12}"/, '"u":"U"').gsub(/"requestId":"[^"]*"/, '"requestId":"R"')
        .gsub(/"eventMetadataId":"[^"]*"/, '"eventMetadataId":"E"').gsub(/name="shopify-[ys]" content="[^"]*" data-expiration="\d+"/, "META")
  end

  it "SF-1/SF-2 🔴 語言只由 URL 決定：三種 Accept-Language 同 URL 逐位元組同體；無 Vary: Accept-Language" do
    bodies = [ "zh-TW,zh;q=0.9", "en-US,en;q=0.9", "ja" ].map do |al|
      get "/products/rose", headers: { "Accept-Language" => al }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Vary"].to_s).not_to include("Accept-Language")
      response.body
    end
    expect(bodies.map { |b| stable(b) }.uniq.length).to eq(1)
  end

  it "SF-9 🔴 SRA 端點語言跟 URL 前綴：recommendations／search suggest／cart sections 在 /zh-hant/ 下取 zh-Hant 字串" do
    get "/zh-hant/recommendations/products", params: { product_id: product.id, section_id: "related-products" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="rhello">你好買家</span>')
    get "/recommendations/products", params: { product_id: product.id, section_id: "related-products" }
    expect(response.body).to include('<span id="rhello">Hello shopper</span>')
    # E17：predictive search 對中文／日文買家語言回 417（官方支援語言清單不含；hoko.vip zh-TW 2026-09-05 實測）——語言跟前綴的
    # 事實由 417 本身證明（en 無前綴 200）。
    get "/zh-hant/search/suggest", params: { q: "rose", section_id: "related-products" }
    expect(response).to have_http_status(:expectation_failed)
    expect(response.body).to eq("Expectation failed: Unsupported buyer locale")
    get "/search/suggest", params: { q: "rose", section_id: "related-products" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="rhello">Hello shopper</span>')
    variant_id = ActsAsTenant.with_tenant(shop) { product.product_variants.first.id }
    post "/zh-hant/cart/add", params: { id: variant_id, quantity: 1, sections: "related-products", sections_url: "/zh-hant/" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("sections", "related-products")).to include('<span id="rhello">你好買家</span>')
  end

  it "SF-9b 🔴 無前綴 SRA 端點以店預設 (market, locale) 渲染（E13：編輯器預覽內主題 JS 打無前綴 URL）：預設切 zh-Hant ⇒ 三端點取 zh-Hant 字串" do
    ActsAsTenant.with_tenant(shop) { presence.set_default_locale!("zh-Hant") }
    get "/recommendations/products", params: { product_id: product.id, section_id: "related-products" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="rhello">你好買家</span>')
    get "/search/suggest", params: { q: "rose", section_id: "related-products" }
    expect(response).to have_http_status(:expectation_failed) # E17：店預設 zh-Hant ⇒ 無前綴 predictive 也是 417（語言跟店預設）
    variant_id = ActsAsTenant.with_tenant(shop) { product.product_variants.first.id }
    post "/cart/add", params: { id: variant_id, quantity: 1, sections: "related-products", sections_url: "/" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("sections", "related-products")).to include('<span id="rhello">你好買家</span>')
    # 對照：預設仍 en 時無前綴端點回英文（不是硬編 zh-Hant）
    ActsAsTenant.with_tenant(shop) { presence.set_default_locale!("en") }
    get "/recommendations/products", params: { product_id: product.id, section_id: "related-products" }
    expect(response.body).to include('<span id="rhello">Hello shopper</span>')
  end

  it "SF-3 語言不自動重導：帶中文 Accept-Language 打 / 仍 200（不 302 到 zh-hant）" do
    get "/", headers: { "Accept-Language" => "zh-TW,zh-Hant;q=0.9" }
    expect(response).to have_http_status(:ok)
  end

  it "SF-5 🔴 三層字串：主題層鍵取主題值；主題缺鍵落平台字串集；zh-Hant 頁取 zh-Hant 兩層" do
    get "/"
    expect(response.body).to include("Hello shopper")     # ② 主題 default 檔
    expect(response.body).to include(">Checkout<")        # ③ 平台字串集（主題無 cart.checkout）
    expect(response.body).not_to include("cart.checkout") # 不得吐 key 名

    get "/zh-hant/"
    expect(response.body).to include("你好買家")           # ② 主題 zh-Hant 檔（JSONC）
    expect(response.body).to include(">結帳<")             # ③ 平台 zh-Hant
  end

  it "SF-6 🔴 JSONC 容錯：zh-Hant locale 檔帶 BOM＋區塊註解＋尾逗號仍正確解析（SF-5 後半已證，這裡釘檔案形態）" do
    raw = File.binread(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0/locales/zh-Hant.json"))
    expect(raw[0..2].bytes).to eq([ 0xEF, 0xBB, 0xBF ]) # BOM 真的在
    expect(raw).to include("/*").and include(",")
    expect(ThemeEngine::Runtime.tolerant_json(raw)).to eq({ "general" => { "hello" => "你好買家" } })
  end

  it "SF-7 🔴 主題內部連結帶前綴：zh-Hant 頁的 cart 連結是 /zh-hant/cart" do
    get "/zh-hant/"
    expect(response.body).to include(%(href="/zh-hant/cart"))
  end

  it "CT1 🔴 內容翻譯走 drops：zh-Hant 商品頁出譯名、en 頁出原文（同一資源）" do
    get "/zh-hant/products/rose"
    expect(response.body).to include("玫瑰精華")
    get "/products/rose"
    expect(response.body).to include("Rose Serum")
    expect(response.body).not_to include("玫瑰精華")
  end

  it "SW1 切換器只列開放∧已發布（含 root_url 前綴）；未發布語言不出現" do
    ActsAsTenant.with_tenant(shop) do
      # zh-Hans enabled 未發布：開進白名單也不得出現在切換器（67 §F.2）。
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hans", position: 2)
    end
    get "/"
    expect(response.body).to include("en|English")
    expect(response.body).to include(%(href="/zh-hant"))
    expect(response.body).not_to include("zh-Hans")
  end

  it "SF-10 🔴 語言 ≡ URL：無關 cookie／偽 GeoIP 標頭／不屬任何市場的 localization cookie 都不改變同 URL 的輸出" do
    get "/products/rose"
    base = stable(response.body)
    get "/products/rose", headers: { "Cookie" => "market=tw; locale=zh-Hant; localization=TW",
                                     "X-Forwarded-For" => "203.0.113.77" }
    expect(stable(response.body)).to eq(base)
  end

  it "SF-11②③⑤ 🔴 別市場前綴 200；關閉 ⇒ 404 且譯文一筆不刪；重開 ⇒ 原樣回來" do
    ActsAsTenant.with_tenant(shop) do
      tw = Market.create!(name: "TW", handle: "tw", status: "active", market_type: "region")
      tw.market_regions.create!(country_code: "TW")
      tw.market_web_presences.create!(subfolder_suffix: "tw", default_shop_locale: "en")
        .market_web_presence_locales.create!(locale_tag: "en", position: 0, is_market_default: false)
    end
    get "/en-tw/" # ② 別市場（子資料夾 presence）的合法前綴 ⇒ 200（D80：子資料夾市場全部語言帶 /{lang}-{suffix}）
    expect(response).to have_http_status(:ok)

    row = ActsAsTenant.with_tenant(shop) { presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant") }
    translation_count = ActsAsTenant.with_tenant(shop) { Translation.count }
    ActsAsTenant.with_tenant(shop) { row.close! }
    get "/zh-hant/" # ③ 關閉 ⇒ 404
    expect(response).to have_http_status(:not_found)
    expect(ActsAsTenant.with_tenant(shop) { Translation.count }).to eq(translation_count) # ⑤ 不刪譯文

    ActsAsTenant.with_tenant(shop) { row.reopen! }
    get "/zh-hant/products/rose"
    expect(response.body).to include("玫瑰精華") # 重開 ⇒ 譯文原樣回來
  end

  it "L1 /localization：切語言 ⇒ 302 到新前綴＋return_to 剝舊前綴；不支援語言落 presence 預設" do
    post "/localization", params: { language_code: "zh-Hant", country_code: "HK",
                                    return_to: "/products/rose" }
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/zh-hant/products/rose")

    post "/localization", params: { language_code: "fr", country_code: "HK", return_to: "/zh-hant/products/rose" }
    expect(URI.parse(response.headers["Location"]).path).to eq("/zh-hant/products/rose") # fr 未開放 ⇒ 維持當前語言（return_to 前綴）
    post "/localization", params: { language_code: "fr", country_code: "HK", return_to: "/" }
    expect(URI.parse(response.headers["Location"]).path).to eq("/") # 無當前語言 ⇒ 落預設 en（無前綴）
  end

  it "L2 🔴 帶前綴形也收（RoutesDrop 吐帶前綴 action）；open redirect 擋（// 開頭回根）" do
    post "/zh-hant/localization", params: { language_code: "en", country_code: "HK",
                                               return_to: "/zh-hant/products/rose" }
    expect(response).to have_http_status(:found)
    expect(URI.parse(response.headers["Location"]).path).to eq("/products/rose") # en＝預設 ⇒ 無前綴

    post "/localization", params: { language_code: "en", country_code: "HK", return_to: "//evil.example" }
    uri = URI.parse(response.headers["Location"])
    expect(uri.host.to_s).to satisfy { |h| h.empty? || h == "i18n-shop.lvh.me" }
    expect(uri.path).to eq("/")
  end

  it "L3 切國家（有自己 presence 的市場）：country_code=TW ⇒ 302 到 TW 市場子資料夾 presence 的前綴" do
    ActsAsTenant.with_tenant(shop) do
      tw = Market.create!(name: "TW", handle: "tw", status: "active", market_type: "region")
      tw.market_regions.create!(country_code: "TW")
      tw.market_web_presences.create!(subfolder_suffix: "tw", default_shop_locale: "en")
    end
    post "/localization", params: { country_code: "TW", language_code: "en", return_to: "/" }
    expect(response.headers["Location"]).to end_with("/en-tw/")
    expect(response.cookies["localization"]).to be_nil
  end

  it "L3b 🔴 切國家（共用主網域市場，D80 本尊形）：country_code=US ⇒ 寫 localization cookie、留在同語言 URL；同 URL 之後以美國市場渲染" do
    ActsAsTenant.with_tenant(shop) do
      us = Market.create!(name: "美國", handle: "us", status: "active", market_type: "region")
      us.market_regions.create!(country_code: "US")
    end
    # 本尊（hoko.vip 2026-09-04）：country_code=US&return_to=/collections/all ⇒ 302 /collections/all ＋ Set-Cookie: localization=US; path=/
    post "/localization", params: { country_code: "US", return_to: "/products/rose" }
    expect(response).to have_http_status(:found)
    expect(URI.parse(response.headers["Location"]).path).to eq("/products/rose")
    expect(response.cookies["localization"]).to eq("US")
    expect(response.headers["Set-Cookie"].to_s).to include("localization=US").and include("path=/")
    # 本尊：country_code=JP&language_code=ja ⇒ 302 /ja/… ＋ Set-Cookie: localization=JP; path=/ja ⇒ 我方 zh-Hant 同形 path=/zh-hant
    post "/localization", params: { country_code: "US", language_code: "zh-TW", return_to: "/products/rose" }
    expect(URI.parse(response.headers["Location"]).path).to eq("/zh-hant/products/rose")
    expect(response.headers["Set-Cookie"].to_s).to include("localization=US").and include("path=/zh-hant")

    cookies.delete("localization") # 上面的 POST 已把 cookie 寫進整合測試的 cookie jar
    get "/products/rose"
    expect(response.body).to include(%(Shopify.country = "HK";)) # 無 cookie ⇒ primary 市場
    get "/products/rose", headers: { "Cookie" => "localization=US" }
    expect(response.body).to include(%(Shopify.country = "US";)) # cookie ⇒ 美國市場（頁快取 key 含 market，不互汙）
    expect(response.body).to include(%(Shopify.locale = "en")) # 語言仍只由 URL 決定
    get "/products/rose", headers: { "Cookie" => "localization=XX" }
    expect(response.body).to include(%(Shopify.country = "HK";)) # 不屬任何市場的國碼 ⇒ 原樣
  end

  it "L4 帶前綴 cart 路由（主題 POST 形）：/zh-hant/cart/add 同語義" do
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    post "/zh-hant/cart/add", params: { id: variant.id, quantity: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].sole["variant_id"]).to eq(variant.id)
  end

  # E16（external-facts §G24，hoko.vip 2026-09-04）：本尊 /localization 只取 return_to 的路徑＋query——絕對 URL（Ella JS 送
  # `window.location.href`）保留路徑與 query、外站 host 丟掉只剩路徑、`back` 不展開 ⇒ `/back`；換語言時對絕對 URL 同樣剝命中前綴。
  # 殺：先前「非 / 開頭一律回根」（真店表單每次切語言都落回首頁）。
  it "L2b 🔴 return_to 絕對 URL：同站保留路徑＋query；外站只剩路徑；back ⇒ /back；絕對 URL 的前綴也剝" do
    post "/localization", params: { country_code: "HK", return_to: "https://i18n-shop.lvh.me/products/rose?page=2&sort_by=x" }
    uri = URI.parse(response.headers["Location"])
    expect([ uri.path, uri.query ]).to eq([ "/products/rose", "page=2&sort_by=x" ])

    post "/localization", params: { country_code: "HK", return_to: "https://evil.example/x?y=1" }
    uri = URI.parse(response.headers["Location"])
    expect(uri.host.to_s).to satisfy { |h| h.empty? || h == "i18n-shop.lvh.me" }
    expect([ uri.path, uri.query ]).to eq([ "/x", "y=1" ])

    post "/localization", params: { country_code: "HK", return_to: "back" }
    expect(URI.parse(response.headers["Location"]).path).to eq("/back")

    post "/localization", params: { language_code: "en", country_code: "HK",
                                    return_to: "https://i18n-shop.lvh.me/zh-hant/products/rose?page=2" }
    uri = URI.parse(response.headers["Location"])
    expect([ uri.path, uri.query ]).to eq([ "/products/rose", "page=2" ]) # en＝預設 ⇒ 無前綴
  end

  # E16：`{% form 'localization' %}` 本尊形自帶 `_method=put` ⇒ Rack::MethodOverride 改寫成 PUT；只收 POST 的路由回 404
  # （bt3 mirror 店 2026-09-04 實測：Ella 真表單提交 404）。本尊 `PUT /localization` 直打 302（hoko.vip 2026-09-04，§G24）。
  it "L5 🔴 /localization 收 PUT：主題表單的 _method=put（裸與帶前綴兩形）與直打 PUT 都 302" do
    post "/localization", params: { _method: "put", form_type: "localization", utf8: "✓",
                                    country_code: "HK", return_to: "/products/rose" }
    expect(response).to have_http_status(:found)
    expect(URI.parse(response.headers["Location"]).path).to eq("/products/rose")

    post "/zh-hant/localization", params: { _method: "put", language_code: "zh-TW", country_code: "HK",
                                            return_to: "/zh-hant/products/rose" }
    expect(response).to have_http_status(:found)
    expect(URI.parse(response.headers["Location"]).path).to eq("/zh-hant/products/rose")

    put "/localization", params: { language_code: "zh-TW", country_code: "HK", return_to: "/products/rose" }
    expect(response).to have_http_status(:found)
    expect(URI.parse(response.headers["Location"]).path).to eq("/zh-hant/products/rose")
  end

  # E16：本尊前綴根的 return_to 不帶尾斜線（hoko.vip `/en/?section_id=…`／`/en?section_id=…` 皆出 `/en?section_id=…`，§G24）。
  it "SR8 🔴 帶前綴的 section 形：return_to＝`/zh-hant?section_id=…`（前綴根去尾斜線）、頁面路徑帶前綴" do
    get "/zh-hant/?section_id=sra-probe"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<input type="hidden" name="return_to" value="/zh-hant?section_id=sra-probe" />')
    get "/zh-hant/products/rose?section_id=sra-probe&variant=1"
    expect(response.body).to include('<input type="hidden" name="return_to" value="/zh-hant/products/rose?section_id=sra-probe&variant=1" />')
  end
end
