# frozen_string_literal: true

module Storefront
  # `content_for_header` 的動態結帳（本尊 portable-wallets）bootstrap 段（E18；E19 起由 `Storefront::ContentForHeader` 依頁型呼叫）。
  #
  # ①這是什麼：本尊每一頁的 head 注入都帶（hoko.vip 2026-09-05；external-facts §G26／§G27），依序：
  #     `<script data-source-attribution="shopify.dynamic_checkout.dynamic.init">`（定義 `Shopify.PaymentButton`＋`init()` 載模組）
  #     `<script data-source-attribution="shopify.dynamic_checkout.buyer_consent">`（`hideBuyerConsent`／`showBuyerConsent`）
  #     **模組形（本頁渲染了 `payment_button`）**：`<script>`（`portableWalletsCleanup`／`portableWalletsNotLoadedAsModule`）
  #       → `<script type="module" src="{origin}/cdn/shopifycloud/portable-wallets/latest/portable-wallets.{lang}.js" onError="portableWalletsCleanup(this)" crossorigin="anonymous">`
  #       → `<script nomodule>`；之後（privacy banner 之後）`<link id="shopify-accelerated-checkout-styles">` ＋ `<style id="shopify-accelerated-checkout-cart">`（`styles`）
  #     **cart.bootstrap 形（其餘頁）**：`<script data-source-attribution="shopify.dynamic_checkout.cart.bootstrap">`（DOMContentLoaded 時頁上若有
  #       `shopify-accelerated-checkout-cart, shopify-accelerated-checkout` 就 `Shopify.PaymentButton.init()`，否則 MutationObserver 等它出現）
  #   主題依賴的介面＝`Shopify.PaymentButton.init()`（Ella product-form.js 呼叫）、`portableWalletsCleanup` 名稱（onError 屬性引用）、
  #   `shopify-accelerated-checkout-styles` id（模組以此判斷樣式表已在頁上）。
  # ②怎麼做：script 本體我方自寫（鐵律 9），行為對位：`init()` 只載一次模組、模組 URL 依頁語言（本尊 `portable-wallets.en.js`／
  #   `zh-cn`／`zh-tw`／`fr`／`ja`＝`<html lang>` 小寫）。`RenderParity::Normalizer` 把這幾支內嵌 script 的本體視為替身（只比 tag／屬性）。
  # ③跨功能：`Storefront::ContentForHeader`（節點序與頁型判準）、`Storefront::AssetsController#portable_wallets`／
  #   `#accelerated_checkout_css`（模組與樣式表本體）、`ThemeEngine::Filters#payment_button`（骨架＋渲染旗標）、Ella `product-form.js`。
  module DynamicCheckoutHead
    module_function

    # @param origin [String] `https://host[:port]`
    # @param locale_tag [String] 我方語言 tag（`zh-Hans` ⇒ bundle `zh-cn`）
    # @param variant [Symbol] `:module`（本頁有 payment_button）／`:cart_bootstrap`
    # @return [String]
    def build(origin:, locale_tag:, variant: :module)
      lang = ThemeEngine::LocaleTags.shopify_code(locale_tag.presence || "en").downcase
      module_src = "#{origin}/cdn/shopifycloud/portable-wallets/latest/portable-wallets.#{lang}.js"
      parts = [ init_script(module_src), buyer_consent_script ]
      if variant == :module
        cleanup, tag, nomodule = module_scripts(module_src)
        parts.concat([ cleanup, "\n" + tag, nomodule ]) # hoko 位元組：module 標籤前空一行（T13 空白骨架對表）
      else
        parts << cart_bootstrap_script
      end
      parts.join("\n")
    end

    # 商品頁（模組形）在 privacy banner 之後的兩個樣式節點
    def styles(origin:)
      css_href = "#{origin}/cdn/shopifycloud/portable-wallets/latest/accelerated-checkout-backwards-compat.css"
      <<~HTML.chomp
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

    def init_script(module_src)
      %(<script data-source-attribution="shopify.dynamic_checkout.dynamic.init">var Shopify=Shopify||{};Shopify.PaymentButton=Shopify.PaymentButton||{isStorefrontPortableWallets:!0,init:function(){window.Shopify.PaymentButton.init=function(){};var t=document.createElement("script");t.src=#{module_src.to_json},t.type="module",document.head.appendChild(t)}};\n</script>)
    end

    def buyer_consent_script
      <<~HTML.chomp
        <script data-source-attribution="shopify.dynamic_checkout.buyer_consent">
          function portableWalletsHideBuyerConsent(e){var t=document.getElementById("shopify-buyer-consent"),n=document.getElementById("shopify-subscription-policy-button");t&&n&&(t.classList.add("hidden"),t.setAttribute("aria-hidden","true"),n.removeEventListener("click",e))}function portableWalletsShowBuyerConsent(e){var t=document.getElementById("shopify-buyer-consent"),n=document.getElementById("shopify-subscription-policy-button");t&&n&&(t.classList.remove("hidden"),t.removeAttribute("aria-hidden"),n.addEventListener("click",e))}window.Shopify?.PaymentButton&&(window.Shopify.PaymentButton.hideBuyerConsent=portableWalletsHideBuyerConsent,window.Shopify.PaymentButton.showBuyerConsent=portableWalletsShowBuyerConsent);
        </script>
      HTML
    end

    def module_scripts(module_src)
      [ <<~HTML.chomp,
        <script>
          function portableWalletsCleanup(e){e&&e.src&&console.error("Failed to load portable wallets script "+e.src);var t=document.querySelectorAll("shopify-accelerated-checkout .shopify-payment-button__skeleton, shopify-accelerated-checkout-cart .wallet-cart-button__skeleton"),n=document.getElementById("shopify-buyer-consent");for(var i=0;i<t.length;i++)t[i].remove();n&&n.remove()}function portableWalletsNotLoadedAsModule(e){e instanceof ErrorEvent&&typeof e.message=="string"&&e.message.includes("import.meta")&&typeof e.filename=="string"&&e.filename.includes("portable-wallets")&&(window.removeEventListener("error",portableWalletsNotLoadedAsModule),window.Shopify.PaymentButton.failedToLoad=e,document.readyState==="loading"?document.addEventListener("DOMContentLoaded",window.Shopify.PaymentButton.init):window.Shopify.PaymentButton.init())}window.addEventListener("error",portableWalletsNotLoadedAsModule);
        </script>
      HTML
        %(<script type="module" src="#{ERB::Util.html_escape(module_src)}" onError="portableWalletsCleanup(this)" crossorigin="anonymous"></script>),
        "<script nomodule>\n  document.addEventListener(\"DOMContentLoaded\", portableWalletsCleanup);\n</script>" ]
    end

    # 非商品頁：等 `shopify-accelerated-checkout(-cart)` 出現才載模組（本尊 cart.bootstrap 語義，本體我方自寫）
    def cart_bootstrap_script
      %(<script data-source-attribution="shopify.dynamic_checkout.cart.bootstrap">document.addEventListener("DOMContentLoaded",function(){function t(){return document.querySelector("shopify-accelerated-checkout-cart, shopify-accelerated-checkout")}if(t())Shopify.PaymentButton.init();else{new MutationObserver(function(e,n){t()&&(Shopify.PaymentButton.init(),n.disconnect())}).observe(document.body,{childList:!0,subtree:!0})}});</script>)
    end
  end
end
