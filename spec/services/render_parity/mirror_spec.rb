# frozen_string_literal: true

require "rails_helper"

# 鏡像店（E8／E15）：把 hoko.vip 快照描述冪等地建到一間店。
# 🔴 假綠殺手：
#   MR1 來源語言必須真的切到 zh-Hans（只加不切 ⇒ `<html lang>` 仍 en）；E15 五語言必須「已發布＋白名單開放」而不只是
#       enabled（只 enabled ⇒ PrefixIndex 不解析、切換器不出現）；非主市場**不得**有 presence（D80：本尊市場共用主網域、
#       /en-us 404；E15 期建的 subfolder presence 要被拆掉，否則 hreflang／sitemap 多出一整組 URL）。
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

  it "MR1 🔴 建店＋對齊：店名／幣別／旗標、五語言（來源 zh-Hans、全部已發布、序同本尊）、五市場（主市場 TW＋四個共用主網域市場、無 presence）、主題、3 商品、集合、頁面、選單" do
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
      # D80：預設語言無前綴、其他裸語言段（本尊 hoko.vip：/ 、/zh-hant、/en、/fr、/ja）
      expect(languages.map { |tag| Markets::UrlPrefix.for(presence, tag) }).to eq([ "", "/zh-hant", "/en", "/fr", "/ja" ])

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
      extras.each { |extra| expect(extra.market_web_presences.count).to eq(0) } # D80：共用主網域市場無 presence
      # 前綴 ≡ (presence, locale)：只有主 presence 的四個非預設語言段可解析；舊地區形與市場段都不存在（本尊 /en-us 404）
      domain = Domain.primary.find_by!(shop_id: shop.id)
      hit = Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hant")
      expect([ hit.market.handle, hit.locale_tag ]).to eq(%w[tw zh-Hant])
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "ja-jp")).to be_nil
      expect(Markets::PrefixIndex.resolve(shop:, domain:, first_segment: "zh-hans")).to be_nil # 預設語言無前綴形
      expect(Markets::PrefixIndex.prefix_segments(shop:)).to eq(Set.new(%w[zh-hant en fr ja]))
      # 買家選國（cookie）⇒ 共用市場覆寫：JP ⇒ 日本市場、presence／語言不變
      jp_hit = Markets::PrefixIndex.with_buyer_country(hit, shop:, domain:, country_code: "JP")
      expect([ jp_hit.market.handle, jp_hit.web_presence, jp_hit.locale_tag, jp_hit.effective_country_code ]).to eq([ "jp", presence, "zh-Hant", "JP" ])
      fr_hit = Markets::PrefixIndex.with_buyer_country(hit, shop:, domain:, country_code: "FR")
      expect([ fr_hit.market.handle, fr_hit.effective_country_code ]).to eq(%w[eu FR])

      expect(Theme.published.first).to have_attributes(name: "ella", version: "7.2.0")
      expect(Product.where(shop_id: shop.id, status: "active").order(:id).pluck(:handle)).to eq(%w[acme-tee bolt-mug cosy-lamp])
      expect(Product.find_by!(handle: "acme-tee").product_variants.first.price_cents).to eq(18_800)
      collection = Collection.find_by!(handle: "frontpage")
      expect(collection.title).to eq("首頁")
      expect(collection.sort_order).to eq("most_relevant") # E8b：本尊 admin 首頁系列 Default sort＝Most relevant
      expect(Page.find_by!(handle: "contact").title).to eq("聯絡我們")
      expect(Page.find_by!(handle: "contact").published_at).to be_present # E8b：本尊頁面已發布（先前草稿 ⇒ 前台 404）
      expect(Page.find_by!(handle: "contact").template_suffix).to eq("contact") # E8b：本尊 /pages/contact 用 page.contact 模板
      expect(ShopPolicy.find_by!(kind: "privacy-policy").title).to eq("隐私政策") # T13：本尊只有 privacy-policy 有內容（其餘 404）
      expect(ShopPolicy.where(kind: "refund-policy")).to be_empty
      # E8b：庫存跟隨快照（本尊 products.json：只有 cosy-lamp available）
      lamp = Product.find_by!(handle: "cosy-lamp").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: lamp.id }).sum(:available)).to eq(10)
      tee = Product.find_by!(handle: "acme-tee").product_variants.first
      expect(InventoryLevel.joins(:inventory_item).where(inventory_items: { product_variant_id: tee.id }).sum(:available)).to eq(0)
      expect(Menu.find_by!(handle: "main-menu").menu_items.order(:position).pluck(:title)).to eq(%w[首頁 目錄 聯絡我們])
    end
    expect(result.log).to include(a_string_matching(/\Ashop created/))
    expect(result.log).to include(a_string_matching(/\Amarket eu regions=27 presence=none/))
    expect(result.log).to include(a_string_matching(/\Amarket tw country=TW presence default=zh-Hans prefixes=,\/zh-hant,\/en,\/fr,\/ja\z/))
  end

  it "MR2 🔴 冪等：第二次呼叫不重複建立（商品／集合／頁面／選單項／主題／市場／region／presence／白名單／語言列數不變），只回報 exists" do
    first = described_class.call(subdomain: "mirror-spec", spec: spec)
    before = counts(first.shop)
    expect(before).to include(markets: 5, presences: 1, whitelist: 5, regions: 31, locales: 5)
    again = described_class.call(subdomain: "mirror-spec", spec: spec)
    expect(counts(again.shop)).to eq(before)
    expect(again.log).to include(a_string_matching(/product exists: acme-tee/))
    expect(again.log).to include(a_string_matching(/theme: published theme exists/))
  end

  it "MR3 🔴 對齊收斂：快照外的已發布語言撤發布、多出的 region 刪、被改掉的預設語言與關閉的白名單列復原、E15 期的 subfolder presence 拆掉" do
    shop = described_class.call(subdomain: "mirror-spec", spec: spec).shop
    ActsAsTenant.with_tenant(shop) do
      ShopLocale.create!(shop_id: shop.id, locale_tag: "ko", enabled: true, published: true, position: 9)
      us = Market.find_by!(handle: "us")
      us.market_regions.create!(shop_id: shop.id, country_code: "CA")
      # E15 期建過的 subfolder presence（D80 前的形）——對齊必須拆掉，否則 hreflang／sitemap 多一整組 /zh-hans-us URL
      us.market_web_presences.create!(shop_id: shop.id, subfolder_suffix: "us", default_shop_locale: "zh-Hans")
        .market_web_presence_locales.create!(shop_id: shop.id, locale_tag: "zh-Hans", position: 0, is_market_default: true)
      presence = Market.find_by!(is_primary: true).market_web_presences.order(:id).first
      presence.set_default_locale!("en")
      presence.market_web_presence_locales.find_by!(locale_tag: "zh-Hant").close!
    end

    result = described_class.call(subdomain: "mirror-spec", spec: spec)
    expect(result.log).to include(a_string_matching(/\Amarket us regions=1 presence=none（共用主網域） removed=1\z/))

    ActsAsTenant.with_tenant(shop) do
      expect(ShopLocale.find_by!(locale_tag: "ko")).to have_attributes(published: false, enabled: true) # 不刪列、只撤發布
      expect(ShopLocale.where(published: true).order(:position).pluck(:locale_tag)).to eq(languages)
      expect(Market.find_by!(handle: "us").market_regions.pluck(:country_code)).to eq([ "US" ])
      expect(Market.find_by!(handle: "us").market_web_presences.count).to eq(0)
      expect(MarketWebPresence.where(shop_id: shop.id).count).to eq(1)
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
        # D80：本尊 language.root_url——預設 "/"、其他 "/zh-hant"（hoko `window.routes.root_url` 於 / 與 /zh-hant/ 各為 "/"／"/zh-hant"）
        expect(available.map { |l| l["root_url"] }).to eq([ "/", "/zh-hant", "/en", "/fr", "/ja" ])
      end

      host! "mirror-spec.lvh.me"
      https!
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(Shopify.locale = "zh-CN"))
      expect(response.body).to include(%(Shopify.routes.root = "/";))
      expect(response.body).to include(%(Shopify.country = "TW";))
      # hreflang 六條＝本尊 hoko.vip 首頁形（x-default／zh-Hans 指根，其餘裸語言段；零地區碼、零市場段）
      links = response.body.scan(/<link rel="alternate" hreflang="([^"]+)" href="https:\/\/mirror-spec\.lvh\.me([^"]*)">/)
    # E19：x-default 首（本尊 content_for_header hreflang 序，§G27）
    expect(links).to eq([ [ "x-default", "/" ], [ "zh-Hans", "/" ], [ "zh-Hant", "/zh-hant" ], [ "en", "/en" ], [ "fr", "/fr" ], [ "ja", "/ja" ] ]) # 帶前綴的根無尾斜線（hoko 首頁 §G27）
      get "/zh-hant/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(Shopify.locale = "zh-TW"))
      expect(response.body).to include(%(Shopify.routes.root = "/zh-hant/";))
      get "/zh-hans-tw/" # 2026-08-13 舊形（E15 期的 mirror URL）＝沒有這個頁面
      expect(response).to have_http_status(:not_found)
      get "/en-us/"      # 本尊 /en-us 404（市場不產生前綴）
      expect(response).to have_http_status(:not_found)
      get "/"

      # Ella header：show_language 只在 available_languages.size > 1 時為真 ⇒ 語言鈕（icon 型：按鈕＋section-fetcher）出現；
      # 單語言時整段不渲染（E8 首輪即此形，與本尊多語言前的首頁同）
      expect(response.body).to include("dropdown-localization__button")
      expect(response.body).to include("CountryLocalizationList")
    end
  end
end
