# frozen_string_literal: true

# 主題檔案 DB 覆寫層（步 16e1；code editor 的唯一寫點）。
# 一列＝一個被編輯過的主題檔；讀序＝overlay → 來源目錄（OverlaySource）。
# 🔴 templates/*.json 與 config/settings_data.json **不走本表**（各自已有
# Template／ThemeSetting 覆寫層——雙真相源禁令，見 themeFileUpsert 白名單）。
class ThemeFileOverlay < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :theme

  validates :path, presence: true, length: { maximum: 512 },
                   uniqueness: { scope: [ :shop_id, :theme_id ] }
end
