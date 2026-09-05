# frozen_string_literal: true

require "rails_helper"

# E17 fetch 端點逐字對表抓到的引擎缺口——單元格（取證＝docs/dev/external-facts.md §G25，hoko.vip 2026-09-05）：
#   U1 `url` 型 setting 回值物件：`{{ link }}`＝值、`{{ link.url }}`＝值（Ella `_menu-tab-item` `href="{{ link.url }}"` 對 "#" 出 `#`）；空值 ⇒ nil
#   U2 `img_url` 對 nil ⇒ 平台無圖佔位 URL（`//host/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_270x.gif`）；`image_url` 對 nil 仍 raise
#   U3 `date` 濾鏡用店時區（registers[:time_zone]）：同一 epoch 在 UTC 是 9/4、在 +08:00 是 9/5
#   U4 collection／search 的 sort_options.name 五語言逐字（zh-Hant 不再出簡體；fr 搜尋形 `Prix : faible à élevé` 帶空格冒號）
#   U5 AjaxJson：`/` ⇒ `\/`、`&` ⇒ `\\u0026`
#   U6 Normalizer 身分規則：替代模板 id、商品卡 id 屬性、推薦卡 grid item、商品 id 開頭的 block scope
#   U7 售罄訊息 zh-Hans 逐字 `产品“…”已售罄。`；無 locale ⇒ 既有文案
#   U8 `all_country_option_tags` option 之間換行、末尾無換行
#   U9 `.js` 端點形（ProductAjaxJson）：無 content、url 在 options 後、變體 22 鍵序、時戳店時區偏移、預設變體仍出 Title 選項
#   U10 `{{ country }}`（CountryDrop）字串化＝國名
#   U11 `product.collections` 含手動系列（collection_products）
RSpec.describe "E17 fetch parity units" do
  let(:shop) { create(:shop, subdomain: "e17u-shop") }

  def render(src, assigns = {}, registers = {})
    Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT)
                    .render(assigns, registers: { host: "e17u-shop.lvh.me", time_zone: "Asia/Hong_Kong" }.merge(registers))
  end

  it "U1 🔴 url 型 setting：值＋.url 同值；空值 nil" do
    settings = ThemeEngine::SettingsDrop.new({ "link" => "#", "ext" => "https://1.envato.market/dokaB2", "none" => "" },
                                             { "link" => "url", "ext" => "url", "none" => "url" })
    out = render("{{ s.link }}|{{ s.link.url }}|{{ s.ext.url }}|{% if s.none != blank %}Y{% else %}N{% endif %}", "s" => settings)
    expect(out).to eq("#|#|https://1.envato.market/dokaB2|N")
  end

  it "U2 🔴 img_url nil ⇒ 無圖佔位 URL（尺寸段照參數）；image_url nil 仍是 invalid url input" do
    expect(render("{{ nothing | img_url: '270x' }}")).to eq("//e17u-shop.lvh.me/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_270x.gif")
    expect(render("{{ nothing | img_url }}")).to eq("//e17u-shop.lvh.me/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12.gif")
    expect(render("{{ nothing | image_url: width: 270 }}")).to include("invalid url input")
  end

  it "U3 🔴 date 濾鏡＝店時區：2026-09-04T17:00Z 在 +08:00 是 9 月 5 日" do
    epoch = Time.utc(2026, 9, 4, 17).to_i
    expect(render("{{ #{epoch} | date: '%Y-%m-%d' }}")).to eq("2026-09-05")
    expect(render("{{ #{epoch} | date: '%Y-%m-%d' }}", {}, { time_zone: "UTC" })).to eq("2026-09-04")
    expect(render("{{ '#{epoch}' | date: '%Y-%m-%d' }}")).to eq("2026-09-05") # 字串形 epoch（Ella schema.liquid）
  end

  it "U4 🔴 sort_options.name 五語言逐字（collection 九項、search 三項）" do
    collection = ActsAsTenant.with_tenant(shop) { Collection.create!(shop_id: shop.id, title: "All", handle: "all-x", description_html: "") }
    names = ->(locale) { ThemeEngine::CollectionDrop.new(collection, locale:).sort_options.map { |o| o["name"] } }
    expect(names.("zh-Hans")).to eq([ "特色", "最相关", "畅销", "按字母顺序排序，A-Z", "按字母顺序排序，Z-A", "价格，从低到高", "价格，从高到低", "日期，从旧到新", "日期，从新到旧" ])
    expect(names.("zh-Hant")).to eq([ "精選", "最相關", "暢銷度", "依字母順序 (由 A 到 Z)", "依字母順序 (由 Z 到 A)", "價格 (從低到高)", "價格 (從高到低)", "日期 (從舊到新)", "日期 (從新到舊)" ])
    expect(names.("en")).to eq([ "Featured", "Most relevant", "Best selling", "Alphabetically, A-Z", "Alphabetically, Z-A", "Price, low to high", "Price, high to low", "Date, old to new", "Date, new to old" ])
    expect(names.("fr")).to eq([ "En vedette", "Le plus pertinent", "Meilleures ventes", "Alphabétique, de A à Z", "Alphabétique, de Z à A", "Prix: faible à élevé", "Prix: élevé à faible", "Date, de la plus ancienne à la plus récente", "Date, de la plus récente à la plus ancienne" ])
    expect(names.("ja")).to eq([ "オススメ", "関連性が最も高い", "ベストセラー", "アルファベット順, A-Z", "アルファベット順, Z-A", "価格の安い順", "価格の高い順", "古い商品順", "新着順" ])

    search = ->(locale) { ThemeEngine::SearchDrop.new(shop:, publication: nil, locale:, params: {}).sort_options.map { |o| o["name"] } }
    expect(search.("zh-Hans")).to eq([ "相关性", "价格，从低到高", "价格，从高到低" ])
    expect(search.("zh-Hant")).to eq([ "關聯性", "價格 (從低到高)", "價格 (從高到低)" ])
    expect(search.("en")).to eq([ "Relevance", "Price, low to high", "Price, high to low" ])
    expect(search.("fr")).to eq([ "Pertinence", "Prix : faible à élevé", "Prix : élevé à faible" ])
    expect(search.("ja")).to eq([ "関連性", "価格の安い順", "価格の高い順" ])
    expect(search.("de")).to eq([ "Relevance", "Price, low to high", "Price, high to low" ]) # 未取得語言退英文
  end

  it "U5 🔴 AjaxJson：斜線與 & 的跳脫形（本尊 predictive JSON url 逐字 _pos=1\\u0026_psq）" do
    out = Storefront::AjaxJson.dump({ "url" => "/en/products/a?x=1&y=2" })
    expect(out).to eq(%q({"url":"\/en\/products\/a?x=1\\u0026y=2"}))
  end

  it "U6 🔴 Normalizer：替代模板 id、商品 id 屬性、推薦卡 grid item、商品 id 開頭的 block scope 都抹成身分替身" do
    n = RenderParity::Normalizer.new(host: "x.example")
    expect(n.call('<div id="shopify-section-template--product-quick_add__main">')).to include('id="shopify-section-template--T__main"')
    expect(n.call('<div id="shopify-section-template--19763396411495__main">')).to include('id="shopify-section-template--T__main"')
    expect(n.call('<div data-product-card-id="7771802992743" data-product-compare-id="30" data-cart-edit-id="7">')).to eq('<div data-product-card-id="ID" data-product-compare-id="ID" data-cart-edit-id="ID">')
    expect(n.call('<li id="template--T__product_recommendations_ecaxGU-7771802992743-1">')).to include('ecaxGU-ID-1"')
    expect(n.call('id="product-form-template--T__product_recommendations_ecaxGU7771802992743AbjNlRGcvbVR4aWtTS__card_product_button_flex_3MFLXj"'))
      .to eq('id="product-form-template--T__product_recommendations_ecaxGUIDB__card_product_button_flex_3MFLXj"')
    expect(n.call('id="product-form-template--T__product_recommendations_ecaxGU31AEE02KlDJjKk91sVp3__card_product_button_flex_3MFLXj"'))
      .to eq('id="product-form-template--T__product_recommendations_ecaxGUIDB__card_product_button_flex_3MFLXj"')
    # __head__ 的兩個身分形：.woff 備援雜湊、JSON 跳脫的主題資產路徑（Ella photoswipeUrls）
    expect(n.call('url("/cdn/fonts/jost/jost_n4.791c46290e672b3f85c3d1c651ef2efa3819eadd.woff") format("woff")'))
      .to eq('url("/fonts/jost/jost_n4.woff") format("woff")')
    expect(n.call('{ css: "\/\/hoko.vip\/cdn\/shop\/t\/2\/assets\/lib-photoswipe.css" }')).to eq('{ css: "\/theme-assets\/lib-photoswipe.css" }')
  end

  it "U7 🔴 售罄訊息：zh-Hans 逐字本尊形；無 locale ⇒ 既有文案" do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 1000, title: "Default Title",
                                   product: create(:product, shop:, status: "active", title: "Acme Tee"))
      v.update!(inventory_policy: "deny")
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 0)
      cart = Cart.create!(shop_id: shop.id, token: SecureRandom.hex(16))
      expect { Storefront::CartWriter.add(cart:, variant_id: v.id, locale: "zh-Hans") }
        .to raise_error(Storefront::CartError, "产品“Acme Tee”已售罄。")
      expect { Storefront::CartWriter.add(cart:, variant_id: v.id) }
        .to raise_error(Storefront::CartError, "商品『Acme Tee』已售罄。")
    end
  end

  it "U8 🔴 all_country_option_tags：option 之間換行、末尾無換行" do
    all = ThemeEngine::CountryOptionTags.all(locale: "en")
    expect(all).to include("</option>\n<option value=\"Afghanistan\"")
    expect(all).not_to end_with("\n")
    expect(all.scan("\n").size).to eq(all.scan("<option ").size - 1)
  end

  it "U10 🔴 country 物件字串化＝國名（icon-flag--台湾）；country | image_url ⇒ 國旗 SVG URL（路徑形照本尊、width 參數照傳）" do
    c = ThemeEngine::CountryDrop.new({ "iso_code" => "TW", "name" => "台湾" })
    expect(render("icon-flag--{{ c }}|{{ c.iso_code }}", "c" => c)).to eq("icon-flag--台湾|TW")
    expect(render("url({{- c | image_url: width: 32 }})", "c" => c)).to eq("url(//e17u-shop.lvh.me/cdn/static/images/flags/tw.svg?width=32)")
    expect(render("{{ c | image_url }}", "c" => c)).to eq("//e17u-shop.lvh.me/cdn/static/images/flags/tw.svg")
    n = RenderParity::Normalizer.new(host: "hoko.vip")
    expect(n.call("url(//cdn.shopify.com/static/images/flags/tw.svg?width=32)")).to eq("url(/cdn/static/images/flags/tw.svg?width=32)")
  end

  it "U11 🔴 product.collections 含手動系列的成員（collection_products），不只物化表" do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title: "P", handle: "p-col")
      create(:product_variant, shop:, product:, price_cents: 100)
      collection = Collection.create!(shop_id: shop.id, title: "首頁", handle: "frontpage-x", description_html: "")
      CollectionProduct.create!(shop_id: shop.id, collection:, product:, position: 1)
      drop = ThemeEngine::ProductDrop.new(product, url_prefix: "", publication: Publication.online_store!)
      expect(drop.collections.map(&:title)).to eq([ "首頁" ])
    end
  end

  it "U9 🔴 .js 端點形：無 content、url 在 options 後、變體 22 鍵序、時戳店時區偏移、預設變體仍出 Title 選項" do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title: "Acme Tee", handle: "acme-tee")
      create(:product_variant, shop:, product:, price_cents: 18800)
      drop = ThemeEngine::ProductDrop.new(product, url_prefix: "", publication: Publication.online_store!)
      js = Storefront::ProductAjaxJson.js_form(drop, product:, zone: ActiveSupport::TimeZone["Asia/Hong_Kong"])
      expect(js.keys).to eq(%w[id title handle description published_at created_at vendor type tags price price_min price_max
                               available price_varies compare_at_price compare_at_price_min compare_at_price_max
                               compare_at_price_varies variants images featured_image options url requires_selling_plan
                               selling_plan_groups])
      expect(js["url"]).to eq("/products/acme-tee")
      expect(js["created_at"]).to end_with("+08:00")
      expect(js["variants"].first.keys).to eq(Storefront::ProductAjaxJson::VARIANT_KEYS)
      expect(js["variants"].first["quantity_price_breaks"]).to eq([])
      expect(js["options"]).to eq([ { "name" => "Title", "position" => 1, "values" => [ "Default Title" ] } ])
      liquid = JSON.parse(ThemeEngine::JsonSerializer.dump(drop))
      expect(liquid).to have_key("content") # Liquid `product | json` 形不動（83 §12.2）
      expect(liquid).not_to have_key("url")
    end
  end
end
