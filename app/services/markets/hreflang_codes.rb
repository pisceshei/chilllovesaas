# frozen_string_literal: true

module Markets
  # hreflang 碼產生器（docs/specs/62 §I.2；🔴 2026-09-04 D80 方案 1 使用者裁定：共用網域改回本尊的語言碼形）。
  #
  #   共用網域 presence（subfolder_suffix 空）⇒ {language[-Script]}  一個碼：zh-Hans／zh-Hant／en／fr／ja
  #   子資料夾 presence（subfolder_suffix 非空）⇒ 逐國展開 {language[-Script]-REGION}：EU(FR/DE/BE)＋en ⇒ {en-FR, en-DE, en-BE}
  #
  # 取證（external-facts §G23，2026-09-04 curl hoko.vip 每頁 `<head>`）：五語言五市場的本尊只輸出六條——
  # x-default→無前綴、zh-Hans→無前綴、zh-Hant→/zh-hant…、en／fr／ja→/en…／/fr…／/ja…；沒有任何 `-TW`／`-US` 地區碼，
  # 市場（台灣／美國／香港／日本／欧盟）完全不進 hreflang。子資料夾／自有網域市場的本尊形未取得（V，91 §3.84）——
  # 沿用逐國展開（2026-08-13 裁定的形），碼的地區維度來自市場 regions。
  #
  # 🔴 回傳 **Set**（複數）——與 `Markets::UrlPrefix`（恰一個 String）型別分離（67 §F.1(a)；SF-9）。
  # 🔴 大小寫與 URL 前綴不同、不得互相借用（62 §I.2）：碼＝小寫語言＋Title script＋大寫地區（zh-Hant／zh-Hant-HK）；
  #   前綴＝全小寫（/zh-hant／/zh-hant-hk）。
  # 🔴 子資料夾 presence 的市場零 region ⇒ raise（逐國展開沒有合法輸出）；共用網域不看 regions。
  module HreflangCodes
    class EmptyRegions < StandardError; end
    class InvalidTag < StandardError; end

    module_function

    # presence 級入口（Seo::HreflangMatrix 唯一消費端）：依 presence 形態分派。
    # @param web_presence [MarketWebPresence]
    # @param locale [ShopLocale, String]
    # @return [Set<String>]
    def for_presence(web_presence, locale)
      return self.for(web_presence.market, locale) if web_presence.subfolder_suffix.present?

      Set.new([ language_code(locale) ])
    end

    # 語言碼（62 §I.2 偽代碼逐字的 base）：language ＋（可選）script；locale 自帶的 region **不進 base**
    # （67 §A.4：地區來自市場，不是語言身分——本尊五語言全部無地區碼）。
    # @param locale [ShopLocale, String]
    # @return [String] 例 "zh-Hant"、"en"
    # @raise [InvalidTag] tag 不匹配 BCP-47 三段形
    def language_code(locale)
      tag = locale.respond_to?(:locale_tag) ? locale.locale_tag : locale
      match = Locales::Tag::FORMAT.match(Locales::Tag.normalize(tag.to_s))
      raise InvalidTag, "無法解析語言標籤 #{tag.inspect}" if match.nil?

      base = match[:language]
      base += "-#{match[:script]}" if match[:script]
      base
    end

    # 逐國展開（子資料夾 presence 專用；D80 前的全域形）。
    # @param market [Market]
    # @param locale [ShopLocale, String] locale 或其 tag
    # @return [Set<String>] 每國一碼，例 #<Set: {"zh-Hant-HK"}>
    # @raise [EmptyRegions] 市場零 region——逐國展開沒有合法輸出
    # @raise [InvalidTag] tag 不匹配 BCP-47 三段形
    def for(market, locale)
      base = language_code(locale)
      countries = market.region_country_codes
      if countries.empty?
        raise EmptyRegions,
              "市場 #{market.id} 零 region——子資料夾 presence 的 hreflang 逐國展開（62 §I.2），沒有合法輸出 #{base.inspect}"
      end

      countries.map { |country| "#{base}-#{country.upcase}" }.to_set
    end
  end
end
