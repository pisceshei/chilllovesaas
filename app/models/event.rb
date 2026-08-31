# frozen_string_literal: true

# 訂單 timeline 事件（表註「業務上 append-only」；15-F5 步 2 的 timeline event）。
#
# 與 EventOutbox 是兩回事：本表＝給人看的訂單時間軸；outbox＝機器消費的
# webhook 事件（11 §8 同 transaction 落列）。
class Event < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :order, optional: true

  validates :kind, presence: true
  validates :happened_at, presence: true
end
