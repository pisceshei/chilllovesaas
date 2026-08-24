# frozen_string_literal: true

module Inventory
  # `/admin/inventory` 列表的讀取 scope（排程第 18 包）。
  #
  # ①這是什麼：以 `inventory_items` 為主表、JOIN 出「該地點的 level 五個數量」與
  #   變體／商品標題的 scope，交給 `Products::KeysetConnection` 分頁。
  # ②值域：`location_id` 必填（呼叫端負責帶預設地點）；`query` v1 支援商品標題／變體標題／
  #   SKU 的字面搜尋（`Products::SearchScope` 的簡化版——庫存列表沒有 status/vendor 這些軸）。
  # ③怎麼做：**一次 JOIN 帶出全部數量欄**（不逐列查 level）。
  #   🔴 N+1 在這裡不是效能潔癖：列表上限 250（`limits.yml`），逐列查 level 就是單一請求
  #   打 250 次 DB，而庫存列表正是倉管整天開著的頁。守衛測試用**正向計數**——
  #   空集斷言測不到缺席（P16 那支守衛就是這樣變成空炮的）。
  #   🔴 LIKE 的 `%`／`_` 經 `sanitize_sql_like` 跳脫（同 SearchScope 的理由：SKU 可能含 `%`）。
  # ④跨功能影響：數量欄的算式與 `Product::TOTAL_INVENTORY_SELECT`（商品列表庫存欄）
  #   必須同源（鐵律 7）——本檔用 level 的實體/generated 欄直讀，商品列表是 SUM(available)，
  #   兩者的**分母不同但來源同一張表**；日後若要顯示「跨地點合計」，抽共用 scope 而不是再寫一份。
  class ItemsQuery
    # 列表顯示的五個數量（實測 94 §2.1 的欄序）。unavailable／on_hand 是 generated 欄，
    # 讀取即恆等式成立（第 16 包的機制），這裡不重算。
    QUANTITY_COLUMNS = %w[unavailable committed available on_hand incoming].freeze

    SELECT_COLUMNS = <<~SQL.squish.freeze
      inventory_items.*,
      product_variants.title AS variant_title,
      product_variants.product_id AS variant_product_id,
      products.title AS product_title,
      inventory_levels.id AS level_id,
      inventory_levels.unavailable AS level_unavailable,
      inventory_levels.committed AS level_committed,
      inventory_levels.available AS level_available,
      inventory_levels.on_hand AS level_on_hand,
      inventory_levels.incoming AS level_incoming
    SQL

    # @param shop [Shop]
    # @param location_id [Integer]
    # @param query [String, nil]
    # @return [ActiveRecord::Relation<InventoryItem>] 已帶 select 別名的 scope
    def self.call(shop:, location_id:, query: nil, product_id: nil)
      scope = InventoryItem
        .where(shop_id: shop.id)
        .joins(<<~SQL.squish)
          INNER JOIN product_variants
            ON product_variants.shop_id = inventory_items.shop_id
           AND product_variants.id = inventory_items.product_variant_id
          INNER JOIN products
            ON products.shop_id = product_variants.shop_id
           AND products.id = product_variants.product_id
          INNER JOIN inventory_levels
            ON inventory_levels.shop_id = inventory_items.shop_id
           AND inventory_levels.inventory_item_id = inventory_items.id
           AND inventory_levels.location_id = #{location_id.to_i}
        SQL
        .select(Arel.sql(SELECT_COLUMNS))
      scope = scope.where("product_variants.product_id = ?", product_id) if product_id

      apply_search(scope, query)
    end

    def self.apply_search(scope, query)
      return scope if query.blank?

      escaped = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)
      pattern = "%#{escaped}%"
      scope.where(
        "products.title LIKE :q OR product_variants.title LIKE :q OR inventory_items.sku LIKE :q",
        q: pattern
      )
    end
    private_class_method :apply_search
  end
end
