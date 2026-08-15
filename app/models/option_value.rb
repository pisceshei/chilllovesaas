# 一個選項的一個可選值（S／M／L、紅／藍…）。
#
# ⚠️ 與 `ProductOption` 同批，表在 M0 建好、model 到 D12（2026-08-15）才第一次出現。
#
# 🔴 **值可以「沒有任何變體用到」**（孤立值是合法狀態）。
# 本尊 `productOptions` 的 `optionValues` 官方明載包含 "values not assigned to any variants"
# ⇒ **不得**把 option value 設計成「只有被變體用到才存在」。
# 做錯的後果：①那個官方欄位語義實作不出來；②`productSet` 式同步刪掉最後一個變體時
# 會**誤刪 option value**。
#
# 🔴 **改名走 in-place UPDATE，`id` 不動** ⇒ 變體的 `option_values_digest` 不變、
# 變體 id 不變、掛在 `option_value_id` 上的譯文全部存活（`docs/specs/67` §B.3-4）。
# 這與本尊一致：`productOptionUpdate` 的 `optionValuesToUpdate` 以 `id: ID!` 定位。
#
# @see docs/DECISIONS.md D12
# @see docs/specs/67-multilingual.md §B.3-4
class OptionValue < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product_option

  # 🔴 `restrict_with_error` **不是** `destroy`：一個還被變體用著的選項值被刪掉，
  # 那些變體的座標就少一維、digest 與 join 列不一致。刪值屬於選項變更流程
  # （本尊的 `ProductOptionUpdateVariantStrategy: MANAGE` 會連帶刪變體），
  # 要走那條路徑明文宣告，不得從這裡靜默 cascade。
  has_many :product_variant_option_values, dependent: :restrict_with_error

  validates :value, presence: true
  validates :position, presence: true
end
