# GraphQL schema type 的 namespace。
module Types
  # keyset connection 中一個 product 與其 opaque cursor 的 edge type。
  #
  # 欄位契約對應 docs/research/28 §0.3；此 type 不查詢或修改資料。
  class ProductEdgeType < BaseObject
    field :cursor, String, null: false
    field :node, ProductType, null: false
  end
end
