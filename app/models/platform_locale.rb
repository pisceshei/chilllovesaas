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

  # 首發語言字典種子（docs/plans/2026-08-23-多語言方案.md §3.1）。**唯一正典**——
  # migration 20260823100000、db/seeds.rb、spec/support 三處都呼叫它，不各抄一份
  # （測試庫走 schema load 不跑 migration，種子若只在 migration 裡，CI 上 platform_locales 是空的）。
  LAUNCH_SEED = [
    { tag: "en",      language: "en", script: nil,    endonym: "English",  plural_rule: "en", collation: "utf8mb4_0900_ai_ci" },
    { tag: "zh-Hant", language: "zh", script: "Hant", endonym: "繁體中文", plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "zh-Hans", language: "zh", script: "Hans", endonym: "简体中文", plural_rule: "zh", collation: "utf8mb4_zh_0900_as_cs" },
    { tag: "ja",      language: "ja", script: nil,    endonym: "日本語",   plural_rule: "ja", collation: "utf8mb4_ja_0900_as_cs" },
    { tag: "fr",      language: "fr", script: nil,    endonym: "Français", plural_rule: "fr", collation: "utf8mb4_0900_ai_ci" }
  ].freeze

  # 冪等寫入種子（已存在的列不動——endonym 等若日後調整走獨立 migration）。
  #
  # @return [Integer] 新建列數
  def self.seed!
    LAUNCH_SEED.count do |row|
      next false if exists?(tag: row[:tag])

      create!(row.merge(direction: "ltr", date_format_id: "default", number_format_id: "default", status: "available"))
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
