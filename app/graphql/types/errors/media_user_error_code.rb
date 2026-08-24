# frozen_string_literal: true

module Types
  module Errors
    # 媒體線 mutation 的 typed error code enum（鐵律 4）。
    class MediaUserErrorCode < BaseCodeEnum
      graphql_name "MediaUserErrorCode"
      description "媒體 mutations 可能回傳的錯誤碼。"

      from_pools
      own_value :MEDIA_LIMIT_EXCEEDED, "媒體數超過 limits.product.max_media。"
      own_value :ALT_VALUE_LIMIT_EXCEEDED, "alt 文字超過 512 字元上限。"
      own_value :FILE_DOES_NOT_EXIST, "指定的檔案不存在。"
      own_value :UNACCEPTABLE_ASSET, "格式不受理（本批僅接受圖片）。"
    end
  end
end
