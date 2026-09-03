# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# 渲染 1:1 對表第二批（E8b；鐵律 22）：其餘頁面（collections／products／search／pages／404）由 hoko.vip 快照 vs 鏡像店逐段 diff 抓到的引擎形差。
# 🔴 假綠殺手（每格對應 scratchpad mutate_e8b.py 一個突變）：
#   PP1 section 級動態來源 `{{ closest.product }}` 以當頁 closest 求值（本尊商品頁 recommendations 走 skeleton 分支）
#   PP2 recommendations 初次渲染 performed=false（印 "false"，非空字串）
#   PP3 search 未執行 results_count=0、`> 0` 比較不炸
#   PP4 linklist 字串形＝handle（`| handleize` 後可再查 linklists）
#   PP5 link_to_vendor／link_to_type 帶 title 屬性（官方逐字）
#   PP6 `/collections/all` zh 標題「产品」
#   PP7 Normalizer 抹商品／變體數字 id（只抹 id 屬性與 query）
RSpec.describe "ThemeEngine 渲染 1:1 形（E8b 頁面批）" do
  let(:shop) { create(:shop, name: "PP Shop") }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "PP Probe", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let(:root) do
    dir = Dir.mktmpdir("cl-parity-pages")
    files = {
      "layout/theme.liquid" => "<html><body><main>{{ content_for_layout }}</main></body></html>",
      "templates/index.json" => JSON.generate("sections" => { "r" => { "type" => "recsec", "settings" => { "product" => "{{ closest.product }}", "title" => "{{ shop.name }}" } } }, "order" => %w[r]),
      "templates/product.json" => JSON.generate("sections" => { "r" => { "type" => "recsec", "settings" => { "product" => "{{ closest.product }}", "title" => "{{ shop.name }}" } }, "x" => { "type" => "misc", "settings" => {} }, "y" => { "type" => "misc2", "settings" => { "cd" => "{{ closest.collection.description }}" }, "blocks" => { "html_NRR4gL" => { "type" => "html", "settings" => {} } }, "block_order" => %w[html_NRR4gL] } }, "order" => %w[r x y]),
      "templates/search.json" => JSON.generate("sections" => { "s" => { "type" => "srch", "settings" => {} } }, "order" => %w[s]),
      "templates/page.json" => JSON.generate("sections" => { "m" => { "type" => "pg", "settings" => {} } }, "order" => %w[m]),
      "templates/page.contact.json" => JSON.generate("sections" => { "m" => { "type" => "pgc", "settings" => {} } }, "order" => %w[m]),
      "templates/collection.json" => JSON.generate("sections" => { "f" => { "type" => "fac", "settings" => { "d" => "{{ closest.collection.description }}", "t" => "<h1>{{ closest.collection.title }}</h1>" } } }, "order" => %w[f]),
      "sections/pg.liquid" => "<pg>default</pg>{% for link in linklists.main-menu.links %}<lk>{{ link.title }}={{ link.current }}</lk>{% endfor %}{% schema %}{ \"name\": \"PG\" }{% endschema %}",
      "sections/misc2.liquid" => "<u>[{{ '<p>Health & Love potions</p>' | url_escape }}][{{ '<p>Health & Love potions</p>' | url_param_escape }}][{{ 'Acme Tee' | url_param_escape }}]</u>" \
                                 "<ph>{{ 'collection-apparel-3' | placeholder_svg_tag: 'placeholder-svg' }}</ph><vo>{{ product.variants.first.options | join: '/' }}</vo>{% for block in section.blocks %}<cb>{{ block.id }}|{{ block.type }}</cb>{% endfor %}<pcd>{% if section.settings.cd != blank %}[{{ section.settings.cd }}]{% endif %}</pcd>" \
                                 "{% schema %}{ \"name\": \"M2\", \"blocks\": [ { \"type\": \"html\", \"name\": \"HTML\" } ] }{% endschema %}",
      "sections/misc.liquid" => "<m>[{{ 1700000000 | date: '%Y-%m-%d' }}][{{ '1700000000' | date: '%Y' }}][{{ 'now' | date: '%s' | plus: 31536000 | date: '%Y' }}]" \
                                "[{{ cart.currency.symbol }}|{{ cart.currency.iso_code }}|{{ cart.currency.name }}][{{ product.selected_or_first_available_variant.option1 }}]" \
                                "[{{ product.selected_or_first_available_variant.featured_media }}]</m>{% schema %}{ \"name\": \"M\" }{% endschema %}",
      "sections/pgc.liquid" => "<pg>contact[{{ template.suffix }}]</pg>{% schema %}{ \"name\": \"PGC\" }{% endschema %}",
      "sections/fac.liquid" => "<f>{% for filter in collection.filters %}[{{ filter.label }}:{% for v in filter.values %}{{ v.label }}={{ v.count }};{% endfor %}]{% endfor %}</f>" \
                               "<so>{% for o in collection.sort_options %}{{ o.value }}={{ o.name }};{% endfor %}</so><iu>[{{ nothing | image_url: width: 100 }}]</iu>" \
                               "<cd>{% if section.settings.d != blank %}[{{ section.settings.d }}]{% endif %}</cd><ct>{{ section.settings.t }}</ct><ds>{{ collection.default_sort_by }}</ds>{% schema %}{ \"name\": \"F\" }{% endschema %}",
      "sections/recsec.liquid" => "<r>[{{ section.settings.product.handle }}][{{ section.settings.title }}][{{ recommendations.performed }}]" \
                                  "[{% if recommendations.performed or section.settings.product == blank %}T{% else %}F{% endif %}]" \
                                  "[{{ linklists['main-menu'] | handleize }}][{% assign h = linklists['main-menu'] | handleize %}{{ linklists[h].links.size }}]" \
                                  "[{% if linklists['nope'] == empty %}E{% else %}N{% endif %}{% if linklists['main-menu'] == empty %}E{% else %}N{% endif %}]" \
                                  "[{{ \"Polina's Potent Potions\" | link_to_vendor }}][{{ 'T-Shirt' | link_to_type }}]</r>{% form 'product', product %}x{% endform %}" \
                                  "{% schema %}{ \"name\": \"R\", \"settings\": [ { \"type\": \"product\", \"id\": \"product\" }, { \"type\": \"text\", \"id\": \"title\" } ] }{% endschema %}",
      "sections/srch.liquid" => "<s>[{{ search.performed }}][{{ search.results_count }}][{% if search.results_count > 0 %}Y{% else %}N{% endif %}]</s>" \
                                "{% schema %}{ \"name\": \"S\", \"settings\": [] }{% endschema %}"
    }
    files.each do |rel, body|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, body)
    end
    dir
  end
  let(:source) { ThemeEngine::FileSource.new(Pathname.new(root)) }

  after { FileUtils.remove_entry(root) if File.directory?(root) }

  def render(path)
    ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source).render(path)
  end

  before do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle: "p1", title: "P1")
      create(:product_variant, product:, price_cents: 1000)
      menu = Menu.create!(shop_id: shop.id, handle: "main-menu", title: "Main menu")
      MenuItem.create!(shop_id: shop.id, menu:, title: "首頁", item_type: "http", url: "/", position: 0)
    end
  end

  it "PP1／PP2 🔴 商品頁：section 設定 `{{ closest.product }}` 解成當頁商品；recommendations.performed 印 false ⇒ 進 skeleton 分支（F）" do
    html = render("/products/p1").html
    expect(html).to include("<r>[p1][PP Shop][false][F]")
    # 首頁無 closest.product ⇒ product blank ⇒ T（onboarding 分支，本尊同）
    expect(render("/").html).to include("<r>[][PP Shop][false][T]")
  end

  it "PP3 🔴 search 未執行：performed false、results_count 0、`> 0` 比較不炸（無 Liquid error）" do
    html = render("/search").html
    expect(html).to include("<s>[false][0][N]</s>")
    expect(html).not_to include("Liquid error")
  end

  it "PP4 🔴 linklist 字串形＝handle：`| handleize` 後 `linklists[h].links.size` 取得同一選單；PP8 `linklists[缺] == empty` 真、有 links 者假" do
    expect(render("/").html).to include("[main-menu][1][EN]")
  end

  it "PP5 🔴 link_to_vendor／link_to_type 帶 title（官方逐字例）" do
    html = render("/").html
    expect(html).to include(%([<a href="/collections/vendors?q=Polina%27s%20Potent%20Potions" title="Polina&#39;s Potent Potions">Polina's Potent Potions</a>]))
    expect(html).to include(%([<a href="/collections/types?q=T-Shirt" title="T-Shirt">T-Shirt</a>]))
  end

  it "PP9 🔴 product 表單：product-id／section-id 隱藏欄在 </form> 前（本尊尾端形），開頭仍只有 form_type＋utf8" do
    html = render("/products/p1").html
    pid = ActsAsTenant.with_tenant(shop) { Product.find_by!(handle: "p1").id }
    expect(html).to include(%(<form method="post" action="/cart/add" id="product_form_#{pid}" accept-charset="UTF-8" class="shopify-product-form" enctype="multipart/form-data"><input type="hidden" name="form_type" value="product" /><input type="hidden" name="utf8" value="✓" />x<input type="hidden" name="product-id" value="#{pid}" /><input type="hidden" name="section-id" value="template--product__r" /></form>))
  end

  it "PP10 🔴 篩選平台字串依語系：zh 為「供貨情況／现货／缺货」，en 為 Availability／In stock／Out of stock；count 隨庫存；預設不出 Brand" do
    ActsAsTenant.with_tenant(shop) do
      p1 = Product.find_by!(handle: "p1")
      p1.update!(vendor: "Acme") # 讓 vendor 過濾器有值——預設集合仍不得出 Brand（突變 M132 的判別力）
      Catalog::SaveCollection.call(shop:, input: { title: "All", handle: "c1", collection_type: "manual", product_ids: [ "gid://chilllove/Product/#{p1.id}" ] })
    end
    zh = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "zh-Hans")
                                  .render("/collections/c1", params: { "_facets_qs" => "" }).html
    expect(zh).to include("[供貨情況:").and include("现货=").and include("缺货=") # 值序見 PP17（count 0 退後）
    expect(zh).to include("[價格:")
    en = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "en")
                                  .render("/collections/c1", params: { "_facets_qs" => "" }).html
    expect(en).to include("[Availability:").and include("In stock=").and include("Out of stock=")
    expect(en).not_to include("Brand") # E8b：預設只出 availability＋price（hoko 新店無 Brand／Type 篩選）
  end

  it "PP14 🔴 sort_options 名稱依語系（zh 九項逐字）；`nil | image_url` 為空字串" do
    ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "All", handle: "c1", collection_type: "manual", description_html: "", sort_order: "manual")
    end
    zh = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "zh-Hans")
                                  .render("/collections/c1", params: { "_facets_qs" => "" }).html
    expect(zh).to include("<so>manual=特色;most-relevant=最相关;best-selling=畅销;title-ascending=按字母顺序排序，A-Z;title-descending=按字母顺序排序，Z-A;" \
                          "price-ascending=价格，从低到高;price-descending=价格，从高到低;created-ascending=日期，从旧到新;created-descending=日期，从新到旧;</so>")
    expect(zh).to include("<iu>[]</iu>")
    en = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "en")
                                  .render("/collections/c1", params: { "_facets_qs" => "" }).html
    expect(en).to include("<so>manual=Featured;")
  end

  it "PP15 🔴 url_escape／url_param_escape 官方例逐字（空白 %20、/ 保留；param 版 & ⇒ %26）；collection-apparel-3 佔位框 448×448" do
    html = render("/products/p1").html
    expect(html).to include("<u>[%3Cp%3EHealth%20&%20Love%20potions%3C/p%3E][%3Cp%3EHealth%20%26%20Love%20potions%3C/p%3E][Acme%20Tee]</u>")
    expect(html).to include(%(<ph><svg class="placeholder-svg" preserveAspectRatio="xMidYMid slice" width="448" height="448" viewBox="0 0 448 448" fill="none" xmlns="http://www.w3.org/2000/svg">))
  end

  it "PP16 🔴 closest 依模板資源填入：集合頁 `{{ closest.collection.title }}`／`.description` 解成當頁集合；無描述 ⇒ nil（blank），不留裸字串" do
    ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "All", handle: "c1", collection_type: "manual", description_html: "", sort_order: "manual")
      Collection.create!(shop_id: shop.id, title: "Lamps", handle: "c2", collection_type: "manual", description_html: "<p>Warm light</p>", sort_order: "manual")
    end
    r = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "en")
    c1 = r.render("/collections/c1", params: { "_facets_qs" => "" }).html
    expect(c1).to include("<cd></cd><ct><h1>All</h1></ct>")
    expect(c1).not_to include("closest.collection")
    # 商品頁沒有 closest.collection ⇒ 解成 nil ⇒ blank（先前 `|| v` 會把裸字串印出來；突變 M138 的判別力）
    expect(render("/products/p1").html).to include("<pcd></pcd>")
    c2 = r.render("/collections/c2", params: { "_facets_qs" => "" }).html
    expect(c2).to include("<cd>[<p>Warm light</p>]</cd><ct><h1>Lamps</h1></ct>")
  end

  it "PP17 🔴 availability 值排序：现货 count 0 時退到缺货之後；兩者皆有 count 則现货在前（hoko.vip 兩頁）" do
    ActsAsTenant.with_tenant(shop) do
      q0 = create(:product, shop:, status: "active", handle: "q0", title: "Q0")
      v0 = create(:product_variant, product: q0, price_cents: 1000, inventory_policy: "deny")
      item = InventoryItem.find_or_create_by!(shop_id: shop.id, product_variant_id: v0.id)
      item.update!(tracked: true) # 追蹤且無庫存層 ⇒ 缺货
      q1 = create(:product, shop:, status: "active", handle: "q1", title: "Q1")
      create(:product_variant, product: q1, price_cents: 1000, inventory_policy: "continue") # 缺貨可售 ⇒ 现货
      gid = ->(p) { "gid://chilllove/Product/#{p.id}" }
      Catalog::SaveCollection.call(shop:, input: { title: "Zero", handle: "c0", collection_type: "manual", product_ids: [ gid.call(q0) ] })
      Catalog::SaveCollection.call(shop:, input: { title: "Both", handle: "c3", collection_type: "manual", product_ids: [ gid.call(q0), gid.call(q1) ] })
    end
    r = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "zh-Hans")
    expect(r.render("/collections/c0", params: { "_facets_qs" => "" }).html).to include("[供貨情況:缺货=1;现货=0;]")
    expect(r.render("/collections/c3", params: { "_facets_qs" => "" }).html).to include("[供貨情況:现货=1;缺货=1;]")
  end

  it "PP18 🔴 自動系列 Default sort＝Most relevant ⇒ default_sort_by most-relevant（manual 系列仍 manual）；無選項預設變體 options＝[Default Title]" do
    ActsAsTenant.with_tenant(shop) do
      Collection.create!(shop_id: shop.id, title: "All", handle: "c1", collection_type: "manual", description_html: "", sort_order: "manual")
      Collection.create!(shop_id: shop.id, title: "Home", handle: "c4", collection_type: "manual", description_html: "", sort_order: "most_relevant")
    end
    r = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, locale: "en")
    expect(r.render("/collections/c4", params: { "_facets_qs" => "" }).html).to include("<ds>most-relevant</ds>")
    expect(r.render("/collections/c1", params: { "_facets_qs" => "" }).html).to include("<ds>manual</ds>")
    expect(render("/products/p1").html).to include("<vo>Default Title</vo>")
  end

  it "PP19 🔴 傳統 block（section schema）的 block.id＝裸 key，不帶 A…__ 實例前綴（theme block 仍帶）" do
    html = render("/products/p1").html
    expect(html).to include("<cb>html_NRR4gL|html</cb>")
    expect(html).not_to match(/<cb>A[A-Za-z0-9]{17}__html_NRR4gL/)
  end

  it "PP20 🔴 link.current 不受市場前綴影響：http 連結 /pages/contact 在 /zh-hans-tw/pages/contact 為 true（首頁項 false）" do
    ActsAsTenant.with_tenant(shop) do
      Page.create!(shop_id: shop.id, title: "Contact", handle: "contact", body_html: "", published_at: 1.day.ago)
      MenuItem.create!(shop_id: shop.id, menu: Menu.find_by!(handle: "main-menu"), title: "聯絡我們", item_type: "http", url: "/pages/contact", position: 1)
    end
    pre = ThemeEngine::PageRenderer.new(theme: theme, shop: shop, publication: online_store, source: source, url_prefix: "/zh-hans-tw")
                                   .render("/pages/contact").html
    expect(pre).to include("<lk>首頁=false</lk><lk>聯絡我們=true</lk>")
    expect(render("/pages/contact").html).to include("<lk>首頁=false</lk><lk>聯絡我們=true</lk>")
    expect(render("/").html).not_to include("聯絡我們=true")
  end

  it "PP13 🔴 無圖商品 featured_media／featured_image 為空（卡片 card--text）；無圖變體亦空" do
    ActsAsTenant.with_tenant(shop) do
      product = Product.find_by!(handle: "p1")
      drop = ThemeEngine::ProductDrop.new(product, url_prefix: "", publication: online_store)
      expect(drop.featured_media).to be_nil
      expect(drop.featured_image).to be_nil
      expect(drop.selected_or_first_available_variant.featured_media).to be_nil
    end
  end

  it "PP11 🔴 頁面 template_suffix ⇒ 用 templates/page.{suffix}.json（本尊 /pages/contact＝page.contact），template.suffix 同步" do
    ActsAsTenant.with_tenant(shop) do
      Page.create!(shop_id: shop.id, title: "C", handle: "contact", body_html: "", published_at: 1.day.ago, template_suffix: "contact")
      Page.create!(shop_id: shop.id, title: "A", handle: "about", body_html: "", published_at: 1.day.ago)
    end
    expect(render("/pages/contact").html).to include("<pg>contact[contact]</pg>")
    expect(render("/pages/about").html).to include("<pg>default</pg>")
  end

  it "PP12 🔴 date 吃時間戳（整數與純數字字串）；cart.currency 帶 symbol／name；無選項變體 option1＝Default Title；無圖變體 featured_media 空" do
    html = render("/products/p1").html
    year = Time.zone.now.year + 1
    expect(html).to include("<m>[2023-11-14][2023][#{year}][$|HKD|Hong Kong Dollar][Default Title][]</m>")
  end

  it "PP6 🔴 全商品集合標題 zh＝「产品」（hoko.vip title／h1／JSON-LD）" do
    expect(ThemeEngine::PageTitles.products_title("zh-Hans")).to eq("产品")
    expect(ThemeEngine::PageTitles.products_title("en")).to eq("Products")
  end

  it "PP7 🔴 Normalizer 抹商品／變體數字 id（只抹 id 屬性與 query），其他數字不動" do
    n = RenderParity::Normalizer.new(host: "hoko.vip")
    out = n.call(%(<x data-product-id="7771796897895" href="/products/a?variant=44547877830759" data-n="12"><input name="id" value="44547877830759">{"product_id":7771796897895,"n":5}) +
                 %( class="countdown_7771796897895" data-countdown-id="7771796897895">window.product_inventory_array_7771796897895 = { '44547877830759': '0', };) +
                 %({"@id": "https:\\/\\/hoko.vip\\/products\\/acme-tee#product"}))
    expect(out).to include(%(data-product-id="ID"))
    expect(out).to include("?variant=ID")
    expect(out).to include(%(name="id" value="ID"))
    expect(out).to include(%("product_id":ID))
    expect(out).to include(%(data-n="12"))
    expect(out).to include(%("n":5))
    expect(out).to include(%(class="countdown_ID" data-countdown-id="ID">window.product_inventory_array_ID = { 'ID': '0', };))
    expect(out).to include(%("@id": "\\/products\\/acme-tee#product")) # JSON 跳脫主機抹掉
    more = n.call(%(<a id="#offer-44547877830759"><label for="7771796897895input-text"><input id="7771796897895input-file"><input type="hidden" name="product-id" value="7771796897895" />))
    expect(more).to eq(%(<a id="#offer-ID"><label for="IDinput-text"><input id="IDinput-file"><input type="hidden" name="product-id" value="ID" />))
  end
end
