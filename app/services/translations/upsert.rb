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
    # prepare 的產物：正規化＋sanitize 完成的 entries（純資料，可安全跨 transaction 邊界攜帶）。
    Prepared = Data.define(:entries, :user_errors)

    class << self
      # 🔴 **prepare／commit 兩段式**（2026-08-25 依審查 C4 拆分）：`prepare` 做全部
      #   CPU 重活（Tag 正規化、白名單、尺寸前置閘、Loofah sanitize、量長度）且**不碰
      #   要寫的表**；`commit` 只做 DB 寫入。理由＝呼叫端（productSet／collectionSet）
      #   在整棵樹的 transaction 內叫進來，而 transaction 期間持有 product 列鎖、改名時
      #   還持店級鎖——實測 sanitize 一個貼近上限的 body_html ≈ 數百 ms，4 個語言就把
      #   鎖持有拉長到秒級。base 的慣例本來就是「normalize（含 sanitize）在 txn 前」
      #   （`SaveProduct#normalize` 在開 txn 之前跑），譯文比照。
      #
      # @param shop [Shop]
      # @param source_locale [String] 來源語言標籤（base row 的語言）
      # @param translations [Array<Hash>] `{ locale:, field:, value: }`；缺席＝不動、空字串＝刪除
      # @return [Prepared] entries ＋ user_errors（欄位路徑對齊 28 §0.3）
      # @note 副作用：只讀 `shop_locales`（enabled 集合）；**不寫任何表**。
      #   🔴 呼叫位置的精確說法（審查 F6 更正）：「在**商品樹 transaction 與任何列鎖之前**」
      #   ——不是「任何 transaction 外」。productSet 建立路徑上 `Idempotency::Guard` 先開
      #   一層 txn 再 yield，prepare 必然在它裡面跑；守住的是 parse 期間不持商品列鎖／店鎖。
      def prepare(shop:, source_locale:, translations:)
        errors = []
        entries = normalize(shop, translations, source_locale, errors)
        Prepared.new(entries:, user_errors: errors)
      end

      # 寫入段。吃 `prepare` 的產物，在**呼叫端的 transaction 內**執行①〜④。
      #
      # @param prepared [Prepared] 必須是 user_errors 為空的 prepare 結果
      # @param source_values [Hash{String=>String}] 來源文字（field_key => 值），用來算 digest
      # @return [Result]
      # @note 副作用：寫 translations／translation_status。
      def commit(shop:, resource_type:, resource_id:, source_locale:, source_values:, prepared:)
        raise ArgumentError, "commit 只收乾淨的 prepare 結果，但收到 user_errors 非空的 Prepared" if prepared.user_errors.any?

        # 本次真的動到列的語言集合——`recompute_status` 據此決定要不要推進 stamp（A2）。
        changed_locales = Set.new
        prepared.entries.each do |entry|
          changed_locales << entry[:locale] if apply(shop, resource_type, resource_id,
                                                     source_locale, source_values, entry)
        end
        refresh_outdated(shop, resource_type, resource_id, source_values)
        Locales::Registry.enabled_tags(shop).each do |tag|
          next if tag == source_locale

          recompute_status(shop:, resource_type:, resource_id:, locale_tag: tag,
                           touch: changed_locales.include?(tag))
        end
        Result.new(user_errors: [])
      end

      # 一段式便利入口（＝prepare＋commit）。直接呼叫端（spec、既有相容）用；
      # 🔴 productSet／collectionSet **不要用這支**——它會把 sanitize 拉回 transaction 內
      #   （見 prepare 的拆分理由）。
      def call(shop:, resource_type:, resource_id:, source_locale:, source_values:, translations:)
        prepared = prepare(shop:, source_locale:, translations:)
        return Result.new(user_errors: prepared.user_errors) if prepared.user_errors.any?

        commit(shop:, resource_type:, resource_id:, source_locale:, source_values:, prepared:)
      end

      # 進度物化（67 §C.6）：required＝必翻欄位數；translated＝有值的必翻欄位數。
      #
      # 🔴 **公開的理由**：`Translations::Audit` 的 `--fix` 刪／改列之後也必須重算，
      #   而進度數字依鐵律 7 只准有一個來源。把算式複製第二份到 Audit 是最典型的
      #   「生產者已改、消費者未同步」根因（鐵律 20.2 第 2 類）。
      #
      # @param touch [Boolean] 該 (resource, locale) 的譯文列本次**真的變了**（寫入／刪除）。
      #   🔴 為什麼需要它（審查 A2）：只改譯文**文字**時四個計數欄一個都不變，
      #   `save!` 對無變更的 record 不發 UPDATE ⇒ `updated_at` 不推進——而 67 §G.3 建議
      #   拿這一欄當 `translations` 的 cache stamp 載體，「商家改了譯文、前台永遠是舊的」
      #   正是那種靜默失效。計數變了 `save!` 自然更新；沒變但列動過 ⇒ 顯式 `touch`。
      #   🔴 不得無條件 touch：那會把沒動過的語言的 stamp 一起推進，快取白白全失效。
      # @return [TranslationStatus]
      # @note 副作用：upsert 一列 `translation_status`。
      def recompute_status(shop:, resource_type:, resource_id:, locale_tag:, touch: false)
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
        status.touch if touch && !status.saved_changes?
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

          raw_value = raw[:value].to_s
          # 🔴 **尺寸前置閘在 sanitize 之前**（2026-08-25 依審查 S4 加上，推翻首版順序）：
          #   Loofah parse 的成本隨輸入超線性成長（實測 64KB≈0.78s、1MB≈14s、5MB≈160s），
          #   而 nginx 收 32MB、rack-attack 只限 login ⇒ 認證後的巨大 payload 可以在
          #   量長度**之前**把 CPU 燒光。先用 0 成本的 bytesize 擋掉超限輸入，parse 的
          #   輸入就被限制在欄位上限內。代價＝「raw 超限但 sanitize 後會縮到限內」的
          #   輸入改為直接拒收——首版註釋以這個情境反對先量長度，本次裁定：
          #   為一個邊緣便利保留一條無上界的 CPU 路徑不值得。
          if Fields.measure(field, raw_value) > Fields.limit(field)
            errors << error(path, I18n.t("errors.translation.too_long"), "TOO_LONG")
            next
          end

          value = sanitize(field, raw_value)
          # 🔴 **sanitize 把非空內容毀成空 ⇒ 顯式報錯，不靜默刪列**（2026-08-25 依審查
          #   S2／A1 加上）：`<video>`／`<iframe>` 這類「content-bearing 但不在白名單」的
          #   內容，以及 libxml2 深度 255 懸崖吞掉的深巢狀文字，sanitize 後都變 ""——
          #   首版把它們走「判空＝刪列」路徑＝商家的內容靜默消失。現在：
          #   raw 本來就空（RTE 初始值）⇒ 照舊刪列；raw 非空而 sanitize 後空 ⇒ userError。
          #   🔴 「raw 有沒有內容」必須用 **parser-independent** 的 `text_bearing?` 判——
          #   毀掉內容的機制之一就是 parser 自己的深度上限，用 `blank?` 判 raw 會撞同一個
          #   懸崖而回報「raw 也是空的」，偵測器與失效共用盲點（見 BlankValue#text_bearing?）。
          kind = Fields.kind(field)
          if BlankValue.blank?(value, kind:) && BlankValue.text_bearing?(raw_value)
            errors << error(path, I18n.t("errors.translation.unsupported_content"), "INVALID")
            next
          end
          # sanitize 可能**放大**輸出（實體跳脫），落庫值仍須在限內。
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
      #   🔴 **順序（2026-08-25 依審查 S2／S4 二次修正）＝「量 raw → sanitize → 判空
      #   （毀內容則報錯）→ 再量 sanitize 後的值」**。首版寫「先 sanitize 後量長度，
      #   不可對調」並以「100KB script sanitize 後可能只剩 10 bytes」為由——該順序被
      #   S4 推翻（無上界輸入先進 parser＝CPU 放大面），原句撤回；判空仍在 sanitize
      #   之後（`i18n.blank_value.runs_after_sanitize` 不變），但「raw 非空而 sanitize
      #   後空」現在是 userError 而不是刪列（見 normalize 內註釋）。
      #
      #   🔴 借用 `Catalog::SaveProduct.sanitize_description_for` 而不是自己再開一份白名單：
      #   `SaveCollection` 已經是這個形態（同檔 `grep -n sanitize_description_for`）。
      #   全倉恰一份 `ALLOWED_TAGS`／`ALLOWED_ATTRIBUTES`——兩份白名單＝兩個真相。
      def sanitize(field, value)
        return value unless Fields.kind(field) == :html

        Catalog::SaveProduct.sanitize_description_for(value)
      end

      # 空值（含語義空 HTML）＝刪除該列；其餘 upsert 並重算 digest。
      # @return [Boolean] 本列是否真的動了（刪了列／寫入了變更）——commit 據此決定 touch。
      def apply(shop, resource_type, resource_id, source_locale, source_values, entry)
        scope = Translation.where(
          shop_id: shop.id, resource_type:, resource_id:,
          locale_tag: entry[:locale], field_key: entry[:field]
        )

        # 值已在 `normalize` 內 sanitize 過（`runs_after_sanitize`），這裡判的是最終要落庫的值。
        # 走到這裡的空值必然「raw 也空」——毀內容形態已在 normalize 被擋成 userError。
        if BlankValue.blank?(entry[:value], kind: Fields.kind(entry[:field]))
          return scope.delete_all.positive?
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
        !unchanged || record.previously_new_record?
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
