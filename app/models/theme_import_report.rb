# frozen_string_literal: true

# 主題匯入報告（G3 步 15a；99 §5——成功/失敗都留痕，相容掃描是資料不是閘）。
class ThemeImportReport < ApplicationRecord
  STATUSES = %w[ok failed].freeze

  acts_as_tenant :shop

  belongs_to :theme, optional: true

  validates :zip_filename, presence: true
  validates :status, inclusion: { in: STATUSES }
end
