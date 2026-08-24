# frozen_string_literal: true

module Storage
  # 檔案庫的寫入路徑（第 28 包）：`fileUpdate`／`fileDelete` 的唯一實作。
  #
  # ①這是什麼：`Storage::FileCreate` 管「檔案怎麼進來」，本服務管「進來之後怎麼改、
  #   怎麼刪」。兩者合起來是 `files` 表的全部業務寫入端（`MediaPipeline::ProcessFile`
  #   只改 status／derivatives，屬管線不屬業務）。
  #
  # ②🔴 **刪檔＝連帶解除引用，不是擋下來**（官方語義，取證 2026-08-25）：
  #   `fileDelete` 的官方說明逐字＝"When you delete files that are referenced by
  #   products, the mutation automatically removes those references and reorders any
  #   remaining media to maintain proper positioning."
  #   ⇒ ⓐ「檔案正在被使用」**不是**錯誤條件（官方 `FilesErrorCode` 整份值域裡沒有
  #   對應碼）ⓑ **刪完必須補位**——那是官方明載的副作用，不是實作細節。
  #   來源：<https://shopify.dev/docs/api/admin-graphql/latest/mutations/fileDelete>
  #
  # ③🔴 **alt 的分層是我方與本尊的已知分歧，不是疏漏**（登記見 `docs/specs/91` §3.10）：
  #   本尊的 alt 在**檔案層且只有一份**（`MediaImage` 同時 implements `File` 與
  #   `Media`，只曝露一個 `alt`）；我方在第 26／27 包裁定 alt 權威在 `media` 那一列
  #   （同檔掛不同商品可有不同 alt）。⇒ `fileUpdate` 只改 `files.alt_text`，
  #   **刻意不回寫既有 media**：使用者針對三個商品分別寫過的 alt，不該被檔案庫的
  #   一次編輯蓋掉。檔案層 alt 的作用＝新掛載時的預設值。
  #
  # ④🔴 **blob 刪除在 transaction 之外、且在 commit 之後**（鐵律 5＋檔案系統不回滾）：
  #   順序是「DB txn 刪 row → commit → 刪 blob 與衍生」。反過來（先刪 blob）在 txn
  #   回滾時會留下**指向不存在檔案的 row**——那比孤兒 blob 嚴重得多（列表整頁破圖，
  #   而孤兒 blob 只是佔空間、還能被清掃收）。
  #
  # ⑤跨功能影響：`file_usages` 是引用計數的唯一來源（`Media#before_destroy` 釋放、
  #   `Catalog::MediaSync#build_media!` 建立）；刪檔會讓引用它的 `media` 列一併消失
  #   ⇒ 商品頁的媒體卡下次載入就少一張、且**剩下的圖會補位**。檔案庫頁
  #   （`FilesPage.tsx`）與選檔 modal 都消費本服務的結果。
  class FileWrite
    Result = Data.define(:files, :deleted_file_ids, :user_errors)

    ALT_MAX = 512

    class << self
      # 改檔案層 metadata（alt／filename）。
      #
      # 🔴 **要求 ready**（官方：`fileUpdate` 的 "Files must be in `ready` state before
      #   they can be updated."）；失敗態是終態、只能刪（官方
      #   `INVALID_FAILED_MEDIA_STATE`："File cannot be updated in a failed state."）。
      #
      # @param shop [Shop]
      # @param entries [Array<Hash>] `{ id:, alt:, filename: }`（後兩者可缺）
      # @return [Result]
      def update(shop:, entries:)
        files = []
        errors = []

        ActiveRecord::Base.transaction do
          entries.each_with_index do |entry, index|
            file, entry_errors = resolve(shop, entry[:id], index)
            attrs = nil
            if entry_errors.empty?
              entry_errors = update_state_errors(file, index)
              attrs, entry_errors = update_attributes(shop, file, entry, index) if entry_errors.empty?
            end
            if entry_errors.any?
              errors.concat(entry_errors)
              raise ActiveRecord::Rollback
            end

            file.update!(attrs) if attrs.present?
            files << file
          end
        end
        return Result.new(files: [], deleted_file_ids: [], user_errors: errors) if errors.any?

        Result.new(files:, deleted_file_ids: [], user_errors: [])
      end

      # 刪檔案：解除全部引用（並補位）→ 刪 row → commit 後刪 blob 與衍生。
      #
      # 🔴 **處理中的檔案不得刪**：`MediaPipeline::ProcessFile` 可能正在寫衍生檔，
      #   刪 row 會讓它寫完之後 `update!` 撞 RecordNotFound（漏成 500），而且新寫的
      #   衍生 blob 沒有任何東西指向它＝永久孤兒。官方對應碼＝`FILE_LOCKED`
      #   （逐字 "File has a pending operation."）。
      #
      # @param shop [Shop]
      # @param file_ids [Array<String>] GID
      # @return [Result]
      def delete(shop:, file_ids:)
        errors = []
        deleted = []
        blobs = []

        ActiveRecord::Base.transaction do
          file_ids.each_with_index do |gid, index|
            file, entry_errors = resolve(shop, gid, index, field_root: "fileIds")
            if entry_errors.any?
              errors.concat(entry_errors)
              raise ActiveRecord::Rollback
            end

            if file.status == "processing"
              errors << error([ "fileIds", index.to_s ],
                              I18n.t("errors.files.still_processing"), "FILE_LOCKED")
              raise ActiveRecord::Rollback
            end

            blobs << { key: file.storage_key, derivatives: derivative_keys(file) }
            detach_media!(file)
            file.destroy!
            deleted << "gid://chilllove/File/#{file.id}"
          end
        end
        return Result.new(files: [], deleted_file_ids: [], user_errors: errors) if errors.any?

        # commit 之後才動檔案系統（見檔頭④）。單一 blob 刪不掉不影響其他檔
        # ——row 已經沒了，剩下的孤兒佔空間但不會破圖。
        blobs.each do |blob|
          safe_unlink(blob[:key])
          blob[:derivatives].each { |key| safe_unlink(key) }
        end

        Result.new(files: [], deleted_file_ids: deleted, user_errors: [])
      end

      private

      # field path 兩種形狀：`fileUpdate` 的輸入是物件陣列 ⇒ ["files","0","id"]；
      # `fileDelete` 的是裸 ID 陣列 ⇒ ["fileIds","0"]（沒有第三段可指）。
      def resolve(shop, gid, index, field_root: "files")
        legacy_id = gid.to_s[%r{\Agid://chilllove/File/(\d+)\z}, 1]
        file = legacy_id && StoredFile.where(shop_id: shop.id).find_by(id: legacy_id.to_i)
        return [ file, [] ] if file

        field = field_root == "files" ? [ "files", index.to_s, "id" ] : [ field_root, index.to_s ]
        [ nil, [ error(field, I18n.t("errors.files.not_found"), "FILE_DOES_NOT_EXIST") ] ]
      end

      # 官方兩條狀態前置（見 `update` 的註釋）。
      def update_state_errors(file, index)
        if file.status == "failed"
          return [ error([ "files", index.to_s, "id" ],
                         I18n.t("errors.files.update_failed_state"), "INVALID_FAILED_MEDIA_STATE") ]
        end
        return [] if file.status == "ready"

        [ error([ "files", index.to_s, "id" ],
                I18n.t("errors.files.not_ready"), "NON_READY_STATE") ]
      end

      def update_attributes(shop, file, entry, index)
        attrs = {}

        if entry.key?(:alt)
          alt = entry[:alt].to_s
          if alt.length > ALT_MAX
            return [ {}, [ error([ "files", index.to_s, "alt" ],
                                 I18n.t("errors.files.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED") ] ]
          end

          attrs[:alt_text] = alt.presence
        end

        if entry[:filename].present?
          filename = entry[:filename].to_s
          if FilenameRules.violation(filename)
            return [ {}, [ error([ "files", index.to_s, "filename" ],
                                 I18n.t("errors.files.filename_invalid"), "INVALID_FILENAME") ] ]
          end
          # 🔴 同店同名擋下（官方 `FILENAME_ALREADY_EXISTS`）。排除自己——把檔名改成
          #    原本的值不該報「已存在」。
          taken = StoredFile.where(shop_id: shop.id, filename:).where.not(id: file.id).exists?
          if taken
            return [ {}, [ error([ "files", index.to_s, "filename" ],
                                 I18n.t("errors.files.filename_taken"), "FILENAME_ALREADY_EXISTS") ] ]
          end

          attrs[:filename] = filename
        end

        [ attrs, [] ]
      end

      # 刪掉引用這個檔的 media 列，**並把受影響商品的 position 補回 1..n**。
      #
      # 🔴 補位是官方明載的副作用（檔頭②）：刪掉中間那張圖之後剩下 [1,3,4]，
      #   下一次上傳算出的 `MAX(position)+1` 仍然對，但**拖曳排序的全量判準會對不上**
      #   ——媒體卡送的是完整 id 清單，服務端拿它重排時預期看到連續序。
      # 🔴 走 `destroy` 逐列而不是 `delete_all`：`Media#before_destroy` 才是釋放
      #   `file_usages` 的地方（第 27 包審查 C6）。
      def detach_media!(file)
        rows = Media.where(shop_id: file.shop_id, file_id: file.id).to_a
        product_ids = rows.filter_map(&:product_id).uniq
        rows.each(&:destroy!)
        product_ids.each do |product_id|
          product = Product.where(shop_id: file.shop_id).find_by(id: product_id)
          Catalog::MediaSync.compact_for!(shop: product.shop, product:) if product
        end
        # 保險：非 Media 擁有者的殘留 usage（未來的主題／頁面引用）也要清，
        # 否則 `dependent: :restrict_with_error` 會讓 destroy! **靜默回 false**。
        FileUsage.where(shop_id: file.shop_id, file_id: file.id).delete_all
        file.file_usages.reset
      end

      # `derivatives` 的值是 `{"key"=>…, "width"=>…, "height"=>…, "byte_size"=>…}`
      # （`MediaPipeline::ProcessFile#write_derivatives!` 寫的形狀），不是裸字串。
      def derivative_keys(file)
        return [] unless file.derivatives.is_a?(Hash)

        file.derivatives.values.filter_map { |entry| entry["key"] if entry.is_a?(Hash) }
      end

      def safe_unlink(key)
        LocalDisk.delete(key)
      rescue StandardError => e
        Rails.logger.warn("event=file_blob_delete_failed key=#{key} error=#{e.class}: #{e.message}")
      end

      def error(field, message, code) = { field:, message:, code: }
    end
  end
end
