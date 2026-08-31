# frozen_string_literal: true

module Types
  module Errors
    # manual 付款方式線的 userError（code 一律有值——鐵律 4 ours 加嚴）。
    class ShopPaymentMethodUserErrorType < BaseObject
      graphql_name "ShopPaymentMethodUserError"
      description "manual 付款方式線的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ShopPaymentMethodUserErrorCode, null: false
    end
  end
end
