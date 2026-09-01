# frozen_string_literal: true

module Types
  module Inputs
    # Basic 折扣輸入（官方 DiscountCodeBasicInput/DiscountAutomaticBasicInput 的
    # ours 合流形：discountClass 顯式（官方以 customerGets 結構隱含）；
    # basisPoints Integer（官方 0–1 Float——鐵律 3 禁 Float 的 API 面）。
    class DiscountBasicInput < GraphQL::Schema::InputObject
      graphql_name "DiscountBasicInput"
      description "折扣欄位（省略＝不變；create 時 title 必填）"

      argument :title, String, required: false
      argument :code, String, required: false, description: "code method 專用（正規化 upcase+trim）"
      argument :discount_class, String, required: false, description: "product/order/shipping"
      argument :value_type, String, required: false
      argument :basis_points, Integer, required: false
      argument :value_cents, Integer, required: false
      argument :combines_product, Boolean, required: false
      argument :combines_order, Boolean, required: false
      argument :combines_shipping, Boolean, required: false
      argument :min_subtotal_cents, Integer, required: false
      argument :min_quantity, Integer, required: false
      argument :usage_limit, Integer, required: false
      argument :once_per_customer, Boolean, required: false
      argument :starts_at, GraphQL::Types::ISO8601DateTime, required: false
      argument :ends_at, GraphQL::Types::ISO8601DateTime, required: false
    end
  end
end
