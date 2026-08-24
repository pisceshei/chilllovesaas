# frozen_string_literal: true

module Types
  # 庫存與出貨地點（排程第 18 包的地點選擇器來源）。
  class LocationType < BaseObject
    graphql_name "Location"
    description "庫存與出貨地點。"

    field :id, ID, null: false
    field :name, String, null: false
    field :active, Boolean, null: false
    field :fulfills_online_orders, Boolean, null: false

    def id = "gid://chilllove/Location/#{object.id}"
  end
end
