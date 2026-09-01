# frozen_string_literal: true

module Mutations
  # 預設地址切換（官方 customerUpdateDefaultAddress 對位）。
  class CustomerUpdateDefaultAddress < BaseMutation
    graphql_name "CustomerUpdateDefaultAddress"
    description "把指定地址設為顧客預設地址。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_id, GraphQL::Types::ID, required: true
    argument :address_id, GraphQL::Types::ID, required: true

    field :customer, Types::CustomerType, null: true

    def resolve(customer_id:, address_id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, customer_id)
      if customer.nil?
        return { customer: nil,
                 user_errors: [ { field: [ "customerId" ], message: "找不到這位顧客。", code: "NOT_FOUND" } ] }
      end
      record = find_address(shop, customer, address_id)
      if record.nil?
        return { customer: nil,
                 user_errors: [ { field: [ "addressId" ], message: "找不到這個地址。", code: "NOT_FOUND" } ] }
      end

      set_default!(shop, customer, record)
      { customer: customer.reload, user_errors: [] }
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

    def find_address(shop, customer, id)
      numeric = id.to_s[%r{\Agid://chilllove/CustomerAddress/(\d+)\z}, 1]
      numeric && ActsAsTenant.with_tenant(shop) do
        CustomerAddress.find_by(customer_id: customer.id, id: numeric.to_i)
      end
    end

    def error(field, message, code)
      { customer: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

    def set_default!(shop, customer, address)
      ActsAsTenant.with_tenant(shop) do
        CustomerAddress.where(customer_id: customer.id).update_all(default_address: false)
        address.update!(default_address: true)
      end
    end

    ADDRESS_KEYS = %i[first_name last_name company address1 address2 city
                      province postal_code country_code phone].freeze

    def address_attrs(input)
      ADDRESS_KEYS.index_with { |key| input[key] }.compact
    end
  end
end
