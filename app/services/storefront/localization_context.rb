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
  module LocalizationContext
    module_function

    # @param web_presence [MarketWebPresence]
    # @param locale_tag [String] 當前語言
    # @return [ThemeEngine::LocalizationDrop]
    def drop(web_presence:, locale_tag:)
      rows = web_presence.market_web_presence_locales.open_to_buyers.to_a
      published = ShopLocale.where(shop_id: web_presence.shop_id, published: true)
                            .pluck(:locale_tag).to_set
      endonyms = PlatformLocale.where(tag: rows.map(&:locale_tag)).pluck(:tag, :endonym).to_h

      languages = rows.select { |row| published.include?(row.locale_tag) }.map do |row|
        {
          "iso_code" => ThemeEngine::LocaleTags.shopify_code(row.locale_tag), # 本尊碼形（zh-Hans ⇒ zh-CN）
          "endonym_name" => endonyms.fetch(row.locale_tag, row.locale_tag),
          "primary" => row.is_market_default,
          "root_url" => Markets::UrlPrefix.for(web_presence, row.locale_tag)
        }
      end

      current_code = ThemeEngine::LocaleTags.shopify_code(locale_tag)
      current = languages.find { |l| l["iso_code"] == current_code } ||
                { "iso_code" => current_code, "endonym_name" => endonyms.fetch(locale_tag, locale_tag),
                  "primary" => false,
                  "root_url" => Markets::UrlPrefix.for(web_presence, locale_tag) }

      market = web_presence.market
      country = market.region_country_codes.first&.then do |code|
        { "iso_code" => code, "name" => code,
          "currency" => { "iso_code" => web_presence.shop.store_currency,
                          "symbol" => nil } }
      end

      ThemeEngine::LocalizationDrop.new(
        language: current, available_languages: languages, country: country,
        market: { "handle" => market.handle, "id" => market.id }
      )
    end
  end
end
