# frozen_string_literal: true

module Types
  module Inputs
    # productUpdateMedia 的單筆輸入（v1 只開 alt——媒體的其他欄位都由管線決定）。
    class UpdateMediaInput < GraphQL::Schema::InputObject
      graphql_name "UpdateMediaInput"
      description "更新一個媒體的 alt。"

      argument :id, ID, required: true
      argument :alt, String, required: false, description: "空字串＝清除 alt。"
    end
  end
end
