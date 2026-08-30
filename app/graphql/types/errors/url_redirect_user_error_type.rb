# frozen_string_literal: true

module Types
  module Errors
    # 重導管理的業務錯誤。
    class UrlRedirectUserErrorType < Types::BaseObject
      graphql_name "UrlRedirectUserError"
      description "重導管理的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, UrlRedirectUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
