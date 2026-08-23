# frozen_string_literal: true

module Types
  module Errors
    # staffLocaleUpdate 的錯誤碼（鐵律 4：code 一律有值；共用池＋無專屬碼）。
    class StaffLocaleUpdateUserErrorCode < BaseCodeEnum
      graphql_name "StaffLocaleUpdateUserErrorCode"
      description "staffLocaleUpdate 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
