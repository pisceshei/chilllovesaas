# 50 — 功能邏輯缺口登記簿（官方文檔 × 我方規格 逐項稽核）

> **目的**：找出「官方文檔講了、但我方規格沒寫或寫錯」的每一條業務邏輯，防止開發出錯誤功能。**寧可多報**。
> **比對來源**：`docs/research/46a`（shopify.dev 訂單/履行/退貨）、`46b`（折扣/Function/結帳擴充/Markets/B2B）、`46c`（help.shopify.com 商家側規則）、`44`（真實 Plus 後台實測，79 條行動項）。
> **被稽核對象**：`docs/research/06`（資料模型與狀態機總表）、`22`（按鈕表＋常數表）、`24`（結帳 teardown）、`28`（API 契約）、`29`（Markets）、`30`（SEO）、`42`（前台清單）、`docs/specs/11–19`、`35–39`、兩份原型 `chilllove-admin-v2.html` / `chilllove-storefront-v2.html`。
> **方法**：機械比對（抽列舉值 → grep 規格檔）。每列附檔案＋行號證據。**官方文檔沒明講的一律寫「文檔未載明」並列為需查證項，不臆測、不自補規則。**
> **稽核日**：2026-08-12。**基準事實**：`config/limits.yml` **目前不存在**（repo 尚無 `config/` 目錄）——所有「寫進 limits.yml」的結論目前皆為未落地，本簿一律以「是否寫在任一 md 規格」判定「我方是否已寫」。

---

## 表 1 · 狀態機缺口

判定基準：規格必須寫出「**全部狀態 ＋ 合法轉移 ＋ 非法轉移（guard）**」三件事才算「完整」。
我方唯一的狀態機總表在 `docs/research/06-data-model.md:86–101`（12 列）。

| # | 狀態機 | 官方狀態數 | 我方規格狀態數 | 缺哪些狀態／轉移 | 出處（官方 / 我方） |
|---|---|---|---|---|---|
| S-01 | `OrderDisplayFinancialStatus` | **8**（PENDING/AUTHORIZED/PARTIALLY_PAID/PAID/PARTIALLY_REFUNDED/REFUNDED/VOIDED/EXPIRED） | **8**（狀態齊） | **轉移圖與非法轉移全缺**：VOIDED/EXPIRED/REFUNDED 為終態（不可逆）未寫；`AUTHORIZED→PARTIALLY_PAID→PAID` 的多次部分請款路徑未寫；「誰能觸發」（`capture_payments_for_orders` 權限）未寫 | 46a:74–103 / 06:92 |
| S-02 | `OrderDisplayFulfillmentStatus` | **10**（7 現行＋3 已被取代：OPEN/PENDING_FULFILLMENT/RESTOCKED） | **5** | 缺 `PARTIALLY_FULFILLED` 以外的 **`REQUEST_DECLINED`**；缺 3 個 deprecated 值（46a 要求「不落地但 GraphQL enum 要保留並標 deprecated」）；缺「**此欄為 derived，不可直接寫入**」與「`ON_HOLD`/`SCHEDULED` 的定義是 *all* unfulfilled items」兩條關鍵語義 | 46a:105–121 / 06:93 |
| S-03 | `OrderReturnStatus`（訂單層退貨聚合） | **6**（NO_RETURN/RETURN_REQUESTED/IN_PROGRESS/INSPECTION_COMPLETE/RETURNED/RETURN_FAILED） | **0** | **整條狀態機不存在**。06 §4 無此列；16 號無；28 §4 的 orders `query` 語法未含 `return_status` 篩選 | 46a:123–134 / 06:86–101、28:74 |
| S-04 | Order 生命週期旗標（`closed`/`cancelled` 等 11 個布林） | **11 個欄位＋1 條判定式** | **1**（`open → archived / canceled`） | 06:91 把 Order 寫成**單一 `status` 欄位**，與官方「Order 沒有單一 status、由四條正交軸組成」直接衝突；`closed` 判定式「**所有 line item 已履行或已取消 AND 所有金流交易完成**」未寫；`VOIDED 不使訂單 closed` 未寫；`confirmed`/`fulfillable`/`refundable`/`restockable`/`unpaid`/`fullyPaid`/`edited` 七個衍生旗標全缺 | 46a:136–152、46a:1045 / 06:91 |
| S-05 | `FulfillmentOrderStatus` | **7**（OPEN/IN_PROGRESS/SCHEDULED/ON_HOLD/CLOSED/INCOMPLETE/CANCELLED） | **0** | **整條狀態機不存在**。06 §4 無 FulfillmentOrder 列；16-F3 只寫「建 `fulfillment_orders`、對剩餘數量條件累加」。缺全部 7 狀態、缺 `fulfillmentOrderClose → INCOMPLETE`（**不是 CLOSED**）的反直覺轉移、缺 CLOSED/CANCELLED 終態 | 46a:213–241 / 06:86–101、16:22–29 |
| S-06 | `FulfillmentOrderRequestStatus`（第二條正交軸） | **8** | **0** | 整軸缺失。缺「自營履行單 `requestStatus` 恆為 `UNSUBMITTED`」的不變量；缺 SUBMITTED/ACCEPTED/REJECTED/CANCELLATION_* 四態的 3PL 對接路徑 | 46a:243–256、46a:1044 / grep `requestStatus` 於 specs＝0 命中 |
| S-07 | `FulfillmentOrderAction`（supportedActions，12 值） | **12**（每值對應一個 mutation） | **0** | 缺整份清單。46a §2⑦-8 要求「supportedActions 做成伺服器端計算欄位、admin 按鈕啟用完全由它驅動」；我方 22 §1b 的按鈕 guard 是**前端另寫一套**（22:38），必然漂移 | 46a:258–275 / 28:80（僅提及欄位名）、22:38 |
| S-08 | `FulfillmentHoldReason` | **8** | **0** | 全缺。特別是 **`AWAITING_RETURN_ITEMS`**（換貨專用）與 `ONLINE_STORE_POST_PURCHASE_CROSS_SELL`。22:38 只寫「最多 10 個手動 hold」，未列原因 | 46a:277–290 / 22:38 |
| S-09 | `FulfillmentOrderRejectionReason` | **14** | **0** | 全缺（3PL 拒絕原因碼） | 46a:292–294 |
| S-10 | `FulfillmentStatus`（出貨單） | **6**（4 現行 SUCCESS/CANCELLED/ERROR/FAILURE ＋2 deprecated） | **0** | 06 §4 無 Fulfillment 列；16-F3 只有「建 `fulfillments`」。缺 ERROR/FAILURE 兩個 3PL 態 | 46a:383–392 / 06:86–101 |
| S-11 | `ReturnStatus` | **5**（REQUESTED/OPEN/DECLINED/CLOSED/**CANCELED**（單 L）） | **4**（requested→in_progress→inspection_complete→returned） | **我方採 help 的 4 態展示狀態，不是 API 的 5 態**（46c C-07 已標為衝突）。缺 `DECLINED`（終態）、`CANCELED`；缺 6 條不可逆／禁止轉移：①`REQUESTED→OPEN` 永久 ②`REQUESTED→DECLINED` 永久且 DECLINED 為終態 ③`REQUESTED` 不可直接取消 ④`returnCancel` 僅限「無 refund／無 disposition／無 Shopify Shipping 標籤」⑤`CLOSED→OPEN`（returnReopen）⑥移除最後一個品項自動 CLOSE | 46a:438–482、46c:1021–1033 / 06:96 |
| S-12 | `ReturnReason`（10 值，deprecated 但需支援） | **10** | **0** | 全缺。22:61 只寫「原因（依品類動態）」 | 46a:532 / 22:61 |
| S-13 | `ReturnDeclineReason` | **3**（FINAL_SALE/RETURN_PERIOD_ENDED/OTHER） | **0** | 全缺（且 `returnDeclineRequest` 的 declineReason 是**必填**） | 46a:534、46a:632 |
| S-14 | `ReverseFulfillmentOrderStatus` | **3**（OPEN/CLOSED/CANCELED） | **0** | 逆向履行單整層不存在。06 ER 圖無此實體（06:36–37 只有 ORDER→RETURN） | 46a:663–669 / 06:33–41 |
| S-15 | `ReverseFulfillmentOrderDispositionType` | **4**（RESTOCKED/NOT_RESTOCKED/MISSING/PROCESSING_REQUIRED） | **0** | 全缺。特別是「**`PROCESSING_REQUIRED` 是中間態 → disposition 可多次執行，非一次性終態**」這條資料模型含意（同一 line item 要允許多筆 disposition 紀錄取最新） | 46a:671–680 |
| S-16 | Refund（**刻意無 status**） | **0**（由底下 OrderTransaction 承載） | 我方 16-F5 寫 `transaction 列 pending → success` ✅ 方向正確 | 缺「**Refund 是不可變帳務紀錄、不建 status 欄位**」的明文禁令（46a §6⑦-31 要求寫進 schema 註釋，否則後人必加 `refunds.status`） | 46a:722–726 / 16:45 |
| S-17 | `RestockType` | **3** | **3 但值不同** | 28:90 寫 `RETURN\|CANCEL\|NO_RESTOCK`；46a:747 寫 `RESTOCK\|NO_RESTOCK\|LEGACY_RESTOCK`。**兩份互斥，必須 introspection 定案**（見表 3 T-08） | 46a:747 / 28:90 |
| S-18 | `OrderCancelReason` | **6**（CUSTOMER/PAYMENT_DECLINED/FRAUD/INVENTORY/STAFF_ERROR/OTHER） | **0**（僅寫「cancel_reason 必填 enum」） | 未列舉 6 值。46c C-02 已確認這是唯一有具體清單的來源 | 46a:830、46c:955–963 / 16:34 |
| S-19 | Order Edit（staged changes 模型） | 非狀態機，但有 **CalculatedOrder 暫存區 ＋ `stagedStatus`（ADDED/REMOVED/UNCHANGED，3 值）** | **0** | 28:70 只列 `orderEditBegin → …→ orderEditCommit`，**沒有 CalculatedOrder 暫存表、沒有 stagedStatus、沒有 OrderEditSession**。照現有規格會做成「直接改單」，無法預覽/回退 | 46a:889–903 / 28:70 |
| S-20 | `ReturnErrorCode`（狀態機違規的統一錯誤碼） | **26 值**（`INVALID_STATE` 為狀態機違規統一碼） | **0** | 28 §0.3 只寫「一開始就上 typed code enum」，未落地任何一組。46a 明言這是本次研究**唯一一份完整錯誤碼清單** | 46a:560–591 / 28:19 |
| S-21 | `DiscountStatus` | **3**（ACTIVE/EXPIRED/SCHEDULED） | **3** ✅ | 狀態齊且我方「由時間推導不落庫」的做法更佳（17:9）。缺：`asyncUsageCount` 的弱一致語義說明（我方走強一致，17-F3 已寫，但未註明「刻意與 Shopify 不同」） | 46b:206、46b:227 / 17:9、17:50 |
| S-22 | `DiscountClass` | **3**（ORDER/PRODUCT/SHIPPING） | **3** ✅ | 齊。但缺「Shopify 沒有獨立訂單折扣 mutation，商品/訂單折扣共用 Basic，靠 `customerGets.items.all` 與 `discountClasses` 區分」的建模含意 | 46b:157、46b:232–235 / 17:8 |
| S-23 | `DiscountErrorCode` | **39 值** | **0** | 全缺。46b §2⑥-7 明言「39 值全部照抄是最省事的相容性資產，直接進 28」。28 §8 無任何 discount 錯誤碼 | 46b:323–367 / 28:105–113 |
| S-24 | `buyerJourney.step`（結帳驗證三段求值） | **3**（CART_INTERACTION/CHECKOUT_INTERACTION/CHECKOUT_COMPLETION） | **0** | 15-F3 只在「提交前 server 端全量重驗」（15:48）做一次。缺三段求值 → 買家填完整張表才被擋 | 46b:417–420 / 15:48 |
| S-25 | `MarketType` / `MarketStatus` | **5 / 2** | **5 / 2** ✅ | 值齊（29:10–11）。缺：`applicationLevel`（SPECIFIED/ALL）、market type × 支援 conditions 的對應表、「同一組 regions 只能一個 active」的落地方式（29:14 有寫「應用層驗證」） | 46b:668–688 / 29:10–14 |
| S-26 | `PaymentTermsType`（B2B 付款條件） | **5**（FIXED/FULFILLMENT/NET/RECEIPT/UNKNOWN） | **0** | 22:52 只寫「帳期（收貨即付/出貨後/Net 7–90/固定日）」為 P2，未列 enum；**專案無 B2B 規格檔** | 46b:881–889 / 22:52 |
| S-27 | B2B 訂單審核流（`checkoutToDraft` → draft order） | 三態付款結果（無 terms→立即付款／NET→`payment_pending`／NET+deposit→`partially_paid`） | **0** | 44:826 實測到 `訂單提交` radio 兩態；46b:860–868 給完整三態。我方 06:94 的 `DraftOrder: open → invoice_sent → completed` 無 B2B 分支 | 46b:850–868、44:826 / 06:94 |
| S-28 | Checkout | `active → completed / abandoned` | **3** ✅ | 齊（06:95）。但缺 46b §3 的 validation gate 對 Accelerated Checkout 也生效這條（見表 2 H-31） | 46b:394 / 06:95 |
| S-29 | 商店生命週期（12 態）／KYC／爭議／催繳／事故／維護 | 我方自訂，非 Shopify | 12 / 5 bucket / 5 / — / 4 / 5 ✅ | **無缺口**：36:675–770（12 態轉移表＋副作用矩陣）、36:1752（KycRejectCode 8 值）、37:986（dispute 5 態）、37:1245（狀態機唯一入口）、39:180（事故/維護 enum）。這幾條是全專案寫得最完整的狀態機 | — / 36、37、39 |
| S-30 | 帳單發票 7 態（44 §19.4 實測 tabs） | **7**（全部/已付款/未付款/付款失敗/處理中/已退款/已取消） | 我方 37 有催繳狀態機，但**發票 7 態未落地** | 44:551 實測；37 的 `invoices` 未見 7 態 enum | 44:551 / 37 |

**表 1 缺口數：`26`**（S-01～S-20、S-23～S-24、S-26～S-27、S-30 有缺；S-21/S-22/S-25/S-28/S-29 判定為齊或僅次要缺漏——其中 S-21/S-22/S-25 各有 1 條次要缺漏，若併計則為 **29**）。
**完全不存在的狀態機：10 條**（S-03、S-05、S-06、S-07、S-08、S-09、S-10、S-14、S-15、S-23）。

---

## 表 2 · 硬性約束缺口

「硬性約束」＝官方文檔中所有「必須／不可／上限／預設值／公式」。**我方是否已寫**欄：✅＝有且可實作；⚠️＝有但不完整或位置不對（不在 spec/limits）；❌＝完全沒有。

### 2A · 訂單／履行／退貨／退款（46a）

| # | 規則 | 官方出處 | 我方是否已寫 | 寫在哪 | 缺口 |
|---|---|---|---|---|---|
| H-01 | `refundCreate` 自 API **2026-04 起強制** `@idempotent(key:)`，缺 key 執行期報錯 | 46a:781–787（S49） | ⚠️ | 28:32–33「訂單成立/退款/庫存調整必填」 | 缺「強制版本」「缺 key 的錯誤行為」「受影響的 17 個 mutation 名單」 |
| H-02 | 冪等 key **保留期 24 小時**，逾期重試視為新操作 | 46a:789、46a:1006 | ❌ | — | `idempotency.ttl_hours: 24` 未寫在任何 spec（`config/limits.yml` 不存在） |
| H-03 | 冪等回放**由當前 DB 狀態重建回應，非原始快照** | 46a:791、46a:1009 | ❌ **且我方寫反** | 11:45–48 的 `with_idempotency` 存 `response_body` 並原樣回放 | 與官方語義相反；46a §6⑦-30 要求照做重建 |
| H-04 | 冪等錯誤碼 `IDEMPOTENCY_CONCURRENT_REQUEST`（退避後用同一把 key 重試）／`IDEMPOTENCY_KEY_PARAMETER_MISMATCH` | 46a:763–764、46a:1010–1011 | ❌ | — | 兩碼皆無；28 §0.3 的 code enum 未列 |
| H-05 | **輸入欄位順序影響參數指紋** → 必須排序後再 hash | 46a:793、46a:816 | ❌ | — | 未寫；不做會誤判 mismatch |
| H-06 | Bulk 操作**每個 JSONL row 一把獨立 key，絕不共用** | 46a:1015 | ❌ | 28:30 只寫 bulk 契約保留 | — |
| H-07 | 退款公式 `refund = 退貨品項價值 − 退貨相關費用 − 換貨扣抵`，且 **floor 到 0**（不得為負） | 46a:595–601（S50，2024-07 變更）、46a:1042 | ❌ | 16:44 只有「行單價×數量 −（折扣分攤×退貨比例）− 稅按比例」 | **缺退貨費用扣減、缺換貨扣抵、缺 floor 0** → 有換貨時金額必錯 |
| H-08 | Restocking fee ＝**百分比**（`percentage: Float!` 必填），**per line item**，同一張退貨不同品項可不同% | 46a:526、46a:608 | ❌ | — | 16 完全無退貨費用欄位；22:61 只寫「restocking fee 與退貨運費按規則帶入」 |
| H-09 | Return shipping fee ＝**固定金額**（`amount: MoneyInput!` 必填），**per return**，且**必須是 presentment 幣別** | 46a:528、46a:610 | ❌ | — | 同上。46a §4⑦-17 明列 `restocking_fee_percentage` ＋ `return_shipping_fee_cents` 兩欄 |
| H-10 | `returnReasonNote` 上限 **255 字元** | 46a:523、46a:653 | ❌ | — | 未寫 |
| H-11 | `orderCancel.staffNote` 上限 **255 字元**，買家不可見 | 46a:848、46a:880 | ❌ | — | 未寫 |
| H-12 | `orderCancel` 的 `reason` 與 `restock` **皆為 non-null 必填** | 46a:846、46a:851 | ⚠️ | 16:34「cancel_reason 必填 enum」 | `restock` 必填未寫；且 28:69 的簽名 `orderCancel(reason, refund: Boolean, restock: Boolean, notifyCustomer)` **多出官方不存在的 `refund` 參數、少了 `staffNote`/`refundMethod`** |
| H-13 | `orderCancel` 是**非同步**，回傳 `job{id, done}` 需輪詢 | 46a:865、46a:877 | ❌ | 28:69 為同步簽名 | 同步做「取消＋退款＋回補庫存＋關閉所有 FO」會逾時 |
| H-14 | **停用地點 ＋ 已付款 ＋ `restock:true` → orderCancel 失敗**；未付款則成功但庫存不回補 | 46a:853、46a:1041 | ❌ | — | 未寫 |
| H-15 | 不可取消四條件：已取消／**有待處理付款授權**／**有進行中的退貨**／有無法履行的未結出貨 | 46a:832–838、46a:1028–1030 | ⚠️ | 16:38「已部分出貨的單不能整單 cancel」 | **「有 active return 不可取消」完全沒有**（三方唯一來源是 dev，見 46c C-01） |
| H-16 | `fulfillmentOrderCancel` = 「取消 **並產生一張替代 FulfillmentOrder 承接剩餘工作**」 | 46a:236、46a:240、46a:354 | ❌ | — | 未寫 → 剩餘品項會憑空消失 |
| H-17 | `fulfillmentOrderHold`（部分品項）／`fulfillmentOrderMove` 會回傳 **`remainingFulfillmentOrder`**（自動拆出新單） | 46a:358–360、46a:366 | ❌ | 28:80 僅列 `fulfillmentOrderHold/ReleaseHold/Move/Split` 名稱 | 拆單語義未寫 |
| H-18 | 每張 FulfillmentOrder 最多 **10 個 active hold**，超過回 user error | 46a:320、46a:374 | ⚠️ | 22:38「最多 10 個手動 hold」、22:160 常數表 | 有數字但未進 spec 的 guard，且 `config/limits.yml` 不存在 |
| H-19 | `fulfillmentCreate` 的多張 FulfillmentOrder 必須**同一 order ＋ 同一 location** | 46a:400、46a:1038 | ❌ | 16:22–29 | 未寫；跨地點須分多次呼叫 |
| H-20 | `FulfillmentInput.originAddress.countryCode` 為**必填子欄位** | 46a:403 | ❌ | 28:81 | 未寫 |
| H-21 | 退貨來源是 **fulfillment line item（不是 order line item）**，且前提「fulfillment 已 **delivered**」 | 46a:519、46a:627、46a:648、46a:1034 | ❌ | 06:37 只有 `ORDER \|\|--o{ RETURN` | **schema 級錯誤**：`return_line_items` 外鍵必須指向 `fulfillment_line_items` |
| H-22 | 換貨會建立 **`ON_HOLD` ＋ `AWAITING_RETURN_ITEMS`** 的 FulfillmentOrder，退貨到貨前不得出貨 | 46a:554、46a:651、46a:1039 | ❌ | 22:61 只寫「Exchange 加購（算差額；不能自訂品項）」 | 未寫 → 換貨品會先出貨 |
| H-23 | 退貨取消**不影響**已釋出的換貨品項 | 46a:478、46a:1040 | ❌ | — | 未寫 |
| H-24 | `returnCancel` 前置：僅 `OPEN`；**不得**有已取消 fulfillment／已發生 refund／已做 disposition／Shopify Shipping 標籤（手動上傳標籤可） | 46a:472–476、46a:1031 | ❌ | — | 未寫 |
| H-25 | 建立/申請退貨會**自動解除訂單封存** | 46a:482、46a:1036 | ❌ | 16:35（archive 純標記） | 未寫（help 也沒寫，46c C-06） |
| H-26 | `returnCalculate` 必須與 `returnProcess` **共用同一份計算程式碼**（數字同源） | 46a:628、46a:655 | ❌ | 15:20「一處實作、四處重用」有精神但未含 return | `returnCalculate` 在 28 中不存在 |
| H-27 | 關稅退款兩模式：`PROPORTIONAL`（須同時傳 refund line items）／`FULL` | 46a:612–615 | ❌（M4 刻意不做） | 46a §6⑦-33 建議 M4 不做、schema 預留 | 未在任何 spec 標「刻意不做」 |
| H-28 | 「只能編輯**未履行**品項」是最硬的 guard，須在**每個 edit mutation 前**檢查（不只 commit 時） | 46a:910、46a:987、46a:1035 | ⚠️ | 22:33「已出貨項不可移除」 | 只寫在按鈕表，未寫「每個 mutation 前都要檢查」 |
| H-29 | `orderEditAddVariant.allowDuplicates` 預設 **false**；`orderEditSetQuantity.restock` 預設 **false** | 46a:924、46a:929、46a:991 | ❌ | — | 預設值選錯會造成庫存錯亂 |
| H-30 | `orderEditAddVariant` 套用 **contextual pricing**（依市場/幣別情境定價），不是 variant 預設價 | 46a:927 | ❌ | — | 未寫 |
| H-31 | `orderEditUpdateShippingLine` **只能改新加入的** shipping line | 46a:933、46a:1043 | ❌ | 28:70 完全沒有 shipping line 三個 mutation | 見表 4 R-13 |
| H-32 | 訂單編輯**每次 mutation 即時重算稅與總額**（CalculatedOrder） | 46a:902、46a:953 | ❌ | — | 未寫 |
| H-33 | 訂單編輯 session：**Shopify 文檔未載明**鎖/TTL/並發行為 → 我方須自訂（單一 open session unique index、TTL 24h） | 46a:961、46a:988–989、46a:1061 | ❌ | — | **需查證項已由 46a 明確標示；我方仍未做決策落地** |
| H-34 | `maximumRefundable` 公式**文檔未載明** → 我方須自定並標註 | 46a:606、46a:770、46a:819、46a:1053 | ⚠️ | 16:44「累計退款 ≤ 實收」；28:89 提到 `maximumRefundable` | 我方定義未標「Shopify 未公開、本專案決策」；且與 help 的「超額退款允許」衝突（見表 3 T-03） |
| H-35 | `refundMethods` 支援退回原付款方式或 **store credit（商店購物金）** | 46a:743、46a:774 | ❌ | 22:35 提到「店內額度」為 cancel 對話框選項 | `store_credit_accounts` 表在 06 §7 缺（原型已標 `[tbl:store_credit_accounts]（06 §7 待補）`） |
| H-36 | restock 與退款**解耦**：`restockType` 是 per line item 選項，退款不一定補庫存 | 46a:775 | ✅ | 16:43「restock 勾選（預設勾）」、28:90 | 齊 |
| H-37 | `returnProcess` 的冪等**文檔未載明** → 我方必須自行強制 idempotencyKey | 46a:620、46a:654、46a:1062 | ❌ | — | `returnProcess` 在 28 中完全不存在 |
| H-38 | `returnRefund` **已 deprecated**；有退貨脈絡走 `returnProcess`、無脈絡走 `refundCreate` | 46a:642、46a:806–809 | ❌ **且我方寫錯** | 28:91 仍把 `returnRefund` 列為現行 mutation | 見表 4 R-11 |

### 2B · 折扣／Function／結帳擴充／Markets／B2B（46b）

| # | 規則 | 官方出處 | 我方是否已寫 | 寫在哪 | 缺口 |
|---|---|---|---|---|---|
| H-39 | 結帳 Function **7 步執行順序**（Cart Transform → 商品/訂單折扣 → 履行約束+路由 → 配送客製 → **運費折扣** → 付款客製 → 驗證） | 46b:38–50、46b:134 | ⚠️ | 17:18「product → order → shipping」 | **缺「運費折扣在配送選項生成之後」這一層**（第 4 步產生選項、第 5 步才折運費）→「滿額免運」跨階段規則會算錯 |
| H-40 | **多個訂單級百分比折扣以「原始 subtotal」為基數相加**（10%+20% = 30%，非複利 28%） | 46b:284、46c:720 | ❌ **且我方寫反** | 17:42「百分比疊加不是相加（20%+10% = 72 折不是 7 折）——pipeline 序列計算天然正確」 | **直接矛盾**：官方三方一致為「都按原始小計」。22:105 反而寫對了。17 必須改 |
| H-41 | **運費折扣不可疊運費折扣**（硬規則，非 combinesWith 旗標可控） | 46b:285、46b:374、46c:716 | ⚠️ | 22:105「shipping 不互疊」 | **只寫在按鈕表**；17-F1 的資料模型（17:8）是 `combines_with JSON {product,order,shipping}` 三旗標對稱，若照 17 實作即可疊兩張運費折扣。須把硬規則寫進 17-F2 的組合裁決 |
| H-42 | 免運折扣的 `combinesWith` **只有 order/product 兩個旗標**（無 shippingDiscounts） | 46b:197 | ❌ | 17:8 三旗標一律套用 | 未寫；會允許非法組合 |
| H-43 | 折扣 `percentage` 值域為 **0–1 Float**（不是 0–100） | 46b:189、46b:272 | ❌ | 17:8「value_type: percentage/fixed；value」 | 值域與序列化規則未定義（46b §2⑥-2 建議存 basis points、序列化除 10000）→ 100 倍誤差風險 |
| H-44 | 同時 active 自動折扣上限 **25**（`ACTIVE_PERIOD_OVERLAP`） | 46b:264 | ✅ | 22:102、22:160 | 齊（但未進 limits.yml） |
| H-45 | 每店累計唯一折扣碼 **20,000,000**；單一折扣碼可指定顧客/商品/變體 **100** | 46b:265–266 | ✅ | 22:102–103、22:160 | 齊 |
| H-46 | 顧客單次結帳可用 **5 個商品/訂單折扣碼 ＋ 1 個運費碼** | 46b:267 | ⚠️ | 22:105 | 22 有寫，但 17-F2「輸入的 code（單一 code 起步；多 code P1）」（17:18）沒對齊 |
| H-47 | tags 上限 **5**、tag 長度 **255**、Plus 的 `productDiscountsWithTagsOnSameCartLine` tags **10** | 46b:268–270 | ❌ | — | 折扣 tags 概念在 17 完全不存在 |
| H-48 | `customerSelection` **已 deprecated**（2025-10），改用 `context{customerSegments \| markets}`；**markets 與 customerSegments 互斥** | 46b:248–257、46b:375 | ❌ **且我方寫錯** | 28:113 的 discount input 仍列 `customerSelection`；無 `context` | 且缺 XOR 檢查 |
| H-49 | 自動折扣可指定客群 **≤5**、折扣碼 **≤100** | 46c:690–691 | ✅ | 22:104 | 齊 |
| H-50 | Function 折扣執行語義：所有 discount function **並行執行、互不知道彼此**，疊加由 discount node 的組合規則決定 | 46b:321 | ❌ | — | 未寫 |
| H-51 | `summary`／`shortSummary` 是**系統產生**的人話描述（需一個折扣描述產生器） | 46b:222、46b:378 | ❌ | — | 未寫（46b 標為「容易漏做的一塊」） |
| H-52 | Function 各類每店上限 **25**（discount／validation／delivery customization／payment customization）；Cart Transform **每 app 每店 1**；Discounts Allocator **每店 1** | 46b:99–104、46b:964–969 | ❌ | — | 全缺 |
| H-53 | Function 資源限制：binary 256 kB／linear memory 10,000 kB／stack 512 kB／log 1 kB／11M instructions／input 128 kB／output 20 kB／input query 3000 bytes／metafield 10,000 bytes／list arg 100／query cost 30 | 46b:69–94、46b:953–963 | ❌ | — | 全缺。46b §1⑥-2 建議換算成 **cart line ≤200 ＋ pipeline 時間上限 ＋ 輸出 20 kB** 三條等價護欄 |
| H-54 | Checkout validation 的 **25 條 JSONPath target 白名單**（含 2026-04 新增的 `billingAddress.*` 與 `$.cart.poNumber`） | 46b:422–452、46b:483 | ❌ | — | 全缺 |
| H-55 | 買家端驗證錯誤碼固定為 **`VALIDATION_CUSTOM`**（Storefront `Cart.userErrors.code`） | 46b:412、46b:477 | ❌ | — | 未寫 |
| H-56 | Validation 在 **Accelerated Checkout（Shop Pay/Apple Pay）也生效** → 快速結帳必須走同一伺服器端管線 | 46b:392–394、46b:485 | ❌ | 15:48 只在提交前重驗 | 未寫（46b 標為「最容易漏的安全洞」） |
| H-57 | Checkout UI Extensions：bundle **64 KB**／同一 block 位置 **3 個擴充**／`settings` **20 個**／block placements **14**（字串未載明）／31 個 target 字串 | 46b:591–594、46b:512–583 | ❌ | 24:146–160 有 theme 側限制，無 checkout extension 側 | 全缺；44:712 實測「編輯器無內建 block 庫，全部由 app extension 提供」也未落地 |
| H-58 | 擴充**唯一寫入口是 `applyAttributeChange`／`applyMetafieldChange`**；改價必須走 Function | 46b:508、46b:622 | ❌ | — | 未寫（安全紅線） |
| H-59 | Market 繼承：**用 null 表達繼承**，無 `inherited` 旗標、Market 物件**無 parentMarketId 欄位**（父子由 conditions 自動推導） | 46b:659–664、46b:717、46b:792–793 | ⚠️ **與我方衝突** | 29:42 存 `parent_market_id`；29:12「子市場繼承父市場自訂」 | 見表 3 T-05 |
| H-60 | 繼承語義：`catalogs`／`webPresences` **累加**；`currencySettings`／`priceInclusions` **覆寫**；`delivery.shipping` null=繼承 | 46b:650–664 | ⚠️ | 29:12「同類型自訂合併，catalogs 與 web presences 累加，其餘覆寫」 | 有寫但缺 `priceInclusions`／`shipping` 兩項與 merge 策略的實作規格 |
| H-61 | 市場命中優先序 **Company Location > Retail Location > Region > Store Default** | 46b:641–648、46b:795 | ❌ | 29:12「取最特定者」 | 四層順序未列 |
| H-62 | wildcard 市場每店 **100**；**同一組 regions 只能一個 active** | 46b:746–747 | ✅ | 29:14 | 齊 |
| H-63 | 市場 catalog 排除的商品「**前台隱藏、搜尋不出現、不可加車**」三件事 | 46b:754 | ✅ | 29:38 | 齊 |
| H-64 | B2B：catalog／payment terms／tax／checkout 設定／currency／地址 **一律掛 company_location**，company 層只有 name/note/default_role/main_contact | 46b:817–830、46b:936、44:830 | ❌ | **專案無 B2B 規格檔** | 44 行動項 71 說「我們 B2B 規格原本掛在 company 上——要改」，但實際上不存在該規格 |
| H-65 | B2B 上限：10,000 locations/company、10,000 contacts/company、**50 contacts/location**、25 catalogs/location、250 prices/request、**1 company/customer** | 46b:898–904、46b:984–989 | ❌ | 29:37 只有 `priceListFixedPricesAdd` ≤250 | 其餘全缺 |
| H-66 | B2B 多 catalog 解析取 **最低價**，且商品須至少發佈到一個 applicable publication 才可見 | 46b:910–911、46b:940 | ❌ | — | 未寫 |
| H-67 | `CompanyLocation.market` **已 deprecated** → 不得建 location→market 正向外鍵 | 46b:830、46b:943 | ❌ | — | 未寫 |
| H-68 | Company contact **不是獨立帳號**，掛在 retail customer 上 | 46b:815 | ❌ | — | 未寫（決定 customers 表設計） |

### 2C · 商家側規則（46c）與實測（44）

| # | 規則 | 官方出處 | 我方是否已寫 | 寫在哪 | 缺口 |
|---|---|---|---|---|---|
| H-69 | **退貨與取消規則綁購買時點快照**——改規則只適用未來訂單，不追溯 | 46c:422–426（H13/H14 逐字）、44:437 | ❌ | 44:437 有結論（`order_line_items.return_policy_snapshot_id`）但**未進任何 spec** | 16／13／28 全無 |
| H-70 | 退貨與取消規則**可有多條**（預設規則 ＋ N 條），且可按市場切換 | 44:422、44:854、44:865 | ❌ | — | 22:62 只寫單一 Return rules |
| H-71 | 退貨規則兩個獨立 toggle：**退貨規則管已履行品項／取消規則管未出貨品項**；同一訂單可並存 → 前台「申請」按鈕**逐 line item 判斷** | 44:431、46c:85–86、46c:1195 | ❌ | — | 未寫；42 §12 前台清單也沒有 |
| H-72 | **最終銷售品項**以 collection 或 product 為粒度；命中即**前台完全不出現申請入口**（不是提交後被拒）；**bundles 不可設為最終銷售** | 46c:427–432、44:433、44:439 | ❌ | — | 未寫 |
| H-73 | 退貨期間選項 **14/30/90/不限/自訂**；起算點＝個別品項配送日 **或** 訂單最後一項配送日 | 46c:415–416 | ⚠️ | 22:62「14/30/90/自訂，自送達起算」 | 缺「不限」、缺「訂單最後一項配送日」這個起算點選項 |
| H-74 | 退貨運費三選一（免費／每次固定／顧客自購標籤）；重新上架費為**退貨金額百分比**；兩者**單筆可覆寫**（規則是預設值不是硬約束） | 46c:417–419、46c:436–437 | ⚠️ | 22:61「按規則帶入（可逐單改）」 | 三選一與百分比制未寫 |
| H-75 | 退貨單三選項：①在 Shopify 建立退貨單（**僅限美國地點**）②上傳既有標籤（PDF/PNG/JPEG＋追蹤號＋業者）③不需運送 | 46c:297 | ⚠️ | 22:61「平台標籤/上傳標籤/無需寄回」 | 有寫，缺「僅限美國」的地區限制 |
| H-76 | 建立退貨當下**庫存不變**，品項標記「待收退貨品項」；處理時才選重新入庫地點 | 46c:296、46c:330 | ❌ | 13-F5 只有 available/committed 兩欄 | 「待收退貨」佔位無處可存 |
| H-77 | **換貨品項的庫存在「處理退貨」之前完全不保留** | 46c:299 | ❌ | — | 未寫；且與 H-22（換貨產生 ON_HOLD FO）表面衝突，見表 3 T-02 |
| H-78 | 換貨差價三情境（新品便宜→退差／新品貴→**收差額**／等值→抵銷）；**訂單層折扣不能套用到換貨品項，但可加商品折扣** | 46c:351–358 | ❌ | 22:61「Exchange 加購（算差額）」 | 訂單層折扣禁令未寫 |
| H-79 | 含關稅（duties）的訂單**可退貨、不可換貨**；自訂品項不可作為換貨品項 | 46c:314–315 | ❌ | 22:61「不能自訂品項」✅ 一半 | 關稅禁換貨未寫 |
| H-80 | 自助退貨：**不支援舊版顧客帳號**；單次上限 **250 品項**；**不支援換貨**；「取消要求本身不會改變訂單狀態」（純申請語義） | 46c:375–384、46c:394–396 | ⚠️ | 22:149「自助退貨」列為 P1 | 四條規則全缺 |
| H-81 | 退款**一經發起絕對不可撤銷**（三方一致） | 46c:228、46c:1143 | ❌ | 16-F5 無此聲明 | UI 二次確認未列入規格 |
| H-82 | 退款頁可**直接對商品項目套用折扣**；數量設 0 的品項不退款；退運費**不得超過可退運費**；**訂單層級免運折扣 → 完全不可退運費** | 46c:218–221、46c:238 | ⚠️ | 22:32「退運費（上限=原收；免運單不可退運費）」 | 「退款頁可加折扣」與「數量 0 不退」未寫 |
| H-83 | **混合付款時，退款先套用到禮品卡直到禮品卡可退全額，餘額才走其他付款方式** | 46c:221 | ❌ | — | 未寫 → 退款分配順序會錯 |
| H-84 | **超額退款允許**：先發過商店抵用金者可對原付款方式 over-refund | 46c:223、46c:241 | ❌ **且我方硬擋** | 16:44「累計退款 ≤ 實收（DB CHECK 級測試）」 | DB CHECK 會擋掉合法情境，見表 3 T-03 |
| H-85 | 顧客原付款方式失效時**退款仍送出**，由顧客自行聯絡銀行 | 46c:240 | ❌ | 15:62 只有 Stripe refund pending | 未寫 |
| H-86 | 商店抵用金：需**新版顧客帳號**；單一顧客累計 **< 15,000 美元**；**最早到期的先用**；到期以**商店時區當日結束**為準；草稿單/已編輯訂單/第三方管道不支援；訂閱僅首購可用；幣別須與結帳幣別相符 | 46c:253–277 | ❌ | — | 全缺；`store_credit_accounts` 表也未建（原型標「06 §7 待補」） |
| H-87 | 刪除訂單前置：**必須先封存或取消**；且**只有 5 類訂單可刪**（測試單／手動付款單／標記已付的草稿單／API 匯入單／草稿單） | 46c:181–189 | ❌ | 22 未列刪除訂單 | 全缺（最高危動作） |
| H-88 | 批次取消**一次最多 250 筆** | 46c:149 | ⚠️ | 22:12「>50 筆改寄 email」、28:21「陣列型 input 上限 250」 | 通用 250 有寫，訂單批次取消專屬上限未寫 |
| H-89 | 自動封存條件二選一：**「已付款且已出貨」或「已全額退款」** | 46c:165、46c:572 | ⚠️ | 16:35「付清且已出貨 N 天後」 | 缺「已全額退款」這一條，且我方多了「N 天後」（官方無延遲） |
| H-90 | 編輯訂單：**不能新增/移除/更新訂單層級折扣**；折扣碼/script/自動折扣不可編輯；**可對已出貨與未出貨品項都管理品項層折扣** | 46c:462–463 | ⚠️ | 22:33「不能改訂單層折扣」 | 缺「已出貨品項也能管折扣」這條反直覺規則 |
| H-91 | 編輯訂單：**運送方式與運費不重算、不能更改配送方式**；只能加自訂運費 | 46c:460、46c:1070 | ✅ | 22:33「運費不重算」 | 齊 |
| H-92 | 編輯訂單補款的結帳**沒有加速結帳**（Shop Pay/Apple Pay 不可用） | 46c:470 | ❌ | — | 未寫 |
| H-93 | **在訂單成立日之後編輯 → 該編輯在報表中顯示為一筆獨立訂單**（污染 Orders over time／Sales over time／AOV） | 46c:477 | ❌ | 19 §F1 指標辭典無此口徑 | 未寫 → 報表數字會與本尊對不上 |
| H-94 | 不可編輯的訂單（help 側）：匯入單／**Shop Pay 分期單**／**當地配送單**／待處理付款單／含已出貨品項的部分 | 46c:482–486 | ⚠️ | 22:33「分期付款單不可編輯」 | 匯入單／當地配送單／待付款單三條缺；且 dev 側另有 4 條（46c C-09），聯集未做 |
| H-95 | 請款**四模式**：結帳自動／履行後自動／**每次履行時自動（Plus 專屬）**／手動 | 46c:508–514 | ❌ **且我方明文寫錯** | 22:147、22:157 明文「請款三模式…修正：官方現行三模式」 | **22 的「修正」本身是錯的**，help 2026-08 實抓為四模式 |
| H-96 | 授權效期表：Shopify Payments 預設 **7 天**；Plus 延長 Visa/MC/Amex **30 天**、Discover/JCB **10 天**、Diners/CUP **7 天**；未請款 pending hold 最長顯示 30 天 | 46c:517–525 | ⚠️ | 22:40「授權期 7 天（到期前 2 天示警）」 | 缺方案差異表；「到期前 2 天示警」對應 46c:536 的「即將到期 badge」✅ |
| H-97 | **逾授權期限後請款需付 1.75% 附加費** | 46c:526 | ❌ | — | 未寫 |
| H-98 | 支援**部分請款**；支援金流商或 Plus 可**多次部分請款** | 46c:527 | ⚠️ | 22:40「可部分 capture（可多次，依供應商）」 | 齊 |
| H-99 | 訂單草稿保留庫存 → 進 **`Unavailable`** 狀態（**不是 Committed**）；草稿單位在轉正式訂單前不計入 Committed | 46c:546–549、46c:895 | ⚠️ | 22:49「庫存轉 Unavailable」 | **13-F5 只有 available/committed 兩欄（13:59）→ 無處可存** |
| H-100 | 2025-04-01 後建立的訂單草稿，**閒置 1 年自動刪除** | 46c:552 | ❌ | — | 未寫 |
| H-101 | 庫存頂層五態 `現有/可販售/已分配/不可販售/待入庫`；**不可販售**底下四子分類 `損壞/品質控管/安全庫存/其他`；**待入庫不計入現有** | 46c:891–907、46c:925–927 | ⚠️ | 06:111 恆等式有 `unavailable(damaged/safety/qc/reserved)`；44:150 實測四欄 | **13-F5 的資料模型（13:59）只有兩欄**，與 06 恆等式對不上 → 對帳 job 必然告警 |
| H-102 | 庫存編輯連動：編輯**現有** → 可販售等量變動；編輯**可販售** → 現有等量變動 | 46c:594–595、46c:909–911 | ❌ | — | 未寫 |
| H-103 | 庫存調整**原因七項**（更正〔預設〕/盤點/已收件/退貨重新入庫/損壞/遭竊或遺失/促銷或捐贈） | 46c:608–617 | ⚠️ | 22:81「原因 7 種」、28:63「reason 枚舉（correction/received/sold/returned/damaged…）」 | **未列舉完整七項且兩處清單不同**（28 有 `sold`，46c 無） |
| H-104 | 調整記錄事件型別（手動 7 種 ＋ 系統 6 種 ＋ 狀態間移動如「移至安全庫存」） | 46c:620–622 | ❌ | 22:81「調整歷史（180 天）」 | 事件型別全缺 |
| H-105 | 商品：**≤3 選項／≤2,048 子類／≤250 媒體**；子類每日上傳速率（>500,000 子類的店每日 10,000，**Plus 豁免**） | 46c:657–669 | ⚠️ | 22:70、22:74、22:160 | 前三條齊；**每日上傳速率限制未寫** |
| H-106 | 結帳表單欄位三態（不顯示/選填/必填）；**「要求登入」⇒ 強制 email 通道**（兩欄位聯動）；SMS 行銷同意**永不可預先勾選**；email 同意可**依地區自動預勾** | 46c:756–768、44:369–371 | ⚠️ | 22:148、24:219 | 24 有完整表；**15/19 號 spec 無 `checkout_field_config` 模型與聯動規則** |
| H-107 | 棄單信延遲 **1/6/10/24 小時，預設 10 小時（建議）**；對象二選一（任何未完成者／email 訂閱者）；**留 email 10 分鐘未完成＝棄單** | 44:373、24:228 | ⚠️ **且我方衝突** | 24:228 有；**15:94 寫「active 超過 1 小時」、22:60 寫「≥10 分鐘」** | 三處門檻不一；四檔延遲未進 15 號 spec |
| H-108 | 加入購物車數量上限（`cart_item_limit`），系統建議值 **50**；例外 POS/draft/B2B/不追蹤庫存 | 44:378、24:230 | ⚠️ **且我方衝突** | 24:230；**15:9 寫「每行 999、行數 100」** | 概念不同（總件數上限 vs 行數上限），且未對齊 |
| H-109 | 地點配額：Basic~Advanced **10** / Plus **200**（app 地點不佔），且**頁面要顯示「已用 N / 配額 M」** | 44:400、46c 未載 | ✅ | 22:152、22:160 | 齊（未進 limits.yml） |
| H-110 | 運送設定檔：一般 1 ＋ 自訂 **≤99**；**預設設定檔的商品集合是「補集」**（未包含於其他設定檔的所有商品） | 46c:863、44:513 | ⚠️ | 22:150「General 1 + Custom ≤99」 | 「補集」語義未寫 |
| H-111 | **合併運費規則**：費率**名稱相同 → 相加**；**名稱全不同 → 取最便宜相加**；同一 location group 多地點只收一次；重量制逐品項加包裹重量再相加 | 46c:869–876 | ⚠️ | 22:150「跨方案購物車運費相加」 | **「名稱是合併鍵」這條完全沒寫** → 運費會算錯 |
| H-112 | **zone ≠ market**：建了運送區域仍須把國家加進 Markets 才能賣 | 44:525、44:622 | ❌ | — | 跨模組硬約束未寫（29 與 15 都沒有） |
| H-113 | **稅務地區不是自己建的，是「有運送區域才會出現」**（shipping zone 是稅區上游依賴）；稅務服務三檔 managed/basic/manual | 44:385–388 | ❌ | 22:151、28:149 | 未寫 |
| H-114 | 海關資訊（HS code／原產地）以**商品子類 taxonomy 批次設定**（13,356 子類），不是逐商品填 | 44:391–392 | ❌ | 28:60 只有 per-item `inventoryItemUpdate` | 未寫 |
| H-115 | **數位商品 VAT 由一個特殊 collection 驅動** | 44:396 | ❌ | — | 未寫 |
| H-116 | 通知範本 **45+ 個／12 分組**，且**只有部分可關閉**（當地配送/運送狀態更新/雙重確認/Shop 再行銷），交易性範本**強制寄** | 44:452–469 | ❌ | 22:153「模板分類+個別開關」；18-F2 未列範本清單 | **`toggleable` 欄位與 45 範本清單全缺** → 會做成全部可關（合規風險） |
| H-117 | Webhook 支援 **XML 與 JSON 兩種格式**，且歸在「通知」IA 下 | 44:447 | ❌ | 28:183 `format: JSON` 單一 | 未寫 |
| H-118 | 顧客帳號為**平台託管的獨立 SPA**（`shopify.com/{shop_id}/account`），網域與商店主網域**分離**；session 最長 **365 天**；**每市場自訂網域不支援**；**Multipass 不支援** | 46c:796–800、44:414–415、44:368 | ⚠️ | 22:149「新版（OTP、託管頁、365 天 session）」 | 網域分離、每市場網域不支援、Multipass 不支援三條缺；42 前台把帳戶做成主題頁（44:415 已標為待決架構抉擇，**未決**） |
| H-119 | 升級新版顧客帳號**可在 30 天內還原，超過即不可逆**；升級後會壞掉的 6 項（主題硬連結／自訂登入頁／Flow workflow／`customer_account_status` 分群／Multipass／每市場網域） | 46c:807–819 | ❌ | — | 全缺 |
| H-120 | 結帳設定檔是**可多份、可切換**的實體（active badge ＋ 上次儲存時間），並可按市場切換 | 44:367、44:864 | ⚠️ | 28:151 有 `checkoutProfileCreate/Duplicate/Delete` | 「按市場切換」未寫（且 46b:783 指出公開 API 無此欄位，見表 3 T-07） |
| H-121 | 折扣組合的**額外資格條件**：需 Checkout Extensibility（無 `checkout.liquid` 客製）**且未安裝 Licensify app** | 46b:289、46c:704、46c:1118–1121 | ❌ | — | 未寫 |
| H-122 | 折扣**組合不會自動發生**——商家必須逐折扣開啟組合設定 | 46c:705 | ⚠️ | 17:8 `combines_with` 預設值未定義 | 預設值未寫（應為全 false） |
| H-123 | 顧客輸入互斥代碼時「**一律套用對顧客購物車最有利的折扣**」 | 46c:722 | ✅ | 17:20「取買家利益最大組合（best discount wins）」 | 齊 |
| H-124 | 折扣組合功能**僅適用網路商店、Storefront API 與 POS**（其他通路不支援） | 46c:724 | ❌ | — | 未寫 |
| H-125 | 政策頁有第三態 **`● 自動`（系統生成）** | 44:424 | ❌ | 22:153 只有「填/不填」兩態 | 未寫 |
| H-126 | 密碼保護頁字元計數硬值：密碼 **100**／訪客訊息 **5,000**／首頁標題 **70**／中繼描述 **320** | 44:571–578 | ⚠️ | 22:75「標題 ≤70、描述 ≤320」；48:1129 | 密碼 100／訪客訊息 5,000 未寫 |
| H-127 | 爬蟲存取權（HTTP Message Signatures / Web Bot Auth，含 Signature/Signature-Input/Signature-Agent 與有效期） | 44:575–577 | ❌ | 30 號無 | 全新面向，30 號 SEO 完全沒有 |
| H-128 | 分頁 cursor 每頁上限 **250**；陣列型 input 上限 250 | 28 自訂（對齊 Shopify） | ✅ | 28:18、28:21 | 齊 |
| H-129 | cursor 分頁參數要寫進 URL（`?before=&after=&tab=`，可分享可回溯） | 44:562 | ❌ | 28 §0.3 未規範 URL 同步 | 未寫 |

**表 2 缺口數：`103`**（H-01～H-129 共 129 條規則中，判定 ✅ 完整者 12 條、⚠️ 部分 26 條、❌ 完全缺 91 條 → **缺口 = ❌91 ＋ ⚠️26 − 重複計 14（⚠️中僅屬命名/位置問題者）= 103**）。
其中「**我方明文寫錯（不是沒寫）**」共 **7 條**：H-03、H-12、H-38、H-40、H-48、H-95、H-107/H-108（後兩者併計為 1）。

---

## 表 3 · 三方衝突（開發文檔 × 商家文檔 × 實測）

### 3A · 驗證 46c 既有衝突清單（C-01～C-16）

| 編號 | 46c 的判定 | 本次驗證結果 |
|---|---|---|
| C-01 取消訂單阻擋條件 | 取聯集 | ✅ **成立**。補充：我方 16:38 只實作了 help 的一條，dev 的四條全缺（H-15） |
| C-02 取消原因清單 | 採 dev 6 值 | ✅ 成立 |
| C-03 `restock`/`notify` 預設值 UI 與 API 相反 | UI 層顯式帶 true | ✅ 成立。我方 22:35 已寫對 |
| C-04 庫存中文譯名三套 | 以 44 實測為準 | ✅ 成立 |
| C-05 「最終銷售品項」譯名 | 採 44 的「最終銷售品項」 | ✅ 成立（46c 已自標抓取可信度） |
| C-06 建立退貨自動解除封存 | 實作＋UI 明示 | ✅ 成立 |
| C-07 退貨狀態機 help 4 態 vs dev 5 態 | 採 dev 5 值＋help「檢查完成」為 OPEN 子進度 | ✅ 成立。**我方 06:96 目前採 help 的 4 態，需改** |
| C-08 編輯訂單補差價的金流商清單 | 三方一致「寄發票」，但 44 §18.7 有「訂單付款收據（自儲存付款方式扣款後傳送）」→ 需實測 | ✅ 成立，仍為未解 |
| C-09 不可編輯訂單清單 help/dev 無交集 | 取聯集 | ✅ 成立。我方 22:33 只有 1 條 |
| C-10 編輯訂單運費 | 兩者不矛盾：可加/刪 line，不能改配送方式、不重算費率 | ✅ 成立 |
| C-11 庫存五欄層級 | 4 彙總欄 ＋ incoming ＋ unavailable 子分類 | ✅ 成立。**我方 13:59 只有 2 欄** |
| C-12 「每位顧客限用一次」是否需帳號 | 三方查無 → 不要寫死 | ✅ 成立。我方 17:51 用 `customer_key = customer_id 或 email hash`——**這正是 46c 警告「不要寫死」的做法**，需標為本專案決策 |
| C-13 結帳顧客帳號三態已淘汰 | 改布林＋獨立設定頁 | ✅ 成立 |
| C-14 折扣組合額外資格條件 | 以 en 版為完整版（多 Licensify 排除） | ✅ 成立 |
| C-15 商店抵用金「只能全額使用」 | 標未驗證 | ✅ 成立，仍待人工覆核 |
| C-16 三方一致正面清單 6 條 | — | ✅ 成立 |

**結論：46c 的 15 條衝突全部成立，但清單不完整——遺漏至少 10 條，補列如下。**

### 3B · 46c 未涵蓋的新增衝突（T-01～T-10）

| # | 功能 | 開發文檔（46a/46b）說 | 商家文檔（46c）說 | 實測（44）看到 | 判定採用哪個 ＋ 理由 |
|---|---|---|---|---|---|
| **T-01** | 退貨費用是否**自動**從退款扣抵 | `suggestedRefund` **自動**扣：`refund = 品項價值 − 退貨費用 − 換貨扣抵`，floor 0（46a:595–601） | 商家在退款頁「**手動改退款金額以扣除重新上架費**」（46c:218）；建立退貨時會顯示退貨運費且**可逐筆編輯**（46c:436） | 未涵蓋 | **兩層都要**：`returnProcess`／`returnCalculate` 自動算出建議值（dev），admin UI 允許覆寫（help）。理由：dev 是 API 行為的權威，help 描述的是 UI 覆寫能力，兩者是「建議值＋可覆寫」而非矛盾。**我方 22:61 寫「退貨費不自動從退款扣」——這條與 dev 直接衝突，須改為「自動帶入建議值、可覆寫」** |
| **T-02** | 換貨品項的**庫存保留時點** | 換貨會建立 fulfillment order（`ON_HOLD` ＋ `AWAITING_RETURN_ITEMS`），且**銷售紀錄自動建立**（46a:552–556） | 「**在您處理退貨之前，不會保留換貨品項的庫存**」，換貨品可能被別人買走（46c:299、46c:359） | 未涵蓋 | **採 help（不保留庫存）**，dev 的 FO 只是**工作單佔位、不動 committed**。理由：help 是逐字且重複兩處；dev 沒有任何一句說「保留庫存」。**⚠️ 需查證**：`AWAITING_RETURN_ITEMS` 的 FO 是否計入 committed，文檔未載明 |
| **T-03** | 退款是否有**上限硬約束** | `maximumRefundable` 存在但**公式文檔未載明**（46a:606、46a:770） | **超額退款允許**：先發過商店抵用金者可對原付款方式 over-refund（46c:223、46c:241） | 未涵蓋 | **不得做成 DB CHECK 硬擋**。我方 16:44「累計退款 ≤ 實收（DB CHECK 級測試）」會擋掉 help 明載的合法情境。改為：預設軟上限 `netPayment`，超額需 `over_refund` 權限＋二次確認＋審計。理由：help 是唯一有具體行為描述的來源；dev 未給公式即代表可自定 |
| **T-04** | **市場的運送設定是否繼承** | `MarketDeliveryConfigurations.shipping` 逐字「**Null means the market inherits shipping from its parent**」（46b:659–661） | 未涵蓋 | 44:866 逐字「**運送與隱私權不繼承，永遠市場本地**」（市場詳情頁把運送放在「更多設定」區而非「繼承的設定」區） | **採 dev（會繼承）**。理由：46b 是 API 欄位的逐字文檔；44 是從 UI 分區推論的（把設定放在「本地」區塊不等於 API 不繼承）。**⚠️ 此為 29 號 Markets 規格的關鍵分歧，須以 introspection 覆核** |
| **T-05** | 市場**父子關係怎麼存** | **父子由 conditions 自動推導（lineage inference）**；`Market` 物件**沒有 `parentMarket`/`childMarkets` 欄位**，不可讀寫（46b:636–639、46b:717） | 未涵蓋（46c:835 只說「子市場繼承母市場設定」） | 44:856 市場詳情頁有「**上層市場：🏪 商店預設**」區塊；44:869 結論建議 `market(parent_id)` | **採 dev（推導）＋存為 derived 快取欄位並標明**。我方 29:42 目前把 `parent_market_id` 當**權威欄位**存，會導致「商家改了 regions 但父子關係沒跟著變」。推導規則：region 嚴格子集 ／ location 落在父 region 內；**具體地點列舉不參與推導**（46b:639） |
| **T-06** | 可繼承維度**有幾個** | 公開 API 只有 **4 個** customization 有繼承定義（catalogs／webPresences 累加；currencySettings／priceInclusions 覆寫）＋ shipping 的 null 語義（46b:650–664、46b:777–788） | 未涵蓋 | 44:862 實測 **8 個**（幣別/目錄/折扣/主題/結帳設定檔/網域+語言/稅與關稅/退貨規則） | **UI 做 8 個、API 標 4+1 有官方語義、其餘 4 個（折扣/主題/結帳設定檔/退貨規則）標「本專案自定」**。理由：46b:788 明言這四項是「admin UI 已上線、公開 API 未跟上」。**29 號目前 8 個都沒寫繼承語義** |
| **T-07** | 結帳設定檔／主題能否**按市場切換** | `CheckoutProfile` **無任何 market 欄位**（46b:783）；主題**無對應 API 欄位**（46b:782） | 未涵蓋 | 44:851–853 市場詳情「繼承的設定」明列 `線上商店 / Horizon`（主題）與 `結帳頁面與顧客帳戶 / 「CHILL LOVE」設定` | **UI 採實測（可切換）、資料模型自定**，並在 spec 標「Shopify 公開 API 未載明，本專案決策」。理由：實測畫面是最終真相，但不能假裝有 API 依據 |
| **T-08** | `RestockType` 的**列舉值** | 46a:747 抓到 **`RESTOCK` / `NO_RESTOCK` / `LEGACY_RESTOCK`**（S11） | 未涵蓋（只說「將品項重新入庫」勾選） | 未涵蓋 | **兩份互斥，須 introspection 定案**。我方 28:90 寫 `RETURN\|CANCEL\|NO_RESTOCK`（第三種寫法）。**三個來源三套值 → 列為必須查證項，實作前不得二選一** |
| **T-09** | 「25 個自動折扣」的**口徑** | 「At any given time, only **25 automatic discounts can be active**」＝**全店同時 active**（46b:264 引 `ACTIVE_PERIOD_OVERLAP`） | 46c:688 表格寫「同時 active 的自動折扣（**每張訂單**）25」 | 未涵蓋 | **採 dev（全店）**。46c 的「每張訂單」是它自己加的口徑，與所引來源 H28 及 46b 的錯誤碼描述都不符——**這是 46c 衝突清單自己沒發現的內部誤植**。我方 22:102「自動折扣全店同時 ≤25」寫對了 |
| **T-10** | 請款**幾種模式** | 未涵蓋（46a 只有 `orderCapture`） | **四種**：結帳自動／履行後自動／**每次履行時自動（Plus）**／手動（46c:508–514，H33 zh-TW） | 未涵蓋 | **採 help 四模式**。我方 22:147/22:157 明文寫「**修正：舊文件寫四模式，官方現行三模式**」——**這條「修正」是錯的**，help 2026-08 實抓仍為四模式，第四種是 Plus 專屬。22 必須回退此修正 |

**表 3 缺口數：`25`**（46c 既有 15 條全部成立且我方規格對其中 **9 條**尚未落地 ＋ 本次新增 10 條）。

---

## 表 4 · API ↔ UI 對應缺口

### 4A · 正向：44 實測到的「會寫入資料的控件」→ 28 有無對應操作

| 方向 | 操作／控件（44 出處） | 對應方（28 章節） | 狀態 |
|---|---|---|---|
| UI→API | 訂單列表「批次處理近期訂單」（44:72） | 28 §4 無 bulk order mutation | **孤兒** |
| UI→API | 更多動作 › 複製訂單（44:102） | 28 §4 無 `orderDuplicate`；22:34 有需求 | **孤兒** |
| UI→API | 更多動作 › 列印（裝箱單/揀貨單/發票）（44:102、44:506） | 28 無列印/文件範本操作 | **孤兒** |
| UI→API | 商品詳情「包材（packaging）」欄位（44:141、44:151） | 28 §1 productUpdate 無此欄；28 §11 deliveryProfile 無 | **孤兒** |
| UI→API | 商品「銷售此商品」洞察卡（44:146） | 28 §14 report 可涵蓋 | TBD（需指定 report type） |
| UI→API | 市場「地區資料夾分組」「圖表檢視」「推出(launches)」（44:188–192、44:186） | 28 §13 無 | **孤兒 ×3** |
| UI→API | 市場詳情「繼承 vs 覆寫」逐項設定（44:843–857） | 28 §13 只有 `marketCreate/Update` | **孤兒**（缺 `market_setting(key, value NULL=繼承)` 的逐項 mutation） |
| UI→API | 主題「有可用的版本 4.1.4」線上更新（44:306–307） | 28 §9 無 themeUpgrade | **孤兒** |
| UI→API | AI 主題生成器（44:309） | `[api:TBD-themeGenerate]` | **TBD** |
| UI→API | 設定 › 運送 › **取貨點（pickup points）**（44:322、44:505） | 28 §11 只有 `deliveryProfile*` | **孤兒（P0，台灣超商取貨的落地點）** |
| UI→API | 運送 › 貨運業者帳號 / carrier rate（44:526–529） | 28 無 carrierService | **孤兒** |
| UI→API | 運送 › 預計配送日期 / 運送標籤 / 包材（44:500–503） | 28 無 | **孤兒 ×3** |
| UI→API | 設定 › 稅金 › 稅務服務三檔切換 / 關稅設定 / 海關資訊批次（44:383–392） | 28 §11 只有 `taxSettingsUpdate`（P1 簡化） | **孤兒 ×3** |
| UI→API | 設定 › 政策 › **退貨與取消規則 CRUD**（44:419–435） | 28 全無 | **孤兒（P0）** |
| UI→API | 設定 › 顧客帳號 › 自助退貨 toggle／商店抵用金 toggle／變更帳號網域（44:412–414） | `[api:TBD-customerAccountsUpdate]` | **TBD ×3** |
| UI→API | 設定 › 結帳 › 結帳規則（validation）（44:376） | 28 無 | **孤兒** |
| UI→API | 設定 › 結帳 › 加入購物車數量上限 modal（44:378） | 28:150 `checkoutSettingsUpdate(... cartItemLimit)` | ✅ 有對應 |
| UI→API | 設定 › 通知 › 個別範本 toggle（44:455、44:461、44:464） | 28:152 只有 `notificationTemplateUpdate(subject, bodyLiquid)` | **孤兒**（缺 enabled 欄位） |
| UI→API | 設定 › 地點 › POS 訂閱層級（44:402–403） | 28 §11 `locationAdd/Edit/Deactivate` 無 pos 欄位 | **孤兒** |
| UI→API | 線上商店 › 偏好設定（密碼保護/OG/hreflang/自動導向/hCaptcha）（44:571–574） | `[api:TBD-onlineStorePreferencesUpdate]` | **TBD** |
| UI→API | 線上商店 › **爬蟲存取權（建立簽章）**（44:575） | 28 無 | **孤兒** |
| UI→API | 內容 › 檔案 › 複製連結（44:273） | 讀操作 | ✅ N/A |
| UI→API | 結帳與帳號編輯器（6 頁 × section × block）（44:645–712） | 28 §10 編輯器 API **只涵蓋主題**（`/editor/api/themes/...`） | **孤兒**（缺 checkout editor 端點與 `checkout_ui_extensions` registry） |
| UI→API | B2B › 建立公司（含 location／catalog／payment terms／稅務／訂單提交模式）（44:814–828） | 28 全無 company* | **孤兒（P1，整組）** |
| UI→API | 分析 › 探索建構器（metrics/dimensions/visualization/filters）（44:786–808） | `[api:TBD-reportCreate]`；28:176 只有 `report(type,...)` | **TBD** |
| UI→API | 分析 › 幣別切換器（44:290、44:295） | 28 §14 無 currency 參數 | **孤兒** |
| UI→API | 財務 › 2FA 閘門（44:281–282） | 28 無 | **孤兒**（38 有 JIT/2FA 設計，未接 API） |
| UI→API | 帳單 › 過去帳單 7 態 tabs（44:551） | `[api:TBD-shopBillingInvoices]` | **TBD** |
| UI→API | 顧客 › AI 分群描述器（44:159） | `[api:TBD-segmentSuggest]` | **TBD** |

**正向小計：孤兒 24 個、TBD 8 個。**

### 4B · 反向：28／46a／46b 的操作 → 有無 UI 消費

| 方向 | 操作 | 對應方 | 狀態 |
|---|---|---|---|
| API→UI | `returnApproveRequest` / `returnDeclineRequest`（28:91） | 原型無自助退貨審核佇列頁 | **孤兒** |
| API→UI | `reverseFulfillmentOrderDispose`（28:91） | 原型無逆向履行 UI | **孤兒** |
| API→UI | `returnRefund`（28:91） | **官方已 deprecated**（46a:642、46a:802） | **應刪除**（見 H-38） |
| API→UI | `fulfillmentOrderSplit` / `Move` / `Hold` / `ReleaseHold`（28:80） | 原型只在 `fulfill` 註釋提到「on hold 須先解除」（admin-v2 DOCS `fulfill`），無 split/move UI | **孤兒 ×3** |
| API→UI | `fulfillmentEventCreate`（28:81） | 無 UI | **孤兒**（可標 API-only） |
| API→UI | `fulfillmentTrackingInfoUpdate` / `fulfillmentCancel`（28:81） | 22:38「取消出貨（先 void 標籤）」有需求，原型無 | **孤兒 ×2** |
| API→UI | `orderCapture`（28:69） | 22:40 有；原型無 capture 控件 | **孤兒** |
| API→UI | `orderMarkAsPaid`（28:69） | 22:41 有；原型無 | **孤兒** |
| API→UI | `orderClose` / `orderOpen`（28:69） | 封存 ✅（原型 DOCS `moreactions`） | ✅ |
| API→UI | `refundCreate`（28:90） | 原型 DOCS `refund` ✅ 但**未標 `[api:]`** | ⚠️ 有 UI、無標註 |
| API→UI | `orderEdit*`（28:70） | 原型 DOCS `editorder` ✅ 但**未標 `[api:]`**，且無 CalculatedOrder diff UI | ⚠️ |
| API→UI | `orderCancel`（28:69） | 原型 DOCS `moreactions` ✅ 但**未標 `[api:]`** | ⚠️ |
| API→UI | `bulkOperationRunQuery/RunMutation`（28:30） | 無 UI | ✅ 應明確標 **API-only** |
| API→UI | `shopResourceFeedbackCreate`（28:146） | 無 UI | ✅ 應標 **API-only** |
| API→UI | `themeFilesCopy`（28:124） | 無 UI | ✅ 應標 **API-only** |
| API→UI | `urlRedirectBulkDeleteAll`（28:122） | 原型有 `[api:urlRedirectBulkDeleteAll]` ✅ | ✅ |
| API→UI | `discountCodeBulkCreate` / `discountRedeemCodeBulkAdd`（28:110） | 22:107 推廣為 P2；原型無 | **孤兒 ×2** |
| API→UI | `giftCardCredit/Debit`（28:111） | 原型只有 `[api:giftCardCreate]` | **孤兒 ×2** |
| API→UI | `customerMerge`（28:99） | 22:92 有；原型無 | **孤兒** |
| API→UI | `catalogCreate/Update`、`priceList*`（28:169） | 原型有 `[api:catalogCreate/Update]`、`[api:priceListCreate/Update]` ✅ | ✅ |
| API→UI | `marketLocalizationsRegister`（28:169） | 原型 ✅ | ✅ |
| **46a 有、28 完全沒有的操作（12 個）** | `fulfillmentOrderSubmitFulfillmentRequest` / `AcceptFulfillmentRequest` / `RejectFulfillmentRequest` / `SubmitCancellationRequest` / `AcceptCancellationRequest` / `RejectCancellationRequest` / `Cancel` / `Close` / `Open` / `Reschedule` / `Merge` / `ReportProgress` / `fulfillmentOrdersReroute` | — | **28 缺（13 個）** |
| **46a 有、28 完全沒有（退貨線 10 個）** | `returnRequest` / `returnCancel` / `returnClose` / `returnReopen` / `returnProcess` / `returnLineItemRemoveFromReturn` / `returnCalculate` / `returnableFulfillments` / `reverseDeliveryCreateWithShipping` / `reverseDeliveryShippingUpdate` | — | **28 缺（10 個）** |
| **46a 有、28 沒有（訂單編輯 4 個）** | `orderEditAddShippingLine` / `UpdateShippingLine` / `RemoveShippingLine` / `orderEditUpdateDiscount` | — | **28 缺（4 個）** |
| **46b 有、28 沒有（折扣 5 個）** | `discountAutomaticAppCreate/Update` / `discountCodeAppCreate/Update` / `discountsAllocatorFunctionRegister` | — | **28 缺（5 個）** |
| **46b 有、28 沒有（B2B 6 個）** | `companyCreate` / `companyLocationCreate` / `companyLocationUpdate` / `companyLocationAssignTaxExemptions` / `paymentTermsCreate` / `draftOrderCalculate` | — | **28 缺（6 個）** |
| **46b 有、28 沒有（Markets 1 個）** | `Market.assignedCustomization(customizationId:)`（「繼承/已覆寫」徽章的資料來源） | — | **28 缺（1 個）** |

**反向小計：孤兒 16 個、應標 API-only 3 個、應刪除 1 個、28 缺漏操作 39 個。**

### 4C · 既有 TBD 標記結案狀態

| 來源 | 數量（本次實際計數） | 結案情形 |
|---|---|---|
| `chilllove-admin-v2.html` 的 `[api:TBD-*]` | **33 個唯一名稱**（45 處出現；含 1 個通用 `api:TBD-*` 樣板佔位 → 實質 **32 個**） | **結案 0 個**——28 號自上次以來未新增任何一個。**全部維持待辦** |
| `chilllove-storefront-v2.html` 的 `[ep:TBD]` | **30 處**（19 種不同說明；任務描述的 28 個為前次計數，本次為 30） | **結案 0 個**。其中 **6 條屬台灣落地關鍵**：ECPay 電子地圖 `ServerReplyURL`（我方待定 `/checkout/cvs_callback`）、地圖服務供應商待定、回拋端點、加值中心開立/作廢 API、store credit 端點、consent 寫入端點 |

**32 個 `api:TBD` 完整清單（全部列為待辦，無一結案）**：
`alertsFeed`、`appUninstall`、`attributionSettingsUpdate`、`brandSettingsUpdate`、`customerAccountsUpdate`、`draftOrderReserveInventory`、`fulfillmentBatchCreate`、`giftCardSettingsUpdate`、`inventoryTransferCreate`、`inventoryTransferReceive`、`marketSuggest`、`marketingActivityCreate`、`marketingAutomationUpdate`、`marketingAutopilot`、`onlineStorePreferencesUpdate`、`payoutList`、`payoutScheduleUpdate`、`privacySettingsUpdate`、`productDescriptionGenerate`、`reportCreate`、`segmentSuggest`、`sellingPlanGroupCreate`、`shippingLabelPurchase`、`shippingOptionsByMarketUpdate`、`shopBillingInvoices`、`shopPlanUpdate`、`shopPolicyUpdate`、`storeCreditAccountCredit`、`storeCreditAccountDebit`、`themeGenerate`、`timelineCommentCreate`、`webPixelCreate`。

**表 4 缺口數：`132`**（正向孤兒 24 ＋ 正向 TBD 8 ＋ 反向孤兒 16 ＋ 反向應刪/應標 4 ＋ 28 缺漏操作 39 ＋ 未結案 TBD 標記 32＋30 中歸併為 41）。
> 精確拆分：正向 32、反向 59、TBD 未結案 41。

---

## 表 5 · 台灣落地缺口

| # | 項目 | 官方/實務要求 | 我方寫在哪 | 是否可實作 | 缺口 |
|---|---|---|---|---|---|
| **TW-1** | **電子發票 4 類** | 個人雲端發票（預設）／捐贈發票／公司戶（統編）／紙本二聯（商家可關） | `42:518`（前台結帳「發票資訊」區完整表） | ✅ 前台可實作 | **商家後台側完全沒有**：哪幾類開/關、捐贈碼機構清單維護、紙本二聯開關——`22 §8` 設定分頁清單無「發票」項；`28` 無 einvoiceSettings mutation（僅平台側 `platformEinvoiceSettingUpdate`，38:1058） |
| **TW-2** | **3 種載具** | 會員載具（預設，存平台/中獎 email）／手機條碼 `^/[0-9A-Z.+-]{7}$`／自然人憑證（2 大寫字母＋14 數字＝16 碼） | `42:519`（含 regex 與即時驗證） | ✅ 格式規則可實作 | ①「手機條碼可打財政部 API 驗證存在性」標為加值，**未定案**；②載具與 `einvoices.carrier_type/carrier_id`（38:1003）的對映表未寫；③**中獎通知流程**（會員載具中獎 email）未寫 |
| **TW-3** | **統編檢核** | 8 碼；權重 `1,2,1,2,1,2,4,1`，各位乘積之數字和可被 10 整除；第 7 碼為 7 時有特例 | `42:520` | ⚠️ 可實作但**須查證** | ①**財政部自 2023 年起放寬檢核（新增可被 5 整除的規則）——本簿不臆測，列為必查證項**；②`36:552` 與 `36:397` 的統編處理只有 `/\b\d{8}\b/` 正規表達式，**無檢核演算法**；③`38:1400` 只比對「揭露的統編 == `shops.tax_id`」，也無檢核 |
| **TW-4** | **字軌** | 由加值中心代辦；期別（雙月制）＋2 碼英文字軌＋號碼區間；**耗盡即無法開立**；15% 門檻告警；工商憑證效期 5 年、到期前 60 天須重辦 | `38:984–998`（`einvoice_tracks` 完整 schema）、`38:1248–1303`（監控 job）、`38:1505`（測試表） | ✅ 平台側可實作 | ①**期別格式與雙月制規則「待定，需使用者確認」**（38:986）；②**作廢的期別限制（是否須在該期別申報前完成）文檔未載明**（38:885）；③**「48 小時上傳」期限 33 §9 明言來自媒體整理，不得寫死**（38:885）；④商家後台看不到自己的字軌餘量（只有平台 console 有） |
| **TW-5** | **發票 ↔ 訂單事件掛鉤** | 開立時機三選一（付款／出貨（建議）／收貨）；全額取消自動作廢；部分退貨自動折讓 | `38:975`（`issue_timing`）、`38:1508`（refund_router：== 作廢／< 折讓／> 作廢） | ⚠️ 平台側邏輯有 | **`16-F5` 退款流程（16:45 的執行順序）完全沒有呼叫發票 router 的步驟**；`16-F4` 取消訂單也沒有；`18-F1` outbox topic 清單（28:186 的 24 個 topic）沒有 `einvoice/*` → **退款不會觸發作廢/折讓 = 稅務錯誤** |
| **TW-6** | **超商取貨 ↔ Shopify pickup points 模型** | Shopify 側：`設定 › 運送 › 其他配送方式 › 取貨點`（44:322）；checkout UI targets `purchase.checkout.pickup-point-list.*` 與 `pickup-location-*` 是**兩組不同 target**（46b:532–552）＝「到店取貨(local pickup)」與「取貨點(pickup points)」是兩種東西；Function API 有 `Pickup Point / Local Pickup Delivery Option Generator`（unstable，46b:65） | `42:521–540`（ECPay 電子地圖完整流程：map 端點、LogisticsSubType 8 種、ServerReplyURL 回拋 5 欄位、門市卡、材積/金額/外島邊界） | ⚠️ 前台流程可實作 | ①**admin 側與 API 側完全沒有**：`15`／`16`／`28`／`22 §8 運送` 全無 pickup point 概念 → **前台選了門市，後台無處存、無法出貨**；②**未區分 local pickup 與 pickup point 兩種模型**；③`FulfillmentOrder.deliveryMethod`（46a:306）未落地 → 無法按配送方式拆單；④storefront-v2 的 `[ep:TBD ServerReplyURL（我方待定 /checkout/cvs_callback）]`、`[ep:TBD 地圖服務供應商待定]`、`[ep:TBD 回拋端點]` **三個端點未定案** |
| **TW-7** | **COD（貨到付款）上限** | 超商代收 **≤NT$20,000**（超過隱藏 COD 選項）；宅配 COD 常加代收手續費 NT$30–60；COD 訂單付款狀態 = pending（`manual` gateway），出貨後物流代收 → 對帳回寫 paid | `42:542`（一段文字） | ⚠️ 有規則、無規格 | ①**NT$20,000 未進任何常數表**（22:160 常數表無此項，`config/limits.yml` 不存在）；②**「代收手續費」行項**在 `15-F2` 金額引擎的 Result 結構（15:19）中無對應欄位；③**COD 對帳回寫 paid 的流程**在 `16` 完全沒有（無 manual gateway 對帳規格）；④COD 限額/拒收黑名單風控只有一句話 |
| **TW-8** | **個資法 72 小時通報** | `authority_notify_due_at = detected_at + 72.hours` | `38:1012`（`pdpa_incidents` 完整欄位）、`38:885`（待確認項） | ✅ 平台側可實作 | ①**起算點是「知悉」還是「發生」，33 未載 → 38:885 標為待確認**（`detected_at` vs `occurred_at` 兩欄都有，判定式未定）；②**台灣 PDPA 對 DSR（查閱/複製/更正/刪除）的法定回覆天數未確認**，38:885 已標且 `statutory_due_at` 留 null；③**商家（租戶）側沒有任何通報入口**——38 是平台 console，商家後台無「回報個資事件」功能 |
| **TW-9** | **電支條例：不得資金池** | 平台不得代收代付並保管資金，否則落入特許範圍；租戶貨款走租戶自持通道商戶號直接入租戶帳戶；平台只處理自己的應收 | `37:3`（三個硬約束之一）、`37:11`（migration 檔頭與 service 註釋強制）、`37:479–491`（架構鐵律）、`37:523`（`payout_accounts` 唯讀鏡像註釋）、`37:895`（「撥款批次僅為鏡像，**無任何『發起撥款』的 mutation**」） | ✅ **完整，本表唯一無實質缺口項** | 唯一小缺：`15-F4` Stripe 整合（15:54–69）沒有引用這條鐵律——Stripe 的 destination/separate charges 模式選擇會直接決定是否踩線，15 號應加一句約束 |
| **TW-10** | **七天鑑賞期（消保法）** | 合規巡檢六項含「七天鑑賞期告知」與「鑑賞期例外商品標示」 | `36:432`、`38:913`、`38:1525`（matcher 測試） | ⚠️ 只有巡檢、無業務規則 | **退貨規則的「退貨期間」下限未強制 ≥7 天**——22:62 寫「14/30/90/自訂」，自訂可填 3 天即違法。`config` 與 spec 均無下限 guard |

**表 5 缺口數：`27`**（TW-1:1、TW-2:3、TW-3:3、TW-4:4、TW-5:3、TW-6:4、TW-7:4、TW-8:3、TW-9:1、TW-10:1）。

---

## P0 / P1 / P2 彙總

**P0 定義**：照現有規格開發**會產出錯誤行為**——金額算錯、狀態卡死、資料遺失、法遵違規。

### P0（15 條，必須在 M3/M4 動工前修）

> ✅ **2026-08-12：15 條已全數處置**，修正紀錄與測試案例見 **`docs/specs/52-p0-logic-fixes.md`**；上限值集中於**新建的 `config/limits.yml`**。
> 52 號另列出本簿**漏掉的 7 條新 P0 候選**（NP0-A～NP0-G），其中 **NP0-F（合併運費以「費率名稱」為合併鍵）建議升為 P0-16**。
> 本簿下方 §「必須查證、不得臆測的項目」的 10 組，已在各規格就地標記 `⚠ 待查證（來源未載明）`，並集中於 52 號 §附錄 A（另補 V-11～V-14 四組新發現）。


| # | 缺口 | 錯誤後果 | 修哪份文件 | 證據 |
|---|---|---|---|---|
| **P0-01** | **退款公式缺「退貨費用扣減」與「換貨扣抵」與「floor 0」** | 有換貨或退貨費的訂單**退款金額必錯**（可能退成負數或多退） | `16-F5`（16:44） | 46a:595–601 / 16:44 |
| **P0-02** | **退貨費用模型完全缺失**（restocking fee 為 %/per line、return shipping fee 為固定額/per return/presentment 幣別） | 無欄位可存 → 退款金額錯、無法對帳 | `16`、`06 §7` | 46a:526–530、46a:649 |
| **P0-03** | **訂單級多個百分比折扣的基數寫反**：17:42 明文「pipeline 序列計算（20%+10%=72 折）」，官方三方一致為「**都按原始小計相加**（30 折）」 | **折扣金額直接算錯 2 個百分點**；且與我方 22:105 自相矛盾 | `17-F2`（17:42） | 46b:284、46c:720、22:105 |
| **P0-04** | **`fulfillmentOrderCancel` 產生替代單、部分 hold/move 產生 remaining 單 未寫** | 取消或部分保留後，**剩餘品項憑空消失**（資料遺失） | `16-F3`、`28 §5`、`06` | 46a:236–240、46a:358–366 |
| **P0-05** | **FulfillmentOrder 狀態機（7 status ＋ 8 requestStatus ＋ 12 supportedActions）完全不存在** | 履約線的按鈕 guard 無依據 → 狀態卡死、非法轉移；`fulfillmentOrderClose → INCOMPLETE`（不是 CLOSED）會做反 | `06 §4`、`16-F3` | 46a:213–275 / 06:86–101 |
| **P0-06** | **Return 狀態機採 help 的 4 態**（06:96），缺 `DECLINED`/`CANCELED`/`OPEN`/`CLOSED` 與 6 條不可逆 guard | 已拒絕的退貨可被重新核准；`REQUESTED` 可被直接取消 → 狀態卡死與帳務錯亂 | `06 §4`、`16` | 46a:438–482、46c:1021–1033 |
| **P0-07** | **「訂單有 active return → 不可取消」互鎖未寫** | 退貨進行中仍可取消訂單 → **雙重退款＋庫存重複回補** | `16-F4`（16:38） | 46a:832–838、46a:1028 |
| **P0-08** | **`return_line_items` 必須外鍵到 `fulfillment_line_items`，且前提「已送達」** | **schema 級錯誤，上線後改不得**；且會允許退未出貨品項 | `06 §2 ER`、`16` | 46a:519、46a:627、46a:648 |
| **P0-09** | **換貨未產生 `ON_HOLD` ＋ `AWAITING_RETURN_ITEMS` 的 FulfillmentOrder** | 換貨品在收到退貨前就出貨 → **直接資損** | `16`、`06` | 46a:552–556、46a:1039 |
| **P0-10** | **退貨與取消規則「綁購買時點快照」未進任何 spec** | 商家改規則會**追溯既往**，舊訂單的退貨期限/費用全部跟著變 → 費用算錯、顧客權益爭議 | `16`、`13`、`28`、`06 §7` | 46c:422–426、44:437（三方一致） |
| **P0-11** | **冪等語義三處錯/缺**：①`11:45–48` 回放**原始快照**，官方是**由當前狀態重建**；②無 TTL 24h；③無 `IDEMPOTENCY_CONCURRENT_REQUEST` / `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` 兩碼與參數指紋正規化 | 退款重試會**重複退款**或誤判 mismatch 而卡死 | `11 §2`、`28 §0.6` | 46a:781–794、46a:1000–1016 |
| **P0-12** | **請款模式數量寫錯**：22:147/22:157 明文「三模式（修正舊文件的四模式）」，help 2026-08 實抓為**四模式**（第四種「每次履行時自動請款」為 Plus 專屬） | 多次出貨的訂單**請款行為錯誤**（該逐次請款卻整單請款） | `22 §8`、`22 §9-1` | 46c:508–514 |
| **P0-13** | **超商取貨（pickup points）在 admin/API 側完全無規格** | 前台選了門市**後台無處存、無法出貨** → 台灣最主要配送方式不可用 | `15`、`16`、`28 §11`、`22 §8` | 44:322、42:521–540、46b:532–552 |
| **P0-14** | **`orderCancel` 契約錯誤**：28:69 的簽名含官方**不存在的 `refund: Boolean`**、缺 `staffNote`/`refundMethod`、缺 `restock` non-null、缺**非同步 job 回傳**、缺「停用地點＋已付款＋restock:true 會失敗」 | 取消訂單行為與本尊不符；同步執行跨聚合操作會逾時中斷 → **半取消狀態卡死** | `28 §4`、`16-F4` | 46a:842–877 / 28:69 |
| **P0-15** | **庫存資料模型只有 `available/committed` 兩欄**（13:59），但 06:111 恆等式與 44:150 實測都需要 `unavailable`（含 4 子分類）＋`incoming` | 草稿單保留庫存、待收退貨無處可存 → **恆等式恆不成立、nightly 對帳永遠告警、且會超賣** | `13-F5`、`06 §7` | 46c:891–927、06:111、44:150 |

### P1（33 條，M4/M5 前修）

金額/契約類：**H-41 運費折扣不可疊運費折扣（只寫在 22:105 按鈕表，17 號資料模型三旗標對稱會做錯）**、H-07 的稅額分攤未定義、H-34 `maximumRefundable` 未標本專案決策、**T-03 退款上限 DB CHECK 會擋掉合法超額退款**、H-83 禮品卡優先扣抵順序、H-97 逾期請款 1.75% 附加費、H-96 授權效期方案差異表、TW-7 COD 上限與代收手續費行項、TW-5 退款未觸發發票作廢/折讓。

狀態/契約類：S-03 `OrderReturnStatus` 6 值、S-20 `ReturnErrorCode` 26 值、S-23 `DiscountErrorCode` 39 值、H-38 `returnRefund` 已 deprecated 仍列於 28、H-48 `customerSelection` 已 deprecated 仍列於 28、H-13 orderCancel async job、S-19 CalculatedOrder 暫存層與 `stagedStatus`、H-33 訂單編輯 session 單一鎖與 TTL、H-19 fulfillmentCreate 同 order 同 location、H-18 hold 上限 10 進 guard。

規則類：H-15 取消四條件聯集、H-94 不可編輯訂單清單聯集（help 5 條＋dev 4 條）、H-93 編輯後在報表中算獨立訂單、H-111 合併運費以「費率名稱」為合併鍵、H-112 zone ≠ market、H-101/H-103 庫存七原因與四子態列舉、H-99 草稿保留進 Unavailable、H-116 通知範本 `toggleable`（合規約束）、H-106 結帳欄位三態與「要求登入⇒強制 email」聯動、H-107 棄單門檻三處不一致、TW-10 退貨期間下限 7 天（消保法）、T-04/T-05 Markets 繼承與父子關係模型、H-64～H-68 B2B 掛載層級（整組，無規格檔）。

### P2（其餘，M5/M6 或明確標「刻意不做」）

Function 資源限制換算（H-52/H-53）、Checkout UI Extensions 31 targets 與三個上限（H-57/H-58）、validation 25 條 JSONPath 白名單（H-54/H-55）、關稅 duties（46a §6⑦-33 建議 M4 不做）、`ReturnReason` 10 值（deprecated）、`FulfillmentOrderRejectionReason` 14 值（無 3PL 時用不到）、爬蟲存取權（H-127，差異化候選）、Webhook XML 格式（H-117）、H-100 草稿單 1 年自動刪除、H-105 子類每日上傳速率、H-126 字元計數硬值、H-129 cursor 參數寫入 URL、S-30 帳單 7 態、TW-8 租戶側個資通報入口。

### 必須查證、不得臆測的項目（10 條）

| # | 項目 | 為何不能自行決定 |
|---|---|---|
| V-01 | `RestockType` 的真實列舉值（46a／28／實務三套） | 三方互斥（表 3 T-08）→ **GraphQL introspection** |
| V-02 | 市場的 `shipping` 到底繼不繼承（46b 說繼承 vs 44 說不繼承） | 直接矛盾（表 3 T-04）→ introspection ＋ 實測 |
| V-03 | 換貨品項的 `ON_HOLD` FulfillmentOrder 是否佔用 committed 庫存 | 46a 與 46c 表面衝突，**兩份文檔皆未載明**（表 3 T-02） |
| V-04 | 台灣統編檢核演算法的現行規則（是否含「可被 5 整除」） | 42:520 只有舊規則；**財政部原文須覆核**（TW-3） |
| V-05 | 電子發票期別格式與雙月制規則 | 38:986 已標「待定，需使用者確認」 |
| V-06 | 發票作廢的期別限制、「48 小時上傳」期限 | 38:885 明言 33 §9 的來源是媒體整理，**須以財政部《電子發票實施作業要點》原文覆核** |
| V-07 | 個資外洩 72 小時的起算點（知悉 vs 發生）、PDPA 的 DSR 法定回覆天數 | 38:885 已標未載明 |
| V-08 | `purchase.checkout.block.render` 的 14 個 placement 字串 | 46b:997 標為「四個版本頁面皆未列出」→ 實測 dev store |
| V-09 | `maximumRefundable` 公式、稅額在退款時的分攤規則、`FulfillmentOrderHoldUserErrorCode`／`SplitUserErrorCode`／`OrderCancelUserErrorCode` 的具體值、`fulfillmentOrderSplit` 最大拆分數、`RestockingFeeInput.percentage` 最大值、`RefundShippingInput` 同時給 `amount` 與 `fullRefund` 的行為 | 46a:1049–1067 已逐條標「文檔未載明」共 15 項 |
| V-10 | 每店 markets 總數上限、market 巢狀層數上限、`MarketUserErrorCode`、單一折扣可綁 markets 數、Function 執行失敗的 fallback 行為 | 46b:993–1010 已逐條標「文檔未載明」共 14 項（其中「社群有 50 markets 說法，**未經官方證實，勿引用**」） |

---

## 附錄：本簿的統計口徑

| 表 | 缺口數 | 口徑 |
|---|---|---|
| 表 1 · 狀態機 | **26**（含次要缺漏則 29） | 30 條狀態機中，狀態數不足或轉移/guard 未寫者計 1 |
| 表 2 · 硬性約束 | **103** | 129 條規則中 ❌91＋⚠️26，扣除純命名/位置問題 14 |
| 表 3 · 三方衝突 | **25** | 46c 既有 15 條（其中 9 條我方未落地）＋新增 10 條 |
| 表 4 · API↔UI | **132** | 正向 32（孤兒 24＋TBD 8）＋反向 59（孤兒 16＋應刪/標 4＋28 缺 39）＋未結案 TBD 41 |
| 表 5 · 台灣落地 | **27** | 10 個主項下的可實作性缺口逐條計 |
| **合計** | **313** | 其中 **P0 15 條**、**P1 33 條**、**必須查證 10 組** |
