# 透過 Admin GraphQL API 公開的 Shop-scoped 商品 model。
#
# `acts_as_tenant` fail-closed 限制所有預設 query/write 在目前 Shop；API
# resolver 仍加明確 shop_id 作 defense in depth。見 docs/specs/12 F4。
class Product < ApplicationRecord
  # 商品狀態是**四**態，不是三態（`docs/specs/13` §F1.2；出處 shopify.dev 的
  # ProductStatus enum 與 unlisted-products 兩頁）。
  #
  # 🔴 `UNLISTED` ＝**可購買但不可被發現**。它的存在本身就證明「可購買」與
  # 「可被發現」是**兩個獨立維度**——三態時兩維完全同步，所以一個 `published`
  # 布林兼管兩件事剛好不出錯；補上 UNLISTED 必定撞牆：要嘛它完全買不到
  # （商家拿直接連結給客人卻結不了帳），要嘛它出現在搜尋與 sitemap 裡（SEO 事故）。
  #
  # 🔴 值域來自 `config/limits.yml`（鐵律 6），不在此硬編——DB 端是 `varchar(32)`
  # 無 CHECK constraint，若這裡與 limits.yml 各寫一份，漂移不會有任何跡象。
  STATUSES = Limits.enum(:product, :status_values).map(&:downcase).freeze

  # 兩個獨立維度的狀態集合（真值表見 13 §F1.2）。
  #
  # 🔴 **2026-08-26 起有具名 scope 了**（`purchasable`／`discoverable`，見本檔下方）。
  #
  # 原本刻意不提供，理由**當時完全成立、現在被解除了**，兩半都記在這裡：
  #   - 13 §F1.2(d) 的 scope SQL 用 `product_publications` 與 `variant_publications`
  #     兩張**不存在的表**（我方落地的是多型的 `resource_publications`，見 88 號）
  #     ⇒ 這一半靠改寫 SQL 對到實際表名即解（見 `published_on`）；
  #   - 🔴 而真正卡住的是另一半：**`20260814200000` 的回填一列 ProductVariant 都沒有，
  #     且倉庫裡沒有任何程式碼會建立發布列。** 在那個狀態下：
  #       ①照規格加上變體層 EXISTS ⇒ 全站每個商品都**靜默**變成不可購買；
  #       ②省略變體層 ⇒ 一個叫 `purchasable` 的 scope 只做了三層 AND 的第一層，名字在說謊。
  #     兩條都比「沒有這個 scope」更糟，所以當時的決定是**等寫入端補上再開讀取端**。
  #
  # 解除的條件已滿足：`Publications::Materialize` ＋ 三個 `after_create` ＋ 回填 migration
  # 讓每個 Product／ProductVariant／Collection 都恆有發布列（第 12 包）。
  # 🔴 **順序不可倒**——先開讀取面再補寫入端，就是上面第 ① 條那個全站靜默下架。
  PURCHASABLE_STATUSES = Limits.enum(:product, :purchasable_statuses).map(&:downcase).freeze
  DISCOVERABLE_STATUSES = Limits.enum(:product, :discoverable_statuses).map(&:downcase).freeze

  acts_as_tenant :shop

  # 🔴 **宣告順序就是刪除順序**（`dependent` 是按宣告順序註冊成 `before_destroy` 的）。
  #    `product_variants` 必須排在 `product_options` **之前**：join 表
  #    (`product_variant_option_values`) 同時被兩者的 `dependent: :destroy` 涵蓋，
  #    但 `option_values` 對 join 列是 `restrict_with_error`
  #    ⇒ 先刪變體（連帶清掉它的 join 列），選項那一側才刪得動。
  #    順序反過來 ⇒ `OptionValue` 的 restrict 會擋住，而錯誤訊息只會說
  #    「無法刪除選項值」，看不出真正的原因是刪除順序。
  has_many :product_variants, dependent: :destroy
  # D12：商品的選項。**2026-08-16 補**（PR #38 Codex review）——
  # 🔴 建了 `ProductOption` 卻沒在這裡宣告關聯，`fk_product_options_product_id`
  #    會讓**任何有選項的商品永遠刪不掉**，而且沒有任何既有測試會紅
  #    （D12 之前 `product_options` 表根本沒有寫入路徑）。
  #    ⚠️ 這與 `docs/specs/88` §4 那個 `Shop#publications` 的教訓是同一型：
  #    **新增一張有外鍵指回來的表時，父表的關聯宣告要一起補**。
  has_many :product_options, dependent: :destroy
  # 媒體（第 26 包接讀取面；寫入端＝第 27 包 productCreateMedia）。
  # dependent: :destroy——刪商品連動刪媒體列；blob 的清掃走第 28 包引用計數
  # （13 §F3 坑「刪商品要連動清 blob」，file_usages 是那個計數的唯一來源）。
  # 🔴 class_name 必填：Rails 把 `media` 單數化成 `Medium`（實測 NameError
  #    "Missing model class Medium"）——model 名是 `Media`，不跟著改。
  has_many :media, class_name: "Media", dependent: :destroy, inverse_of: :product
  # 多型：商品可獨立發布到各管道（docs/specs/88）。
  has_many :resource_publications, as: :publishable, dependent: :destroy
  # 自訂運送設定檔歸屬（結帳線第二包）。🔴 nil＝General 補集（85 §2），所以
  # optional 是語義不是偷懶；刪 profile 由 DB FK `on_delete: :nullify` 回落 General。
  belongs_to :shipping_profile, optional: true

  # 建立當下即物化發布列（本尊實測 82 §8.4①：新商品存檔後預設變體即有全部管道的列）。
  #
  # 🔴 掛 model callback 而不是寫在 `Catalog::SaveProduct` 裡，理由與
  # `Shop#after_create :create_default_publication` 完全相同（見該處註釋）：
  # callback **涵蓋每一條建立路徑**（GraphQL、seeds、factory、rake、日後的匯入器），
  # service 只涵蓋 GraphQL 那一條。缺列的症狀是「商品在前台看不到」而非拋錯，
  # 所以漏掉一條路徑不會有人發現。
  #
  # ⚠️ **`insert_all`／`upsert_all` 一律繞過本 callback**——那條路徑目前沒有防護。
  # 匯入器（第 20+ 包）若走批量寫入，匯進來的商品會全部沒有發布列
  # ⇒ 前台全部看不到。已登記於 `docs/dev/m2-publication-model.md` 的消費者影響圖。
  after_create :materialize_publications

  # 商品列表的庫存合計：**相關子查詢一次撈完**（與 Collection::MEMBER_COUNT_SELECT 同構，
  # N+1 的理由同 84 §2 那次——列表上限 250，逐列 SUM 就是單一請求 250 次 DB）。
  # 🔴 鐵律 7（數字同源）：/admin/inventory（第 18 包）與本欄必須同一份算式——
  #    到時把這段抽成共用 scope，不得另寫一份 SUM。
  # 🔴 SUM 只計 tracked=1 的品項；全部未追蹤 ⇒ NULL（GraphQL null ⇒ UI「未追蹤」）。
  #    回 0 是在說「有追蹤而且是零」，與「沒在追蹤」是兩個真相。
  TOTAL_INVENTORY_SELECT = <<~SQL.squish.freeze
    (SELECT SUM(il.available)
       FROM inventory_levels il
       JOIN inventory_items ii
         ON ii.shop_id = il.shop_id AND ii.id = il.inventory_item_id
       JOIN product_variants pv
         ON pv.shop_id = ii.shop_id AND pv.id = ii.product_variant_id
      WHERE pv.shop_id = products.shop_id
        AND pv.product_id = products.id
        AND ii.tracked = TRUE) AS total_inventory_sum
  SQL

  validates :title, :handle, :status, presence: true
  validates :handle, uniqueness: { scope: :shop_id, case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  # 依狀態集合過濾的**單一產生器**（鐵律 7：同一個條件只能有一個產生處）。
  #
  # 為什麼是產生器而不是兩個 scope：兩個 scope 會變成兩份複製貼上的 SQL，
  # 而它們遲早要各自補上 publication／catalog 條件——那時兩份會分岔。
  #
  # @param statuses [Array<String>] 小寫狀態字串集合，通常傳
  #   `PURCHASABLE_STATUSES` 或 `DISCOVERABLE_STATUSES`
  # @param shop_id [Integer] 明確的租戶 id（defense in depth；`acts_as_tenant` 已有
  #   default scope，這裡再帶一次的慣例與本檔檔頭一致）
  # @return [ActiveRecord::Relation] 該租戶內狀態落在集合中的商品
  # @note 副作用：無；只組 relation，不執行查詢。
  # @note 🔴 這**不是**「可購買」的完整判準——完整判準是 Publishable × Publication ×
  #   Catalog 三層 AND（88 §1）。本方法只做第一層（狀態），呼叫端不得把它當成完整判準。
  # @see docs/specs/13-spec-products-inventory-media.md §F1.2
  def self.with_status_set(statuses, shop_id:)
    where(shop_id:, status: statuses)
  end

  # 「在這個管道上可購買」——狀態層 ∧ 商品發布層 ∧ 變體發布層。
  #
  # 🔴 **管道是必填參數，沒有「任一管道」的版本**。買家面的問題永遠是
  # 「這個商品在**我正在逛的這個店面**買不買得到」，不是「在某個管道買得到」。
  # v1 只有 `online_store` 一個管道，呼叫端傳 `Publication.online_store`；
  # 寫成「任一管道」現在也會過，但等第二個管道出現時語義會**靜默**變錯
  # （POS 專屬商品開始出現在線上商店的搜尋結果裡）。
  #
  # @param publication [Publication] 目標管道
  # @param at [Time] 判定時點（排程發布：`published_at` 在未來者尚未上架）
  # @return [ActiveRecord::Relation]
  # @note 副作用：無；只組 relation。
  # @note 🔴 **第三層 catalog 不在這裡**（88 §3.2 裁定延後到 M5）。完整判準是三層 AND，
  #   本方法做前兩層。catalog 是讀取時的過濾，補上它是在這個 relation 後面再加條件。
  # @see docs/plans/2026-08-26-第12包執行規格.md §2.3
  def self.purchasable(publication:, at: Time.current)
    with_status_set(PURCHASABLE_STATUSES, shop_id: publication.shop_id)
      .published_on(publication, at:)
  end

  # 「在這個管道上可被發現」（搜尋、系列、推薦、sitemap、feed）。
  #
  # 🔴 **恆等不變量 `discoverable ⊆ purchasable` 在這裡是定理，不是測試項**——
  # 因為本方法**由 `purchasable` 導出**再收窄狀態集合，而
  # `DISCOVERABLE_STATUSES ⊆ PURCHASABLE_STATUSES`（`config/limits.yml` 的
  # `discoverable_subset_of_purchasable: true` 是該包含關係的正典）。
  #
  # 若改寫成兩份各自獨立的 SQL，不變量就退化成「要靠測試盯著別漂移」的性質——
  # 而漂移的後果是把買家從搜尋結果送進一個買不了的頁面（soft-404）。
  #
  # @see docs/specs/13-spec-products-inventory-media.md §F1.2
  def self.discoverable(publication:, at: Time.current)
    purchasable(publication:, at:).where(status: DISCOVERABLE_STATUSES)
  end

  # 發布層：商品自己已發布到該管道 **∧** 至少有一個變體已發布到該管道。
  #
  # 🔴 **兩個 EXISTS 缺一不可**，因為本尊的三層 AND 裡 `ProductVariant` 自己就是一個
  # Publishable（82 §0.2／§8.2 實測：每個變體都有自己的發布列，且與商品層**互不連動**
  # ——商品層取消發布某管道後，變體層的列原封不動，82 §8.4③）。
  # 只看商品層 ⇒ 一個所有變體都下架的商品仍會被判成可購買，前台點進去買不了。
  #
  # 🔴 **NULL 在這裡是安全的**（與第 11 包踩了三次的三值邏輯坑相反）：
  # 這裡是**正向** EXISTS，`published_at IS NULL` 的列單純不匹配即可。
  # 只有把它寫成 `NOT EXISTS` 或 `NOT (...)` 時，NULL 才會讓整個謂詞變成 UNKNOWN
  # 而靜默漏掉整批列。**日後若要加「未發布」的反向 scope，必須用
  # `NOT COALESCE(<expr>, FALSE)`**，不能直接對這段取反。
  #
  # ⚠️ **2026-08-26 收斂**：EXISTS 片段本身已抽到
  # `ResourcePublication.published_exists_sql`（謂詞的唯一產生處，鐵律 7），
  # 本常數只負責「商品層 ∧ 變體層」這個**組合**。
  #
  # 🔴 **在類別載入時就組好並凍結**，不在每次呼叫時插值：
  #   ①片段全部來自 `ResourcePublication::VISIBILITY_TARGETS` 這個封閉常數，
  #     沒有任何外部輸入進得來；
  #   ②組好之後呼叫端只做 `sanitize_sql_array` 的具名 bind 代入
  #     （與 `MEMBER_COUNT_SELECT` 同一個既有形態），Brakeman 才追得動。
  PUBLISHED_ON_SQL = <<~SQL.squish.freeze
    #{ResourcePublication.published_exists_sql(:product)}
    AND EXISTS (
      SELECT 1 FROM product_variants pv
      WHERE pv.shop_id = :shop_id AND pv.product_id = products.id
        AND #{ResourcePublication.published_exists_sql(:variant_of_pv)}
    )
  SQL

  # @api private 由 `purchasable` 使用；不建議直接呼叫（它不含狀態層）
  def self.published_on(publication, at: Time.current)
    where(Arel.sql(sanitize_sql_array([
      PUBLISHED_ON_SQL,
      { shop_id: publication.shop_id, publication_id: publication.id, at: }
    ])))
  end

  # 把 `publications_updated_at`（cache stamp）推到 `at`。
  #
  # 🔴 **不得動 `lock_version`**，而 `update_all` 的 **hash 形式會自動遞增它**
  # （Rails 對啟用樂觀鎖的 model 如此，實測：發布列一建立，商家手上的
  # `product` 物件立刻 `StaleObjectError`）。
  # 兩者的用途完全不同：
  #   - `lock_version`＝**使用者面**的全樹樂觀鎖（含譯文），用來擋兩個人同時編輯；
  #   - `publications_updated_at`＝**系統面**的 cache stamp，用來讓前台快取失效。
  # 讓系統戳去推使用者鎖 ⇒ 每次發布變動都會把商家**開著的編輯表單作廢**，
  # 而商家什麼都沒做錯。
  # ⇒ 改用 `update_all` 的**字串形式**（不走那段樂觀鎖邏輯），只動那一欄。
  #
  # @param shop_id [Integer] 明確帶租戶（defense in depth）
  # @param id [Integer] 商品 id
  # @param at [Time]
  # @return [Integer] 受影響列數
  # @note 副作用：對 `products` 做一次 UPDATE。不觸發 callback／validation。
  # @see docs/dev/m2-publication-model.md §8（P12-B11 的結案）
  def self.bump_publications_stamp!(shop_id:, id:, at:)
    where(shop_id:, id:)
      .update_all(sanitize_sql_array([ "publications_updated_at = ?", at ]))
  end

  private

  # @see Publications::Materialize
  def materialize_publications
    Publications::Materialize.for(self)
  end
end
