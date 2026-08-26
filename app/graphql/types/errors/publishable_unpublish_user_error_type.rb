# frozen_string_literal: true

module Types
  module Errors
    # 把資源自 publication 取消發布時的業務錯誤（S5）。
    #
    # 🔴 本尊此處是**裸 `UserError`**（無 `code`，取證 2026-08-27）；
    #   本型別與其 `code` 欄都是我方新增。偏離依據與登記見
    #   `PublishablePublishUserErrorCode` 檔頭。
    class PublishableUnpublishUserErrorType < Types::BaseObject
      graphql_name "PublishableUnpublishUserError"
      description "把資源自 publication 取消發布時的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, PublishableUnpublishUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值；🔴 本尊此線根本沒有這個欄位）。"
    end
  end
end
