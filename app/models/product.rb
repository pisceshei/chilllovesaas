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
  # 🔴 **刻意只提供集合，不提供具名 scope**（例如 `Product.purchasable`）。
  # 理由：13 §F1.2(d) 的 scope SQL 用 `product_publications` 與 `variant_publications`
  # 兩張**不存在的表**（我方落地的是多型的 `resource_publications`，見 88 號），
  # 而 `20260814200000` 的回填**一列 ProductVariant 都沒有**。
  #   - 照規格加上變體層 EXISTS ⇒ 全站每個商品都靜默變成不可購買；
  #   - 省略變體層 ⇒ 一個叫 `purchasable` 的 scope 只做了三層 AND 的第一層，**名字在說謊**。
  # 兩條都比「現在沒有這個 scope」更糟。待 63 §H.2 與 88 的模型收斂後再落地。
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
end
