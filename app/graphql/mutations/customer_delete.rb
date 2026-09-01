# frozen_string_literal: true

module Mutations
  # 顧客刪除（G6 步 8a）。
  #
  # 官方逐字："You can only delete customers who haven't placed any orders."
  # help 另擋 pending redaction（"has pending redaction because of a GDPR erasure
  # request"）——兩格都有突變紅證。
  class CustomerDelete < BaseMutation
    graphql_name "CustomerDelete"
    description "刪除顧客（有訂單或待抹除者擋下——官方同規則）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :id, GraphQL::Types::ID, required: true

    field :deleted_customer_id, GraphQL::Types::ID, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, id)
      if customer.nil?
        return { deleted_customer_id: nil,
                 user_errors: [ { field: [ "id" ], message: "找不到這位顧客。", code: "NOT_FOUND" } ] }
      end
      if ActsAsTenant.with_tenant(shop) { Order.where(customer_id: customer.id).exists? }
        return { deleted_customer_id: nil,
                 user_errors: [ { field: [ "id" ],
                                  message: "只能刪除沒有任何訂單的顧客（官方規則）。",
                                  code: "INVALID_STATE" } ] }
      end
      if customer.redaction_scheduled_at.present?
        return { deleted_customer_id: nil,
                 user_errors: [ { field: [ "id" ],
                                  message: "此顧客有待執行的個資抹除請求，不可刪除。",
                                  code: "INVALID_STATE" } ] }
      end

      ActsAsTenant.with_tenant(shop) do
        ActiveRecord::Base.transaction do
          CustomerMarketingConsent.where(customer_id: customer.id).delete_all
          CustomerAddress.where(customer_id: customer.id).delete_all
          Checkout.where(customer_id: customer.id).update_all(customer_id: nil)
          customer.destroy!
        end
      end
      { deleted_customer_id: id, user_errors: [] }
    end

    private

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && CustomerPolicy.new(staff, Customer).destroy?
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
  end
end
