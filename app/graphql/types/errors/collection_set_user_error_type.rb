# frozen_string_literal: true

module Types
  module Errors
    # collectionSet 的業務錯誤。
    class CollectionSetUserErrorType < Types::BaseObject
      graphql_name "CollectionSetUserError"
      description "collectionSet 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, CollectionSetUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
