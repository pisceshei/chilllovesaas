# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-4：Collection／Blog／Page／Article／Product drops 缺屬性＋`/collections/vendors|types` 路由
# ＋url_for_type。官方：shopify.dev objects/collection・blog・article・page・product、filters/url_for_vendor・
# url_for_type（取證 2026-09-02）；D78 triage 已驗證項 CollectionDrop.all_tags／featured_image／metafields、
# BlogDrop.next_article／previous_article、PageDrop.metafields、ProductDrop.created_at；
# gap-triage-m59 的 current_vendor／current_type／sort_options。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   G1 /collections/vendors?q=／types?q= ⇒ 虛擬系列 title＝q、商品以 vendor／type 過濾（殺：不過濾＝全商品）
#   G2 sort_options 九項官方 name/value；all_tags／tags／all_types／all_vendors；featured_image 退回第一個
#      商品的圖；真系列 current_vendor nil（殺：sort_options 漏項／順序、featured_image 恆 nil）
#   G3 blog.next_article＝較舊、previous_article＝較新、端點 nil（殺：方向反、非文章頁誤有值）
#   G4 product.created_at；article.image／collection.image 宣告為 nil 不計 miss；page／blog／collection
#      metafields 走同一 MetafieldsRootDrop（殺：仍計 miss／回 {}）
#   G5 url_for_vendor／url_for_type 官方逐字例（殺：`+` 編碼）
RSpec.describe "Storefront drops gap (collection/blog/page/article/product)", type: :request do
  let(:shop) { create(:shop, subdomain: "g4-shop") }

  before do
    host! "g4-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  # active＋自動發布＝discoverable（storefront_collections_spec 同形）
  def make_product(title:, handle:, vendor:, product_type:, tags:)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title:, handle:, vendor:, product_type:, tags:)
      create(:product_variant, shop:, product:, price_cents: 1000)
      product
    end
  end

  let!(:tee) { make_product(title: "Acme Tee", handle: "acme-tee", vendor: "Acme", product_type: "Tee", tags: %w[red new]) }
  let!(:mug) { make_product(title: "Bolt Mug", handle: "bolt-mug", vendor: "Bolt", product_type: "Mug", tags: %w[blue]) }
  let!(:collection) do
    ActsAsTenant.with_tenant(shop) do
      c = Collection.create!(shop_id: shop.id, title: "Picks", handle: "picks", sort_order: "manual", description_html: "")
      CollectionProduct.create!(shop_id: shop.id, collection: c, product: tee, position: 1)
      CollectionProduct.create!(shop_id: shop.id, collection: c, product: mug, position: 2)
      c
    end
  end

  def render(src, assigns)
    ActsAsTenant.with_tenant(shop) do
      Liquid::Template.parse(src, environment: ThemeEngine::Runtime::ENVIRONMENT).render(assigns, registers: {})
    end
  end

  def publication = ActsAsTenant.with_tenant(shop) { Publication.online_store! }

  it "G1 🔴 /collections/vendors?q=／types?q=：title＝q、只列該 vendor／type 的商品；無 q ⇒ 全商品" do
    get "/collections/vendors?q=Acme"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1 id="ctitle">Acme</h1>')
    expect(response.body).to include('data-h="acme-tee"')
    expect(response.body).not_to include('data-h="bolt-mug"')

    get "/collections/types?q=Mug"
    expect(response.body).to include('<h1 id="ctitle">Mug</h1>')
    expect(response.body).to include('data-h="bolt-mug"')
    expect(response.body).not_to include('data-h="acme-tee"')

    get "/collections/vendors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1 id="ctitle">Products</h1>').and include('data-h="acme-tee"').and include('data-h="bolt-mug"')
  end

  it "G2 🔴 collection 屬性：sort_options 九項、all_tags／tags／all_types／all_vendors、featured_image 退回商品圖、current_vendor nil" do
    drop = ThemeEngine::CollectionDrop.new(collection, publication: publication)
    out = render("{{ collection.all_tags | join: ',' }}|{{ collection.tags | join: ',' }}|" \
                 "{{ collection.all_types | join: ',' }}|{{ collection.all_vendors | join: ',' }}|" \
                 "[{{ collection.current_vendor }}{{ collection.current_type }}]|" \
                 "{% for o in collection.sort_options %}{{ o.name }}={{ o.value }};{% endfor %}|" \
                 "{{ collection.featured_image.src | slice: 0, 18 }}|{{ collection.image }}", "collection" => drop)
    expect(out).to eq(
      "blue,new,red|blue,new,red|Mug,Tee|Acme,Bolt|[]|" \
      "Featured=manual;Most relevant=most-relevant;Best selling=best-selling;Alphabetically, A-Z=title-ascending;" \
      "Alphabetically, Z-A=title-descending;Price, low to high=price-ascending;Price, high to low=price-descending;" \
      "Date, old to new=created-ascending;Date, new to old=created-descending;||" # E8b：無圖商品 ⇒ featured_image nil（PP13），不再退佔位
    )

    vendor_page = ThemeEngine::CollectionDrop.new(
      ThemeEngine::VirtualAllCollection.new("Acme", "vendors", "title_asc", nil, nil, "Acme", nil), publication: publication
    )
    expect(render("{{ collection.current_vendor }}/{{ collection.all_types | join: ',' }}/{{ collection.products_count }}",
                  "collection" => vendor_page)).to eq("Acme/Tee/1")
  end

  it "G3 🔴 blog.next_article＝較舊、previous_article＝較新、端點 nil、非文章頁 nil" do
    ActsAsTenant.with_tenant(shop) do
      blog = Blog.create!(shop_id: shop.id, title: "News", handle: "news")
      %w[old mid new].each_with_index do |h, i|
        Article.create!(shop_id: shop.id, blog:, title: h, handle: h, body_html: "<p>#{h}</p>",
                        published_at: (3 - i).days.ago, author_name: "TC")
      end
    end

    get "/blogs/news/mid"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<span id="anext">news/old</span><span id="aprev">news/new</span>')
    get "/blogs/news/old"
    expect(response.body).to include('<span id="anext"></span><span id="aprev">news/mid</span>')
    get "/blogs/news/new"
    expect(response.body).to include('<span id="anext">news/mid</span><span id="aprev"></span>')

    blog = ActsAsTenant.with_tenant(shop) { Blog.find_by!(handle: "news") }
    expect(render("[{{ blog.next_article }}{{ blog.previous_article }}]", "blog" => ThemeEngine::BlogDrop.new(blog)))
      .to eq("[]")
  end

  it "G4 🔴 created_at／image／metafields：宣告即不計 miss；metafields 走 MetafieldsRootDrop" do
    page, article, blog = ActsAsTenant.with_tenant(shop) do
      b = Blog.create!(shop_id: shop.id, title: "Notes", handle: "notes")
      a = Article.create!(shop_id: shop.id, blog: b, title: "A", handle: "a", body_html: "<p>a</p>",
                          published_at: 1.hour.ago, author_name: "TC")
      p = Page.create!(shop_id: shop.id, title: "About", handle: "about", body_html: "<p>x</p>", published_at: 1.hour.ago)
      definition = MetafieldDefinition.create!(shop_id: shop.id, namespace: "custom", key: "tagline", name: "Tagline",
                                               owner_type: "Page", value_type: "single_line_text_field")
      Metafield.create!(shop_id: shop.id, metafield_definition: definition, owner_type: "Page", owner_id: p.id, value: "hi")
      [ p, a, b ]
    end
    ThemeEngine::MISSES.clear
    out = render("{{ product.created_at | slice: 0, 4 }}|[{{ article.image }}]|[{{ collection.image }}]|" \
                 "{{ page.metafields.custom.tagline.value }}|[{{ blog.metafields.custom.nope }}]|[{{ collection.metafields.custom.nope }}]",
                 "product" => ThemeEngine::ProductDrop.new(tee), "article" => ThemeEngine::ArticleDrop.new(article),
                 "collection" => ThemeEngine::CollectionDrop.new(collection), "page" => ThemeEngine::PageDrop.new(page),
                 "blog" => ThemeEngine::BlogDrop.new(blog))
    expect(out).to eq("#{Time.current.year}|[]|[]|hi|[]|[]")
    expect(ThemeEngine::MISSES.keys.grep(/\A(ProductDrop\.created_at|ArticleDrop\.image|CollectionDrop\.(image|metafields)|PageDrop\.metafields|BlogDrop\.metafields)\z/))
      .to eq([])
  end

  it "G5 url_for_vendor／url_for_type 官方逐字例（percent-encoding）" do
    out = render("{{ \"Polina's Potent Potions\" | url_for_vendor }}|{{ 'health' | url_for_type }}|{{ 'Health & Beauty' | url_for_type }}", {})
    expect(out).to eq("/collections/vendors?q=Polina%27s%20Potent%20Potions|/collections/types?q=health|/collections/types?q=Health%20%26%20Beauty")
  end
end
