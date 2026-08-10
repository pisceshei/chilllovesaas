# 09 — API 全景與可拓展性

> Shopify 的對外介面可分五層：商家後台（Admin API）、買家前台（Storefront API / Customer Account API）、主題同源端點（Ajax / Section Rendering）、事件流（Webhooks）、App 擴充點（UI extensions + Functions）。本篇整理各層的規格與復刻對應（2025–2026 現況，以 shopify.dev 為準）。

## 1. Admin API（商家端）

**GraphQL-first**：REST Admin API 自 2024-10 起列為 legacy、不再獲新功能；2025-04 起新上架 public app 強制只用 GraphQL。新資源（新版 product model、metaobjects）僅在 GraphQL。

**版本化**：季度版本 `YYYY-MM`（每季首日發版），每版至少支援 12 個月、相鄰版本 9 個月重疊；發版同時出下一季 RC。棄用溝通：developer changelog、API health report、GraphiQL 內警告、REST 的 deprecation header。

**認證**：public app 走 OAuth 2.0（authorization code，或 embedded app 建議的 **token exchange**：App Bridge session token 直換 access token）；scopes 宣告在 `shopify.app.toml` 由平台代管安裝。商家自建 custom app 直接產 Admin API token。token 分 offline（長效）/ online（隨使用者 session）。

**Access scopes**：`read_X`/`write_X` 成對，按資源群劃分；敏感權限需額外審核（`read_all_orders`——預設 app 只能讀最近 60 天訂單、customer payment methods、protected customer data）。

**限流**：GraphQL 用 **calculated query cost**——scalar 0 點、object 1 點、connection 依 first/last、mutation 基礎 10 點；單 query 上限 1,000 點。Leaky bucket 依方案（回填速率）：standard 100 點/秒、Advanced 200、Plus 1,000、Enterprise 2,000；桶量以回應 `throttleStatus.maximumAvailable` 為準（官方未公布固定倍數）。REST：桶 40、回填 2 rps（Plus ×10），超限 429 + Retry-After。

**Bulk operations**：大量讀寫非同步——`bulkOperationRunQuery` 提交 → 輪詢或訂 `bulk_operations/finish` webhook → 下載 JSONL（巢狀以 `__parentId` 攤平）；寫入側 `bulkOperationRunMutation` + staged upload。

**主要資源群與代表操作**：
- Products：`productSet`（宣告式 upsert）、`productCreate/Update`、`productVariantsBulkCreate/Update`、`collectionCreate`
- Orders：`orderCreate`、`draftOrderCreate/Complete`、`orderEditBegin/Commit`、`refundCreate`、`returnCreate`
- Customers：`customerCreate/Update`、`customerMerge`、`customerSegmentMembers`
- Inventory：`inventoryAdjustQuantities`、`inventorySetQuantities`、`inventoryItemUpdate`（多地點、多 quantity state）
- Fulfillment：以 **FulfillmentOrder** 為中心——`fulfillmentCreate`、`fulfillmentOrderMove`、`fulfillmentTrackingInfoUpdate`
- Discounts：`discountCodeBasicCreate`、`discountAutomaticBasicCreate`、`discountAutomaticAppCreate`（掛 Function）
- Custom data：`metafieldsSet`、`metafieldDefinitionCreate`、`metaobjectDefinitionCreate`
- 平台：`webhookSubscriptionCreate`、billing（`appSubscriptionCreate`、usage records）、`publishablePublish`（通路上架）

**復刻對應**：demo 用內部 REST/tRPC，但先定好：資源命名、cursor 分頁、版本前綴（`/api/v1/`）、統一錯誤格式；限流一個簡單 token bucket。**FulfillmentOrder 的「訂單 ↔ 履約單分離」與 metafields 值得第一天進資料模型**。GraphQL 對外層可後補。

## 2. Storefront API（買家前台）

- 買家側 GraphQL，**token 可公開**。層級：tokenless（基本查詢）→ public token（瀏覽器）→ private token（server 端，可解鎖 customer 資料）。
- 能力：products/collections/search/metaobjects/menus 查詢；**cart mutations**（`cartCreate`、`cartLinesAdd/Update/Remove`、`cartBuyerIdentityUpdate`、`cartDiscountCodesUpdate`…）；cart 讀出 **`checkoutUrl` → 把買家交棒給平台結帳**（headless 也不自建結帳）。
- `@inContext(country, language, buyerIdentity)` 做市場定價/翻譯/B2B。
- 限流：不設固定 rpm，真實買家流量隨量擴展、bot 按 IP 與行為節流。
- Hydrogen/Oxygen 本質是 Storefront API 的官方預裝消費者。

**復刻對應**：**這是 Shopify 最核心的邊界設計，值得認真繼承**——後台 API 與前台 API 分離、前台 token 可公開、cart 是前台可寫的唯一資源、結帳只交出一個 URL。demo：唯讀 catalog API + cart CRUD + hosted checkout URL。

## 3. Customer Account API

新版顧客帳號（passwordless/OTP）的買家自助 GraphQL：訂單歷史、地址、profile、退貨、B2B。認證 OAuth 2.0 + OpenID Connect（SPA 用 PKCE）。

**復刻對應**：demo 用自家 session/JWT + 「我的訂單」幾個 endpoint；保留「買家身分與商家身分是兩套系統」的分離。

## 4. Theme 端 Ajax / 頁面 API（同源、免 token）

- **Cart 全家**：`GET /cart.js`、`POST /cart/add.js`、`/cart/update.js`、`/cart/change.js`、`/cart/clear.js`
- Shipping rates：`/cart/shipping_rates.json`（節流中，官方建議改用 prepare + async 非同步對）
- `GET /products/{handle}.js`（單品 JSON）、`/search/suggest.json`（predictive search）、`/recommendations/products.json`
- **Section Rendering API**：任何頁面 `?section_id=xxx`（回單一 section HTML）或 `?sections=a,b`（≤5 個，回 JSON map）；cart POST 支援 bundled section rendering（改 cart 同時拿回更新後的 HTML）——cart drawer 不整頁刷新的官方解法。

**復刻對應**：自營店面 demo 做 `/cart.js` + `/cart/add.js` + 一個 partial render 端點（回指定區塊 HTML）就能重現「加購 → drawer 滑出 → badge 更新」的體驗。

## 5. Webhooks

- 訂閱兩軌：app TOML 宣告（deploy 同步到所有店）或 API 建立店家別訂閱；通道：HTTPS、Amazon EventBridge、Google Pub/Sub。
- Topic 以 `資源/事件` 命名（數百個）：`orders/create`、`orders/paid`、`products/update`、`inventory_levels/update`、`app/uninstalled`…
- 驗證：`X-Shopify-Hmac-Sha256`（app secret 對 raw body 的 HMAC-SHA256）；`X-Shopify-Webhook-Id` 去重；at-least-once、不保證順序。
- 重試：5 秒未回 2xx 即失敗，4 小時內最多 8 次；24 小時窗口內持續失敗後訂閱被移除。
- Mandatory compliance webhooks（GDPR 三支）：`customers/data_request`、`customers/redact`、`shop/redact`。

**復刻對應**：先做 outbox 事件表 + 輪詢消費者；事件命名沿用 `資源/動詞`；對外 webhook 補上時照抄「HMAC + 唯一 event id + 指數退避 + 失敗停用」。

## 6. App 擴充點與 Shopify Functions

- **安裝與 session**：CLI 產 app 骨架（React Router template + TOML + extensions/）；embedded app 跑在 admin iframe，用 App Bridge session token（約 1 分鐘效期 JWT）驗證前端請求，token exchange 換 API token。
- **Extension 清單**：admin UI extensions（actions = 資源頁自訂 modal、blocks = 自訂卡片）、checkout UI extensions、post-purchase、customer account extensions、theme app extensions（app blocks 注入主題）、POS UI extensions、Flow triggers/actions、web pixels（sandbox 分析 JS）、marketing activities、payments apps。UI extensions 全部跑在受控 sandbox，不能任意動 DOM。
- **Shopify Functions**：伺服器端自訂邏輯，**編譯成 WASM** 由平台在關鍵流程同步執行（毫秒級、無網路/檔案）。Function APIs：Discount（cart lines + delivery 兩階段）、Cart Transform（bundle）、Cart & Checkout Validation、Payment Customization、Delivery Customization、Fulfillment Constraints、Order Routing、Pickup 選項生成。限制：input query 成本上限、輸入 128 kB/輸出 20 kB、約 11M instructions、binary 256 kB。
- **開發者體驗**：GraphiQL explorer、dev store、**Shopify Dev MCP server**（讓 AI 工具查文件/introspect schema/驗證 query——官方文件已「AI 可讀化」）。

**復刻對應**：擴充系統是護城河但屬第三階段。demo 的最小前瞻設計：(a) theme 層留 block 插槽概念；(b) 計價管線留 hook 介面（`applyDiscounts(cart, config)`），之後可換沙箱化 user code；(c) API 設計自帶 scope 概念。自家文件對 LLM 友善（llms.txt/MCP）成本低回報高。

## 來源

shopify.dev：/docs/api/admin-graphql、/docs/api/usage/versioning、/docs/api/usage/limits、/docs/api/usage/access-scopes、/docs/api/usage/bulk-operations/queries、/docs/api/storefront、/docs/storefronts/headless/building-with-the-storefront-api/cart/manage、/docs/api/customer、/docs/api/ajax（reference/cart、section-rendering）、/docs/apps/build/webhooks、/docs/apps/build/compliance/privacy-law-compliance、/docs/apps/build/app-extensions/list-of-app-extensions、/docs/apps/build/functions、/docs/api/functions、/docs/apps/build/authentication-authorization、/docs/apps/build/devmcp、changelog 各條目
