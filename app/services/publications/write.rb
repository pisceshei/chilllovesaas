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

    # 一次 **publishable 中心** 寫入的結果（S5）。
    #
    # 🔴 與 `Result` 分開是因為**回傳的主體不同**：S1 三支回 publication，
    #   S5 兩支回 publishable（本尊 payload 逐字 `publishable: Publishable`）。
    #   共用一個 struct 會讓其中一半的呼叫端永遠讀一個 nil 欄位。
    PublishableResult = Struct.new(:publishable, :user_errors, keyword_init: true) do
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
    #   that publication, the mutation succeeds with no change.`
    #   ——<https://shopify.dev/docs/apps/build/sales-channels/product-publishing.md>，
    #   取證 2026-08-27。⚠️ 該句主詞是 **variant**，射程未涵蓋「已排程」態，見 R7）。
    #   ⇒ 走 `apply_publication!` 的 R5／R7 兩格，DB 兜底是既有的 `uq_res_pub_target` 唯一索引。
    #   <!-- 2026-08-27 更正（S5，鐵律 19.5）：本條原本標「官方逐字未複驗」，
    #        因為當初只查了 mutation 參考頁（缺席）。S5 的官方第六路在**指南頁**逐字命中，
    #        來源與取證日期補齊如上。原判斷「未取得」在當時的證據下是正確的，
    #        改變的是證據集合而不是判斷方法。 -->
    #
    # 🔴 **刻意逐列寫入而不是 `insert_all`**：多型的 `publishable` 側
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

          # 🔴 **S5 收斂**：這裡原本是 `find_or_create_by!` 帶 create-only 區塊，
          #   與 `publishablePublish` 各寫一份「要不要改既有列」的規則。兩份規則
          #   在「既有列 `published_at IS NULL`」那一格會給出相反結果——
          #   舊寫法什麼都不做（回報成功但資源仍不可見），新寫法改成 `at`。
          #   ⇒ 同一件事經兩支 mutation 得到兩種結果，正是鐵律 7 要防的分岔。
          #   現在兩支共用 `apply_publication!`（R1–R9 全矩陣的唯一實作處）。
          #
          # ⚠️ 本路徑**不傳 `publish_date`**：`PublicationUpdateInput` 官方**恰三欄且
          #   沒有 `publishDate`**（取證 2026-08-27）⇒ **排程只能經 `publishablePublish`
          #   進入系統**。這不是我方省略，是本尊的功能邊界。
          #
          # 🔴 排序是死鎖防線（見 `apply_publication!` 檔頭）：本路徑是
          #   「一個管道 × N 個資源」，兩個並發請求若各自照輸入順序取鎖就會互相咬住。
          added.sort_by { |record| [ record.class.name, record.id ] }.each do |record|
            apply_publication!(shop:, publication:, record:, at:)
          end

          removed.each do |record|
            remove_publication!(shop:, publication:, record:)
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

    # ── S5：逐資源的發布／取消發布（publishable 中心）────────────────────────────

    # 把一個 publishable 發布到 N 個 publication（本尊 `publishablePublish`）。
    #
    # ## 本尊契約逐字（取證 2026-08-27）
    #
    # > Publishes a resource, such as a Product or Collection, to one or more publications.
    # > For products to be visible in a channel, they must have an active ProductStatus.
    # > Products sold exclusively on subscription (requiresSellingPlan: true) can only be
    # > published to online stores. You can schedule future publication by providing a
    # > publish date. Only online store channels support scheduled publishing.
    #
    # ⚠️ 第二、三句**我方本輪不實作**，兩者各有理由：
    #   - ACTIVE 檢查：S2 §4.D 已裁定檢查層在**到點事件投遞層**而不是寫入層
    #     （寫入時商品可以是 draft，到點時才需要 active）⇒ 屬 S2 PR-C。
    #     🔴 且其正典鍵 `sales_channels.future_publishing_requires_active_status`
    #     目前**無行內出處註釋**，把無出處常數變成生效判準違反鐵律 19。
    #   - `requiresSellingPlan`：我方尚無訂閱制商品概念（欄位不存在）。
    #   兩條都在 `docs/dev/m2-publishable-write.md` §6 誠實登記為延後，不是靜默略過。
    #
    # ## 🔴 這是全倉第一條 `resource_publications.published_at` 的 **UPDATE** 路徑
    #
    # S1 交付了 INSERT 與 DELETE，但 add 分支走的是 `find_or_create_by!` 的
    # **create-only 區塊**——Rails 8.1.3.1 的實作是
    # `find_by(attributes) || create_or_find_by!(attributes, &block)`，
    # `find_by` 命中時區塊**根本不執行** ⇒ 既有列的任何欄位在結構上不可能被改到。
    # 那正是「設排程／改期／取消排程」在 S5 之前沒有任何路徑可達的根因。
    # ⇒ 本方法把它拆成顯式的 `find`（帶列鎖）→ `update!` ／ else `create!`。
    #
    # @param shop [Shop]
    # @param publishable_gid [String] 要發布的資源 GID
    # @param entries [Array<Hash>] 逐筆 `{publication_id:, publish_date:, publish_date_given:}`
    # @param at [Time] 「現在」——**只**用於未指定 `publish_date` 時的預設發布時刻與 cache stamp
    # @return [PublishableResult]
    # @note 副作用：INSERT／UPDATE `resource_publications`；bump 受影響商品的
    #   `publications_updated_at`；排程列另 INSERT 一筆 `event_outbox`。
    def publish(shop:, publishable_gid:, entries:, at: Time.current)
      write_publishable(shop:, publishable_gid:, entries:, at:, mode: :publish)
    end

    # 把一個 publishable 自 N 個 publication 取消發布（本尊 `publishableUnpublish`）。
    #
    # ## 本尊契約逐字（取證 2026-08-27）
    #
    # > Unpublishes a resource, such as a `Product` or `Collection`, from one or more
    # > publications. The resource remains in your store but becomes unavailable to customers.
    #
    # 🔴 「The resource remains in your store」講的是**資源本身**（商品不會被刪），
    #   **不是**講那筆發布紀錄的去向。不得讀成「紀錄保留」。
    #
    # ## 🔴 硬刪列的論證（ours；官方對紀錄去向完全沉默）
    #
    # 已讀完並確認**不存在**該陳述的官方頁（皆 2026-08-27）：`publishableUnpublish`
    # 正文與全部八個 Examples、`PublicationInput`、`ResourcePublication`、
    # `ResourcePublicationV2`、`Publishable`、`product-publishing.md`。
    #
    # 可用的**間接**訊號只證明一件事：**官方 API 面上沒有任何入口可以觀測
    # 「被取消發布的紀錄」**——
    #   - `resourcePublications(onlyPublished:)` 逐字 `Whether to return only the resources
    #     that are currently published. If false, then also returns the resources that are
    #     scheduled to be published.` ⇒ 值域**只有兩類**，沒有第三類「已取消發布的歷史」；
    #   - 「未發布」在官方是用 `Publishable.unpublishedPublications`（逐字
    #     `The list of publications that the resource isn't published to.`）表達的，
    #     回的是 **Publication** 而不是一筆特殊紀錄。
    # ⇒ **「硬刪列」與「留列標未發布」在對外 GraphQL 契約上不可區分。**
    #   這是本題唯一可安全發布的結論；「本尊實際怎麼存」＝**未取得**。
    #
    # 我方選硬刪的理由**不是**「本尊也刪」，而是我方只出 V2 投影，
    # 而 V2 的三個 scope 全部以 `published_at IS NULL` 為「不存在」
    # ⇒ NULL 列在我方全部讀出面與「沒有列」不可區分，留 NULL 列只增加隱形狀態。
    # 🔴 更關鍵：留 NULL 列會**佔住 `uq_res_pub_target`**，而重新 publish 若命中它
    #   就踩上面那個 create-only 陷阱 ⇒ **回報成功但資源仍不可見**（靜默資料損壞）。
    #
    # ⚠️ 外部參考只作旁證、不作依據：Saleor（BSD-3）同樣刪列並明說會丟資料，
    #   但它另留一條軟移除路徑——🔴 **那條路在我方不成立**，因為 Saleor 的 listing 列上
    #   有 per-channel 售價與日期要保住，我方 `resource_publications` **只有
    #   `published_at` 一欄可保**。日後 S10 把 price list 掛上這條線時本裁定需重開。
    #
    # 🔴 `publishDate` 在本方法**完全不看**（官方唯一的規範句：
    #   `This field has no effect if you include it in the publishableUnpublish mutation.`）
    #   ——不驗證、不生效、不回錯。
    #
    # @param shop [Shop]
    # @param publishable_gid [String]
    # @param entries [Array<Hash>]
    # @param at [Time] cache stamp 時刻
    # @return [PublishableResult]
    # @note 副作用：DELETE `resource_publications`；bump 受影響商品的 cache stamp。
    def unpublish(shop:, publishable_gid:, entries:, at: Time.current)
      write_publishable(shop:, publishable_gid:, entries:, at:, mode: :unpublish)
    end

    # 兩支的共同骨架（形態 A：先驗證全收集 → 任一錯整批不寫 → 才進 transaction）。
    #
    # 🔴 **all-or-nothing 是 ours 裁定，不得寫成照抄本尊**：
    #   `publishablePublish` 頁對 `partial`／`fails` 兩個關鍵字皆 Not found on page
    #   （取證 2026-08-27）⇒ 該支自身的原子性語義＝**未取得**。
    #   我方取全有全無的三個理由：
    #   ①**同表同線的既有先例**＝`Publications::Write.update`，且已有 spec 逐字釘死
    #     「🔴 任何一筆不合法 ⇒ 整批不寫入（不是寫一半）」；
    #   ②本尊在**別支**上把逐筆獨立做成明確 opt-in（`productVariantsBulkUpdate.allowPartialUpdates`
    #     逐字 `When partial updates are not allowed, any error will prevent all variants from
    #     updating.`）、`metafieldsSet` 更是硬性 atomic（逐字 `This operation is atomic,
    #     meaning no changes are persisted if an error is encountered.`）⇒ 預設側是全有全無；
    #   ③Saleor 預設 `REJECT_EVERYTHING` 同向（取證 2026-08-27）。
    #   ⚠️ 我方 `Storage::FileCreate` 是逐筆部分成功，那是因為**檔案系統不可回滾**，
    #     不是通用選擇——不得拿它當本支的先例。
    #
    # @return [PublishableResult]
    def write_publishable(shop:, publishable_gid:, entries:, at:, mode:)
      list = Array(entries)

      # 🔴 上限用 `api.array_input_max_items`（出處註釋指向 `28-api-contract.md`）。
      #   ⚠️ **不得**外推 `sales_channels.publication_bulk_products_max: 50`——官方那個 50
      #   只出現在 `PublicationUpdateInput.publishablesToAdd/Remove` 的欄位描述上，
      #   `publishablePublish` 頁對 `maximum`／`limit`／`up to`／`at most`／`partial`
      #   五個關鍵字**皆 Not found on page**（取證 2026-08-27）⇒ 本支上限＝官方未取得。
      cap = Limits.fetch(:api, :array_input_max_items)
      if list.size > cap
        return PublishableResult.new(
          publishable: nil,
          user_errors: [ { field: [ "input" ], message: I18n.t("errors.publication.entries_too_big", cap: cap), code: "TOO_BIG" } ]
        )
      end

      ActsAsTenant.with_tenant(shop) do
        record = resolve_publishable(shop:, gid: publishable_gid)
        return PublishableResult.new(publishable: nil, user_errors: publishable_not_found_errors) if record.nil?

        targets, errors = resolve_publication_entries(shop:, entries: list, record:, mode:, at:)
        return PublishableResult.new(publishable: nil, user_errors: errors) if errors.any?

        ApplicationRecord.transaction do
          targets.each do |target|
            if mode == :publish
              apply_publication!(shop:, publication: target[:publication], record:,
                                 publish_date: target[:publish_date], at:)
            else
              remove_publication!(shop:, publication: target[:publication], record:)
            end
          end

          # 🔴 stamp 一律用 `at`（＝「現在」），**絕不用 `publish_date`**：
          #   把未來時間寫進 `products.publications_updated_at`，之後的真實變動
          #   要嘛不讓 stamp 前進、要嘛讓它倒退，兩種都污染 stamp 語義。
          #   到點那一刻的 stamp 由 outbox 事件的消費者負責（見 `enqueue_scheduled_event!`）。
          bump_stamps!(shop_id: shop.id, records: [ record ], at:)
          PublishableResult.new(publishable: record, user_errors: [])
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      publishable_invalid_result(error)
    end

    # 🔴 **狀態矩陣的唯一實作處**（S5 的核心產出；`publicationUpdate` 也走這裡）。
    #
    # 輸入維度：`publish_date` 給不給（給 `null` 在更上層就已被 reject）× 既有列四態。
    #
    # | # | 既有列 | `publish_date` | 語義 | 依據 |
    # |---|---|---|---|---|
    # | R1 | 不存在 | 省略 | 建列，`published_at = at`＝立即發布 | 沿用 `Materialize`／`Write` 既有預設 |
    # | R2 | 不存在 | 未來 T | 建列，`published_at = T`＝設排程 | 官方逐字 `Setting this to a date in the future will schedule the resource to be published.` |
    # | R3 | **NULL** | 省略 | **改成 `at`** | 🔴 硬需求：不改則靜默無效（NULL 列佔住唯一鍵，回報成功但資源仍不可見） |
    # | R4 | NULL | 未來 T | 改成 T | 同上 |
    # | R5 | 已發布（過去） | 省略 | **no-op success，不動 `published_at`** | 官方逐字 `If the variant is already published to that publication, the mutation succeeds with no change.` |
    # | R6 | 已發布（過去） | 未來 T | 改成 T＝把已發布改成排程 | 🔴 **官方沉默＝ours**。取「照做」而非 `INVALID_STATE`：`id` 參數描述逐字含 `create or update`，且商家意圖明確 |
    # | R7 | **排程中（未來）** | 省略 | 🔴 **no-op success，不動** | 🔴 官方那句 no-change 的主詞是「已發布」，**射程未涵蓋排程態**（未取得）⇒ fail-closed。反面（改寫成 `at`）＝**靜默取消排程**，正是 S2 §4-E4 登記的事故形態 |
    # | R8 | 排程中 | 另一未來 T′ | 改成 T′＝**改期** | ours |
    # | R9 | 排程中 | 過去／現在 T | 改成 T＝**取消排程並立即發布** | ours |
    #
    # 🔴 R10（`publish_date` 明確傳 `null`）在 `resolve_publication_entries` 就 reject，
    #   不進本方法：官方對 `null` 完全沉默（三個版本的 `PublicationInput` 頁、兩支
    #   mutation 頁、兩份 sales-channel 指南全文皆無相關陳述，取證 2026-08-27）。
    #   **不得**自行定義成「取消排程」——那會與 `publishableUnpublish` 的語義重疊、
    #   且官方已正面排除「用 unpublish 帶日期來取消排程」這條路。
    #
    # ## 🔴 列鎖：本方法為什麼要 `SELECT ... FOR UPDATE`
    #
    # `uq_res_pub_target` 是 `(shop_id, publication_id, publishable_type, publishable_id)`
    # 的唯一索引——它**不涉及 `published_at` 的值** ⇒ 同一列的兩個並發 UPDATE
    # 是 last-write-wins，唯一索引一點忙都幫不上。S1／S2 全倉零 UPDATE，
    # 所以這是**本包新引入的風險**，必須自己處理。
    #
    # ⚠️ 鎖順序：呼叫端已依 `publication_id` 排序（見 `resolve_publication_entries`）
    #   ⇒ `publishablePublish`（一個資源 × N 個管道）與 `publicationUpdate`
    #   （一個管道 × N 個資源）交錯執行時不會互相咬住。
    #
    # @return [ResourcePublication]
    # @note 副作用：INSERT 或 UPDATE 一列；產生排程列時另 INSERT 一筆 `event_outbox`。
    def apply_publication!(shop:, publication:, record:, publish_date: nil, at: Time.current, attempt: 0)
      row = locked_publication_row(shop:, publication:, record:)
      before = row&.published_at

      if row.nil?
        begin
          row = ResourcePublication.create!(                                                      # R1／R2
            shop_id: shop.id,
            publication_id: publication.id,
            publishable_type: record.class.name,
            publishable_id: record.id,
            published_at: publish_date || at
          )
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
          raise unless uniqueness_conflict?(error) && attempt.zero?

          # 🔴 **重走完整矩陣，不是就地補一個 update**：輸掉建列競態之後，
          #   這一列的狀態可能是「已發布」也可能是「排程中」——呼叫端的
          #   `publish_date` 該不該生效，答案就在 R5–R9 那張表裡。
          #   ⚠️ 反面做法（rescue 裡只補 `update!(published_at:) if nil?`）會在
          #   對手先建了一列「已發布」時**靜默丟掉呼叫端要設的排程日期**，
          #   而呼叫端收到的是成功。⇒ 遞回一次，讓同一份規則決定。
          #   `attempt` 有界（恰一次）：第二次仍撞唯一鍵代表不是競態而是真的壞了。
          return apply_publication!(shop:, publication:, record:, publish_date:, at:, attempt: 1)
        end
      elsif row.published_at.nil?
        row.update!(published_at: publish_date || at)                                             # R3／R4
      elsif publish_date.present?
        row.update!(published_at: publish_date)                                                   # R6／R8／R9
      end
      # publish_date 省略且既有列非 NULL ⇒ 什麼都不做（R5／R7）

      enqueue_scheduled_event!(shop:, publication:, row:, at:) if row.published_at != before
      row
    end

    # 這個例外是不是「同鍵已存在」——**兩種形態都要認**。
    #
    # 🔴 **為什麼 rescue 要收兩種例外**：`ResourcePublication` **同時**有 DB 唯一索引
    #   `uq_res_pub_target` 與 model 層 `validates :publishable_id, uniqueness:`。
    #   兩個交易同時走到「查不到 ⇒ 建立」時，慢的那個會撞上其中之一：
    #   model validation 先跑就是 `RecordInvalid`、跑得過去就是 DB 的 `RecordNotUnique`。
    #   ⚠️ **兩種都必須收斂成 no-op／update**，否則「重複 publish 是 no-op success」
    #   這條官方語義在並發下會破功，回一個呼叫端根本沒做錯的假驗證錯誤。
    #
    # ⚠️ Rails 自己的 `create_or_find_by!` **只吞 `RecordNotUnique`**，而其官方文檔
    #   逐字警告：`Columns with unique database constraints should not have uniqueness
    #   validations defined, otherwise #create will fail due to validation errors and
    #   #find_by will never be called.` ——我方兩者都有（而且都該有：DB 索引是底線、
    #   model validation 是給得出 `userErrors` 的那一層）⇒ 自己處理，不用那個 helper。
    #
    # ⚠️ MySQL 的失敗 INSERT 只中止該敘述、不中止交易 ⇒ rescue 之後同一個交易
    #   仍可繼續查詢與寫入（這一點與 PostgreSQL 不同，換 DB 時要重看）。
    #
    # @return [Boolean]
    def uniqueness_conflict?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)

      error.record.is_a?(ResourcePublication) && error.record.errors.of_kind?(:publishable_id, :taken)
    end

    # @return [ResourcePublication, nil] 帶 `SELECT ... FOR UPDATE` 的既有列
    # @note 副作用：在交易內對該列（或其唯一索引間隙）取排他鎖。
    def locked_publication_row(shop:, publication:, record:)
      ResourcePublication.lock.find_by(
        shop_id: shop.id,
        publication_id: publication.id,
        publishable_type: record.class.name,
        publishable_id: record.id
      )
    end

    # 取消發布＝硬刪列（理由全文見 `.unpublish` 檔頭）。
    #
    # 🔴 **`destroy_all` 不是 `delete_all`**：前者走 model、跑 callback；
    #   後者繞過一切。本表目前沒有 destroy callback，但 `dependent:` 與日後的
    #   稽核掛載都掛在 model 上，用 `delete_all` 會在無聲中跳過它們。
    #
    # 🔴 **U2：本來就沒發布 ⇒ no-op success，不報錯**（ours）。
    #   官方 `publishableUnpublish` 頁正文與**全部八個 Examples** 皆未涵蓋這個情形，
    #   對 `already`／`no-op`／`idempotent` 三個關鍵字亦無命中（取證 2026-08-27）
    #   ⇒ 未取得。取 no-op 的理由是**對稱於 R5**：publish 一個已發布的資源是
    #   no-op success，unpublish 一個未發布的資源沒有理由改成錯誤。
    #
    # @return [Integer] 實際刪掉的列數
    # @note 副作用：DELETE 0 或 1 列。
    def remove_publication!(shop:, publication:, record:)
      ResourcePublication.where(
        shop_id: shop.id,
        publication_id: publication.id,
        publishable_type: record.class.name,
        publishable_id: record.id
      ).destroy_all.size
    end

    # 排程列在同一個 transaction 內補一筆 outbox（鐵律 5：事件與業務寫入同交易）。
    #
    # 🔴 **這是全倉 `event_outbox.available_at` 未來值的第一個使用者**——
    #   既有六個 producer 一律寫 `Time.current`，既有 spec 從未覆蓋這個分支。
    #
    # 🔴 **只在「結果是排程態」時發**，不在每次發布都發：
    #   立即發布的 cache stamp 已經在同一個請求裡同步 bump 完了，沒有任何延後的事要做；
    #   排程列才有「到點那一刻要再 bump 一次」這件事，而那正是本事件的載荷。
    #
    # ⚠️ **消費者尚不存在**，誠實登記（鐵律 19）：`Events::Consumers::REGISTRY`
    #   目前四個鍵，`PRODUCT_PUBLICATION_CHANGED` 不在其中
    #   （既有唯一生產者 `Catalog::StatusTransition` 同樣是只發不接）。
    #   ⇒ 在 S2 PR-C 接上消費者之前，這些事件會在到點時被 relay 取出、
    #   派給零個消費者、標記完成。**PR-C 必須處理「在它之前已被消化掉的排程事件」**
    #   ——這一點寫在 `docs/dev/m2-publishable-write.md` §6，不是留給下一個人自己發現。
    #
    # ⚠️ **不掛在 `Publications::Materialize` 的 `after_create` 上**：那條路徑是
    #   建商品時自動物化發布列，掛上去會讓 `spec/services/events/producers_spec.rb`
    #   的「status 未變更 ⇒ 不產 publication.changed」直接轉紅，而那格斷言是對的
    #   ——建立商品不是「發布狀態變更」。本事件只掛**顯式**的 publish 路徑。
    #
    # @note 副作用：INSERT 一筆 `event_outbox`（非排程態時 no-op）。
    def enqueue_scheduled_event!(shop:, publication:, row:, at:)
      return unless ResourcePublication.scheduled?(row.published_at, at: at)

      EventOutbox.create!(
        shop_id: shop.id,
        event_id: SecureRandom.uuid,
        topic: Events::Topics::PRODUCT_PUBLICATION_CHANGED,
        aggregate_type: row.publishable_type,
        aggregate_id: row.publishable_id,
        payload: {
          publication_id: publication.id,
          publishable_type: row.publishable_type,
          publishable_id: row.publishable_id,
          published_at: row.published_at.utc.iso8601,
          scheduled: true
        },
        available_at: row.published_at,
        status: "pending"
      )
    end

    # 把 `input` 陣列逐筆解析成寫入目標，並回帶索引的錯誤（形態 A 的收集階段）。
    #
    # 🔴 **`field` path 不剝殼**：`["input", "0", "publicationId"]`。
    #   依據是官方 fixture 逐字 `["input","0","publicationId"]`
    #   （`publishableUnpublish` 頁 Examples，取證 2026-08-27）——這同時**推翻**了
    #   `docs/research/28` §0.3.6 原本登記的「沒有官方範例可證是否剝殼」假設。
    #   ⚠️ fixture 是**形狀**證據不是規則宣告，但形狀已足以定 path 慣例。
    #
    # 🔴 **同一個 publicationId 出現多次 ⇒ 後者覆蓋前者**（ours；官方沉默）。
    #   理由：逐筆套用本來就會讓後者贏，明確去重只是把它變成**與輸入順序無關的
    #   確定行為**，順便讓下面的排序不會對同一列鎖兩次。
    #
    # 🔴 **依 `publication_id` 排序後才回傳**——這是死鎖防線，不是美觀：
    #   本支是「一個資源 × N 個管道」、`publicationUpdate` 是「一個管道 × N 個資源」，
    #   兩者交錯執行時若各自照輸入順序取鎖，就會互相咬住。
    #
    # @return [Array(Array<Hash>, Array<Hash>)] 目標與錯誤
    def resolve_publication_entries(shop:, entries:, record:, mode:, at:)
      targets = {}
      errors = []

      entries.each_with_index do |entry, index|
        gid = entry[:publication_id]
        if gid.blank?
          errors << entry_error(index, "publicationId", I18n.t("errors.publication.publication_id_required"), "INVALID")
          next
        end

        publication = Lookup.call(shop:, gid:)
        if publication.nil?
          errors << entry_error(index, "publicationId", I18n.t("errors.publication.not_found"), "NOT_FOUND")
          next
        end

        # 🔴 unpublish **完全不看** `publish_date`（官方逐字：`This field has no effect
        #   if you include it in the publishableUnpublish mutation.`）——連 R10 的
        #   `null` reject 都不做，因為「無效果」的字面意思就是不驗證也不報錯。
        if mode == :publish
          date, error = validate_publish_date(entry:, index:, publication:, record:, at:)
          if error
            errors << error
            next
          end
          targets[publication.id] = { publication:, publish_date: date }
        else
          targets[publication.id] = { publication:, publish_date: nil }
        end
      end

      [ targets.values.sort_by { |target| target[:publication].id }, errors ]
    end

    # `publishDate` 的三道判準（R10／R11／R12）。
    #
    # 🔴 **兩道排程守衛的判準來自 `ResourcePublication` 的公開謂詞，不是這裡自己寫一份**
    #   （鐵律 7）：同一條規則另外還有 model validation 這個消費者，
    #   在這裡照抄條件式就是第二份判準，日後改一邊會靜默分岔。
    #   在這裡**預檢**的理由是形態 A——必須在 `save` 之前就給得出帶索引、
    #   且 code 分得開的 userError（`FEATURE_NOT_ENABLED` vs `INVALID_STATE`）。
    #   ⚠️ model validation **不移除**：它是 `update_all` 以外一切路徑的底線。
    #
    # @return [Array(Time, nil), Array(nil, Hash)] `[時刻, nil]` 或 `[nil, 錯誤]`
    def validate_publish_date(entry:, index:, publication:, record:, at:)
      date = entry[:publish_date]

      # R10：明確傳 null（不是省略）⇒ reject。官方對 null 完全沉默，
      #   自行定義成「取消排程」會與 unpublish 語義重疊且無官方背書。
      if entry[:publish_date_given] && date.nil?
        return [ nil, entry_error(index, "publishDate", I18n.t("errors.publication.publish_date_null"), "INVALID") ]
      end

      return [ date, nil ] unless ResourcePublication.scheduled?(date, at: at)

      # R11：官方逐字 `Only online store channels support future publishing.`
      #   我方以能力旗標承載、不硬編管道名（官方對範圍自相矛盾：API 頁寫
      #   `Only online store channels`（單數），help 寫 `your online store and for some
      #   sales channels`（複數未列舉）⇒ 已登記 `91` §3.21）。
      unless publication.supports_future_publishing
        return [ nil, entry_error(index, "publishDate", I18n.t("errors.publication.future_publishing_unsupported"), "FEATURE_NOT_ENABLED") ]
      end

      # R12：官方 help 逐字 `You can't set a future publishing date for individual
      #   product variants.`；正典＝`sales_channels.future_publishing_unsupported`。
      if ResourcePublication.unschedulable_publishable_type?(record.class.name)
        return [ nil, entry_error(index, "publishDate", I18n.t("errors.publication.variant_not_schedulable"), "INVALID_STATE") ]
      end

      [ date, nil ]
    end

    # @return [Hash] 帶陣列索引的 userError（`28 §0.3.1`：索引用十進位裸字串）
    def entry_error(index, field, message, code)
      { field: [ "input", index.to_s, field ], message:, code: }
    end

    # 把 `id` 參數解析成本店的 publishable。
    #
    # 🔴 復用 `parse_publishable_gid`（同一份型別白名單與 regex），**不新寫第四份 GID parser**
    #   ——`lookup.rb` 檔頭已劃定邊界：全域 GID parser 重構是跨元件的事（鐵律 20.5），
    #   登記於 `docs/specs/91-pit-register.md` §3。
    #
    # @return [ApplicationRecord, nil]
    def resolve_publishable(shop:, gid:)
      type, legacy_id = parse_publishable_gid(gid)
      return nil if type.nil?

      type.constantize.where(shop_id: shop.id).find_by(id: legacy_id)
    end

    # `id` 查無資源時的 userErrors。
    #
    # 🔴 `field` 是 `["id"]` 不是 `["input","id"]`——本尊 `publishablePublish` 的
    #   `id` 是**扁平具名參數**（`id: ID!`），不在 input object 裡。
    #   ⚠️ code 用 `NOT_FOUND` 而不是 S1 那個 `INVALID_PUBLISHABLE_ID`：
    #   S1 那個碼描述的是「陣列裡某一筆 publishable 有問題」，本支的 `id` 是**主體**，
    #   語義不同（同型對照＝`Publications::Lookup.not_found_errors`）。
    #
    # @return [Array<Hash>]
    def publishable_not_found_errors
      [ { field: [ "id" ], message: I18n.t("errors.publication.publishable_not_found_by_id"), code: "NOT_FOUND" } ]
    end

    # @return [PublishableResult]
    def publishable_invalid_result(error)
      user_errors = error.record.errors.map do |detail|
        { field: [ "input", detail.attribute.to_s.camelize(:lower) ], message: detail.message, code: "INVALID" }
      end
      PublishableResult.new(publishable: nil, user_errors:)
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
