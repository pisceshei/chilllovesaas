# frozen_string_literal: true

# 平台語言字典（docs/specs/67 §C.1）。跨租戶共用、隨版本部署，**無 shop_id**——
# 它是「平台字典表」不是業務資料（鐵律 2 註釋；scripts/check-tenant-isolation.rb NON_TENANT_TABLES）。
#
# 🔴 只存**語言**（`zh-Hant`），不存帶地區的繁中（`zh-Hant-HK`）：地區屬市場，
# hreflang／URL 前綴在組字串時當場推導（67 §C.1 規則 1 的防線）。
#
# @see docs/plans/2026-08-23-多語言方案.md §3.1
class PlatformLocale < ApplicationRecord
  self.primary_key = :tag

  STATUSES = %w[available deprecated].freeze
  DIRECTIONS = %w[ltr rtl].freeze

  has_many :shop_locales, foreign_key: :locale_tag, primary_key: :tag, inverse_of: :platform_locale, dependent: :restrict_with_error

  validates :tag, :language, :endonym, :plural_rule, :collation, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validate :tag_is_normalized_and_allowed

  scope :available, -> { where(status: "available").order(:tag) }

  # 平台候選語言字典（ML-4）：商家在「設定 › 語言」能選到的全部語言。
  #
  # 🔴 **這是資料不是列舉**（67 §A.2）：新增一個語言＝在這張清單加一列＋跑 seed!，
  # **不新增表、不改任何業務程式碼**；商家啟用它只是往 `shop_locales` 插一列。
  #
  # 三個欄位的取值紀律：
  #   - `endonym`＝**語言自稱**（切換器顯示這個；不用國旗、不用語言碼——`en` 不屬於任何國家）。
  #   - `plural_rule`＝丟給 `Intl.PluralRules` 的識別字，直接用語言碼（前端 format.ts 消費）。
  #   - `collation`＝MySQL 8.4 **實際存在**的 collation 名（站內搜尋與排序用，67 §C.7）；
  #     無語言特定 collation 者一律 `utf8mb4_0900_ai_ci`（Unicode 預設），不得亂編名字。
  #
  # 🔴 `region` 只在**語言本身因地區而不同**時才給（`pt-BR` vs `pt-PT` 拼寫與用詞不同）；
  # **不得**為了表達「香港的繁中」而建 `zh-Hant-HK`——那是 `zh-Hant` ＋ HK 市場兩個維度（§C.1 規則 1）。
  CATALOG_SEED = [
    { tag: "en",      language: "en", script: nil,    region: nil,  endonym: "English",            plural_rule: "en", collation: "utf8mb4_0900_ai_ci" },
    { tag: "zh-Hant", language: "zh", script: "Hant", region: nil,  endonym: "繁體中文",           plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "zh-Hans", language: "zh", script: "Hans", region: nil,  endonym: "简体中文",           plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "ja",      language: "ja", script: nil,    region: nil,  endonym: "日本語",             plural_rule: "ja", collation: "utf8mb4_ja_0900_as_cs" },
    { tag: "fr",      language: "fr", script: nil,    region: nil,  endonym: "Français",           plural_rule: "fr", collation: "utf8mb4_0900_ai_ci" },
    { tag: "ko",      language: "ko", script: nil,    region: nil,  endonym: "한국어",             plural_rule: "ko", collation: "utf8mb4_0900_ai_ci" },
    { tag: "de",      language: "de", script: nil,    region: nil,  endonym: "Deutsch",            plural_rule: "de", collation: "utf8mb4_0900_ai_ci" },
    { tag: "es",      language: "es", script: nil,    region: nil,  endonym: "Español",            plural_rule: "es", collation: "utf8mb4_es_0900_ai_ci" },
    { tag: "pt-BR",   language: "pt", script: nil,    region: "BR", endonym: "Português (Brasil)", plural_rule: "pt", collation: "utf8mb4_0900_ai_ci" },
    { tag: "pt-PT",   language: "pt", script: nil,    region: "PT", endonym: "Português (Portugal)", plural_rule: "pt", collation: "utf8mb4_0900_ai_ci" },
    { tag: "it",      language: "it", script: nil,    region: nil,  endonym: "Italiano",           plural_rule: "it", collation: "utf8mb4_0900_ai_ci" },
    { tag: "nl",      language: "nl", script: nil,    region: nil,  endonym: "Nederlands",         plural_rule: "nl", collation: "utf8mb4_0900_ai_ci" },
    { tag: "ru",      language: "ru", script: nil,    region: nil,  endonym: "Русский",            plural_rule: "ru", collation: "utf8mb4_ru_0900_ai_ci" },
    { tag: "pl",      language: "pl", script: nil,    region: nil,  endonym: "Polski",             plural_rule: "pl", collation: "utf8mb4_pl_0900_ai_ci" },
    { tag: "tr",      language: "tr", script: nil,    region: nil,  endonym: "Türkçe",             plural_rule: "tr", collation: "utf8mb4_tr_0900_ai_ci" },
    { tag: "sv",      language: "sv", script: nil,    region: nil,  endonym: "Svenska",            plural_rule: "sv", collation: "utf8mb4_sv_0900_ai_ci" },
    { tag: "da",      language: "da", script: nil,    region: nil,  endonym: "Dansk",              plural_rule: "da", collation: "utf8mb4_da_0900_ai_ci" },
    { tag: "nb",      language: "nb", script: nil,    region: nil,  endonym: "Norsk bokmål",       plural_rule: "nb", collation: "utf8mb4_nb_0900_ai_ci" },
    { tag: "fi",      language: "fi", script: nil,    region: nil,  endonym: "Suomi",              plural_rule: "fi", collation: "utf8mb4_0900_ai_ci" },
    { tag: "cs",      language: "cs", script: nil,    region: nil,  endonym: "Čeština",            plural_rule: "cs", collation: "utf8mb4_cs_0900_ai_ci" },
    { tag: "el",      language: "el", script: nil,    region: nil,  endonym: "Ελληνικά",           plural_rule: "el", collation: "utf8mb4_0900_ai_ci" },
    { tag: "th",      language: "th", script: nil,    region: nil,  endonym: "ไทย",                plural_rule: "th", collation: "utf8mb4_0900_ai_ci" },
    { tag: "vi",      language: "vi", script: nil,    region: nil,  endonym: "Tiếng Việt",         plural_rule: "vi", collation: "utf8mb4_vi_0900_ai_ci" },
    { tag: "id",      language: "id", script: nil,    region: nil,  endonym: "Bahasa Indonesia",   plural_rule: "id", collation: "utf8mb4_0900_ai_ci" },
    { tag: "ms",      language: "ms", script: nil,    region: nil,  endonym: "Bahasa Melayu",      plural_rule: "ms", collation: "utf8mb4_0900_ai_ci" },
    { tag: "hi",      language: "hi", script: nil,    region: nil,  endonym: "हिन्दी",                plural_rule: "hi", collation: "utf8mb4_0900_ai_ci" },
    # 🔴 RTL：`direction` 這一欄的存在意義就是它們（主題層落地在 M6／L18，資料層現在就位）。
    { tag: "ar",      language: "ar", script: nil,    region: nil,  endonym: "العربية",             plural_rule: "ar", collation: "utf8mb4_0900_ai_ci", direction: "rtl" },
    { tag: "he",      language: "he", script: nil,    region: nil,  endonym: "עברית",               plural_rule: "he", collation: "utf8mb4_0900_ai_ci", direction: "rtl" }
  ].freeze

  # 首發啟用語言（新店 after_create 會啟用這些；正典在 limits `i18n.launch_locales`）。
  # 🔴 與 CATALOG_SEED 是兩件事：字典＝**可以選什麼**，首發＝**預設已啟用什麼**。
  LAUNCH_SEED = CATALOG_SEED.first(5).freeze

  # 冪等寫入字典（已存在的列不動——endonym 等若日後調整走獨立 migration）。
  #
  # @return [Integer] 新建列數
  def self.seed!
    CATALOG_SEED.count do |row|
      next false if exists?(tag: row[:tag])

      create!({ direction: "ltr", date_format_id: "default", number_format_id: "default", status: "available" }.merge(row))
      true
    end
  end

  private

  # 寫入層的標籤驗證（67 §C.1 規則 2）：格式、禁用表、zh 必帶 script。
  def tag_is_normalized_and_allowed
    return if tag.blank?

    normalized = Locales::Tag.validate!(tag)
    errors.add(:tag, "必須是正規化形態（#{normalized}）") if normalized != tag
  rescue Locales::Tag::Invalid => error
    errors.add(:tag, error.message)
  end
end
