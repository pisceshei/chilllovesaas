# frozen_string_literal: true

# webhook 投遞紀錄（步 20a；specs/18 F4：保留 7 天供除錯）。
class WebhookDelivery < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :webhook_subscription

  STATES = %w[sent failed].freeze
  validates :state, inclusion: { in: STATES }
end
