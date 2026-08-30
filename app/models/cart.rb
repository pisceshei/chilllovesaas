# frozen_string_literal: true

# 買家購物車（specs/15 F1）。
#
# ①這是什麼：DB-backed cart 本體；`token` 由 controller 放進簽名 cookie
#   `_cl_buyer`（🔴 host-only——F1 ⚠️坑：設在主網域＝跨店共享）。
# ②note／attributes：Ajax cart 契約欄（官方語義：clear 清行不清這兩欄——
#   Ajax API 官方句取證 2026-08-30，83 §3.3 live 同形）。
#   attributes 欄名帶 _json 後綴迴避 AR 的 attributes 保留字。
# ③過期：90 天未動 purge（F1 #4；ix_carts_updated_at 為掃描鍵；job 隨排程包）。
class Cart < ApplicationRecord
  acts_as_tenant :shop

  has_many :cart_line_items, dependent: :delete_all

  validates :token, presence: true, uniqueness: { scope: :shop_id }

  before_validation :ensure_token, on: :create

  def self.generate_token = SecureRandom.hex(24)

  private

  def ensure_token
    self.token ||= self.class.generate_token
    self.attributes_json ||= {}
  end
end
