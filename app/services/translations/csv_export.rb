# frozen_string_literal: true

require "csv"

module Translations
  # 翻譯 CSV 匯出（docs/specs/67 §E.6(b)；ML-5b）。
  #
  # 🔴 **翻譯是第三套 CSV**（商品 CSV／庫存 CSV／翻譯 CSV 互不合併，§E.6 四條理由）：
  # 鍵不同（resource×locale×field vs handle）、範圍不同（頁面/選單/主題字串也要翻）、
  # 生命週期不同（檔案會出境給譯者再回來，所以需要 `source_digest`）、空白語義不同。
  #
  # 欄位順序對齊本尊 8 欄（`limits i18n.export.columns`）＋我方獨有的 `source_digest`：
  # 沒有 digest 就無法安全回匯（回匯時要知道譯者是照哪一版原文翻的）。
  class CsvExport
    HEADERS = %w[
      resource_type resource_gid field_key locale market_handle status source_text translated_text source_digest
    ].freeze

    # 匯出檔沒有譯文的欄位也要出列（否則譯者不知道有什麼要翻）。
    EXPORTABLE_FIELDS = Upsert::FIELDS

    Result = Data.define(:csv, :row_count, :filename)

    class << self
      # @param shop [Shop]
      # @param locales [Array<String>, nil] 只匯出這些語言；nil＝全部已啟用（不含來源語言）
      # @param fields [Array<String>, nil] 只匯出這些欄位；nil＝全部可翻欄位
      # @param resource_type [String] PRODUCT / COLLECTION
      # @return [Result]
      # @note 副作用：唯讀（tenant-scoped SELECT）。
      def call(shop:, locales: nil, fields: nil, resource_type: "PRODUCT")
        target_locales = resolve_locales(shop, locales)
        target_fields = (fields.presence || EXPORTABLE_FIELDS) & EXPORTABLE_FIELDS
        source_locale = Locales::Registry.source_tag(shop)

        rows = []
        ActsAsTenant.with_tenant(shop) do
          resources(resource_type).find_each do |resource|
            existing = Translation.where(resource_type:, resource_id: resource.id).index_by { |row| [ row.locale_tag, row.field_key ] }
            target_locales.each do |locale|
              target_fields.each do |field|
                source_text = source_value(resource, field)
                # 來源沒有內容的欄位不出列：給譯者一列空的原文只會製造噪音。
                next if source_text.blank?

                translation = existing[[ locale, field ]]
                rows << row_for(resource, resource_type, field, locale, source_text, translation)
              end
            end
          end
        end

        csv = CSV.generate do |output|
          output << HEADERS
          rows.each { |row| output << row }
        end
        Result.new(csv:, row_count: rows.length, filename: filename_for(resource_type, target_locales))
      end

      private

      # 匯出對象＝已啟用且非來源語言（來源語言的文字在 base row，不是譯文）。
      def resolve_locales(shop, requested)
        translatable = Locales::Registry.translatable_tags(shop)
        return translatable if requested.blank?

        requested.map { |tag| Locales::Tag.normalize(tag) } & translatable
      end

      def resources(resource_type)
        resource_type == "COLLECTION" ? Collection.all : Product.all
      end

      def source_value(resource, field)
        case field
        when "title" then resource.title
        when "body_html" then resource.description_html
        when "meta_title" then resource.seo_title
        else resource.seo_description
        end
      end

      def row_for(resource, resource_type, field, locale, source_text, translation)
        [
          resource_type,
          "gid://chilllove/#{resource_type.capitalize}/#{resource.id}",
          field,
          locale,
          # 🔴 market_handle 恆空白：本平台不做市場級內容覆寫（裁定 10）。
          #    欄位保留只為對齊本尊 8 欄，讓本尊的檔案能直接匯入而不必手工改欄。
          nil,
          status_for(translation),
          source_text,
          translation&.value,
          # digest 一律輸出**當前來源文字**的 digest：回匯時比對它就知道譯者看到的是哪一版。
          Translation.digest_for(source_text)
        ]
      end

      # status 三值對齊本尊（`limits i18n.export.status_values`）；**純輸出**，匯入時忽略（V-201）。
      def status_for(translation)
        return "untranslated" if translation.nil?

        translation.outdated ? "outdated" : "translated"
      end

      def filename_for(resource_type, locales)
        suffix = locales.length == 1 ? locales.first : "all-locales"
        "translations-#{resource_type.downcase}-#{suffix}.csv"
      end
    end
  end
end
