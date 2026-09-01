# frozen_string_literal: true

module Types
  module Errors
    # abandonedCheckoutSendRecovery 的 userError。
    class AbandonedCheckoutUserErrorType < BaseObject
      graphql_name "AbandonedCheckoutUserError"
      description "abandonedCheckoutSendRecovery 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, AbandonedCheckoutUserErrorCode, null: false
    end
  end
end
