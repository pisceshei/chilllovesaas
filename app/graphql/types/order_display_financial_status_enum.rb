# frozen_string_literal: true

module Types
  # 訂單金流顯示狀態（G6-6a；對位 Admin API OrderDisplayFinancialStatus 八值——
  # 88 §7 官方取證 2026-09-01；儲存層＝orders.financial_status 小寫八值同集，
  # Order::FINANCIAL_STATUSES 是唯一值域正典）。
  #
  # ⚠ 列表「篩選層」另有 Due/Unpaid 兩個聚合值（88 §2 層差登記）——那是查詢語法
  # 的糖，不是本 enum 的值；不得混進來。
  class OrderDisplayFinancialStatusEnum < GraphQL::Schema::Enum
    graphql_name "OrderDisplayFinancialStatus"
    description "訂單的金流顯示狀態"

    Order::FINANCIAL_STATUSES.each do |status|
      value status.upcase, value: status
    end
  end
end
