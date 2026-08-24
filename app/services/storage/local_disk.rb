# frozen_string_literal: true

module Storage
  # 本機磁碟儲存後端（第 25 包；limits `media.storage_backend`＝
  # self_hosted_presigned_post 的實體層）。
  #
  # ①這是什麼：`storage_key` → 磁碟路徑的唯一換算點。根目錄＝`storage/chilllove/`
  #   （Rails 預設 gitignore；bt3 上隨 app 目錄持久）。
  # ②🔴 路徑安全：storage_key 逐段驗證（不含 `..`／空段／反斜線），組出的絕對路徑
  #   必須落在根目錄下——後綴比對用 `File::SEPARATOR` 錨定，防 `storage/chilllove-evil`
  #   前綴繞過。
  # ③跨功能影響：SignedUpload（staged 寫入）、FileCreate（staged→permanent 搬移）、
  #   Admin::UploadsController#show（讀出）、第 26 包管線（衍生圖寫入）。
  class LocalDisk
    class InvalidKey < StandardError; end

    class << self
      def root
        Rails.root.join("storage", "chilllove")
      end

      # @param key [String] storage_key（如 "shops/1/files/uuid.jpg"）
      # @return [Pathname] 驗證過的絕對路徑
      def path_for(key)
        segments = key.to_s.split("/")
        if segments.empty? || segments.any? { |part| part.empty? || part == ".." || part.include?("\\") }
          raise InvalidKey, "invalid storage key"
        end

        candidate = root.join(*segments)
        raise InvalidKey, "key escapes root" unless candidate.to_s.start_with?(root.to_s + File::SEPARATOR)

        candidate
      end

      # @param io [IO, StringIO]
      def write(key, io)
        target = path_for(key)
        FileUtils.mkdir_p(target.dirname)
        ::File.open(target, "wb") { |f| IO.copy_stream(io, f) }
        target
      end

      def read(key) = ::File.binread(path_for(key))

      def exist?(key) = ::File.exist?(path_for(key))

      def byte_size(key) = ::File.size(path_for(key))

      # staged → permanent（同磁碟 rename，原子）。
      def move(from_key, to_key)
        target = path_for(to_key)
        FileUtils.mkdir_p(target.dirname)
        FileUtils.mv(path_for(from_key), target)
      end

      def delete(key)
        target = path_for(key)
        FileUtils.rm_f(target)
      end

      # 刪檔，並把因此變空的**上層目錄**一併收掉。
      #
      # 🔴 為什麼需要這一支（2026-08-25 於 bt3 實測發現）：`delete` 用 `rm_f`，
      #   只拿掉檔案、留下目錄。對 `shops/{id}/files/` 沒差（全部 blob 共用一層），
      #   但衍生尺寸的 key 是
      #   `shops/{id}/derivatives/{file_id}/{checksum}/{variant}.webp`——**每個檔案
      #   自己一棵樹**。刪一個檔就永久留下兩層空目錄，而且沒有任何東西會來收。
      #   實測數字：14 個檔案對應 31 個 `derivatives/{file_id}` 目錄、17 個空目錄，
      #   差額正好是本輪刪掉的檔數。累積的是 inode 不是位元組，但一樣是單向成長。
      #   複驗：`find storage/chilllove/shops/*/derivatives -type d -empty | wc -l`
      #
      # 🔴 **只往上收到 root 為止，而且只收空的**：`Dir.rmdir` 對非空目錄會丟
      #   `Errno::ENOTEMPTY`，那是天然的停止條件——不必自己判斷「還有沒有別人在用」，
      #   也就不會有「以為空的其實不空」的競態。到 root 就停，絕不刪 root 本身。
      #
      # @param key [String] storage_key
      # @param stop_at [Pathname] 收到這一層就停（預設＝storage root）
      # @return [void]
      def delete_with_empty_parents(key, stop_at: root)
        target = path_for(key)
        FileUtils.rm_f(target)
        prune_empty_parents(target.dirname, stop_at)
      end

      private

      def prune_empty_parents(dir, stop_at)
        stop = stop_at.cleanpath
        current = dir.cleanpath
        while current != stop && current.to_s.start_with?("#{stop}#{::File::SEPARATOR}")
          begin
            Dir.rmdir(current)
          rescue SystemCallError
            # 非空（ENOTEMPTY）或已不存在（ENOENT）⇒ 停，兩者都不是錯誤。
            break
          end
          current = current.parent
        end
      end
    end
  end
end
