# frozen_string_literal: true

module Types
  module Errors
    # fulfillmentCancel 的錯誤碼（鐵律 4：code 一律有值。🔴 本尊此支是裸 UserError 無 code
    # ——ord-4 取證 2026-09-01；typed 化＝我方既有加嚴，S5 先例同）。
    class FulfillmentCancelUserErrorCode < BaseCodeEnum
      graphql_name "FulfillmentCancelUserErrorCode"
      description "fulfillmentCancel 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
