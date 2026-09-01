# frozen_string_literal: true

module Mutations
  # 顧客建立（G6 步 8a；官方 customerCreate 對位）。
  #
  # 官方要點（取證 2026-09-01）：email/phone 唯一（"The unique email address of
  # the customer."）；三擇一必填（"Customer must have a name, phone number or
  # email address"）；consent 可在 create 帶入（update 則走專用 mutation）。
  # tags＝覆寫語義與 update 共用（官方逐字見 customer_update.rb）。
  class CustomerCreate < BaseMutation
    graphql_name "CustomerCreate"
    description "建立顧客（name/email/phone 三擇一必填；consent 可隨建帶入）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :first_name, String, required: false
    argument :last_name, String, required: false
    argument :email, String, required: false
    argument :phone, String, required: false
    argument :note, String, required: false
    argument :locale, String, required: false, description: "通知語言（BCP-47；null＝店預設）"
    argument :tags, [ String ], required: false
    argument :tax_exempt, Boolean, required: false
    argument :email_marketing_consent, Types::Inputs::MarketingConsentInput, required: false
    argument :sms_marketing_consent, Types::Inputs::MarketingConsentInput, required: false

    field :customer, Types::CustomerType, null: true

    def resolve(**args)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      if args[:first_name].blank? && args[:last_name].blank? &&
         args[:email].blank? && args[:phone].blank?
        return error("email", "顧客必須有姓名、電話或 email 其中之一（官方底線）。", "INVALID")
      end
      if args[:email_marketing_consent] && args[:email].blank?
        return error("email", "帶 email 行銷同意時必須提供 email（官方前置）。", "INVALID")
      end
      if args[:sms_marketing_consent] && args[:phone].blank?
        return error("phone", "帶 SMS 行銷同意時必須提供電話（官方前置）。", "INVALID")
      end

      customer = ActsAsTenant.with_tenant(shop) do
        Customer.new(shop_id: shop.id,
                     first_name: args[:first_name], last_name: args[:last_name],
                     email: args[:email].presence, phone: args[:phone].presence,
                     note: args[:note], tags: args[:tags] || [], locale: args[:locale].presence,
                     tax_exempt: args.fetch(:tax_exempt, false))
      end
      return invalid_record(customer) unless ActsAsTenant.with_tenant(shop) { customer.save }

      [ [ :email_marketing_consent, "email" ], [ :sms_marketing_consent, "sms" ] ].each do |key, channel|
        consent = args[key]
        next if consent.nil?

        result = ActsAsTenant.with_tenant(shop) do
          Customers::UpdateMarketingConsent.call(
            shop:, customer:, channel:, state: consent[:marketing_state],
            opt_in_level: consent[:marketing_opt_in_level],
            consent_updated_at: consent[:consent_updated_at], source: "admin"
          )
        end
        if result.error
          return { customer: customer.reload,
                   user_errors: [ { field: [ key.to_s.camelize(:lower) ],
                                    message: result.error[0], code: result.error[1] } ] }
        end
      end

      { customer: customer.reload, user_errors: [] }
    end

    private

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && CustomerPolicy.new(staff, Customer).create?
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

    # model 驗證失敗 → userError（唯一鍵撞名 ⇒ TAKEN，對位 REST 422 has already been taken）。
    def invalid_record(record)
      detail = record.errors.first
      code = detail.type == :taken ? "TAKEN" : "INVALID"
      { customer: nil,
        user_errors: [ { field: [ detail.attribute.to_s.camelize(:lower) ],
                         message: detail.message, code: } ] }
    end
  end
end
