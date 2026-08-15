# GraphQL schema type 的 namespace。
module Types
  # GraphQL interface 的 namespace。
  module Interfaces
    # 所有 mutation user error 共用的可顯示錯誤 contract。
    #
    # 🔴 **與本尊的 `DisplayableError` 一字不差**（Admin API 2026-07）：
    # 官方 SDL 逐字 `interface DisplayableError { field: [String!]  message: String! }`
    # ——**只有兩個欄位，沒有 `code`**。
    # `code` 放在各 mutation 專屬的 error object type 上（我方的刻意加嚴，見 D14 偏離 A）；
    # 把它加進本 interface 就會偏離本尊的 interface 形狀，而 interface 是客戶端寫
    # `... on DisplayableError` fragment 的依據。
    #
    # ⚠️ **不確定本尊的泛用 `UserError` 有沒有 implements 這個 interface**：
    # shopify.dev 對 `UserError` **不印 Implements 區塊**（三版、兩種格式皆無），
    # 而 `DiscountUserError` 等都明確印出。⇒ 客戶端**不得假設**所有 userErrors
    # 都能用 `... on DisplayableError` 取用（D14 仍未查到 #2）。
    #
    # @see docs/research/28-api-contract.md §0.3.1
    # @see docs/DECISIONS.md D14
    module DisplayableError
      include GraphQL::Schema::Interface

      description "可顯示給使用者的錯誤。"

      # 🔴 `[String], null: true` 在 graphql-ruby 渲染成 **`[String!]`**
      # （list 可為 null、元素非 null），這正是本尊的形狀。
      # **不要**寫成 `[String, null: true]`——那會變成 `[String]`（元素可空），
      # 與本尊不符，且會讓「path 中間有一段是 null」變成合法值。
      field :field, [ String ], null: true,
        description: "錯誤所屬的輸入欄位路徑；無法歸屬到任何欄位時為 null（不是空陣列）。"

      field :message, String, null: false,
        description: "可直接顯示給使用者的錯誤訊息。"
    end
  end
end
