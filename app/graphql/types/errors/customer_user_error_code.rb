# frozen_string_literal: true

module Types
  module Errors
    # 顧客線的錯誤碼（S1 同線共用先例；步 8a 全部 customer* mutation 共用）。
    class CustomerUserErrorCode < BaseCodeEnum
      graphql_name "CustomerUserErrorCode"
      description "顧客線 mutation 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
