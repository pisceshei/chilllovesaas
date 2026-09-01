# frozen_string_literal: true

module Types
  # 選單項（官方 MenuItem 7 欄的 v1 對位；items 遞迴巢狀——98 §3）。
  class MenuItemType < BaseObject
    graphql_name "MenuItem"
    description "選單項（可巢狀 ≤3 層）。"

    field :id, ID, null: false
    field :items, [ MenuItemType ], null: false, description: "子項（照 position 序）。"
    field :resource_id, ID, null: true, description: "資源參照（type 為資源型時）。"
    field :title, String, null: false
    field :type, MenuItemKindType, null: false, resolver_method: :item_kind
    field :url, String, null: true, description: "http 型的自由 URL；資源型渲染期解析。"

    def id = "gid://chilllove/MenuItem/#{object.id}"
    def item_kind = object.item_type

    def resource_id
      object.resource_id && "gid://chilllove/#{object.resource_type}/#{object.resource_id}"
    end

    def items
      object.children.sort_by(&:position)
    end
  end
end
