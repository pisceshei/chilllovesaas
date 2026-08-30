# frozen_string_literal: true

module Markets
  # hreflang 碼產生器（docs/specs/62 §I.2；2026-08-13 裁定「恆帶地區」）。
  #
  # 🔴 回傳 **Set**（複數）——多國市場逐國展開成 N 個碼、全部指向同一 URL：
  #   EU（FR/DE/BE）＋ en ⇒ {en-FR, en-DE, en-BE}。原函式名 hreflang_code（單數）已停用。
  # 🔴 裸語言碼一律禁止（limits `seo.hreflang.bare_language_code_forbidden`）：
  #   regions 空集合 ⇒ raise，**不得退回裸碼**（62 §I.2 逐字 assert）。
  # 🔴 大小寫與 URL 前綴不同、不得互相借用（62 §I.2）：碼＝小寫語言＋Title script＋大寫地區
  #   （zh-Hant-HK）；前綴＝全小寫（/zh-hant-hk）。型別也分離（Set vs String，67 §F.1(a)）。
  #
  # 明知偏離 Shopify 登記：本尊多國市場輸出裸語言碼（62 §I.2-1）；我方依裁定逐國展開。
  module HreflangCodes
    class EmptyRegions < StandardError; end
    class InvalidTag < StandardError; end

    module_function

    # @param market [Market]
    # @param locale [ShopLocale, String] locale 或其 tag
    # @return [Set<String>] 每國一碼，例 #<Set: {"zh-Hant-HK"}>
    # @raise [EmptyRegions] 市場零 region——裸碼被禁，這裡沒有合法輸出
    # @raise [InvalidTag] tag 不匹配 BCP-47 三段形
    def for(market, locale)
      tag = locale.respond_to?(:locale_tag) ? locale.locale_tag : locale
      match = Locales::Tag::FORMAT.match(Locales::Tag.normalize(tag.to_s))
      raise InvalidTag, "無法解析語言標籤 #{tag.inspect}" if match.nil?

      # 62 §I.2 偽代碼逐字：base ＝ language ＋（可選）script。locale 自帶的 region **不進 base**
      # ——碼的地區維度一律來自市場（67 §A.4：地區來自市場，不是語言身分）。
      base = match[:language]
      base += "-#{match[:script]}" if match[:script]

      countries = market.region_country_codes
      if countries.empty?
        raise EmptyRegions,
              "市場 #{market.id} 零 region——hreflang 恆帶地區（62 §I.2），不得退回裸語言碼 #{base.inspect}"
      end

      countries.map { |country| "#{base}-#{country.upcase}" }.to_set
    end
  end
end
