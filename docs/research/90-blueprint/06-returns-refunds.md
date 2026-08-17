# 06. 退貨、換貨與退款（Returns / Exchanges / Refunds / Store Credit）

> 研究方法：2026-08-14 以 WebSearch＋WebFetch 實抓 shopify.dev（`latest`＝2026 版 Admin GraphQL）與 help.shopify.com；並對照倉庫既有 `docs/research/46a`（2026-08-11 實抓）、`docs/specs/16` F5/F7、`docs/specs/86`。每條規則性斷言附來源編號（見 §G）；官方未載明者一律標 ⚠️ 或列入 openQuestions，不臆測。
> 讀者假設：已讀 `docs/specs/86`（returns 資源 vs sales_reversals 指標的概念分界）與 CLAUDE.md 鐵律 3（金額單位邊界）。

---

## A. 領域物件模型

### A.1 物件總表與 cardinality

```
Shop 1─N Order
Order 1─N Return                      （一張訂單可多次退貨）
Return 1─N ReturnLineItem             （FK → FulfillmentLineItem，不是 OrderLineItem）
Return 1─N ExchangeLineItem           （換貨品項，掛在 Return 底下）
Return 1─N ReverseFulfillmentOrder    （逆向履行單；returnCreate/approve 時建立）
ReverseFulfillmentOrder 1─N ReverseDelivery（退貨包裹：標籤＋追蹤）
Order 1─N Refund                      （退款掛訂單，不掛退貨）
Refund N─0..1 Return                  （refund.return 可為 null＝無退貨脈絡的退款）
Refund 1─N RefundLineItem             （每行帶 restockType）
Refund 1─N OrderTransaction(kind=REFUND)
Customer/CompanyLocation 1─N StoreCreditAccount（每幣別一戶）
StoreCreditAccount 1─N StoreCreditAccountTransaction
Shop 1─1 ReturnRules                  （退貨規則設定：窗口/費用/final sale/取消窗口）
```

### A.2 Return（退貨單）——關鍵欄位 [G1][G2]

| 欄位 | 型別 | 語義 |
|---|---|---|
| `status` | ReturnStatus! | 見 §B.1 |
| `name` | String! | 退貨單編號（如 `#1001-R1`） |
| `order` | Order! | 所屬訂單 |
| `returnLineItems` | Connection! | 退貨品項 |
| `exchangeLineItems` | Connection! | 換貨品項 |
| `refunds` | RefundConnection! | 由此退貨發起的退款 |
| `transactions` | OrderTransactionConnection! | 「The order transactions created from the return」 |
| `returnShippingFees` | [ReturnShippingFee!]! | 退貨運費（per return 固定額） |
| `reverseFulfillmentOrders` | Connection! | 逆向履行單 |
| `totalQuantity` | Int! | 所有退貨品項數量總和 |
| `decline` | ReturnDecline | 拒絕資訊（reason＋note） |
| `requestApprovedAt` / `closedAt` / `createdAt` | DateTime | 生命週期時戳 |
| `suggestedFinancialOutcome` | SuggestedReturnFinancialOutcome | 財務試算（**`suggestedRefund` 已 deprecated，被此欄取代**）[G2] |
| `staffMember` | StaffMember | 建立者（自助退貨為 null） |

### A.3 ReturnLineItem 與 ExchangeLineItem

- **ReturnLineItem 的外鍵指向 `FulfillmentLineItem`**（`fulfillmentLineItemId`），只有已出貨（且已送達）的品項才能退 [G3][46a §4]。schema 級決策，上線後改不得（16 F7.2 已定）。
- 每行可帶：`quantity`（必填）、`restockingFee`（百分比）、`returnReasonDefinitionId`（標準化原因庫）、`returnReasonNote`（上限 255 字）[46a §4]。
- **ExchangeLineItem 欄位** [G4]：`quantity`（含已退/已移除單位）、`processedQuantity` / `unprocessedQuantity` / `processableQuantity`（三個數量軸追蹤換貨釋出進度）、`lineItems`（指回 order line items——換貨品是**加進原訂單**的行，不是另開新訂單）、`variantId`（建立退貨當下的 variant 快照）。單數 `lineItem` 已 deprecated。

### A.4 Refund（退款）——不可變帳務紀錄 [46a §6]

- **無 status 欄位**。「Refund 物件存在」不等於錢已退到——實際狀態看底下 OrderTransaction。
- `RefundInput`：`orderId`（必）、`refundLineItems[]`（lineItemId＋quantity＋restockType）、`refundShipping`（amount 或 fullRefund）、`refundDuties[]`、`transactions[]`、`note`、`notify`、`refundMethods[]`（→ store credit）。
- **`RefundLineItemRestockType` 值域（4 值，窮舉）** [G5]：

| 值 | 語義（官方描述改寫） | 使用時機 |
|---|---|---|
| `CANCEL` | 品項作廢並回庫存 | **未履行**品項的退款回補 |
| `RETURN` | 品項退回並回庫存 | **已履行**品項的退貨回補 |
| `NO_RESTOCK` | 不回補庫存 | 任意 |
| `LEGACY_RESTOCK` | ⚠️ deprecated；「not accepted when creating new refunds」——只出現在歷史資料，**新建退款不接受** | 只讀 |

### A.5 StoreCreditAccount（商店購物金帳戶）[G6][G7]

| 欄位 | 型別 | 語義 |
|---|---|---|
| `owner` | HasStoreCreditAccounts! | **Customer 或 CompanyLocation** 二者其一 |
| `balance` | MoneyV2! | 目前餘額 |
| `transactions` | Connection! | 可依 `expires_at` / `id` / `type` 篩選 |

- **每幣別一戶**：owner 可持有多戶，各戶綁定單一幣別；credit 時若該幣別無帳戶則**自動開戶** [G7]。
- 交易 type 值域（4 值，窮舉）[G6]：`credit`（入金）、`debit`（扣款）、`debit_revert`（扣款回沖）、`expiration`（過期沖銷）。
- `storeCreditAccountCredit` 的 `creditInput`：`creditAmount: MoneyInput!`＋`expiresAt: Date`（選填）[G7]。debit 對應 `storeCreditAccountDebit`。
- Scope：`write_store_credit_account_transactions`；admin 權限拆為「Store credit／Edit store credit／Refund to store credit」三顆 [G8]。

### A.6 ReturnRules（退貨與取消規則，商店層設定）[G9]

不是 API 物件而是 admin 設定（Settings → Policies），但**值域已窮舉**（見 §C.5）。規則同時餵兩個消費者：①self-serve 自助退貨的資格判定；②商家手動建退貨時的**預設費用帶入**（self-serve 關閉時規則仍生效）[G9][G10]。

---

## B. 狀態機

### B.1 Return.status（5 值，權威狀態機）[G1][46a §4]

值域（窮舉；注意 **CANCELED 單 L**，與 FulfillmentOrderStatus 的 CANCELLED 雙 L 不同）：
`REQUESTED`｜`OPEN`｜`DECLINED`｜`CLOSED`｜`CANCELED`

**轉移表**（觸發動作／前置條件／副作用）：

| # | 轉移 | 觸發 | 前置條件 | 副作用 |
|---|---|---|---|---|
| T1 | ∅ → REQUESTED | `returnRequest`（買家自助或 app） | 品項已送達；非 final sale；在退貨窗口內；單次 ≤250 行 [G10] | webhook `returns/request`；訂單 returnStatus → RETURN_REQUESTED；已封存訂單自動解封存 [46a §4] |
| T2 | ∅ → OPEN | `returnCreate`（商家直建，跳過審核） | 品項已送達（returnableFulfillments） | 建 ReverseFulfillmentOrder [G2]；換貨品項行加入訂單＋換貨 FulfillmentOrder 進 ON_HOLD |
| T3 | REQUESTED → OPEN | `returnApproveRequest`（商家審核通過） | status=REQUESTED | **不可逆**（permanent）[46a §4]；建 RFO；webhook `returns/approve`；寄核准信（可附標籤） |
| T4 | REQUESTED → DECLINED | `returnDeclineRequest` | status=REQUESTED；**declineReason 必填** | **不可逆**；webhook `returns/decline`；寄拒絕信（自訂訊息；reason 僅內部可見 [G11]）；**被拒品項可再建新退貨** [G2] |
| T5 | OPEN → CLOSED | `returnProcess` 處理完全部品項；或移除最後一個品項；或 `returnClose` 手動關 | status=OPEN | **自動關閉條件＝「每個品項都已處理且每個退貨品項都已 restock」**[G3]；webhook `returns/close` |
| T6 | OPEN → CANCELED | `returnCancel` | status=OPEN 且五條全部成立：①未退款 ②未 restock ③未標記已退回 ④無 Shopify 產生的退貨標籤（手動上傳的可以）⑤fulfillment 未被取消 [G3][46a §4] | 「All sales records…will be reversed」；**換貨品項不受影響**；webhook `returns/cancel`；**取消後不可重開，只能另建新退貨** [G3] |
| T7 | CLOSED → OPEN | `returnReopen` | status=CLOSED | webhook `returns/reopen` |

- **孤兒檢查**：DECLINED 與 CANCELED 為終態（無出邊，設計如此）；CLOSED 可經 T7 離開；REQUESTED 只有 T3/T4 兩條出路——**REQUESTED 不能直接取消**（必須 approve 或 decline）[46a §4]。全部 5 狀態進出可達，無孤兒。
- 全程另有 webhook `returns/update`（任何更新）與 `returns/process`（處理時）[G12]。

### B.2 Order.returnStatus（訂單層聚合，6 值，derived）[46a §1]

`NO_RETURN`｜`RETURN_REQUESTED`｜`IN_PROGRESS`｜`INSPECTION_COMPLETE`｜`RETURNED`｜`RETURN_FAILED`
——由該單所有 Return/RFO 事件重算的**衍生快取**，不可直接寫；同時是 orders query 的篩選參數。

### B.3 ReverseFulfillmentOrder（3 值）＋ Disposition（4 值）[46a §5]

- RFO status：`OPEN` → `CLOSED`／`CANCELED`（跟隨 Return 生命週期；return 取消時 RFO 取消）。
- Disposition type（窮舉）：`RESTOCKED`｜`NOT_RESTOCKED`｜`MISSING`｜`PROCESSING_REQUIRED`。
  `PROCESSING_REQUIRED` 是**中間態**（檢驗後尚未定案，可再次 disposition）⇒ 同一 line item 允許多筆 disposition 紀錄，取最新。
- disposition 觸發 webhook `reverse_fulfillment_orders/dispose`；退貨標籤掛上時觸發 `reverse_deliveries/attach_deliverable` [G12]。

### B.4 Refund——刻意無狀態機 [46a §6]

Refund 一經建立不可變、**不可取消不可反轉**（「You can't cancel or reverse a refund after you initiate」[G8]）。金流進度由 OrderTransaction 承載（我方：pending → success/failure，見 16 F5）。訂單層聚合反映在 `displayFinancialStatus`：PARTIALLY_REFUNDED / REFUNDED（REFUNDED 為終態）。

### B.5 Self-serve 取消請求（與退貨請求平行的第二條線）[G11]

取消請求（未出貨品項）沒有獨立資源狀態機，落在訂單卡片上：
`requested → resolved`（商家走 refund 流程移除品項，退款完成即標記 resolved；未付款訂單可走 restock 頁移除或整單取消）或 `requested → declined`（寄信說明）或「Mark as resolved」（不動訂單、不通知，用於已線下處理）。Timeline 記「Cancellation declined」事件。

---

## C. 業務規則與不變量

### C.1 退款金額公式（含 rounding；integer cents 版）

官方語義（2024-07 起）：建議退款＝退貨品項價值 − 退貨費用 − 換貨扣抵 − 買家未付餘額，**floor 到 0** [46a §4④]。我方可測式（16 F5.1 已定，此處為權威摘要）：

```
line_gross[i]     = unit_price_cents[i] × qty_returned[i]
discount_alloc[i] = 最大餘數法(該行折扣分攤額, qty_returned[i]/qty_ordered[i])
line_net[i]       = line_gross[i] − discount_alloc[i]
line_tax[i]       = 最大餘數法(該行原始稅額, 退貨比例)     # 含稅定價時＝0（稅內含不重複加總）
restocking_fee[i] = floor(line_net[i] × restocking_bp[i] / 10000)   # 費用取小⇒退款取大
returned_value    = Σ(line_net[i] + line_tax[i])
return_fees       = Σ restocking_fee[i] + return_shipping_fee_cents
exchange_value    = Σ(換貨單價×數量 − 商品折扣 + 稅)        # 訂單級折扣禁止套用於換貨品
outstanding       = max(0, 應收 − 已收)
net               = returned_value − return_fees − exchange_value − outstanding
suggested_refund  = max(0, net)          # 🔴 不得為負
balance_to_collect= max(0, −net)         # 換貨/欠款造成的負值＝向買家收款
```

- 捨入點只有三個：折扣/稅分攤（最大餘數法）、restocking fee（floor）、零小數幣別跨界（**raise 不 round**，65 §D）。
- 官方對照範例：$50.99 品項 − $5.00 return fee ＝ $45.99 [46a §4④]。
- 「Return fees aren't automatically deducted from refunds」出現在 help 語境＝**UI 顯示建議值、商家可覆寫**；API 的 `returnCalculate`/`suggestedFinancialOutcome` 會自動扣抵 [G13][16 F5.3]。兩層語義不可混淆。

### C.2 退款上限與併發（要害）

- **官方**：標準退款不得超過原付款額 [G8]；`maximumRefundable` 存在但**公式未公開** [46a §11]。
- **我方定義**（16 F5.1，需標註為本專案定義）：`maximumRefundable_cents = captured_total_cents − refunded_total_cents`。
- **超額退款（over-refund）是官方明載的合法情境** [G8]：已退到 store credit 後買家改要求退原卡 ⇒ 可超額退。因此上限是**軟上限**：條件式 UPDATE ＋ `orders.over_refund` 權限＋二次確認，**不得做成 DB CHECK**。API 面：`ReturnProcessRefundInput.allowOverRefunding: Boolean`（default **false**）[G14]。
- 併發不變量：任何時刻 `Σ refunds ≤ captured + approved_over_refund`；兩個並發退款不得合計突破上限（條件式 UPDATE，禁止先 SELECT 再 INSERT；測試 C1–C3 見 16 F5.1(d)）。
- **冪等**：`refundCreate` 自 API 2026-04 起**強制** `@idempotent(key:)`，TTL 24h，錯誤碼 `IDEMPOTENCY_CONCURRENT_REQUEST` / `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` [46a §9]。`returnProcess` 官方未載明冪等 ⇒ 我方強制 `idempotencyKey`（鐵律 5）。

### C.3 混合付款與禮品卡

- **禮品卡優先**：「the suggestion tries to refund the gift card in full first」[G8]——建議分配把退款先塞滿禮品卡，餘額才到其他付款方式；商家可逐一調整各付款方式金額，**上限＝各該付款方式的可退餘額** [G8]。演算法＝greedy 逐筆吃滿（16 F5.4），不是按比例攤。
- 退回禮品卡＝餘額自動加回 [G15]。**過期禮品卡**：不能直接退 ⇒ 先把效期改到未來、退款、再改回 [G15]。**已停用禮品卡**：不可重啟 ⇒ **另發一張新禮品卡**當退款 [G15]。
- 部分退款後買家仍可對**全額**發起 chargeback [G8]（風控要留意）。

### C.4 運費、稅、關稅

- 運費可單獨退；**訂單套用了訂單層級免運折扣 ⇒ 運費完全不可退** [G8]。退運費 ≤ 剩餘可退運費。`RefundShippingInput` 的 `amount` 與 `fullRefund` 同給的行為官方未載明 ⚠️。
- 退款時稅隨品項比例走（我方 X1–X6 規則，16 F5.1）：**官方未公開稅額分攤規則** ⚠️——含稅定價 line_tax=0；未稅定價按原始已收稅分攤（不重算現行稅率）；餘數歸最後一次退貨；全退完必須精確歸零。
- 關稅退款兩模式：`PROPORTIONAL`（按退貨數量比例，需同傳 line items）／`FULL`（該 duty 全退）[46a §4④]；仍屬 developer preview ⇒ M4 不做，schema 預留。

### C.5 退貨規則值域（窮舉）[G9]

| 設定 | 值域（全量） | 補充 |
|---|---|---|
| 退貨窗口 | `14 days`｜`30 days`｜`90 days`｜`Unlimited`｜`Custom days` | 二選一起算：**品項送達日**（無送達資料 fallback 出貨日＋轉運 buffer，buffer 天數未載明 ⚠️）或**整單最後一件送達日**（一單一窗） |
| 取消窗口 | `No cancellations`｜`Until item is fulfilled`｜`15 minutes`｜`1 hour`｜`24 hours` | self-serve 取消請求的資格 |
| 退貨運費 | ①免費退貨 ②固定費率（**每次退貨收一次**）③買家自購標籤 | 三選一 |
| Restocking fee | 勾選啟用＋百分比 | **上限未載明** ⚠️；未履行品項退款**不顯示** restocking fee [G9] |
| Final sale | `Specific collections` 或 `Specific products`（**二擇一，不可混**） | **Bundles 不能設 final sale** [G9] |
| 生效範圍 | **只對未來訂單生效**，不回溯 [G9] | 我方已裁定：規則綁購買時點快照（16 F7.4，同向） |

### C.6 Self-serve returns 硬限制 [G10]

- 退貨資格＝**已送達**品項；取消資格＝**未出貨**品項。
- **換貨不能自助申請**（僅商家端可加換貨品項）；數位商品與客製品需人工審。
- **單次請求 ≤250 line items**，超過須拆單申請。
- 僅支援**新版 customer accounts**（legacy 帳戶不相容）。
- `ReturnRequestLineItemInput.customerNote` 上限 **300 字** [G16]（注意：與商家端 `returnReasonNote` 的 255 不同）。
- 商家設定可選開放類型：兩者皆開／只開退貨／只開取消 [G10]。

### C.7 Store credit 硬規則 [G6][G7][G8]

| # | 規則 |
|---|---|
| 1 | 手動 credit 上限：**單一帳戶 max $15,000 USD**（等值）；credit 金額必須為正；超過幣別上限回 error「credit limit to be exceeded」 |
| 2 | 結帳時**只能整額使用**——官方轉述：只能套用店家信用的全額，顧客無法指定部分金額（餘額全上） |
| 3 | 過期＝**商店時區當日結束**；多筆不同效期 ⇒ **先到期先扣**（FEFO） |
| 4 | 可用通路：online store／POS／Shop app；**不可用於** draft orders、edited orders、訂閱續扣（首購可）、其他通路 |
| 5 | 兌換前提：**新版 customer accounts 登入驗證**；D2C 購物金不可用於 B2B |
| 6 | 退款轉購物金可帶 `expiresAt`（效期合法性依法域） [G17] |
| 7 | 帳戶按幣別隔離；結帳只顯示**與結帳幣別相符**的餘額，不可跨幣併用 |

### C.8 換貨規則 [G3]

- 換貨品**不能是自訂品項**（custom item 禁止）；可套**商品層**折扣，**訂單層折扣禁止**。
- 換貨品**庫存在退貨處理前不保留**（「Inventory not reserved until return processing」）。
- 換貨品產生 `ON_HOLD`＋`AWAITING_RETURN_ITEMS` 的 FulfillmentOrder；等待補款時同樣 hold，商家可提前「Release fulfillment」[G3][46a §4]。
- 差額三情境：商家欠買家（退款 now/later）；買家欠商家（處理時寄 invoice 或訂單頁刷卡收款）；等額換（自動軋平，金額零流動）。
- 等額換貨對分析的影響：金額 `sales_reversals` 淨 0，件數 `returned_quantity` +1（86 §3.3）。

### C.9 與訂單取消的互鎖 [46a §7]

- 訂單有 **active return** ⇒ 不可 `orderCancel`。
- `orderCancel.refundMethod` 可選原付款方式或 store credit。
- 反向：退貨取消不影響換貨品項；fulfillment 已取消 ⇒ 退貨不能取消（見 B.1 T6 前置⑤）。

### C.10 分析口徑（returns 在報表的位置）[G18][G19]

- **記帳日**：銷售記在成立日（正值）；reversal 記在**處理日**（負值）——退貨不回頭改原訂單日。
- 公式（官方逐字改寫）：`net_sales = gross_sales − discounts − sales_reversals`；`total_sales = gross_sales − discounts − sales_reversals + taxes + duties + shipping + fees`。
- `sales_reversals` 涵蓋退貨品值＋取消＋訂單編輯＋運費/稅/費用/折扣調整（**不只退貨**）⇒ 資源命名鐵律見 86 §3.1：指標欄用 `sales_reversal*`／資源表用 `return*`，不可互換。
- **Total sales 可以是負數**（當日 reversal > 銷售）[G18]。
- Return fees（restocking＋return shipping）是獨立指標「你向顧客收的退貨費用」[G19]，不進 net_sales 減項側。
- Store credit 有兩張專屬報表：「Store credit transactions」與「Outstanding store credit balance」[G6]。
- 🔴 AOV 分子**刻意排除** post-order adjustments（退貨/換貨/編輯）＝本尊官方例外（80 §3、鐵律 7 註記）——實作 AOV 不得直接用 net_sales/orders。

---

## D. 關鍵流程

### D.1 買家自助退貨（self-serve）[G10][G11]

| 步 | 操作者 | 系統動作 | 事件 | 失敗分支 |
|---|---|---|---|---|
| 1 | 買家 | 訂單狀態頁登入（新版帳戶）→ 選已送達品項＋數量＋原因（分類原因庫，如服飾「Too big」）＋customerNote(≤300) | — | final sale／窗口過期／>250 行 ⇒ 前端擋 |
| 2 | 系統 | `returnRequest` → Return=REQUESTED；訂單卡片出現「Return requested」；解封存 | `returns/request`；商家通知信 | — |
| 3 | 商家 | Review request → **Approve**：選標籤（三選一：Shopify 產標籤〔US only〕／上傳 PDF/PNG/JPEG/URL＋追蹤碼／不需寄回）；可改費用、可加換貨品項 | `returns/approve`；核准信（附標籤） | — |
| 3' | 商家 | **Decline**：內部 reason 必選（FINAL_SALE/RETURN_PERIOD_ENDED/OTHER）＋給買家的自訂訊息 | `returns/decline`；拒絕信 | 拒絕後不可回 REQUESTED；品項可另建新退貨 |

### D.2 商家直建退貨＋換貨 [G3]

1. 訂單頁 → Return → 選品項數量＋原因 → Summary 可逐項編 restocking fee、編退貨運費（規則值為預設，可覆寫，覆寫寫 audit log）。
2. 「Add products」加換貨品項（限現有 variant；商品折扣可、訂單折扣禁）。
3. 選退貨運送方式（三選一同 D.1 步 3）→ Create return ⇒ Return=OPEN、建 RFO、換貨 FulfillmentOrder=ON_HOLD(AWAITING_RETURN_ITEMS)、換貨行加入訂單（銷售紀錄即建）。
4. 失敗分支：品項未送達 ⇒ returnableFulfillments 為空；quantity 超過可退量 ⇒ userError。

### D.3 收貨與處理（returnProcess）[G3][46a §4]

1. 商家在「Return items to receive」勾收到的品項 → 每項選 disposition（restock 則選 location）。
2. 「Exchange items to release」勾要釋出的換貨品項（解 hold）。
3. 財務段：`financialTransfer.issueRefund`（`orderTransactions[]` 必填＋`refundMethods[]` 可含 storeCreditRefund＋`allowOverRefunding`）[G14]；或選「Later」延後；買家欠款 ⇒ 寄 invoice/收款。可退運費。
4. 副作用：restock 走庫存調整（冪等 key **兩路**：本流程（returnProcess 收貨、財務段可選 Later）＝**return/RFO disposition line id**；退款路徑的 restock 才用 refund_line_item——步 3 可選 Later 時 Refund 可能尚不存在，單路鍵無鍵可用；兩路對同 disposition 單位**原子 claim**（INSERT guard 唯一鍵、成功者才動庫存——pre-check 不互斥），正典見總綱 T3 步驟表 <!-- 2026-08-17 更正（PR #52 第 5 輪；claim 原子化第 12 輪） -->）；`returns/process`＋`refunds/create`＋`reverse_fulfillment_orders/dispose` webhook；**全部品項處理完且全部 restock ⇒ Return 自動 CLOSED**。
5. 失敗分支：PSP 退款失敗 ⇒ 本地 pending 交易列＋告警＋可重試（同一把 idempotency key）；狀態不符（如已 CLOSED）⇒ `INVALID_STATE`。

### D.4 無退貨脈絡的退款（refundCreate）[46a §6][G8]

1. 退款面板：逐行數量（≤已購未退）→ restockType（未履行行用 CANCEL；已履行用 RETURN；不回補用 NO_RESTOCK）→ 運費欄 → notify。
2. **執行順序鐵則**：本地 transaction（refund＋lines＋transaction=pending＋restock＋outbox）→ transaction 外呼叫 PSP → webhook 確認 → pending→success → financial_status 重物化 → 通知信。先打 PSP 再落庫＝退了錢沒紀錄。
3. **退未履行品項 ⇒ 該品項從訂單移除、不可再履行** [G8]。
4. 分工：有 return 脈絡一律 `returnProcess`；無脈絡（取消補償、客訴）才 `refundCreate` [46a §6⑥]。

### D.5 退款到購物金 [G6][G7][G17]

1. 退款面板選目的地：`Original payment`／`Store credit`／兩者併用（三選一組合）[G3]。
2. 選 store credit ⇒ 可帶 `expiresAt` ⇒ 依訂單 presentment 幣別找 owner 的該幣別帳戶，無則自動開戶 ⇒ 寫 `credit` 交易。
3. 買家事後反悔 ⇒ over-refund 到原付款方式（需權限；**不回沖**先前的購物金）[G8]。

### D.6 取消退貨 [G3]

前置五條（B.1 T6）全部成立才可；效果＝銷售紀錄全數反轉、RFO 取消、換貨品項不動；**不可重開**，要重來只能另建。

---

## E. 跨模組耦合

### E.1 Webhook topics（本領域全集，2023-01+）[G12]

| Topic | 觸發 |
|---|---|
| `returns/request` | Return=REQUESTED |
| `returns/approve` | Return=OPEN（審核通過） |
| `returns/decline` | Return=DECLINED |
| `returns/cancel` | Return=CANCELED |
| `returns/close` | Return=CLOSED |
| `returns/reopen` | CLOSED→OPEN |
| `returns/process` | returnProcess 執行 |
| `returns/update` | 任何更新 |
| `refunds/create` | 退款建立，「independent from the movement of money」（金流未必已動） |
| `reverse_deliveries/attach_deliverable` | 退貨標籤/追蹤掛上 |
| `reverse_fulfillment_orders/dispose` | disposition 發生 |

### E.2 依賴方向

- **上游（本領域消費）**：Fulfillment/Delivery（「已送達」判定退貨資格）；Orders（line item、折扣分攤快照、captured/refunded 總額）；Customer accounts（self-serve 登入、store credit 兌換）；ReturnRules 設定。
- **下游（本領域發出）**：Inventory（restock 調整，冪等）；Payments/PSP（退款指令，走 65 §D 單位邊界）；Gift card（餘額回加/新發卡）；Store credit（credit/debit 交易）；Analytics（outbox 事件 → sales_reversals/returned_quantity rollup，記處理日）；Tax（**只發稅務事件**，憑證由 jurisdiction pack 決定——TW 折讓單在 tw pack，HK 無憑證，16 F5.5）；Notifications（三封 self-serve 信版型：確認/核准/拒絕 [G10]）。
- **互鎖**：active return ⇔ orderCancel 互斥；換貨 hold ⇔ fulfillment。

---

## F. 落地對應

### F.1 對應倉庫既有文檔

| 主題 | 既有檔 | 本章補充/修正 |
|---|---|---|
| Return/Refund 狀態機、mutation 面 | `docs/research/46a` §4/§5/§6 | 本章 §B 補 webhook 對映、declined 可再退、removeFromReturn 新名 |
| 退款公式/上限/併發/混合付款 | `docs/specs/16` F5.1–F5.4 | 一致；本章 §C.1–C.3 為摘要＋help 側證據 |
| Return 狀態機規格 | `docs/specs/16` F7.1–F7.6 | 一致 |
| returns vs sales_reversals 概念分界 | `docs/specs/86` | 一致；§C.10 引用其命名鐵律 |
| 退貨規則快照 | `docs/specs/16` F7.4 | help 證實「規則只對未來訂單生效」同向 [G9] |

**🔴 需回寫 46a 的修正一條**：46a §6② 寫 RestockType 為「`RESTOCK`／`NO_RESTOCK`／`LEGACY_RESTOCK`（3 值）」——2026-08-14 實抓 `RefundLineItemRestockType` 為 **4 值：`CANCEL`／`RETURN`／`NO_RESTOCK`／`LEGACY_RESTOCK`**，沒有叫 `RESTOCK` 的值 [G5]。CANCEL/RETURN 之分（未履行 vs 已履行）直接影響庫存回補語義與報表歸類，M4 schema 要用 4 值 enum。

### F.2 本尊 vs 我方裁定（差異清單，逐條）

| # | 主題 | 本尊 | 我方裁定 |
|---|---|---|---|
| 1 | 金額表示 | Decimal 字串＋MoneyBag 雙幣別 | **integer cents ×100 全幣別**（鐵律 3/65）；序列化層才轉 MoneyV2/MoneyBag；百分比用 basis points 整數 |
| 2 | restocking fee 型別 | `percentage: Float!` | `restocking_fee_bp: int (0–10000)`，float 不落地；上限官方未載 ⇒ 先以 100% 防呆（16 F5.3） |
| 3 | userErrors | 泛用 UserError 無 code（僅新 mutation 有 typed code） | **全 mutation 一律 typed code**（鐵律 4 加嚴，ours）；`INVALID_STATE` 為狀態機違規統一碼 |
| 4 | `maximumRefundable` | 存在但公式未公開 | **我方定義** `= captured − refunded`；軟上限＋over-refund 走條件式 UPDATE |
| 5 | `returnProcess` 冪等 | 未載明 | **強制 `idempotencyKey`**（鐵律 5），TTL 24h 對齊 refundCreate |
| 6 | 稅務憑證 | 內建於退款流程（美加稅制視角） | **只發稅務事件**，憑證落地交 jurisdiction pack（HK 無/TW 折讓/MY e-Invoice，鐵律 11） |
| 7 | 儲值（store credit/禮品卡） | 全球通用功能 | HK PSSVFO **單一用途豁免 ⇒ 不得跨租戶通用**（產品級硬限制，鐵律 11）；效期規則 per-jurisdiction |
| 8 | 關稅退款 | PROPORTIONAL/FULL（developer preview） | **M4 不做**，schema 預留 `refund_duties` |
| 9 | 分析欄名 | 2026-03 起 `returns`→`sales_reversals` 改名（11 組） | 一開始就用新名：指標 `sales_reversal*`／資源 `return*`（86 §3.1），無歷史包袱 |
| 10 | AOV | 官方例外：分子排除 post-order adjustments | 照抄本尊例外（80 §3），不與 net_sales 同源——是**裁定過的偏離「數字同源」直覺**的點 |
| 11 | refunds 表 | Refund 無 status | 照抄：**不建 `refunds.status`**，狀態看 transactions（16 F5-5） |
| 12 | 退款上限硬約束 | 允許 over-refund | **禁止 DB CHECK**；唯一硬約束 `refunded_total_cents >= 0`（16 F5.1(e)） |
| 13 | 幣別 | return shipping fee 必須 presentment 幣別 | 照抄＋DB 驗證 `return_shipping_fee_currency == orders.presentment_currency`（16 F5.3） |

### F.3 開發驗收要點（M4 測試清單增補）

1. **狀態機測試**：B.1 七條轉移逐條＋「REQUESTED 不可 cancel」「DECLINED/CANCELED 無出邊」「CLOSED 可 reopen」「處理完＋全 restock 自動 CLOSED」。
2. **restockType 語義**：CANCEL（未履行→移除＋回庫存）／RETURN（已履行→回庫存）／NO_RESTOCK；`LEGACY_RESTOCK` 建立時 reject。退未履行品項後該行不可再履行。
3. **金額矩陣**：JPY/TWD/KRW 必測（65 §H）；算例 1–3（16 F5.2）含換貨負值→`balance_to_collect`；restocking fee floor；退款 floor 0。
4. **併發**：C1（雙分頁同退）/C2（100 執行緒）/C3（與 capture 併發）；restock 冪等（webhook 重放不重複進貨）。
5. **雙重扣除**：換貨（有退貨無退款）不得進 sales_reversals 金額側；已付款取消/編輯的退款不得算兩次（86 §5 三形態）。
6. **禮品卡分配**：greedy 吃滿非比例攤；過期卡（改效期）與停用卡（新發卡）兩分支。
7. **Store credit**：整額使用、FEFO 扣款、跨幣別隔離、$15,000 上限、draft/edited order 拒用。
8. **Self-serve**：250 行上限、final sale 擋、窗口過期擋、換貨不可自助、customerNote 300／returnReasonNote 255。
9. **Webhook/outbox**：11 個 topic 全部由 outbox 發出，`refunds/create` 在金流確認前即發（對齊本尊語義「independent from the movement of money」）。
10. **互鎖**：active return ⇒ orderCancel 拒絕；returnCancel 五前置逐條。

---

## G. 來源

以下取證日期 2026-08-14（透過 WebFetch/WebSearch 實抓）；標「46a」者為倉庫 `docs/research/46a`（其原始取證 2026-08-11，本章引用時已對關鍵值域重新抽查）。

| # | URL | 內容 |
|---|---|---|
| G1 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ReturnStatus | Return 5 狀態（CANCELED 單 L）｜取證 2026-08-14 |
| G2 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Return | Return 欄位、mutation 清單、suggestedFinancialOutcome、declined 可再退｜取證 2026-08-14 |
| G3 | https://help.shopify.com/en/manual/fulfillment/managing-orders/returns/creating-returns | 建立/處理退貨與換貨、標籤三選一、自動關閉、取消五前置、退款目的地三選一｜取證 2026-08-14 |
| G4 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ExchangeLineItem | 換貨品項欄位與數量軸｜取證 2026-08-14 |
| G5 | https://shopify.dev/docs/api/admin-graphql/latest/enums/RefundLineItemRestockType | restock type 4 值窮舉｜取證 2026-08-14 |
| G6 | https://help.shopify.com/en/manual/customers/store-credit | 購物金：$15,000 上限、整額使用、FEFO、通路、B2B 限制、兩張報表｜取證 2026-08-14 |
| G7 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/storeCreditAccountCredit ＋ /objects/StoreCreditAccount | 帳戶模型、交易 4 型別、自動開戶、credit limit｜取證 2026-08-14 |
| G8 | https://help.shopify.com/en/manual/fulfillment/managing-orders/refunding-orders | 退款目的地、禮品卡優先、over-refund、退款不可逆、未履行品項移除、免運折扣不退運費、chargeback｜取證 2026-08-14 |
| G9 | https://help.shopify.com/en/manual/fulfillment/managing-orders/returns/return-rules | 退貨/取消規則全值域、final sale、只對未來訂單生效｜取證 2026-08-14 |
| G10 | https://help.shopify.com/en/manual/fulfillment/managing-orders/returns/self-serve-returns/setup | self-serve 前提、資格、250 行上限、三封信版型｜取證 2026-08-14 |
| G11 | https://help.shopify.com/en/manual/fulfillment/managing-orders/returns/self-serve-returns/management | 審核流程、decline reason 內部限定、取消請求 resolve/decline｜取證 2026-08-14 |
| G12 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic | 本領域 11 個 webhook topic 逐字｜取證 2026-08-14 |
| G13 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnProcessFinancialTransferInput | financialTransfer.issueRefund｜取證 2026-08-14 |
| G14 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnProcessRefundInput ＋ /RefundMethodInput ＋ /StoreCreditRefundInput | allowOverRefunding default false、refundMethods、store credit amount+expiresAt｜取證 2026-08-14 |
| G15 | https://help.shopify.com/en/manual/products/gift-card-products/manage-purchased-gift-cards | 過期卡改效期再退、停用卡另發新卡｜取證 2026-08-14 |
| G16 | https://shopify.dev/docs/api/admin-graphql/latest/input-objects/ReturnRequestLineItemInput | customerNote ≤300、fulfillmentLineItemId｜取證 2026-08-14 |
| G17 | https://help.shopify.com（store credit 檢索摘要：refund-to-store-credit 可設效期、時區規則） | 取證 2026-08-14 |
| G18 | https://help.shopify.com/en/manual/reports-and-analytics/discrepancies/sales-discrepancies | 正負值記帳日、total sales 可為負、reversal 定義｜取證 2026-08-14 |
| G19 | https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/sales-report | gross/net/total sales 公式、return fees 指標、處理日記帳｜取證 2026-08-14 |
| 46a | `docs/research/46a-shopify-docs-orders-returns.md` | ReturnErrorCode 26 值、ReturnReason 10 值、ReturnDeclineReason 3 值、RFO/disposition、冪等總則、orderCancel 互鎖（原始取證 2026-08-11） |

### ⚠️ 官方未載明（不得腦補成事實）

1. 退貨窗口 fallback（出貨日＋轉運 buffer）的 **buffer 天數**。
2. `RestockingFeeInput.percentage` 的**最大值**。
3. `maximumRefundable` 的**官方公式**（我方定義 = captured − refunded）。
4. 退款時的**稅額分攤規則**（我方 X1–X6 為本專案定義）。
5. `returnProcess` 的**冪等保證**（我方自行強制）。
6. `RefundShippingInput.amount` 與 `fullRefund` **同時給**的行為。
7. store credit **各幣別的 credit limit 具體值**（僅知 USD $15,000 與「currency-specific limits」存在）。
8. 買家能否**自行撤回** self-serve 請求。
9. 純退貨費用超過品項價值時**是否產生應收**（我方裁定：不自動產生）。
