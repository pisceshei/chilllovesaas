# E18 動態結帳按鈕（portable-wallets）逐字對位——骨架、升級後光 DOM、head bootstrap、cartCreate 與結帳連結

> 路線圖 T4（`docs/plans/2026-09-05-全對齊路線圖.md` §2）。取證全文＝`docs/dev/external-facts.md` §G26（hoko.vip 2026-09-05，headless Chrome＋curl）；
> 未取得／範圍外＝`docs/specs/91-pit-register.md` §3.87。worklog／handoff＝`docs/worklog/2026-09-05-動態結帳按鈕E18.md`、
> `docs/handoff/2026-09-05-動態結帳按鈕E18.md`。鐵律 9：本包所有平台 JS／CSS 本體皆我方自寫，只有主題會依賴的介面（tag／id／class／屬性名／全域 API 名）同形。

## 1. 這是什麼（本尊行為）

商品表單裡 `{{ form | payment_button }}` 出「立即購買」動態結帳按鈕（官方：unbranded accelerated checkout button；"When a customer clicks an unbranded
button, they skip the cart and go to the Shopify Checkout."）。本尊分四層：

| 層 | 本尊 | 我方（本包） |
|---|---|---|
| ① Liquid 骨架 | `<div data-shopify="payment-button" class="shopify-payment-button"> <shopify-accelerated-checkout … disabled > <div class="shopify-payment-button__button" role="button" …> <div class="shopify-payment-button__skeleton">&nbsp;</div> </div> </shopify-accelerated-checkout> </div>` | `ThemeEngine::Filters#payment_button`（逐字；`access-token`／`shop-id` 由店導出、Normalizer 抹） |
| ② head bootstrap（content_for_header） | `dynamic.init`／`buyer_consent`／cleanup 三支 script → `<script type="module" src=…/portable-wallets.{lang}.js>` → `nomodule` → `<link id="shopify-accelerated-checkout-styles">` → `<style id="shopify-accelerated-checkout-cart">` | `Storefront::DynamicCheckoutHead.build`（接在 SEO head 段後；本尊完整 head 順序歸 T10） |
| ③ 模組升級光 DOM | `shopify-accelerated-checkout`（拆 `disabled`、加 `requires-shipping=""`）> `shopify-buy-it-now-button`（8 個屬性）> `button.shopify-payment-button__button.shopify-payment-button__button--unbranded`（文案依語言）；兩層 closed shadow root；注入 `<style id="global-shopify-accelerated-checkout-styles">` | `app/assets/storefront/portable-wallets.js`（自訂元素＋樣式回溯演算法對位） |
| ④ 按下 | `POST /api/unstable/graphql.json?operation_name=cartCreate`（Storefront API，另建 cart、不動買家購物車）→ `location = cart.checkoutUrl`（`/cart/c/{token}?key=…`）→ 302 結帳頁 | `Storefront::ApiController#graphql`（只認 cartCreate）→ `Storefront::CartController#checkout_link` → `/checkouts/{token}` |

## 2. 具體功能與值域

- **骨架屬性**（①）：`recommended="null"`、`fallback`（JSON 跳脫形：`supports_subs`／`supports_def_opts`／`name: buy_it_now`／`wallet_params: {}`）、
  `access-token`（`Storefront::AccessToken.for(shop.id)`＝HMAC-MD5 32 hex；公開值）、`buyer-country`（D80 生效國碼）、`buyer-locale`（本尊碼 `zh-CN`）、
  `buyer-currency`、`variant-params`（選中變體 `[{id, requiresShipping}]`）、`shop-id`、`enabled-flags="[&quot;a1d1f9a1&quot;]"`（本尊值照抄，91 V）、`disabled`。
  無 product 脈絡 ⇒ 空字串。
- **bundle 語言**（②）：`<html lang>` 的本尊碼小寫（`LocaleTags.shopify_code(tag).downcase`）：en／zh-cn／zh-tw／fr／ja；模組路由把 `zh-cn` 反查回
  `zh-Hans` 取字典。文案＝`config/storefront_locales/*.yml` `_platform.accelerated_checkout.buy_now`（各語言 bundle 逐字：Buy it now／立即购买／立即購買／
  Acheter maintenant／今すぐ購入）；未知語言落 en。
- **模組行為**（③）：
  - `shopify-accelerated-checkout` 連線時：確保 `link#shopify-accelerated-checkout-styles` 存在（缺則插到 head 首）；第一個實例執行樣式回溯；建 closed
    shadow root（`<slot name="button">`）；依表單同步 `disabled`（submit 鈕 disabled／aria-disabled）、`requires-shipping`（variant-params 查選中變體）、
    `has-selling-plan`；移除骨架子節點；建 `shopify-buy-it-now-button`（屬性序 access-token／buyer-country／buyer-currency／wallet-params="{}"／
    page-type="product"／slot="button"／[disabled]／[requires-shipping]／[has-selling-plan]／call-to-action=""）；MutationObserver＋`change` 跟表單。
  - `shopify-buy-it-now-button`：closed shadow root（`<slot>`）＋光 DOM `<button type="button" class="shopify-payment-button__button shopify-payment-button__button--unbranded">`；
    `disabled` 反映成按鈕 `aria-disabled`／`disabled`；按下 ⇒ ④。
  - **樣式回溯**（本尊 style backwards compatibility，演算法對位 §G26）：讀同源／`crossorigin=anonymous` 樣式表中命中舊選擇器的規則 → 特異度排序 →
    取 height／min-height／border-radius／margin-top（`!important` 優先；含 `var(--…-block-size` 或 `auto` 者排除；height＋min-height 皆有取 `max()`）→
    box-shadow 取 `.product-form__buttons .button::before` computed → 元素上已有的 `--shopify-accelerated-checkout-*` 跳過 → 寫
    `<style id="global-shopify-accelerated-checkout-styles">`（`document.head.appendChild`）。Ella ⇒ `--…-button-block-size: 5rem; --…-button-box-shadow: none;`。
  - `shopify-accelerated-checkout-cart`：只拆 `.wallet-cart-button__skeleton`（我方無第三方錢包；購物車包再對表）。
- **cartCreate**（④）：標頭 `X-Shopify-Storefront-Access-Token`（錯／缺 ⇒ 401，91 V）／`X-SDK-Variant: portable-wallets`／`X-Wallet-Name: BuyItNow`／
  `X-Start-Wallet-Checkout: true`；變數 `{input:{lines:[{merchandiseId:"gid://chilllove/ProductVariant/{id}",quantity,attributes:[{key,value}]}],discountCodes:[]},country,language}`；
  回應鍵序＝抓包（`data.result.{cart{id,checkoutUrl,deliveryGroups,cost,discountAllocations,discountCodes,lines},errors,warnings}`＋
  `extensions.{context{country,language},cart_changelog}`）；`MoneyV2.amount`＝`BigDecimal#to_s("F")`（`"188.0"`；鐵律 3：儲存 cents，序列化層才轉）；
  售罄變體照建（`CartWriter.add(allow_sold_out: true)`；庫存閘在訂單成立）；查無變體 ⇒ `errors:[{message,field:["input","lines"],code:"INVALID"}]` HTTP 200；
  非 cartCreate ⇒ top-level `errors`（HTTP 200；鐵律 4 分層）。cart 為獨立記錄（不設 `_cl_buyer` cookie）。
- **結帳連結**：`GET /cart/c/{token}?key=`：key＝`Storefront::CartKeys.checkout_key`（HMAC-SHA512 base64url，`%3D%3D` 收尾）；驗過 ⇒
  `Checkouts::CreateFromCart` ⇒ `302 /checkouts/{token}`；key 錯／缺 ⇒ 404；空車 ⇒ 302 `/cart`。cart 全域 id 的 `?key=`＝`CartKeys.id_key`（32 hex）。

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `app/liquid/theme_engine/filters.rb#payment_button` | 骨架逐字；registers `shop_id`／`buyer_country`／`buyer_locale`（`Runtime#base_registers`） |
| `app/services/storefront/dynamic_checkout_head.rb` | head bootstrap 段（script 本體我方自寫；`Shopify.PaymentButton.init()` 只載一次模組） |
| `app/liquid/theme_engine/page_renderer.rb` | `origin:`（scheme＋host＋port；`PagesController` 傳 `request.protocol + host_with_port`）；200 頁把 bootstrap 接在 SEO head 段後 |
| `app/assets/storefront/portable-wallets.js`／`accelerated-checkout-backwards-compat.css` | 模組（`__BUY_NOW_LABEL__` 由路由代入 JSON 字串）／光 DOM 樣式表（規則集對位本尊，我方自寫） |
| `app/controllers/storefront/assets_controller.rb` | `portable_wallets`（語言反查＋文案代入；5 分鐘 public cache）、`accelerated_checkout_css`；檔案啟動時讀成常量 |
| `app/controllers/storefront/api_controller.rb` | `POST /api/:version/graphql.json`（version＝`unstable`／`YYYY-MM`）：cartCreate 形同回應 |
| `app/controllers/storefront/cart_controller.rb#checkout_link` | `GET /cart/c/:token` |
| `app/services/storefront/{access_token,cart_keys}.rb` | 權杖／兩把 key（HMAC 導出，不落表） |
| `app/services/storefront/cart_writer.rb` | `add(allow_sold_out:)` |
| `app/services/render_parity/normalizer.rb` | `access-token`／`shop-id` 抹值；bootstrap script 本體替身；bundle 語言檔名抹 `LANG` |
| `config/routes.rb` | 四條路由（模組／CSS／API／結帳連結；皆在租戶 host 約束內、catch-all 之前） |
| `config/storefront_locales/*.yml` | `_platform.accelerated_checkout.buy_now` |
| `spec/liquid/payment_button_spec.rb`（P1–P3）、`spec/requests/storefront_dynamic_checkout_spec.rb`（H1–H6）、fixture `minimal-1.0/templates/product.e18.json`＋`sections/main-product-form.liquid` | 驗證 |

🔴 **dev server 不 reload theme_engine**（§3.75／§3.86 既有登記，本包再犯）：本機對表期間改任何 app 檔（含 `touch`）都會讓下一個請求 500
（`uninitialized constant ThemeEngine::PageRenderer::ProductDrop`）——改檔一律重啟 server。模組 JS 是啟動時讀進常量：改 JS 也要重啟。

## 4. 跨功能／跨頁／前端影響

- **Ella `product-form.js`**：`Shopify.PaymentButton.init()`（我方 head 定義）；agree-condition 對 `.shopify-payment-button` 加 `disabled` class（主題自己的行為，
  兩邊同）。`product-info.js` 變體切換後重渲染表單 ⇒ 自訂元素自動升級（customElements）。
- **主題無關**：任何主題只要輸出 `{{ form | payment_button }}` 就得到同一套；Kalles／Minimog（T8／T9）對 `.shopify-payment-button__button` 的舊 CSS 由樣式回溯接住。
- **Storefront API 預留**：`/api/:version/graphql.json` 端點與 `X-Shopify-Storefront-Access-Token` 驗證已立；完整 GraphQL 執行器＝獨立包（路線圖 T11）。
- **結帳線**：`Checkout` 快照由獨立 cart 建立，與 Ajax 購物車無關；`/checkouts/{token}` 頁行為不變（X1 再對齊 URL 形）。
- **head 注入**：本尊完整 content_for_header（`shopify-features`／`__st`／`preloads.js`／`sections-script`…）＝T10；本包只放動態結帳段。
- **render parity**：`__head__` 段新增本段（Normalizer 已把 script 本體視為替身）；`template--T__main` 段的 `(missing)` 四列（payment button 子樹）由本包補齊。

## 5. 驗證（本機 mirror 店，dev server `mirror.lvh.me:3000`；hoko 快照＝2026-09-05）

| 項 | hoko（§G26） | 本機（scratchpad `e18/local_payment_button_probe.json`、`report-products_acme-tee-{1280,768,390}-open.md`） |
|---|---|---|
| 升級後 `.shopify-payment-button` 光 DOM | `shopify-accelerated-checkout[requires-shipping]` > `shopify-buy-it-now-button`（access-token／buyer-country／buyer-currency／wallet-params／page-type／slot／requires-shipping／call-to-action）> `button.shopify-payment-button__button.shopify-payment-button__button--unbranded` 立即购买 | 同結構、同屬性序、同文案；多 `disabled`／`aria-disabled`（本機 submit 鈕 `disabled`，見下） |
| `<style id="global-shopify-accelerated-checkout-styles">` | `shopify-accelerated-checkout {
  --shopify-accelerated-checkout-button-block-size: 5rem;
  --shopify-accelerated-checkout-button-box-shadow: none;
}` | 逐字相同 |
| computed（自訂元素兩層，28 屬性子集） | display inline… | 全同 |
| computed button | opacity 1 | opacity 0.5（`disabled` ⇒ Ella `button.shopify-payment-button__button--unbranded[disabled]{opacity:var(--opacity-50)}`） |
| computed 三寬 diff 的 payment 子樹 | — | 1280／768／390 各只剩上列 opacity 一列；E12 時的四列 `(missing)` 已補齊 |

`disabled` 的來源＝**資料態**：hoko 同一變體 Liquid `inventory_quantity` 99（sticky 鈕 `data-inventory-quantity="99" data-inventory-policy="deny"`）
而 `.js`／`available` false ⇒ Ella `blocks/buy-buttons.liquid` 判 `can_add_to_cart` true、不出 `hidden`／`disabled`；本機 mirror 店 `inventory_quantity` 0 ⇒
`hidden`＋`disabled`。本尊「available ≠ inventory_quantity > 0」（地點可履行／不可用量）尚未建模——91 §3.87、路線圖 T5。其餘段的差（header 語言選單、
promotion popup、multitasking bar）＝本機 dev 資料／時序，與本包無關；bt3 部署後以 mirror.chilling.com.hk 複驗（worklog Pending）。

閘門／突變：worklog「閘門」段。
