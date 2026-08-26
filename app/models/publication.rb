# 一個銷售管道在本店的發布容器（對應本尊的 `Publication`）。
#
# 發布模型是**三層 AND**（docs/specs/88 §1，help 原文）：
#   Publishable（Product／Collection／ProductVariant）
#     × Publication（本類別，綁一個管道）
#     × SalesCatalog（該管道的目錄；2026-08-26 S0 建）
# 三個條件**缺一不可上架**——「已發布到該管道」與「在該管道市場的目錄內」是兩件獨立的事。
#
# 🔴 這是業務資料，受 `acts_as_tenant` fail-closed 隔離（鐵律 2；G24 的豁免只給身分表）。
#
# @see docs/specs/88-publication-model.md
# @see docs/research/82-admin-channels.md §0.2
class Publication < ApplicationRecord
  # 本尊 `ResourceOperationStatus` 的我方對位——**恰三值，沒有 failed**
  # （官方 SDL：`CREATED` / `ACTIVE` / `COMPLETE`）。
  # 🔴 「沒有 failed」是刻意登記的事實：本尊的批量發布操作**不表達失敗態**，
  #   我方若自行加一個 `failed` 就與本尊分岔。⚠️ 本步只有欄位，狀態機屬 S1。
  OPERATION_STATUSES = %w[created active complete].freeze

  acts_as_tenant :shop

  # 🔴 **本尊每個 publication 都有 catalog**（`docs/research/82` §9.5b／§10.3 兩次抓包）。
  #   `optional: true` 是**過渡態**：既有資料由 `20260826062000` 回填，
  #   但兩支更早的 migration（20260814200000／20260815000010）在重跑舊庫時仍會先建
  #   publication ⇒ 現在轉必填會讓那條路徑炸。轉 NOT NULL 屬 S1（那時所有路徑都已對齊）。
  # ⚠️ 關聯名是 `sales_catalog` 不是 `catalog`——`Catalog` 常數已被服務層命名空間佔用，
  #   理由見 `app/models/sales_catalog.rb` 檔頭。
  belongs_to :sales_catalog, optional: true

  has_many :resource_publications, dependent: :destroy

  validates :name, :channel_handle, presence: true
  validates :channel_handle, uniqueness: { scope: :shop_id }
  validates :operation_status, inclusion: { in: OPERATION_STATUSES }, allow_nil: true

  # 🔴 顯示名的**權威來源是 `sales_catalog.title`**，不是 `publications.name`
  #   ——本尊 `Publication.name` 已 deprecated → `Catalog.title`（官方 deprecation 指向）。
  #   `name` 欄保留為 legacy（刪欄要改所有讀取端，屬 S1）。
  #   沒有 catalog 時退回 `name`，那是回填完成前的過渡態。
  #
  # @return [String]
  # @note 副作用：可能觸發一次 `sales_catalogs` 的 SELECT（未 preload 時）。
  def display_title
    sales_catalog&.title.presence || name
  end

  # 本管道是否有**進行中**的非同步發布操作。
  #
  # 🔴 本尊在進行中會**鎖住該 catalog 的逐商品發布切換**並顯示
  #   「Publishing for this catalog can't be changed while updates are in progress.」
  #   （`82` §9.5d 實測）。我方目前只記狀態、還沒有人消費它——
  #   消費者（寫入面的鎖）屬 S1／S5。
  #
  # @return [Boolean]
  def operation_in_progress?
    %w[created active].include?(operation_status)
  end

  # 本店預設的線上商店 publication。
  #
  # M1 階段只有這一個管道；建立商店時必須連帶建立它（見 88 §4）。
  #
  # 🔴 **handle 取自 `Shop::DEFAULT_CHANNEL_HANDLE`，不在這裡再寫一次字面量**
  # （2026-08-26 S0 修）。原本這裡硬寫 `"online_store"`，與 `Shop` 的常數**同值但兩個來源**
  # ⇒ 改了常數而沒改這裡，本方法就靜默回 `nil`，而 `nil` 的後果是
  # 「整店商品前台不可見且不拋任何錯」（`shop.rb` 的 `create_default_publication`
  # 註釋第 ③ 條已經記過這個症狀）。鐵律 7：同一個值只能有一個產生處。
  #
  # ⚠️ **本尊的 channel handle 不是全域常數**（`docs/research/82` §10.3 實測）：
  # Shop 管道的 `Channel.handle` 是 **`shop-72`**，帶每店產生的後綴。
  # 我方目前用固定 handle 是**簡化**，不是對齊——S0 的身分模型裁定會處理這件事。
  #
  # @return [Publication, nil] 線上商店管道；尚未建立時為 nil
  # @note 副作用：一次 tenant-scoped SELECT。
  # @see docs/specs/88-publication-model.md §4
  # @see docs/research/82-admin-channels.md §10.3
  def self.online_store
    find_by(channel_handle: Shop::DEFAULT_CHANNEL_HANDLE)
  end

  # 同 `.online_store`，但**沒有就炸**。
  #
  # 🔴 兩個方法並存是刻意的，因為呼叫端分成兩類：
  #   - **可以沒有前台**的（例如系列列表的「前台可見件數」——沒有管道就顯示 null＝不知道）
  #     ⇒ 用 `.online_store`，自己處理 nil；
  #   - **沒有就是資料損壞**的（例如發布寫入路徑）⇒ 用本方法，讓它大聲失敗。
  # 讓第二類呼叫端拿到 `nil` 是最糟的形態：`Product.purchasable(publication: nil)`
  # 會在 `publication.shop_id` 上炸成 `NoMethodError`，訊息完全指不出根因。
  #
  # @return [Publication]
  # @raise [ActiveRecord::RecordNotFound] 本店沒有線上商店管道
  # @note 副作用：一次 tenant-scoped SELECT。
  def self.online_store!
    online_store || raise(ActiveRecord::RecordNotFound,
      "本店沒有 #{Shop::DEFAULT_CHANNEL_HANDLE} publication——" \
      "建店流程應由 Shop#after_create 建立它（88 §4）。" \
      "缺了它，所有商品都不可能通過三層 AND 的第二層。")
  end
end
