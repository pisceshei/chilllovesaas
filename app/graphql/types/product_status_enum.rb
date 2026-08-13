# GraphQL 公開的商品狀態列舉。
#
# Database 以小寫字串保存狀態；GraphQL 以穩定的大寫 enum token 對外，避免
# client 依賴 persistence spelling。見 docs/research/28 §0.2–0.3。
class Types::ProductStatusEnum < GraphQL::Schema::Enum
  graphql_name "ProductStatus"
  description "商品在 Admin API 中的生命週期狀態。"

  value "ACTIVE", value: "active"
  value "DRAFT", value: "draft"
  value "ARCHIVED", value: "archived"
end
