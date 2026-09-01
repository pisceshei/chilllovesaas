# frozen_string_literal: true

module Types
  module Errors
    # webhook 訂閱 mutation 的業務錯誤。
    class WebhookUserErrorType < Types::BaseObject
      graphql_name "WebhookUserError"
      description "webhook 訂閱 mutation 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, WebhookUserErrorCode, null: false,
        description: "機器可判別的錯誤碼（鐵律 4：一律有值）。"
    end
  end
end
