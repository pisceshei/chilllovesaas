# 商品的子類選項（variant）。
#
# ⚠️ **M1 尚未展開**：本類別目前只有租戶隔離、關聯與最基本的驗證。
# 變體 diff 更新、價格/成本、庫存連動、選項組合等屬 M1 商品線的主體工作
# （HANDOFF §5：「Products CRUD＋變體 diff 更新＋媒體＋系列＋庫存 ledger」）。
#
# 為什麼現在就建：`ResourcePublication` 的 `publishable` 是**多型**關聯，
# 而本尊的 Publishable 介面由 Product／Collection／ProductVariant 三者實作
# （docs/research/82 §0.2）——三個類別缺一個，多型關聯就無法驗證。
#
# @see docs/specs/88-publication-model.md
class ProductVariant < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  has_many :resource_publications, as: :publishable, dependent: :destroy

  # D12：變體的選項座標。`dependent: :destroy`——座標是變體的組成部分，變體沒了就沒有意義。
  has_many :product_variant_option_values, dependent: :destroy
  has_many :option_values, through: :product_variant_option_values

  validates :title, presence: true

  # 🔴 digest 一律由 join 列算出來，**不接受呼叫端指定**。
  # 允許外部塞值 ＝ 允許 join 列與 digest 不一致，而唯一索引只認 digest。
  before_validation :recompute_option_values_digest

  validates :option_values_digest, presence: true,
    format: { with: /\A[0-9a-f]{40}\z/,
              message: "必須是 40 字元小寫 hex（由 Catalog::OptionValuesDigest 產生）" }

  # 🔴 **座標必須「商品的每個選項恰好一個值」**（2026-08-16，PR #38 Codex review）。
  #
  # DB 層擋得住的只有「**至多**一個」（`uq_pvov_variant_option`）與「值屬於該選項」
  # （`fk_pvov_value`）——**擋不住「少給」**。於是在一個已經有選項的商品上：
  #   - 完全不給座標 ⇒ 被當成合法的 `NO_OPTIONS`（那是**無選項商品**才對的狀態）；
  #   - 只給三個選項中的兩個 ⇒ 也照樣存得進去。
  # ⇒ 前台的選項矩陣會出現點不到的組合，而 `selectedOptions` 序列化出去是殘缺的。
  #
  # ⚠️ **這條只能在 model 層擋**：MySQL 的 CHECK 不能跨表（子查詢 ⇒ ERROR 3815），
  #    而「恰好等於另一張表的某個集合」不是任何單一索引表達得了的約束。
  #    ⇒ 它是**唯一**的防線，`insert_all`／`upsert_all` 繞過它時沒有第二道。
  validate :option_coordinates_cover_every_product_option

  # @return [void]
  # @note 副作用：可能加入 `:product_variant_option_values` 的錯誤。
  def option_coordinates_cover_every_product_option
    return if product.nil?

    expected = product.product_options.pluck(:id).to_set
    actual = product_variant_option_values.map(&:product_option_id).to_set
    return if expected == actual

    missing = expected - actual
    extra = actual - expected
    errors.add(:product_variant_option_values,
      "必須對商品的每個選項各給恰好一個值" \
      "#{missing.any? ? "（缺：#{missing.to_a.sort.join(', ')}）" : ''}" \
      "#{extra.any? ? "（多：#{extra.to_a.sort.join(', ')}）" : ''}")
  end

  # 依目前的 join 列重算 digest。
  #
  # 🔴 **無 join 列 ⇒ `NO_OPTIONS`**（空集合的 SHA1），那正是本尊「Default Title」
  # 那顆隱含變體的座標。它是合法狀態，不是「還沒填」。
  #
  # ⚠️ **重算必須與 join 列的 INSERT/UPDATE/DELETE 在同一個 transaction 內**。
  # 這個 callback 只覆蓋「透過本 model 存檔」的路徑；直接操作 join 表之後
  # **必須自己再存一次變體**（或呼叫本方法），否則 digest 會落後。
  # 🔴 `insert_all`／`upsert_all` 一律繞過本 callback——那條路徑目前沒有防護，
  #    而 DB 的 `option_values_digest` 是 `null: false` 且**刻意不給 default**，
  #    所以那種寫法會**大聲失敗**而不是靜默寫進假 digest。這是刻意的。
  #
  # @return [String] 重算後的 digest
  # @note 副作用：改寫 `option_values_digest` 屬性（不存檔）。
  # @see docs/DECISIONS.md D12
  def recompute_option_values_digest
    # 🔴 **已持久化的變體一律重讀 DB，不吃關聯快取**（2026-08-16，PR #38 Codex review）。
    #    寫入 service 的典型形態是：先讀變體（關聯被載入並快取）→ 直接
    #    `ProductVariantOptionValue.create!`／`destroy` 動 join 列 → 再 `variant.save!`。
    #    此時 `product_variant_option_values` 回的是**載入當下的快照**，不是現在的 DB 內容
    #    ⇒ digest **算出來是舊的**，而唯一索引只認 digest
    #    ⇒ 要嘛放進重複座標、要嘛擋掉合法座標，**兩種都不會有錯誤訊息指向真正的原因**。
    # ⚠️ `reset` 的代價是每次存檔多一次查詢；相對於「digest 與 join 列不一致」這種
    #    查不出來的錯，這個代價可以接受。
    # 🔴 新建的變體（尚未有 id）**不能** reset——那會清掉呼叫端剛用
    #    `variant.product_variant_option_values.build(...)` 掛上去、還沒存檔的列。
    association = product_variant_option_values
    association.reset if persisted?

    pairs = association.map { |row| [ row.product_option_id, row.option_value_id ] }
    self.option_values_digest = Catalog::OptionValuesDigest.call(pairs)
  end
end
