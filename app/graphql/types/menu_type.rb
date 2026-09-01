# frozen_string_literal: true

module Types
  # 導覽選單（官方 Menu；isDefault＝handle 白名單——98 §3/§4 三個預設選單）。
  class MenuType < BaseObject
    graphql_name "Menu"
    description "導覽選單。"

    field :handle, String, null: false
    field :id, ID, null: false, description: "gid://chilllove/Menu/{id}"
    field :is_default, Boolean, null: false,
      description: "預設選單（handle 不可改、不可刪——官方語義）。"
    field :items, [ MenuItemType ], null: false, description: "頂層項（照 position 序）。"
    field :title, String, null: false

    def id = "gid://chilllove/Menu/#{object.id}"
    def is_default = Menu::DEFAULT_HANDLES.include?(object.handle)

    def items
      object.menu_items.select { |item| item.parent_menu_item_id.nil? }.sort_by(&:position)
    end
  end
end
