# frozen_string_literal: true

module Types
  # 官方 ProductSortKeys 值域逐字（取證 2026-09-01，
  # https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductSortKeys）。
  # 🔴 v1 支援＝TITLE/CREATED_AT/UPDATED_AT/ID（有真欄位且 non-null）；
  # 其餘（INVENTORY_TOTAL 計算欄/RELEVANCE 搜尋分/PUBLISHED_AT·VENDOR·
  # PRODUCT_TYPE 無欄或 nullable keyset 縫）＝fail-closed 拒絕＋91 §3.74 登記。
  class ProductSortKeysEnum < GraphQL::Schema::Enum
    graphql_name "ProductSortKeys"
    description "products 排序鍵（官方值域；v1 支援子集見各值說明）。"

    value "CREATED_AT", "Sort by the created_at value."
    value "ID", "Sort by the id value."
    value "INVENTORY_TOTAL", "Sort by the inventory_total value.（v1 未支援）"
    value "PRODUCT_TYPE", "Sort by the product_type value.（v1 未支援——nullable keyset 縫）"
    value "PUBLISHED_AT", "Sort by the published_at value.（v1 未支援——無此欄）"
    value "RELEVANCE", "Sort by relevance to the search terms.（v1 未支援）"
    value "TITLE", "Sort by the title value."
    value "UPDATED_AT", "Sort by the updated_at value."
    value "VENDOR", "Sort by the vendor value.（v1 未支援——無此欄）"
  end
end
