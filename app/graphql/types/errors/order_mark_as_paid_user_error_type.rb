# frozen_string_literal: true

module Types
  module Errors
    # orderMarkAsPaid 的 userError object（field/message 承接 DisplayableError；
    # code 放 concrete type——鐵律 4 的 ours 加嚴）。
    class OrderMarkAsPaidUserErrorType < BaseObject
      graphql_name "OrderMarkAsPaidUserError"
      description "orderMarkAsPaid 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, OrderMarkAsPaidUserErrorCode, null: false
    end
  end
end
