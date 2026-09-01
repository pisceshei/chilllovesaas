# frozen_string_literal: true

module Types
  # 選單項型別（官方 MenuItemType 13 值的 v1 子集——METAOBJECT／SHOP_POLICY／
  # CUSTOMER_ACCOUNT_PAGE 延後，91 §3.64；值名照官方）。
  class MenuItemKindType < GraphQL::Schema::Enum
    graphql_name "MenuItemKind"
    description "選單項連結型別。"

    value "HTTP", "外部或自由 URL。", value: "http"
    value "FRONTPAGE", "首頁。", value: "frontpage"
    value "SEARCH", "搜尋頁。", value: "search"
    value "CATALOG", "全商品頁（/collections/all）。", value: "catalog"
    value "COLLECTIONS", "系列清單頁（/collections）。", value: "collections"
    value "COLLECTION", "單一系列。", value: "collection"
    value "PRODUCT", "單一商品。", value: "product"
    value "PAGE", "自訂頁面。", value: "page"
    value "BLOG", "部落格。", value: "blog"
    value "ARTICLE", "部落格文章。", value: "article"
  end
end
