# frozen_string_literal: true

module Types
  module Errors
    # 語言設定的業務錯誤。
    class ShopLocaleUserErrorType < Types::BaseObject
      graphql_name "ShopLocaleUserError"
      description "語言設定的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ShopLocaleUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
