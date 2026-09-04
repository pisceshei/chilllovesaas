# frozen_string_literal: true

module UrlRedirects
  # 重導路徑正規化與驗證（包 36；create／update 共用單一實作）。
  #
  # 🔴 **DOC-5 裁定（本包）**：manual 列與 handle_change 列**統一存無前綴正規形**——
  #   引擎剝前綴查表＋301 保留前綴，一列覆蓋全部語言；帶前綴輸入一律拒絕
  #   （PREFIXED_PATH_FORBIDDEN）。62 §B.5「帶前綴＝該 presence 內重導」的
  #   per-presence 形態**不採**：它讓同一改名要逐語言維護 N 列，且與 handle_change
  #   producer 的正規形不變量互相打架；真需求出現時另立欄位明示 presence，不用
  #   路徑前綴暗示（登記）。
  module Normalize
    Result = Data.define(:path, :target, :error) # error: [field, message, code] or nil

    module_function

    def call(path:, target:)
      normalized_path = normalize(path)
      normalized_target = normalize(target)

      if normalized_path.nil?
        return error("path", "路徑必須以 / 開頭且不含空白。", "INVALID")
      end
      if normalized_target.nil?
        return error("target", "目標必須以 / 開頭且不含空白。", "INVALID")
      end
      if prefixed?(normalized_path)
        return error("path", "路徑不得帶 locale 前綴（各語言由路由層自動保留）。", "PREFIXED_PATH_FORBIDDEN")
      end
      if prefixed?(normalized_target)
        return error("target", "目標不得帶 locale 前綴（各語言由路由層自動保留）。", "PREFIXED_PATH_FORBIDDEN")
      end
      if normalized_path == normalized_target
        return error("target", "來源與目標不得相同。", "SELF_REDIRECT")
      end

      Result.new(path: normalized_path, target: normalized_target, error: nil)
    end

    def normalize(raw)
      value = raw.to_s.strip
      value = "/#{value}" unless value.start_with?("/")
      return nil if value.match?(/[[:space:][:cntrl:]]/) || value == "/"

      value
    end

    # D80：「帶前綴」＝第一段是本店**實際存在**的前綴（presence × 白名單列），不是「像前綴」——
    # 預設語言無前綴、/faq 這種兩三字母段是合法路徑。租戶脈絡缺失（無 tenant）⇒ 形狀粗篩（fail-closed 偏拒絕）。
    def prefixed?(path)
      first = path.delete_prefix("/").split("/", 2)[0].to_s.downcase
      return false unless first.match?(/\A#{Markets::UrlPrefix::SEGMENT.source}\z/)

      shop = ActsAsTenant.current_tenant
      return true if shop.nil?

      Markets::PrefixIndex.prefix_segments(shop:).include?(first)
    end

    def error(field, message, code)
      Result.new(path: nil, target: nil, error: [ field, message, code ])
    end
  end
end
