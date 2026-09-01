# frozen_string_literal: true

# 對外 webhook 訂閱（步 20a；specs/18 F4 表設計）。
# 🔴 topic 值域＝Events::Topics::EXTERNAL（內部 topic 永不可訂閱——28 §15）；
# URL 紅線（HTTPS＋SSRF resolve 層防護）在 Webhooks::UrlGuard，建立與投遞雙時點。
class WebhookSubscription < ApplicationRecord
  acts_as_tenant :shop

  STATUSES = %w[active disabled].freeze

  has_many :webhook_deliveries, dependent: :delete_all

  validates :topic, presence: true, inclusion: { in: Events::Topics::EXTERNAL }
  validates :url, presence: true, length: { maximum: 1024 }
  validates :status, inclusion: { in: STATUSES }
  validates :secret, presence: true
end
