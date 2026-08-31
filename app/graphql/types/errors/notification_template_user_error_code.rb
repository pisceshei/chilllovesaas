# frozen_string_literal: true

module Types
  module Errors
    # notificationTemplateUpdate 的錯誤碼。
    class NotificationTemplateUserErrorCode < BaseCodeEnum
      graphql_name "NotificationTemplateUserErrorCode"
      description "notificationTemplateUpdate 可能回傳的錯誤碼。"

      from_pools
    end
  end
end
