# frozen_string_literal: true

module Types
  module Errors
    # fulfillmentCancel 的 userError object（field/message 承接 DisplayableError；
    # code 放 concrete type——鐵律 4 的 ours 加嚴）。
    class FulfillmentCancelUserErrorType < BaseObject
      graphql_name "FulfillmentCancelUserError"
      description "fulfillmentCancel 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, FulfillmentCancelUserErrorCode, null: false
    end
  end
end
