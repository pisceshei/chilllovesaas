# 13. 事件、Webhooks、通知與自動化（Webhooks / Flow / Notifications / Channels）

> 取證日期：2026-08-14。來源＝shopify.dev（2026-07 API 版本）＋ help.shopify.com；倉庫對照＝`docs/specs/18`、`docs/research/28` §15、`docs/research/82`。
> 標注慣例：【官方】＝官方文檔直證；【內部】＝倉庫既有實測/裁定；⚠＝官方查不到或兩源不一致，詳見 openQuestions。

---

## A. 領域物件模型

### A.1 物件總表與 cardinality

| 物件 | 歸屬（cardinality） | 說明 |
|---|---|---|
| `WebhookSubscription` | App 1—N；**app-owned**，不屬於商家 | 一條「topic → 投遞端點」的訂閱。兩種建立途徑：app 設定檔（TOML，裝到所有店一體生效）或 GraphQL `webhookSubscriptionCreate`（逐店）【官方，見 G-1】 |
| Webhook delivery（投遞） | Subscription 1—N | 每次事件對每條匹配訂閱產生一次投遞（含重試序列）；以 `X-Shopify-Webhook-Id` 識別去重【官方 G-2】 |
| Compliance webhook 端點 | App 1—3 | `customers/data_request`／`customers/redact`／`shop/redact`；**不在 GraphQL topic enum 內**，走 app 設定申報【官方 G-5、G-6】 |
| Flow `Workflow` | Shop 1—N | 1 個 trigger ＋ N 條件 ＋ N 動作；**每個 workflow 恰好一個 trigger**【官方 G-9】 |
| Flow `Workflow run` | Workflow 1—N | 一次執行實例；保留 **14 天**後移除【官方 G-11】 |
| Flow trigger/action extension | App 1—N | 第三方 app 以 TOML extension 提供自訂 trigger／action；條件（condition）**不可自訂，只有 Shopify 內建**【官方 G-8、G-10】 |
| 顧客通知範本（customer notification template） | Shop 1—N（每 event 1 範本，另有 locale 變體） | Settings > Notifications > Customer notifications；subject/body 皆 Liquid，可自訂、可還原預設【官方 G-12、G-13】 |
| 員工訂單通知（staff order notification） | Shop 1—N 條規則 | 收件者＝任意 email 或既有 staff；裝 POS 後可**逐地點**建規則【官方 G-14】 |
| `Channel`（銷售管道） | App 1—1（channel capability） | 管道就是 app（`channelCreate` 綁 channel specification 到商家）【官方 G-15；內部 82 §0.1 實測 href 直證】 |
| `Publication` | Channel(App) 1—1..N；Publishable N—M Publication | 發布模型三層 AND：Publishable × Publication × Catalog（`catalogType: APP / COMPANY_LOCATION / MARKET`）【內部 82 §0.2，help 雙源】 |
| `ResourceFeedback` | Channel × Resource | 管道回報商品同步錯誤的官方通道【官方 G-15】 |
| App extension（擴充面） | App 1—N | 全清單見 A.4【官方 G-16】 |

### A.2 `WebhookSubscription` 欄位（GraphQL Admin API，2026-07）【官方 G-3】

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `ID!` | 全域唯一 |
| `topic` | `WebhookSubscriptionTopic!` | 見 A.3 enum 全表 |
| `format` | `WebhookSubscriptionFormat!` | `JSON`／`XML` 兩值（44 號後台實測亦見兩種；⚠ enum 值頁未另抄，據物件頁＋內部實測合證） |
| `uri` | `String!` | 三種端點：HTTPS URL／Google Pub/Sub `pubsub://{project-id}:{topic-id}`／AWS EventBridge ARN |
| `filter` | `String` | 以 API search syntax 子集篩選「哪些資源變更才發」，語法全文見 A.2.1【官方 G-18】；2024-07 版起全 topic 可選配、metaobject 三 topic **必帶**（A.3 要點 4）；我方首發不支援（F.2 D-13） |
| `includeFields` | `[String!]!` | payload 欄位白名單（減量投遞） |
| `metafieldNamespaces` | `[String!]!` | 隨 payload 附帶的 metafield namespace 清單 |
| `apiVersion` | `ApiVersion!` | payload 以哪版 API 序列化 |
| `createdAt` / `updatedAt` | `DateTime!` | — |
| `callbackUrl`／`endpoint` | 已棄用 | 由 `uri` 統一取代 |

Mutations：`webhookSubscriptionCreate(topic!, webhookSubscription!)`、`webhookSubscriptionUpdate(id!, webhookSubscription!)`、delete；Pub/Sub／EventBridge 專用 mutation 已棄用、併入統一版【官方 G-3】。

### A.2.1 `filter` 語法規格（API search syntax 子集，2024-07 版起）【官方 G-18、G-19】

> 前輪標記「語法細節頁 404」＝誤判；本輪 2026-08-14 抓取成功，值域如下。

- **可用範圍**：`2024-07` 版起**所有 topic 皆可選配** filter；唯一「必帶」例外＝metaobject 三 topic（A.3 要點 4）。
- **求值語義**：事件發生後，對**投遞當下的 payload 現值**求值；結果 false ⇒ **靜默抑制**該次投遞（不投遞、不告警、不計失敗）。
- **文法**（基底＝Shopify API search syntax【G-19】，一處關鍵差異：**filter 區分大小寫**，一般 search 不區分【G-18】）：

  | 元素 | 語法 | 例 |
  |---|---|---|
  | 等值 | `field:value`（欄位與值間無空白） | `status:active` |
  | 巢狀欄位 | 點號路徑；**陣列欄位＝任一元素符合即通過** | `variants.price:>=100` |
  | 比較 | `:>`／`:>=`／`:<`／`:<=` | `variants.weight:<5` |
  | 邏輯 | `AND`／`OR`／`()` 分組；連接詞省略時預設 `AND`；**`OR` 優先級高於 `AND`** | `(product_type:Music OR product_type:Movies)` |
  | 否定 | `-` 前綴（後不接空白；與 `NOT` 等價） | `-invalid_field:*` |
  | 萬用 | `*`＝前綴匹配或「欄位存在」檢查 | `variants.title:Album*`、`id:*` |
  | 片語 | 雙引號精確匹配；日期值必須引號＋ISO 格式 | `created_at:>"2026-01-01"` |
  | 跳脫 | 特殊字元 `:`、`\`、`(`、`)` 以反斜線跳脫 | — |

- 🔴 **建立時不擋、投遞時全滅**：filter 引用 payload 不存在的欄位或型別不符 ⇒ 訂閱**照樣建立成功**，但**所有投遞被靜默抑制**——官方明文行為。消費端症狀＝「webhook 完全沒來」，與端點故障不可區分；任何實作 filter 的一方都必須把這條寫進除錯手冊。
- **與 `includeFields` 交互**：兩者同時設定時，filter 引用的欄位**必須**同時出現在 `includeFields` 白名單內。
- **設定途徑**：TOML `[[webhooks.subscriptions]]` 的 `filter` 參數；GraphQL `webhookSubscriptionCreate/Update` 的 `webhookSubscription.filter` input。
- ⚠ filter 字串長度上限與運算式複雜度上限：官方未明文，待實測。（`WebhookSubscriptionTopic` enum 全量抄錄，2026-07，共 218 值）【官方 G-4】

> 下表為 GraphQL enum 原文。TOML／header 用 snake_case 對應形（如 `orders/create`）；**customer 事件家族**的 TOML 形是點號（`customer.tags_added`、`customer.joined_segment`）【官方 G-4a】。

| 家族 | enum 值 |
|---|---|
| app（5） | `APP_PURCHASES_ONE_TIME_UPDATE`, `APP_SCOPES_UPDATE`, `APP_SUBSCRIPTIONS_APPROACHING_CAPPED_AMOUNT`, `APP_SUBSCRIPTIONS_UPDATE`, `APP_UNINSTALLED` |
| audit（1） | `AUDIT_EVENTS_ADMIN_API_ACTIVITY` |
| bulk（1） | `BULK_OPERATIONS_FINISH` |
| carts（2） | `CARTS_CREATE`, `CARTS_UPDATE` |
| channels（1） | `CHANNELS_DELETE` |
| checkouts（3） | `CHECKOUTS_CREATE`, `CHECKOUTS_DELETE`, `CHECKOUTS_UPDATE` |
| collection_listings（3） | `COLLECTION_LISTINGS_ADD`, `COLLECTION_LISTINGS_REMOVE`, `COLLECTION_LISTINGS_UPDATE` |
| collection_publications（3） | `COLLECTION_PUBLICATIONS_CREATE`, `COLLECTION_PUBLICATIONS_DELETE`, `COLLECTION_PUBLICATIONS_UPDATE` |
| collections（3） | `COLLECTIONS_CREATE`, `COLLECTIONS_DELETE`, `COLLECTIONS_UPDATE` |
| companies／B2B（11） | `COMPANIES_CREATE`, `COMPANIES_DELETE`, `COMPANIES_UPDATE`, `COMPANY_CONTACT_ROLES_ASSIGN`, `COMPANY_CONTACT_ROLES_REVOKE`, `COMPANY_CONTACTS_CREATE`, `COMPANY_CONTACTS_DELETE`, `COMPANY_CONTACTS_UPDATE`, `COMPANY_LOCATIONS_CREATE`, `COMPANY_LOCATIONS_DELETE`, `COMPANY_LOCATIONS_UPDATE` |
| customer 事件（8） | `CUSTOMER_ACCOUNT_SETTINGS_UPDATE`, `CUSTOMER_GROUPS_CREATE`, `CUSTOMER_GROUPS_DELETE`, `CUSTOMER_GROUPS_UPDATE`, `CUSTOMER_JOINED_SEGMENT`, `CUSTOMER_LEFT_SEGMENT`, `CUSTOMER_TAGS_ADDED`, `CUSTOMER_TAGS_REMOVED` |
| customer_payment_methods（3） | `CUSTOMER_PAYMENT_METHODS_CREATE`, `CUSTOMER_PAYMENT_METHODS_REVOKE`, `CUSTOMER_PAYMENT_METHODS_UPDATE` |
| customers（10） | `CUSTOMERS_CREATE`, `CUSTOMERS_DELETE`, `CUSTOMERS_DISABLE`, `CUSTOMERS_EMAIL_MARKETING_CONSENT_UPDATE`, `CUSTOMERS_ENABLE`, `CUSTOMERS_MARKETING_CONSENT_UPDATE`, `CUSTOMERS_MERGE`, `CUSTOMERS_PURCHASING_SUMMARY`, `CUSTOMERS_UPDATE`, `CUSTOMERS_WHATS_APP_MARKETING_CONSENT_UPDATE` |
| delivery_promise（1） | `DELIVERY_PROMISE_SETTINGS_UPDATE` |
| discounts（5） | `DISCOUNTS_CREATE`, `DISCOUNTS_DELETE`, `DISCOUNTS_REDEEMCODE_ADDED`, `DISCOUNTS_REDEEMCODE_REMOVED`, `DISCOUNTS_UPDATE` |
| disputes（2） | `DISPUTES_CREATE`, `DISPUTES_UPDATE` |
| domains（3） | `DOMAINS_CREATE`, `DOMAINS_DESTROY`, `DOMAINS_UPDATE` |
| draft_orders（3） | `DRAFT_ORDERS_CREATE`, `DRAFT_ORDERS_DELETE`, `DRAFT_ORDERS_UPDATE` |
| finance（5） | `FINANCE_APP_STAFF_MEMBER_DELETE`, `FINANCE_APP_STAFF_MEMBER_GRANT`, `FINANCE_APP_STAFF_MEMBER_REVOKE`, `FINANCE_APP_STAFF_MEMBER_UPDATE`, `FINANCE_KYC_INFORMATION_UPDATE` |
| fulfillment_events（2） | `FULFILLMENT_EVENTS_CREATE`, `FULFILLMENT_EVENTS_DELETE` |
| fulfillment_holds（2） | `FULFILLMENT_HOLDS_ADDED`, `FULFILLMENT_HOLDS_RELEASED` |
| fulfillment_orders（21） | `FULFILLMENT_ORDERS_CANCELLATION_REQUEST_ACCEPTED`, `..._CANCELLATION_REQUEST_REJECTED`, `..._CANCELLATION_REQUEST_SUBMITTED`, `..._CANCELLED`, `..._FULFILLMENT_REQUEST_ACCEPTED`, `..._FULFILLMENT_REQUEST_REJECTED`, `..._FULFILLMENT_REQUEST_SUBMITTED`, `..._FULFILLMENT_SERVICE_FAILED_TO_COMPLETE`, `..._HOLD_RELEASED`, `..._LINE_ITEMS_PREPARED_FOR_LOCAL_DELIVERY`, `..._LINE_ITEMS_PREPARED_FOR_PICKUP`, `..._MANUALLY_REPORTED_PROGRESS_STOPPED`, `..._MERGED`, `..._MOVED`, `..._ORDER_ROUTING_COMPLETE`, `..._PLACED_ON_HOLD`, `..._PROGRESS_REPORTED`, `..._RESCHEDULED`, `..._SCHEDULED_FULFILLMENT_ORDER_READY`, `..._SPLIT`（前綴 `FULFILLMENT_ORDERS_`） |
| fulfillments（2） | `FULFILLMENTS_CREATE`, `FULFILLMENTS_UPDATE` |
| inventory_items（3） | `INVENTORY_ITEMS_CREATE`, `INVENTORY_ITEMS_DELETE`, `INVENTORY_ITEMS_UPDATE` |
| inventory_levels（3） | `INVENTORY_LEVELS_CONNECT`, `INVENTORY_LEVELS_DISCONNECT`, `INVENTORY_LEVELS_UPDATE` |
| inventory_shipments（8） | `INVENTORY_SHIPMENTS_ADD_ITEMS`, `..._CREATE`, `..._DELETE`, `..._MARK_IN_TRANSIT`, `..._RECEIVE_ITEMS`, `..._REMOVE_ITEMS`, `..._UPDATE_ITEM_QUANTITIES`, `..._UPDATE_TRACKING` |
| inventory_transfers（7） | `INVENTORY_TRANSFERS_ADD_ITEMS`, `..._CANCEL`, `..._COMPLETE`, `..._READY_TO_SHIP`, `..._REMOVE_ITEMS`, `..._UPDATE_ITEM_QUANTITIES`, `..._UPDATED` |
| locales（3） | `LOCALES_CREATE`, `LOCALES_DESTROY`, `LOCALES_UPDATE` |
| locations（5） | `LOCATIONS_ACTIVATE`, `LOCATIONS_CREATE`, `LOCATIONS_DEACTIVATE`, `LOCATIONS_DELETE`, `LOCATIONS_UPDATE` |
| markets（4） | `MARKETS_BACKUP_REGION_UPDATE`, `MARKETS_CREATE`, `MARKETS_DELETE`, `MARKETS_UPDATE` |
| metafield_definitions（3） | `METAFIELD_DEFINITIONS_CREATE`, `METAFIELD_DEFINITIONS_DELETE`, `METAFIELD_DEFINITIONS_UPDATE` |
| metaobjects（3） | `METAOBJECTS_CREATE`, `METAOBJECTS_DELETE`, `METAOBJECTS_UPDATE` |
| order_transactions（1） | `ORDER_TRANSACTIONS_CREATE` |
| orders（11） | `ORDERS_CANCELLED`, `ORDERS_CREATE`, `ORDERS_DELETE`, `ORDERS_EDITED`, `ORDERS_FULFILLED`, `ORDERS_LINK_REQUESTED`, `ORDERS_PAID`, `ORDERS_PARTIALLY_FULFILLED`, `ORDERS_RISK_ASSESSMENT_CHANGED`, `ORDERS_SHOPIFY_PROTECT_ELIGIBILITY_CHANGED`, `ORDERS_UPDATED` |
| payment_schedules／terms（4） | `PAYMENT_SCHEDULES_DUE`, `PAYMENT_TERMS_CREATE`, `PAYMENT_TERMS_DELETE`, `PAYMENT_TERMS_UPDATE` |
| product_feeds（5） | `PRODUCT_FEEDS_CREATE`, `PRODUCT_FEEDS_FULL_SYNC`, `PRODUCT_FEEDS_FULL_SYNC_FINISH`, `PRODUCT_FEEDS_INCREMENTAL_SYNC`, `PRODUCT_FEEDS_UPDATE` |
| product_listings（3） | `PRODUCT_LISTINGS_ADD`, `PRODUCT_LISTINGS_REMOVE`, `PRODUCT_LISTINGS_UPDATE` |
| product_publications（3） | `PRODUCT_PUBLICATIONS_CREATE`, `PRODUCT_PUBLICATIONS_DELETE`, `PRODUCT_PUBLICATIONS_UPDATE` |
| products（3） | `PRODUCTS_CREATE`, `PRODUCTS_DELETE`, `PRODUCTS_UPDATE` |
| profiles（3） | `PROFILES_CREATE`, `PROFILES_DELETE`, `PROFILES_UPDATE` |
| refunds（1） | `REFUNDS_CREATE` |
| returns（8） | `RETURNS_APPROVE`, `RETURNS_CANCEL`, `RETURNS_CLOSE`, `RETURNS_DECLINE`, `RETURNS_PROCESS`, `RETURNS_REOPEN`, `RETURNS_REQUEST`, `RETURNS_UPDATE` |
| reverse（2） | `REVERSE_DELIVERIES_ATTACH_DELIVERABLE`, `REVERSE_FULFILLMENT_ORDERS_DISPOSE` |
| scheduled_product_listings（3） | `SCHEDULED_PRODUCT_LISTINGS_ADD`, `SCHEDULED_PRODUCT_LISTINGS_REMOVE`, `SCHEDULED_PRODUCT_LISTINGS_UPDATE` |
| segments（3） | `SEGMENTS_CREATE`, `SEGMENTS_DELETE`, `SEGMENTS_UPDATE` |
| selling_plan_groups（3） | `SELLING_PLAN_GROUPS_CREATE`, `SELLING_PLAN_GROUPS_DELETE`, `SELLING_PLAN_GROUPS_UPDATE` |
| shipping_addresses（2） | `SHIPPING_ADDRESSES_CREATE`, `SHIPPING_ADDRESSES_UPDATE` |
| shop（1） | `SHOP_UPDATE` |
| subscription（15） | `SUBSCRIPTION_BILLING_ATTEMPTS_CHALLENGED`, `..._FAILURE`, `..._SUCCESS`；`SUBSCRIPTION_BILLING_CYCLE_EDITS_CREATE/DELETE/UPDATE`；`SUBSCRIPTION_BILLING_CYCLES_SKIP/UNSKIP`；`SUBSCRIPTION_CONTRACTS_ACTIVATE/CANCEL/CREATE/EXPIRE/FAIL/PAUSE/UPDATE` |
| tax_services（2） | `TAX_SERVICES_CREATE`, `TAX_SERVICES_UPDATE` |
| tender_transactions（1） | `TENDER_TRANSACTIONS_CREATE` |
| themes（4） | `THEMES_CREATE`, `THEMES_DELETE`, `THEMES_PUBLISH`, `THEMES_UPDATE` |
| variants（2） | `VARIANTS_IN_STOCK`, `VARIANTS_OUT_OF_STOCK` |

四個要點：
1. 🔴 **合規三 topic（`customers/data_request`、`customers/redact`、`shop/redact`）不在此 enum**——只能經 app 設定（TOML／Partner Dashboard）申報端點，不可用 `webhookSubscriptionCreate` 訂閱【官方 G-4、G-5 交叉】。
2. ⚠ 同日兩次取證有出入：TOML 參考頁的擷取曾出現 `variants/create|update|delete`、`returns/create`、`subscription_contracts/resumed`、`metafields/*`，但 enum 頁（本表依據）**沒有**這些值、卻有 `VARIANTS_IN_STOCK/OUT_OF_STOCK`、`RETURNS_APPROVE` 等。以 enum 頁為準；差異列 openQuestions。
3. App Store 上架 app **必須**訂閱合規三 topic，否則審核直接退【官方 G-5】。
4. 🔴 **metaobject 三 topic（`METAOBJECTS_CREATE/UPDATE/DELETE`）自 2024-07 版起訂閱必帶 `filter`**，固定形＝`type:{metaobject 定義 type}`；多個 type 用 `OR` 明列（`type:banana OR type:apple`）；**禁用 `type:*` 萬用**【官方 G-18】。⇒ 對這三個 topic，filter 不是選配而是訂閱模型的必要欄位（與 15 章 E.1 交叉）；我方處置見 F.2 D-13。

### A.4 App 擴充面全清單（對應我方外掛架構）【官方 G-16】

| 擴充面 | 跑在哪 | 一句話 |
|---|---|---|
| Admin action / Admin block / Admin link | admin 資源頁 | modal 動作／資源頁卡片／跳轉連結 |
| Checkout UI extension | 結帳流程定義掛點 | 結帳客製 UI |
| Post-purchase extension | 結帳完成後 | 加購頁（需 Shopify 核准才可用） |
| Customer account UI extension | 顧客帳戶區 | 帳戶頁掛點 |
| Theme app extension | Online Store 2.0 主題 | 取代 Script Tag 的正規注入 |
| Web pixel | 前台 sandbox | 行為數據收集 JS |
| Shopify Functions | 平台內 Wasm | 見下表 |
| Flow trigger / Flow action | Shopify Flow | 自動化事件源／動作 |
| POS UI extension | POS app | POS 客製掛點 |

Functions API 家族（各 API 一個客製點；runtime＝WebAssembly，官方建議 Rust 以免大購物車超時）【官方 G-17】：Discount／Payments（隱藏付款方式）／Delivery options／Cart & Checkout validation／Location rule（出貨地點選擇）／Bundles／Fulfillment constraints／Local pickup options／Local pickup charges／Pickup points。⚠ 指令數與 payload 上限數字在總覽頁未載明。

---

## B. 狀態機

### B.1 Webhook 投遞（單一事件 × 單一訂閱）

狀態全集：`pending`（已產生待投）→ `delivering` → `succeeded` ／ `retrying` → `abandoned`。

| 現態 | 觸發 | 前置條件 | 次態 | 副作用 |
|---|---|---|---|---|
| pending | 事件發生、匹配訂閱（含 `filter` 通過——對投遞當下 payload 現值求值，A.2.1） | 訂閱存在 | delivering | POST 到 `uri`，connect timeout **1s**、總 timeout **5s**【官方 G-2】 |
| delivering | 收到 2xx | — | succeeded | 終態 |
| delivering | 非 2xx（**3xx 也算失敗**）／timeout／無回應 | — | retrying | 排入重試【官方 G-2】 |
| retrying | 重試（共 **8 次／約 4 小時**） | 重試次數未滿 | delivering | 指數間隔【官方 G-2】 |
| retrying | 8 次耗盡 | — | abandoned | 該事件放棄；**寄警告信到 app 的 emergency developer email**【官方 G-2】 |

孤兒檢查：無。abandoned 為終態；補救靠消費端 reconciliation（C.3）。

### B.2 WebhookSubscription 生命週期

| 現態 | 觸發 | 次態 | 副作用 |
|---|---|---|---|
| active | `webhookSubscriptionUpdate` | active | 原子改 uri／filter／includeFields／metafieldNamespaces【官方 G-3】 |
| active | 持續投遞失敗（**Admin API 建立的訂閱**） | deleted | **自動刪除**；先寄警告信【官方 G-2】 |
| active | `webhookSubscriptionDelete`／app 解除安裝 | deleted | — |

- TOML 設定檔宣告的訂閱不走自動刪除（文檔只對 API 建立者宣告刪除）；⚠ 設定檔訂閱失敗後的確切處置官方未寫明。
- 🔴 本尊**沒有 `disabled` 中間態**——失敗直接刪訂閱。我方裁定不同（見 F.2 D-3）。

### B.3 Flow workflow run【官方 G-11】

狀態全集（help 明文）：`In progress`（執行中或重試中）／`Waiting`（Wait 步驟延時中）／`Rate limited`（資源占用過高被節流）／`Canceled`（完成前被停止）／`Completed`（結束）。

| 現態 | 觸發 | 次態 | 副作用 |
|---|---|---|---|
| （事件） | trigger 命中且 workflow 開啟 | In progress | 建 run，快照 trigger 資料 |
| In progress | 遇 Wait 動作 | Waiting | 到時回 In progress |
| In progress | 資源超限 | Rate limited | 後續 run 被限速，緩解後續跑 |
| In progress／Waiting | 人工停止 | Canceled | 終態 |
| In progress | 全部步驟走完（含 Fail workflow run 動作） | Completed | 終態；結果再分類：Succeeded with actions／Succeeded without actions／Failed（監控頁的篩選值域）【官方 G-11a】 |
| In progress | 動作遇 **transient error** | In progress | 重試直到成功或 timeout【官方 G-11b】 |
| In progress | 動作遇 **permanent error** | Completed(Failed) | 不重試【官方 G-11b】 |

終態 run 保留 **14 天**後移除【官方 G-11】。孤兒檢查：Rate limited 非終態（資源釋放後恢復）；Waiting 由排程喚醒——皆有出路。

### B.4 顧客通知範本

狀態全集：`default`（未改）／`customized`（已改 subject/body）／`deactivated`（僅限可關閉範本）。

| 現態 | 觸發 | 前置條件 | 次態 |
|---|---|---|---|
| default | 編輯範本（Liquid） | 已驗證寄件 email【官方 G-13a】 | customized |
| customized | 「還原預設」 | — | default |
| default/customized | 停用 | 該範本屬**可停用清單**（C.5） | deactivated |
| deactivated | 重新啟用 | — | 回原態 |

不可停用的範本沒有 deactivated 態（開關不存在／灰化）。

---

## C. 業務規則與不變量

### C.1 投遞語義（消費端設計的三條地基）【官方 G-1、G-2、G-7】

1. **At-least-once ＋ 會重複**：同一事件可能收到多次；用 `X-Shopify-Webhook-Id` 去重。
2. **順序完全不保證**：「同 topic 之內」與「同資源跨 topic」都不保序——官方例子：`products/update` 可能先於 `products/create` 到達。排序靠 `X-Shopify-Triggered-At` header 或 payload 的 `updated_at`，消費端做 last-write-wins 或版本比較。
3. **投遞不保證送達**：官方明文 app「不應依賴 webhook 作為唯一資料來源」，必須配 **reconciliation job** 週期性以 `updated_at` 過濾條件拉取近期變更對帳。⇒ webhook 是加速器，不是資料真相。

### C.2 驗證與安全【官方 G-2】

- HMAC 公式：`base64( HMAC-SHA256( raw_request_body, app_client_secret ) )`，與 `X-Shopify-Hmac-Sha256` 用 **timing-safe compare**；🔴 必須在任何 body-parsing middleware 之前抓 raw body。
- 已確認 headers：`X-Shopify-Topic`、`X-Shopify-Hmac-Sha256`、`X-Shopify-Webhook-Id`、`X-Shopify-Triggered-At`；⚠ `X-Shopify-Shop-Domain`／`X-Shopify-API-Version` 為投遞結構標準欄，本輪未逐字重驗。
- 驗簽失敗一律拒收；成功要在 **5 秒內回 2xx**——**順序＝先持久化（DB-backed inbox/queue 落庫）再回 2xx**：ack 與落庫之間崩潰＝已確認事件永久遺失；與本章併發節及總綱不變量一致。超載時寧可超時讓對端重試（`(shop_id, webhook_id)` 唯一鍵冪等去重兜底，同 C.6 （2026-08-17 更正，PR #52 第 10 輪））<!-- 2026-08-17 更正（PR #52 第 5 輪） -->：原括號「先 ack 再入 queue」順序相反。

### C.3 上限值與數字總表

| 項目 | 值 | 來源 |
|---|---|---|
| 連線 timeout | 1s（已落 `outbound_http.webhook_connect_timeout_seconds`，第 20 輪） | G-2 |
| 回應 timeout | 5s（已落 `outbound_http.webhook_response_timeout_seconds`，第 20 輪） | G-2 |
| 重試 | 8 次／約 4 小時，指數退避 | G-2 |
| 成功判定 | 僅 2xx；3xx＝失敗 | G-2 |
| 失敗告警 | 8 連敗寄 emergency developer email；API 建立的訂閱其後自動刪除 | G-2 |
| Flow trigger payload | **< 50KB**（超過回 validation error `Properties size exceeds the limit of 50000 bytes`） | G-10 |
| Flow For-each 清單 | **> 1,000 項 ⇒ run 失敗**，迴圈後動作全不執行 | G-11c |
| Flow run 保留 | 14 天 | G-11 |
| Flow workflow trigger 數 | 恰 1 | G-9 |
| 合規：`shop/redact` 時點 | 解除安裝後 **48 小時** | G-5 |
| 合規：`customers/redact` 時點 | 顧客 6 個月內無訂單⇒請求後 **10 天**發；有近期訂單⇒滿 **6 個月**才發 | G-5 |
| 合規：處置期限 | 收到後 **30 天**內完成（法定留存義務可豁免刪除） | G-5 |
| Publication 批次 | `publicationCreate/Update` 單次 ≤ **50** products | 內部 82 §0.2（help 源） |
| Flow 可用性 | 任何付費方案；**自建 custom app 的 Flow extension 僅 Plus** | G-8 |

（落地時全部進 `config/limits.yml`，出處欄照抄本表 URL——鐵律 6。）

### C.4 Flow 模型規則【官方 G-8～G-11】

- **Trigger**：事件型（店內或 app 事件）與 **Scheduled time**（一次性或每小時／日／週／月循環；因 trigger 本身不帶資料，**必須配 Get data 動作**）。Trigger 決定整條 workflow 可用的資料環境、條件與動作（例：Customer created 拿不到 shipping method）。
- **Condition**：只有 Shopify 內建，app 不可自訂；資料不匹配（動作需要 trigger 沒有的資源）＝建立時即擋或 run 失敗。
- **Action**：內建三類（store 操作／通訊 email·Slack／進階：Get data、Count/Sum 聚合、For-each、Send HTTP request、Wait、Fail workflow run）＋ app 提供的 action。變數插值 `{{ }}`＋GraphQL dot notation。
- **自訂 trigger 發火**：app 呼叫 GraphQL mutation **`flowTriggerReceive(handle, payload)`**；handle kebab-case（如 `auction-bid-placed`）；payload 欄位型別在 TOML `[[settings.fields]]` 宣告（如 `number_decimal`、`customer_reference`）；命名慣例「受詞＋過去式動詞」。
- **錯誤分級**：transient（重試到成功或 timeout）vs permanent（不重試）——與我方 Solid Queue `retry_on 明列` 規約同構。
- ⚠ **per-resource 定序**：官方文檔查無「Flow 對同資源事件保序」的任何承諾；連 webhook 層都明文不保序，應假設 Flow 亦然（openQuestions）。

### C.5 通知規則【官方 G-12、G-13、G-14】

- 顧客通知大多**自動寄送且不可停用**；官方明文可停用的訂單動作通知：**Order canceled、Order refund、Shipping confirmation、Shipping update、Out for delivery、Delivered**；當地配送另有獨立確認信與獨立停用規則。⇒「可停用」是白名單不是預設——與內部 18-F2.1 的裁定同向。
- 編輯範本前**必須先驗證寄件 email**；範本 subject/body 用 Liquid 變數。
- **Shop app 的追蹤通知商家不可停用也不可編輯**（它是管道 app 自己的通知面）。
- 員工通知：店主預設收所有新訂單；加收件者兩途（任意 email／既有 staff）；設定需 **Orders ＋ Manage settings** 權限；裝 POS 後可逐地點建規則（或 All）；種類值域：Store order summary（日／週）、New orders、New return requests、New draft orders（僅店主）、Sales attribution changes。⚠ 收件者數量上限官方未載明。
- 內部補充【內部 18-F2.1／44 實測】：後台顧客通知共 **45+ 範本、12 分組**；官方 help 無機器可讀的完整 event 清單——我方 `event_key` 為自定。

### C.6 併發與邊界要害

- 消費端「先 200 再處理」⇒ ack 與處理之間 crash 會丟事件：ack 前必須先把事件**持久化入 queue**（DB-backed），否則 at-least-once 在消費端被降級成 at-most-once。
- 去重表要有 TTL 與唯一索引（**`(shop_id, webhook_id)` unique**——inbox 是租戶業務資料，鐵律 2；查重帶已解析租戶 （2026-08-17 更正，PR #52 第 9 輪））；並發雙投同時 INSERT 靠唯一索引裁決。
- 亂序＋去重並存的陷阱：`products/delete` 先到、`products/update` 後到 ⇒ 消費端要能容忍「更新一個已刪資源」（tombstone 或 upsert-with-deleted-check）。
- 金額欄位：webhook payload 中的金額是序列化層產物（MoneyV2／字串），**消費與生產兩側都不得把它當儲存值**（鐵律 3：儲存尺度≠對外單位）。

---

## D. 關鍵流程

### D.1 訂閱建立（操作者：app 開發者）

1. 途徑 A：TOML 設定檔宣告 topics＋uri → 部署後對**所有安裝店**生效【官方 G-1】。途徑 B：`webhookSubscriptionCreate`（逐店、可帶 filter/includeFields）。
2. 系統驗證 uri 形態（HTTPS／pubsub://／ARN）。失敗分支：格式錯 → userErrors。🔴 形態驗證只擋語法——目的地是 app 控制的出站端點，**每次投遞連線另過 SSRF 政策**（C.3「3xx 算失敗且禁 follow redirect」的完整化 （2026-08-17 更正，PR #52 第 18 輪））：scheme/port 白名單、DNS 解析後**與連線時**雙重拒 private/link-local/metadata 位址（rebinding 防護＝連線 pin 已驗 IP——註冊時通過的 hostname 事後可改指內網）、禁 redirect、回應大小上限＝`outbound_http.webhook_response_bytes_max`、逾時＝`outbound_http.webhook_connect_timeout_seconds`／`webhook_response_timeout_seconds`（config/limits.yml，鐵律 6——三條出站契約共用鍵組，第 19 輪落鍵；第 21 輪補逾時鍵，與 09:53／12 §C.7 副本形態一致）。
3. App Store app 另須申報合規三端點，缺 → 審核退件【官方 G-5】。

### D.2 事件投遞（操作者：平台）

1. 資源變更 commit → 產生事件（帶 `X-Shopify-Triggered-At`）。
2. 匹配訂閱（topic ＋ filter）→ 逐訂閱投遞：POST，connect 1s／total 5s。
3. 2xx → 完結。非 2xx／timeout → 進重試序列（8 次／4h）。
4. 耗盡 → 放棄該事件＋寄警告信；API 建立的訂閱在持續失敗後**自動刪除**。
5. 失敗分支之外的安全網：消費端 reconciliation（D.3 步驟 5）。

### D.3 消費端標準流程（操作者：訂閱方 app／我方文件要教的）

1. 抓 raw body → 驗 HMAC（timing-safe）→ 失敗 401 結束。
2. **原子落庫**：payload 持久化入 DB-backed inbox/queue，**與 `(shop_id, webhook_id)` 去重鍵同一寫入**（INSERT 唯一索引；duplicate ⇒ 已落庫，直接 200）——去重「只查不寫」失去 X-27 唯一索引裁決；「先寫標記、200 前崩潰」則 retry 被丟（2026-08-17 更正，PR #52 第 12 輪）：原步 2/3 分離、去重鍵寫入時點未定。
3. **回 200（5 秒內）**——落庫成功後才回。
4. 背景處理：需要現值時回查 API（payload 可能已陳舊——eventual consistency）。
5. 週期 reconciliation job：以 `updated_at` 窗口拉取變更補漏【官方 G-7】。

### D.4 合規三流程（操作者：平台×app）【官方 G-5】

- `customers/data_request`：顧客請求查看資料 → payload 帶 shop_id/shop_domain/customer{id,email,phone}/orders_requested/data_request.id → app 30 天內提供資料給商家。
- `customers/redact`：商家請求刪除顧客資料 → 依 10 天／6 個月規則發出 → app 30 天內刪除（法定留存豁免）。
- `shop/redact`：解除安裝 48h 後發出（僅 shop_id/shop_domain）→ 刪店級資料。
- 全部要求 2xx ack；未申報或不回應 → app 審核拒絕。

### D.5 Flow 執行（操作者：商家配置、平台執行）

1. 事件發生（或 `flowTriggerReceive` 被 app 呼叫、或排程到時、或手動執行）→ 對每條開啟的 workflow 建 run。
2. 依序評估條件 → 不滿足 ⇒ Completed（Succeeded without actions）。
3. 滿足 ⇒ 執行動作（可並行或依序；Wait 轉 Waiting；For-each >1,000 項即 Fail）。
4. 動作錯誤：transient 重試至 timeout；permanent 直接 Fail。
5. run 記錄 14 天內可查（篩選：狀態／workflow／動作／錯誤／時間／trigger 型別／重試態／run ID／tags）。

### D.6 顧客通知寄送（操作者：平台）

1. 業務事件（下單／出貨／退款⋯）→ 找該 event 的範本（自訂版或預設版）。
2. 檢查停用態：可停用範本且已停用 ⇒ 跳過；不可停用 ⇒ 必寄。
3. Liquid 渲染 subject＋body → 寄送（email；部分場景 SMS）。
4. Shop app 安裝時：Shop 自己的追蹤通知獨立於商家範本。

### D.7 管道接入與發布（操作者：管道 app）

1. app 安裝 → OAuth → 帳號連接 onboarding（可含審核制）【官方 G-15】。
2. `channelCreate` 綁 channel specification（宣告地區／語言／幣別行為／feed 管理）→ 建立 Publication。
3. 商品可見性＝三層 AND：發布到該 Publication ＋ 商品在管道 market 掛的 Catalog 內 ＋ 資源本身可發布（Active 等）；預設**既有商品自動可用**【內部 82 §0.2】。
4. 同步失敗 → 寫 `ResourceFeedback` 回報商家。
5. 管道結帳：cart permalink 或 Buy SDK（Storefront API），付款仍在 Shopify checkout【官方 G-15】。

---

## E. 跨模組耦合

### E.1 topic ↔ 我方模組對映（依 A.3 家族）

| 事件族 | 生產者（我方模組） | 平台內建消費者 |
|---|---|---|
| products/collections/variants | 商品模組（specs/12 族） | feed 增量＋IndexNow（研究 30）、管道 Publication 同步 |
| orders/draft_orders/order_transactions/refunds/returns | 訂單模組（specs/16 族） | 通知信、分析 rollup、`einvoice/*` 內部 topic（jurisdiction pack）、Simprosys 餵送 |
| inventory_* | 庫存模組 | 低庫存告警、`VARIANTS_IN_STOCK/OUT_OF_STOCK` 類事件 |
| customers/customer_* | 顧客模組（15 族） | segment 重算、行銷同意稽核 |
| fulfillment_* | 履約模組 | 出貨通知（Shipping confirmation 等六範本）、取貨通知 |
| checkouts/carts | 結帳模組 | 棄單挽回（站外再行銷分組） |
| app/channels/themes/domains/locales/markets | 平台層 | 管道解除清理（`channels/delete`）、主題發布快取失效 |

### E.2 依賴方向

- **Outbox（18-F1）是唯一事件源**：對外 webhooks、通知信、Flow 型自動化、rollup 全部掛在 outbox 消費側；業務模組只負責「與業務同 transaction 寫 outbox」，不直接呼叫任何通知/投遞（鐵律 5：transaction 內禁外部 IO）。
- 通知信渲染依賴 **outbox payload 凍結的事件時點欄位**（品項/金額/收件人/tracking——D.6／總綱 A1）；訂單/履約/顧客**現值只用於顯式動態 guard**（退訂抑制、取消判定）。（2026-08-17 更正，PR #52 第 19 輪）：原「渲染時回查現值、不信 payload 快照」與 A1 第 18 輪凍結規則逐字互斥——延遲 job 下回查現值會把第二批出貨的 tracking 寫進第一封信、把寄送前的訂單編輯寫進成單確認。
- 管道（channel=app）依賴 Publication/Catalog（商品域）＋ webhook（同步）＋ ResourceFeedback（回報）；方向是管道消費商品域，商品域不知道管道。
- 合規事件依賴 jurisdiction pack：本尊的 GDPR 三 topic 在我方對應「隱私法 per-jurisdiction」（HK PDPO／TW 個資法／GDPR），核心只發事件、pack 決定落地動作（鐵律 11）。

---

## F. 落地對應

### F.1 對應倉庫文件

| 本章節 | 倉庫既有 |
|---|---|
| A.2/B.1/B.2/C.1–C.3/D.1–D.3 | `docs/specs/18` F4（對外 webhooks）、F1（outbox）；`docs/research/28` §15（契約） |
| C.5/D.6 | `docs/specs/18` F2/F2.1（通知管線＋toggleable 白名單）、F3（送達性） |
| C.4/D.5（Flow） | **無對應 spec**——自動化（Flow 等價物）目前不在 M1–M4 範圍，見 D-8 |
| A.1 管道／D.7 | `docs/research/82`（channels teardown）、`docs/research/43` §6（三端對接） |
| A.4 擴充面 | `docs/research/43`（生態）；外掛架構 spec 待立 |
| D.4 合規 | 鐵律 11 jurisdiction pack；`docs/specs/15` 隱私相關節 |

### F.2 本尊 vs 我方裁定差異清單

| # | 本尊 | 我方裁定 | 依據 |
|---|---|---|---|
| D-1 | payload 金額＝序列化字串（MoneyV2 等） | 內部全程 integer cents，**只在序列化層**轉 MoneyV2/MoneyBag；webhook payload 屬序列化層，絕不外洩 `*_cents` | 鐵律 3、specs/65 |
| D-2 | `format`＝JSON／XML 兩種 | 只做 JSON；XML 登記 H-117 屬 P2，明文「已知差異不實作」 | 28 §15 |
| D-3 | 持續失敗 ⇒ **自動刪除**訂閱（API 建立者） | 24h 持續失敗 ⇒ `disabled` ＋通知商家＋後台可重啟（不刪資料） | 18-F4；差異：本尊無 disabled 態（B.2） |
| D-4 | headers `X-Shopify-*` | `X-CL-*`（Topic/Event-Id/Webhook-Id/Hmac-Sha256/Shop-Domain/Triggered-At/API-Version） | 28 §15；不用本尊命名（鐵律 9） |
| D-5 | topic 218 個（enum 全表） | 首發 **24 個** ＋ 3 個內部 `einvoice/*`（不對外開放訂閱，發票 payload 含統編敏感欄位） | 28 §15；本表＝日後擴充的靶 |
| D-6 | 合規三 topic＝GDPR 硬編 | 隱私事件走 jurisdiction pack（HK PDPO 基準；GDPR/TW 為 pack） | 鐵律 11 |
| D-7 | 通知可停用清單：六個訂單動作通知（C.5） | `toggleable` 種子白名單四分組（當地配送/運送更新/雙重確認/Shop 再行銷），API 不可改 toggleable | 18-F2.1；⚠ 兩清單粒度不同——本尊以「範本」為單位、我方以「分組」，落地時以官方六範本校準白名單內容 |
| D-8 | Shopify Flow（付費方案內建；extension 生態） | **無 Flow 等價物排program**；outbox topic 架構已預留（消費者可插拔）；若日後做，run 狀態機照 B.3、payload 上限照 C.3 | 18-F1；P2 待議 |
| D-9 | 訂閱歸 app（app-owned） | 首發 webhook 訂閱歸**商家**（後台通知 IA 下建立，`clat_` token 生態未開放前無第三方 app） | 28 §15；44 實測本尊後台也有商家級 webhook 入口，兩形態並存 |
| D-10 | 重試 8 次／4h、connect 1s／total 5s、僅 2xx 成功 | **照抄本尊數值**（18-F4 原「8 次/約 4 小時」與本尊一致；demo 3 次為過渡）；3xx 算失敗＋禁 redirect 同時服務 SSRF 防護 | 18-F4＋G-2 |
| D-11 | reconciliation 由訂閱方自理 | 平台文件（消費端指南）必須明寫：驗 HMAC→**原子落庫（payload 與去重鍵同一寫入；duplicate ⇒ 直接 200）**→回 200→自 inbox 回查現值→對帳 job（舊序「去重→200→處理」在 200 後崩潰時 retry 被去重丟棄（2026-08-17 更正，PR #52 第 11 輪）） | 18-F4 第 4 點擴充 |
| D-12 | 管道＝app、發布三層 AND | 同構落地：`App` 下掛 `Channel` capability、Publication/Catalog 四掛載點 | 82 §0.1/§0.2（R13-V2/V4） |
| D-13 | `filter`：2024-07 起全 topic 可選配（search syntax 子集，A.2.1）；metaobject 三 topic **必帶** | **首發不支援 `filter`**（本輪補訂，非既有裁定的推翻而是其自然推論）：①28 §15 現行 `webhookSubscriptionCreate(topic, callbackUrl, format)` 簽名本就無 filter 參數，schema 不曝露此欄位（未知 input 欄位＝GraphQL 層驗證錯誤）；②metaobject 三 topic 不在首發 24 topic 內（D-5），「必帶 filter」的訂閱形態隨之**整體遞延**——遞延解除的前置條件＝metaobject topic 開放時 filter 必須同時落地（否則違反本尊必要欄位語義）；③日後開放 filter 時文法照 A.2.1 官方子集，不自創方言；「invalid field ⇒ 建立成功但投遞全抑制」的本尊語義屆時要麼照抄、要麼明文登記差異 | 28 §15＋G-18；本表即裁定登記處 |

### F.3 開發驗收要點（併入 18 號驗收節）

1. **at-least-once×亂序矩陣測試**：同事件雙投（Webhook-Id 相同）只處理一次；`update` 先於 `create`、`delete` 先於 `update` 到達不炸、終態正確。
2. **重試狀態機**：mock 端點回 500/301/timeout 各驗「3xx＝失敗」「8 次後 abandoned＋告警」「24h 失敗→disabled→後台重啟」全鏈路可觀測。
3. **HMAC**：raw body 驗簽（改一 byte 即拒）、timing-safe、middleware 先 parse 的回歸測試。
4. **SSRF 測試集**照 18-F4（私網/rebinding/redirect）。
5. **金額出口**：webhook payload 任何金額欄位斷言為序列化型別（無 `_cents` 外洩）；JPY/TWD/KRW fixture 進矩陣（鐵律 3）。
6. **通知 toggleable**：對不可停用範本呼叫停用 API 必回 userErrors；前端灰化＋tooltip；六個官方可停用範本與白名單比對一致。
7. **合規事件**：pack 介面測「HK＝PDPO 動作、TW＝個資法動作」，時點參數（48h/10 天/6 個月/30 天）進 `config/limits.yml` 可調。
8. **outbox 地基**：kill -9 worker 零丟失；事件必在業務 transaction 內寫入（code review 死盯項）。
9. **filter 邊界（D-13）**：首發 `webhookSubscriptionCreate` input schema 無 `filter` 欄位——測試釘住（傳入即 GraphQL 驗證錯誤），防止未經裁定誤加；可訂閱 topic 值域測試斷言不含 `metaobjects/*`；D-13 的遞延前置條件（metaobject topic ⇔ filter 同時落地）寫進 18 號驗收清單備註。

---

## G. 來源

| # | URL | 取證 |
|---|---|---|
| G-1 | https://shopify.dev/docs/apps/build/webhooks | 2026-08-14 |
| G-2 | https://shopify.dev/docs/apps/build/webhooks/subscribe/https | 2026-08-14 |
| G-3 | https://shopify.dev/docs/api/admin-graphql/latest/objects/WebhookSubscription | 2026-08-14 |
| G-4 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic（enum 全表） | 2026-08-14 |
| G-4a | https://shopify.dev/docs/api/webhooks?reference=toml（TOML topic 形；與 enum 有出入處以 enum 為準） | 2026-08-14 |
| G-5 | https://shopify.dev/docs/apps/build/privacy-law-compliance | 2026-08-14 |
| G-7 | https://shopify.dev/docs/apps/build/webhooks/best-practices（at-least-once／不保序／reconciliation） | 2026-08-14 |
| G-8 | https://shopify.dev/docs/apps/build/flow（trigger/condition/action；Plus 限制） | 2026-08-14 |
| G-9 | https://help.shopify.com/en/manual/shopify-flow/getting-started/understanding-triggers | 2026-08-14 |
| G-10 | https://shopify.dev/docs/apps/build/flow/triggers/create（flowTriggerReceive、50KB） | 2026-08-14 |
| G-11 | https://help.shopify.com/en/manual/shopify-flow/manage/monitor（run 狀態、14 天） | 2026-08-14 |
| G-11a | https://help.shopify.com/en/manual/shopify-flow/manage/monitor（篩選值域，經 WebSearch 摘要） | 2026-08-14 |
| G-11b | https://help.shopify.com/en/manual/shopify-flow/create/troubleshoot（transient/permanent，經 WebSearch 摘要） | 2026-08-14 |
| G-11c | https://help.shopify.com/en/manual/shopify-flow/reference/actions/for-each（1,000 上限，經 WebSearch 摘要） | 2026-08-14 |
| G-12 | https://help.shopify.com/en/manual/fulfillment/setup/notifications/customer-notifications | 2026-08-14 |
| G-13 | https://help.shopify.com/en/manual/fulfillment/setup/notifications | 2026-08-14 |
| G-13a | https://help.shopify.com/en/manual/fulfillment/setup/notifications/customizing-notification-template（寄件 email 驗證，經 WebSearch 摘要） | 2026-08-14 |
| G-14 | https://help.shopify.com/en/manual/orders/notifications/order-notifications | 2026-08-14 |
| G-15 | https://shopify.dev/docs/apps/build/sales-channels | 2026-08-14 |
| G-16 | https://shopify.dev/docs/apps/build/app-extensions/list-of-app-extensions | 2026-08-14 |
| G-17 | https://shopify.dev/docs/apps/build/functions | 2026-08-14 |
| G-18 | https://shopify.dev/docs/apps/build/webhooks/customize/filters（filter 語法／metaobject 三 topic 必帶／invalid-field 靜默抑制／includeFields 交互；前輪誤判 404，本輪抓取成功） | 2026-08-14 |
| G-19 | https://shopify.dev/docs/api/usage/search-syntax（search syntax 基底文法：連接詞優先級、跳脫字元、萬用、片語） | 2026-08-14 |
| 內部 | `docs/specs/18-spec-messaging-events-webhooks.md`、`docs/research/28-api-contract.md` §15、`docs/research/82-admin-channels.md` §0 | 2026-08-14 讀取 |
