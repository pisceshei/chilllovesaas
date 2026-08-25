# frozen_string_literal: true

module Collections
  # 智慧系列全量重建（第 11 包；13 §F4.6-3；D50）。
  #
  # ①這是什麼：把一個系列的 sources 求值結果**整份**物化進 `collection_memberships`。
  #   觸發＝規則/來源變更 commit 後（SaveCollection enqueue）＋ `catalog:rebuild:collections`
  #   rake（`limits.catalog_flow.projection_rebuild_tasks`：商品線沒有 saga，只有可重跑的投影）。
  #
  # ②🔴 求值只有 SQL 一套（13 §F4.9）：成員集合由 `RuleCompiler` 的 WHERE 片段經
  #   `INSERT … SELECT` 直接落列——**沒有** Ruby 端逐商品求值的第二套實作。
  #   resync（增量）用同一段 WHERE 加商品 id 等值，語義構造上一致。
  #   🔴 「同一段」包含**商品層資格謂詞**（`RuleCompiler::PRODUCT_ELIGIBLE_SQL`）：
  #   初版只有 resync 擋 ARCHIVED、本服務沒擋 ⇒ 全量重建把封存商品塞回物化表，
  #   成員集合變成「取決於最後跑的是哪一支引擎」（2026-08-26 收斂輪 H4）。
  #
  # ③怎麼做到（世代戳＋批次＋逐批短鎖；13 §F4.9「rebuild 不能鎖住前台」）：
  #   1. 先把**全部** sources 編譯完（任何一條編不了 ⇒ 整個系列 `rebuild_status=ERROR`、
  #      **不部分寫入**——13 §F4.5(d) 的「不得部分寫入」同款紀律）。
  #   2. `generation`＝本輪時戳。逐 source、逐商品 id 批（`limits.collection.rebuild_batch_size`）
  #      跑 upsert 型 `INSERT … SELECT … ON DUPLICATE KEY UPDATE rebuilt_at = 世代`：
  #      既有列只推世代戳（不動 position），新列插入。每批自己一個短 transaction，
  #      批間前台照常讀舊物化列。
  #   3. 掃尾：刪掉本系列 `origin='conditions'` 且 `rebuilt_at` 落後本世代的列
  #      （＝這輪沒被任何 source 命中）。⇒ **連跑兩次列數不變**（13:716 的驗收錨，
  #      也是 variant_key 產生欄擋 NULL 重複的實證面）。
  #   4. 成員有變動 ⇒ `CacheStamps.bump_collection_members!`＋outbox `collections/update`
  #      （blueprint D.4；鐵律 5——外發只寫 outbox 列）。
  #
  # ④併發（研究 §5 的序列化點＝**collection 列鎖**，不是店鎖）：
  #   每個寫批在自己的 transaction 內先 `Collection.lock.find`——規則編輯服務也先鎖
  #   同一列再寫 rules ⇒ rebuild 讀到的規則必然是最新已提交版（REPEATABLE READ 快照
  #   陷阱的解法同 `handle_change.rb:71-73`：鎖定讀讀最新已提交版本）。
  #   resync 與 rebuild 交錯無害：兩者都在鎖下對同一份最新規則求值、都以收斂為語義。
  #
  # ⑤🔴 **rebuild 對 rebuild 必須整程序列化**（2026-08-26 審查 F2，gated-threads 實跑重現）：
  #   逐批列鎖只序列化「單一批」，**不序列化整場 rebuild**——兩場同系列 rebuild 交錯時，
  #   晚開場但先拿到批鎖的一方會用**較小的世代戳**蓋掉現任列（初版 ON DUPLICATE 無條件
  #   `rebuilt_at = 世代`），另一方的掃尾（`rebuilt_at < 世代`）接著把這些**本該留下**的列
  #   全刪——重現輸出＝BASELINE members=[1282]／FINAL members=[]，兩場都回報 OK。
  #   防線兩道：
  #   a) **MySQL advisory lock**（`GET_LOCK('chilllove:rebuild:<shop>:<collection>')`）鎖住
  #      整場 rebuild（含 sources 讀取與編譯——晚到者必見最新已提交規則），等待預算
  #      `limits.collection.rebuild_lock_wait_seconds`；等不到＝讓位（RebuildJob 延後重排，
  #      不靜默丟——跑者可能在本 job 的規則版本之前編譯）。連線死掉鎖自動釋放（MySQL 語義）。
  #   b) **世代戳單調帶**：upsert 改 `GREATEST(COALESCE(rebuilt_at, 世代), 世代)`——即使 a)
  #      被繞過（新呼叫點不走本服務之類），舊世代也**降不了**現任列的戳，掃尾就刪不掉它們。
  #      🔴 `COALESCE` 不是裝飾：`rebuilt_at` 可空（schema 無 `null: false`；日後的
  #      manual／nested／app origin 物化不必然帶世代戳），而 MySQL 的 `GREATEST(NULL, x)`
  #      **回 NULL** ⇒ 少了 COALESCE，一列 NULL 戳會變成「再也蓋不上戳、也掃不掉」的
  #      不死列（掃尾的 `< 世代` 在三值邏輯下同樣漏掉 NULL）。掃尾因此也顯式收 NULL
  #      ——與 F1 的否定條件同一個三值邏輯坑（2026-08-26 自查 F7）。
  class Rebuild
    Result = Data.define(:status, :inserted, :swept, :error)
    # 檔頭⑤a 的讓位訊號（RebuildJob 據此延後重排，不靜默丟）。
    LOCK_TIMEOUT_ERROR = "rebuild lock wait timeout"
    # `where_sql` 的代入槽（見 `upsert_batch`）：模板先 sanitize，之後才把編譯好的
    # 片段換進來。內容不含 `?`、不含引號，且不可能出現在 bind 值（全是 id 與時戳）裡。
    WHERE_SLOT = "/*__CHILLLOVE_WHERE__*/"

    class << self
      # @param shop [Shop]
      # @param collection [Collection] smart（有 conditions source）
      # @return [Result] status ∈ [:ok, :error, :skipped]
      # @note 副作用：寫 memberships／collections.rebuild_status／cache stamp／outbox。
      def call(shop:, collection:)
        ActsAsTenant.with_tenant(shop) do
          with_rebuild_lock(shop, collection) do
            rebuild!(shop, collection)
          end
        end
      end

      # 成員變動的兩個對外面（resync 也用；一處實作）。
      def notify_members_changed!(shop, collection)
        # cache stamp（唯一寫入面＝CacheStamps；`update_all` 帶 lock_version 守則在那一支裡）。
        Catalog::CacheStamps.bump_collection_members!(shop.id, collection.id)
        # 外部事件（blueprint D.4）：outbox 形態，鐵律 5。
        EventOutbox.create!(
          event_id: SecureRandom.uuid,
          topic: Events::Topics::COLLECTIONS_UPDATE,
          aggregate_type: "Collection",
          aggregate_id: collection.id,
          shop_id: shop.id,
          available_at: Time.current,
          payload: { collection_id: collection.id, members_changed: true }
        )
      end

      private

      # 檔頭⑤a：整場 rebuild 的 advisory lock；等不到＝讓位（LOCK_TIMEOUT_ERROR）。
      def with_rebuild_lock(shop, collection)
        # 檔頭⑤a：advisory lock 綁「這條連線」——同執行緒後續語句同連線（Rails 連線池
        # per-thread checkout），構造上成立。鎖名 <64 字元（MySQL 上限）。
        lock_name = "chilllove:rebuild:#{shop.id}:#{collection.id}"
        wait = Limits.fetch(:collection, :rebuild_lock_wait_seconds)
        got = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array([ "SELECT GET_LOCK(?, ?)", lock_name, wait ])
        ).to_i
        unless got == 1
          Rails.logger.warn({ event: "collection_rebuild_lock_timeout", shop_id: shop.id,
                              collection_id: collection.id, wait_seconds: wait }.to_json)
          return Result.new(status: :skipped, inserted: 0, swept: 0, error: LOCK_TIMEOUT_ERROR)
        end

        begin
          yield
        ensure
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array([ "SELECT RELEASE_LOCK(?)", lock_name ])
          )
        end
      end

      def rebuild!(shop, collection)
        # 🔴 非智慧系列才是「與本服務無關」＝跳過（手動成員在 collection_products，
        #   不歸這裡管）。**零 source 的智慧系列不是跳過，是「成員集合＝空集合」**——
        #   2026-08-26 收斂輪 G1：初版在 `sources.empty?` 就早退，而早退點在**世代掃尾
        #   之前** ⇒ 商家把條件清成 `sources: []`（契約明文的「空陣列＝清除」、本包
        #   request spec 自己在測的合法輸入）之後，先前物化的成員**永久殘留**，
        #   `rebuild_status` 永遠停在 PENDING，且三條清理路徑同時照不到它
        #   （早退不掃尾／resync 與 rake 的工作清單都從 `collection_sources` 導出，
        #   該系列已無 source 列）。殘留列不是死資料：`compile_collection_exclusion`
        #   讀 memberships ⇒ **另一個**系列會繼續把這些幽靈成員減掉，成員判定當場出錯。
        return Result.new(status: :skipped, inserted: 0, swept: 0, error: nil) unless collection.collection_type == "smart"

        sources = CollectionSource.where(shop_id: shop.id, collection_id: collection.id)
                                  .conditions_type.includes(:rules).order(:position).to_a

        # ③-1：全部先編譯，編不了就 ERROR、零寫入。零 source ⇒ 空編譯清單，
        #   下面的批次迴圈不插任何列、掃尾把舊成員全清——語義上正確且與
        #   `sources: [{rules: []}]`（空條件集）走同一條路。
        compiled = compile_all!(shop, collection, sources)
        return compiled if compiled.is_a?(Result)

        generation = Time.current
        batch_size = Limits.fetch(:collection, :rebuild_batch_size)
        Product.where(shop_id: shop.id).in_batches(of: batch_size) do |batch|
          ids = batch.ids
          next if ids.empty?

          Collection.transaction do
            Collection.lock.find_by!(shop_id: shop.id, id: collection.id)
            compiled.each do |source, where_sql|
              next if where_sql.nil?   # 空 inclusion＝該來源貢獻空集合

              upsert_batch(shop, collection, source, where_sql, ids, generation)
            end
          end
        end

        swept = 0
        inserted = 0
        Collection.transaction do
          Collection.lock.find_by!(shop_id: shop.id, id: collection.id)
          # 🔴 「有沒有變」不能看 affected_rows：`ON DUPLICATE KEY UPDATE rebuilt_at`
          #   對既有列**每輪都**改世代戳（MySQL 記 affected=2）⇒ 拿它當變更訊號，
          #   內容沒變的 rebuild 也會白白打掉快取＋發事件（初版 smoke 實測抓到）。
          #   新列的判準＝`created_at >= generation`——ON DUPLICATE 不動 created_at，
          #   只有真 INSERT 會設，構造上精確。
          inserted = CollectionMembership
                     .where(shop_id: shop.id, collection_id: collection.id, origin: "conditions")
                     .where(created_at: generation..).count
          # `rebuilt_at IS NULL` 顯式納入：三值邏輯下 `NULL < 世代`＝NULL，
          # 純 range 條件會把 NULL 戳的陳舊列永遠留在系列裡（檔頭⑤b）。
          swept = CollectionMembership
                  .where(shop_id: shop.id, collection_id: collection.id, origin: "conditions")
                  .where("collection_memberships.rebuilt_at IS NULL OR collection_memberships.rebuilt_at < ?", generation)
                  .delete_all
          collection.update_columns(rebuild_status: "OK", rebuilt_at: generation,
                                    updated_at: Time.current)
        end

        notify_members_changed!(shop, collection) if inserted.positive? || swept.positive?
        Result.new(status: :ok, inserted:, swept:, error: nil)
      end

      # @return [Array<[CollectionSource, String|nil]>] 或 ERROR Result
      def compile_all!(shop, collection, sources)
        sources.map do |source|
          # 🔴 unknown 型別＝存而不編（passthrough），但**引擎不能假裝會算**：
          #   含 unknown 的來源照 all/any 語義都無法既忠實又靜默 ⇒ 整系列 ERROR＋告警，
          #   不做「跳過那一條」那種會靜默放寬/收窄集合的事。
          if source.rules.any? { |rule| rule.condition_type == "unknown" || rule.raw_payload.present? }
            mark_error!(shop, collection, "來源 #{source.id} 含未知條件型別（passthrough 列）")
            return Result.new(status: :error, inserted: 0, swept: 0,
                              error: "unknown condition type")
          end
          [ source, RuleCompiler.where_sql(source) ]
        end
      rescue RuleCompiler::Unsupported => e
        mark_error!(shop, collection, e.message)
        Result.new(status: :error, inserted: 0, swept: 0, error: e.message)
      end

      def mark_error!(shop, collection, message)
        collection.update_columns(rebuild_status: "ERROR", updated_at: Time.current)
        Rails.logger.error({ event: "collection_rebuild_error", shop_id: shop.id,
                             collection_id: collection.id, error: message }.to_json)
      end

      # upsert 型批次寫入。🔴 兩類動態片段的注入安全各有出處：
      #   - `where_sql`＝RuleCompiler 產物，值已在編譯期綁定、識別字全部字面；
      #   - id 清單＝`in_batches` 的整數主鍵，逐一 `Integer()` 強轉後才進 SQL——
      #     不是「相信它是整數」，是**構造上只能是整數**（非整數在這裡就炸）。
      #   其餘值一律 `sanitize_sql_array` 佔位符。
      def upsert_batch(shop, collection, source, where_sql, ids, generation)
        id_list = ids.map { |id| Integer(id) }.join(",")
        now = Time.current
        # 🔴 `where_sql` **在 sanitize 之後才代入**（2026-08-26 收斂輪 H1／H2；
        #   理由全文在 `RuleCompiler#bind` 上方）。兩件事同時被這個順序解決：
        #   ①`sanitize_sql_array` 只看得到本模板自己的 `?`，商家值裡的 `?`
        #     （`"Why not?"`）不再被 `count("?")` 誤算成佔位符；
        #   ②`.squish` 只作用在模板上，壓不到商家值字面量**內部**的空白
        #     （`'紅玫瑰  禮盒'` 保持兩個空白，rebuild 與 resync 因此同答案）。
        #   代入用 `sub` 的 **block 形式**：block 形式不解讀 `\0`／`\1`／`\&`
        #   反向參照，值裡的反斜線因此原樣保留（字串形式會被當替換指令解析）。
        template = <<~SQL.squish
          INSERT INTO collection_memberships
            (shop_id, collection_id, product_id, variant_id, origin, origin_source_id,
             position, rebuilt_at, created_at, updated_at)
          SELECT ?, ?, p.id, NULL, 'conditions', ?, 0, ?, ?, ?
          FROM products p
          WHERE p.shop_id = ? AND p.id IN (#{id_list})
            AND #{RuleCompiler::PRODUCT_ELIGIBLE_SQL} AND (#{WHERE_SLOT})
          ON DUPLICATE KEY UPDATE rebuilt_at = GREATEST(COALESCE(rebuilt_at, ?), ?)
        SQL
        sql = ActiveRecord::Base.sanitize_sql_array(
          [ template, shop.id, collection.id, source.id, generation, now, now, shop.id, generation, generation ]
        ).sub(WHERE_SLOT) { where_sql }
        ActiveRecord::Base.connection.execute(sql)
        nil   # affected_rows 對 ON DUPLICATE 是 2/列，不是變更訊號——變更判定見 call 內註釋
      end
    end
  end
end
