# frozen_string_literal: true

module Types
  module Errors
    # themePublish 的業務錯誤（本尊對位＝`ThemePublishUserError`，取證 2026-08-30）。
    class ThemePublishUserErrorType < Types::BaseObject
      graphql_name "ThemePublishUserError"
      description "themePublish 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ThemePublishUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值；本尊此欄 nullable，我方加嚴）。"
    end
  end
end
