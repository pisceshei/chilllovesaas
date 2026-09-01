# frozen_string_literal: true

module Mutations
  # 手動寄挽回信（G6 步 7；89 §6 官方手動路徑的按鈕化）。
  #
  # 前置：checkout 已標棄單（abandoned_at 非空）∧ email 非空 ∧ 未成單。
  # 寄送走步 6 通知鏈（DeliverJob abandoned_checkout 分支；交易外 IO——鐵律 5）。
  # 自動排程寄送（本尊 Messaging automation 的 Send after）＝⚪ 後置。
  class AbandonedCheckoutSendRecovery < BaseMutation
    graphql_name "AbandonedCheckoutSendRecovery"
    description "對棄單寄出挽回信（走通知模板 abandoned_checkout）。"

    user_errors_type Types::Errors::AbandonedCheckoutUserErrorType

    argument :id, GraphQL::Types::ID, required: true

    field :abandoned_checkout, Types::AbandonedCheckoutType, null: true

    def resolve(id:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      numeric = id.to_s[%r{\Agid://chilllove/AbandonedCheckout/(\d+)\z}, 1]
      checkout = numeric && ActsAsTenant.with_tenant(shop) { Checkout.find_by(id: numeric.to_i) }
      return error("id", "找不到這筆棄單。", "NOT_FOUND") if checkout.nil?
      return error("id", "此結帳尚未達棄單判定。", "INVALID_STATE") if checkout.abandoned_at.nil?
      return error("id", "此結帳沒有 email，無法寄送。", "INVALID_STATE") if checkout.email.blank?
      if ActsAsTenant.with_tenant(shop) { Order.where(checkout_id: checkout.id).exists? }
        return error("id", "此結帳已完成下單。", "INVALID_STATE")
      end

      Notifications::DeliverJob.perform_later(shop_id: shop.id, kind: "abandoned_checkout",
                                              checkout_id: checkout.id)
      { abandoned_checkout: checkout, user_errors: [] }
    end

    private

    def error(field, message, code)
      { abandoned_checkout: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end

    def authorized_shop!
      staff = context[:current_staff]
      unless staff && OrderPolicy.new(staff, Order).index?
        raise GraphQL::ExecutionError.new(
          I18n.t("errors.orders.access_denied"),
          extensions: { "code" => "ACCESS_DENIED" }
        )
      end

      context.fetch(:current_shop)
    end
  end
end
