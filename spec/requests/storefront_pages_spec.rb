# frozen_string_literal: true

require "rails_helper"

# 公開店面頁面（包 33 後半；67 §F.1(b)(c) 路由紀律＋63 §D.3 頁級快取＋B12/B13）。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   S1/S2 根與無前綴 302（殺：寫成 301——預設市場會變；殺：丟 query）
#   S3  前綴命中匿名可看（殺：storefront 誤掛 staff 閘）
#   S4  未知／長得像前綴但查無 ⇒ 404 不重導（殺：把一切未知都補預設前綴——前綴≡身分破裂）
#   S6  快取命中不重渲染＋stamp 動即換 key（殺：key 漏 resource stamp——永遠舊頁）
#   S8  平台 host 無店面（殺：storefront 路由漏 constraint，平台 host 被 catch-all 吃掉）
RSpec.describe "Storefront pages", type: :request do
  let(:shop) { create(:shop, subdomain: "sf-shop") }

  before do
    host! "sf-shop.lvh.me"
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

  it "S1 🔴 根路徑 ⇒ 302（不是 301）到預設 (market, locale) 前綴（B12；根不是內容頁）" do
    get "/"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/en-hk/")
  end

  it "S2 🔴 無前綴路徑 ⇒ 302 補預設前綴，保留路徑與 query（67 §F.1(b)）" do
    get "/products/rose?variant=9&x=1"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/en-hk/products/rose?variant=9&x=1")
  end

  it "S3 前綴命中 ⇒ 匿名 200 渲染主題頁；X-Robots-Tag noindex（B13 步 4 前）" do
    get "/en-hk/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("首頁英雄")
    expect(response.headers["X-Robots-Tag"]).to include("noindex")
  end

  it "S4 🔴 長得像前綴但查無 ⇒ 404（unknown_prefix_status；不補預設前綴、不重導）" do
    get "/fr-hk/"
    expect(response).to have_http_status(:not_found)
    get "/zh-hant-hk/" # 白名單只開 en ⇒ 未開放組合同樣 404（§A.5(c)）
    expect(response).to have_http_status(:not_found)
  end

  it "S5 robots.txt ⇒ 全站 Disallow（B13：SEO 面步 4 才開放）" do
    get "/robots.txt"
    expect(response.body).to eq("User-agent: *\nDisallow: /\n")
  end

  it "S6 🔴 頁級快取：同 key 第二請求不重渲染；資源 stamp 動 ⇒ 換 key 重渲染" do
    memory = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory)
    variant = ActsAsTenant.with_tenant(shop) do
      create(:product_variant, shop:,
             product: create(:product, shop:, status: "active", title: "快取測品", handle: "cache-item"))
    end

    allow(ThemeEngine::PageRenderer).to receive(:new).and_call_original
    2.times { get "/en-hk/products/cache-item" }
    expect(response).to have_http_status(:ok)
    expect(ThemeEngine::PageRenderer).to have_received(:new).once

    travel(1.second) { ActsAsTenant.with_tenant(shop) { variant.product.update!(title: "改名") } }
    get "/en-hk/products/cache-item"
    expect(ThemeEngine::PageRenderer).to have_received(:new).twice
  end

  it "S6b 快取值 404 不落快取（handle 空間無界——敵手不得灌爆儲存）" do
    memory = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory)
    allow(ThemeEngine::PageRenderer).to receive(:new).and_call_original
    2.times { get "/en-hk/products/no-such" }
    expect(response).to have_http_status(:not_found)
    expect(ThemeEngine::PageRenderer).to have_received(:new).twice
  end

  it "S7 主題資產：/theme-assets 供給已發布主題檔；路徑逃逸 404" do
    get "/theme-assets/site.css"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("color: #111")
    expect(response.headers["Cache-Control"]).to include("max-age=300")

    get "/theme-assets/..%2Fconfig%2Fsettings_schema.json"
    expect(response).to have_http_status(:not_found)
  end

  it "S8 🔴 平台 host 上沒有店面：根仍導 /admin、storefront catch-all 不匹配" do
    host! "lvh.me"
    get "/"
    expect(response).to redirect_to("/admin")
    # 平台 host 打前綴路徑＝無此路由（依測試環境 show_exceptions 設定，raise 或 404 皆為同一事實）。
    begin
      get "/en-hk/"
      expect(response).to have_http_status(:not_found)
    rescue ActionController::RoutingError
      # raise 形也證明 constraint 擋住了 catch-all
    end
  end

  it "D1 🔴 domains 表是 host→shop 權威：alias host 進站原樣服務；pending 列不可路由" do
    ActsAsTenant.with_tenant(shop) do
      Domain.create!(host: "mirror.example", domain_type: "alias", status: "active")
      Domain.create!(host: "pending.example", domain_type: "alias", status: "pending")
    end
    host! "mirror.example"
    get "/robots.txt"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Disallow: /")

    host! "pending.example"
    get "/robots.txt"
    expect(response).to have_http_status(:not_found)
  end

  it "D2 🔴 redirect 型網域 ⇒ 301 到 primary domain，保留路徑與 query（84 §4 逐字語義）" do
    ActsAsTenant.with_tenant(shop) do
      Domain.create!(host: "old.example", domain_type: "redirect", status: "active")
    end
    host! "old.example"
    get "/en-hk/products/x?a=1"
    expect(response).to have_http_status(:moved_permanently)
    expect(response.headers["Location"]).to eq("https://sf-shop.lvh.me/en-hk/products/x?a=1")
  end

  it "S9 canary：限流判別式真的掛上（storefront-page／storefront-cart 兩條，fail-open 防線）" do
    page_block = Rack::Attack.throttles.fetch("storefront-page/ip").block
    cart_block = Rack::Attack.throttles.fetch("storefront-cart/ip").block

    tenant_env = { "chilllove.shop_id" => shop.id, "REMOTE_ADDR" => "203.0.113.9" }
    page_get = Rack::Attack::Request.new(Rack::MockRequest.env_for("/en-hk/", method: "GET").merge(tenant_env))
    admin_get = Rack::Attack::Request.new(Rack::MockRequest.env_for("/admin", method: "GET").merge(tenant_env))
    platform_get = Rack::Attack::Request.new(
      Rack::MockRequest.env_for("/en-hk/", method: "GET").merge("REMOTE_ADDR" => "203.0.113.9")
    )
    cart_post = Rack::Attack::Request.new(Rack::MockRequest.env_for("/cart/add.js", method: "POST").merge(tenant_env))

    expect(page_block.call(page_get)).to be_present   # 🔴 env 鍵名打錯＝這裡轉 nil
    expect(page_block.call(admin_get)).to be_nil
    expect(page_block.call(platform_get)).to be_nil
    expect(cart_block.call(cart_post)).to be_present
  end
end
