# frozen_string_literal: true

# 與業務寫入同 transaction 的 at-least-once 事件 outbox（鐵律 5：事件走 outbox）。
#
# 一列 ＝ 一個待發布的領域事件。發布端（relay job）在 M1 後續包落地；
# 在那之前本表只進不出——這是刻意的：**事件必須與業務寫入同 transaction 產生**，
# 否則「商品建立了但 products/create 事件永遠沒發」的縫在發布端上線那天
# 已經有一批補不回來的歷史。
#
# @see docs/specs/11-production-baseline.md §0（可觀測維度）
# @see docs/specs/13-spec-products-inventory-media.md §F1（七維度表：單一 transaction 含 outbox）
class EventOutbox < ApplicationRecord
  self.table_name = "event_outbox"

  # dead＝attempts 達 limits.events.outbox_dead_letter_attempts 的終態（specs/18 F1-5；
  # 第 19 包 §4.3-1 裁定入列）。終態列的 dedupe_key 由 Events::Relay 清成 NULL。
  STATUSES = %w[pending published failed dead].freeze
  TERMINAL_STATUSES = %w[published failed dead].freeze

  acts_as_tenant :shop

  validates :event_id, presence: true
  validates :topic, presence: true
  validates :aggregate_type, presence: true
  validates :status, inclusion: { in: STATUSES }
end
