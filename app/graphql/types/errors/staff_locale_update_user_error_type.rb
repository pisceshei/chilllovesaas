# frozen_string_literal: true

module Types
  module Errors
    # staffLocaleUpdate 的業務錯誤物件。
    class StaffLocaleUpdateUserErrorType < Types::BaseObject
      graphql_name "StaffLocaleUpdateUserError"
      description "staffLocaleUpdate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, StaffLocaleUpdateUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
