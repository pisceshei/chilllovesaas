# frozen_string_literal: true

module Translations
  # 繁簡字形誤借偵測（第 7 包 `script_mismatch` 稽核規則的判別核心；D49 裁定引入）。
  #
  # ①這是什麼：純函式。給一段文字與期望字形（`:hant`／`:hans`），回傳「用錯字形的字」
  #   的清單。資料來源＝OpenCC 的兩張字元表（`lib/opencc/`，Apache-2.0，NOTICE 同目錄；
  #   採用登記＝`docs/specs/107-external-adoption-register.md` OpenCC-1）。
  #
  # ②具體功能（判準的推導，2026-08-25 對表實測）：
  #   - `STCharacters.txt`＝簡→繁映射（4012 鍵）；`TSCharacters.txt`＝繁→簡（4148 鍵）。
  #   - **簡體專用字**＝ST 的鍵中「自己不在自己的映射值裡」者（汉→漢 ⇒ 汉 是簡體專用；
  #     台→臺/檯/颱/**台** ⇒ 台 含自映射 ⇒ 兩體共用，**不判**）。繁體專用字同構自 TS。
  #   - 實測錨：汉／门／发＝簡專；漢／門／發＝繁專；的／人／大／台／后／里／干＝共用。
  #   - 🔴 五個字（緼苧藴輼醖）在兩表**都**判專用＝上游資料自相矛盾 ⇒ 一律剔除
  #     （fail-safe：矛盾字當共用，寧漏報不誤報——誤報會讓商家對整個稽核失去信任）。
  #   - 期望 `:hant` 的文字裡出現簡體專用字 ⇒ 誤借；`:hans` 反之。共用字永不觸發。
  #
  # ③已知邊界（誠實登記，不得讀成完整方案）：
  #   - **字元級**判別，不做詞彙級（软件 vs 軟體 那類「兩邊都是合法字、用詞不同」
  #     不在射程——那是 `machine_translation`／`script_conversion` 的在地化問題，
  #     不是字形錯誤）。
  #   - 只適用 zh-*：日文漢字也是 Han 字元，拿日文文字來判會滿屏誤報 ⇒ 呼叫端
  #     （`Translations::Audit`）只對 `zh-Hant*`／`zh-Hans*` locale 呼叫。
  #   - 覆蓋率＝OpenCC 字元表的覆蓋率（P7 研究輪的 U15 疑慮是**詞庫** TWPhrases 的
  #     電商詞覆蓋，與本字元表無關；字元表是 Unicode Han 常用字全集級）。
  #
  # ④跨功能影響：唯一消費者＝`Translations::Audit#inspect_row`（僅登記、不自動修——
  #   簡→繁一對多（发→發/髮），自動改字是 `script_conversion`（ML-5）的事且必須
  #   `review_required`；稽核擅自改字＝把歧義寫死）。
  module ScriptDetector
    DATA_DIR = "lib/opencc"

    class << self
      # @param text [String]
      # @param expected [Symbol] `:hant`（期望繁體）或 `:hans`（期望簡體）
      # @return [Array<String>] 用錯字形的字（去重、依出現序）；空陣列＝無誤借
      # @raise [ArgumentError] expected 不是兩值之一（fail-closed，不猜方向）
      def mismatched_chars(text, expected:)
        wrong_set =
          case expected
          when :hant then simplified_only
          when :hans then traditional_only
          else raise ArgumentError, "expected 只有 :hant / :hans（收到 #{expected.inspect}）"
          end
        text.to_s.each_char.select { |char| wrong_set.include?(char) }.uniq
      end

      # locale tag → 期望字形；非 zh-Hant*/zh-Hans* 回 nil（呼叫端據此跳過）。
      # 🔴 用**子標籤邊界**比對（zh-Hant 與 zh-Hant-HK 都算；假想的 zh-Hantx 不算）。
      def expected_for(locale_tag)
        tag = locale_tag.to_s
        return :hant if tag == "zh-Hant" || tag.start_with?("zh-Hant-")
        return :hans if tag == "zh-Hans" || tag.start_with?("zh-Hans-")

        nil
      end

      # 表載入一次、程序級快取（凍結 Set；資料隨版本部署，不會執行期變動）。
      def simplified_only
        @simplified_only ||= begin
          simp = exclusive_keys("STCharacters.txt")
          trad = exclusive_keys("TSCharacters.txt")
          (simp - trad).freeze   # 剔除五個雙邊矛盾字（見檔頭②）
        end
      end

      def traditional_only
        @traditional_only ||= begin
          simp = exclusive_keys("STCharacters.txt")
          trad = exclusive_keys("TSCharacters.txt")
          (trad - simp).freeze
        end
      end

      private

      # 「自己不在自己的映射值裡」的鍵集合。
      def exclusive_keys(file)
        path = Rails.root.join(DATA_DIR, file)
        result = Set.new
        File.foreach(path, encoding: "UTF-8") do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          key, values = line.split("\t", 2)
          next if key.nil? || values.nil?

          result << key unless values.split(" ").include?(key)
        end
        # 🔴 零列 canary：表讀出來是空的（路徑錯／檔案被清）必須炸，不得靜默變成
        #   「掃了但零命中」——那正是本規則先前用「明文棄權」防的那種假乾淨。
        raise "OpenCC 字表 #{file} 讀出 0 個專用字——資料檔缺失或格式變了" if result.empty?

        result
      end
    end
  end
end
