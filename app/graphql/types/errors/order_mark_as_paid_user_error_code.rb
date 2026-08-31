# frozen_string_literal: true

module Types
  module Errors
    # orderMarkAsPaid 的錯誤碼（鐵律 4：code 一律有值）。
    # 共用池即足（NOT_FOUND＝查無訂單；INVALID_STATE＝已取消/已入帳）。
    class OrderMarkAsPaidUserErrorCode < BaseCodeEnum
      graphql_name "OrderMarkAsPaidUserErrorCode"
      description "orderMarkAsPaid 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
