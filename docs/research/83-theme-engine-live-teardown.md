# 83 — Liquid 主題引擎 live teardown（真店跑 Ella 7.2.0 的全面實測）

> 取證日期：**2026-08-30**。環境：測試店 `chill-love-u5q5mnzq`（Shopify Plus dev、
> development 態強制密碼保護）、發布主題＝`ella-7-2-0-theme-source` v7.2.0
> （**theme id 165451858155**，2026-08-12 上傳）——與我方 golden fixture
> `test/fixtures/themes/ella-7.2.0` 同源（§9 有實例級同一性證據）。
> 工具：本地 Chrome（claude-in-chrome）＋鐵律 14 網路抓包；密碼牆內的前台
> 量測全部經 admin「View store」旁路 session 在 **真網域 chill.deals** 取得，
> 預覽站（`*.shopifypreview.com`）僅作對照組（§7.3 證實兩者行為不同）。
> 本檔是 25/26/27/31 四件套的 live 補充層：**衝突時以本檔實測為準**，
> 修正已回寫的條目在原檔留更正註。

## §0 入口與工具限制（先讀，省你半天）

- **admin 主題面板／code editor／theme editor 的內容全在跨域 iframe**
  （`online-store-web.shopifyapps.com`）。🔴 **本機 Chrome 擴充的合成輸入
  （滑鼠＋鍵盤）完全進不去這些 iframe**——themes 清單的 ⋯ 選單、Edit theme
  按鈕、code editor 檔樹、editor 左欄，點了無任何反應（三個面各自實測）；
  a11y 樹也讀不到（14.3 工具限制）。可用的替代：
  - **官方文檔錨定的頂層 URL**（實測有效）：
    - code editor＝`admin.shopify.com/store/{store}/themes/{id}`（文檔錨
      `shopify.com/admin/themes/current`，https://shopify.dev/docs/storefronts/themes/tools/code-editor）
    - theme editor＝`…/themes/{id}/editor`（文檔錨 `…/themes/current/editor`，
      https://shopify.dev/docs/storefronts/themes/tools/online-editor）
    兩者頁面會載入渲染（可截圖取結構），但互動仍被 iframe 牆擋。
  - **theme id 不用猜**：任何前台頁的 `window.Shopify.theme.id`（§5）。
- **View store 旁路機制**：admin themes 頁「View store」→ 開新分頁直達
  `https://chill.deals/`（真網域），密碼牆自動旁路（cookie session）。
  🔴 **session 會過期**（本輪實測約 10–20 分鐘後分頁標題變回密碼頁
  「Come back ⚡」）；過期就回 admin 再點一次。頁尾出現 Shopify 注入的
  **preview bar**（theme 名＋Password protected 鎖標＋View as＋國家/語言
  選擇器＋Edit theme）——它本身也是跨域 iframe（`cdn.shopify.com/shopifycloud/preview-bar`），同樣點不進去。
- **claude-in-chrome 的 `resize_window` 在本機也是假成功**（回報 resized、
  `innerWidth/Height` 實測不變）——與內嵌瀏覽器同款坑（記憶
  `three-width-measurement` 的判準擴大到本工具）。
- 產品頁「Preview」按鈕（admin 商品詳情頁頂欄）→ 開
  `https://{token}-{id}.shopifypreview.com/products_preview?preview_key={32hex}`
  ——**獨立預覽網域**，key 即認證。🔴 §7.3：該站**不執行管道發布閘**，
  可見性量測不得在它上面做。

## §1 面板層（themes admin）

實測到的可見面（iframe 牆內、僅截圖）：單一主題卡（縮圖雙裝置預覽、
`ella-7-2-0-theme-source`、`Added: Aug 12 at 11:28 pm`、`Version 7.2.0 ˅`
版本下拉、⋯ 選單、`Edit theme` 主鈕）＋橫幅
「In development: visitors need the password to access your store」＋
`See password`。⋯ 選單值域＝**未取得**（iframe 牆；候選解鎖路徑見 §10）。

Preferences（`online_store/preferences`）Store access 節與 82 §9.6a 一致：
Password protection toggle（development 態**灰化強制開**）、密碼明文顯示
（6/100 字元）、Message to visitors（0/5000）、資訊條逐字
`Your online store is in development. To let visitors access your store, give them the password.`

## §2 渲染面：section 實例 id 與群組對映

商品頁全 section 清單（DOM `.shopify-section` 的 id，2026-08-30）：

```
sections--23451774451947__announcement_bar_4tGfEp   ┐
sections--23451774451947__header_default            │ header-group（type: header）
sections--23451774451947__header_mobile_MqfLk9      ┘
sections--23451774484715__multitasking_bar_AY9KgF   ┐
sections--23451774484715__cart_drawer_PFLQy3        │
sections--23451774484715__toolbar_mobile_3HBwAV     │ popup-group（type: custom.popup）
sections--23451774484715__promotion_popup_epACJx    │
sections--23451774484715__before_you_leave_GxJyQy   ┘
sections--23451774419179__color_swatches_wJV8Fg     ─ general-group（type: aside）
sections--23451774386411__footer                    ─ footer-group（type: footer）
template--23451774025963__main                      ┐
template--23451774025963__section_product_tabs_U8mYg9        │ product.json
template--23451774025963__recently_viewed_products_WcH46k    │ template
template--23451774025963__product_recommendations_ecaxGU     ┘
```

- **id 語法**＝`{sections|template}--{實例數字id}__{section鍵}`；section 鍵
  來自群組/模板 JSON 的 key（預設鍵如 `header_default`／`main` 無隨機尾碼，
  新增實例帶 6 位尾碼如 `_AY9KgF`）。官方定義（section-rendering 頁，
  2026-08-30）：static section 的 id＝檔名；JSON template／section group 內
  的 section 拿 dynamic id。
- **數字前綴＝群組（或模板）實例的 DB id**：同店四個群組四個數字。
  404 頁同樣渲染全部群組（8+ section）⇒ 群組是 layout 級、與模板無關。
- 🔴 **群組 type 值域實測**：`header`／`footer`／`aside`／`custom.popup`
  （fixture 四個群組檔的 `type` 欄；`custom.*` 命名空間真實存在）。
- editor 左欄同構（§8）：Header group／Popup group／General group（＋捲動
  外的 Template/Footer）逐組 `Add section`。

## §3 HTTP 相容面：live 驗證表（25 §5 的實測對賬）

全部在真網域、View store session 內取得（2026-08-30）。

### §3.1 金額三態（🔴 鐵律 3 的活體標本）

同一商品（Vichy…50ml，HK$318）三個端點三種編碼：

| 端點 | 值 | 形態 |
|---|---|---|
| `/products/{handle}.js` | `31800` | **integer cents** |
| 頁內 JSON-LD `offers.price` | `318` | **十進位主單位（number）** |
| `/search/suggest.json` `products[].price` | `"318.00"` | **十進位字串** |

另：`/cart.js` 全金額欄位＝integer cents（官方句「All monetary properties
are returned in the customer's presentment currency」講幣別不講單位——單位
是我方實測補的）；`ShopifyAnalytics.meta.product.variants[].price`＝cents；
`Shopify.currency = {active:"HKD", rate:"1.0"}`（**rate 是字串**）。

### §3.2 product 端點對

| | `/products/{h}.js`（Ajax API） | `/products/{h}.json` |
|---|---|---|
| 頂層 | 商品物件本體（25 鍵） | `{product: {…16 鍵}}` |
| 金額 | cents 整數 | `"0.00"` 十進位字串 |
| 特有鍵 | `price_min/max`、`compare_at_price_*`、`options[{name,position,values}]`、`featured_image`、`requires_selling_plan`、`selling_plan_groups`、`media` | `body_html`、`published_scope`、`template_suffix`、`admin_graphql_api_id` 系 |
| `status` 鍵 | **無** | **無** |

`.js` 變體 22 鍵含 `quantity_rule`、`quantity_price_breaks`、
`selling_plan_allocations`、`inventory_management`。單變體商品的 options＝
`[{name:"Title",position:1,values:["Default Title"]}]`（隱含變體實體化）。

### §3.3 cart 家族

- **`/cart.js` ≡ `/cart.json`**（頂層鍵序完全相同——與 product 端點對的
  **不對稱**是本節要點）。頂層 **14 鍵**＝26 號清單 13 鍵
  ＋🔴 **`discount_codes`**（文檔清單外，live 多出）。
- line item `key` 格式實測：`{variant_id}:{32hex}`（`49283448701163:d879b…463`）。
- `POST /cart/clear.js` → 200、整車物件（14 鍵）、`item_count:0`。
- Ella 的寫入路徑（§4）用**無 `.js` 後綴**的 `/cart/add`、`/cart/change`
  ——兩種形都被伺服器接受。

### §3.4 Section Rendering API（六格）

| 探針 | 結果 |
|---|---|
| `?section_id={合法動態id}` | 200，**帶 wrapper** 的裸 HTML（`<div id="shopify-section-{id}" class="shopify-section">`，主 section 64KB） |
| `?section_id=no-such-section` | **404**（官方句逐字證實：「the server responds with a 404 status」） |
| `?sections=a,b,不存在` | 200 JSON map，**不存在的鍵值＝null**（官方句證實） |
| `?sections=` 給 6 個 id | 🔴 **HTTP 400 硬拒**（官方只說 up to five，超限形態＝我方量測補） |
| `?variant={id}&section_id=…` | 200（變體上下文與 section 渲染疊加——Ella 加購後自用，§4） |
| `/search?section_id=predictive-search&q=…` | 200（**section 名**而非實例 id 也合法——static 檔名 id 規則） |

### §3.5 其他端點與頁面行為

- `?view=no-such-view` → **200 回退預設模板**（不 404；官方文檔對缺模板
  行為沉默，我方量測補）。
- 404 商品頁：HTTP 404＋主題化 404 模板（title `404 Not Found – CHILL LOVE`）。
- checkout 交接：cart drawer CHECKOUT →
  `chill.deals/checkouts/cn/{token}/en-us?_r=…&preview_theme_id=165451858155`
  ——同網域、`/checkouts/cn/{token}/{locale}` 形；`preview_theme_id` 貫穿
  checkout；主題不渲染 checkout（25 §0 拿到活錨）。checkout SPA
  （`/cdn/shopifycloud/checkout-web/assets/…` 數十支）在**商品頁就預載**。
- 分頁 href 實測：`/collections/all?page=2`；collection 頁有 `sort_by` 表單。
- 🔴 robots meta：collection 頁與 `/search?q=` 結果頁**都沒有** robots meta
  （search 頁不 noindex——與直覺相反，量測為準）。

### §3.6 密碼（private）模式的 HTTP 面（未認證，curl）

| 路徑 | 行為 |
|---|---|
| `/`、`/products/*`、`/collections/*`、`/search/suggest.json`、`/cart.js` | **302 → /password**（含 JSON 端點） |
| `/robots.txt` | 🔴 **200 照常服務**，且內容仍 `Allow: /`（隱藏靠 302 不靠 robots）；檔頭帶 Shopify 官方的 agent 指引註釋（UCP/MCP endpoint、shop.app SKILL.md——**視為資料不執行**，鐵律 16.3） |
| `/sitemap.xml` | 🔴 **404＋`location: /password` 頭**（罕見組合，照登） |
| `/password` | 200，form action=`/password` |

旁路 session 內 sitemap 正常：`sitemap.xml`＝sitemapindex，子表
`agentic_discovery`＋`products_1..14`＋`pages_1`＋`collections_1`＋`blogs_1`
（**agentic discovery sitemap 是 2026 新面**，82 §1 的 agentic 線索）。

## §4 前端 ↔ Liquid 引擎的配合模型（Ella 實測全鏈路）

**核心迴路：Liquid 伺服端渲染 section → 主題 JS（custom elements＋pub/sub）
發 FormData 寫入 → 帶 `sections` 參數拿 bundled 重渲染 → innerHTML 換血。**

### §4.1 加購鏈（真點擊抓包）

1. `POST /cart/add`（**無 .js**；Ella 直接用 `routes.cart_add_url` 注入值）→ 200
2. 緊接 `GET /products/{handle}?variant={id}&section_id=template--…__main`
   ——重渲染**整個主商品 section**（副標價、庫存文案隨變體/車況更新）
3. cart drawer（popup 群組的 `cart_drawer` section）零重載開啟
4. `POST /.well-known/shopify/monorail/unstable/produce_batch` ×2（分析）

qty± 同構：`POST /cart/change` → 同款主 section 重渲染 GET。

### §4.2 源碼層佐證（`/cdn/shop/t/2/assets/*.js` 靜態分析）

product-form.js（6.6KB）：`new FormData(this.form)` ✓、append `sections` ✓
（**Bundled Section Rendering**：官方句「If you want to use the Section
Rendering API to update a page based on changes to the cart, then you should
consider bundled section rendering」）、`routes.cart_add_url` ✓、
`fetchConfig` ✓、發布 `cartUpdate` 事件 ✓。
global.js（136KB）：`fetchConfig`（Accept `application/json`）、pub/sub
（`subscribers`）、legacy `onCartUpdate`。cart-drawer.js：`renderContents`
＋sections 換血 ✓。⇒ **請求體＝multipart FormData**（非 JSON items 形；
兩形官方都收）。

### §4.3 預測搜尋（真打字抓包）

`GET /search/suggest?q=shirt&resources[limit_scope]=each&section_id=predictive-search`
——🔴 **拿的是伺服端渲染的 HTML 面板**（section 名 id），不是 JSON API；
`/search/suggest.json` 是另一模式（我方手動驗證可用）。同一路由雙模式。
UI：查詢建議（關鍵詞高亮）＋商品格（劃線 compare-at＋紅色售價）。

### §4.4 Ella 的 `window.routes` 注入（theme.liquid）

```json
{"cart_add_url":"/cart/add","cart_change_url":"/cart/change",
 "cart_update_url":"/cart/update","cart_url":"/cart",
 "collection_all":"/collections/all","predictive_search_url":"/search/suggest",
 "root":null,"root_url":"/","search_url":"/search",
 "shop_origin":"https://chill.deals"}
```

🔴 `root` 字面 **null**（`root_url` 才有值）——相容層照抄，別「修好」它。

### §4.5 行為層雜項（逐項實測）

- 售罄變體 radio：桌機版 class `disabled`（**attr 不 disabled**）、行動版
  attr `disabled`＋`visually-disabled`——同一控件兩渲染兩策略。點擊售罄
  radio 無任何效果（不切換、不發請求）。
- promotion_popup（NEW ARRIVALS 訂閱窗，demo 文案含原版錯字「SUTMIT」）與
  before_you_leave（exit-intent：STYLE20 折扣碼＋copy 鈕＋Example product
  ×3）都會**攔截點擊**且 before_you_leave 滑鼠上移即**重複觸發**——
  量測腳本必須先關窗再點目標。
- multitasking bar（recently viewed）：
  `GET /search?section_id=…__multitasking_bar_…&type=product&q=id:9913007767787 OR id:9813965504747`
  ——**用 search 路由的 `q=id:X OR id:Y` 語法**做多 id 撈取＋section 渲染。
- `/api/collect` POST 在本店恆 **503**，主題 JS 靜默容忍（fail-open）。

## §5 `window.Shopify` 全域 API 面（Ella 世代 live 實錄）

密碼頁就已注入（32 鍵，2026-08-30）：
`shop, locale, currency, country, theme, cdnHost, routes, previewMode,
shopJsCdnBaseUrl, SignInWithShop, loadFeatures, autoloadFeatures,
featureAssets, ce_forms, captcha, MCP, PaymentButton, analytics, evids,
formatMoney, bind, setSelectorByValue, addListener, postLink, [b64], removeItem,
getCart, onCartUpdate, modules, [b64], actions`

- 🔴 比 25 號坑13 的 Dawn/Horizon 集**多出 legacy 檔**：`formatMoney`、
  `getCart`、`onCartUpdate`、`removeItem`、`bind`、`setSelectorByValue`、
  `addListener`、`postLink`（option_selection.js 世代 API）——**Ella 相容
  stub 集必須含這批**，25 §3 清單已加更正註。
- `Shopify.theme` live 形：`{handle:"null"(字串!), id, name, role:"main",
  schema_name:"Ella", schema_version, style:{handle:null,id:null},
  theme_store_id:null}`。
- `Shopify.routes` 平台版只有 `root`（官方句：「The global value
  `window.Shopify.routes.root` is available…」）；Ella 的 `window.routes`
  （§4.4）是主題自己的另一份。

## §6 `content_for_header` 注入清單（live）

平台腳本 15 支（去重、去主題資產）：`trekkie.storefront.*.min.js`、
`/checkouts/internal/preloads.js`、shop-js `loader.init-shop-cart-sync`、
🔴 `theme-hot-reload/theme-hot-reload.js`（preview session 才有；§8.3）、
storefront `load_feature`／`origin_trials`／`shop_events_listener`、
`portable-wallets`、🔴 `preview-bar/preview-bar-modules.js`（preview 注入）、
`/cdn/wpm/*.js`（web pixels manager）。
**App 注入鏈**（本店裝了 shipany 取貨 app）：loader.js＋spurit.js＋
Delivery-Options.js＋🔴 **unpkg.com 的 localforage/pako**——app script 可以
拉第三方 CDN 進店面（W6 做 app 注入面時的安全對照）。
另：`meta[name=generator]`＝**null**（沒有「Shopify」generator meta，
與傳言相反）；`shopify-digital-wallet` meta 存在；preconnect
`fonts.shopifycdn.com`。

## §7 可見性合流（S9 的前台格——真網域實測）

### §7.1 UNLISTED（D53-QC，觀察用 fixture）

| 面 | 結果 |
|---|---|
| 直連 `/products/{h}` | **200 渲染** |
| robots meta | 🔴 **`noindex,nofollow`**（對照組 Active 商品＝**無 robots meta**——排除全站因素，**限 UNLISTED 專屬**；limits.yml `unlisted_meta_robots` 由 D4 裁定升格為已量測） |
| canonical | **照常存在**（noindex 與 canonical 並存） |
| `/search/suggest.json` | 排除 |
| `/search?q={全名}` | 0 結果 |
| products sitemap（14 子表全掃） | 排除 |
| `.js`／`.json` 端點 | **都 200**（「referenced individually by handle」含 JSON 端點） |

### §7.2 未發布（S9-VIS-Lifecycle-Test 9917399335147，本輪新建、Active、已自 Online Store 取消發布）

直連 404、`.js` 404、suggest 排除、sitemap 排除——「unpublished ⇒ 如同不存在」
在 Liquid 面＝**404**（Storefront API 面＝null＋connection 移除，官方句
「Unpublished products will behave just like they were archived or deleted:
they will be omitted from connections and not found when queried by handle
or ID」，shopify.dev product query，2026-08-30）。
Draft＋已發布（同商品狀態流轉時段）＝同樣 404＋suggest 排除。
🔴 該商品**保留**作長期 fixture（同 P12 用法）：Active、只發布 POS/Shop。

### §7.3 🔴 預覽站不執行發布閘（量測方法坑，最高優先）

同一時刻同一商品（S9-VIS，已自 OS 取消發布）：
**真網域 404 ∥ shopifypreview.com 預覽站 200**（45 秒與 10+ 分鐘後複測仍 200）。
預覽站執行 status 閘（Draft→404）但**不執行 publication 閘**。
⇒ 任何可見性量測必須在真網域旁路 session 做；預覽站結論一律無效。
另：預覽站**全站** robots＝`noindex,nofollow`（Active 商品也有）⇒ 在預覽站
量 UNLISTED noindex 必然假陽性——本輪就是先在預覽站踩到、再用真網域對照組
排掉的（過程留檔於本節作方法教材）。

## §8 編輯器層

### §8.1 Code editor（`/themes/{id}`）＝ VS Code web

完整 VS Code 殼（EXPLORER／OUTLINE／TIMELINE／REFERENCES／DEPENDENCIES、
`Ctrl+Shift+P` 命令面板提示、狀態列 `chill-love-u5q5mnzq.myshopify.com ⊘0 ⚠0`、
`Layout: US`）。檔樹八夾：**assets, blocks, config, layout, locales,
sections, snippets, templates**（與官方 architecture 頁的目錄結構逐字一致，
2026-08-30）。互動被 iframe 牆擋（§0）。

### §8.2 Theme editor（`/themes/{id}/editor`）

頂欄：主題名＋`Active` chip＋`Store default`＋頁面選擇器（`Home page`）＋
裝置切換＋⋯＋`Save`（灰）。左欄 section 樹與 §2 群組完全對映，逐組
`Add section`。右側預覽 pane（storefront iframe）。互動同被牆擋。

### §8.3 editor↔preview 協議（theme-hot-reload.js 靜態特徵）

`/cdn/shopifycloud/theme-hot-reload/theme-hot-reload.js`（14.8KB，preview
session 注入）：`postMessage` ✓、message listener ✓、`section_id` ✓、
`shopify-section` ✓；無 `morph`／`designMode` 字面。⇒ 編輯器經 postMessage
指揮 storefront 內的 agent 以 section 為粒度熱替換——與 27 §6 的推定機制
同構；訊息 schema 全文＝未取得（要驅動 editor 才抓得到，被 iframe 牆擋）。

## §9 fixture ↔ live 同一性（golden parity 的地基）

- fixture `sections/popup-group.json` 的 section 鍵：
  `multitasking_bar_AY9KgF, cart_drawer_PFLQy3, toolbar_mobile_3HBwAV,
  promotion_popup_epACJx, before_you_leave_GxJyQy`——**與 live 渲染的實例
  尾碼逐字元一致**（§2）。header/general/footer 三組同驗。
  ⇒ live 主題與 fixture 在群組實例層同源；**golden-parity 渲染對比可以
  直接拿現有 fixture 當基準**，不必先拉 live 源碼。
- 🔴 **坑12 拿到 live 證據**：fixture `layout/theme.liquid:89`
  `{% sections 'toolbar-mobile' %}` 引用的群組檔 `sections/toolbar-mobile.json`
  不存在（fixture 群組只有四個；live 渲染也無該群組實例）——**真引擎對
  缺失群組＝靜默空渲染，頁面照常**（25 §10 坑12 的「渲染空＋警告，不可炸」
  由推定升格為 live 實證；warning 面未取得）。
  註：`sections/toolbar-mobile.liquid`（section 檔）存在且作為 popup 群組
  成員渲染——**同名 section 檔與群組引用是兩回事**，讀 fixture 時別混。
- fixture 有 `blocks/` 夾（`_*.liquid` 命名的 theme blocks）⇒ Ella 7.2.0
  已用 2026 blocks 體系（theme blocks ≤300／`@theme` opt-in／
  `{% content_for 'blocks' %}`——官方 blocks 頁，2026-08-30；27 §1
  「三代混合」的第三代成分定量）。
- `compiled_assets/scripts.js`＋`snippet-scripts.js`：**平台側編譯產物**
  （路徑不在 assets/、`?v=` 時間戳比主題資產晚 97–98 秒＝上傳後編譯）——
  `{% javascript %}`／snippet script 的運行時載體。我方引擎 25 §4 匯入管線
  需要對位物。

## §10 未取得（誠實清單）＋解鎖路徑

| 項 | 為什麼未取得 | 解鎖路徑 |
|---|---|---|
| themes ⋯ 選單值域、editor/code editor 互動面 | iframe 輸入牆（§0） | 使用者親手操作一輪＋截圖；或 Shopify CLI 覆蓋大部分需求 |
| live 源碼全量 diff（匯入正規化：JSON 註解/尾逗號清洗、settings_data 現值） | 源碼只能經 editor UI 或 Theme API | 🔴 **Shopify CLI `theme pull`**（需使用者做一次 OAuth 授權） |
| `{{ product \| json }}` 級 drop 形狀、nil 語義、錯誤渲染形態 | 要 push 診斷模板 | 同上（`theme push` 到 **unpublished 副本**跑探針） |
| editor↔preview postMessage schema 全文 | 要驅動 editor | iframe 牆解除後抓包 |
| cart add 的 raw multipart bytes | 抓包工具不給 body；源碼特徵已定性 FormData | CLI push 疊加測頁可繞 |
| `?sections=` 上限 400 的 body 文案 | 誤差成本低未追 | 隨手補 |
| Ella 自有 localization form 的 POST 形 | 排程取捨 | 下輪前台包補 |

## §12 CLI 探針輪（2026-08-30 晚；Shopify CLI 4.7.0，使用者完成 OAuth）

工具解鎖：`shopify theme list/pull/push`。店內主題：ella-7-2-0-theme-source
[live] #165451858155、Horizon [unpublished] #164510695659（主題庫被 §0 iframe
牆擋住看不到的，CLI 可見）。探針主題 **S9-Probe #166056231147**（unpublished，
極簡 layout＋受控 product 模板，保留作長期儀器）。

### §12.1 上傳驗證與正規化（pull 全量普查，884 檔）

| 發現 | 逐字／數字 |
|---|---|
| layout 驗證錯誤文案 | `Missing {{content_for_header}} in the head section of the template`（缺 content_for_header 時 push 拒收該檔；theme 仍建立） |
| 必備模板強制 | 新主題被平台自動補 `templates/gift_card.liquid` 且**拒絕刪除**（`templates/gift_card.liquid could not be deleted`） |
| 🔴 平台把 JSON 寫成 JSONC | 53 個 JSON template／group／settings 檔被平台加上 `/* … auto-generated … */` 頭註——**平台自身的存檔格式就含註釋** ⇒ 我方 tolerant JSON 解析（25 §4）從寬容項升格為必要條件 |
| 🔴 平台會改寫 Liquid 源碼 | 2 檔（blocks/_country-selector、_product-media-gallery）被修 typo（`loca lPosition:`→`lPosition:`）並在檔尾追加 `{% comment %} This file has been rewritten to preserve the original behavior… Changes: from…to…` 機器 changelog |
| 其餘 | 828 檔逐位元組相同；唯一真語義差＝templates/index.json 的 media_gallery section settings（素材引用層，41KB blob）；檔案名單零增刪 |

### §12.2 真引擎 drop 語義（受控模板逐格）

| 格 | 真引擎行為 | 我方（#200） |
|---|---|---|
| 壞 `?variant=999999999` | 忽略，回退首可購變體 | **同款** ✓（原「ours」升格為已證同形） |
| `?variant=` 指向售罄變體 | 選中生效（selection 壓過 availability） | 同款 ✓ |
| 全售罄（單變體）sofav | 回該變體（非 nil） | 同款 ✓（多變體全售罄格仍未取證） |
| `{{ product.status }}` | 空輸出 | 同款 ✓（93 §D 真引擎級驗證） |
| 缺屬性／缺屬性 `\| money` | 空／空 | 同款 ✓ |
| `inventory_quantity/policy/management` | 10／deny／shopify | 語義同款 ✓ |
| `value.available/selected/id` | S=true,true,\<option_value_id\>；售罄值 false | 介面同款 ✓ |
| `variant.url` | `/products/{handle}?variant={id}` | 同款 ✓ |
| 🔴 全 nil compare_at 的 min/max | 印 **0** | 原回 nil ⇒ **已修**（0 fallback） |
| 🔴 `weight_unit` | 預設 `kg` | 原 miss-nil ⇒ **已補**（常數 kg，ours） |
| `product \| json` | ≈ `.js`：差 `url`↔`content`、variant 無 `quantity_price_breaks`、無 media | 登記（W6 json filter parity） |
| `options_with_values \| json` | values＝**純字串陣列**（drop 面有屬性、json 面壓平） | 登記（W6 json filter parity） |

## §11 對四件套的回寫索引

- **25 §3**：window.Shopify stub 集加 Ella legacy 八件（→ §5）；坑13 更正註。
- **25 §5**：cart.js≡cart.json＋`discount_codes`；`/cart/add` 無後綴形合法；
  FormData 定性；三態金額（→ §3）。
- **25 §10 坑12**：live 證實註（→ §9）。
- **26 §1**：routes drop 的 `root:null` 怪癖；`Shopify.theme` live 形。
- **27 §6**：hot-reload 特徵實測註（→ §8.3）。
- **27 §0/§1**：blocks/ 三代成分定量（→ §9）。
- **31 §2 E 線**：本檔 §3 全表作為端點驗收的 live 基準。
