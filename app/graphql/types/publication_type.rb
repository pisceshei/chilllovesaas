# frozen_string_literal: true

module Types
  # 一個銷售管道在本店的發布容器（本尊 `Publication`）。
  #
  # ## 🔴 顯示名的權威是 `catalog.title`，不是 `publications.name`
  #
  # 本尊 `Publication.name` **已 deprecated**，deprecation reason 逐字
  # `Use Catalog.title instead.`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/Publication>，
  # 取證 2026-08-26）。⇒ 本 type **不曝露 `name`**；對外只有 `title`，值取自 catalog。
  # `publications.name` 欄位保留為 legacy（刪欄要改所有讀取端，屬後續步驟）。
  #
  # ## 🔴 `handle` 取自 `channels.handle`
  #
  # 本尊的 handle 屬於 `Channel`，官方描述逐字
  # `A unique, human-readable identifier for the channel within the shop`——
  # 注意 **within the shop**，即每店唯一而非全域唯一，且實測帶每店後綴
  # （`docs/research/82` §10.3：Shop 管道的 handle 是 `shop-72` 不是 `shop`）。
  # ⇒ 沒有 channel 的 publication（API 建立的 catalog publication）`handle` 回 **null**，
  #   那是「這不是一個管道」的正確表達，不是缺資料。
  #
  # ## 六個能力旗標
  #
  # 🔴 本尊 `Publication` 對外**只曝露 `supportsFuturePublishing` 一支**（同上取證）；
  # 我方另外五支是 S0 依 `docs/research/82` §10.4 的抓包補的，屬 **ours**。
  # 曝露它們的理由：admin SPA 是唯一客戶端，發布 modal 要靠它們決定能不能勾
  # （實測 URL 參數 `includesBundle=false` 就是這個用途，`82` §11.5）。
  #
  # @see docs/specs/88-publication-model.md
  # @see docs/dev/m2-publication-lifecycle.md
  class PublicationType < BaseObject
    graphql_name "Publication"
    description "一個銷售管道在本店的發布容器。"

    field :id, ID, null: false, description: "gid://chilllove/Publication/{id}"
    field :legacy_resource_id, ID, null: false
    field :title, String, null: false,
      description: "顯示名。權威來源＝catalog.title（本尊 Publication.name 已 deprecated）。"
    field :handle, String, null: true,
      description: "管道 handle（來自 channels.handle，每店唯一）。非管道的 publication 為 null。"
    field :auto_publish, Boolean, null: false,
      description: "新建立的資源是否自動納入本 publication（本尊 autoPublish；input 預設 false）。"
    field :catalog_id, ID, null: true, description: "gid://chilllove/AppCatalog/{id}"
    field :catalog_type, String, null: true, description: "app／market／company_location。"

    field :supports_future_publishing, Boolean, null: false,
      description: "是否支援排程發布（🔴 本尊只曝露這一支能力旗標）。"
    field :supports_bundles, Boolean, null: false, description: "是否支援組合商品（ours）。"
    field :supports_combined_listings, Boolean, null: false, description: "是否支援 combined listing（ours）。"
    field :supports_variant_fixed_bundles, Boolean, null: false, description: "是否支援變體固定組合（ours）。"
    field :supports_subscriptions, Boolean, null: false, description: "是否支援訂閱商品（ours）。"
    field :supports_publication_for_unlisted_products, Boolean, null: false,
      description: "是否接受 UNLISTED 狀態的商品（ours；解釋了 help 那句「不能把 unlisted 發布到第三方管道」）。"

    # 🔴 只讀不寫：狀態機屬後續步驟，本步沒有任何寫入者。
    # ⚠️ 不得因為「有這個欄位」就以為鎖已經生效——目前**零寫入者、恆為 null**。
    field :operation_status, String, null: true,
      description: "進行中的發布操作：created／active／complete；null＝無（本尊 ResourceOperationStatus 恰三值，無失敗態）。"

    # 🔴 **2026-08-26 S2 修正的一個真 bug**：S1 交付的版本是
    #   `object.resource_publications.count`——**完全不看 `published_at`**。
    #   在 S1 當下無害（生產上 `published_at` 恆為過去），但**排程一存在就是錯值**：
    #   一筆排程到下個月的商品會被算成「已發布」。
    #   ⇒ 兩個欄位分開，語義各自明確，不再讓一個數字承擔兩種意思。
    field :published_resource_count, Integer, null: false,
      description: "**已到點**發布到本 publication 的資源列數（Product／Collection／ProductVariant 合計）。不含排程中的。"
    field :staged_resource_count, Integer, null: false,
      description: "已排程但**尚未到點**的資源列數（本尊 V2 投影的 isPublished=false／staged）。"

    # @return [String] GID
    def id
      "gid://chilllove/Publication/#{object.id}"
    end

    # @return [String] 十進位主鍵字串
    def legacy_resource_id
      object.id.to_s
    end

    # @return [String] 顯示名（catalog 缺席時退回 legacy 的 name）
    # @note 副作用：可能觸發一次 `sales_catalogs` 的 SELECT（未 preload 時）。
    def title = object.display_title

    # @return [String, nil]
    # @note 副作用：可能觸發一次 `channels` 的 SELECT（未 preload 時）。
    def handle = object.channel&.handle

    # 🔴 GID Type 用本尊的名字 `AppCatalog`（鐵律 4），**不是**我方的 model 名 `SalesCatalog`——
    #   model 名加 `Sales` 前綴是因為本倉庫的 `Catalog` 常數被服務層命名空間佔用，
    #   那是實作層的事，不應該漏到對外契約上。
    # @return [String, nil]
    def catalog_id
      object.sales_catalog_id && "gid://chilllove/AppCatalog/#{object.sales_catalog_id}"
    end

    # @return [String, nil]
    def catalog_type = object.sales_catalog&.catalog_type

    # @return [Integer] 已到點的列數
    # @note 副作用：一次 COUNT。列表用請 preload 或改走相關子查詢。
    def published_resource_count
      object.resource_publications.currently_published.count
    end

    # @return [Integer] 已排程未到點的列數
    # @note 副作用：一次 COUNT。
    def staged_resource_count
      object.resource_publications.staged.count
    end
  end
end
