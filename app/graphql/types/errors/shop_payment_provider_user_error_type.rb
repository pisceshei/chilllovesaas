# frozen_string_literal: true

module Types
  module Errors
    # PSP provider 設定的業務錯誤。
    class ShopPaymentProviderUserErrorType < Types::BaseObject
      graphql_name "ShopPaymentProviderUserError"
      description "PSP provider 設定的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ShopPaymentProviderUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
