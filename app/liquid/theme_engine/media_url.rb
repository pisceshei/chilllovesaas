# frozen_string_literal: true

module ThemeEngine
  # 買家面媒體 URL（Ella 修復 PR-2）。本尊走 CDN（cdn.shopify.com）；我方 v1
  # ＝租戶 host 相對路徑 `/media/{id}/{filename}`（ours，登記於 worklog）。
  # filename 只作可讀性／副檔名——查找一律憑 id＋shop_id（媒體端點）。
  module MediaUrl
    module_function

    def for(stored_file)
      return nil if stored_file.nil?

      "/media/#{stored_file.id}/#{ERB::Util.url_encode(stored_file.filename.to_s)}"
    end
  end
end
