# frozen_string_literal: true

module Types
  module Inputs
    # 選單項輸入（巢狀 ≤3 層；官方 MenuItemCreateInput 對位——98 §3）。
    class MenuItemInputType < GraphQL::Schema::InputObject
      graphql_name "MenuItemInput"
      description "選單項（可巢狀）。"

      argument :items, [ MenuItemInputType ], required: false, description: "子項。"
      argument :resource_id, ID, required: false
      argument :title, String, required: true
      argument :type, Types::MenuItemKindType, required: true
      argument :url, String, required: false
    end
  end
end
