# frozen_string_literal: true

module Types
  # tenant customers 的 bounded、offset-free connection type。
  #
  # 最大 page size 由 `config/limits.yml` 控制，materialization 交給
  # Products::KeysetConnection（通用 keyset，scope 換成 Customer）。
  # 見 docs/research/28 §0.3。
  class CustomerConnectionType < BaseObject
    field :nodes, [ CustomerType ], null: false
    field :edges, [ CustomerEdgeType ], null: false
    field :page_info, PageInfoType, null: false
  end
end
