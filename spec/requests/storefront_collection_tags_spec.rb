# frozen_string_literal: true

require "rails_helper"

# 引擎缺口 PR-9：系列 tag 路徑 `/collections/{handle}/{tag1+tag2}`＋`current_tags`＋系列語境商品 URL。
# 官方：help.shopify.com url-redirect "URLs that use collection tag filtering (such as
# yourstore.com/collections/collection-name/tag-name). Even if no products exist with that tag, the URL path is
# still considered valid"；make-collections-findable "display only the products that match all of the tags that
# you enter"（取證 2026-09-03）。真店 hoko.vip：`/collections/all/red`／`/collections/frontpage/red`（無此 tag）皆 200，
# `<title>` 前者「产品」、後者系列標題「首頁」。
#
# 🔴 假綠殺手矩陣（鐵律 20.2⑤）：
#   CT1 單 tag：只列帶該 tag 的商品；current_tags 可用；products_count＝當前檢視、all_products_count＝全集；
#       all_tags 仍列全集 tag（殺：不過濾／all_* 被 tag 污染）
#   CT2 多 tag `+`＝AND（殺：OR）
#   CT3 tag 以 handle 形對實際 tag（"Extra Potent" ⇔ extra-potent）（殺：只比原字串）
#   CT4 無此 tag 仍 200、零商品（殺：404）
#   CT5 `/collections/all/{tag}`：虛擬全商品＋tag；page_title＝Products（en）；zh＝产品
#   CT6 `/collections/{handle}/products/{p}`＝商品頁（殺：404）
#   CT7 link_to_add_tag／remove_tag 在 tag 頁的 href 以系列根為基底（殺：把 tag 段當 handle）
RSpec.describe "Storefront collection tag paths", type: :request do
  let(:shop) { create(:shop, subdomain: "ct-shop") }

  before do
    host! "ct-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
      red = create(:product, shop:, status: "active", handle: "red-tee", title: "Red Tee", tags: [ "red", "Extra Potent" ])
      blue = create(:product, shop:, status: "active", handle: "blue-mug", title: "Blue Mug", tags: [ "blue" ])
      both = create(:product, shop:, status: "active", handle: "duo", title: "Duo", tags: %w[red blue])
      [ red, blue, both ].each { |p| create(:product_variant, shop:, product: p, price_cents: 1000) }
      c = Collection.create!(shop_id: shop.id, title: "Picks", handle: "picks", sort_order: "manual", description_html: "")
      [ red, blue, both ].each_with_index { |p, i| CollectionProduct.create!(shop_id: shop.id, collection: c, product: p, position: i + 1) }
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def handles = response.body.scan(/data-h="([^"]+)"/).flatten

  it "CT1 🔴 單 tag：只列帶 tag 的商品；current_tags／計數／all_tags 各歸各" do
    get "/en-hk/collections/picks/red"
    expect(response).to have_http_status(:ok)
    expect(handles).to match_array(%w[red-tee duo])
    expect(response.body).to include('<span id="ctags">red</span>')
    expect(response.body).to include('<span id="ccount">2</span>')
    expect(response.body).to include('<span id="callcount">3</span>')
    expect(response.body).to include('<span id="calltags">blue,Extra Potent,red</span>')
    expect(response.body).to include('<h1 id="ctitle">Picks</h1>')
    expect(response.body).to include("<title>Picks</title>")
  end

  it "CT2 🔴 多 tag `+`＝AND" do
    get "/en-hk/collections/picks/red+blue"
    expect(handles).to eq(%w[duo])
    expect(response.body).to include('<span id="ctags">red+blue</span>')
  end

  it "CT3 🔴 tag 段是 handle 形：extra-potent ⇔ \"Extra Potent\"" do
    get "/en-hk/collections/picks/extra-potent"
    expect(handles).to eq(%w[red-tee])
  end

  it "CT4 🔴 無此 tag 仍 200、零商品（官方：路徑仍有效）" do
    get "/en-hk/collections/picks/zzz-none"
    expect(response).to have_http_status(:ok)
    expect(handles).to eq([])
    expect(response.body).to include('<span id="ccount">0</span>')
  end

  it "CT5 🔴 /collections/all/{tag}：虛擬全商品＋tag；page_title en＝Products、zh＝产品" do
    get "/en-hk/collections/all/blue"
    expect(response).to have_http_status(:ok)
    expect(handles).to match_array(%w[blue-mug duo])
    expect(response.body).to include("<title>Products</title>")

    theme = ActsAsTenant.with_tenant(shop) { Theme.find_by!(shop_id: shop.id, role: "published") }
    pub = ActsAsTenant.with_tenant(shop) { Publication.online_store! }
    zh = ThemeEngine::PageRenderer.new(theme:, shop:, publication: pub, locale: "zh-Hant",
                                       source: ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")))
    expect(zh.render("/collections/all/blue").html).to include("<title>产品</title>")
    # E8b：hoko.vip `/collections/all` 標題「产品」（2026-09-03 快照＋2026-09-04 live；虛擬系列，/collections/all.json 404）
    expect(zh.render("/collections/all").html).to include("<title>产品</title>")
  end

  it "CT6 🔴 /collections/{handle}/products/{p}＝商品頁" do
    get "/en-hk/collections/picks/products/red-tee"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<title>Red Tee</title>")
  end

  it "CT7 tag 頁上的 link_to_add_tag／link_to_remove_tag 以系列根為基底" do
    out = ThemeEngine::PageRenderer.new(
      theme: ActsAsTenant.with_tenant(shop) { Theme.find_by!(shop_id: shop.id, role: "published") }, shop:,
      publication: ActsAsTenant.with_tenant(shop) { Publication.online_store! },
      source: ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    ).render("/collections/picks/red", assigns: {}).html
    expect(out).to include('<span id="ctags">red</span>')
    tpl = Liquid::Template.parse("{{ 'blue' | link_to_add_tag: 'blue' }}|{{ 'red' | link_to_remove_tag: 'red' }}",
                                 environment: ThemeEngine::Runtime::ENVIRONMENT)
    links = tpl.render({ "current_tags" => [ "red" ] }, registers: { request_path: "/en-hk/collections/picks/red" })
    expect(links).to eq('<a href="/en-hk/collections/picks/red+blue" title="Narrow selection to products matching tag blue">blue</a>|' \
                        '<a href="/en-hk/collections/picks" title="Remove tag red">red</a>')
  end
end
