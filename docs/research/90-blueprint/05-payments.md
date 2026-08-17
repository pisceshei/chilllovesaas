# 05. 支付與交易（Transactions / Capture / Payouts / 多幣別）

> 官方文檔考掘（shopify.dev Admin GraphQL latest ＋ help.shopify.com），取證日期一律 2026-08-14。
> 定位：本章是 `docs/research/04` §2 的深化——04 號只有一段話的 OrderTransaction 模型，本章把值域、
> 狀態機、計算公式、payout／dispute／多幣別全部抄全。與我方裁定的差異集中在 §F。
> ⚠ 標記＝官方文檔查不到或有歧義，對應 openQuestions；**未標 ⚠ 的斷言均有 §G 來源**。

---

## A. 領域物件模型

### A.1 物件關係總圖（cardinality）

```
Order 1 ──< N OrderTransaction          （交易事件流，append-only）
OrderTransaction 0..1 ──< N OrderTransaction   （parentTransaction 自關聯：capture→auth、refund→capture/sale、void→auth）
Order 0..1 ──< N ShopifyPaymentsDispute （一單可多爭議；dispute 也可無 order 關聯——order 欄位 nullable）
ShopifyPaymentsDispute 1 ── 1 ShopifyPaymentsDisputeEvidence
ShopifyPaymentsPayout 1 ──< N ShopifyPaymentsBalanceTransaction （balance txn 經 associatedPayout 歸屬）
ShopifyPaymentsBalanceTransaction 0..1 ── ShopifyPaymentsAssociatedOrder
Refund 1 ──< N OrderTransaction(kind=REFUND) （退款單聚合退款交易）
```

### A.2 OrderTransaction（交易事件，核心物件）

單一交易事件，**不可變**：授權、請款、退款各是一筆新紀錄，靠 `parentTransaction` 串鏈。

| 欄位 | 型別 | 語義 |
|---|---|---|
| `id` | ID! | GID |
| `kind` | OrderTransactionKind! | 交易種類（§A.3） |
| `status` | OrderTransactionStatus! | 交易結果（§A.4） |
| `amountSet` | MoneyBag! | 金額，**shop ＋ presentment 雙幣別**（§A.9） |
| `amountRoundingSet` | MoneyBag | 現金交易的湊整調整額（POS cash rounding） |
| `parentTransaction` | OrderTransaction | 父交易（capture 的父＝authorization 等） |
| `order` | Order | 所屬訂單 |
| `gateway` | String | 通道機器名（如 `shopify_payments`、`manual`、`bogus`） |
| `formattedGateway` | String | 通道顯示名 |
| `manualPaymentGateway` | Boolean! | 是否為 manual payment 通道 |
| `test` | Boolean! | 是否測試交易 |
| `processedAt` | DateTime | 交易處理時間 |
| `createdAt` | DateTime! | 建立時間 |
| `authorizationExpiresAt` | DateTime | 授權失效時點（**官方標注僅 Plus 店可讀**） |
| `manuallyCapturable` | Boolean! | 是否可手動 capture |
| `multiCapturable` | Boolean! | 是否可多次 capture |
| `totalUnsettledSet` | MoneyBag | 原授權尚未請款的餘額（雙幣別） |
| `maximumRefundableV2` | MoneyV2 | 通道側可退上限（用於 SuggestedRefund） |
| `errorCode` | OrderTransactionErrorCode | 標準化錯誤碼，**與通道無關**（§A.5） |
| `receiptJson` | JSON | 通道原始回執（**通道自定形狀，非穩定契約**） |
| `fees` | [TransactionFee!] | 手續費明細（**僅 Shopify Payments 有值**） |
| `paymentId` | String | 收單側 payment 識別碼 |
| `accountNumber` | String | 遮罩後帳號／卡號 |
| `paymentDetails` | PaymentDetails | 卡別／錢包細節 union |
| `paymentIcon` | Image | 付款方式 icon |
| `settlementCurrency` | CurrencyCode | 結算幣別 |
| `settlementCurrencyRate` | Decimal | 交易金額 → 結算幣別的匯率 |
| `currencyExchangeAdjustment` | CurrencyExchangeAdjustment | 匯率波動造成的損益調整（退款時） |
| `shopifyPaymentsSet` | ShopifyPaymentsTransactionSet | SP 專屬資訊（官方標注僅 Plus） |
| `location` / `device` / `user` | Location / PointOfSaleDevice / StaffMember | POS 情境：門市／裝置／操作店員 |

### A.3 OrderTransactionKind（值域窮舉，8 值）

| 值 | 語義 | 父交易 |
|---|---|---|
| `AUTHORIZATION` | 對持卡人資金來源的圈存；capture 前錢不換手 | — |
| `CAPTURE` | 把授權圈存的錢轉走（請款） | AUTHORIZATION |
| `SALE` | 授權＋請款一步完成 | — |
| `VOID` | 取消一筆授權 | AUTHORIZATION（未 capture） |
| `REFUND` | 把已 capture 的錢部分/全額退回；**只能發生在 capture 之後** | CAPTURE 或 SALE |
| `CHANGE` | POS 現金交易找零（顧客多付的退還） | — |
| `EMV_AUTHORIZATION` | EMV 讀卡機（POS 實體卡）授權 | — |
| `SUGGESTED_REFUND` | 建議退款交易，**用於產生退款的計算結果**（`suggestedRefund` 回傳），⚠ 非落庫事件 | — |

### A.4 OrderTransactionStatus（值域窮舉，6 值）

| 值 | 語義 |
|---|---|
| `PENDING` | 處理中（通道尚未回定論；manual payment 的初始態） |
| `SUCCESS` | 成功 |
| `FAILURE` | 失敗（業務性拒絕：卡拒付等） |
| `ERROR` | 處理過程出錯（技術性錯誤） |
| `AWAITING_RESPONSE` | 等待回應（⚠ 官方描述僅一句「Awaiting a response.」；依 offsite/3DS 流程推斷為等待外部認證/跳轉回來，未見明文）；超時收斂裁定見 §B.1.1-R1 |
| `UNKNOWN` | 狀態不明（官方描述僅「The transaction status is unknown.」）；**非終態**，收斂裁定見 §B.1.1-R2 |

### A.5 OrderTransactionErrorCode（值域窮舉，47 值）

通道無關的標準化錯誤碼。分組列全：

- **卡片資料錯**：`INCORRECT_NUMBER`／`INVALID_NUMBER`／`INCORRECT_CVC`／`INVALID_CVC`／`INVALID_EXPIRY_DATE`／`EXPIRED_CARD`／`INCORRECT_PIN`／`INCORRECT_ZIP`／`INCORRECT_ADDRESS`
- **拒付類**：`CARD_DECLINED`／`INSUFFICIENT_FUNDS`／`DO_NOT_HONOR`（發卡行拒絕未給原因）／`CALL_ISSUER`（請顧客聯繫發卡行）／`PICK_UP_CARD`（卡已掛失/被盜，發卡行要求扣卡）／`INSTRUMENT_DECLINED`／`RETRY_DECLINED`
- **風控類**：`FRAUD_SUSPECTED`／`CARD_TESTING`（疑似測卡攻擊）／`MERCHANT_RULE`（商家自訂風控規則攔截）
- **3DS 類**：`AUTHENTICATION_FAILED`（3DS 驗證失敗）／`AUTHENTICATION_REQUIRED`（需要 3DS 但未帶驗證嘗試扣款）
- **金額類**：`AMOUNT_TOO_LARGE`／`AMOUNT_TOO_SMALL`／`INVALID_AMOUNT`／`TRANSACTION_LIMIT_EXCEEDED`（頻率上限）
- **授權生命週期**：`AUTHORIZATION_EXPIRED`／`CANCELLED_PAYMENT`
- **配置/通道類**：`CONFIG_ERROR`／`MERCHANT_ACCOUNT_ERROR`／`PAYMENT_PROVIDER_ERROR`／`PROCESSING_ERROR`／`GENERIC_ERROR`／`TEST_MODE_LIVE_CARD`（測試模式收到真卡）／`UNSUPPORTED_FEATURE`
- **付款方式類**：`INVALID_PAYMENT_METHOD`／`PAYMENT_METHOD_UNAVAILABLE`（暫時不可用）／`PAYMENT_METHOD_UNSUPPORTED`／`INVALID_COUNTRY`／`INVALID_CURRENCY`／`INVALID_PURCHASE_TYPE`
- **Amazon Pay 專屬**（7 值）：`AMAZON_PAYMENTS_INVALID_PAYMENT_METHOD`／`AMAZON_PAYMENTS_MAX_AMOUNT_CHARGED`／`AMAZON_PAYMENTS_MAX_AMOUNT_REFUNDED`／`AMAZON_PAYMENTS_MAX_AUTHORIZATIONS_CAPTURED`（一單最多 capture 10 筆授權）／`AMAZON_PAYMENTS_MAX_REFUNDS_PROCESSED`（一單最多 10 筆退款）／`AMAZON_PAYMENTS_ORDER_REFERENCE_CANCELED`／`AMAZON_PAYMENTS_STALE`（3 小時內未確認）

### A.6 Order.displayFinancialStatus（值域窮舉，8 值）

| 值 | 語義 |
|---|---|
| `PENDING` | 通道還在處理、或 manual payment 未收款 |
| `AUTHORIZED` | 已授權未請款（**只出現在手動 capture 模式**） |
| `PARTIALLY_PAID` | 手動 capture 了小於全額的金額 |
| `PAID` | 已全額請款（自動/手動/mark as paid） |
| `PARTIALLY_REFUNDED` | 退款額 < 已付額 |
| `REFUNDED` | 已全額退款 |
| `VOIDED` | 授權未請款即作廢，圈存釋放（**是付款的狀態，訂單本身可仍 open**） |
| `EXPIRED` | 授權逾期未 capture（部分通道也用它表示付款處理失敗） |

### A.7 Payouts（Shopify Payments 撥款）

**ShopifyPaymentsPayout**：`id`、`legacyResourceId`、`issuedAt`（發起時點；payout 只含該時點已 available 的 balance transactions）、`net`（MoneyV2，撥款淨額）、`status`（§B.4）、`summary`（ShopifyPaymentsPayoutSummary：按交易類型拆 gross／fee）、`transactionType`（撥款方向：**deposit｜withdrawal**）、`externalTraceId`（銀行端追蹤參考號）、`businessEntity`；deprecated：`bankAccount`、`gross`。

**ShopifyPaymentsBalanceTransaction**（對帳的原子單位）：`amount`／`fee`／`net`（MoneyV2 三元組，`net = amount − fee`）、`sourceType`、`type`、`transactionDate`、`associatedPayout`、`associatedOrder`、`adjustmentReason`（僅 adjustment 類有值）、`test`。

**ShopifyPaymentsSourceType（值域窮舉，7 值）**：`CHARGE`／`REFUND`／`DISPUTE`／`ADJUSTMENT`／`ADJUSTMENT_REVERSAL`／`SYSTEM_ADJUSTMENT`／`TRANSFER`。

**ShopifyPaymentsTransactionType（值域窮舉，113 值）**——收款核心子集：`CHARGE`／`CHARGE_ADJUSTMENT`／`REFUND`／`REFUND_ADJUSTMENT`／`REFUND_FAILURE`／`ADJUSTMENT`／`TRANSFER`／`TRANSFER_CANCEL`／`TRANSFER_FAILURE`／`TRANSFER_REFUND`／`CHARGEBACK_FEE`／`CHARGEBACK_FEE_REFUND`／`CHARGEBACK_HOLD`／`CHARGEBACK_HOLD_RELEASE`／`DISPUTE_REVERSAL`／`DISPUTE_WITHDRAWAL`／`RESERVED_FUNDS`／`RESERVED_FUNDS_REVERSAL`／`RESERVED_FUNDS_WITHDRAWAL`／`RISK_REVERSAL`／`RISK_WITHDRAWAL`／`STRIPE_FEE`。其餘 91 值為平台金融產品與通路生態（G15 邊界外），**逐字全錄如下、無任何縮寫**——F.3-1 的 enum CI 快照＝本清單＋上列 22 值核心子集，合計 113 值。先前草稿以 `LENDING_*(10)`／`SHOP_CASH_*(8)` 萬用字元壓縮，2026-08-14 對 API 頁逐值重數，實為 **LENDING 12 值、SHOP_CASH 10 值**——壓縮寫法連計數都藏錯，故廢止（G11）：

- **A–B（15 值）**：`ACH_BANK_FAILURE_DEBIT_FEE`、`ACH_BANK_FAILURE_DEBIT_REVERSAL_FEE`、`ADS_PUBLISHER_CREDIT`、`ADS_PUBLISHER_CREDIT_REVERSAL`、`ADVANCE`、`ADVANCE_FUNDING`、`ANOMALY_CREDIT`、`ANOMALY_CREDIT_REVERSAL`、`ANOMALY_DEBIT`、`ANOMALY_DEBIT_REVERSAL`、`APPLICATION_FEE_REFUND`、`BALANCE_TRANSFER_INBOUND`、`BALANCE_TRANSFER_OUTBOUND`、`BILLING_DEBIT`、`BILLING_DEBIT_REVERSAL`
- **C（16 值）**：`CHANNEL_CREDIT`、`CHANNEL_CREDIT_REVERSAL`、`CHANNEL_PROMOTION_CREDIT`、`CHANNEL_PROMOTION_CREDIT_REVERSAL`、`CHANNEL_TRANSFER_CREDIT`、`CHANNEL_TRANSFER_CREDIT_REVERSAL`、`CHANNEL_TRANSFER_DEBIT`、`CHANNEL_TRANSFER_DEBIT_REVERSAL`、`CHARGEBACK_PROTECTION_CREDIT`、`CHARGEBACK_PROTECTION_CREDIT_REVERSAL`、`CHARGEBACK_PROTECTION_DEBIT`、`CHARGEBACK_PROTECTION_DEBIT_REVERSAL`、`COLLECTIONS_CREDIT`、`COLLECTIONS_CREDIT_REVERSAL`、`CUSTOMS_DUTY`、`CUSTOMS_DUTY_ADJUSTMENT`
- **I–L（15 值）**：`IMPORT_TAX`、`IMPORT_TAX_ADJUSTMENT`、`IMPORT_TAX_REFUND`、`LENDING_CAPITAL_REFUND`、`LENDING_CAPITAL_REFUND_REVERSAL`、`LENDING_CAPITAL_REMITTANCE`、`LENDING_CAPITAL_REMITTANCE_REVERSAL`、`LENDING_CREDIT`、`LENDING_CREDIT_REFUND`、`LENDING_CREDIT_REFUND_REVERSAL`、`LENDING_CREDIT_REMITTANCE`、`LENDING_CREDIT_REMITTANCE_REVERSAL`、`LENDING_CREDIT_REVERSAL`、`LENDING_DEBIT`、`LENDING_DEBIT_REVERSAL`
- **M–R（13 值）**：`MARKETPLACE_FEE_CREDIT`、`MARKETPLACE_FEE_CREDIT_REVERSAL`、`MARKETS_PRO_CREDIT`、`MERCHANT_GOODWILL_CREDIT`、`MERCHANT_GOODWILL_CREDIT_REVERSAL`、`MERCHANT_TO_MERCHANT_CREDIT`、`MERCHANT_TO_MERCHANT_CREDIT_REVERSAL`、`MERCHANT_TO_MERCHANT_DEBIT`、`MERCHANT_TO_MERCHANT_DEBIT_REVERSAL`、`PROMOTION_CREDIT`、`PROMOTION_CREDIT_REVERSAL`、`REFERRAL_FEE`、`REFERRAL_FEE_TAX`
- **S（26 值）**：`SELLER_PROTECTION_CREDIT`、`SELLER_PROTECTION_CREDIT_REVERSAL`、`SHIPPING_LABEL`、`SHIPPING_LABEL_ADJUSTMENT`、`SHIPPING_LABEL_ADJUSTMENT_BASE`、`SHIPPING_LABEL_ADJUSTMENT_SURCHARGE`、`SHIPPING_OTHER_CARRIER_CHARGE_ADJUSTMENT`、`SHIPPING_RETURN_TO_ORIGIN_ADJUSTMENT`、`SHOP_CASH_BILLING_DEBIT`、`SHOP_CASH_BILLING_DEBIT_REVERSAL`、`SHOP_CASH_CAMPAIGN_BILLING_CREDIT`、`SHOP_CASH_CAMPAIGN_BILLING_CREDIT_REVERSAL`、`SHOP_CASH_CAMPAIGN_BILLING_DEBIT`、`SHOP_CASH_CAMPAIGN_BILLING_DEBIT_REVERSAL`、`SHOP_CASH_CREDIT`、`SHOP_CASH_CREDIT_REVERSAL`、`SHOP_CASH_REFUND_DEBIT`、`SHOP_CASH_REFUND_DEBIT_REVERSAL`、`SHOPIFY_COLLECTIVE_CREDIT`、`SHOPIFY_COLLECTIVE_CREDIT_REVERSAL`、`SHOPIFY_COLLECTIVE_DEBIT`、`SHOPIFY_COLLECTIVE_DEBIT_REVERSAL`、`SHOPIFY_SOURCE_CREDIT`、`SHOPIFY_SOURCE_CREDIT_REVERSAL`、`SHOPIFY_SOURCE_DEBIT`、`SHOPIFY_SOURCE_DEBIT_REVERSAL`
- **T–V（6 值）**：`TAX_ADJUSTMENT_CREDIT`、`TAX_ADJUSTMENT_CREDIT_REVERSAL`、`TAX_ADJUSTMENT_DEBIT`、`TAX_ADJUSTMENT_DEBIT_REVERSAL`、`VAT_REFUND_CREDIT`、`VAT_REFUND_CREDIT_REVERSAL`

### A.8 Disputes（爭議/拒付）

**ShopifyPaymentsDispute**：`id`、`legacyResourceId`、`amount`（MoneyV2，被爭議總額）、`order`（nullable）、`type`（§下）、`status`（§B.5）、`reasonDetails`（ShopifyPaymentsDisputeReasonDetails!）、`disputeEvidence`（ShopifyPaymentsDisputeEvidence!）、`initiatedAt`、`evidenceDueBy`（證據截止）、`evidenceSentOn`（null＝未送）、`finalizedOn`（null＝未結案）。

**DisputeType（2 值）**：`INQUIRY`（查詢階段）｜`CHARGEBACK`（已成拒付）。

**ShopifyPaymentsDisputeReason（值域窮舉，14 值）**：`FRAUDULENT`（持卡人稱未授權）／`UNRECOGNIZED`（帳單上不認得）／`DUPLICATE`（重複扣款）／`SUBSCRIPTION_CANCELLED`（取消訂閱後仍被扣）／`PRODUCT_NOT_RECEIVED`／`PRODUCT_UNACCEPTABLE`（瑕疵/與描述不符）／`CREDIT_NOT_PROCESSED`（退貨/取消但未退款）／`GENERAL`（未分類）／`CUSTOMER_INITIATED`／`INCORRECT_ACCOUNT_DETAILS`／`INSUFFICIENT_FUNDS`／`BANK_CANNOT_PROCESS`／`DEBIT_NOT_AUTHORIZED`／`NONCOMPLIANT`（發卡方認定違反卡組織規則）。

### A.9 多幣別金額（MoneyBag）

- **shop currency**＝店定價/報表主幣別；**presentment currency**＝買家結帳幣別；訂單/交易所有金額欄以 `MoneyBag{shopMoney, presentmentMoney}` 雙記。
- 未啟多幣別時 presentment＝shop，兩值相同。
- **payout currency** 是第三個幣別軸：SP 結算入帳的幣別（§C.6 Multi-Currency Payouts）。

---

## B. 狀態機

### B.1 單筆 OrderTransaction.status（事件級）

交易紀錄**建立後 kind 不變**，status 由通道回報收斂：

| 現態 | 觸發 | 次態 | 副作用 |
|---|---|---|---|
| （建立） | 送通道 | PENDING | — |
| PENDING | 通道成功回報 | SUCCESS | 依 kind 推進付款生命週期（B.2）與 financial status（B.3） |
| PENDING | 通道業務拒絕 | FAILURE | 寫 `errorCode`；金額不生效 |
| PENDING | 技術錯誤 | ERROR | 寫 `errorCode` |
| （建立） | 需外部認證/跳轉（offsite、3DS） | AWAITING_RESPONSE | 等待買家完成認證 ⚠（官方描述僅一句，見 A.4） |
| AWAITING_RESPONSE | 買家完成認證，通道回終局 | SUCCESS／FAILURE | 正常出口 |
| AWAITING_RESPONSE | 超時（我方裁定值，B.1.1-R1） | 先查 PSP 實況：有終局 ⇒ 照落 SUCCESS／FAILURE；明確拒絕 ⇒ FAILURE；查無／無終局 ⇒ UNKNOWN（進 R2 收斂）（本列＝R1 的表格投影，隨 R1 第 18 輪更正同改） | ⚠ 本尊的超時次態與時長官方均未明文，待實測；相鄰官方錨點與我方裁定見 B.1.1 |
| PENDING／AWAITING_RESPONSE（僅非終態） | 通道無法判定 | UNKNOWN | **非終態**；由 reconcile job 收斂（B.1.1-R2），官方無自動轉移。（2026-08-17 更正，PR #52 第 18 輪）：原現態「（任意）」含 SUCCESS/FAILURE/ERROR——終態宣告即不可變，晚到的模糊 PSP 回應／對帳錯誤不得把已成功付款拉回 UNKNOWN（訂單投影會丟失已付結果）；終態寫入一律條件式（現態仍非終態才寫） |
| UNKNOWN | reconcile job 查得 PSP 終局 | SUCCESS／FAILURE／ERROR | 收斂出口 |
| UNKNOWN | 逾放棄期限仍無終局（B.1.1-R2） | （維持 UNKNOWN＋ops alert） | 轉人工對帳；訂單級 financial status 依 pending 過期規則 → EXPIRED（B.1.1） |

#### B.1.1 AWAITING_RESPONSE／UNKNOWN 收斂：官方錨點＋我方裁定

官方在 OrderTransactionStatus 層級**沒有**任何超時/收斂明文（G3 全頁僅六句 enum 描述）。可查得的相鄰錨點有兩個，皆非交易狀態本體：

1. **訂單級 pending payment 有過期日**：「典型約一週」（"typically a week"），逾期 payment status → **EXPIRED**；付款失敗時官方行為＝寄「Pay now」重試信給買家、訂單續掛 pending；pending 期間**鎖單**（不可編修 items/折扣/地址、不可 restock、不可取消、不可手動收款、不可 mark as paid）。（G23）（🔴 鎖範圍＝**存在未決 PSP 交易**的 pending；manual 單（COD/轉帳/payment terms）不鎖 `orderMarkAsPaid`/收款——§05 C.12 靠它結清，2026-08-17 更正（PR #52 第 7 輪））
2. **Payments Apps 的 pending 流程**：`paymentSessionPending.pendingExpiresAt` 官方建議設在 **3 天內**；pending 最終必須由 `paymentSessionResolve`／`paymentSessionReject` 終局化——**逾期後有無自動轉移，官方未載**。（G24）

⚠ AWAITING_RESPONSE 超時後轉 FAILURE 還是 UNKNOWN、超時多長，官方未明文，待實測（測試店造 offsite/3DS 中斷單觀察）。以下為**我方裁定**（防孤兒態；所有時間值引 `config/limits.yml`，鐵律 6，不得硬編）：

- **R1（AWAITING_RESPONSE 超時）**：超時上限 `payment.awaiting_response_timeout`（預設 3 天，對齊 G24 官方建議值）。超時**先向 PSP 查詢實況**：查得終局 ⇒ 照落 SUCCESS/FAILURE；**PSP 明確拒絕 ⇒ FAILURE**（`errorCode=PAYMENT_PROVIDER_ERROR`，§A.5 既有值，不新造）；**查無此交易或無終局 ⇒ 轉 UNKNOWN 進 R2 收斂**——僅明確拒絕可落終態 FAILURE，非終局不得落 FAILURE：PSP 之後仍可能結清成功，落 FAILURE 即離開對帳路徑，買家重試新 attempt＝雙收、晚到的成功扣款掛在被視為未付的訂單上（（2026-08-17 更正，PR #52 第 18 輪）：原文「查無 ⇒ FAILURE、不轉 UNKNOWN」即此形；孤兒防護由 R2 的放棄期限＋ops alert＋EXPIRED 投影承擔，不靠提前判死）。
- **R2（UNKNOWN reconcile job）**：指數退避輪詢 PSP 查交易實況（首查間隔與退避曲線引 `payment.reconcile_backoff`，預設 15 分鐘起、退避至每日一次）；**收斂目標態＝SUCCESS／FAILURE／ERROR 三者之一**；放棄期限 `payment.reconcile_give_up`（預設 7 天，對齊 G23「典型約一週」口徑）——逾期仍無終局 ⇒ 維持 UNKNOWN＋發 ops alert 轉人工對帳，訂單級 financial status 依 G23 規則轉 EXPIRED。資金狀態不得永久懸置在無人看管的掛單。
- **R3（併發約束）**：兩個收斂 job 必須冪等（鐵律 5），且與 capture/void 共用授權列行鎖（C.13-2 同鎖）——收斂寫入與人工操作競態時，後者以資料庫現況重讀為準。

### B.2 付款生命週期（kind 鏈，訂單付款級）

```
              ┌─ orderCapture（可多次）──> CAPTURE ──┬─ refund ──> REFUND（可多次，Σ ≤ captured）
AUTHORIZATION ┤                                      └─（finalCapture 或額度用盡）授權關閉
   (SUCCESS)  ├─ transactionVoid ─────────> VOID（僅未 capture 的授權）
              └─ 逾 authorizationExpiresAt ─> 授權失效（無新交易，financial status → EXPIRED）
SALE (auth+capture 一步) ────────────────────────────> REFUND（可多次，Σ ≤ sale 額）
```

轉移表：

| 動作 | 前置條件 | 產生交易 | 副作用 |
|---|---|---|---|
| checkout（自動 capture 模式） | 付款授權成功 | SALE | financial status → PAID |
| checkout（手動/出貨時 capture 模式） | 授權成功 | AUTHORIZATION | financial status → AUTHORIZED；起算授權期 |
| `orderCapture` | 有 SUCCESS 授權且未逾期；amount ≤ totalUnsettled；多幣別單必帶 currency＝presentment 幣別 | CAPTURE（parent＝該授權） | totalUnsettledSet 遞減；全額→PAID、部分→PARTIALLY_PAID；`finalCapture:true` 關閉授權、不得再 capture |
| 再次 `orderCapture` | `multiCapturable=true`（SP 需 Plus；第三方需通道支援） | 第 2..n 筆 CAPTURE | 同上 |
| `transactionVoid` | parent 為**未 capture** 的授權 | VOID | 圈存釋放；financial status → VOIDED |
| 授權逾期 | 過 authorizationExpiresAt 未 capture | （無） | financial status → EXPIRED；款項收不到 |
| `refundCreate` | 已有 CAPTURE/SALE；Σrefund ≤ maximumRefundable | REFUND（parent＝capture/sale，**建立時 pending**） | financial status 投影**待 REFUND 交易 SUCCESS 後**重算 → PARTIALLY_REFUNDED／REFUNDED——SUCCESS 出口分目的地：**外部金流形＝PSP webhook 確認；內部目的地形（禮品卡餘額／store credit／manual 線下）＝同一本地 transaction 內即 SUCCESS**（R-11；第 21 輪分支——單一 webhook 出口會讓無 PSP 的退款投影永卡）（R-11／§06 D.4——本地建立即改投影＝PSP 拒絕時謊稱錢已退；總綱耦合列第 18 輪修、本列第 19 輪同步；`refunds/create` 於建立即發不變）；退款**不可撤銷** |
| `orderMarkAsPaid` | `canMarkAsPaid=true`；有正的未收餘額；非已 PAID | 有待授權→CAPTURE；否則 SALE，`gateway=manual`、status SUCCESS | financial status → PAID |

**無孤兒驗證**：AUTHORIZATION 的三個出口＝CAPTURE／VOID／逾期 EXPIRED；CAPTURE 與 SALE 的出口＝REFUND 或自然終結（全額保留）；VOID、REFUND、EXPIRED 為終態；CHANGE／EMV_AUTHORIZATION 為 POS 情境事件（CHANGE 是現金找零終態、EMV_AUTHORIZATION 等價 AUTHORIZATION 入口）；SUGGESTED_REFUND 不落庫、無狀態。

### B.3 Order.displayFinancialStatus（訂單付款彙總級）

| 現態 | 觸發 | 次態 |
|---|---|---|
| PENDING | manual payment 收款人工確認（mark as paid）／通道完成處理 | PAID |
| PENDING | 通道回報付款失敗 | （不轉態）官方明文行為＝寄「Pay now」重試信給買家、訂單續掛 PENDING 至過期（G23）；⚠ 有無直接轉態路徑官方未明文 |
| PENDING | 逾 pending 過期日（典型約一週，通道側值、非我方可設） | EXPIRED（G23 明文；即 A.6「部分通道以 EXPIRED 表處理失敗」的官方出處） |
| AUTHORIZED | 全額 capture | PAID |
| AUTHORIZED | 部分 capture | PARTIALLY_PAID |
| AUTHORIZED | void | VOIDED（終態；訂單可仍 open） |
| AUTHORIZED | 授權逾期 | EXPIRED（終態） |
| PARTIALLY_PAID | 補足 capture（multi-capture） | PAID |
| PAID／PARTIALLY_PAID | 部分退款 | PARTIALLY_REFUNDED |
| PARTIALLY_REFUNDED | 退到全額 | REFUNDED（終態） |
| PAID | 全額退款 | REFUNDED（終態） |

註：PENDING 期間官方明文鎖單（不可編修 items/折扣/地址、不可 restock、不可取消、不可手動收款、不可 mark as paid，G23）——我方**未決 PSP 交易形**的 pending 單必須同鎖，否則 pending→EXPIRED 與訂單編修會產生金額競態；manual 單（COD/轉帳/payment terms）**不鎖** `orderMarkAsPaid`/收款（§05 C.12 靠它結清 2026-08-17 更正（PR #52 第 7 輪））。

### B.4 ShopifyPaymentsPayoutStatus（撥款）

值域窮舉（5 值，含 1 deprecated）：

| 現態 | 觸發 | 次態 | 語義／副作用 |
|---|---|---|---|
| SCHEDULED | payout 生成、balance txn 已歸戶，尚未送銀行 | → PAID／FAILED／CANCELED | 起點 |
| SCHEDULED | 送銀行入帳成功 | PAID | 終態 |
| SCHEDULED | 銀行拒絕（帳戶資料錯/不符） | FAILED | 商家須依通知修正帳戶資料，否則後續撥款停擺 |
| SCHEDULED | Shopify 取消該筆撥款 | CANCELED | 終態 |
| `IN_TRANSIT` | — | — | **API 已標 deprecated**；⚠ help 端（73 §7.3 實測）撥款詳情仍呈現「已排程/已存入/失敗/已提款」四值 UI，與 API enum 對映關係未有官方對照頁 |

### B.5 DisputeStatus（爭議）

值域窮舉（7 值，含 1 deprecated）：`NEEDS_RESPONSE`／`UNDER_REVIEW`／`ACCEPTED`／`WON`／`LOST`／`PREVENTED`／`CHARGE_REFUNDED`（deprecated）。

| 現態 | 觸發 | 次態 | 副作用 |
|---|---|---|---|
| （發起，type=INQUIRY） | 買家向銀行質疑 | NEEDS_RESPONSE | **不先扣款、不先收費**；商家可直接退款終結 |
| INQUIRY: NEEDS_RESPONSE | 商家全額退款 | 終結（不升級） | 買家拿回錢；⚠ 對應終態 enum 未明文（deprecated 的 CHARGE_REFUNDED 疑即此形態） |
| INQUIRY: NEEDS_RESPONSE | 買家/銀行不滿意 | 升級為 type=CHARGEBACK | 進入下行 |
| （發起，type=CHARGEBACK） | 銀行立案 | NEEDS_RESPONSE | **立即從下一次可用 payout 扣走爭議額＋chargeback fee**（balance txn：`CHARGEBACK_HOLD`＋`CHARGEBACK_FEE`）；設 `evidenceDueBy`（立案後 7–21 天，依卡組織） |
| NEEDS_RESPONSE | 到 `evidenceDueBy`：Shopify 自動彙整可得證據代送（商家可在截止前隨時增改；**送出後不可再改**） | UNDER_REVIEW | `evidenceSentOn` 落值 |
| NEEDS_RESPONSE | 商家主動接受爭議 | ACCEPTED（終態） | 爭議額歸持卡人 |
| UNDER_REVIEW | 發卡方裁定（chargeback 審最長 75 天；inquiry 通常 65–75 天；全程約 65–120 天） | WON／LOST（終態） | WON：爭議額＋fee 於下一次 payout 退還（`CHARGEBACK_HOLD_RELEASE`＋`CHARGEBACK_FEE_REFUND`）；LOST：扣款成立。**裁定為終局，不可上訴** |
| （任一非終態） | 卡組織爭議預防程序攔下 | PREVENTED（終態） | 未成正式 chargeback，無證據視窗 |

孤兒檢查：全部狀態可達且可出；終態＝ACCEPTED／WON／LOST／PREVENTED。

---

## C. 業務規則與不變量

### C.1 授權期與逾期請款費

| 通道/卡別 | 授權期 |
|---|---|
| Shopify Payments（標準） | **7 天** |
| Plus 延長授權：Visa／Mastercard／Amex | 最長 **30 天**（依發卡行支援而異） |
| Plus 延長授權：Discover／JCB | 最長 **10 天** |
| Diners Club／China UnionPay | **7 天** |
| SP 第 7 天後才手動 capture（延長授權期內） | 加收 **1.75%** 附加費（疊加在標準卡費之上） |

- 逾 `authorizationExpiresAt` 未 capture ⇒ 收不到款，無任何交易產生，financial status → EXPIRED。
- ⚠ 第三方通道的授權期由各通道自定，官方無統一表。

### C.2 Capture 模式（Settings → Payments，4 選 1）

| 模式 | 行為 |
|---|---|
| Automatically at checkout（預設） | 信用卡當下請款（＝SALE）；替代付款方式待通道完成後入帳 |
| Automatically when order fulfilled | 結帳授權，**整單出貨完成**時自動 capture（須在授權期內） |
| Automatically per fulfillment（**僅 Plus**） | 每次出貨 capture 該次出貨額；末次出貨 capture 殘額；**一旦手動 capture 或發生退貨，該單自動化即停止** |
| Manually | 商家須在授權期內手動 capture |

### C.3 Capture 金額規則

- 允許 partial capture（可小於授權額）。
- 多次 capture 需 `multiCapturable=true`：SP＝Plus 專屬；第三方＝視通道支援。
- `orderCapture` 輸入：`id`、`parentTransactionId`、`amount`（Decimal）、`currency`（多幣別單**必填且必須＝presentment 幣別**）、`finalCapture`（true＝關閉授權，不得再 capture）。
- 權限：`write_orders`（或 `write_marketplace_orders`）＋ `capture_payments_for_orders`。
- 不變量：`Σ captures ≤ authorization 額`；`totalUnsettledSet = authorization − Σ captures`。

### C.4 退款規則

- REFUND 只能掛在 CAPTURE/SALE 之後；`Σ refunds ≤ Σ captured`（通道側上限＝`maximumRefundableV2`）。
- 退款金額**恆為正數**，方向由 kind 承載（65 §A.7 已考掘：唯 `tenderTransactions` 查詢面例外「負數＝退款」）。
- 退款不可撤銷；多幣別退款以**訂單原幣別（presentment）**處理。
- 匯率損益：退款時用**當時匯率**（非下單匯率），差額落 `currencyExchangeAdjustment`——商家可能因匯率波動賺或賠（§C.5）。

### C.5 多幣別轉換（匯率鎖定時點＋手續費公式）

- **轉換發生在交易處理時**：「Currency conversion occurs at the time of a transaction」——capture、refund、chargeback 各自用**當下匯率**。⇒ 手動 capture 的單，授權時與請款時匯率可以不同（金額差異風險官方明文）。
- 匯率兩制：**自動**（即時市場匯率）／**手動**（Managed Markets 商家自訂，穩定價格、自負匯損）。⚠ 自動匯率的更新頻率官方未載。
- **價格轉換公式**：`買家看到的價 = 商品價 × 匯率 × (1 + 轉換費率)`（再套 rounding，§C.7）。
- **轉換費率**：美國店 **1.5%**、其他地區店 **2%**（依店所在地，非買家所在地）。
- **轉換費計算基數（2026-04-06 改制）**：
  - 舊制（< 2026-04-06）：`(訂單毛額 − SP 手續費) × 費率 ÷ (1 + 費率)`——有效費率低於名目費率。
  - 新制（≥ 2026-04-06）：`訂單毛額 × 費率`——有效費率＝名目費率。**Multi-Currency Payout fee 同步改為以毛額計**。

### C.6 Multi-Currency Payouts（多幣別撥款）

- 資格：**Advanced 或 Plus** 方案＋業務實體在合格地區（37 國/區清單，取證見 §G；含 HK、SG、US、UK、EU 多數、CA、AU、AE=Plus 限定）。
- 每個 payout 幣別綁一個專屬銀行帳戶（部分地區限本地帳戶：SG／HK／AU）。
- **未綁帳戶的幣別 ⇒ 轉入預設帳戶幣別，收轉換費**。
- **Multi-Currency Payout fee**：Advanced **1.5%**／Plus **1%**（加拿大 Plus **1.25%**）；本幣撥款免費；**費用看 payout 幣別，不看有沒有實際轉換**。
- 特例：加拿大 Basic/Grow 店可選 USD 作預設撥款幣別，收 **1.5%** payout fee。
- 設定後新增帳戶（啟用 24 小時後）⇒ 撥款暫停 **3–5 個工作天**。
- 退款與 chargeback 一律以**訂單原幣別**處理。

### C.7 國際定價 rounding

- 逐 market 開關；開啟後價格自動湊整到該幣別的慣用檔位；**規則不可自訂**。
- 適用：商品價、運費；**不適用：gift card**。⚠ 各幣別的具體湊整檔位表（.99／.95／整數）help 現行頁未載——值域缺口，見 openQuestions。
- ⚠ 稅額與 checkout 合計是否湊整未明文。

### C.8 Payout 排程與時效

- **結算時間（capture → 可撥款）**，週五至週日 capture 的併入同一筆 payout：

| 地區 | 結算時間 | 最低撥款額 |
|---|---|---|
| 澳洲 | 2 工作天 | 無 |
| 奧、比、克羅埃西亞、賽普勒斯、芬、德、愛爾蘭、義、立陶宛、馬爾他、荷、波、葡、斯洛維尼亞、西、英 | 3 工作天 | €1（或等值） |
| 加、紐、美 | 3 工作天 | 無 |
| 捷克 | 3 工作天 | €1 或 30 Kč |
| 丹、挪、瑞典 | 3 工作天 | €1 或 20 當地幣 |
| 法國 | 3 **日曆天** | €10 |
| 香港、新加坡 | 4 工作天 | 10 HKD／1 SGD |
| 日本 | 5 工作天 | 5 JPY |
| 墨西哥 | 7 工作天 | 10 MXN |
| 阿聯 | 5 工作天 | 20 AED |

- 排程選項：**daily／weekly（選星期幾）／monthly（選日期，超出月末自動調整）**；法國、日本選項受限（日本無 daily）。
- 改排程 ⇒ 待撥款延至新排程的下一適用日。
- **負餘額**（退款/拒付 > 銷售）⇒ **撥款暫停，直到未來銷售沖平**。⚠「長期負餘額是否直接扣商家銀行帳戶」官方現行頁未明文。
- 撥款失敗（FAILED）⇒ 依通知修正帳戶資料，未修正前收不到後續款。

### C.9 Reserves（保留款）

- 觸發因子：訂閱制長帳期、拒付率升高、退款率升高、長交期行業、量能暴增。
- 兩型：**固定額**（例：$1,000 保留 120 天）／**比例制**（例：交易額 10% 保留 120 天，其餘 90% 照常撥）。
- 條款以 email 通知；期滿前重審（續留/降/升）；保留款於 payouts 頁獨立顯示（Payout balance vs Reserved funds）；期滿返還，入帳另需數個工作天；一般不影響繼續收單。
- balance txn 形態：`RESERVED_FUNDS`／`RESERVED_FUNDS_REVERSAL`／`RESERVED_FUNDS_WITHDRAWAL`。

### C.10 Chargeback 計費與時限

- chargeback 立案即扣：爭議額（立即從下一次可用 payout 扣）＋手續費（US **$15 USD**；歐洲多數 **€15 EUR**；其他地區依所在地）。
- 證據截止：立案後 **7–21 天**（依卡組織）；Shopify（SP 店）**自動彙整可得資料並在截止日代送**；截止前可隨時增改、**送出後不可改**。
- 審期：chargeback 最長 **75 天**；inquiry 通常 **65–75 天**；官方另一頁口徑「送證後 120 天內結案」——工程上取 120 天為逾時上限。
- 勝訴：爭議額＋fee 於下一次 payout 退回（fee 是否退依地區）；敗訴終局不可上訴。
- 買家撤回爭議（withdrawal letter）：處理 **30–90 天**。
- **勝訴仍計入 dispute rate**（風控分母監控上的反直覺點，實作 KPI 時分子不得剔除 WON）。
- Shopify 明文不介入裁定、不對 chargeback 負責。

### C.11 3DS／SCA

- 適用區：**EEA 全部國家＋英國**（PSD2）。
- 觸發邏輯：SP「**最小化使用** 3DS——僅當發卡行要求非驗證不可才觸發」；SCA 要求區內全部交易自動走 3DS 驗證流。
- 驗證成功 ⇒ **liability shift**：詐欺拒付責任移轉發卡行。上限例外：Visa 規定單月詐欺拒付逾 **$7,500 USD** 即喪失 liability shift 資格。
- 驗證失敗/未帶驗證：`AUTHENTICATION_FAILED`／`AUTHENTICATION_REQUIRED` 錯誤碼（§A.5）。
- 訂閱等 off-session 場景：發卡行要求確認時，以 email 送認證 URL 給買家。
- ⚠ 商家能否強制全量 3DS、SCA 豁免（低額/TRA）的平台側行為：官方 help 未載。

### C.12 Manual payments 對帳

- 內建型：**Bank Deposit／Money Order／Cash on Delivery (COD)**＋自訂名稱（避開保留字）；help 另列 Cash／External Credit／External Debit／Store Credit／Gift Card 形態。
- 下單 ⇒ financial status **PENDING**（列表顯示 unpaid）；付款指示顯示於確認頁/信。
- 商家實收後 `orderMarkAsPaid` ⇒ 產生 `gateway=manual` 的 SALE（或 capture 既有授權）、status SUCCESS ⇒ PAID。
- manual payments **不收第三方交易費**；啟用國際銷售＋SP 時以買家當地幣別顯示。

### C.13 併發要害（實作不變量）

1. **重複 capture**：同一授權併發兩筆 capture ⇒ 超收。防線＝`idempotencyKey`（鐵律 5）＋ DB 層 `Σ captures ≤ auth` 檢查在同一 transaction 內、行鎖授權列。
2. **capture vs void 競態**：兩者互斥於「授權未消耗」前置條件，必須同鎖。
3. **refund 上限**：併發退款下以**同交易行鎖＋條件式 UPDATE 計數器**兜底——`new_refund ≤ captured − refunded + approved_over_refund`（`approved_over_refund` 預設 0，僅授權分支寫入；式形同 §06 C.2）；**不得做成無條件 DB CHECK `Σ refunds ≤ captured`**——上限是**軟上限**（總綱 2.4 M7）：`allowOverRefunding=true` 的核准 over-refund（已退 store credit 改退原卡）是官方合法情境，硬約束會全數拒絕；唯一硬約束＝`refunded_total_cents ≥ 0`（§06 F.2#12）（2026-08-17 更正，PR #52 第 18 輪；CLAUDE.md 驗收基準明列退款上限併發測試）。
4. **payout 對帳**：balance txn append-only、payout 只收 `issuedAt` 時點前 available 的 txn——rollup 不得把 pending txn 算進已撥款。
5. **多幣別金額比對**：對 PSP 回報值比對一律走 65 §D 的單位轉換，**禁止**拿儲存 cents 直接比 PSP minor units（zero-decimal 幣別 100 倍事故，鐵律 3）。

---

## D. 關鍵流程

### D.1 自動請款結帳（預設）

1. 買家送出付款（操作者：買家）→ 系統向通道 authorize+capture 一步（SALE）。
2. 需 3DS 時：買家先完成發卡行驗證（AWAITING_RESPONSE →）；失敗 ⇒ `AUTHENTICATION_FAILED`，結帳頁報錯，訂單不成立。
3. SALE SUCCESS ⇒ 訂單成立、financial status PAID；發 `orders/paid`、`order_transactions/create`。
4. 失敗分支：`CARD_DECLINED` 等 ⇒ 買家改卡重試；棄單則入 abandoned checkout（04 §3）。

### D.2 手動請款

1. 結帳產生 AUTHORIZATION，訂單 AUTHORIZED，起算授權期（SP 7 天）。
2. 商家（操作者：staff，需 capture 權限）於訂單頁 Collect payment → capture 全額或部分；多幣別單以 presentment 幣別、**當下匯率**換算。
3. 全額 ⇒ PAID；部分 ⇒ PARTIALLY_PAID（Plus＋multiCapturable 可續 capture 至 finalCapture）。
4. 失敗分支：逾期 ⇒ EXPIRED 收不到款；SP 第 8 天起 capture 加收 1.75%；不想收款 ⇒ void。

### D.3 Mark as paid（manual payment 對帳）

1. 買家選 bank deposit/COD 下單 ⇒ PENDING＋付款指示。
2. 商家帳外收到款（銀行入帳/貨到收現）→ 訂單頁 Mark as paid。
3. 系統建 `gateway=manual` SALE(SUCCESS) ⇒ PAID；發 `orders/paid`。
4. 失敗分支：`canMarkAsPaid=false`（已付/無未收額）⇒ userError「Order cannot be marked as paid」。

### D.4 退款

1. 商家發起 refund（可勾 restock、可含運費，Σ ≤ 已收）。
2. 系統建 REFUND(parent=capture/sale) 送通道；成功 ⇒ PARTIALLY_REFUNDED/REFUNDED；發 `refunds/create`。
3. SP 側 balance txn `REFUND`（負向）；退款用當下匯率，差額落 currencyExchangeAdjustment。
4. 失敗分支：通道退款失敗 ⇒ balance txn `REFUND_FAILURE`；餘額不足退 ⇒ 負餘額規則（§C.8）。

### D.5 Payout 生成

1. capture 完成 ⇒ balance txn（CHARGE，net = amount − fee）進 pending。
2. 過結算期（§C.8 表）⇒ available。
3. 排程日到 ⇒ 系統把 available txn 聚成 payout（SCHEDULED，`issuedAt` 戳記）→ 送銀行。
4. 入帳 ⇒ PAID；銀行退件 ⇒ FAILED（商家修帳戶資料）；Shopify 撤回 ⇒ CANCELED。
5. 負餘額 ⇒ 不生成 payout，等沖平。

### D.6 Chargeback

1. 持卡人向發卡行爭議 ⇒ dispute 建立（INQUIRY 或直接 CHARGEBACK）；發 `disputes/create`。
2. CHARGEBACK：立即扣爭議額＋fee（balance txn `CHARGEBACK_HOLD`＋`CHARGEBACK_FEE`）；商家收通知＋`evidenceDueBy`。
3. 商家於截止前補證據；截止日 Shopify 自動送出 ⇒ UNDER_REVIEW；發 `disputes/update`。
4. 發卡行 ≤75 天裁定：WON ⇒ `CHARGEBACK_HOLD_RELEASE`＋`CHARGEBACK_FEE_REFUND` 入下一 payout；LOST ⇒ 扣款成立。
5. 分支：商家 ACCEPTED；買家撤回（30–90 天）；卡組織預防程序 ⇒ PREVENTED。

---

## E. 跨模組耦合

- **發出事件（webhook topics，本域）**：`order_transactions/create`（每筆交易）、`orders/paid`、`refunds/create`、`disputes/create`、`disputes/update`。
- **依賴方向**：
  - Orders → 本域：financial status 是訂單列表 badge／訂單詳情付款卡的資料源（數字同源，鐵律 7）。
  - Fulfillment → 本域：capture 模式 2/3 由出貨事件觸發 capture（per-fulfillment 是 Plus 分層）；反向：manual payment 單建議收款後再出貨。
  - Markets/國際化 → 本域：presentment 幣別、匯率制度、rounding 由 Markets 設定（29 號）；本域消費其匯率。
  - Checkout → 本域：產生首筆 AUTHORIZATION/SALE；3DS 流程在 checkout 內完成。
  - Refund/Return 域 → 本域：refundCreate 掛 REFUND 交易；換貨/退貨的金額差異走 order adjustments（80 §3 AOV 例外）。
  - Fraud analysis → 本域：風險指標消費 AVS/CVV 結果（paymentDetails）；高風險單建議先不 capture。
  - 分析/Finance 報表 → 本域：payout/balance txn 是財務報表與對帳 CSV 的資料源（73 §7.3 11 欄 CSV）。
- **平台計費（specs/37）與本域無資金往來**：37 是平台向租戶收軟體費的線；本域是租戶收貨款的線。唯一耦合＝第三方交易費從交易額計算後入平台帳單。

## F. 落地對應

### F.1 對應倉庫文件

| 主題 | 既有文件 | 本章補充 |
|---|---|---|
| Transaction kind/status/parent | `docs/research/04` §2.3（一句話模型） | §A.2–A.6 全值域＋§B 狀態機 |
| 金額單位 | `docs/specs/65`（六表示法）＋CLAUDE.md 鐵律 3 | §C.5/C.13-5 與其完全相容，無衝突 |
| Payout/對帳 UI | `docs/research/73` §7.3（排程/CSV/狀態四值） | §A.7/§B.4/§C.8-9 API 側與時效表 |
| 平台計費 | `docs/specs/37` | §E 邊界重申：兩線不混表 |
| Markets 匯率 | `docs/research/29` | §C.5–C.7 交易側規則 |

### F.2 本尊 vs 我方裁定（差異清單）

| # | 本尊 | 我方裁定 | 出處 |
|---|---|---|---|
| 1 | 金額對外用 `MoneyV2/MoneyBag`（Decimal 字串），內部實作未公開 | 內部全程 integer cents ×100（R1），序列化層才轉 MoneyV2；PSP 送出走 pack 宣告格式（R5/R6） | 鐵律 3、65 |
| 2 | Shopify Payments 自營收單，payout/balance/reserve 是第一方功能 | 我方不自營收單（G15 平台金融產品邊界）：收單走 PSP pack（Stripe 等），payout/對帳資料**從 PSP 回收再建模**；Balance/Capital/Bill Pay 不建 | 73 §7.2、CLAUDE.md 鐵律 11 |
| 3 | 轉換費 1.5%/2%、payout fee 1%/1.25%/1.5% 是 Shopify 商業條款 | 我方費率屬商業決策，**不照抄數字**；但「費用基數＝毛額」的 2026-04-06 新制語義照抄（可解釋性） | §C.5 |
| 4 | `authorizationExpiresAt`、multi-capture、per-fulfillment capture、延長授權＝**Plus 方案分層** | 我方方案分層由平台計費模型（37 §1 三層計價）另定，**功能本體全部實作**、分層做成 feature flag | 37 |
| 5 | 授權期 7/10/30 天依通道與卡別 | 授權期屬 **PSP pack 宣告值**（各 PSP 不同），上限值落 `config/limits.yml` 引用，不硬編 7 天 | 鐵律 6 |
| 6 | 稅務、chargeback fee 金額（$15/€15）per 地區 | 法域差異一律走 jurisdiction pack（HK 基準）；chargeback fee 由 PSP pack 回報值直錄，不自算 | 鐵律 11 |
| 7 | `userErrors` 泛用型無 code | 我方全 mutation typed code enum（ours 加嚴） | CLAUDE.md 鐵律 4 |
| 8 | POS 專屬 kind（CHANGE／EMV_AUTHORIZATION）與 device/location/user 欄位 | 無 POS 里程碑：**enum 值保留、不實作產生路徑**（保 1:1 對齊的資料模型相容） | HANDOFF §5 |
| 9 | 退款方向由 kind 承載、金額恆正；tenderTransactions 例外負數 | 已裁定照抄（65 §A.7） | 65 |
| 10 | 匯率鎖定在**交易處理時點**（capture/refund 各自取當下匯率） | 照抄本尊語義；⚠ 我方 checkout 顯示價與 capture 價的差異處理需在 M 實作時決策（本尊容忍差異存在） | §C.5 |
| 11 | dispute rate 分子含 WON | 照抄（風控 KPI 不得剔除勝訴爭議）；37 的「爭議率雙分母雙欄」沿用 | 37、§C.10 |
| 12 | 撥款狀態 API 4 值＋deprecated IN_TRANSIT；admin UI 呈現另有口徑 | 我方以 API enum 為準建模，UI 顯示層再映射 | §B.4 |
| 13 | AWAITING_RESPONSE 超時／UNKNOWN 收斂**官方均未明文**；僅相鄰錨點：訂單級 pending 過期「典型約一週」→EXPIRED（G23）、payments-apps `pendingExpiresAt` 建議 ≤3 天（G24） | 我方裁定收斂策略（§B.1.1 R1–R3）：超時、退避曲線、放棄期限全引 `config/limits.yml`；UNKNOWN 非終態，逾放棄期限 alert＋人工對帳，不得永久懸置 | §B.1.1、G23/G24 |

### F.3 開發驗收要點

1. 交易表 append-only＋parent 鏈；kind/status enum 對齊 §A.3/A.4 全值域；payout 側 `ShopifyPaymentsTransactionType` 對齊 §A.7 **逐字 113 值清單**（22 核心＋91 生態，CI 快照直接比對本檔清單）；財務狀態由交易推導（不可獨立改寫）。
2. 併發測試四件：重複 capture、capture×void 競態、refund 上限、超授權 capture——各配 `idempotencyKey`＋DB 兜底約束。
3. 金額測試矩陣含 JPY/TWD/KRW（65 §H）；capture/refund 的 PSP 金額比對必走單位轉換層。
4. 授權逾期掃描 job：逾 `authorization_expires_at` ⇒ financial status EXPIRED＋通知；授權期值引 `config/limits.yml`。
5. Dispute 狀態機以 §B.5 全轉移表實作，`evidence_due_by` 前可編修、送出後鎖定；逾時自動送。
6. Payout 對帳：balance txn（amount/fee/net）與 payout 聚合數字同源（鐵律 7）；CSV 匯出 11 欄對齊 73 §7.3。
7. AWAITING_RESPONSE／UNKNOWN 收斂測試（§B.1.1）：①超時且 PSP **明確拒絕** ⇒ FAILURE＋`PAYMENT_PROVIDER_ERROR`；①′超時且 PSP **查無／無終局** ⇒ 轉 UNKNOWN 進 R2（**斷言不落 FAILURE**——（2026-08-17 更正，PR #52 第 19 輪）：R1 反轉後原「查無 ⇒ FAILURE」斷言會把新行為判紅或反鎖舊行為）；②超時但 PSP 查得終局 ⇒ 照落；③UNKNOWN 退避輪詢收斂到 SUCCESS/FAILURE/ERROR；④逾放棄期限 ⇒ 維持 UNKNOWN＋alert（斷言不會被誤轉終局）；⑤收斂 job 與人工 capture/void 競態走同一行鎖。時間值全 stub `config/limits.yml`，不得硬編（鐵律 6）。

---

## G. 來源（全部取證 2026-08-14）

| # | URL | 內容 |
|---|---|---|
| 1 | https://shopify.dev/docs/api/admin-graphql/latest/objects/OrderTransaction | OrderTransaction 欄位全表 |
| 2 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderTransactionKind | kind 8 值 |
| 3 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderTransactionStatus | status 6 值 |
| 4 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderTransactionErrorCode | errorCode 47 值 |
| 5 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderCapture | capture 輸入/多次 capture 規則 |
| 6 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/transactionVoid | void 前置條件 |
| 7 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/orderMarkAsPaid | mark as paid 前置與產生交易 |
| 8 | https://shopify.dev/docs/api/admin-graphql/latest/enums/OrderDisplayFinancialStatus | 財務狀態 8 值 |
| 9 | https://help.shopify.com/en/manual/payments/payment-authorization | 授權期 7/10/30 天、1.75%、capture 4 模式 |
| 10 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ShopifyPaymentsPayout ＋ /enums/ShopifyPaymentsPayoutStatus | payout 物件＋狀態 5 值 |
| 11 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ShopifyPaymentsBalanceTransaction ＋ /enums/ShopifyPaymentsSourceType ＋ /enums/ShopifyPaymentsTransactionType | balance txn＋sourceType 7 值＋type 113 值 |
| 12 | https://help.shopify.com/en/manual/payments/shopify-payments/payouts/payout-timing | 結算天數表、最低撥款額、排程、負餘額 |
| 13 | https://help.shopify.com/en/manual/payments/shopify-payments/payouts/reserves | 保留款兩型與 120 天例 |
| 14 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ShopifyPaymentsDispute ＋ /enums/DisputeStatus ＋ /enums/DisputeType ＋ /enums/ShopifyPaymentsDisputeReason | dispute 物件＋狀態 7 值＋type 2 值＋reason 14 值 |
| 15 | https://help.shopify.com/en/manual/payments/shopify-payments/chargebacks（含子頁 chargeback-process、resolve-chargeback） | 7–21 天證據期、$15/€15、75/120 天、自動代送、終局性 |
| 16 | https://help.shopify.com/en/manual/international/pricing/exchange-rates | 匯率鎖定時點、自動/手動匯率、轉換公式 |
| 17 | https://help.shopify.com/en/manual/payments/shopify-payments/store-currency/currency-conversion-calculation | 轉換費新舊制公式（2026-04-06） |
| 18 | https://help.shopify.com/en/manual/payments/shopify-payments/store-currency/payouts-in-multiple-currencies | 多幣別撥款資格、費率 1%/1.25%/1.5%、未綁幣別處理 |
| 19 | https://help.shopify.com/en/manual/international/pricing/rounding | rounding 不可自訂、不適用 gift card |
| 20 | https://help.shopify.com/en/manual/payments/shopify-payments/transactions/psd2-and-3d-secure-checkout | EEA+UK、最小化 3DS、liability shift、$7,500 |
| 21 | https://help.shopify.com/en/manual/payments/manual-payments | manual payment 型別、PENDING、mark as paid |
| 22 | https://shopify.dev/docs/apps/build/payments | payment 擴充 5 類型＋5 操作（charge/refund/authorize/capture/void） |
| 23 | https://help.shopify.com/en/manual/fulfillment/managing-orders/payments/pending-payments | pending payment 過期日「典型約一週」→EXPIRED；失敗寄「Pay now」重試信；pending 期間鎖編修/restock/取消/收款/mark as paid |
| 24 | https://shopify.dev/docs/api/payments-apps/latest/mutations/paymentSessionPending | `pendingExpiresAt` 官方建議 ≤3 天；pending 須由 paymentSessionResolve/Reject 終局化；**逾期自動轉移官方未載** |
