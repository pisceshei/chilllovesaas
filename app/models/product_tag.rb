# frozen_string_literal: true

# 商品標籤正規化列（13 §F4.4）：`tag_display` 顯示、`tag_key` 比對（`Tags::Normalize` 唯一實作）。
#
# 🔴 寫入面只有兩個：`Catalog::SaveProduct`（tags 變更同 tx 同步）與 migration 回填。
#   `products.tags`（JSON 欄）仍是**顯示順序**的權威；本表是**比對**的權威——兩者由
#   同一個 tx 內的同步保持一致，出現分岔＝SaveProduct 的同步壞了，不是本表該修。
class ProductTag < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  # 上限一律引 `limits`（鐵律 6）——服務層、model、migration 回填三處必須同一個判準
  # （2026-08-26 第六輪 K5：第五輪在 model 與 migration 各硬編了一個 255）。
  TAG_MAX_CHARS = Limits.fetch(:product, :tag_max_chars)

  validates :tag_display, presence: true, length: { maximum: TAG_MAX_CHARS }
  # 🔴 `tag_key` 也要驗長度（2026-08-26 收斂輪 J2）：它是**正規化後**的值，
  #   而正規化會展開（ß→ss、㍿→株式会社）⇒ 原字串合法不代表 key 合法。
  #   少了這一條，溢位會以 `ActiveRecord::ValueTooLong`（DB 層）現形，
  #   而那個例外不在服務層的 rescue 清單裡 ⇒ 漏成 500。
  validates :tag_key, presence: true, length: { maximum: TAG_MAX_CHARS },
                      uniqueness: { scope: [ :shop_id, :product_id ] }
end
