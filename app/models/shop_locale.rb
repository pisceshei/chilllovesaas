# frozen_string_literal: true

# 租戶啟用的語言（docs/specs/67 §C.1 `shop_locales`）。
#
# 不變量：
#   - 每店**恰一列** `is_source`（DB 生成欄位 `source_guard` + 唯一索引兜底；model 層再擋一次給人話錯誤）。
#   - 來源語言 `published` 恆 true、不可停用、不可刪（`SOURCE_LOCALE_IMMUTABLE`；67 §C.3(d)）。
#   - 語言數 ≤ `i18n.max_shop_locales`（20）。
#   - `enabled=false`＝下架但譯文保留，re-enable 即復原（採 SHOPLINE 的承諾，109 號可採項）。
#
# @see docs/plans/2026-08-23-多語言方案.md §3.2／§7
class ShopLocale < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :platform_locale, foreign_key: :locale_tag, primary_key: :tag, inverse_of: :shop_locales

  validates :locale_tag, presence: true, uniqueness: { scope: :shop_id }
  validate :single_source_per_shop
  validate :source_stays_published_and_enabled
  validate :within_locale_limit, on: :create

  before_validation { self.locale_tag = Locales::Tag.normalize(locale_tag) if locale_tag.present? }
  before_destroy :forbid_destroying_source

  scope :enabled, -> { where(enabled: true).order(:position, :locale_tag) }
  scope :published, -> { where(published: true) }

  # @return [ShopLocale] 本店來源語言（恆存在；找不到＝資料損毀，寧可 raise）
  def self.source!
    find_by!(is_source: true)
  end

  private

  def single_source_per_shop
    return unless is_source

    conflicting = self.class.where(shop_id:, is_source: true).where.not(id:)
    errors.add(:is_source, "每店只能有一個來源語言（67 §C.3）") if conflicting.exists?
  end

  def source_stays_published_and_enabled
    return unless is_source

    errors.add(:published, "來源語言不可取消發布（SOURCE_LOCALE_IMMUTABLE）") unless published
    errors.add(:enabled, "來源語言不可停用（SOURCE_LOCALE_IMMUTABLE）") unless enabled
  end

  def within_locale_limit
    maximum = Limits.fetch(:i18n, :max_shop_locales)
    return if self.class.where(shop_id:).count < maximum

    errors.add(:base, "語言數已達上限 #{maximum}（LOCALE_LIMIT_EXCEEDED）")
  end

  def forbid_destroying_source
    return unless is_source

    errors.add(:base, "來源語言不可刪除（SOURCE_LOCALE_IMMUTABLE）")
    throw :abort
  end
end
