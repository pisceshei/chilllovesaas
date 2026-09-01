# frozen_string_literal: true

module Types
  module Errors
    # 折扣線錯誤碼（同線共用；S1 先例）。
    class DiscountUserErrorCode < BaseCodeEnum
      graphql_name "DiscountUserErrorCode"
      description "折扣線 mutation 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
