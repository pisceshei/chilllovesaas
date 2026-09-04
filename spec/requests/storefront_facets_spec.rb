# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-20：storefront filtering（facets）v1——91 §3.61 收口。
# 官方契約取證 2026-09-02（objects/filter・filter_value；support-storefront-
# filtering）；param 精確字串除 `filter.v.option.{name}`（官方逐字例）外標 V。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   FA1 過濾真的作用在列表（殺：filters 只渲染不過濾＝裝飾品）
#   FA3 多值 OR 從 query string 解析（殺：Rails params last-wins 靜默丟值）
#   FA5 filter 參數進頁快取鍵（殺：過濾頁污染未過濾頁快取＝跨訪客錯資料）
RSpec.describe "Storefront facets", type: :request do
  let(:shop) { create(:shop, subdomain: "fa-shop") }

  before do
    host! "fa-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    Rails.cache.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def make_product(handle:, price:, vendor: nil, option: nil, stock: 1)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title: handle, handle:,
                       vendor: vendor.to_s)
      ovs = []
      if option
        po = create(:product_option, product:, shop:, name: option[0], position: 1)
        ovs = [ create(:option_value, product_option: po, shop:, value: option[1], position: 1) ]
      end
      variant = create(:product_variant, shop:, product:, price_cents: price, option_values: ovs)
      variant.inventory_item.inventory_levels.order(:id).first.update!(available: stock)
      product
    end
  end

  def make_collection!(products)
    ActsAsTenant.with_tenant(shop) do
      collection = Collection.create!(shop_id: shop.id, title: "Filtered", handle: "filtered",
                                      sort_order: "manual", description_html: "")
      products.each_with_index do |product, index|
        CollectionProduct.create!(shop_id: shop.id, collection:, product:, position: index + 1)
      end
      collection
    end
  end

  it "FA1 🔴 availability：過濾真作用；products_count/all_products_count 分家；counts 正確" do
    a = make_product(handle: "in-stock-a", price: 1000, stock: 5)
    b = make_product(handle: "sold-out-b", price: 2000, stock: 0)
    make_collection!([ a, b ])

    get "/collections/filtered?filter.v.availability=1"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-h="in-stock-a"')
    expect(response.body).not_to include('data-h="sold-out-b"') # 🔴 列表真被過濾
    expect(response.body).to include('<span id="ccount">1</span>')
    expect(response.body).to include('<span id="callcount">2</span>') # 官方語義分家
    expect(response.body).to include(%(data-f="filter.v.availability" data-type="boolean"))
    expect(response.body).to include(%(data-v="1" data-c="1" data-a="true"))
  end

  it "FA2 price_range：URL 主單位 → drop cents（鐵律 3 邊界）；range_max＝最高商品最低價" do
    make_collection!([ make_product(handle: "cheap", price: 1000),
                       make_product(handle: "mid", price: 5000),
                       make_product(handle: "dear", price: 9900) ])

    get "/collections/filtered?filter.v.price.gte=20.00&filter.v.price.lte=60.00"
    expect(response.body).to include('data-h="mid"')
    expect(response.body).not_to include('data-h="cheap"')
    expect(response.body).not_to include('data-h="dear"')
    # min_value.value/max_value.value＝cents（Ella `| money` 直餵）；range_max 同
    expect(response.body).to include("[2000..6000/9900]")
  end

  it "FA3 🔴 變體選項多值 OR（query string 重複鍵）＋跨過濾器 AND（vendor）" do
    # E8b：新店預設只有 availability＋price（hoko.vip），選項／vendor 過濾器要經 shops.storefront_filters 啟用
    shop.update!(storefront_filters: ThemeEngine::Facets::ALL_FILTERS)
    r = make_product(handle: "opt-red", price: 1000, vendor: "Acme", option: [ "Color", "Red" ])
    b = make_product(handle: "opt-blue", price: 1000, vendor: "Zeta", option: [ "Color", "Blue" ])
    g = make_product(handle: "opt-green", price: 1000, vendor: "Acme", option: [ "Color", "Green" ])
    make_collection!([ r, b, g ])

    # 多值 OR：Red 或 Blue（重複鍵——Rails params 只留最後一值，必從 qs 解析）
    get "/collections/filtered?filter.v.option.Color=Red&filter.v.option.Color=Blue"
    expect(response.body).to include('data-h="opt-red"')
    expect(response.body).to include('data-h="opt-blue"')
    expect(response.body).not_to include('data-h="opt-green"')

    # 跨過濾器 AND：Color 選中 ∧ vendor=Acme ⇒ 只剩 red
    get "/collections/filtered?filter.v.option.Color=Red&filter.v.option.Color=Blue&filter.p.vendor=Acme"
    expect(response.body).to include('data-h="opt-red"')
    expect(response.body).not_to include('data-h="opt-blue"')
    # counts＝套用其他過濾器後：vendor 濾 Acme 下 Color 各值 count
    expect(response.body).to include(%(data-v="Green" data-c="1"))
  end

  it "FA4 URL 建構：url_to_add 疊加、url_to_remove 摘除、page 恆剝、sort_by 保留" do
    shop.update!(storefront_filters: ThemeEngine::Facets::ALL_FILTERS) # E8b：vendor 過濾器非預設
    a = make_product(handle: "u-a", price: 1000, vendor: "Acme")
    make_collection!([ a ])

    get "/collections/filtered?filter.p.vendor=Acme&sort_by=price-ascending&page=2"
    body = response.body
    # Acme 值自己的 url_to_remove：去掉自家 pair、保 sort_by
    acme_rm = body[/data-v="Acme"[^>]*data-rm="([^"]*)"/, 1]
    expect(acme_rm).to include("sort_by=price-ascending")
    expect(acme_rm).not_to include("filter.p.vendor")
    # 他過濾器值的 url_to_add 保留 vendor pair（跨過濾器疊加）
    expect(body).to match(/data-v="1"[^>]*data-add="[^"]*filter\.p\.vendor=Acme[^"]*"/)
    # page 恆剝（官方：分頁參數移除）——全部 add/rm 都不得帶
    expect(body).not_to match(/data-(add|rm)="[^"]*page=2[^"]*"/)
  end

  it "FS1 🔴 search facets：商品被過濾＋官方「filter 啟用 ⇒ 非商品結果全濾除」；URL 保 q" do
    make_product(handle: "probe-acme", price: 1000, vendor: "Acme")
    make_product(handle: "probe-zeta", price: 1000, vendor: "Zeta")
    ActsAsTenant.with_tenant(shop) do
      Page.create!(shop_id: shop.id, title: "probe page", handle: "probe-page",
                   body_html: "<p>probe</p>", published_at: 1.hour.ago)
    end

    get "/search?q=probe"
    expect(response.body).to include('data-h="probe-acme"')
    expect(response.body).to include('data-h="probe-zeta"')
    get "/search?q=probe&page=2" # fixture paginate by 2 ⇒ 混型在第 2 頁
    expect(response.body).to include('data-ot="page"') # 未過濾＝混型

    get "/search?q=probe&filter.p.vendor=Acme"
    expect(response.body).to include('data-h="probe-acme"')
    expect(response.body).not_to include('data-h="probe-zeta"') # 商品被過濾
    expect(response.body).not_to include('data-ot="page"')      # 🔴 非商品全濾除（官方逐字）
    # url_to_add 保 q（搜尋語境不丟）
    expect(response.body).to match(/data-add="[^"]*q=probe[^"]*"/)
  end

  it "FA5 🔴 filter 參數進頁快取鍵：過濾頁與未過濾頁互不污染" do
    a = make_product(handle: "cache-a", price: 1000, stock: 5)
    b = make_product(handle: "cache-b", price: 1000, stock: 0)
    make_collection!([ a, b ])

    get "/collections/filtered" # 未過濾先進快取
    expect(response.body).to include('data-h="cache-b"')

    get "/collections/filtered?filter.v.availability=1"
    expect(response.body).not_to include('data-h="cache-b"') # 沒吃到未過濾快取

    get "/collections/filtered"
    expect(response.body).to include('data-h="cache-b"') # 未過濾頁沒被過濾版寫髒
  end
end
