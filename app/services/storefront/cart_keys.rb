# frozen_string_literal: true

module Storefront
  # Storefront API cart 的兩把「key」（E18；本尊 `cartCreate` 回應形，hoko.vip 2026-09-05 抓包，external-facts §G26）。
  #
  # ①這是什麼：本尊的 cart 全域 id 帶 32 hex 的 `?key=`（`gid://shopify/Cart/{token}?key=9491cba5…`），
  #   `checkoutUrl` 另帶一把 base64url、以 `%3D%3D` 收尾的長 key（`https://hoko.vip/cart/c/{token}?key=AwE28R6E…-Q%3D%3D`）。
  #   兩者都是「拿 token 不夠、還要拿得出 key」的持有證明——cart token 會隨 URL 外流，key 擋住只知 token 的人。
  # ②怎麼做：兩把都由 `secret_key_base` 對 cart token 做 HMAC 導出（不落表）：id key＝HMAC-SHA256 取前 32 hex；
  #   checkout key＝HMAC-SHA512 的 base64url（含 `=` padding ⇒ URL 編碼後 `%3D%3D`，形同本尊；長度 88 vs 本尊約 120——
  #   本尊 key 的實際位元組數未取得，登記 91 §3.87）。驗證用常數時間比較。
  # ③跨功能：`Storefront::ApiController#cart_create`（產出）、`Storefront::CartController#checkout_link`（驗證）、
  #   `Storefront::CartSerializer`（日後 Ajax `cart.js` 不帶這兩把——Ajax 契約無 key）。
  module CartKeys
    module_function

    # @return [String] 32 hex（cart 全域 id 的 `?key=`）
    def id_key(token)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "cart-id-key:#{token}")[0, 32]
    end

    # @return [String] base64url（含 padding；放進 URL 前再 CGI.escape ⇒ `%3D%3D` 收尾）
    def checkout_key(token)
      Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA512", Rails.application.secret_key_base, "cart-checkout-key:#{token}"))
    end

    # @return [Boolean]
    def checkout_key_valid?(token, key)
      candidate = key.to_s
      return false if candidate.empty?

      ActiveSupport::SecurityUtils.secure_compare(checkout_key(token), candidate)
    end
  end
end
