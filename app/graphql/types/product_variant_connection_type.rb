# frozen_string_literal: true

# GraphQL schema type 的 namespace。
module Types
  # 變體的 bounded connection（第 21 包：list → connection）。
  # 排序＝(position asc, id asc)——position 是變體的語義序（拖曳重排改它不改
  # created_at），materialization 交給泛化後的 Products::KeysetConnection。
  class ProductVariantConnectionType < BaseObject
    field :nodes, [ ProductVariantType ], null: false
    field :edges, [ ProductVariantEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
