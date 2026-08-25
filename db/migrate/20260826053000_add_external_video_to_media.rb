# frozen_string_literal: true

# 第 37 包：外嵌 ExternalVideo（YouTube／Vimeo）。
#
# 只加兩欄——其餘一律複用既有欄位：
#   `media_type='external_video'`／`source_url`＝正規化後的 origin URL／
#   `alt_text`＝外嵌影片的 alt 權威（D48 對「有檔案」的媒體不變，見 `Media#alt_authority`）／
#   `file_id` 恆 NULL（A 面無縮圖檔）。
#
# 🔴 **不另開 `external_origin_url` 欄**：`source_url` 是 `null: false`，另開欄就得在
#   `source_url` 塞一個無意義佔位值——那才是真正的兩套真相。`source_url` 的語義本來
#   就是「這個媒體從哪來」：圖片列放內部 blob 路徑、外嵌放來源頁 URL。
class AddExternalVideoToMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :media, :external_host, :string, limit: 16,
      comment: "外嵌影片平台（youtube／vimeo，小寫；對齊 Liquid external_video.host 值域）"
    # 🔴 `string` 不是整數：Vimeo 是純數字但 YouTube 不是，且 Liquid 的
    #   `external_video.external_id` 官方型別逐字就是 string。
    add_column :media, :external_id, :string, limit: 32,
      comment: "平台的影片 ID（string——YouTube 非數字）"
    # 鐵律 2：複合索引以 shop_id 開頭。用途＝日後查「這支影片被哪些商品用了」。
    add_index :media, [ :shop_id, :external_host, :external_id ], name: "ix_media_external_ref"
  end
end
