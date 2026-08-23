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
    end

    field :product, ProductType, null: true do
      description "以 GID 取單一商品（不存在或非本店回 null）。"
      argument :id, GraphQL::Types::ID, required: true
    end

    field :node, Interfaces::Node, null: true do
      argument :id, ID, required: true
    end

    field :shop_locales, [ Types::ShopLocaleType ], null: false,
      description: "本店已啟用的內容語言（position 序，來源語言優先；ML-2）。"

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
    def products(first: nil, after: nil, last: nil, before: nil)
      authorize_products!
      scope = Product.where(shop_id: context.fetch(:current_shop).id)
      Products::KeysetConnection.call(scope:, first:, after:, last:, before:)
    end

    # 本店已啟用的內容語言。語言集合是**資料**（67 §A.2）：新增語言不改程式碼、
    # 不 migration，編輯頁下次載入就多出那一格。
    #
    # @return [Array<ShopLocale>] enabled 的語言（來源語言排第一，其餘照 position）
    # @note 副作用：tenant-scoped SELECT，不寫入資料。
    def shop_locales
      authorize_products!
      shop = context.fetch(:current_shop)
      ActsAsTenant.with_tenant(shop) do
        ShopLocale.enabled.includes(:platform_locale).sort_by { |row| [ row.is_source ? 0 : 1, row.position ] }
      end
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
  end
end
