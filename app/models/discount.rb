# frozen_string_literal: true

# 折扣規則（G6 步 9a；17-F1；表＝M0 既有 discounts）。
#
# ①單表多型：discount_class（product/order/shipping）× method（code/automatic）×
#   value_type（percentage/fixed_amount）。percentage 內部一律 **basis points 整數**
#   （17-F2.1 值域註：API 線 0–1 Float、序列化層除以 10000）；fixed 帶 currency
#   （跨幣別不適用——schema 先留）。
# ②status 欄＝**商家生命週期**（draft/active/archived）；scheduled/expired 由時間欄
#   推導（17-F1.2：不落庫不 cron——消滅時鐘競態）。讀 `effective_status`。
# ③code 正規化：upcase+trim（17-F1.2）；唯一索引 uq_discounts_code。
# ④🔴 combines_* 三旗標不對稱（17-F1.4）：shipping 類的 combines_shipping 恆 false
#   （官方免運 combinesWith 只有 order/product 兩旗標；運費不可疊運費＝引擎級硬規則
#   double-guard）。M0 表是對稱三欄 ⇒ 約束落 model 驗證（schema 級子表 ⚪）。
# ⑤conditions JSON（v1 鍵）：min_subtotal_cents／min_quantity／entitled_variant_ids
#   （product 類的適用範圍 v1 形；entitlements 正規化表 ⚪ 91 §3.54）。
class Discount < ApplicationRecord
  CLASSES = %w[product order shipping].freeze
  METHODS = %w[code automatic].freeze
  VALUE_TYPES = %w[percentage fixed_amount].freeze
  STATUSES = %w[draft active archived].freeze

  acts_as_tenant :shop

  validates :title, presence: true
  validates :discount_class, inclusion: { in: CLASSES }
  validates :method, inclusion: { in: METHODS }
  validates :value_type, inclusion: { in: VALUE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :code, presence: true, uniqueness: { scope: :shop_id }, if: -> { method == "code" }
  validates :percentage_basis_points,
            numericality: { only_integer: true, in: 0..10_000 },
            if: -> { value_type == "percentage" }
  validates :value_cents, numericality: { only_integer: true, greater_than: 0 },
            if: -> { value_type == "fixed_amount" }
  validate :shipping_class_cannot_combine_shipping

  before_validation :normalize_code

  # @return [String] draft/archived 原樣；active ⇒ scheduled/active/expired（時間推導）
  def effective_status(now = Time.current)
    return status unless status == "active"
    return "scheduled" if starts_at && now < starts_at
    return "expired" if ends_at && now > ends_at

    "active"
  end

  def self.normalize_code(raw)
    raw.to_s.strip.upcase.presence
  end

  private

  def normalize_code
    self.code = Discount.normalize_code(code) if method == "code"
  end

  # 17-F1.4：官方錯誤碼同名（INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS 的 model 位）。
  def shipping_class_cannot_combine_shipping
    return unless discount_class == "shipping" && combines_shipping

    errors.add(:combines_shipping, "免運折扣沒有 shippingDiscounts 旗標（官方 combinesWith 只有 order/product）")
  end
end
