# frozen_string_literal: true

# 購物車行（specs/15 F1 #1/#5）。
#
# 🔴 行合併語義（F1 #5，PR #52 第 4/11/19 輪三次修正的終形）：
#   merge_key_hash＝SHA-256(variant_id｜properties 正規化 JSON｜selling_plan_id｜
#   unit_price_cents｜parent_id)——**全同才併行**；同 variant 不同屬性／方案／
#   單價／bundle 父項＝合法多行。唯一索引 (shop_id, cart_id, merge_key_hash)
#   以 shop_id 開頭（鐵律 2）；併發加購靠 upsert 撞此索引收斂（CartWriter）。
# 🔴 unit_price_cents＝加入當下價（合併鍵承重輸入，非顯示欄）；顯示即時價
#   由 serializer 查 variant 現價（F1 #3）。
class CartLineItem < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :cart
  belongs_to :product_variant

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :merge_key_hash, presence: true

  before_validation :compute_merge_key

  # @return [String] 與 before_validation 同一算法（writer 的 upsert 用）
  def self.merge_key_for(product_variant_id:, properties:, selling_plan_id:, unit_price_cents:, parent_id:)
    canonical = [
      product_variant_id,
      Idempotency::CanonicalJson.dump(properties || {}),
      selling_plan_id,
      unit_price_cents,
      parent_id
    ].join("|")
    Digest::SHA256.hexdigest(canonical)
  end

  private

  def compute_merge_key
    self.properties ||= {}
    self.merge_key_hash = self.class.merge_key_for(
      product_variant_id:, properties:, selling_plan_id:, unit_price_cents:, parent_id:
    )
  end
end
