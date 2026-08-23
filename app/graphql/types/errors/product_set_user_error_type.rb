# frozen_string_literal: true

module Types
  module Errors
    # `productSet` 的 user error object（DisplayableError ＋ 我方加嚴的 code）。
    #
    # @see Types::Interfaces::DisplayableError
    class ProductSetUserErrorType < Types::BaseObject
      graphql_name "ProductSetUserError"
      description "productSet 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ProductSetUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
