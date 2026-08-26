# 平台的 app 字典——本尊 `App` 的我方對位。
#
# 🔴 **這是「平台字典表」，不是業務資料也不是身分表**（CLAUDE.md 鐵律 2 第三類）。
#   判準逐字＝「表裡**一列都不屬於任何一家店**才算平台字典表」。
#   app 的定義（handle／名稱／開發者／是否官方開發）確實一列都不屬於任何店：
#   本尊的 `App` 是 **App Store 的目錄**，全域共用；每店的部分是 `AppInstallation`。
#   同類＝`platform_locales`（跨租戶語言字典）。
#   ⇒ 無 `shop_id`，進 `scripts/check-tenant-isolation.rb` 的 `NON_TENANT_TABLES`，
#     並依鐵律 2 配套條款③同步登記於 CLAUDE.md 本文與 `docs/specs/71` §A G24。
#
# ## 欄位的官方依據（逐欄，取證 2026-08-26）
#
# 來源＝<https://shopify.dev/docs/api/admin-graphql/latest/objects/App>
#
# | 我方欄 | 本尊欄 | 官方型別與描述（逐字） |
# |---|---|---|
# | `handle`（PK） | `App.handle` | `String`／"Handle of the app." |
# | `title` | `App.title` | `String!`／"Name of the app." |
# | `developer_name` | `App.developerName` | `String`／"The name of the app developer." |
# | `shopify_developed` | `App.shopifyDeveloped` | `Boolean!`／"Whether the app was developed by Shopify." |
#
# 🔴 **兩處對設計文件原文的更正**（實作前查官方文檔時發現，鐵律 16.1）：
#   ① 原文擬了 `has_channel_capability` 布林欄——**本尊沒有這個欄位**。
#      「管道能力」在本尊是 `App.channels: ChannelConnection!`
#      （"The sales channels associated with this app."）⇒ **有沒有 channel 推導出來的**，
#      不是一個會與現實不同步的旗標。我方照同一個形狀：`channels.app_installation_id`
#      指得到本 app 的安裝，就代表它有管道能力。⇒ **本表不建那個欄。**
#   ② 原文寫 `first_party` boolean——官方欄名是 **`shopifyDeveloped`**。
#      我方文檔慣用語是「第一方」，但欄名用官方語義名，避免同一件事兩個名字。
#
# ⚠️ **刻意不建的官方欄**（有官方定義但我方目前**沒有寫入者**，
#   建了就是重演 `publications.catalog_id` 空轉兩週的坑）：
#   `apiKey`／`embedded`／`published`／`developerType`／`publicCategory`／
#   `installUrl`／`uninstallMessage`／`privacyPolicyUrl` 等。要用時再加。
#
# @see docs/plans/2026-08-26-S0-方案D-schema設計.md §3
# @see docs/research/82-admin-channels.md §10.3
class PlatformApp < ApplicationRecord
  self.primary_key = "handle"

  # 🔴 **唯一正典**：migration／`db:seed`／spec 全部走 `seed!`，不各寫一份。
  #   形態抄 `PlatformLocale::CATALOG_SEED`（同為平台字典表）。
  #
  # v1 只有一個第一方管道 app。⚠️ 這裡**不是**「本尊有哪些 app」的清單——
  # 那是 App Store 的目錄，我方沒有 App Store（`docs/specs/88` §5）。
  # 這是**我方自己提供的管道 app**。
  CATALOG_SEED = [
    {
      handle: "online_store",
      title: "線上商店",
      developer_name: "CHILL LOVE",
      shopify_developed: true
    }
  ].freeze

  has_many :app_installations, foreign_key: :app_handle, inverse_of: :platform_app

  validates :handle, presence: true, length: { maximum: 64 },
            format: { with: /\A[a-z0-9_-]+\z/, message: "只能用小寫字母、數字、底線與連字號" }
  validates :title, presence: true, length: { maximum: 255 }

  # 冪等地把字典寫進資料庫。
  #
  # 🔴 **既有列要被更新，不是跳過**。`PlatformLocale.seed!` 的形態是
  #   `next false if exists?(...)`（純新增），對語言字典成立——語言的 endonym 不會改。
  #   app 的 `title` 會改（改名、換開發者），跳過會讓改動**靜默不生效**、
  #   而部署看起來完全成功。⇒ 這裡用 find_or_initialize ＋ save。
  #
  # 🔴 **不用 `upsert_all`** 的兩個理由：①MySQL adapter 不支援 `unique_by`
  #   （實測 `ArgumentError: Mysql2Adapter does not support :unique_by`）
  #   ②`upsert_all` 繞過 validation ⇒ 字典可以寫進不合法的 handle 而沒有人擋。
  #   字典很小（v1 一列），逐筆 save 的成本可以忽略。
  #
  # @return [Integer] 字典的總列數
  # @note 副作用：INSERT／UPDATE `platform_apps`。
  def self.seed!
    CATALOG_SEED.each do |row|
      record = find_or_initialize_by(handle: row[:handle])
      record.assign_attributes(row.except(:handle))
      record.save!
    end
    count
  end
end
