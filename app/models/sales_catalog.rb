# 一個 publication 的「目錄」——本尊 `Catalog` interface 的我方對位。
#
# 發布模型是**三層 AND**（`docs/specs/88` §1，help 原文）：
#   Publishable（Product／Collection／ProductVariant）
#     × Publication（綁一個管道）
#     × **Catalog（本類別）**
# 本類別是第三層。它在 2026-08-26 之前**不存在**——`publications.catalog_id` 自
# `20260814200000` 起就有欄位，但無外鍵、無寫入者、值恆為 NULL ⇒ 第三層永遠是 no-op。
#
# 🔴 **為什麼叫 `SalesCatalog` 而不是本尊的 `Catalog`**：
#   本倉庫的 `Catalog` 常數**已被服務層命名空間佔用**——`Catalog::SaveProduct`／
#   `MediaSync`／`SaveCollection`／`CacheStamps`／`HandleChange`／`OptionValuesDigest`
#   等十餘個類掛在 `module Catalog` 之下，語義是「商家的**商品目錄**操作」。
#   本尊的 `Catalog` 則是「publication ＋ price list 的容器」——同一個字兩個意思。
#   宣告 `class Catalog < ApplicationRecord` 會讓那十餘個服務檔在載入時全部拋
#   `TypeError: Catalog is not a module`（2026-08-26 實測：8 個 spec 檔載入失敗）。
#   ⇒ 加 `Sales` 前綴把兩個概念分開。對外 GID Type 仍照鐵律 4 對齊本尊
#   （`AppCatalog`／`MarketCatalog`／`CompanyLocationCatalog`），那是序列化層的事。
#
# 🔴 這是業務資料，受 `acts_as_tenant` fail-closed 隔離（鐵律 2；G24 的豁免只給身分表）。
#
# ## 本尊實測形態（`docs/research/82` §9.5b／§10.3，兩次抓包）
#
# Online Store 與 Shop 兩個管道的 catalog 都是 `AppCatalog`，標題形如
# `Channel Catalog 209681744107 for Shop`，`status: "ACTIVE"`。
# ⇒ **每個 publication 都有一個 catalog**，不是選配。
#
# @see docs/specs/88-publication-model.md
# @see docs/plans/2026-08-26-S0-方案D-schema設計.md
# @see docs/research/82-admin-channels.md §9.5b、§10.3
class SalesCatalog < ApplicationRecord
  # 本尊 `CatalogType` 的我方對位。
  #
  # 🔴 **`none` 刻意不落庫**。本尊的 enum 有第四個值 `NONE`，但它的語義是
  #   「這個 publishable 不屬於任何 catalog」——那是**讀取時的一種結果**，
  #   不是一種 catalog 的種類。把它落成一列 `catalog_type = "none"` 的資料
  #   會讓「沒有 catalog」與「有一個叫 none 的 catalog」變成兩個無法區分的狀態。
  TYPES = %w[app market company_location].freeze

  # 本尊 `CatalogStatus` 恰三值。
  # ⚠️ ~~admin UI 只曝露 active／archived 兩個（`82` §9.5c 實測的表單沒有 draft），~~
  #   ~~`draft` 只在 API 層出現 ⇒ 我方保留三值但 UI 同樣只給兩個。~~
  # 🔴 **2026-08-26 更正（實測推翻，`docs/research/82` §12.5）**：原句把「**建立表單**只給兩個」
  #   的觀察寫成了「**admin UI** 只曝露兩個」的全稱，射程過寬。正確表述分兩處：
  #     - **catalog 建立表單**（`82` §9.5c）確實只給 active／archived；
  #     - **逐商品發布 modal 的 `Status` 篩選器**（`82` §12.5）**三個都給**——
  #       實測展開後恰為 `Active`／`Draft`／`Archived` 三個 checkbox ＋ 一個 `Clear`。
  #   ⇒ 我方保留三值是對的；**UI 該不該給 draft 要看是哪一個 UI**，
  #     建立表單不給、篩選器要給。
  STATUSES = %w[active archived draft].freeze

  acts_as_tenant :shop

  # 🔴 **沒有 `dependent:`**，這是刻意的。
  #   catalog 被 publication 指著（FK `fk_publications_sales_catalog_id`）⇒ 直接刪
  #   應該被資料庫擋下來，那正是我們要的行為：**沒有 catalog 的 publication
  #   ＝三層 AND 的第三層斷掉＝整個管道的商品靜默不可見**。
  #   寫 `dependent: :destroy` 會把 publication 一起刪掉（更糟）、
  #   寫 `dependent: :restrict_with_error` 則是把資料庫已經在做的事再做一次
  #   ——但它只擋 `catalog.destroy`，擋不住 `SalesCatalog.delete_all`，
  #   而 FK 兩者都擋。⇒ 讓 FK 當唯一防線，不製造「以為有兩道其實只有一道」的錯覺。
  #   整店刪除的順序由 `Shop` 的關聯宣告順序處理（見 `shop.rb`）。
  has_one :publication

  validates :title, presence: true, length: { maximum: 255 }
  validates :catalog_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  # 管道 catalog 的標題產生器。
  #
  # 🔴 **本尊的標題有固定格式**：`Channel Catalog {publicationId} for {ChannelName}`
  #   （`82` §10.3 抓包原文：`"Channel Catalog 209681744107 for Shop"`）。
  #   我方**不照抄這個格式**，理由是它把 publication 的數字 id 寫進顯示字串——
  #   而我方的 catalog 是**先於** publication 建立的（FK 方向決定順序），
  #   建立當下根本還沒有 publication id。硬要對齊就得建完 publication 再回寫標題，
  #   多一次 UPDATE 換一個**使用者看不到**的字串（本尊 admin UI 顯示的是管道名，
  #   不是 catalog 標題）。
  #   ⇒ 我方直接用管道名當標題。這是**登記在案的刻意分岔**，不是漏做。
  #
  # ⚠️ 若日後 admin UI 要曝露 catalog 標題（S10 的 catalog 管理頁），
  #   再回來決定要不要對齊格式——屆時 publication 已存在，回寫成本消失。
  #
  # @param channel_name [String] 管道顯示名，例如 "線上商店"
  # @return [String]
  # @see docs/research/82-admin-channels.md §10.3
  def self.channel_catalog_title(channel_name)
    channel_name
  end
end
