# frozen_string_literal: true

module Types
  module Errors
    # refundCreate 的錯誤碼（鐵律 4：code 一律有值。🔴 本尊此支是裸 UserError 無 code
    # ——ord-4 取證 2026-09-01；typed 化＝我方既有加嚴，S5 先例同）。
    class RefundCreateUserErrorCode < BaseCodeEnum
      graphql_name "RefundCreateUserErrorCode"
      description "refundCreate 可能回傳的錯誤碼。"

      from_pools

      # 16 F5.1(c)：affected==0 的兩種語義必須分開回（limits.refund.cap_exceeded_
      # error_code／concurrent_conflict_error_code 正典鍵）。
      own_value :REFUND_EXCEEDS_MAXIMUM_REFUNDABLE,
        "退款金額超過可退上限（軟上限；帶 orders.over_refund 權限與二次確認可超額）。"
      own_value :REFUND_CONCURRENT_MODIFIED,
        "訂單金額剛被其他操作修改（併發競爭）——以同一把冪等鍵原樣重試。"
    end
  end
end
