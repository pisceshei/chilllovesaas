# frozen_string_literal: true

# 翻譯進度物化（docs/specs/67 §C.6）。鐵律 7：進度數字只有這一個來源——
# 編輯頁 tab 徽章、商品列表翻譯欄、設定頁語言總覽都讀這張表，任一處不得現算 GROUP BY。
#
# 寫入時機＝translations 寫入的**同一 transaction**（ML-2 的 Translations::Upsert 負責重算）。
class TranslationStatus < ApplicationRecord
  self.table_name = "translation_status"

  acts_as_tenant :shop

  validates :resource_type, inclusion: { in: Translation::RESOURCE_TYPES }
  validates :resource_id, :locale_tag, presence: true
  validates :locale_tag, uniqueness: { scope: %i[shop_id resource_type resource_id] }

  before_validation { self.locale_tag = Locales::Tag.normalize(locale_tag) if locale_tag.present? }

  # @return [Boolean] 必翻欄位全部有譯文且無過期
  def complete?
    required_fields.positive? && translated_fields >= required_fields && outdated_count.zero?
  end
end
