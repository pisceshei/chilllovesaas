# 28 — 全項目 API 契約（服務端 ↔ 商家端 ↔ 前台）

> **D5 決策落地文件**：整個項目 API 化——admin React SPA 與服務端之間**只走 GraphQL Admin API**（1:1 仿 Shopify 慣例）；買家前台走 **Liquid SSR＋Ajax/Section Rendering HTTP 面**（25 §5）；事件出口走 **Webhooks**。本文＝三個面的完整契約：§0 慣例（照抄 Shopify 工程慣例，經官方文檔查證）→ §1–14 逐模組操作表 → §15 webhooks → §16 前台面 → §17 三端對接矩陣。欄位級細節在 specs 12–19 與 22 號按鈕表；本文是「有哪些介面、輸入輸出什麼、遵守什麼規則」的單一真相。

## 0. API 慣例（1:1 仿 Shopify，來源：shopify.dev 版本/認證/GID/分頁/限流/bulk/webhooks 章）

### 0.1 端點與版本
- Admin GraphQL：`POST /admin/api/{version}/graphql.json`，version＝日期制 `YYYY-MM`（首版 `2026-08`）。回應 header `X-CL-API-Version` 標實際服務版本（fall-forward 語義佔位）。schema 演進用 `@deprecated(reason:)`。
- demo 期單版本；版本窗口目標（12 個月支援、9 個月重疊）寫入規格待商業化執行。

### 0.2 認證與授權
- **Admin SPA**：登入 → session cookie＋CSRF（同源 BFF 模式）；**API token**（機器整合）：`clat_` 前綴長效 token，header `X-CL-Access-Token`。（Session-token JWT 交換為 v2。）
- **Scopes**：`read_{resource}/write_{resource}` 成對蛇形複數，逗號字串。首發 10 對：products, orders, customers, inventory, fulfillments, discounts, themes, content, markets, translations（＋`read_analytics`、`read/write_settings`）。staff 角色（12 號 spec）映射為 scope 集合。
- 受保護資源（60 天訂單窗口、payment methods）：規格佔位，demo 不啟用。

### 0.3 GraphQL 核心慣例（全部照抄）
- **GID**：`gid://chilllove/{Type}/{id}`；主要物件實作 `Node`，支援 `node(id:)/nodes(ids:)`；物件帶 `legacyResourceId`。
- **分頁**：connection `first/after/last/before`＋`pageInfo{hasNextPage,hasPreviousPage,startCursor,endCursor}`；**每頁上限 250**；優先查 `nodes` 而非 `edges`；cursor＝base64(排序鍵+id) 不透明。
- **Mutation**：命名 `resourceVerb`（productCreate/orderCancel）；input object `{Mutation}Input`；payload＝`{ resource, userErrors: [{field: [String], message: String!, code: Enum}] }`——**業務錯誤走 userErrors（HTTP 200）**，top-level errors 只承載 syntax/THROTTLED/ACCESS_DENIED/INTERNAL（附 requestId）。**一開始就上 typed code enum**。宣告式 upsert 用 `*Set`（metafieldsSet/productSet）。
- **標量**：`DateTime`（ISO8601 UTC）、`Date`、`Decimal`（字串）、`URL`、`HTML`、`JSON`；金額一律 **`MoneyV2{amount: Decimal, currencyCode}`**，多幣雙記 **`MoneyBag{shopMoney, presentmentMoney}`**（29 §3）。內部儲存仍 integer cents，序列化層轉 Decimal 字串。
- **陣列型 input 上限 250**。

### 0.4 限流（cost 制）
- 計費：object=1、scalar=0、connection=按 first 計、mutation 基礎=10；**單請求上限 1,000 points**（超過 `MAX_COST_EXCEEDED`）。
- Leaky bucket：預扣 requestedQueryCost、結算 actualQueryCost 退差額；demo 全店統一 **bucket 2,000 / restore 100 points/s**。
- 節流回應：HTTP 200＋`errors[0].extensions.code="THROTTLED"`；每個回應附 `extensions.cost{requestedQueryCost, actualQueryCost, throttleStatus{maximumAvailable, currentlyAvailable, restoreRate}}`——**前端 SDK 依此自主節流**。
- 前台 Ajax 面：IP＋cart token 滑動窗（15 §規格）；429＋Retry-After。

### 0.5 Bulk operations（規格保留、demo 簡化）
契約保留 `bulkOperationRunQuery/RunMutation`＋狀態機 `CREATED→RUNNING→COMPLETED|FAILED|CANCELED`＋JSONL `__parentId` 格式＋`bulk_operations/finish` topic；demo 以同步分批實作，介面不變。

### 0.6 冪等
寫入型 mutation 一律收 `idempotencyKey`（可選；訂單成立/退款/庫存調整必填——11 號 spec 鐵律）；重複 key 回首次結果。

## 1. 商品線（read_products/write_products）

| 類別 | Queries | Mutations |
|---|---|---|
| 商品 | `products(first, query, sortKey)`, `product(id)`, `productByHandle` | `productCreate(input{title, descriptionHtml, vendor, productType, tags, status, seo, options})`, `productUpdate`, `productDelete`, `productDuplicate(newTitle, includeImages)`, `productSet`（upsert 全樹）, `productChangeStatus(ACTIVE\|DRAFT\|ARCHIVED)` |
| 變體 | product.variants | `productVariantsBulkCreate/Update/Delete/Reorder(productId, variants[]{options, price, compareAtPrice, sku, barcode, inventoryPolicy, inventoryItem{tracked, cost}})`——**diff 更新語義**（22 §2：改選項矩陣時保留既有變體資料） |
| 選項 | product.options | `productOptionsCreate/Update/Delete/Reorder` |
| 媒體 | product.media | `productCreateMedia(media[]{originalSource, alt, mediaContentType})`, `productUpdateMedia`, `productDeleteMedia`, `productReorderMedia`, `productVariantAppendMedia/DetachMedia` |
| 搜尋語法 | `query:` 支援 `title:* status:active vendor:X tag:Y created_at:>date`（22 §1 檢視列） | — |

規則：handle 自動生成＋唯一化（13 號）；`query` 與 `sortKey` 需同欄位（大集合逾時保護）；media 上限 250/商品（limits.yml）；userErrors code 例：`HANDLE_TAKEN`、`VARIANT_LIMIT_EXCEEDED`（2048）。

## 2. 系列與發佈

| 類別 | Queries | Mutations |
|---|---|---|
| 系列 | `collections`, `collection(id)`, `collectionByHandle` | `collectionCreate(input{title, descriptionHtml, image, ruleSet{appliedDisjunctively, rules[{column, relation, condition}]}, sortOrder, seo})`, `collectionUpdate`, `collectionDelete`, `collectionAddProducts`, `collectionRemoveProducts`, `collectionReorderProducts(moves)` |
| 發佈 | `publications` | `publishablePublish/Unpublish(id, publicationIds)`（online store／POS／市場 catalog 皆是 publication——與 29 §1.3 銜接） |

規則：智慧系列規則變更 → 背景重算 membership（Solid Queue，5000 上限）；手動系列 position 排序。

## 3. 庫存與地點（read_inventory/write_inventory）

| 類別 | Queries | Mutations |
|---|---|---|
| 庫存 | `inventoryItem(id)`, `inventoryLevel(參數化 GID ?inventory_item_id=&location_id=)`, `inventoryProperties` | `inventoryAdjustQuantities(input{reason, name(available\|on_hand), changes[{delta, inventoryItemId, locationId, ledgerDocumentUri}]})`, `inventorySetQuantities(setQuantities[], reason, compareQuantity 樂觀鎖)`, `inventoryItemUpdate(tracked, cost, countryCodeOfOrigin, harmonizedSystemCode)`, `inventoryActivate/Deactivate` |
| 地點 | `locations`, `location(id)` | `locationAdd/Edit/Deactivate` |

規則：一切變動走 **ledger**（06 §恆等式：available = on_hand − committed − reserved − damaged…）；`reason` 枚舉（correction/received/sold/returned/damaged…）；併發用 compareQuantity CAS；`ledgerDocumentUri` 關聯單據。

## 4. 訂單線（read_orders/write_orders）

| 類別 | Queries | Mutations |
|---|---|---|
| 訂單 | `orders(first, query, sortKey)`, `order(id)`（金額全 MoneyBag；timeline events connection） | `orderUpdate(note, tags, email, shippingAddress)`, `orderClose/Open`, `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)`, `orderMarkAsPaid`, `orderCapture(amount, parentTransactionId)` |
| 訂單編輯 | `order.editSession` | `orderEditBegin(id)` → `orderEditAddVariant/AddCustomItem/SetQuantity/AddLineItemDiscount/RemoveDiscount` → `orderEditCommit(notifyCustomer, staffNote)`（差額走 15 §金額引擎重算＋補收/退差） |
| 草稿單 | `draftOrders`, `draftOrder(id)` | `draftOrderCreate(input{lineItems[{variantId\|custom{title,price}, quantity, appliedDiscount}], customerId, shippingAddress, appliedDiscount, shippingLine, note, email})`, `draftOrderUpdate`, `draftOrderDelete`, `draftOrderComplete(paymentPending: Boolean)` → 轉正式單, `draftOrderInvoiceSend(email 主旨/內文)` |
| 棄單 | `abandonedCheckouts(first, query)` | `abandonedCheckoutSendRecovery`（15 §棄單信規則） |

規則：訂單號 `#1001` 起連號 per shop；cancel 前置檢查（未出貨）；60 天窗口概念佔位；search 語法 `status/financial_status/fulfillment_status/email/name`。

## 5. 履約（read/write_fulfillments）

| 類別 | Queries | Mutations |
|---|---|---|
| 履約單 | `order.fulfillmentOrders`（assignedLocation、lineItems、supportedActions） | `fulfillmentOrderMove(newLocationId)`, `fulfillmentOrderHold/ReleaseHold`, `fulfillmentOrderSplit` |
| 出貨 | `fulfillment(id)` | `fulfillmentCreate(fulfillment{lineItemsByFulfillmentOrder[{fulfillmentOrderId, fulfillmentOrderLineItems[{id, quantity}]}], trackingInfo{number, company, url}, notifyCustomer})`, `fulfillmentTrackingInfoUpdate`, `fulfillmentCancel`, `fulfillmentEventCreate(status: IN_TRANSIT\|OUT_FOR_DELIVERY\|DELIVERED\|FAILURE…)` |

規則：**部分出貨**按 fulfillment order line 數量；出貨後 order.fulfillment_status 推導（16 號狀態機）；通知信走 18 號 outbox。

## 6. 退款與退貨

| 類別 | Queries | Mutations |
|---|---|---|
| 試算 | `order.suggestedRefund(refundLineItems, shippingAmount)` → maximumRefundable、按比例分攤結果 | — |
| 退款 | `order.refunds` | `refundCreate(input{orderId, refundLineItems[{lineItemId, quantity, restockType: RETURN\|CANCEL\|NO_RESTOCK, locationId}], shipping{amount\|fullRefund}, transactions[{parentId, amount, kind: REFUND, gateway}], note, notify})` |
| 退貨 | `returns`, `return(id)` | `returnCreate(orderId, returnLineItems)`, `returnApproveRequest/DeclineRequest`, `returnRefund`, `reverseFulfillmentOrderDispose` |

規則：**退款上限硬保證**（16 §：Σrefunds ≤ captured，DB 層鎖）；比例分攤折扣與稅（15 §引擎同源）；退款匯率＝當下（29 §3.4）。

## 7. 顧客（read/write_customers）

| 類別 | Queries | Mutations |
|---|---|---|
| 顧客 | `customers(first, query)`, `customer(id)`（ordersCount/amountSpent/lastOrder/addresses/taxExempt/marketing consent） | `customerCreate(input{firstName, lastName, email, phone, addresses, tags, note, taxExempt})`, `customerUpdate`, `customerDelete`（有訂單→匿名化，16 §）, `customerAddressCreate/Update/Delete/SetDefault`, `customerMerge(customerOneId, customerTwoId)` |
| 行銷同意 | customer.emailMarketingConsent/smsMarketingConsent | `customerEmailMarketingConsentUpdate(input{marketingState: SUBSCRIBED\|UNSUBSCRIBED, marketingOptInLevel, consentUpdatedAt})`、`customerSmsMarketingConsentUpdate` |
| 分群 | `segments`, `customerSegmentMembers(segmentId)` | `segmentCreate(name, query)`, `segmentUpdate`, `segmentDelete`——query 語法＝分群 DSL（01 §顧客） |

規則：email/phone 唯一 per shop；consent 帶時間戳與來源（GDPR 稽核）；merge 保留訂單歸屬。

## 8. 折扣與禮品卡（read/write_discounts）

| 類別 | Queries | Mutations |
|---|---|---|
| 自動折扣 | `automaticDiscountNodes` | `discountAutomaticBasicCreate/Update`（金額/百分比）、`discountAutomaticBxgyCreate/Update`、`discountAutomaticFreeShippingCreate/Update`、`discountAutomaticDelete/Activate/Deactivate` |
| 折扣碼 | `codeDiscountNodes`, `codeDiscountNodeByCode` | `discountCodeBasicCreate/Update`、`discountCodeBxgyCreate`、`discountCodeFreeShippingCreate`、`discountCodeDelete/Activate/Deactivate`、`discountCodeBulkCreate(codes[]，2000 萬配額)`、`discountRedeemCodeBulkAdd` |
| 禮品卡 | `giftCards`, `giftCard(id)` | `giftCardCreate(initialValue, code?, customerId?, expiresOn, note)`, `giftCardUpdate`, `giftCardDeactivate`, `giftCardCredit/Debit(amount)` |

規則：求值管線與組合裁決（17 號：allocation/combination matrix）；**用量併發硬保證**（usage_count CAS＋唯一索引）；input 統一 `{title, startsAt, endsAt, combinesWith{orderDiscounts, productDiscounts, shippingDiscounts}, minimumRequirement, customerSelection, usageLimit, appliesOncePerCustomer}`。

## 9. 內容與線上商店（read/write_content, read/write_themes）

| 類別 | Queries | Mutations |
|---|---|---|
| 頁面 | `pages`, `page(id)` | `pageCreate(title, body, handle, templateSuffix, isPublished)`, `pageUpdate`, `pageDelete` |
| 網誌 | `blogs`, `articles` | `blogCreate/Update/Delete`, `articleCreate(blogId, title, body, summary, image, tags, author, publishedAt)`, `articleUpdate/Delete`, `commentApprove/Delete/Spam` |
| 選單 | `menus`, `menu(id)` | `menuCreate(title, handle, items[{title, type, resourceId\|url, items 巢狀}])`, `menuUpdate`, `menuDelete` |
| 轉址 | `urlRedirects` | `urlRedirectCreate(path, target)`, `urlRedirectUpdate/Delete`, `urlRedirectBulkDeleteAll` |
| 主題 | `themes`, `theme(id)`（role: MAIN\|UNPUBLISHED\|DEVELOPMENT；files connection） | `themeCreate(source: zip URL/staged upload, name)`（→ 25 §4 匯入管線＋授權 gate）, `themePublish`, `themeUpdate(name)`, `themeDelete`, `themeDuplicate` |
| 主題檔 | `theme.files(filenames, first)` → body/contentType/size/checksumMd5 | `themeFilesUpsert(themeId, files[{filename, body{type: TEXT\|BASE64, value}}])`（**寫檔＝AST cache bust**）, `themeFilesDelete`, `themeFilesCopy(fromTheme)` |

規則：主題檔上限與白名單（25 §4）；publish＝原 MAIN 降級＋快取整體失效；redirects 命中在 storefront router 404 前查表。

## 10. 主題編輯器內部 API（31 號的 API 面；editor scope）

REST-ish 內部端點（编辑器高頻小 payload，不走 GraphQL）：

| 端點 | 說明 |
|---|---|
| `GET /editor/api/themes/{id}/schema` | 全主題編譯後 schema：sections/blocks 清單＋settings 定義＋presets＋翻譯後 labels（31 §ED） |
| `GET /editor/api/themes/{id}/template?path=index` | 模板 JSON＋section groups＋contextual overrides |
| `POST /editor/api/themes/{id}/draft` | 提交 op batch（add/remove/move/set-setting/toggle-disabled/duplicate/rename）→ 存 draft 態 |
| `POST /editor/api/themes/{id}/render_section` | **draft 渲染通道**（27 §6.3）：body={template draft JSON, sectionKey, context{market, locale, route}} → 回 wrapper HTML |
| `POST /editor/api/themes/{id}/publish_draft` | draft → 落正式檔（themeFilesUpsert 語義）＋清 undo stack |
| `GET /editor/api/fonts` | 字型庫清單（31 §R3） |
| `GET /editor/api/dynamic_sources?context=product` | 動態來源 picker 資料（metafields/資源屬性樹） |

## 11. 結帳、金流與設定域（read/write_settings）

| 類別 | Queries | Mutations |
|---|---|---|
| 商店 | `shop`（name/currency/ianaTimezone/domains/plan/billingAddress/backupRegion） | `shopUpdate`, `shopResourceFeedbackCreate` |
| 員工 | `staffMembers` | `staffMemberInvite`, `staffMemberUpdate(roles)`, `staffMemberDeactivate`（12 號權限模型） |
| 運送 | `deliveryProfiles`, `deliveryProfile(id)` | `deliveryProfileCreate/Update`（zones[{countries, methodDefinitions[{name, rateDefinition{price}\|conditions weight/price range}]}]）, `deliveryProfileRemove` |
| 稅 | `taxSettings` | `taxSettingsUpdate`（P1 簡化：per-country rate 表） |
| 結帳設定 | `checkoutSettings`（24 §5 全欄位） | `checkoutSettingsUpdate(contactMethod, requireLogin, nameMode, companyMode, addressAutocomplete, tipping{...}, abandoned{...}, cartItemLimit)` |
| 結帳外觀 | `checkoutProfiles`, `checkoutProfile(id)` | `checkoutProfileCreate/Duplicate/Delete`, `checkoutBrandingUpsert(profileId, designSystem{colors, typography, cornerRadius}, customizations{...})`（24 §6.4 jsonb 結構） |
| 通知 | `notificationTemplates` | `notificationTemplateUpdate(templateId, subject, bodyLiquid)`（18 號 Liquid 沙箱） |
| 網域 | `domains` | `domainCreate(host)` → DNS 驗證流程, `domainSetPrimary`, `domainDelete` |
| 支付 | `paymentProviders` | `paymentProviderActivate(stripe test keys)`（15 號） |

## 12. Metafields／Metaobjects／Files

| 類別 | Queries | Mutations |
|---|---|---|
| Metafield | 任意資源 `.metafield(namespace, key)` / `.metafields(first)` | **`metafieldsSet(metafields[{ownerId, namespace, key, type, value, compareDigest?}]) ≤25 筆 atomic`**, `metafieldsDelete` |
| 定義 | `metafieldDefinitions(ownerType)` | `metafieldDefinitionCreate(name, namespace, key, type, ownerType, validations, access{storefront: PUBLIC_READ\|NONE})`, `metafieldDefinitionUpdate/Delete` |
| Metaobject | `metaobjects(type)`, `metaobjectByHandle` | `metaobjectDefinitionCreate(type, fieldDefinitions)`, `metaobjectCreate/Update/Delete`（theme 的 metaobject template 資料來源，24 §1.7） |
| 檔案 | `files(first, query)` | `stagedUploadsCreate(input[{resource, filename, mimeType, fileSize}])` → 簽名 URL → `fileCreate(files[{originalSource, alt}])`, `fileUpdate`, `fileDelete` |

type 系統首發 15 種：single_line_text/multi_line_text/rich_text/integer/decimal/boolean/date/date_time/url/color/json/money/file_reference/product_reference/metaobject_reference（+list. 變體）。

## 13. Markets／翻譯（29 §7 全表併入）

`markets/market/marketCreate/Update/Delete`、`webPresence*`、`marketCurrencySettingsUpdate`、`catalog*`、`priceList*`＋`priceListFixedPrices*`、`translatableResources/translationsRegister/Remove`、`marketLocalizations*`、`shopLocale*`。金額回傳一律 MoneyBag；storefront context 由 SSR RequestContext 承擔（等價 @inContext）。

## 14. 分析（read_analytics）

| 類別 | Queries |
|---|---|
| 總覽 | `analyticsOverview(range, compareRange)` → 指標卡集（19 號辭典：total_sales/net_sales/orders/conversion_rate/AOV/returning_rate/sessions） |
| 報告 | `report(type, range, groupBy, filters)` → rows connection（sales_over_time/sales_by_product/by_channel/by_location/traffic…19 §報告清單） |
| 即時 | `liveView` → 當前 sessions/cart/checkout/orders 計數 |

規則：**同源鐵律**——pulse 卡/列表 badge/報告數字全部出自 rollup 服務（19 號）；range 用 shop timezone。

## 15. Webhooks（事件出口）

- 訂閱：`webhookSubscriptions` query＋`webhookSubscriptionCreate(topic, callbackUrl, format: JSON)/Update/Delete`。
- **簽章**：`X-CL-Hmac-Sha256`＝base64(HMAC-SHA256(raw body, app secret))，timing-safe 比較；headers `X-CL-Topic/X-CL-Shop-Domain/X-CL-Webhook-Id（去重）/X-CL-Event-Id/X-CL-Triggered-At/X-CL-API-Version`。
- **投遞**：5 秒內 2xx；重試指數退避（demo 3 次；規格目標 8 次/4 小時）；API 建立的訂閱連續失敗自動刪除；outbox 驅動（18 號）。
- **Topics 首發 24 個**：`app/uninstalled`, `shop/update`；`products/create|update|delete`；`collections/create|update|delete`；`inventory_levels/update`；`orders/create|updated|paid|cancelled|fulfilled|partially_fulfilled|edited`；`draft_orders/create|update`；`customers/create|update|delete`；`fulfillments/create|update`；`refunds/create`；`checkouts/create|update`（棄單）；`themes/publish`；`bulk_operations/finish`（佔位）。payload＝資源 snake_case JSON＋`admin_graphql_api_id`。
- Feed/SEO 消費者（30 號）：products/update→feed 增量＋IndexNow；orders/*→Simprosys 訂單餵送。

## 16. 前台 HTTP 面（買家端）

- **頁面路由**（SSR，全部支援 `/{locale}` 前綴＋market 網域，29 §2.5）：`/`、`/products/{handle}`（`?variant=` canonical 規則 30 §1.3）、`/collections`、`/collections/{handle}`（分頁/排序/篩選 query）、`/pages/{handle}`、`/blogs/{handle}`、`/blogs/{handle}/{article}`、`/search`（`?q=`）、`/cart`、`/checkout`（15 號）、`/account/*`（login/register/orders/addresses）、`/gift_card/{code}`、`/password`、`/404`、**`?view={suffix}` alternate template**（25 §5）。
- **Ajax/JSON 面**：25 §5 全表（cart 家族雙格式、SRA、predictive search、recommendations、localization、shipping_rates）。
- **SEO 面**（30 §9）：`/sitemap.xml`＋分片、`/robots.txt`（liquid 可覆寫）、`/{indexnow-key}.txt`、`/feeds/google/{market}.xml|.tsv`（feed 直出）、`.well-known` 驗證檔路由。
- **結帳 POST**：`/checkout` 提交、`/checkout/shipping_rates`、`/checkout/complete`（Stripe confirm）——15 號欄位規格。

## 17. 三端對接矩陣（誰用哪個面）

| 客戶端 | 使用的 API 面 | 認證 |
|---|---|---|
| Admin React SPA | GraphQL Admin API（§1–14）＋編輯器內部 API（§10）＋stagedUploads | session cookie＋CSRF |
| 買家瀏覽器（主題 JS） | 前台 HTTP 面（§16）：Ajax cart/SRA/search/localization | cart token（cookie） |
| Liquid SSR 渲染器 | 內部 service objects（**不走 HTTP**——drops 直讀 preloaded scope，25 §6） | 進程內 |
| 外部整合（Simprosys/自建 feed 消費者/未來 apps） | GraphQL Admin API（token）＋Webhooks（§15） | `clat_` token＋scopes |
| Checkout（React island） | 結帳 POST＋`/checkout/shipping_rates`＋Stripe.js | checkout session token |

## 18. 驗收

1. Admin SPA 的**每一個**網路請求都是 `/admin/api/2026-08/graphql.json`（或 §10 編輯器端點）——瀏覽器 network 面板抽查零例外。
2. 任一 mutation 的業務錯誤出現在 userErrors（含 code），HTTP 恆 200；表單元件只消費 userErrors。
3. `extensions.cost` 在每個回應出現；壓測觸發 THROTTLED 後前端 SDK 自動退避重試成功。
4. 三個 webhook 消費者（feed 增量/IndexNow/測試 endpoint）HMAC 驗證通過並在 orders/create 後 5 秒內收到。
5. GID/分頁/MoneyV2 慣例 lint：schema 檢查器擋住裸 float 金額與 offset 分頁。
6. 22 號按鈕表逐行對照：每個 admin 按鈕都能映射到本文一個操作（缺口=補 mutation）。
