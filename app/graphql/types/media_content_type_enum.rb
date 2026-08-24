# frozen_string_literal: true

module Types
  # 媒體型別（官方 MediaContentType 的本批子集）。
  # 🔴 B9：本批只開 IMAGE——伺服器僅 libvips、無轉碼器；影片走第 37 包外嵌 ExternalVideo。
  #   值域取 limits `media.upload_media_types_enabled`（改 limits 即改 schema）。
  class MediaContentTypeEnum < GraphQL::Schema::Enum
    graphql_name "MediaContentType"
    description "媒體型別。"

    Limits.enum(:media, :upload_media_types_enabled).each do |value|
      value value.to_s, value: value.to_s.downcase
    end
  end
end
