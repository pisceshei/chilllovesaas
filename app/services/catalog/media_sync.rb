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
    # alt 上限＝limits `media.alt_max_length`（鐵律 6；官方逐字出處見該鍵註釋）。
    # D48 之後權威在 `files.alt_text`，三個服務共用同一個鍵、不再各自硬編。
    ALT_MAX = Limits.fetch(:media, :alt_max_length)

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
          # 🔴 **先分派再解析**（第 37 包）：外嵌影片沒有檔案，走 `resolve_file` 會掉進
          #    `Storage::FileCreate` → `SafeFetch` 去抓一份 YouTube 的 HTML，
          #    使用者看到的錯誤訊息與真實原因完全無關。
          if external_video_entry?(entry)
            item, entry_errors = resolve_external_video(entry, index)
          else
            file, entry_errors = resolve_file(shop, entry, index, idempotency_key)
            item = { kind: :file, file:, alt: entry[:alt] }
          end
          errors.concat(entry_errors)
          item
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
              position = base_position + index + 1
              created <<
                if item[:kind] == :external_video
                  build_external_video!(shop, product, item, position)
                else
                  build_media!(shop, product, item[:file], item[:alt], position)
                end
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

      # 更新 alt。
      #
      # 🔴 **寫的是 `files.alt_text` 不是 `media.alt_text`**（D48，2026-08-25 使用者裁定
      #   「所有的都跟 Shopify」）：本尊一張圖只有一份說明，在商品頁改 alt 會影響
      #   所有用到這張圖的商品，而且**不給警告**。第 26 包那句「媒體層才是權威」
      #   已被推翻。
      # 🔴 這代表 `productUpdateMedia` 的副作用比它的名字大——它動的是檔案。
      #   前端沒有額外提示是**刻意對齊**，不是漏做。
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
            # 沒送 alt ⇒ 什麼都不動（見 `product_update_media.rb` 的 `key?` 註）。
            unless entry.key?(:alt)
              updated << row
              next
            end

            alt = entry[:alt].to_s
            if alt.length > ALT_MAX
              errors << error([ "media", index.to_s, "alt" ],
                I18n.t("errors.media.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED")
              raise ActiveRecord::Rollback
            end
            # 🔴 外嵌影片沒有檔案，媒體列就是 alt 的唯一落點（D48 的窄縫，裁定 C5）。
            #   沒有這一段的話外嵌影片的 alt **永遠改不了**——會落到下面的
            #   「無處可寫」分支回 NOT_FOUND，而那個訊息與真實原因完全無關。
            if row.external_video?
              row.update!(alt_text: alt.presence)
              updated << row
              next
            end
            # 沒有檔案的媒體列（M0 遺產，`file_id` nullable）無處可寫 alt。
            file = row.stored_file
            if file.nil?
              errors << error([ "media", index.to_s, "id" ],
                I18n.t("errors.media.not_found"), "NOT_FOUND")
              raise ActiveRecord::Rollback
            end
            # 🔴 **這裡刻意不套 `fileUpdate` 的 ready 前置**，理由不是「懶得對齊」：
            #    官方那條限制掛在 `fileUpdate` 上，而 `fileUpdate` 還能換
            #    `originalSource`／`previewImageSource`——**換內容**與處理管線真的衝突，
            #    所以要求 ready 有它的道理。本路徑只寫 alt，而管線
            #    （`MediaPipeline::ProcessFile`）只動 status／derivatives／processing_error，
            #    從不碰 alt_text ⇒ 沒有衝突可言。
            #    套上去的實際後果是：使用者剛拖進一張圖、趁處理中打 alt 會被拒——
            #    多一個本尊沒有明文要求的失敗態。⚠️ 本尊 `productUpdateMedia` 是否要求
            #    ready＝**未取得**（官方只對 fileUpdate 明文）；查得到再回頭對齊。
            file.update!(alt_text: alt.presence)
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
          # 🔴 **鎖商品列**（審查 VIS-4）：下面是「讀出已掛的圖 → 卸超額 → 掛新的」
          #    三步 read-then-write，中間沒有任何列鎖，而
          #    `ix_media_product_variant_id` **不是 unique** ⇒ DB 層也沒有
          #    「一個變體最多一張圖」的約束。兩個請求同時給同一變體掛不同的圖，
          #    兩邊都讀到「目前 0 張」⇒ 兩邊都不卸 ⇒ 掛完是 2 張，超過官方上限 1。
          #    同檔 `create` 為完全同型的並發問題已取 `Product.lock`（見上），本處沿用。
          locked = Product.lock.find_by(id: product.id)
          raise ActiveRecord::RecordNotFound if locked.nil?

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

      # 這一筆是不是外嵌影片（第 37 包）。
      #
      # 兩種判定：①`mediaContentType: EXTERNAL_VIDEO` 顯式指定 ②**型別省略但
      # `originalSource` 的 host 命中 YouTube／Vimeo**（ours）。②的理由＝不這樣做，
      # 使用者貼 YouTube URL 會掉進 `Storage::FileCreate` 去抓 HTML，錯誤訊息與
      # 真實原因無關。官方 `fileCreate` 有「contentType 可省略、平台自行判斷」的
      # 先例，但那是**別支 mutation**，所以本規則標 ours 不標「對齊」。
      # 🔴 判準是 `external_video_candidate?`（host 命中）**不是「parse 成功」**
      #   （審查 EVU-2）：`shorts/x` 是「認得的平台、抽不出 id」，用 parse 成功當
      #   判準會把它分派去 FileCreate——伺服器對 youtube.com 抓一份 HTML、回
      #   UNACCEPTABLE_ASSET，而 Shorts 專屬的「可改成 watch 形態」引導訊息
      #   永遠不會出現。host 命中就進外嵌分支，成敗由 parse 在分支內回報。
      # 🔴 顯式 `IMAGE` 不套用②——使用者明說是圖片就照圖片走。
      def external_video_entry?(entry)
        declared = entry[:media_content_type].to_s.presence
        return true if declared == "external_video"
        return false if declared.present?

        source = entry[:original_source].presence
        source.present? && Catalog::ExternalVideoUrl.external_video_candidate?(source)
      end

      # 外嵌影片的解析（**零外部 IO**——見 `ExternalVideoUrl` 檔頭②）。
      def resolve_external_video(entry, index)
        if entry[:file_id].present?
          # 外嵌沒有檔案可選——給了 fileId 就是語義矛盾。
          return [ nil, [ error([ "media", index.to_s, "fileId" ],
            I18n.t("errors.media.external_video_no_file"), "INVALID") ] ]
        end

        if entry[:alt].to_s.length > ALT_MAX
          return [ nil, [ error([ "media", index.to_s, "alt" ],
            I18n.t("errors.media.alt_too_long"), "ALT_VALUE_LIMIT_EXCEEDED") ] ]
        end

        parsed = Catalog::ExternalVideoUrl.parse(entry[:original_source])
        if parsed.is_a?(Catalog::ExternalVideoUrl::Rejection)
          code = parsed.code == :unsupported_host ? "EXTERNAL_VIDEO_UNSUPPORTED_HOST" : "EXTERNAL_VIDEO_INVALID_URL"
          return [ nil, [ error([ "media", index.to_s, "originalSource" ],
            I18n.t(parsed.message_key), code) ] ]
        end

        [ { kind: :external_video, host: parsed.host, external_id: parsed.external_id,
            origin_url: parsed.origin_url, alt: entry[:alt] }, [] ]
      end

      # 🔴 **不建 `files` 列、不寫 `file_usages`**（裁定 C4）：`files` 的 `byte_size`／
      #   `checksum`／`content_type`／`storage_key`(unique) 全是 `null: false`，塞一個
      #   沒有 bytes 的實體就得把那些 NOT NULL 全部可空化＝拆掉既有防線。
      #   代價＝外嵌影片不出現在檔案庫（本尊是否如此＝未取得 U7），登記 V。
      # 🔴 `status` 建立即 `ready`：A 面沒有非同步驗證鏈（B 面 oEmbed 才有）。
      #   **這是已知偏離**——本尊建立時是 `UPLOADED`（官方範例逐字），登記 V（U10）。
      def build_external_video!(shop, product, item, position)
        Media.create!(
          shop_id: shop.id, product_id: product.id, file_id: nil,
          media_type: "external_video", position:,
          external_host: item[:host], external_id: item[:external_id],
          # 存的是**重建**的 origin URL，不是使用者原字串（`ExternalVideoUrl` 檔頭②）。
          source_url: item[:origin_url],
          alt_text: item[:alt].presence,
          status: "ready"
        )
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

        # `FileCreate` 本來就把 alt 寫進 `files.alt_text`（D48 之後那正是權威所在），
        # 所以這條路徑不必也不該再寫一次。
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

      # @param alt [String, nil] 建立時附帶的 alt。**寫進檔案不寫進媒體列**（D48）；
      #   `nil`＝不動檔案既有的 alt（掛既有檔案時常見：檔案庫早就寫好了說明，
      #   掛到商品上不該把它清成 nil）。
      def build_media!(shop, product, file, alt, position)
        # 🔴 `media.status` 只是建立當下的快照，**不是真相**（審查 C2）：管線之後把
        #    `files.status` 轉 ready／failed 時不會回頭改這一列，凍結它會讓媒體卡
        #    永遠顯示「處理中」。讀取面（`Types::MediaType#status`）一律讀
        #    `stored_file.status`；本欄保留是 M0 建表遺產，寫入端不再依賴它。
        row = Media.create!(shop_id: shop.id, product_id: product.id, file_id: file.id,
                            media_type: "image", position:,
                            source_url: "/admin/files/#{file.id}/blob",
                            status: file.status)
        # 🔴 D48：alt 落在**檔案**上。只在有給值時寫——沒給就保留檔案既有的 alt
        #    （掛既有檔案的常見情形），寫 nil 會把檔案庫裡寫好的說明清掉。
        file.update!(alt_text: alt) if alt.present?
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
