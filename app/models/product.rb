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

  has_many :product_variants, dependent: :destroy
  # 多型：商品可獨立發布到各管道（docs/specs/88）。
  has_many :resource_publications, as: :publishable, dependent: :destroy

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
