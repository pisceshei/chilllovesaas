# frozen_string_literal: true

module Types
  module Errors
    # shopPaymentProviderSet 的錯誤碼（鐵律 4：code 一律有值）。
    class ShopPaymentProviderUserErrorCode < BaseCodeEnum
      graphql_name "ShopPaymentProviderUserErrorCode"
      description "PSP provider 設定可能回傳的錯誤碼。"

      from_pools
      own_value :PROVIDER_UNKNOWN, "provider 不在平台 pack 字典內（config/limits.yml psp_packs）。"
      own_value :NOT_CONFIGURED, "尚未儲存 API 憑證——先填憑證才能讀取可用付款方式。"
      own_value :UPSTREAM_UNAUTHORIZED, "PSP 拒絕了憑證（401/403）——請重新確認 Client ID 與 API key。"
      own_value :UPSTREAM_ERROR, "PSP 端回應異常，請稍後重試。"
    end
  end
end
