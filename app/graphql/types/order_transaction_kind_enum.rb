# frozen_string_literal: true

module Types
  # 交易種類（G6-6a；對位 Admin API OrderTransactionKind）。
  # 值域＝OrderTransaction::KINDS（v1 五值：sale/authorization/capture/void/refund；
  # 藍圖八值中 POS 專屬的 CHANGE/EMV_AUTHORIZATION 與非落庫的 SUGGESTED_REFUND
  # 不建值——model 檔頭同一裁定，兩處同源）。
  class OrderTransactionKindEnum < GraphQL::Schema::Enum
    graphql_name "OrderTransactionKind"
    description "金流交易種類"

    OrderTransaction::KINDS.each do |kind|
      value kind.upcase, value: kind
    end
  end
end
