# frozen_string_literal: true

module Storefront
  # 301／410 查表引擎（包 36；62 §B.5；14 §F5-3「掛在 404/410 handler 之前」）。
  #
  # 🔴 查表用**無前綴正規路徑**（表註釋既定；引擎在剝前綴後呼叫，命中後由呼叫端
  #   把前綴加回去——limits `handle.redirect_preserves_locale_prefix`：
  #   /en/products/舊 ⇒ /en/products/新，不得丟回預設語言）。
  # 🔴 只在 404 之後諮詢（呼叫點契約）：活頁面永遠先贏 ⇒ redirect 列不可能遮蔽
  #   現任資源，manual 建立時也因此不需跨表活性檢查（UrlRedirectCreate 檔頭同記）。
  # 鏈：handle_change 列由鏈坍縮不變量保證單跳；manual 列可能成鏈 ⇒ 這裡跟鏈
  #   至 `seo.redirect_max_chain`（10），環或超限 ⇒ 停在最後一跳（fail-open 到
  #   已知最遠目標，不 500——Google 自己也只跟 10 跳）。
  module RedirectResolver
    Hit = Data.define(:status_code, :to_path)

    module_function

    # @param shop [Shop]
    # @param path [String] 無前綴正規路徑
    # @return [Hit, nil]
    def resolve(shop:, path:)
      max = Limits.fetch(:seo, :redirect_max_chain)
      seen = Set.new
      current = path.to_s
      hit = nil
      while seen.size < max
        row = UrlRedirect.where(shop_id: shop.id, from_path: current).pick(:status_code, :to_path)
        break if row.nil?

        status, target = row
        return Hit.new(status_code: 410, to_path: nil) if status == 410
        break if seen.include?(target) # 環：停在已知最遠目標

        seen << current
        hit = Hit.new(status_code: status, to_path: target)
        current = target
      end
      hit
    end
  end
end
