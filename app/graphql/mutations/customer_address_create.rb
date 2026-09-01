# frozen_string_literal: true

module Mutations
  # 地址建立（官方 customerAddressCreate 對位："You can optionally set the
  # address as the customer's default address."）。
  class CustomerAddressCreate < BaseMutation
    graphql_name "CustomerAddressCreate"
    description "為顧客建立地址（可同時設為預設）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_id, GraphQL::Types::ID, required: true
    argument :address, Types::Inputs::CustomerAddressInput, required: true
    argument :set_as_default, Boolean, required: false

    field :customer_address, Types::CustomerAddressType, null: true

    def resolve(customer_id:, address:, set_as_default: false)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, customer_id)
      return error("customerId", "找不到這位顧客。", "NOT_FOUND") if customer.nil?

      record = ActsAsTenant.with_tenant(shop) do
        CustomerAddress.new(shop_id: shop.id, customer_id: customer.id, **address_attrs(address))
      end
      saved = ActsAsTenant.with_tenant(shop) { record.save }
      unless saved
        detail = record.errors.first
        return error(detail.attribute.to_s.camelize(:lower), detail.message, "INVALID")
      end

      is_first = ActsAsTenant.with_tenant(shop) do
        CustomerAddress.where(customer_id: customer.id).count == 1
      end
      set_default!(shop, customer, record) if set_as_default || is_first

      { customer_address: record.reload, user_errors: [] }
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
      { customer_address: nil, user_errors: [ { field: [ field ], message:, code: } ] }
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
