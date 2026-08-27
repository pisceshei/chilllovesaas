# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL API 的 tenant-scoped product representation。
  #
  # 主要物件實作 Node，同時提供 legacyResourceId 供遷移相容。見
  # docs/research/28 §0.3。
  class ProductType < BaseObject
    implements Interfaces::Node
    # S2：本尊 Product 實作 `Publishable` 介面。實作者恰三個，與 `ResourcePublication::PUBLISHABLE_TYPES` 同一份集合。
    implements Interfaces::Publishable

    field :legacy_resource_id, ID, null: false
    field :title, String, null: false
    field :handle, String, null: false
    field :status, Types::ProductStatusEnum, null: false
    field :description_html, String, null: false,
      description: "富文本說明（已 sanitize 的儲存值）。"
    # 第 21 包：list → connection（cursor 編 (position, id)；≤ limits 分頁上限）。
    # 🔴 排序鍵＝position 不是 created_at：加選項後既有變體 position 會重排、
    #    created_at 不會（排程 §2.1③）。
    # `connection: false`：禁用 graphql-ruby 內建 Relay extension（會自動加分頁引數
    # 與手動宣告撞名），keyset 實作與參數自管——同 QueryType#products 慣例。
    field :variants, Types::ProductVariantConnectionType, null: false, connection: false,
      description: "變體 connection（position 序）；無選項商品恆為一筆隱含變體。" do
      argument :after, String, required: false
      argument :before, String, required: false
      argument :first, Integer, required: false
      argument :last, Integer, required: false
    end
    field :options, [ Types::ProductOptionType ], null: false,
      description: "商品選項（position 序；無選項商品為空陣列）。"
    # SaveBar 樂觀鎖（63 §A.4：lockVersion 涵蓋整棵樹）；payload 帶回讓前端
    # 下一次儲存能偵測併發覆蓋（STALE_OBJECT）。
    field :lock_version, Integer, null: false
    # 庫存合計（排程第 16 包）。null＝沒有任何 tracked 品項（UI 顯示「未追蹤」），
    # 0＝有追蹤且為零——兩個真相不得合併。權限沿用 products.view（D42：本尊同樣以
    # read_products 讀 Product.totalInventory）。
    field :total_inventory, Integer, null: true

    # ── 媒體（第 26 包）──
    # 首圖＝position 最小的那張（本尊語義；media 的排序即展示序）。
    # 🔴 用 `media` 關聯而非 `images`：後者在本尊已 deprecated（90-blueprint/01:49）。
    field :featured_image, Types::ImageType, null: true,
      description: "首圖（position 最小的媒體；無媒體時 null）。"
    # 媒體全量（第 27 包媒體卡；position 序）。上限 250（limits.product.max_media）
    # ⇒ 不做分頁：一次全取，媒體卡本來就要顯示全部縮圖。
    field :media, [ Types::MediaType ], null: false,
      description: "商品媒體（position 序；第一格＝精選圖）。"
    # 缺 alt 數（62 §M S3 明列 M1）：alt 不自動填但要度量。
    field :media_missing_alt_count, Integer, null: false,
      description: "缺 alt 文字的媒體數（無障礙與 SEO 度量；62 §F.1 不自動填、只度量）。"

    # ── 組織分類＋SEO（91 §11–12，P1）──
    field :vendor, String, null: true
    field :product_type, String, null: true
    field :tags, [ String ], null: false,
      description: "標籤全量（宣告式契約的讀取面；恆為陣列，無標籤＝[]）。"
    field :seo, Types::SeoType, null: false,
      description: "SEO 覆寫（物件恆在，子欄位 null＝未覆寫）。"
    field :translations, [ Types::TranslationType ], null: false,
      description: "非來源語言的譯文（ML-2）；locales 省略＝該店已啟用的全部語言。" do
      argument :locales, [ String ], required: false
    end
    field :translation_status, [ Types::TranslationStatusType ], null: false,
      description: "各語言翻譯進度（鐵律 7：唯一來源 translation_status）。"

    # ── 可見性兩維（S6a-2）──────────────────────────────────────────────
    #
    # 🔴 **為什麼要有這兩個欄位**：前端 `ProductDetailPage.tsx` 有一張硬編的
    #   `STATUS_DIMENSIONS` 表（只看 status 算兩維），其註釋逐字寫著
    #   「前端沒有 publication 資料，硬算出來的第二個答案遲早與伺服器分岔，
    #   而分岔的症狀是後台說可購買、前台買不到」。S6a 把 publication 資料
    #   送進前端之後，那個「順手擴充」的誘惑就是活的 ⇒ 由伺服器出唯一答案。
    #
    # 🔴 **判準完全復用 `Product.purchasable` / `.discoverable` 兩個 scope**，
    #   **不在這裡寫任何 Ruby 版的比較**。`docs/specs/91` 已登記過同型事故：
    #   「同一條『已發布』規則有兩份實作（`ResourcePublication#published?` 與
    #   `Product.published_on`）」——本欄位若自己算就是**第三份**。
    #   `discoverable ⊆ purchasable` 在 model 層是**定理**（由 purchasable 導出），
    #   繞過 scope 會讓它退化成「要靠測試盯著別漂移」的性質。
    field :purchasable, Boolean, null: false,
      description: "在指定管道當下買不買得到（三層 AND 的前兩層；第三層 catalog 延後，見 88 §3.2）。" do
      argument :publication_id, ID, required: false,
        description: "gid://chilllove/Publication/{id}；省略＝線上商店（v1 唯一前台管道）。"
    end
    field :discoverable, Boolean, null: false,
      description: "在指定管道可否被發現（搜尋／系列／推薦／sitemap／feed）。恆為 purchasable 的子集。" do
      argument :publication_id, ID, required: false
    end

    # @param publication_id [String, nil] 省略＝線上商店
    # @return [Boolean]
    # @note 副作用：一次 `EXISTS` 查詢（scope + `where(id:)`）。
    # @note ⚠️ **單筆路徑用**：列表上逐列取用會是 N+1。列表要用的話應另做
    #   批次解析（一次查出整批的可購買集合），本包不做——`ProductsPage`
    #   目前不顯示這兩維。
    def purchasable(publication_id: nil)
      visible_by(Product.method(:purchasable), publication_id)
    end

    # @see #purchasable
    def discoverable(publication_id: nil)
      visible_by(Product.method(:discoverable), publication_id)
    end

    # 序列化 product 的穩定 global API identifier。
    #
    # @return [String] `gid://chilllove/Product/{id}`
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def id
      "gid://chilllove/Product/#{object.id}"
    end

    # 首圖：position 序中**第一個有檔案的**媒體（審查 P37-W2／R6-EV-2）。
    # 🔴 不是「position 最小的媒體」：外嵌影片沒有 `stored_file`，第一版遇到
    #    影片排在第一格就直接回 nil ⇒ 商品列表對一個明明有圖的商品顯示「沒有圖片」，
    #    而媒體卡的第一格又掛著「精選」標——前後台兩份互相矛盾的真相。
    #    「featuredImage＝第一張**圖片**」與 Liquid `product.featured_image` 的語義
    #    一致（本尊 admin 列表對「影片在首格」的實際行為＝未取得，登記 V；
    #    B 面 oEmbed 縮圖落地後可改回「第一格媒體的 preview」）。
    # 🔴 用 `object.media.to_a`（不是 `.includes` 再查）——`includes` 掛在關聯上會
    #    **另發一次查詢**、繞開呼叫端的 preload（審查 C10）。列表路徑的 preload 在
    #    `Types::QueryType#products`（`preload(media: :stored_file)`）；單筆路徑
    #    多一次查詢可接受。
    def featured_image
      row = object.media.to_a.sort_by(&:position).find(&:stored_file)
      return nil unless row

      Types::ImageType::Presenter.new(file: row.stored_file)
    end

    # 🔴 單筆路徑（`product(id:)` 走 `object_from_id`）沒有 QueryType 的 preload，
    #    而每列讀 `stored_file` ⇒ 250 列＝250 次查詢（審查 C18）。就地批次載入一次；
    #    列表路徑已 preload 則跳過（不用 `.includes` 掛關聯——那會另發查詢並繞開
    #    呼叫端的 preload，第 26 包審查 C10 的教訓）。
    def media = preloaded_media.sort_by(&:position)

    # 缺 alt 數（62 §M S3）：alt 不自動填、只度量。
    # 🔴 `to_a.count { }` 而非關聯的 block-form `count`——後者每次都回 DB 全撈
    #    （審查 C11）；`to_a` 吃 preload 好的那份。
    def media_missing_alt_count
      # 🔴 D48：數的是**檔案**有沒有 alt，不是媒體列。語義仍是「這個商品有幾張圖
      #    缺說明」——同一張圖在同一商品掛兩次就算兩次（那確實是兩個要修的格子）。
      #    🔴 `stored_file` 沒載到時算「缺」而不是跳過：漏算比多算糟，
      #    這是無障礙度量，寧可提醒過頭。
      # 🔴 **走 `preloaded_media` 而不是 `object.media.to_a`**：D48 之前這個計數只讀
      #    `row.alt_text`（media 已載入、零額外查詢），所以單筆路徑沒有 preload 也無妨；
      #    改讀 `stored_file` 之後，不 preload 就是每列一條查詢。
      #    `media` 欄位的 preload 幫不上忙——GraphQL 不保證兩個欄位的解析順序。
      # 🔴 判準＝`Media#alt_authority`（審查 R6-EV-1）：第一版直接讀
      #    `stored_file&.alt_text`，外嵌影片的 alt 在媒體列 ⇒ 填了 alt 的外嵌影片
      #    被永遠算成「缺 alt」，而且在 UI 上**清不掉**（外嵌的 alt 不寫檔案）。
      preloaded_media.count { |row| row.alt_authority.blank? }
    end

    # SEO 子物件直接以 product 本身為 object（欄位在同一列上，SeoType 讀
    # seo_title／seo_description）——不做額外查詢。
    # 媒體列＋其檔案的單次批次載入。`media` 與 `mediaMissingAltCount` 共用同一份
    # ——兩個欄位各自 preload 會發兩次查詢，各自不 preload 則各自 N+1。
    # 🔴 不用 `.includes`：那會另發查詢並繞開呼叫端已經做好的 preload
    #    （第 26 包審查 C10 的教訓）。
    def preloaded_media
      @preloaded_media ||= begin
        rows = object.media.to_a
        unless rows.empty? || rows.all? { |row| row.association(:stored_file).loaded? }
          ActiveRecord::Associations::Preloader.new(records: rows, associations: :stored_file).call
        end
        rows
      end
    end

    def seo = object

    # @return [Array<String>] products.tags（json 欄，DB default []）
    def tags = object.tags || []

    # @param locales [Array<String>, nil] 篩選語言；省略＝全部已啟用語言
    # @return [Array<Translation>] 本商品的譯文列
    # @note 副作用：tenant-scoped SELECT。
    def translations(locales: nil)
      scope = Translation.where(shop_id: object.shop_id, resource_type: "PRODUCT", resource_id: object.id)
      scope = scope.where(locale_tag: locales.map { |tag| Locales::Tag.normalize(tag) }) if locales.present?
      scope.order(:locale_tag, :field_key)
    end

    # @return [Array<TranslationStatus>] 各語言進度（無列＝尚未有任何譯文，前端顯示 0/N）
    def translation_status
      TranslationStatus.where(shop_id: object.shop_id, resource_type: "PRODUCT", resource_id: object.id)
                       .order(:locale_tag)
    end

    # @return [Hash] Relay connection（B1-2：恆 ≥1 筆）
    # @note preload 選項座標：selected_options 走記憶體，不逐變體查（N+1 守衛
    #   ＝spec 的 query count 斷言）。
    def variants(first: nil, after: nil, last: nil, before: nil)
      # 🔴 第 29 包新增的三個欄位各自會 N+1，preload 一起帶（變體子頁一次載 250 列，
      #    少一個 includes 就是 250 條查詢；N+1 守衛＝spec 的 query count 斷言）：
      #    `inventoryLevels` → inventory_item → levels → location；`image` → media → file。
      scope = object.product_variants
                    .includes(product_variant_option_values: [ :product_option, :option_value ],
                              inventory_item: { inventory_levels: :location },
                              media: :stored_file)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:,
                                      order_key: :position, direction: :asc)
    end

    # @return [Array<ProductOption>] position 序（含值，一次 preload）
    def options
      object.product_options.includes(:option_values).order(:position)
    end

    # 為 migration compatibility 序列化底層 database id。
    #
    # @return [String] 十進位 primary key
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def legacy_resource_id
      object.id.to_s
    end
    # 列表路徑讀 select 帶下來的 total_inventory_sum；單筆讀取（編輯頁）無該欄時現算。
    # SUM 回 NULL（無 tracked 品項）⇒ nil ⇒ UI「未追蹤」。
    def total_inventory
      if object.has_attribute?("total_inventory_sum")
        value = object.read_attribute("total_inventory_sum")
        return value.nil? ? nil : value.to_i
      end

      value = Product
        .where(shop_id: object.shop_id, id: object.id)
        .select(Arel.sql(Product::TOTAL_INVENTORY_SELECT))
        .take
        &.read_attribute("total_inventory_sum")
      value.nil? ? nil : value.to_i
    end
    private

    # 兩個可見性欄位的共同骨架。
    #
    # 🔴 **scope 是唯一判準來源**：這裡只負責①解析 publication ②把 scope 套到
    #   這一列上。任何「順手在 Ruby 裡比一下 status」的寫法都會製造第二份真相。
    #
    # 🔴 **租戶一律從 `context.fetch(:current_shop)` 取，不靠 thread-local**
    #   （`spec/graphql/mutation_context_shop_spec.rb` 的靜態掃描＋直呼冒煙兩道守衛）。
    #   第一版寫 `Publication.online_store`（無參數，靠 `acts_as_tenant` 的隱式租戶）
    #   ⇒ **request spec 全綠**，但直呼 `ChillloveSchema.execute`（rails runner／背景
    #   job／內部呼叫）時 thread-local 是 nil ⇒ 查不到管道、兩維靜默回 false。
    #   那正是第 25 包線上驗收抓到的形態。
    #
    # 🔴 **管道不存在 ⇒ 回 false，不 raise**：缺管道代表「三層 AND 的第二層不可能
    #   通過」⇒ 語義上就是買不到，回 false 是正確答案而不是錯誤
    #   （`Publication.online_store!` 的檔頭把呼叫端分成兩類，讀取面屬
    #   「沒有就當不可見」那一類）。
    #
    # @param scope_method [Method] `Product.method(:purchasable)` 或 `:discoverable`
    # @param publication_id [String, nil]
    # @return [Boolean]
    def visible_by(scope_method, publication_id)
      shop = context.fetch(:current_shop)
      # GID 解析復用 `Publications::Lookup`（它同時**顯式**帶租戶）。理由是不再新增
      #   第四份 GID parser——倉庫沒有共用 parser、各線各寫一份 regex（該檔檔頭已登記）。
      publication =
        if publication_id.present?
          Publications::Lookup.call(shop:, gid: publication_id)
        else
          ActsAsTenant.with_tenant(shop) { Publication.online_store }
        end
      return false if publication.nil?

      scope_method.call(publication:).where(id: object.id).exists?
    end
  end
end
