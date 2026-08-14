# GraphQL schema type 的 namespace。
module Types
  # keyset connection 使用的 Relay-compatible 分頁邊界 metadata。
  #
  # 欄位契約對應 docs/research/28 §0.3；此 type 不執行資料庫操作。
  class PageInfoType < BaseObject
    field :has_next_page, Boolean, null: false
    field :has_previous_page, Boolean, null: false
    field :start_cursor, String, null: true
    field :end_cursor, String, null: true
  end
end
