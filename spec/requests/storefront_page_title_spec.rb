# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-8：`page_title` 各頁型（官方 objects/page_title "The page title of the current page."；值形＝真店逐字：
# 英文店 kyliecosmetics.com、中文店 hoko.vip，2026-09-03，兩店主題 layout 皆為 `{{ page_title }} &ndash; {{ shop.name }}` 形）：
#   首頁＝店名（hoko `<title>我的商店 3</title>`）；商品／系列／頁面／部落格／文章＝資源標題；
#   /collections/all＝"Products"／"商品"；/collections＝"Collections"／"产品系列"（hoko 逐字，繁體店出簡體字）；
#   vendors／types 虛擬系列＝q；搜尋無 q＝"Search"／"搜索"；有 q＝`Search: N results found for "q"`／
#   `搜尋：找到「q」的結果，共 N 筆`；購物車＝"Your Shopping Cart"／"您的購物車"；404＝"404 Not Found"／"404 找不到"。
# 原實作恆＝店名（hoko 稽核候選）。
#
# 🔴 假綺殺手矩陣（鐵律 20.2⑤）：
#   PT1 首頁＝店名、資源頁＝資源標題（殺：恆店名）
#   PT2 /collections/all／/collections／vendors 三種虛擬頁（殺：虛擬系列漏標題）
#   PT3 搜尋兩形＋計數同源 search.results_count（殺：計數寫死／無 q 仍出「找到…」）
#   PT4 購物車／404（殺：漏 status 404 分支）
#   PT5 zh-Hant 字串表（殺：只做英文）
RSpec.describe "Storefront page_title per page type", type: :request do
  let(:shop) { create(:shop, subdomain: "pt-shop", name: "PT Shop") }

  before do
    host! "pt-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
      product = create(:product, shop:, status: "active", handle: "pt-tee", title: "PT Tee", vendor: "Acme")
      create(:product_variant, shop:, product:, price_cents: 1000)
      c = Collection.create!(shop_id: shop.id, title: "Picks", handle: "picks", sort_order: "manual", description_html: "")
      CollectionProduct.create!(shop_id: shop.id, collection: c, product:, position: 1)
      Page.create!(shop_id: shop.id, title: "About Us", handle: "about", body_html: "<p>x</p>", published_at: 1.hour.ago)
      blog = Blog.create!(shop_id: shop.id, title: "News", handle: "news")
      Article.create!(shop_id: shop.id, blog:, title: "Hello World", handle: "hello", body_html: "<p>y</p>",
                      published_at: 1.hour.ago, author_name: "TC")
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def title_of(path)
    get path
    response.body[%r{<title>(.*?)</title>}m, 1]
  end

  it "PT1 🔴 首頁＝店名；商品／系列／頁面／部落格／文章＝資源標題" do
    expect(title_of("/en-hk/")).to eq("PT Shop")
    expect(title_of("/en-hk/products/pt-tee")).to eq("PT Tee")
    expect(title_of("/en-hk/collections/picks")).to eq("Picks")
    expect(title_of("/en-hk/pages/about")).to eq("About Us")
    expect(title_of("/en-hk/blogs/news")).to eq("News")
    expect(title_of("/en-hk/blogs/news/hello")).to eq("Hello World")
  end

  it "PT2 🔴 /collections/all＝Products；/collections＝Collections；vendors／types 虛擬系列＝q" do
    expect(title_of("/en-hk/collections/all")).to eq("Products")
    expect(title_of("/en-hk/collections")).to eq("Collections")
    expect(title_of("/en-hk/collections/vendors?q=Acme")).to eq("Acme")
    expect(title_of("/en-hk/collections/types?q=Mug")).to eq("Mug")
  end

  it "PT3 🔴 搜尋：無 q＝Search；有 q＝Search: N results found for \"q\"（N＝search.results_count）" do
    expect(title_of("/en-hk/search")).to eq("Search")
    expect(title_of("/en-hk/search?q=zzz-none")).to eq('Search: 0 results found for "zzz-none"')
    expect(title_of("/en-hk/search?q=PT")).to eq('Search: 1 results found for "PT"')
  end

  it "PT4 🔴 購物車＝Your Shopping Cart；404＝404 Not Found" do
    expect(title_of("/en-hk/cart")).to eq("Your Shopping Cart")
    expect(title_of("/en-hk/nope-404")).to eq("404 Not Found")
  end

  it "PT5 🔴 zh-Hant 字串表（hoko.vip 逐字）" do
    theme = ActsAsTenant.with_tenant(shop) { Theme.find_by!(shop_id: shop.id, role: "published") }
    pub = ActsAsTenant.with_tenant(shop) { Publication.online_store! }
    renderer = ThemeEngine::PageRenderer.new(
      theme:, shop:, publication: pub, locale: "zh-Hant",
      source: ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
    titles = %w[/cart /nope-404 /collections/all /collections /search].to_h do |p|
      [ p, renderer.render(p).html[%r{<title>(.*?)</title>}m, 1] ]
    end
    titles["/search?q=tee"] = renderer.render("/search", params: { "q" => "tee" }).html[%r{<title>(.*?)</title>}m, 1]
    expect(titles).to eq(
      "/cart" => "您的購物車", "/nope-404" => "404 找不到", "/collections/all" => "商品",
      "/collections" => "产品系列", "/search" => "搜索", "/search?q=tee" => "搜尋：找到「tee」的結果，共 1 筆" # PT Tee 命中 1 筆
    )
  end
end
