# frozen_string_literal: true

module Types
  module Errors
    # 折扣線 userError。
    class DiscountUserErrorType < BaseObject
      graphql_name "DiscountUserError"
      description "折扣線 mutation 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, DiscountUserErrorCode, null: false
    end
  end
end
