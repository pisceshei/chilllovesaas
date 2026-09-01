# frozen_string_literal: true

module Types
  module Errors
    # abandonedCheckoutSendRecovery 的錯誤碼。
    class AbandonedCheckoutUserErrorCode < BaseCodeEnum
      graphql_name "AbandonedCheckoutUserErrorCode"
      description "abandonedCheckoutSendRecovery 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
