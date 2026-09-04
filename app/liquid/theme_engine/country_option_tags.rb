# frozen_string_literal: true

require "json"
require "set"

module ThemeEngine
  # Liquid 全域 `all_country_option_tags`／`country_option_tags` 的 `<option>` 串（E14，2026-09-04）。
  #
  # ①這是什麼：官方 objects 頁逐字（external-facts §G20）——`all_country_option_tags`："Creates an `<option>` tag for each country."；
  #   `country_option_tags`："Creates an `<option>` tag for each country and region that's included in a shipping zone on the Shipping
  #   page of the Shopify admin."；兩者每個 option 都帶 `data-provinces`＝子區域 JSON 陣列（無子區域＝`[]`）。
  # ②形（本尊編輯器設計模式渲染 Ella cart-shipping-calculator 的實測，A′ 2026-09-04，zh-CN 店面）：首項
  #   `<option value="---" data-provinces="[]">---</option>`，其後 237 國；`value`＝英文國名（`'` 保留原字）、文字＝店面語言的在地名、
  #   `data-provinces`＝`[["英文","在地名"],…]` 經 HTML 屬性跳脫（`&quot;`／`&#39;`），順序＝在地名的碼位排序（Python `sorted` 同序實證）。
  # ③🔴 為什麼不用 ISO 3166：本尊集合對 ISO 少 21 碼（AQ／CU／IR／KP／SY／US 屬地…）、多 9 個非 ISO 項（Kosovo／Ascension／
  #   Tristan da Cunha／Aland Islands…）、23 個命名差、37 個有子區域的國家中 12 國省份數不同（HK 三區非 ISO）——鐵律 22 要的是
  #   與本尊一致，故字典＝`config/country_option_tags.json`（平台字典表：與租戶無關，由本尊渲染輸出整理；在地名目前只有 zh-CN，
  #   其他語言退英文名，登記 91 §3.81）。
  # ④跨功能：`Runtime` 全域 assigns 兩個鍵；`Storefront::CartController#estimate_rates` 接受國名或國碼（Ella 表單 POST 的是 value＝國名）；
  #   `Checkouts::RateResolver.sellable_countries` 仍是 `country_option_tags` 的值域來源（鐵律 7 與結帳頁同源）。
  module CountryOptionTags
    PATH = Rails.root.join("config", "country_option_tags.json")
    PLACEHOLDER = %(<option value="---" data-provinces="[]">---</option>)

    module_function

    # @return [Array<Hash>] 字典列（code／name／labels／provinces），檔案序＝英文名序
    def entries
      @entries ||= JSON.parse(File.read(PATH, encoding: "UTF-8")).freeze
    end

    # 本尊 `all_country_option_tags`：`---` ＋ 全部國家（依在地名碼位排序）。
    # @param locale [String, nil] 內部 locale tag（zh-Hans…）；nil／無在地名 ⇒ 英文名
    def all(locale: nil)
      PLACEHOLDER + render(entries, locale:)
    end

    # 本尊 `country_option_tags`：只列 `codes`（運送區域內國家）。
    def only(codes, locale: nil)
      wanted = Array(codes).map { |c| c.to_s.upcase }.to_set
      render(entries.select { |e| wanted.include?(e["code"]) }, locale:)
    end

    # 國名或國碼 ⇒ 大寫 ISO 碼（表單 `shipping_address[country]` 收兩形；不認得回 nil）。
    def code_for(name_or_code)
      s = name_or_code.to_s.strip
      return nil if s.empty?

      up = s.upcase
      return up if entries.any? { |e| e["code"] == up }

      entries.find { |e| e["name"].casecmp?(s) }&.fetch("code")
    end

    # 語言鍵＝本尊 storefront 語言碼（zh-CN／zh-TW／en／fr／ja；E14b 五語言皆為 hoko.vip 發布後的實測輸出）；字典沒有的語言退 en。
    FALLBACK_LANG = "en"

    def lang_key(locale)
      key = LocaleTags.shopify_code(locale) if locale.present?
      key.presence && entries.first["labels"].key?(key) ? key : FALLBACK_LANG
    end

    # 順序＝該語言在本尊輸出裡觀察到的順序（`sort[lang]`）——本尊用的是 ICU 類 collation（en 的 Åland 排在 A 後、
    # zh 依碼位），執行期不重算，直接複製觀察序。
    def render(list, locale:)
      key = lang_key(locale)
      list.sort_by { |e| e["sort"][key] }
          .map { |e| option_tag(e["name"], label(e, key), provinces_json(e, key)) }
          .join
    end

    # 字典不變式：每國、每子區域都有全部語言的在地名與 sort（產生器斷言）；語言退路只在 lang_key 一處。
    def label(entry, key)
      entry["labels"].fetch(key)
    end

    def provinces_json(entry, key)
      JSON.generate(entry["provinces"].map { |p| [ p["name"], p["labels"].fetch(key) ] })
    end

    # value／文字只跳脫 `& < > "`（本尊 `value="Côte d'Ivoire"` 保留 `'`）；data-provinces 的 JSON 走完整屬性跳脫（本尊 `&quot;`／`&#39;`）。
    def option_tag(name, lbl, json)
      %(<option value="#{attr(name)}" data-provinces="#{ERB::Util.html_escape(json)}">#{attr(lbl)}</option>)
    end

    def attr(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end
    private_class_method :render, :label, :provinces_json, :option_tag, :attr
  end
end
