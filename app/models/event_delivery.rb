# frozen_string_literal: true

# event × consumer 投遞帳（第 25 包；63 §L-4 門檻結清）。
#
# 一列＝某事件對某具名消費者的投遞狀態。done 列在事件重試時跳過——
# **一個消費者失敗不連累另一個重放**。outbox purge 時經 FK CASCADE 同批消失。
class EventDelivery < ApplicationRecord
  STATES = %w[pending done].freeze

  acts_as_tenant :shop

  validates :event_id, presence: true
  validates :consumer, presence: true
  validates :state, inclusion: { in: STATES }
end
