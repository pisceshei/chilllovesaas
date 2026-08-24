# frozen_string_literal: true

module Types
  # 本尊三策略 enum 之三（13:90-106；POSITION＝重複時保留 position 較低者）。
  class ProductOptionDeleteStrategyEnum < GraphQL::Schema::Enum
    graphql_name "ProductOptionDeleteStrategy"
    value "DEFAULT", "標準刪除。"
    value "NON_DESTRUCTIVE", "不刪除任何變體，僅在安全時執行。"
    value "POSITION", "值重複時保留 position 較低者（官方 highest position first 刪）。"
  end
end
