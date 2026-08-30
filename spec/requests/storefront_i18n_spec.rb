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
#   L2  /localization 剝舊前綴（殺：前綴疊加 /zh-hant-hk/en-hk/...）
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

  it "SF-1/SF-2 🔴 語言只由 URL 決定：三種 Accept-Language 同 URL 逐位元組同體；無 Vary: Accept-Language" do
    bodies = [ "zh-TW,zh;q=0.9", "en-US,en;q=0.9", "ja" ].map do |al|
      get "/en-hk/products/rose", headers: { "Accept-Language" => al }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Vary"].to_s).not_to include("Accept-Language")
      response.body
    end
    expect(bodies.uniq.length).to eq(1)
  end

  it "SF-3 語言不自動重導：帶中文 Accept-Language 打 /en-hk/ 仍 200（不 302 到 zh-hant）" do
    get "/en-hk/", headers: { "Accept-Language" => "zh-TW,zh-Hant;q=0.9" }
    expect(response).to have_http_status(:ok)
  end

  it "SF-5 🔴 三層字串：主題層鍵取主題值；主題缺鍵落平台字串集；zh-Hant 頁取 zh-Hant 兩層" do
    get "/en-hk/"
    expect(response.body).to include("Hello shopper")     # ② 主題 default 檔
    expect(response.body).to include(">Checkout<")        # ③ 平台字串集（主題無 cart.checkout）
    expect(response.body).not_to include("cart.checkout") # 不得吐 key 名

    get "/zh-hant-hk/"
    expect(response.body).to include("你好買家")           # ② 主題 zh-Hant 檔（JSONC）
    expect(response.body).to include(">結帳<")             # ③ 平台 zh-Hant
  end

  it "SF-6 🔴 JSONC 容錯：zh-Hant locale 檔帶 BOM＋區塊註解＋尾逗號仍正確解析（SF-5 後半已證，這裡釘檔案形態）" do
    raw = File.binread(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0/locales/zh-Hant.json"))
    expect(raw[0..2].bytes).to eq([ 0xEF, 0xBB, 0xBF ]) # BOM 真的在
    expect(raw).to include("/*").and include(",")
    expect(ThemeEngine::Runtime.tolerant_json(raw)).to eq({ "general" => { "hello" => "你好買家" } })
  end

  it "SF-7 🔴 主題內部連結帶前綴：zh-Hant 頁的 cart 連結是 /zh-hant-hk/cart" do
    get "/zh-hant-hk/"
    expect(response.body).to include(%(href="/zh-hant-hk/cart"))
  end

  it "CT1 🔴 內容翻譯走 drops：zh-Hant 商品頁出譯名、en 頁出原文（同一資源）" do
    get "/zh-hant-hk/products/rose"
    expect(response.body).to include("玫瑰精華")
    get "/en-hk/products/rose"
    expect(response.body).to include("Rose Serum")
    expect(response.body).not_to include("玫瑰精華")
  end

  it "SW1 切換器只列開放∧已發布（含 root_url 前綴）；未發布語言不出現" do
    ActsAsTenant.with_tenant(shop) do
      # zh-Hans enabled 未發布：開進白名單也不得出現在切換器（67 §F.2）。
      presence.market_web_presence_locales.create!(locale_tag: "zh-Hans", position: 2)
    end
    get "/en-hk/"
    expect(response.body).to include("en|English")
    expect(response.body).to include(%(href="/zh-hant-hk"))
    expect(response.body).not_to include("zh-Hans")
  end

  it "SF-10 🔴 前綴 ≡ 身分：cookie／偽 GeoIP 標頭不改變同 URL 的輸出" do
    get "/en-hk/products/rose"
    base = response.body
    get "/en-hk/products/rose", headers: { "Cookie" => "market=tw; locale=zh-Hant",
                                           "X-Forwarded-For" => "203.0.113.77" }
    expect(response.body).to eq(base)
  end

  it "SF-11②③⑤ 🔴 別市場前綴 200；關閉 ⇒ 404 且譯文一筆不刪；重開 ⇒ 原樣回來" do
    ActsAsTenant.with_tenant(shop) do
      tw = Market.create!(name: "TW", handle: "tw", status: "active", market_type: "region")
      tw.market_regions.create!(country_code: "TW")
      tw.market_web_presences.create!(subfolder_suffix: "xx", default_shop_locale: "en")
        .market_web_presence_locales.create!(locale_tag: "en", position: 0, is_market_default: false)
    end
    get "/en-tw/" # ② 別市場的合法前綴 ⇒ 200
    expect(response).to have_http_status(:ok)

    row = ActsAsTenant.with_tenant(shop) { presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant") }
    translation_count = ActsAsTenant.with_tenant(shop) { Translation.count }
    ActsAsTenant.with_tenant(shop) { row.close! }
    get "/zh-hant-hk/" # ③ 關閉 ⇒ 404
    expect(response).to have_http_status(:not_found)
    expect(ActsAsTenant.with_tenant(shop) { Translation.count }).to eq(translation_count) # ⑤ 不刪譯文

    ActsAsTenant.with_tenant(shop) { row.reopen! }
    get "/zh-hant-hk/products/rose"
    expect(response.body).to include("玫瑰精華") # 重開 ⇒ 譯文原樣回來
  end

  it "L1 /localization：切語言 ⇒ 302 到新前綴＋return_to 剝舊前綴；不支援語言落 presence 預設" do
    post "/localization", params: { language_code: "zh-Hant", country_code: "HK",
                                    return_to: "/en-hk/products/rose" }
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/zh-hant-hk/products/rose")

    post "/localization", params: { language_code: "fr", country_code: "HK", return_to: "/en-hk/" }
    expect(response.headers["Location"]).to end_with("/en-hk/") # fr 未開放 ⇒ 落預設 en
  end

  it "L2 🔴 帶前綴形也收（RoutesDrop 吐帶前綴 action）；open redirect 擋（// 開頭回根）" do
    post "/zh-hant-hk/localization", params: { language_code: "en", country_code: "HK",
                                               return_to: "/zh-hant-hk/products/rose" }
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/en-hk/products/rose")

    post "/localization", params: { language_code: "en", country_code: "HK", return_to: "//evil.example" }
    uri = URI.parse(response.headers["Location"])
    expect(uri.host.to_s).to satisfy { |h| h.empty? || h == "i18n-shop.lvh.me" }
    expect(uri.path).to eq("/en-hk/")
  end

  it "L3 切國家：country_code=TW ⇒ 落 TW 市場 presence 的前綴" do
    ActsAsTenant.with_tenant(shop) do
      tw = Market.create!(name: "TW", handle: "tw", status: "active", market_type: "region")
      tw.market_regions.create!(country_code: "TW")
      tw.market_web_presences.create!(subfolder_suffix: "xx", default_shop_locale: "en")
    end
    post "/localization", params: { country_code: "TW", language_code: "en", return_to: "/en-hk/" }
    expect(response.headers["Location"]).to end_with("/en-tw/")
  end

  it "L4 帶前綴 cart 路由（主題 POST 形）：/en-hk/cart/add 同語義" do
    variant = ActsAsTenant.with_tenant(shop) { product.product_variants.sole }
    post "/en-hk/cart/add", params: { id: variant.id, quantity: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].sole["variant_id"]).to eq(variant.id)
  end
end
