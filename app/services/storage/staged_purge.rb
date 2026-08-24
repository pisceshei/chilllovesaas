# frozen_string_literal: true

module Storage
  # staged 區孤兒清掃（第 28 包；25→26→27 三度順延後在此收口）。
  #
  # ①這是什麼：把 `shops/{shop_id}/staged/{uuid}/` 這一層裡**過期且沒被
  #   `fileCreate` 取用**的目錄整個刪掉。孤兒有兩種產生方式：
  #   ⓐ 簽了 `stagedUploadsCreate` 但使用者從沒把檔案傳上來（目錄根本不存在，
  #     不需要清）；ⓑ 傳上來了但 `fileCreate` 沒跑或失敗回滾——`Storage::FileCreate`
  #     是**讀 staged bytes 另寫一份永久 blob**（不是 move），原檔一律留在原地。
  #   ⇒ ⓑ 每一次上傳都會留一份，這是**確定會發生**的磁碟成長，不是邊界情況。
  #
  # ②判準只有一個：**目錄的 mtime 早於 `now - 過期窗`**。過期窗＝
  #   `media.staged_upload_ttl_seconds`（簽名有效期）＋`media.staged_purge_grace_seconds`
  #   （寬限）。🔴 為什麼要寬限而不是只用 TTL：簽名過期的那一刻，
  #   `Storage::FileCreate` 可能**正在讀**那份 bytes（簽名在上傳端點驗，
  #   fileCreate 本身不驗簽）——沒有寬限就是在別人讀到一半時把檔案抽掉。
  #
  # ③🔴 **不查資料庫、不比對 `files.storage_key`**。理由：staged key 與永久 key
  #   是兩個不同的命名空間（`shops/{id}/staged/...` vs `shops/{id}/files/...`），
  #   fileCreate 從來不會把 staged key 寫進 `files` ⇒ 「有沒有被取用」在 DB 裡
  #   查不到，查了也只會得到恆空的比對——那正是 fail-open 的典型形態
  #   （鐵律 20.2 第 5 類）。唯一可靠的訊號就是時間。
  #
  # ④跨功能影響：`Storage::SignedUpload.issue` 決定 key 形狀與 TTL（改那裡要回頭
  #   看本檔的 `STAGED_GLOB`）；`Admin::UploadsController` 是唯一寫入者；
  #   `Storage::FileCreate` 是唯一讀取者。本服務由 `Storage::StagedPurgeJob` 每日
  #   排程呼叫（`config/recurring.yml`），也可手動 `Storage::StagedPurge.call`。
  class StagedPurge
    # 一次 purge 的結果；`scanned` 是掃到的目錄數、`purged` 是實際刪掉的數。
    Result = Data.define(:scanned, :purged, :bytes_freed, :errors)

    class << self
      # @param now [Time] 判定基準時刻（測試可注入）
      # @return [Result]
      # @note 副作用：刪除檔案系統上的目錄。不碰資料庫。
      def call(now: Time.current)
        cutoff = now - expiry_window
        scanned = 0
        purged = 0
        bytes_freed = 0
        errors = []

        staged_directories.each do |dir|
          scanned += 1
          next if File.mtime(dir) > cutoff

          size = directory_bytes(dir)
          FileUtils.rm_rf(dir)
          purged += 1
          bytes_freed += size
        rescue SystemCallError => e
          # 🔴 單一目錄失敗不得中斷整輪（權限、正在寫入、race 下已被刪）。
          #    吞掉例外但**記進 errors 並寫 log**——靜默吞是 fail-open。
          errors << "#{dir}: #{e.class}: #{e.message}"
        end

        log(scanned:, purged:, bytes_freed:, errors:)
        Result.new(scanned:, purged:, bytes_freed:, errors:)
      end

      # 過期窗＝簽名有效期＋寬限（見檔頭②）。
      # @return [Integer] 秒
      def expiry_window
        Limits.fetch(:media, :staged_upload_ttl_seconds) +
          Limits.fetch(:media, :staged_purge_grace_seconds)
      end

      private

      # `shops/{shop_id}/staged/{uuid}` 這一層——**不是**它底下的檔案。
      # 一個 uuid 目錄對應一次簽發，整個刪掉才不會留空目錄。
      def staged_directories
        Dir.glob(LocalDisk.root.join("shops", "*", SignedUpload::STAGED_PREFIX, "*"))
           .select { |path| File.directory?(path) }
      end

      def directory_bytes(dir)
        Dir.glob(File.join(dir, "**", "*"))
           .select { |path| File.file?(path) }
           .sum { |path| File.size(path) }
      rescue SystemCallError
        0
      end

      def log(scanned:, purged:, bytes_freed:, errors:)
        Rails.logger.info(
          "event=staged_purge scanned=#{scanned} purged=#{purged} " \
          "bytes_freed=#{bytes_freed} errors=#{errors.size}",
        )
        errors.each { |message| Rails.logger.warn("event=staged_purge_error detail=#{message}") }
      end
    end
  end
end
