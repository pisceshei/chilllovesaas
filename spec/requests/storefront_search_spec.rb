# frozen_string_literal: true

require "rails_helper"

# 步 12b：/search 頁＋predictive suggest 雙形＋recommendations 雙形（96 §3–§5）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   S5 未發布／draft 不進結果（殺：搜尋漏 discoverable/visible 閘）
#   S4 price 排序＋非商品推尾（殺：sort 參數被忽略）
#   P2 參數值域 422（殺：fail-open 全收）
#   R2 官方三錯誤形（殺：查無回 200 空陣列）
RSpec.describe "Storefront G2 search line", type: :request do
  let(:shop) { create(:shop, subdomain: "g2s-shop") }

  before do
    host! "g2s-shop.lvh.me"
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

  def make_product(title:, handle:, price:, vendor: nil, at: nil)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", title:, handle:, vendor:)
      product.update_columns(created_at: at) if at
      create(:product_variant, shop:, product:, price_cents: price)
      product
    end
  end

  let!(:serum)  { make_product(title: "玫瑰精華", handle: "rose-serum", price: 18800, vendor: "RoseLab", at: Time.zone.parse("2026-03-01")) }
  let!(:soap)   { make_product(title: "玫瑰皂", handle: "rose-soap", price: 2000, at: Time.zone.parse("2026-02-01")) }
  let!(:candle) { make_product(title: "檀香蠟燭", handle: "sandal-candle", price: 5000, at: Time.zone.parse("2026-01-01")) }
  let!(:story) do
    ActsAsTenant.with_tenant(shop) do
      Page.create!(shop_id: shop.id, title: "玫瑰故事", handle: "rose-story",
                   body_html: "<p>rose</p>", published_at: 1.day.ago)
    end
  end

  describe "/search 頁" do
    it "S1 無 q ⇒ performed=false 只出表單（不渲染結果格）" do
      get "/en-hk/search"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<span id="sperf">false</span>')
      expect(response.body).not_to include('id="sgrid"')
    end

    it "S2 q=玫瑰 ⇒ 混型結果＋object_type＋真分頁＋sort_options 恰 3 值" do
      get "/en-hk/search?q=#{CGI.escape('玫瑰')}"
      expect(response.body).to include('<h1 id="sterms">玫瑰</h1>')
      expect(response.body).to include('<span id="sperf">true</span>')
      expect(response.body).to include('<span id="scount">3</span>') # 2 商品＋1 頁面
      expect(response.body).to include('<span id="ssort">relevance</span>')
      expect(response.body).to include('<span id="sdef">relevance</span>')
      expect(response.body).to include('<span id="stypes">article,page,product</span>')
      expect(response.body).to include('<span id="sopts">relevance;price-ascending;price-descending;</span>')
      expect(response.body).to include('<span id="spages">2</span>')
      expect(response.body).to include('data-ot="product"')
    end

    it "S3 type=page ⇒ 只回頁面型；types 回聲參數" do
      get "/en-hk/search?q=#{CGI.escape('玫瑰')}&type=page"
      expect(response.body).to include('<span id="stypes">page</span>')
      expect(response.body).to include('<span id="scount">1</span>')
      expect(response.body).to include('data-ot="page"')
      expect(response.body).not_to include('data-ot="product"')
    end

    it "S4 🔴 sort_by=price-ascending ⇒ 皂(2000) 在精華(18800) 前；非商品推尾（第 2 頁）" do
      get "/en-hk/search?q=#{CGI.escape('玫瑰')}&sort_by=price-ascending"
      expect(response.body).to include('<span id="ssort">price-ascending</span>')
      expect(response.body.index('data-h="rose-soap"')).to be < response.body.index('data-h="rose-serum"')
      expect(response.body).not_to include('data-ot="page"') # 頁面被推到第 2 頁
      get "/en-hk/search?q=#{CGI.escape('玫瑰')}&sort_by=price-ascending&page=2"
      expect(response.body).to include('data-ot="page"')
    end

    it "S5 🔴 draft 商品與未發布頁面不進結果" do
      ActsAsTenant.with_tenant(shop) do
        product = create(:product, shop:, status: "draft", title: "玫瑰草稿", handle: "rose-draft")
        create(:product_variant, shop:, product:, price_cents: 100)
        Page.create!(shop_id: shop.id, title: "玫瑰未發布", handle: "rose-unpub",
                     body_html: "", published_at: nil)
      end
      get "/en-hk/search?q=#{CGI.escape('玫瑰')}"
      expect(response.body).to include('<span id="scount">3</span>')
      expect(response.body).not_to include("rose-draft")
      expect(response.body).not_to include("玫瑰未發布")
    end
  end

  describe "GET /search/suggest.json" do
    it "P1 官方形：只回請求型鍵；product 條目 16 鍵＋decimal 字串＋歸因參數" do
      # 追蹤且零庫存＝available:false（factory 預設形）；改未追蹤驗 true 分支
      ActsAsTenant.with_tenant(shop) do
        serum.product_variants.first.inventory_item.update!(tracked: false)
      end
      get "/search/suggest.json", params: {
        q: "玫瑰", resources: { type: "product,collection,page,query",
                                 options: { fields: "title,product_type,variants.title,vendor" } }
      }
      expect(response).to have_http_status(:ok)
      results = response.parsed_body.dig("resources", "results")
      expect(results.keys).to match_array(%w[products collections pages queries])
      expect(results["queries"]).to eq([])
      product = results["products"].find { |row| row["handle"] == "rose-serum" }
      expect(product.keys).to match_array(%w[available body compare_at_price_max
                                             compare_at_price_min handle id image price price_max
                                             price_min tags title type url variants vendor
                                             featured_image])
      expect(product["price"]).to eq("188.00")
      expect(product["available"]).to be(true)
      expect(product["url"]).to include("/products/rose-serum?_pos=")
      expect(product["url"]).to include("&_ss=e")
      expect(product["url"]).to include("_psq=%E7%8E%AB%E7%91%B0")
    end

    it "P2 🔴 參數值域 fail-closed：非法 type／limit 0／limit 11／limit_scope／fields 全 422" do
      [ { resources: { type: "product,bogus" } },
        { resources: { limit: "0" } },
        { resources: { limit: "11" } },
        { resources: { limit_scope: "some" } },
        { resources: { options: { fields: "title,password" } } } ].each do |bad|
        get "/search/suggest.json", params: { q: "玫瑰" }.merge(bad)
        expect(response).to have_http_status(:unprocessable_content), bad.inspect
        expect(response.parsed_body["message"]).to eq("Invalid parameter error")
      end
    end

    it "P3 limit_scope：all＝跨型共享額度；each＝每型獨立" do
      get "/search/suggest.json", params: { q: "玫瑰", resources: { type: "product,page", limit: "2", limit_scope: "all" } }
      results = response.parsed_body.dig("resources", "results")
      expect(results["products"].size + results["pages"].size).to eq(2)

      get "/search/suggest.json", params: { q: "玫瑰", resources: { type: "product,page", limit: "2", limit_scope: "each" } }
      results = response.parsed_body.dig("resources", "results")
      expect(results["products"].size).to eq(2)
      expect(results["pages"].size).to eq(1)
    end

    it "P4 section 形：section_id=predictive-search 回 HTML（predictive_search 物件）；未知檔 404" do
      get "/en-hk/search/suggest", params: { q: "玫瑰", section_id: "predictive-search" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<span id="psterms">玫瑰</span>')
      expect(response.body).to include("玫瑰精華|/en-hk/products/rose-serum")

      get "/en-hk/search/suggest", params: { q: "玫瑰", section_id: "zzz-none" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /recommendations/products.json" do
    before do
      ActsAsTenant.with_tenant(shop) do
        a = Collection.create!(shop_id: shop.id, title: "Rose", handle: "rose", description_html: "")
        b = Collection.create!(shop_id: shop.id, title: "Home", handle: "home", description_html: "")
        CollectionProduct.create!(shop_id: shop.id, collection: a, product: serum, position: 1)
        CollectionProduct.create!(shop_id: shop.id, collection: a, product: soap, position: 2)
        CollectionProduct.create!(shop_id: shop.id, collection: b, product: serum, position: 1)
        CollectionProduct.create!(shop_id: shop.id, collection: b, product: candle, position: 2)
      end
    end

    it "R1 related＝共同系列成員（排除自身）＋intent 回聲；complementary＝空陣列（未配置真實形）" do
      get "/recommendations/products.json", params: { product_id: serum.id, intent: "related", limit: 4 }
      body = response.parsed_body
      expect(body["intent"]).to eq("related")
      expect(body["products"].map { |row| row["handle"] }).to match_array(%w[rose-soap sandal-candle])
      expect(body["products"].first["url"]).to include("pr_ref_pid=#{serum.id}")
      expect(body["products"].first["price"]).to be_a(Integer) # 整數分——與 suggest 尺度不同

      get "/recommendations/products.json", params: { product_id: serum.id, intent: "complementary" }
      expect(response.parsed_body).to eq({ "products" => [], "intent" => "complementary" })
    end

    it "R4 🔴 共同系列不足 limit ⇒ 其他可見商品依建立時間升冪補位（hoko.vip acme-tee ⇒ bolt-mug、cosy-lamp）；不在任何系列亦同" do
      lone = make_product(title: "孤品", handle: "lone-item", price: 1000, at: Time.zone.parse("2026-04-01"))
      get "/recommendations/products.json", params: { product_id: lone.id, limit: 2 }
      expect(response.parsed_body["products"].map { |row| row["handle"] }).to eq(%w[sandal-candle rose-soap]) # 建立序：1 月、2 月
      get "/recommendations/products.json", params: { product_id: serum.id, limit: 4 }
      handles = response.parsed_body["products"].map { |row| row["handle"] }
      expect(handles.first(2)).to match_array(%w[rose-soap sandal-candle]) # 共同系列成員在前
      expect(handles.last).to eq("lone-item") # 補位在後
    end

    it "R2 🔴 官方三錯誤形：缺 product_id 422／intent 非法 422／未發布 404（逐字訊息）" do
      get "/recommendations/products.json"
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to eq("A product_id value is missing")

      get "/recommendations/products.json", params: { product_id: serum.id, intent: "bogus" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"])
        .to eq("The intent parameter must be one of related, complementary")

      draft = ActsAsTenant.with_tenant(shop) do
        create(:product, shop:, status: "draft", title: "隱品", handle: "hidden-item")
      end
      get "/recommendations/products.json", params: { product_id: draft.id }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["message"])
        .to eq("No product with id #{draft.id} is published in the online store")
    end

    it "R3 section 形：related-products 以 recommendations 物件渲染" do
      get "/en-hk/recommendations/products", params: { product_id: serum.id, section_id: "related-products" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<span id="rint">related</span>')
      expect(response.body).to include('<span id="rcount">2</span>')
      expect(response.body).to include("玫瑰皂")
    end
  end
end
