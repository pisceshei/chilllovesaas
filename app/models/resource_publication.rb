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

  # 此關聯在指定時點是否算「已上架到本管道」。
  #
  # 🔴 注意這只是**三層 AND 的第二層**——完整的上架判定還要加上 catalog 條件（88 §1）。
  # 只用這個方法當「商品是否可購買」會漏掉市場目錄那一層。
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

  # 本尊：不能為單一 variant 排程發布（82 §0.2）。
  def variant_cannot_be_scheduled
    return unless publishable_type == "ProductVariant"
    return if published_at.nil? || published_at <= Time.current

    errors.add(:published_at, "不支援為單一子類選項排程發布")
  end
end
