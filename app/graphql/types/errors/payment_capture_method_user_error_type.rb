# frozen_string_literal: true

module Types
  module Errors
    # paymentCaptureMethodUpdate 的 userError。
    class PaymentCaptureMethodUserErrorType < BaseObject
      graphql_name "PaymentCaptureMethodUserError"
      description "paymentCaptureMethodUpdate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, PaymentCaptureMethodUserErrorCode, null: false
    end
  end
end
