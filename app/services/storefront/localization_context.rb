# frozen_string_literal: true

module Storefront
  # localization drop 的真值建構（包 34；67 §F.2 切換器內容規則）。
  #
  # 🔴 available_languages **只列「當前 presence 開放且已發布」**（open_to_buyers ∧
  #   shop_locales.published），依 position 排序、顯示 endonym——不列全店啟用語言
  #   （裁定逐字「前台不用全部顯示出來」）。⇒ 切換器在定義上不可能產生 404 連結
  #   （每一條 root_url 都來自 PrefixIndex 可解析的同一開放集）。
  # 🔴 語言與地區是兩個控件（switcher_is_two_controls）：本服務只供資料，
  #   合併控件的 UI 形態在 lint 層擋。
  #
  # E15（2026-09-04）`available_countries`／`country`：
  #   官方 objects/localization 逐字 "The countries that are available on the store."；objects/country 逐字
  #   （external-facts §G22）：name "The name of the country."、iso_code "…ISO 3166-1 (alpha 2)…"、currency "The currency used in
  #   the country."、market "The market that includes this country."、available_languages "The languages that have been added to the
  #   market that this country belongs to."、popular? "Returns `true` if the country is popular for this shop."。
  #   本尊實測（hoko.vip 五市場、header 區段 Section Rendering，2026-09-04）：31 國＝全部市場 regions 聯集；順序＝當前語言在地名的
  #   本尊觀察序（zh-CN 碼位序：丹麦／保加利亚／克罗地亚／匈牙利…）；`name`＝在地名（台湾／美国／香港特别行政区／日本）；每列
  #   `({{ currency.symbol }}{{ currency.iso_code }})`＝`($HKD)`（全市場繼承店幣別）；當前國＝presence 市場的 region（TW）。
  #   ⇒ 我方集合＝與當前 presence 同一 effective domain 的 active region 市場（自身無 presence 者沿 lineage 用 primary 的），
  #   在地名與順序讀 `ThemeEngine::CountryOptionTags` 字典（與 `all_country_option_tags` 同一本尊來源）。
  #   `popular?` 恆 false（本尊零訂單店未出 popular 清單，規則官方未逐字 ⇒ V）；`continent`／`unit_system` 官方值域已取得、
  #   逐國對映未取得（V，91 §3.83）——不給值，主題讀到 nil 走 count_miss 遙測。
  #   🔴 Ella 頁首據此分支：`available_countries.size > 1 ∧ available_languages.size > 1` ⇒ 「地區＋語言」形（section-fetcher＋按鈕，
  #   本尊初始 HTML 即此形）；只有語言 ⇒ 內嵌整個語言表單。E15 前我方恆單國 ⇒ 五語言同步後初始 HTML 仍與本尊不同（MR4）。
  module LocalizationContext
    module_function

    # @param web_presence [MarketWebPresence] URL 身分所屬的 presence（語言集合／root_url 來源）
    # @param locale_tag [String] 當前語言
    # @param market [Market, nil] 生效市場（D80：買家選國 cookie 覆寫後；nil ⇒ presence 的市場）
    # @param country_code [String, nil] 買家選定國家（nil ⇒ 市場第一個 region）
    # @return [ThemeEngine::LocalizationDrop]
    def drop(web_presence:, locale_tag:, market: nil, country_code: nil)
      shop = web_presence.shop
      languages = languages_for(web_presence)
      current_code = ThemeEngine::LocaleTags.shopify_code(locale_tag)
      current = languages.find { |l| l["iso_code"] == current_code } ||
                { "iso_code" => current_code,
                  "endonym_name" => PlatformLocale.where(tag: locale_tag).pick(:endonym) || locale_tag,
                  "primary" => false,
                  "root_url" => root_url_for(web_presence, locale_tag) }

      market ||= web_presence.market
      countries = available_countries(web_presence, locale_tag)
      country_code ||= market.region_country_codes.first
      country = countries.find { |c| c["iso_code"] == country_code } ||
                (country_code && country_hash(country_code, market, languages, shop, locale_tag))
      # E17：country 物件用 CountryDrop（`{{ country }}` ⇒ 國名）；available_countries 逐項同形
      country = ThemeEngine::CountryDrop.new(country) if country.is_a?(Hash)
      countries = countries.map { |c| ThemeEngine::CountryDrop.new(c) }

      ThemeEngine::LocalizationDrop.new(
        language: current, available_languages: languages, country: country, available_countries: countries,
        market: { "handle" => market.handle, "id" => market.id }
      )
    end

    # 當前 presence 開放 ∧ 已發布的語言（position 序）。
    # @return [Array<Hash>] iso_code（本尊碼）／endonym_name／primary／root_url
    def languages_for(web_presence)
      rows = web_presence.market_web_presence_locales.open_to_buyers.to_a
      published = ShopLocale.where(shop_id: web_presence.shop_id, published: true).pluck(:locale_tag).to_set
      endonyms = PlatformLocale.where(tag: rows.map(&:locale_tag)).pluck(:tag, :endonym).to_h

      rows.select { |row| published.include?(row.locale_tag) }.map do |row|
        {
          "iso_code" => ThemeEngine::LocaleTags.shopify_code(row.locale_tag), # 本尊碼形（zh-Hans ⇒ zh-CN）
          "endonym_name" => endonyms.fetch(row.locale_tag, row.locale_tag),
          "primary" => row.is_market_default,
          "root_url" => root_url_for(web_presence, row.locale_tag)
        }
      end
    end

    # language.root_url（D80）：預設語言於共用網域無前綴 ⇒ "/"（本尊 `window.routes.root_url = "/"`；其他語言 "/zh-hant"）。
    def root_url_for(web_presence, locale_tag)
      Markets::UrlPrefix.for(web_presence, locale_tag).presence || "/"
    end

    # 與 `web_presence` 同一 effective domain 的 active region 市場 ⇒ regions 聯集（同國只列一次，先命中的市場為準），
    # 依當前語言在字典的本尊觀察序排序。draft 市場、非 region 市場、其他網域的市場不列。
    # @return [Array<Hash>] 官方 country 物件形（見檔頭）
    def available_countries(web_presence, locale_tag)
      shop = web_presence.shop
      domain_id = Markets::PrefixIndex.effective_domain_id(web_presence)
      key = ThemeEngine::CountryOptionTags.lang_key(locale_tag)
      rows = {}
      ActsAsTenant.with_tenant(shop) do
        primary_presence = Market.where(shop_id: shop.id).find_by(is_primary: true)
                                 &.market_web_presences&.order(:id)&.first
        Market.where(shop_id: shop.id).active.where(market_type: "region")
              .includes(:market_regions, :market_web_presences).order(:id).each do |market|
          presence = market.market_web_presences.min_by(&:id) || primary_presence
          next if presence.nil? || Markets::PrefixIndex.effective_domain_id(presence) != domain_id

          market.market_regions.each { |region| rows[region.country_code] ||= [ market, presence ] }
        end
      end
      languages_by_presence = Hash.new { |h, presence| h[presence] = languages_for(presence) }
      rows.sort_by { |code, _| [ ThemeEngine::CountryOptionTags.sort_key(code, key), code ] }
          .map { |code, (market, presence)| country_hash(code, market, languages_by_presence[presence], shop, locale_tag) }
    end

    # 官方 country 物件（external-facts §G22）；currency＝店幣別（我方市場無獨立幣別，同本尊 hoko 全市場繼承 HKD）。
    def country_hash(code, market, languages, shop, locale_tag)
      key = ThemeEngine::CountryOptionTags.lang_key(locale_tag)
      {
        "iso_code" => code,
        "name" => ThemeEngine::CountryOptionTags.label_for(code, key),
        "currency" => { "iso_code" => shop.store_currency,
                        "symbol" => ThemeEngine::Currencies.symbol(shop.store_currency, money_format: shop.money_format),
                        "name" => ThemeEngine::Currencies.name(shop.store_currency) },
        "market" => { "handle" => market.handle, "id" => market.id },
        "available_languages" => languages,
        "popular?" => false
      }
    end
  end
end
