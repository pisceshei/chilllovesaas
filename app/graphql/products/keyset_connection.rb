# Product GraphQL query service 的 namespace。
module Products
  # 只用 keyset SQL materialize Relay-shaped Product connection。
  #
  # 排序鍵固定為 `(created_at, id)`，避免 concurrent write 下 offset pagination
  # 造成重複或跳列；本類別只讀取 relation，不修改資料。見
  # docs/specs/11 §4、docs/research/28 §0.3。
  class KeysetConnection
    class << self
      # 建立一個有上限的 product connection。
      #
      # @param scope [ActiveRecord::Relation<Product>] 已套 tenant scope 的 relation
      # @param first [Integer, nil] 向後讀取的 page size
      # @param after [String, nil] 向後讀取起點 cursor
      # @param last [Integer, nil] 向前讀取的 page size
      # @param before [String, nil] 向前讀取終點 cursor
      # @return [Hash] GraphQL 使用的 nodes、edges 與 page_info
      # @raise [GraphQL::ExecutionError] 參數或 cursor 無效時拋出
      # @note 副作用：執行一筆有 `LIMIT`、無 `OFFSET` 的 SELECT，不寫入資料。
      # @see docs/research/28-api-contract.md §0.3
      def call(scope:, first: nil, after: nil, last: nil, before: nil)
        new(scope:, first:, after:, last:, before:).call
      end
    end

    # 建立尚未執行的 keyset connection query object。
    #
    # @param scope [ActiveRecord::Relation<Product>] 已套 tenant scope 的 relation
    # @param first [Integer, nil] 向後讀取的 page size
    # @param after [String, nil] 向後讀取起點 cursor
    # @param last [Integer, nil] 向前讀取的 page size
    # @param before [String, nil] 向前讀取終點 cursor
    # @return [KeysetConnection] query object
    # @note 副作用：只保存參數，不執行 SQL。
    # @see docs/research/28-api-contract.md §0.3
    def initialize(scope:, first:, after:, last:, before:)
      @scope = scope
      @first = first
      @after = after
      @last = last
      @before = before
    end

    # 不使用 OFFSET，materialize 此 connection。
    #
    # @return [Hash] GraphQL connection value
    # @raise [GraphQL::ExecutionError] 分頁參數或 cursor 無效時拋出
    # @note 副作用：執行 tenant-scoped SELECT，不寫入資料。
    # @see docs/specs/11-production-baseline.md §4
    def call
      validate_arguments!
      @last ? backward_page : forward_page
    end

    private

    def validate_arguments!
      if @first && @last
        invalid!("first 與 last 不可同時使用。")
      elsif @after && @last
        invalid!("after 必須搭配 first。")
      elsif @before && !@last
        invalid!("before 必須搭配 last。")
      end

      size = @first || @last || default_page_size
      maximum = GraphqlLimits.fetch(:pagination_max_page_size)
      invalid!("分頁筆數必須介於 1 與 #{maximum}。") unless size.between?(1, maximum)
    end

    # 未指定 first/last 時的預設頁大小；一律讀 limits.yml（鐵律 6，
    # 原骨架硬編碼 50 於 2026-08-13 移植時外移）。
    #
    # @return [Integer]
    def default_page_size
      GraphqlLimits.fetch(:pagination_default_page_size)
    end

    def forward_page
      size = @first || default_page_size
      relation = canonical_scope
      relation = apply_after(relation, @after) if @after
      rows = relation.limit(size + 1).to_a
      has_next_page = rows.length > size
      nodes = rows.first(size)

      build_result(nodes, has_next_page:, has_previous_page: @after.present?)
    end

    def backward_page
      size = @last
      relation = @scope.reorder(created_at: :asc, id: :asc)
      relation = apply_before(relation, @before) if @before
      rows = relation.limit(size + 1).to_a
      has_previous_page = rows.length > size
      nodes = rows.first(size).reverse

      build_result(nodes, has_next_page: @before.present?, has_previous_page:)
    end

    def canonical_scope
      @scope.reorder(created_at: :desc, id: :desc)
    end

    # 表名由 scope 導出（2026-08-23 泛化）：原版把 `products.` 寫死在 SQL 字串裡，
    # collections 等其他資源要用同一套 cursor 分頁就得整支拷貝——沒有拷貝就沒有
    # 不同步。條件欄位固定為 (created_at, id)，任何帶這兩欄的表都可用。
    def table
      @scope.model.table_name
    end

    def apply_after(relation, cursor)
      time, id = KeysetCursor.decode(cursor)
      relation.where(
        "#{table}.created_at < :time OR (#{table}.created_at = :time AND #{table}.id < :id)",
        time:, id:
      )
    end

    def apply_before(relation, cursor)
      time, id = KeysetCursor.decode(cursor)
      relation.where(
        "#{table}.created_at > :time OR (#{table}.created_at = :time AND #{table}.id > :id)",
        time:, id:
      )
    end

    def build_result(nodes, has_next_page:, has_previous_page:)
      edges = nodes.map { |node| { node:, cursor: KeysetCursor.encode(node) } }
      {
        nodes:,
        edges:,
        page_info: {
          has_next_page:,
          has_previous_page:,
          start_cursor: edges.first&.fetch(:cursor),
          end_cursor: edges.last&.fetch(:cursor)
        }
      }
    end

    def invalid!(message)
      raise GraphQL::ExecutionError.new(
        message,
        extensions: { "code" => "BAD_USER_INPUT" }
      )
    end
  end
end
