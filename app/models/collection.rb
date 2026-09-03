# 商品系列（collection）。
#
# ⚠️ **M1 尚未展開**：本類別目前只有租戶隔離與最基本的驗證。
# 手動/智慧系列的規則引擎、排序、成員關聯屬 M1 的主體工作。
# 🔴 建立式的概念差已登記（71-R8-V4）：本尊 2026 改為「來源」卡（新增條件與新增商品同卡混用
# ＋排除 negative 條件＋多來源組），與我方 13-F4 的「手動/智慧二分不可互轉」不同——**未裁定**。
#
# 為什麼現在就建：`ResourcePublication` 的 `publishable` 是多型關聯，
# Publishable 介面由 Product／Collection／ProductVariant 三者實作（82 §0.2）。
#
# @see docs/specs/88-publication-model.md
class Collection < ApplicationRecord
  acts_as_tenant :shop

  has_many :resource_publications, as: :publishable, dependent: :destroy

  # 系列出生即物化發布列。Collection 與 Product／ProductVariant 同為本尊 `Publishable`
  # 介面的實作者（82 §0.2），走同一支生產者、同一條規則。
  # 掛 callback 而非 service 的理由見 `Publications::Materialize` 檔頭。
  after_create :materialize_publications
  # 手動系列的成員；智慧系列不用這個關聯（成員是規則的函數，見 CollectionProduct）。
  has_many :collection_products, dependent: :delete_all
  has_many :products, through: :collection_products
  has_many :collection_rules, dependent: :delete_all

  validates :title, :handle, presence: true
  # DB 已有 uq_collections_handle (shop_id, handle) 唯一索引；沒有 model validation
  # 的話重複 handle 會拋 RecordNotUnique 而不是乾淨的驗證錯誤，
  # 與 Product 的處理不一致（PR #24 的 Claude 驗收 🟡 建議）。
  validates :handle, uniqueness: { scope: :shop_id, case_sensitive: false }

  # 兩種系列型別（13 §F4；71-R8-V4 的「來源」概念差仍待裁定，v1 維持二分）。
  TYPES = %w[manual smart].freeze
  # 列表頁的成員數：**用相關子查詢一次撈完**，不是每列一次 COUNT。
  # 🔴 N+1 在這裡不是效能潔癖——列表上限是 250（`limits.yml`），
  # 逐列 COUNT 就是單一請求打 250 次 DB，而列表正是最常開的頁。
  # 單筆讀取（編輯頁）沒有這個 select，`Types::CollectionType` 會退回逐筆 COUNT。
  # 🔴 型別分流（第 11 包收斂三處成員數）：手動＝collection_products；
  #   智慧＝collection_memberships（物化，13 §F4.6-1）。兩張表兩個真相的邊界
  #   就在 collection_type 上——CASE 讓一條 select 同時答對兩型。
  MEMBER_COUNT_SELECT = <<~SQL.squish.freeze
    (CASE WHEN collections.collection_type = 'smart' THEN
      (SELECT COUNT(*) FROM collection_memberships cm
        WHERE cm.shop_id = collections.shop_id
          AND cm.collection_id = collections.id)
     ELSE
      (SELECT COUNT(*) FROM collection_products cp
        WHERE cp.shop_id = collections.shop_id
          AND cp.collection_id = collections.id)
     END) AS member_count
  SQL

  # E8b：`most_relevant`＝本尊 2026 admin 自動系列的「Default sort: Most relevant」（hoko.vip 首頁系列，admin 實測 2026-09-04；
  # 前台 `collection.default_sort_by` 出 `most-relevant`）。官方 objects/collection 的 default_sort_by 值表未列它（external-facts §G17 追加）；
  # 排序語義未取得（91 §3.75b V），前台以上新代位。
  SORT_ORDERS = %w[manual best_selling title_asc title_desc price_asc price_desc created_desc created_asc most_relevant].freeze

  validates :collection_type, inclusion: { in: TYPES }
  validates :sort_order, inclusion: { in: SORT_ORDERS }

  scope :manual, -> { where(collection_type: "manual") }

  # 「這個系列在該管道上可見」——**系列只有一層**。
  #
  # 🔴 與商品不同，系列**沒有 status 欄**，也**沒有變體層**
  # ⇒ 它的可見性判定就是 publication 那一層，沒有別的。
  #
  # 🔴 而且本尊的系列**只能發布到 APP 型 catalog**（官方 `resourcePublicationsV2` 逐字：
  # 「`Collection` only supports publications to `APP` catalog types.」），
  # 後台也照這個實作：系列的發布控件是一個**只有銷售管道的輕量 popover**，
  # 沒有商品那個 modal 的 `Agentic` 與 `Catalogs` 兩組（`docs/research/82` §9.3／§9.10 實測）。
  # ⇒ 日後補第三層時，**系列不得接 market／B2B catalog**。
  #
  # @param publication [Publication] 目標管道
  # @param at [Time] 判定時點（排程發布：`published_at` 在未來者尚未上架）
  # @return [ActiveRecord::Relation]
  # @note 副作用：無；只組 relation。
  # @see docs/research/82-admin-channels.md §9.10
  # 組合在類別載入時完成並凍結（理由同 `Product::PUBLISHED_ON_SQL`）。
  PUBLISHED_ON_SQL = ResourcePublication.published_exists_sql(:collection).freeze

  def self.published_on(publication, at: Time.current)
    where(shop_id: publication.shop_id)
      .where(Arel.sql(sanitize_sql_array([
        PUBLISHED_ON_SQL,
        { shop_id: publication.shop_id, publication_id: publication.id, at: }
      ])))
  end

  # 系列列表的第二個數字：**前台可見的成員數**。
  #
  # 🔴 這是第 12 包在權威計畫表（`docs/plans/2026-08-24-三方向執行順序.md` §3 第 12 列）
  # 上「部署後看得到什麼」欄的**逐字交付**：
  #   > 系列列表出現「後台 N 件（前台可見 M 件）」兩個數字
  # 初版只交付了讀取面 scope、零消費者 ⇒ 部署後其實什麼都看不到（第二輪對抗審查 §3.1③）。
  #
  # 🔴 **判準是 `discoverable` 不是 `purchasable`**，依據是本尊對 UNLISTED 的官方定義：
  #   > An unlisted product doesn't display in Shopify-powered collection pages,
  #   > search results including predictive search, or product recommendations.
  # ⇒ Unlisted 商品**可購買但不出現在系列頁**，所以系列的「前台可見」要用可發現那一維。
  #
  # 🔴 **與 `MEMBER_COUNT_SELECT` 同構且同源**：一樣走相關子查詢（列表上限 250，
  # 逐列 COUNT ＝ 單一請求打 250 次 DB）、一樣用 `collection_type` 的 CASE 分流
  # （手動＝`collection_products`／智慧＝`collection_memberships`）。
  # 兩個數字**共用同一個成員定義**，只差在多套一層可見性——這是鐵律 7 要的形態。
  #
  # @param publication [Publication] 用哪個管道判定「前台」。v1 傳 `Publication.online_store`
  # @param at [Time] 判定時點
  # @return [Array(String, Hash)] `select` 用的 SQL 片段與具名 bind
  # @note 副作用：無。
  # @see docs/dev/m2-publication-model.md §5
  def self.visible_member_count_select(publication, at: Time.current)
    # 一個成員商品「在前台可見」＝狀態可發現 ∧ 商品層已發布 ∧ 至少一個變體已發布。
    # 三個條件與 `Product.discoverable` **同一組謂詞**（EXISTS 片段來自
    # `ResourcePublication.published_exists_sql`，狀態集合來自 `Product::DISCOVERABLE_STATUSES`）。
    member_visible = <<~SQL.squish
      p.status IN (:discoverable_statuses)
      AND #{ResourcePublication.published_exists_sql(:product_of_p)}
      AND EXISTS (
        SELECT 1 FROM product_variants pv
        WHERE pv.shop_id = p.shop_id AND pv.product_id = p.id
          AND #{ResourcePublication.published_exists_sql(:variant_of_pv)}
      )
    SQL

    sql = <<~SQL.squish
      (CASE WHEN collections.collection_type = 'smart' THEN
        (SELECT COUNT(*) FROM collection_memberships cm
           JOIN products p ON p.shop_id = cm.shop_id AND p.id = cm.product_id
          WHERE cm.shop_id = collections.shop_id
            AND cm.collection_id = collections.id
            AND #{member_visible})
       ELSE
        (SELECT COUNT(*) FROM collection_products cp
           JOIN products p ON p.shop_id = cp.shop_id AND p.id = cp.product_id
          WHERE cp.shop_id = collections.shop_id
            AND cp.collection_id = collections.id
            AND #{member_visible})
       END) AS visible_member_count
    SQL

    [ sql, { shop_id: publication.shop_id, publication_id: publication.id, at:,
             discoverable_statuses: Product::DISCOVERABLE_STATUSES } ]
  end

  # 列表用：一次帶上「後台 N 件」與「前台可見 M 件」兩個數字。
  #
  # @param publication [Publication, nil] nil ⇒ 只帶 `member_count`（沒有管道就沒有前台）
  # @return [ActiveRecord::Relation]
  # @note 副作用：無；只組 relation。
  def self.with_member_counts(publication: nil, at: Time.current)
    base = select(arel_table[Arel.star], Arel.sql(MEMBER_COUNT_SELECT))
    return base if publication.nil?

    sql, binds = visible_member_count_select(publication, at:)
    base.select(Arel.sql(sanitize_sql_array([ sql, binds ])))
  end

  private

  # @see Publications::Materialize
  def materialize_publications
    Publications::Materialize.for(self)
  end
end
