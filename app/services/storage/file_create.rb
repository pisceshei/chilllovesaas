# frozen_string_literal: true

require "digest"

module Storage
  # fileCreate 的核心（第 25 包；12 §D.7 兩段式的第 3 步）。
  #
  # ①這是什麼：把 originalSource（staged resourceUrl 或外部 URL）落成 `files` 一列
  #   ＋磁碟 blob＋MEDIA_UPLOADED outbox 事件（同 transaction——鐵律 5）。
  # ②來源兩路（兩路都把 bytes 讀進記憶體再落庫——staged 也不 move 原檔）：
  #   - staged（本家 resourceUrl）：驗 key 屬本店 → 讀 bytes（原檔留給孤兒清掃，26 包）。
  #   - 外部 URL：Storage::SafeFetch（SSRF 四道防線）。
  #   內容型別一律 Storage::ImageSniff **magic-byte 決定**（審查 C5：不信副檔名／
  #   宣告 mimeType）；不在 `media.image_content_types` 白名單＝UNACCEPTABLE_ASSET。
  # ③🔴 檔案系統操作在 DB transaction **之外**（審查 C2/C3/C8）：
  #   先寫新 blob → DB txn 只做 metadata＋event → rollback 補償清剛寫的 blob →
  #   commit 後才刪 replace 的舊 blob。fs 不回滾，混進 txn 會在 rollback 留下
  #   「row 指向已刪 blob」或「孤兒 blob／被吞的 staged 檔」。
  # ④🔴 batch 每列各自 rescue（審查 C4）：一列 raise 轉該列 userError，不炸整批、
  #   不讓前面已 commit 的檔留無主 blob（該列的 blob 在 rescue 內清掉）。
  # ⑤撞名解法＝limits `media.duplicate_resolution_modes`（B8）：append_uuid（改名）／
  #   raise_error（INVALID）／replace（保留原列 id 換 blob——引用不斷）。
  # ⑥狀態：圖片本層直接 ready；第 26 包管線接手後改 uploaded→processing（worklog 登記）。
  # ⑦錯誤碼＝已證四值（12 §C.7:90）：INVALID／UNACCEPTABLE_ASSET／
  #   ALT_VALUE_LIMIT_EXCEEDED／FILE_DOES_NOT_EXIST。
  class FileCreate
    Result = Data.define(:files, :user_errors)

    ALT_MAX = 512

    class << self
      # @param shop [Shop]
      # @param files_input [Array<Hash>] [{original_source:, alt:, filename:, duplicate_resolution_mode:}]
      # @return [Result]
      def call(shop:, files_input:)
        if files_input.length > Limits.fetch(:media, :file_create_batch_max)
          return Result.new(files: [], user_errors: [ error([ "files" ],
            I18n.t("errors.files.batch_too_large"), "INVALID") ])
        end

        errors = []
        created = []
        files_input.each_with_index do |input, index|
          file, file_errors = create_one(shop, input, index)
          errors.concat(file_errors)
          created << file if file
        end
        Result.new(files: created, user_errors: errors)
      rescue StandardError
        # call 級兜底：任何漏網例外不得變成 top-level 500（鐵律 4）。
        Result.new(files: [], user_errors: [ error([ "files" ],
          I18n.t("errors.files.source_invalid"), "INVALID") ])
      end

      private

      def error(field, message, code) = { field:, message:, code: }

      def create_one(shop, input, index)
        alt = input[:alt].to_s
        if alt.length > ALT_MAX
          return [ nil, [ error([ "files", index.to_s, "alt" ],
            I18n.t("errors.files.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED") ] ]
        end

        source = resolve_source(shop, input, index)
        return [ nil, source[:errors] ] if source[:errors].any?

        bytes = source[:bytes]
        content_type = ImageSniff.content_type(bytes)
        unless content_type && Limits.enum(:media, :image_content_types).map { |v| v.to_s.downcase }.include?(content_type)
          return [ nil, [ error([ "files", index.to_s, "originalSource" ],
            I18n.t("errors.files.type_unacceptable"), "UNACCEPTABLE_ASSET") ] ]
        end
        if bytes.bytesize > Limits.fetch(:content, :files_image_max_mb) * 1024 * 1024
          return [ nil, [ error([ "files", index.to_s, "originalSource" ],
            I18n.t("errors.files.too_large"), "INVALID") ] ]
        end

        filename = normalized_filename(input[:filename].presence || source[:filename], content_type)
        if (violation = FilenameRules.violation(filename))
          code = violation == :unacceptable ? "UNACCEPTABLE_ASSET" : "INVALID"
          return [ nil, [ error([ "files", index.to_s, "filename" ],
            I18n.t("errors.files.filename_invalid"), code) ] ]
        end

        mode = (input[:duplicate_resolution_mode].presence ||
                Limits.fetch(:media, :duplicate_resolution_mode_default).to_s).to_s.downcase
        filename, replace_target, dup_errors = resolve_duplicate(shop, filename, mode, index)
        return [ nil, dup_errors ] if dup_errors.any?

        persist!(shop, bytes, content_type, filename, alt, replace_target)
      rescue StandardError
        # persist! 的 blob 補償已在其自身 rescue 內完成；這裡只把該列轉 userError。
        [ nil, [ error([ "files", index.to_s, "originalSource" ],
          I18n.t("errors.files.source_invalid"), "INVALID") ] ]
      end

      # @return [Hash] { bytes:, filename:, errors: [] }
      def resolve_source(shop, input, index)
        original = input[:original_source].to_s
        staged_key = SignedUpload.staged_key_from(original, shop:)
        if staged_key
          unless LocalDisk.exist?(staged_key)
            return { errors: [ error([ "files", index.to_s, "originalSource" ],
              I18n.t("errors.files.source_missing"), "FILE_DOES_NOT_EXIST") ] }
          end
          { bytes: LocalDisk.read(staged_key), filename: ::File.basename(staged_key), errors: [] }
        else
          fetch_external(original, index)
        end
      end

      def fetch_external(url, index)
        result = SafeFetch.call(url)
        { bytes: result.body, filename: ::File.basename(URI.parse(url).path.presence || "file"), errors: [] }
      rescue SafeFetch::Blocked, SafeFetch::TooLarge, URI::InvalidURIError
        { errors: [ error([ "files", index.to_s, "originalSource" ],
          I18n.t("errors.files.source_invalid"), "INVALID") ] }
      end

      def resolve_duplicate(shop, filename, mode, index)
        existing = StoredFile.find_by(filename:)
        return [ filename, nil, [] ] unless existing

        case mode
        when "append_uuid"
          extension = ::File.extname(filename)
          stem = ::File.basename(filename, ".*")
          [ "#{stem}-#{SecureRandom.uuid.first(8)}#{extension}", nil, [] ]
        when "replace"
          [ filename, existing, [] ]
        else # raise_error（撞名專屬碼未取證 ⇒ INVALID，ours）
          [ nil, nil, [ error([ "files", index.to_s, "filename" ],
            I18n.t("errors.files.filename_taken"), "INVALID") ] ]
        end
      end

      # 🔴 fs 在 txn 外（審查 C2/C3/C8）：先寫新 blob → txn 只碰 DB →
      #    rollback 清新 blob → commit 後才刪舊 blob。
      def persist!(shop, bytes, content_type, filename, alt, replace_target)
        checksum = Digest::SHA256.hexdigest(bytes)
        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}#{::File.extname(filename).downcase}"
        LocalDisk.write(key, StringIO.new(bytes))

        file = nil
        old_key = nil
        begin
          ActiveRecord::Base.transaction do
            if replace_target
              old_key = replace_target.storage_key
              replace_target.update!(storage_key: key, content_type:, byte_size: bytes.bytesize,
                                     checksum:, alt_text: alt.presence, status: "ready")
              file = replace_target
            else
              file = StoredFile.create!(filename:, content_type:, byte_size: bytes.bytesize,
                                        checksum:, storage_key: key, alt_text: alt.presence, status: "ready")
            end
            # 鐵律 5：事件與業務寫入同 transaction（消費者＝第 26 包處理管線）
            EventOutbox.create!(event_id: SecureRandom.uuid, topic: Events::Topics::MEDIA_UPLOADED,
                                aggregate_type: "StoredFile", aggregate_id: file.id,
                                payload: { file_id: file.id, filename: file.filename,
                                           content_type: file.content_type, byte_size: file.byte_size },
                                available_at: Time.current, status: "pending")
          end
        rescue StandardError
          LocalDisk.delete(key) # 補償：txn 失敗清剛寫的新 blob（舊 blob 未動、row 仍指舊）
          raise
        end

        LocalDisk.delete(old_key) if old_key # commit 後才刪 replace 的舊 blob（不可逆）
        [ file, [] ]
      end

      # 檔名副檔名對齊 sniff 出的內容型別（宣告 .png 實為 jpeg ⇒ 落庫用真副檔名）。
      def normalized_filename(filename, content_type)
        expected = { "image/jpeg" => ".jpg", "image/png" => ".png",
                     "image/gif" => ".gif", "image/webp" => ".webp" }.fetch(content_type)
        stem = ::File.basename(filename.to_s, ".*")
        stem = "file" if stem.blank?
        "#{stem}#{expected}"
      end
    end
  end
end
