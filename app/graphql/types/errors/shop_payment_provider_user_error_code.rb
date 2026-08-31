# frozen_string_literal: true

module Types
  module Errors
    # shopPaymentProviderSet 的錯誤碼（鐵律 4：code 一律有值）。
    class ShopPaymentProviderUserErrorCode < BaseCodeEnum
      graphql_name "ShopPaymentProviderUserErrorCode"
      description "PSP provider 設定可能回傳的錯誤碼。"

      from_pools
      own_value :PROVIDER_UNKNOWN, "provider 不在平台 pack 字典內（config/limits.yml psp_packs）。"
    end
  end
end
