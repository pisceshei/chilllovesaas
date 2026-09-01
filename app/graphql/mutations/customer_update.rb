# frozen_string_literal: true

module Mutations
  # 顧客更新（G6 步 8a）。
  #
  # 🔴 不收 consent（官方逐字："To set marketing consent, use the
  # customerEmailMarketingConsentUpdate or customerSmsMarketingConsentUpdate
  # mutations instead."）。tags＝**覆寫**（官方逐字："Updating tags overwrites
  # any existing tags that were previously added to the customer."）。
  class CustomerUpdate < BaseMutation
    graphql_name "CustomerUpdate"
    description "更新顧客基本資料（省略＝不變；tags 為覆寫語義；consent 走專用 mutation）。"

    user_errors_type Types::Errors::CustomerUserErrorType

    argument :id, GraphQL::Types::ID, required: true
    argument :first_name, String, required: false
    argument :last_name, String, required: false
    argument :email, String, required: false
    argument :phone, String, required: false
    argument :note, String, required: false
    argument :locale, String, required: false
    argument :tags, [ String ], required: false
    argument :tax_exempt, Boolean, required: false

    field :customer, Types::CustomerType, null: true

    def resolve(id:, **args)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      customer = find_customer(shop, id)
      return error("id", "找不到這位顧客。", "NOT_FOUND") if customer.nil?
      if customer.anonymized_at.present?
        return error("id", "個資已抹除的顧客不可編輯。", "NOT_EDITABLE")
      end

      attrs = {}
      %i[first_name last_name email phone note tags tax_exempt locale].each do |key|
        attrs[key] = args[key] if args.key?(key)
      end
      ok = ActsAsTenant.with_tenant(shop) { customer.update(attrs) }
      return invalid_record(customer) unless ok

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
