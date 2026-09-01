# frozen_string_literal: true

module Mutations
  # 顧客合併（官方 customerMerge 對位；規則全文＝Customers::Merge 檔頭）。
  class CustomerMerge < BaseMutation
    graphql_name "CustomerMerge"
    description "合併兩位顧客（保留規則與 blockers 見 dev doc；不可復原）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_one_id, GraphQL::Types::ID, required: true
    argument :customer_two_id, GraphQL::Types::ID, required: true

    field :customer, Types::CustomerType, null: true,
          description: "合併後保留的顧客（官方 resultingCustomerId 語義）"

    def resolve(customer_one_id:, customer_two_id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      one = find_customer(shop, customer_one_id)
      two = find_customer(shop, customer_two_id)
      return error("customerOneId", "找不到顧客（官方 DELETED_AT）。", "NOT_FOUND") if one.nil?
      return error("customerTwoId", "找不到顧客（官方 DELETED_AT）。", "NOT_FOUND") if two.nil?

      result = ActsAsTenant.with_tenant(shop) do
        Customers::Merge.call(shop:, customer_one: one, customer_two: two)
      end
      return error("customerOneId", result.error[0], result.error[1]) if result.error

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
