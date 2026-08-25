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
      # 🔴 第 37 包新增兩碼，**都是 ours**：官方 `MediaUserErrorCode` 的 22 個值裡
      #   **沒有任何外部影片專屬碼**（已逐字核對）——官方那六個 `EXTERNAL_VIDEO_*`
      #   全在**非同步**的 `MediaErrorCode`／`FileErrorCode`，是建立成功之後才出現在
      #   `media.mediaErrors` 的。我方 A 面是**同步**形態驗證，需要可機器判別的分支
      #   （鐵律 4 的 ours 加嚴條款：admin SPA 是唯一客戶端，錯誤分支必須可判別）。
      # 🔴 **不得**把官方那六碼搬進來——那會把官方的同步／非同步層次搞反。
      own_value :EXTERNAL_VIDEO_UNSUPPORTED_HOST, "外嵌影片只支援 YouTube 與 Vimeo（ours）。"
      own_value :EXTERNAL_VIDEO_INVALID_URL, "外嵌影片 URL 解析不出影片 ID（ours）。"
    end
  end
end
