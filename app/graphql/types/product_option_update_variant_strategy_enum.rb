# frozen_string_literal: true

module Types
  # 本尊三策略 enum 之二（13:90-106）。
  class ProductOptionUpdateVariantStrategyEnum < GraphQL::Schema::Enum
    graphql_name "ProductOptionUpdateVariantStrategy"
    value "LEAVE_AS_IS", "需刪變體時回 error（預設）。"
    value "MANAGE", "連帶刪除受影響變體。"
  end
end
