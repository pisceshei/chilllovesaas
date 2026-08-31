# frozen_string_literal: true

module Types
  module Errors
    # paymentCaptureMethodUpdate 的錯誤碼。
    class PaymentCaptureMethodUserErrorCode < BaseCodeEnum
      graphql_name "PaymentCaptureMethodUserErrorCode"
      description "paymentCaptureMethodUpdate 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
