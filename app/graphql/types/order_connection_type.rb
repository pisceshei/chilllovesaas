# frozen_string_literal: true

module Types
  # tenant orders 的 bounded、offset-free connection type。
  #
  # 最大 page size 由 `config/limits.yml` 控制，materialization 交給
  # Products::KeysetConnection（通用 keyset；orders 預設序＝processed_at desc，
  # 88 §1 URL 實測＝官方 sortKey 預設 PROCESSED_AT）。見 docs/research/28 §0.3。
  class OrderConnectionType < BaseObject
    field :nodes, [ OrderType ], null: false
    field :edges, [ OrderEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
