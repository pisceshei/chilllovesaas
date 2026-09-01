# frozen_string_literal: true

require "rails_helper"

# Ella 修復 PR-13：Liquid 全域覆蓋批（pages/images 全域、shop.vendors/types、
# collection.filters、powered_by_link、page_image、unit_price_with_measurement）。
# 官方取證 2026-09-02（shopify.dev objects/pages·images·shop·powered_by_link·
# page_image、filters/unit_price_with_measurement）；Ella 消費點見各格註釋。
#
# 🔴 假綠殺手（鐵律 20.2⑤）：
#   LG1 pages by-handle（殺：全域缺鍵 ⇒ header wishlist 連結恆走 fallback）
#   LG2 images by-filename（殺：品牌圖卡全走無圖分支）
#   LG4 collection.filters=[]（殺：nil ⇒ facets.liquid:90 `nil != empty` 渲染空容器）
RSpec.describe "ThemeEngine liquid globals（PR-13）" do
  let(:shop) { create(:shop) }
  let(:theme) do
    ActsAsTenant.with_tenant(shop) do
      Theme.create!(shop_id: shop.id, name: "Minimal", version: "1.0", role: "published",
                    source: "first_party", license_attested: true)
    end
  end
  let(:source) do
    ThemeEngine::FileSource.new(Rails.root.join("spec/fixtures/theme_engine/minimal-1.0"))
  end
  let(:filter_harness) do
    h = Class.new { include ThemeEngine::Filters }.new
    # format_money 讀 @context.registers[:money_symbol]（無 ⇒ "$"）
    h.instance_variable_set(:@context, Struct.new(:registers).new({}))
    h
  end

  def runtime
    ThemeEngine::Runtime.new(theme: theme, shop: shop, source: source)
  end

  around { |example| ActsAsTenant.with_tenant(shop) { example.run } }

  it "LG1 🔴 pages 全域：by-handle 取 PageDrop（官方 pages['about-us'] 形）；未知 handle ⇒ nil" do
    Page.create!(shop_id: shop.id, title: "願望清單", handle: "wish-list", body_html: "<p>x</p>")
    pages = runtime.global_assigns["pages"]
    drop = pages.liquid_method_missing("wish-list")
    expect(drop).to be_a(ThemeEngine::PageDrop)
    expect(drop.url).to eq("/pages/wish-list") # Ella header-functions:52 消費形
    expect(pages.liquid_method_missing("nope")).to be_nil
  end

  it "LG2 🔴 images 全域：by-filename 取 FileImageDrop（官方 images['x.png'] 形）；未知 ⇒ nil" do
    file = StoredFile.create!(shop_id: shop.id, filename: "brand-a.png", byte_size: 10,
                              content_type: "image/png", checksum: "x",
                              storage_key: "t/brand-a.png", status: "ready", width: 10, height: 10)
    images = runtime.global_assigns["images"]
    drop = images.liquid_method_missing("brand-a.png")
    expect(drop).to be_a(ThemeEngine::FileImageDrop)
    expect(drop.url.to_s).to include("/media/#{file.id}/")
    expect(images.liquid_method_missing("missing.png")).to be_nil
  end

  it "LG3 shop.vendors/types：distinct＋去空＋不分大小寫排序（官方 array of string）" do
    create(:product, shop:, status: "active", handle: "v1", vendor: "Zeta", product_type: "Tee")
    create(:product, shop:, status: "active", handle: "v2", vendor: "alpha", product_type: "")
    create(:product, shop:, status: "active", handle: "v3", vendor: "alpha", product_type: "Bag")
    drop = ThemeEngine::ShopDrop.new(shop)
    expect(drop.vendors).to eq([ "alpha", "Zeta" ])
    expect(drop.types).to eq([ "Bag", "Tee" ])
  end

  it "LG4 🔴 collection.filters ⇒ []（與 SearchDrop 一致；facets 空容器分支不誤入）" do
    collection = Collection.create!(shop_id: shop.id, title: "F", handle: "f-col",
                                    description_html: "", collection_type: "manual",
                                    sort_order: "manual")
    expect(ThemeEngine::CollectionDrop.new(collection).filters).to eq([])
  end

  it "LG5 powered_by_link（ours：品牌換我方）＋page_image＝商品 featured image" do
    link = runtime.global_assigns["powered_by_link"]
    expect(link).to include("Powered by CHILL LOVE")
    expect(link).to include(%(target="_blank"))
    expect(link).to include(%(rel="nofollow")) # 官方 HTML 形對位（連結/品牌換我方）

    product = create(:product, shop:, status: "active", handle: "pi-tee", title: "PI Tee")
    create(:product_variant, product:, price_cents: 1000)
    drop = ThemeEngine::ProductDrop.new(Product.find(product.id))
    renderer = ThemeEngine::PageRenderer.new(theme:, shop:, source:,
                                             publication: Publication.online_store!)
    # 無媒體商品 featured_image＝佔位 drop（每次新實例 ⇒ 比 to_s 不比物件同一）
    expect(renderer.send(:page_image_for, { "product" => drop }).to_s)
      .to eq(drop.featured_image.to_s)
    expect(renderer.send(:page_image_for, {})).to be_nil # 其餘頁型無 social image ⇒ nil
  end

  it "LG6 unit_price_with_measurement：官方輸出形 $50.00/kg；ref>1 ⇒ /100ml；nil 寬容" do
    expect(filter_harness.unit_price_with_measurement(
             5000, { "reference_value" => 1, "reference_unit" => "kg" })).to eq("$50.00/kg")
    expect(filter_harness.unit_price_with_measurement(
             990, { "reference_value" => 100, "reference_unit" => "ml" })).to eq("$9.90/100ml")
    expect(filter_harness.unit_price_with_measurement(5000, nil)).to eq("$50.00")
    expect(filter_harness.unit_price_with_measurement(nil, nil)).to eq("")
  end
end
