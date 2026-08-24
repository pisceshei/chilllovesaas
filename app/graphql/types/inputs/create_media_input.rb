# frozen_string_literal: true

module Types
  module Inputs
    # productCreateMedia 的單筆輸入。
    #
    # 🔴 `originalSource` 與 `fileId` **二選一**（both／neither 都是 INVALID）：
    #   前者對齊官方契約（28 §契約「媒體」列 `media[]{originalSource, alt, mediaContentType}`）
    #   ——staged resourceUrl 直接建新檔；後者是我方擴充（ours），給第 28 包
    #   「選取現有檔案」用，避免同一張圖在檔案庫裡重複上傳。
    class CreateMediaInput < GraphQL::Schema::InputObject
      graphql_name "CreateMediaInput"
      description "要掛到商品上的一個媒體。"

      argument :original_source, String, required: false,
        description: "staged resourceUrl 或外部 URL（走 fileCreate 的同一條 SSRF 防線）。"
      argument :file_id, ID, required: false, description: "既有檔案 GID（ours 擴充）。"
      argument :alt, String, required: false
      argument :media_content_type, Types::MediaContentTypeEnum, required: false,
        description: "本批僅 IMAGE（B9）；省略即 IMAGE。"
    end
  end
end
