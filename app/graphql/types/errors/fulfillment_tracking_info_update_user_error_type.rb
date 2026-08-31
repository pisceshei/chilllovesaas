# frozen_string_literal: true

module Types
  module Errors
    # fulfillmentTrackingInfoUpdate 的 userError object（field/message 承接 DisplayableError；
    # code 放 concrete type——鐵律 4 的 ours 加嚴）。
    class FulfillmentTrackingInfoUpdateUserErrorType < BaseObject
      graphql_name "FulfillmentTrackingInfoUpdateUserError"
      description "fulfillmentTrackingInfoUpdate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, FulfillmentTrackingInfoUpdateUserErrorCode, null: false
    end
  end
end
