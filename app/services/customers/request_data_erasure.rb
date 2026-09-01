# frozen_string_literal: true

module Customers
  # 個資抹除請求（G6 步 8a；官方 customerRequestDataErasure 對位）。
  #
  # 官方語義（help 逐字＋測試店 modal 實測 2026-09-01）：排程制——
  # "you have 10 days to cancel the request"；modal 明示排程日（9/1 請求→9/11 執行）
  # 且 "The customer's orders will still be visible for business reporting purposes."
  # 窗長落 limits customer.erasure_cancel_days（鐵律 6）。
  class RequestDataErasure
    Result = Data.define(:customer, :error)

    def self.call(shop:, customer:)
      if customer.redaction_scheduled_at.present?
        return Result.new(customer:, error: [ "已有待執行的抹除請求。", "INVALID_STATE" ])
      end
      if customer.anonymized_at.present?
        return Result.new(customer:, error: [ "此顧客個資已抹除。", "INVALID_STATE" ])
      end

      days = Limits.fetch(:customer, :erasure_cancel_days).to_i
      customer.update!(redaction_scheduled_at: days.days.from_now)
      Result.new(customer: customer.reload, error: nil)
    end
  end
end
