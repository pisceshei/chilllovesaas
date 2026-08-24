# frozen_string_literal: true

module Storage
  # staged 孤兒清掃的薄包裝（第 28 包；排程＝recurring.yml storage_staged_purge）。
  #
  # 🔴 **刻意不繼承租戶 job 的慣例**（同 `Events::RelayJob`）：清掃跨全部租戶掃
  #    檔案系統，沒有單一 shop_id 可帶。它不碰資料庫，因此也不需要 tenant scope。
  class StagedPurgeJob < ApplicationJob
    queue_as :background

    def perform = Storage::StagedPurge.call
  end
end
