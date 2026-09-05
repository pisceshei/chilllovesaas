# frozen_string_literal: true

require "rails_helper"

# E17 fetch 端點逐字對表（docs/dev/e17-fetch-endpoints-parity.md；取證 external-facts §G25，hoko.vip 2026-09-05）——請求格：
#   F1 `/products/{handle}.js`：200 JSON、鍵序（…options, url, requires_selling_plan, selling_plan_groups）、無 content、變體 22 鍵、
#      時戳店時區偏移、斜線跳脫 `\/products\/`；帶前綴形同義；查無 ⇒ 404 空 body
#   F2 `/products/{handle}.json`：REST 形 `{"product":{…}}`、price 十進位字串、compare_at_price 無值＝""、price_currency
#   F3 predictive search 417：zh-Hant 前綴（section 形 text/html 逐字、JSON 形三鍵）；en 200
#   F4 搜尋零結果 ⇒ `search.filters` 空；有結果 ⇒ 非空
#   F5 `q=id:A OR id:B`：只回這些商品、順序＝relevance（created_at DESC），與 query 內順序無關
#   F8 搜尋結果的 `product.url` 帶 `?_pos={序}&_sid={9 hex}&_ss=r`；同一回應 _sid 相同、跨回應不同
#   F6 無圖佔位 gif 路由 200 image/gif
#   F7 predictive JSON：無 compare_at_price ⇒ "0.00"；無圖 ⇒ featured_image 五鍵 null 物件
#   F9 國旗路由（`country | image_url` 的目標）200 svg；未知碼 404
RSpec.describe "Storefront fetch parity (E17)", type: :request do
  let(:shop) { create(:shop, subdomain: "e17-shop") }

  before do
    host! "e17-shop.lvh.me"
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

  def make_product(title:, handle:, price:, at: nil)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title:, handle:)
      product.update_columns(created_at: at) if at
      create(:product_variant, shop:, product:, price_cents: price)
      product
    end
  end

  let!(:serum)  { make_product(title: "玫瑰精華", handle: "rose-serum", price: 18800, at: Time.zone.parse("2026-03-01")) }
  let!(:candle) { make_product(title: "檀香蠟燭", handle: "sandal-candle", price: 5000, at: Time.zone.parse("2026-01-01")) }

  it "F1 🔴 /products/{handle}.js：本尊 .js 形（鍵序、無 content、變體 22 鍵、+08:00 時戳、\\/ 跳脫）；帶前綴同義；查無 404" do
    get "/products/rose-serum.js"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.body).to include('"url":"\/products\/rose-serum"')
    j = JSON.parse(response.body)
    expect(j.keys).to eq(%w[id title handle description published_at created_at vendor type tags price price_min price_max
                            available price_varies compare_at_price compare_at_price_min compare_at_price_max
                            compare_at_price_varies variants images featured_image options url requires_selling_plan
                            selling_plan_groups])
    expect(j["created_at"]).to end_with("+08:00") # shop factory timezone Asia/Hong_Kong
    expect(j["variants"].first.keys).to eq(Storefront::ProductAjaxJson::VARIANT_KEYS)
    expect(j["variants"].first["quantity_price_breaks"]).to eq([])
    expect(j["price"]).to eq(18800)
    expect(j["options"]).to eq([ { "name" => "Title", "position" => 1, "values" => [ "Default Title" ] } ]) # 本尊 acme-tee.js 逐字

    get "/zh-hant/products/rose-serum.js"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["url"]).to eq("/zh-hant/products/rose-serum")

    get "/products/nope.js"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq("")
  end

  it "F2 🔴 /products/{handle}.json：REST 形（product 包裹、十進位價格字串、compare_at_price 空字串、price_currency）" do
    get "/products/rose-serum.json"
    expect(response).to have_http_status(:ok)
    j = JSON.parse(response.body)
    expect(j.keys).to eq([ "product" ])
    p = j["product"]
    expect(p.keys).to eq(%w[id title body_html vendor product_type created_at handle updated_at published_at template_suffix
                            published_scope tags variants options images image])
    v = p["variants"].first
    expect(v.keys).to eq(%w[id product_id title price sku position compare_at_price fulfillment_service inventory_management
                            option1 option2 option3 created_at updated_at taxable barcode grams image_id weight weight_unit
                            requires_shipping quantity_rule price_currency compare_at_price_currency quantity_price_breaks])
    expect(v["price"]).to eq("188.00")
    expect(v["compare_at_price"]).to eq("")
    expect(v["compare_at_price_currency"]).to eq("")
    expect(v["price_currency"]).to eq(shop.store_currency)
    expect(v["weight_unit"]).to eq("kg")
    expect(p["tags"]).to eq("")
    expect(p["image"]).to be_nil
    expect(p["options"].first.keys).to eq(%w[id product_id name position values])
  end

  it "F3 🔴 predictive search 對不支援語言回 417（section 形 text/html 逐字；JSON 形三鍵）；en 200" do
    get "/zh-hant/search/suggest", params: { q: "rose", section_id: "predictive-search" }
    expect(response).to have_http_status(:expectation_failed)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to eq("Expectation failed: Unsupported buyer locale")

    get "/zh-hant/search/suggest.json", params: { q: "rose" }
    expect(response).to have_http_status(:expectation_failed)
    expect(response.media_type).to eq("application/json")
    expect(JSON.parse(response.body)).to eq({ "status" => 417, "message" => "Expectation Failed",
                                              "description" => "Unsupported buyer locale" })

    get "/search/suggest", params: { q: "玫瑰", section_id: "predictive-search" }
    expect(response).to have_http_status(:ok)
    get "/search/suggest.json", params: { q: "玫瑰" }
    expect(response).to have_http_status(:ok)
  end

  it "F4 🔴 搜尋零結果 ⇒ search.filters 空（Ella 只出狀態句、無 facets）；有結果 ⇒ 非空" do
    get "/search?q=zzzzqq"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="scount">0</span>')
    expect(response.body).to include('<ul id="sfacets"></ul>')

    get "/search?q=#{CGI.escape('玫瑰')}"
    expect(response.body).to include('<span id="scount">1</span>')
    expect(response.body).to match(%r{<ul id="sfacets"><li data-f="filter\.v\.availability"})
  end

  it "F5 🔴 q=id:A OR id:B：只回這些商品、順序＝relevance（created_at DESC），與 query 內順序無關（本尊三組查詢實測）" do
    get "/search", params: { type: "product", q: "id:#{candle.id} OR id:#{serum.id}" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="scount">2</span>')
    expect(response.body.index('data-h="rose-serum"')).to be < response.body.index('data-h="sandal-candle"') # serum 2026-03 較新

    get "/search", params: { type: "product", q: "id:#{serum.id} OR id:#{candle.id}" }
    expect(response.body.index('data-h="rose-serum"')).to be < response.body.index('data-h="sandal-candle"')

    get "/search", params: { type: "product", q: "id:#{serum.id}" }
    expect(response.body).to include('<span id="scount">1</span>')
    expect(response.body).not_to include('data-h="sandal-candle"')
  end

  it "F8 🔴 搜尋結果 product.url 帶歸因參數 ?_pos={序}&_sid={9 hex}&_ss=r（同回應同 sid、跨回應不同）" do
    get "/search", params: { type: "product", q: "id:#{candle.id} OR id:#{serum.id}" }
    urls = response.body.scan(/data-u="([^"]+)"/)
    expect(urls.flatten).to match([ %r{\A/products/rose-serum\?_pos=1&_sid=[0-9a-f]{9}&_ss=r\z},
                                    %r{\A/products/sandal-candle\?_pos=2&_sid=[0-9a-f]{9}&_ss=r\z} ])
    sids = urls.flatten.map { |u| u[/_sid=([0-9a-f]{9})/, 1] }.uniq
    expect(sids.size).to eq(1)
    get "/search", params: { type: "product", q: "id:#{candle.id} OR id:#{serum.id}" }
    expect(response.body[/_sid=([0-9a-f]{9})/, 1]).not_to eq(sids.first)
  end

  it "F6 🔴 無圖佔位 gif 路由（img_url nil 的 URL 形）200 image/gif" do
    get "/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_270x.gif"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/gif")
    expect(response.body.bytes.first(6).pack("c*")).to eq("GIF89a")
    get "/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12.gif"
    expect(response).to have_http_status(:ok)
  end

  it "F9 🔴 國旗路由 /cdn/static/images/flags/{cc}.svg：200 image/svg+xml（MIT flag-icons 4x3）；未知碼 404" do
    get "/cdn/static/images/flags/tw.svg"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/svg+xml")
    expect(response.body).to include('viewBox="0 0 640 480"')
    get "/cdn/static/images/flags/zz.svg"
    expect(response).to have_http_status(:not_found)
  end

  it "F7 🔴 predictive JSON 商品條目：無 compare_at_price ⇒ \"0.00\"；無圖 ⇒ featured_image 五鍵 null 物件；斜線跳脫" do
    get "/search/suggest.json", params: { q: "玫瑰", resources: { type: "product" } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"url":"\/products\/rose-serum?_pos=1')
    item = JSON.parse(response.body).dig("resources", "results", "products").first
    expect(item["compare_at_price_max"]).to eq("0.00")
    expect(item["compare_at_price_min"]).to eq("0.00")
    expect(item["featured_image"]).to eq({ "alt" => nil, "aspect_ratio" => nil, "height" => nil, "url" => nil, "width" => nil })
  end
end
