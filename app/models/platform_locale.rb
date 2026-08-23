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
