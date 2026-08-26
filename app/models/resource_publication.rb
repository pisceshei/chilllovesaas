# Publishable 與 Publication 的發布關聯（對應本尊的 `ResourcePublication`）。
#
# 命名為 `resource_*` 而非 `product_*`：它是**多型**的——本尊的 Publishable 介面由
# Product、Collection、ProductVariant 三者實作（82 §0.2），叫 product_* 會讓後兩者
# 看起來像硬塞進來的。
#
# 🔴 `published_at` 的三種語義（88 §2.2）：
#   - NULL        ⇒ 尚未發布到本管道
#   - 過去時間    ⇒ 已發布
#   - **未來時間** ⇒ **排程發布**（future publishing）
#
# @see docs/specs/88-publication-model.md
class ResourcePublication < ApplicationRecord
  PUBLISHABLE_TYPES = %w[Product Collection ProductVariant].freeze

  acts_as_tenant :shop

  belongs_to :publication
  belongs_to :publishable, polymorphic: true

  validates :publishable_type, inclusion: { in: PUBLISHABLE_TYPES }
  validates :publishable_id, uniqueness: {
    scope: %i[shop_id publication_id publishable_type]
  }

  validate :publishable_belongs_to_same_shop
  validate :future_publishing_supported_by_channel
  validate :variant_cannot_be_scheduled

  # ── S2：三種狀態的 scope（對位本尊 V2 投影的 `onlyPublished` 參數）─────────────
  #
  # 🔴 **本尊的兩種讀出投影在「已排程未到點」這一格語義相反**，官方原文逐字：
  #   - `ResourcePublication`（V1）：`Whether the resource publication is published.
  #     **Also returns true if the resource publication is scheduled to be published.**
  #     If false, then the resource publication is neither published nor scheduled to be published.`
  #   - `ResourcePublicationV2`：`Whether the resource publication is published. If true,
  #     then the resource publication is published to the publication. **If false, then the
  #     resource publication is staged to be published to the publication.**`
  #   （<https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublication>
  #     與 `.../ResourcePublicationV2`，取證 2026-08-26）
  #
  # ⇒ 同一個布林在兩個投影上對「排程中」給出相反的答案。我方**只實作 V2 語義**
  #   （理由見 `Types::ResourcePublicationV2Type` 檔頭），本組 scope 就是它的資料面。
  #
  # ⚠️ 「相反」這兩個字是**由上面兩段原文導出的判斷**，不是官方原文——
  #   任何引用這個結論的地方都要一併附原文（鐵律 19.1）。

  # 已發布（到點）。
  scope :currently_published, ->(at: Time.current) {
    where.not(published_at: nil).where(published_at: ..at)
  }

  # 🔴 已排程但**尚未**到點＝本尊 V2 的 `isPublished == false`（`staged`）。
  # ⚠️ 官方在**欄位描述**用 `staged`、在**物件描述**用 `scheduled`，且從未把兩詞等同
  #   ⇒ 我方註釋兩詞並列，不合併成單一術語。
  scope :staged, ->(at: Time.current) { where(published_at: (at + 1.second)..) }

  # V2 的成員集合：已發布 ∪ 已排程。
  # 🔴 `published_at IS NULL` 的列**不在 V2 裡**——官方逐字
  #   `Unlike ResourcePublication, an instance of ResourcePublicationV2 can't be unpublished.
  #    It must either be published or scheduled to be published.`
  scope :published_or_staged, -> { where.not(published_at: nil) }

  # 「已發布」謂詞的**唯一產生處**（鐵律 7）——SQL 側與 Ruby 側都從這裡長出來。
  #
  # 🔴 2026-08-26 收斂（第二輪對抗審查 G29／P12-B13）：第 12 包初版讓
  # `ResourcePublication#published?`（Ruby）與 `Product.published_on`（SQL）
  # **各寫一份**同一條規則。那不是既有問題，是本包新增 `published_on` 時造成的分叉
  # ⇒ 屬鐵律 20.5 的「同一元件狀態矩陣」，本輪收斂。
  #
  # 語義：`published_at` 非 NULL **且**不在未來（未來時間＝排程發布，到點前不算上架）。
  PUBLISHED_SQL = "%<a>s.published_at IS NOT NULL AND %<a>s.published_at <= :at"

  # 可以放進 EXISTS 的發布目標。**鍵是封閉集合**，值全部是本檔的字面常數
  # ⇒ 下面的字串插值不可能被外部輸入影響（`fetch` 對未知鍵直接拋）。
  #
  # 命名：`{要找的 publishable 型別}_{它的 id 在外層 SQL 裡怎麼稱呼}`
  VISIBILITY_TARGETS = {
    # 商品自己（外層是 products 表）
    product: { type: "Product", id: "products.id" },
    # 系列自己（外層是 collections 表）
    collection: { type: "Collection", id: "collections.id" },
    # 變體自己（外層是 product_variants 表）
    variant: { type: "ProductVariant", id: "product_variants.id" },
    # 某商品底下的變體（外層已把 product_variants 別名成 pv）
    variant_of_pv: { type: "ProductVariant", id: "pv.id" },
    # 某成員商品（外層已把 products 別名成 p，例如系列成員數的子查詢）
    product_of_p: { type: "Product", id: "p.id" }
  }.freeze

  # 「這個 publishable 在該管道上、在該時點已發布」的 SQL `EXISTS` 片段。
  #
  # 產生的片段帶三個具名 bind：`:shop_id`／`:publication_id`／`:at`，
  # 由呼叫端在 `where` 一起提供。別名固定 `rp`——每個 EXISTS 是獨立的子查詢作用域，
  # 同名不衝突（實測：`Product.published_on` 的兩個 EXISTS 都用 `rp`）。
  #
  # 🔴 **這裡是正向 EXISTS，NULL 安全**：`published_at IS NULL` 的列單純不匹配。
  # 日後若要「未發布」的反向謂詞，**必須** `NOT COALESCE(<expr>, FALSE)`，
  # 不得直接對本片段取反——第 11 包在三值邏輯上踩過三次。
  #
  # @param target [Symbol] `VISIBILITY_TARGETS` 的鍵
  # @return [String] 可直接嵌進 `where` 的 SQL 片段
  # @raise [KeyError] target 不在封閉集合內
  def self.published_exists_sql(target)
    spec = VISIBILITY_TARGETS.fetch(target)

    <<~SQL.squish
      EXISTS (
        SELECT 1 FROM resource_publications rp
        WHERE rp.shop_id = :shop_id
          AND rp.publication_id = :publication_id
          AND rp.publishable_type = '#{spec[:type]}'
          AND rp.publishable_id = #{spec[:id]}
          AND #{format(PUBLISHED_SQL, a: 'rp')}
      )
    SQL
  end

  # 此關聯在指定時點是否算「已上架到本管道」。
  #
  # 🔴 注意這只是**三層 AND 的第二層**——完整的上架判定還要加上 catalog 條件（88 §1）。
  # 只用這個方法當「商品是否可購買」會漏掉市場目錄那一層。
  #
  # ⚠️ 這是 `PUBLISHED_SQL` 的 Ruby 對偶。兩者必須同義，
  # `spec/models/resource_publication_spec.rb` 有一格用**同一批時點**同時跑兩側比對，
  # 只改一邊會轉紅。
  #
  # @param at [Time] 判定時點，預設現在
  # @return [Boolean] 已發布且發布時間已到時為 true
  # @note 副作用：無。
  # @see docs/specs/88-publication-model.md §1
  def published?(at: Time.current)
    published_at.present? && published_at <= at
  end

  private

  # 🔴 多型關聯的租戶歸屬驗證——**`acts_as_tenant` 不做這件事，資料庫也不做**。
  #
  # 兩層都沒有人擋：
  #   1. gem 層：`acts_as_tenant-1.0.1/lib/acts_as_tenant/model_extensions.rb:57-62`
  #      把多型外鍵**明確排除**在歸屬驗證之外
  #      （`unless a == reflect_on_association(tenant) || polymorphic_foreign_keys.include?(...)`）；
  #   2. DB 層：多型欄位無法建外鍵，所以 `publication` 有複合外鍵、`publishable` 沒有。
  #
  # 🔴 **今天為什麼還沒出事，以及為什麼仍要加這一條**：
  # 常規請求路徑下，`belongs_to :publishable` 的存在性驗證會去載入該物件，
  # 而 Product／Collection／ProductVariant 都有 `acts_as_tenant` 的 default_scope
  # ⇒ 別家店的 id 載不出來 ⇒ 驗證以「must exist」失敗。
  # 但那是**偶然的副作用，不是明擋**，以下情況它全部失效：
  #   - `ActsAsTenant.without_tenant { ... }`（資料遷移、seeds、維運腳本）
  #   - 明確指定 `shop_id` 而非由 current_tenant 帶入
  #   - `insert_all` / `upsert_all`（**完全跳過 validation**——這一條連本方法都擋不住，
  #     見下方限制聲明）
  #   - 日後有人把這個關聯改成 `optional: true`
  #
  # 不擋的後果：帶著 A 店的 `shop_id`、`publishable_id` 指向 B 店的商品，
  # 這一列會存進去；之後 `dependent: :destroy` 與發布判定就跨到 B 店的資料上（鐵律 2）。
  #
  # ⚠️ **限制**：本驗證擋不住 `insert_all`／`upsert_all`（Rails 一律跳過 validation）。
  # 真正的底線防護要等多型改成「逐型別各一張關聯表」才拿得到 DB 外鍵——
  # 那是取捨，不在本 PR 範圍（88 §6）。
  def publishable_belongs_to_same_shop
    return if publishable_id.nil? || publishable_type.nil?
    return unless PUBLISHABLE_TYPES.include?(publishable_type)

    # 🔴 一定要 without_tenant 才問得到「它真正的 shop_id」——
    # 帶著 default_scope 查會被過濾成 nil，那樣就分不出「不存在」與「屬於別店」。
    owner_shop_id = ActsAsTenant.without_tenant do
      publishable_type.constantize.where(id: publishable_id).pick(:shop_id)
    end

    return if owner_shop_id.present? && owner_shop_id == shop_id

    errors.add(:publishable, "必須屬於同一間商店")
  end

  # 本尊：Shop 管道不支援排程發布（82 §0.2）——能力旗標在 publication 上。
  def future_publishing_supported_by_channel
    return if published_at.nil? || published_at <= Time.current
    return if publication.nil? || publication.supports_future_publishing

    errors.add(:published_at, "此銷售管道不支援排程發布")
  end

  # 本尊：不能為單一 variant 排程發布。
  #
  # 🔴 **2026-08-26 S2 改：判準從硬編字面值改成引 `config/limits.yml`**（鐵律 6）。
  #   原本硬編 `publishable_type == "ProductVariant"`，而正典是
  #   `sales_channels.future_publishing_unsupported: [variant, shop_channel]`——
  #   兩份清單。日後照正典加第三種不支援的資源，這條 validation **不會跟著變**，
  #   而且不會有任何測試轉紅（靜默分岔）。
  #   ⚠️ 該正典鍵在此之前是**零消費者**（正典宣告與實作不符，鐵律 19）；本方法是它的第一個消費者。
  #
  # 官方依據（help，取證 2026-08-26）：`You can't set a future publishing date for
  # individual product variants.`
  # （<https://help.shopify.com/en/manual/shopify-admin/productivity-tools/future-publishing>）
  #
  # ⚠️ **與 `docs/research/90` 的 V-4 字面不符，本輪維持現行**：V-4 寫「variant 不得排程發布
  #   （**publishDate 必須為空**）」，而本方法只擋**未來**時間、允許 variant 帶過去時間的
  #   `published_at`——那正是 `Publications::Materialize` 的既有寫法（它對 variant 也寫
  #   `published_at: at`）。照 V-4 字面收緊會打爛既有生產者。已登記 `docs/specs/91` §3.21。
  def variant_cannot_be_scheduled
    return unless unschedulable_publishable_type?
    return if published_at.nil? || published_at <= Time.current

    errors.add(:published_at, "不支援為單一子類選項排程發布")
  end

  # `publishable_type`（駝峰）是否落在正典的「不支援排程」清單（底線小寫）裡。
  #
  # 🔴 兩邊的命名慣例不同：limits 用 `variant`，model 用 `ProductVariant`
  #   ⇒ 這裡做一次明確的對照，**不用 `underscore` 之類的字串魔法**——
  #   `ProductVariant.underscore` 是 `product_variant` 不是 `variant`，
  #   靠推導會靜默對不上而且沒有任何測試會紅。
  #
  # @return [Boolean]
  UNSCHEDULABLE_LIMIT_KEYS = { "ProductVariant" => "variant" }.freeze

  def unschedulable_publishable_type?
    key = UNSCHEDULABLE_LIMIT_KEYS[publishable_type]
    return false if key.nil?

    Limits.fetch(:sales_channels, :future_publishing_unsupported).include?(key)
  end
end
