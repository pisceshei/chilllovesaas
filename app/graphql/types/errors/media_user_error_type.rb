# frozen_string_literal: true

module Types
  module Errors
    # 媒體線的 user error object。
    class MediaUserErrorType < Types::BaseObject
      graphql_name "MediaUserError"
      description "媒體 mutations 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, MediaUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
