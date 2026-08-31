# frozen_string_literal: true

module Mutations
  # 停用 PSP provider（G6-3 步 2；憑證保留——與 manual method 的 deactivate 同語義，
  # 停用後結帳頁付款段不再顯示該 provider 的方式）。
  class ShopPaymentProviderDeactivate < BaseMutation
    graphql_name "ShopPaymentProviderDeactivate"
    description "停用 PSP provider（憑證保留、可隨時再啟用）。"

    user_errors_type Types::Errors::ShopPaymentProviderUserErrorType

    argument :provider, String, required: true

    field :shop_payment_provider, Types::ShopPaymentProviderType, null: true

    def resolve(provider:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      record = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.find_by(provider:) }
      if record.nil?
        return { shop_payment_provider: nil,
                 user_errors: [ { field: [ "provider" ], message: "此 provider 尚未設定。", code: "NOT_FOUND" } ] }
      end

      ActsAsTenant.with_tenant(shop) { record.update!(status: "inactive") }
      { shop_payment_provider: record, user_errors: [] }
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
  end
end
