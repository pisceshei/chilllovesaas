# frozen_string_literal: true

# 行銷同意事件（G6 步 8a；08 §C.4 append-only）。
#
# ①這是什麼：每次同意變更一列，永不改寫——稽核與 latest-wins 合併的事實來源；
#   customers 的狀態欄只是投影快取（唯一寫入者＝Customers::UpdateMarketingConsent）。
# ②official 對位（取證 2026-09-01）：consent_updated_at＝合併鍵（"The customer's
#   consent state reflects the consent record with the most recent
#   consent_updated_at date."）；缺值＝寫入當下（官方同規則）。
# ③🔴 append-only 由 readonly? 承載：UPDATE/DELETE 一律 raise（不靠紀律靠機制）。
class CustomerMarketingConsent < ApplicationRecord
  CHANNELS = %w[email sms].freeze
  # 官方 enum 小寫形；INVALID 僅 email 有（SMS 五值），兩者的 redacted/invalid/
  # not_subscribed 皆唯讀（mutation 只收 WRITABLE_STATES）。
  STATES = %w[not_subscribed pending subscribed unsubscribed redacted invalid].freeze
  WRITABLE_STATES = %w[subscribed unsubscribed pending].freeze
  OPT_IN_LEVELS = %w[single_opt_in confirmed_opt_in unknown].freeze

  acts_as_tenant :shop
  belongs_to :customer

  validates :channel, inclusion: { in: CHANNELS }
  validates :state, inclusion: { in: STATES }
  validates :opt_in_level, inclusion: { in: OPT_IN_LEVELS }, allow_nil: true
  validates :consent_updated_at, presence: true
  validates :source, presence: true

  def readonly? = persisted?
end
