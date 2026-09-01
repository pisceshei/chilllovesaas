# frozen_string_literal: true

# 分析日聚合列（G6 步 10；19-F2）。唯一寫入者＝Analytics::RollupDaily（upsert）。
class DailyRollup < ApplicationRecord
  acts_as_tenant :shop

  validates :metric, presence: true
  validates :date, presence: true
end
