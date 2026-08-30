# frozen_string_literal: true

module Types
  # 主題（包 30／D77）。本尊對位＝`OnlineStoreTheme`；v1 只曝露清單頁需要的欄。
  class ThemeType < BaseObject
    graphql_name "Theme"
    description "主題庫項目（清單頁子集；本尊 OnlineStoreTheme 的對位）。"

    field :id, ID, null: false
    field :name, String, null: false
    field :role, String, null: false, description: "draft／published（published_slot 唯一索引保證同店至多一個 published）。"
    field :version, String, null: true
    field :published_at, GraphQL::Types::ISO8601DateTime, null: true
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :preview_url, String, null: false, description: "登入後預覽入口（noindex；admin session 內有效）。"

    def id = "gid://chilllove/Theme/#{object.id}"
    def preview_url = "/admin/store/preview/#{object.id}"
  end
end
