# frozen_string_literal: true

module Types
  # manual 付款方式（G6-3 步 2；86 §3 實測正典）。
  class ShopPaymentMethodType < BaseObject
    graphql_name "ShopPaymentMethod"
    description "manual 付款方式（銀行轉帳／匯票／貨到付款／自訂）"

    field :id, GraphQL::Types::ID, null: false
    field :method_type, String, null: false, description: "bank_deposit/money_order/cash_on_delivery/custom"
    field :name, String, null: false
    field :additional_details, String, null: true,
          description: "結帳頁選方式時顯示（86 §3 helper 逐字對位）"
    field :payment_instructions, String, null: true,
          description: "下單後確認頁顯示（86 §3 helper 逐字對位）"
    field :active, Boolean, null: false
    field :position, Integer, null: false

    def id
      "gid://chilllove/ShopPaymentMethod/#{object.id}"
    end
  end
end
