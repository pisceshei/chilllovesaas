# 一個 app 在某一間店的安裝狀態——本尊 `AppInstallation` 的我方對位。
#
# 🔴 **為什麼非有不可**（決策文件 C-5）：「已安裝」這個狀態在我方**無處可表達**。
#   自然的替代做法是「安裝＝INSERT publication、卸載＝DELETE publication」，
#   而那條路會**連帶清掉全部發布列**（`resource_publications` 對 `publications`
#   有複合外鍵）⇒ 商家重裝管道後逐商品的上架設定全部消失。
#
# 🔴 這是業務資料（每店一份），帶 `shop_id`（鐵律 2）。
#   ⚠️ 它指向的 `platform_apps` **才是**平台字典表——兩者不要混淆。
#
# ## 🔴 與本尊的差異，逐條登記（鐵律 19：不得把我方設計寫成本尊形狀）
#
# 官方 `AppInstallation`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/AppInstallation>，
# 取證 2026-08-26）的欄位是 `app`／`accessScopes`／`activeSubscriptions`／`credits`／
# `launchUrl`／`uninstallUrl`／`metafield(s)`／`allSubscriptions`／`oneTimePurchases`／
# `revenueAttributionRecords`，另有三個 **deprecated**：`channel`／`publication`／`subscriptions`。
#
# 1. ~~🔴 **`installed_at`／`uninstalled_at` 是我方加的，本尊沒有。**~~
#    ~~官方該型別**沒有任何時間戳**，也**沒有表達卸載狀態的欄位**（同上來源）。~~
#    🔴 **2026-08-26 更正（實測推翻，`docs/research/82` §11.1）**：原文說「本尊沒有」**過窄**。
#    正確表述分兩層：
#      - **官方公開 GraphQL 的 `AppInstallation` 型別確實沒有任何時間戳欄位**（原判斷成立）；
#      - **但 admin UI 顯示得出來**——app installation 詳情頁
#        （`/settings/sales_channels/app_installations/app/<handle>`）逐字印
#        `Installed July 14`，且另有 `App history` 時間軸逐字印
#        `App installed by KEN LEE` ＋ 時間 ＋ 日期分組。
#      ⇒ **平台有存，只是不在公開 API 面上。** 我方 `installed_at` 因此是
#        **與本尊實質對齊**，不是憑空發明的欄位。
#    我方要這兩欄的理由（不變）：軟刪是本輪四家外部平台的共同做法（無一硬刪管道），
#    而「已卸載但保留發布紀錄」這個狀態必須落表才存在。
#    ⚠️ **卸載後 publication 與發布列的實際去向仍＝未取得**（決策文件 U-3，需安裝管道才測得到，
#    使用者已裁定不安裝）⇒ **卸載的語義**仍是我方定義的。
#    ⚠️ 另一條實測後果：本尊的 `App history` 是**帶操作者的事件時間軸**，不是一個布林狀態
#    ⇒ 我方「不留安裝歷史」（每店每 app 恆一列）是**已證實的缺口**，不是假設。
#    需要歷史時另開事件表，登記於 S0 PR B worklog 的 S0B-3。
# 2. 🔴 **不建 `app_installation.channel` / `.publication` 的對應欄**——官方**已 deprecated**。
#    現行模型的連結方向是 `App.channels`，所以我方的外鍵掛在 `channels.app_installation_id`
#    這一側（與本尊同向）。
#
# @see docs/plans/2026-08-26-S0-管道身分模型-決策文件.md §4 C-5、§7 U-3
class AppInstallation < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :platform_app, foreign_key: :app_handle, inverse_of: :app_installations
  has_many :channels, inverse_of: :app_installation

  validates :app_handle, presence: true
  validates :installed_at, presence: true
  validates :app_handle, uniqueness: { scope: :shop_id }

  # 🔴 **明確 scope，不用 `default_scope`**。
  #   `default_scope` 看起來更安全，實際上不是：`unscoped` 會繞過它，而本倉庫的
  #   migration 與 `without_tenant` 區塊到處在用 `unscoped`／`update_all`
  #   ⇒ 會得到「以為有防線其實沒有」。改成呼叫端明寫，並在此說明漏掉的後果：
  #   **已卸載的管道還會出現在發布 modal 裡**。
  scope :installed, -> { where(uninstalled_at: nil) }

  # 本安裝目前是否有效。
  #
  # @return [Boolean]
  def installed?
    uninstalled_at.nil?
  end
end
