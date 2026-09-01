# frozen_string_literal: true

module Customers
  # 取消抹除（官方 customerCancelDataErasure："Cancels a pending erasure"——
  # 已到點執行者不可取消，官方 "Once the data is erased, it cannot be retrieved."）。
  class CancelDataErasure
    Result = Data.define(:customer, :error)

    def self.call(customer:)
      if customer.redaction_scheduled_at.nil?
        return Result.new(customer:, error: [ "沒有待取消的抹除請求。", "INVALID_STATE" ])
      end
      if customer.anonymized_at.present?
        return Result.new(customer:, error: [ "個資已抹除，無法取消。", "INVALID_STATE" ])
      end

      customer.update!(redaction_scheduled_at: nil)
      Result.new(customer: customer.reload, error: nil)
    end
  end
end
