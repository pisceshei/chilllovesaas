# GraphQL schema type 的 namespace。
module Types
  # GraphQL interface 的 namespace。
  module Interfaces
    # 主要 API resource 共用的 global-identifier contract。
    #
    # 實作者都提供 `gid://chilllove/{Type}/{id}`。見 docs/research/28 §0.3。
    module Node
      include GraphQL::Schema::Interface

      field :id, ID, null: false, description: "全域資源 GID"
    end
  end
end
