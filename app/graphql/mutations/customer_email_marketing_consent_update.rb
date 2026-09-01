# frozen_string_literal: true

module Mutations
  # email 行銷同意更新（官方 customerEmailMarketingConsentUpdate 對位；
  # 狀態機全文＝Customers::UpdateMarketingConsent 檔頭）。
  class CustomerEmailMarketingConsentUpdate < BaseMutation
    graphql_name "CustomerEmailMarketingConsentUpdate"
    description "更新顧客 email 行銷同意（可寫三值；latest-wins 合併）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :customer_id, GraphQL::Types::ID, required: true
    argument :email_marketing_consent, Types::Inputs::MarketingConsentInput, required: true

    field :customer, Types::CustomerType, null: true

    def resolve(customer_id:, email_marketing_consent:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, customer_id)
      return error("customerId", "找不到這位顧客。", "NOT_FOUND") if customer.nil?

      result = ActsAsTenant.with_tenant(shop) do
        Customers::UpdateMarketingConsent.call(
          shop:, customer:, channel: "email",
          state: email_marketing_consent[:marketing_state],
          opt_in_level: email_marketing_consent[:marketing_opt_in_level],
          consent_updated_at: email_marketing_consent[:consent_updated_at], source: "admin"
        )
      end
      return error("emailMarketingConsent", result.error[0], result.error[1]) if result.error

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
