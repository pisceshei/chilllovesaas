# 46a — Shopify 訂單／履行／退貨換貨／退款／編輯訂單 權威功能邏輯字典

> **用途**：M4「履約線」的唯一權威來源。所有狀態機、上限值、錯誤碼、金額規則以本檔為準；本檔沒寫的才去問使用者或另行研究。
> **研究方法**：2026-08-11 以 WebFetch 實際抓取 shopify.dev（`latest` = 2026 版 API）。每條結論後方標出處 URL。抓不到的內容一律標「**文檔未載明**」，不臆測。
> **對應**：`CLAUDE.md` 鐵律 3（integer cents）／4（userErrors）／5（冪等）／6（limits.yml）；`docs/research/22` §1b guard 清單；`docs/research/28` API 契約。

## 0. 來源清單（全部實抓）

| # | URL | 抓取結果 |
|---|---|---|
| S1 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Order | ✅ |
| S2 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFulfillmentStatus | ✅ |
| S3 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFinancialStatus | ✅ |
| S4 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderReturnStatus | ✅ |
| S5 | https://shopify.dev/docs/apps/build/orders-fulfillment | ✅ |
| S6 | https://shopify.dev/docs/apps/build/orders-fulfillment/returns-apps | ✅ |
| S7 | https://shopify.dev/docs/apps/build/orders-fulfillment/returns-apps/build-return-management | ✅ |
| S8 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Return | ✅ |
| S9 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReturnStatus | ✅ |
| S10 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/returnCreate | ✅（欄位細節另抓 input objects） |
| S11 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/refundCreate | ✅ |
| S12 | https://shopify.dev/docs/api/admin-graphql/latest/objects/FulfillmentOrder | ✅ |
| S13 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentOrderStatus | ✅ |
| S14 | https://shopify.dev/docs/apps/build/orders-fulfillment/order-management-apps/build-order-editing | ❌ **404**，等價頁見 S15 |
| S15 | https://shopify.dev/docs/apps/build/orders-fulfillment/order-management-apps/edit-orders | ✅（S14 的實際位置） |
| S16 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderEditBegin | ✅ |
| S17 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderEditCommit | ✅ |
| S18 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderEditAddVariant | ✅ |
| S19 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderCancel | ✅ |
| S20 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderCapture | ✅ |
| S21 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentOrderRequestStatus | ✅ |
| S22 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentOrderAction | ✅ |
| S23 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentHoldReason | ✅ |
| S24 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentOrderRejectionReason | ✅ |
| S25 | https://shopify.dev/docs/api/admin-graphql/latest/enums/FulfillmentStatus | ✅ |
| S26 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentCreate | ✅ |
| S27 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentOrderHold | ✅ |
| S28 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/fulfillmentOrderSplit | ✅ |
| S29 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReturnErrorCode | ✅ |
| S30 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReturnReason | ✅ |
| S31 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReturnDeclineReason | ✅ |
| S32 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnInput | ✅ |
| S33 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnLineItemInput | ✅ |
| S34 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/RestockingFeeInput | ✅ |
| S35 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnShippingFeeInput | ✅ |
| S36 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnProcessInput | ✅ |
| S37 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/returnProcess | ✅ |
| S38 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/returnRequest | ✅ |
| S39 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/returnCancel | ✅ |
| S40 | https://shopify.dev/docs/api/admin-graphql/latest/queries/returnCalculate | ✅ |
| S41 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Refund | ✅ |
| S42 | https://shopify.dev/docs/api/admin-graphql/latest/objects/SuggestedRefund | ✅ |
| S43 | https://shopify.dev/docs/api/admin-graphql/latest/objects/SuggestedReturnRefund | ✅ |
| S44 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ReverseFulfillmentOrder | ✅ |
| S45 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReverseFulfillmentOrderStatus | ✅ |
| S46 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReverseFulfillmentOrderDispositionType | ✅ |
| S47 | https://shopify.dev/docs/api/usage/idempotent-requests | ✅ |
| S48 | https://shopify.dev/docs/api/usage/implementing-idempotency | ✅ |
| S49 | https://shopify.dev/changelog/making-idempotency-mandatory-for-inventory-adjustments-and-refund-mutations | ✅ |
| S50 | https://shopify.dev/changelog/return-suggestedrefund-and-returnrefund-consider-exchanges-and-fees | ✅ |
| S51 | https://shopify.dev/docs/apps/build/orders-fulfillment/returns-apps/migrate-to-return-processing | ✅ |
| S52 | https://shopify.dev/docs/apps/build/orders-fulfillment/returns-apps/view-and-refund-duties | ✅ |

**重要提醒**：Shopify 的 GraphQL 參考頁是動態渲染的，WebFetch 抓到的是伺服器端 markdown 摘要。**列舉值與 input 欄位可信度高**（逐字引述），但「完整 userErrors code 清單」在多數 mutation 頁上並未列出——本檔對這些一律標「文檔未載明」，實作時請以 introspection 為準。

---

## 1. Order（訂單主體）

### ① 狀態機表

Shopify 的 Order **沒有單一 status 欄位**，而是由四個正交的展示狀態＋兩個布林生命週期旗標組合（S1）。這是 1:1 復刻時最容易做錯的地方。

**1a. `displayFinancialStatus` — OrderDisplayFinancialStatus（金流狀態，8 值）**（S3）

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `PENDING` | 待付款 | 「Orders have this status when the payment provider needs time to complete the payment, or when manual payment methods are being used.」 |
| `AUTHORIZED` | 已授權 | 「The payment provider has validated the customer's payment information. This status appears only for manual payment capture and indicates payments should be captured before the authorization period expires.」 |
| `PARTIALLY_PAID` | 部分付款 | 「A payment was manually captured for the order with an amount less than the full order value.」 |
| `PAID` | 已付款 | 「Payment was automatically or manually captured, or the order was marked as paid.」 |
| `PARTIALLY_REFUNDED` | 部分退款 | 「The amount refunded to a customer is less than the full amount paid for an order.」 |
| `REFUNDED` | 已退款 | 「The full amount paid for an order was refunded to the customer.」 |
| `VOIDED` | 已作廢 | 「An authorized but uncaptured payment was voided, releasing the hold on the funds. This is the payment's financial status and is distinct from the order's status: an order can remain open even when its payment is voided.」 |
| `EXPIRED` | 授權過期 | 「Payment wasn't captured before the payment provider's deadline on an authorized order. Some payment providers use this status to indicate failed payment processing.」 |

合法轉移（由文檔語義推導，**Shopify 未提供正式轉移圖**）：

```
PENDING ──(付款完成/標記已付)──> PAID
PENDING ──(授權成功，手動請款)──> AUTHORIZED
AUTHORIZED ──orderCapture(部分)──> PARTIALLY_PAID
AUTHORIZED ──orderCapture(全額/finalCapture)──> PAID
AUTHORIZED ──(作廢授權)──> VOIDED          【不可逆】
AUTHORIZED ──(超過請款期限)──> EXPIRED      【不可逆】
PARTIALLY_PAID ──orderCapture(補足)──> PAID
PAID / PARTIALLY_PAID ──refundCreate(部分)──> PARTIALLY_REFUNDED
PAID / PARTIALLY_REFUNDED ──refundCreate(全額)──> REFUNDED  【不可逆】
```

- **不可逆**：`VOIDED`、`EXPIRED`、`REFUNDED` 皆為終態（refund 無法「反退款」，只能再開新訂單）。
- **誰能觸發**：`AUTHORIZED→PAID` 由具 `capture_payments_for_orders` 權限者經 `orderCapture` 觸發（S20）；退款相關由具 `orders` scope 者經 `refundCreate` / `returnProcess` 觸發（S11/S37）。
- **關鍵陷阱**：`VOIDED` 文檔明確聲明「an order can remain open even when its payment is voided」——**金流狀態與訂單開關狀態是兩條獨立的軸**，不可用 financial status 推導訂單是否結案。

**1b. `displayFulfillmentStatus` — OrderDisplayFulfillmentStatus（履行狀態，10 值，其中 3 值已被取代）**（S2）

| 英文原值 | 中文 | 狀態 | 文檔描述（逐字） |
|---|---|---|---|
| `UNFULFILLED` | 未履行 | ✅ 現行 | 「None of the items in the order have been fulfilled.」 |
| `PARTIALLY_FULFILLED` | 部分履行 | ✅ 現行 | 「Some of the items in the order have been fulfilled.」 |
| `FULFILLED` | 已履行 | ✅ 現行 | 「All the items in the order have been fulfilled.」 |
| `IN_PROGRESS` | 處理中 | ✅ 現行 | 「All of the items in the order have had a request for fulfillment sent to the fulfillment service or all of the items have been marked as in progress.」 |
| `ON_HOLD` | 保留中 | ✅ 現行 | 「All of the unfulfilled items in this order are on hold.」 |
| `SCHEDULED` | 已排程 | ✅ 現行 | 「All of the unfulfilled items in this order are scheduled for fulfillment at a later time.」 |
| `REQUEST_DECLINED` | 請求被拒 | ✅ 現行 | 「Some of the items in the order have been rejected for fulfillment by the fulfillment service.」 |
| `OPEN` | （舊）開啟 | ⚠️ 被取代 | 「None of the items in the order have been fulfilled. **Replaced by 'UNFULFILLED' status.**」 |
| `PENDING_FULFILLMENT` | （舊）待履行 | ⚠️ 被取代 | 「A request for fulfillment of some items awaits a response from the fulfillment service. **Replaced by 'IN_PROGRESS' status.**」 |
| `RESTOCKED` | （舊）已補回庫存 | ⚠️ 被取代 | 「All the items in the order have been restocked. **Replaced by 'UNFULFILLED' status.**」 |

- **關鍵**：此狀態是 **derived（衍生）** 的，由該訂單底下所有 FulfillmentOrder 的狀態聚合而成，**不是可直接寫入的欄位**。`ON_HOLD` / `SCHEDULED` 的定義都是「**all of the unfulfilled items**」——只要有一個未履行品項不在 hold，就不會顯示 ON_HOLD。
- 「誰能觸發」：無人直接觸發，全由 FulfillmentOrder 事件重算。

**1c. `returnStatus` — OrderReturnStatus（訂單層退貨聚合狀態，6 值）**（S4）

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `NO_RETURN` | 無退貨 | 「No items in the order were returned.」 |
| `RETURN_REQUESTED` | 已申請退貨 | 「A return was requested for some items in the order.」 |
| `IN_PROGRESS` | 退貨進行中 | 「Some items in the order are being returned.」 |
| `INSPECTION_COMPLETE` | 檢驗完成 | 「All return shipments from a return in this order were inspected.」 |
| `RETURNED` | 已退貨 | 「Some items in the order were returned.」 |
| `RETURN_FAILED` | 退貨失敗 | 「Some returns in the order were not completed successfully.」 |

同樣為衍生欄位；文檔註明它同時是 `orders` query 的**篩選參數**（S4）。

**1d. 生命週期布林旗標**（S1）

| 欄位 | 型別 | 文檔描述（逐字） |
|---|---|---|
| `closed` | Boolean | 「Whether an order is closed. An order is considered closed if all its line items have been fulfilled or canceled, and all financial transactions are complete.」 |
| `closedAt` | DateTime | 結案時間；未結案為 null |
| `cancelledAt` | DateTime | 取消時間；未取消為 null |
| `cancelReason` | OrderCancelReason | 「The reason provided for an order cancellation.」 |
| `confirmed` | Boolean | 「Whether inventory has been reserved for an order.」 |
| `edited` | Boolean | 「Whether the order has had any edits applied.」 |
| `fulfillable` | Boolean | 「Whether there are line items that can be fulfilled.」 |
| `refundable` | Boolean | 「Whether the order can be refunded based on its payment transactions.」 |
| `restockable` | Boolean | 「Whether any line items on the order can be restocked into inventory.」 |
| `unpaid` | Boolean | 「Whether no payments have been made for the order.」 |
| `fullyPaid` | Boolean | 「Whether the order has been paid in full.」 |

**closed 的判定式（逐字）＝ 所有 line item 已履行或已取消 **AND** 所有金流交易完成。**這是兩個條件的合取，實作時不能只看履行。

### ② 欄位與約束

金額欄位（全部為 `MoneyBag`，含 shop／presentment 雙幣別）（S1）：

| 欄位 | 文檔描述（逐字） |
|---|---|
| `subtotalPriceSet` | 「The sum of the prices for all line items after discounts and before returns.」 |
| `currentTotalPriceSet` | 「The total price of the order, **after returns**, in shop and presentment currencies.」 |
| `totalReceivedSet` | 「The total amount received from the customer **before returns**.」 |
| `totalRefundedSet` | 「The total amount that was refunded.」 |
| `netPaymentSet` | 「The net payment for the order, based on the total amount received **minus** the total amount refunded.」 |
| `totalCapturableSet` | 「The authorized amount that's uncaptured or undercaptured.」 |
| `refundDiscrepancySet` | suggested refund 與實際 refund 的差額 |

- **`current*` 前綴 = 退貨後的當前值；無前綴 = 原始下單值**。這是整個 Order 金額模型的核心命名慣例，M4 必須照抄。
- `suggestedRefund`：「A calculated refund suggestion for the order based on specified line items, shipping, and duties.」——是 Order 上的 **query 欄位**（帶參數），非儲存值。
- `transactions`：OrderTransaction 陣列，支援依 capturable／manuallyResolvable 篩選。
- 上限值：**文檔未載明** Order 層的 line item 數上限、tag 數上限等。

### ③ 錯誤碼

Order 物件本身無錯誤碼。各 mutation 的錯誤碼見對應章節。**Shopify 的 Order 相關 mutation 大量使用泛型 `UserError{field, message}`（無 code）**，只有 return／fulfillment hold／order cancel 等較新的 mutation 有具名 code enum。

### ④ 金額規則

- 雙幣別強制：所有金額欄位是 `MoneyBag`（shop currency + presentment currency 兩份）（S1）。
- `netPayment = totalReceived − totalRefunded`（文檔逐字定義）。
- `totalCapturable` = 已授權但未請款或請款不足的金額。

### ⑤ 併發／冪等

Order 讀取層無冪等議題。寫入層見 §9。**文檔未載明** Order 層的樂觀鎖或版本號欄位。

### ⑥ API 操作表

| 操作 | 名稱 | 關鍵 input | 回傳 |
|---|---|---|---|
| 查單 | `order(id:)` / `orders(first:, query:, ...)` | `query` 支援 `return_status` 等篩選（S4） | Order / OrderConnection |
| 更新 | `orderUpdate` | OrderInput | order, userErrors |
| 請款 | `orderCapture` | 見 §8 | OrderTransaction, userErrors |
| 取消 | `orderCancel` | 見 §7 | job, orderCancelUserErrors |
| 標籤 | `tagsAdd` | 「adding tags without overwriting existing ones」（S1） | node, userErrors |

### ⑦ 對 CHILL LOVE 的實作結論

1. **`orders` 表不得有單一 `status` 欄位**。必須落地四個獨立欄位：`display_financial_status`、`display_fulfillment_status`、`return_status`，＋ `closed_at` / `cancelled_at`。前三者全部是 **derived cache**，由 fulfillment_orders / returns / transactions 的 domain event 重算後寫回（配合 CLAUDE.md 鐵律 7「數字同源」，重算邏輯只能有一份）。
2. **只實作 7 個現行 fulfillment 狀態**，`OPEN` / `PENDING_FULFILLMENT` / `RESTOCKED` 三個被取代值不落地——但 GraphQL enum **要保留這三個值**以維持 schema 相容（標 deprecated），否則第三方對接會炸。
3. 金額欄位命名照抄 `current*` 前綴慣例，並依鐵律 3 全部存 integer cents，序列化層才轉 MoneyBag。
4. `closed` 的判定必須是「所有 line item 已履行或已取消 **AND** 所有交易完成」兩個條件；只看履行會導致有未結金流的單被誤判結案。
5. `VOIDED` 不得使訂單自動 closed（文檔明確反例）。

---

## 2. FulfillmentOrder（履行單）

FulfillmentOrder 是整條履約鏈的**核心資料模型**（S5：「FulfillmentOrder Object - Central data model for end-to-end fulfillment processes」）。一張 Order 可拆成多張 FulfillmentOrder（依地點、配送方式）。

### ① 狀態機表

**2a. `status` — FulfillmentOrderStatus（7 值）**（S13）

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `OPEN` | 待處理 | 「The fulfillment order is ready for fulfillment.」 |
| `IN_PROGRESS` | 處理中 | 「The fulfillment order is being processed.」 |
| `SCHEDULED` | 已排程 | 「The fulfillment order is deferred and will be ready for fulfillment after the date and time specified in `fulfill_at`.」 |
| `ON_HOLD` | 保留中 | 「The fulfillment order is on hold. The fulfillment process can't be initiated until the hold on the fulfillment order is released.」 |
| `CLOSED` | 已完成 | 「The fulfillment order has been completed and closed.」 |
| `INCOMPLETE` | 未能完成 | 「The fulfillment order cannot be completed as requested.」 |
| `CANCELLED` | 已取消 | 「The fulfillment order has been cancelled by the merchant.」 |

轉移（由 mutation 語義推導，S12/S22）：

```
SCHEDULED ──fulfillmentOrderOpen──> OPEN
SCHEDULED ──fulfillmentOrderReschedule──> SCHEDULED（改 fulfillAt）
OPEN ──fulfillmentOrderHold──> ON_HOLD
ON_HOLD ──fulfillmentOrderReleaseHold──> OPEN
OPEN ──fulfillmentOrderSubmitFulfillmentRequest──> IN_PROGRESS（requestStatus=SUBMITTED）
OPEN/IN_PROGRESS ──fulfillmentCreate（全部品項）──> CLOSED
OPEN/IN_PROGRESS ──fulfillmentCreate（部分品項）──> 維持 + 剩餘量
IN_PROGRESS ──fulfillmentOrderClose──> INCOMPLETE   ※「Marks in-progress order as incomplete」
任意 ──fulfillmentOrderCancel──> CANCELLED（並「creates replacement for remaining work」）
OPEN ──fulfillmentOrderReportProgress──> IN_PROGRESS
```

- **不可逆**：`CLOSED`、`CANCELLED` 為終態。`fulfillmentOrderCancel` 文檔逐字：「Cancels order and creates replacement for remaining work」——**取消不是就地改狀態，而是產生一張新的替代 FulfillmentOrder 承接剩餘工作**（S12）。這是復刻時極易漏掉的一步。
- `fulfillmentOrderClose` 文檔逐字：「Marks in-progress order as incomplete」——close 導向的是 `INCOMPLETE` 而非 `CLOSED`，命名與結果不一致，需特別注意。

**2b. `requestStatus` — FulfillmentOrderRequestStatus（8 值，與 status 正交）**（S21）

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `UNSUBMITTED` | 未送出 | 「The initial request status for newly-created fulfillment orders. This is the only valid request status for fulfillment orders **not assigned to a fulfillment service**.」 |
| `SUBMITTED` | 已送出 | 「The merchant requested fulfillment for this fulfillment order.」 |
| `ACCEPTED` | 已接受 | 「The fulfillment service accepted the merchant's fulfillment request.」 |
| `REJECTED` | 已拒絕 | 「The fulfillment service rejected the merchant's fulfillment request.」 |
| `CANCELLATION_REQUESTED` | 已請求取消 | 「The merchant requested a cancellation of the fulfillment request for this fulfillment order.」 |
| `CANCELLATION_ACCEPTED` | 取消已接受 | 「The fulfillment service accepted the merchant's fulfillment cancellation request.」 |
| `CANCELLATION_REJECTED` | 取消被拒 | 「The fulfillment service rejected the merchant's fulfillment cancellation request.」 |
| `CLOSED` | 服務方關閉 | 「The fulfillment service closed the fulfillment order without completing it.」 |

**關鍵**：這是**第二條獨立狀態軸**。自營出貨（merchant-managed）的 FulfillmentOrder **永遠停在 `UNSUBMITTED`**（文檔逐字）；只有指派給 fulfillment service 的才會走這條軸。

**2c. `supportedActions` — FulfillmentOrderAction（12 值）**（S22）

文檔為每個 action 明確對應一個 mutation，這是**權限／按鈕可用性的官方來源**：

| 英文原值 | 中文 | 對應 mutation（文檔逐字） |
|---|---|---|
| `CREATE_FULFILLMENT` | 建立出貨 | `fulfillmentCreateV2` |
| `REQUEST_FULFILLMENT` | 請求履行 | `fulfillmentOrderSubmitFulfillmentRequest` |
| `CANCEL_FULFILLMENT_ORDER` | 取消履行單 | `fulfillmentOrderCancel` |
| `REQUEST_CANCELLATION` | 請求取消 | `fulfillmentOrderSubmitCancellationRequest` |
| `HOLD` | 保留 | `fulfillmentOrderHold` |
| `RELEASE_HOLD` | 解除保留 | `fulfillmentOrderReleaseHold` |
| `MOVE` | 移動地點 | `fulfillmentOrderMove` |
| `SPLIT` | 拆分 | `fulfillmentOrderSplit` |
| `MERGE` | 合併 | `fulfillmentOrderMerge` |
| `MARK_AS_OPEN` | 標記為開啟 | `fulfillmentOrderOpen` |
| `REPORT_PROGRESS` | 回報進度 | 「marking as in progress if it's not already in progress」 |
| `EXTERNAL` | 外部連結 | 「Opens an external URL... paired with `FulfillmentOrderSupportedAction.externalUrl`」 |

**2d. `fulfillmentHolds[].reason` — FulfillmentHoldReason（8 值）**（S23）

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `AWAITING_PAYMENT` | 等待付款 | 「The fulfillment hold is applied because payment is pending.」 |
| `AWAITING_RETURN_ITEMS` | 等待退貨到貨 | 「...because of return items not yet received during an exchange.」 |
| `HIGH_RISK_OF_FRAUD` | 高詐騙風險 | 「...because of a high risk of fraud.」 |
| `INCORRECT_ADDRESS` | 地址錯誤 | 「...because of an incorrect address.」 |
| `INVENTORY_OUT_OF_STOCK` | 庫存不足 | 「...because inventory is out of stock.」 |
| `UNKNOWN_DELIVERY_DATE` | 配送日未定 | 「...because of an unknown delivery date.」 |
| `ONLINE_STORE_POST_PURCHASE_CROSS_SELL` | 購後加購 | 「...because of a post purchase upsell offer.」 |
| `OTHER` | 其他 | 「The fulfillment hold is applied for another reason.」 |

**`AWAITING_RETURN_ITEMS` 是換貨流程的專用 hold reason**——見 §4 換貨。

**2e. `FulfillmentOrderRejectionReason`（14 值）**（S24）

`INCORRECT_ADDRESS`（地址錯誤）、`INCORRECT_PRODUCT_INFO`（商品資訊錯誤）、`INELIGIBLE_PRODUCT`（商品不符資格）、`INTERNATIONAL_SHIPPING_UNAVAILABLE`（未開通國際配送）、`INVALID_CONTACT_INFORMATION`（聯絡資訊無效）、`INVALID_SKU`（SKU 無效）、`INVENTORY_OUT_OF_STOCK`（庫存不足）、`MERCHANT_BLOCKED_OR_SUSPENDED`（商家被封鎖或停權）、`MISSING_CUSTOMS_INFO`（缺報關資訊）、`ORDER_TOO_LARGE`（訂單過大）、`PACKAGE_PREFERENCE_NOT_SET`（未設定包裝偏好）、`PAYMENT_DECLINED`（付款被拒）、`UNDELIVERABLE_DESTINATION`（無法配送目的地）、`OTHER`（其他）。

### ② 欄位與約束

（S12）

| 欄位 | 型別 | 說明（逐字） |
|---|---|---|
| `status` | FulfillmentOrderStatus! | 必填 |
| `requestStatus` | FulfillmentOrderRequestStatus! | 必填 |
| `assignedLocation` | FulfillmentOrderAssignedLocation! | 「The location where the fulfillment is expected to happen」 |
| `destination` | FulfillmentOrderDestination | 「The destination where the items should be sent」 |
| `deliveryMethod` | DeliveryMethod | 配送方式 |
| `fulfillAt` | DateTime | 「Date and time when order becomes fulfillable」 |
| `fulfillBy` | DateTime | 履行截止時間 |
| `lineItems` | FulfillmentOrderLineItemConnection! | 必填 |
| `fulfillmentHolds` | [FulfillmentHold!]! | 「Fulfillment holds applied on the order」 |
| `merchantRequests` | FulfillmentOrderMerchantRequestConnection! | 「Requests sent by merchant or order management app」 |
| `supportedActions` | [FulfillmentOrderSupportedAction!]! | 「Actions that can be performed on order」 |
| `fulfillmentOrdersForMerge` | FulfillmentOrderConnection! | 「Orders eligible for merging」 |
| `locationsForMove` | FulfillmentOrderLocationForMoveConnection! | 「Potential relocation destinations」 |
| `remainingLineItemsWeight` | Weight | 未履行品項總重 |
| `orderName` / `orderId` / `orderProcessedAt` | — | 反正規化欄位 |
| `channelId` | ID | **已 DEPRECATED** |

**明確上限值**：
- **每張 FulfillmentOrder 最多 10 個 active hold**（API 2025-01 起支援多重 hold）。文檔逐字：「up to "10 active holds per fulfillment order"。If this limit is exceeded, the mutation returns a user error, requiring the app to release existing holds first.」（S27）
- `fulfillmentOrderSplit` 的最大拆分數：**文檔未載明**（S28 頁面未列出）。
- `fulfillmentCreate` 的 tracking number／url 數量上限：**文檔未載明**（S26 僅說「supports multiple numbers/URLs」）。

**Access scopes**（S12）：`read/write_assigned_fulfillment_orders`（給 fulfillment service）、`read/write_merchant_managed_fulfillment_orders`（自營地點）、`read/write_third_party_fulfillment_orders`（第三方）。**三種來源的履行單權限是分開的**。

`fulfillmentCreate` 另需 user permission `fulfill_and_ship_orders`（S26）；`fulfillmentOrderHold`、`fulfillmentOrderSplit` 同樣需要（S27/S28）。

### ③ 錯誤碼

- `FulfillmentOrderHoldUserErrorCode`：文檔在 S12 列出此 enum 存在，**具體值未載明**（S27 頁面未展開清單）。已知觸發條件一項：超過 10 個 active hold 會回 user error。
- `FulfillmentOrderSplitUserErrorCode`：存在，**具體值文檔未載明**（S28 逐字：「Complete schema details regarding maximum splits permitted and all error codes are not explicitly stated」）。
- `fulfillmentCreate`：回傳泛型 `userErrors`，**code 清單文檔未載明**。

### ④ 金額規則

FulfillmentOrder 本身不持有金額。不適用。

### ⑤ 併發／冪等

- `fulfillmentCreate`、`fulfillmentOrder*` 系列**不在** 2026-04 強制冪等的 17 個 mutation 名單內（該名單以 inventory 與 refund 為主，見 §9）（S49）。
- **文檔未載明** FulfillmentOrder 的樂觀鎖機制。但 `supportedActions` 實質上是伺服器端的前置條件檢查——客戶端應在每次操作前重讀 `supportedActions`，這是文檔給的併發防護慣例（S22）。

### ⑥ API 操作表

| 分類 | Mutation | 關鍵 input | 回傳 |
|---|---|---|---|
| 出貨 | `fulfillmentCreate` | `FulfillmentInput{ lineItemsByFulfillmentOrder!(必填), trackingInfo, notifyCustomer, originAddress(countryCode 必填) }` | fulfillment, userErrors |
| 請求 | `fulfillmentOrderSubmitFulfillmentRequest` | fulfillmentOrderId, message, notifyCustomer | fulfillmentOrder, userErrors |
| 接受請求 | `fulfillmentOrderAcceptFulfillmentRequest` | id, message | fulfillmentOrder |
| 拒絕請求 | `fulfillmentOrderRejectFulfillmentRequest` | id, reason(FulfillmentOrderRejectionReason), message, lineItems | fulfillmentOrder |
| 請求取消 | `fulfillmentOrderSubmitCancellationRequest` | id, message | fulfillmentOrder |
| 接受取消 | `fulfillmentOrderAcceptCancellationRequest` | id, message | fulfillmentOrder |
| 拒絕取消 | `fulfillmentOrderRejectCancellationRequest` | id, message | fulfillmentOrder |
| 取消 | `fulfillmentOrderCancel` | id | fulfillmentOrder, **replacementFulfillmentOrder** |
| 關閉 | `fulfillmentOrderClose` | id, message | fulfillmentOrder |
| 開啟 | `fulfillmentOrderOpen` | id | fulfillmentOrder |
| 改排程 | `fulfillmentOrderReschedule` | id, fulfillAt | fulfillmentOrder |
| 保留 | `fulfillmentOrderHold` | id!, fulfillmentHold!{ reason, reasonNotes, notifyMerchant, handle, fulfillmentOrderLineItems } | fulfillmentHold, fulfillmentOrder, **remainingFulfillmentOrder**, userErrors |
| 解除保留 | `fulfillmentOrderReleaseHold` | id, externalId/handle | fulfillmentOrder |
| 移動 | `fulfillmentOrderMove` | id, newLocationId, lineItems | movedFulfillmentOrder, originalFulfillmentOrder, remainingFulfillmentOrder |
| 拆分 | `fulfillmentOrderSplit` | `fulfillmentOrderSplits!: [FulfillmentOrderSplitInput!]` | fulfillmentOrderSplits[FulfillmentOrderSplitResult], userErrors |
| 合併 | `fulfillmentOrderMerge` | fulfillmentOrderMergeInputs | fulfillmentOrderMerges |
| 改派路由 | `fulfillmentOrdersReroute` | 「Routes to alternative location per shop settings」 | — |
| 回報進度 | `fulfillmentOrderReportProgress` | id | fulfillmentOrder |

**`fulfillmentOrderHold` 回傳 `remainingFulfillmentOrder`**——當只 hold 部分 line item 時，系統自動拆出一張新的 FulfillmentOrder 承接未 hold 的品項（S27）。`fulfillmentOrderMove` 同理。

### ⑦ 對 CHILL LOVE 的實作結論

6. **必須落地 FulfillmentOrder 這一層**，不能用「order + shipment」兩層簡化。整條履約鏈（hold／split／merge／move／換貨 hold）都掛在這一層；沒有它，M4 的按鈕清單無法實作。
7. **`status` 與 `requestStatus` 是兩個獨立欄位**，自營出貨永遠 `UNSUBMITTED`。CHILL LOVE 初期無第三方 fulfillment service，`requestStatus` 仍要建欄位並固定寫 `UNSUBMITTED`，否則未來接 3PL 要改 schema。
8. **`supportedActions` 做成伺服器端計算欄位**，admin SPA 的按鈕啟用/停用完全由它驅動（對照 `docs/research/22` §1b guard 清單）。不要在前端重寫一套 guard 邏輯——兩份邏輯必然漂移。
9. **「取消產生替代單」與「部分 hold/move 產生 remaining 單」這兩個拆單語義必須實作**，且新單要繼承 `shop_id` 與原單關聯。這是最容易漏、漏了會導致品項憑空消失的地方。
10. `config/limits.yml` 新增 `fulfillment_order.max_active_holds: 10`（出處 S27）。
11. `fulfillmentOrderClose → INCOMPLETE`（不是 CLOSED）務必照抄，中文 UI 標「未能完成」。

---

## 3. Fulfillment（出貨單）

### ① 狀態機表

`FulfillmentStatus`（6 值，其中 2 值已 deprecated）（S25）：

| 英文原值 | 中文 | 狀態 | 文檔描述（逐字） |
|---|---|---|---|
| `SUCCESS` | 成功 | ✅ | 「The fulfillment was completed successfully.」 |
| `CANCELLED` | 已取消 | ✅ | 「The fulfillment was canceled.」 |
| `ERROR` | 錯誤 | ✅ | 「There was an error with the fulfillment request.」 |
| `FAILURE` | 失敗 | ✅ | 「The fulfillment request failed.」 |
| `OPEN` | （舊） | ⚠️ deprecated | — |
| `PENDING` | （舊） | ⚠️ deprecated | — |

### ② 欄位與約束

`FulfillmentInput`（S26）：

| 欄位 | 必填 | 說明 |
|---|---|---|
| `lineItemsByFulfillmentOrder` | ✅ 必填 | 「Array specifying which items to fulfill」；可跨多張 FulfillmentOrder，但**必須屬於同一 order 且同一 location**（文檔逐字：「creates fulfillments for one or more FulfillmentOrder objects associated with the same order and location」） |
| `trackingInfo` | 否 | 「Carrier and tracking number details (supports multiple numbers/URLs)」 |
| `notifyCustomer` | 否 | 是否寄出貨通知 |
| `originAddress` | 否 | **countryCode 為必填子欄位** |

**互斥／約束**：一次 `fulfillmentCreate` 的所有 FulfillmentOrder 必須同 order 同 location——跨地點必須分多次呼叫。tracking number／url 上限：**文檔未載明**。

### ③ 錯誤碼

泛型 `userErrors`，**code 清單文檔未載明**。

### ④ 金額規則

不適用（Fulfillment 不持有金額）。

### ⑤ 併發／冪等

**文檔未載明**；不在強制冪等名單內（S49）。

### ⑥ API 操作表

| 操作 | 名稱 | 說明 |
|---|---|---|
| 建立出貨 | `fulfillmentCreate` | 需 `fulfill_and_ship_orders` 權限 |
| 更新追蹤 | `fulfillmentTrackingInfoUpdate` | （由 S12 mutation 清單推得，本次未單獨抓取頁面） |
| 取消出貨 | `fulfillmentCancel` | 同上 |

### ⑦ 對 CHILL LOVE 的實作結論

12. Fulfillment 的 `status` 只實作 4 個現行值。`SUCCESS` 與 `CANCELLED` 是主要路徑，`ERROR`/`FAILURE` 保留給未來 3PL 對接。
13. **「同 order 同 location」約束要在 service 層驗證並回 `userErrors`**，不要靠 DB constraint（跨地點是合法的多次呼叫，不是資料錯誤）。

---

## 4. Return（退貨）＋ Exchange（換貨）

### ① 狀態機表

`ReturnStatus`（5 值）（S9）：

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `REQUESTED` | 已申請 | 「The return was requested.」 |
| `OPEN` | 進行中 | 「The return is in progress.」 |
| `DECLINED` | 已拒絕 | 「The return was declined.」 |
| `CLOSED` | 已完成 | 「The return has been completed.」 |
| `CANCELED` | 已取消 | 「The return has been canceled.」（注意：**單 L 拼寫** `CANCELED`，與 FulfillmentOrderStatus 的 `CANCELLED` 雙 L 不同） |

**完整轉移圖**（S6 逐字整理）：

```
（無）──returnRequest──> REQUESTED
（無）──returnCreate──> OPEN          ※ 跳過審核，直接開啟
REQUESTED ──returnApproveRequest──> OPEN      【不可逆：「Approving a return is a permanent action」】
REQUESTED ──returnDeclineRequest(reason)──> DECLINED  【不可逆：「cannot revert to REQUESTED」】
OPEN ──returnProcess(全部品項處理完)──> CLOSED
OPEN ──returnLineItemRemoveFromReturn(移除最後一項)──> CLOSED（自動）
OPEN ──returnClose──> CLOSED
OPEN ──returnCancel──> CANCELED
CLOSED ──returnReopen──> OPEN
```

**誰能觸發**：
- `REQUESTED` 由買家端（self-serve returns）或 app 觸發 `returnRequest`。
- `OPEN` 由商家審核（`returnApproveRequest`）或商家直接建立（`returnCreate`，「Assumes customer approval already obtained」）。
- 全部 return mutation 需 `write_returns` 或 `write_marketplace_returns` scope（S37/S38/S39）。

**不可逆轉移（文檔明示）**：
- `REQUESTED → OPEN`：「Approving a return is a permanent action」（S7）
- `REQUESTED → DECLINED`：「Permanent action – cannot revert to REQUESTED」（S7）
- `DECLINED` 為終態，無 mutation 可離開。

**`returnCancel` 的合法條件（S7 逐字）**：
- 必須在 `OPEN` 狀態
- **不得**有：已取消的 fulfillment、已發生的 refund、已做的 disposition、Shopify Shipping 產生的退貨標籤
- 手動上傳的標籤**可以**（「Manually-uploaded labels permissible」）
- S39 逐字補充：「Canceling a return is only available before any work has been done on the return (such as an inspection or refund).」
- 效果：「All sales records generated from the creation of a return will be reversed」（S7）
- 換貨品項**不受**退貨取消影響（「Exchange items unaffected by return cancellation」，S7）

**`REQUESTED` 狀態不能直接取消**（S7 逐字：「Cannot be canceled directly – must approve/decline instead」）。

**副作用**：建立或申請退貨會**自動解除訂單封存**（S7 逐字：「Archived orders — Auto-unarchives when return created/requested」）。

### ② 欄位與約束

**Return 物件**（S8）：

| 欄位 | 型別 | 說明（逐字） |
|---|---|---|
| `status` | ReturnStatus! | 「The status of the return」 |
| `name` | String! | 「The name of the return」 |
| `order` | Order! | 所屬訂單 |
| `returnLineItems` | ReturnLineItemTypeConnection! | 退貨品項 |
| `exchangeLineItems` | ExchangeLineItemConnection! | 「The exchange line items attached to the return」 |
| `returnShippingFees` | [ReturnShippingFee!]! | 「The return shipping fees for the return」 |
| `reverseFulfillmentOrders` | ReverseFulfillmentOrderConnection! | 逆向履行單 |
| `refunds` | RefundConnection! | 「The list of refunds associated with the return」 |
| `totalQuantity` | Int! | 「The sum of all return line item quantities」 |
| `decline` | ReturnDecline | 「Additional information about the declined return」 |
| `requestApprovedAt` | DateTime | 核准時間 |
| `closedAt` | DateTime | 結案時間 |

**`ReturnInput`（returnCreate 的 input）**（S32）：

| 欄位 | 型別 | 必填 | 說明（逐字） |
|---|---|---|---|
| `orderId` | ID | ✅ | 「The ID of the order to be returned.」 |
| `returnLineItems` | [ReturnLineItemInput!]! | ✅ | 「The return line items list to be handled.」 |
| `exchangeLineItems` | [ExchangeLineItemInput!] | ✗ | 「The new line items to be added to the order.」 |
| `requestedAt` | DateTime | ✗ | 「The UTC date and time when the return was first solicited by the customer.」 |
| `returnShippingFee` | ReturnShippingFeeInput | ✗ | 「The return shipping fee to capture.」 |
| `notifyCustomer` | Boolean | ✗ | **已 deprecated**（default false） |
| `unprocessed` | Boolean | ✗ | **已 deprecated**（default false） |

**`ReturnLineItemInput`**（S33）：

| 欄位 | 型別 | 必填 | 說明（逐字）／上限 |
|---|---|---|---|
| `fulfillmentLineItemId` | ID! | ✅ | 「The ID of the fulfillment line item to be returned」——**注意是 fulfillment line item，不是 order line item**（只有已出貨的才能退） |
| `quantity` | Int! | ✅ | 「The quantity of the item to be returned」 |
| `restockingFee` | RestockingFeeInput | ✗ | 「The restocking fee to capture.」 |
| `returnReasonDefinitionId` | ID | ✗ | 標準化退貨原因庫的 ID |
| `returnReasonNote` | String | ✗ | 「A note about the reason that the item is being returned」，**上限 255 字元** |
| `returnReason` | ReturnReason | ✗ | **已 deprecated**（改用 `returnReasonDefinitionId`） |

**`RestockingFeeInput`**（S34）：單一欄位 `percentage: Float!`（**必填**），「The value of the fee as a percentage.」——**是百分比，不是金額**。最大值：**文檔未載明**。被 `CalculateReturnLineItemInput`、`ReturnLineItemInput`、`ReturnRequestLineItemInput` 三處共用。

**`ReturnShippingFeeInput`**（S35）：單一欄位 `amount: MoneyInput!`（**必填**），「The value of the fee as a fixed amount **in the presentment currency of the order**.」——**是固定金額，且必須是 presentment 幣別**。

> **不對稱設計**：restocking fee 是**百分比**（per line item），return shipping fee 是**固定金額**（per return）。這個不對稱是 Shopify 的刻意設計，M4 必須照抄。

**`ReturnReason`（10 值，已 deprecated 但仍需支援）**（S30）：`COLOR`（顏色不喜歡）、`DEFECTIVE`（瑕疵損壞）、`NOT_AS_DESCRIBED`（與描述不符）、`SIZE_TOO_LARGE`（尺寸過大）、`SIZE_TOO_SMALL`（尺寸過小）、`STYLE`（款式不喜歡）、`UNWANTED`（改變心意）、`WRONG_ITEM`（收到錯品）、`UNKNOWN`（原因不明）、`OTHER`（其他，「For this value, a return reason note is also provided.」）。

**`ReturnDeclineReason`（3 值）**（S31）：`FINAL_SALE`（最終出清品）、`RETURN_PERIOD_ENDED`（退貨期已過）、`OTHER`（其他）。

**`ReturnProcessInput`**（S36）：

| 欄位 | 型別 | 必填 | 說明（逐字） |
|---|---|---|---|
| `returnId` | ID | ✅ | 「The ID of the return to be processed.」 |
| `returnLineItems` | [ReturnProcessReturnLineItemInput!] | ✗ | 「The return line items list to be handled.」（default `[]`） |
| `exchangeLineItems` | [ReturnProcessExchangeLineItemInput!] | ✗ | 「The exchange line items list to be handled.」（default `[]`） |
| `refundDuties` | [RefundDutyInput!] | ✗ | 「The refund duties list to be handled.」（default `[]`） |
| `refundShipping` | ReturnProcessFinancialTransferInput | ✗ | 「The shipping cost to refund.」 |
| `financialTransfer` | ReturnProcessFinancialTransferInput | ✗ | 「The financial transfer for the return.」 |
| `notifyCustomer` | Boolean | ✗ | 「Whether to notify the customer about the return.」（default false） |
| `note` | String | ✗ | 「The note for the return.」 |
| `tipLineId` | ID | ✗ | 「ID of the tip line item.」 |

`returnProcess` 每個 line item 的 disposition 內容（S7）：`dispositionType`（RESTOCKED／MISSING／DISCARDED 等）、restock 的 `locationId`、對應的 reverse fulfillment order line item ref。

**換貨（Exchange）機制**（S7 逐字）：
- 在 `returnCreate` 時以 `exchangeLineItems` 指定替換品的 variant ID 與數量。
- 系統會建立 fulfillment order，狀態為 **`ON_HOLD`**，hold reason 為 **`AWAITING_RETURN_ITEMS`**。
- 換貨品項的銷售紀錄（sales records）自動建立。
- 若換貨品價值高於退貨品，可向買家收取差額（「potentially collecting balances」）。

### ③ 錯誤碼

**`ReturnErrorCode`（26 值，`ReturnUserError.code` 使用）**——這是本研究中**唯一一份完整的錯誤碼清單**（S29）：

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `ALREADY_EXISTS` | 已存在 | 「The requested resource already exists.」 |
| `BLANK` | 空白 | 「The input value is blank.」 |
| `CREATION_FAILED` | 建立失敗 | 「A requested resource could not be created.」 |
| `EQUAL_TO` | 須等於 | 「The input value should be equal to the value allowed.」 |
| `FEATURE_NOT_ENABLED` | 功能未啟用 | 「A required feature is not enabled.」 |
| `GREATER_THAN` | 須大於 | 「The input value should be greater than the minimum allowed value.」 |
| `GREATER_THAN_OR_EQUAL_TO` | 須大於等於 | 「The input value should be greater than or equal to the minimum value allowed.」 |
| `INCLUSION` | 不在允許清單 | 「The input value isn't included in the list.」 |
| `INCOMPATIBLE_WITH_STANDARD_POLICY` | 與標準退貨政策衝突 | 「The requested configuration cannot be applied to this standard return policy which is managed for you in compliance with relevant regulations.」 |
| `INTERNAL_ERROR` | 內部錯誤 | 「Unexpected internal error happened.」 |
| `INVALID` | 無效 | 「The input value is invalid.」 |
| `INVALID_STATE` | 狀態不符 | 「A resource was not in the correct state for the operation to succeed.」 |
| `LESS_THAN` | 須小於 | 「The input value should be less than the maximum value allowed.」 |
| `LESS_THAN_OR_EQUAL_TO` | 須小於等於 | 「The input value should be less than or equal to the maximum value allowed.」 |
| `MISSING_PERMISSION` | 缺少權限 | 「The user does not have permission to perform the operation.」 |
| `NOT_A_NUMBER` | 非數字 | 「The input value is not a number.」 |
| `NOT_EDITABLE` | 不可編輯 | 「A requested item is not editable.」 |
| `NOT_FOUND` | 找不到 | 「A requested item could not be found.」 |
| `NOTIFICATION_FAILED` | 通知失敗 | 「A requested notification could not be sent.」 |
| `PRESENT` | 須為空 | 「The input value needs to be blank.」 |
| `TAKEN` | 已被佔用 | 「The input value is already taken.」 |
| `TOO_BIG` | 值過大 | 「The input value is too big.」 |
| `TOO_LONG` | 過長 | 「The input value is too long.」 |
| `TOO_MANY_ARGUMENTS` | 參數過多 | 「Too many arguments provided.」 |
| `TOO_SHORT` | 過短 | 「The input value is too short.」 |
| `WRONG_LENGTH` | 長度錯誤 | 「The input value is the wrong length.」 |

**`INVALID_STATE` 是狀態機違規的統一錯誤碼**（例如對 `DECLINED` 的 return 呼叫 `returnProcess`）。

### ④ 金額規則

**退款計算公式（2024-07 起變更，重大）**（S50）：

- 舊邏輯：refund = 退貨品項價值。
- **新邏輯（2024-07 / 2024-07-01 起）**：「The refund amount considers exchange line items and fees on the return, as well as any outstanding amount owed by the buyer on an order.」
- **公式：`refund = 退貨品項價值 − 退貨相關費用 − 換貨扣抵`**
- 文檔範例：$50.99 品項 − $5.00 return fee = **$45.99** 建議退款。
- **下限鉗制（逐字）**：「If the return fee was greater than $50.99 CAD, the suggested amount cannot be lower than $0 CAD」——**退款金額不得為負，一律 floor 到 0**。
- 此變更標記為「Action required」，2024-07 以前版本維持舊算法。

**`SuggestedReturnRefund` 欄位**（S43）：`amount`、`discountedSubtotal`、`maximumRefundable`（「The total monetary value available to refund」）、`subtotal`、`shipping`、`totalTax`（「The value must be positive.」）、`totalDuties`（「The value must be positive.」）、`totalCartDiscountAmount`、`refundDuties`、`suggestedTransactions`。

**`maximumRefundable` 的計算式：文檔未載明**（S42/S43 皆只給定義「可退的總額上限」，未給公式）。

**Restocking fee**：百分比制，按 line item subtotal 計算，「Supports partial returns with different fees per item」——**同一張退貨的不同品項可以有不同的 restocking fee 百分比**（S7）。

**Return shipping fee**：固定金額，per return，presentment 幣別（S35）。

**關稅退款（duties）**（S52）：兩種模式——
- `PROPORTIONAL`：「refunds duties in proportion to the line item quantity that you want to refund」，**必須同時傳 refund line items 才能算出比例**。
- `FULL`：「refunds all the duties associated with a duty ID」，不需要 line item 細節。
- `refundDuties` input 需要 duty ID ＋ refund type 兩個參數。

### ⑤ 併發／冪等

- Return mutation **不在** 2026-04 強制冪等名單內（S49）。
- 但 `returnProcess` 內含退款（`financialTransfer.issueRefund`），實質上是金流寫入——**文檔未載明**其冪等保證。這是文檔的空白處，也是最危險的地方（重試會重複退款）。
- 併發防護：`returnCancel` 的前置條件（不得已有 refund/disposition）本身就是一道樂觀檢查（S7/S39）。

### ⑥ API 操作表

| 操作 | 名稱 | 關鍵 input | 回傳 |
|---|---|---|---|
| 查可退品項 | `returnableFulfillments(orderId:)` | orderId | fulfillment line item id、可退數量。**前提：「A returnable fulfillment is an order that has been delivered」**（S7） |
| 試算 | `returnCalculate(input:)` | `CalculateReturnInput` | `CalculatedReturn{ returnLineItems, exchangeLineItems, returnShippingFee, id }`；預覽 refund／稅／restocking fee／return shipping fee／訂單級折扣重分配（S40）。**不建立資料** |
| 建立（免審） | `returnCreate(returnInput:)` | ReturnInput | return（狀態 `OPEN`），userErrors |
| 申請（需審） | `returnRequest(input:)` | ReturnRequestInput | return（狀態 `REQUESTED`），userErrors |
| 核准 | `returnApproveRequest(input:)` | returnId | return（`OPEN`），建立 reverse fulfillment order |
| 拒絕 | `returnDeclineRequest(input:)` | returnId, declineReason **必填** | return（`DECLINED`） |
| 移除品項 | `returnLineItemRemoveFromReturn` | returnId, returnLineItems | return；移到最後一項會自動 CLOSE |
| 處理＋退款 | `returnProcess(input:)` | ReturnProcessInput（見上表） | return, `[ReturnUserError!]!` |
| 取消 | `returnCancel(id:, notifyCustomer:)` | id（notifyCustomer 已 deprecated） | return, ReturnUserError |
| 關閉 | `returnClose(id:)` | id | return（`CLOSED`） |
| 重開 | `returnReopen(id:)` | id | return（`OPEN`） |
| 財務預測 | `suggestedFinancialOutcome` | — | 折後小計、稅、關稅、運費可退性、**maximumRefundable**、退款方式配置（S7） |
| 逆向處置 | `reverseFulfillmentOrderDispose` | dispositionInputs | reverseFulfillmentOrderLineItems |
| 建立退貨物流 | `reverseDeliveryCreateWithShipping` | reverseFulfillmentOrderId, reverseDeliveryLineItems, trackingInput, labelInput | reverseDelivery |

**已 deprecated：`returnRefund`**（S41 逐字：「Deprecated mutation for refunding returns without restocking input」）。

### ⑦ 對 CHILL LOVE 的實作結論

14. **`returnCreate` 與 `returnRequest` 是兩個不同入口**，必須都做：前者給後台商家（直接 `OPEN`），後者給買家自助退貨（`REQUESTED` 待審）。`REQUESTED` 不可直接取消，只能核准或拒絕——這條 guard 要寫進 state machine。
15. **核准與拒絕都是不可逆的**（文檔明示 permanent）。UI 上必須有二次確認彈窗（對照 `docs/research/22` 的破壞性操作規範）。
16. **退貨的來源是 fulfillment line item 而非 order line item**（`fulfillmentLineItemId`），且前提是「已送達」。CHILL LOVE 的 `return_line_items` 外鍵必須指向 `fulfillment_line_items`。這決定了 schema，改不得。
17. **費用模型照抄不對稱設計**：`restocking_fee_percentage`（decimal，per line item）＋ `return_shipping_fee_cents`（integer cents，per return，presentment 幣別）。
18. **退款公式 `退貨品項價值 − 退貨費用 − 換貨扣抵`，並 floor 到 0**（出處 S50）。這是併發測試「退款上限」的判定基準（CLAUDE.md 驗收要求）。
19. **換貨要產生 `ON_HOLD` + `AWAITING_RETURN_ITEMS` 的 fulfillment order**，退貨收到後才解 hold。這是換貨流程的骨架，不能簡化成「退一單開一單」。
20. `ReturnErrorCode` 26 值**全部落地**為 CHILL LOVE 的 `userErrors.code`（鐵律 4）。`INVALID_STATE` 作為狀態機違規的統一碼。
21. `returnReasonNote` 上限 255，寫進 `config/limits.yml`（鐵律 6）。
22. **`returnProcess` 的冪等文檔未載明——CHILL LOVE 必須自行強制 `idempotencyKey`**（鐵律 5 已要求退款必帶）。不要因為 Shopify 沒寫就不做。
23. `returnCalculate` 要做，且必須與 `returnProcess` 共用同一份計算程式碼（鐵律 7 數字同源），否則預覽與實際退款會對不上。

---

## 5. ReverseFulfillmentOrder / ReverseDelivery（逆向履行）

### ① 狀態機表

**`ReverseFulfillmentOrderStatus`（3 值）**（S45）：

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `OPEN` | 進行中 | 「The reverse fulfillment order is in progress.」 |
| `CLOSED` | 已完成 | 「The reverse fulfillment order has been completed.」 |
| `CANCELED` | 已取消 | 「The reverse fulfillment order has been canceled.」 |

**`ReverseFulfillmentOrderDispositionType`（4 值）**（S46）：

| 英文原值 | 中文 | 文檔描述（逐字） |
|---|---|---|
| `RESTOCKED` | 已補回庫存 | 「An item that was restocked.」 |
| `NOT_RESTOCKED` | 未補回庫存 | 「An item that wasn't restocked.」 |
| `MISSING` | 缺件 | 「An item that was expected but absent.」 |
| `PROCESSING_REQUIRED` | 需進一步處理 | 「An item that requires further processing before being restocked or discarded.」 |

**`PROCESSING_REQUIRED` 是中間態**——代表檢驗後尚未決定，稍後仍需再次 disposition。這使 disposition 成為可多次執行的操作，而非一次性終態。

### ② 欄位與約束

（S44）`id`、`status`、`lineItems`（ReverseFulfillmentOrderLineItemConnection!）、`order`、`reverseDeliveries`（ReverseDeliveryConnection!）、`thirdPartyConfirmation`（第三方物流確認，不適用時為 null）。

Reverse delivery 定義（S6 逐字）：「Sets of items packaged together for return shipment, including delivery metadata like labels and tracking information.」

**上限值**：**文檔未載明**（每張 RFO 的 delivery 數、label 數等）。

### ③ 錯誤碼

**文檔未載明**（S44 頁面未列出 mutation 與錯誤碼）。推測共用 `ReturnErrorCode`／`ReturnUserError`，但**未經文檔確認**。

### ④ 金額規則

RFO 本身不持有金額；restock 決策透過 `returnProcess` 的 disposition 影響庫存與財報（S6：「The returnProcess mutation handles restock decisions as part of financial reporting updates」）。

### ⑤ 併發／冪等

**文檔未載明**。

### ⑥ API 操作表

| 操作 | 名稱 | 說明 |
|---|---|---|
| 處置 | `reverseFulfillmentOrderDispose` | 設定 disposition type ＋ restock location |
| 建立退貨物流（含運送） | `reverseDeliveryCreateWithShipping` | 產生退貨標籤與追蹤 |
| 更新退貨物流 | `reverseDeliveryShippingUpdate` | 更新標籤／追蹤 |

（此三者於 S6 指南頁被提及，S44 物件頁未展開；細部 input schema **本次未取得**。）

### ⑦ 對 CHILL LOVE 的實作結論

24. **M4 可以先只做 `RESTOCKED` / `NOT_RESTOCKED` 兩種 disposition**，但 enum 要一次定義完 4 值，`MISSING` 與 `PROCESSING_REQUIRED` 留給 M5。
25. Disposition **不是一次性終態**（`PROCESSING_REQUIRED` 可再處理），資料表要允許同一 line item 多筆 disposition 紀錄，取最新一筆為準。
26. Reverse delivery 的標籤／追蹤在 M4 只做「手動上傳追蹤碼」——Shopify Shipping 標籤是自營物流整合，超出 M4 範圍（且它會鎖住 `returnCancel`，見 §4）。

---

## 6. Refund（退款）

### ① 狀態機表

**Refund 沒有 status 欄位**。退款的「狀態」由其底下的 `OrderTransaction` 承載。S41 逐字警告：「A Refund object's existence doesn't guarantee payment completion; check associated OrderTransaction statuses for actual processing confirmation.」

→ **Refund 是不可變的帳務紀錄，不是狀態機。** 訂單層的退款狀態則反映在 `displayFinancialStatus` 的 `PARTIALLY_REFUNDED` / `REFUNDED`（見 §1）。

### ② 欄位與約束

**Refund 物件**（S41）：`totalRefundedSet`（MoneyBag!，「The total amount across all transactions for the refund」）、`refundLineItems`、`refundShippingLines`、`duties`、`transactions`、`note`、`createdAt`、`updatedAt`、`order`（Order!）、`return`（Return，若由退貨流程發起）、`staffMember`。

**`RefundInput`**（S11）：

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `orderId` | ID | ✅ | 退款對應的訂單 |
| `refundLineItems` | [RefundLineItemInput!] | ✗ | 品項與數量 |
| `refundShipping` | RefundShippingInput | ✗ | 運費退款 |
| `refundDuties` | [RefundDutyInput!] | ✗ | 關稅退款 |
| `transactions` | [OrderTransactionInput!] | ✗ | 退款交易 |
| `note` | String | ✗ | 備註 |
| `notify` | Boolean | ✗ | 是否通知買家 |
| `refundMethods` | [RefundMethodInput!] | ✗ | 退款方式（如 store credit 商店購物金） |

**`RefundLineItemInput`**：`lineItemId`（ID，必填）、`quantity`（Int，必填）、`restockType`（RestockType，選填）。

**`RestockType`（3 值）**（S11）：`RESTOCK`（補回庫存）、`NO_RESTOCK`（不補回）、`LEGACY_RESTOCK`（**已 deprecated**）。

**`RefundShippingInput`**：`amount`（Decimal，選填，指定運費退款金額）、`fullRefund`（Boolean，選填，全額退運費）。**兩者實務上互斥**（同時給的行為：**文檔未載明**）。

**`RefundDutyInput`**：`dutyId`（ID，必填）＋ refund type（`PROPORTIONAL` / `FULL`，見 S52）。

**`OrderTransactionInput`**：`orderId`（ID，必填）、`gateway`（String，必填）、`kind`（TransactionKind，必填，退款用 `REFUND`）、`amount`（Decimal，必填）、`parentId`（ID，選填，指向被退的原交易）。

**Access scope**：`orders`、`marketplace_orders` 或 `buyer_membership_orders`（S11）。

**上限值**：`refundCreate` 頁面**未載明**最大可退金額、單次 line item 數上限。S11 逐字：「The documentation provided does not include: Comprehensive list of all possible userErrors codes / Maximum refundable amount thresholds / Specific tax calculation rules」。

### ③ 錯誤碼

- **`refundCreate` 的 userErrors code 清單：文檔未載明**（回傳泛型 `[UserError!]!`）。
- 冪等相關錯誤（2026-04 起適用，S48）：
  - `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`：「Reusing a key with different request parameters. Occurs when the fingerprinted inputs differ from the original request.」
  - `IDEMPOTENCY_CONCURRENT_REQUEST`：「Another request with the same key is currently processing. Retry with the same key after backoff.」
  - 網域性 `*_NOT_FOUND`（如 `LOCATION_NOT_FOUND`）：「Original request succeeded, but associated data was subsequently deleted.」

### ④ 金額規則

- **幣別**：所有金額使用 **presentment currency**，以 decimal ＋ currency code 表示（S11）。
- **退款上限**：由 `SuggestedRefund.maximumRefundableSet` / `SuggestedReturnRefund.maximumRefundable` 表示，**但計算式文檔未載明**（S42/S43）。
- **稅**：`totalTax`「The value must be positive.」；具體稅額分攤規則**文檔未載明**（S11 明言未提供 tax calculation rules）。
- **關稅**：`PROPORTIONAL`（按退貨數量比例）或 `FULL`（該 duty ID 全退）（S52）。⚠️ S52 註明此功能屬「Shopify Markets developer preview」，且「The values that are returned are generated and aren't consistent with actual duty rates set by each country」。
- **運費退款**：`fullRefund` 全退，或 `amount` 指定金額。
- **退款方式**：`refundMethods` 支援退回原付款方式或 **store credit（商店購物金）**（S11/S19）。
- **restock 與退款解耦**：`restockType` 是 per line item 的選項，**退款不一定補庫存**（S11 逐字：「The refundCreate mutation lets you specify restocking behavior for line items」）。

### ⑤ 併發／冪等 ★★★

**這是本研究最重要的一節。**

- **`refundCreate` 自 API 版本 `2026-04` 起「強制」帶冪等鍵**（S49，公告日 **2025-12-12**）。語法：
  ```graphql
  mutation {
    refundCreate(input: {...}) @idempotent(key: "uuid-value") { ... }
  }
  ```
- 未帶 `@idempotent` 指令，「requests will result in an error at runtime」（S49）。
- 受影響 mutation 共 **17 個**，含 `refundCreate`、`inventoryAdjustQuantities`、`inventoryMoveQuantities`、`inventorySetQuantities`、`inventorySetOnHandQuantities`、`inventoryShipmentReceive`、`inventoryShipmentCreate`、`inventoryTransferCreate`、`locationActivate`、`locationDeactivate` 等（S49）。
- **保留期 24 小時**（S48 逐字：「The retention window is 24 hours from the original request. After this period, idempotency keys expire and retries are treated as separate operations.」）。
- **key 格式**：建議 UUID v4 或 v7；背景排程等確定性場景用 **UUID v5**（namespace + job 參數），「同一 job + 變數永遠產生相同 key」，免持久化（S48）。S47 逐字：「we recommend using a randomly generated universally unique identifier (UUID)」。長度／格式硬性限制：**文檔未載明**。
- **重播行為**：S47 逐字：「repeated requests with the same parameters are executed only once, no matter how many times the request is retried.」**但**S48 逐字警告：「Successfully cached responses are constructed from current database state, so *on rare occasions, the cached GraphQL response may not be the same as the original one.*」——**回放的是「當前狀態下重建的回應」，不是原始回應快照**。
- **併發衝突**：同 key 同時進來，後到者收 `IDEMPOTENCY_CONCURRENT_REQUEST`，處理方式為 exponential backoff 後用**同一把 key** 重試（S48）。
- **參數指紋**：同 key 不同參數 → `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`。S48 提醒「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」——**輸入欄位順序會影響指紋**。
- **最佳實踐**（S48）：送出前先持久化 key（防當機）；成功後才產生新 key；bulk 操作每列（JSONL row）獨立 key，**絕不共用**。

### ⑥ API 操作表

| 操作 | 名稱 | 關鍵 input | 回傳 |
|---|---|---|---|
| 建立退款 | `refundCreate` | RefundInput（見上）＋ `@idempotent(key:)`（2026-04 起必填） | refund, order, `[UserError!]!` |
| 退貨退款 | `returnProcess` | 見 §4 | return, ReturnUserError |
| ~~退貨退款（舊）~~ | ~~`returnRefund`~~ | **已 deprecated** | — |
| 建議退款 | `Order.suggestedRefund(...)` | line items, shipping, duties | SuggestedRefund |
| 退貨建議退款 | `Return.suggestedRefund` | — | SuggestedReturnRefund |

**`returnProcess` vs `refundCreate` 的分工（S51，重要）**：
- S51 逐字：`returnProcess`（**2025-07 起可用**）取代兩個舊做法——`returnRefund`（純財務退款）與 `refundCreate`（「Processed refunds at the order level **without return context**」）。
- 逐字：「Existing return apps that use `returnRefund` or `refundCreate` must migrate to `returnProcess` to ensure consistent behavior」。
- **⚠️ 範圍限定**：這條遷移要求是針對 **return apps／退貨情境**。`refundCreate` 本身**並未全域廢止**（它仍在 `latest` 文檔中，且 2026-04 才剛加上強制冪等）。**結論：有退貨脈絡的退款走 `returnProcess`；無退貨脈絡的退款（如純取消、客訴補償）走 `refundCreate`。**
- 遷移理由（逐字）：`returnProcess` 用 `ReturnLineItem` 參照而非泛用的 order line item，因此「the exact returned items are properly processed」，解決多數量退貨的歧義。

### ⑦ 對 CHILL LOVE 的實作結論

27. **`refundCreate` 與 `returnProcess` 兩條路都要做，且分工照 Shopify**：有 return 關聯 → `returnProcess`（一次完成 disposition + 退款 + 換貨）；無 return 關聯 → `refundCreate`。兩者底層共用同一個 `RefundService`（鐵律 7）。
28. **冪等實作規格（直接抄）**：`@idempotent(key:)` 指令 → CHILL LOVE 用 `idempotencyKey` input 欄位（鐵律 5 已定）；**TTL 24 小時**；key 建議 UUID v4/v7，排程任務用 v5；錯誤碼落地 `IDEMPOTENCY_CONCURRENT_REQUEST` 與 `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` 兩個。寫進 `config/limits.yml`：`idempotency.ttl_hours: 24`。
29. **參數指紋要正規化**（欄位排序後再 hash），否則同一請求換個欄位順序就會誤判 mismatch（S48 明確警告）。
30. **回放回應「由當前狀態重建」而非快照**——CHILL LOVE 直接照做（重跑 serializer），比存快照簡單且與 Shopify 行為一致。要在程式碼註明「為什麼」＋出處 S48（CLAUDE.md 註釋驗收要求）。
31. **Refund 是不可變帳務紀錄，不建 status 欄位**；退款是否成功看底下 transaction。這條要寫進 schema 註釋，否則後人一定會加 `refunds.status`。
32. `maximumRefundable` 公式文檔未載明 → CHILL LOVE 自定為 `已收金額 − 已退金額`（＝ `netPayment`），並在 spec 標明「Shopify 未公開公式，此為本專案定義」。**併發測試必須覆蓋「兩個並發退款請求不得超過上限」**（CLAUDE.md 驗收要求）。
33. 關稅（duties）M4 **不做**——S52 明言仍在 developer preview 且回傳值不準。schema 預留 `refund_duties` 表即可。

---

## 7. Order Cancel（取消訂單）

### ① 狀態機表

取消是 Order 的終態操作，寫入 `cancelledAt` ＋ `cancelReason`（見 §1d）。

**`OrderCancelReason`（6 值）**（S19）：`CUSTOMER`（買家要求）、`PAYMENT_DECLINED`（付款被拒）、`FRAUD`（詐騙）、`INVENTORY`（庫存不足）、`STAFF_ERROR`（員工作業錯誤）、`OTHER`（其他）。

**不可取消的條件（S19 逐字）**——訂單符合以下任一即不可取消：
- 已經取消（Are already cancelled）
- 有待處理的付款授權（Have pending payment authorizations）
- 有進行中的退貨（**Contain active returns**）
- 有無法履行的未結出貨（Feature unfulfillable outstanding fulfillments）

**「有進行中的退貨就不能取消訂單」是關鍵互鎖**——退貨與取消互斥。

### ② 欄位與約束

| 參數 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `orderId` | ID! | ✅ | 訂單 ID |
| `reason` | OrderCancelReason! | ✅ | 取消原因 |
| `restock` | Boolean! | ✅ | **必填**，是否補回庫存 |
| `notifyCustomer` | Boolean | ✗ | default `false` |
| `staffNote` | String | ✗ | **上限 255 字元**，買家不可見 |
| `refundMethod` | OrderCancelRefundMethodInput | ✗ | 退回原付款方式或 store credit |

**`reason` 與 `restock` 都是必填（non-null）**——這是刻意的設計，強迫呼叫端做決定。

**停用地點的特殊庫存行為（S19 逐字）**：「Paid orders fail if restocking enabled; unpaid orders succeed but inventory remains unavailable」——已付款訂單在停用地點且要求 restock 會**失敗**；未付款訂單會成功但庫存不會回補。

### ③ 錯誤碼

`orderCancelUserErrors`（`OrderCancelUserErrorCode`）——**具體 enum 值文檔未載明**（S19 頁面未展開）。`userErrors` 欄位已 deprecated，新程式應讀 `orderCancelUserErrors`。

### ④ 金額規則

取消時的退款透過 `refundMethod` 處理（原付款方式或 store credit）。**具體金額計算文檔未載明**——推測沿用 refund 的規則。

### ⑤ 併發／冪等

**`orderCancel` 是非同步的**（S19 逐字：「The mutation operates asynchronously—responses include a job object for tracking completion」）。回傳 `job{ id, done }`，需輪詢 job 狀態。

不在強制冪等名單內（S49）；但因為是 async job，**重複呼叫的行為文檔未載明**。

### ⑥ API 操作表

| 操作 | 名稱 | 回傳 |
|---|---|---|
| 取消訂單 | `orderCancel(orderId:, reason:, restock:, notifyCustomer:, staffNote:, refundMethod:)` | `job{id, done}`, `orderCancelUserErrors`, ~~`userErrors`~~(deprecated) |

### ⑦ 對 CHILL LOVE 的實作結論

34. **`orderCancel` 做成非同步 job**（Solid Queue，鐵律 1），GraphQL 回傳 `job{id, done}`，前端輪詢。這是 Shopify 的做法，也是唯一能安全處理「取消 ＋ 退款 ＋ 回補庫存 ＋ 關閉所有 FulfillmentOrder」這組跨聚合操作的方式。
35. **`reason` 與 `restock` 設為 non-null**，強迫呼叫端表態。
36. **「有 active return 不可取消」的互鎖要實作**，且要有測試。
37. `staffNote` 上限 255 → `config/limits.yml`。
38. 非同步 job 必須自行加冪等鍵（同一訂單重複觸發取消只能執行一次）——Shopify 文檔未載明此點，但這是明顯的正確做法。

---

## 8. Order Edit（編輯訂單）

### ① 狀態機表

編輯訂單走的是 **staged changes（暫存變更）** 模型，不是狀態機（S15）：

```
Order ──orderEditBegin──> CalculatedOrder（暫存區，含 OrderEditSession）
CalculatedOrder ──orderEditAddVariant / AddCustomItem / SetQuantity / 
                  AddLineItemDiscount / RemoveDiscount / UpdateDiscount /
                  AddShippingLine / UpdateShippingLine / RemoveShippingLine──> CalculatedOrder（累積）
CalculatedOrder ──orderEditCommit──> Order（套用，觸發 orders/edited webhook）
CalculatedOrder ──（放棄）──> 丟棄，原 Order 不變
```

- `CalculatedOrder` 是**暫存區**（staging area），內含 `addedLineItems`、`lineItems`、`shippingLines`。
- `shippingLines` 有 **`stagedStatus`** 欄位，值為 `ADDED` / `REMOVED` / `UNCHANGED`（S15）——這是暫存差異的表示法。
- 「The system recalculates taxes and totals automatically as edits occur.」——**每次 edit mutation 都即時重算稅與總額**。
- Commit 後 `Order.edited` 變 `true`（S1）。

### ② 欄位與約束

**不可編輯的限制（S15 / S17 逐字，全列）**：
- 「Archived orders or **orders placed before January 1st, 2019**」
- 「Orders placed in currencies other than store currency (without Checkout Extensions upgrade)」
- **「You can only edit unfulfilled line items.」**（S17）——已履行品項不可編輯
- 「Subscription orders with prepaid plans containing multiple scheduled fulfillments when changing line quantities」
- 「Subscription orders via checkout UI extensions」
- 訂閱附註：「Editing the order doesn't modify the subscription contract itself」——需另外呼叫訂閱合約的 mutation

**`orderEditBegin`**（S16）：`id: ID!`（必填，「The ID of the order to begin editing.」）。回傳 `calculatedOrder`、`orderEditSession`、`userErrors`。需 `write_order_edits` scope。

**`orderEditAddVariant`**（S18）：

| 參數 | 必填 | 說明（逐字） |
|---|---|---|
| `id` | ✅ | calculated order 或 order edit session ID |
| `variantId` | ✅ | 要加入的 variant |
| `quantity` | ✅ | 「Must be a positive integer value」 |
| `allowDuplicates` | ✗ | 「Controls whether the system permits adding variants already present on the order」（**default `false`**） |
| `locationId` | ✗ | 「Specifies which location to check for inventory and tax calculations; a default location is selected if omitted」 |

「respecting the variant's contextual pricing」——**加品項時套用 contextual pricing（依市場／幣別的情境定價）**，不是直接抓 variant 預設價。

**`orderEditSetQuantity`**：`id`、`lineItemId`、`quantity`，＋選填 `restock`（**default `false`**）——「determines whether inventory is restored when reducing quantities」（S15）。

**`orderEditAddCustomItem`**：`id`、`title`、`quantity`、`price`（含 currencyCode）。用途：包裝費、手續費、非庫存品項。

**Shipping line mutations**：`orderEditAddShippingLine`（title + price）、`orderEditUpdateShippingLine`（「Modify title or price on **newly added** lines」）、`orderEditRemoveShippingLine`（by `shippingLineId`）——三者皆 **API 2024-04 起**可用（S15）。⚠️ update 只能改**新加入**的 shipping line。

**`orderEditCommit`**（S17）：

| 參數 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `id` | ID | ✅ | calculated order 或 order edit session ID |
| `notifyCustomer` | Boolean | ✗ | 「When notifyCustomer: true, an email invoice with the updated order information is sent to the customer」 |
| `staffNote` | String | ✗ | 內部備註 |

回傳：`order`、**`successMessages`**（「Array of user-facing confirmation messages」）、`userErrors`。

**上限值**：單次編輯的 line item 數上限、staged change 數上限、session TTL：**全部文檔未載明**。

### ③ 錯誤碼

泛型 `UserError{field, message}`，**code 清單文檔未載明**。

### ④ 金額規則

- **自動重算**：「The `CalculatedOrder` recalculates all monetary fields (taxes, discounts, totals) in real-time as edits accumulate.」（S15）
- **總額增加** → 買家需補款：「If total increases, customer owes additional balance」；commit 時可寄發票收款（「Use `orderEditCommit` to send invoice for outstanding balances, **similar to draft order completion**」）。
- **總額減少** → 產生退款：「If total decreases, refund is processed」。
- 稅額由系統自動重算（「System calculates new tax amounts automatically」）；**具體稅則計算方式文檔未載明**。
- 折扣：可加固定金額或百分比的 line item discount（含選填 description）。

### ⑤ 併發／冪等

- **文檔未載明** OrderEditSession 的鎖機制、TTL、或同一訂單並發編輯的行為。
- `orderEditCommit` 不在強制冪等名單內（S49）。
- 唯一的併發線索：`orderEditBegin` 回傳 `orderEditSession`，暗示 session 是具名資源，**但文檔未說明兩個 session 同時開啟會發生什麼**。

### ⑥ API 操作表

| 階段 | Mutation | 關鍵 input |
|---|---|---|
| 開始 | `orderEditBegin` | `id!`（Order ID） |
| 加變體 | `orderEditAddVariant` | `id!`, `variantId!`, `quantity!`, `allowDuplicates`, `locationId` |
| 加自訂品項 | `orderEditAddCustomItem` | `id!`, `title`, `quantity`, `price{amount, currencyCode}` |
| 改數量 | `orderEditSetQuantity` | `id!`, `lineItemId!`, `quantity!`, `restock`(default false) |
| 加品項折扣 | `orderEditAddLineItemDiscount` | `id!`, `lineItemId!`, discount(fixed/percentage), description |
| 改折扣 | `orderEditUpdateDiscount` | `id!`, `discountApplicationId!`, 新值 |
| 移除折扣 | `orderEditRemoveDiscount` | `id!`, `discountApplicationId!` |
| 加運費 | `orderEditAddShippingLine` | `id!`, title, price（2024-04+） |
| 改運費 | `orderEditUpdateShippingLine` | `id!`, shippingLineId, title/price（**僅限新加入的**，2024-04+） |
| 移除運費 | `orderEditRemoveShippingLine` | `id!`, `shippingLineId!`（2024-04+） |
| 提交 | `orderEditCommit` | `id!`, `notifyCustomer`, `staffNote` |

**Webhook**：`orders/edited`（編輯完成時觸發，S15）。

### ⑦ 對 CHILL LOVE 的實作結論

39. **必須實作 CalculatedOrder 暫存層**（獨立資料表 + session），不能做成「直接改單」。編輯期間原訂單完全不動，commit 才落地——這是可回退、可預覽的唯一做法。
40. **`stagedStatus`（ADDED/REMOVED/UNCHANGED）照抄**，前端靠它渲染 diff（綠色新增／刪除線移除）。
41. **「只能編輯未履行品項」是最硬的 guard**，必須在每個 edit mutation 前檢查，不只在 commit 時。
42. **Session 併發控制是 Shopify 文檔的空白 → CHILL LOVE 必須自己補**：同一訂單同時只允許一個 open 的 edit session（DB unique index on `order_id where committed_at is null`），第二個 begin 回 `userErrors` 帶 `INVALID_STATE`。要在程式碼註明「Shopify 未載明，此為本專案決策」。
43. **Session TTL 自訂**（建議 24h，與冪等 TTL 對齊），逾時自動丟棄，寫進 `config/limits.yml`。
44. **commit 後的補款走 draft order 的收款流程**（文檔逐字類比「similar to draft order completion」），退款走 `refundCreate`。M3 的金額引擎要能被這裡複用（鐵律 7）。
45. `allowDuplicates` default `false`、`restock` default `false` 兩個預設值照抄——預設值選錯會造成庫存錯亂。
46. 「2019-01-01 前的訂單不可編輯」是 Shopify 的歷史包袱，**CHILL LOVE 不需要複製這條**，但要在 spec 註明「刻意不復刻」以免審核時被誤判為遺漏。

---

## 9. 冪等總則（跨實體）

> 本節是 §6⑤ 的抽出彙整，供 `docs/specs` 直接引用。

| 項目 | 規則 | 出處 |
|---|---|---|
| 語法 | `mutation { xxx(input:{...}) @idempotent(key: "uuid") { ... } }` | S49 |
| 強制版本 | **2026-04**（公告 2025-12-12） | S49 |
| 強制範圍 | **17 個 mutation**，含 `refundCreate` 及 inventory／location 系列 | S49 |
| 缺 key 後果 | 「result in an error at runtime」 | S49 |
| Key 保留期 | **24 小時**；逾期後重試視為新操作 | S48 |
| Key 建議格式 | UUID v4/v7；確定性場景用 UUID v5（namespace + 參數） | S48 |
| Key 硬性長度限制 | **文檔未載明** | S47 |
| 重播語義 | 同參數只執行一次；**回應由當前 DB 狀態重建，可能與原始回應不同** | S47/S48 |
| 併發同 key | 回 `IDEMPOTENCY_CONCURRENT_REQUEST`，exponential backoff 後用**同一把 key** 重試 | S48 |
| 同 key 異參數 | 回 `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`；**輸入欄位順序影響指紋** | S48 |
| 已刪關聯資料 | 回網域性 `*_NOT_FOUND`（如 `LOCATION_NOT_FOUND`），代表原請求其實成功了 | S48 |
| 何時重用 key | 網路失敗／逾時／後端處理失敗／不確定是否完成 | S48 |
| 何時換新 key | 意圖不同的新操作／任何參數變動 | S48 |
| Bulk 操作 | **每個 JSONL row 一把獨立 key，絕不共用** | S48 |
| 落地建議 | 送出前先持久化 key（防當機）；成功後才產生新 key | S48 |

**未被 Shopify 強制但 CHILL LOVE 應強制的**（鐵律 5 已要求，文檔未載明其冪等）：`returnProcess`（含退款）、`orderCancel`（async job）、`orderEditCommit`（可能觸發補款/退款）、`fulfillmentCreate`（避免重複出貨）。

---

## 10. 跨實體互鎖矩陣（實作 guard 清單）

本節綜合全部來源，列出**實體之間的硬性互鎖**，供 M4 逐條寫測試。

| # | 互鎖規則 | 出處 |
|---|---|---|
| 1 | 訂單有 **active return** → 不可 `orderCancel` | S19 |
| 2 | 訂單有 **pending payment authorization** → 不可 `orderCancel` | S19 |
| 3 | 訂單有 **unfulfillable outstanding fulfillment** → 不可 `orderCancel` | S19 |
| 4 | Return 已有 **refund / disposition / Shopify Shipping 標籤** → 不可 `returnCancel` | S7, S39 |
| 5 | Return 在 `REQUESTED` → 不可 `returnCancel`，只能 approve/decline | S7 |
| 6 | Return `REQUESTED→OPEN` 與 `REQUESTED→DECLINED` **皆不可逆** | S7 |
| 7 | 只有**已送達（delivered）**的 fulfillment 才可退貨 | S7 |
| 8 | 只有**未履行**的 line item 才可編輯 | S17 |
| 9 | 已封存訂單 → 不可編輯；但**建立退貨會自動解除封存** | S15, S7 |
| 10 | FulfillmentOrder 每張最多 **10 個 active hold**，超過回 user error | S27 |
| 11 | `fulfillmentCreate` 的多張 FulfillmentOrder 必須**同 order 同 location** | S26 |
| 12 | 換貨會產生 `ON_HOLD` + `AWAITING_RETURN_ITEMS` 的 FulfillmentOrder，**退貨到貨前不得出貨** | S7 |
| 13 | 退貨取消**不影響**已釋出的換貨品項 | S7 |
| 14 | 停用地點 + 已付款 + `restock:true` → `orderCancel` **失敗** | S19 |
| 15 | 退款金額 **floor 到 0**，不得為負 | S50 |
| 16 | `orderEditUpdateShippingLine` 只能改**新加入**的 shipping line | S15 |
| 17 | 自營履行單 `requestStatus` 恆為 `UNSUBMITTED` | S21 |
| 18 | `VOIDED` 金流狀態**不使訂單 closed** | S3 |

---

## 11. 文檔未載明清單（實作時需自行決策並標註）

以下項目經實抓確認 shopify.dev **未提供**，CHILL LOVE 必須自行定義並在 spec／程式碼註明「Shopify 未公開，本專案決策」：

1. `maximumRefundable` 的精確計算公式（S42/S43 只給定義）
2. `refundCreate` 的完整 userErrors code 清單（S11 明言未提供）
3. 稅額在退款時的分攤規則（S11 明言未提供）
4. `FulfillmentOrderHoldUserErrorCode` / `FulfillmentOrderSplitUserErrorCode` 的具體值（S27/S28）
5. `OrderCancelUserErrorCode` 的具體值（S19）
6. `fulfillmentOrderSplit` 的最大拆分數（S28 明言未提供）
7. `fulfillmentCreate` 的 tracking number／url 數量上限（S26）
8. `RestockingFeeInput.percentage` 的最大值（S34）
9. OrderEditSession 的 TTL、鎖機制、並發編輯行為（S15/S16/S17 全未提及）
10. `returnProcess` 的冪等保證（不在 S49 名單內，S37 未提及）
11. Order 層的樂觀鎖／版本號（S1）
12. `RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為（S11）
13. 冪等 key 的硬性長度／字元集限制（S47）
14. ReverseFulfillmentOrder 相關 mutation 的完整 input schema 與錯誤碼（S44）
15. Order 層的 line item 數／tag 數上限（S1）

---

## 12. M4 落地檢查清單（給 Codex 的實作入口）

- [ ] `orders` 表：三個 derived 狀態欄位 ＋ `closed_at` / `cancelled_at` / `cancel_reason` / `edited`（§1⑦-1）
- [ ] `fulfillment_orders` 表：`status` ＋ `requestStatus` 雙軸、`assigned_location_id`、`fulfill_at` / `fulfill_by`（§2⑦-6,7）
- [ ] `fulfillment_holds` 表：支援每單多筆，上限 10（§2⑦-10）
- [ ] 「取消產生替代單」「部分 hold/move 產生 remaining 單」的拆單邏輯（§2⑦-9）
- [ ] `supportedActions` 伺服器端計算，驅動前端按鈕（§2⑦-8）
- [ ] `returns` / `return_line_items`（FK → `fulfillment_line_items`）/ `reverse_fulfillment_orders`（§4⑦-16）
- [ ] `returnCreate` 與 `returnRequest` 雙入口 ＋ 不可逆 guard ＋ 二次確認 UI（§4⑦-14,15）
- [ ] 費用模型：`restocking_fee_percentage`（per item）＋ `return_shipping_fee_cents`（per return）（§4⑦-17）
- [ ] 退款公式 `品項價值 − 退貨費用 − 換貨扣抵`，floor 0（§4⑦-18）
- [ ] 換貨 `ON_HOLD` + `AWAITING_RETURN_ITEMS` 流程（§4⑦-19）
- [ ] `ReturnErrorCode` 26 值落地為 userErrors.code（§4⑦-20）
- [ ] `refundCreate` ＋ `returnProcess` 雙路徑，共用 RefundService（§6⑦-27）
- [ ] 冪等：TTL 24h、兩個錯誤碼、參數指紋正規化、回應重建（§6⑦-28,29,30）
- [ ] `orderCancel` 非同步 job ＋ `reason`/`restock` non-null ＋ active return 互鎖（§7⑦-34,35,36）
- [ ] CalculatedOrder 暫存層 ＋ `stagedStatus` diff ＋ 單一 session 鎖（§8⑦-39,40,42）
- [ ] `config/limits.yml` 新增：`fulfillment_order.max_active_holds: 10`、`return.reason_note_max: 255`、`order.staff_note_max: 255`、`idempotency.ttl_hours: 24`、`order_edit.session_ttl_hours: 24`
- [ ] 併發測試：退款上限、並發退貨、重複出貨、並發編輯 session（CLAUDE.md 驗收要求）
- [ ] §10 互鎖矩陣 18 條，逐條寫測試
