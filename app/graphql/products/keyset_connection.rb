# Product GraphQL query service 的 namespace。
module Products
  # 只用 keyset SQL materialize Relay-shaped connection（products／collections／variants 共用）。
  #
  # 第 21 包泛化：排序鍵改為參數 `(order_key, direction)`＋id tiebreaker（同向）——
  # 預設 `(created_at desc, id desc)` 與舊版行為逐位元組相同（零回歸）；
  # 變體連線用 `(position asc, id asc)`（🔴 position 是變體的語義序：拖曳重排改
  # position 不改 created_at，直接沿用預設鍵會讓加選項後的順序凍在建立時間序
  # ——排程 §2.1③ 點名的缺陷）。order_key 走 KeysetCursor::ORDER_KEYS 白名單。
  # 避免 concurrent write 下 offset pagination 造成重複或跳列；本類別只讀取
  # relation，不修改資料。見 docs/specs/11 §4、docs/research/28 §0.3。
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
      def call(scope:, first: nil, after: nil, last: nil, before: nil,
               order_key: :created_at, direction: :desc)
        new(scope:, first:, after:, last:, before:, order_key:, direction:).call
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
    def initialize(scope:, first:, after:, last:, before:,
                   order_key: :created_at, direction: :desc)
      raise ArgumentError, "unknown order_key" unless KeysetCursor::ORDER_KEYS.key?(order_key)
      raise ArgumentError, "direction must be :asc or :desc" unless %i[asc desc].include?(direction)
      @order_key = order_key
      @direction = direction
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
      relation = @scope.reorder(@order_key => reversed, :id => reversed)
      relation = apply_before(relation, @before) if @before
      rows = relation.limit(size + 1).to_a
      has_previous_page = rows.length > size
      nodes = rows.first(size).reverse

      build_result(nodes, has_next_page: @before.present?, has_previous_page:)
    end

    def canonical_scope
      @scope.reorder(@order_key => @direction, :id => @direction)
    end

    def reversed = @direction == :desc ? :asc : :desc

    # 條件由 scope 的 arel_table 導出（2026-08-23 泛化）：原版把 `products.` 寫死在
    # SQL 字串裡，collections 等其他資源要用同一套 cursor 分頁就得整支拷貝——
    # 沒有拷貝就沒有不同步。條件欄位固定為 (created_at, id)，任何帶這兩欄的表都可用。
    #
    # 🔴 用 Arel 而不是 "#{table}.created_at < :time" 字串內插：表名雖然來自
    # `model.table_name`（不是使用者輸入），但**把識別字接進 SQL 字串**這個形態本身
    # 就是 Brakeman 的 SQL Injection 告警來源，而 CI 的 quality 閘門是 fail-closed。
    # 更重要的是語義：Arel 會替我們處理識別字引號與 binding，泛化後表名成了變數，
    # 「這個字串永遠安全」不再是讀一眼就能確定的事——讓型別去保證比讓人去記得好。
    def arel
      @scope.model.arel_table
    end

    # after＝沿 canonical 方向「之後」：desc ⇒ lt、asc ⇒ gt；before 相反。
    def apply_after(relation, cursor)
      value, id = KeysetCursor.decode(cursor, key: @order_key)
      cmp = @direction == :desc ? :lt : :gt
      relation.where(keyset_predicate(value, id, cmp))
    end

    def apply_before(relation, cursor)
      value, id = KeysetCursor.decode(cursor, key: @order_key)
      cmp = @direction == :desc ? :gt : :lt
      relation.where(keyset_predicate(value, id, cmp))
    end

    def keyset_predicate(value, id, cmp)
      arel[@order_key].public_send(cmp, value).or(
        arel[@order_key].eq(value).and(arel[:id].public_send(cmp, id))
      )
    end

    def build_result(nodes, has_next_page:, has_previous_page:)
      edges = nodes.map { |node| { node:, cursor: KeysetCursor.encode(node, key: @order_key) } }
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
