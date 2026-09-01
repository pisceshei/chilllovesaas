# frozen_string_literal: true

module Types
  # 折扣（G6 步 9b；17-F1 單表多型的讀面）。
  #
  # percentage 對外＝**basisPoints Integer**（ours 加嚴：官方 API 是 0–1 Float，
  # 我方鐵律 3 全線禁 Float——admin SPA 是唯一客戶端，顯示層自行 /100）。
  class DiscountType < BaseObject
    graphql_name "Discount"
    description "折扣規則（code/automatic × product/order/shipping）"

    field :id, GraphQL::Types::ID, null: false
    field :title, String, null: false
    field :code, String, null: true
    field :method, String, null: false, description: "code/automatic", resolver_method: :discount_method
    field :discount_class, String, null: false, description: "product/order/shipping"
    field :value_type, String, null: false, description: "percentage/fixed_amount"
    field :basis_points, Integer, null: true, method: :percentage_basis_points
    field :value_cents, Integer, null: true
    field :currency, String, null: false
    field :combines_product, Boolean, null: false
    field :combines_order, Boolean, null: false
    field :combines_shipping, Boolean, null: false
    field :conditions, GraphQL::Types::JSON, null: false
    field :usage_limit, Integer, null: true
    field :times_used, Integer, null: false
    field :once_per_customer, Boolean, null: false
    field :starts_at, GraphQL::Types::ISO8601DateTime, null: true
    field :ends_at, GraphQL::Types::ISO8601DateTime, null: true
    field :status, String, null: false, description: "draft/scheduled/active/expired/archived（推導制）"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    def id
      "gid://chilllove/Discount/#{object.id}"
    end

    def discount_method = object.method

    def status = object.effective_status
  end
end
