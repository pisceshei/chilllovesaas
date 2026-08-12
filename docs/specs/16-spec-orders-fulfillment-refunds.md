# 16 — 功能規格：訂單管理、出貨、退款、顧客（生產級）

> 覆蓋功能：訂單列表/詳情、timeline、出貨、取消/封存、退款、匯出、顧客管理。規格對照研究 01/06，基線見 11。

## F1. 訂單列表與詳情（後台）

**生產級做法**：
1. 列表：keyset 分頁（11 §4）、tabs = saved views（`saved_views` 表：staff、resource、filters JSON、sort）、雙狀態 badge（financial/fulfillment 各自推導值）、bulk 動作走 job（>50 筆時背景處理 + 進度回報）。
2. 詳情：資料聚合一支 query 物件（`Orders::DetailQuery`）preload 全關聯，頁面 0 額外查詢；金額區塊全部來自訂單快照欄位（不重算）。
3. 併發編輯保護：訂單詳情操作（fulfill/refund/cancel）都是狀態條件轉移（`WHERE status = ?` 的 UPDATE），兩個 staff 同時操作時後者收到「狀態已變更，請重新整理」。
4. 搜尋：單號精確 + email/姓名 FULLTEXT（13-F4 同技術）。

**⚠️ 坑**：列表的 badge 若即時推導（JOIN transactions/fulfillments 聚合）會拖垮列表——推導結果**物化在 orders 兩欄**，由服務層在每次金流/出貨動作後更新（同 transaction）；bulk 動作要逐筆獨立 transaction（一筆失敗不連坐）並產出結果報告。

## F2. Timeline 與內部備註

**生產級做法**：`events` append-only（actor: system/staff/buyer、verb、payload JSON）；所有服務動作結尾寫事件（建單、付款、出貨、退款、編輯、寄信、備註）；備註是 verb=comment 的事件，僅後台可見；渲染白名單 verb → 文案模板。

**⚠️ 坑**：事件 payload 別塞整包物件（PII 蔓延 + 膨脹）——只存 diff 與 ID；事件不可編輯刪除（稽核價值），備註「刪除」= 追加一筆 redaction 事件。

## F3. 出貨（Fulfillment）

**生產級做法**：
1. 模型照 06：訂單成立時建 `fulfillment_orders`（demo 單地點 1 筆）；fulfill 動作對 FO 的**剩餘數量**驗證（`≤ quantity - fulfilled_quantity`，條件式 UPDATE 累加防超出）。
2. 出貨 = transaction：建 `fulfillments`（tracking number/carrier/url）→ FO 數量累加 → 庫存 committed−/on_hand−（13-F5 的 service）→ 訂單 fulfillment_status 重新物化 → 事件 + outbox（fulfillments/create）→（transaction 外）出貨通知信 job。
3. tracking URL：carrier → URL 模板表（黑貓/7-11/郵局/DHL…），未知 carrier 允許自填 URL（驗證 http(s) 白名單）。
4. 部分出貨天然支援（數量制）；取消出貨（P1）：逆向還原數量與庫存，限「已出貨未送達」窗口。
5. **`fulfillmentCreate` 的多張 FulfillmentOrder 必須同一 order ＋ 同一 location**——跨地點分多次呼叫。在 service 層驗證並回 `userErrors`（**不要**做成 DB constraint：跨地點是合法的多次呼叫，不是資料錯誤）。`FulfillmentInput.originAddress.countryCode` 為**必填子欄位**。
   <!-- 依 46a:400、46a:403、46a:1038 補寫，原文：「creates fulfillments for one or more FulfillmentOrder objects associated with the same order and location」；`originAddress` 的 `countryCode` 為必填子欄位 -->

**⚠️ 坑**：同一 FO 兩個 staff 同時 fulfill 剩餘 3 件各出 3 件 → 沒有條件式累加就變 6 件；tracking 通知信寄出前驗 email 存在（draft order 可能沒 email）；fulfillment_status 的物化更新忘了做 → 列表永遠 unfulfilled（把「物化」寫進 service 的共用 after 步驟 + 測試）。

### F3.1 FulfillmentOrder 狀態機（P0-05，完整表）

> <!-- 依 46a:213–275 補寫，原文：整條 FulfillmentOrder 狀態機（7 status ＋ 8 requestStatus ＋ 12 supportedActions）在我方規格完全不存在；06 §4 無此列、16-F3 原本只寫「建 fulfillment_orders、對剩餘數量條件累加」 -->
> **三條正交軸**：`status`（7 值）× `requestStatus`（8 值）× `supportedActions`（12 值計算欄位）。三者**分開存、分開判**，不可壓成一個欄位。

**(a) `status` — FulfillmentOrderStatus 全部 7 個狀態**

| 值 | 中文 | 語義（46a:216–224 逐字） | 是否終態 |
|---|---|---|---|
| `OPEN` | 待處理 | 「The fulfillment order is ready for fulfillment.」 | 否 |
| `IN_PROGRESS` | 處理中 | 「The fulfillment order is being processed.」 | 否 |
| `SCHEDULED` | 已排程 | 「deferred and will be ready for fulfillment after the date and time specified in `fulfill_at`」 | 否 |
| `ON_HOLD` | 保留中 | 「The fulfillment process can't be initiated until the hold ... is released.」 | 否 |
| `CLOSED` | 已完成 | 「has been completed and closed」 | **是** |
| `INCOMPLETE` | 未能完成 | 「cannot be completed as requested」 | 否（可被 `fulfillmentOrderOpen` 拉回 OPEN） |
| `CANCELLED` | 已取消 | 「has been cancelled by the merchant」（**雙 L**，與 `ReturnStatus.CANCELED` 單 L 不同） | **是** |

**(b) 合法轉移表（含前置條件與副作用）**

| # | 從 | 到 | 觸發 mutation | 前置條件（guard） | 副作用 |
|---|---|---|---|---|---|
| T1 | （建立） | `OPEN` | 訂單成立時系統建立 | 有可履行品項且無 `fulfill_at` | 依 location 拆單；`requestStatus = UNSUBMITTED` |
| T2 | （建立） | `SCHEDULED` | 訂單成立且有 `fulfill_at` | `fulfill_at > now` | 到期由 job 自動轉 `OPEN` |
| T3 | `SCHEDULED` | `OPEN` | `fulfillmentOrderOpen` | 狀態＝SCHEDULED | 清 `fulfill_at`；寫事件 |
| T4 | `SCHEDULED` | `SCHEDULED` | `fulfillmentOrderReschedule` | 狀態＝SCHEDULED；新 `fulfillAt > now` | 僅改 `fulfill_at` |
| T5 | `OPEN` | `ON_HOLD` | `fulfillmentOrderHold` | active hold 數 < `limits.fulfillment_order.max_active_holds`(10)；reason ∈ 8 值 | 建 hold 紀錄；**若只 hold 部分 line item → 回傳 `remainingFulfillmentOrder`（自動拆出新 FO 承接未 hold 品項）** |
| T6 | `ON_HOLD` | `OPEN` | `fulfillmentOrderReleaseHold` | 該 hold 存在（externalId/handle 命中）；**釋放最後一個 hold 才轉態** | 剩餘 hold >0 時仍為 ON_HOLD |
| T7 | `OPEN` | `IN_PROGRESS` | `fulfillmentOrderSubmitFulfillmentRequest` | 已指派 fulfillment service | `requestStatus: UNSUBMITTED → SUBMITTED` |
| T8 | `OPEN` | `IN_PROGRESS` | `fulfillmentOrderReportProgress` | — | 「marking as in progress if it's not already in progress」 |
| T9 | `OPEN`/`IN_PROGRESS` | `CLOSED` | `fulfillmentCreate`（**全部**剩餘品項） | 同 order 同 location；數量 ≤ 剩餘量 | 建 `fulfillments`；庫存 committed−/on_hand−；訂單 fulfillment_status 重物化 |
| T10 | `OPEN`/`IN_PROGRESS` | （不變） | `fulfillmentCreate`（**部分**品項） | 同上 | 只累加 `fulfilled_quantity`，**狀態不變** |
| T11 | `IN_PROGRESS` | `INCOMPLETE` | `fulfillmentOrderClose` | 狀態＝IN_PROGRESS | **🔴 close 導向 `INCOMPLETE` 不是 `CLOSED`**（46a:240 逐字「Marks in-progress order as incomplete」）；中文 UI 標「未能完成」 |
| T12 | `INCOMPLETE` | `OPEN` | `fulfillmentOrderOpen` | 狀態＝INCOMPLETE | 重新開放履行 |
| T13 | 任一非終態 | `CANCELLED` | `fulfillmentOrderCancel` | 非 CLOSED／非 CANCELLED | **🔴 見 F3.2：同時產生一張替代 FulfillmentOrder 承接剩餘工作** |
| T14 | `OPEN`/`ON_HOLD` | （不變，產生新 FO） | `fulfillmentOrderMove` | 目標 location 有該品項的 inventory item | 回傳 `movedFulfillmentOrder` ＋ `originalFulfillmentOrder` ＋ **`remainingFulfillmentOrder`** |
| T15 | `OPEN` | （不變，產生新 FO） | `fulfillmentOrderSplit` | 拆分數量 ≥1 且 ≤ 剩餘量 | 回傳 `fulfillmentOrderSplits[]` |
| T16 | `OPEN` ×2 | （合併為 1） | `fulfillmentOrderMerge` | 同 order 同 location 同狀態 | 回傳 `fulfillmentOrderMerges` |

**(c) 非法轉移（一律回 `userErrors.code = INVALID_STATE`，比照 46a:592 的 `ReturnErrorCode.INVALID_STATE` 統一碼）**

| 非法操作 | 為什麼 |
|---|---|
| `CLOSED → *`（任何） | CLOSED 為終態 |
| `CANCELLED → *`（任何） | CANCELLED 為終態 |
| `ON_HOLD → fulfillmentCreate` | 逐字：「fulfillment process can't be initiated until the hold ... is released」 |
| `SCHEDULED → fulfillmentCreate` | 未到 `fulfill_at`，須先 `fulfillmentOrderOpen` |
| `fulfillmentOrderClose` 用在 `OPEN` | 文檔只定義 in-progress → incomplete |
| 第 11 個 active hold | 超過 `max_active_holds: 10` → userError |
| `fulfillmentCreate` 跨 location 混批 | 46a:400「same order and location」 |
| 自營 FO 呼叫 `fulfillmentOrderSubmitFulfillmentRequest` | 見 (d)：自營恆為 `UNSUBMITTED` |

**(d) `requestStatus` — FulfillmentOrderRequestStatus 全部 8 個狀態（第二條正交軸）**

| 值 | 中文 | 語義（46a:245–254 逐字） | 誰寫入 |
|---|---|---|---|
| `UNSUBMITTED` | 未送出 | 「the only valid request status for fulfillment orders **not assigned to a fulfillment service**」 | 系統（建立時） |
| `SUBMITTED` | 已送出 | 「The merchant requested fulfillment」 | `fulfillmentOrderSubmitFulfillmentRequest` |
| `ACCEPTED` | 已接受 | 「The fulfillment service accepted」 | `fulfillmentOrderAcceptFulfillmentRequest` |
| `REJECTED` | 已拒絕 | 「The fulfillment service rejected」 | `fulfillmentOrderRejectFulfillmentRequest`（帶 14 值 `FulfillmentOrderRejectionReason`） |
| `CANCELLATION_REQUESTED` | 已請求取消 | 「The merchant requested a cancellation of the fulfillment request」 | `fulfillmentOrderSubmitCancellationRequest` |
| `CANCELLATION_ACCEPTED` | 取消已接受 | 「The fulfillment service accepted the ... cancellation request」 | `fulfillmentOrderAcceptCancellationRequest` |
| `CANCELLATION_REJECTED` | 取消被拒 | 「The fulfillment service rejected the ... cancellation request」 | `fulfillmentOrderRejectCancellationRequest` |
| `CLOSED` | 服務方關閉 | 「The fulfillment service closed the fulfillment order without completing it」 | fulfillment service |

**不變量（必須寫成 DB CHECK 或 model validation ＋ 測試）**：
`assigned_fulfillment_service_id IS NULL ⟹ request_status = 'UNSUBMITTED'`。
CHILL LOVE 初期無 3PL，**欄位仍要建**並固定寫 `UNSUBMITTED`，否則未來接 3PL 要改 schema。
<!-- 依 46a:243–256、46a:1044 補寫，原文：「This is the only valid request status for fulfillment orders not assigned to a fulfillment service.」；我方 specs grep `requestStatus` ＝ 0 命中 -->

**requestStatus 合法轉移**：`UNSUBMITTED → SUBMITTED → {ACCEPTED | REJECTED}`；`ACCEPTED → CANCELLATION_REQUESTED → {CANCELLATION_ACCEPTED | CANCELLATION_REJECTED}`；任一非終態 `→ CLOSED`（服務方單方關閉）。
**非法**：`UNSUBMITTED → ACCEPTED`（跳過 SUBMITTED）、`REJECTED → *`（終態）、`CANCELLATION_ACCEPTED → *`（終態）、自營單離開 `UNSUBMITTED`。

**(e) `supportedActions` — FulfillmentOrderAction 全部 12 值（伺服器端計算欄位）**

> **鐵律**：`supportedActions` 由**伺服器**依 (b)(c)(d) 計算後回傳；admin SPA 的按鈕啟用/停用**完全由它驅動**，前端**不得**另寫一套 guard（22 §1b 的前端 guard 清單改為「渲染層對照表」，判定權移交伺服器）。
> <!-- 依 46a:258–275、46a §2⑦-8 補寫，原文：「supportedActions 做成伺服器端計算欄位、admin 按鈕啟用完全由它驅動」「不要在前端重寫一套 guard 邏輯——兩份邏輯必然漂移」；我方 22:38 原為前端另寫一套 -->

| # | 值 | 中文 | 對應 mutation | 出現條件 |
|---|---|---|---|---|
| 1 | `CREATE_FULFILLMENT` | 建立出貨 | `fulfillmentCreate` | status ∈ {OPEN, IN_PROGRESS} 且有剩餘量 |
| 2 | `REQUEST_FULFILLMENT` | 請求履行 | `fulfillmentOrderSubmitFulfillmentRequest` | 已指派 service 且 requestStatus = UNSUBMITTED |
| 3 | `CANCEL_FULFILLMENT_ORDER` | 取消履行單 | `fulfillmentOrderCancel` | status ∉ {CLOSED, CANCELLED} |
| 4 | `REQUEST_CANCELLATION` | 請求取消 | `fulfillmentOrderSubmitCancellationRequest` | requestStatus ∈ {SUBMITTED, ACCEPTED} |
| 5 | `HOLD` | 保留 | `fulfillmentOrderHold` | status ∈ {OPEN, SCHEDULED} 且 active hold < 10 |
| 6 | `RELEASE_HOLD` | 解除保留 | `fulfillmentOrderReleaseHold` | status = ON_HOLD |
| 7 | `MOVE` | 移動地點 | `fulfillmentOrderMove` | status ∈ {OPEN, ON_HOLD, SCHEDULED} |
| 8 | `SPLIT` | 拆分 | `fulfillmentOrderSplit` | status = OPEN 且 line items > 1 或數量 > 1 |
| 9 | `MERGE` | 合併 | `fulfillmentOrderMerge` | 同 order 同 location 同 status 有 ≥2 張 |
| 10 | `MARK_AS_OPEN` | 標記為開啟 | `fulfillmentOrderOpen` | status ∈ {SCHEDULED, INCOMPLETE} |
| 11 | `REPORT_PROGRESS` | 回報進度 | `fulfillmentOrderReportProgress` | status = OPEN（「marking as in progress if it's not already」） |
| 12 | `EXTERNAL` | 外部連結 | 無（開啟 `externalUrl`） | 由 fulfillment service 提供 `externalUrl` 時 |

**(f) `FulfillmentHoldReason` 全部 8 值** <!-- 依 46a:277–290 補寫，原文：我方 22:38 只寫「最多 10 個手動 hold」，未列原因 -->

`AWAITING_PAYMENT`（等待付款）、**`AWAITING_RETURN_ITEMS`（等待退貨到貨——換貨專用，見 F7.3）**、`HIGH_RISK_OF_FRAUD`、`INCORRECT_ADDRESS`、`INVENTORY_OUT_OF_STOCK`、`UNKNOWN_DELIVERY_DATE`、`ONLINE_STORE_POST_PURCHASE_CROSS_SELL`（購後加購）、`OTHER`。

**(g) `FulfillmentStatus`（出貨單，6 值）**：現行 `SUCCESS` / `CANCELLED` / `ERROR` / `FAILURE`；deprecated `OPEN` / `PENDING`（GraphQL enum 保留並標 deprecated，**不落地**）。 <!-- 依 46a:383–392 補寫 -->

### F3.2 拆單語義：替代單與剩餘單（P0-04，資料遺失防線）

> <!-- 依 46a:236、46a:240、46a:354、46a:358–366 補寫，原文：`fulfillmentOrderCancel`＝「Cancels order and creates replacement for remaining work」；`fulfillmentOrderHold`／`fulfillmentOrderMove` 回傳 `remainingFulfillmentOrder`。我方原本完全未寫 → 剩餘品項會憑空消失 -->

**三個會產生新 FulfillmentOrder 的操作，一律在同一 transaction 內建立新單並回傳**：

| 操作 | 回傳欄位 | 新單內容 | 不做的後果 |
|---|---|---|---|
| `fulfillmentOrderCancel` | `replacementFulfillmentOrder` | **原單所有「尚未出貨」的品項與數量**，status = `OPEN`，繼承 `shop_id`／`order_id`／`assigned_location_id`，`replaced_fulfillment_order_id` 指回原單 | 取消後剩餘品項**憑空消失**，訂單永遠 partially_fulfilled 卡死 |
| `fulfillmentOrderHold`（只 hold 部分 line item） | `remainingFulfillmentOrder` | **未被 hold 的品項**，status = `OPEN`；原單轉 `ON_HOLD` 只留被 hold 的品項 | 未 hold 的品項被連坐鎖住，無法出貨 |
| `fulfillmentOrderMove`（只移部分 line item） | `movedFulfillmentOrder` ＋ `originalFulfillmentOrder` ＋ `remainingFulfillmentOrder` | 移動的品項落在新 location 的新單；剩餘品項留在原 location 的新單 | 同上 |

**實作規格**：
1. 資料表 `fulfillment_orders` 加 `parent_fulfillment_order_id`（自參照 FK）＋ `split_reason` enum（`cancel_replacement` / `partial_hold` / `partial_move` / `manual_split`）。
2. 不變量（nightly 對帳 job 斷言）：**同一 order 的所有 FulfillmentOrder（含已取消者的替代單）對每個 line item 的 `quantity` 總和，恆等於 order line item 的可履行數量**。此斷言就是「品項憑空消失」的黑盒測試。
3. 全部在**同一 DB transaction** 內完成（取消原單 ＋ 建替代單），中斷不得留下半套。
4. 若原單「無剩餘工作」（全部已出貨），`fulfillmentOrderCancel` **不產生**替代單，回傳 `replacementFulfillmentOrder: null`。

### F3.3 超商取貨／取貨點的 admin 側規格（P0-13）

> <!-- 依 44:322 補寫，原文：Shopify 後台「其他配送方式」三列＝當地配送／到店取貨／**取貨點（pickup points）**；44 已標「這正是台灣超商取貨的對應概念，我們 42 號前台的超商取貨流程在 admin 側要對應此設定」。我方 15/16/22/28 原本完全無 admin 側規格 → 前台選了門市後台無處存、無法出貨 -->
> 46b:551–552 佐證結帳擴充點存在獨立的 `purchase.checkout.pickup-point-list.*` 家族（與 `pickup-location-list` 分開），確認 pickup point 是**與到店取貨不同的第三種配送方式**。

**(a) 資料模型（新表）**

| 表 | 欄位 | 說明 |
|---|---|---|
| `pickup_point_providers` | `shop_id`, `carrier`(unimart/fami/hilife/okmart), `subtype`, `enabled`, `cod_enabled`, `credentials_ref` | 對應 `limits.pickup_point.carriers`；per shop 開關 |
| `order_pickup_points` | `shop_id`, `order_id`(唯一), `checkout_id`, `carrier`, `subtype`, `store_id`, `store_name`, `store_address`, `store_phone`, `is_outside_island`, `selected_at` | 前台電子地圖回拋的門市快照（**快照，不是外鍵**——門市會關） |

**(b) 配送方式模型的三分法**（`delivery_method_type`，寫進 `fulfillment_orders` 與 `shipping_lines`）：`SHIPPING`（宅配）／`LOCAL_PICKUP`（到店取貨，取貨點＝賣家 location）／**`PICKUP_POINT`（取貨點，取貨門市為第三方，不是賣家 location）**。三者的 admin 出貨畫面不同：`PICKUP_POINT` 的 FulfillmentOrder **不顯示收件地址欄，改顯示門市卡**，且 `FulfillmentInput.originAddress` 仍為賣家出貨地點。

**(c) 出貨流程差異**：`PICKUP_POINT` 的 fulfillment 的 `trackingInfo.number` ＝物流商的寄件代號（ECPay `AllPayLogisticsID`／廠商交易編號），`company` 固定為該超商通路，`url` 由 `limits` 外的 carrier URL 模板表提供。**到店領取 ≠ 已送達**：需要 `DELIVERED` 之外的 `READY_FOR_PICKUP` 事件（對應 `fulfillmentEventCreate`），退貨的「已送達」前提（F7.1）以 buyer 實際領件時間為準。

**(d) 邊界規則**（進 `config/limits.yml` 的 `pickup_point`）：COD 上限 NT$20,000、三邊和 ≤105cm、重量 ≤5kg、外島門市（`CVSOutSide=1`）處理策略。
**⚠ 待查證（來源未載明）**：以上 COD 上限與材積限制是**業界慣例值，非 Shopify 官方文檔亦非 ECPay 合約原文**；Shopify 官方對 pickup point 的 admin 側資料模型（是否有對應 GraphQL 型別）**三方文檔皆未載明**。見 §待查證清單 V-11。

## F4. 取消與封存

**生產級做法**：
1. Cancel 前置檢查：見 F4.1 的**五條聯集** guard；動作 = 狀態條件轉移 + 庫存 committed 釋放（available+）+ 依選項退款（走 F5）+ **關閉／取消所有未結 FulfillmentOrder（走 F3.2 的替代單語義）** + 事件 + outbox（orders/cancelled）；`reason` 與 `restock` **皆為 non-null 必填**。
2. Archive：純標記（closed_at），不影響金流庫存；**自動封存條件二選一：「已付款且已出貨」或「已全額退款」**，且**官方無延遲**（原本寫的「N 天後」是我方自加，改為預設 0 天、可設定）。P1 做成 nightly job。
   <!-- 依 46c:165、46c:572 修正，原文：自動封存條件為「已付款且已出貨」或「已全額退款」；我方原寫「付清且已出貨 N 天後」——缺「已全額退款」分支且多了官方沒有的延遲 -->
3. 兩者語意分開（研究 01）：cancel 是業務反悔、archive 是收納——UI 文案明確。
4. **建立或申請退貨會自動解除訂單封存**（副作用要在 UI 明示，否則商家會看到封存單自己跳回清單）。
   <!-- 依 46a:482、46a:1036 補寫，原文：「Archived orders — Auto-unarchives when return created/requested」；help 未寫此條（46c C-06） -->

**⚠️ 坑**：cancel 不自動等於 refund（要明確勾選）；已部分出貨的單不能整單 cancel（只能對未出貨行退款）——前置檢查要細到行級。

### F4.1 不可取消條件：五條聯集 guard（P0-07）

> <!-- 依 46a:832–838、46a:1028–1030 修正，原文（dev 逐字，訂單符合任一即不可取消）：①已經取消 ②有待處理的付款授權 ③**有進行中的退貨（Contain active returns）** ④有無法履行的未結出貨。我方 16:38 原本只有 help 側的一條「已部分出貨的單不能整單 cancel」，dev 的四條全缺 -->
> 46c C-01 判定「取消阻擋條件取 dev ∪ help 聯集」。

| # | 條件 | 判定式 | 來源 | 錯誤碼 |
|---|---|---|---|---|
| G1 | 已經取消 | `orders.cancelled_at IS NOT NULL` | 46a:834 | `INVALID_STATE` |
| G2 | 有待處理的付款授權 | `EXISTS(order_transactions WHERE kind='authorization' AND status='pending')` | 46a:835 | `INVALID_STATE` |
| G3 | **有進行中的退貨** | `EXISTS(returns WHERE order_id=? AND status IN ('REQUESTED','OPEN'))` | 46a:836 | `INVALID_STATE` |
| G4 | 有無法履行的未結出貨 | `EXISTS(fulfillment_orders WHERE status='INCOMPLETE')` | 46a:837 | `INVALID_STATE` |
| G5 | 已（部分）出貨 | `EXISTS(fulfillments WHERE status='SUCCESS')` → 只能對未出貨行退款 | 46c（help 側，我方原有） | `INVALID_STATE` |

**G3 是本次新增的關鍵互鎖**：不做這條 → 退貨進行中仍可取消訂單 → **雙重退款 ＋ 庫存重複回補**。
實作：`Orders::Cancel` service 的第一步就跑這五條；**同時**在 `returns` 建立路徑加反向互鎖（訂單已 cancelled 不得建 return），兩邊都要有測試。
`DECLINED` / `CLOSED` / `CANCELED` 狀態的 return **不算** active（不阻擋取消）。

### F4.2 `orderCancel` 契約（P0-14）

> <!-- 依 46a:842–877 修正，原文：`orderCancel(orderId!, reason: OrderCancelReason!, restock: Boolean!, notifyCustomer, staffNote, refundMethod)` 回傳 `job{id,done}` ＋ `orderCancelUserErrors`。
>      🔴 此處原本寫錯：docs/research/28:69 的簽名 `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)`
>      ——多出官方**不存在**的 `refund: Boolean`、少了 `staffNote` / `refundMethod`、`restock` 未標 non-null、且做成**同步**。
>      任何人翻舊版看到 `refund: Boolean` 都不要改回去。 -->

| 參數 | 型別 | 必填 | 規則 |
|---|---|---|---|
| `orderId` | `ID!` | ✅ | — |
| `reason` | `OrderCancelReason!` | ✅ | 6 值：`CUSTOMER` / `PAYMENT_DECLINED` / `FRAUD` / `INVENTORY` / `STAFF_ERROR` / `OTHER`（46a:830、46c:955–963） |
| `restock` | `Boolean!` | ✅ | **non-null**——強迫呼叫端表態，**沒有預設值** |
| `notifyCustomer` | `Boolean` | ✗ | default `false`（UI 層顯式帶 `true`，46c C-03） |
| `staffNote` | `String` | ✗ | 上限 255 字元（`limits.order.cancel_staff_note_max_chars`），**買家不可見** |
| `refundMethod` | `OrderCancelRefundMethodInput` | ✗ | 退回原付款方式或 store credit |
| ~~`refund`~~ | ~~`Boolean`~~ | — | **🔴 官方不存在，刪除**（是否退款由 `refundMethod` 表達） |

**回傳**：`{ job: { id, done }, orderCancelUserErrors: [{field, message, code}] }`。~~`userErrors`~~ 已 deprecated。

**非同步執行（硬要求）**：
1. `orderCancel` 是**非同步**的（46a:865、46a:877 逐字：「responses include a job object for tracking completion」）。做成 Solid Queue job，GraphQL 立即回 `job{id, done:false}`，前端輪詢。
2. 理由：取消要跨聚合完成「狀態轉移 ＋ 退款 ＋ 回補庫存 ＋ 關閉所有 FulfillmentOrder」，同步執行必逾時中斷 → **半取消狀態卡死**。
3. job 自身**必須帶冪等鍵**（`limits.idempotency.required_for` 已列入）：同一訂單重複觸發取消只執行一次。Shopify 文檔未載明此點，**本專案決策**。

**停用地點的特殊行為**（46a:853、46a:1041 逐字）：
- 訂單**已付款** ＋ 品項所在 location **已停用** ＋ `restock: true` → **整個 mutation 失敗**（回 userError，不做部分取消）。
- 訂單**未付款** ＋ 同上 → **成功，但庫存不回補**（保持 unavailable）。

### F4.3 `OrderDisplayFinancialStatus` 與訂單生命週期旗標（補完 06 §4）

<!-- 依 46a:74–103、46a:136–152、46a:1045 補寫，原文：Order **沒有單一 status 欄位**，由四條正交軸（financial / fulfillment / 生命週期旗標 / return）組成；06:91 原本把 Order 寫成單一 `status: open → archived / canceled` 與官方直接衝突 -->

- `PENDING` / `AUTHORIZED` / `PARTIALLY_PAID` / `PAID` / `PARTIALLY_REFUNDED` / `REFUNDED` / `VOIDED` / `EXPIRED` 共 8 值，**由 transactions 聚合推導、不可直接寫入**。
- **終態（不可逆）**：`VOIDED`、`EXPIRED`、`REFUNDED`。
- 多次部分請款路徑：`AUTHORIZED → PARTIALLY_PAID → PAID`（需 `capture_payments_for_orders` 權限；請款模式見 22 §8 的四模式）。
- `closed` 判定式（46a:1045 逐字語義）：**所有 line item 已履行或已取消 AND 所有金流交易完成**。**`VOIDED` 不使訂單 closed**。
- 衍生旗標（全部 derived，不落庫）：`confirmed` / `fulfillable` / `refundable` / `restockable` / `unpaid` / `fullyPaid` / `edited`。
- `OrderDisplayFulfillmentStatus`：現行 7 值（含 **`REQUEST_DECLINED`**）＋ 3 個 deprecated（`OPEN` / `PENDING_FULFILLMENT` / `RESTOCKED`，GraphQL enum 保留標 deprecated、不落地）。**此欄為 derived 不可寫入**；`ON_HOLD` / `SCHEDULED` 的定義是「***所有*** unfulfilled items 皆處於該狀態」。

## F5. 退款（Refund）

**生產級做法**：
1. 退款面板：逐行選數量（≤ 已購未退數）、restock 勾選（預設勾，**僅在該品項有追蹤庫存時可用**）、另退運費欄（≤ 可退運費）、原因、是否通知（預設勾）——完全對齊研究 01 的畫面。**數量設為 0 的品項不退款**；退款頁**可直接對商品項目套用折扣**（46c:218–221）。
2. 計算：**一律走 F5.1 的公式**（不得在 UI 或 controller 另算一份）。
3. 執行順序：本地 transaction（建 refund + refund_line_items + transaction 列 pending + restock via Inventory::Adjust 冪等 + 事件）→ **transaction 外**呼叫 Stripe refund → webhook 確認 → transaction 列轉 success → financial_status 重物化 → 通知信。
4. Stripe 失敗處理：pending 退款列 + 告警 + 後台可重試（冪等 key 不變）。
5. **Refund 是不可變的帳務紀錄，`refunds` 表不建 `status` 欄位**——退款是否成功看底下 `order_transactions` 的狀態。這條要寫進 schema 註釋，否則後人一定會加 `refunds.status`。
   <!-- 依 46a:722–726 補寫，原文：「A Refund object's existence doesn't guarantee payment completion; check associated OrderTransaction statuses」 -->
6. **退款一經發起絕對不可撤銷**（三方一致，46c:228、46c:1143）→ UI 強制二次確認彈窗，文案明示不可逆。
7. `refundMethods` 支援「退回原付款方式」與 **store credit（商店購物金）**；`restockType` 與退款**解耦**（退款不一定補庫存）。

**⚠️ 坑**：restock 冪等（13-F5：refund_line_item_id 唯一）防 webhook 重放重複進貨；「先打 Stripe 再落庫」順序錯誤會在本地失敗時退了錢沒紀錄——**永遠先落 pending 再打金流**；部分退款多次後的殘額計算用資料庫聚合而不是前端傳入。

### F5.1 退款金額公式（P0-01，可測式子）

> <!-- 依 46a:595–601、46a:1042 修正，原文（2024-07 起變更，標記 Action required）：「The refund amount considers exchange line items and fees on the return, as well as any outstanding amount owed by the buyer on an order.」＋下限鉗制逐字「the suggested amount cannot be lower than $0 CAD」。
>      我方 16:44 原本只有「行單價×數量 −（折扣分攤×退貨比例）− 稅按比例」——**缺退貨費用扣減、缺換貨扣抵、缺 floor 0** → 有換貨的訂單退款金額必錯 -->

**單位與捨入的唯一規定**（鐵律 3）：
- 全程 **integer cents**（presentment currency）；**任何中間值都不得出現 float**。百分比以 **basis points（0–10000 整數）** 儲存與運算。
- **只有三個捨入點**，其餘一律精確整數運算：
  1. **折扣／稅的比例分攤** → 15-F2 的**最大餘數法**（分完的分不多不少，Σ 分攤 ＝ 原始總額）。
  2. **重新上架費（百分比 → 金額）** → `floor`（**費用取小 ⇒ 退款取大**，對買家有利，避免多扣）。
  3. **零小數幣別（JPY 等）** → 只在序列化層由 15-F4 的 `stripe_amount()` 處理，業務層不感知。
- 幣別捨入**不在**公式層發生；公式層只有 cents 整數。

**公式（逐項可測）**

```
# 每個退貨品項 i（i 對應一筆 return_line_item / refund_line_item）
line_gross[i]      = unit_price_cents[i] * qty_returned[i]
discount_alloc[i]  = 最大餘數法( 該行 discount_applications 分攤額 , qty_returned[i] / qty_ordered[i] )
line_net[i]        = line_gross[i] - discount_alloc[i]                 # 折後未稅
line_tax[i]        = 最大餘數法( 該行稅額 , qty_returned[i] / qty_ordered[i] )
                     # 含稅定價（台灣預設）時稅已內含於 unit_price → line_tax[i] = 0，
                     # 稅額僅為報表反推值，不重複加總

restocking_fee[i]  = floor( line_net[i] * restocking_bp[i] / 10000 )   # 百分比、per line item
                     # 基數＝該行「折後未稅」小計（46a §4④「按 line item subtotal 計算」）
                     # ⚠ 待查證（來源未載明）：subtotal 是否含稅，官方未定義 → 見 §待查證清單 V-13

returned_value     = Σ_i ( line_net[i] + line_tax[i] )
return_fees        = Σ_i restocking_fee[i] + return_shipping_fee_cents # 後者固定額、per return
exchange_value     = Σ_j ( exchange_price_cents[j] * qty[j]
                           - exchange_product_discount_cents[j]        # 只准商品折扣
                           + exchange_tax_cents[j] )                   # 訂單級折扣禁止套用
outstanding        = max(0, Σ order_due_cents - Σ captured_cents)      # 買家在該訂單的未付金額

net                = returned_value - return_fees - exchange_value - outstanding

suggested_refund   = max(0, net)                                       # 🔴 floor 到 0，不得為負
balance_to_collect = max(0, -net)                                      # 見下方「負值的兩種語義」
```

**負值的兩種語義（不可混為一談）**
- `exchange_value > 0` 或 `outstanding > 0` 造成 `net < 0` → **向買家收取差額**（46c:351–358 逐字：「Return fees and exchange items are applied against returned items to determine whether a refund is due or **payment needs to be collected**」）。產生應收，走 15-F3 的補款結帳連結。
- **只有退貨費用**造成 `net < 0`（無換貨、無欠款）→ 46a:601 只說「建議金額不得低於 0」，**未說**會產生應收。本專案：`suggested_refund = 0`，**不自動產生應收**，由商家自行決定是否另行收款。
  **⚠ 待查證（來源未載明）**：純費用超過退貨品價值時是否應產生應收——見 §待查證清單 V-09。

**退款上限（軟上限，不得做成 DB CHECK）**
<!-- 依 46c:223、46c:241 修正，原文：「超額退款允許——先前已發過商店抵用金者，之後可對原付款方式做 over-refund」。
     🔴 此處原本寫錯：16:44 原寫「累計退款 ≤ 實收（DB CHECK 級測試）」——DB CHECK 會擋掉 help 明載的合法情境。任何人翻舊版都不要改回硬約束。 -->
- 預設軟上限 `maximumRefundable = netPayment = Σcaptured − Σrefunded`。
  **⚠ 待查證（來源未載明）**：`maximumRefundable` 的官方公式 Shopify **未公開**（46a:606、46a:770、46a:819）——上式為**本專案定義**。
- 超過軟上限 → 需 `orders.over_refund` 權限 ＋ 二次確認 ＋ 寫 audit log；**不是 DB 層硬擋**。
- 併發要求不變：**兩個並發退款請求的總額不得突破軟上限**（條件式 UPDATE ＋ request spec，CLAUDE.md 驗收要求）。

**運費退款規則**：`amount`（指定金額）或 `fullRefund`（全退）二選一；退運費**不得超過可退運費**；**訂單套用了訂單層級免運折扣 → 完全不可退運費**（46c:218–221、46c:238）。
**⚠ 待查證（來源未載明）**：`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為（46a §6② 明列為未載明）。

**混合付款的退款分配順序（P1，但屬同一段程式碼）**：混合付款時**先把退款金額套用到禮品卡**，直到禮品卡達可退全額，餘額才走其他付款方式（46c:221）。

**`returnCalculate` 與 `returnProcess` 必須共用同一份計算程式碼**（鐵律 7 數字同源）——預覽的建議值與實際退款金額若能對不上就是 bug。同一支 `Refunds::Calculator` 純函式，兩處呼叫。

### F5.2 三個算例（驗收用測試向量）

**算例 1 — 對照官方文檔範例（只有退貨運費）**
| 項 | 值 |
|---|---|
| 退貨品項價值 `returned_value` | 5099（$50.99） |
| `return_shipping_fee_cents` | 500（$5.00） |
| `exchange_value` / `outstanding` | 0 / 0 |
| `net` | 5099 − 500 = **4599** |
| **`suggested_refund`** | **4599（$45.99）** ✅ 與 46a:599 文檔範例一致 |

若把 return fee 改成 6000（> 5099）：`net = −901` → `suggested_refund = 0`（floor 生效），且**不自動產生應收**。

**算例 2 — 重新上架費（%）＋ 退貨運費（固定額），含訂單級折扣分攤**
| 項 | 值 |
|---|---|
| 品項 A 單價 148000 × 數量 2 | `line_gross` = 296000 |
| 該行分攤的訂單級折扣（10% 全單折，退 2/2） | `discount_alloc` = 29600 |
| `line_net` | 296000 − 29600 = **266400** |
| 含稅定價（TW 5% 內含）→ `line_tax` | 0（稅內含，不重複加總） |
| 重新上架費 15%（`restocking_bp` = 1500） | `floor(266400 × 1500 / 10000)` = `floor(39960.0)` = **39960** |
| 退貨運費（per return 固定額） | **6000** |
| `returned_value` / `return_fees` | 266400 / 45960 |
| `net` = `suggested_refund` | **220440（NT$2,204.40 → 顯示 NT$2,204）** |

> 捨入檢查：`266400 × 1500 = 399600000`，`/10000 = 39960` 整除，無餘數；若改成 13%（1300 bp）則 `266400 × 1300 / 10000 = 34632.0` → floor 34632。任何有小數的情況一律 **floor**。

**算例 3 — 🔴 換貨與退貨費用同時存在（P0-01 的核心案例）**
| 項 | 值 | 依據 |
|---|---|---|
| 退貨品 B：單價 220000 × 1，無分攤折扣 | `line_net` = 220000 | — |
| 重新上架費 10%（1000 bp） | `floor(220000 × 1000 / 10000)` = **22000** | 46a:526（%／per line） |
| 退貨運費 | **6000** | 46a:528（固定額／per return／presentment 幣別） |
| 換貨品 C：單價 268000 × 1 | — | — |
| 換貨品的**商品折扣** −18000 | 允許 | 46c:351–358 |
| 換貨品套訂單級折扣 | **禁止**（本例不套） | 46c:351–358 逐字「Order level discounts can't be applied to exchange items」 |
| `exchange_value` | 268000 − 18000 = **250000** | — |
| `returned_value` / `return_fees` | 220000 / 28000 | — |
| `net` | 220000 − 28000 − 250000 = **−58000** | — |
| **`suggested_refund`** | **`max(0, −58000)` = 0** | 46a:601 floor 0 |
| **`balance_to_collect`** | **58000（向買家收 NT$580）** | 46c:351–358「payment needs to be collected」 |

> 若照**修正前**的舊公式（只算「行單價×數量 − 折扣分攤 − 稅按比例」），本例會算出**退款 220000（NT$2,200）**——多退 NT$2,200 且漏收 NT$580，單筆誤差 NT$2,780。這就是 P0-01 被列為 P0 的理由。

### F5.3 退貨費用資料模型（P0-02）

> <!-- 依 46a:526、46a:528、46a:608–610、46a §4⑦-17 補寫，原文：restocking fee 是 `percentage: Float!`（必填、per line item、同一張退貨不同品項可不同%）；return shipping fee 是 `amount: MoneyInput!`（必填、per return、**必須是 presentment 幣別**）。這個不對稱是 Shopify 的刻意設計，照抄。我方原本完全無欄位可存 -->

| 表 | 新增欄位 | 型別 | 規則 |
|---|---|---|---|
| `return_line_items` | `restocking_fee_bp` | `int unsigned NULL` | 百分比 × 100（basis points，0–10000）；**per line item**，同一張退貨各品項可不同 |
| `return_line_items` | `restocking_fee_cents` | `int NULL` | 物化的計算結果（＝ `floor(line_net × bp / 10000)`），供對帳；重算必須等值 |
| `returns` | `return_shipping_fee_cents` | `int NULL` | **固定金額、per return** |
| `returns` | `return_shipping_fee_currency` | `char(3)` | **必須等於 `orders.presentment_currency`**（DB CHECK 或 model validation ＋ 測試） |

**不對稱設計不可「統一」**：不要為了整齊把 restocking fee 也做成固定額、或把 return shipping fee 做成百分比——會與 `returnCalculate` 的建議值對不上。
**⚠ 待查證（來源未載明）**：`RestockingFeeInput.percentage` 的**最大值**文檔未載明（46a §4②）→ 程式先以 100% 作防呆上界（`limits.return.restocking_fee_max_percentage_guard`），實際上界待查證。

**費用來源與覆寫（T-01 兩層語義）**
<!-- 依 46a:595–601（dev 自動扣抵）＋ 46c:218、46c:436（help 可覆寫）修正。
     🔴 此處原本寫錯：docs/research/22:61 原寫「『退貨費不自動從退款扣』照抄」——與 dev 的 `suggestedRefund` 自動扣抵行為直接衝突，已改為「自動帶入建議值、可覆寫」。任何人翻舊版都不要改回去。 -->
1. **建議值層（API 權威）**：`returnCalculate` / `returnProcess` **自動**依 F5.1 扣抵退貨費用與換貨扣抵。
2. **覆寫層（UI 能力）**：admin 建立退貨時顯示退貨運費**可逐筆編輯**、重新上架費**可按個別品項編輯**；退款頁可手動改退款金額。
3. **退貨規則只是預設值來源，不是硬約束**——商家在 admin 端永遠可覆寫（覆寫要寫 audit log）。

## F6. 顧客管理

**生產級做法**：
1. 建檔：訂單成立時 email upsert（`(shop_id, email)` 唯一）；統計欄位（amount_spent、orders_count、last_order_at）由訂單事件增量維護 + nightly 重算對帳。
2. 詳情頁：訂單歷史 keyset 分頁、地址簿 CRUD（預設地址單選）、tags（正規化表）、備註（事件）。
3. 合併（P1）：`Customers::Merge` service——訂單/地址/tags 重掛、統計重算、事件記錄雙方 ID；被併者標記 merged_into_id 不硬刪。
4. 匯出 CSV：streaming（13-F6），欄位含 consent 狀態；匯出動作記 audit log（PII 外流點）。
5. 刪除（隱私請求）：檢查無未完成訂單 → 匿名化（email→hash 佔位、姓名地址清空、保留訂單金額統計）而非硬刪（帳務完整性）。

**⚠️ 坑**：guest 重複下單不同大小寫 email → 正規化後 upsert；統計欄位只靠增量會漂移 → nightly 重算是必備對帳；匿名化要連 events payload 與 checkouts 一起處理（PII 清單驅動，11 §7）。

## F7. 退貨與換貨（Return / Exchange）

> 本節為新增。原本 16 號完全沒有退貨規格，退貨只散落在 22 §1d 的按鈕表。

### F7.1 Return 狀態機（P0-06，完整表）

> <!-- 依 46a:438–482、46c:1021–1033 修正，原文：`ReturnStatus` **5 值**（REQUESTED / OPEN / DECLINED / CLOSED / **CANCELED**，單 L 拼寫）。
>      🔴 此處原本寫錯：06:96 採 help 的 4 態展示狀態 `requested → in_progress → inspection_complete → returned`，
>      缺 DECLINED / CANCELED 兩個終態與全部不可逆 guard。46c C-07 已判定「採 dev 5 值 ＋ help 的『檢查完成』降為 OPEN 底下的子進度」。
>      任何人翻舊版看到 4 態都不要改回去。 -->

**(a) 全部 5 個狀態**

| 值 | 中文 | 語義（46a:442–446 逐字） | 是否終態 |
|---|---|---|---|
| `REQUESTED` | 已申請 | 「The return was requested.」（買家自助申請，待審） | 否 |
| `OPEN` | 進行中 | 「The return is in progress.」（help 的「檢查完成」是本狀態底下的**子進度** `inspection_completed_at`，**不是**獨立狀態） | 否 |
| `DECLINED` | 已拒絕 | 「The return was declined.」 | **是（無 mutation 可離開）** |
| `CLOSED` | 已完成 | 「The return has been completed.」 | 否（可 `returnReopen`） |
| `CANCELED` | 已取消 | 「The return has been canceled.」**單 L 拼寫**，與 `FulfillmentOrderStatus.CANCELLED`（雙 L）不同，enum 照抄不得統一 | **是** |

**(b) 合法轉移表（含前置條件與副作用）**

| # | 從 | 到 | mutation | 前置條件（guard） | 副作用 |
|---|---|---|---|---|---|
| R1 | （無） | `REQUESTED` | `returnRequest` | 品項來自**已送達**的 fulfillment（見 F7.2）；未命中最終銷售品項；在退貨期間內（依購買時點快照，見 F7.4） | **自動解除訂單封存**；寄「已收到退貨申請」通知 |
| R2 | （無） | `OPEN` | `returnCreate` | 同上；商家端建立（「Assumes customer approval already obtained」） | 建立 reverse fulfillment order；**自動解除訂單封存**；若帶 `exchangeLineItems` → 見 F7.3 |
| R3 | `REQUESTED` | `OPEN` | `returnApproveRequest` | 狀態＝REQUESTED | **🔴 不可逆**（46a:468 逐字「Approving a return is a permanent action」）→ UI 二次確認；建立 reverse fulfillment order；寫 `requestApprovedAt` |
| R4 | `REQUESTED` | `DECLINED` | `returnDeclineRequest` | 狀態＝REQUESTED；`declineReason` **必填**（`FINAL_SALE` / `RETURN_PERIOD_ENDED` / `OTHER`） | **🔴 不可逆**（46a:469 逐字「cannot revert to REQUESTED」）→ UI 二次確認；寄「退貨申請已被拒絕」 |
| R5 | `OPEN` | `CLOSED` | `returnProcess`（全部品項處理完） | 每個 return line item 都有 disposition | 依 disposition 補/不補庫存；產生退款（走 F5.1）；寫 `closedAt` |
| R6 | `OPEN` | `CLOSED` | `returnLineItemRemoveFromReturn`（移除**最後一項**） | — | **自動** CLOSE（副作用，非另一支 mutation） |
| R7 | `OPEN` | `CLOSED` | `returnClose` | 狀態＝OPEN | 寫 `closedAt` |
| R8 | `OPEN` | `CANCELED` | `returnCancel` | 見 (d) 四條硬前置 | 「All sales records generated from the creation of a return will be reversed」；**換貨品項不受影響**（見 F7.3） |
| R9 | `CLOSED` | `OPEN` | `returnReopen` | 狀態＝CLOSED | 清 `closedAt` |

**(c) 非法轉移（一律回 `ReturnErrorCode.INVALID_STATE`）**

| 非法操作 | 為什麼 | 出處 |
|---|---|---|
| `DECLINED → *`（任何） | 終態，無 mutation 可離開 | 46a:471 |
| `OPEN → REQUESTED` | 核准是永久動作，不可回退 | 46a:468 |
| `DECLINED → REQUESTED` | 拒絕是永久動作 | 46a:469 |
| **`REQUESTED → CANCELED`** | 「Cannot be canceled directly – must approve/decline instead」 | 46a:480 |
| `CANCELED → *`（任何） | 終態 | 46a:446 |
| 對 `DECLINED` 呼叫 `returnProcess` | 狀態機違規統一碼 `INVALID_STATE` | 46a:592 |
| 對訂單已 `cancelled_at` 的訂單建 return | F4.1 G3 的反向互鎖 | 本專案（互鎖對稱性） |

**(d) `returnCancel` 的四條硬前置（46a:472–476 逐字，全部不得省略）**
1. 必須在 `OPEN` 狀態；
2. **不得**有已取消的 fulfillment；
3. **不得**有已發生的 refund；
4. **不得**有已做的 disposition；
5. **不得**有 Shopify Shipping 產生的退貨標籤（**手動上傳的標籤可以**）。
> 46a:475 補充逐字：「Canceling a return is only available before any work has been done on the return (such as an inspection or refund).」

**(e) `ReturnDeclineReason`（3 值，`returnDeclineRequest` 必填）**：`FINAL_SALE` / `RETURN_PERIOD_ENDED` / `OTHER`。
**(f) `ReturnReason`（10 值，已 deprecated 但需支援，改用 `returnReasonDefinitionId`）**：`COLOR` / `DEFECTIVE` / `NOT_AS_DESCRIBED` / `SIZE_TOO_LARGE` / `SIZE_TOO_SMALL` / `STYLE` / `UNWANTED` / `WRONG_ITEM` / `UNKNOWN` / `OTHER`。`returnReasonNote` 上限 **255 字元**（`limits.return.reason_note_max_chars`）。
**(g) `ReverseFulfillmentOrderStatus`（3 值）**：`OPEN` / `CLOSED` / `CANCELED`。
**(h) `ReverseFulfillmentOrderDispositionType`（4 值）**：`RESTOCKED` / `NOT_RESTOCKED` / `MISSING` / **`PROCESSING_REQUIRED`**。
> **`PROCESSING_REQUIRED` 是中間態** → disposition **不是一次性終態**，同一 line item 要允許**多筆** disposition 紀錄、取最新一筆為準（46a:678–680）。M4 只做 `RESTOCKED` / `NOT_RESTOCKED`，enum 一次定義完 4 值。

**(i) 訂單層 `OrderReturnStatus`（6 值，聚合欄位）**：`NO_RETURN` / `RETURN_REQUESTED` / `IN_PROGRESS` / `INSPECTION_COMPLETE` / `RETURNED` / `RETURN_FAILED`——**derived，不可寫入**，由該訂單所有 return 聚合推導；訂單列表篩選器要支援。

### F7.2 `return_line_items` 的外鍵（P0-08，schema 級，上線後改不得）

> <!-- 依 46a:519、46a:627、46a:648、46a:1034 修正，原文：`ReturnLineItemInput.fulfillmentLineItemId: ID!` 逐字「The ID of the **fulfillment line item** to be returned」；
>      且 `returnableFulfillments` 的前提逐字「A returnable fulfillment is an order that **has been delivered**」。
>      我方 06:37 原本只有 `ORDER ||--o{ RETURN`，退貨掛在訂單層 → 會允許退未出貨品項 -->

```
orders ─┬─< order_line_items
        ├─< fulfillment_orders ─< fulfillment_order_line_items
        └─< fulfillments ─< fulfillment_line_items ─< return_line_items   ← 🔴 外鍵在這裡
                                                          │
returns ─────────────────────────────────────────────────┘
```

| 規則 | 實作 |
|---|---|
| `return_line_items.fulfillment_line_item_id` **NOT NULL FK** → `fulfillment_line_items.id` | 不是 `order_line_items` |
| 建立前提：該 fulfillment 已 **delivered** | `fulfillments.delivered_at IS NOT NULL`（`PICKUP_POINT` 以實際領件時間為準，見 F3.3） |
| 可退數量 | `fulfillment_line_items.quantity − 已退數量`（由 `returnableFulfillments` query 計算並回傳） |
| 未出貨品項要「退」 | **走取消/編輯訂單路徑，不是退貨路徑**（F4／訂單編輯） |

`returnableFulfillments(orderId:)` query 為必做——它是前台/後台「可退品項清單」的唯一來源。

### F7.3 換貨會產生 `ON_HOLD` ＋ `AWAITING_RETURN_ITEMS` 的 FulfillmentOrder（P0-09）

> <!-- 依 46a:552–556、46a:651、46a:1039 補寫，原文：換貨在 `returnCreate` 以 `exchangeLineItems` 指定；
>      系統會建立 fulfillment order，狀態為 **`ON_HOLD`**、hold reason 為 **`AWAITING_RETURN_ITEMS`**；換貨品項的銷售紀錄自動建立。
>      我方 22:61 原本只有「Exchange 加購（算差額；不能自訂品項）」 → 換貨品會在收到退貨前就出貨，直接資損 -->

| # | 規則 | 出處 |
|---|---|---|
| 1 | 建立退貨時帶 `exchangeLineItems{variantId, quantity}` → 系統**在同一 transaction 內**建立一張 FulfillmentOrder，`status = ON_HOLD`、hold `reason = AWAITING_RETURN_ITEMS` | 46a:554 |
| 2 | **退貨到貨（`returnProcess` 完成 disposition）前，此 FO 不得出貨**——由 F3.1 的 `ON_HOLD → fulfillmentCreate` 非法轉移擋住 | 46a:554 |
| 3 | 退貨處理完成 → 自動 `fulfillmentOrderReleaseHold` → FO 轉 `OPEN` → 可正常出貨 | 本專案（銜接 R5） |
| 4 | **`returnCancel` 不影響已釋出的換貨品項** | 46a:478、46a:1040 |
| 5 | 換貨品項**不能是自訂品項**；**含關稅（duties）的訂單可退貨、不可換貨** | 46c:314–315 |
| 6 | 換貨品項**不得套用訂單層級折扣**，但**可加商品折扣** | 46c:351–358 |
| 7 | 差價三情境：新品便宜 → 退差額；新品貴（或含退貨費）→ **收差額**；等值 → 抵銷。全部由 F5.1 的 `net` 正負決定 | 46c:351–358 |
| 8 | **換貨品項的庫存在「處理退貨」之前完全不保留**——`AWAITING_RETURN_ITEMS` 的 FO 只是**工作單佔位，不動 `committed`**；換貨品可能在這期間被別人買走 | 46c:299（help 逐字，46c C-02 判定採 help） |

> **⚠ 待查證（來源未載明）**：`AWAITING_RETURN_ITEMS` 的 FulfillmentOrder **是否計入 `committed`**——46a（會建 FO）與 46c（不保留庫存）表面衝突，**兩份文檔皆未載明**。本專案暫採 help（不佔 committed），見 §待查證清單 V-03。

### F7.4 退貨與取消規則綁「購買時點快照」（P0-10）

> <!-- 依 46c:422–426、44:437 補寫（三方一致），原文：
>      H14 en 逐字「Changes to your return rules apply only to future orders. Changes don't apply to previous orders」；
>      H13 zh-TW 逐字「對退貨規則所做的變更僅適用於未來的訂單」；
>      44 後台頁尾逐字「退貨與取消規則適用於在啟用或更新規則後所購買的品項」。
>      我方原本 16／13／28 全無 → 商家改規則會追溯既往，舊訂單的退貨期限/費用全部跟著變 -->

| # | 規則 | 實作 |
|---|---|---|
| 1 | 規則**必須在下單當下 snapshot 到 line item** | `order_line_items.return_policy_snapshot_id` **NOT NULL**（FK → `return_policy_snapshots.id`）；**不可只存 `return_rule_id` 外鍵**（規則會被改） |
| 2 | 快照表 append-only、immutable | `return_policy_snapshots(shop_id, source_rule_id, window_days, window_start_basis, shipping_fee_mode, shipping_fee_cents, restocking_fee_bp, is_final_sale, created_at)`；規則每次儲存產生新一筆，舊筆永不更新 |
| 3 | 退貨期限、退貨運費、重新上架費、最終銷售 **一律讀快照**，不得讀現行規則 | 前台「申請退貨」入口與 admin `returnCalculate` 都走快照 |
| 4 | 規則**可有多條**（預設規則 ＋ N 條），且可按市場切換 | `return_rules` 一對多；快照時解析出唯一適用規則 |
| 5 | 兩個**獨立** toggle：**退貨規則管已履行品項／取消規則管未出貨品項**，同一訂單可並存 | 前台「申請」按鈕**逐 line item 判斷**，不是整單一個按鈕 |
| 6 | **最終銷售品項**以 collection 或 product 為粒度；命中即**前台完全不出現申請入口**（不是提交後被拒）；**bundles 不可設為最終銷售** | 入口層擋掉（46c:427–432 逐字「Your customers can't submit return or cancellation requests for final sale items」） |
| 7 | 退貨期間選項 `14 / 30 / 90 / 不限 / 自訂`；起算點＝**個別品項配送日** 或 **訂單最後一項配送日** | `limits.return.window_day_options` / `window_start_options`；我方原本缺「不限」與「訂單最後一項配送日」 |
| 8 | 建立退貨當下**庫存不變**，品項標記「待收退貨品項」；處理時才選重新入庫地點 | 佔位存在 13-F5 的 `unavailable` 子分類（P0-15），不是 `committed` |

### F7.5 `returnProcess` 的冪等（文檔空白處，本專案強制）

`returnProcess` 內含退款（`financialTransfer.issueRefund`），實質是金流寫入，**Shopify 文檔未載明其冪等保證**（46a:620、46a:654、46a:1062）——**本專案強制帶 `idempotencyKey`**（已列入 `limits.idempotency.required_for`）。不要因為 Shopify 沒寫就不做：重試會**重複退款**。

### F7.6 `refundCreate` 與 `returnProcess` 的分工

<!-- 依 46a:642、46a:806–809 修正，原文：`returnRefund` **已 deprecated**；有退貨脈絡走 `returnProcess`、無脈絡走 `refundCreate`。
     🔴 此處原本寫錯：docs/research/28:91 仍把 `returnRefund` 列為現行 mutation。任何人翻舊版都不要改回去。 -->

| 情境 | 走哪支 | 理由 |
|---|---|---|
| 有 return 關聯（退貨/換貨） | `returnProcess` | 用 `ReturnLineItem` 參照，解決多數量退貨的歧義；一次完成 disposition ＋ 退款 ＋ 換貨 |
| 無 return 關聯（純取消、客訴補償） | `refundCreate` | `refundCreate` **未全域廢止**，2026-04 才剛加上強制冪等 |
| ~~`returnRefund`~~ | **已 deprecated，不實作** | 46a:806–809 |

兩條路底層共用同一個 `Refunds::Calculator` ＋ `RefundService`（鐵律 7）。

## 本篇驗收（對照 11 §0）

雙 staff 併發 fulfill/refund 不產生超量；退款上限在惡意請求下不可突破（request spec）；restock 重放冪等；cancel 後庫存恆等式仍成立（ledger 對帳）；訂單列表 10 萬筆下 p95 <300ms（keyset 驗證）；匿名化後全文搜尋/匯出查無 PII；每個動作 timeline 都有事件且 audit 可追。

**本次新增（P0 修正對應）**：
- F5.1 公式的三個算例（F5.2）逐一斷言，**算例 3（換貨＋退貨費）必須產生 `refund=0` ＋ `balance_to_collect=58000`**；任何 float 出現在中間值即測試失敗。
- `returnCalculate` 與 `returnProcess` 對同一輸入回傳**完全相同**的金額（數字同源測試）。
- FulfillmentOrder 狀態機：(b) 的 16 條合法轉移全綠、(c) 的 8 條非法轉移全部回 `INVALID_STATE`。
- **拆單不變量**：任意 cancel/hold/move 序列後，`Σ 所有 FO 的 line item quantity == order line item 可履行數量`（property test）。
- Return 狀態機：(c) 的 7 條非法轉移全部被擋；`REQUESTED → CANCELED` 必須失敗。
- **F4.1 G3 互鎖**：存在 `REQUESTED`/`OPEN` 的 return 時 `orderCancel` 必失敗；反向亦然。
- 換貨：建立帶 `exchangeLineItems` 的 return 後，該 FO 必為 `ON_HOLD` ＋ `AWAITING_RETURN_ITEMS`，且 `fulfillmentCreate` 必失敗。
- 快照：改退貨規則後，舊訂單的 `returnCalculate` 結果**不變**（回歸測試）。
