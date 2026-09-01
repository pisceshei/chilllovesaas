# frozen_string_literal: true

module Analytics
  # rollup 排程（G6 步 10；recurring 每 15 分）：每店重算「今日＋昨日」
  # （shop 時區）——今日覆蓋即時性、昨日補換日窗的遲到寫入；整日重算＋upsert
  # 覆蓋＝冪等（19-F2.2）。
  class RollupJob < ApplicationJob
    queue_as :background

    def perform
      ActsAsTenant.without_tenant do
        Shop.where(status: "active").find_each do |shop|
          tz = ActiveSupport::TimeZone[shop.timezone] || Time.zone
          today = tz.today
          ActsAsTenant.with_tenant(shop) do
            RollupDaily.call(shop:, date: today - 1)
            RollupDaily.call(shop:, date: today)
          end
        end
      end
    end
  end
end
