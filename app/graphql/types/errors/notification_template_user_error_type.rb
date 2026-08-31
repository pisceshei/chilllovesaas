# frozen_string_literal: true

module Types
  module Errors
    # notificationTemplateUpdate 的 userError。
    class NotificationTemplateUserErrorType < BaseObject
      graphql_name "NotificationTemplateUserError"
      description "notificationTemplateUpdate 的業務錯誤。"

      implements Types::Interfaces::DisplayableError

      field :code, NotificationTemplateUserErrorCode, null: false
    end
  end
end
