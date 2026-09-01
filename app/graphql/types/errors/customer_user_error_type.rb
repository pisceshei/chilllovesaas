# frozen_string_literal: true

module Types
  module Errors
    # 顧客線的 userError（code 一律有值——鐵律 4 ours 加嚴）。
    class CustomerUserErrorType < BaseObject
      graphql_name "CustomerUserError"
      description "顧客線 mutation 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, CustomerUserErrorCode, null: false
    end
  end
end
