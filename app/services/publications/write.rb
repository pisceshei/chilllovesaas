# frozen_string_literal: true

module Publications
  # Publication 生命週期的**唯一寫入入口**（S1）。
  #
  # 三支 mutation（`publicationCreate`／`publicationUpdate`／`publicationDelete`）都只是
  # 這裡的薄殼；業務規則一律住在這裡，避免「同一條規則在 GraphQL 層寫三次」。
  #
  # ## 🔴 這是本倉庫第一條 `resource_publications` 的**非建立**寫入路徑
  #
  # 在 S1 之前，`resource_publications.published_at` 只在**建立時**被寫入
  # （`Publications::Materialize` 的兩條路徑 ＋ 兩支 migration 的原生 SQL），
  # **全倉零 UPDATE、零 DELETE、零 publish／unpublish 入口**。
  # ⇒ 「進行中的發布操作鎖」（`publications.operation_status`）在 S1 之前是**空掛的**
  #   ——沒有可被鎖住的動作。本檔就是那個動作。
  #
  # ## 本尊對位（逐條，取證 2026-08-26）
  #
  # | 我方 | 本尊 | 官方原文逐字 |
  # |---|---|---|
  # | `.create` | `publicationCreate(input: PublicationCreateInput!)` | `Creates a Publication that controls which Product and Collection customers can access through a Catalog.` |
  # | `.update` | `publicationUpdate(id: ID!, input: PublicationUpdateInput!)` | `You can add or remove products from the publication, with a maximum of 50 items per operation.` |
  # | `.delete` | `publicationDelete(id: ID!)` | `Deletes a publication.`（全文只有這一句） |
  #
  # 🔴 **`publicationDelete` 的副作用官方完全沉默**——既沒說會級聯刪 resource publications，
  # 也沒說不會。我方的處置是 ours 裁定（見 `.delete` 的註釋），**不得寫成照抄本尊**。
  #
  # @see docs/plans/2026-08-26-S1-規格草案.md
  # @see docs/dev/m2-publication-lifecycle.md
  module Write
    # 一次寫入的結果。`user_errors` 非空時 `publication` 為 nil（或未被修改的原物件）。
    Result = Struct.new(:publication, :user_errors, keyword_init: true) do
      def ok? = user_errors.empty?
    end

    # `publishablesToAdd`／`publishablesToRemove` 接受的 GID 型別。
    # 🔴 由 `ResourcePublication::PUBLISHABLE_TYPES` 導出，**不另寫一份清單**（鐵律 7）——
    #   同型教訓見 `Publications::Materialize.publishable_scopes` 的註釋。
    def self.publishable_types = ResourcePublication::PUBLISHABLE_TYPES

    module_function

    # 建立一個 publication。
    #
    # ## 與本尊的三處對位與一處刻意不做
    #
    # - `autoPublish` 官方 `Default:false`（`PublicationCreateInput` 頁明文 `Default:false`）
    #   ⇒ 我方預設同為 false。⚠️ 注意這與 `Shop#create_default_publication` 建的
    #   線上商店管道（明文傳 `auto_publish: true`）**不衝突**：那是建店流程的顯式選擇，
    #   不是 input 的預設值。
    # - `defaultState` 官方 `Default:EMPTY`，值域恰兩個（`EMPTY`／`ALL_PRODUCTS`）。
    # - `catalogId` 官方是 **nullable**（`ID` 不是 `ID!`），描述只有 `The ID of the catalog.`。
    #   ⚠️ **「省略時實際會怎樣」＝官方未取得**；我方的處置是「省略就自己建一個 catalog」，
    #   理由：我方 `publications.sales_catalog_id` 有外鍵、且顯示名的權威在
    #   `sales_catalogs.title`（S0 PR A）⇒ 沒有 catalog 的 publication 沒有名字可顯示。
    #
    # 🔴 **`ALL_PRODUCTS` 目前明文不支援**，回 `FEATURE_NOT_ENABLED`：
    #   本尊那條路是 `AddAllProductsOperation`（非同步、帶 `processedRowCount`／`rowCount`
    #   進度，`ResourceOperationStatus` 恰三值），我方**完全沒有進度欄位的落點**，
    #   加了就是第二個零消費者欄位（`publications.catalog_id` 空轉兩週那個坑的同型）。
    #   ⇒ 誠實拒絕 ＋ 登記，**不做「同步跑一遍假裝是它」**（那會在商品多時把請求跑爆，
    #   而且與本尊的非同步語義分岔）。
    #
    # @param shop [Shop]
    # @param title [String] 顯示名（寫進 `sales_catalogs.title`——權威來源）
    # @param auto_publish [Boolean]
    # @param default_state [String] `EMPTY`／`ALL_PRODUCTS`
    # @param sales_catalog [SalesCatalog, nil] 既有 catalog；nil＝本方法建一個
    # @return [Result]
    # @note 副作用：INSERT `publications`；`sales_catalog` 為 nil 時另 INSERT `sales_catalogs`。
    def create(shop:, title:, auto_publish: false, default_state: "EMPTY", sales_catalog: nil)
      if default_state.to_s == "ALL_PRODUCTS"
        return reject("defaultState", I18n.t("errors.publication.all_products_unsupported"), "FEATURE_NOT_ENABLED")
      end

      # 🔴 **一個 catalog 最多一個 publication**，這是我方 `SalesCatalog has_one :publication`
      #   的模型宣告，但**在此之前沒有任何東西擋它**（`publications.sales_catalog_id`
      #   沒有唯一索引）。第二個 publication 共用同一個 catalog 會撞到的是
      #   `channel_handle` 的唯一性（佔位值由 catalog id 導出）——那是**症狀不是根因**，
      #   而且錯誤訊息會指向一個呼叫端根本沒有傳的欄位。
      #   ⚠️ 本輪由「catalog 還被別的 publication 用著時不得刪」那格 spec 當場抓到。
      #   ⚠️ **不加 DB 唯一索引**：本尊的 `Publication : Catalog` 是 1:1 還是 1:N ＝**未取得**
      #     （S1 規格草案 U-19）。在那之前把 1:1 硬寫進 schema 是把未取得寫成事實。
      # 🔴 這段**必須在 `with_tenant` 之內**：`Publication` 宣告 `acts_as_tenant`，
      #   而 `require_tenant = true` ⇒ 在租戶外查它是 `NoTenantSet` 而不是空集合。
      ActsAsTenant.with_tenant(shop) do
        if sales_catalog && Publication.where(sales_catalog_id: sales_catalog.id).exists?
          return reject("catalogId", I18n.t("errors.publication.catalog_taken"), "TAKEN")
        end

        ApplicationRecord.transaction do
          catalog = sales_catalog || shop.sales_catalogs.create!(
            catalog_type: "app",
            title: title,
            status: "active"
          )

          publication = shop.publications.create!(
            sales_catalog: catalog,
            name: title,
            # 🔴 `channel_handle` 自 S0 PR B 起是 **legacy 快照**，權威在 `channels.handle`。
            #   API 建立的 publication **沒有 channel**（channel 是 app 的身分，來自安裝流程）
            #   ⇒ 這裡只能寫一個不與任何管道衝突的佔位值。用 catalog id 保證每店唯一。
            channel_handle: "catalog-#{catalog.id}",
            auto_publish: auto_publish,
            supports_future_publishing: true
          )

          Result.new(publication:, user_errors: [])
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      invalid_result(error, field_root: "input")
    end

    # 更新一個 publication：`autoPublish` 與批次加／減 publishable。
    #
    # 🔴 **累加／扣除語義，不是狀態編輯器**（`docs/research/82` §11.5 實測）：
    #   本尊的發布 modal 一律以「全部未勾」開場，即使選取的商品已經在某些管道上。
    #   ⇒ 沒被列在 `publishables_to_remove` 的資源**不會**被移除。
    #   把它做成宣告式全量（未列出＝移除）會讓商家的一次勾選清空整個管道。
    #
    # 🔴 **重複 add 是 no-op success**（本尊官方逐字：`If the variant is already published to
    #   that publication, the mutation succeeds with no change.`）⇒ 用 `find_or_create_by`，
    #   DB 兜底是既有的 `uq_res_pub_target` 唯一索引。
    #
    # 🔴 **刻意逐列 `find_or_create_by` 而不是 `insert_all`**：多型的 `publishable` 側
    #   **沒有資料庫外鍵**，唯一那道租戶守衛是 `ResourcePublication#publishable_belongs_to_same_shop`
    #   （一個 model validation）⇒ `insert_all` 會直接繞過它，寫出跨租戶的列而不拋任何錯。
    #   這個缺口已在 `resource_publication.rb` 與 `docs/dev/m2-publication-model.md` §6 登記，
    #   而 S1 是**第一個真的會踩到它的批次寫入者**（50 筆一批很自然會寫 `insert_all`）。
    #   代價是 N 次 INSERT，而 N ≤ 50（見下）。
    #
    # @param shop [Shop]
    # @param publication [Publication]
    # @param auto_publish [Boolean, nil] nil＝不動（缺席＝保持現值）
    # @param publishables_to_add [Array<String>] GID
    # @param publishables_to_remove [Array<String>] GID
    # @param at [Time] 發布時刻
    # @return [Result]
    # @note 副作用：UPDATE `publications`；INSERT／DELETE `resource_publications`；
    #   bump 受影響商品的 `publications_updated_at`。
    def update(shop:, publication:, auto_publish: nil, publishables_to_add: [], publishables_to_remove: [], at: Time.current)
      to_add = Array(publishables_to_add)
      to_remove = Array(publishables_to_remove)

      # 🔴 **合計 ≤ 上限，不是各自 ≤ 上限**。官方兩句措辭不同
      #   （input object 頁 `...to update simultaneously is 50.`；
      #    mutation 頁 `...with a maximum of 50 items per operation.`），
      #   **都沒有指明是各自還是合計** ⇒ fail-closed 取較嚴的一側，並登記為 ours 加嚴。
      #   取得證據後（測試店以 add／remove 各 26 個實測）再放寬。
      cap = Limits.fetch(:sales_channels, :publication_bulk_products_max)
      if to_add.size + to_remove.size > cap
        return reject("input", I18n.t("errors.publication.batch_too_big", cap: cap), "TOO_BIG")
      end

      ActsAsTenant.with_tenant(shop) do
        added, add_errors = resolve_publishables(shop:, gids: to_add, field: "publishablesToAdd")
        removed, remove_errors = resolve_publishables(shop:, gids: to_remove, field: "publishablesToRemove")
        errors = add_errors + remove_errors
        return Result.new(publication: nil, user_errors: errors) if errors.any?

        ApplicationRecord.transaction do
          publication.update!(auto_publish:) unless auto_publish.nil?

          added.each do |record|
            ResourcePublication.find_or_create_by!(
              shop_id: shop.id,
              publication_id: publication.id,
              publishable_type: record.class.name,
              publishable_id: record.id
            ) { |row| row.published_at = at }
          end

          removed.each do |record|
            ResourcePublication.where(
              shop_id: shop.id,
              publication_id: publication.id,
              publishable_type: record.class.name,
              publishable_id: record.id
            ).destroy_all
          end

          bump_stamps!(shop_id: shop.id, records: added + removed, at:)
          Result.new(publication: publication.reload, user_errors: [])
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      invalid_result(error, field_root: "input")
    end

    # 刪除一個 publication。
    #
    # 🔴 **官方對副作用完全沉默**（`publicationDelete` 全文只有 `Deletes a publication.`），
    #   以下三條全部是 **ours 裁定**，不得讀成照抄本尊：
    #
    # 1. **有 channel 的 publication 不可刪**。channel 是 app 的身分（S0：`channels.app_installation_id`
    #    指向安裝），移除它是**卸載管道**不是刪 publication。這條與本尊的錯誤碼家族同構——
    #    本尊有 `CANNOT_MODIFY_APP_CATALOG_PUBLICATION`（逐字
    #    `Can't modify a publication that belongs to an app catalog.`）。
    #    ⚠️ 沒有這條守衛，刪線上商店 publication 會讓 `Publication.online_store` 回 nil，
    #    而那個 nil 的後果是**整店商品前台不可見且不拋任何錯**（C-9 的同一個症狀）。
    #    技術上也擋得住：`fk_channels_publication_id` 會拋 `InvalidForeignKey`——
    #    但那是 500 不是 `userErrors`，違反鐵律 4 ①。
    # 2. **級聯刪 `resource_publications`**（`has_many ... dependent: :destroy` 既有行為）。
    #    切分原則有外部旁證（Saleor `channelDelete` 逐字：`Orders associated with the deleted
    #    channel will be moved to the target channel. Checkouts, product availability, and
    #    pricing will be removed.`，取證 2026-08-26）：**交易類資料必須遷移、配置類可刪**。
    #    發布列是配置類（可重建），不是財務憑證。
    # 3. 🔴 **絕不連帶刪 publishable 本體**。Medusa 明文區分 `dismiss`（解除關聯）與
    #    `delete`（連帶刪被連記錄）兩件事；我方只做前者。有反向 fixture 鎖死。
    #
    # 🔴 **刪除前必須 bump cache stamp**：`dependent: :destroy` 不會 bump
    #   `products.publications_updated_at`。刪 publication 會讓大量商品的前台可見性改變，
    #   而快取**不失效且不拋錯**。順序不可倒——刪掉之後就查不到受影響的是哪些商品了。
    #
    # @param shop [Shop]
    # @param publication [Publication]
    # @param at [Time]
    # @return [Result] 成功時 `publication` 是**已被刪除**的物件（供呼叫端取 id）
    # @note 副作用：DELETE `publications` 與其 `resource_publications`；bump 受影響商品的 cache stamp。
    def delete(shop:, publication:, at: Time.current)
      ActsAsTenant.with_tenant(shop) do
        if publication.channel.present?
          # 🔴 code 用本尊的 `CANNOT_MODIFY_APP_CATALOG_PUBLICATION`（逐字
          #   `Can't modify a publication that belongs to an app catalog.`）——
          #   在我方模型裡「綁著 channel」就等於「屬於某個 app 的 catalog」。
          #   ⚠️ field path 是 `["id"]` 不是 `["input","id"]`：本尊的 publicationDelete
          #   是扁平 `id: ID!`，沒有 input object。
          return Result.new(
            publication: nil,
            user_errors: [ {
              field: [ "id" ],
              message: I18n.t("errors.publication.channel_bound"),
              code: "CANNOT_MODIFY_APP_CATALOG_PUBLICATION"
            } ]
          )
        end

        ApplicationRecord.transaction do
          affected = ResourcePublication
            .where(shop_id: shop.id, publication_id: publication.id)
            .pluck(:publishable_type, :publishable_id)
          catalog = publication.sales_catalog

          bump_stamps_for_pairs!(shop_id: shop.id, pairs: affected, at:)
          publication.destroy!
          destroy_orphan_catalog!(catalog)
          Result.new(publication:, user_errors: [])
        end
      end
    end

    # ── 以下為內部規則產生器 ──────────────────────────────────────────────────

    # 刪掉已經沒有任何 publication 指著的 catalog。
    #
    # 🔴 **這是線上驗證抓到的缺陷**（2026-08-26，正式庫實跑）：`publicationDelete` 只刪
    #   publication，`sales_catalogs` 那一列**留在庫裡**——驗證腳本印出
    #   `cleanup: publication_left=0 catalog_left=1`。每建一次刪一次就漏一列，
    #   而且**不拋任何錯**。⚠️ 本機 spec 抓不到它：那些格子斷言的是 publication 與
    #   發布列的數量，沒有人數 catalog。
    #
    # 🔴 **判準是「沒有 publication 指著」，不是「這個 catalog 是不是我們建的」**：
    #   ①呼叫端可以傳 `catalogId` 指向一個既有 catalog——那時它**可能還被別的
    #     publication 用著**，刪掉就是刪別人的東西；
    #   ②反過來，一個沒有任何 publication 的 catalog 在我方模型裡是**不可達的**
    #     （沒有建立裸 catalog 的 API，每一列都來自 `Shop#after_create` 或
    #     `publicationCreate`）⇒ 它只能是垃圾。
    #   兩條合起來就是這個判準。
    #
    # ⚠️ 本尊在同一個位置**留孤兒**：B2B 指南逐字
    #   `When using catalogUpdate to change a catalog's publicationId, the previous
    #   publication remains in the system and becomes orphaned unless you explicitly
    #   delete it.`（取證 2026-08-26）——它孤兒的是 publication，方向相反。
    #   我方選擇清理是 **ours**，理由是我方沒有 catalog 的管理介面，
    #   孤兒列商家永遠看不到也刪不掉。
    #
    # @param catalog [SalesCatalog, nil]
    # @return [void]
    # @note 副作用：可能 DELETE 一列 `sales_catalogs`。
    def destroy_orphan_catalog!(catalog)
      return if catalog.nil?
      return if Publication.where(sales_catalog_id: catalog.id).exists?

      catalog.destroy!
    end

    # 把 GID 陣列解析成本店的 publishable 記錄。
    #
    # 🔴 **逐筆帶索引回報錯誤**（`docs/research/28-api-contract.md` §0.3.1：陣列索引用十進位
    #   裸字串）——50 筆一起送時，帶索引是前端定位「第幾筆出錯」的唯一方式。
    #
    # 🔴 **查詢一律帶 `shop_id`**：GID 裡的數字是使用者輸入，不帶租戶條件就等於
    #   「任何人都能把別店的商品發布到自己的管道」。
    #
    # @return [Array(Array<ApplicationRecord>, Array<Hash>)] 記錄與錯誤
    def resolve_publishables(shop:, gids:, field:)
      records = []
      errors = []

      gids.each_with_index do |gid, index|
        type, legacy_id = parse_publishable_gid(gid)
        record = type && type.constantize.where(shop_id: shop.id).find_by(id: legacy_id)

        if record.nil?
          errors << {
            field: [ "input", field, index.to_s ],
            message: I18n.t("errors.publication.publishable_not_found", gid: gid.to_s),
            code: "INVALID_PUBLISHABLE_ID"
          }
          next
        end

        records << record
      end

      [ records, errors ]
    end

    # @return [Array(String, Integer), Array(nil, nil)] 型別名與十進位主鍵
    def parse_publishable_gid(gid)
      match = gid.to_s.match(%r{\Agid://chilllove/([A-Za-z]+)/(\d+)\z})
      return [ nil, nil ] unless match
      return [ nil, nil ] unless publishable_types.include?(match[1])

      [ match[1], match[2].to_i ]
    end

    # bump 受影響商品的 cache stamp。
    #
    # 🔴 規則與 `Publications::Materialize.bump_publications_stamp!` **同一份**：
    #   Product ⇒ bump 自己；ProductVariant ⇒ bump **父商品**；Collection ⇒ **不 bump**
    #   （`collections` 表沒有這個欄位）。
    #
    # @note 副作用：對 `products` 做一次 UPDATE（無受影響商品時 no-op）。
    def bump_stamps!(shop_id:, records:, at:)
      pairs = records.map { |record| [ record.class.name, record.id ] }
      bump_stamps_for_pairs!(shop_id:, pairs:, at:)
    end

    # @param pairs [Array<Array(String, Integer)>] `[publishable_type, publishable_id]`
    # @note 副作用：對 `products` 做一次 UPDATE（無受影響商品時 no-op）。
    def bump_stamps_for_pairs!(shop_id:, pairs:, at:)
      direct = pairs.select { |type, _| type == "Product" }.map(&:last)
      variant_ids = pairs.select { |type, _| type == "ProductVariant" }.map(&:last)
      parents = variant_ids.empty? ? [] : ProductVariant.where(shop_id:, id: variant_ids).pluck(:product_id)

      ids = (direct + parents).compact.uniq
      return if ids.empty?

      Product.bump_publications_stamp!(shop_id:, id: ids, at:)
    end

    # @return [Result] 單一錯誤的結果
    def reject(field, message, code)
      Result.new(publication: nil, user_errors: [ { field: [ "input", field ].uniq, message:, code: } ])
    end

    # 把 model validation 的錯誤轉成 `userErrors`（鐵律 4 ①：HTTP 200）。
    #
    # @return [Result]
    def invalid_result(error, field_root:)
      user_errors = error.record.errors.map do |detail|
        { field: [ field_root, detail.attribute.to_s.camelize(:lower) ], message: detail.message, code: "INVALID" }
      end
      Result.new(publication: nil, user_errors:)
    end
  end
end
