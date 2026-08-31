# frozen_string_literal: true

module Mutations
  # 手動重新讀取 PSP 帳號已開通的付款方式（詳情頁「重新讀取」鈕；G6-1b）。
  #
  # 語義見 `Psp::ProviderCapabilities`（首次全開／其後保留手動關閉／移除不可用）。
  # 🔴 外部 IO 在 DB 交易外（鐵律 5）；上游失敗走 **userErrors**（可判別 code），
  # 不是 top-level error——這是商家可自行修復的業務情境（憑證錯／PSP 暫時異常）。
  class ShopPaymentProviderSyncCapabilities < BaseMutation
    graphql_name "ShopPaymentProviderSyncCapabilities"
    description "重新讀取 PSP 帳號已開通的付款方式並更新快取（首次成功會自動啟用可用方式）。"

    user_errors_type Types::Errors::ShopPaymentProviderUserErrorType

    argument :provider, String, required: true

    field :shop_payment_provider, Types::ShopPaymentProviderType, null: true

    def resolve(provider:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      record = ActsAsTenant.with_tenant(shop) { ShopPaymentProvider.find_by(provider:) }
      unless ShopPaymentProvider.provider_dictionary.include?(provider)
        return invalid("provider", "provider 不在平台 pack 字典內", "PROVIDER_UNKNOWN")
      end
      if record.nil? || record.api_secret.blank?
        return invalid("provider", "尚未儲存 API 憑證——先填憑證才能讀取可用付款方式", "NOT_CONFIGURED")
      end

      begin
        ActsAsTenant.with_tenant(shop) { Psp::ProviderCapabilities.sync!(record) }
      rescue Psp::Airwallex::Client::Unauthorized
        return invalid("provider", "Airwallex 拒絕了這組憑證（credentials_invalid）", "UPSTREAM_UNAUTHORIZED")
      rescue Psp::ProviderCapabilities::Unsupported => error
        return invalid("provider", error.message, "INVALID_STATE")
      rescue Psp::Airwallex::Client::Error => error
        return invalid("provider", "讀取可用付款方式失敗：#{error.message}", "UPSTREAM_ERROR")
      end

      { shop_payment_provider: record, user_errors: [] }
    end

    private

    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end

    def invalid(field, message, code)
      { shop_payment_provider: nil, user_errors: [ { field: [ field ], message:, code: } ] }
    end
  end
end
