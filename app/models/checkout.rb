# frozen_string_literal: true

# 結帳快照（15 F3；表建於 M0、第一個消費者＝結帳線第一包）。
#
# ①line_items_snapshot：**進入結帳當下**的行快照（variant_id／quantity／title／
#   unit_price_cents／properties）——進入時**重新快照價格**（F1 #3：cart 顯示價
#   已是即時價，結帳把它定格）；此後價格變動不影響本結帳（F2 坑 3 的快照紀律）。
# ②🔴 建立結帳**不扣庫存**（F1 ⚠️坑／15 F5：訂單成立事件才扣）。
# ③token＝結帳 URL 身分（/checkouts/<token>）；recovery_token＝棄單挽回連結
#   （F7；兩把不同的鑰匙——挽回信外洩不等於現場結帳被接管）。
# ④金額欄全 integer cents（鐵律 3）；presentment 雙欄 v1 與店幣同值（多幣別
#   隨 markets 幣別包）。
class Checkout < ApplicationRecord
  STATUSES = %w[active completed expired].freeze

  acts_as_tenant :shop

  validates :token, presence: true, uniqueness: { scope: :shop_id }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true

  before_validation :ensure_tokens, on: :create

  private

  def ensure_tokens
    self.token ||= SecureRandom.hex(24)
    self.recovery_token ||= SecureRandom.hex(24)
  end
end
