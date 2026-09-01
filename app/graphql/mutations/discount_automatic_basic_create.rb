# frozen_string_literal: true

module Mutations
  # 建立自動折扣（basic 形）（官方同名 mutation 對位；輸入形＝ours 合流 DiscountBasicInput）。
  class DiscountAutomaticBasicCreate < BaseMutation
    graphql_name "DiscountAutomaticBasicCreate"
    description "建立自動折扣（basic 形）"

    user_errors_type Types::Errors::DiscountUserErrorType

    argument :input, Types::Inputs::DiscountBasicInput, required: true

    field :discount, Types::DiscountType, null: true

    def resolve(input:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!
      return error("title", "折扣必須命名。", "BLANK") if input[:title].blank?

      record = ActsAsTenant.with_tenant(shop) do
        Discount.new(shop_id: shop.id, method: "automatic", status: "active",
                     discount_class: input[:discount_class] || "order",
                     value_type: input[:value_type] || "percentage")
      end
      saved = ActsAsTenant.with_tenant(shop) { apply_input!(record, input) }
      return invalid_record(record) unless saved

      { discount: record.reload, user_errors: [] }
    end

    private

    # 登入態即可（payments/notifications 線同門檻：discounts.* 權限鍵不在 RBAC
    # 種子，先驗會鎖死全部非 owner 員工——8a 教訓；細粒度隨 M5）。
    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def find_discount(shop, id)
      numeric = id.to_s[%r{\Agid://chilllove/Discount/(\d+)\z}, 1]
      numeric && ActsAsTenant.with_tenant(shop) { Discount.find_by(id: numeric.to_i) }
    end

    def error(field, message, code)
      { discount: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

    def invalid_record(record)
      detail = record.errors.first
      code = detail.type == :taken ? "TAKEN" : "INVALID"
      { discount: nil,
        user_errors: [ { field: [ detail.attribute.to_s.camelize(:lower) ],
                         message: detail.message, code: } ] }
    end

    def apply_input!(record, input)
      attrs = {}
      %i[title code discount_class value_type combines_product combines_order
         combines_shipping usage_limit once_per_customer starts_at ends_at].each do |key|
        attrs[key] = input[key] unless input[key].nil?
      end
      attrs[:percentage_basis_points] = input[:basis_points] unless input[:basis_points].nil?
      attrs[:value_cents] = input[:value_cents] unless input[:value_cents].nil?

      conditions = (record.conditions || {}).dup
      conditions["min_subtotal_cents"] = input[:min_subtotal_cents] unless input[:min_subtotal_cents].nil?
      conditions["min_quantity"] = input[:min_quantity] unless input[:min_quantity].nil?
      attrs[:conditions] = conditions

      record.update(attrs)
    end
  end
end
