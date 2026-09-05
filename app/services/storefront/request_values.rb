# frozen_string_literal: true

module Storefront
  # content_for_header 的每請求值（E19）：頁快取存 placeholder，送出前代入；analytics cookie 與本尊同名同期
  # （§G27：`_shopify_y` 1 年、`_shopify_s` 30 分鐘、SameSite=Lax；meta `shopify-y`／`shopify-s` 的 content＝同 uuid、
  # `data-expiration`＝過期 ms）。🔴 cookie **不設 domain**（host-only）：共用主網域上設 domain＝跨店共享（F1 坑）。
  # `__st.reqid`＝`{uuid}-{epoch 秒}`、`__st.u`＝12 hex（每請求隨機；本尊語義未取得，91 V）、trekkie `eventMetadataId`＝uuid。
  module RequestValues
    Y_TTL = 1.year
    S_TTL = 30.minutes

    module_function

    # @param html [String] 含 placeholder 的整頁 HTML
    # @param cookies [ActionDispatch::Cookies::CookieJar]
    # @return [String]
    def substitute(html, cookies:)
      return html unless html.include?("__CL_")

      now = Time.now
      y = cookies["_shopify_y"].presence || SecureRandom.uuid
      s = cookies["_shopify_s"].presence || SecureRandom.uuid
      cookies["_shopify_y"] = { value: y, expires: now + Y_TTL, path: "/", same_site: :lax } unless cookies["_shopify_y"].present?
      cookies["_shopify_s"] = { value: s, expires: now + S_TTL, path: "/", same_site: :lax }
      values = { ContentForHeader::PLACEHOLDER[:reqid] => "#{SecureRandom.uuid}-#{now.to_i}",
                 ContentForHeader::PLACEHOLDER[:u] => SecureRandom.hex(6),
                 ContentForHeader::PLACEHOLDER[:y] => y, ContentForHeader::PLACEHOLDER[:y_exp] => ((now + Y_TTL).to_f * 1000).to_i.to_s,
                 ContentForHeader::PLACEHOLDER[:s] => s, ContentForHeader::PLACEHOLDER[:s_exp] => ((now + S_TTL).to_f * 1000).to_i.to_s,
                 ContentForHeader::PLACEHOLDER[:evmeta] => SecureRandom.uuid }
      html.gsub(/__CL_(?:REQID|U|Y|Y_EXP|S|S_EXP|EVMETA)__/) { |m| values.fetch(m, m) }
    end
  end
end
