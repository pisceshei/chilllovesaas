# frozen_string_literal: true

module Collections
  # 條件 → SQL 的編譯器（第 11 包；13 §F4.2／F4.3／F4.7；D50）。
  #
  # ①這是什麼：把一個 `conditions`×`products` 來源的 typed 規則編成**一段** products 上的
  #   WHERE 片段（含 bind 好的值）。rebuild 的 `INSERT…SELECT` 與 resync 的單商品判定
  #   **共用同一段 SQL**——13 §F4.9：「規則求值與前台查詢的語意必須完全一致…只有 SQL 一套」。
  #
  # ②🔴 注入安全的兩軸分治（編譯器安全契約；Rails Security Guide 2026-08-25 取證）：
  #   - **值**一律經 `sanitize_sql_array` 佔位符綁定；`contains` 類的 LIKE 值先過
  #     `sanitize_sql_like`（官方逐字：escape `'_'` and `'%'`——商家輸入 `50%` 不跳脫
  #     就變萬用字元，limits `string_contains_requires_wildcard_escape`）。
  #   - **識別字**（欄名／運算子）永不參數化也永不插值：全部來自本檔的 frozen 常數表，
  #     `condition_type`／`relation` 只當**查表鍵**用，查不到 ⇒ `Unsupported`（fail-closed）。
  #     任何一段 SQL 文字都不含使用者輸入的拼接。
  #
  # ③逐型 SQL 形態（值域＝docs/research/95 §1.2 的 19 型中 v1 支援的 10 型；命名＝
  #   canon 型別的 snake_case，與 limits `exclusion_condition_types` 同一命名系）：
  #   - 字串（product_title/product_type/product_vendor/variant_title）：eq/not_eq/
  #     starts_with/ends_with/contains/not_contains。contains 是 LIKE 子字串；
  #     官方要求值 ≥3 字元（limits `condition_value_contains_min_length`，寫入層驗）。
  #   - product_tag：includes/does_not_include＝**集合運算**（13 §F4.3）——正規化
  #     `tag_key` 的等值 EXISTS，🔴 禁 LIKE（`red` 誤中 `red-new`/`tired`）、
  #     🔴 多條件禁併 IN（IN＝OR，all 模式下答案是錯的）。條件值過 `Tags::Normalize.key`
  #     （與寫入端同一支——兩邊各一份必然漂移）。
  #   - 金額（variant_price/variant_compare_at_price）：`value_cents` 對 `*_cents` 欄
  #     整數比對（鐵律 3；規則值任何十進位字串在寫入層就地折 cents）。
  #   - variant_compare_at_price 另有 is_set/is_not_set：🔴 **is_set＝ALL variants**
  #     （官方逐字 "all variants must have a compare-at price value (including 0) for the
  #     product to match."，help /smart-collections/conditions 2026-08-25）⇒ NOT EXISTS
  #     (variant 缺 compare_at)。**不是** any-variant EXISTS——寫成 EXISTS 是靜默語義錯。
  #   - 數值比對基準＝**任一變體**（V-58 已結案：官方逐字 "the condition is true if any
  #     variant matches the condition."）⇒ EXISTS 形。
  #   - variant_inventory：變體的跨倉合計 available 對 `value_int` 比對（EXISTS 變體，
  #     其 SUM(inventory_levels.available) 滿足比較）。
  #   - product_status：p.status 的 eq/not_eq（四態；13 §F4.7「原缺」的補齊）。
  #   - 🔴 exclusion 區塊只認 4 型（product_tag/product_type/product_vendor/collection；
  #     canon 6 型中 product_category v1 不支援、unknown 不可編譯）。`collection` 型＝
  #     減去被引用系列的**最終成員**（V-140：memberships，不是候選集），引用 id 存
  #     `value_int`。
  #
  # ④跨功能影響：消費者＝`Collections::Rebuild`（INSERT…SELECT）與
  #   `Collections::ResyncProduct`（單商品 WHERE ＋ id 條件）。新增條件型別＝
  #   本表加一列＋寫入層白名單同步＋`docs/dev` 值域表同步——三處一起動。
  class RuleCompiler
    class Unsupported < StandardError; end

    # v1 可編譯的型別（inclusion）。🔴 canon 19 型中不在此表者：
    #   metafield 六型／product_category（無 taxonomy 樹）＝寫入層拒收（登記待後續包）；
    #   unknown＝存而不編（引擎遇到 ⇒ 整個系列 ERROR，見 Rebuild）。
    STRING_COLUMNS = {
      "product_title" => "p.title",
      "product_type" => "p.product_type",
      "product_vendor" => "p.vendor",
      "variant_title" => nil    # 變體字串走 EXISTS，見 compile_variant_string
    }.freeze

    STRING_RELATIONS = %w[eq not_eq starts_with ends_with contains not_contains].freeze
    NUMERIC_RELATIONS = { "eq" => "=", "not_eq" => "<>", "gt" => ">", "lt" => "<" }.freeze

    INCLUSION_TYPES = %w[
      product_title product_type product_vendor product_tag product_status
      variant_title variant_price variant_compare_at_price variant_weight variant_inventory
    ].freeze
    EXCLUSION_TYPES = %w[product_tag product_type product_vendor collection].freeze

    # 逐型合法 relation（`condition_relations_source: runtime_query` 的資料源——
    # 前端經 `collectionRuleConditions` query 取得，不得硬編；本表同時是寫入層驗證的依據，
    # 三個消費者共用一份＝不漂移）。
    RELATIONS = {
      "product_title" => STRING_RELATIONS,
      "product_type" => STRING_RELATIONS,
      "product_vendor" => STRING_RELATIONS,
      "variant_title" => STRING_RELATIONS,
      "product_tag" => %w[includes does_not_include].freeze,
      "product_status" => %w[eq not_eq].freeze,
      "variant_price" => NUMERIC_RELATIONS.keys.freeze,
      "variant_weight" => NUMERIC_RELATIONS.keys.freeze,
      "variant_inventory" => NUMERIC_RELATIONS.keys.freeze,
      "variant_compare_at_price" => (NUMERIC_RELATIONS.keys + %w[is_set is_not_set]).freeze,
      "collection" => %w[includes].freeze   # exclusion 專用：語義恆「成員屬於該系列」
    }.freeze

    DEFAULT_RELATIONS = {
      "product_tag" => "includes", "product_status" => "eq",
      "variant_inventory" => "gt", "collection" => "includes"
    }.freeze

    class << self
      # @return [Array<String>] 該型別的合法 relation（未知型別回空陣列）
      def relations_for(type) = RELATIONS.fetch(type.to_s, [])

      # @return [String, nil] 最常用 relation（對齊本尊 CollectionRuleConditions.defaultRelation）
      def default_relation(type) = DEFAULT_RELATIONS.fetch(type.to_s, relations_for(type).first)

      # 編一個來源 ⇒ products（別名 `p`）上的完整 WHERE 片段（shop 條件由呼叫端加）。
      #
      # @param source [CollectionSource] conditions×products
      # @return [String, nil] 片段；nil＝該來源沒有可貢獻的 inclusion（空來源＝空集合）
      # @raise [Unsupported] 未知/不支援型別或 relation（fail-closed——存而不編的 unknown
      #   由呼叫端先攔，走到這裡的一律是「應可編譯」的列）
      def where_sql(source)
        rules = source.rules.to_a
        inclusion = rules.select { |rule| rule.block == "inclusion" }
        exclusion = rules.select { |rule| rule.block == "exclusion" }
        return nil if inclusion.empty?

        joiner = source.inclusion_match == "any" ? " OR " : " AND "
        sql = "(#{inclusion.map { |rule| compile(rule) }.join(joiner)})"

        if exclusion.any?
          # per-source 相減（membership_formula）：命中 exclusion 組合者從本來源剔除。
          # exclusion_match 三態：NULL（單型別時無意義）視同 all。
          ex_joiner = source.exclusion_match == "any" ? " OR " : " AND "
          sql += " AND NOT (#{exclusion.map { |rule| compile(rule) }.join(ex_joiner)})"
        end
        sql
      end

      private

      def compile(rule)
        type = rule.condition_type
        if rule.block == "exclusion"
          raise Unsupported, "exclusion 不支援 #{type}" unless EXCLUSION_TYPES.include?(type)
        elsif !INCLUSION_TYPES.include?(type)
          raise Unsupported, "inclusion 不支援 #{type}"
        end

        case type
        when "product_title", "product_type", "product_vendor"
          compile_string(STRING_COLUMNS.fetch(type), rule)
        when "variant_title"
          exists_variants(compile_string("v.title", rule))
        when "product_tag" then compile_tag(rule)
        when "product_status" then compile_status(rule)
        when "variant_price"
          exists_variants(numeric("v.price_cents", rule, money(rule)))
        when "variant_weight"
          exists_variants(numeric("v.weight_grams", rule, int(rule)))
        when "variant_compare_at_price" then compile_compare_at(rule)
        when "variant_inventory" then compile_inventory(rule)
        when "collection" then compile_collection_exclusion(rule)
        else
          raise Unsupported, "無 SQL 形態：#{type}"   # 白名單同步漏了才會到這
        end
      end

      def compile_string(column, rule)
        value = rule.value_text.to_s
        case rule.relation
        when "eq" then bind("#{column} = ?", value)
        # 🔴 否定運算子必須 NULL-guard（2026-08-25 審查 F1，實跑重現）：
        #   `product_type`／`vendor` 可為 NULL（SaveProduct 對空值存 `presence`＝NULL），
        #   而 SQL 三值邏輯下 `NULL <> 'x'`＝NULL ⇒ **未設定類型的商品被「不等於」
        #   靜默剔除**——同一個功能裡 tag 的 does_not_include（NOT EXISTS）卻會納入
        #   無標籤商品，兩個「is not」對空值一個進一個出。語義基準＝「未設定＝不是那個值」
        #   （與 tag 否定、與本尊空字串儲存下的行為一致）。NOT NULL 欄（variant_title）
        #   多出的 OR IS NULL 恆假、無害。
        when "not_eq" then bind("(#{column} <> ? OR #{column} IS NULL)", value)
        when "starts_with" then bind("#{column} LIKE ?", "#{like(value)}%")
        when "ends_with" then bind("#{column} LIKE ?", "%#{like(value)}")
        when "contains" then bind("#{column} LIKE ?", "%#{like(value)}%")
        when "not_contains" then bind("(#{column} NOT LIKE ? OR #{column} IS NULL)", "%#{like(value)}%")
        else raise Unsupported, "字串欄不支援 relation=#{rule.relation}"
        end
      end

      def compile_tag(rule)
        # 🔴 查詢端與寫入端共用 Tags::Normalize（13 §F4.3 配套 1）。
        key = Tags::Normalize.key(rule.value_text)
        exists = bind(
          "EXISTS (SELECT 1 FROM product_tags pt WHERE pt.shop_id = p.shop_id " \
          "AND pt.product_id = p.id AND pt.tag_key = ?)", key
        )
        case rule.relation
        when "includes" then exists
        when "does_not_include" then "NOT #{exists}"
        else raise Unsupported, "product_tag 只有 includes / does_not_include"
        end
      end

      def compile_status(rule)
        value = rule.value_text.to_s
        case rule.relation
        when "eq" then bind("p.status = ?", value)
        when "not_eq" then bind("p.status <> ?", value)
        else raise Unsupported, "product_status 只有 eq / not_eq"
        end
      end

      def compile_compare_at(rule)
        case rule.relation
        when "is_set"
          # 🔴 官方例外：is_set＝**全部**變體都有 compare_at（含 0）——ALL 語義，
          #   NOT EXISTS(缺值變體)。同時要求商品至少有一個變體（無變體商品不匹配）。
          "(NOT EXISTS (SELECT 1 FROM product_variants v WHERE v.shop_id = p.shop_id " \
            "AND v.product_id = p.id AND v.compare_at_price_cents IS NULL) " \
            "AND EXISTS (SELECT 1 FROM product_variants v WHERE v.shop_id = p.shop_id " \
            "AND v.product_id = p.id))"
        when "is_not_set"
          # 對偶：存在缺值變體（any-variant——與其他數值條件同基準）。
          "EXISTS (SELECT 1 FROM product_variants v WHERE v.shop_id = p.shop_id " \
            "AND v.product_id = p.id AND v.compare_at_price_cents IS NULL)"
        else
          exists_variants(numeric("v.compare_at_price_cents", rule, money(rule)))
        end
      end

      def compile_inventory(rule)
        op = NUMERIC_RELATIONS.fetch(rule.relation) do
          raise Unsupported, "variant_inventory 不支援 relation=#{rule.relation}"
        end
        # 變體的跨倉合計 available；COALESCE 讓「無庫存列」算 0（未追蹤/未鋪倉的變體）。
        bind(
          "EXISTS (SELECT 1 FROM product_variants v WHERE v.shop_id = p.shop_id " \
          "AND v.product_id = p.id AND (SELECT COALESCE(SUM(il.available), 0) " \
          "FROM inventory_items ii JOIN inventory_levels il ON il.shop_id = ii.shop_id " \
          "AND il.inventory_item_id = ii.id WHERE ii.shop_id = v.shop_id " \
          "AND ii.product_variant_id = v.id) #{op} ?)", int(rule)
        )
      end

      def compile_collection_exclusion(rule)
        # 減去被引用系列的**最終成員**（V-140）＝讀 memberships（物化），不是重算它的規則。
        raise Unsupported, "collection 排除缺引用 id" if rule.value_int.nil?

        bind(
          "EXISTS (SELECT 1 FROM collection_memberships cm WHERE cm.shop_id = p.shop_id " \
          "AND cm.collection_id = ? AND cm.product_id = p.id)", rule.value_int.to_i
        )
      end

      def numeric(column, rule, value)
        op = NUMERIC_RELATIONS.fetch(rule.relation) do
          raise Unsupported, "#{column} 不支援 relation=#{rule.relation}"
        end
        bind("#{column} #{op} ?", value)
      end

      def exists_variants(inner)
        "EXISTS (SELECT 1 FROM product_variants v WHERE v.shop_id = p.shop_id " \
          "AND v.product_id = p.id AND #{inner})"
      end

      def money(rule)
        rule.value_cents or raise(Unsupported, "金額條件缺 value_cents（鐵律 3：不收十進位字串）")
      end

      def int(rule)
        rule.value_int or raise(Unsupported, "數值條件缺 value_int")
      end

      def like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s)
      end

      def bind(template, value)
        ActiveRecord::Base.sanitize_sql_array([ template, value ])
      end
    end
  end
end
