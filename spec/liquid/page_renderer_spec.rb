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

  it "E10 🔴 ?variant= 進選中態（缺口分析 A2）：帶參數選中該變體；壞值回退首可購變體" do
    first, second = ActsAsTenant.with_tenant(shop) do
      product = create(:product, shop:, status: "active", handle: "engine-sel", title: "選中測試")
      option = create(:product_option, product:, shop:, name: "尺寸", position: 1)
      ov1 = create(:option_value, product_option: option, shop:, value: "S", position: 1)
      ov2 = create(:option_value, product_option: option, shop:, value: "M", position: 2)
      [ create(:product_variant, product:, shop:, title: "S", position: 1, option_values: [ ov1 ]),
        create(:product_variant, product:, shop:, title: "M", position: 2, option_values: [ ov2 ]) ]
    end
    html = renderer.render("/products/engine-sel", params: { "variant" => second.id.to_s }).html
    expect(html).to include(%(<span id="pselected">#{second.id}</span>))
    # 壞值 ⇒ 忽略（ours，未取證格照缺口分析 §D 登記）⇒ 回退首「可購」；
    # 兩變體都 0 庫存 deny ⇒ 全售罄 fallback＝position 首位（S）。
    html2 = renderer.render("/products/engine-sel", params: { "variant" => "not-a-number" }).html
    expect(html2).to include(%(<span id="pselected">#{first.id}</span>))
  end

  it "E11 🔴 ?section_id=<template 鍵> ⇒ 200、裸 wrapper 片段（不含 layout）；83 §12.3 單 id 格" do
    sellable(handle: "engine-frag")
    result = renderer.render("/products/engine-frag", params: { "section_id" => "main" })
    expect(result.status).to eq(200)
    expect(result.html).to start_with(%(<div id="shopify-section-template--product__main"))
    expect(result.html).to include("引擎測試商品")
    expect(result.html).not_to include("<!doctype html>")
    expect(result.content_type).not_to eq(:json)
  end

  it "E12 🔴 ?section_id=未知 ⇒ 404＋空 body（真店：不是主題 404 頁——fallback 到 not_found template ⇒ 轉紅）" do
    sellable(handle: "engine-frag-404")
    result = renderer.render("/products/engine-frag-404", params: { "section_id" => "no-such" })
    expect(result.status).to eq(404)
    expect(result.html).to eq("")
  end

  it "E13 ?sections=main,no-such ⇒ 200 JSON map：有效鍵＝wrapper 字串、未知鍵＝null" do
    sellable(handle: "engine-frag-multi")
    result = renderer.render("/products/engine-frag-multi", params: { "sections" => "main,no-such" })
    expect(result.status).to eq(200)
    expect(result.content_type).to eq(:json)
    map = JSON.parse(result.html)
    expect(map.keys).to eq(%w[main no-such])
    expect(map["main"]).to start_with(%(<div id="shopify-section-template--product__main"))
    expect(map["no-such"]).to be_nil
  end

  it "E14 🔴 ?sections= 超過 limits 上限（5）⇒ 400 空 body（官方 up to five＋真店超限實測）" do
    result = renderer.render("/", params: { "sections" => "a,b,c,d,e,f" })
    expect(result.status).to eq(400)
    expect(result.html).to eq("")
  end

  it "E15 兩參數並存 ⇒ sections 壓過 section_id（真店：回 JSON）" do
    sellable(handle: "engine-frag-both")
    result = renderer.render("/products/engine-frag-both",
                             params: { "section_id" => "main", "sections" => "main" })
    expect(result.content_type).to eq(:json)
    expect(JSON.parse(result.html)["main"]).to be_a(String)
  end

  it "E16 🔴 fragment 繼承請求頁 context：?variant= 選中態疊加（Ella 變體切換的伺服端半邊）" do
    product = sellable(handle: "engine-frag-var")
    second = ActsAsTenant.with_tenant(shop) do
      option = create(:product_option, product:, shop:, name: "尺寸", position: 1)
      ov1 = create(:option_value, product_option: option, shop:, value: "S", position: 1)
      ov2 = create(:option_value, product_option: option, shop:, value: "M", position: 2)
      first = product.product_variants.sole
      first.product_variant_option_values.build(shop:, product:, product_option: option, option_value: ov1)
      first.save!
      create(:product_variant, product:, shop:, title: "M", position: 2, option_values: [ ov2 ])
    end
    result = renderer.render("/products/engine-frag-var",
                             params: { "section_id" => "main", "variant" => second.id.to_s })
    expect(result.html).to include(%(<span id="pselected">#{second.id}</span>))
  end

  it "E17 群組 JSON 的 section 鍵可經兩端點定址（layout {% sections %} 名單解析）" do
    single = renderer.render("/", params: { "section_id" => "grouped_hero_Ab12Cd" })
    expect(single.status).to eq(200)
    expect(single.html).to include("群組英雄")
    multi = renderer.render("/", params: { "sections" => "grouped_hero_Ab12Cd" })
    expect(JSON.parse(multi.html)["grouped_hero_Ab12Cd"]).to include("群組英雄")
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
