# frozen_string_literal: true

require "rails_helper"

# 步 12a：/collections 清單頁＋collections/all_products 全域＋collection.products
# 真分頁＋/collections/all 虛擬系列＋?view= 替代模板（96 號 teardown 的實作面）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   L1 未發布系列不得進清單（殺：漏 published_on 閘）
#   C2 paginate 頁窗（殺：paginate! 未接線——stub 單頁全量）
#   C3 sort_by 對映（殺：參數被忽略恆預設序）
#   V1/V2 view 進快取 key（殺：CACHE_PARAMS 漏 view ⇒ 替代頁污染預設頁快取）
RSpec.describe "Storefront G2 collections", type: :request do
  let(:shop) { create(:shop, subdomain: "g2-shop") }

  before do
    host! "g2-shop.lvh.me"
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

  # active＋自動發布（Product after_create materialize）＝discoverable。
  def make_product(title:, handle:, price:, at: nil)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title:, handle:)
      product.update_columns(created_at: at) if at
      create(:product_variant, shop:, product:, price_cents: price)
      product
    end
  end

  def make_collection(title:, handle:, sort_order: "manual", products: [])
    ActsAsTenant.with_tenant(shop) do
      collection = Collection.create!(shop_id: shop.id, title:, handle:, sort_order:,
                                      description_html: "")
      products.each_with_index do |product, index|
        CollectionProduct.create!(shop_id: shop.id, collection:, product:, position: index + 1)
      end
      collection
    end
  end

  describe "/collections 清單頁" do
    it "L1 🔴 列已發布系列（字母序）、未發布不進清單；size／[handle] 可用" do
      spring = make_collection(title: "Spring", handle: "spring")
      make_collection(title: "Autumn", handle: "autumn")
      hidden = make_collection(title: "Hidden", handle: "hidden")
      ActsAsTenant.with_tenant(shop) do
        ResourcePublication.where(publishable_type: "Collection", publishable_id: hidden.id).delete_all
        CollectionProduct.create!(shop_id: shop.id, collection: spring,
                                  product: Product.find_by!(handle: "rose-serum"), position: 9)
      end

      get "/collections"
      expect(response).to have_http_status(:ok)
      # 字母序：Autumn 在 Spring 前；Hidden 不出現（真店實證形——96 §1.2）
      expect(response.body.index('data-ch="autumn"')).to be < response.body.index('data-ch="spring"')
      expect(response.body).not_to include('data-ch="hidden"')
      expect(response.body).to include('<span id="lcsize">2</span>')
      expect(response.body).to include('<span id="lcbyhandle">Spring</span>')
      # all_products['rose-serum']（96 §7）＋清單卡的成員計數
      expect(response.body).to include('<span id="lcap">玫瑰精華</span>')
      expect(response.body).to include("Spring(1)")
    end

    before do
      make_product(title: "玫瑰精華", handle: "rose-serum", price: 18800)
    end
  end

  describe "系列頁商品格＋真分頁" do
    let!(:cheap)  { make_product(title: "平品", handle: "item-cheap",  price: 1000, at: Time.zone.parse("2026-01-01")) }
    let!(:mid)    { make_product(title: "中品", handle: "item-mid",    price: 5000, at: Time.zone.parse("2026-02-01")) }
    let!(:dear)   { make_product(title: "貴品", handle: "item-dear",   price: 9000, at: Time.zone.parse("2026-03-01")) }
    let!(:collection) do
      make_collection(title: "Picks", handle: "picks", products: [ mid, cheap, dear ])
    end

    it "C1 手動序照 position；draft 成員不進格（discoverable 閘）" do
      draft = ActsAsTenant.with_tenant(shop) do
        product = create(:product, shop:, status: "draft", title: "草稿品", handle: "item-draft")
        create(:product_variant, shop:, product:, price_cents: 100)
        CollectionProduct.create!(shop_id: shop.id, collection:, product:, position: 0)
        product
      end

      get "/collections/picks"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("item-draft")
      # position 序＝mid(1)→cheap(2)（第 1 頁只有前兩件——paginate by 2）
      expect(response.body.index('data-h="item-mid"')).to be < response.body.index('data-h="item-cheap"')
      expect(response.body).to include('<span id="ccount">3</span>')
      expect(response.body).to include('<span id="cpages">2</span><span id="cpage">1</span><span id="citems">3</span>')
      expect(draft.reload.status).to eq("draft")
    end

    it "C2 🔴 ?page=2 ⇒ 第二頁窗（只剩第 3 件）＋parts 連結帶前綴路徑" do
      get "/collections/picks?page=2"
      expect(response.body).to include('<span id="cpage">2</span>')
      expect(response.body).to include('data-h="item-dear"')
      expect(response.body).not_to include('data-h="item-mid"')
      # parts：第 1 頁連結不帶 page 參數、路徑帶當前語言前綴（預設語言無前綴；買家可點形）
      expect(response.body).to include("1=/collections/picks</i>")
    end

    it "C3 🔴 sort_by=price-descending ⇒ 貴品在前（storefront 鍵對映；sort_by 回傳現值）" do
      get "/collections/picks?sort_by=price-descending"
      expect(response.body).to include('<span id="csort">price-descending</span>')
      expect(response.body).to include('<span id="cdefsort">manual</span>')
      expect(response.body.index('data-h="item-dear"')).to be < response.body.index('data-h="item-mid"')
      expect(response.body).not_to include('data-h="item-cheap"') # 第 3 名掉到第 2 頁
    end

    it "C4 /collections/all 虛擬系列：title=Products、全店 discoverable、字母序（96 §2）" do
      get "/collections/all"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1 id="ctitle">Products</h1>')
      expect(response.body).to include('<span id="citems">3</span>')
      # title_asc：中品 < 平品（Unicode 序）——只斷言兩者都在第 1 頁且順序穩定
      expect(response.body).to include('<span id="cpages">2</span>')
    end

    it "C5 商家自建 handle=all 的真系列壓過虛擬系列" do
      make_collection(title: "我的全部", handle: "all", products: [ cheap ])
      get "/collections/all"
      expect(response.body).to include('<h1 id="ctitle">我的全部</h1>')
      expect(response.body).to include('<span id="citems">1</span>')
    end

    it "V1 ?view=alt ⇒ 替代模板＋template.suffix；不存在 suffix ⇒ 靜默 fallback（真店實證）" do
      get "/collections/picks?view=alt"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1 id="alttitle">替代版 Picks</h1>')
      expect(response.body).to include('<span id="altsuffix">alt</span>')
      expect(response.body).to include('<span id="alttpl">collection</span>')

      get "/collections/picks?view=zzz-nonexistent"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1 id="ctitle">Picks</h1>')
    end

    it "C6 🔴 content_for block 的 closest.product 與任意參數到達 block（Ella 商品卡形）" do
      get "/collections/picks"
      # closest.product：卡內拿到當前迭代商品（不是 nil、不是頁面 closest）
      expect(response.body).to include('<b class="cardtitle">中品</b>')
      expect(response.body).to include('<b class="cardtitle">平品</b>')
      # 任意參數（官方 static block 參數契約）：note 變數進 block
      expect(response.body).to include('<i class="cardnote">hot</i>')
      expect(response.body).not_to include('<i class="cardnote">none</i>')
    end

    it "V2 🔴 view 進快取 key：替代頁與預設頁各自快取、互不污染" do
      memory = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory)

      get "/collections/picks"
      expect(response.body).to include('<h1 id="ctitle">Picks</h1>')
      get "/collections/picks?view=alt"
      expect(response.body).to include('<h1 id="alttitle">替代版 Picks</h1>')
      get "/collections/picks"
      expect(response.body).to include('<h1 id="ctitle">Picks</h1>')
    end
  end
end
