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
2. 不變量（nightly 對帳 job 斷言）：**同一 order 的 FulfillmentOrder（含已取消者的替代單）對每個 line item 的 `quantity` 總和，恆等於 order line item 的可履行數量——取數排除已被替代的歷史段**（部分出貨遭 cancel 時原 FO 已出貨段留史；等價式＝`Σ remainingQuantity ＋ Σ 非 CANCELLED fulfillment 量`，總綱 S-14 同式 <!-- 2026-08-17 更正（PR #52 第 12 輪）：原「所有 FO 總和」為雙計形 -->）。此斷言就是「品項憑空消失」的黑盒測試。
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
1. Cancel 前置檢查：見 F4.1 的**五條聯集** guard；動作 = 狀態條件轉移 + 庫存 committed 釋放（available+；**僅限 T1 曾 commit 的行**——`ON_FULFILLMENT` deferred 行與 `tracked=false` 行未進 committed，無條件釋放會下溢或憑空生 available（總綱 S4/S13 例外的反向條件；測試須含「取消含 deferred 行的訂單 ⇒ 該行不動帳」）（2026-08-17 更正，PR #52 第 19 輪））+ 依選項退款（走 F5）+ **關閉／取消所有未結 FulfillmentOrder（走 F3.2 的替代單語義）** + 事件 + outbox（orders/cancelled）；`reason` 與 `restock` **皆為 non-null 必填**。
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

### F4.4 COD（貨到付款）對帳回寫（P1-08／TW-7）

> <!-- 依 42:542 補寫，原文逐字：「COD 訂單付款狀態＝pending（`manual` gateway），出貨後由物流代收→對帳回寫 paid（16 號）」。
>      50 號 TW-7 缺口③逐字：「COD 對帳回寫 paid 的流程在 16 完全沒有（無 manual gateway 對帳規格）」。本輪複核確認成立。 -->

| 階段 | 狀態 | 動作 |
|---|---|---|
| 訂單成立 | `financial_status = PENDING`、`gateway = manual`、`order_transactions` **不建 sale 列** | 只建 `kind = 'sale', status = 'pending'` 的一列，金額＝含代收手續費的應收總額 |
| 出貨 | 不變 | fulfillment 帶物流商代收單號；`orders.cod_expected_cents` 落庫 |
| 物流商撥款對帳 | `PENDING → PAID` | 匯入物流商對帳檔 → 逐筆比對 `(carrier, cod_tracking_no, amount_cents)`；**完全相符才**條件式 UPDATE transaction `pending → success` |
| 金額不符 | 停在 `PENDING` ＋ 標 `review` | **不得自動回寫**；進「COD 對帳差異」佇列由人工處置（差 1 元也不放行——這是現金流入口） |
| 買家未取件退回 | `PENDING → VOIDED`（或取消訂單） | 走 F4 取消流程；庫存依 `restock` 回補；🔴 **由訂單層直接發 `TaxEvent(kind: sale_uncollected)`，不走 F5.5 的退款 router**。憑證動作由法域 pack 決定：`tax_invoice: gui`（TW）⇒ `einvoice/void_requested`；`tax_invoice: none`（HK）⇒ `no_document` ＋ 落一列 `jurisdiction_capability_skips` |

<!-- 依 docs/specs/55 §B.1 T17、§D G-05 修正，原文：「**觸發 F5.5 的發票 router**」。
     🔴 此處原本寫錯：未取件退回時**款項從未收到**，退款金額為 0 → router 的三分支（== 作廢／< 折讓／> 作廢）
     會全部落到「折讓 0 元」：開一張 0 元折讓、原發票仍然有效 ⇒ 一筆從未成立的銷售留著全額發票。
     必須由訂單層事件直接作廢。任何人翻舊版都不要改回走 router。 -->

<!-- 依 56 §E 分流，原 55 §D 結論：G-05「COD 未取件退回走**訂單層**作廢，不走退款 router」。
     依 56 §E.1，**憑證面在 HK 為 N/A**（無作廢機制），但**訂單層 `PENDING → VOIDED` 的金流與庫存處理原樣保留**。
     本輪的實質改動只有一處：事件名稱從 TW 專屬的 `einvoice/void_requested` 改為法域中性的
     `TaxEvent(kind: sale_uncollected)`（56 §A.2 C1 的五個 kind 之一），由 pack dispatch 成憑證動作或 no_document。
     🔴 G-05 的原始教訓在 HK **完全不變**：那是「router 的入參語義不成立」，不是「憑證怎麼開」——
        `refund_cash_cents == 0` 走退款路徑會靜默產生一個看起來成功的錯誤結果，這與有沒有稅制無關。
        HK 下若照舊走 router，症狀會從「開一張 0 元折讓」變成「落一列 refund 金額 0 的假退款」，一樣是髒資料。
     🔴 防回退：任何人日後因為「HK 沒有發票」而清掉本列，會連帶清掉訂單層 VOIDED 的處置——那是金流與庫存動作。 -->

**硬要求**：對帳匯入是**冪等**的（以 `(carrier, statement_id, row_no)` 唯一索引去重，重覆匯入同一份對帳檔不得產生兩筆 paid）；回寫一律走 `Orders::MarkAsPaid` 同一支 service（不得在匯入器裡直接 `update(financial_status:)`）。
**⚠ 待查證（來源未載明）**：各物流商對帳檔格式與撥款週期為合約值，非官方文檔（同 V-11 的 `verify_tw_carrier_limits`）。

## F5. 退款（Refund）

**生產級做法**：
1. 退款面板：逐行選數量（≤ 已購未退數）、restock 勾選（預設勾，**僅在該品項有追蹤庫存時可用**）、另退運費欄（≤ 可退運費）、原因、是否通知（預設勾）——完全對齊研究 01 的畫面。**數量設為 0 的品項不退款**；退款頁**可直接對商品項目套用折扣**（46c:218–221）。
2. 計算：**一律走 F5.1 的公式**（不得在 UI 或 controller 另算一份）。
3. 執行順序：本地 transaction（建 refund + refund_line_items + transaction 列 pending + restock via Inventory::Adjust 冪等 + 事件）→ **出口分目的地**（2026-08-17 更正，PR #52 第 21 輪——原單一 Stripe 出口會讓禮品卡/store credit/manual 退款的交易永停 pending、投影卡 PAID）：**外部金流分支**＝transaction 外呼叫 Stripe refund → webhook 確認 → transaction 列轉 success；**內部目的地分支**（禮品卡餘額回加、store credit 寫入、manual 線下退款）＝無 PSP 呼叫，transaction 列於**同一本地 transaction 內即建 success**（manual 需對帳確認者走 F5 物流商撥款對帳的條件式 UPDATE `pending → success` 形）→ financial_status 重物化 → 通知信。
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
  3. **零小數幣別（JPY 等）** → 業務層**完全不感知**；單位換算只發生在**跨界點**（R1 儲存 cents → 該 PSP pack 宣告的 `amount_format` 對應表示法，R5 或 R6），唯一出口是 `Money::Storage#to_psp_amount(psp:)`，契約見 **65 §D**（落地見 15-F4 第 5 點）。
     🔴 注意這一點**不是捨入點**：`minor_units` 分支對餘數的處置是 **raise，不是 round**（65 §D.2 A3；`decimal_string` 分支的對應規則是 A6 宣告位數檢查——同一條紀律在另一種格式的形態）。JPY 的 `148050`（¥1,480.50）代表**上游算錯了**（湊整規則沒套用，29 §3.3），悄悄抹掉那 50 會讓對帳永遠差幾分錢卻查不出來。所以本節「只有三個捨入點」的斷言**不因本點而破**——第三點根本不捨入。
     <!-- 依 65 §J M-9（69 §V-188）二次修正（2026-08-13），原文：「（R1 儲存 cents → 該 PSP pack 宣告的 minor unit），
          唯一出口是 Money::Storage#to_psp_minor(psp:)」「to_psp_minor 對餘數的處置是 raise」。
          本點是 M-2 結案時用**當時正確**的新名改寫的；同日稍後 69 §V-188 把出口改名 to_psp_amount 並宣布
          舊名不留別名 ⇒ 二度過時。🔴 65 §J 的 M-9 只登記了 15 的三處，本處（與 55 §A.0）落在登記表縫隙裡，
          由 2026-08-13 跨界點詞 grep 補出——「登記表要靠 grep 補完」（65 §J.1）第三次應驗。 -->
     <!-- 依 65 §J M-2 修正，原文：「3. **零小數幣別（JPY 等）** → 只在序列化層由 15-F4 的 `stripe_amount()` 處理，業務層不感知。」
          **指標方向本來就是對的**（業務層不感知 ✅），錯的是它指向的定義已被 2026-08-12 裁定二作廢：
          15-F4 原本寫「JPY 等零小數幣別**不乘 100**」，那是裁定二**之前**的儲存模型（JPY 存 1480）。
          裁定二之後 JPY 存 148000，照那句話實作＝送 PSP 收款 100 倍。15-F4-5 已隨 M-1 改寫，本點改指 65 §D。
          🔴 **防回退**：不得改回 `stripe_amount()`——那個函式名已隨 M-1 廢止（它把 PSP 寫死在名字裡，
          而不同 PSP 對同一幣別可能宣告不同 minor unit）。也不得把本點降回一行「由序列化層處理」。 -->
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

**稅額分攤規則（P1-02，補完 H-07 的第二半）**
<!-- 依 46a:595–601 補寫上位公式；稅額分攤的**具體規則官方未載明**（46a:1049–1067 逐條列為未載明項之一，見 V-09）。
     50 號 P1「H-07 的稅額分攤未定義」成立：P0 輪只寫了 `line_tax[i] = 最大餘數法(該行稅額, 退貨比例)` 一行，
     未涵蓋①未稅／含稅兩種定價模式的分工 ②運費稅 ③退貨費用是否課稅 ④部分數量退貨的餘數歸屬。以下為**本專案定義**。 -->

| # | 情境 | 規則 | 理由 |
|---|---|---|---|
| X1 | **含稅定價**（台灣預設，`taxes_included = true`） | `line_tax[i] = 0`；稅只是 `line_net[i]` 的內含反推值，**不另加、不另退** | 稅已在單價內，重複加總會多退一次稅 |
| X2 | **未稅定價**（`taxes_included = false`） | `line_tax[i] = 最大餘數法( order_line_items.tax_cents[i] , qty_returned[i]/qty_ordered[i] )`——**分攤原始已收稅額，不用現行稅率重算** | 稅率可能已變更；重算會與原訂單對不上帳（同 15-F2「訂單存快照」原則） |
| X3 | **餘數歸屬** | 同一行分多次部分退貨時，餘數一律歸**最後一次**退貨（`Σ 各次 line_tax == 原始 tax_cents`，全退完必須精確歸零） | 保證「全部退完 ⟹ 稅退光」，不會殘留 1 分錢 |
| X4 | **運費稅** | 退運費時按 `refund_shipping_amount / shipping_cents` 比例分攤 `shipping_tax_cents`，同樣走最大餘數法；**訂單層免運折扣 ⟹ 運費與運費稅皆不可退**（46c:238） | 與 F5.1 運費退款規則同一道判斷 |
| X5 | **退貨費用（restocking／return shipping）是否課稅** | 本專案**不對退貨費用課稅**（`return_fees` 以未稅金額直接抵減 `net`） | **⚠ 待查證（來源未載明）**：46a 只給 `percentage` 與 `amount`，未定義稅務屬性——見 §待查證 V-13 延伸 |
| X6 | **不變量** | `Σ_i line_tax[i] ≤ 該訂單原始稅額 − 已退稅額`，且任何路徑都不得用 float 中間值 | 對帳測試斷言 |

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

**(a) 累計上限式（integer cents，法域無關）**

```
maximumRefundable_cents = orders.captured_total_cents − orders.refunded_total_cents
不變量（任何時刻）      : Σ refunds.amount_cents ≤ orders.captured_total_cents
                          ⟺ orders.refunded_total_cents ≤ orders.captured_total_cents
```

`refunded_total_cents` 是**物化欄位**（`limits.refund.cumulative_cap_column`），與 `refunds` 明細 nightly 對帳。**沒有捨入點**——這裡全是加減法，本節不引入任何 floor/ceil（唯一的三個捨入點仍在 F5.1 的分攤與 F5.5 的稅額拆分）。

**(b) 條件式 UPDATE 樣式（🔴 禁止先 SELECT 再 INSERT）**

```sql
-- 正常路徑：上限檢查與寫入在同一條 SQL，依 affected rows 判定成敗
UPDATE orders
   SET refunded_total_cents = refunded_total_cents + :amount_cents,
       updated_at = :now
 WHERE id = :order_id
   AND shop_id = :shop_id                                    -- 鐵律 2：複合索引以 shop_id 開頭
   AND refunded_total_cents + :amount_cents <= captured_total_cents;
-- affected == 1 ⇒ 在同一個 transaction 內 INSERT refunds ＋ refund_line_items ＋ outbox
-- affected == 0 ⇒ 見 (c)，**不得**改成先 SELECT 再判斷後重試
```

```sql
-- 超額路徑（46c:223 明載的合法情境）：帶權限與二次確認後走這條
-- 🔴 **仍然是條件式 UPDATE**，只是上界換成「本次核准的超額額度」，不是拿掉 WHERE 條件。
--    繞過條件式 UPDATE ＝ 在超額路徑上失去併發保護（`limits.refund.over_refund_uses_same_conditional_update: true`）
UPDATE orders
   SET refunded_total_cents = refunded_total_cents + :amount_cents
 WHERE id = :order_id
   AND shop_id = :shop_id
   AND refunded_total_cents + :amount_cents <= captured_total_cents + :approved_over_refund_cents;
```

**(c) `affected == 0` 的兩種語義必須分開回**（合成一個錯誤碼，前端就無從判斷要不要顯示二次確認）

| 判別 | 錯誤碼 | 前端行為 | HTTP |
|---|---|---|---|
| 重讀後 `refunded_total + amount > captured_total` | `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE` | 顯示超額退款二次確認；有 `orders.over_refund` 權限才可續行 | 200（鐵律 4） |
| 重讀後上限其實還夠（`lock_version`／`updated_at` 已變） | `REFUND_CONCURRENT_MODIFIED` | 退避後**原樣重試**（同一把 `idempotencyKey`） | 200 |

判別方式：`affected == 0` 後**重讀一次**做**分類**（只用於決定回哪個錯誤碼），**不得**用重讀的值去做第二次寫入決策。

**(d) 三個併發情境（各一個 request spec）**

| # | 情境 | 期望 |
|---|---|---|
| C1 | 已收 100000、已退 0，兩個分頁同時退 60000 | 恰 1 筆成功；另一筆回 `REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`；`refunded_total_cents == 60000` |
| C2 | 已收 100000，100 執行緒各退 1000 | 恰 100 筆成功、`refunded_total_cents == 100000`；第 101 筆失敗。**成功數 ＋ 失敗數 ＝ 請求數** |
| C3 | 退款與 `orderCapture` 併發（capture 使 `captured_total` 上升） | 不得出現 `refunded_total > captured_total` 的中間態；兩者對同一列競爭，後到者重試後成功 |

**(e) 為什麼 `refunded_total_cents` 不做成 DB CHECK**：`CHECK (refunded_total_cents <= captured_total_cents)` 會擋掉 46c:223 明載的合法超額退款（先前發過商店抵用金者可對原付款方式 over-refund）。**軟上限＝應用層條件式 UPDATE，硬約束只有 `refunded_total_cents >= 0`。**

<!-- 依 56 §E 分流，原 55 §D 結論：G-02「折讓沒有累計上限檢查 ⇒ 兩次各退 60% 會開出折讓總額 120%」。
     依 56 §E.1，該結論的**稅務側**（`Σ allowances ≤ invoice.total_cents`）在 HK 為 **N/A**——`tax_invoice: none`，
     沒有折讓單這種東西，整條規則移入 tw pack（見 F5.5(b)(d)，本節不動）。
     🔴 但**金流側的 `Σ refunded ≤ maximumRefundable` 是 55 §A.2 M09/M10 的不變量，法域無關，必須留著**。
     56 §E.1 把這條的危險等級標為「高（**容易誤刪**）」——把稅務側與金流側一起拿掉是本輪最容易犯的錯：
     兩者長得很像（都是「同一個對象的多次寫入有累計上界」），但一個是憑證面、一個是錢面。
     本輪的實質補充：55 §A.2 只給了式子與一句「條件式 UPDATE」，**沒有 SQL 樣式、沒有錯誤碼、沒有併發情境**，
     實作者無從判斷 `affected == 0` 要回哪個錯誤碼（而這直接決定前端要不要彈二次確認）。以上 (a)–(e) 補齊。
     鍵：`limits.refund.cumulative_cap_formula` / `cumulative_cap_enforcement` / `cap_exceeded_error_code`
         / `concurrent_conflict_error_code` / `over_refund_uses_same_conditional_update`。
     🔴 防回退：任何人日後因為「HK 沒有折讓」而清理 G-02 相關內容時，**不得**把本節一起刪掉。 -->

**運費退款規則**：`amount`（指定金額）或 `fullRefund`（全退）二選一；退運費**不得超過可退運費**；**訂單套用了訂單層級免運折扣 → 完全不可退運費**（46c:218–221、46c:238）。
**⚠ 待查證（來源未載明）**：`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為（46a §6② 明列為未載明）。

**混合付款的退款分配順序**：見 F5.4（P1-05，完整演算法與算例）。

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

### F5.4 混合付款的退款分配順序（P1-05／H-83，金額正確性）

> <!-- 依 46c:221 補寫，原文（H05 zh-TW 逐字）：「混合付款時，**系統先把退款金額套用到禮品卡**，直到禮品卡達可退全額，餘額才用其他付款方式」。
>      並依 46c:222「退款去向：原付款方式／商店抵用金／兩者併用」、46c:223「超額退款允許」、46c:241「已發過商店抵用金後想改退原付款方式需超額退款權限」。
>      我方原本只有 22:32 與 16-F5.1 各一句規則描述，**沒有演算法、沒有算例** → 混合付款訂單的退款會分配到錯誤的 transaction 上。 -->

**(a) 名詞**：`R` ＝ 本次要退的總額（＝ F5.1 的 `suggested_refund` 或商家覆寫值，integer cents）；
`payments[]` ＝ 該訂單所有**成功且尚有可退餘額**的付款 transaction，每筆帶 `gateway`、`captured_cents`、`already_refunded_cents`；
`refundable(t) = captured_cents(t) − already_refunded_cents(t)`。

**(b) 分配演算法（`Refunds::Allocator`，純函式、確定性、integer cents）**

```
# 第 1 順位：禮品卡（46c:221 逐字硬規則，不是偏好設定，商家不可調整順序）
gift = payments.select { gateway == 'gift_card' }.sort_by { |t| [t.created_at, t.id] }   # 同類多筆：先收先退
# 第 2 順位：其餘付款方式（原付款方式）
rest = payments.reject { gateway == 'gift_card' }.sort_by { |t| [t.created_at, t.id] }

remaining = R
allocation = []
for t in (gift + rest):                       # 順序固定：禮品卡在前
    take = min(remaining, refundable(t))      # 逐筆吃滿再進下一筆，不按比例攤
    if take > 0: allocation << { transaction: t, amount_cents: take }
    remaining -= take
    break if remaining == 0

# remaining > 0 ⇒ 已超出所有付款方式的可退餘額
if remaining > 0:
    → 走 F5.1 的「超額退款」路徑：需 `orders.over_refund` 權限 ＋ 二次確認 ＋ audit log；
      超出部分只能退到 **store credit**，或由商家明示指定某一筆原付款 transaction 承擔（46c:241）。
```

- **無捨入**：`min` 與減法皆整數；`Σ allocation.amount_cents + remaining == R` 為不變量。
- **不是按比例攤**：逐筆吃滿（greedy）是官方描述的語義（「直到禮品卡達可退全額」），按比例攤會讓禮品卡退不完。
- 退到 store credit 時走 `refundMethods`（46a:743），寫 `store_credit_transactions`（06 §7）。

**(c) 三個算例（TWD integer cents）**

**算例 A — 禮品卡吃得下**：訂單 100000，禮品卡付 30000 ＋ 信用卡付 70000；退 25000。
→ 禮品卡 25000、信用卡 0。（**不是**禮品卡 7500／信用卡 17500 的比例攤）

**算例 B — 禮品卡吃不下，溢出到原付款方式**：同上付款組成，退 50000。
→ 禮品卡 30000（吃滿）、信用卡 20000。

**算例 C — 已退過 ＋ 超額**：同上付款組成，先前已對禮品卡退 30000、對信用卡退 70000（`refundable` 全為 0），現因先前發過商店抵用金而需再退 5000。
→ 迴圈結束 `remaining = 5000` → 觸發超額退款路徑：需 `orders.over_refund` 權限＋二次確認，退往 store credit 並寫 audit log。**不得**被 DB CHECK 擋死（NP0-A 已定案）。

**(d) 必測性質**：①分配總和恆等於 `R`；②禮品卡永遠排在第一位（改成可設定即為 bug）；③同類多筆按 `created_at, id` 穩定排序（結果可重現）；④併發兩筆退款同時分配時，`refundable` 以條件式 UPDATE 取得（不可先讀後寫）。

### F5.5 退款／取消必須觸發稅務事件（P1-09／TW-5，稅務正確性）

> **法域分流（依 56 §E，2026-08-12）**——**本節整體降級為 `jurisdiction/tw` pack 的實作**，核心流程只負責**發稅務事件**，不生產憑證。
>
> | 層 | 誰負責 | 法域相關？ |
> |---|---|---|
> | **掛鉤點**（何時發事件）＝ (a) 表左兩欄 | 核心 | ❌ 法域無關，**全部保留** |
> | **事件 kind**＝`sale_recognised` / `sale_reversed` / `sale_reduced` / `sale_increased` / `sale_uncollected` | 核心 | ❌ 法域無關（56 §A.2 C1） |
> | **憑證動作**（開立／作廢／折讓／補開）＝ (a) 表右兩欄、(b) 判定樹、(d) 不變量 1–3 | `tax_invoice` pack | ✅ **TW only** |
>
> **HK（`tax_invoice: none`，基準法域）**：(b) 的 `route()` **不執行**，全部事件回 `no_document` ＋ 落一列 `jurisdiction_capability_skips`。🔴 它必須是**明確宣告的 no-op**，不是「沒有呼叫端」——後者正是 55 §D G-03 的病根（56 §B.2.1 末段）。55 §B 的 30 條事件點在 HK 的去向：**20 條轉純會計事件**（57 §G-07）／8 條消失／1 條轉移至 `tax_id_format`／1 條不受影響。
>
> <!-- 依 56 §E 分流，原 55 §D 結論：G-02（折讓累計上限）／G-03（作廢窗 fallback）／G-04（一訂單多發票）
>      三條的**稅務側**在 HK 皆為 N/A，移入 tw pack；G-01 的擋單處置**有害**（見 (a) 的 V-23 段）；
>      G-05 的訂單層處置**保留**（見 F4.4）；G-04 的 **schema 結論保留**（見 (c) 第 5 點）。
>      🔴 台灣內容**一行未刪**（56 §C.3 不刪除聲明）——本節仍然滿是統一發票內容是**刻意保留**，不是漏改。 -->

> <!-- 依 38:876–877（33 §2.14）補寫，原文：開立時機三選一「付款／**出貨（建議）**／收貨」；「全額取消**自動作廢**、部分退貨**自動折讓**」；
>      落地物在 38:1338–1356 `Platform::Einvoice::RefundRouter`（== 作廢／< 折讓／> 作廢，金額全程 integer cents）與 38:1104 的 `VoidJob` / `AllowanceJob`。
>      50 號 TW-5 逐字：「`16-F5` 退款流程（16:45 的執行順序）完全沒有呼叫發票 router 的步驟；`16-F4` 取消訂單也沒有；`18-F1` outbox topic 清單沒有 `einvoice/*`
>      → 退款不會觸發作廢/折讓 ＝ 稅務錯誤」。本輪複核確認：`grep 發票|einvoice` 於 15／16／18 命中數 ＝ 0。 -->

**(a) 掛鉤點（三處，缺一即稅務錯誤）**

| 觸發 | 位置 | 事件 topic | 下游 |
|---|---|---|---|
| 訂單全額取消 | F4 主流程最後一步（**transaction 內寫 outbox，transaction 外執行**） | `einvoice/void_requested` | `Platform::Einvoice::VoidJob`（38:1104） |
| 退款（不論走 `refundCreate` 或 `returnProcess`） | F5 執行順序第 3 步之後 | `einvoice/refund_routed` | `Platform::Einvoice::RefundRouter`（38:1341）→ VoidJob 或 AllowanceJob |
| 出貨（`issue_timing = on_fulfillment` 時的開立） | F3 出貨 transaction 的 outbox | `einvoice/issue_requested` | `Platform::Einvoice::IssueJob`（38:1103） |
| **訂單編輯 commit 造成總額變動**（NP1-H，本輪新發現） | F8.1(c) 的 commit transaction | `einvoice/refund_routed`（同 router） | 總額**下降**⇒ 折讓；總額**上升**⇒ 補開一張發票（不是改原發票） |
| **換貨：買家補差額**（`net < 0`，F7.3 規則 7） | 補款成功後（M17 同一路徑） | `einvoice/issue_requested` | **補開一張**，金額＝`balance_to_collect` |
| **換貨：退差額**（`net > 0`） | F5 執行順序第 3 步之後（同退款） | `einvoice/refund_routed` | 折讓，金額＝實際金流退款額 |
| **換貨：等值互換**（`net == 0`） | — | **無事件** | ⚠ **待查證 V-23 同組**：等值換貨是否須「折讓原發票＋重開」台灣實務未覆核；暫定 **no-op**（無金額變動＝無折讓基數） |
| **COD 買家未取件退回**（F4.4 第 5 列） | F4 取消流程的 outbox | `TaxEvent(sale_uncollected)` ⇒ TW 落地為 **`einvoice/void_requested`**（🔴 **不是** `refund_routed`）；HK 為 `no_document` | 直接作廢；作廢窗已關 ⇒ 全額折讓 |

<!-- 依 docs/specs/55 §B.1 T13–T15、T17 與 §D G-05、G-09 補寫。
     ①**換貨三列原本完全不存在**：F7.3 有八條換貨規則，**無一條提發票** → 補差額不補開、退差額不折讓 ＝ 稅務金額與實收對不上（55 §D G-09）。
     ②🔴 **COD 未取件退回原本寫「觸發 F5.5 的發票 router」，但 router 的入參語義在此不成立**：
        該情境的退款金額為 **0**（款項從未收到），router 的三分支（== 作廢／< 折讓／> 作廢）會全部落到「折讓 0 元」——
        開一張 0 元折讓、原發票仍然有效 ⇒ 一筆從未成立的銷售留著全額發票。
        改為由**訂單層事件**直接發 `einvoice/void_requested`，不經退款路徑。任何人翻舊版都不要改回走 router。（55 §D G-05） -->

**⚠ 待查證（來源未載明，V-23）**：`issue_timing = on_fulfillment` 在**部分出貨**時的開立粒度（每次出貨各開一張／全部出完才開一張）——38:876 只寫「出貨（建議）」，未定義多次出貨；Shopify 不開立台灣發票，三份官方文檔皆不可能有答案。

**擋單規則（🔴 有法域條件，不是無條件）**：

```
# 依 56 §E 分流補上 pack 條件。判斷順序不可顛倒——先問法域，再問未定案。
pack = Jurisdiction.resolve(order).seller          # 取 orders.seller_jurisdiction 快照
if pack.tax_invoice.kind == :none:
    → 照常出貨。落一列 jurisdiction_capability_skips(capability: tax_invoice,
        event_kind: sale_recognised, source_write_point: 'F3 fulfillment', reason: 'no_document_regime')
    #   documented_no_op，**不是**靜默 return（56 §A.3）
elif pack.tax_invoice.block_multi_fulfillment_when_undecided
     and pack.tax_invoice.partial_fulfillment_issue_granularity.nil?
     and order.fulfillments.count > 1:
    → 擋下並轉人工佇列（不得靜默選一邊）
else:
    → 依 partial_fulfillment_issue_granularity 開立
```

<!-- 依 56 §E 分流，原 55 §D 結論：G-01「⚠ V-23 未定案；**定案前該組合擋下並轉人工佇列**」。
     🔴 此處原本寫錯（漏了法域條件）：原文為「定案前，`on_fulfillment` ＋ 多次出貨的組合**一律**擋下並轉人工佇列」——
        **無條件**。在基準法域 HK（`tax_invoice: none`）下照此實作，會把**所有多次出貨的訂單卡進人工佇列**：
        HK 根本沒有憑證可開，`partial_fulfillment_issue_granularity` 永遠是 `null`，擋單條件永遠成立。
        56 §E.1 已把此列為危險等級**最高**（會造成營運中斷）並落了 `block_multi_fulfillment_when_undecided: false`，
        但那只是 limits 的一個值——**本節（唯一的呼叫端）當時沒有讀它**。旗標寫了卻沒有人讀，
        病根與 55 §D G-03（`EinvoiceVoidPolicy.window_open?` 掛勾寫了但 router 從不呼叫）**完全相同**，只是換到法域層。
     鍵路徑：`limits.jurisdictions.<code>.tax_invoice.partial_fulfillment_issue_granularity`（原 `limits.einvoice.*`）
             ＋ `.block_multi_fulfillment_when_undecided`（hk: false／tw: true）。
     🔴 防回退：任何人翻舊版看到「一律擋下」都不要改回無條件版本。HK 分三次出貨必須三次全部正常完成（56 §F 驗收 9）。 -->

**⚠ 待查證（來源未載明，NP1-G ／ V-20，55 號盤點**擴大至商店抵用金**）**：退款分配到**禮品卡**或**商店抵用金**的部分是否計入發票折讓基數——F5.4 會把退款優先分配給禮品卡（且 `refundMethods` 支援退至 store credit，46a:743），但 38:1341 的 router 只比較「退款金額 vs 發票金額」。台灣實務上商品禮券／購物金退回未必等同現金退款，兩份規格的交界**皆未定義**。在覆核前，router 的輸入一律傳「**扣除禮品卡與商店抵用金分配後**的實際金流退款額」並標旗標（`limits.einvoice.allowance_base_excludes`），見 §待查證 V-20／V-22。

**(b) 路由判定（55 號盤點收斂版，取代 38:1341 的「單張發票 × 單次退款」判定）**

> <!-- 依 docs/specs/55 §B.2、§D G-02／G-03／G-04／G-10 修正。
>      🔴 此處原本寫錯：本節原文為「退款金額 `== 發票金額` → 作廢；`<` → 折讓；`>` → 作廢」，直接照抄 38:1341 的
>      `if refund.amount_cents >= invoice.total_cents`。該判定**只看本次退款額、只看一張發票**，有四個破口：
>        ①**無累計上限**：兩次各退 60% ⇒ 開出兩張各 60% 的折讓 ⇒ 折讓總額 120% > 發票金額 ⇒ 稅務申報錯誤且不可逆。
>        ②**作廢窗已關時無 fallback**：38:1356 留了 `EinvoiceVoidPolicy.window_open?` 掛勾但 router **從不呼叫**
>          ⇒ 跨期別的全額退款會嘗試作廢、被加值中心拒絕、該筆銷售永遠沒有沖銷憑證。
>        ③**假設一訂單一發票**（38:1346 逐字 `refund.order.einvoice` 單數）⇒ 與本節 (a) 的「總額上升補開一張」直接矛盾。
>        ④**開立在途（`state='issuing'`）判為 no_invoice 而 no-op** ⇒ 加值中心 p95 數秒（38:1303）的窗口內退款會永久遺失稅務動作。
>      任何人翻舊版看到 `refund.amount_cents >= invoice.total_cents` 都不要改回去。 -->

```
route(order, refund_cash_cents):        # refund_cash_cents 定義見 (a) 的 V-20/V-22 註記
  # 0. 在途保護：開立中的發票不得被當成「沒有發票」
  if order.einvoices.exists?(state: 'issuing'): return :defer     # 🔴 延後重試，不得 no-op

  invoices = order.einvoices.where(state: 'issued')
  return :no_invoice if invoices.empty?                            # 尚未開立 ⇒ no-op（不產生孤兒作廢）

  # 1. 沖銷順序：能追溯到品項的先沖該張；不能追溯者 LIFO（後開的先沖，離作廢窗關閉最遠）
  #    ⚠ 無官方來源，本專案決策（limits.einvoice.allowance_offset_order: traceable_then_lifo）
  remaining = refund_cash_cents
  for inv in ordered_invoices(invoices):
      allowed = inv.total_cents - Σ inv.allowances.amount_cents    # 該張剩餘可沖額＝累計上限
      take    = min(remaining, allowed)
      next if take == 0
      if take == inv.total_cents and inv.allowances.empty? and EinvoiceVoidPolicy.window_open?(inv):
          → VoidJob(inv)                                           # 全額 + 未折讓過 + 作廢窗未關 ⇒ 作廢
      else:
          → AllowanceJob(inv, amount_cents: take)                  # 其餘一律折讓（含「本該作廢但窗已關」）
      remaining -= take

  # 2. 超額退款：沒有稅務憑證可沖，🔴 不得憑空產生折讓
  enqueue_manual_review(order, remaining) if remaining > 0
```

**金額比較全程 integer cents**（傳入 float 即 raise，38:1508 既有測試）。累計上限一律以**條件式 UPDATE** 實作（`limits.einvoice.allowance_cap_enforcement: conditional_update`），**禁止先 SELECT 再 INSERT**。

**折讓單的未稅／稅額拆分（含稅定價，台灣預設）**——唯一捨入點是 `floor`，稅額用差額法保證精確相加：

```
allowance_untaxed_cents = floor( take * 10000 / (10000 + limits.einvoice.business_tax_rate_bp) )
allowance_tax_cents     = take - allowance_untaxed_cents        # 差額法 ⇒ 未稅 + 稅 == 含稅（無 1 分錢漂移）
```
未稅定價（`taxes_included = false`）時改走 F5.1 的 X2／X3（最大餘數法、餘數歸最後一次）。
**⚠ 待查證**：折讓單金額拆分的**法定捨入方向**尚未由本專案覆核，上式為本專案決策的機械規則。

**(c) 硬要求**
1. outbox 寫入與退款／取消**同一個 transaction**（18-F1 的「事件必達」保證）；provider 呼叫一律在 transaction 外。
2. 發票 job 失敗**不得**回滾退款——退款已對顧客生效，發票補開由 38 的重試與「開立失敗待重試」告警承擔（38:909）。
3. 尚未開立發票的訂單被退款 → router 直接 no-op（不產生孤兒作廢）；**但「開立在途」不算「尚未開立」**，見 (b) 第 0 步。
4. 18-F1 的 topic 清單與 28 §15 的 webhook topics 必須同步新增這三個 `einvoice/*`。
5. **一張訂單可以有多張發票**（編輯加收補開、以及 V-23 若定案為「每次出貨各開一張」）——🔴 **不得**對 `einvoices(shop_id, order_id)` 建唯一索引（`limits.jurisdictions.tw.tax_invoice.multiple_invoices_per_order_allowed: true`）。
   <!-- 依 56 §E 分流，原 55 §D 結論：G-04「schema 級裁決，上線後改不得」。
        **稅務理由在 HK 為 N/A**（`tax_invoice: none` ⇒ `einvoices` 恆空），但 🔴 **結論保留**：
        schema 取所有 pack 的聯集，行為才取當前 pack（`limits.jurisdiction.schema_is_union_of_all_packs: true`）。
        本條在核心層的可執行列舉已補在 `limits.jurisdiction.schema_union_rules.forbidden_unique_indexes`
        ＋ `docs/research/06` §7.1——因為 `tw.enabled: false`，**建表的人不會去讀一個未啟用的 pack**，
        裁決值只留在 pack 內等於沒有落地。（57 §G-04）
        🔴 防回退：HK 上線後 `einvoices` 會是長期空表，任何人**不得**因此加唯一索引或刪表。 -->

**(d) 四條不變量（nightly 對帳斷言，55 §B.2）**
1. `Σ einvoice_allowances.amount_cents`（per invoice）`≤ einvoices.total_cents`——**任何時刻**成立。
2. `Σ 該訂單所有 issued 發票的 total_cents ≥ Σ 該訂單實收金流`（不得少開）。
3. 每一筆 `refunds` 都能對應到 0 或 1 筆 `void` ＋ N 筆 `allowance`，**不得對應到 0 個稅務動作**（除非 `:no_invoice`）。
4. 全程 integer cents。

**必測**：①同一發票連退 60%＋60% → 第二張折讓**只有 40%**，第三次退款轉人工佇列；②`window_open? == false` 的全額退款 → 產生**全額折讓**而非失敗；③`state = 'issuing'` 時退款 → `:defer` 並重試，最終仍產生折讓；④編輯加收補開後該訂單 `einvoices` 有 2 列；⑤COD 未取件退回 → 產生 `einvoice/void_requested`（**不是** 0 元折讓）；⑥含稅 105 折讓 → 未稅 100 ＋ 稅 5，且 `未稅 + 稅 == 含稅` 對 1～1,000,000 cents 全域成立。

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

**(i) 訂單層 `OrderReturnStatus`（6 值，聚合欄位）**：`NO_RETURN` / `RETURN_REQUESTED` / `IN_PROGRESS` / `INSPECTION_COMPLETE` / `RETURNED` / `RETURN_FAILED`——**derived，不可寫入**，由該訂單所有 return 聚合推導；訂單列表篩選器要支援（`28 §4` 的 `return_status` 搜尋語法）。

**推導表（P1-10，逐條可測；`Rs` ＝ 該訂單所有 return）**
<!-- 依 46a:123–134 補寫，原文：`OrderReturnStatus` 6 值。P0 輪已把 6 值落地於本節與 06:114、28 §4，
     但**未寫「由 5 態 return 如何聚合成 6 態」的推導規則** → 兩個開發者會寫出兩套結果。以下推導式為本專案定義（46a 只給值不給推導）。 -->

| 順位 | 值 | 判定式（由上而下，first match wins） | 說明 |
|---|---|---|---|
| 1 | `NO_RETURN` | `Rs 為空`，或全部 `∈ {CANCELED}` | 取消掉的退貨視同沒發生 |
| 2 | `RETURN_FAILED` | `∃ r ∈ Rs, r.status = DECLINED` 且**無**任何 `∈ {REQUESTED, OPEN}` 的 return | 只有在沒有進行中退貨時才顯示失敗，否則以進行中優先 |
| 3 | `RETURN_REQUESTED` | `∃ r, r.status = REQUESTED` | 待審優先於進行中（商家要先看到「有東西等你審」） |
| 4 | `IN_PROGRESS` | `∃ r, r.status = OPEN` 且該 r **未**完成全部 disposition | help 的「進行中」 |
| 5 | `INSPECTION_COMPLETE` | `∃ r, r.status = OPEN` 且該 r **已**完成全部 disposition、**尚未** `returnProcess` 出退款 | 即 46c C-07 判定「help 的『檢查完成』是 `OPEN` 底下的子進度 `inspection_completed_at`」的**訂單層投影** |
| 6 | `RETURNED` | 其餘（`Rs` 非空且全部 `∈ {CLOSED, CANCELED}`，至少一筆 `CLOSED`） | 全部處理完 |

**不變量**：①本欄**永遠不落庫為權威值**，可物化為查詢快取但必須能由 `Rs` 完全重算（nightly 對帳斷言重算值 == 快取值）；②`returnReopen`（R9）會讓訂單層從 `RETURNED` 退回 `IN_PROGRESS`——**訂單層是可逆的**，即使 return 層有不可逆轉移；③6 個值任一都不得由 API 直接寫入（`orderUpdate` 無此欄位）。

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
| 9 | **台灣七日鑑賞期的處置＝軟 guard，不是硬下限**（見下方 (b)） | `limits.return.tw_minimum_window_days: 7`，`tw_minimum_window_enforcement: warn` |

**(b) 台灣七日鑑賞期與退貨期間下限（P1-31／TW-10）**
<!-- 50 號 TW-10 逐字：「退貨規則的『退貨期間』下限未強制 ≥7 天——22:62 寫「14/30/90/自訂」，自訂可填 3 天即違法。`config` 與 spec 均無下限 guard」。
     🔻 **本輪複核：原判定的「硬下限」處方不成立，改為軟 guard**。三個理由：
     ①《消保法》第 19 條的七日解約權是**法定權利，獨立於商家退貨規則存在**——商家把自訂窗口設成 3 天並不會消滅它，
       平台該做的是「保證法定管道存在」，不是把商家的自訂窗口硬綁 ≥7。
     ②同法授權之「合理例外情事適用準則」明列多類**排除適用**的商品（易腐敗／客製化／已拆封影音／報紙期刊／線上數位服務等）；
       硬性 ≥7 會讓合法的例外商品**無法設定**，等於用一個錯誤取代另一個錯誤。
     ③本專案為多租戶 SaaS，商家可能銷往非台灣市場（退貨規則可按市場切換，F7.4 規則 4）——把台灣法規套到所有市場是錯的。
     法規原文仍未由本專案覆核（`limits.return.verify_tw_minimum_window: true`），因此**不寫死任何法律結論**。 -->

| # | 規則 | 落地 |
|---|---|---|
| B1 | 規則適用市場含 `TW` 且 `window_days < 7` 且 `is_final_sale = false` → **儲存時出警示**（可繼續儲存），文案指向消保法七日鑑賞期，並要求商家勾選「本商品屬合理例外情事」 | `returnRuleCreate/Update` 回 `userWarnings`（不是 `userErrors`）；勾選結果落 `return_rules.tw_statutory_exemption_claimed` |
| B2 | **法定管道恆存在**：不論商家規則設定為何，`TW` 市場的訂單在「配送日 + 7 天」內，前台一律提供「依消保法申請解約」入口（走 `returnRequest`，`reason = STATUTORY_WITHDRAWAL_TW`） | 這條才是真正的合規保證；B1 只是提醒 |
| B3 | B2 的入口對 `is_final_sale = true` 的品項**仍然出現**（最終銷售不能排除法定權利），但對已勾 `tw_statutory_exemption_claimed` 的品項出現時附例外說明 | 與 F7.4 規則 6「最終銷售前台不出現入口」的**唯一例外**，實作要特別測 |
| B4 | 商家未在 admin 設定任何退貨規則時，`TW` 市場的預設快照 `window_days = 7` | 預設值取自 `limits.return.tw_minimum_window_days` |

**⚠ 待查證（來源未載明）**：《消費者保護法》第 19 條與「通訊交易解除權合理例外情事適用準則」的**條文原文與現行例外清單**尚未由本專案覆核（同 50 號 §必須查證 的精神）——B1–B4 的**機制**可以先實作，**具體例外品類清單不得由本規格臆測**，須以主管機關公告原文填入。見 §待查證 V-17。

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

## F8. 訂單編輯（Order Edit）

> 本節為新增。原本 16 號完全沒有訂單編輯規格，只散落在 22 §1b 的按鈕表一列與 28 §4 的一行 mutation 鏈。

### F8.1 CalculatedOrder 暫存層與 `stagedStatus`（P1-16／S-19）

> <!-- 依 46a:889–903、46a:985–986 補寫，原文（逐字）：
>      「Order ──orderEditBegin──> CalculatedOrder（暫存區，含 OrderEditSession）… CalculatedOrder ──orderEditCommit──> Order（套用，觸發 orders/edited webhook）」；
>      「`CalculatedOrder` 是**暫存區**（staging area），內含 `addedLineItems`、`lineItems`、`shippingLines`」；
>      「`shippingLines` 有 **`stagedStatus`** 欄位，值為 `ADDED` / `REMOVED` / `UNCHANGED`」；
>      「The system recalculates taxes and totals automatically as edits occur.」；「Commit 後 `Order.edited` 變 `true`」。
>      46a §8⑦-39 逐字：「**必須實作 CalculatedOrder 暫存層**（獨立資料表 + session），不能做成『直接改單』。編輯期間原訂單完全不動，commit 才落地——這是可回退、可預覽的唯一做法。」
>      我方 28:94 原本只有 `orderEditBegin → … → orderEditCommit` 一行鏈，**沒有暫存表、沒有 stagedStatus、沒有 session** → 照現有規格會做成「直接改單」，無法預覽/回退。 -->

**(a) 資料模型（兩張新表）**

| 表 | 欄位 | 說明 |
|---|---|---|
| `order_edit_sessions` | `shop_id`, `order_id`, `staff_id`, `started_at`, `committed_at`(NULL), `abandoned_at`(NULL), `expires_at` | **唯一索引 `(order_id) WHERE committed_at IS NULL AND abandoned_at IS NULL`**（見 F8.2） |
| `calculated_orders` | `shop_id`, `order_edit_session_id`, `snapshot_json`, `subtotal_cents`, `discount_total_cents`, `shipping_cents`, `tax_cents`, `total_cents`, `recalculated_at` | 暫存區；**原 `orders` / `order_line_items` 在 commit 前一個欄位都不動** |

`snapshot_json` 內含三個集合，每個元素帶 `staged_status`：

| 集合 | 元素 | `staged_status` 值 |
|---|---|---|
| `lineItems` | 原有品項（含改量、加品項折扣） | `UNCHANGED` / `REMOVED`（數量歸零）／`ADDED`（新加） |
| `addedLineItems` | 本次新增的 variant 與自訂品項 | 恆 `ADDED` |
| `shippingLines` | 運費行 | **`ADDED` / `REMOVED` / `UNCHANGED`**（46a:901 逐字三值，enum 照抄） |

**前端 diff 渲染完全由 `staged_status` 驅動**（`ADDED` 綠底、`REMOVED` 刪除線、`UNCHANGED` 常態）——**不得**在前端自行 diff 兩份 JSON 算差異（會與伺服器的稅額重算對不上）。

**(b) 每個 edit mutation 都即時重算**（46a:902 逐字）：任一 `orderEdit*` 之後立刻重跑 **15-F2 的同一支 Calculator**（鐵律 7），把結果寫回 `calculated_orders` 的金額欄位。**不是** commit 時才算一次——UI 的「差額」數字必須每步都正確。

**(c) commit 與放棄**

| 動作 | 行為 |
|---|---|
| `orderEditCommit` | 單一 transaction：套用 `snapshot_json` → 更新 `orders`／`order_line_items` → `orders.edited = true` → 寫 timeline 與 outbox `orders/edited` → `committed_at = now()` |
| 差額 > 0（總額上升） | 產生應收，走**寄發票／補款結帳連結**；**該補款結帳頁沒有加速結帳**（Shop Pay／Apple Pay 不可用，46c:470 逐字「You won't have accelerated checkouts available through the new checkout」） |
| 差額 < 0（總額下降） | 走 F5 退款流程（**不可逆**，二次確認） |
| 放棄／逾時 | `abandoned_at = now()`，`calculated_orders` 保留 7 天供稽核後 purge；**原訂單完全未變** |

🔴 **`orderEditCommit` 必須帶冪等鍵（NP1-D，本輪新發現，50 號漏列）**：`46a:962` 逐字「`orderEditCommit` **不在**強制冪等名單內（S49）」——但它會產生應收或退款，**是金流寫入**。與 `returnProcess`（P0-11 已強制）完全同性質：重覆 commit ⇒ 重複扣款或重複退款。
處置：比照 P0-11 的既有決策（**金流寫入一律強制冪等**）把 `orderEditCommit` 加入 `limits.idempotency.required_for`，並在鍵值註明「Shopify 未強制，本專案強制」。**不要因為官方沒列就不做。**

**(d) 兩個預設值照抄（P0 輪已進 limits，此處為使用點）**：`orderEditAddVariant.allowDuplicates` 預設 **false**（`limits.order.edit_add_variant_allow_duplicates_default`）、`orderEditSetQuantity.restock` 預設 **false**（`limits.order.edit_set_quantity_restock_default`）。
**(e) 加品項套 contextual pricing**（46a:927 逐字「respecting the variant's contextual pricing」）：依訂單的 market／presentment 幣別情境定價，**不是** variant 預設價。
**(f) `orderEditUpdateShippingLine` 只能改「本次新加入」的運費行**（46a:933 逐字「Modify title or price on **newly added** lines」）→ guard：`staged_status == 'ADDED'`，否則 `userErrors`。既有運費行只能 `RemoveShippingLine` 後重加。
**(g) 刻意不復刻**：46a:908「2019-01-01 前的訂單不可編輯」是 Shopify 的歷史包袱，**CHILL LOVE 不復刻**（46a §8⑦-46 明確建議），此處明文標註以免下輪稽核誤判為遺漏。

### F8.2 編輯 session 的併發鎖與 TTL（P1-17／H-33，文檔空白處）

> <!-- 依 46a:959–963、46a:988–989 補寫，原文逐字：「**文檔未載明** OrderEditSession 的鎖機制、TTL、或同一訂單並發編輯的行為」；
>      「唯一的併發線索：`orderEditBegin` 回傳 `orderEditSession`，暗示 session 是具名資源，**但文檔未說明兩個 session 同時開啟會發生什麼**」。
>      46a §8⑦-42/43 逐字建議：「同一訂單同時只允許一個 open 的 edit session（DB unique index on `order_id where committed_at is null`），第二個 begin 回 `userErrors` 帶 `INVALID_STATE`。
>      （我方落地鍵＝生成欄 open_flag＋`UNIQUE(shop_id, order_id, open_flag)`（同 C1；MySQL 8 可建），鐵律 2 shop_id 開頭——上句為 46a 原文引述，鍵形以總綱 X-19 為準 <!-- 2026-08-17 註（PR #52 第 15 輪；同形化第 16 輪） -->）
>      要在程式碼註明『Shopify 未載明，此為本專案決策』」「Session TTL 自訂（建議 24h，與冪等 TTL 對齊），逾時自動丟棄，寫進 `config/limits.yml`」。 -->

**⚠ 這整節是「Shopify 文檔未載明 → 本專案決策」**（46a 自己標的空白處，`limits.order.edit_session_*` 已於 P0 輪落地，本節是它的規格面）。

| # | 規則 | 落地 |
|---|---|---|
| C1 | **同一訂單同時只允許一個 open session** | DB 唯一索引＝**生成欄** `open_flag`（open ⇒ 1；committed/abandoned ⇒ NULL）＋ `UNIQUE(shop_id, order_id, open_flag)`——MySQL 8 無 partial index、唯一索引多筆 NULL 並存故歷史 session 不擋（58 §D.5(b) waybill 生成欄同法（第 17 輪更正：原引 §G.3 錯節）；鐵律 2 shop_id 開頭 <!-- 2026-08-17 更正（PR #52 第 16 輪）：原「部分唯一索引 (order_id) WHERE …」MySQL 8 建不出且無 shop_id -->）（`limits.order.edit_session_single_open_per_order: true`）；第二個 `orderEditBegin` 回 `userErrors{code: INVALID_STATE}` 並帶持有者 staff 名稱與開始時間 |
| C2 | **TTL 24 小時**，與冪等 TTL 對齊 | `limits.order.edit_session_ttl_hours: 24`；`expires_at = started_at + TTL`；hourly job 把逾期 session 標 `abandoned_at` |
| C3 | 逾期 session 的 commit | 一律拒絕（`INVALID_STATE`）——不可讓 24 小時前的暫存值套用到已被別人改過的訂單 |
| C4 | commit 前**重驗訂單版本** | `orders.lock_version` 在 begin 時快照，commit 時比對；不一致 → 拒絕並要求重開 session（樂觀鎖） |
| C5 | 強制接管 | `orders.force_release_edit_session` 權限者可強制 `abandoned` 他人的 session，寫 audit log |

### F8.3 不可編輯訂單的九條聯集 guard（P1-21／H-94）

> <!-- 依 46c:479–488（help 側 6 條）與 46a:907–913（dev 側 5 條）**取聯集**補寫。46c C-09 判定逐字「不可編輯訂單清單 help/dev 無交集 → 取聯集」。
>      原文（help，46c:482–487 逐字）：「匯入 Shopify 管理介面的訂單（app 建立的，除非由訂單草稿轉換而來）」「使用 Shop Pay 分期付款的訂單」
>      「配送方式為當地配送（local delivery）的訂單」「待處理付款（Pending payment）狀態的訂單」「含已出貨品項的部分」「含已出貨品項且帶稅/關稅的訂單」；
>      原文（dev，46a:908–912 逐字）：「Archived orders or **orders placed before January 1st, 2019**」「Orders placed in currencies other than store currency (without Checkout Extensions upgrade)」
>      「**You can only edit unfulfilled line items.**」「Subscription orders with prepaid plans…」「Subscription orders via checkout UI extensions」。
>      我方 22:38（現 22:38 Edit 列）原本只有「已出貨項不可移除」「分期付款單不可編輯」**兩條**，其餘七條全缺。 -->

**判定順序：整單級（E1–E7，擋住 `orderEditBegin`）→ 行級（E8–E9，擋住個別 mutation）**

| # | 條件 | 判定式 | 來源 | 層級 |
|---|---|---|---|---|
| E1 | 訂單已取消 | `orders.cancelled_at IS NOT NULL` | 本專案（與 F4.1 對稱） | 整單 |
| E2 | **匯入訂單**（外部 app 建立，且非由草稿轉換） | `orders.source = 'import'` AND `orders.draft_order_id IS NULL` | 46c:482 | 整單 |
| E3 | **Shop Pay 分期付款單** | `EXISTS(order_transactions WHERE payment_method_type = 'installments')` | 46c:483 ＋ 我方原有 | 整單 |
| E4 | **當地配送（local delivery）訂單** | `EXISTS(shipping_lines WHERE delivery_method_type = 'LOCAL_DELIVERY')` | 46c:484 | 整單 |
| E5 | **待處理付款訂單** | `financial_status = 'PENDING'` | 46c:485 | 整單 |
| E6 | **非商店幣別訂單**（未升級 Checkout Extensions 時） | `presentment_currency != shop.currency` AND NOT `shop.checkout_extensibility_enabled` | 46a:909 | 整單 |
| E7 | **預付型訂閱訂單**（改數量時）／經 checkout UI extension 建立的訂閱單 | `EXISTS(subscription_contracts WHERE prepaid = true)` | 46a:911–912 | 整單 |
| E8 | **只能編輯未履行品項**（最硬的一條） | `order_line_items.fulfilled_quantity = 0`；已出貨部分不可移除／改量 | 46a:910、46c:486 | **逐行** |
| E9 | **不能新增／移除／更新訂單層級折扣**；折扣碼／script／自動折扣皆不可編輯 | `order_level_discount_applications` 唯讀 | 46c:462–463 | 整單（折扣面） |

**兩條「反直覺、最容易做反」的規則**（46c:461 逐字）：
1. **品項層手動折扣：已出貨與未出貨品項「都能」管理**——E8 只鎖「移除／改量」，**不鎖品項層折扣**。把 E8 寫成「已出貨行整行唯讀」是錯的。
2. **運送方式與運費不重算、不能更改配送方式**；只能**加**自訂運費行（46c:460、46c:1070）。稅則相反：**每次編輯自動重算**（46c:464）。

**E8 必須在每一個 edit mutation 前檢查，不只在 commit 時**（46a:987 逐字「必須在每個 edit mutation 前檢查，不只在 commit 時」）——只在 commit 檢查會讓商家做完一整輪編輯才被拒絕。

**必測**：九條各自的獨立案例；「已出貨行可加品項折扣但不可改量」的組合案例；「E9 訂單層折扣唯讀但品項層可改」的組合案例；`orderEditBegin` 在 E1–E7 任一成立時回 `INVALID_STATE` 且**不建立** session。

## 本篇驗收（對照 11 §0）

雙 staff 併發 fulfill/refund 不產生超量；退款上限在惡意請求下不可突破（request spec）；restock 重放冪等；cancel 後庫存恆等式仍成立（ledger 對帳）；訂單列表 10 萬筆下 p95 <300ms（keyset 驗證）；匿名化後全文搜尋/匯出查無 PII；每個動作 timeline 都有事件且 audit 可追。

**本次新增（P0 修正對應）**：
- F5.1 公式的三個算例（F5.2）逐一斷言，**算例 3（換貨＋退貨費）必須產生 `refund=0` ＋ `balance_to_collect=58000`**；任何 float 出現在中間值即測試失敗。
- `returnCalculate` 與 `returnProcess` 對同一輸入回傳**完全相同**的金額（數字同源測試）。
- FulfillmentOrder 狀態機：(b) 的 16 條合法轉移全綠、(c) 的 8 條非法轉移全部回 `INVALID_STATE`。
- **拆單不變量**：任意 cancel/hold/move 序列後，FO 對每個 line item 的 quantity 總和 == order line item 可履行數量——**取數排除已被替代的歷史段**（等價式＝`Σ remainingQuantity ＋ Σ 非 CANCELLED fulfillment 量`，同 F3.2#2／總綱 S-14 <!-- 2026-08-17 更正（PR #52 第 13 輪）：原「Σ 所有 FO」為雙計形 -->）（property test）。
- Return 狀態機：(c) 的 7 條非法轉移全部被擋；`REQUESTED → CANCELED` 必須失敗。
- **F4.1 G3 互鎖**：存在 `REQUESTED`/`OPEN` 的 return 時 `orderCancel` 必失敗；反向亦然。
- 換貨：建立帶 `exchangeLineItems` 的 return 後，該 FO 必為 `ON_HOLD` ＋ `AWAITING_RETURN_ITEMS`，且 `fulfillmentCreate` 必失敗。
- 快照：改退貨規則後，舊訂單的 `returnCalculate` 結果**不變**（回歸測試）。

**本次新增（P1 修正對應，見 `docs/specs/54-p1-logic-fixes.md`）**：
- **稅額分攤（F5.1 X1–X6）**：含稅模式 `line_tax = 0`；未稅模式分攤原始已收稅額且**分多次退完後精確歸零**（無 1 分錢殘留）。
- **混合付款分配（F5.4）**：算例 A/B/C 逐一斷言；**禮品卡永遠第一順位**（改成可設定即為 bug）；`Σ allocation == R` 不變量。
- **發票掛鉤（F5.5）**：退款／取消／出貨三處各有一筆 `einvoice/*` outbox 事件且與業務同 transaction；發票 job 失敗不回滾退款。
- **COD 對帳（F4.4）**：金額不符不得自動回寫 paid；同一份對帳檔重覆匯入冪等。
- **OrderReturnStatus 推導（F7.1(i)）**：6 值推導表逐條；`returnReopen` 後訂單層可從 `RETURNED` 退回 `IN_PROGRESS`。
- **訂單編輯（F8）**：commit 前原訂單零變動（欄位級斷言）；`stagedStatus` 三值驅動 diff；同訂單第二個 `orderEditBegin` 回 `INVALID_STATE`；逾期 session 的 commit 被拒；E1–E9 九條 guard 各自案例＋兩條反直覺組合案例。
- **台灣七日鑑賞期（F7.4(b)）**：B2 的法定管道對 `is_final_sale` 品項**仍然出現**（與 F7.4 規則 6 的唯一例外）。
