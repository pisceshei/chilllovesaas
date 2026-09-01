# frozen_string_literal: true

module Storefront
  # 買家面媒體服務（Ella 修復 PR-2；根因 A＝ImageDrop#url 恆 nil、買家面無任何
  # 媒體端點 ⇒ 真圖鏈輸出端斷裂）。
  # ①查找憑 shop_id＋id（租戶隔離天然成立）；filename 段不參與查找。
  # ②Cache-Control public 1 天（檔案可被同 id 換內容的形態未定案前不設 immutable）。
  class MediaController < BaseController
    def show
      file = StoredFile.find_by(shop_id: current_shop.id, id: params[:id])
      return head :not_found if file.nil? || file.status == "failed"

      body = Storage::LocalDisk.read(file.storage_key)
      expires_in 1.day, public: true
      send_data body, type: file.content_type.presence ||
                            Marcel::MimeType.for(name: file.filename.to_s),
                      disposition: "inline"
    rescue Errno::ENOENT, Storage::LocalDisk::InvalidKey
      head :not_found
    end
  end
end
