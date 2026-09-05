# frozen_string_literal: true

module Storefront
  # `content_for_header` 的動態結帳（本尊 portable-wallets）bootstrap 段（E18）。
  #
  # ①這是什麼：本尊每一頁的 head 注入都帶這一組（hoko.vip 2026-09-05 商品／集合／購物車／文章頁 HTML；external-facts §G26），
  #   依序：
  #     `<script data-source-attribution="shopify.dynamic_checkout.dynamic.init">`（定義 `Shopify.PaymentButton`＋`init()` 載模組）
  #     `<script data-source-attribution="shopify.dynamic_checkout.buyer_consent">`（`hideBuyerConsent`／`showBuyerConsent`）
  #     `<script>`（`portableWalletsCleanup`：模組載入失敗時拆骨架；`portableWalletsNotLoadedAsModule`）
  #     `<script type="module" src="{origin}/cdn/shopifycloud/portable-wallets/latest/portable-wallets.{lang}.js" onError="portableWalletsCleanup(this)" crossorigin="anonymous">`
  #     `<script nomodule>`（DOMContentLoaded ⇒ cleanup）
  #     …（本尊此處夾 privacy-banner script——歸 content_for_header 包）…
  #     `<link id="shopify-accelerated-checkout-styles" rel="stylesheet" media="screen" href="{origin}/cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css" crossorigin="anonymous">`
  #     `<style id="shopify-accelerated-checkout-cart">`（`#shopify-buyer-consent` 系列宣告）
  #   主題依賴的介面＝`Shopify.PaymentButton.init()`（Ella product-form.js 呼叫）、`portableWalletsCleanup` 名稱（onError 屬性引用）、
  #   `shopify-accelerated-checkout-styles` id（模組以此判斷樣式表已在頁上）。
  # ②怎麼做：script 本體我方自寫（鐵律 9），行為對位：`init()` 只載一次模組、模組 URL 依頁語言（本尊 `portable-wallets.en.js`／
  #   `zh-cn`／`zh-tw`／`fr`／`ja`＝`<html lang>` 小寫）。`RenderParity::Normalizer` 把這幾支內嵌 script 的本體視為替身（只比 tag／屬性）。
  # ③跨功能：`ThemeEngine::PageRenderer`（接在 SEO head 段之後）、`Storefront::AssetsController#portable_wallets`／
  #   `#accelerated_checkout_css`（模組與樣式表本體）、`ThemeEngine::Filters#payment_button`（骨架）、Ella `product-form.js`。
  module DynamicCheckoutHead
    module_function

    # @param origin [String] `https://host[:port]`
    # @param locale_tag [String] 我方語言 tag（`zh-Hans` ⇒ bundle `zh-cn`）
    # @return [String]
    def build(origin:, locale_tag:)
      lang = ThemeEngine::LocaleTags.shopify_code(locale_tag.presence || "en").downcase
      module_src = "#{origin}/cdn/shopifycloud/portable-wallets/latest/portable-wallets.#{lang}.js"
      css_href = "#{origin}/cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css"
      <<~HTML.chomp
        <script data-source-attribution="shopify.dynamic_checkout.dynamic.init">var Shopify=Shopify||{};Shopify.PaymentButton=Shopify.PaymentButton||{isStorefrontPortableWallets:!0,init:function(){window.Shopify.PaymentButton.init=function(){};var t=document.createElement("script");t.src=#{module_src.to_json},t.type="module",document.head.appendChild(t)}};
        </script>
        <script data-source-attribution="shopify.dynamic_checkout.buyer_consent">
          function portableWalletsHideBuyerConsent(e){var t=document.getElementById("shopify-buyer-consent"),n=document.getElementById("shopify-subscription-policy-button");t&&n&&(t.classList.add("hidden"),t.setAttribute("aria-hidden","true"),n.removeEventListener("click",e))}function portableWalletsShowBuyerConsent(e){var t=document.getElementById("shopify-buyer-consent"),n=document.getElementById("shopify-subscription-policy-button");t&&n&&(t.classList.remove("hidden"),t.removeAttribute("aria-hidden"),n.addEventListener("click",e))}window.Shopify?.PaymentButton&&(window.Shopify.PaymentButton.hideBuyerConsent=portableWalletsHideBuyerConsent,window.Shopify.PaymentButton.showBuyerConsent=portableWalletsShowBuyerConsent);
        </script>
        <script>
          function portableWalletsCleanup(e){e&&e.src&&console.error("Failed to load portable wallets script "+e.src);var t=document.querySelectorAll("shopify-accelerated-checkout .shopify-payment-button__skeleton, shopify-accelerated-checkout-cart .wallet-cart-button__skeleton"),n=document.getElementById("shopify-buyer-consent");for(var i=0;i<t.length;i++)t[i].remove();n&&n.remove()}function portableWalletsNotLoadedAsModule(e){e instanceof ErrorEvent&&typeof e.message=="string"&&e.message.includes("import.meta")&&typeof e.filename=="string"&&e.filename.includes("portable-wallets")&&(window.removeEventListener("error",portableWalletsNotLoadedAsModule),window.Shopify.PaymentButton.failedToLoad=e,document.readyState==="loading"?document.addEventListener("DOMContentLoaded",window.Shopify.PaymentButton.init):window.Shopify.PaymentButton.init())}window.addEventListener("error",portableWalletsNotLoadedAsModule);
        </script>
        <script type="module" src="#{ERB::Util.html_escape(module_src)}" onError="portableWalletsCleanup(this)" crossorigin="anonymous"></script>
        <script nomodule>
          document.addEventListener("DOMContentLoaded", portableWalletsCleanup);
        </script>
        <link id="shopify-accelerated-checkout-styles" rel="stylesheet" media="screen" href="#{ERB::Util.html_escape(css_href)}" crossorigin="anonymous">
        <style id="shopify-accelerated-checkout-cart">
                #shopify-buyer-consent {
          margin-top: 1em;
          display: inline-block;
          width: 100%;
        }

        #shopify-buyer-consent.hidden {
          display: none;
        }

        #shopify-subscription-policy-button {
          background: none;
          border: none;
          padding: 0;
          text-decoration: underline;
          font-size: inherit;
          cursor: pointer;
        }

        #shopify-subscription-policy-button::before {
          box-shadow: none;
        }

              </style>
      HTML
    end
  end
end
