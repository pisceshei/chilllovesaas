# frozen_string_literal: true

module Types
  module Errors
    # 主題管理的業務錯誤。
    class ThemeManageUserErrorType < Types::BaseObject
      graphql_name "ThemeManageUserError"
      description "主題管理（rename/duplicate/delete）的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ThemeManageUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
