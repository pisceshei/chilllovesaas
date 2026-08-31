# frozen_string_literal: true

# PSP webhook 收件匣列（G6-1a）。
#
# ①冪等承載：(shop_id, provider, event_id) UNIQUE——控制器對 RecordNotUnique 回 200
#   （重複投遞＝已收，不是錯誤）。②消費者（G6-1b）以 status 推進 received→processed
#   ／failed；🔴 payload 內金額欄位**只准**經 `Money.from_psp_amount` 讀出（65 §E）。
class PspWebhookEvent < ApplicationRecord
  acts_as_tenant :shop

  STATUSES = %w[received processed failed].freeze

  validates :provider, presence: true
  validates :event_id, presence: true, uniqueness: { scope: [ :shop_id, :provider ] }
  validates :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }
end
