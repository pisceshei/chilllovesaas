# frozen_string_literal: true

module Types
  module Errors
    # collectionSet 的錯誤碼（鐵律 4：code 一律有值）。
    class CollectionSetUserErrorCode < BaseCodeEnum
      graphql_name "CollectionSetUserErrorCode"
      description "collectionSet 可能回傳的錯誤碼。"

      from_pools
      own_value :HANDLE_TAKEN, "handle 已被同店其他系列使用。"
      own_value :LOCALE_NOT_ENABLED, "指定的語言未在本商店啟用。"
    end
  end
end
