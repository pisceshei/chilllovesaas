# frozen_string_literal: true

module Translations
  # 既有譯文的稽核（第 7 包；`docs/plans/2026-08-24-三方向執行順序.md` 第 7 列）。
  #
  # ①這是什麼：唯讀掃描 + 可選修復，對象是**在本包的判準立起來之前**就已落庫的譯文列。
  #   譯文寫入端 2026-08-23 就上線並持續累積，所以「規則之前的資料」不是假想情境。
  #   （bt3 正式環境 2026-08-25 盤點快照：全平台 8 列、兩條可修規則命中皆 0 ⇒ 本工具
  #   目前是**預防性**的補網，不是待執行的清理。）
  #
  # ②具體功能（完整規則值域，四條＋一條棄權）：
  #   | rule                | 判準 | 為什麼是問題 | `--fix` 動作 |
  #   |---------------------|------|--------------|--------------|
  #   | `blank_value`       | sanitize 後的值在 `BlankValue` 判準下為空 | 後台顯示「已翻譯」、前台落 fallback ⇒ 兩個真相（鐵律 7） | 刪列（重驗後） |
  #   | `unsanitized_html`  | html 欄的值 ≠ 白名單 sanitize 後的值（且 sanitize 後非空） | 儲存型 XSS：本包之前 `Upsert` 對譯文完全不 sanitize | 覆寫成 sanitize 後的值（重驗後） |
  #   | `orphan_locale`     | `locale_tag` 不在該店 `shop_locales`（**含停用列**） | 語言列被刪後遺留；匯出／進度分母會少算 | **不動**（僅登記） |
  #   | `source_locale_row` | `locale_tag == source_locale` | 來源語言的文字在 base row，這列是重複真相 | **不動**（僅登記） |
  #
  #   🔴 **`blank_value` 與 `unsanitized_html` 的判定順序是安全邊界**（2026-08-25 依審查
  #   A1／S1 修正）：先算 `clean = sanitize(value)`，`clean` 判空 ⇒ `blank_value`（刪列），
  #   否則 `clean != value` ⇒ `unsanitized_html`（覆寫成 clean）。首版反過來——值非空就進
  #   sanitize 分支，於是 `<iframe>`／`<video>` 這類「content-bearing 但白名單外」的列被
  #   `update_columns(value: "")` 覆寫成**空字串**：繞過 model 的 presence 驗證、造出
  #   「後台已翻譯、前台空白」的鬼列（本模組要消滅的東西）、且第二輪 audit 又把同一列
  #   報成 blank_value ⇒ fix 不冪等（兩位審查方各自以 e2e 實跑重現）。
  #
  #   🔴 **`orphan_locale` 比對的是 `shop_locales` 全列，不濾 `enabled`**（2026-08-25 依
  #   審查 A5 修正）：`enabled=false` 是官方的「下架但譯文保留」功能
  #   （`Mutations::ShopLocaleDisable` 明文不動譯文），首版用 `enabled_tags` 比對，
  #   於是每一家用過停用鈕的店 audit 恆非零、恆 abort。
  #
  #   🔴 **`script_mismatch`（繁簡誤借）本輪一律「棄權」，不是「零筆」**：可靠的判別需要
  #   繁簡字表，而本輪調查所及唯一成熟的公開字表（OpenCC 的 `STCharacters.txt`／
  #   `TSCharacters.txt`，LICENSE＝Apache-2.0，
  #   https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE，2026-08-25）依鐵律 9
  #   「混入前法務面要知情」屬計畫外授權裁定，命中鐵律 17.3 的例外，**不在本包擅自做**。
  #   本規則因此以「棄權」形態存在：介面就位、報告明講「未執行」，
  #   **絕不回報 0 筆**（回報 0 筆等於宣稱掃過且乾淨，把未取得寫成事實，違反鐵律 19）。
  #   待裁定事項全文＝`docs/dev/m2-translations-resolve.md` §7；登記＝
  #   `docs/specs/91-pit-register.md` §3（P7 條目）。
  #
  # ③怎麼做到 —— 掃描與修復的併發紀律（2026-08-25 依審查 C2／C3 修正）：
  #   🔴 (a) **掃描不開 transaction**（`find_each` 逐批讀），**修復逐列短 transaction**：
  #      首版把整批修復包在一個大 transaction 裡、Loofah parse 也在裡面跑——鎖持有時間
  #      隨壞列數線性成長（審查方實測 400 列 ≈ 30.9s，~650 列即破 MySQL 預設
  #      `innodb_lock_wait_timeout=50s`，把併發的 productSet 撞成 500）。現在：
  #      sanitize 全部在鎖外算好，每列只在自己的短 transaction 內「鎖 → 重驗 → 寫」。
  #   🔴 (b) **修復前逐列重驗（TOCTOU）**：掃描到修復之間隔著整段掃描時間，商家可能
  #      已經把那一列改成真內容——首版 `clear!` 拿掃描時的 id 清單盲 `delete_all`，
  #      會把剛存好的譯文刪掉。現在：鎖住列後值與掃描時不同 ⇒ 跳過並計入
  #      `skipped_stale`，絕不動一個沒重驗過的列。
  #   🔴 (c) **零掃描 canary**：`scanned` 恆回報實際掃過的列數；0 列時 rake 印
  #      「一列都沒有」而不是「乾淨」——「沒找到問題」與「沒去找」必須看得出差別。
  #   🔴 (d) **棄權必須顯式**：`abstained` 列出沒跑的規則與原因；rake 印在最上面。
  #   ⚠️ 已知成本（審查 C6，登記不隱瞞）：每一列 html 欄要跑判空＋sanitize 比對兩次
  #      parse（本機實測合計 ~50ms/列量級），5 萬列規模的店一次 audit 是**分鐘級**任務；
  #      它是低頻維運 rake，慢是可接受的，**鎖**才是不可接受的（已由 (a) 解掉）。
  #      rake 每 500 列印一次進度，看得出活著。
  #
  # ④跨功能影響：
  #   - 唯一呼叫端＝`lib/tasks/translations.rake`（`rails translations:audit`）。
  #     🔴 **不放 `scripts/`**：那是 CI 閘門所在地（鐵律 18.3），且本任務需要 Rails 環境。
  #   - `--fix` 動列後 `translation_status` 重算走 `Upsert.recompute_status`（鐵律 7 單一
  #     來源），`touch: true` 推進 stamp。
  #   - 修復是 tenant-scoped 的，一次一家店；不提供「全平台一次修」的入口。
  class Audit
    Finding = Data.define(:rule, :translation_id, :resource_type, :resource_id,
                          :locale_tag, :field_key, :detail, :observed_value, :clean_value)

    Report = Data.define(:shop_id, :scanned, :findings, :abstained, :fixed, :skipped_stale) do
      def findings_by_rule = findings.group_by(&:rule).transform_values(&:length)
      def clean? = findings.empty?
    end

    # 棄權的規則與逐字理由（見檔頭②的紅字段落）。
    ABSTAINED = [
      {
        rule: "script_mismatch",
        reason: "繁簡誤借偵測需要繁簡字表；本輪調查所及唯一成熟公開字表（OpenCC）為 Apache-2.0，" \
                "依鐵律 9 屬混入前需法務知情的授權裁定 ⇒ 未取得裁定前不執行。" \
                "🔴 這是「未執行」不是「零筆」。"
      }
    ].freeze

    FIXABLE = %w[blank_value unsanitized_html].freeze

    class << self
      # @param shop [Shop]
      # @param fix [Boolean] true＝修復可修的兩條規則並重算 translation_status
      # @param progress [Proc, nil] 每掃 500 列回呼一次（rake 印進度用）
      # @return [Report]
      # @note 副作用：`fix: true` 時刪除／覆寫 `translations` 列並重寫 `translation_status`；
      #   掃描本身不開 transaction、不持鎖。
      def call(shop:, fix: false, progress: nil)
        ActsAsTenant.with_tenant(shop) do
          known_tags = ShopLocale.where(shop_id: shop.id).pluck(:locale_tag)
          source_locale = Locales::Registry.source_tag(shop)
          findings = []
          scanned = 0

          Translation.where(shop_id: shop.id).find_each do |record|
            scanned += 1
            progress&.call(scanned) if (scanned % 500).zero?
            findings.concat(inspect_row(record, known_tags, source_locale))
          end

          fixed, stale = fix ? apply_fixes!(shop, findings) : [ 0, 0 ]
          Report.new(shop_id: shop.id, scanned:, findings:, abstained: ABSTAINED,
                     fixed:, skipped_stale: stale)
        end
      end

      private

      def inspect_row(record, known_tags, source_locale)
        found = []
        # 🔴 泛用 `Fields.kind`，不硬編 "body_html"（審查 S5）：寫入端已是這個形態，
        #   audit 硬編字串會在新增第二個 html 欄時靜默漏掃（鐵律 20.2 第 2 類）。
        html = Fields.kind(record.field_key) == :html
        clean = html ? Catalog::SaveProduct.sanitize_description_for(record.value.to_s) : record.value.to_s

        # 檔頭②紅字：先判 clean 空不空，再談 sanitize 差異——順序反了就會製造鬼列。
        if BlankValue.blank?(clean, kind: Fields.kind(record.field_key))
          found << finding(record, "blank_value",
                           "sanitize 後的值在 BlankValue 判準下等於沒有翻譯（後台會顯示「已翻譯」）",
                           clean)
        elsif html && clean != record.value.to_s
          found << finding(record, "unsanitized_html", "值含白名單外的標籤或屬性", clean)
        end

        found << finding(record, "orphan_locale", "locale_tag 不在 shop_locales（含停用列都算在內）", nil) unless known_tags.include?(record.locale_tag)
        found << finding(record, "source_locale_row", "來源語言的文字應在 base row", nil) if record.locale_tag == source_locale
        found
      end

      def finding(record, rule, detail, clean_value)
        Finding.new(rule:, translation_id: record.id, resource_type: record.resource_type,
                    resource_id: record.resource_id, locale_tag: record.locale_tag,
                    field_key: record.field_key, detail:,
                    observed_value: record.value.to_s, clean_value:)
      end

      # @return [Array(Integer, Integer)] [實際動到的列數, 因值已變而跳過的列數]
      def apply_fixes!(shop, findings)
        targets = findings.select { |f| FIXABLE.include?(f.rule) }
        return [ 0, 0 ] if targets.empty?

        fixed = 0
        stale = 0
        recompute = Set.new

        targets.each do |f|
          # 逐列短 transaction：鎖 → 重驗（值必須仍是掃描時看到的那個）→ 寫。
          # 🔴 sanitize（`clean_value`）在掃描期就算好了，transaction 內零 parse。
          changed = Translation.transaction do
            record = Translation.lock.find_by(shop_id: shop.id, id: f.translation_id)
            next :gone if record.nil?
            next :stale if record.value.to_s != f.observed_value

            if f.rule == "blank_value"
              record.destroy!
            else
              # update!（非 update_columns）：跑 presence 驗證（clean 依分類保證非空，
              # 這裡是防線不是裝飾）並正常推進 updated_at。
              record.update!(value: f.clean_value)
            end
            :fixed
          end

          case changed
          when :fixed
            fixed += 1
            recompute << [ f.resource_type, f.resource_id, f.locale_tag ]
          when :stale then stale += 1
          end
        end

        # 進度重算逐組短 transaction（鐵律 7 單一來源；touch 推進 stamp）。
        recompute.each do |type, id, tag|
          Upsert.recompute_status(shop:, resource_type: type, resource_id: id,
                                  locale_tag: tag, touch: true)
        end
        [ fixed, stale ]
      end
    end
  end
end
