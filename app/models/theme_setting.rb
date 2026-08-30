# frozen_string_literal: true

# 主題全域設定（settings_data 的 current；包 30／D77）。
# 一主題一列（uq_theme_settings_theme_id）；引擎讀取順序＝本表 → 來源檔
# `config/settings_data.json` 的 `current`（fallback）。
class ThemeSetting < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :theme
  validates :theme_id, uniqueness: { scope: :shop_id }
end
