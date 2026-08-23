# frozen_string_literal: true

module Catalog
  # URL handle 生成器——`config/limits.yml` `handle:` 區塊的可執行形。
  #
  # 🔴 每一步的順序與規則都對應 limits 的一個鍵（值不硬編、規則出處在該區塊
  # 逐鍵註釋；使用者 2026-08-12 裁定 ASCII-only，**明知偏離本尊**的 CJK 保留）。
  # 管線：NFKC → 小寫 → 刪撇號類 → 查表轉寫 → 摺疊變音 → 標點轉分隔 →
  # 壓縮/修剪分隔 → 品質閘門 → （不過）確定性 fallback。
  #
  # 🔴 **這不是 Liquid 的 handleize filter**（`handle.liquid_filter_shares_implementation:
  # false`）：filter 對非 ASCII 是保留（本尊行為，68 §F-3），URL 生成是 ASCII-only
  # （裁定）。兩個值域天生不同，不得共用實作。
  #
  # @see config/limits.yml handle 區塊（規則唯一出處）
  # @see docs/specs/67-multilingual.md §D
  class HandleGenerator
    Result = Data.define(:handle, :letters_dropped) do
      # @return [Boolean] 有任何字母被丟棄（`flag_when_letters_dropped`——不得靜默）
      def flagged? = letters_dropped
    end

    class << self
      # 從標題生成 handle（不含唯一化——衝突尾碼由呼叫端在 DB 附近處理）。
      #
      # @param title [String] 來源標題（`source_field_priority` 的 base_title 步；
      #   en_title 步待多語言表落地，見 docs/dev/m1-product-set-foundation.md）
      # @param resource [String] fallback 用的資源名（如 "product"）
      # @return [Result] handle 與「有字母被丟棄」旗標
      # @note 副作用：fallback 使用 SecureRandom（per-shop 隨機、不用流水號）。
      def call(title, resource: "product")
        cleaned = pipeline(title.to_s)
        return Result.new(handle: fallback(resource), letters_dropped: true) unless quality_ok?(title.to_s, cleaned)

        Result.new(handle: cleaned, letters_dropped: letters_dropped?(title.to_s, cleaned))
      end

      private

      def rules = Limits.fetch(:handle)

      def pipeline(raw)
        s = raw.unicode_normalize(:nfkc)           # nfkc_normalize：全形→半形
        s = s.downcase                              # lowercase
        rules.fetch(:delete_chars).each { |ch| s = s.delete(ch) } # 撇號類刪除：Bob's→bobs
        rules.fetch(:transliterate_table).each { |from, to| s = s.gsub(from.to_s, to.to_s) } # ß→ss（NFKD 不分解）
        # fold_diacritics：NFKD 後去 combining marks（Kérastase→kerastase）
        s = s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "")
        # punctuation_to_separator＋decimal_point_to_separator：其餘非 [a-z0-9] 一律轉分隔，
        # **不是刪除**——刪掉小數點會把 125ml/4.2oz 改寫成 42oz（HDL-3，規格數字被改寫）。
        s = s.gsub(/[^a-z0-9]+/, "-")
        s = s.gsub(/-{2,}/, "-")                    # collapse_separators
        s = s.delete_prefix("-").delete_suffix("-") # trim_separators
        truncate_on_boundary(s, rules.fetch(:max_chars))
      end

      # 截斷必須落在分隔符邊界（不得切出半個詞）。
      def truncate_on_boundary(s, max)
        return s if s.length <= max

        cut = s[0, max]
        boundary = cut.rindex("-")
        boundary ? cut[0, boundary] : cut
      end

      # 品質閘門：拉丁字母數下限＋字母丟棄比例上限。
      # 「殘渣 slug」比自動代碼更糟（棉質短T → "t" 幾乎必然碰撞且無語義）。
      def quality_ok?(raw, cleaned)
        return false if cleaned.empty?

        latin = cleaned.count("a-z")
        return false if latin < rules.fetch(:min_latin_alpha_chars)

        source_letters = raw.scan(/\p{L}/).length
        return true if source_letters.zero?

        dropped_ratio = 1.0 - (latin.to_f / source_letters)
        dropped_ratio <= rules.fetch(:max_dropped_letter_ratio)
      end

      def letters_dropped?(raw, cleaned)
        raw.scan(/\p{L}/).length > cleaned.count("a-z")
      end

      # deterministic_fallback：`{resource}-{token8}`，Crockford base32。
      # 不用流水號——那會洩漏商品數與建立順序。
      def fallback(resource)
        alphabet = "0123456789abcdefghjkmnpqrstvwxyz" # Crockford（去 i l o u）
        token = Array.new(8) { alphabet[SecureRandom.random_number(alphabet.length)] }.join
        rules.fetch(:fallback_pattern).sub("{resource}", resource).sub("{token8}", token)
      end
    end
  end
end
