# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL API 的 tenant-scoped product representation。
  #
  # 主要物件實作 Node，同時提供 legacyResourceId 供遷移相容。見
  # docs/research/28 §0.3。
  class ProductType < BaseObject
    implements Interfaces::Node

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

    # 序列化 product 的穩定 global API identifier。
    #
    # @return [String] `gid://chilllove/Product/{id}`
    # @note 副作用：無。
    # @see docs/research/28-api-contract.md §0.3
    def id
      "gid://chilllove/Product/#{object.id}"
    end

    # 首圖：position 最小的媒體所指的檔案（媒體排序即展示序）。
    # 🔴 用 `object.media.to_a`（不是 `.includes` 再查）——`includes` 掛在關聯上會
    #    **另發一次查詢**、繞開呼叫端的 preload（審查 C10）。列表路徑的 preload 在
    #    `Types::QueryType#products`（`preload(media: :stored_file)`）；單筆路徑
    #    多一次查詢可接受。
    def featured_image
      row = object.media.to_a.min_by(&:position)
      return nil unless row&.stored_file

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
      preloaded_media.count { |row| row.stored_file&.alt_text.blank? }
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
  end
end
