# frozen_string_literal: true

module ThemeEngine
  # 我方語言 tag ↔ 本尊 storefront 語言碼（渲染 1:1，2026-09-03）。
  #
  # ①這是什麼：兩套命名的橋。我方 `shop_locales.locale_tag` 依 limits `i18n.locale_tag_format`＋
  #   `script_subtag_required_for: [zh]` 恆帶 script（`zh-Hans`／`zh-Hant`；裁定 2026-08-13，繁簡永不互為 fallback）；
  #   本尊 storefront 對中文用 language-region 碼——官方 locale 檔命名規則逐字（storefront-locale-files，取證
  #   2026-09-03）："Locale file naming must follow the standard IETF language tag nomenclature, where the first
  #   lowercase letter code represents the language, and the second uppercase letter code represents the region."；
  #   真店 hoko.vip（簡體中文店）輸出 `<html lang="zh-CN">`／`Shopify.locale = "zh-CN"`，Ella 主題檔為
  #   `locales/zh-CN.json`／`zh-TW.json`（無 zh-Hans／zh-Hant 檔）。
  # ②怎麼做：**內部 tag 不變**（DB、路由前綴、hreflang 各走既有規則）；只在「主題 locale 檔查找」與「輸出給主題／
  #   買家的語言碼」兩處換成本尊碼，語言切換表單送回本尊碼時再反查回我方 tag。
  # ③跨功能：`Runtime#build_locale_dict`（檔案候選）、`RequestDrop`（`request.locale.iso_code` ⇒ `<html lang>`）、
  #   `ShopifyGlobal.script`（`Shopify.locale`）、`Storefront::LocalizationContext`（`localization.language.iso_code`
  #   與 `available_languages`）、`Storefront::LocalizationController`（表單 `locale_code` 反查）。
  #   zh-Hant→zh-TW 由同一命名規則推得（hoko.vip 為簡體店，繁體形未實測；登記 V）。
  module LocaleTags
    SHOPIFY_CODES = { "zh-Hans" => "zh-CN", "zh-Hant" => "zh-TW" }.freeze
    PLATFORM_TAGS = SHOPIFY_CODES.invert.freeze

    module_function

    # @param tag [String, nil] 我方 tag
    # @return [String] 本尊 storefront 語言碼（無對映 ⇒ 原 tag）
    def shopify_code(tag) = SHOPIFY_CODES.fetch(tag.to_s, tag.to_s)

    # @param code [String, nil] 本尊碼或我方 tag
    # @return [String] 我方 tag
    def platform_tag(code) = PLATFORM_TAGS.fetch(code.to_s, code.to_s)

    # 主題 `locales/{name}.json` 的候選檔名：精確 tag 之後再試本尊碼（後者存在時覆蓋前者——同一語言只該有一份）。
    # @return [Array<String>]
    def theme_file_names(name) = [ name.to_s, SHOPIFY_CODES[name.to_s] ].compact.uniq
  end
end
