# frozen_string_literal: true

# 內容譯文（docs/specs/67 §C.2）：一列＝一個 (resource, locale, field)。
#
# 🔴 base 資料表（products.title…）永遠是**來源語言**的文字；本表只存其他語言。
# 🔴 不做 per-locale JSON blob（67 §E.2-1 硬規則 1）——欄位級 digest／outdated／進度分子／CSV 逐欄都靠這個粒度。
#
# 六稽核欄的語義：
#   - `source_digest`：譯文建立時來源文字的正規化 SHA-256；來源改了 ⇒ 比對不同 ⇒ `outdated`（67 §C.5）。
#   - `value_source`：human / machine / script_conversion / import——無標記的大量自動內容日後無法回溯清理。
#   - `review_required`：machine / script_conversion 一律 true（寫入層強制）。
#   - `source_locale_tag`：這條譯文是從哪個語言翻的（改來源語言時才知道哪些要重標過期）。
#
# v1 射程（docs/plans/2026-08-23-多語言方案.md §3.3）：PRODUCT／COLLECTION × title／body_html／meta_title／meta_description。
class Translation < ApplicationRecord
  acts_as_tenant :shop

  RESOURCE_TYPES = %w[PRODUCT COLLECTION].freeze
  FIELD_KEYS = %w[title body_html meta_title meta_description].freeze
  VALUE_SOURCES = %w[human machine script_conversion import].freeze
  OUTDATED_SEVERITIES = %w[none minor major].freeze
  # 自動產生的譯文一律待覆核（67 §C.2）。
  REVIEW_REQUIRED_SOURCES = %w[machine script_conversion].freeze

  belongs_to :platform_locale, foreign_key: :locale_tag, primary_key: :tag, inverse_of: false

  validates :resource_type, inclusion: { in: RESOURCE_TYPES }
  validates :field_key, inclusion: { in: FIELD_KEYS }
  validates :value_source, inclusion: { in: VALUE_SOURCES }
  validates :outdated_severity, inclusion: { in: OUTDATED_SEVERITIES }
  validates :resource_id, :locale_tag, :source_locale_tag, :source_digest, presence: true
  validates :value, presence: true
  validates :locale_tag, uniqueness: { scope: %i[shop_id resource_type resource_id field_key] }
  validate :locale_differs_from_source

  before_validation do
    self.locale_tag = Locales::Tag.normalize(locale_tag) if locale_tag.present?
    self.source_locale_tag = Locales::Tag.normalize(source_locale_tag) if source_locale_tag.present?
    self.review_required = true if REVIEW_REQUIRED_SOURCES.include?(value_source)
  end

  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :outdated, -> { where(outdated: true) }

  # 來源文字的正規化 digest（67 §C.5：trim、統一換行、HTML 去尾空白後 SHA-256）。
  #
  # @param text [String, nil]
  # @return [String] 64 hex
  def self.digest_for(text)
    normalized = text.to_s.gsub("\r\n", "\n").strip
    Digest::SHA256.hexdigest(normalized)
  end

  private

  # 譯文語言＝來源語言是資料錯誤（來源語言的文字在 base row）。
  def locale_differs_from_source
    return if locale_tag.blank? || source_locale_tag.blank?

    errors.add(:locale_tag, "不得等於來源語言（來源語言文字存在 base row）") if locale_tag == source_locale_tag
  end
end
