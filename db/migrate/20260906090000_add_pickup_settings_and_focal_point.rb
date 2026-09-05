# frozen_string_literal: true

# T14：①門市取貨（本尊 Settings › Shipping and delivery › Pickup in store，每地點一組設定——
#   help.shopify.com/en/manual/shipping/setting-up-and-managing-your-shipping/local-methods/local-pickup 逐字四區塊
#   "Location status"／"Expected pickup date"／"Store transfers"／"Ready for pickup notification"，取證 2026-09-05）。
#   Liquid 面＝`variant.store_availabilities`（array of store_availability：available／location／pick_up_enabled／pick_up_time），
#   官方另載 location 物件 "is only available when one or more locations have local pickup enabled"。
#   三套主題（Ella `sections/pickup-availability`、Kalles `blocks/_product-pickup`、Minimog `sections/pickup-availability`）都讀它。
# ②圖片焦點（本尊 image.presentation.focal_point；官方 focal_point.x／y＝百分比、"Returns 50 if no focal point is set"）。
#   欄位為 NULL ⇒ drop 回官方預設 50／50；admin 設定面＝後續包（91 §3.91 V）。
class AddPickupSettingsAndFocalPoint < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :pick_up_enabled, :boolean, default: false, null: false,
               comment: "本尊「Let customers pick up orders directly at this location」；false ⇒ 該地點不進 store_availabilities"
    add_column :locations, :pick_up_time, :string, limit: 64,
               comment: "本尊 Expected pickup date 的顯示字串（如 Usually ready in 24 hours）；值域未取得（91 §3.91 V）"
    add_column :locations, :pick_up_instructions, :text,
               comment: "本尊 Ready for pickup notification 的取貨指示；買家面出處未取得（91 §3.91 V）"
    add_column :files, :focal_point, :json,
               comment: "本尊 image.presentation.focal_point：{\"x\":0-100,\"y\":0-100}；NULL ⇒ 官方預設 50／50"
  end
end
