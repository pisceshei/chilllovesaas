# frozen_string_literal: true

require "csv"

module Translations
  # 翻譯 CSV 匯入（docs/specs/67 §E.6(a)(b)；ML-5b）。
  #
  # 🔴 **四種「不變更」的表達**（§E.6(a) 核心契約，四種都必須各自成立）：
  # ```
  # 列缺席                 ⇒ 該 (resource, locale, field) 完全不處理
  # 欄位缺席（表頭沒有）   ⇒ 該欄位對檔案內所有列都不處理
  # 儲存格空白             ⇒ 本列本欄不做任何事（🔴 **不是**刪除，69 §V-182）
  # 有值 ∧ 未勾 overwrite  ⇒ 該譯文已存在時保持原值（只補新的）
  # ```
  # 🔴 清空譯文的**唯一**手段＝寫 `__CLEAR__`（`i18n.import.explicit_clear_token`）。
  # 為什麼不用空白表達刪除：譯者交回只填 20% 的檔案是**常態**，用易誤觸的狀態觸發不可逆操作
  # 等於把資料毀損做成預設路徑。本尊也不這麼做——它用一個顯式勾選框問使用者。
  #
  # 🔴 **缺席與空白必須在解析層就分開**（`absent_vs_blank_distinguished_by_header`）：
  # 多數 CSV 函式庫把兩者都塌成 nil；而 `overwrite_existing` 的作用範圍正是靠表頭界定
  # （`overwrite_scope: non_blank_cells_in_present_columns`）——分不出來的話，
  # 一份只想改標題的檔案會把描述一起洗掉。
  class CsvImport
    CLEAR_TOKEN = "__CLEAR__"

    Row = Data.define(:line, :resource_type, :resource_id, :locale, :field, :value, :source_digest, :market_handle)
    Outcome = Data.define(:created, :updated, :cleared, :skipped, :digest_mismatch, :errors, :applied)

    class << self
      # @param shop [Shop]
      # @param csv_text [String]
      # @param overwrite_existing [Boolean] 覆寫既有譯文（預設 false＝只補新的）
      # @param dry_run [Boolean] 預覽：算出各類計數但不寫入（`preview_required`）
      # @return [Outcome]
      def call(shop:, csv_text:, overwrite_existing: false, dry_run: true)
        table = CSV.parse(csv_text, headers: true)
        headers = table.headers.compact.map(&:to_s)

        # 🔴 缺 source_digest 欄 ⇒ **整檔拒絕**：沒有它就無法判斷譯者照的是哪一版原文，
        #    寫進去等於把「可能過期」的譯文靜默當成最新（§E.6(b)）。
        unless headers.include?("source_digest")
          return Outcome.new(created: 0, updated: 0, cleared: 0, skipped: 0, digest_mismatch: 0,
                             errors: [ { line: 0, message: I18n.t("errors.translation_csv.missing_digest_column"), code: "INVALID" } ],
                             applied: false)
        end
        # 欄位缺席＝該欄對全檔不處理；translated_text 缺席就沒有任何可寫的東西。
        unless headers.include?("translated_text")
          return Outcome.new(created: 0, updated: 0, cleared: 0, skipped: 0, digest_mismatch: 0,
                             errors: [ { line: 0, message: I18n.t("errors.translation_csv.missing_value_column"), code: "INVALID" } ],
                             applied: false)
        end

        enabled = Locales::Registry.enabled_tags(shop)
        source_locale = Locales::Registry.source_tag(shop)
        counters = { created: 0, updated: 0, cleared: 0, skipped: 0, digest_mismatch: 0 }
        errors = []

        ActsAsTenant.with_tenant(shop) do
          table.each_with_index do |csv_row, index|
            line = index + 2 # 表頭佔第 1 行
            row = parse_row(csv_row, line)
            error = validate(row, enabled, source_locale)
            if error
              errors << error
              next
            end

            # 🔴 儲存格空白＝本列不做任何事（不是刪除）。
            if row.value.nil? || row.value.strip.empty?
              counters[:skipped] += 1
              next
            end

            apply_row(shop, row, counters, overwrite_existing:, dry_run:)
          end
        end

        Outcome.new(**counters, errors:, applied: !dry_run && errors.empty?)
      end

      private

      def parse_row(csv_row, line)
        gid = csv_row["resource_gid"].to_s
        Row.new(
          line:,
          resource_type: csv_row["resource_type"].to_s.upcase.presence,
          resource_id: gid[%r{/(\d+)\z}, 1]&.to_i,
          locale: Locales::Tag.normalize(csv_row["locale"].to_s),
          field: csv_row["field_key"].to_s,
          # 🔴 只有「表頭有這一欄」時值才有意義；欄位缺席時 CSV::Row 回 nil，
          #    與「有欄位但儲存格空白」在這裡都走 skip 分支（兩者結果相同、理由不同）。
          value: csv_row["translated_text"],
          source_digest: csv_row["source_digest"].to_s,
          market_handle: csv_row["market_handle"]
        )
      end

      def validate(row, enabled, source_locale)
        return error(row.line, "resource_gid", "INVALID") if row.resource_id.nil?
        return error(row.line, "resource_type", "INVALID") unless Translation::RESOURCE_TYPES.include?(row.resource_type)
        return error(row.line, "field_key", "INVALID") unless Upsert::FIELDS.include?(row.field)
        return error(row.line, "locale_not_enabled", "LOCALE_NOT_ENABLED") unless enabled.include?(row.locale)
        return error(row.line, "source_locale", "INVALID") if row.locale == source_locale
        # 🔴 market_handle 非空＝拒絕該列並明示理由（裁定 10：不做市場級內容覆寫）。
        return error(row.line, "market_not_supported", "INVALID") if row.market_handle.present?

        nil
      end

      def error(line, key, code)
        { line:, message: I18n.t("errors.translation_csv.#{key}", default: I18n.t("errors.translation_csv.invalid_row")), code: }
      end

      def apply_row(shop, row, counters, overwrite_existing:, dry_run:)
        record = Translation.find_by(
          shop_id: shop.id, resource_type: row.resource_type, resource_id: row.resource_id,
          locale_tag: row.locale, field_key: row.field
        )
        clearing = row.value.strip == CLEAR_TOKEN

        if clearing
          # `__CLEAR__` 是唯一清空手段；沒有既有譯文就沒事可做。
          if record.nil?
            counters[:skipped] += 1
            return
          end
          counters[:cleared] += 1
          # 🔴 清空寫稽核軌（clear_writes_audit_trail）：誰、何時、哪一次匯入、舊值是什麼——
          #    沒有它，「譯者交錯檔案」事後完全無法還原。
          unless dry_run
            log_audit(shop, row, previous: record.value, action: "clear")
            record.destroy!
          end
          return
        end

        # 🔴 有值但已存在且未勾 overwrite ⇒ 保持原值（只補新的）。
        if record && !overwrite_existing
          counters[:skipped] += 1
          return
        end

        source_text = source_text_for(row)
        mismatch = row.source_digest.present? && row.source_digest != Translation.digest_for(source_text)
        counters[:digest_mismatch] += 1 if mismatch
        record ? counters[:updated] += 1 : counters[:created] += 1
        return if dry_run

        log_audit(shop, row, previous: record&.value, action: record ? "overwrite" : "create") if record
        write_row(shop, row, source_text, mismatch)
      end

      def source_text_for(row)
        resource = row.resource_type == "COLLECTION" ? Collection.find_by(id: row.resource_id) : Product.find_by(id: row.resource_id)
        return "" unless resource

        case row.field
        when "title" then resource.title
        when "body_html" then resource.description_html
        when "meta_title" then resource.seo_title
        else resource.seo_description
        end.to_s
      end

      # 🔴 digest 不符仍然**寫入**（譯者是照當時原文翻的，內容多半可用），
      #    但標 outdated＋review_required，並在報告單列出——**不得靜默當成最新**（§E.6(b)）。
      def write_row(shop, row, source_text, mismatch)
        record = Translation.find_or_initialize_by(
          shop_id: shop.id, resource_type: row.resource_type, resource_id: row.resource_id,
          locale_tag: row.locale, field_key: row.field
        )
        record.assign_attributes(
          value: row.value,
          source_locale_tag: Locales::Registry.source_tag(shop),
          source_digest: Translation.digest_for(source_text),
          value_source: "import",
          review_required: mismatch,
          outdated: mismatch,
          outdated_severity: mismatch ? "major" : "none"
        )
        # 逐行獨立 transaction（`per_row_transaction`，沿用 13 §F6.1 形態）：
        # 一列壞掉不該讓整份檔案回滾，報告單逐行列出結果。
        ActiveRecord::Base.transaction(requires_new: true) { record.save! }
      end

      # 稽核軌以結構化日誌承載（專用資料表屬後續包；`clear/overwrite_writes_audit_trail` 的最小實作）。
      def log_audit(shop, row, previous:, action:)
        Rails.logger.info(
          {
            event: "translation_csv_#{action}",
            shop_id: shop.id, resource_type: row.resource_type, resource_id: row.resource_id,
            locale: row.locale, field: row.field, previous_value: previous, line: row.line
          }.to_json
        )
      end
    end
  end
end
