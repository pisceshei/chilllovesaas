# frozen_string_literal: true

module Mutations
  # 取消抹除（官方 customerCancelDataErasure："Cancels a pending erasure of a
  # customer's data."）。
  class CustomerCancelDataErasure < BaseMutation
    graphql_name "CustomerCancelDataErasure"
    description "取消待執行的個資抹除請求（已執行者不可取消）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_id, GraphQL::Types::ID, required: true

    field :customer, Types::CustomerType, null: true

    def resolve(customer_id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, customer_id)
      return error("customerId", "找不到這位顧客。", "NOT_FOUND") if customer.nil?

      result = ActsAsTenant.with_tenant(shop) { Customers::CancelDataErasure.call(customer:) }
      return error("customerId", result.error[0], result.error[1]) if result.error

      { customer: result.customer, user_errors: [] }
    end

    private

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && CustomerPolicy.new(staff, Customer).update?
        raise GraphQL::ExecutionError.new(
          I18n.t("errors.customers.access_denied", default: "沒有顧客管理權限。"),
          extensions: { "code" => "ACCESS_DENIED" }
        )
      end

      context.fetch(:current_shop)
    end

    def find_customer(shop, id)
      numeric = id.to_s[%r{\Agid://chilllove/Customer/(\d+)\z}, 1]
      numeric && ActsAsTenant.with_tenant(shop) { Customer.find_by(id: numeric.to_i) }
    end

    def error(field, message, code)
      { customer: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
