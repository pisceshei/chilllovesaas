# frozen_string_literal: true

module Markets
  # URL 前綴的唯一產生器（docs/specs/67 §F.1(b)；2026-08-13 裁定）。
  #
  #   url_prefix(wp, loc) = "/" + downcase( locale_tag(loc) + "-" + region_of(wp.market) )
  #
  # 🔴 恆帶地區、恆有前綴、無例外——與市場是否 primary 無關、與語言是否預設無關
  #   （裁定逐字：「香港就是 en-HK……共用繁體中文，那香港就是 zh-Hant-HK，台灣就是 zh-Hant-TW」）。
  #   全函式（永不回空字串）是刻意設計：部分函式會讓 hreflang／sitemap／canonical／routes
  #   四處各自長出一套「前綴為空時」的拼接邏輯（67 §F.1(b) 為什麼獨立網域也要帶）。
  #
  # 🔴 與 `Markets::HreflangCodes` 是**型別分離的兩個函式**（67 §F.1(a)；SF-9）：
  #   本函式回**恰一個 String**（路由身分）；那邊回 **Set**（標註碼，多國市場逐國展開）。
  #   簽名不收 Set/Array——把 hreflang 集合餵進路由的路徑以 TypeError 封死。
  #   輸出**永遠不得**被當成 hreflang 值使用（limits `i18n.locale_prefix.never_reused_as_hreflang_code`）。
  module UrlPrefix
    class Error < StandardError; end

    # region 來源缺失：多國市場無 subfolder_suffix（V-225 暫案 C 之外的形態）或零 region 市場。
    # 🔴 fail-closed：不得退回裸語言前綴（bare_language_prefix_forbidden）、不得猜「代表國」。
    class MissingRegionSource < Error; end

    # 輸出必匹配（67 §F.1(b) 逐字正則）：/{lang(2-3)}[-{script(4)}]-{region(2)}
    FORMAT = /\A\/[a-z]{2,3}(-[a-z]{4})?-[a-z]{2}\z/

    module_function

    # @param web_presence [MarketWebPresence]
    # @param locale [ShopLocale, String] locale 或其 tag。🔴 不收 Set/Array（SF-9 型別分離）
    # @return [String] 恆非空、全小寫，例 "/zh-hant-hk"
    # @raise [TypeError] locale 是集合——那是 hreflang_codes 的形狀，不是路由的
    # @raise [MissingRegionSource] 市場 region 來源缺失（fail-closed，V-225）
    # @raise [Error] 輸出不匹配 FORMAT（tag／suffix 髒值一律拒絕，不得靜默修剪）
    def for(web_presence, locale)
      prefix = "/#{locale_tag_of(locale).downcase}-#{region_of(web_presence)}"
      unless prefix.match?(FORMAT)
        raise Error, "前綴 #{prefix.inspect} 不匹配 67 §F.1(b) 正則——輸入含非法字元或格式"
      end

      first_segment = prefix.delete_prefix("/")
      if Limits.fetch(:handle, :reserved_first_segments).map(&:to_s).include?(first_segment)
        raise Error, "前綴 #{prefix.inspect} 撞保留第一路徑段（67 §F.1(c)）"
      end

      prefix
    end

    # @param locale [ShopLocale, String]
    # @return [String] 正規化 tag（zh-Hant 形；大小寫在 #for 才壓小寫）
    def locale_tag_of(locale)
      if locale.is_a?(Enumerable)
        raise TypeError, "url_prefix 不收集合（SF-9）：一個 (market, locale) 恰一個前綴；" \
                         "hreflang 的一組碼請走 Markets::HreflangCodes"
      end

      tag = locale.respond_to?(:locale_tag) ? locale.locale_tag : locale
      raise TypeError, "locale 必須是 ShopLocale 或 String tag，收到 #{locale.class}" unless tag.is_a?(String)

      tag
    end

    # region 段（67 §F.1(b)／(b-2)）：
    #   單國市場 ⇒ 該國碼；多國市場 ⇒ presence 的 subfolder_suffix（V-225 暫案 C——
    #   「唯一不需要平台替商家做任意選擇的選項」）；零 region ⇒ raise。
    # @param web_presence [MarketWebPresence]
    # @return [String] 兩碼小寫
    def region_of(web_presence)
      countries = web_presence.market.region_country_codes
      return countries.first.downcase if countries.size == 1
      if countries.size > 1
        suffix = web_presence.subfolder_suffix
        return suffix if suffix.present?

        raise MissingRegionSource,
              "多國市場的 presence 無 subfolder_suffix——region 來源缺失（V-225 暫案 C 只認 suffix）"
      end

      raise MissingRegionSource,
            "市場 #{web_presence.market_id} 零 region（type=#{web_presence.market.market_type}）——" \
            "非 region 條件市場沒有 URL 前綴語義"
    end
  end
end
