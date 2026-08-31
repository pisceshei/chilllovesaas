# frozen_string_literal: true

# manual 付款方式（86 §3 實測正典；結帳線第三包）。
#
# ①這是什麼：Settings→Payments→Manual payment methods 的對位——商家自行收款的
#   付款方式（銀行轉帳／匯票／貨到付款／自訂）。⊕ 選單恰四值（86 §3 DOM 逐字）。
# ②🔴 PSP 付款方式不落本表（15-F4.2：那是對已連接 PSP 的 capability 查詢，我方不是
#   真相來源）；COD 的 TW 超商代收手續費也不在這裡（jurisdiction pack 擴充，F2.3）。
# ③內建型別每店至多一列（86 §3：已啟用者從 ⊕ 選單消失）——DB 層 builtin_guard 虛擬欄
#   ＋本 model 驗證雙防線；custom 可多列、名稱擋官方保留名單（86 §3 逐字九名）。
# ④停用＝active=false（86 §3 Deactivate 語義：設定保留、可隨時再啟用）；不刪列。
# ⑤跨功能影響：checkout Payment 段的方法清單與快照（payment_method_snapshot）；
#   下單確認頁的 payment_instructions（F5 訂單包消費）；財務狀態 manual ⇒ PENDING
#   （86 §3 官方句、90-blueprint/05 §C.12）。
class ShopPaymentMethod < ApplicationRecord
  METHOD_TYPES = %w[bank_deposit money_order cash_on_delivery custom].freeze
  # 內建型別的正典顯示名（86 §3 選單逐字；文案層另走 i18n，本欄是識別名）。
  BUILTIN_NAMES = {
    "bank_deposit" => "Bank Deposit",
    "money_order" => "Money Order",
    "cash_on_delivery" => "Cash on Delivery (COD)"
  }.freeze
  # 官方保留名單（86 §3 逐字；custom 方法不得用——小寫正規化後比對）。
  RESERVED_NAMES = [ "Bank Deposit", "Cash", "Cash on Delivery (COD)", "custom",
                    "External Credit", "External Debit", "Gift Card", "Money Order",
                    "Store Credit" ].map(&:downcase).freeze

  acts_as_tenant :shop

  validates :method_type, inclusion: { in: METHOD_TYPES }
  validates :name, presence: true, uniqueness: { scope: :shop_id }
  validate :single_builtin_per_shop
  validate :custom_name_not_reserved

  before_validation :default_builtin_name, on: :create

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # checkout 落庫的快照形（訂單成立與確認頁都吃它——商家後改文案不影響已建結帳）。
  def snapshot
    {
      "id" => id, "method_type" => method_type, "name" => name,
      "additional_details" => additional_details, "payment_instructions" => payment_instructions
    }
  end

  private

  def default_builtin_name
    self.name ||= BUILTIN_NAMES[method_type]
  end

  # 內建型別每店恰一（86 §3 已啟用者從選單消失）；DB builtin_guard 是第二道防線。
  def single_builtin_per_shop
    return if method_type == "custom" || shop_id.nil?
    return unless ShopPaymentMethod.where(shop_id:, method_type:).where.not(id:).exists?

    errors.add(:method_type, "此內建付款方式已存在（每店至多一個）")
  end

  def custom_name_not_reserved
    return unless method_type == "custom"
    return unless RESERVED_NAMES.include?(name.to_s.strip.downcase)

    errors.add(:name, "此名稱為平台保留字，不可用於自訂付款方式")
  end
end
