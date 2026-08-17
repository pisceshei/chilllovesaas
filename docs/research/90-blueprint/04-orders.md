# 04. 訂單生命週期（Order / Draft Order / Editing / Risk）

> 考掘日 2026-08-14。來源代號見 §G；每條規則性斷言標 [Sx]。倉庫既有底盤：`docs/research/46a`（API 狀態機字典）、`docs/research/76`（admin 按鈕級實測）、`docs/specs/16/86/87`（我方裁定）。本檔補齊 46a/76 未深挖的：建立來源、單號體系、封存、風險評估、Timeline、Draft Order 全流程；與既有裁定的差異一律在 §F 標注。

---

## A. 領域物件模型

### A.1 核心物件與 cardinality

```
Shop 1 ── N Order ── N LineItem（下單快照，見 87 號）
              │ 1 ── 0..1 OrderRiskSummary（risk 欄；聚合 recommendation）
              │            └── N OrderRiskAssessment ── N RiskFact
              │ 1 ── N Event（timeline；CommentEvent 是其中一種）
              │ 1 ── N OrderTransaction
              │ 1 ── 0..1 OrderCancellation（取消後才存在）
              │ 1 ── N FulfillmentOrder（見 46a §2，本檔不重複）
              │ 1 ── N Refund / N Return（見 46a §4/§6，本檔不重複）
Shop 1 ── N DraftOrder ── N DraftOrderLineItem
              │ 0..1 ──> Order（completedAt 後的 order 欄；單向、至多一張）[S2]
              │ 1 ── N Event（draft 有自己的 timeline，不與正式單共用）[S28]
```

### A.2 Order 的身分欄位（四種識別字，語義各異）[S1][S31]

| 欄位 | 型別 | 語義 | 規則 |
|---|---|---|---|
| `id` | ID! | GraphQL GID（`gid://shopify/Order/{n}`） | API 唯一主鍵 |
| `legacyResourceId` | UnsignedInt64! | REST 數字 id | 與 GID 尾碼同值 |
| `name` | String! | admin 與訂單狀態頁顯示的單號（如 `#1001`、`EN1001-CA`） | ＝prefix + number + suffix；prefix/suffix 在 設定→一般 自訂 [S1]；起始號 1001 不可改、逐筆 +1（76 §1 實測）|
| `number` | Int! | 用來組 `name` 的序號 | GraphQL 的 number 即 1001 起的值 [S1]；REST 另有 `number`（1 起）與 `order_number`（1001 起）兩欄 [S31] ⚠ 兩者差值恆為 1000 是觀察值，官方未明文保證 |
| `confirmationNumber` | String | 顧客面確認碼，隨機英數（例 `XPAV284CT`） | 🔴 官方明言**不保證唯一** [S1][S31]——不得當 key 用 |
| `poNumber` | String | B2B 採購單號 | 可經 `orderUpdate` 改 [S14] |

### A.3 Order 的來源欄位（建立管道歸屬）[S1]

| 欄位 | 說明 |
|---|---|
| `sourceName` | 來源字串，官方例：`web`、`mobile_app`、`pos`；REST 例另見 `instagram`、`shopify_draft_order` [S31] ⚠ 全值域官方未窮舉（第三方 app 可自報 handle）|
| `sourceIdentifier` | POS 或第三方的外部單號（例 `1234-12-1000`）|
| `app` | OrderApp——建立訂單的應用（Online Store／Point of Sale／自訂 app 名） |
| `publication` | 建單的銷售管道（sales channel） |
| `statusPageUrl` | URL!——顧客查單頁（含追蹤與配送進度） |

**四種建立來源與其欄位組合**：①checkout（`web`/`mobile_app`，publication＝Online Store）②draft order 轉正（`shopify_draft_order`，Order.name 取**新的**訂單序號，draft 保留自己的 `#D` 序號 [S2]）③API 匯入（`orderCreate`，app＝建立它的 app [S10]）④POS（`pos` ＋ `sourceIdentifier`）。管道歸屬會反向鎖能力：app 建的單**不可用 admin 編輯**（[S32]；76 §3 實測同一閘）。

### A.4 DraftOrder 關鍵欄位 [S2]

- 身分：`name`（`#D` 序列，例 `#D1223`）、`legacyResourceId`。
- 狀態：`status`（DraftOrderStatus，§B.4）、`ready`（可否完成）、`completedAt`、`order`（轉正後的訂單）。
- 收款：`invoiceUrl`（安全結帳連結）、`invoiceSentAt`、`paymentTerms`、`amountDueNowSet` / `amountDueLaterSet`（有付款條款時拆兩段）、`deposit`（Plus 訂金設定）。
- 庫存：`reserveInventoryUntil`——預設**不**保留庫存，設了才保留，語義＝「保留到期時間」[S6]；物件頁稱其為自動回補（restock）期限 [S2]。
- 折扣：`appliedDiscount`（訂單層自訂折扣，**一單一個**；行項亦一行一個）[S6]、`discountCodes`（不合格的 code 計算時跳過）[S6]、`acceptAutomaticDiscounts`、`allowDiscountCodesInCheckout`。
- 幣別：`currencyCode`（商店幣別）＋ `presentmentCurrencyCode`（顧客幣別）雙軌。
- 其他：`visibleToCustomer`（自助 portal 可見性）、`purchasingEntity`（B2B）、`taxExempt`、`poNumber`、`warnings`。

### A.5 風險物件 [S20][S21][S24]

```
Order.risk : OrderRiskSummary!
  ├─ recommendation : OrderRiskRecommendationResult!   （整單建議，聚合值）
  └─ assessments    : [OrderRiskAssessment!]!          （多筆，每提供者一筆）
       ├─ provider  : App?    （null＝Shopify 自家評估）[S20]
       ├─ riskLevel : RiskAssessmentResult!
       └─ facts     : [RiskFact!]!   （description ≤256 字元、超過截斷 [S24]；sentiment 三值）
```

舊物件 `OrderRisk`（REST／舊 GraphQL）已被本組物件取代；我方只落地新模型（46a 同判）。

### A.6 Timeline 事件 [S28][S29]

- `Event` interface：`id`、`createdAt`、`message`、`attributeToApp`、`attributeToUser`、`criticalAlert`、`appTitle`。
- `CommentEvent`（人寫的留言）額外有：`author`（StaffMember）、`rawMessage`、`attachments`、`embed`（參照的物件）、`subject`（所屬資源）、`edited` / `canEdit` / `canDelete`。
- Timeline 出現在：訂單、草稿訂單、顧客、（庫存）轉移四種資源 [S28]；**全部僅內部可見，顧客看不到** [S28]。

---

## B. 狀態機

> Order 沒有單一 status——是「生命週期軸＋金流軸＋履行軸＋退貨軸」四條正交軸（46a §1 已立）。本節補生命週期軸、Draft Order、Edit session、Risk 四個 46a 未成表的狀態機；金流軸（8 值）與履行軸（7＋3 值）**全表引用 46a §1，不重抄**。

### B.1 Order 生命週期軸（open / closed / cancelled）

狀態全集：`open`（closedAt=null, cancelledAt=null）｜`closed`（封存；closedAt≠null）｜`cancelled`（cancelledAt≠null）。`cancelled` 與 `closed` **可疊加**（取消後自動封存）。

| 轉移 | 觸發 | 前置條件 | 副作用 |
|---|---|---|---|
| open→closed | `orderClose` [S12]／admin「封存」／bulk 封存／**自動封存** | 自動封存條件＝「已付款且已履行」或「已全額退款」[S16]；手動無前置 | 設 `closedAt`；移出開啟訂單清單；建 timeline 事件 |
| closed→open | `orderOpen` [S13]／admin「取消封存」 | 訂單需在 closed 態 [S13] | 清 `closedAt`；回到開啟清單。另：**建立退貨會自動解除封存**（46a 互鎖 #9） |
| open→cancelled | `orderCancel`（async job）[S17]（46a §7 全表） | 46a §7 四條 guard＋[S17] 補：**部分履行後不可取消**（先取消出貨或走退貨）；排程付款中的 pending 單可能不可取消；三方履行服務單須先在該服務取消；FB/IG 在 Commerce Manager 編輯過的單不可取消 | 設 `cancelledAt`＋`cancelReason`＋`OrderCancellation.staffNote`；依選項退款/回補庫存；timeline 記錄退款與回補明細 [S17] |
| cancelled→closed | 自動封存（全額退款單符合 [S16] 條件） | — | 已取消列在列表全列刪除線（76 §1） |

- **無孤兒**：cancelled 是商業終態（無 uncancel）；closed 可逆（orderOpen）；open 是初態。
- `closed` 判定式（closed 欄）＝所有 line item 已履行或已取消 **AND** 所有金流交易完成 [S1]——兩條件合取＝**自動封存資格判定式**（手動 orderClose 無前置、不受此限，見 B.1 （2026-08-17 更正，PR #52 第 9 輪）），46a §1⑦-4 已立為實作鐵則。
- 封存 vs 取消的語義分界：取消＝中止處理中的訂單；封存＝處理完畢移出清單 [S17]。

### B.2 金流軸（`displayFinancialStatus`，8 值）

全集＝`PENDING / AUTHORIZED / PARTIALLY_PAID / PAID / PARTIALLY_REFUNDED / REFUNDED / VOIDED / EXPIRED`，轉移表見 46a §1-1a（本次覆核 [S1] 無增減）。REST 側為 7 個小寫值（無 expired）[S31]；help 顯示層另有聚合值「未付款」＝授權＋待處理＋已到期＋部分付款、badge「即將到期」（76 §2）——**顯示聚合不是狀態**，不落庫。補充：`orderMarkAsPaid` 的轉移語義＝有未清餘額且非 PAID 時，建一筆 SALE 交易（或 capture 既有授權）直接推向 PAID [S15]。

### B.3 履行軸與退貨軸

履行軸 7 現行值＋3 被取代值、退貨軸 6 值：46a §1-1b/1c 全表照用，皆為 derived。（本次覆核無版本變動。）

### B.4 DraftOrder 狀態機 [S3]

狀態全集（3 值，官方定義意譯）：

| 值 | 語義 |
|---|---|
| `OPEN` | 未付款、未寄發票 |
| `INVOICE_SENT` | 已寄發票給顧客 |
| `COMPLETED` | **已轉正式單**（＝conversion；付款態留在轉出訂單的獨立金流軸——payment terms 單轉正時金流態非 PAID，定義若綁「已付款」會擋合法的付款條款轉正 （2026-08-17 更正，PR #52 第 8 輪）） |

| 轉移 | 觸發 | 前置 | 副作用 |
|---|---|---|---|
| （建立）→OPEN | `draftOrderCreate` [S5]／admin 建立／POS 存 cart | 至少 1 個行項（"Add at least 1 product" [S5]） | 取 `#D` 序號；設 reserveInventoryUntil 才保留庫存 [S6] |
| OPEN→INVOICE_SENT | `draftOrderInvoiceSend`／admin 寄發票 | 本地幣別（非商店幣別）＋非 Plus 不可寄發票（76/[S7]） | 設 `invoiceSentAt`；email 含 checkout 連結 [S8] |
| OPEN/INVOICE_SENT→COMPLETED | ①顧客走 invoice checkout 付款 [S8] ②admin 標記已付／刷卡 [S7] ③`draftOrderComplete` [S4] ④「payment due later」（付款條款）完成 | `ready`＝true；標記已付前不得先 mark paid（會弄壞 invoice 連結 [S8]） | 🔴 轉正瞬間：建立正式 Order（取新訂單序號）、進訂單列表、**為品項保留/扣庫存**、通知顧客 [S4]；`completedAt`＋`order` 欄回填；draft 的 metafields 單向複製到 order（76 §4 實測）；付款條款單→order 帶 paymentTerms、金流態非 PAID（⚠ 精確值官方未載，見 openQuestions） |
| OPEN/INVOICE_SENT→（刪除） | `draftOrderDelete`／admin 刪除 | — | 直接消失；**2025-04-01 後建立的 draft 閒置 1 年自動清除，任何編輯重置計時** [S9] |

- **無孤兒**：COMPLETED 為終態（不可回 draft；改單走正式單的 edit）；OPEN/INVOICE_SENT 皆可完成或刪除。
- INVOICE_SENT 後再改內容合法，但**已算出的運費不會自動更新** [S8]。

### B.5 Order Edit（staged changes，非狀態機）

`orderEditBegin → CalculatedOrder（累積 staged 變更）→ orderEditCommit / 放棄`，`stagedStatus`＝`ADDED/REMOVED/UNCHANGED`——46a §8 全表照用。本次覆核補充（help 側 [S32][S33]）：admin 可做＝加/移商品、調數量、調運費、加行項手動折扣；**order 層折扣不可加/移/改**；discount code、script、自動折扣不可改；不可改配送方式（如運送改取貨）。

### B.6 Risk 狀態機（`riskLevel`：RiskAssessmentResult，5 值）[S23]

| 值 | 語義 |
|---|---|
| `PENDING` | 評估中 |
| `LOW` / `MEDIUM` / `HIGH` | 詐騙可能性低／中／高 |
| `NONE` | 該提供者不給建議 |

轉移＝`PENDING →（評估完成）→ LOW/MEDIUM/HIGH/NONE`；每次有新評估（任一 provider 呼叫 `orderRiskAssessmentCreate` 或 Shopify 重評）→ 覆寫該 provider 那筆並發 `orders/risk_assessment_changed` webhook [S26]。整單 `recommendation`（OrderRiskRecommendationResult，4 值）[S22]：`ACCEPT`（建議履行）/ `INVESTIGATE`（建議聯絡買家查證）/ `CANCEL`（建議取消）/ `NONE`（無建議）。

**聚合函數（assessments → recommendation）**：⚠️ 官方未明文——[S21] 對 `recommendation` 只寫「基於各評估的建議動作」，未載任何聚合規則（2026-08-14 覆核，原文即止於此），本尊實際行為待實測。**我方裁定（登記 F.2 #18）＝最壞者勝（worst-of）純函數**，四條：

1. severity 全序：`NONE(0) < LOW(1) < MEDIUM(2) < HIGH(3)`；`PENDING` 不參與取 max（語義＝尚無結果，非零風險）。
2. 映射（窮舉）：`max=HIGH → CANCEL`｜`max=MEDIUM → INVESTIGATE`｜`max=LOW → ACCEPT`｜無任何已完成評估（零筆或全 `PENDING`）或已完成者全 `NONE` → `NONE`。
3. provider 平權：自家引擎（provider=null）不加權、不優先——最壞者勝已保證「任一 provider 喊 HIGH 即攔」，加權只多特例不多安全。
4. deterministic 重算：任一筆 assessment 被覆寫即整單重算，`recommendation = f(現存 assessments)`，無隱藏狀態——同組輸入必得同輸出（可測性前提）。

若日後 parity 實測發現本尊聚合與此不符，以實測修正本節並更新 F.2 #18。社群稱「出貨前皆可新增評估」但 mutation 頁未載明期限 [S26]。

---

## C. 業務規則與不變量

### C.1 單號規則

1. 訂單序號從 1001 起、逐筆 +1、**起始號不可改**（76 §1 實測；[S1] 佐證 name＝prefix+number+suffix）。取消、刪除不回收號碼（序列只進不退）。
2. prefix/suffix 改動只影響**之後的新單**，不回溯（⚠ 官方 help 未直書，第三方與實測一致）。
3. draft 用獨立 `#D` 序列；轉正時**另取**訂單序列的下一號 [S2][S4]。
4. `confirmationNumber` 隨機英數、不保證唯一 [S1]——只可顯示，不可當索引鍵；查詢用 name/id。

### C.2 建立（orderCreate）規則 [S10][S11]

- `options.inventoryBehaviour` 三值（全集）：`BYPASS`（不動庫存）/ `DECREMENT_IGNORING_POLICY`（無視超賣政策扣）/ `DECREMENT_OBEYING_POLICY`（尊重政策、能扣才扣）。**預設值＝`BYPASS`，官方明標於 `OrderCreateOptionsInput`（2026-08-14 覆核）[S34]**——省略此參數＝完全不扣庫存；匯入單要扣庫存必須明文傳 `DECREMENT_*`。我方照抄此預設並加一條 UI 加嚴（F.2 #17）。
- `options.sendReceipt` / `sendFulfillmentReceipt` 控制是否補寄確認信／出貨通知，兩者預設皆 `false` [S34]。
- 自動折扣**不套用**、discount code 一單只認一個、稅與交易須呼叫端自帶 [S10]——API 匯入單是「原樣落地」，不重跑 checkout 定價。
- 試用店/開發店限流：每分鐘最多 5 張新單 [S10]。
- 可在建立時直接指定 `financialStatus` / `fulfillmentStatus`（例 PAID＋FULFILLED 的歷史單匯入）[S10]。

### C.3 取消規則（46a §7 之外的 help 補強）[S17][S18]

- 退款方式三選一：原付款方式（預設）／store credit（需權限；input 為 `OrderCancelRefundMethodInput.originalPaymentMethodsRefund` / `storeCreditRefund` [S18]）／稍後再退（Later）。
- `restock` 預設勾選、`notifyCustomer` 預設勾選（admin 對話框 [S17]；API 側 restock 為必填、notify 預設 false——**admin 預設與 API 預設不同**，46a §7②）。
- 取消後金流終態：未請款→`VOIDED`；已退→`REFUNDED`；先取消後補退→`PARTIALLY_REFUNDED` [S17]。
- 回補與退款明細寫入 timeline [S17]。
- 不可取消聯集（46a 四條 ＋ help 補三條）：已取消／pending authorization／active return／不可履行的未結出貨（46a）＋部分履行後／排程付款中／三方管道限制（[S17]）。全集收斂進 16 §F4.1 的 guard。

### C.4 編輯規則（46a §8 之外的 help 補強）[S32][S33]

- 不可編輯聯集（官方散落各頁，收斂）：app 建立的單｜Shop Pay Installments 付的單｜本地配送（local delivery）單｜pending payment（**未決 PSP 交易形**；manual 單不在此列 （2026-08-17 更正，PR #52 第 9 輪））中的品項/折扣受限｜已履行品項不可移除/調量｜order 層折扣不可動｜非手動折扣（code/script/automatic）不可改｜不可改配送方式｜（46a）封存單、2019-01-01 前、非商店幣別（無升級）、多期預付訂閱調量。→ 對應 16 §F8.3 的九條聯集 guard。
- 編輯後：總額增→寄更新發票收款；總額減→發退款 [S33]。
- 運費不會因編輯自動重算 [S32]；稅會自動重算（46a §8④）。
- 分析側：編輯後的訂單在報表以獨立分錄呈現 [S32]；部分 app 整合不識別編輯 [S32]。
- 匯率：多幣別單編輯用的匯率依編輯型態而異 [S32] ⚠ 精確規則未載。

### C.5 Draft Order 規則 [S7][S8]

- 自訂品項必填：名稱＋價格＋數量；選項：需課稅、實體商品；**不入庫存、不動存量** [S7]。bundle 不支援鎖價 [S7]。
- 付款條款全集（[S7]，76 §3 同）：`Due on receipt`／`Due on fulfillment`／Net `7/15/30/45/60/90`／`Fixed date`。付款提醒 email 至多 5 則（76 §3）。
- 訂金（deposit）＝Plus 限定，百分比制 [S7]。
- 本地幣別（≠商店幣別）＋設付款條款：只能刷卡或標記已付收款 [S8]。
- 標籤每個 ≤40 字元 [S7]。
- invoice 的幣別由顧客收件地址所屬市場決定 [S8]。
- 保留庫存：選到期時間，期間他人不可購買 [S7]；到期自動釋放（[S2] 稱 automatic restock deadline）。

### C.6 風險規則 [S20][S24][S16][S27]

- fact.description >256 字元截斷 [S24]；sentiment 全集＝`NEGATIVE`（推高風險）/`NEUTRAL`/`POSITIVE`（降低風險）[S25]。
- Shopify 自家評估的 provider 為 null [S20]。
- 官方四類指標：AVS、CVV、IP 位址、異常購買模式 [S27]（76 §3 實測同：三色指標＋購買模式）。
- 自動履行設定有「連高風險單也自動出」的獨立勾選 [S16]——即**預設高風險單不自動履行**。
- 未經審查就履行高風險單的後果＝chargeback 風險 [S27]；Shopify Protect／Fraud Protect＝美國 Shopify Payments 限定 [S27]。
- ⚠ 完整詐騙分析的方案門檻：76 §3 實測「完整分析=Grow+ 或用平台收款」；help 本次未查得成文——維持實測值、標待證。

### C.7 Timeline 規則 [S28]

- 留言**只有作者本人**可編輯/刪除；**編輯窗＝發文後 5 分鐘**，逾時只可刪不可改 [S28]（76 §3 實測同值）。
- @mention 通知：email＋（裝 app 者）push；**不通知**：自我提及、對該區無權限者 [S28]。
- `#` 參照可連 7 型：訂單／草稿訂單／顧客／商品／變體／轉移／採購單 [S28]（76 §3「7 型」吻合）。
- 全部內部可見；attachments 型別/大小上限官方未載 ⚠。

### C.8 併發要害（本領域）

- 取消＝async job：同單重複觸發只可執行一次（46a §7⑦-38，我方強制冪等）。
- edit session 單開鎖＋TTL＝我方裁定（16 §F8.2；官方空白）。
- draft 轉正瞬間的庫存保留與 checkout 庫存競態：官方只說完成時 reserve [S4]——超賣防線由我方庫存模組鎖（16/46a 併發測試清單）。
- 風險評估寫入與履行的競態（評估到達時已出貨）：官方無鎖——我方以「履行前檢查 recommendation」為 guard，寫入照收。

### C.9 金額計算（本領域內的公式）

- 訂單淨收款：`netPayment = totalReceived − totalRefunded`（46a §1④；[S1] 覆核不變）。
- draft 有付款條款時：`amountDueNow + amountDueLater = totalPrice`（deposit % 決定拆分 [S2][S7]）。
- 編輯調降的退款、取消的退款：全部走 16 §F5 退款公式與 86 §3.2 撤銷聚合（不重複定義）。
- rounding：本尊以 MoneyBag（shop＋presentment 雙幣 decimal）承載；我方一律 integer cents，捨入規則見 65 號（本檔不另立規則，避免雙源）。

---

## D. 關鍵流程

### D1. Checkout 建單（略述，詳見 checkout 章）
顧客結帳 → 訂單建立（sourceName=web，publication=Online Store）→ 發 `orders/create` → 依付款模式落 `PAID`（自動請款）或 `AUTHORIZED`（手動請款，SP 授權 7 日，76 §3）→ 風險評估非同步產出（`orders/risk_assessment_changed`）。

### D2. API 匯入建單
操作者＝外部系統/app。`orderCreate(order, options)` → 驗證（行項必有；試用店限流 5 單/分 [S10]）→ 依 `inventoryBehaviour` 決定扣不扣庫存 [S11]（**省略＝`BYPASS` 不扣 [S34]**；要動存量必須明文傳 `DECREMENT_*`，經庫存模組執行——超賣防線只在 `DECREMENT_OBEYING_POLICY` 下生效）→ 建單（app 欄記建立者）→ `orders/create`。失敗分支：`OrderCreateUserError`（code 未窮舉 ⚠）。**此單日後不可 admin 編輯**（C.4 第一條）。

### D3. Draft Order 全流程（invoice 路徑）
1. 店員建 draft（商品/自訂品項/折扣/運費/顧客/市場幣別）→ `draft_orders/create`。
2. （選）設 reserveInventoryUntil 保留庫存 [S6]。
3. 寄發票：email 含 checkout 連結 → status=INVOICE_SENT、`invoiceSentAt` [S8] → `draft_orders/update`。
4. 顧客開連結，填帳單資訊、選運送方式、付款 [S8]。
5. 🔴 轉正瞬間（一個交易內該發生的事）：建 Order（新序號）＋扣/保留庫存＋draft.status=COMPLETED＋`completedAt`/`order` 回填＋訂單標 Paid [S8]＋metafields 單向複製（76 §4）→ 發 `orders/create`＋`orders/paid`＋`draft_orders/update`。
6. 失敗分支：庫存不足→顧客無法完成 checkout，解法＝保留品項 [S8]；先手動標 Paid→invoice 連結失效 [S8]。

### D4. Draft Order（payment due later 路徑）
店員選付款條款（C.5 全集）→ 立即轉正：Order 帶 paymentTerms、金流非 PAID（顯示「未付款」聚合，76 §2）→ 到期前 badge「即將到期」（截止前 2 天，76 §2）→ 之後用「收款」（send invoice / 刷卡 / 標記已付 [S15]）補收 → 全額到帳發 `orders/paid`。

### D5. 編輯訂單
`orderEditBegin`（guard：C.4 聯集）→ staged mutations 累積、稅與總額即時重算（46a §8）→ `orderEditCommit(notifyCustomer, staffNote)` → `orders/edited` webhook [S30] → 差額為正：寄更新發票；為負：退款流程 [S33]。放棄＝丟棄 CalculatedOrder，原單不變。我方另加：session 單開鎖＋TTL 24h（16 §F8.2，官方空白）。

### D6. 取消訂單
admin「取消訂單」對話框（原因必選＋退款方式三選一＋restock/notify 預設勾 [S17]）→ `orderCancel`（async job，46a §7）→ job 完成：cancelledAt/reason/staffNote 落地、退款建立（走 F5）、庫存回補、FulfillmentOrder 全關、timeline 記明細 [S17] → `orders/cancelled`。失敗分支：C.3 不可取消聯集之一 → `orderCancelUserErrors`；停用地點＋已付款＋restock → 整體失敗（46a §7②）。

### D7. 封存／取消封存
自動：付清＋履行完 或 全額退款 → 自動進封存（設定預設開 [S16]，76 §2 同）。手動：單筆「封存」/bulk（76 §1 bulk 13 動作含封存/取消封存）→ `orderClose`/`orderOpen` [S12][S13]。封存不動金流與庫存，只是清單歸類（[S17] 語義分界）。

### D8. 風險評估
訂單建立 → Shopify（provider=null）評估、第三方 app 可 `orderRiskAssessmentCreate` 補評 [S26] → 每次變更發 `orders/risk_assessment_changed` [S26] → admin 訂單詳情顯示風險卡（三級＋指標，76 §3）→ 商家分支：ACCEPT→履行；INVESTIGATE→聯絡買家；CANCEL→走 D6（reason=FRAUD）。自動履行開啟時，高風險單仍預設攔下（除非勾了 [S16] 的高風險例外）。

### D9. 標記已付
「收款→標記已付」→ `orderMarkAsPaid`：有未清餘額且非 PAID → 建 SALE 交易或 capture 授權 [S15] → 金流轉 PAID → `orders/paid`。失敗：已付清 → userError（"Order cannot be marked as paid."）。

---

## E. 跨模組耦合

### E.1 本領域發出的 webhook topics（全集，[S30]）

| Topic | 時機 |
|---|---|
| `orders/create` | 建單（四種來源都發） |
| `orders/updated` | 任何更新（含請款、履行推進、編輯 commit） |
| `orders/paid` | 付清 |
| `orders/cancelled` | 取消完成 |
| `orders/fulfilled` / `orders/partially_fulfilled` | 履行完成／部分履行 |
| `orders/edited` | 編輯 commit（與 orders/updated 並發） |
| `orders/delete` | 刪單 |
| `orders/link_requested` | 顧客從過期狀態頁要求新連結 |
| `orders/risk_assessment_changed` | 新風險評估到達 |
| `orders/shopify_protect_eligibility_changed` | Protect 資格變更（我方不實作 Protect，topic 保留位） |
| `order_transactions/create` | 交易建立**或狀態更新**（注意：update 也走這個 topic） |
| `draft_orders/create` / `update` / `delete` | 草稿三事件（轉正時發 update，非 delete） |
| `refunds/create`、`returns/*`（8 topics） | 見 46a §4/§6 領域 |

### E.2 依賴方向

- **庫存**（消費方向）：draft reserve／orderCreate inventoryBehaviour／cancel restock／edit setQuantity restock——全部呼叫庫存模組，本領域不自算存量。
- **金流**（雙向）：請款/作廢/退款動作發起於本領域，交易結果回寫金流軸；`order_transactions/create` 是對帳線的輸入。
- **履行**：FulfillmentOrder 事件 → 重算 `displayFulfillmentStatus`（derived，46a）；取消訂單會關閉履行單。
- **退貨**：Return 事件 → 重算 `returnStatus`；active return 反向鎖取消（互鎖 #1）。
- **稅務**：取消/退款/編輯發「稅務事件」→ jurisdiction pack 決定憑證動作（CLAUDE.md 鐵律 11；16 §F5.5）。
- **分析**：編輯單獨立分錄 [S32]；AOV 分子刻意排除 post-order adjustments（鐵律 7 例外註）；撤銷聚合走 86 §3.2。
- **通知**：invoice email、取消通知、mention email/push——經通知模組，transaction 內禁外部 IO（鐵律 5）。

---

## F. 落地對應

### F.1 對應倉庫文件

| 主題 | 本檔節 | 既有文件 |
|---|---|---|
| 四軸狀態機、Cancel/Edit API 面 | B.1–B.3、B.5 | `docs/research/46a` §1/§7/§8（權威，本檔只補缺） |
| admin 按鈕與值域實測 | C.3–C.7 | `docs/research/76` §1–§4 |
| 取消 guard、編輯 guard、退款公式 | C.3/C.4 | `docs/specs/16` F4/F5/F8 |
| 撤銷 vs 退貨命名與聚合 | E.2 | `docs/specs/86` |
| line item 快照五欄 | A.1 | `docs/specs/87` |
| 金額單位 | C.9 | `docs/specs/65` |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊原貌 | 我方裁定 | 出處 |
|---|---|---|---|
| 1 | 金額＝MoneyBag（shop＋presentment 雙幣 decimal） | 內部一律 integer cents（×100），序列化層才轉 MoneyV2/MoneyBag；原幣與換算值是兩個獨立 Storage 值 | 鐵律 3、65 號、76 §3 |
| 2 | 單租戶概念（每 shop 一庫） | 全業務表帶 `shop_id`＋複合索引開頭（訂單全家族無豁免） | 鐵律 2 |
| 3 | 泛用 `UserError` 無 code（訂單線大量使用，46a §1③） | 全 mutation 一律 typed code enum——**刻意加嚴，非照抄** | CLAUDE.md 鐵律 4 |
| 4 | `orderCancel` async 但冪等未載 | 強制 idempotencyKey；同單取消只執行一次 | 46a §7⑦-38、鐵律 5 |
| 5 | edit session 鎖/TTL/併發全空白 | 單開鎖（unique index）＋TTL 24h，錯誤碼 INVALID_STATE | 16 §F8.2 |
| 6 | 稅務原生內建、憑證即開 | 核心只發稅務事件，憑證由 jurisdiction pack 落地 | 鐵律 11、16 §F5.5 |
| 7 | 2019-01-01 前訂單不可編輯（歷史包袱） | 不復刻，spec 註明刻意不做 | 46a §8⑦-46 |
| 8 | 履行軸含 3 個被取代值（OPEN 等） | 內部只落 7 現行值；GraphQL enum 保留 3 值標 deprecated | 46a §1⑦-2 |
| 9 | 分析線叫 sales_reversals、訂單線叫退貨（兩線用詞不同） | 照抄兩線並存；資料欄名跟語義不跟 UI | 86 §4.2 |
| 10 | 報表預設用商品「當前值」維度（2024 改版） | 快照五欄下單即存、永不回寫；報表走哪軌 M5 定案 | 87 號 |
| 11 | 自動封存預設開、條件＝付清+履行完/全退 [S16] | 照抄（含 bulk 封存/取消封存 13 動作之列） | 76 §1/§2 |
| 12 | 訂單無合併功能（僅 FO 層 split/merge） | 不做合併訂單（做了＝超集） | 76 §3 |
| 13 | draft 閒置 1 年自動清除（2025-04 起）[S9] | ⚠ 未裁定——多租戶 SaaS 的資料保留應為租戶政策，建議做成 per-shop 設定，M3 定案 | 本檔新發現 |
| 14 | `confirmationNumber` 隨機不唯一 [S1] | ⚠ 未裁定——建議 M3 先不做（我方無「隱藏序號」需求），欄位保留 | 本檔新發現 |
| 15 | admin 取消對話框 restock/notify 預設勾；API notify 預設 false | 兩層預設都照抄（admin UI 預設 ≠ API 預設，是本尊事實） | [S17]＋46a §7② |
| 16 | 風險評估＝Shopify＋第三方 app 並列，provider=null 表自家 | 我方自家規則引擎＝provider null 位；三方評估走 app 介面（M6） | [S20]、76 §3 |
| 17 | `orderCreate` 省略 `options.inventoryBehaviour` 預設 `BYPASS`（官方明標）[S34] | API 預設照抄 `BYPASS`；**加嚴**：我方 admin／內建匯入工具呼叫時一律顯式帶值、不吃預設——防「以為匯入有扣庫存」的靜默超賣 | 本檔 C.2/D2 |
| 18 | 整單 `recommendation` 與各 assessments 的聚合函數官方未載 [S21] | 最壞者勝＋PENDING 不參與＋provider 平權＋deterministic 純函數重算（B.6 四條）；⚠ 官方未明文，待 parity 實測比對，不符則以實測修正 | 本檔 B.6 |

### F.3 開發驗收要點（本章新增項；46a §12 清單之外）

- [ ] `orders` 表：`name`/`number`（1001 起 per-shop 序列，含 prefix/suffix 快照）、`source_name`/`source_identifier`/`app_id`、`confirmation_number`（保留欄）、`po_number`。序號產生器須防併發跳號重複（per-shop 鎖或序列表）。
- [ ] 生命週期軸三態＋B.1 轉移表全測；`closed` 判定式兩條件合取的反例測試（**自動封存 job 路徑**：金流未完不得自動 close；手動 orderClose 不適用 （2026-08-17 更正，PR #52 第 9 輪））。
- [ ] 自動封存 job：兩組條件（付清+履行完／全退）各一測；取消封存後不得被同一條件立即重新封存（需事件觸發，非輪詢重掃）。
- [ ] `draft_orders` 表＋B.4 狀態機；轉正交易的原子性測試（庫存扣減與訂單建立同生共死）；invoice 先 mark-paid 的失效分支。
- [ ] 付款條款：due 值域 C.5 全集入 enum；提醒 ≤5 則入 `limits.yml`。
- [ ] 風險：`order_risk_assessments`（provider nullable）＋`risk_facts`（description 256 截斷）＋整單 recommendation 聚合欄——**聚合＝B.6 我方裁定的最壞者勝純函數（F.2 #18）**；測項至少四條：①任一 HIGH 壓過其餘 LOW→CANCEL ②全 PENDING→NONE ③覆寫同 provider 後重算結果 deterministic ④已完成者全 NONE→NONE；`orders/risk_assessment_changed` outbox 事件；高風險攔自動履行的 guard 測試。
- [ ] `orderCreate` 預設值測試（F.2 #17）：省略 `options.inventoryBehaviour` → 走 `BYPASS` 完全不動存量；明文 `DECREMENT_OBEYING_POLICY` 撞超賣政策 → reject 不建單；內建匯入工具的呼叫層有「必顯式帶值」的 lint/測試。
- [ ] Timeline：CommentEvent 的 5 分鐘編輯窗（server 端強制，非純前端）；mention 通知的兩條排除規則；7 型參照。
- [ ] Webhook topics（E.1 表）全部入 outbox enum；`order_transactions/create` 的「update 也發」語義要有測試。
- [ ] `sourceName` 值不得自由字串入庫——收斂為 enum＋app handle 兩段式，未知值 reject。

---

## G. 來源（全部取證 2026-08-14）

| # | URL | 用途 |
|---|---|---|
| S1 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Order | Order 身分/來源/風險/封存欄位 |
| S2 | https://shopify.dev/docs/api/admin-graphql/latest/objects/DraftOrder | DraftOrder 全欄位、1 年清除 |
| S3 | https://shopify.dev/docs/api/admin-graphql/latest/enums/DraftOrderStatus | 草稿狀態 3 值 |
| S4 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/draftOrderComplete | 轉正副作用、參數 |
| S5 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/draftOrderCreate | 建立參數、關聯 mutation |
| S6 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/DraftOrderInput | reserveInventoryUntil、折扣一單一個 |
| S7 | https://help.shopify.com/en/manual/fulfillment/managing-orders/create-orders/create-draft | 建草稿選項、付款條款全集、訂金、保留 |
| S8 | https://help.shopify.com/en/manual/fulfillment/managing-orders/create-orders/send-draft | invoice 流程、mark-paid 陷阱、幣別限制 |
| S9 | https://help.shopify.com/en/manual/fulfillment/managing-orders/create-orders | 草稿總覽、1 年自動刪除 |
| S10 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderCreate | API 建單行為差異、限流 |
| S11 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderCreateInputsInventoryBehavior | 庫存行為 3 值 |
| S12 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderClose | 封存 |
| S13 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderOpen | 取消封存 |
| S14 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderUpdate | 屬性更新 vs 編輯的邊界 |
| S15 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderMarkAsPaid | 標記已付前置與交易 |
| S16 | https://help.shopify.com/en/manual/checkout-settings/order-processing | 自動封存條件、自動履行與高風險例外 |
| S17 | https://help.shopify.com/en/manual/fulfillment/managing-orders/canceling-orders | 取消對話框、後果、限制 |
| S18 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/OrderCancelRefundMethodInput | 取消退款方式 input |
| S19 | https://shopify.dev/docs/api/admin-graphql/latest/objects/OrderCancellation | staffNote |
| S20 | https://shopify.dev/docs/api/admin-graphql/latest/objects/OrderRiskAssessment | 評估物件、provider null |
| S21 | https://shopify.dev/docs/api/admin-graphql/latest/objects/OrderRiskSummary | recommendation 聚合 |
| S22 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderRiskRecommendationResult | 建議 4 值 |
| S23 | https://shopify.dev/docs/api/admin-graphql/latest/enums/RiskAssessmentResult | 風險 5 值 |
| S24 | https://shopify.dev/docs/api/admin-graphql/latest/objects/RiskFact | fact 256 截斷 |
| S25 | https://shopify.dev/docs/api/admin-graphql/latest/enums/RiskFactSentiment | sentiment 3 值 |
| S26 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderRiskAssessmentCreate | 評估寫入與 webhook |
| S27 | https://help.shopify.com/en/manual/fulfillment/managing-orders/protecting-orders | 四類指標、Protect 資格 |
| S28 | https://help.shopify.com/en/manual/shopify-admin/productivity-tools/timeline | 5 分鐘編輯窗、mention、7 型參照 |
| S29 | https://shopify.dev/docs/api/admin-graphql/latest/objects/CommentEvent | 留言事件欄位 |
| S30 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic | 訂單線 topic 全集 |
| S31 | https://shopify.dev/docs/api/admin-rest/latest/resources/order | REST 值域（financial/fulfillment/cancel_reason）、number/order_number |
| S32 | https://help.shopify.com/en/manual/fulfillment/managing-orders/editing-orders/considerations | 不可編輯聯集、分析影響 |
| S33 | https://help.shopify.com/en/manual/fulfillment/managing-orders/editing-orders | 編輯操作與收款/退款 |
| S34 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/OrderCreateOptionsInput | inventoryBehaviour 預設 BYPASS；sendReceipt/sendFulfillmentReceipt 預設 false |
