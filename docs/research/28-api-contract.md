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
寫入型 mutation 一律收 `idempotencyKey`；**強制清單見 `config/limits.yml` 的 `idempotency.required_for`**（含 Shopify 自 2026-04 起強制的 17 個 mutation，以 refund／inventory 為主，缺 key **執行期報錯**；另加本專案強制的 `returnProcess` 與 `orderCancel`）。

| 項 | 規定 | 出處 |
|---|---|---|
| TTL | **24 小時**，逾期同 key 重試視為**全新操作** | 46a:789、46a:1006 |
| 回放 | 🔴 **由當前 DB 狀態重建回應**（重載 `result_ref` ＋ 重跑 serializer），**不存回應快照** | 46a:791、46a:1009 |
| 參數指紋 | canonical_json（**物件 key 遞迴排序**後）→ SHA256；欄位順序會影響指紋 | 46a:793、46a:816 |
| 錯誤碼 | `IDEMPOTENCY_CONCURRENT_REQUEST`（退避後**用同一把 key** 重試）／`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（同 key 不同參數） | 46a:763–764、46a:1010–1011 |
| Bulk | **每個 JSONL row 一把獨立 key，絕不共用** | 46a:1015 |
| key 格式 | 互動 UUID v4/v7；排程 **UUID v5**（namespace + job 參數） | 46a（S47/S48） |

<!-- 依 46a:781–794、46a:1000–1016 修正，原文見上表。
     🔴 此處原本寫錯：本節原寫「重複 key 回首次結果」＋ 11:45–48 存 `response_body` 原樣回放，
     與官方「constructed from current database state」語義相反。完整規格見 docs/specs/11 §2.1。任何人翻舊版都不要改回去。 -->

**⚠ 待查證（來源未載明）**：冪等 key 的長度／字元格式硬性限制（46a §6⑤ 未載明）。

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

規則：一切變動走 **ledger**（06 §5 恆等式：`on_hand = available + committed + unavailable`，`incoming` 獨立不計入 on_hand）；併發用 compareQuantity CAS；`ledgerDocumentUri` 關聯單據。

<!-- 依 46c:608–617、46c:891–927 修正，原文：官方調整原因**七項**（更正〔預設〕/盤點/已收件/退貨重新入庫/損壞/遭竊或遺失/促銷或捐贈）；
     庫存頂層五態（現有/可販售/已分配/不可販售/待入庫）＋ unavailable 四子分類。
     🔴 此處原本寫錯：`reason` 枚舉原寫「correction/received/sold/returned/damaged…」——未列滿七項，且含官方**沒有**的 `sold`
     （出庫由 fulfillment 事件表達，不是調整原因），與 22:81 的清單也不一致。任何人翻舊版都不要改回去。 -->
- `name` 參數的量測面：`available` / `on_hand` / **`unavailable`** / **`incoming`**（四個實體欄位，見 13-F5.1）。
- `reason` 枚舉＝`limits.inventory.adjustment_reasons` **七項**：`correction`（預設）/ `count` / `received` / `return_restock` / `damaged` / `theft_or_loss` / `promotion_or_donation`。
- 狀態間移動（如「移至安全庫存」「草稿保留」）走 `inventoryMoveQuantities`，ledger 帶 `from_state` / `to_state`。
- **訂單草稿保留庫存進 `unavailable[draft_reserved]`，不是 `committed`**（46c:546–549）。

## 4. 訂單線（read_orders/write_orders）

| 類別 | Queries | Mutations |
|---|---|---|
| 訂單 | `orders(first, query, sortKey, **return_status 可篩**)`, `order(id)`（金額全 MoneyBag；timeline events connection） | `orderUpdate(note, tags, email, shippingAddress)`, `orderClose/Open`, **`orderCancel(orderId: ID!, reason: OrderCancelReason!, restock: Boolean!, notifyCustomer: Boolean, staffNote: String, refundMethod: OrderCancelRefundMethodInput) → { job{id,done}, orderCancelUserErrors }`**（**非同步**）, `orderMarkAsPaid`, `orderCapture(amount, parentTransactionId)` |
| 訂單編輯 | `order.editSession` | `orderEditBegin(id)` → `orderEditAddVariant/AddCustomItem/SetQuantity/AddLineItemDiscount/RemoveDiscount` → `orderEditCommit(notifyCustomer, staffNote)`（差額走 15 §金額引擎重算＋補收/退差） |
| 草稿單 | `draftOrders`, `draftOrder(id)` | `draftOrderCreate(input{lineItems[{variantId\|custom{title,price}, quantity, appliedDiscount}], customerId, shippingAddress, appliedDiscount, shippingLine, note, email})`, `draftOrderUpdate`, `draftOrderDelete`, `draftOrderComplete(paymentPending: Boolean)` → 轉正式單, `draftOrderInvoiceSend(email 主旨/內文)` |
| 棄單 | `abandonedCheckouts(first, query)` | `abandonedCheckoutSendRecovery`（15 §棄單信規則） |

規則：訂單號 `#1001` 起連號 per shop；60 天窗口概念佔位；search 語法 `financial_status/fulfillment_status/return_status/email/name`（**不含 `status`——Order 沒有單一 status 欄位**）。

**`orderCancel` 契約（P0-14，逐項）**
<!-- 依 46a:842–877 修正，原文：`reason` 與 `restock` 皆 non-null；`staffNote` ≤255 且買家不可見；`refundMethod` 可退原路或 store credit；
     回傳 `job{id,done}` ＋ `orderCancelUserErrors`（`userErrors` 已 deprecated）；mutation 為**非同步**。
     🔴 此處原本寫錯：原簽名 `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)`——
     多出官方**不存在**的 `refund: Boolean`、少了 `staffNote`/`refundMethod`、`restock` 未標 non-null、且做成同步。任何人翻舊版都不要改回去。 -->
- `reason: OrderCancelReason!` **6 值**：`CUSTOMER` / `PAYMENT_DECLINED` / `FRAUD` / `INVENTORY` / `STAFF_ERROR` / `OTHER`。
- `restock: Boolean!` **non-null 無預設**；`staffNote` ≤ `limits.order.cancel_staff_note_max_chars`(255)、買家不可見。
- ~~`refund: Boolean`~~ **官方不存在，已刪除**（是否退款由 `refundMethod` 表達）。
- **非同步**：回 `job{id, done}` 供輪詢；job 本身帶冪等鍵。
- **不可取消五條件（聯集 guard）**：已取消／有待處理付款授權／**有進行中的退貨（`REQUESTED`/`OPEN`）**／有無法履行的未結出貨／已（部分）出貨 → 皆回 `INVALID_STATE`。
- **停用地點**：已付款 ＋ `restock:true` → **整個 mutation 失敗**；未付款 → 成功但庫存不回補。
- 副作用：關閉／取消所有未結 FulfillmentOrder（走 §5 的替代單語義）。

## 5. 履約（read/write_fulfillments）

| 類別 | Queries | Mutations |
|---|---|---|
| 履約單 | `order.fulfillmentOrders`（assignedLocation、lineItems、**status(7)**、**requestStatus(8)**、**supportedActions(12)**、fulfillmentHolds{reason(8)}） | **`fulfillmentOrderCancel(id) → { fulfillmentOrder, replacementFulfillmentOrder }`**, `fulfillmentOrderClose(id, message) → INCOMPLETE`, `fulfillmentOrderOpen(id)`, `fulfillmentOrderReschedule(id, fulfillAt)`, **`fulfillmentOrderHold(id!, fulfillmentHold!{reason, reasonNotes, notifyMerchant, handle, fulfillmentOrderLineItems}) → { fulfillmentHold, fulfillmentOrder, remainingFulfillmentOrder }`**, `fulfillmentOrderReleaseHold(id, externalId\|handle)`, **`fulfillmentOrderMove(id, newLocationId, lineItems) → { movedFulfillmentOrder, originalFulfillmentOrder, remainingFulfillmentOrder }`**, `fulfillmentOrderSplit(fulfillmentOrderSplits!)`, `fulfillmentOrderMerge`, `fulfillmentOrdersReroute`, `fulfillmentOrderReportProgress` |
| 3PL 請求軸 | fulfillmentOrder.requestStatus | `fulfillmentOrderSubmitFulfillmentRequest(id, message, notifyCustomer)`, `fulfillmentOrderAcceptFulfillmentRequest(id, message)`, `fulfillmentOrderRejectFulfillmentRequest(id, reason: FulfillmentOrderRejectionReason(14), message, lineItems)`, `fulfillmentOrderSubmitCancellationRequest`, `fulfillmentOrderAcceptCancellationRequest`, `fulfillmentOrderRejectCancellationRequest` |
| 出貨 | `fulfillment(id)` | `fulfillmentCreate(fulfillment{lineItemsByFulfillmentOrder[{fulfillmentOrderId, fulfillmentOrderLineItems[{id, quantity}]}], trackingInfo{number, company, url}, notifyCustomer, **originAddress{countryCode!}**})`, `fulfillmentTrackingInfoUpdate`, `fulfillmentCancel`, `fulfillmentEventCreate(status: IN_TRANSIT\|OUT_FOR_DELIVERY\|**READY_FOR_PICKUP**\|DELIVERED\|FAILURE…)` |

規則：**部分出貨**按 fulfillment order line 數量；出貨後 order.fulfillment_status 推導（16 號狀態機）；通知信走 18 號 outbox。

**FulfillmentOrder 契約補完（P0-04／P0-05）**
<!-- 依 46a:213–275、46a:236–240、46a:354–366 補寫，原文：`fulfillmentOrderCancel`＝「Cancels order and creates replacement for remaining work」；
     `fulfillmentOrderHold`／`Move` 回傳 `remainingFulfillmentOrder`（自動拆出新單承接未處理品項）；
     `fulfillmentOrderClose` 逐字「Marks in-progress order as incomplete」→ 導向 INCOMPLETE 不是 CLOSED。
     我方原本只列 `Move/Hold/ReleaseHold/Split` 四個名稱，拆單語義完全未寫 → 剩餘品項會憑空消失 -->
- **三個會產生新 FO 的操作必須回傳新單 ID**：`fulfillmentOrderCancel → replacementFulfillmentOrder`、`fulfillmentOrderHold/Move → remainingFulfillmentOrder`。無剩餘工作時回 `null`。
- **`fulfillmentOrderClose` 導向 `INCOMPLETE`（不是 `CLOSED`）**，中文 UI 標「未能完成」。
- `supportedActions` 為**伺服器端計算欄位**，admin 按鈕啟用完全由它驅動；**前端不得另寫 guard**。
- `fulfillmentCreate` 的多張 FO 必須**同一 order ＋ 同一 location**（service 層驗證回 `userErrors`，非 DB constraint）；`originAddress.countryCode` 必填。
- 每張 FO **≤`limits.fulfillment_order.max_active_holds`(10)** 個 active hold。
- 自營 FO（未指派 fulfillment service）**恆為 `requestStatus: UNSUBMITTED`**。
- **⚠ 待查證（來源未載明）**：`FulfillmentOrderHoldUserErrorCode` / `SplitUserErrorCode` / `OrderCancelUserErrorCode` 的具體 enum 值、`fulfillmentOrderSplit` 最大拆分數、tracking number/url 數量上限（46a:1049–1067 逐條標未載明）。

## 6. 退款與退貨

| 類別 | Queries | Mutations |
|---|---|---|
| 試算 | `order.suggestedRefund(refundLineItems, shippingAmount)` → maximumRefundable、按比例分攤結果；`return.suggestedRefund` → `SuggestedReturnRefund`；**`returnCalculate(input: CalculateReturnInput) → CalculatedReturn{returnLineItems, exchangeLineItems, returnShippingFee}`（不建立資料）**；`returnableFulfillments(orderId)` → **可退的 fulfillment line item ＋ 可退數量**（前提：已 delivered） | — |
| 退款 | `order.refunds` | `refundCreate(input{orderId, refundLineItems[{lineItemId, quantity, restockType, locationId}], refundShipping{amount\|fullRefund}, refundDuties[], transactions[{parentId, amount, kind: REFUND, gateway}], refundMethods[]（原路／store credit）, note, notify}) @idempotent(key:)` |
| 退貨 | `returns`, `return(id)`（status/returnLineItems/exchangeLineItems/**returnShippingFees**/reverseFulfillmentOrders/refunds/decline） | `returnRequest(input)`→REQUESTED, `returnCreate(returnInput{orderId!, returnLineItems!, exchangeLineItems, returnShippingFee, requestedAt})`→OPEN, `returnApproveRequest`, `returnDeclineRequest(returnId, declineReason!)`, `returnLineItemRemoveFromReturn`, **`returnProcess(input: ReturnProcessInput)`**, `returnCancel(id)`, `returnClose(id)`, `returnReopen(id)`, `reverseFulfillmentOrderDispose`, `reverseDeliveryCreateWithShipping` |

規則：**退款金額走 16-F5.1 的唯一公式**（`refund = max(0, 退貨品項價值 − 退貨費用 − 換貨扣抵 − 未付款額)`）；比例分攤折扣與稅（15 §引擎同源）；退款匯率＝當下（29 §3.4）。

**退貨／退款契約補完（P0-01／P0-02／P0-06）**
<!-- 依 46a:642、46a:806–809 修正，原文：`returnRefund` **已 deprecated**（逐字「Deprecated mutation for refunding returns without restocking input」）；
     有退貨脈絡走 `returnProcess`（2025-07 起可用），無脈絡走 `refundCreate`。
     🔴 此處原本寫錯：本表原把 `returnRefund` 列為現行 mutation。任何人翻舊版都不要改回去。 -->
- ~~`returnRefund`~~ **已 deprecated，不實作**；有 return 關聯 → `returnProcess`；無 return 關聯（純取消、客訴補償）→ `refundCreate`。
- **費用不對稱設計照抄**：`RestockingFeeInput{percentage: Float!}`（**百分比**、**per line item**）／`ReturnShippingFeeInput{amount: MoneyInput!}`（**固定額**、**per return**、**必須 presentment 幣別**）。
- `returnReasonNote` ≤ `limits.return.reason_note_max_chars`(255)；`returnDeclineRequest.declineReason` **必填**（`FINAL_SALE`/`RETURN_PERIOD_ENDED`/`OTHER`）。
- `returnCalculate` 與 `returnProcess` **共用同一份計算程式碼**（數字同源，鐵律 7）。
- `returnProcess` 內含退款 → **本專案強制 `idempotencyKey`**（Shopify 未載明）。
- **退款上限是軟上限、不是 DB 硬鎖**：預設 `netPayment`，超額需 `orders.over_refund` 權限＋二次確認（46c:223 明載超額退款合法）。
- `ReturnErrorCode` **26 值全部落地**為 `userErrors.code`；`INVALID_STATE` 為狀態機違規統一碼。
- **⚠ 待查證（來源未載明）**：`restockType` 的真實列舉值——46a:747 為 `RESTOCK`/`NO_RESTOCK`/`LEGACY_RESTOCK`，本檔原寫 `RETURN`/`CANCEL`/`NO_RESTOCK`，實務另有第三套 → **三方互斥，須 GraphQL introspection 定案，實作前不得二選一**（50 號 T-08／V-01）。
- **⚠ 待查證（來源未載明）**：`maximumRefundable` 公式、稅額在退款時的分攤規則、`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為、`RestockingFeeInput.percentage` 最大值。

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

規則：求值管線與組合裁決（17 號：allocation/combination matrix）；**用量併發硬保證**（usage_count CAS＋唯一索引）；input 統一 `{title, startsAt, endsAt, combinesWith{orderDiscounts, productDiscounts, shippingDiscounts}, minimumRequirement, **context{customerSegments | markets}**, usageLimit, appliesOncePerCustomer}`。

<!-- 依 46b:248–257、46b:375 修正，原文：`customerSelection` **已 deprecated（2025-10）**，改用 `context{customerSegments | markets}`，且 **markets 與 customerSegments 互斥（XOR）**。
     🔴 此處原本寫錯：input 原列 `customerSelection` 且無 `context`、無 XOR 檢查。任何人翻舊版都不要改回去。 -->
- `context` 的 `customerSegments` 與 `markets` **互斥**（XOR 驗證，兩者皆給 → userError）。
- 免運折扣的 `combinesWith` **只有 `orderDiscounts` / `productDiscounts` 兩個旗標**（無 `shippingDiscounts`）——46b:197。
- `combinesWith` 三旗標**預設全 false**（46c:705）；**運費折扣不可疊運費折扣**是引擎級硬規則，不由旗標控制。
- `percentage` 線上格式為 **0–1 Float**（不是 0–100），內部存 basis points（46b:189、46b:272）。
- 上限一律引用 `config/limits.yml` 的 `discount.*`（自動折扣全店同時 ≤25、每店碼 2,000 萬、每碼適用清單 100、每次結帳 5 碼＋1 運費碼、tags 5／長度 255）。
- **⚠ 待查證（來源未載明）**：`DiscountErrorCode` 39 值尚未落地（46b:323–367，建議全部照抄）；單一折扣可綁 markets 數上限（46b:993–1010 標未載明）。

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
| **其他配送方式**（44:322 實測三列） | `localDeliverySettings`, `localPickupSettings`, **`pickupPointProviders`** | `localDeliverySettingsUpdate`, `localPickupSettingsUpdate`, **`pickupPointProviderUpsert(carrier, subtypes[], enabled, codEnabled, credentialsRef)`**, **`pickupPointProviderDelete`** |
| **取貨點門市**（P0-13） | **`order.pickupPoint`**（門市快照：carrier/storeId/storeName/address/phone/isOutsideIsland）, **`checkout.pickupPoint`** | **`checkoutPickupPointSet(checkoutToken, carrier, subtype, storeId, storeName, storeAddress, storePhone, isOutsideIsland)`**（電子地圖回拋端點寫入）, **`orderPickupPointUpdate`**（門市關轉店的改派） |
| 稅 | `taxSettings` | `taxSettingsUpdate`（P1 簡化：per-country rate 表） |
| **退貨與取消規則**（P0-10） | **`returnRules`**（多條：預設 ＋ N 條，可按市場切換）, **`returnPolicySnapshot(id)`** | **`returnRuleCreate/Update/Delete(input{returnsEnabled, cancellationsEnabled, windowDays\|unlimited, windowStartBasis: ITEM_DELIVERED\|ORDER_LAST_ITEM_DELIVERED, shippingFeeMode: FREE\|FLAT_FEE\|CUSTOMER_BUYS_LABEL, shippingFeeAmount, restockingFeeBp, finalSaleTargets[{type: COLLECTION\|PRODUCT, id}], marketId})** |
| 結帳設定 | `checkoutSettings`（24 §5 全欄位） | `checkoutSettingsUpdate(contactMethod, requireLogin, nameMode, companyMode, addressAutocomplete, tipping{...}, abandoned{...}, cartItemLimit)` |
| 結帳外觀 | `checkoutProfiles`, `checkoutProfile(id)` | `checkoutProfileCreate/Duplicate/Delete`, `checkoutBrandingUpsert(profileId, designSystem{colors, typography, cornerRadius}, customizations{...})`（24 §6.4 jsonb 結構） |
| 通知 | `notificationTemplates` | `notificationTemplateUpdate(templateId, subject, bodyLiquid)`（18 號 Liquid 沙箱） |
| 網域 | `domains` | `domainCreate(host)` → DNS 驗證流程, `domainSetPrimary`, `domainDelete` |
| 支付 | `paymentProviders` | `paymentProviderActivate(stripe test keys)`（15 號） |

**退貨與取消規則契約說明（P0-10）**
<!-- 依 46c:422–426、44:437 補寫（三方一致），原文：H14 en 逐字「Changes to your return rules apply only to future orders. Changes don't apply to previous orders」；
     44 後台頁尾逐字「退貨與取消規則適用於在啟用或更新規則後所購買的品項」。我方 16／13／28 原本全無 → 商家改規則會追溯既往 -->
- **規則變更不追溯既往**：`returnRuleUpdate` **必定產生一筆新的 `return_policy_snapshots`**（append-only、immutable），舊快照永不更新。
- 訂單成立時把當下適用的 snapshot id 寫進 `order_line_items.return_policy_snapshot_id`（**NOT NULL**）；`returnCalculate`／前台申請入口**一律讀快照**。
- **兩個獨立 toggle**：`returnsEnabled` 管**已履行**品項、`cancellationsEnabled` 管**未出貨**品項，同一訂單可並存 → 前台「申請」按鈕**逐 line item 判斷**。
- **最終銷售品項**：粒度為 collection 或 product；命中即前台**不出現申請入口**（不是提交後被拒）；**bundles 不可設為最終銷售**。
- 退貨期間 `14/30/90/不限/自訂`、起算點兩選項、退貨運費三選一、重新上架費為百分比——值域見 `limits.return.*`。

**取貨點（pickup points）契約說明（P0-13）**
<!-- 依 44:322 補寫，原文：Shopify 後台「其他配送方式」三列＝當地配送／到店取貨／**取貨點**（44 已標「這正是台灣超商取貨的對應概念，
     我們 42 號前台的超商取貨流程在 admin 側要對應此設定」）；46b:551–552 佐證 `purchase.checkout.pickup-point-list.*` 擴充點與
     `pickup-location-list`（到店取貨）分屬不同家族。我方原本 15/16/22/28 皆無 admin 側規格 → 前台選了門市後台無處存、無法出貨 -->
- **`delivery_method_type` 三分法**：`SHIPPING`（宅配）／`LOCAL_PICKUP`（到店取貨，取貨點＝賣家 location）／**`PICKUP_POINT`（取貨點，門市為第三方）**。寫在 `shipping_lines` 與 `fulfillment_orders` 上。
- `PICKUP_POINT` 的訂單**不收運送地址**，改存**門市快照**（門市會關店，不可只存外鍵）。
- 履行事件多一個 **`READY_FOR_PICKUP`**；退貨的「已送達」前提以**實際領件時間**為準（16-F7.2）。
- 上限值（COD ≤NT$20,000、三邊和 ≤105cm、≤5kg）引用 `limits.pickup_point.*`。
- **⚠ 待查證（來源未載明）**：Shopify 官方對 pickup point 的 admin 側**是否有對應 GraphQL 型別**，三方文檔皆未載明——上表的 `pickupPointProviders` / `checkoutPickupPointSet` 為**本專案自定契約**；台灣各物流商的 COD 上限與材積限制須逐一以合約原文覆核（V-11）。

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
