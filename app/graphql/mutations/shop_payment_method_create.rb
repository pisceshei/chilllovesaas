# frozen_string_literal: true

module Mutations
  # 建立 manual 付款方式（G6-3 步 2；86 §3：⊕ 選單四值；內建型別每店恰一、
  # custom 名稱擋官方保留名單——皆由 model 驗證承載）。
  class ShopPaymentMethodCreate < BaseMutation
    graphql_name "ShopPaymentMethodCreate"
    description "建立 manual 付款方式（bank_deposit/money_order/cash_on_delivery/custom）。"

    user_errors_type Types::Errors::ShopPaymentMethodUserErrorType

    argument :method_type, String, required: true
    argument :name, String, required: false, description: "custom 必填；內建型別省略＝正典顯示名"
    argument :additional_details, String, required: false
    argument :payment_instructions, String, required: false

    field :shop_payment_method, Types::ShopPaymentMethodType, null: true

    def resolve(method_type:, name: nil, additional_details: nil, payment_instructions: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      unless ShopPaymentMethod::METHOD_TYPES.include?(method_type)
        return error("methodType", "付款方式型別不在允許值域內。", "INCLUSION")
      end
      if method_type == "custom" && name.blank?
        return error("name", "自訂付款方式必須命名。", "BLANK")
      end

      record = ActsAsTenant.with_tenant(shop) do
        ShopPaymentMethod.create(shop_id: shop.id, method_type:, name: name.presence,
                                 additional_details:, payment_instructions:,
                                 active: true, position: ShopPaymentMethod.maximum(:position).to_i + 1)
      end
      return invalid_record(record) unless record.persisted?

      payload(record)
    end

    def invalid_record(record)
      detail = record.errors.first
      { shop_payment_method: nil,
        user_errors: [ { field: [ detail.attribute.to_s.camelize(:lower) ],
                         message: detail.message, code: "INVALID" } ] }
    end

    private

    # 登入態即可（與 shopPaymentProviderSet 同門檻：settings 細粒度權限隨 M5 RBAC
    # 展開——「settings.edit」尚不存在於 RBAC 種子，先驗會鎖死全部非 owner 員工）。
    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def payload(record)
      { shop_payment_method: record, user_errors: [] }
    end

    def error(field, message, code)
      { shop_payment_method: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

    def find_method(shop, id)
      numeric = id.to_s[%r{\Agid://chilllove/ShopPaymentMethod/(\d+)\z}, 1]
      return nil if numeric.nil?

      ActsAsTenant.with_tenant(shop) { ShopPaymentMethod.find_by(id: numeric.to_i) }
    end
  end
end
