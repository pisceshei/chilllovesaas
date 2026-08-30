# frozen_string_literal: true

# 網域（包 32；實測 2026-08-31 Settings→Domains，store chill-love-u5q5mnzq）。
#
# ①這是什麼：host→shop 解析的權威表（步 2 的公開店面 hosting 消費）；
#   本尊 Domains 列表一列＝一 host（chill.deals［Primary］／www.chill.deals／*.myshopify.com）。
# ②值域（實測 Change domain type 對話，恰三值逐字）：
#   - `primary`＝Primary domain：「Displayed in the address bar when visitors are browsing Online Store.」
#   - `redirect`＝Redirecting domain：「Directs users to the primary domain for Online Store.」
#   - `alias`＝Alias domain：「Displays contents of Online Store but doesn't redirect or update
#     the browser address bar. Misuse can harm SEO.」（redirect／alias 的行為實作在步 2 hosting）
# ③恰一 primary：DB 生成欄位 primary_guard＋唯一索引兜底（本尊列表恰一個 Primary 徽章）。
# ④跨功能影響：market_web_presences.domain_id 引用（FK restrict——先改 presence 再刪網域）；
#   `url_prefix` 的 origin 半邊（67 §F.1(d) absolute_url = origin(wp) + url_prefix + path）；
#   平台管理後台的 DNS 驗證／SSL ops（bt3 nginx 配套）讀 status。
class Domain < ApplicationRecord
  DOMAIN_TYPES = %w[primary redirect alias].freeze
  STATUSES = %w[pending active].freeze
  # 小寫 FQDN：label（a-z0-9-，不以 - 開頭結尾）以點連接，至少兩段。
  HOST_FORMAT = /\A(?=.{4,253}\z)([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/

  acts_as_tenant :shop

  has_many :market_web_presences, dependent: :restrict_with_error

  normalizes :host, with: ->(value) { value.to_s.strip.downcase.delete_suffix(".") }

  validates :host, presence: true, format: { with: HOST_FORMAT }, uniqueness: true
  validates :domain_type, inclusion: { in: DOMAIN_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :primary, -> { where(domain_type: "primary") }

  # @return [Domain, nil] 本店的 primary domain（生成欄位唯一索引保證至多一個）
  def self.primary_for(shop_id)
    primary.find_by(shop_id:)
  end
end
