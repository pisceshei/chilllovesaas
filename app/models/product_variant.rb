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
    pairs = product_variant_option_values.map { |row| [ row.product_option_id, row.option_value_id ] }
    self.option_values_digest = Catalog::OptionValuesDigest.call(pairs)
  end
end
