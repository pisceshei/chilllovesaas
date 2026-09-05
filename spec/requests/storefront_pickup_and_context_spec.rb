# frozen_string_literal: true

require "rails_helper"

# T14 主題引擎缺口（docs/dev/t14-theme-engine-gaps.md；external-facts §G30，官方 objects/store_availability／location／address／
# focal_point／image_presentation／collection＋filters/format_address，取證 2026-09-05）——三套主題（Ella／Kalles／Minimog 的
# pickup-availability、Kalles brc-nav-product／_media）實際讀到的介面。格：
#   PU1 🔴 `variant.store_availabilities`：只在 selected 或 first available variant 有定義（其餘 nil）；集合＝pick_up_enabled 的 active 地點
#   PU2 🔴 逐地點 available：該地點可售量 > 0；未追蹤庫存 ⇒ 恆 true；無取貨地點 ⇒ []
#   PU3 `store_availability.location`：id／name／address（address1／city／province／zip／phone／street／summary）／latitude nil
#   PU4 🔴 `format_address`：官方例的順序與 `<p>…<br>…</p>` 形；空欄跳過；HTML 轉義
#   PU5 🔴 `collection.previous_product`／`next_product`：系列語境商品頁才有值；序＝系列排序；首尾各回 nil；一般商品頁 nil
#   PU6 `image.presentation.focal_point`：未設 ⇒ 官方預設 50／50，`X% Y%`；有值照出
RSpec.describe "Storefront pickup availability & collection context (T14)", type: :request do
  let(:shop) { create(:shop, subdomain: "t14-shop") }
  let(:publication) { Publication.online_store! }

  before do
    host! "t14-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published", source: "first_party", license_attested: true)
    end
    allow(ThemeEngine::Sources).to receive(:resolve).and_return(
      ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
    )
  end

  def product_with_stock(handle:, title:, qty: 5, tracked: true)
    ActsAsTenant.with_tenant(shop) do
      p = create(:product, shop:, status: "active", title:, handle:)
      # 🔴 position 顯式釘 1：工廠的 `sequence(:position)` 是**全域**序號，單跑時剛好是 1、整套跑時可能是 47 ⇒
      # `variants.first` 會變成本格後加的 position 2 那個變體（測試順序依賴，PU1 在套件內失敗過）。
      v = create(:product_variant, shop:, product: p, price_cents: 18_800, position: 1)
      item = v.inventory_item
      item.update!(tracked: tracked)
      item.inventory_levels.order(:id).first&.update!(available: qty)
      p
    end
  end

  def pickup_location(name:, enabled: true, time: "Usually ready in 24 hours", address: {})
    ActsAsTenant.with_tenant(shop) do
      loc = Location.find_or_create_by!(shop_id: shop.id, name:)
      loc.update!(pick_up_enabled: enabled, pick_up_time: time, address:)
      loc
    end
  end

  def variant_drop(product, selected: true)
    ActsAsTenant.with_tenant(shop) do
      pd = ThemeEngine::ProductDrop.new(product.reload, publication:, selected_variant_id: selected ? product.product_variants.first.id : nil)
      [ pd, pd.variants.first ]
    end
  end

  it "PU1 🔴 只在 selected 或 first available variant 有定義（其餘變體 nil）；集合＝pick_up_enabled 的 active 地點" do
    product = product_with_stock(handle: "acme-tee", title: "Acme Tee")
    # 第二個變體要有自己的選項座標（無選項變體同商品只能一筆——uq_product_variants_option_values_digest）
    second = ActsAsTenant.with_tenant(shop) do
      option = create(:product_option, product:, shop:, name: "尺寸", position: 1)
      ov = create(:option_value, product_option: option, shop:, value: "L", position: 1)
      create(:product_variant, shop:, product:, price_cents: 19_800, position: 2, option_values: [ ov ])
    end
    pickup_location(name: "Kowloon Bay")
    ActsAsTenant.with_tenant(shop) { Location.find_or_create_by!(shop_id: shop.id, name: "Warehouse").update!(pick_up_enabled: false) }

    pd, first = variant_drop(product, selected: false)
    expect(first.store_availabilities.map { |a| a.location.name }).to eq([ "Kowloon Bay" ]) # 未選 ⇒ 靠 first available
    other = pd.variants.find { |v| v.id == second.id }
    expect(other.store_availabilities).to be_nil # 🔴 官方：只在那兩種情況下有定義

    _pd2, sel = variant_drop(product, selected: true)
    expect(sel.store_availabilities.size).to eq(1)
  end

  it "PU2 🔴 逐地點 available 取該地點可售量；未追蹤庫存 ⇒ 恆 true；無取貨地點 ⇒ []" do
    product = product_with_stock(handle: "bolt-mug", title: "Bolt Mug", qty: 0)
    near = pickup_location(name: "Near", time: "Usually ready in 2 hours")
    far = pickup_location(name: "Far")
    _pd, v = variant_drop(product)
    by_name = v.store_availabilities.index_by { |a| a.location.name }
    expect(by_name.keys).to match_array(%w[Near Far])
    expect(by_name.values.map(&:available)).to eq([ false, false ]) # 兩地點皆 0
    expect(by_name["Near"].pick_up_time).to eq("Usually ready in 2 hours")
    expect(by_name["Near"].pick_up_enabled).to be(true)

    ActsAsTenant.with_tenant(shop) do
      item = product.product_variants.first.inventory_item
      item.inventory_levels.find_by(location_id: near.id).update!(available: 3)
    end
    _pd2, v2 = variant_drop(product.reload)
    expect(v2.store_availabilities.index_by { |a| a.location.name }["Near"].available).to be(true)
    expect(v2.store_availabilities.index_by { |a| a.location.name }["Far"].available).to be(false)

    untracked = product_with_stock(handle: "cosy-lamp", title: "Cosy Lamp", qty: 0, tracked: false)
    _pd3, v3 = variant_drop(untracked)
    expect(v3.store_availabilities.map(&:available)).to eq([ true, true ]) # 未追蹤 ⇒ 恆 true

    ActsAsTenant.with_tenant(shop) { Location.where(shop_id: shop.id).update_all(pick_up_enabled: false) }
    _pd4, v4 = variant_drop(product.reload)
    expect(v4.store_availabilities).to eq([]) # 無取貨地點 ⇒ 空陣列（官方 location 物件不可用）
    expect(far).to be_present
  end

  it "PU3 store_availability.location：id／name／address 欄位；latitude／longitude nil（無地址驗證）" do
    product = product_with_stock(handle: "acme-tee", title: "Acme Tee")
    loc = pickup_location(name: "Kowloon Bay", address: {
      "address1" => "20 Sheung Yuet Road", "address2" => "9/F", "city" => "Kowloon Bay",
      "province" => "Kowloon", "zip" => "999077", "country" => "Hong Kong SAR", "phone" => "+852 1234 5678",
      "company" => "CHILL LOVE", "first_name" => "Benny", "last_name" => "Wong"
    })
    _pd, v = variant_drop(product)
    a = v.store_availabilities.first
    expect(a.location.id).to eq(loc.id)
    expect(a.location.name).to eq("Kowloon Bay")
    expect(a.location.latitude).to be_nil
    expect(a.location.longitude).to be_nil
    addr = a.location.address
    expect(addr.address1).to eq("20 Sheung Yuet Road")
    expect(addr.city).to eq("Kowloon Bay")
    expect(addr.phone).to eq("+852 1234 5678")
    expect(addr.street).to eq("20 Sheung Yuet Road, 9/F")   # 官方：first 與 second line 的組合
    expect(addr.name).to eq("Benny Wong")                   # 官方：first 與 last name 的組合
    expect(addr.summary).to include("Benny Wong", "Kowloon Bay", "Hong Kong SAR")
  end

  it "PU4 🔴 format_address：官方例的順序與 <p>…<br>…</p> 形；空欄跳過；HTML 轉義" do
    h = Class.new { include ThemeEngine::Filters }.new
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    addr = ThemeEngine::AddressDrop.new(
      "company" => "Polina's Potions, LLC", "address1" => "150 Elgin Street", "address2" => "8th floor",
      "city" => "Ottawa", "province" => "ON", "zip" => "K2P 1L4", "country" => "Canada"
    )
    expect(h.format_address(addr))
      .to eq("<p>Polina&#39;s Potions, LLC<br>150 Elgin Street<br>8th floor<br>Ottawa ON K2P 1L4<br>Canada</p>")
    expect(h.format_address(ThemeEngine::AddressDrop.new("address1" => "A", "country" => "HK")))
      .to eq("<p>A<br>HK</p>")
    expect(h.format_address(ThemeEngine::AddressDrop.new({}))).to eq("<p></p>")
  end

  it "PU5 🔴 collection.previous_product／next_product：系列語境商品頁才有值，序＝系列排序，首尾 nil" do
    a = product_with_stock(handle: "aaa", title: "AAA")
    b = product_with_stock(handle: "bbb", title: "BBB")
    c = product_with_stock(handle: "ccc", title: "CCC")
    ActsAsTenant.with_tenant(shop) do
      col = Collection.create!(shop_id: shop.id, title: "Frontpage", handle: "frontpage", description_html: "",
                               collection_type: "manual", sort_order: "manual") # 建立即自動發布到 online store
      [ a, b, c ].each_with_index { |p, i| CollectionProduct.create!(shop_id: shop.id, collection: col, product: p, position: i) }
    end

    get "/collections/frontpage/products/bbb?view=t14"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("[prev:AAA][next:CCC]")

    get "/collections/frontpage/products/aaa?view=t14"
    expect(response.body).to include("[prev:][next:BBB]")
    get "/collections/frontpage/products/ccc?view=t14"
    expect(response.body).to include("[prev:BBB][next:]")

    get "/products/bbb?view=t14" # 無系列語境
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("[prev:][next:]")

    get "/collections/nope/products/bbb?view=t14" # 系列查無 ⇒ 商品頁照常 200
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("[prev:][next:]")
  end

  it "PU6 image.presentation.focal_point：未設 ⇒ 官方預設 50／50 與 `X% Y%`；有值照出" do
    default = ThemeEngine::ImagePresentationDrop.new(nil).focal_point
    expect([ default.x, default.y ]).to eq([ 50, 50 ])
    expect(default.to_s).to eq("50% 50%")
    set = ThemeEngine::ImagePresentationDrop.new("x" => 1.9231, "y" => 9.7917).focal_point
    expect(set.to_s).to eq("1.9231% 9.7917%") # 官方例的形
    expect(ThemeEngine::PlaceholderImageDrop.new(label: "image").presentation.focal_point.to_s).to eq("50% 50%")
  end
end
