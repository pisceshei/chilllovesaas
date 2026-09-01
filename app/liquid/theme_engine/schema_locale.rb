# frozen_string_literal: true

module ThemeEngine
  # 步 16d：schema 內 `t:` 鍵解析（26 §4.6：editor 翻譯檔＝
  # `locales/*.default.schema.json`；storefront 的 locales/*.json 是另一層，
  # 不得混用）。生產實錘：Ella 40 個 preset 區段的 name 全是 `t:names.*`。
  #
  # 解析策略：取第一個 `*.default.schema.json`（預設語系；多語系挑選＝16e+
  # 射程，91 §3 登記）；缺檔或缺鍵**回傳原鍵**（fail-open 顯示原文，比
  # 本尊的 "Translation missing" 保守——editor 顯示層，不是資料層）。
  module SchemaLocale
    module_function

    # @return [Proc] value → 解析後字串（非 `t:` 開頭原樣通過）
    def resolver_for(source)
      dict = load_dictionary(source)
      lambda do |value|
        next_value = value.is_a?(String) && value.start_with?("t:") ? value : nil
        return value if next_value.nil?

        dig_path(dict, next_value.delete_prefix("t:")) || value
      end
    end

    def load_dictionary(source)
      rel = source.list.find { |path| path.match?(%r{\Alocales/[^/]+\.default\.schema\.json\z}) }
      return {} if rel.nil?

      raw = source.read(rel)
      raw ? Runtime.tolerant_json(raw) : {}
    rescue JSON::ParserError
      {}
    end

    def dig_path(dict, dotted)
      dotted.split(".").reduce(dict) do |node, part|
        node.is_a?(Hash) ? node[part] : nil
      end.then { |leaf| leaf.is_a?(String) ? leaf : nil }
    end
  end
end
