# frozen_string_literal: true

module Types
  module Errors
    # 內容線 mutation 的業務錯誤。
    class ContentUserErrorType < Types::BaseObject
      graphql_name "ContentUserError"
      description "內容線（pages/blogs/articles/menus）的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, ContentUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
