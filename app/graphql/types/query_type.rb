# GraphQL schema type 的 namespace。
module Types
  # 首版 Admin GraphQL contract 的唯讀 query root。
  #
  # 所有 resolver 都先執行 server-side ProductPolicy，再使用明確 shop_id
  # scope。見 docs/research/28 §0.2–0.3、docs/specs/12 F3/F4。
  class QueryType < BaseObject
    # `connection: false` 禁用 graphql-ruby 內建的 offset Relay extension；
    # 此欄位自行提供 keyset 實作與參數。見 docs/specs/11 §4。
    field :products, ProductConnectionType, null: false, connection: false do
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      # 伺服器端搜尋（28 §1 契約的 query 參數；v1 白名單子集見 Products::SearchScope）。
      # `sortKey` 刻意不在本包——排程第 21 包做排序鍵一般化時一起上。
      argument :query, String, required: false
    end

    # ── 庫存讀取面（排程第 18 包）──
    field :inventory_items, InventoryItemConnectionType, null: false, connection: false do
      description "庫存列表（單一地點視角；keyset 分頁，與商品/系列同一套實作）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      argument :location_id, GraphQL::Types::ID, required: false,
        description: "地點 GID；省略＝該店第一個地點（priority 序）。"
      argument :query, String, required: false,
        description: "字面搜尋：商品標題／變體標題／SKU（v1 無 status/vendor 等軸）。"
      argument :product_id, GraphQL::Types::ID, required: false,
        description: "只回該商品的品項（商品頁庫存卡用；比用標題搜尋可靠）。"
    end

    field :locations, [ LocationType ], null: false do
      description "本店地點（priority 序）；庫存頁的地點選擇器來源。"
    end

    field :inventory_history, [ InventoryHistoryRowType ], null: false do
      description "某 (品項, 地點) 的調整歷程（新→舊，保留窗見 limits.inventory.adjustment_history_retention_days）。"
      argument :inventory_item_id, GraphQL::Types::ID, required: true
      argument :location_id, GraphQL::Types::ID, required: false
      argument :first, Integer, required: false
    end

    field :collections, CollectionConnectionType, null: false, connection: false do
      description "商品系列列表（keyset 分頁，與商品同一套實作）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
    end

    # ── 檔案庫（排程第 28 包）──
    field :files, FileConnectionType, null: false, connection: false do
      description "檔案庫列表（keyset 分頁，與商品同一套實作）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      # 🔴 檔名子字串搜尋，不是 products 的 search syntax。檔案庫沒有 status:／vendor:
      #    這類欄位語法可談，硬套 SearchScope 只會讓 `status:ready` 被當成檔名文字
      #    ——那比不支援更糟（使用者以為篩了）。型別／狀態走各自的具名參數。
      argument :query, String, required: false, description: "檔名子字串（大小寫不敏感）。"
      argument :status, FileStatusEnum, required: false, description: "只回這個處理狀態。"
      argument :content_type, String, required: false, description: "只回這個 MIME 型別。"
      argument :used_in, FileUsedInFilterEnum, required: false,
                         description: "依引用狀態篩選（NONE＝沒有任何商品引用，可安全刪除）。"
    end

    field :collection, CollectionType, null: true do
      description "以 GID 取單一系列（不存在或非本店回 null）。"
      argument :id, GraphQL::Types::ID, required: true
    end

    field :product, ProductType, null: true do
      description "以 GID 取單一商品（不存在或非本店回 null）。"
      argument :id, GraphQL::Types::ID, required: true
    end

    field :node, Interfaces::Node, null: true do
      argument :id, ID, required: true
    end

    field :shop_locales, [ Types::ShopLocaleType ], null: false,
      description: "本店的內容語言（position 序，來源語言優先；ML-2）。" do
      argument :include_disabled, Boolean, required: false,
        description: "含停用中的語言（設定頁要能重新啟用它們；停用是狀態不是刪除）。"
    end

    field :available_locales, [ Types::PlatformLocaleType ], null: false,
      description: "平台字典中尚未被本店啟用的語言（設定 › 語言的「新增」候選；ML-4）。"

    field :product_vendors, [ String ], null: false,
      description: "本店既有廠商（去重、字母序；組織分類卡 autocomplete 用，91 §12）。"
    field :product_types, [ String ], null: false,
      description: "本店既有產品類型（去重、字母序；search-or-create combobox 用）。"

    field :nodes, [ Interfaces::Node, { null: true } ], null: false do
      argument :ids, [ ID ], required: true
    end

    # 回傳一頁已授權、tenant-isolated 的 product keyset connection。
    #
    # @param first [Integer, nil] 向後讀取的 page size
    # @param after [String, nil] 向後讀取起點 cursor
    # @param last [Integer, nil] 向前讀取的 page size
    # @param before [String, nil] 向前讀取終點 cursor
    # @return [Hash] Relay-shaped product connection
    # @note 副作用：執行 Pundit 等價政策檢查與 tenant-scoped SELECT，不寫入資料。
    # @see docs/research/28-api-contract.md §0.2–0.3
    def products(first: nil, after: nil, last: nil, before: nil, query: nil)
      authorize_products!
      scope = Product
        .where(shop_id: context.fetch(:current_shop).id)
        .select(Arel.sql("products.*"), Arel.sql(Product::TOTAL_INVENTORY_SELECT))
        # 🔴 列表的縮圖欄與缺 alt 數（第 26 包）：沒有這個 preload，
        #    `featuredImage`＋`mediaMissingAltCount` 會變成每列兩三條查詢
        #    （審查 C10/C11 實證）。單筆路徑不走這裡、多一次查詢可接受。
        .preload(media: :stored_file)
      # filter 先於 cursor：同一 query 跨頁傳遞時 keyset 語義不變。
      scope = Products::SearchScope.apply(scope:, query:)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:)
    end

    # 本店已啟用的內容語言。語言集合是**資料**（67 §A.2）：新增語言不改程式碼、
    # 不 migration，編輯頁下次載入就多出那一格。
    #
    # @return [Array<ShopLocale>] enabled 的語言（來源語言排第一，其餘照 position）
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def shop_locales(include_disabled: false)
      authorize_products!
      shop = context.fetch(:current_shop)
      ActsAsTenant.with_tenant(shop) do
        scope = include_disabled ? ShopLocale.all : ShopLocale.enabled
        scope.includes(:platform_locale).sort_by { |row| [ row.is_source ? 0 : 1, row.position ] }
      end
    end

    # 可新增的語言＝平台字典 − 本店已啟用（含停用中的：停用是狀態不是刪除，
    # 它們走「重新啟用」而不是「新增」，所以一樣不列在候選裡）。
    #
    # @return [Array<PlatformLocale>] tag 序
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def available_locales
      authorize_products!
      shop = context.fetch(:current_shop)
      taken = ActsAsTenant.with_tenant(shop) { ShopLocale.pluck(:locale_tag) }
      PlatformLocale.available.where.not(tag: taken)
    end

    # 本店既有廠商清單（distinct、排序、上限引 api.pagination_max_page_size）。
    #
    # @return [Array<String>] 去重後的 vendor 值（排除 null 與空字串）
    # @note 副作用：tenant-scoped SELECT DISTINCT，不寫入資料。
    def product_vendors = organization_values(:vendor)

    # 本店既有產品類型清單（同 product_vendors 規則）。
    #
    # @return [Array<String>] 去重後的 product_type 值
    def product_types = organization_values(:product_type)

    # 在不跨越目前 tenant boundary 的前提下解析一個 GID。
    #
    # @param id [String] CHILL LOVE global id
    # @return [Product, nil] 已授權 resource；不存在或非本店時為 nil
    # @note 副作用：執行 tenant-scoped SELECT，不寫入資料。
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F4
    def node(id:)
      authorize_products!
      context.schema.object_from_id(id, context)
    end

    # 一頁庫存品項（單一地點視角）。
    #
    # @param location_id [String, nil] 地點 GID；省略取預設地點
    # @return [Hash] Relay-shaped connection
    # @note 副作用：tenant-scoped SELECT（一次 JOIN 帶出數量，不逐列查 level）。
    # @see docs/plans/2026-08-24-第18包執行規格.md §4a
    def inventory_items(first: nil, after: nil, last: nil, before: nil, location_id: nil, query: nil, product_id: nil)
      authorize_inventory!
      shop = context.fetch(:current_shop)
      location = resolve_location(shop, location_id)
      return empty_connection if location.nil?

      product_key = product_id.presence && product_id.to_s[%r{\Agid://chilllove/Product/(\d+)\z}, 1]
      return empty_connection if product_id.present? && product_key.nil?

      # 🔴 型別層要知道這一頁是哪個地點（回 locationId 欄用）——放 context 而不是逐列查。
      context[:inventory_location_id] = location.id
      scope = Inventory::ItemsQuery.call(shop:, location_id: location.id, query:, product_id: product_key&.to_i)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:)
    end

    # 本店地點（priority 序）。
    #
    # @return [Array<Location>]
    # @note 副作用：tenant-scoped SELECT。
    def locations
      authorize_inventory!
      ActsAsTenant.with_tenant(context.fetch(:current_shop)) do
        Location.where(shop_id: context.fetch(:current_shop).id).order(:priority, :id).to_a
      end
    end

    # 調整歷程（新→舊）。
    #
    # @return [Array<Inventory::HistoryQuery::Row>] 查不到品項／地點時回空陣列
    # @note 副作用：tenant-scoped SELECT（window function 的 running sum 在日期過濾前開窗）。
    # @see docs/plans/2026-08-24-庫存ledger形狀總裁定.md §四-2（第八式）
    def inventory_history(inventory_item_id:, location_id: nil, first: nil)
      authorize_inventory!
      shop = context.fetch(:current_shop)
      item_id = inventory_item_id.to_s[%r{\Agid://chilllove/InventoryItem/(\d+)\z}, 1]
      return [] if item_id.nil?

      location = resolve_location(shop, location_id)
      return [] if location.nil?

      level = ActsAsTenant.with_tenant(shop) do
        InventoryLevel.find_by(shop_id: shop.id, inventory_item_id: item_id.to_i, location_id: location.id)
      end
      return [] if level.nil?

      # 🔴 頁量引 limits.yml（鐵律 6），不硬編。
      default_page = Limits.fetch(:api, :pagination_default_page_size).to_i
      max_page = Limits.fetch(:api, :pagination_max_page_size).to_i
      rows = Inventory::HistoryQuery.call(
        shop:, level_id: level.id, limit: (first || default_page).clamp(1, max_page)
      )
      # 一次把整頁的 staff_member_id 交給 InventoryHistoryRowType 批次查 email，
      # 避免它逐列 SELECT（本包在列表端已用 JOIN 擋掉同一形態的 N+1）。
      context[:inventory_history_staff_ids] = rows.filter_map(&:staff_member_id).uniq
      context[:inventory_history_staff_emails] = nil
      rows
    end

    # 一頁商品系列（keyset；與商品共用 `Products::KeysetConnection`——泛化後只差 scope）。
    #
    # @return [Hash] Relay-shaped connection
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def collections(first: nil, after: nil, last: nil, before: nil)
      authorize_products!
      scope = Collection
        .where(shop_id: context.fetch(:current_shop).id)
        .select(Arel.sql("collections.*"), Arel.sql(Collection::MEMBER_COUNT_SELECT))
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:)
    end

    # 檔案庫列表（第 28 包）。
    #
    # @param query [String, nil] 檔名子字串
    # @param status [String, nil] `FileStatusEnum` 值（大寫）
    # @param content_type [String, nil] MIME 型別等值
    # @return [Hash] keyset connection
    # @note 副作用：一條 tenant-scoped SELECT（引用計數走相關子查詢，不是逐列 COUNT）。
    def files(first: nil, after: nil, last: nil, before: nil,
              query: nil, status: nil, content_type: nil, used_in: nil)
      authorize_files!
      scope = StoredFile
        .where(shop_id: context.fetch(:current_shop).id)
        .select(Arel.sql("files.*"), Arel.sql(StoredFile::USAGE_COUNT_SELECT))
      # 🔴 LIKE 的 % 與 _ 必須跳脫——檔名本來就可能含它們（`100%_final.png`），
      #    不跳脫則使用者打 `%` 會匹配整表（同 Products::SearchScope 的前例）。
      if query.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(query.to_s)
        scope = scope.where("files.filename LIKE ?", "%#{escaped}%")
      end
      # enum 進來是大寫（GraphQL 契約），DB 存小寫。
      scope = scope.where(status: status.to_s.downcase) if status.present?
      scope = scope.where(content_type:) if content_type.present?
      # 🔴 用 EXISTS 而不是 `usage_count_select` 的 HAVING：select 別名在 WHERE 階段
      #    還不存在（MySQL 只在 HAVING／ORDER BY 認別名），而 HAVING 會逼出
      #    暫存表、又與 keyset 的 LIMIT 打架。EXISTS 走 uq_file_usages_file_owner
      #    的前綴索引，代價是一次半連接。
      if used_in.present?
        exists = FileUsage.where("file_usages.shop_id = files.shop_id")
                          .where("file_usages.file_id = files.id").arel.exists
        scope = used_in == "NONE" ? scope.where.not(exists) : scope.where(exists)
      end
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:)
    end

    # 以 GID 取單一系列（編輯頁載入用）。
    #
    # @param id [String] `gid://chilllove/Collection/{id}`
    # @return [Collection, nil]
    # @note 副作用：tenant-scoped SELECT。
    def collection(id:)
      authorize_products!
      context.schema.object_from_id(id, context)
    end

    # 以 GID 取單一商品（28 §1 的 product(id) 對應；編輯頁載入用）。
    #
    # @param id [String] `gid://chilllove/Product/{id}`
    # @return [Product, nil] tenant-scoped；不存在或非本店回 nil
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def product(id:)
      authorize_products!
      context.schema.object_from_id(id, context)
    end

    # 解析多個 GID，未知或非本店的 resource 位置保留 nil。
    #
    # @param ids [Array<String>] CHILL LOVE global ids
    # @return [Array<Product, nil>] 與輸入同順序的已授權 resources
    # @raise [GraphQL::ExecutionError] 輸入超過集中設定上限時拋出
    # @note 副作用：逐筆執行 tenant-scoped SELECT，不寫入資料。
    # @see docs/research/28-api-contract.md §0.3
    def nodes(ids:)
      authorize_products!
      maximum = GraphqlLimits.fetch(:array_input_max_items)
      if ids.length > maximum
        raise GraphQL::ExecutionError.new(
          "輸入陣列不可超過 #{maximum} 筆。",
          extensions: { "code" => "BAD_USER_INPUT" }
        )
      end

      ids.map { |id| context.schema.object_from_id(id, context) }
    end

    private

    # 組織欄位（vendor／product_type）的去重清單共同實作。
    # 排除 null 與空字串；上限引 `api.pagination_max_page_size`（鐵律 6）。
    def organization_values(column)
      authorize_products!
      Product.where(shop_id: context.fetch(:current_shop).id)
             .where.not(column => [ nil, "" ])
             .distinct.order(column).limit(GraphqlLimits.fetch(:pagination_max_page_size))
             .pluck(column)
    end

    def authorize_products!
      return if ProductPolicy.new(context[:current_staff], Product).index?

      raise GraphQL::ExecutionError.new(
        "沒有權限讀取商品。",
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    # D42：庫存讀取用 `inventory.view`，與 products.view **分開的鍵**。
    # M1 全員 owner ⇒ `can?` 恆 true，但縫現在就分開，M5 RBAC 展開時不必回頭拆。
    # 檔案庫的讀取授權（第 28 包）。權限鍵是 `files.view`，**不是** products.view
    # ——檔案庫在內容線、有自己的權限格（12 F3），沿用商品的會讓只給了商品權限的
    # staff 看到整個檔案庫。
    def authorize_files!
      return if StoredFilePolicy.new(context[:current_staff], StoredFile).index?

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.files.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    def authorize_inventory!
      staff = context[:current_staff]
      return if staff && (staff.owner? || staff.can?("inventory.view"))

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.inventory.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    # 地點解析：帶 GID 就用它（跨店回 nil ⇒ 空結果，不是別店資料）；
    # 省略則取 priority 序第一個（建店必有預設地點＝第 16 包的 callback 保證）。
    def resolve_location(shop, location_id)
      ActsAsTenant.with_tenant(shop) do
        if location_id.present?
          id = location_id.to_s[%r{\Agid://chilllove/Location/(\d+)\z}, 1]
          return nil if id.nil?

          Location.find_by(shop_id: shop.id, id: id.to_i)
        else
          Location.where(shop_id: shop.id).order(:priority, :id).first
        end
      end
    end

    def empty_connection
      { nodes: [], edges: [], page_info: { has_next_page: false, has_previous_page: false, start_cursor: nil, end_cursor: nil } }
    end
  end
end
