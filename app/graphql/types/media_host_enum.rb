# frozen_string_literal: true

module Types
  # 外嵌影片的平台（第 37 包）。
  #
  # 🔴 型別名是 **`MediaHost`**，不是 `ExternalVideoHost`——後者在官方 schema 裡
  #   **不存在**。憑印象命名會建出一個本尊沒有的型別，而 admin SPA 是唯一客戶端、
  #   一旦寫進查詢就得改回來。
  #   官方逐字："VIMEO — Host for Vimeo embedded videos." /
  #   "YOUTUBE — Host for YouTube embedded videos."
  #   <https://shopify.dev/docs/api/admin-graphql/latest/enums/MediaHost>（取證 2026-08-25）
  #
  # 值域封閉、恰兩值，由 limits `media.external_video_hosts` 導出（鐵律 6）。
  class MediaHostEnum < GraphQL::Schema::Enum
    graphql_name "MediaHost"
    description "外嵌影片的平台。"

    Limits.enum(:media, :external_video_hosts).each do |value|
      value value.to_s, value: value.to_s.downcase
    end
  end
end
