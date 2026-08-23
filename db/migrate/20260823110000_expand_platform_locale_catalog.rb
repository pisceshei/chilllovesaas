# frozen_string_literal: true

# 擴充平台語言字典（ML-4）：商家在「設定 › 語言」新增語言時，候選清單來自這張表。
#
# 🔴 **新增語言不新增表**（docs/specs/67 §A.2：語言集合是**資料**不是列舉）：
#   ① 平台字典 `platform_locales` 要有那一列（本 migration 補齊常用語言）；
#   ② 商家啟用＝往 `shop_locales` 插一列（設定頁做的事）；
#   ③ 譯文全部落同一張 `translations`（resource × locale × field 一列）。
# 每語言一張表的代價：加語言＝改 schema＋部署，且 N 語言 × M 資源型別會表爆炸，
# 更關鍵的是**做不到欄位級的過期偵測**（67 §C.5 需要逐欄位 digest）。
#
# 冪等：實際寫入走 `PlatformLocale.seed!`（唯一正典，migration／db:seed／spec 共用）。
class ExpandPlatformLocaleCatalog < ActiveRecord::Migration[8.1]
  def up
    safety_assured { PlatformLocale.seed! }
  end

  def down
    # 只移除本輪新增的候選語言，且**不碰任何商店已啟用的語言**（FK 也會擋）。
    safety_assured do
      enabled = select_values("SELECT DISTINCT locale_tag FROM shop_locales")
      removable = PlatformLocale::CATALOG_SEED.map { |row| row[:tag] } -
                  PlatformLocale::LAUNCH_SEED.map { |row| row[:tag] } - enabled
      PlatformLocale.where(tag: removable).delete_all if removable.any?
    end
  end
end
