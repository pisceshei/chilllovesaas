# frozen_string_literal: true

module Types
  module Errors
    # fulfillmentTrackingInfoUpdate 的錯誤碼（鐵律 4：code 一律有值。🔴 本尊此支是裸 UserError 無 code
    # ——ord-4 取證 2026-09-01；typed 化＝我方既有加嚴，S5 先例同）。
    class FulfillmentTrackingInfoUpdateUserErrorCode < BaseCodeEnum
      graphql_name "FulfillmentTrackingInfoUpdateUserErrorCode"
      description "fulfillmentTrackingInfoUpdate 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
