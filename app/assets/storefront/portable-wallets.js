// 動態結帳模組（本尊 `portable-wallets.{lang}.js` 的對位；E18，docs/dev/e18-dynamic-checkout.md）。
//
// ①這是什麼：`{{ form | payment_button }}` 出的 `<shopify-accelerated-checkout>` 骨架，由本模組升級成本尊 JS 後的光 DOM
//   （hoko.vip 2026-09-05 商品頁實測，external-facts §G26）：
//     <shopify-accelerated-checkout … requires-shipping="">          ← 升級後拆 `disabled`、依 variant-params 補 requires-shipping
//       <shopify-buy-it-now-button access-token buyer-country buyer-currency wallet-params="{}" page-type="product" slot="button" requires-shipping="" call-to-action="">
//         <button type="button" class="shopify-payment-button__button shopify-payment-button__button--unbranded">{立即購買}</button>
//   骨架子節點（`.shopify-payment-button__button[role=button]` ＋ skeleton）移除；兩個自訂元素各掛 closed shadow root（本尊同形，
//   官方句 "hide their HTML in a custom element with a closed shadow DOM"）；按鈕在光 DOM（slot），主題 CSS 直接命中。
// ②按下：本尊不動買家購物車，改以 Storefront API `cartCreate` 另建 cart（POST `/api/unstable/graphql.json?operation_name=cartCreate`，
//   標頭 X-Shopify-Storefront-Access-Token／X-SDK-Variant: portable-wallets／X-Wallet-Name: BuyItNow／X-Start-Wallet-Checkout: true），
//   再 `location.assign(cart.checkoutUrl)`（`/cart/c/{token}?key=…` ⇒ 302 結帳頁）。help.shopify.com dynamic-checkout 官方句：
//   "When a customer clicks an unbranded button, they skip the cart and go to the Shopify Checkout."
// ③樣式回溯（本尊 style backwards compatibility）：讀主題 CSS 對舊選擇器（`.shopify-payment-button__button` 等）宣告的
//   height／min-height／border-radius／margin-top，換算成 `--shopify-accelerated-checkout-*` 自訂屬性，寫進
//   `<style id="global-shopify-accelerated-checkout-styles">`（append 至 head）。演算法依本尊 bundle 逐步對位（Ta 特異度、
//   反序＋穩定排序、`!important` 優先、`var(--…-block-size` 與 `auto` 排除、既有自訂屬性跳過、box-shadow 取
//   `.product-form__buttons .button::before` 的 computed）。Ella 實測輸出 `--…-button-block-size: 5rem; --…-button-box-shadow: none;`。
// ④跨功能：`Storefront::DynamicCheckoutHead`（head bootstrap：`Shopify.PaymentButton.init()` 載本檔）、`Storefront::ApiController`
//   （cartCreate）、`Storefront::CartController#checkout_link`、`accelerated-checkout-backwards-compat.css`（光 DOM 樣式）、
//   Ella `product-form.js`（agree-condition 時對 `.shopify-payment-button` 加 `disabled` class——主題自己的行為）。
// 🔴 本檔為我方自寫（鐵律 9：不抄本尊 JS）；與本尊同形的只有主題會依賴的介面：tag／id／class／屬性名／全域 API 名。
(() => {
  "use strict";
  const BUY_NOW = __BUY_NOW_LABEL__;
  const MODULE_URL = import.meta.url;
  const STYLE_ID = "shopify-accelerated-checkout-styles";
  const K = {
    buttonBlockSize: "--shopify-accelerated-checkout-button-block-size",
    buttonBorderRadius: "--shopify-accelerated-checkout-button-border-radius",
    buttonBoxShadow: "--shopify-accelerated-checkout-button-box-shadow",
    inlineAlignment: "--shopify-accelerated-checkout-inline-alignment"
  };
  // 本尊 portable-wallets 送出的 query（抓包逐字；我方 ApiController 只認 operation_name＋`cartCreate(`，query 原文照送）
  const CART_CREATE_QUERY =
    "mutation cartCreate($input:CartInput!$country:CountryCode$language:LanguageCode)@inContext(country:$country language:$language){result:cartCreate(input:$input){cart{...CartParts}errors:userErrors{...on CartUserError{message field code}}warnings:warnings{...on CartWarning{code}}}}" +
    "fragment CartParts on Cart{id checkoutUrl deliveryGroups(first:10){edges{node{id groupType selectedDeliveryOption{code title handle deliveryPromise deliveryMethodType estimatedCost{amount currencyCode}}deliveryOptions{code title handle deliveryPromise deliveryMethodType estimatedCost{amount currencyCode}}}}}cost{subtotalAmount{amount currencyCode}totalAmount{amount currencyCode}totalTaxAmount{amount currencyCode}totalDutyAmount{amount currencyCode}}discountAllocations{discountedAmount{amount currencyCode}...on CartCodeDiscountAllocation{code}...on CartAutomaticDiscountAllocation{title}...on CartCustomDiscountAllocation{title}}discountCodes{code applicable}lines(first:10){edges{node{...on CartLine{parentRelationship{parent{id}}}quantity cost{subtotalAmount{amount currencyCode}totalAmount{amount currencyCode}}discountAllocations{discountedAmount{amount currencyCode}...on CartCodeDiscountAllocation{code}...on CartAutomaticDiscountAllocation{title}...on CartCustomDiscountAllocation{title}}merchandise{...on ProductVariant{requiresShipping title product{title}}}sellingPlanAllocation{remainingBalanceChargeAmount{amount}priceAdjustments{price{amount currencyCode}}sellingPlan{billingPolicy{...on SellingPlanRecurringBillingPolicy{interval intervalCount}}priceAdjustments{orderCount}recurringDeliveries}}}}}}";

  // ── 樣式表確保（本尊：頁上已有 `style#…`／`link#…` 就不再插） ────────────────────────────────────
  function ensureStyles() {
    if (document.querySelector("style#" + STYLE_ID) || document.querySelector("link#" + STYLE_ID)) return;
    const link = document.createElement("link");
    link.id = STYLE_ID;
    link.rel = "stylesheet";
    link.media = "screen";
    link.href = MODULE_URL.replace(/portable-wallets\.[a-z-]+\.js.*$/, "accelerated-checkout-backwards-compat.css");
    link.crossOrigin = "anonymous";
    document.head.insertBefore(link, document.head.firstChild);
  }

  // ── 樣式回溯（本尊 Io／xa／La／Oa／ip／op／Ma／ko 逐步對位） ───────────────────────────────────────
  const PRODUCT_SELECTORS = [
    /(?!.*\.shopify-cleanslate)\.shopify-payment-button__button(?:--branded)?(?![\w-:.#>])/,
    /\.(shopify-payment-button|shopify-payment-button__button|shopify-payment-button__button--branded)\s*\[role="?button"?\](?![:\w-])/,
    /.dynamic-checkout-buttons .shopify-payment-button__button/
  ];
  const CART_SELECTORS = [
    /\.cart__dynamic-checkout-buttons|\.dynamic-checkout-buttons\s*\[role="?button"?\](?![:\w-])/,
    /\[data-shopify-buttoncontainer\](?![:\w-])/,
    /\.cart__dynamic-checkout-buttons|\.dynamic-checkout-buttons\s*(>\s*)?li(?![a-zA-Z0-9_.:#-])/,
    /\.additional-checkout-buttons\s*(?:div\s*)?\[role="?button"?\](?![:\w-])/,
    /.dynamic-checkout-buttons .shopify-payment-button__button/
  ];
  const BUTTON_CONTAINER_RE = /\[data-shopify-buttoncontainer\](?![:\w-])/;
  const MEDIA_RE = /(?:only\s+)?(?:screen\s+and\s+)?\((?:min|max)-(?:width|height):\s*\d+px\)/;
  const PROPS = [["height"], ["minHeight", "min-height"], ["borderRadius", "border-radius"], ["marginTop", "margin-top"], ["justifyContent", "justify-content"]];

  function specificity(selector) {
    let ids = 0, classes = 0, elements = 0;
    for (const part of selector.split(/\s+/)) {
      if (part === ">") continue;
      if (part.includes("#")) ids += (part.match(/#/g) || []).length;
      if (part.includes(".")) classes += (part.match(/\./g) || []).length;
      if (part.includes("[")) classes += (part.match(/\[/g) || []).length;
      if (part.includes(":")) classes += (part.match(/:[^:]/g) || []).length;
      if (/^[A-Za-z]/.test(part)) elements += 1;
    }
    return [ids, classes, elements];
  }
  function bySpecificityDesc(rules) {
    return [...rules].sort((a, b) => {
      const sa = specificity(a.selector), sb = specificity(b.selector);
      for (let i = 0; i < 3; i++) if (sa[i] !== sb[i]) return sb[i] - sa[i];
      return 0;
    });
  }
  function readableSheet(sheet) {
    const node = sheet.ownerNode;
    const anonymous = node instanceof HTMLLinkElement && (node.getAttribute("crossorigin") === "anonymous" || node.getAttribute("crossorigin") === "");
    return sheet.href == null || sheet.href.startsWith(window.location.origin) || anonymous;
  }
  function ruleProps(rule) {
    const out = {};
    for (const [key, cssName] of PROPS) {
      const value = rule.style.getPropertyValue(cssName || key);
      out[key] = value !== "" && rule.style.getPropertyPriority(cssName || key) ? value + " !important" : (value || null);
    }
    return out;
  }
  function pick(rule, prop, current) {
    const value = rule[prop];
    return !(current || "").includes("!important") && (value || "").includes("!important") ? value : (current ?? value);
  }
  function blockSize(height, minHeight) {
    let h = height, m = minHeight;
    if ((h || "").includes("var(" + K.buttonBlockSize) || h === "auto") h = null;
    if ((m || "").includes("var(" + K.buttonBlockSize) || m === "auto") m = null;
    if (h === m) return h;
    return m && h ? "max(" + h + "," + m + ")" : (h || m);
  }
  function cssBlock({ mediaCondition, selector, styles, existing }) {
    const out = { ...styles };
    existing.forEach((prop) => { delete out[prop]; });
    for (const [prop, value] of Object.entries(out)) if ((value || "").startsWith("var(" + prop)) delete out[prop];
    for (const [prop, value] of Object.entries(out)) if (value == null || value === "") delete out[prop];
    if (Object.keys(out).length === 0) return "";
    let text = (mediaCondition ? "@media " + mediaCondition + " { " : "") + selector + " {";
    for (const [prop, value] of Object.entries(out)) text += "\n  " + prop + ": " + value + ";";
    text += "\n}" + (mediaCondition ? " }" : "");
    return text;
  }
  function extractStyles(element, pageType) {
    const isCart = pageType === "cart";
    const selectors = isCart ? CART_SELECTORS : PRODUCT_SELECTORS;
    const sheets = document.styleSheets;
    if (typeof sheets?.[Symbol.iterator] !== "function") return "";
    const matches = (selector) => selectors.some((re) => re.test(selector));
    const plain = [], media = [];
    for (const sheet of [...sheets].filter(readableSheet)) {
      try {
        for (const rule of sheet.cssRules) {
          if (rule instanceof CSSMediaRule) {
            if (!MEDIA_RE.test(rule.conditionText)) continue;
            for (const inner of rule.cssRules) {
              if (!(inner instanceof CSSStyleRule)) continue;
              for (const selector of inner.selectorText.split(",").map((s) => s.trim())) {
                if (matches(selector)) media.push({ selector, conditionText: rule.conditionText, ...ruleProps(inner) });
              }
            }
          } else if (rule instanceof CSSStyleRule) {
            for (const selector of rule.selectorText.split(",").map((s) => s.trim())) {
              if (matches(selector)) plain.push({ selector, ...ruleProps(rule) });
            }
          }
        }
      } catch (_e) { /* 跨來源樣式表不可讀：與本尊同樣略過 */ }
    }
    const ranked = bySpecificityDesc(plain.reverse()), rankedMedia = bySpecificityDesc(media.reverse());
    const acc = {};
    const reference = document.querySelector(isCart ? ".cart__blocks .button" : ".product-form__buttons .button");
    if (reference) acc.boxShadow = getComputedStyle(reference, ":before").boxShadow;
    for (const rule of ranked) {
      const props = ["height", "minHeight", "borderRadius", "marginTop"];
      if (isCart && BUTTON_CONTAINER_RE.test(rule.selector)) props.push("justifyContent");
      for (const prop of props) acc[prop] = pick(rule, prop, acc[prop]);
    }
    const tag = element.tagName.toLowerCase(), computed = getComputedStyle(element), existing = new Set();
    for (const prop of Object.values(K)) if (computed.getPropertyValue(prop)) existing.add(prop);
    const toStyles = (r) => (isCart
      ? { [K.buttonBorderRadius]: r.borderRadius, [K.buttonBoxShadow]: r.boxShadow, [K.inlineAlignment]: r.justifyContent }
      : { [K.buttonBlockSize]: blockSize(r.height, r.minHeight), [K.buttonBorderRadius]: r.borderRadius, [K.buttonBoxShadow]: r.boxShadow,
          "margin-top": r.marginTop, display: r.marginTop ? "block" : undefined });
    let text = cssBlock({ selector: tag, styles: toStyles(acc), existing });
    for (const rule of rankedMedia) {
      if (!(rule.height || rule.minHeight || rule.borderRadius || rule.boxShadow || rule.justifyContent || rule.marginTop)) continue;
      text += cssBlock({ mediaCondition: rule.conditionText, selector: tag, styles: toStyles(rule), existing });
    }
    return text.trim();
  }
  function writeGlobalStyles(element, pageType) {
    const styles = extractStyles(element, pageType);
    if (!styles) return;
    const id = "global-" + element.tagName.toLowerCase() + "-styles";
    if (document.head.querySelector("style#" + id) != null) return;
    const style = document.createElement("style");
    style.id = id;
    style.innerHTML = styles;
    document.head.appendChild(style);
  }

  // ── 表單讀取（本尊 productFormData 對位：id／quantity／properties[…]／selling_plan） ────────────────────
  function formValue(form, name) {
    const field = form?.elements?.namedItem(name);
    if (!field) return null;
    if (field instanceof RadioNodeList) return field.value;
    return field.value;
  }
  function formLines(form) {
    const variantId = formValue(form, "id");
    if (!variantId) return null;
    const attributes = [];
    for (const field of form.elements) {
      const m = field.name && field.name.match(/^properties\[(.+)\]$/);
      if (!m || field.disabled) continue;
      if ((field.type === "checkbox" || field.type === "radio") && !field.checked) continue;
      attributes.push({ key: m[1], value: field.value });
    }
    const line = { merchandiseId: "gid://chilllove/ProductVariant/" + variantId, quantity: Number(formValue(form, "quantity") ?? "1") || 1, attributes };
    const plan = formValue(form, "selling_plan");
    if (plan) line.sellingPlanId = "gid://chilllove/SellingPlan/" + plan;
    return [line];
  }

  // ── 立即購買：cartCreate ⇒ checkoutUrl ─────────────────────────────────────────────────────────
  async function buyItNow(container) {
    const form = container.closest("form");
    const lines = form && formLines(form);
    if (!lines) { console.error("[shopify-buy-it-now-button] Missing variant ID in product form"); return; }
    const language = (container.getAttribute("buyer-locale") || "en").replace("-", "_").toUpperCase();
    const body = JSON.stringify({ query: CART_CREATE_QUERY, variables: { input: { lines, discountCodes: [] }, country: container.getAttribute("buyer-country"), language } });
    const response = await fetch("/api/unstable/graphql.json?operation_name=cartCreate", {
      method: "POST", credentials: "same-origin", body,
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-Shopify-Storefront-Access-Token": container.getAttribute("access-token") || "",
                 "X-SDK-Variant": "portable-wallets", "X-Wallet-Name": "BuyItNow", "X-Start-Wallet-Checkout": "true" }
    });
    const json = await response.json().catch(() => null);
    const result = json?.data?.result;
    if (!response.ok || !result?.cart?.checkoutUrl) {
      console.error("[BuyItNow] Failed to create cart: " + JSON.stringify(result?.errors ?? json?.errors ?? response.status));
      return;
    }
    window.location.assign(result.cart.checkoutUrl);
  }

  // ── 自訂元素 ─────────────────────────────────────────────────────────────────────────────────
  class BuyItNowButton extends HTMLElement {
    static get observedAttributes() { return ["disabled"]; }
    #root; #button; #busy = false;
    connectedCallback() {
      if (this.#button) return;
      this.#root = this.attachShadow({ mode: "closed" });
      this.#root.appendChild(document.createElement("slot"));
      const button = document.createElement("button");
      button.type = "button";
      button.className = "shopify-payment-button__button shopify-payment-button__button--unbranded";
      button.textContent = BUY_NOW;
      button.addEventListener("click", () => this.#onClick());
      this.#button = button;
      this.appendChild(button);
      this.attributeChangedCallback("disabled", null, this.getAttribute("disabled"));
    }
    attributeChangedCallback(name, oldValue, newValue) {
      if (name !== "disabled" || !this.#button || oldValue === newValue) return;
      if (newValue === "" || newValue === "true") { this.#button.setAttribute("aria-disabled", "true"); this.#button.setAttribute("disabled", ""); }
      else { this.#button.removeAttribute("aria-disabled"); this.#button.removeAttribute("disabled"); }
    }
    async #onClick() {
      if (this.#busy || this.hasAttribute("disabled")) return;
      this.#busy = true;
      try { await buyItNow(this.closest("shopify-accelerated-checkout") || this); } finally { this.#busy = false; }
    }
  }

  let instanceCount = 0;
  class AcceleratedCheckout extends HTMLElement {
    static get observedAttributes() { return ["disabled"]; }
    #root; #child; #observer; #form; #rendered = false;
    connectedCallback() {
      if (this.#rendered) return;
      this.#rendered = true;
      const instance = ++instanceCount;
      ensureStyles();
      if (instance === 1) writeGlobalStyles(this, "product");
      this.#root = this.attachShadow({ mode: "closed" });
      const slot = document.createElement("slot");
      slot.name = "button";
      this.#root.appendChild(slot);
      this.#form = this.closest("form");
      this.#syncFromForm();
      // 骨架子節點（本尊升級後只剩 <shopify-buy-it-now-button>）
      for (const node of [...this.children]) node.remove();
      const child = document.createElement("shopify-buy-it-now-button");
      const attrs = [["access-token", this.getAttribute("access-token") || ""], ["buyer-country", this.getAttribute("buyer-country") || ""],
                     ["buyer-currency", this.getAttribute("buyer-currency") || ""], ["wallet-params", "{}"], ["page-type", "product"], ["slot", "button"]];
      for (const [name, value] of attrs) child.setAttribute(name, value);
      if (this.hasAttribute("disabled")) child.setAttribute("disabled", "");
      if (this.hasAttribute("requires-shipping")) child.setAttribute("requires-shipping", "");
      if (this.hasAttribute("has-selling-plan")) child.setAttribute("has-selling-plan", "");
      child.setAttribute("call-to-action", "");
      this.#child = child;
      this.appendChild(child);
      if (this.#form) {
        // 🔴 只理會表單裡「我方元素以外」的變動：自己 set/remove 屬性也會產生 mutation record，不過濾＝無窮迴圈（頁面 load 事件永不觸發）
        this.#observer = new MutationObserver((records) => {
          if (records.some((r) => !(r.target === this || this.contains(r.target)))) this.#syncFromForm();
        });
        this.#observer.observe(this.#form, { attributes: true, subtree: true, childList: true, attributeFilter: ["disabled", "aria-disabled", "value"] });
        this.#form.addEventListener("change", () => this.#syncFromForm());
      }
    }
    // 屬性只在狀態真的改變時才寫（同值重寫也會觸發 MutationObserver）
    #flag(name, on) {
      if (on && !this.hasAttribute(name)) this.setAttribute(name, "");
      else if (!on && this.hasAttribute(name)) this.removeAttribute(name);
    }
    disconnectedCallback() { this.#observer?.disconnect(); this.#observer = undefined; }
    attributeChangedCallback(name, oldValue, newValue) {
      if (name === "disabled" && this.#child && oldValue !== newValue) {
        if (newValue === "" || newValue === "true") this.#child.setAttribute("disabled", ""); else this.#child.removeAttribute("disabled");
      }
    }
    get variantParams() {
      try { return JSON.parse(this.getAttribute("variant-params") || "[]"); } catch (_e) { return []; }
    }
    // 本尊 formObserver：表單的 submit 狀態 ⇒ disabled；選中變體 ⇒ requires-shipping（variant-params 查表）
    #syncFromForm() {
      const form = this.#form;
      const submit = form?.querySelector('button[name="add"], .product-form__submit');
      const disabled = !!submit && (submit.disabled || submit.getAttribute("aria-disabled") === "true");
      this.#flag("disabled", disabled);
      const variantId = Number(formValue(form, "id"));
      const params = this.variantParams;
      const selected = params.find((v) => v.id === variantId) || params[0];
      this.#flag("requires-shipping", !!selected?.requiresShipping);
      this.#flag("has-selling-plan", !!formValue(form, "selling_plan"));
    }
  }

  // 購物車面（`content_for_additional_checkout_buttons`）：我方無第三方錢包 ⇒ 只拆骨架（本尊無錢包時同樣不出按鈕；購物車包再對表）
  class AcceleratedCheckoutCart extends HTMLElement {
    connectedCallback() { for (const node of this.querySelectorAll(".wallet-cart-button__skeleton")) node.remove(); }
  }

  function define(tag, klass) {
    if (window.customElements == null) return false;
    try { if (!window.customElements.get(tag)) window.customElements.define(tag, klass); return true; } catch (e) { console.error(e); return false; }
  }
  define("shopify-buy-it-now-button", BuyItNowButton);
  define("shopify-accelerated-checkout", AcceleratedCheckout);
  define("shopify-accelerated-checkout-cart", AcceleratedCheckoutCart);
})();
