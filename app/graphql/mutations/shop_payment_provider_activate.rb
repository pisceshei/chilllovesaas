# frozen_string_literal: true

module Mutations
  # 啟用 PSP provider（G6-3 步 2；activation 狀態機——取代「有指紋即啟用」的
  # 隱式判定：status 欄成為唯一啟用真相，checkout 的 configured_provider 同批改讀它）。
  #
  # 前置：憑證已存（api_secret_fingerprint 非空）——沒憑證的 activate 回
  # INVALID_STATE（86 §1 本尊 Activate 鈕的前置＝完成 setup）。
  class ShopPaymentProviderActivate < BaseMutation
    graphql_name "ShopPaymentProviderActivate"
    description "啟用 PSP provider（結帳頁付款段隨之顯示；前置＝憑證已設定）。"

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
      if record.api_secret_fingerprint.blank?
        return { shop_payment_provider: record,
                 user_errors: [ { field: [ "provider" ],
                                  message: "先完成憑證設定才能啟用。", code: "INVALID_STATE" } ] }
      end

      ActsAsTenant.with_tenant(shop) { record.update!(status: "active") }
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
