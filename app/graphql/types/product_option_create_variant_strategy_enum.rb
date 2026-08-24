# frozen_string_literal: true

module Types
  # 本尊三策略 enum 之一（13:90-106 對齊；第 22 包 B5 曝露 schema 面）。
  # 🔴 productSet 是宣告式（未列出即刪除），不吃策略——本 enum 供未來
  # productOption* 獨立 mutation（B2 後補）使用；先曝露＝契約先定、CI enum 對照可掛。
  class ProductOptionCreateVariantStrategyEnum < GraphQL::Schema::Enum
    graphql_name "ProductOptionCreateVariantStrategy"
    value "LEAVE_AS_IS", "既有變體不動（預設）。"
    value "CREATE", "笛卡兒積展開新變體（顯式 opt-in）。"
  end
end
