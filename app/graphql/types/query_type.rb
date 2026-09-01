# GraphQL schema type 的 namespace。
module Types
  # 首版 Admin GraphQL contract 的唯讀 query root。
  #
  # 所有 resolver 都先執行 server-side ProductPolicy，再使用明確 shop_id
  # scope。見 docs/research/28 §0.2–0.3、docs/specs/12 F3/F4。
  class QueryType < BaseObject
    include Types::InventoryAuthorization

    # `connection: false` 禁用 graphql-ruby 內建的 offset Relay extension；
    # 此欄位自行提供 keyset 實作與參數。見 docs/specs/11 §4。
    field :products, ProductConnectionType, null: false, connection: false do
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      # 伺服器端搜尋（28 §1 契約的 query 參數；v1 白名單子集見 Products::SearchScope）。
      # 🔴 **products 的 `sortKey` 仍未上**（登記 V）。第 21 包已把排序鍵一般化、
      #    D48 也已把 `files` 的排序補齊，但 products 的排序值域要對齊本尊
      #    （PRODUCT_TITLE／INVENTORY_TOTAL／PUBLISHED_AT…）是另一份值域窮舉，
      #    不在 D48 射程內。這句話**只對 products 成立**，不要讀成全站沒有排序。
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

    # ── 發布管道讀取面（S1）──
    #
    # 🔴 **不做 connection 分頁**，回單純的 list。理由不是偷懶：
    #   `config/limits.yml` 的 `sales_channels.max_channels` 是 **null（文檔未載）**，
    #   而實測本尊測試店恰三個管道（`docs/research/82` §11.1）。
    #   為一個實際只有個位數的集合套 keyset 分頁，會讓前端多寫一整套 cursor 處理
    #   卻永遠只有一頁。⚠️ 若日後 catalog publication 大量出現（S10），這裡要改成 connection。
    field :publications, [ Types::PublicationType ], null: false,
      description: "本店的 publication（管道與 catalog 的發布容器）。"

    # ── 主題讀取面（包 30）──
    # 集合＝個位數（本尊 theme library 上限 20），不做 connection（與 publications 同理）。
    field :theme, Types::ThemeType, null: true do
      argument :id, ID, required: true
    end
    field :themes, [ Types::ThemeType ], null: false,
      description: "本店主題庫（published 在前、再依更新時間新→舊）。"

    field :inventory_history, [ InventoryHistoryRowType ], null: false do
      description "某 (品項, 地點) 的調整歷程（新→舊，保留窗見 limits.inventory.adjustment_history_retention_days）。"
      argument :inventory_item_id, GraphQL::Types::ID, required: true
      argument :location_id, GraphQL::Types::ID, required: false
      argument :first, Integer, required: false
    end

    # 第 11 包：條件 × relation 的執行期對照（`condition_relations_source: runtime_query`；
    # 對齊本尊 `collectionRulesConditions` 的形狀）。🔴 前端不得硬編這張表。
    field :collection_rule_conditions, [ Types::CollectionRuleConditionType ], null: false,
      description: "智慧系列可用的條件型別與各自的合法 relation（執行期查詢，前端不得硬編）。"

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
      # D48：本尊 Files 頁可依 Date added／File name／Size 排序，各可升降。
      argument :sort_key, FileSortKeysEnum, required: false,
                          description: "排序鍵；預設 CREATED_AT。"
      argument :reverse, Boolean, required: false,
                         description: "反轉排序方向。預設方向：CREATED_AT 新到舊、其餘由小到大。"
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

    # 🔴 本店本身。建立於 S6b-2，當時唯一消費端是排程彈層要的時區
    #   （欄位取捨與「為什麼是店鋪級不是使用者級」見 `Types::ShopType` 檔頭）。
    field :shop, Types::ShopType, null: false,
      description: "本店。"

    # ── 內容線（步 14a）────────────────────────────────────────────────────
    field :article, ArticleType, null: true do
      argument :id, ID, required: true
    end
    field :articles, ArticleConnectionType, null: false, connection: false do
      argument :after, String, required: false
      argument :before, String, required: false
      argument :blog_id, ID, required: false
      argument :first, Integer, required: false
      argument :last, Integer, required: false
      argument :query, String, required: false
    end
    field :blogs, [ BlogType ], null: false, description: "全部部落格（店內數量小，不分頁）。"
    field :page, PageType, null: true, resolver_method: :content_page do
      argument :id, ID, required: true
    end
    field :menus, [ MenuType ], null: false, description: "全部導覽選單。"
    field :pages, PageConnectionType, null: false, connection: false do
      argument :after, String, required: false
      argument :before, String, required: false
      argument :first, Integer, required: false
      argument :last, Integer, required: false
      argument :query, String, required: false
    end

    field :url_redirects, UrlRedirectConnectionType, null: false, connection: false do
      description "路徑級重導列表（包 36；keyset 分頁 ≤250）。"
      argument :after, String, required: false
      argument :before, String, required: false
      argument :first, Integer, required: false
      argument :last, Integer, required: false
      argument :query, String, required: false, description: "來源路徑子字串過濾。"
    end

    field :shop_locales, [ Types::ShopLocaleType ], null: false,
      description: "本店的內容語言（position 序，來源語言優先；ML-2）。" do
      argument :include_disabled, Boolean, required: false,
        description: "含停用中的語言（設定頁要能重新啟用它們；停用是狀態不是刪除）。"
    end

    field :available_locales, [ Types::PlatformLocaleType ], null: false,
      description: "平台字典中尚未被本店啟用的語言（設定 › 語言的「新增」候選；ML-4）。"

    # G6-3（步 2）：manual 付款方式與請款模式（86 §2/§3）。
    # G6 步 6：通知模板（89 號 teardown）。
    # G6 步 7：棄單清單（89 §8 七欄）。
    # G6 步 9b：折扣清單（17-F4.3 列表）。
    # G6 步 10：分析總覽（19-F2.3——一支 endpoint 回全部卡片）。
    field :analytics_overview, AnalyticsOverviewType, null: false do
      description "期間指標卡＋走勢（讀 rollup；80 §3 紅線見 type 註）。"
      argument :from, GraphQL::Types::ISO8601Date, required: true
      argument :to, GraphQL::Types::ISO8601Date, required: true
    end

    field :discounts, DiscountConnectionType, null: false, connection: false do
      description "折扣 keyset connection（建立日新到舊）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
    end
    field :discount, DiscountType, null: true do
      description "單一折扣。"
      argument :id, GraphQL::Types::ID, required: true
    end

    field :abandoned_checkouts, AbandonedCheckoutConnectionType, null: false, connection: false do
      description "棄單 keyset connection（abandoned_at 新到舊）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
    end

    field :notification_templates, [ Types::NotificationTemplateType ], null: false,
      description: "通知模板合併視圖（覆寫或平台預設；v1 三支）。"
    field :notification_sender_email, String, null: true,
      description: "通知信寄件人位址（89 §6；null＝未設定走平台預設）。"

    field :shop_payment_methods, [ Types::ShopPaymentMethodType ], null: false,
      description: "manual 付款方式清單（含停用；86 §3）。"
    field :payment_capture_method, String, null: false,
      description: "請款模式（limits capture.modes；86 §2 modal）。"

    field :shop_payment_providers, [ Types::ShopPaymentProviderType ], null: false,
      description: "本店已落鍵的 PSP provider 設定列（G6-3 前半；祕密欄只回指紋，37 §6.3）。"

    field :psp_method_dictionary, [ Types::PspMethodDictEntryType ], null: false,
      description: "平台層 method 字典（limits psp_method_dictionary；詳情頁 toggle 清單的來源）。" do
      argument :provider, String, required: true
    end

    field :product_vendors, [ String ], null: false,
      description: "本店既有廠商（去重、字母序；組織分類卡 autocomplete 用，91 §12）。"
    field :product_types, [ String ], null: false,
      description: "本店既有產品類型（去重、字母序；search-or-create combobox 用）。"

    field :nodes, [ Interfaces::Node, { null: true } ], null: false do
      argument :ids, [ ID ], required: true
    end

    # ── 顧客讀取面（G6-7；契約＝28 §7 最小集）──
    field :customers, CustomerConnectionType, null: false, connection: false do
      description "本店顧客清單（keyset 分頁；預設序＝更新日期新到舊，74 §1 本尊預設鍵）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      # v1 自由文字（姓名/email/電話 CONTAINS、多詞 AND）；ShopifyQL 查詢視圖
      # 與 field filter 隨顧客模組全量包（Customers::SearchScope 檔頭）。
      argument :query, String, required: false
    end

    field :customer, CustomerType, null: true do
      description "以 GID 取單一顧客（不存在或非本店回 null）。"
      argument :id, GraphQL::Types::ID, required: true
    end

    # ── 訂單讀取面（G6-6a；契約＝28 §4 最小集＋88 號實測）──
    field :orders, OrderConnectionType, null: false, connection: false do
      description "本店訂單清單（keyset 分頁；預設序＝processed_at desc＝官方 sortKey 預設）。"
      argument :first, Integer, required: false
      argument :after, String, required: false
      argument :last, Integer, required: false
      argument :before, String, required: false
      # v1 語法：裸詞→單號/email CONTAINS；status:/financial_status:/
      # fulfillment_status: 白名單（Orders::SearchScope）。sortKey 全值域（88 §2
      # 十二鍵）隨列表排序包——與 products 同姿勢登記 V。
      argument :query, String, required: false
    end

    field :order, OrderType, null: true do
      description "以 GID 取單一訂單（不存在或非本店回 null）。"
      argument :id, GraphQL::Types::ID, required: true
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

    # 回傳一頁已授權、tenant-isolated 的 customer keyset connection（G6-7）。
    #
    # 預設序＝updated_at desc（74 §1 本尊預設「顧客更新日期 由新到舊」；
    # 排序鍵一般化——7×2 全值域——隨顧客模組全量包）。
    #
    # @return [Hash] Relay-shaped customer connection
    # @note 副作用：政策檢查與 tenant-scoped SELECT，不寫入資料。
    def customers(first: nil, after: nil, last: nil, before: nil, query: nil)
      authorize_customers!
      scope = Customer
        .where(shop_id: context.fetch(:current_shop).id)
        .preload(:customer_addresses) # 列表「地點」欄；不 preload 就是每列一查
      scope = Customers::SearchScope.apply(scope:, query:)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :updated_at, direction: :desc)
    end

    # @return [Customer, nil] 跨店或不存在一律 null（不是錯誤——28 §0.3 慣例）
    def customer(id:)
      authorize_customers!
      numeric = id.to_s[%r{\Agid://chilllove/Customer/(\d+)\z}, 1]
      return nil if numeric.nil?

      Customer.find_by(shop_id: context.fetch(:current_shop).id, id: numeric.to_i)
    end

    # 回傳一頁已授權、tenant-isolated 的 order keyset connection（G6-6a）。
    #
    # 預設序＝processed_at desc（88 §1 實測＝官方預設）；preload 行項/交易/顧客
    # ——列表卡與詳情欄不 preload 就是每列三查。
    #
    # @return [Hash] Relay-shaped order connection
    # @note 副作用：政策檢查與 tenant-scoped SELECT，不寫入資料。
    def orders(first: nil, after: nil, last: nil, before: nil, query: nil)
      authorize_orders!
      scope = Order
        .where(shop_id: context.fetch(:current_shop).id)
        .preload(:line_items, :order_transactions, :customer)
      scope = Orders::SearchScope.apply(scope:, query:)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :processed_at, direction: :desc)
    end

    # @return [Order, nil] 跨店或不存在一律 null
    def order(id:)
      authorize_orders!
      numeric = id.to_s[%r{\Agid://chilllove/Order/(\d+)\z}, 1]
      return nil if numeric.nil?

      Order.find_by(shop_id: context.fetch(:current_shop).id, id: numeric.to_i)
    end

    # @return [Shop] 目前租戶
    # @note 授權沿用 `authorize_products!`——本 type 目前唯一的欄位（時區）是商品排程
    #   發布的輸入，讀商品的人就該讀得到它。日後若加入與商品無關的欄位（帳務、方案），
    #   必須改成該欄位自己的 policy，**不得讓 products 權限順帶開出去**。
    def shop
      authorize_products!
      context.fetch(:current_shop)
    end

    # 路徑級重導列表（包 36；62 §B.5）。列含 handle_change 系統列（唯讀）與 manual 列。
    #
    # @return [Hash] keyset connection
    # @note 副作用：一條 tenant-scoped SELECT。
    # ── 內容線 resolvers（步 14a；updated_at desc＝admin 列表 Updated 欄序）──
    def pages(first: nil, after: nil, last: nil, before: nil, query: nil)
      authorize_products!
      scope = Page.where(shop_id: context.fetch(:current_shop).id)
      if query.present?
        escaped = Page.sanitize_sql_like(query.to_s)
        scope = scope.where("title LIKE :like OR handle LIKE :like", like: "%#{escaped}%")
      end
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :updated_at, direction: :desc)
    end

    def articles(first: nil, after: nil, last: nil, before: nil, blog_id: nil, query: nil)
      authorize_products!
      scope = Article.where(shop_id: context.fetch(:current_shop).id)
      if blog_id.present?
        numeric = blog_id.to_s[%r{\Agid://chilllove/Blog/(\d+)\z}, 1]
        scope = scope.where(blog_id: numeric.to_i)
      end
      if query.present?
        escaped = Article.sanitize_sql_like(query.to_s)
        scope = scope.where("title LIKE :like OR handle LIKE :like", like: "%#{escaped}%")
      end
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :updated_at, direction: :desc)
    end

    def article(id:)
      authorize_products!
      shop = context.fetch(:current_shop)
      numeric = id.to_s[%r{\Agid://chilllove/Article/(\d+)\z}, 1]
      numeric && Article.find_by(shop_id: shop.id, id: numeric)
    end

    def content_page(id:)
      authorize_products!
      shop = context.fetch(:current_shop)
      numeric = id.to_s[%r{\Agid://chilllove/Page/(\d+)\z}, 1]
      numeric && Page.find_by(shop_id: shop.id, id: numeric)
    end

    def blogs
      authorize_products!
      Blog.where(shop_id: context.fetch(:current_shop).id).order(:title)
    end

    def menus
      authorize_products!
      Menu.includes(menu_items: :children)
          .where(shop_id: context.fetch(:current_shop).id).order(:title)
    end

    def url_redirects(first: nil, after: nil, last: nil, before: nil, query: nil)
      authorize_products!
      scope = UrlRedirect.where(shop_id: context.fetch(:current_shop).id)
      if query.present?
        escaped = UrlRedirect.sanitize_sql_like(query.to_s)
        scope = scope.where("from_path LIKE ?", "%#{escaped}%")
      end
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

    # PSP provider 設定列（G6-3 前半）。只回**已落鍵**的列——未設定的 provider
    # 由前端以 pack 字典（airwallex／paypal）補空卡，避免後端替每店預生資料列。
    #
    # @return [Array<ShopPaymentProvider>] provider 字母序；祕密欄不在 type 上（37 §6.3）
    # @note 副作用：tenant-scoped SELECT，不寫入資料。授權沿用 `authorize_products!`
    #   （與 shop_locales／timezone 同一現況：settings 細粒度權限隨 M5 RBAC 展開）。
    def shop_payment_providers
      authorize_products!
      shop = context.fetch(:current_shop)
      ActsAsTenant.with_tenant(shop) do
        ShopPaymentProvider.order(:provider).to_a
      end
    end

    # manual 付款方式清單（G6-3 步 2；86 §3——含停用列，admin 端要顯示兩段）。
    #
    # @return [Array<ShopPaymentMethod>] position 序
    # @note 副作用：tenant-scoped SELECT，不寫入資料。授權同 shop_payment_providers。
    # 合併視圖（89 §7.3：無覆寫列＝平台預設）。
    #
    # @return [Array<Hash>] kind 序（Catalog::KINDS）
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    # @return [Hash] keyset connection（只列已標 abandoned_at 者）
    # @note 副作用：政策檢查與 tenant-scoped SELECT，不寫入資料。授權同 orders。
    # @return [Hash] keyset connection
    # @note 副作用：政策檢查與 tenant-scoped SELECT。授權沿 orders（discounts.view
    #   細粒度隨 M5 RBAC）。
    # @return [Hash] 指標卡（Σ rollup）；aov＝分子/分母（G25：不得以 total/orders 反推）
    # @note 副作用：tenant-scoped SELECT（daily_rollups），不寫入資料。
    def analytics_overview(from:, to:)
      authorize_orders!
      shop_id = context.fetch(:current_shop).id
      rows = DailyRollup.where(shop_id:, date: from..to, dimension: "")
                        .group(:metric).sum(:value)
      series = DailyRollup.where(shop_id:, date: from..to, metric: "total_sales", dimension: "")
                          .order(:date).pluck(:date, :value)
                          .map { |date, value| { date:, total_sales_cents: value } }
      denominator = rows.fetch("aov_denominator", 0)
      {
        total_sales_cents: rows.fetch("total_sales", 0),
        net_sales_cents: rows.fetch("net_sales", 0),
        gross_sales_cents: rows.fetch("gross_sales", 0),
        discounts_cents: rows.fetch("discounts", 0),
        returns_cents: rows.fetch("returns", 0),
        shipping_cents: rows.fetch("shipping_charges", 0),
        taxes_cents: rows.fetch("taxes", 0),
        orders_count: rows.fetch("orders_count", 0),
        units_sold: rows.fetch("units_sold", 0),
        aov_cents: denominator.zero? ? 0 : rows.fetch("aov_numerator", 0) / denominator,
        series:
      }
    end

    def discounts(first: nil, after: nil, last: nil, before: nil)
      authorize_orders!
      scope = Discount.where(shop_id: context.fetch(:current_shop).id)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :created_at, direction: :desc)
    end

    # @return [Discount, nil]
    def discount(id:)
      authorize_orders!
      numeric = id.to_s[%r{\Agid://chilllove/Discount/(\d+)\z}, 1]
      numeric && Discount.find_by(shop_id: context.fetch(:current_shop).id, id: numeric.to_i)
    end

    def abandoned_checkouts(first: nil, after: nil, last: nil, before: nil)
      authorize_orders!
      scope = Checkout.where(shop_id: context.fetch(:current_shop).id)
                      .where.not(abandoned_at: nil)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :abandoned_at, direction: :desc)
    end

    def notification_templates
      authorize_products!
      shop = context.fetch(:current_shop)
      overlays = ActsAsTenant.with_tenant(shop) do
        NotificationTemplate.where(channel: "email").index_by(&:key)
      end
      Notifications::Catalog::KINDS.map do |kind|
        overlay = overlays[kind]
        entry = Notifications::Catalog.entry(kind)
        { key: kind, subject: overlay&.subject || entry.default_subject,
          body_liquid: overlay&.body || Notifications::Catalog.default_body(kind),
          is_default: overlay.nil? }
      end
    end

    # @return [String, nil]
    def notification_sender_email
      authorize_products!
      context.fetch(:current_shop).sender_email
    end

    def shop_payment_methods
      authorize_products!
      shop = context.fetch(:current_shop)
      ActsAsTenant.with_tenant(shop) { ShopPaymentMethod.ordered.to_a }
    end

    # 請款模式（G6-3 步 2；86 §2 modal 的讀端）。
    #
    # @return [String] limits capture.modes 之一
    # @note 副作用：無；讀 shop 欄。
    def payment_capture_method
      authorize_products!
      context.fetch(:current_shop).payment_capture_method
    end

    # 平台字典（無租戶資料，仍要求登入態——與其他 settings 查詢一致）。
    #
    # @return [Array<Hash>] [{code:, label:}, …]
    # @note 副作用：無；只讀 limits。
    def psp_method_dictionary(provider:)
      authorize_products!
      ShopPaymentProvider.method_dictionary(provider)
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

    # 本店的 publication 列表（S1）。
    #
    # 🔴 preload `sales_catalog` 與 `channel`：`PublicationType` 的 `title` 走
    #   `display_title`（讀 catalog）、`handle` 走 `channel.handle`。不 preload 就是
    #   每列兩次額外 SELECT——集合小所以不會痛，但那正是 N+1 最容易長進來的地方。
    #
    # @return [Array<Publication>] 依 id 序（穩定順序；建店那一個恆為最早）
    # @note 副作用：一次 tenant-scoped SELECT ＋ 兩次 preload SELECT。
    def publications
      shop = context.fetch(:current_shop)
      ActsAsTenant.with_tenant(shop) do
        Publication.where(shop_id: shop.id).includes(:sales_catalog, :channel).order(:id).to_a
      end
    end

    # 單一主題（步 15b；theme.files／importReport 的入口）。
    def theme(id:)
      shop = context.fetch(:current_shop)
      unless ThemePolicy.new(context[:current_staff], Theme).index?
        raise GraphQL::ExecutionError.new("沒有權限讀取主題。", extensions: { "code" => "ACCESS_DENIED" })
      end

      numeric = id.to_s[%r{\Agid://chilllove/Theme/(\d+)\z}, 1]
      numeric && ActsAsTenant.with_tenant(shop) { Theme.find_by(shop_id: shop.id, id: numeric) }
    end

    # 主題清單（包 30）。授權＝ThemePolicy#index?（themes.view；形態同 authorize_products!）。
    def themes
      shop = context.fetch(:current_shop)
      unless ThemePolicy.new(context[:current_staff], Theme).index?
        raise GraphQL::ExecutionError.new("沒有權限讀取主題。", extensions: { "code" => "ACCESS_DENIED" })
      end

      ActsAsTenant.with_tenant(shop) do
        Theme.where(shop_id: shop.id)
             .order(Arel.sql("role = 'published' DESC"), updated_at: :desc)
             .to_a
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

    # 執行期的條件值域對照表（前端不得硬編——`limits.condition_relations_source`）。
    #
    # @return [Array<Hash>] 每型一列：ruleType／allowedRelations／defaultRelation／allowedInExclusion
    # @note 副作用：無（純讀常數表）。
    def collection_rule_conditions
      authorize_products!
      # 🔴 聯集，不是只有 INCLUSION_TYPES（2026-08-26 收斂輪 J6）：`collection`
      #   是 **exclusion 專用**型別，不在 INCLUSION_TYPES 裡 ⇒ 只走 inclusion 的話
      #   這支 query 永遠不回傳它，前端就拿不到它的 allowedRelations。而契約檔頭與
      #   `limits.condition_relations_source: runtime_query` 明文「前端不得硬編這張表」
      #   ⇒ 規則編輯器只剩「違反明文硬編」或「做不出 collection 排除」兩條路。
      (Collections::RuleCompiler::INCLUSION_TYPES | Collections::RuleCompiler::EXCLUSION_TYPES).map do |type|
        {
          rule_type: type,
          allowed_relations: Collections::RuleCompiler.relations_for(type),
          default_relation: Collections::RuleCompiler.default_relation(type),
          allowed_in_exclusion: Collections::RuleCompiler::EXCLUSION_TYPES.include?(type)
        }
      end
    end

    # 一頁商品系列（keyset；與商品共用 `Products::KeysetConnection`）。
    #
    # @return [Hash] Relay-shaped connection
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def collections(first: nil, after: nil, last: nil, before: nil)
      authorize_products!
      shop = context.fetch(:current_shop)

      # 🔴 兩個數字一次撈完（計畫表第 12 列逐字：「系列列表出現『後台 N 件
      #   （前台可見 M 件）』兩個數字」）。相關子查詢而非逐列 COUNT——列表上限 250。
      # `publication` 為 nil（店還沒有 online_store 管道）⇒ 只帶後台那個數字，
      #   `visibleProductsCount` 回 null＝「不知道」，不是 0。
      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      scope = Collection
        .where(shop_id: shop.id)
        .with_member_counts(publication:)
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
              query: nil, status: nil, content_type: nil, used_in: nil,
              sort_key: nil, reverse: false)
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
      order_key, direction = file_order(sort_key, reverse)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:, order_key:, direction:)
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
    # `sortKey`／`reverse` → keyset 的 `(order_key, direction)`。
    #
    # 🔴 **預設方向依鍵而異**，不是一律 desc：日期預設「新到舊」（本尊逐字
    #    "from newest to oldest"），但檔名與大小預設「由小到大」才符合直覺
    #    ——檔名 desc 開頭是 z 開頭的檔，沒有人會期待那個。
    #    `reverse` 反轉的是「該鍵的預設方向」，不是「desc」。
    def file_order(sort_key, reverse)
      key, natural = case sort_key
      when "FILENAME" then [ :filename, :asc ]
      when "ORIGINAL_UPLOAD_SIZE" then [ :byte_size, :asc ]
      else [ :created_at, :desc ]
      end
      [ key, reverse ? (natural == :asc ? :desc : :asc) : natural ]
    end

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

    # 顧客線讀取授權（G6-7）。權限鍵 `customers.view`（12 F3 慣例）——
    # 顧客資料是 PII（PDPO/GDPR 射程），不沿用商品/檔案權限（files 前例同理由）。
    def authorize_customers!
      return if CustomerPolicy.new(context[:current_staff], Customer).index?

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.customers.access_denied"),
        extensions: { "code" => "ACCESS_DENIED" }
      )
    end

    # 訂單線讀取授權（G6-6a）。權限鍵 `orders.view`（12 F3；金額與收件 PII 獨立格）。
    def authorize_orders!
      return if OrderPolicy.new(context[:current_staff], Order).index?

      raise GraphQL::ExecutionError.new(
        I18n.t("errors.orders.access_denied"),
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
