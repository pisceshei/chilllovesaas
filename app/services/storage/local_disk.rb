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
    end
  end
end
