# frozen_string_literal: true

module Catalog
  # 商品媒體的寫入引擎（第 27 包；28 §契約「媒體」列）。
  #
  # ①這是什麼：`media` 表的唯一寫入路徑——建立／更新 alt／刪除／重排／掛變體。
  #   五支 mutation 與 SaveProduct 的 `mediaOrder` 都經過這裡。
  # ②🔴 **position 兩階段落位**（整合規格 §1.4／§8-3）：`uq_media_product_id_position`
  #   是 **unique**（系列的 `ix_collection_products_collection_id_position` 不是），
  #   逐列 save! 交換兩張圖會撞 1062 ⇒ 留存者先整批挪負區間再落正
  #   （`Catalog::VariantSync#apply_matched!` 同型；`update_all` 後必 reload——
  #   P19 dirty-tracking 坑）。
  # ③position 語義：**1-based**，第一格＝精選圖（原型 `pd-media` 註釋逐字
  #   「第一張＝精選圖；拖曳排序即 position」）；`ProductType.featuredImage`
  #   取 position 最小的那列（第 26 包）。
  # ④變體掛圖：`limits.product.max_images_per_variant`（官方 1 張）＋
  #   **只接受 image**（官方明載變體不支援影片/3D，limits :887-889 出處）。
  # ⑤跨功能影響：`Storage::FileCreate`（originalSource 建檔）、`file_usages`
  #   （引用計數＝第 28 包刪除確認的數字來源）、`ProductType.featuredImage`、
  #   第 29 包變體子頁圖格。
  class MediaSync
    Result = Data.define(:media, :user_errors)

    OWNER_TYPE = "Media"
    # alt 上限＝DB 欄寬（media.alt_text limit 512）；兩條建立路徑共用同一個判準。
    ALT_MAX = 512

    class << self
      # 建立媒體（originalSource 建新檔／fileId 用既有檔，二選一）。
      # @param shop [Shop]
      # @param product [Product]
      # @param entries [Array<Hash>] [{original_source:, file_id:, alt:}]
      # @param idempotency_key [String, nil] 衍生 fileCreate 的鍵用
      # @return [Result]
      def create(shop:, product:, entries:, idempotency_key: nil)
        # 🔴 **檔案準備在 transaction 之外**（審查 C4/C15）：`Storage::FileCreate`
        #    會抓外部 URL（HTTP）並寫 blob——鐵律 5「transaction 內禁外部 IO」；
        #    包在交易裡還會讓外層 rollback 留下無主 blob。
        errors = []
        prepared = entries.each_with_index.map do |entry, index|
          file, entry_errors = resolve_file(shop, entry, index, idempotency_key)
          errors.concat(entry_errors)
          { file:, alt: entry[:alt] }
        end
        return Result.new(media: [], user_errors: errors) if errors.any?

        created = []
        begin
          ActiveRecord::Base.transaction do
            # 🔴 **鎖商品列**（審查 C0/C1/C3/C14/C21）：position 由
            #    `MAX(position)+1` 分配，而 `uq_media_product_id_position` 是 unique
            #    ——前端 `Promise.all` 逐檔並發送出，兩個請求讀到同一個 MAX 就撞 1062
            #    並漏成 500（實測重現）。`SaveProduct` 的更新路徑同樣用 FOR UPDATE
            #    序列化並發儲存，本處沿用。順帶讓容量檢查也在鎖內做（C1 的 TOCTOU）。
            locked = Product.lock.find_by(id: product.id)
            raise ActiveRecord::RecordNotFound if locked.nil?

            capacity_errors = validate_capacity!(locked, prepared.length)
            if capacity_errors.any?
              errors.concat(capacity_errors)
              raise ActiveRecord::Rollback
            end

            base_position = locked.media.maximum(:position).to_i
            prepared.each_with_index do |item, index|
              created << build_media!(shop, product, item[:file], item[:alt], base_position + index + 1)
            end
          end
        rescue ActiveRecord::RecordNotUnique
          # 第二道（鎖之外的意外並發／未來的其他寫入端）：不得漏成 500（鐵律 4）。
          return Result.new(media: [], user_errors: [ error([ "media" ],
            I18n.t("errors.media.position_conflict"), "CONFLICT") ])
        end
        return Result.new(media: [], user_errors: errors) if errors.any?

        Result.new(media: created, user_errors: [])
      end

      # 更新 alt（媒體層的 alt 才是權威——同一檔案掛不同商品可有不同 alt，
      # 第 26 包 ImageType 檔頭已載明）。
      def update(shop:, product:, entries:)
        errors = []
        updated = []
        ActiveRecord::Base.transaction do
          entries.each_with_index do |entry, index|
            row = product.media.find_by(id: entry[:id])
            if row.nil?
              errors << error([ "media", index.to_s, "id" ],
                I18n.t("errors.media.not_found"), "NOT_FOUND")
              raise ActiveRecord::Rollback
            end
            alt = entry[:alt].to_s
            if alt.length > ALT_MAX
              errors << error([ "media", index.to_s, "alt" ],
                I18n.t("errors.media.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED")
              raise ActiveRecord::Rollback
            end
            row.update!(alt_text: alt.presence)
            updated << row
          end
        end
        Result.new(media: errors.any? ? [] : updated, user_errors: errors)
      end

      # 刪除媒體：連動釋放 file_usages（引用計數↓），blob 由第 28 包的檔案庫決定去留
      # （93 實測文案：只刪「僅供此商品使用」的檔案，共用檔保留）。
      def delete(shop:, product:, media_ids:)
        errors = []
        deleted = []
        ActiveRecord::Base.transaction do
          media_ids.each_with_index do |media_id, index|
            row = product.media.find_by(id: media_id)
            if row.nil?
              errors << error([ "mediaIds", index.to_s ],
                I18n.t("errors.media.not_found"), "NOT_FOUND")
              raise ActiveRecord::Rollback
            end
            release_usage!(shop, row)
            deleted << row.id
            row.destroy!
          end
          compact_positions!(shop, product) if errors.empty?
        end
        Result.new(media: errors.any? ? [] : deleted, user_errors: errors)
      end

      # 重排：宣告式全量（送入順序即 position）。
      # 🔴 兩階段落位——見檔頭 ②。
      # @param media_ids [Array<Integer>] 必須恰為該商品的全部媒體 id
      def reorder(shop:, product:, media_ids:)
        existing = product.media.order(:position).to_a
        if media_ids.map(&:to_i).sort != existing.map(&:id).sort
          return Result.new(media: [], user_errors: [ error([ "mediaIds" ],
            I18n.t("errors.media.reorder_incomplete"), "INVALID") ])
        end

        by_id = existing.index_by(&:id)
        ActiveRecord::Base.transaction do
          shift_to_negative!(shop, existing)
          media_ids.each_with_index do |media_id, index|
            row = by_id.fetch(media_id.to_i)
            row.reload # update_all 繞過 dirty-tracking，不 reload 會靜默不發 UPDATE
            row.update!(position: index + 1)
          end
        end
        Result.new(media: product.media.reload.order(:position).to_a, user_errors: [])
      end

      # 變體掛圖（官方 productVariantAppendMedia）；media_id 為 nil＝卸下。
      def append_to_variant(shop:, product:, variant_id:, media_id:)
        variant = product.product_variants.find_by(id: variant_id)
        return Result.new(media: [], user_errors: [ error([ "variantId" ],
          I18n.t("errors.media.variant_not_found"), "NOT_FOUND") ]) if variant.nil?

        if media_id.nil?
          product.media.where(product_variant_id: variant.id).update_all(product_variant_id: nil)
          return Result.new(media: [], user_errors: [])
        end

        row = product.media.find_by(id: media_id)
        return Result.new(media: [], user_errors: [ error([ "mediaId" ],
          I18n.t("errors.media.not_found"), "NOT_FOUND") ]) if row.nil?
        # 官方明載：變體不支援影片／3D（limits :887-889）
        return Result.new(media: [], user_errors: [ error([ "mediaId" ],
          I18n.t("errors.media.variant_image_only"), "INVALID") ]) unless row.media_type == "image"

        max = Limits.fetch(:product, :max_images_per_variant)
        ActiveRecord::Base.transaction do
          # 每變體上限（官方 1 張）：掛新的之前，把「超出上限的舊圖」卸下。
          # 🔴 保留數＝max-1（新的那張佔一格）；`limit` 不可用——MySQL 不接受
          #    UPDATE ... LIMIT 搭配子查詢，且 limit(0) 會變成什麼都不卸（實測抓到）。
          attached = product.media.where(product_variant_id: variant.id)
                            .where.not(id: row.id).order(:position).to_a
          overflow = attached.drop([ max - 1, 0 ].max)
          if overflow.any?
            Media.where(shop_id: shop.id, id: overflow.map(&:id)).update_all(product_variant_id: nil)
          end
          row.update!(product_variant_id: variant.id)
        end
        Result.new(media: [ row ], user_errors: [])
      end

      # 補位到 1..n 連續的**公開入口**（第 28 包：檔案庫刪檔會連帶拿掉媒體列）。
      #
      # 🔴 為什麼要開這道口而不是讓呼叫端自己補：補位必須走兩階段落位
      #   （`uq_media_product_id_position` 是 unique，逐列 update 會撞 1062），
      #   那個知識屬於本服務。`Storage::FileWrite` 只該說「這個商品的媒體少了幾列，
      #   請補位」，不該知道負區間那一招。
      # 🔴 呼叫端必須自己在 transaction 裡（本方法不開交易——刪媒體與補位要原子）。
      #
      # @param shop [Shop]
      # @param product [Product]
      # @return [void]
      def compact_for!(shop:, product:) = compact_positions!(shop, product)

      private

      def error(field, message, code) = { field:, message:, code: }

      def validate_capacity!(product, incoming)
        total = product.media.count + incoming
        return [] if total <= Limits.fetch(:product, :max_media)

        [ error([ "media" ], I18n.t("errors.media.over_limit"), "MEDIA_LIMIT_EXCEEDED") ]
      end

      # originalSource ⇒ 走 Storage::FileCreate 建檔；file_id ⇒ 取既有檔（第 28 包選檔）。
      def resolve_file(shop, entry, index, idempotency_key)
        source = entry[:original_source].presence
        file_id = entry[:file_id].presence

        if source.present? == file_id.present?
          return [ nil, [ error([ "media", index.to_s ],
            I18n.t("errors.media.source_required"), "INVALID") ] ]
        end

        # alt 長度在兩條路徑都要驗（審查 C5：fileId 分支原本跳過，超長會在
        # Media.create! 拋 RecordInvalid 漏成 500 而不是 userErrors）
        if entry[:alt].to_s.length > ALT_MAX
          return [ nil, [ error([ "media", index.to_s, "alt" ],
            I18n.t("errors.media.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED") ] ]
        end

        if file_id
          file = StoredFile.find_by(id: file_id)
          return [ nil, [ error([ "media", index.to_s, "fileId" ],
            I18n.t("errors.files.source_missing"), "FILE_DOES_NOT_EXIST") ] ] if file.nil?

          return [ file, [] ]
        end

        result = Storage::FileCreate.call(shop:, files_input: [
          { original_source: source, alt: entry[:alt] }
        ])
        if result.user_errors.any?
          # 🔴 FileCreate 的 field 形如 ["files", "0", "originalSource"]——要砍掉的是
          #    **前兩段**（集合名＋它自己的批次 index，恆為 "0"，因為我們一次只送一筆）；
          #    只 drop(1) 會產出 ["media","1","0","originalSource"] 這種多一層的路徑，
          #    前端 SERVER_PATHS 對不上（審查 C17/C22）。
          return [ nil, result.user_errors.map { |e|
            e.merge(field: [ "media", index.to_s ] + Array(e[:field]).drop(2))
          } ]
        end

        [ result.files.first, [] ]
      end

      def build_media!(shop, product, file, alt, position)
        # 🔴 `media.status` 只是建立當下的快照，**不是真相**（審查 C2）：管線之後把
        #    `files.status` 轉 ready／failed 時不會回頭改這一列，凍結它會讓媒體卡
        #    永遠顯示「處理中」。讀取面（`Types::MediaType#status`）一律讀
        #    `stored_file.status`；本欄保留是 M0 建表遺產，寫入端不再依賴它。
        row = Media.create!(shop_id: shop.id, product_id: product.id, file_id: file.id,
                            media_type: "image", position:,
                            source_url: "/admin/files/#{file.id}/blob",
                            alt_text: alt.presence, status: file.status)
        # 引用計數（第 28 包刪除確認的唯一來源）
        FileUsage.find_or_create_by!(shop_id: shop.id, file_id: file.id,
                                     owner_type: OWNER_TYPE, owner_id: row.id)
        row
      end

      # 🔴 本方法只在 MediaSync.delete 用；`product.destroy!` 走 `dependent: :destroy`
      #    不經這裡——那條路徑的釋放改由 `Media` model 的 `before_destroy` 保證
      #    （審查 C6：polymorphic owner 沒有 FK，漏了就留 stale usage 讓引用計數虛高）。
      def release_usage!(shop, row)
        return if row.file_id.nil?

        FileUsage.where(shop_id: shop.id, file_id: row.file_id,
                        owner_type: OWNER_TYPE, owner_id: row.id).delete_all
      end

      # 刪除後補位（1..n 連續）——同樣要兩階段，否則補位過程會撞既有 position。
      def compact_positions!(shop, product)
        rows = product.media.reload.order(:position).to_a
        return if rows.empty? || rows.map(&:position) == (1..rows.length).to_a

        shift_to_negative!(shop, rows)
        rows.each_with_index do |row, index|
          row.reload
          row.update!(position: index + 1)
        end
      end

      def shift_to_negative!(shop, rows)
        return if rows.empty?

        Media.where(shop_id: shop.id, id: rows.map(&:id))
             .update_all("position = -position - 100000")
      end
    end
  end
end
