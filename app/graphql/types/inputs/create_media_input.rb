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
        description: "staged resourceUrl／外部檔案 URL／YouTube 或 Vimeo 影片頁 URL。"
      argument :file_id, ID, required: false, description: "既有檔案 GID（ours 擴充）。"
      argument :alt, String, required: false
      # 第 37 包：值域＝IMAGE ∪ EXTERNAL_VIDEO。
      # 🔴 省略時**不是恆 IMAGE**：`MediaSync` 會看 `originalSource` 的形態——命中
      #   YouTube／Vimeo 就走外嵌（ours）。不這樣做的話，使用者貼 YouTube URL 會掉進
      #   `Storage::FileCreate` 去抓一份 HTML，錯誤訊息與真實原因完全無關。
      argument :media_content_type, Types::MediaContentTypeEnum, required: false,
        description: "IMAGE 或 EXTERNAL_VIDEO；省略時依 originalSource 形態判定。"
    end
  end
end
