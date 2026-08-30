# frozen_string_literal: true

require "rails_helper"

# 包 30（D77）：主題引擎整頁渲染矩陣。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   E2 product 頁的 `{{ product.status }}` 必須輸出空（specs/93 §D 紅線——
#      在 ProductDrop 定義 status 方法 ⇒ 轉紅）
#   E3 未發布商品直連 ⇒ 404 template（PageRenderer 繞過 Storefront::Lookup ⇒ 轉紅）
#   E5 DB template 覆寫蓋過來源檔（讀取順序倒過來 ⇒ 轉紅）
#   E7 路徑逃逸讀不到（FileSource 去掉防線 ⇒ 轉紅）
RSpec.describe ThemeEngine::PageRenderer do
  let(:shop) { create(:shop) }
  let(:online_store) { ActsAsTenant.with_tenant(shop) { Publication.online_store! } }
  let(:source) { ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0")) }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end

  def renderer
    described_class.new(theme: theme, shop: shop, publication: online_store, source: source)
  end

  def sellable(handle:)
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle:, title: "引擎測試商品")
      create(:product_variant, product:, price_cents: 148_000)
      product
    end
  end

  it "E1 首頁：template sections → layout 組裝；settings 預設合併；money 走 HKD 符號；snippet 檔案系統通" do
    result = renderer.render("/")
    expect(result.status).to eq(200)
    expect(result.html).to include("<h1>首頁英雄</h1>")           # 實例值蓋 schema default
    expect(result.html).to include("HK$1,480.00")                 # cents → 顯示兩位小數（鐵律 3/10）
    expect(result.html).to include(%(data-shop="#{shop.name}"))   # layout 組裝＋ShopDrop
    expect(result.html).to include('href="/cart"')                # RoutesDrop（無前綴形態）
  end

  it "E2 🔴 product 頁渲染真 DB 商品；{{ product.status }} 輸出空（specs/93 §D 紅線）" do
    sellable(handle: "engine-p1")
    result = renderer.render("/products/engine-p1")
    expect(result.status).to eq(200)
    expect(result.html).to include('<h1 id="ptitle">引擎測試商品</h1>')
    expect(result.html).to include('<span id="pprice">HK$1,480.00</span>')
    expect(result.html).to include('<span id="pstatus"></span>')
    expect(result.html).to include('<em class="badge">HKD</em>') # snippet render
  end

  it "E3 🔴 draft 商品直連 ⇒ 404 template（可見性判準＝Storefront::Lookup，specs/93 §C）" do
    ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "draft", handle: "engine-draft")
      create(:product_variant, product:)
    end
    result = renderer.render("/products/engine-draft")
    expect(result.status).to eq(404)
    expect(result.html).to include("404 not found page")
  end

  it "E4 查無 handle ⇒ 404 template；未知路由同" do
    expect(renderer.render("/products/no-such").status).to eq(404)
    expect(renderer.render("/no-such-route").status).to eq(404)
  end

  it "E5 🔴 DB template 覆寫蓋過來源檔（編輯器寫入面的讀取契約）" do
    ActsAsTenant.with_tenant(shop) do
      Template.create!(shop_id: shop.id, theme:, key: "index", template_type: "index",
                       content: { "sections" => { "hero" => { "type" => "hero",
                                                              "settings" => { "heading" => "DB 覆寫標題" } } },
                                  "order" => [ "hero" ] })
    end
    html = renderer.render("/").html
    expect(html).to include("DB 覆寫標題")
    expect(html).not_to include("首頁英雄")
  end

  it "E6 theme_settings 覆寫 settings_data（同一讀取契約的設定側）" do
    ActsAsTenant.with_tenant(shop) do
      runtime = ThemeEngine::Runtime.new(theme: theme, shop: shop, source: source)
      expect(runtime.global_assigns["settings"].liquid_method_missing("brand_color").to_s).to eq("#a9502c")
      ThemeSetting.create!(shop_id: shop.id, theme:, settings: { "brand_color" => "#123456" })
      runtime2 = ThemeEngine::Runtime.new(theme: theme, shop: shop, source: source)
      expect(runtime2.global_assigns["settings"].liquid_method_missing("brand_color").to_s).to eq("#123456")
    end
  end

  it "E7 🔴 FileSource 路徑逃逸一律 nil（讀取側的 25 §4 對偶）" do
    expect(source.read("../../../config/limits.yml")).to be_nil
    expect(source.read("/etc/passwd")).to be_nil
    expect(source.read("layout/theme.liquid")).to be_present
  end

  it "E9 Ella 7.2.0 冒煙：真實第三方主題渲染首頁不拋例外、輸出非空（PoC 三目標的整頁版）" do
    ella_dir = Rails.root.join("test/fixtures/themes/ella-7.2.0")
    skip "Ella fixture 不在" unless File.directory?(ella_dir)

    ella_theme = ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Ella", version: "7.2.0", role: "draft",
                    source: "first_party", license_attested: true)
    end
    result = described_class.new(theme: ella_theme, shop: shop, publication: online_store,
                                 source: ThemeEngine::FileSource.new(ella_dir)).render("/")
    expect(result.status).to eq(200)
    expect(result.html.length).to be > 1_000
    expect(result.html).to include("shopify-section")
  end

  it "E8 Theme.publish!：單一發布不變量（現任降級、目標升級，同交易）" do
    theme # 現任 published
    second = ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Second", version: "1.0", role: "draft", source: "first_party")
    end
    ActsAsTenant.with_tenant(shop) { second.publish! }
    expect(theme.reload.role).to eq("draft")
    expect(second.reload.role).to eq("published")
    expect(ActsAsTenant.with_tenant(shop) { Theme.published.count }).to eq(1)
  end
end
