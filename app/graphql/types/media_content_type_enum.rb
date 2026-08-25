# frozen_string_literal: true

module Types
  # 媒體型別（官方 MediaContentType 的本批子集）。
  #
  # 🔴 值域＝**兩鍵聯集**：`upload_media_types_enabled` ∪ `embed_media_types_enabled`。
  #   兩鍵是**不同的事**，合併成一鍵會把 B9 的閘門一起弄鬆：
  #   - `upload_*`＝可**上傳**的型別。B9（伺服器僅 libvips、無轉碼器）就靠它擋住
  #     影片／3D 上傳，`spec/config/m0_configuration_spec.rb` 釘死它等於 `%w[image]`。
  #   - `embed_*`＝可**外嵌**的型別（第 37 包）。外嵌不經上傳、不進 files 表、
  #     不佔儲存配額（官方逐字 "Doesn't count against shop's storage quota."）。
  #   ⇒ 加外嵌**一個字都不動 `upload_*`**。官方 `MediaContentType` 逐字含
  #     "EXTERNAL_VIDEO — An externally hosted video."（取證 2026-08-25）。
  class MediaContentTypeEnum < GraphQL::Schema::Enum
    graphql_name "MediaContentType"
    description "媒體型別。"

    (Limits.enum(:media, :upload_media_types_enabled) |
     Limits.enum(:media, :embed_media_types_enabled)).sort.each do |value|
      value value.to_s, value: value.to_s.downcase
    end
  end
end
