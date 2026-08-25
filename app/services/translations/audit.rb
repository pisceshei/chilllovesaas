# frozen_string_literal: true

module Translations
  # 既有譯文的稽核（第 7 包；`docs/plans/2026-08-24-三方向執行順序.md` 第 7 列）。
  #
  # ①這是什麼：唯讀掃描 + 可選修復，對象是**在本包的判準立起來之前**就已落庫的譯文列。
  #   譯文寫入端 2026-08-23 就上線並持續累積，所以「規則之前的資料」不是假想情境。
  #
  # ②具體功能（完整規則值域，四條）：
  #   | rule                | 判準 | 為什麼是問題 | `--fix` 動作 |
  #   |---------------------|------|--------------|--------------|
  #   | `blank_value`       | `BlankValue.blank?` 為真的列 | 後台顯示「已翻譯」、前台落 fallback ⇒ 兩個真相（鐵律 7） | 刪列 |
  #   | `unsanitized_html`  | `body_html` 的值 ≠ 白名單 sanitize 後的值 | 儲存型 XSS：本包之前 `Upsert` 對譯文完全不 sanitize（base 有） | 覆寫成 sanitize 後的值 |
  #   | `orphan_locale`     | `locale_tag` 不在該店 `shop_locales` | 語言被刪後遺留；匯出／進度分母會少算 | **不動**（僅登記） |
  #   | `source_locale_row` | `locale_tag == source_locale` | 來源語言的文字在 base row，這列是重複真相 | **不動**（僅登記） |
  #
  #   🔴 **`script_mismatch`（繁簡誤借）本輪一律「棄權」，不是「零筆」**：可靠的判別需要
  #   繁簡字表，而唯一成熟的公開字表（OpenCC 的 `STCharacters.txt`／`TSCharacters.txt`）是
  #   **Apache-2.0**——依鐵律 9，Apache-2.0「可用但有專利授權與 NOTICE 保留義務，混入前
  #   法務面要知情」⇒ 屬計畫外授權裁定，命中鐵律 17.3 的例外，**不在本包擅自做**。
  #   本規則因此以「棄權」形態存在：介面就位、報告明講「未執行」，
  #   **絕不回報 0 筆**（回報 0 筆等於宣稱掃過且乾淨，那是把未取得寫成事實，違反鐵律 19）。
  #   登記＝`docs/specs/91-pit-register.md` §2；取得字表後的實作見 dev doc「延後項」。
  #
  # ③怎麼做到 —— 三條 fail-open 防線（鐵律 20.2 第 5 項）：
  #   🔴 (a) **零掃描 canary**：`scanned` 恆回報實際掃過的列數。掃到 0 列時報告寫
  #      「掃描 0 列」而**不是**「乾淨」——「沒找到問題」與「沒去找」必須看得出差別。
  #   🔴 (b) **棄權必須顯式**：`abstained` 陣列列出沒跑的規則與原因；rake 任務印在最上面。
  #   🔴 (c) **`--fix` 只動 `blank_value` 與 `unsanitized_html`**，兩者都是「這列的值本來就
  #      不該長這樣」；`orphan_locale`／`source_locale_row` 牽涉商家意圖（可能是刻意保留的
  #      下架語言譯文），一律只登記不動——刪錯了不可逆。
  #
  # ④跨功能影響：
  #   - 唯一呼叫端＝`lib/tasks/translations.rake`（`rails translations:audit`）。
  #     🔴 **不放 `scripts/`**：那個目錄是 CI 閘門的所在地，放進去會讓本任務落入鐵律 18.3
  #     的人工合併清單，且它需要 Rails 環境（`scripts/` 的腳本一律不需要）。
  #   - `--fix` 刪列後 **`translation_status` 會失準** ⇒ 修復完必須重算，本服務自己做
  #     （與 `Upsert#recompute_status` 同一套分母口徑，鐵律 7）。
  #   - 修復是 tenant-scoped 的，一次一家店；不提供「全平台一次修」的入口
  #     （跨租戶批次寫入沒有任何一個呼叫端需要，而它是最容易寫錯 shop_id 的形態）。
  class Audit
    Finding = Data.define(:rule, :translation_id, :resource_type, :resource_id,
                          :locale_tag, :field_key, :detail)

    Report = Data.define(:shop_id, :scanned, :findings, :abstained, :fixed) do
      def findings_by_rule = findings.group_by(&:rule).transform_values(&:length)
      def clean? = findings.empty?
    end

    # 棄權的規則與逐字理由（見檔頭②的紅字段落）。
    ABSTAINED = [
      {
        rule: "script_mismatch",
        reason: "繁簡誤借偵測需要繁簡字表；唯一成熟公開字表（OpenCC）為 Apache-2.0，" \
                "依鐵律 9 屬混入前需法務知情的授權裁定 ⇒ 未取得裁定前不執行。" \
                "🔴 這是「未執行」不是「零筆」。"
      }
    ].freeze

    FIXABLE = %w[blank_value unsanitized_html].freeze

    class << self
      # @param shop [Shop]
      # @param fix [Boolean] true＝修復可修的兩條規則並重算 translation_status
      # @return [Report]
      # @note 副作用：`fix: true` 時刪除／覆寫 `translations` 列並重寫 `translation_status`。
      def call(shop:, fix: false)
        ActsAsTenant.with_tenant(shop) do
          enabled = Locales::Registry.enabled_tags(shop)
          source_locale = Locales::Registry.source_tag(shop)
          findings = []
          scanned = 0

          Translation.where(shop_id: shop.id).find_each do |record|
            scanned += 1
            findings.concat(inspect_row(record, enabled, source_locale))
          end

          fixed = fix ? apply_fixes!(shop, findings) : 0
          Report.new(shop_id: shop.id, scanned:, findings:, abstained: ABSTAINED, fixed:)
        end
      end

      private

      def inspect_row(record, enabled, source_locale)
        found = []
        kind = Fields.kind(record.field_key)

        if BlankValue.blank?(record.value, kind:)
          found << finding(record, "blank_value", "值在 BlankValue 判準下等於沒有翻譯（後台會顯示「已翻譯」）")
        elsif record.field_key == "body_html"
          # 🔴 `elsif`：已判空的列會被刪掉，不必再談它的 HTML 乾不乾淨（也避免同一列出兩筆）。
          clean = Catalog::SaveProduct.sanitize_description_for(record.value.to_s)
          found << finding(record, "unsanitized_html", "值含白名單外的標籤或屬性") if clean != record.value.to_s
        end

        found << finding(record, "orphan_locale", "locale_tag 不在 shop_locales") unless enabled.include?(record.locale_tag)
        found << finding(record, "source_locale_row", "來源語言的文字應在 base row") if record.locale_tag == source_locale
        found
      end

      def finding(record, rule, detail)
        Finding.new(rule:, translation_id: record.id, resource_type: record.resource_type,
                    resource_id: record.resource_id, locale_tag: record.locale_tag,
                    field_key: record.field_key, detail:)
      end

      # @return [Integer] 實際動到的列數
      def apply_fixes!(shop, findings)
        targets = findings.select { |f| FIXABLE.include?(f.rule) }
        return 0 if targets.empty?

        count = 0
        ActiveRecord::Base.transaction do
          targets.group_by(&:rule).each do |rule, group|
            ids = group.map(&:translation_id)
            count += rule == "blank_value" ? clear!(shop, ids) : sanitize!(shop, ids)
          end
          recompute_statuses!(shop, targets)
        end
        count
      end

      def clear!(shop, ids) = Translation.where(shop_id: shop.id, id: ids).delete_all

      def sanitize!(shop, ids)
        changed = 0
        Translation.where(shop_id: shop.id, id: ids).find_each do |record|
          record.update_columns(value: Catalog::SaveProduct.sanitize_description_for(record.value.to_s))
          changed += 1
        end
        changed
      end

      # 修復動到的 (resource, locale) 組合全部重算。
      # 🔴 呼叫 `Upsert.recompute_status` 而**不是**在這裡重寫一份同樣的算式——
      #   進度數字的分母只有一個來源（鐵律 7），兩份實作遲早會對同一批列給不同答案。
      def recompute_statuses!(shop, targets)
        targets.map { |f| [ f.resource_type, f.resource_id, f.locale_tag ] }.uniq.each do |type, id, tag|
          Upsert.recompute_status(shop:, resource_type: type, resource_id: id, locale_tag: tag)
        end
      end
    end
  end
end
