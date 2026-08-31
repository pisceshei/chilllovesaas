# frozen_string_literal: true

module Types
  # 交易狀態（G6-6a；對位 Admin API OrderTransactionStatus）。
  # 值域＝OrderTransaction::STATUSES 六值全落（pending/success/failure/error/
  # awaiting_response/unknown）；UNKNOWN 非終態、由 reconcile job 收斂
  # （90-blueprint/05 §B.1.1-R2——本 enum 只是出口，收斂語義在服務層）。
  class OrderTransactionStatusEnum < GraphQL::Schema::Enum
    graphql_name "OrderTransactionStatus"
    description "金流交易狀態"

    OrderTransaction::STATUSES.each do |status|
      value status.upcase, value: status
    end
  end
end
