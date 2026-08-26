# frozen_string_literal: true

module Types
  module Errors
    # publication 生命週期的業務錯誤。
    #
    # 本尊對位＝`PublicationUserError`（object，不是 union；
    # `/unions/PublicationUserError` 回 404，取證 2026-08-26），實作 `DisplayableError`。
    class PublicationUserErrorType < Types::BaseObject
      graphql_name "PublicationUserError"
      description "publication 生命週期的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, PublicationUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值；🔴 本尊此欄可為 null，我方加嚴）。"
    end
  end
end
