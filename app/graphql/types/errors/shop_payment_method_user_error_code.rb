# frozen_string_literal: true

module Types
  module Errors
    # manual 付款方式線的錯誤碼（S1 publication 先例：同線 mutation 共用一組）。
    class ShopPaymentMethodUserErrorCode < BaseCodeEnum
      graphql_name "ShopPaymentMethodUserErrorCode"
      description "manual 付款方式線可能回傳的錯誤碼。"

      from_pools
    end
  end
end
