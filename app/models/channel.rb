# 一個銷售管道——本尊 `Channel` 的我方對位。
#
# 🔴 **為什麼非有不可**（決策文件 C-2）：`channel_handle` 原本掛在 `publications` 上，
#   而本尊的 handle 屬於 `Channel`，且**帶每店後綴**——`docs/research/82` §10.3 實測
#   Shop 管道的 handle 是 **`shop-72`** 不是乾淨的 `shop`。
#   把一個「每店產生的值」當成全域常數在比對，是 C-9 那個靜默 nil 的同一個根因。
#
# 🔴 這是業務資料，帶 `shop_id`（鐵律 2）。
#
# ## 官方形狀（<https://shopify.dev/docs/api/admin-graphql/latest/objects/Channel>，取證 2026-08-26）
#
# 逐字節錄我方有對應的部分：
#   - `handle: String!`／"A unique, human-readable identifier for the channel within the shop"
#     ——🔴 官方描述自己就寫 **within the shop**，即每店唯一而非全域唯一。
#   - `app: App!`／"The underlying app used by the channel"——**非 null**，每個 Channel 都有 app。
#
# ⚠️ **`app: App!` 與我方的 `app_installation_id` 可為 NULL 有落差**，理由登記在下面
#   `belongs_to :app_installation, optional: true` 的註釋。
#
# ## 刻意不建的官方欄（有官方定義、我方目前**沒有寫入者**）
#
# 建無人寫的欄正是 `publications.catalog_id` 空轉兩週的坑（S0 就是來收那個口的）
# ⇒ 一律等有寫入者再加：
#   - `name: String!`——🔴 **不建，且這是刻意的鐵律 7 判斷**：顯示名的權威已經在
#     `sales_catalogs.title`（本尊 `Publication.name` 已 deprecated → `Catalog.title`）。
#     再開一個 `channels.name` 就是同一件事的第三個產生處。
#   - `supportsFuturePublishing: Boolean!`——本尊 **`Publication` 與 `Channel` 兩邊都有**，
#     我方只在 `publications` 留一份（同上理由）。
#   - `accountId` / `accountName`（多帳號連線，決策文件 C-1；v1 無此流程）
#   - `resourceFeedback` / `activeRegions` / `markets` / `specificationHandle`
#     / `productsCount` / `hasCollection`（皆為讀取面衍生或未進射程）
#
# @see docs/plans/2026-08-26-S0-管道身分模型-決策文件.md §4 C-1、C-2
# @see docs/research/82-admin-channels.md §10.3
class Channel < ApplicationRecord
  # 本尊把 `Channel` 與 `AgenticChannel` 做成**兩個不同的 GraphQL 型別**
  # （`docs/research/82` §10.5）。我方先用一欄區分。
  # ⚠️ `AgenticChannel` 是否有獨立的 App／AppInstallation 實體＝**未取得**
  #   （決策文件 U-5）⇒ 這個二值是**我方的過渡表達**，不是照抄本尊的 enum。
  TYPES = %w[app agentic].freeze

  acts_as_tenant :shop

  belongs_to :publication, inverse_of: :channel

  # 🔴 `optional: true` 與本尊的 `Channel.app: App!`（非 null）有落差，理由：
  #   `82` §10.1 實測 **Agentic 不在已安裝管道清單裡卻出現在發布 modal**
  #   ⇒ 存在「沒有安裝實體的管道」這種形態。本尊用**另一個型別**（`AgenticChannel`）
  #   表達它，我方在型別實體性未取得（U-5）之前用同一張表 ＋ 可為 NULL 的安裝外鍵。
  #   ⚠️ **不得**把這個 NULL 讀成「本尊的 app 也可以是 NULL」——本尊那一欄是非 null 的。
  belongs_to :app_installation, optional: true, inverse_of: :channels

  validates :handle, presence: true, length: { maximum: 64 }
  validates :handle, uniqueness: { scope: :shop_id }
  validates :channel_type, inclusion: { in: TYPES }

  # 🔴 `channel_type = 'app'` 的管道**必須**有安裝實體。
  #   沒有這條，`app` 型管道可以在沒有 app 的情況下存在，而那與本尊的 `app: App!` 直接矛盾。
  validate :app_channel_requires_installation

  private

  def app_channel_requires_installation
    return unless channel_type == "app"
    return if app_installation_id.present?

    errors.add(:app_installation, "app 型管道必須綁一個 app 安裝（本尊 Channel.app 是非 null）")
  end
end
