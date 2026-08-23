# frozen_string_literal: true

module Locales
  # BCP-47 語言標籤的正規化與驗證（docs/specs/67 §C.1 規則 2／3；limits `i18n.*`）。
  #
  # 形態：`iso639_1[-iso15924][-iso3166_1_alpha2]`——語言小寫、script Title case、region 大寫。
  # 🔴 不得依賴 MySQL collation 做大小寫正規化（67 §C.1 規則 3）：API 回傳與 URL 前綴都需要確定字面值。
  # 🔴 禁裸 `zh`（字體歧義）、禁 `EU`/`UK`/`es-419` 等非標準聚合碼（`i18n.forbidden_locale_tags`）。
  #
  # 命名用 `Locales` 而非 `I18n`：後者是 Rails 內建模組，撞名會靜默覆蓋其方法。
  module Tag
    FORMAT = /\A(?<language>[a-z]{2,3})(?:-(?<script>[A-Z][a-z]{3}))?(?:-(?<region>[A-Z]{2}))?\z/

    class Invalid < StandardError; end

    module_function

    # 正規化大小寫（寫入層強制）。不驗證語義；驗證交給 `validate!`。
    #
    # @param raw [String, nil]
    # @return [String] 例：`zh-hant` → `zh-Hant`、`EN-gb` → `en-GB`
    def normalize(raw)
      parts = raw.to_s.strip.split("-")
      return "" if parts.empty?

      parts.each_with_index.map do |part, index|
        next part.downcase if index.zero?
        part.length == 4 ? part.capitalize : part.upcase
      end.join("-")
    end

    # 正規化後驗證；失敗拋 Invalid（GraphQL 層轉 `LOCALE_TAG_INVALID`）。
    #
    # @param raw [String]
    # @return [String] 正規化後的標籤
    # @raise [Invalid] 格式不符、禁用標籤、或 zh 缺 script subtag
    def validate!(raw)
      tag = normalize(raw)
      match = FORMAT.match(tag)
      raise Invalid, "語言標籤格式不符：#{raw.inspect}" unless match

      # 禁用表比對不分大小寫：`EU`／`UK` 是偽地區碼，正規化後會變成合法長相的 `eu`／`uk`
      # （`eu` 甚至撞巴斯克語 639-1）——limits 的意圖是整個標籤禁用，照字面比就漏了。
      forbidden = Limits.fetch(:i18n, :forbidden_locale_tags).map { |value| value.to_s.downcase }
      if forbidden.include?(tag.downcase) || forbidden.include?(match[:region].to_s.downcase)
        raise Invalid, "禁用的語言標籤：#{tag}"
      end

      needs_script = Limits.fetch(:i18n, :script_subtag_required_for).map(&:to_s)
      if needs_script.include?(match[:language]) && match[:script].nil?
        raise Invalid, "#{match[:language]} 必須帶 script subtag（zh-Hant / zh-Hans），不得用裸語言碼或地區碼"
      end

      tag
    end

    # @return [Boolean]
    def valid?(raw)
      validate!(raw)
      true
    rescue Invalid
      false
    end
  end
end
