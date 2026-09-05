# frozen_string_literal: true

module Storefront
  # 店面（買家面）存取權杖（E18；本尊 storefront access token 的對位）。
  #
  # ①這是什麼：本尊每家店有一個公開的 storefront access token（32 hex），出現在 `payment_button` 骨架的
  #   `access-token`、`shopify-features` JSON 的 `accessToken`，並由 portable-wallets 以
  #   `X-Shopify-Storefront-Access-Token` 標頭送回 `/api/unstable/graphql.json`（hoko.vip 2026-09-05 抓包，
  #   external-facts §G26）。它是**公開值**（隨 HTML 出去），只用來把請求綁到店，不是祕密。
  # ②怎麼做：由店 id 與 `secret_key_base` 以 HMAC-MD5 導出（32 hex，形同本尊）；同店恆同值、不落 DB、
  #   不可由店 id 直接猜出。日後若要支援可撤銷／多權杖（本尊 Headless channel），改成落表即可——
  #   呼叫端只透過 `.for`／`.valid?` 兩個入口。
  # ③跨功能：`ThemeEngine::Filters#payment_button`（骨架屬性）、`Storefront::ApiController`（驗標頭）、
  #   日後 `shopify-features` head 注入（content_for_header 包）。
  module AccessToken
    module_function

    # @param shop_id [Integer]
    # @return [String] 32 hex
    def for(shop_id)
      OpenSSL::HMAC.hexdigest("MD5", Rails.application.secret_key_base, "storefront-access-token:#{shop_id}")
    end

    # @return [Boolean] 常數時間比較
    def valid?(shop_id, token)
      candidate = token.to_s
      return false if candidate.empty?

      ActiveSupport::SecurityUtils.secure_compare(self.for(shop_id), candidate)
    end
  end
end
