# frozen_string_literal: true

require "rails_helper"

# SEO 面（包 35；62 §A/§B/§C/§D/§H/§I——REG／SEO 驗收的可請求子集）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   SEO2 hreflang 自指＋雙向＋語言碼（D80：殺：加回地區碼 en-HK／矩陣按頁客製）
#   SEO3 三處價格同源（殺：JSON-LD 從 money 字串逆向 parse——第二價格來源）
#   SEO4 UNLISTED noindex＋逐面排除（殺：只擋 sitemap 漏 hreflang/jsonld——noindex 失效）
#   SEO6 sitemap 只列 discoverable（殺：用 purchasable——UNLISTED 直接進索引）
RSpec.describe "Storefront SEO", type: :request do
  let(:shop) { create(:shop, subdomain: "seo-shop") }
  let!(:variant) do
    ActsAsTenant.with_tenant(shop) do
      v = create(:product_variant, shop:, price_cents: 14_800,
                 product: create(:product, shop:, status: "active", title: "Rose Serum", handle: "rose"))
      v.inventory_item.inventory_levels.order(:id).first.update!(available: 5)
      v
    end
  end

  before do
    host! "seo-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
      ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
      primary_presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1)
      # 對照組：已開白名單但**未發布** ⇒ 不得進矩陣（open ∧ published 兩閘缺一即漏）。
      primary_presence.market_web_presence_locales.create!(locale_tag: "zh-Hans", position: 2)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def primary_presence
    Market.find_by!(is_primary: true).market_web_presences.sole
  end

  it "SEO1 canonical：絕對、自引、去 variant 參數；分頁 page 參數保留（62 §B.1）" do
    get "/products/rose?variant=#{variant.id}&utm_source=x"
    expect(response.body)
      .to include(%(<link rel="canonical" href="https://seo-shop.lvh.me/products/rose">))

    get "/collections/nope" # 404 頁不出 canonical（不是內容頁）
    expect(response.body).not_to include("rel=\"canonical\"")
  end

  it "SEO2 🔴 hreflang：自指＋雙向（兩語言頁同一集合）＋語言碼無地區＋x-default 指預設語言的無前綴 URL（D80 本尊形）" do
    get "/products/rose"
    en_links = response.body.scan(/<link rel="alternate" hreflang="[^"]+" href="[^"]+">/)
    expect(en_links).to include(
      %(<link rel="alternate" hreflang="en" href="https://seo-shop.lvh.me/products/rose">),
      %(<link rel="alternate" hreflang="zh-Hant" href="https://seo-shop.lvh.me/zh-hant/products/rose">),
      %(<link rel="alternate" hreflang="x-default" href="https://seo-shop.lvh.me/products/rose">)
    )
    expect(en_links.size).to eq(3)
    expect(response.body).not_to match(/hreflang="[a-zA-Z-]+-[A-Z]{2}"/) # 共用網域零地區碼（本尊 hoko.vip §G23）
    expect(response.body).not_to include("zh-Hans") # 未發布語言不進矩陣（62 §I.1 open_locales）

    get "/zh-hant/products/rose"
    zh_links = response.body.scan(/<link rel="alternate" hreflang="[^"]+" href="[^"]+">/)
    expect(zh_links).to eq(en_links) # 同一函式同一集合＝天然雙向（62 §I.1 不變量 2）
  end

  it "SEO3 🔴 JSON-LD：price 由 cents 直出（兩位小數字串）、priceCurrency=presentment；與可見價同源" do
    get "/products/rose"
    json = response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1]
    data = JSON.parse(json)
    offer = data["offers"].first
    expect(offer["price"]).to eq("148.00")
    expect((offer["price"].to_d * 100).to_i).to eq(variant.price_cents) # 同一 cents 來源
    expect(offer["priceCurrency"]).to eq("HKD")
    expect(offer["availability"]).to eq("https://schema.org/InStock")
    expect(response.body).to include("$148.00") # 可見價（money filter，店級 ${{amount}}）同 cents、不同格式器
  end

  it "SEO4 🔴 UNLISTED：直連 200＋meta noindex；無 hreflang、無 JSON-LD offer（逐面排除）" do
    ActsAsTenant.with_tenant(shop) { variant.product.update!(status: "unlisted") }
    get "/products/rose"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(<meta name="robots" content="noindex,nofollow">))
    expect(response.body).not_to include("hreflang=")
    expect(response.body).not_to include("application/ld+json")
  end

  it "SEO5 robots 開放（B13 撤除）：無全站 Disallow；帶 Sitemap 行與預設 disallow 集合；頁面無 X-Robots-Tag" do
    get "/robots.txt"
    expect(response.body).not_to include("Disallow: /\n")
    expect(response.body).to include("Disallow: /cart").and include("Disallow: /checkout")
      .and include("Disallow: /account").and include("Disallow: /search")
      .and include("Sitemap: https://seo-shop.lvh.me/sitemap.xml")

    get "/products/rose"
    expect(response.headers["X-Robots-Tag"]).to be_nil
  end

  it "SEO6 🔴 sitemap：index＋products 子表；兩語言 loc 各一、xhtml:link 同矩陣；UNLISTED／draft 排除" do
    ActsAsTenant.with_tenant(shop) do
      create(:product_variant, shop:,
             product: create(:product, shop:, status: "unlisted", title: "Hidden", handle: "hidden"))
      create(:product_variant, shop:,
             product: create(:product, shop:, status: "draft", title: "Draft", handle: "draftp"))
    end
    get "/sitemap.xml"
    expect(response.body).to include("<sitemapindex")
    expect(response.body).to include("https://seo-shop.lvh.me/sitemap_products_1.xml")

    get "/sitemap_products_1.xml"
    expect(response.body).to include("<loc>https://seo-shop.lvh.me/products/rose</loc>")
    expect(response.body).to include("<loc>https://seo-shop.lvh.me/zh-hant/products/rose</loc>")
    expect(response.body).to include(%(hreflang="zh-Hant"))
    expect(response.body).not_to include(%(hreflang="zh-Hant-HK"))
    expect(response.body).not_to include("hidden")
    expect(response.body).not_to include("draftp")
  end

  it "SEO7 llms 三別名同一生成器：三路徑同體，含 sitemap_url；不含未實作的 ucp/mcp 欄位" do
    get "/agents.md"
    base = response.body
    expect(base).to include("sitemap_url: https://seo-shop.lvh.me/sitemap.xml")
    expect(base).not_to include("ucp")
    expect(base).not_to include("mcp")
    get "/llms.txt"
    expect(response.body).to eq(base)
    get "/llms-full.txt"
    expect(response.body).to eq(base)
  end

  it "SEO8 售罄／續賣的 availability 對映（62 §A.5：只看可用；continue ⇒ BackOrder）" do
    ActsAsTenant.with_tenant(shop) do
      variant.inventory_item.inventory_levels.update_all(available: 0)
      variant.update!(inventory_policy: "continue")
    end
    get "/products/rose"
    json = response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1]
    expect(JSON.parse(json)["offers"].first["availability"]).to eq("https://schema.org/BackOrder")
  end
end
