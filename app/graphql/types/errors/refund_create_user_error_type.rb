# frozen_string_literal: true

module Types
  module Errors
    # refundCreate 的 userError object（field/message 承接 DisplayableError；
    # code 放 concrete type——鐵律 4 的 ours 加嚴）。
    class RefundCreateUserErrorType < BaseObject
      graphql_name "RefundCreateUserError"
      description "refundCreate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, RefundCreateUserErrorCode, null: false
    end
  end
end
