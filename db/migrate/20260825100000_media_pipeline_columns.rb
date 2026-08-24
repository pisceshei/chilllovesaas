# frozen_string_literal: true

# 第 26 包（整合規格 §4-26）：處理管線的欄位與 default 修正。
#
# ①`media.status` default `"ready"` → `"uploaded"`：四態起點是 UPLOADED
#   （90-blueprint/01-products §B.3 G22：UPLOADED→PROCESSING→READY／FAILED）。
#   原 default 是 M0 建表時的佔位值，與狀態機矛盾——第 24 包登記、本包解掉。
#   🔴 既有列不回填：`media` 表在本包前**零列**（寫入端＝第 27 包 productCreateMedia
#   尚未落地），複驗 `SELECT COUNT(*) FROM media`。
# ②`media.file_id`：媒體指向檔案本體（`files`）。沒有它，`featuredImage` 拿不到
#   衍生尺寸——`source_url` 是字串、推導不出 derivatives。nullable 因為第 27 包
#   才開始寫入；FK 走複合鍵 (shop_id, file_id) → files(shop_id, id)（鐵律 2）。
# ③`files.derivatives`：衍生尺寸清單 JSON（variant → {key,width,height,byte_size}）。
#   單欄而非另立表：衍生是**檔案的附屬產物**、恆隨檔案生滅、無獨立查詢面
#   （查詢面是「這張圖的 thumb 在哪」＝跟著 file 一起讀）。
# ④`files.processing_error`：損壞檔 rescue 的訊息落點（13 §F3 坑：libvips 對損壞檔
#   拋例外 ⇒ 標「處理失敗」而不是無限重試）。
class MediaPipelineColumns < ActiveRecord::Migration[8.1]
  def change
    change_column_default :media, :status, from: "ready", to: "uploaded"

    add_column :media, :file_id, :bigint, null: true
    add_index :media, [ :shop_id, :file_id ], name: "ix_media_file_id"
    safety_assured do
      add_foreign_key :media, :files, column: [ :shop_id, :file_id ],
                      primary_key: [ :shop_id, :id ], name: "fk_media_file_id"
    end

    add_column :files, :derivatives, :json, null: true
    add_column :files, :processing_error, :text, null: true
  end
end
