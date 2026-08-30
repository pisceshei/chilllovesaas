# frozen_string_literal: true

module Storefront
  # 平台字串集載入器（B14；67 §F.3(a) 三層解析的第 ③ 層）。
  #
  # 來源＝`config/storefront_locales/*.yml`（平台字典：跨租戶共用、隨版本部署）。
  # 回傳巢狀 Hash（`t` filter 的字典形）；未知 locale ⇒ 截尾鏈 ⇒ en。
  # process 級 memoize：檔案隨部署不可變，與 Runtime AST cache 同一假設。
  module PlatformStrings
    CACHE = {}
    MUTEX = Mutex.new
    DEFAULT = "en"

    module_function

    # @param locale_tag [String]
    # @return [Hash] 深併結果（en 兜底 ← 截尾鏈 ← 精確 locale；後者勝）
    def dict(locale_tag)
      tag = locale_tag.to_s.presence || DEFAULT
      MUTEX.synchronize do
        CACHE[tag] ||= chain(tag).reverse.reduce({}) { |acc, name| deep_merge(acc, load_file(name)) }
      end
    end

    # 截尾鏈（精確 → 去 region；🔴 zh 系不落裸 zh——繁簡永不互為 fallback，
    # limits `i18n.script_subtag_required_for`）＋ en 終端兜底。
    def chain(tag)
      parts = tag.split("-")
      candidates = []
      while parts.any?
        candidates << parts.join("-")
        parts = parts[0..-2]
        break if parts.length == 1 && Limits.fetch(:i18n, :script_subtag_required_for).map(&:to_s).include?(parts[0])
      end
      candidates << DEFAULT unless candidates.include?(DEFAULT)
      candidates
    end

    def load_file(name)
      path = Rails.root.join("config/storefront_locales/#{name}.yml")
      return {} unless File.file?(path)

      YAML.safe_load_file(path) || {}
    end

    def deep_merge(base, over)
      base.merge(over) do |_k, a, b|
        a.is_a?(Hash) && b.is_a?(Hash) ? deep_merge(a, b) : b
      end
    end
  end
end
