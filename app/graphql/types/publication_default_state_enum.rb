# frozen_string_literal: true

module Types
  # 建立 publication 時的初始成員狀態。
  #
  # 🔴 **型別名稱陷阱（已實測）**：本尊這個 enum 的名字是
  # `PublicationCreateInputPublicationDefaultState`，**不是** `PublicationDefaultState`
  # ——後者的官方路徑 `/enums/PublicationDefaultState` 回 **HTTP 404**（取證 2026-08-26）。
  # ⚠️ 但 404 只證明「該路徑沒有頁面」，**不足以**斷言 schema 裡沒有同名型別（未取得）。
  # 我方用短名 `PublicationDefaultState`，這是**刻意的偏離**：本尊那個名字把 input object
  # 的名字黏進 enum 名裡，是它自家 codegen 的產物，抄過來只會讓我方 schema 難讀。
  #
  # 值域恰兩個（官方頁自報「All values from the page have been extracted」）。
  #
  # @see docs/plans/2026-08-26-S1-規格草案.md §1.1
  class PublicationDefaultStateEnum < GraphQL::Schema::Enum
    graphql_name "PublicationDefaultState"
    description "建立 publication 時的初始成員狀態（本尊 Default:EMPTY）。"

    # 官方逐字：`The publication is empty.`
    value "EMPTY", "建立一個空的 publication。", value: "EMPTY"

    # 官方逐字：`The publication is populated with all products.`
    # 🔴 **本步不支援**，傳它會回 `FEATURE_NOT_ENABLED`。理由見
    #   `Publications::Write.create` 的註釋：本尊那條路是非同步的
    #   `AddAllProductsOperation`（帶 processedRowCount／rowCount 進度），
    #   我方沒有進度欄位的落點，加了就是第二個零消費者欄位。
    value "ALL_PRODUCTS", "以全部商品預先填滿（🔴 本步尚未支援，會回 FEATURE_NOT_ENABLED）。",
      value: "ALL_PRODUCTS"
  end
end
