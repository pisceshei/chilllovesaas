# frozen_string_literal: true

# 內容翻譯的寫入層（docs/specs/67 §C.2／C.5／C.6；ML-2）。
module Translations
  # 宣告式寫入某資源的一批譯文，並在**同一 transaction** 內：
  #   ① 寫／刪 `translations` 列（空字串＝刪除該譯文列，回落來源語言）
  #   ② 以來源文字重算 `source_digest`
  #   ③ 依 digest 比對標記 `outdated`（來源文字改了 ⇒ 既有譯文過期）
  #   ④ 重算 `translation_status`（鐵律 7：進度數字只有這一個來源）
  #
  # 🔴 呼叫端必須已在商品／系列的 transaction 內（productSet 的全樹寫入）：
  # 譯文與 base row 分兩次 commit 會產生「base 已改、digest 還是舊的」的窗口，
  # 那正是 §C.5 過期偵測要防的東西。
  class Upsert
    # v1 射程：PRODUCT／COLLECTION × 四欄（67 §B.2 必翻＋可選）。
    #
    # 🔴 這兩個常數的語義是**翻譯進度的分子與分母**（`translation_status`），
    #   與 `Translations::Fields::MISSING`（缺翻譯時前台怎麼辦）**不是同一件事**，
    #   只是 v1 射程小而目前值相同。`spec/services/translations/fields_spec.rb` 有一格
    #   tripwire 盯著這個巧合；它紅掉時要裁定哪一邊該變，不是把值改回一致。
    REQUIRED_FIELDS = %w[title body_html].freeze
    OPTIONAL_FIELDS = %w[meta_title meta_description].freeze
    FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze

    Result = Data.define(:user_errors)

    class << self
      # @param shop [Shop]
      # @param resource_type [String] PRODUCT / COLLECTION
      # @param resource_id [Integer]
      # @param source_locale [String] 來源語言標籤（base row 的語言）
      # @param source_values [Hash{String=>String}] 來源文字（field_key => 值），用來算 digest
      # @param translations [Array<Hash>] `{ locale:, field:, value: }`；缺席＝不動、空字串＝刪除
      # @return [Result] user_errors（欄位路徑對齊 28 §0.3：`translations.<locale>.<field>`）
      # @note 副作用：寫 translations／translation_status；**必須在呼叫端的 transaction 內**。
      def call(shop:, resource_type:, resource_id:, source_locale:, source_values:, translations:)
        errors = []
        entries = normalize(shop, translations, source_locale, errors)
        return Result.new(user_errors: errors) if errors.any?

        entries.each { |entry| apply(shop, resource_type, resource_id, source_locale, source_values, entry) }
        refresh_outdated(shop, resource_type, resource_id, source_values)
        Locales::Registry.enabled_tags(shop).each do |tag|
          next if tag == source_locale

          recompute_status(shop:, resource_type:, resource_id:, locale_tag: tag)
        end
        Result.new(user_errors: [])
      end

      # 進度物化（67 §C.6）：required＝必翻欄位數；translated＝有值的必翻欄位數。
      #
      # 🔴 **公開的理由**：`Translations::Audit` 的 `--fix` 刪／改列之後也必須重算，
      #   而進度數字依鐵律 7 只准有一個來源。把算式複製第二份到 Audit 是最典型的
      #   「生產者已改、消費者未同步」根因（鐵律 20.2 第 2 類）。
      #
      # @return [TranslationStatus]
      # @note 副作用：upsert 一列 `translation_status`。
      def recompute_status(shop:, resource_type:, resource_id:, locale_tag:)
        rows = Translation.where(shop_id: shop.id, resource_type:, resource_id:, locale_tag:).to_a
        translated = rows.count { |row| REQUIRED_FIELDS.include?(row.field_key) }
        status = TranslationStatus.find_or_initialize_by(
          shop_id: shop.id, resource_type:, resource_id:, locale_tag:
        )
        status.assign_attributes(
          required_fields: REQUIRED_FIELDS.length,
          translated_fields: translated,
          outdated_count: rows.count(&:outdated),
          review_pending: rows.count(&:review_required)
        )
        status.save!
        status
      end

      private

      # 驗證與正規化；錯誤一次收齊（不是遇到第一個就回）。
      def normalize(shop, translations, source_locale, errors)
        enabled = Locales::Registry.enabled_tags(shop)
        Array(translations).filter_map do |raw|
          locale = Locales::Tag.normalize(raw[:locale].to_s)
          field = raw[:field].to_s
          path = [ "translations", locale.presence || "?", field.presence || "?" ]

          if !enabled.include?(locale)
            errors << error(path, I18n.t("errors.translation.locale_not_enabled"), "LOCALE_NOT_ENABLED")
            next
          end
          if locale == source_locale
            # 來源語言的文字在 base row（title／descriptionHtml…），不進 translations。
            errors << error(path, I18n.t("errors.translation.source_locale_not_translatable"), "INVALID")
            next
          end
          unless FIELDS.include?(field)
            errors << error(path, I18n.t("errors.translation.field_not_translatable"), "INVALID")
            next
          end

          value = sanitize(field, raw[:value].to_s)
          # 🔴 `Fields.measure` 而不是 `.length`：body_html 的上限是**位元組**（見 Fields#measure）。
          if Fields.measure(field, value) > Fields.limit(field)
            errors << error(path, I18n.t("errors.translation.too_long"), "TOO_LONG")
            next
          end

          { locale:, field:, value: }
        end
      end

      # 🔴 **富文本譯文必須與 base 走同一套白名單 sanitize**（本包修補的安全缺口）。
      #
      #   缺口實證（2026-08-25 於 bt3 正式環境 rev 1a75ceb 實跑）：同一段
      #   `<p>ok</p><script>alert(1)</script><img src=x onerror=alert(2)>`
      #     - 走 `description_html` ⇒ 落庫 `<p>ok</p>alert(1)<img>`（script 與 onerror 都沒了）
      #     - 走 `translations[body_html]` ⇒ **原樣落庫**，`<script>` 與 `onerror` 俱在
      #   原因是本方法之前不存在，`SaveProduct` 的註釋逐字寫「譯文原樣帶下去（驗證在
      #   `Translations::Upsert`）」，而 Upsert 只驗長度與欄位白名單、不 sanitize。
      #   ⇒ 第 30／34 包把譯文渲染到前台的那一刻它就是儲存型 XSS。
      #
      #   🔴 **順序是「先 sanitize 後判空、後量長度」，三者都不可對調**：
      #   - 先判空 ⇒ `<video src=x></video>` 判非空，但 sanitize 後它變成 `""`，
      #     於是存進一列「後台已翻譯、前台空白」的鬼列（`i18n.blank_value.runs_after_sanitize`）。
      #   - 先量長度 ⇒ 100KB 的 `<script>` 被判 TOO_LONG，但它 sanitize 後可能只剩 10 bytes。
      #     base 的 `SaveProduct#normalize` 也是先 sanitize 再量（複驗＝
      #     `grep -n "sanitize_description(input\[:description_html\]" -A 3 app/services/catalog/save_product.rb`）。
      #
      #   🔴 借用 `Catalog::SaveProduct.sanitize_description_for` 而不是自己再開一份白名單：
      #   `SaveCollection` 已經是這個形態（同檔 `grep -n sanitize_description_for`）。
      #   全倉恰一份 `ALLOWED_TAGS`／`ALLOWED_ATTRIBUTES`——兩份白名單＝兩個真相。
      def sanitize(field, value)
        return value unless Fields.kind(field) == :html

        Catalog::SaveProduct.sanitize_description_for(value)
      end

      # 空值（含語義空 HTML）＝刪除該列；其餘 upsert 並重算 digest。
      def apply(shop, resource_type, resource_id, source_locale, source_values, entry)
        scope = Translation.where(
          shop_id: shop.id, resource_type:, resource_id:,
          locale_tag: entry[:locale], field_key: entry[:field]
        )

        # 值已在 `normalize` 內 sanitize 過（`runs_after_sanitize`），這裡判的是最終要落庫的值。
        if BlankValue.blank?(entry[:value], kind: Fields.kind(entry[:field]))
          scope.delete_all
          return
        end

        record = scope.first_or_initialize
        # 🔴 **譯文值沒變就不動 digest**（線上實測抓到的缺口）：admin SPA 是宣告式、
        #    **恆送全樹**（含未編輯的既有譯文），若無條件重寫 digest，商家「改了英文標題、
        #    沒動翻譯」的那一次儲存會把 digest 更新成新來源文字 ⇒ 過期偵測永遠不觸發。
        #    digest 的語義是「這條譯文是照哪一版來源文字翻的」，只有譯文真的被改寫時才推進。
        unchanged = record.persisted? && record.value == entry[:value]
        record.assign_attributes(
          shop_id: shop.id, resource_type:, resource_id:,
          locale_tag: entry[:locale], field_key: entry[:field],
          value: entry[:value],
          source_locale_tag: source_locale
        )
        unless unchanged
          record.assign_attributes(
            source_digest: Translation.digest_for(source_values[entry[:field]]),
            value_source: "human",
            outdated: false,
            outdated_severity: "none",
            review_required: false
          )
        end
        record.save!
      end

      # 來源文字改了 ⇒ 該欄位所有語言的譯文標過期（67 §C.5；minor/major 依變更比例）。
      def refresh_outdated(shop, resource_type, resource_id, source_values)
        Translation.where(shop_id: shop.id, resource_type:, resource_id:).find_each do |record|
          current_digest = Translation.digest_for(source_values[record.field_key])
          if current_digest == record.source_digest
            record.update_columns(outdated: false, outdated_severity: "none") if record.outdated
            next
          end

          severity = severity_for(record, source_values[record.field_key])
          record.update_columns(outdated: true, outdated_severity: severity)
        end
      end

      # 變更比例 ≤ `i18n.outdated_minor_change_ratio` ⇒ minor（例：改錯字），否則 major。
      # 🔴 只是提示強度，**不影響前台渲染**（`outdated_affects_storefront_render: false`）。
      def severity_for(record, current_source_text)
        ratio = Limits.fetch(:i18n, :outdated_minor_change_ratio).to_f
        previous_length = record.value.to_s.length
        current_length = current_source_text.to_s.length
        return "major" if previous_length.zero?

        delta = (current_length - previous_length).abs.to_f / [ previous_length, 1 ].max
        delta <= ratio ? "minor" : "major"
      end

      def error(path, message, code)
        { field: path, message:, code: }
      end
    end
  end
end
