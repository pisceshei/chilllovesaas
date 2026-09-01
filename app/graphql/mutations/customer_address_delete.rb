# frozen_string_literal: true

module Mutations
  # 地址刪除（官方 customerAddressDelete；回 deletedAddressId 同形）。
  # 刪到預設地址時把預設讓給最舊的存活地址（本尊行為未取證＝ours 保守值，
  # 保證「有地址就有預設」不變量——checkout 預填依賴它）。
  class CustomerAddressDelete < BaseMutation
    graphql_name "CustomerAddressDelete"
    description "刪除顧客地址。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_id, GraphQL::Types::ID, required: true
    argument :address_id, GraphQL::Types::ID, required: true

    field :deleted_address_id, GraphQL::Types::ID, null: true

    def resolve(customer_id:, address_id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, customer_id)
      if customer.nil?
        return { deleted_address_id: nil,
                 user_errors: [ { field: [ "customerId" ], message: "找不到這位顧客。", code: "NOT_FOUND" } ] }
      end
      record = find_address(shop, customer, address_id)
      if record.nil?
        return { deleted_address_id: nil,
                 user_errors: [ { field: [ "addressId" ], message: "找不到這個地址。", code: "NOT_FOUND" } ] }
      end

      was_default = record.default_address
      ActsAsTenant.with_tenant(shop) do
        record.destroy!
        if was_default
          survivor = CustomerAddress.where(customer_id: customer.id).order(:id).first
          survivor&.update!(default_address: true)
        end
      end
      { deleted_address_id: address_id, user_errors: [] }
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
