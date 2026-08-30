# frozen_string_literal: true

# 主題庫項目（包 30／D77；表＝M0 既建，本包補模型與引擎接線）。
#
# ①這是什麼：一個可渲染的主題。**主題是資料而非可執行程式碼**（M0 表註）——
#   Liquid 檔案由 `source`＋`name` 經 `ThemeEngine::Sources` 解析成唯讀檔案來源；
#   可編輯狀態（JSON template／settings_data）入庫（`templates`／`theme_settings`），
#   引擎讀取順序＝**DB 覆寫 → 來源檔 fallback**（25 §6；D77）。
# ②單一發布不變量：`published_slot` 產生欄（role='published' ⇒ 1，否則 NULL）
#   ＋ `uq_themes_published_slot` 唯一索引 ⇒ **同店至多一個已發布主題**由 DB 保證
#   （docs/research/06 §4）。發布轉場一律走 `publish!`（先降現任、再升目標，同交易）。
# ③License：`license_attested`＝上傳／匯入時的授權聲明 gate（25 §4 第 5 步；
#   Ella fixture 僅測試授權、不隨平台散布——鐵律 9）。
class Theme < ApplicationRecord
  # M0 schema 的 role 值域（published_slot 產生欄以 'published' 判定 ⇒ 值域鎖死）。
  ROLES = %w[draft published].freeze

  acts_as_tenant :shop

  has_many :templates, dependent: :destroy
  has_one :theme_setting, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 },
                   uniqueness: { scope: :shop_id }
  validates :role, inclusion: { in: ROLES }
  validates :source, presence: true

  scope :published, -> { where(role: "published") }

  # 發布轉場：現任 published（若有）降回 draft，目標升 published——同交易。
  #
  # 🔴 順序不可倒：唯一索引擋的是「兩個 published 並存」，先升目標會在索引上炸；
  #   先降現任則中途死掉的最壞形態是「全店暫無已發布主題」（可重試收斂），
  #   不是「兩個都published」（資料損壞）。fail-closed 選前者。
  # @return [void]
  # @note 副作用：至多兩列 UPDATE。
  def publish!(at: Time.current)
    with_lock do
      self.class.where(shop_id: shop_id, role: "published").where.not(id: id)
          .update_all(role: "draft", updated_at: at)
      update!(role: "published", published_at: at)
    end
  end
end
