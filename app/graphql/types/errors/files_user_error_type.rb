# frozen_string_literal: true

module Types
  module Errors
    # 檔案線的 user error object。
    class FilesUserErrorType < Types::BaseObject
      graphql_name "FilesUserError"
      description "檔案 mutations 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, FilesUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
