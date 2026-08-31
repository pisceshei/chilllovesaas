# frozen_string_literal: true

module Types
  module Errors
    # fulfillmentCreate 的 userError object（field/message 承接 DisplayableError；
    # code 放 concrete type——鐵律 4 的 ours 加嚴）。
    class FulfillmentCreateUserErrorType < BaseObject
      graphql_name "FulfillmentCreateUserError"
      description "fulfillmentCreate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, FulfillmentCreateUserErrorCode, null: false
    end
  end
end
