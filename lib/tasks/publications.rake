# frozen_string_literal: true

# PR-C 的一次性 backfill 入口（D53；語義與冪等紀律見
# `Publications::BackfillScheduledStamps` 檔頭）。跑完即結案，不是常駐 sweeper。
#
# 用法（正式庫照 handoff 的 run_as_app 形態）：
#   bin/rails publications:backfill_scheduled_stamps
namespace :publications do
  desc "補 PR-C 之前被零消費者消化掉的排程事件（冪等，可重跑）"
  task backfill_scheduled_stamps: :environment do
    result = Publications::BackfillScheduledStamps.call
    puts "backfill_scheduled_stamps scanned=#{result[:scanned]} bumped=#{result[:bumped]}"
  end
end
