# frozen_string_literal: true

module Markets
  # URL 前綴的唯一產生器（docs/specs/67 §F.1(b)；🔴 2026-09-04 D80 方案 1 使用者裁定：改回本尊形）。
  #
  #   共用網域 presence（primary domain 或市場自有網域；subfolder_suffix 空）：
  #     locale ＝ presence 預設語言 ⇒ ""（無前綴；根路徑直接服務、不重導）
  #     其他語言                    ⇒ "/" + downcase(locale_tag)                 例 /zh-hant、/en、/ja
  #   子資料夾 presence（subfolder_suffix 非空）：
  #     全部語言 ⇒ "/" + downcase(locale_tag) + "-" + subfolder_suffix            例 /en-ca、/fr-ca
  #
  # 取證（docs/dev/external-facts.md §G23，2026-09-04 curl hoko.vip）：`/` 200 且 `lang="zh-CN"`（預設語言無前綴）；
  # `/zh-hans/` 404（預設語言沒有前綴形）；`/zh-hant/`、`/en/`、`/en/collections/all` 200；`Shopify.routes.root = "/zh-hant/"`。
  # 官方 help 逐字 "Use subfolders, such as example.com/de"；子資料夾市場逐字 "such as example.com/fr-ca"。
  # 2026-08-13「恆帶地區、恆有前綴」裁定被 D80 推翻——67 §F.1(b) 保留該段沿革與本次更正（鐵律 19.5）。
  #
  # 🔴 部分函式（可回空字串）：消費端拼接一律 `"#{prefix}#{path}"`，根路徑 ⇒ `"#{prefix}/"`；
  #   `Shopify.routes.root` 由 PageRenderer#root_prefix_path 統一加尾斜線（"" ⇒ "/"）、`routes.root_url` 由 RoutesDrop（"" ⇒ "/"）。
  # 🔴 與 `Markets::HreflangCodes` 仍是**型別分離的兩個函式**（67 §F.1(a)；SF-9）：本函式回**恰一個 String**（路由身分），
  #   那邊回 **Set**（標註碼）。簽名不收 Set/Array——把 hreflang 集合餵進路由的路徑以 TypeError 封死。
  #   輸出**永遠不得**被當成 hreflang 值使用（limits `i18n.locale_prefix.never_reused_as_hreflang_code`）。
  # 🔴 前綴不再依賴市場 regions：子資料夾 presence 的 region 段＝suffix 本身（本尊 subfolder 是商家設定的識別字，
  #   不是從市場國家推導）；零 region 市場的 presence 照樣算得出前綴（hreflang 那邊仍對零 region raise）。
  module UrlPrefix
    class Error < StandardError; end

    # 沿革保留：D80 前「多國市場無 suffix／零 region ⇒ raise」的錯誤類別。D80 後本函式不再拋它（前綴不看 regions），
    # 保留類別只為既有 `rescue Markets::UrlPrefix::Error` 面不需逐一改動；新程式不得依賴它會被拋出。
    class MissingRegionSource < Error; end

    # 第一路徑段形（路由層「像不像前綴」判別共用同一來源，不得在 controller 抄第二份）：
    #   {lang(2-3)}[-{script(4)}][-{region(2)}]——後段可選（共用網域 /zh-hant、子資料夾 /en-ca 兩形都要收）。
    # 🔴 「像前綴」只是省一次查表的粗篩，不是身分：身分一律由 PrefixIndex.resolve 對實際白名單決定。
    SEGMENT = /[a-z]{2,3}(-[a-z]{4})?(-[a-z]{2})?/
    # 輸出必匹配：空字串（預設語言）或 /SEGMENT
    FORMAT = %r{\A(|/#{SEGMENT.source})\z}

    module_function

    # @param web_presence [MarketWebPresence]
    # @param locale [ShopLocale, String] locale 或其 tag。🔴 不收 Set/Array（SF-9 型別分離）
    # @return [String] 全小寫；預設語言於共用網域 ⇒ ""；其餘例 "/zh-hant"、"/en-ca"
    # @raise [TypeError] locale 是集合——那是 hreflang_codes 的形狀，不是路由的
    # @raise [Error] 輸出不匹配 FORMAT（tag／suffix 髒值一律拒絕，不得靜默修剪）或撞保留段
    def for(web_presence, locale)
      tag = locale_tag_of(locale)
      suffix = web_presence.subfolder_suffix.presence
      prefix =
        if suffix
          "/#{tag.downcase}-#{suffix}"
        elsif tag.casecmp?(web_presence.default_shop_locale.to_s)
          ""
        else
          "/#{tag.downcase}"
        end
      unless prefix.match?(FORMAT)
        raise Error, "前綴 #{prefix.inspect} 不匹配 67 §F.1(b) 正則——輸入含非法字元或格式"
      end

      if prefix.present?
        first_segment = prefix.delete_prefix("/")
        if Limits.fetch(:handle, :reserved_first_segments).map(&:to_s).include?(first_segment)
          raise Error, "前綴 #{prefix.inspect} 撞保留第一路徑段（67 §F.1(c)）"
        end
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
  end
end
