# frozen_string_literal: true

module Mutations
  # 更新 manual 付款方式的文案（G6-3 步 2；86 §3 兩欄表單）。
  class ShopPaymentMethodUpdate < BaseMutation
    graphql_name "ShopPaymentMethodUpdate"
    description "更新 manual 付款方式（名稱與兩欄文案；省略＝不變）。"

    user_errors_type Types::Errors::ShopPaymentMethodUserErrorType

    argument :id, GraphQL::Types::ID, required: true
    argument :name, String, required: false
    argument :additional_details, String, required: false
    argument :payment_instructions, String, required: false

    field :shop_payment_method, Types::ShopPaymentMethodType, null: true

    def resolve(id:, name: nil, additional_details: nil, payment_instructions: nil)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      record = find_method(shop, id)
      return error("id", "找不到這個付款方式。", "NOT_FOUND") if record.nil?

      attrs = {}
      attrs[:name] = name unless name.nil?
      attrs[:additional_details] = additional_details unless additional_details.nil?
      attrs[:payment_instructions] = payment_instructions unless payment_instructions.nil?
      ok = ActsAsTenant.with_tenant(shop) { record.update(attrs) }
      unless ok
        detail = record.errors.first
        return error(detail.attribute.to_s.camelize(:lower), detail.message, "INVALID")
      end

      payload(record)
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
