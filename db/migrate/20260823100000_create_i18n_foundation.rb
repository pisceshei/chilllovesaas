# frozen_string_literal: true

# 多語言地基（ML-0）：docs/specs/67 §C.1／C.2／C.6 的四張表落地
# ＋首發五語種子＋既有商店啟用＋介面語言預設改 en。
#
# 裁定出處：docs/plans/2026-08-23-多語言方案.md §3（使用者 2026-08-23 裁定 C1–C7）。
#
# 表的分層（鐵律 2）：
#   - `platform_locales`：**平台字典表**（跨租戶共用、隨版本部署、無任何租戶資料）⇒ 無 shop_id，
#     列入 scripts/check-tenant-isolation.rb 的 NON_TENANT_TABLES（同 PR 改 CLAUDE.md 鐵律 2 與 71 §A G24）。
#   - `shop_locales`／`translations`／`translation_status`：業務資料 ⇒ 帶 shop_id，複合索引以 shop_id 開頭。
#
# 🔴 不做的事（67 §E.2-1 硬規則 1）：translations **不是** per-locale JSON blob。
#    一列＝一個 (resource, locale, field)，否則欄位級 digest／outdated／進度分子／CSV 逐欄一起壞。
# 🔴 `zh-Hant-HK` 之類帶地區的繁中**不進** platform_locales（67 §C.1 規則 1）：
#    地區只在 URL 前綴與 hreflang 組字串時出現；譯文只有一份 `zh-Hant`。
class CreateI18nFoundation < ActiveRecord::Migration[8.1]
  # 首發五語（limits `i18n.launch_locales`；種子不是列舉——商家之後可自行新增）。
  # endonym＝語言自稱（切換器顯示用；不用國旗、不用語言碼——`en` 不屬於任何國家）。
  PLATFORM_LOCALES = [
    { tag: "en",      language: "en", script: nil,    endonym: "English",  plural_rule: "en", collation: "utf8mb4_0900_ai_ci" },
    { tag: "zh-Hant", language: "zh", script: "Hant", endonym: "繁體中文", plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "zh-Hans", language: "zh", script: "Hans", endonym: "简体中文", plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "ja",      language: "ja", script: nil,    endonym: "日本語",   plural_rule: "ja", collation: "utf8mb4_ja_0900_as_cs" },
    { tag: "fr",      language: "fr", script: nil,    endonym: "Français", plural_rule: "fr", collation: "utf8mb4_0900_ai_ci" }
  ].freeze

  SOURCE_LOCALE = "en"

  def up
    create_table :platform_locales, id: false,
      comment: "平台語言字典（跨租戶共用；非租戶資料，無 shop_id——鐵律 2 平台字典表）" do |t|
      t.string :tag, limit: 35, null: false, primary_key: true, comment: "BCP-47，寫入層正規化：zh-Hant / zh-Hans / en / ja / fr"
      t.string :language, limit: 3, null: false, comment: "ISO 639-1（必要時 639-3）"
      t.string :script, limit: 4, comment: "ISO 15924：Hant / Hans；拉丁文字留 NULL"
      t.string :region, limit: 2, comment: "ISO 3166-1 alpha-2；通常 NULL（地區屬市場，67 §C.1 規則 1）"
      t.string :endonym, limit: 64, null: false, comment: "語言自稱：繁體中文 / English（切換器顯示這個）"
      t.string :direction, limit: 3, null: false, default: "ltr", comment: "ltr / rtl"
      t.string :plural_rule, limit: 32, null: false, comment: "複數類別集合識別字（Intl.PluralRules 的 locale）"
      t.string :date_format_id, limit: 32, null: false, default: "default"
      t.string :number_format_id, limit: 32, null: false, default: "default"
      t.string :collation, limit: 64, null: false, comment: "該語言排序用 collation（67 §C.7）"
      t.string :status, limit: 16, null: false, default: "available", comment: "available / deprecated"
      t.timestamps
    end

    create_table :shop_locales, comment: "租戶啟用的語言（67 §C.1）：恆一列 is_source" do |t|
      t.bigint :shop_id, null: false
      t.string :locale_tag, limit: 35, null: false
      t.boolean :is_source, null: false, default: false, comment: "來源語言：base 資料表的文字語言；每店恰一列"
      t.boolean :published, null: false, default: false, comment: "前台可見；未發布＝只能預覽連結"
      t.boolean :enabled, null: false, default: true, comment: "false＝下架但譯文保留（加回即復原）"
      t.integer :position, null: false, default: 0, comment: "切換器與堆疊欄位排序"
      # MySQL 無部分唯一索引 ⇒ 生成欄位模擬：is_source 為 true 時＝1，否則 NULL（NULL 不參與唯一比較）。
      t.virtual :source_guard, type: :integer, as: "IF(is_source, 1, NULL)", stored: true
      t.timestamps
      t.index [ :shop_id, :locale_tag ], unique: true, name: "uq_shop_locales_locale_tag"
      t.index [ :shop_id, :source_guard ], unique: true, name: "uq_shop_locales_single_source"
      t.index [ :shop_id, :enabled, :position ], name: "ix_shop_locales_enabled_position"
      t.index [ :shop_id, :id ], unique: true, name: "uq_shop_locales_tenant_id"
      # FK 在 create_table 內宣告（新表，strong_migrations 視為安全；獨立 add_foreign_key 會被擋）。
      t.foreign_key :shops, name: "fk_shop_locales_shop"
      t.foreign_key :platform_locales, column: :locale_tag, primary_key: :tag, name: "fk_shop_locales_locale"
    end

    create_table :translations, comment: "內容譯文（67 §C.2）：一列＝一個 (resource, locale, field)；base row 永遠是來源語言" do |t|
      t.bigint :shop_id, null: false
      t.string :resource_type, limit: 48, null: false, comment: "PRODUCT / COLLECTION /（後續）…"
      t.bigint :resource_id, null: false
      t.string :locale_tag, limit: 35, null: false
      t.string :field_key, limit: 255, null: false, comment: "title / body_html / meta_title / meta_description"
      t.text :value, size: :medium, null: false
      t.string :source_digest, limit: 64, null: false, comment: "來源文字正規化後 SHA-256（67 §C.5 過期偵測）"
      t.boolean :outdated, null: false, default: false
      t.string :outdated_severity, limit: 8, null: false, default: "none", comment: "none / minor / major"
      t.string :value_source, limit: 24, null: false, comment: "human / machine / script_conversion / import"
      t.boolean :review_required, null: false, default: false, comment: "machine / script_conversion 一律 true"
      t.string :source_locale_tag, limit: 35, null: false, comment: "這條譯文是從哪個語言翻的（改來源語言時用）"
      t.bigint :updated_by_staff_id
      t.timestamps
      # 🔴 五欄全 NOT NULL，唯一約束才真正生效（MySQL：NULL≠NULL）。
      t.index [ :shop_id, :resource_type, :resource_id, :locale_tag, :field_key ], unique: true, name: "uq_translations_resource_locale_field"
      t.index [ :shop_id, :resource_type, :resource_id, :locale_tag ], name: "ix_translations_resource_locale"
      t.index [ :shop_id, :locale_tag, :outdated, :resource_type ], name: "ix_translations_locale_outdated"
      t.index [ :shop_id, :locale_tag, :review_required ], name: "ix_translations_locale_review"
      t.index [ :shop_id, :id ], unique: true, name: "uq_translations_tenant_id"
      t.foreign_key :shops, name: "fk_translations_shop"
      t.foreign_key :platform_locales, column: :locale_tag, primary_key: :tag, name: "fk_translations_locale"
    end

    create_table :translation_status, comment: "翻譯進度物化（67 §C.6；鐵律 7：進度數字唯一來源）" do |t|
      t.bigint :shop_id, null: false
      t.string :resource_type, limit: 48, null: false
      t.bigint :resource_id, null: false
      t.string :locale_tag, limit: 35, null: false
      t.integer :required_fields, null: false, default: 0
      t.integer :translated_fields, null: false, default: 0
      t.integer :outdated_count, null: false, default: 0
      t.integer :review_pending, null: false, default: 0
      t.timestamps
      t.index [ :shop_id, :resource_type, :resource_id, :locale_tag ], unique: true, name: "uq_translation_status_resource_locale"
      t.index [ :shop_id, :locale_tag, :translated_fields ], name: "ix_translation_status_locale_progress"
      t.index [ :shop_id, :id ], unique: true, name: "uq_translation_status_tenant_id"
      t.foreign_key :shops, name: "fk_translation_status_shop"
    end

    # 介面語言預設改 en（裁定 C3：新員工 en、既有員工沿用自己的值——只改 default，不動資料）。
    change_column_default :staff_members, :locale, from: "zh-Hant", to: "en"

    # 種子是純 INSERT IGNORE（冪等、只寫新表）；strong_migrations 看不進 execute ⇒ safety_assured。
    safety_assured do
      seed_platform_locales!
      enable_launch_locales_for_existing_shops!
    end
  end

  def down
    change_column_default :staff_members, :locale, from: "en", to: "zh-Hant"
    drop_table :translation_status
    drop_table :translations
    drop_table :shop_locales
    drop_table :platform_locales
  end

  private

  # 平台字典種子（冪等：已存在則略過）。
  def seed_platform_locales!
    now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S")
    PLATFORM_LOCALES.each do |row|
      execute <<~SQL.squish
        INSERT IGNORE INTO platform_locales
          (tag, language, script, region, endonym, direction, plural_rule, date_format_id, number_format_id, collation, status, created_at, updated_at)
        VALUES (#{quote(row[:tag])}, #{quote(row[:language])}, #{row[:script] ? quote(row[:script]) : 'NULL'}, NULL,
                #{quote(row[:endonym])}, 'ltr', #{quote(row[:plural_rule])}, 'default', 'default',
                #{quote(row[:collation])}, 'available', '#{now}', '#{now}')
      SQL
    end
  end

  # 既有商店：en 為來源語言（published），其餘四語啟用但未發布（商家補齊譯文後自行發布）。
  # 新商店由 Shop#after_create 走同一規則（app/models/shop.rb）。
  def enable_launch_locales_for_existing_shops!
    now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S")
    select_values("SELECT id FROM shops").each do |shop_id|
      PLATFORM_LOCALES.each_with_index do |row, position|
        source = row[:tag] == SOURCE_LOCALE
        execute <<~SQL.squish
          INSERT IGNORE INTO shop_locales
            (shop_id, locale_tag, is_source, published, enabled, position, created_at, updated_at)
          VALUES (#{shop_id}, #{quote(row[:tag])}, #{source ? 1 : 0}, #{source ? 1 : 0}, 1, #{position}, '#{now}', '#{now}')
        SQL
      end
    end
  end
end
