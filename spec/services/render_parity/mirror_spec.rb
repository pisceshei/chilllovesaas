# frozen_string_literal: true

require "rails_helper"

# 鏡像店（E8／E15）：把 hoko.vip 快照描述冪等地建到一間店。
# 🔴 假綠殺手：
#   MR1 來源語言必須真的切到 zh-Hans（只加不切 ⇒ `<html lang>` 仍 en）；E15 五語言必須「已發布＋白名單開放」而不只是
#       enabled（只 enabled ⇒ PrefixIndex 不解析、切換器不出現）；非主市場必須各有 subfolder presence（否則前綴組不出來）。
#   MR2 二次呼叫不得產生重複商品／集合／選單項／市場／presence／白名單列（find-or-skip 被拿掉 ⇒ 轉紅）。
#   MR3 對齊必須收斂：快照外的已發布語言不撤、多出的 region 不刪、預設語言被改不改回、關閉的白名單不重開 ⇒ 轉紅。
#   MR4 把資料面接到渲染面：available_languages 五項（碼／在地名／順序／前綴）＋頁首語言鈕真的出現。
RSpec.describe RenderParity::Mirror do
  let(:spec) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/render_parity/hoko.json"), encoding: "UTF-8"))
  end
  # 本尊 Settings › Languages 五語言（external-facts §G21；順序＝hoko 首頁 hreflang 序）
  let(:languages) { %w[zh-Hans zh-Hant en fr ja] }

  def counts(shop)
    ActsAsTenant.with_tenant(shop) do
      { products: Product.where(shop_id: shop.id).count, collections: Collection.where(shop_id: shop.id).count,
        pages: Page.where(shop_id: shop.id).count, items: MenuItem.where(shop_id: shop.id).count,
        themes: Theme.where(shop_id: shop.id).count, markets: Market.where(shop_id: shop.id).count,
        regions: MarketRegion.where(shop_id: shop.id).count, presences: MarketWebPresence.where(shop_id: shop.id).count,
        whitelist: MarketWebPresenceLocale.where(shop_id: shop.id).count, locales: ShopLocale.where(shop_id: shop.id).count }
    end
  end

  def whitelist_of(presence)
    presence.market_web_presence_locales.order(:position).pluck(:locale_tag, :is_market_default, :open_to_buyers)
  end

  it "MR1 🔴 建店＋對齊：店名／幣別／旗標、五語言（來源 zh-Hans、全部已發布、序同本尊）、五市場（主市場 TW＋四個 subfolder 市場）、主題、3 商品、集合、頁面、選單" do
    result = described_class.call(subdomain: "mirror-spec", spec: spec)
    shop = result.shop
    expect(shop.name).to eq("我的商店 3")
    expect(shop.store_currency).to eq("HKD")
    expect(shop.customer_accounts_enabled).to be(true)
    expect(shop.taxes_included).to be(true)
    ActsAsTenant.with_tenant(shop) do
      source = ShopLocale.find_by!(is_source: true)
      expect(source.locale_tag).to eq("zh-Hans")
      expect(ShopLocale.where(published: true).order(:position).pluck(:locale_tag)).to eq(languages)
      expect(ShopLocale.where(enabled: false)).to be_empty

      market = Market.find_by!(is_primary: true)
      expect(market).to have_attributes(name: "台灣", handle: "tw")
      expect(market.market_regions.pluck(:country_code)).to eq([ "TW" ])
      presence = market.market_web_presences.order(:id).first
      expect(presence.default_shop_locale).to eq("zh-Hans")
      expect(whitelist_of(presence)).to eq(languages.map { |tag| [ tag, tag == "zh-Hans", true ] })
      expect(languages.map { |tag| Markets::UrlPrefix.for(presence, tag) }).to eq(%w[/zh-hans-tw /zh-hant-tw /en-tw /fr-tw /ja-tw])

      extras = Market.where(is_primary: false).order(:handle)
      expect(extras.pluck(:handle, :name, :status, :market_type)).to eq(
        [ %w[eu 欧盟 active region], %w[hk 香港 active region], %w[jp 日本 active region], %w[us 美國 active region] ]
      )
      eu, hk, jp, us = extras.to_a
      expect(us.market_regions.pluck(:country_code)).to eq([ "US" ])
      expect(hk.market_regions.pluck(:country_code)).to eq([ "HK" ])
      expect(jp.market_regions.pluck(:country_code)).to eq([ "JP" ])
      expect(eu.market_regions.count).to eq(27)
      expect(eu.market_regions.pluck(:country_code)).to include("FR", "DE", "MT")
      extras.each do |extra|
        expect(extra.market_web_presences.count).to eq(1)
        extra_presence = extra.market_web_presences.first
        expect(extra_presence).to have_attributes(domain_id: nil, subfolder_suffix: extra.handle, default_shop_locale: "zh-Hans")
        expect(whitelist_of(extra_presence)).to eq(languages.map { |tag| [ tag, tag == "zh-Hans", true ] })
      end
      expect(Markets::UrlPrefix.for(eu.market_web_presences.first, "zh-Hant")).to eq("/zh-hant-eu") # 多國市場 region＝suffix
      expect(Markets::UrlPrefix.for(hk.market_web_presences.first, "en")).to eq("/en-hk")           # 單國市場 region＝國碼
      # 前綴 ≡ (market, locale)：五市場 × 五語言全部可解析、互不撞（67 §F.1(c)）
      domain = Domain.primary.find_by!(shop_id: shop.id)
      hit = Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "ja-jp")
      expect([ hit.market.handle, hit.locale_tag ]).to eq(%w[jp ja])
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hant")).to be_nil # 本尊形 /zh-hant 我方未裁（D80）

      expect(Theme.published.first).to have_attributes(name: "ella", version: "7.2.0")
      expect(Product.where(shop_id: shop.id, status: "active").order(:id).pluck(:handle)).to eq(%w[acme-tee bolt-mug cosy-lamp])
      expect(Product.find_by!(handle: "acme-tee").product_variants.first.price_cents).to eq(18_800)
      collection = Collection.find_by!(handle: "frontpage")
      expect(collection.title).to eq("首頁")
      expect(collection.sort_order).to eq("most_relevant") # E8b：本尊 admin 首頁系列 Default sort＝Most relevant
      expect(Page.find_by!(handle: "contact").title).to eq("聯絡我們")
      expect(Page.find_by!(handle: "contact").published_at).to be_present # E8b：本尊頁面已發布（先前草稿 ⇒ 前台 404）
      expect(Page.find_by!(handle: "contact").template_suffix).to eq("contact") # E8b：本尊 /pages/contact 用 page.contact 模板
      # E8b：庫存跟隨快照（本尊 products.json：只有 cosy-lamp available）
      lamp = Product.find_by!(handle: "cosy-lamp").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: lamp.id }).sum(:available)).to eq(10)
      tee = Product.find_by!(handle: "acme-tee").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: tee.id }).sum(:available)).to eq(0)
      expect(Menu.find_by!(handle: "main-menu").menu_items.order(:position).pluck(:title)).to eq(%w[首頁 目錄 聯絡我們])
    end
    expect(result.log).to include(a_string_matching(/\Ashop created/))
    expect(result.log).to include(a_string_matching(/\Amarket eu regions=27 suffix=eu prefixes=\/zh-hans-eu,/))
  end

  it "MR2 🔴 冪等：第二次呼叫不重複建立（商品／集合／頁面／選單項／主題／市場／region／presence／白名單／語言列數不變），只回報 exists" do
    first = described_class.call(subdomain: "mirror-spec", spec: spec)
    before = counts(first.shop)
    expect(before).to include(markets: 5, presences: 5, whitelist: 25, regions: 31, locales: 5)
    again = described_class.call(subdomain: "mirror-spec", spec: spec)
    expect(counts(again.shop)).to eq(before)
    expect(again.log).to include(a_string_matching(/product exists: acme-tee/))
    expect(again.log).to include(a_string_matching(/theme: published theme exists/))
  end

  it "MR3 🔴 對齊收斂：快照外的已發布語言撤發布、多出的 region 刪、被改掉的預設語言與關閉的白名單列復原" do
    shop = described_class.call(subdomain: "mirror-spec", spec: spec).shop
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.create!(shop_id: shop.id, locale_tag: "ko", enabled: true, published: true, position: 9)
      us = Market.find_by!(handle: "us")
      us.market_regions.create!(shop_id: shop.id, country_code: "CA")
      presence = Market.find_by!(is_primary: true).market_web_presences.order(:id).first
      presence.set_default_locale!("en")
      presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant").close!
    end

    described_class.call(subdomain: "mirror-spec", spec: spec)

    ActsAsTenant.with_tenant(shop) do
      expect(ShopLocale.find_by!(locale_tag: "ko")).to have_attributes(published: false, enabled: true) # 不刪列、只撤發布
      expect(ShopLocale.where(published: true).order(:position).pluck(:locale_tag)).to eq(languages)
      expect(Market.find_by!(handle: "us").market_regions.pluck(:country_code)).to eq([ "US" ])
      presence = Market.find_by!(is_primary: true).market_web_presences.order(:id).first
      expect(presence.default_shop_locale).to eq("zh-Hans")
      expect(whitelist_of(presence)).to eq(languages.map { |tag| [ tag, tag == "zh-Hans", true ] })
      expect(presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant").closed_at).to be_nil
    end
  end

  describe "MR4 資料面接到渲染面", type: :request do
    before do
      Rack::Attack.cache.store.clear
      Rails.cache.clear
    end

    it "MR4 🔴 available_languages 五項（本尊碼／在地名／primary／前綴）；首頁渲染出 Ella 頁首語言鈕（section-fetcher 形）" do
      shop = described_class.call(subdomain: "mirror-spec", spec: spec).shop
      ActsAsTenant.with_tenant(shop) do
        presence = Market.find_by!(is_primary: true).market_web_presences.order(:id).first
        drop = Storefront::LocalizationContext.drop(web_presence: presence, locale_tag: "zh-Hans")
        available = drop.invoke_drop("available_languages")
        # 本尊 header 區段（Section Rendering `hoko.vip/?section_id=sections--19763396837479__header_default`，2026-09-04）
        # 語言清單逐字：zh-CN 简体中文／zh-TW 繁體中文／en English／fr Français／ja 日本語
        expect(available.map { |l| l["iso_code"] }).to eq(%w[zh-CN zh-TW en fr ja])
        expect(available.map { |l| l["endonym_name"] }).to eq(%w[简体中文 繁體中文 English Français 日本語])
        expect(available.map { |l| l["primary"] }).to eq([ true, false, false, false, false ])
        expect(available.map { |l| l["root_url"] }).to eq(%w[/zh-hans-tw /zh-hant-tw /en-tw /fr-tw /ja-tw])
      end

      host! "mirror-spec.lvh.me"
      https!
      get "/zh-hans-tw/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(Shopify.locale = "zh-CN"))
      # Ella header：show_language 只在 available_languages.size > 1 時為真 ⇒ 語言鈕（icon 型：按鈕＋section-fetcher）出現；
      # 單語言時整段不渲染（E8 首輪即此形，與本尊多語言前的首頁同）
      expect(response.body).to include("dropdown-localization__button")
      expect(response.body).to include("CountryLocalizationList")
    end
  end
end
