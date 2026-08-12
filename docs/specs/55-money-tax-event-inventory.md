# 55 — 金流寫入點與稅務事件點專項盤點（M4 前置）

> **緣由**：`docs/specs/54-p1-logic-fixes.md` §4 的結論——NP1-D（`orderEditCommit` 未列強制冪等）與 NP1-F（訂單編輯未觸發發票折讓）是**同源缺口**：本專案從未完整列舉過「會動錢的程式路徑」與「會動發票的程式路徑」。54 號逐字建議：「建議在 M4 動工前做一次專項盤點（列出所有會動錢、會動發票的程式路徑），比逐條補漏可靠。」本檔即為該盤點。
> **權威順序**（沿用 52／54）：官方開發文檔（46a/46b）＞ 官方商家文檔（46c）＞ 實測畫面（44）＞ 我方既有規格。**我方與官方衝突時一律改我方。**
> **台灣法遵的權威來源不同**：Shopify 不開立台灣統一發票，46a/46b/46c **不可能**是電子發票規則的來源。本檔凡台灣稅務規則一律標「**我方依台灣法規自訂**」或 `⚠ 待查證`，**不得偽裝成 Shopify 行為**。
> **金額鐵律**（CLAUDE.md 鐵律 3）：全程 **integer cents**；本檔每一條公式都寫明 floor/ceil 與捨入發生的位置；沒有寫捨入的地方就是**精確整數運算，不得引入捨入**。
> **盤點日**：2026-08-12。**可追溯性**：本檔對既有規格檔的每一處改動都留 `<!-- 依 … 修正，原文：… -->`，格式沿用 52／54。

---

## 0. 盤點方法與結論摘要

### 0.1 方法

1. **由資料表反推**，不由畫面反推：凡會 INSERT／UPDATE 下列任一張表的路徑，一律列為金流寫入點——
   `order_transactions`／`refunds`／`refund_line_items`／`returns.return_shipping_fee_cents`／`return_line_items.restocking_fee_cents`／`gift_cards.balance_cents`／`store_credit_accounts.balance_cents`／`billing_invoices`／`billing_gmv_rollups`／`reserve_ledger_entries`／`negative_balances`／`disputes`／`payout_runs`。
   理由：從按鈕表（22）反推會漏掉排程與 webhook——54 號漏掉訂單編輯正是因為當時 16 號沒有那一章，而**表永遠在**。
2. **三個入口都要掃**：API mutation（28）／後台動作（22）／排程與 webhook（18-F5、37、38 的 job 表）。
3. **稅務側由「發票狀態機」反推**：`einvoices.state`（reserved / issuing / issued / failed / voided / number_burned，38:1003）與 `einvoice_allowances`，凡會改變這兩張表的業務事件即為稅務事件點。
4. 每一條都回頭核對**是否真的有規格落點**；沒有落點的記入 §D，不靜默補。

### 0.2 結論摘要

| 項 | 數量 |
|---|---|
| **A 金流寫入點** | **41 條**（其中 **11 條屬「同一筆金流的多次寫入」**，必須有累計上限檢查＋併發鎖） |
| **B 稅務事件點** | **30 條**（其中 **11 條**會造成已開立發票需**折讓／作廢／補開**） |
| **C 交叉矩陣** | **41 × 6**（246 格） |
| **D 缺口** | **24 條**：P0 **8**／P1 **11**／P2 **5** |
| **E limits.yml 增補** | **541 → 726 行（+185）**：`idempotency.required_for` **+9**、新增 `required_for_platform`(2) 與 `business_unique_keys`(5)、新增 `einvoice`(32 鍵) / `gift_card`(12 鍵) / `dispute`(4 鍵) 三個頂層區塊、`capture` +5 / `store_credit` +5 / `refund` +2 / `checkout` +3 |
| **F 新增 ⚠ 待查證** | **V-21 ～ V-24**（4 條），並**擴大 V-20** 的範圍 |

### 0.3 一句話結論

**最危險的不是「哪個金流動作沒做」，而是「金流動作做了、稅務動作沒跟上」，以及「同一筆金流被寫兩次」。**
前者的具體形態是 §D 的 G-01／G-02／G-03；後者的具體形態是 §A.2 的 11 條多次寫入路徑——其中 **`orderCapture` 與禮品卡扣抵兩條目前既無冪等、也無累計上限**，是照現有規格開發必定資損的位置。

---

## A. 金流寫入點總表（Money Write Points）

### A.0 欄位定義與讀法

| 欄 | 定義 |
|---|---|
| **方向** | `收`＝現金／應收流入；`退`＝流出；`調整`＝既有帳務欄位變更但無新的資金移動（含沖銷、狀態改寫）；`凍結`＝資金被保留但未移轉（授權、保留金） |
| **是否需冪等** | ✅＝已在 `limits.idempotency.required_for`；🔴＝**本檔判定必須強制、但目前不在清單內**（缺口，見 §D）；⚪＝天然冪等（同態重入 no-op）或以唯一索引兜底 |
| **冪等鍵組成** | 互動請求 UUID v4/v7；排程／背景任務 UUID v5（namespace ＋ 下表列出的參數），依 `limits.idempotency.key_format_*`（46a S47/S48） |
| **🔁** | 標記「**同一筆金流的多次寫入**」——必須有**累計上限檢查**與**併發鎖**，詳見 §A.2 |

**捨入總則**：下表所有金額欄位皆 integer cents。全表**只有三個捨入點**（與 16-F5.1 完全一致，不得另立第四個）：
①折扣／稅的比例分攤 → **最大餘數法**（15-F2）；②百分比費用（重新上架費）→ **floor**（費用取小 ⇒ 退款取大，對買家有利）；③零小數幣別 → 業務層**完全不感知**，單位換算只發生在**跨界點**（R1 → 該 PSP pack 宣告的 minor unit），唯一出口是 `Money::Storage#to_psp_minor(psp:)`，契約見 **65 §D**（落地見 15-F4 第 5 點）。
🔴 **③其實不是捨入點**：`to_psp_minor` 對不整除的餘數是 **raise（`NonIntegralPspConversion`），不是 round**（65 §D.2 A3）。所以本表「只有三個捨入點」的斷言仍然成立，而且實際上只有兩個真的在捨入。
<!-- 依 65 §J M-2 修正，原文：「③零小數幣別 → **僅在序列化層**由 15-F4 `stripe_amount()` 處理。」
     **指標方向本來就是對的**（業務層不感知 ✅），錯的是它指向的定義已被 2026-08-12 裁定二作廢：
     15-F4 原本逐字寫「JPY 等零小數幣別**不乘 100**」，那是裁定二**之前**的儲存模型（JPY 存 1480）。
     裁定二之後 JPY 存 148000，照那句話實作＝送 PSP 收款 100 倍。15-F4-5 已隨 M-1 改寫，本點改指 65 §D。
     ⚠️ 本表所有金額欄位仍一律 R1（integer cents）——**分錄與金流寫入點禁止以 PSP minor unit 記帳**（65 §F.1），
     記了就對不回訂單金額，而且 JPY 的帳會小 100 倍。M02 的冪等鍵 `pi-{checkout.token}-{amount_cents}` 同理恆為 R1（65 §E.1-3）。
     🔴 **防回退**：不得改回 `stripe_amount()`，也不得把本點縮回「僅在序列化層處理」一句。 -->
GMV 抽成 `gmv_cents * bps / 10_000` 為**整數除法（截斷＝floor）**，37:85 已定。

### A.1 總表（41 條）

| # | 觸發點（API 操作／後台動作／排程／webhook） | 方向 | 影響的帳務欄位 | 冪等 | 冪等鍵組成 | 失敗重試語義 | 併發風險 | 對應規格章節 |
|---|---|---|---|---|---|---|---|---|
| **M01** | 結帳付款成功 → `Orders::CreateFromCheckout`（return_url **與** `payment_intent.succeeded` webhook 雙路徑） | 收 | `order_transactions(kind=sale\|authorization)`、`orders.total_cents`／`financial_status`、`discounts.usage_count` | ⚪ | `orders.checkout_id` 唯一索引（天然鍵）＋ PI id 比對 | 雙路徑先到先贏；重入直接回既有訂單，**不建第二張** | 50 執行緒重複提交 → 恰 1 張訂單（15 驗收） | 15-F5 |
| **M02** | 建立 Stripe PaymentIntent（授權） | 凍結 | `order_transactions(kind=authorization, status=pending→success)`；買家卡片 hold | ✅ | `pi-{checkout.token}-{amount_cents}` | 金額變動＝新 key，舊 PI `cancel` | 同 checkout 多分頁 → 同 key 命中同一 PI | 15-F4 第 1 點 |
| **M03** | **授權到期**（排程 job） | 調整（凍結解除） | `order_transactions(authorization → expired)`；`financial_status → EXPIRED`（終態） | 🔴 | UUID v5(`authexpire`, transaction_id, expires_on) | 可重跑；已 expired 為 no-op | 與手動 capture 競態 → 條件式 UPDATE `WHERE status='success' AND kind='authorization'` | 16-F4.3 ＋ **G-18（無 job 規格）** |
| **M04** | 取消授權 void（`orderCancel` 未請款單／後台 void） | 凍結解除 | `order_transactions(kind=void)`；`financial_status → VOIDED`（終態） | ✅ | 隨 `orderCancel` 的 key | job 重入 no-op | 與 M05–M08 競態：void 與 capture 只能一個成功 | 16-F4.2、22 §8 |
| **M05** | 請款模式①`automatic_at_checkout`（預設，全方案） | 收 | `order_transactions(kind=capture)`；`financial_status → PAID` | 🔴 | `capture-{order_id}-checkout` | 通道逾時不自動重試，交回排程（比照 37:120） | 與 M04 競態 | 15-F4.1(a)、22 §8、`limits.capture.modes` |
| **M06** | 請款模式②`automatic_after_fulfilled`（整單出貨後，全方案） | 收 | 同上 | 🔴 | `capture-{order_id}-fulfilled` | 同上 | 最後一次出貨與手動 capture 同時發生 | 同上 |
| **M07** 🔁 | 請款模式③`automatic_per_fulfillment`（**每次出貨各請一次，僅 Plus**） | 收 | 同上，**每次出貨各一列 capture** | 🔴 | `capture-{fulfillment_id}` | 同上 | **兩次出貨同時完成 → 兩筆 capture 同時寫入，總額可能 > 授權額** | 15-F4.1(a)、46c:508–514 |
| **M08** 🔁 | 手動請款 `orderCapture(amount, parentTransactionId)`（**支援部分請款、可多次**） | 收 | 同上 | 🔴 | 呼叫端帶 `idempotencyKey`；後端另以 `(order_id, parent_transaction_id, amount_cents, seq)` 防呆 | 同上 | **同上；且手動請款沒有 `fulfillment_id` 可當鍵**（G-17） | 15-F4.1(a)、46c:526 |
| **M09** 🔁 | `refundCreate`（無退貨脈絡：純取消、客訴補償） | 退 | `refunds`、`refund_line_items`、`order_transactions(kind=refund, pending→success)` | ✅ | 呼叫端 UUID v4（46a 2026-04 起強制） | 先落 pending 再打金流；Stripe 失敗保留 pending 可重試（key 不變） | **兩個並發退款總額不得突破軟上限**（條件式 UPDATE） | 16-F5.1／F5.4、46a:781–787 |
| **M10** 🔁 | `returnProcess`（含 `financialTransfer.issueRefund`） | 退 | 同 M09 ＋ `returns.status`、disposition | ✅（**本專案強制**，Shopify 未載明） | 呼叫端 UUID v4 | 同上 | 同一訂單多張退貨並行處理 | 16-F7.5、46a:620/1062 |
| **M11** 🔁 | 退貨費用扣抵（重新上架費 ＋ 退貨運費），含 admin 覆寫 | 調整（減少應退） | `return_line_items.restocking_fee_bp`／`_cents`、`returns.return_shipping_fee_cents` | 隨 M10 | — | 覆寫寫 audit log | 兩人同時改同一張退貨的費用 → `lock_version` | 16-F5.3 |
| **M12** | 換貨差額（`net` 正負決定收或退） | 收／退 | `balance_to_collect` 或 `suggested_refund`；換貨品項的銷售紀錄 | 隨 M10 | — | — | 換貨品在 hold 期間被別人買走（庫存不保留，46c:299） | 16-F5.1、16-F7.3 規則 7 |
| **M13** | `orderCancel`（帶 `refundMethod`）→ 非同步 job | 退 | `refunds`、`order_transactions`、`financial_status` | ✅ | 呼叫端 UUID v4（job 內沿用） | job 重入只執行一次 | 與 `returnCreate` 雙向互鎖（16-F4.1 G3） | 16-F4.2 |
| **M14** | Stripe webhook `charge.refunded` 回寫 | 調整 | `order_transactions(refund: pending → success)` | ⚪ | `stripe_event_id` 去重表（唯一索引） | 接收層恆 200＋丟 job；Stripe 自行重送 | 同一 event 重放 10 次 → 只寫一次 | 15-F4 第 4／6 點 |
| **M15** | `orderEditCommit` 差額 **> 0** → 產生應收 | 收（應收） | `orders.total_cents`↑、`order_edit_deltas`、應收餘額 | ✅（NP1-D） | 呼叫端 UUID v4 | commit 失敗整個 transaction 回滾，`calculated_orders` 保留 | 單一 open session 鎖（部分唯一索引）＋ `orders.lock_version` 樂觀鎖 | 16-F8.1(c)、16-F8.2 |
| **M16** | `orderEditCommit` 差額 **< 0** → 退款 | 退 | 同 M09 | ✅（NP1-D） | 同上 | **退款不可逆**，二次確認 | 同上 | 16-F8.1(c) |
| **M17** | 補款結帳連結付款成功（`orderEditCommit` 的下游） | 收 | `order_transactions(kind=sale)`、`financial_status` | ⚪ | 補款 checkout token（同 M01 機制） | 同 M01 雙路徑 | 同 M01 | 16-F8.1(c)、46c:470（**補款頁無加速結帳**） |
| **M18** | COD 訂單成立 | 收（掛帳） | `order_transactions(kind=sale, status=pending)`、`orders.cod_expected_cents`、`financial_status=PENDING` | ⚪ | 隨 M01 | — | — | 16-F4.4、15-F2.3 |
| **M19** 🔁 | COD 物流商對帳檔匯入 → 回寫 paid | 收 | `order_transactions(pending → success)`；`financial_status → PAID` | ⚪ | `(carrier, statement_id, row_no)` 唯一索引（`limits.cod.settlement_idempotency_key`） | **金額不符不得自動回寫**，停在 PENDING 進人工佇列 | 同一份對帳檔並行匯入兩次 → 唯一索引兜底 | 16-F4.4 |
| **M20** | COD 買家未取件退回 | 調整（應收沖銷） | `financial_status: PENDING → VOIDED`；庫存依 `restock` | 隨 M13 | — | — | 與對帳回寫競態（貨已退但對帳檔仍有該筆） | 16-F4.4 第 5 列 |
| **M21** | `orderMarkAsPaid`（手動付款方式標記已收款） | 收 | `order_transactions(kind=sale, status=success)`；`financial_status → PAID` | 🔴 | `markpaid-{order_id}` | 一律走 `Orders::MarkAsPaid` 單一 service（不得在匯入器直改欄位） | **兩個 staff 同時標記 → 兩筆 sale**；須條件式 UPDATE `WHERE financial_status='PENDING'` | 28 §4、16-F4.4 |
| **M22** | `draftOrderComplete(paymentPending:)` → 轉正式單 | 收（false）／掛帳（true） | 建 `orders` ＋ `order_transactions`；`unavailable[draft_reserved] → committed` | 🔴 | `draftcomplete-{draft_order_id}` | 重入回既有訂單 | 重複 complete → `orders.draft_order_id` 唯一索引 | 28 §4；**草稿單無專屬 spec 檔（G-20）** |
| **M23** | `storeCreditAccountCredit`（後台發放商店抵用金） | 收（平台對顧客負債↑） | `store_credit_accounts.balance_cents`↑、`store_credit_transactions` | 🔴 | `sccredit-{account_id}-{client_ref}` | — | **累計上限 `< USD 15,000`**（46c:253–277）在併發下會被突破 | `limits.store_credit.*`；**無規格章節（G-07）** |
| **M24** 🔁 | 商店抵用金用於結帳 `storeCreditAccountDebit` | 收（抵付） | `balance_cents`↓、`store_credit_transactions`；訂單付款組成 | 🔴 | `scdebit-{checkout_token}-{account_id}` | 結帳失敗必須回補（補償交易） | **兩分頁同時結帳用同一帳戶 → 超額扣抵**；「最早到期先用」順序在併發下不穩定 | `limits.store_credit.consumption_order`；**無規格章節（G-07）** |
| **M25** | 商店抵用金到期（排程） | 調整（餘額歸零） | `balance_cents → 0`、`store_credit_transactions(kind=expire)` | 🔴 | UUID v5(`scexpire`, account_id, expiry_date) | 可重跑（同日重入 no-op） | 到期瞬間有人正在結帳 → 邊界以**商店時區當日結束**為準（`expiry_boundary`） | `limits.store_credit.expiry_boundary` |
| **M26** | 退款退至商店抵用金（`refundMethods = STORE_CREDIT`） | 退（改變形式） | `balance_cents`↑；`refunds` 的分配列 | 隨 M09／M10 | — | — | 與 M24 同帳戶併發 | 16-F5.4(b)、46a:743 |
| **M27** | `giftCardCreate`（後台發卡） | 收（負債↑） | `gift_cards.initial_value_cents`／`balance_cents`、`gift_card_transactions` | 🔴 | `gcissue-{client_ref}` | — | — | 22:116、41:426（**面額 ≤ $2,000**）；**無 limits 鍵（G-12）、無規格章節（G-07）** |
| **M28** | 禮品卡**商品**售出 → 訂單成立時自動發卡（可排程寄送 ≤90 天） | 收（負債↑） | 同 M27 ＋ 排程寄送 | 隨 M01 | — | 排程寄送失敗不影響卡片有效性 | — | 42:492–494；**無規格章節（G-07）** |
| **M29** 🔁 | `giftCardCredit`（儲值／餘額調整） | 收 | `balance_cents`↑ | 🔴 | `gccredit-{gift_card_id}-{client_ref}` | — | 與 M30 併發 | 28 §8 |
| **M30** 🔁 | 禮品卡於結帳扣抵 `giftCardDebit` | 收（抵付） | `balance_cents`↓、`gift_card_transactions` | 🔴 | `gcdebit-{checkout_token}-{gift_card_id}` | 結帳失敗必須回補 | **同一張卡兩張訂單同時結帳 → 超額扣抵（最典型的併發資損）**；`balance_cents ≥ 0` 必須是條件式 UPDATE | 28 §8；**無規格章節（G-07）** |
| **M31** | `giftCardDeactivate`（停用＝**永久**） | 調整 | `gift_cards.enabled = false`（餘額不歸零，供對帳） | ⚪ | 同態重入 no-op | — | — | 22:116 |
| **M32** 🔁 | 退款分配回補禮品卡餘額 | 退（回補） | `balance_cents`↑、`gift_card_transactions` | 隨 M09／M10 | — | — | 與 M30 併發 | 16-F5.4；**F5.4 只寫「分配」未寫「回補寫入點」（G-19）** |
| **M33** | 爭議開立（通道 webhook `charge.dispute.created`） | 凍結／扣回 | 平台側 `disputes`；**租戶側 `order_transactions` 無對應 kind（G-08）** | ⚪ | `(provider, provider_case_no)` 唯一 ＋ `payment_events` 去重 | 接收層恆 200＋丟 job | 同一 dispute 重送 10 次 → 恰 1 列 | 37 §爭議與風控、37:1032 |
| **M34** | 爭議勝訴 | 收（資金回補） | `disputes.state → won`、`dispute_state_transitions` | ⚪ | 狀態機同態重入 no-op | — | 與月度 rollup job 併發 | 37:1033 |
| **M35** | 爭議敗訴 | 退（確認扣回） | `disputes.state → lost`；`negative_balances` 開立（`deadline_on = opened_on + 180`） | ⚪ | `(shop_id, source_type, source_id)` 唯一 | — | **爭議 webhook 與每日回收 job 同時對同一負餘額入帳**（37:705） | 37:531、37:577 |
| **M36** 🔁 | 保留金 hold／release／offset | 凍結／解凍 | `reserve_ledger_entries(direction)` | ⚪ | `(shop_id, source_type, source_id)` 唯一 | — | 同一來源重複入帳 → 唯一索引 | 37:530 |
| **M37** 🔁 | 負餘額回收（排程） | 調整 | `negative_balances.recovered_cents`／`offset_cents` 累加 | ⚪ | 條件式 UPDATE | 可重跑 | **`offset + recovered ≤ amount` 恆成立**（37:870） | 37:675–678 |
| **M38** | 平台方案費出帳 `Platform::Billing::InvoiceGenerator`（排程） | 收（平台應收） | `billing_invoices`、`billing_invoice_lines(kind=plan\|addon)` | ⚪ | `(shop_id, period_start)` UNIQUE | job 重試 3 次指數退避 | 同期重跑 → 唯一索引 | 37:118 |
| **M39** | GMV 抽成 `GmvCommissionCalculator`（排程） | 收（平台應收） | `billing_gmv_rollups.commission_cents = gmv_cents * bps / 10_000`（**整數除法，截斷**） | ⚪ | `(shop_id, period_start)` upsert | 可重跑 | — | 37:119、37:85 |
| **M40** 🔁 | 平台向租戶扣款 `Platform::Billing::ChargeAttempt`（dunning） | 收（平台實收） | `dunning_attempts`、`billing_invoices.paid_cents` | ⚪ | `dunning_attempts.idempotency_key` | **通道逾時不自動重試**，交回排程（避免重複扣款） | `paid_cents + waived_cents ≤ total_cents` DB CHECK | 37:120、37:402 |
| **M41** | 撥款批次鏡像 `PayoutMirrorSync`（每 30 分鐘） | **不移動資金** | `payout_runs`／`payout_run_items`（**唯讀鏡像**） | ⚪ | `(channel_id, provider_batch_no)` UNIQUE upsert | 指數退避 5 次 | upsert 不產生重複列 | 37:576；**TW-9 電支條例鐵律：無任何「發起撥款」的 mutation**（37:895） |

> **M41 的存在意義是「明文標註它不是金流寫入點」**——依 TW-9（電支條例）我方不代收代付、不保管資金，租戶貨款直接進租戶自持的 Stripe／通道商戶號。任何人日後想在此加一支「發起撥款」的 mutation，本表就是擋下它的依據。

### A.2 「同一筆金流的多次寫入」——必須有累計上限檢查與併發鎖

以下 **11 條**（表中標 🔁）的共同特徵：**同一個帳務對象會被寫入 N 次，且 N 次的總和有一個不可突破的上界**。這類路徑只做冪等是不夠的——冪等只擋「同一把 key 重送」，擋不住「兩把不同 key 的合法請求加起來超額」。

> 🔴 **本節 11 條全部法域無關，一條都不得因法域改動而削弱**（56 §F 驗收 21）。
> <!-- 依 56 §E 分流補寫。§B（稅務事件）整節在 HK 大幅降階，但**本節是金流側**：錢動了幾次、加起來有沒有超過上界，
>      與賣方有沒有稅務憑證制度完全無關。56 §E.1 已把「G-02 連金流不變量一起拿掉」標為危險等級**高（容易誤刪）**。
>      唯一的例外方向是**新增**而非刪減：HK 基準法域下，M27–M32（禮品卡）與 M23–M26（抵用金）除了餘額上限之外，
>      還要在同一個 transaction 內落一列 `contract_liability_entries`（HKFRS 15，57 §G-07）。 -->

| # | 多次寫入的對象 | 累計上限式（integer cents） | 併發鎖做法 |
|---|---|---|---|
| M07／M08 | 同一筆授權的多次部分請款 | `Σ captured_cents ≤ authorization.amount_cents` | `UPDATE order_transactions SET captured_total = captured_total + ? WHERE id = ? AND captured_total + ? <= amount_cents`；affected 0 ⇒ `userErrors` |
| M09／M10 | 同一訂單的多次部分退款 | `Σ refunded_cents ≤ maximumRefundable`（軟上限，**不得做成 DB CHECK**——NP0-A） | 條件式 UPDATE 取得 `refundable`；超過 ⇒ 走 `orders.over_refund` 權限＋二次確認路徑。**完整 SQL 樣式／併發情境／兩個錯誤碼見 `16-F5.1(a)–(e)`（57 §G-02 補齊）** |
| M11 | 同一張退貨的費用覆寫 | `Σ restocking_fee_cents ≤ Σ line_net`；`return_shipping_fee_cents ≥ 0` | `returns.lock_version` 樂觀鎖 |
| M19 | 同一張 COD 訂單的多次對帳匯入 | `Σ settled_cents == cod_expected_cents`（**完全相符才回寫**） | `(carrier, statement_id, row_no)` 唯一索引 |
| M24 | 同一顧客抵用金帳戶的多次扣抵 | `Σ debit ≤ balance_cents` 且逐筆 `balance_cents ≥ 0` | `UPDATE store_credit_accounts SET balance_cents = balance_cents - ? WHERE id = ? AND balance_cents >= ?` |
| M29／M30／M32 | 同一張禮品卡的多次儲值／扣抵／回補 | `balance_cents ≥ 0` 恆成立；`Σ debit ≤ Σ credit` | 同上條件式 UPDATE；**禁止先讀後寫** |
| M36 | 同一 reserve 的多筆分錄 | `Σ hold − Σ release − Σ offset ≥ 0` | `(shop_id, source_type, source_id)` 唯一索引 ＋ 條件式 UPDATE |
| M37 | 同一負餘額的多次回收 | `offset_cents + recovered_cents ≤ amount_cents` | 條件式 UPDATE（37:870 既有要求） |
| M40 | 同一張平台帳單的多次扣款嘗試 | `paid_cents + waived_cents ≤ total_cents`（**DB CHECK**，37:402） | 平台自己的帳單，可用 DB CHECK（與租戶退款上限不同，後者有合法超額情境） |

**三條硬要求（實作驗收）**
1. **不得先 SELECT 再 UPDATE**：上表所有上限檢查一律做成**帶條件的 UPDATE**（`WHERE 餘額 >= ?`），依 affected rows 判定成敗。這是 CLAUDE.md「併發要害必須有測試」的直接落點。
2. **上限檢查與寫入必須在同一條 SQL 或同一個 transaction 內**；provider（Stripe／加值中心／物流商）呼叫一律在 transaction 外（11 §8）。
3. **每一條都要有 100 執行緒併發測試**：斷言「總和不突破上限」且「成功筆數 ＋ 失敗筆數 ＝ 請求數」。比照 17-F3「100 執行緒搶 `usage_limit=10` 的碼恰好 10 單成立」的既有做法。

### A.3 冪等鍵命名規約（本檔新增，供 §E 落地）

```
互動請求（前端／API 呼叫端提供）      : UUID v4 或 v7          # limits.idempotency.key_format_interactive
排程與背景 job（服務端自行推導）      : UUID v5(namespace, 下列參數)
  授權到期        authexpire  : (transaction_id, expires_on)
  抵用金到期      scexpire    : (store_credit_account_id, expiry_date)
  對帳回寫        codsettle   : (carrier, statement_id, row_no)
  平台出帳        billinvoice : (shop_id, period_start)
服務端防呆的第二層鍵（不取代呼叫端 key，只做重覆偵測）
  請款            capture-{order_id}-{fulfillment_id|checkout|fulfilled|seq}
  標記已付        markpaid-{order_id}
  草稿轉單        draftcomplete-{draft_order_id}
  禮品卡          gcissue|gccredit|gcdebit-{gift_card_id|checkout_token}-{client_ref}
  抵用金          sccredit|scdebit-{store_credit_account_id}-{client_ref}
```

> **為什麼要有第二層鍵**：`limits.idempotency.ttl_hours: 24`——24 小時後同一把 key 視為全新操作（46a:789 逐字）。對「一年後仍不得重複發生」的動作（例如同一張 fulfillment 的 capture），24 小時的冪等窗不夠，必須另有業務唯一索引兜底。這一點 52 號 P0-11 未涵蓋。

---

## B. 稅務事件點總表（Tax Event Points）

### B.0 前提：本節的台灣法遵動作全部是「我方依台灣法規自訂」

**Shopify 不開立台灣統一發票**——46a／46b／46c 三份官方文檔中**沒有任何一條**關於字軌、折讓單、作廢、載具、統編的規則，本檔也**不會**引用它們來支撐台灣稅務結論。本節規則的來源只有三類：

| 來源類型 | 具體出處 | 權威等級 |
|---|---|---|
| 我方既有平台規格 | `38 §3B`（38:964–1006 資料模型、38:1248–1356 job 與 router）、`33 §2.14`（經 38 轉述） | 我方決策，可改 |
| 我方既有前台研究 | `42 §12.1`（42:516–526 結帳發票資訊區四類型／三載具／統編檢核／捐贈碼） | 我方研究，可改 |
| 台灣法規原文 | **尚未由本專案覆核** | ⚠ 一律標待查證，不寫死法律結論 |

凡下表「台灣法遵動作」欄出現 `⚠` 者，代表**機制可先實作、法律結論不得由本規格臆測**（沿用 16-F7.4(b) 對消保法的同一處置原則）。

### B.1 總表（30 條）

| # | 事件 | 稅務後果 | 台灣法遵動作（開立／折讓／作廢／重開） | 觸發時機 | 失敗補償 | 對應規格章節 |
|---|---|---|---|---|---|---|
| **T01** | 訂單成立且付款成功（`issue_timing = on_payment`） | 銷售實現 | **開立**（`einvoices.state: reserved → issuing → issued`） | 非同步（outbox `einvoice/issue_requested`，與訂單同 transaction 寫入、transaction 外執行） | 開立失敗不回滾訂單；進「開立失敗待重試」，`attempts` 累加；永久失敗標 `number_burned` 供字軌對帳 | 16-F5.5(a)、38:1103、38:1301–1332 |
| **T02** | **整張訂單出貨完成**（`issue_timing = on_fulfillment`，**官方建議值**） | 同上 | **開立** | 非同步（F3 出貨 transaction 的 outbox） | 同上 | 16-F5.5(a)、38:876 |
| **T03** | **部分出貨**（`issue_timing = on_fulfillment` 且訂單分多次出貨） | 同上，但**開立粒度未定義** | ⚠ **待查證 V-23**：每次出貨各開一張／全部出完才開一張，二者互斥。**在定案前 `on_fulfillment` 模式對多次出貨訂單必須擋下並轉人工佇列，不得靜默選一邊** | — | — | **G-01（P0）** |
| **T04** | 買家收貨（`issue_timing = on_delivery`）；`PICKUP_POINT` 以**實際領件時間**為準 | 同上 | **開立** | 非同步（`fulfillmentEventCreate: DELIVERED` / `READY_FOR_PICKUP` 後的實際領件） | 同上 | 16-F3.3(c)、38:876 |
| **T05** | 訂單取消，**尚未開立發票** | 無 | **no-op**（不得產生孤兒作廢） | 同步判定 | — | 16-F5.5(c) 第 3 點 |
| **T06** | 訂單取消，**已開立**（全額） | 銷售未實現 | **作廢**（`VoidJob`）；作廢窗已關 ⇒ **改開全額折讓** | 非同步（`einvoice/void_requested`） | 發票 job 失敗**不得**回滾取消 | 16-F5.5(a)、38:1104、**G-03** |
| **T07** | 全額退款（本次退款額 == 該張發票金額，且未折讓過） | 銷貨退回 | **作廢**；作廢窗已關 ⇒ 全額折讓 | 非同步（`einvoice/refund_routed`） | 同上 | 16-F5.5(b)、38:1341 |
| **T08** | 部分退款 | 銷貨折讓 | **折讓**（`AllowanceJob`，`einvoice_allowances` +1 筆） | 非同步 | 同上 | 16-F5.5(b) |
| **T09** | 超額退款（退款額 > 發票金額） | 超出部分無稅務憑證可沖 | **就發票金額作廢／折讓至歸零；超出部分不得產生折讓**，轉人工佇列 | 非同步 | 同上 | **G-02（P0）**，修正 38:1341 |
| **T10** | **多次部分退款**（同一發票的第 2、3…次） | 銷貨折讓累加 | **每次各開一張折讓**，且 `Σ 折讓金額 ≤ 發票金額`（累計上限） | 非同步 | 同上 | **G-02（P0）** |
| **T11** | 訂單編輯 commit 造成**總額下降** | 銷貨折讓 | **折讓** | 非同步（F8.1(c) commit transaction 的 outbox） | 同上 | 16-F5.5(a) 第 4 列（NP1-F） |
| **T12** | 訂單編輯 commit 造成**總額上升** | 追加銷售 | **補開一張新發票**（**不是**改原發票） | 非同步 | 同上 | 16-F5.5(a) 第 4 列；**G-04（P0：一訂單多發票的資料模型未支援）** |
| **T13** | 換貨（等值互換，`net == 0`） | ⚠ 無金流變動但品項改變 | ⚠ **待查證**：等值換貨是否須「折讓原發票＋重開」。暫定 **no-op**（無金額變動＝無折讓基數） | — | — | **G-09（P1）** |
| **T14** | 換貨（買家補差額，`net < 0`） | 追加銷售 | **補開一張**（金額＝`balance_to_collect`） | 非同步（補款成功後） | 同上 | **G-09（P1）** |
| **T15** | 換貨（退差額，`net > 0`） | 銷貨折讓 | **折讓**（金額＝實際退還金流額） | 非同步 | 同上 | **G-09（P1）** |
| **T16** | 退貨費用扣抵（重新上架費／退貨運費） | 影響折讓基數 | **不另開立**——費用本來就沒有從 `net` 退出去，折讓基數天然不含它（見 §B.3）。⚠ 若費用本身應課稅（V-16／16-F5.1 X5 待查證），則另需一張「收取費用」的發票，**目前不做** | — | — | 16-F5.1 X5、`limits.refund.return_fees_taxable: false` |
| **T17** | COD 未取件退回（`PENDING → VOIDED`） | 銷售未實現，**且款項從未收到** | **作廢**。⚠ 但 router 的「退款金額 vs 發票金額」比較在此失效（退款額為 0）——必須改以**訂單層事件**（`VOIDED`）觸發作廢，不能走退款路徑 | 非同步 | 同上 | 16-F4.4 第 5 列；**G-05（P0）** |
| **T18** | 爭議敗訴（chargeback lost，資金被扣回） | ⚠ 是否構成銷貨退回未定義 | ⚠ **待查證 V-24**。暫定：**不自動折讓**，開人工工單由合規窗口判定 | — | — | **G-08（P1）** |
| **T19** | **禮品卡發行／售出** | ⚠ 台灣「商品禮券」的開立時點為二選一 | ⚠ **待查證 V-21**：模式 A＝發行時開立、兌換時不再開立；模式 B＝發行時不開立、兌換時開立。**兩者互斥，選定其一後必須全系統一致** | — | — | **G-06（P0）** |
| **T20** | 禮品卡兌換使用（結帳扣抵） | ⚠ 與 T19 互斥 | ⚠ 同 V-21。**最危險的錯誤是兩邊都開 ⇒ 同一筆銷售開兩張發票（重複課稅）** | — | — | **G-06（P0）** |
| **T21** | 禮品卡到期／停用（餘額未用完） | ⚠ 未定義 | ⚠ 待查證 V-21 延伸。暫定：**不產生任何稅務動作**，只寫 `gift_card_transactions` 供對帳 | — | — | **G-06（P0）** |
| **T22** | 商店抵用金**發放** | ⚠ 非銷售行為 | ⚠ **待查證 V-22**。暫定：**不開立**（發放抵用金不是銷售，是負債認列） | — | — | **G-07（P0）** |
| **T23** | 商店抵用金**用於結帳** | ⚠ 影響發票金額基數 | ⚠ **待查證 V-22**：抵用金是「付款方式」（發票金額 ＝ 商品總額，含抵用金支付部分）還是「折扣」（發票金額 ＝ 扣除抵用金後的實收）。**二選一直接決定發票金額** | — | — | **G-07（P0）** |
| **T24** | 退款分配到**禮品卡／商店抵用金**的部分 | 影響折讓基數 | ⚠ **V-20（本檔擴大至抵用金）**：覆核前 router 一律傳「**扣除禮品卡與抵用金分配後**的實際金流退款額」 | 非同步 | — | 16-F5.5 表後、§B.3 |
| **T25** | 跨境 DDP（含關稅，`inclusiveDutiesPricingStrategy`） | 關稅與稅金 | **M4 刻意不做**（46a:820 逐字「S52 明言仍在 developer preview 且回傳值不準」）；schema 預留 `refund_duties` | — | — | 46a:820、29 §Duties（P2） |
| **T26** | 跨境 DDU／外銷 | 零稅率 | ⚠ 外銷零稅率發票的開立規則**未由本專案覆核**；M4 範圍內僅支援台灣境內銷售 | — | — | **G-19（P2）** |
| **T27** | B2B 統編（三聯式） | 進項憑證 | **開立**時 `buyer_type = b2b`、`buyer_tax_id`；統編 8 碼檢核（權重 1,2,1,2,1,2,4,1）⚠ **現行規則含「可被 5 整除」的放寬與否＝V-04 待查證** | 同 T01–T04 | 統編格式錯誤在**結帳期**擋下，不得留到開立時才失敗 | 42:522、38:1400、V-04 |
| **T28** | 捐贈發票 | 捐贈 | **開立**時帶愛心碼（3–7 碼）；**不寄發票給買家** | 同上 | 捐贈碼無效在結帳期擋下 | 42:523 |
| **T29** | 載具（會員載具／手機條碼／自然人憑證） | 存入載具、中獎通知 | **開立**時帶 `carrier_type` / `carrier_id`；手機條碼 `^/[0-9A-Z.+-]{7}$`、自然人憑證 2 大寫字母＋14 數字 | 同上 | 格式錯誤結帳期擋下 | 42:521、38:1003 |
| **T30** | 商店調整稅率設定 | 舊訂單不受影響 | **不回溯**：發票金額與稅額一律取**訂單快照**，不得用現行稅率重算 | — | — | 15-F2「訂單存快照」、16-F5.1 X2 |

### B.2 會造成「已開立發票需折讓／作廢／重開」的 11 個事件

`T06`（取消已開立）、`T07`（全額退款）、`T08`（部分退款）、`T09`（超額退款）、`T10`（多次部分退款）、`T11`（編輯總額下降）、`T12`（編輯總額上升 ⇒ 補開）、`T14`（換貨補差 ⇒ 補開）、`T15`（換貨退差 ⇒ 折讓）、`T17`（COD 退回 ⇒ 作廢）、`T24`（退款含禮品卡／抵用金分配 ⇒ 折讓基數受影響）。

**判定樹（本檔收斂版，取代 38:1341 的單張單次版）**

```
route(order, refund_cash_cents):                      # refund_cash_cents 見 §B.3 定義
  # 0. 在途保護：開立中的發票不得被當成「沒有發票」
  if order.einvoices.exists?(state: 'issuing'):
      return :defer                                   # 延後重試，🔴 不得 no-op（G-10）

  invoices = order.einvoices.where(state: 'issued')
  return :no_invoice if invoices.empty?               # 尚未開立 ⇒ no-op（T05）

  # 1. 沖銷順序：能追溯到品項的先沖該張；不能追溯者 LIFO（後開的先沖）
  #    理由：後開的發票離作廢窗關閉最遠，優先沖它可最大化「可作廢」的機會。
  #    ⚠ 本專案決策（無官方來源），limits.einvoice.allowance_offset_order
  ordered = traceable_by_line_item(invoices) + invoices_not_traceable.sort_by(&:issued_at).reverse

  remaining = refund_cash_cents
  for inv in ordered:
      allowed = inv.total_cents - inv.allowances.sum(:amount_cents)   # 該張剩餘可沖額（累計上限）
      take    = min(remaining, allowed)
      next if take == 0
      if take == inv.total_cents and inv.allowances.empty? and EinvoiceVoidPolicy.window_open?(inv):
          VoidJob(inv, reason: 'fully_refunded')      # 全額 + 未折讓過 + 作廢窗未關 ⇒ 作廢
      else:
          AllowanceJob(inv, amount_cents: take)       # 其餘一律折讓（含「本該作廢但窗已關」）
      remaining -= take

  # 2. 超額退款：沒有稅務憑證可沖，不得憑空產生折讓
  enqueue_manual_review(order, remaining) if remaining > 0            # T09
```

**四條不變量（nightly 對帳斷言）**
1. `Σ einvoice_allowances.amount_cents(per invoice) ≤ einvoices.total_cents`——**任何時刻**成立（DB 層以條件式 UPDATE 保證）。
2. `Σ 該訂單所有 issued 發票的 total_cents ≥ Σ 該訂單實收金流`（不得少開）。
3. 每一筆 `refunds` 都能對應到 0 或 1 筆 `void` ＋ N 筆 `allowance`，**不得對應到 0 個稅務動作**（除非 `:no_invoice`）。
4. 全程 integer cents；`refund_cash_cents` 傳入 float 即 `raise`（38:1508 既有測試要求，本檔延用）。

### B.3 折讓基數的收斂定義（54 號 V-20 的處置：**機械部分收斂、兩個未知項明確保留**）

```
# 折讓基數（integer cents，全程精確整數運算）
refund_cash_cents                                   # ＝ 送進 router 的金額
  = Σ allocation[t].amount_cents  for t in F5.4 的分配結果
  − allocation[gift_card]                           # ⚠ V-20  暫扣除
  − allocation[store_credit]                        # ⚠ V-22  暫扣除（本檔新增）
  # 退貨費用（restocking / return shipping）不需另扣：它們在 F5.1 的 net 階段就沒被退出去，
  # 因此 Σallocation 天然不含它們。**不得重複扣一次**（重複扣＝折讓金額偏低＝短報銷貨退回）。

# 折讓單的未稅／稅額拆分（含稅定價，台灣預設 taxes_included = true）
allowance_total_cents   = refund_cash_cents 分配到該張發票的部分（見 §B.2 判定樹的 take）
allowance_untaxed_cents = floor( allowance_total_cents * 10000 / (10000 + tax_bp) )   # ← 唯一捨入點：floor
allowance_tax_cents     = allowance_total_cents − allowance_untaxed_cents             # 差額法，保證兩者相加精確等於含稅額

# 未稅定價（taxes_included = false）
allowance_untaxed_cents = 該次退款分攤到的未稅金額（走 16-F5.1 X2 的最大餘數法）
allowance_tax_cents     = 該次退款分攤到的稅額（同上，餘數歸最後一次 ⇒ X3）
allowance_total_cents   = allowance_untaxed_cents + allowance_tax_cents
```

**收斂了什麼／保留了什麼**

| 項 | 狀態 | 說明 |
|---|---|---|
| 折讓基數 ＝ **實際金流退款額**（不是退貨品項價值、不是 `suggested_refund` 名目值） | ✅ **收斂** | 名目值與實付值在有換貨／有欠款時不相等；用名目值會多開折讓 |
| 退貨費用**不從基數再扣一次** | ✅ **收斂** | 這是本輪新發現的重複扣風險，明文寫死 |
| 稅額拆分用 **floor 未稅 ＋ 差額法算稅** | ✅ **收斂**（機械部分） | 保證 `未稅 + 稅 == 含稅` 精確相等，無 1 分錢漂移 |
| 累計上限 `Σ 折讓 ≤ 發票金額` | ✅ **收斂** | 條件式 UPDATE，見 §B.2 不變量 1 |
| **禮品卡分配是否計入基數** | ⚠ **保留（V-20）** | 台灣實務上商品禮券退回未必等同現金退款；**與 T19/T20 的模式選擇連動**——若採「發行時開立」，禮品卡支付部分本就已開過票，退還禮品卡不應再折讓 |
| **商店抵用金分配是否計入基數** | ⚠ **保留（V-22，本檔新增）** | 與 T23「抵用金是付款方式還是折扣」是同一個問題的兩面 |
| **稅額拆分的法定捨入方向** | ⚠ **保留** | floor 未稅是本專案決策；主管機關對折讓單金額拆分的捨入規定尚未覆核 |

> **為什麼可以收斂機械部分卻保留兩個未知項**：兩個未知項只影響**基數的加減項**，不影響**公式結構、捨入位置與累計上限**。先把結構寫死，覆核後只需改 `limits.einvoice.allowance_base_excludes` 一個陣列，不必動任何程式邏輯。這與 54 號對 V-02（市場 shipping 繼承）「欄位先建、解析器留兩套策略開關」的處置同一原則。

---

## C. 交叉矩陣：金流寫入點 × 稅務事件

**尺寸 41 × 6**（246 格）。**用法**：改動任一金流路徑時，逐列對照本表——**列上有 ● 或 ○ 的，程式碼改動必須同時涵蓋稅務側**。這張表就是「改了 A 忘了 B」的防呆清單。

**符號**：`●` 必然伴隨　`○` 條件成立時伴隨　`—` 不會伴隨　`⚠` 語義未定義（見 §D）

| 金流寫入點 | 開立 | 折讓 | 作廢 | 補開 | 不涉稅 | ⚠未定義 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| M01 訂單成立（付款成功） | ○<sub>T01</sub> | — | — | — | ○ | — |
| M02 PaymentIntent 授權 | — | — | — | — | ● | — |
| M03 授權到期 | — | — | — | — | ● | — |
| M04 取消授權 void | — | — | ○<sub>T06</sub> | — | ○ | — |
| M05 請款①結帳時自動 | ○<sub>T01</sub> | — | — | — | ○ | — |
| M06 請款②整單出貨後 | ○<sub>T02</sub> | — | — | — | ○ | — |
| M07 請款③每次出貨（Plus） | ○<sub>T02</sub> | — | — | — | — | **⚠<sub>T03</sub>** |
| M08 手動請款（可部分多次） | ○<sub>T01</sub> | — | — | — | ○ | **⚠<sub>T03</sub>** |
| M09 `refundCreate` | — | ●<sub>T08/T10</sub> | ○<sub>T07/T09</sub> | — | — | — |
| M10 `returnProcess` | — | ●<sub>T08/T10</sub> | ○<sub>T07</sub> | — | — | — |
| M11 退貨費用扣抵 | — | ○（改變基數） | — | — | ○<sub>T16</sub> | ⚠（費用課稅 V-16） |
| M12 換貨差額 | — | ○<sub>T15</sub> | — | ○<sub>T14</sub> | — | **⚠<sub>T13</sub>** |
| M13 `orderCancel`（含退款） | — | ○ | ●<sub>T06</sub> | — | ○<sub>T05</sub> | — |
| M14 `charge.refunded` 回寫 | — | — | — | — | ● | — |
| M15 編輯 commit 差額 >0 | — | — | — | ●<sub>T12</sub> | — | — |
| M16 編輯 commit 差額 <0 | — | ●<sub>T11</sub> | — | — | — | — |
| M17 補款結帳付款成功 | ○ | — | — | ●<sub>T12</sub> | — | — |
| M18 COD 訂單成立 | ○<sub>T01</sub> | — | — | — | ○ | — |
| M19 COD 對帳回寫 paid | ○<sub>T01</sub> | — | — | — | ○ | — |
| M20 COD 未取件退回 | — | ○ | ●<sub>T17</sub> | — | — | **⚠<sub>T17</sub>** |
| M21 `orderMarkAsPaid` | ○<sub>T01</sub> | — | — | — | ○ | — |
| M22 `draftOrderComplete` | ○<sub>T01</sub> | — | — | — | ○ | — |
| M23 抵用金發放 | — | — | — | — | ○<sub>T22</sub> | **⚠<sub>T22</sub>** |
| M24 抵用金結帳扣抵 | ○ | — | — | — | — | **⚠<sub>T23</sub>** |
| M25 抵用金到期 | — | — | — | — | ● | — |
| M26 退款退至抵用金 | — | ○ | — | — | — | **⚠<sub>T24</sub>** |
| M27 禮品卡後台發卡 | — | — | — | — | ○ | **⚠<sub>T19</sub>** |
| M28 禮品卡商品售出發卡 | ○<sub>T19-A</sub> | — | — | — | ○<sub>T19-B</sub> | **⚠<sub>T19</sub>** |
| M29 禮品卡儲值 | — | — | — | — | ○ | **⚠<sub>T19</sub>** |
| M30 禮品卡結帳扣抵 | ○<sub>T20-B</sub> | — | — | — | ○<sub>T20-A</sub> | **⚠<sub>T20</sub>** |
| M31 禮品卡停用 | — | — | — | — | ● | **⚠<sub>T21</sub>** |
| M32 退款回補禮品卡 | — | ○ | — | — | — | **⚠<sub>T24</sub>** |
| M33 爭議開立 | — | — | — | — | ● | — |
| M34 爭議勝訴 | — | — | — | — | ● | — |
| M35 爭議敗訴 | — | ○ | — | — | ○ | **⚠<sub>T18</sub>** |
| M36 保留金 hold/release | — | — | — | — | ● | — |
| M37 負餘額回收 | — | — | — | — | ● | — |
| M38 平台方案費出帳 | ●（**平台自己的發票**，非租戶電子發票） | — | — | — | — | — |
| M39 GMV 抽成 | ●（同上） | — | — | — | — | — |
| M40 平台扣款 | — | — | — | — | ● | — |
| M41 撥款鏡像 | — | — | — | — | ● | — |

**三條讀表結論**

1. **「必然伴隨稅務事件」的只有 7 條**：M09／M10（退款 ⇒ 折讓）、M13（取消已開立 ⇒ 作廢）、M15／M17（編輯加收 ⇒ 補開）、M16（編輯減收 ⇒ 折讓）、M20（COD 未取件退回 ⇒ 作廢）。這 7 條是**寫程式時必須成對出現**的，任一條缺了稅務側都是稅務錯誤——目前 M20 的對接是錯的（G-05）。
2. **「不涉稅」的 13 條要明文標註**：11 條完全不涉稅（M02／M03／M14／M25／M31／M33／M34／M36／M37／M40／M41）＋ 2 條走**平台自己的帳單發票**而非租戶電子發票（M38／M39——兩者名稱都叫「發票」，是命名衝突的高風險點）。不標註的話，下一輪稽核會把它們當成「漏了稅務掛鉤」重新開單——這是 54 號 P1-06 的既有教訓（「不標註的『沒做』下一輪稽核會重新開單」）。
3. **⚠ 未定義的 15 格集中在五個區塊**：禮品卡（M27–M32，**6 格**）、商店抵用金（M23／M24／M26，**3 格**）、換貨與部分出貨（M07／M08／M12／M20，**4 格**）、退貨費用是否課稅（M11，1 格）、爭議敗訴（M35，1 格）。這正是 §D 的 P0 集中處——**盤點的價值就在這裡：這些區塊在既有 40 份文件裡各自都「有規格」，但它們的稅務交界從來沒有人寫過。**

---

## D. 缺口清單（24 條）

> 分佈：**P0 8 條**（照現有規格開發會算錯錢／重複開立發票／稅務申報錯誤）／**P1 11 條**／**P2 5 條**。
> 「本輪處置」欄：✅＝已直接修對應規格檔（改動清單見 §D.4）；⚠＝標待查證或需另案決策；📌＝已明文登記待 M4 實作時處理。

### D.1 P0（8 條）

> **⚠ 法域分流（2026-08-12 後補，見下表最右欄）**——本檔成文時的預設法域是**台灣**；使用者已裁定基準法域為**香港**（`CLAUDE.md` 鐵律 11、56 號）。
> **本檔的方法與發現一條未推翻**，但下列 8 條 P0 中有 **4 條的處置在 HK 不成立、其中 2 條照搬會出事**。分流結論見 56 §E.1，逐條落地見 **57 號**。
> <!-- 依 56 §E 分流補寫「法域適用性」欄。原 §D.1 六欄，右起新增第 7 欄。既有六欄一字未改（56 §C.3 不刪除聲明）。 -->

| # | 缺口 | 錯誤後果 | 為什麼是 P0 | 本輪處置 | **法域適用性（56 §E／57）** |
|---|---|---|---|---|---|
| **G-01** | **部分出貨時 `issue_timing = on_fulfillment` 的開立粒度未定義** | 一張訂單分三次出貨：可能開三張（總額 3 倍）、可能一張都沒開（漏開）、可能開一張全額（提前開立未出貨部分）。三種實作都「看起來合理」 | 38:876 只寫「出貨（建議）」，沒有定義多次出貨；這是台灣最常見的出貨型態（超商取貨常拆單），錯了就是**系統性重複開立或系統性漏開** | ⚠ **V-23**；✅ 已在 `limits.einvoice.partial_fulfillment_issue_granularity: null` ＋ **定案前該組合擋下轉人工佇列**（不得靜默選一邊） | 🔴 **HK：N/A 且處置有害**。`tax_invoice: none` ⇒ 無粒度問題；「擋下轉人工佇列」照搬會卡死**所有多次出貨的訂單**。已加法域條件（`block_multi_fulfillment_when_undecided`，hk:false／tw:true），呼叫端 `16-F5.5(a)`。**57 §G-01** |
| **G-02** | **折讓沒有累計上限檢查**——`38:1341` 用 `refund.amount_cents >= invoice.total_cents` 判定，只看**本次**退款額 | 兩次各退 60% ⇒ 開出兩張各 60% 的折讓 ⇒ **折讓總額 120% > 發票金額**，稅務申報直接錯誤且不可逆 | 與 A.2 的「多次寫入必須有累計上限」同一類錯誤，只是落在稅務側；`einvoice_allowances` 表存在但無任何累計約束 | ✅ 已修 `38 §6-3` router ＋ `16-F5.5(b)`；新增不變量 `Σ allowances ≤ invoice.total_cents` | **稅務側 HK N/A**（無折讓）⇒ 移入 tw pack。🔴 **金流側 `Σ refunded ≤ maximumRefundable` 法域無關，必須留著**（§A.2 M09/M10）——56 §E.1 標「容易誤刪」。可測式子（條件式 UPDATE／併發情境／錯誤碼）已補 `16-F5.1`。**57 §G-02** |
| **G-03** | **作廢窗已關時沒有 fallback**——`EinvoiceVoidPolicy.window_open?` 掛勾存在（38:1356）但 router **從不呼叫它** | 跨期別的全額退款會嘗試作廢 → 加值中心拒絕 → 發票卡在 `issued`、退款已生效、**該筆銷售永遠沒有沖銷憑證** | 掛勾寫了卻沒接上＝比沒寫更糟（會讓人以為已處理）；與 54 號 P1-09「模組完整實作但沒有呼叫端」是同一種缺陷 | ✅ 已修：`window_open? == false` ⇒ **降級為全額折讓**（不是失敗） | **HK：N/A**（無作廢機制 ⇒ 無作廢窗）。整條移入 tw pack。🔴 但「掛勾寫了卻沒接上＝比沒寫更糟」的**教訓**升格為法域層通則（56 §A.3 禁止靜默略過），G-01 的旗標無人讀正是同一病根。**57 §G-03** |
| **G-04** | **一張訂單多張發票的資料模型未支援**——`38:1346` 逐字 `refund.order.einvoice`（**單數**），暗示 `(shop_id, order_id)` 唯一 | 但 `16-F5.5` 第 4 列明寫「總額上升 ⇒ **補開一張**」，且 G-01 定案若為「每次出貨各開一張」也會產生多張。兩份規格**直接矛盾**，照 38 實作則補開必定失敗 | 這是 schema 級決定（是否對 `(shop_id, order_id)` 建唯一索引），**上線後改不得**，與 P0-08（`return_line_items` 外鍵）同性質 | ✅ 已修 `38 §3B` 表註釋 ＋ `limits.einvoice.multiple_invoices_per_order_allowed: true`（明寫**不得**建該唯一索引） | **稅務理由 HK N/A**（該表恆空）；🔴 **結論保留**——schema 取所有 pack 的聯集。裁決值原本只在 `jurisdictions.tw.*`（`enabled: false`），已提到核心層 `limits.jurisdiction.schema_union_rules` ＋ `06 §7.1`。**schema 級，優先做。57 §G-04** |
| **G-05** | **COD 未取件退回的作廢無法經由退款 router 觸發**——退款金額為 0（款項從未收到），router 的三分支（`==`／`<`／`>`）全部落到「折讓 0 元」 | 開了一張 0 元折讓，原發票仍有效 ⇒ 一筆從未成立的銷售留著全額發票 | 16-F4.4 第 5 列已寫「觸發 F5.5 的發票 router」，但 router 的入參語義不成立——**規格之間對接錯誤，不是遺漏** | ✅ 已修 `16-F4.4` ＋ `16-F5.5(a)`：COD 退回走**訂單層 `einvoice/void_requested`**，不走退款路徑 | **憑證面 HK N/A**；🔴 **訂單層 `PENDING → VOIDED` 的金流與庫存處理原樣保留**。事件改為法域中性的 `TaxEvent(sale_uncollected)`。原始教訓（router 入參語義不成立）在 HK 完全不變。**57 §G-05** |
| **G-06** | **禮品卡的稅務處理完全未定義**（T19/T20/T21） | 「發行時開立」與「兌換時開立」兩制若混用 ⇒ **同一筆銷售開兩張發票（重複課稅）**；若兩邊都不開 ⇒ 漏開 | 禮品卡在專案內只有 22:116 一行按鈕描述與 28 §8 的 4 支 mutation，**沒有任何規格檔**；而它同時是金流（M27–M32，6 條）與稅務（T19–T21，3 條）的交會點 | ⚠ **V-21**；✅ 已建 `limits.gift_card` 區塊（含 `tax_event_on_issue` / `on_redeem` 皆 `null` ＋ **解析器在未定案時拒絕啟動**，比照 V-02 的處置） | 🔴 **HK：問題性質改變且已有答案**（HKFRS 15 合約負債，非「開立時點二選一」）。`resolver_refuses_start_when_undecided` 已移入 `jurisdictions.tw.accounting` 限定 TW——照搬會讓**禮品卡在香港永遠無法啟用**。**57 §G-06** |
| **G-07** | **商店抵用金的稅務定位與併發安全皆未定義**（T22/T23 ＋ M23/M24） | ①抵用金是「付款方式」或「折扣」直接決定發票金額（差額＝抵用金全額）②`storeCreditAccountDebit` 無冪等、無條件式 UPDATE ⇒ 兩分頁同時結帳可**超額扣抵** | `limits.store_credit` 有 5 個鍵但**沒有任何規格章節**；金額路徑與稅務路徑雙缺 | ⚠ **V-22**；✅ 已補 `limits.store_credit` 併發與稅務鍵、`idempotency.required_for` 加兩支 mutation | **不消失，只改性質**：TW＝決定**發票金額**（V-22）；HK＝決定**收入認列金額**（V-29，HKFRS 15）。🔴 **併發安全那一半法域無關**，不得因「移到會計層」而漏掉。HK 定案前 `record_with_undetermined_basis`，**不擋發放與使用**。**57 §G-07** |
| **G-08** | **`orderCapture` / `orderMarkAsPaid` / `draftOrderComplete` / 4 支 giftCard / 2 支 storeCredit 共 **9 支金流 mutation 未列強制冪等** | 重試 ⇒ **重複請款／重複標記已付／重複發卡／重複扣抵**。`orderCapture` 尤甚：支援部分多次請款，重試會直接多扣顧客的錢 | 與 NP1-D（`orderEditCommit`）**完全同性質**——54 號只補了一支，這是同一個系統性缺口的其餘 9 支。`limits.idempotency.required_for` 原本 13 條全部來自「抄官方 17 個清單」，**從未反向盤點我方自己的金流寫入點** | ✅ 已補進 `limits.idempotency.required_for`（+9）＋ 新增 `required_for_platform`（+2） | ✅ **與法域無關，完整適用**，9 支一條不減（`idempotency.jurisdiction_scope: core_all_packs`）。⚠ 但 `required_for_platform` 那 2 支**是 pack-scoped 的**（統一發票專屬，HK 下不存在於 schema）——56 §E 未涵蓋此點。**57 §G-08** |
### D.2 P1（11 條）

| # | 缺口 | 錯誤後果 | 本輪處置 |
|---|---|---|---|
| **G-09** | **換貨的稅務事件完全未定義**（T13/T14/T15）——`16-F7.3` 有八條規則，**無一條提發票** | 換貨補差額不補開、退差額不折讓 ⇒ 稅務金額與實收對不上 | ✅ 已在 `16-F5.5(a)` 掛鉤點表新增換貨列（補差 ⇒ 補開；退差 ⇒ 折讓；等值 ⇒ no-op ＋ ⚠ 標記） |
| **G-10** | **開立在途（`state = 'issuing'`）時退款 → router 判為 `:no_invoice` 而 no-op** | 加值中心 p95 可達數秒（38:1303）；這段窗口內的退款會**永久遺失稅務動作**（發票隨後開出，但沒有任何折讓） | ✅ 已修 router：`issuing` ⇒ **`:defer` 延後重試**，不得 no-op |
| **G-11** | **`config/limits.yml` 完全沒有 `einvoice` 區塊**——38:1467 逐字要求「`config/limits.yml` 加 `einvoice.track_low_ratio: 0.15`、`einvoice.cert_warn_days: 60`」 | 15% 門檻與 60 天憑證告警值散落在 38 的程式碼常數（`LOW_RATIO = 0.15`）中，違反 CLAUDE.md 鐵律 6「上限值一律引用 `config/limits.yml`，不得硬編碼」 | ✅ 已新增 `einvoice` 頂層區塊（19 鍵） |
| **G-12** | **`config/limits.yml` 沒有 `gift_card` 區塊**——面額上限 `≤ $2,000`（41:426、22:116）無處引用 | 同上，硬編碼風險 | ✅ 已新增 `gift_card` 頂層區塊（9 鍵） |
| **G-13** | **`Σ 捕獲 ≤ 授權額` 的累計上限未寫在任何規格**——`16-F4.3` 只寫狀態推導（`AUTHORIZED → PARTIALLY_PAID → PAID`），沒有上限式與併發鎖 | 多次部分請款（M07/M08）可請超過授權額；Stripe 會拒絕，但我方本地帳已寫入 ⇒ 帳實不符 | ✅ 已補 `15-F4.1(d)` 累計上限式＋條件式 UPDATE |
| **G-14** | **手動部分請款沒有可用的冪等鍵**——`15-F4.1(a)` 只寫 `capture-{fulfillment_id}`，手動請款沒有 fulfillment | 實作者只能自創或乾脆不做冪等 | ✅ 已補 `15-F4.1(d)` 的鍵模板（呼叫端 UUID ＋ 服務端 `(order_id, parent_transaction_id, amount_cents, seq)` 第二層） |
| **G-15** | **授權到期（`EXPIRED`）沒有任何 job 規格**——16-F4.3 列了 `EXPIRED` 為終態、`limits.capture.expiry_warning_days_before: 2` 有示警，但**誰把 authorization 轉成 EXPIRED、何時轉**完全沒寫 | 訂單永遠停在 `AUTHORIZED`，商家以為還能請款；報表的「待請款金額」永遠虛高 | 📌 已在本檔 M03 定義（鍵、併發鎖、條件式 UPDATE），實作落點 `16-F4.3` |
| **G-16** | **退款分配（F5.4 的 `allocation`）沒有落庫表** | `Refunds::Allocator` 是純函式、輸出不落庫 ⇒ 無法對帳「這筆退款各退到哪張卡／哪張禮品卡」，也無法支撐 §B.3 的折讓基數計算 | 📌 建議表 `refund_transaction_allocations(shop_id, refund_id, order_transaction_id, gateway, amount_cents)`，唯一鍵 `(refund_id, order_transaction_id)` |
| **G-17** | **退款回補禮品卡餘額（M32）沒有寫入點規格**——F5.4 只寫「分配給禮品卡」，沒寫「禮品卡餘額要加回去」 | 退款分配算對了、卡片餘額沒加 ⇒ 顧客的錢憑空消失 | 📌 依 G-16 的落庫表驅動；`gift_card_transactions` 一筆 `kind=refund_credit` |
| **G-18** | **爭議（chargeback）在租戶側完全無模型**——`order_transactions.kind` 沒有 `chargeback`／`chargeback_reversal`；`OrderDisplayFinancialStatus` 8 值也沒有爭議態 | 平台側 `disputes` 表齊備（37:986），但租戶訂單頁看不到「這筆被爭議了」，`financial_status` 仍顯示 `PAID` | ✅ 已建 `limits.dispute` 區塊（租戶側 transaction kind ＋ 稅務旗標）；規格落點待 M8（37 屬平台側，與 M4 不同波次） |
| **G-19** | **小費（tip）在金額引擎的 Result 結構中無欄位** | `22 §8` 結帳分頁有「小費三檔%」，`15-F2.3` 的 Result 只有 `subtotal/discount/shipping/cod_fee/tax/total` ⇒ 小費**無處存**，且小費是否計入發票金額未定義 | ✅ 已補 `limits.checkout.tip_*`（三檔值 `null` ＋ verify 旗標，44/46c 皆未載明實際檔位） |

### D.3 P2（5 條）

| # | 缺口 | 說明 | 本輪處置 |
|---|---|---|---|
| **G-20** | **草稿訂單（draft order）無專屬規格檔** | `draftOrderComplete` 是金流寫入點（M22）、`draftOrderInvoiceSend` 是應收通知，但專案內只有 28 §4 的 mutation 清單與 22 §1c 的按鈕表 | 📌 建議 M5 另立工項（範圍跨 15／16／28） |
| **G-21** | **外銷零稅率發票規則未覆核** | T26；M4 範圍僅台灣境內銷售 | ⚠ 明文標「M4 不做」，避免下輪稽核重新開單 |
| **G-22** | **`refund_duties` 表未列入 06 §7** | 46a:820 逐字建議「schema 預留 `refund_duties` 表即可」；06 §7 的 15＋8 張表清單中沒有它 | 📌 登記，M4 建表時一併預留 |
| **G-23** | **GMV 抽成的「GMV」口徑未定義是否扣退款** | `billing_gmv_rollups` 有 `gmv_cents` 與 `refund_cents` 兩欄（37:82），但 `commission_cents = gmv_cents * bps / 10000` **沒有用到 `refund_cents`** ⇒ 退款後仍按毛額抽成 | 📌 登記；屬平台計費商業決策，需使用者確認 |
| **G-24** | **沒有「發票 ↔ 訂單」的 nightly 對帳斷言** | 38:1509 有 `ReconcileJob`（本地字軌 vs 加值中心回報），但**沒有**「Σ 發票金額 − Σ 折讓 == Σ 實收金流」的對帳 | 📌 登記；斷言式已在 §B.2 不變量 2 給出 |

### D.4 本輪順手修掉的改動清單

| 檔案 | 行數變化 | 改了什麼 | 對應缺口 |
|---|---|---|---|
| `config/limits.yml` | 541 → **726**（+185） | 新增 `einvoice`（32 鍵）／`gift_card`（12 鍵）／`dispute`（4 鍵）三個頂層區塊；`idempotency.required_for` **+9**、新增 `required_for_platform`（2）與 `business_unique_keys`（5）；`capture` +5 鍵；`store_credit` +5 鍵；`refund` +2 鍵；`checkout` +3 鍵 | G-02/03/04/06/07/08/10/11/12/13/14/16/17/18/19 |
| `docs/specs/16-spec-orders-fulfillment-refunds.md` | 787 → **860**（+73） | `F4.4` COD 退回列改為訂單層作廢＋防回退註記；`F5.5(a)` 掛鉤點表新增**換貨三列**與 **COD 退回列**；`F5.5(b)` 路由判定**整段重寫**（累計上限／作廢窗 fallback／多發票沖銷順序／在途延後／折讓稅額拆分公式）；`F5.5(c)` 加第 5 點；**新增 `F5.5(d)` 四條不變量＋六條必測** | G-02/03/04/05/09/10 |
| `docs/specs/15-spec-cart-checkout-payments.md` | 341 → **385**（+44） | **新增 `F4.1(d)`**：部分請款的累計上限式、條件式 UPDATE、兩層冪等鍵表、與 void 的互斥、四條必測 | G-08/13/14 |
| `docs/specs/38-platform-trust-modules.md` | 2746 → **2790**（+44） | `§6-3` 的 `RefundRouter` **整段重寫**（累計上限／`window_open?` fallback／`issuing` 延後／金流退款額入參／超額轉人工）；`§3B` `einvoice_allowances` 列加累計上限，表後加「🔴 **不得**對 `einvoices(shop_id, order_id)` 建唯一索引」 | G-02/03/04/10 |
| `docs/research/28-api-contract.md` | 397 → **404**（+7） | `§0.6` 冪等段補「本專案另強制的 9 支金流 mutation」＋`required_for_platform`＋第二層業務唯一鍵，附追溯註釋 | G-08 |
| `docs/specs/54-p1-logic-fixes.md` | 486 → **490**（+4） | §4 末尾的「建議」加**結案指標**指向本檔（避免下輪稽核重複開單，沿用 52→50 的既有做法） | — |
| `docs/specs/55-money-tax-event-inventory.md` | **新增** | 本檔 | — |

> **未觸碰**：`docs/specs/37`（平台清結算／爭議屬 W2／M8 波次，本檔只登記 G-18／G-23 不改）、`docs/specs/19`（報表口徑 P1 輪已處理）、`docs/design/*.html`（原型有其他工作流）、`docs/specs/50`（本檔不是 50 號的條目，結案指標留在 54 §4）。

---

## E. `config/limits.yml` 的增補（依 A 表補齊）

> 全部已寫入 `config/limits.yml`。以下為對照說明，**出處欄的官方層級沿用該檔檔頭的 dev／help／live／ours 四級**。

### E.1 `idempotency.required_for` 依 A 表補齊（+9）

| 新增 mutation | 對應金流寫入點 | 為什麼必須強制 | 出處 |
|---|---|---|---|
| `orderCapture` | M05–M08 | 支援**部分請款且可多次**（46c:526）；重試 ⇒ 重複扣款 | ours（46c:508–526 為行為來源，冪等要求為我方決策） |
| `orderMarkAsPaid` | M21 | 兩個 staff 同時標記 ⇒ 兩筆 sale | ours |
| `draftOrderComplete` | M22 | 重複 complete ⇒ 兩張訂單 | ours |
| `giftCardCreate` | M27／M28 | 重複發卡 ⇒ 憑空多出負債 | ours |
| `giftCardCredit` | M29 | 重複儲值 | ours |
| `giftCardDebit` | M30 | 重複扣抵 ⇒ 顧客資損 | ours |
| `giftCardDeactivate` | M31 | 天然冪等，但列入以統一契約 | ours |
| `storeCreditAccountCredit` | M23 | 重複發放 | ours |
| `storeCreditAccountDebit` | M24 | 重複扣抵 ⇒ 顧客資損 | ours |

新增 `idempotency.required_for_platform`（平台域，避免與租戶 GraphQL 層耦合）：`platformEinvoiceVoid`、`platformEinvoiceAllowanceCreate`——兩者的簽名本就有 `idempotencyKey!`（38:1061–1062），列入清單使「唯一真相」成立。

### E.2 新增稅務相關鍵（`einvoice` 頂層區塊）

| 鍵 | 值 | 出處／狀態 |
|---|---|---|
| `track_low_ratio` | `0.15` | 38:1467、38:1265（ours，33 §2.14 轉述）——**38 明文要求進 limits，本檔補上** |
| `cert_warn_days` | `60` | 38:1467、38:910（ours） |
| `issue_timing_options` / `issue_timing_default` | `[on_payment, on_fulfillment, on_delivery]` / `on_fulfillment` | 38:876（ours，「出貨（建議）」） |
| `partial_fulfillment_issue_granularity` | `null` ＋ `verify_*: true` | **⚠ V-23**；`null` 時該組合擋下轉人工佇列 |
| `upload_deadline_hours` | `null` ＋ `verify_*: true` | **⚠ V-06**（38:885 逐字「來自媒體整理…**不得寫死**」） |
| `void_window_policy` | `null` ＋ `verify_*: true` | **⚠ V-06**（38:885、38:1356 掛勾） |
| `allowance_deadline_days` | `null` ＋ `verify_*: true` | **⚠ V-06 延伸**（折讓期限，38 未載） |
| `allowance_cumulative_cap` | `invoice_total` | **本檔新增硬不變量**（G-02） |
| `allowance_tax_split` | `floor_untaxed_then_difference` | 本檔收斂（§B.3），機械規則 |
| `allowance_base_excludes` | `[gift_card_allocation, store_credit_allocation]` ＋ `verify_*: true` | **⚠ V-20（擴大）／V-22** |
| `allowance_offset_order` | `traceable_then_lifo` | 本專案決策（無官方來源） |
| `multiple_invoices_per_order_allowed` | `true` | **G-04**：明寫**不得**對 `(shop_id, order_id)` 建唯一索引 |
| `defer_when_issuing` | `true` | **G-10**：開立在途時退款 router 延後重試 |
| `buyer_types` / `carrier_types` | `[b2c, b2b]` / `[member, mobile_barcode, natural_person_cert]` | 38:1003、42:521（ours） |
| `mobile_barcode_regex` / `natural_person_cert_regex` / `donation_code_length_range` | `^/[0-9A-Z.+-]{7}$` / `^[A-Z]{2}[0-9]{14}$` / `[3,7]` | 42:521–523（ours，我方依台灣法規自訂） |
| `tax_id_length` / `verify_tax_id_checksum_rule` | `8` / `true` | 42:522（ours）；**⚠ V-04**（是否含「可被 5 整除」放寬） |
| `business_tax_rate_bp` | `500` ＋ `verify_*: true` | **我方依台灣法規自訂**；專案內既有假設見 16-F5.2 算例 2「TW 5% 內含」。法規原文未覆核 |

### E.3 其他區塊補鍵

| 區塊 | 新增鍵 | 說明 |
|---|---|---|
| `capture` | `cumulative_cap_source: authorization_amount`、`partial_capture_allowed: true`、`multi_partial_capture_requires_psp_probe: true`、`idempotency_key_template` | G-13／G-14；`multi_partial_capture_requires_psp_probe` 呼應 15-F4.1(a)「必須先探測 PSP 能力，不是只看方案旗標」 |
| `store_credit` | `concurrent_debit_strategy: conditional_update`、`balance_floor_cents: 0`、`tax_event_on_issue: null`、`tax_event_on_use: null`、`verify_tw_tax_treatment: true` | G-07／V-22 |
| `gift_card`（新） | `max_initial_value_cents: 200000`、`deactivate_is_permanent: true`、`balance_floor_cents: 0`、`concurrent_debit_strategy: conditional_update`、`scheduled_send_max_days: 90`、`tax_event_on_issue: null`、`tax_event_on_redeem: null`、`verify_tw_voucher_tax_treatment: true`、`resolver_refuses_start_when_undecided: true` | G-06／G-12／V-21；最後一鍵比照 V-02 的「未定案時解析器拒絕啟動」處置。<br>🔴 **2026-08-12 後已改路徑**：後四鍵（`tax_event_*` ＋ `verify_*` ＋ `resolver_refuses_*`）已移入 `jurisdictions.tw.accounting` 並**限定 TW**；前五鍵（面額／併發／餘額）留在核心 `gift_card`（法域無關）。詳見下方註 |
| `dispute`（新） | `tenant_transaction_kinds: [chargeback, chargeback_reversal]`、`tax_event_on_lost: null`、`verify_chargeback_tax_treatment: true`、`negative_balance_deadline_days: 180` | G-18／V-24；180 天出處 37:531 |
| `refund` | `allocation_persistence_required: true`、`gift_card_refund_credits_balance: true` | G-16／G-17 |
| `checkout` | `tip_enabled_default: false`、`tip_percent_options: null`、`verify_tip_options: true` | G-19；22 §8 只寫「三檔%」未載明檔位值 |

---

## F. ⚠ 待查證（來源未載明）——新增 V-21 ～ V-24，並擴大 V-20

> V-01 ～ V-14 見 `docs/specs/52` §附錄 A；V-15 ～ V-20 見 `docs/specs/54` §3。狀態不變者不重列。
> **規則不變：這些項目一律不自補規則。**

| # | 項目 | 為何不能自行決定 | 就地標記位置 |
|---|---|---|---|
| **V-20（擴大）** | 退款分配到**禮品卡**的部分是否計入折讓基數 → **本檔擴大為：禮品卡 ＋ 商店抵用金兩者** | 原 V-20 只涵蓋禮品卡；`16-F5.4` 的分配結果同時含 `store_credit`（`refundMethods` 支援退至 store credit，46a:743），兩者面臨完全相同的問題 | `16-F5.5` 表後、本檔 §B.3、`limits.einvoice.allowance_base_excludes` |
| **V-21**（新增） | **禮品卡（商品禮券）的開立時點**：發行時開立且兌換不再開立（模式 A）／發行時不開立而兌換時開立（模式 B）；以及**到期未用完餘額**的稅務處理 | 財政部對商品禮券的函釋原文**未由本專案覆核**。兩制互斥，選錯或混用 ⇒ 重複開立或漏開。**不得由規格臆測** | `limits.gift_card.tax_event_on_issue` / `on_redeem`（皆 `null`）＋ `resolver_refuses_start_when_undecided: true`；本檔 §B.1 T19–T21 |
| **V-22**（新增） | **商店抵用金（store credit）的稅務定位**：發放是否為應稅事件；使用時屬「付款方式」（發票金額 ＝ 商品總額）或「折扣」（發票金額 ＝ 扣抵後實收） | 台灣稅法對「平台發放之購物金」的定性未由本專案覆核；二選一**直接決定發票金額**，差額等於抵用金全額 | `limits.store_credit.tax_event_on_issue` / `on_use`（皆 `null`）；本檔 §B.1 T22–T23 |
| **V-23**（新增） | **`issue_timing = on_fulfillment` 在部分出貨情境下的開立粒度** | 38:876／33 §2.14 只寫「出貨（建議）」，未定義多次出貨；Shopify 無此概念（不開台灣發票）故三份官方文檔皆不可能有答案 | `limits.einvoice.partial_fulfillment_issue_granularity: null`；本檔 §B.1 T03、§D G-01 |
| **V-24**（新增） | **爭議敗訴（chargeback lost）是否構成銷貨退回而應開立折讓** | 資金被扣回但**商品未退回**、買賣關係未解除，與一般退款的稅務性質不同；法規與實務作法皆未由本專案覆核 | `limits.dispute.tax_event_on_lost: null`；本檔 §B.1 T18、§D G-18 |

**⚠ V-20 ～ V-24 的法域歸屬（2026-08-12 後補）**

<!-- 依 56 §E 分流補寫。五條全部是**台灣稅務**問題，一律隨 tw pack 走；`jurisdictions.tw.enable_gate`
     已把 V-20/V-21/V-22/V-23/V-24 中的四條（V-20/21/22/23/24 取其在 gate 內者）列為「未結案不得啟用 tw pack」。
     🔴 **但其中三條在 HK 有「同題不同答」的對應項，不是消失**——把它們讀成「HK 沒這個問題」會漏掉整個會計面。 -->

| TW 待查證 | 在 HK 的對應 | 差別 |
|---|---|---|
| **V-21**（禮品卡開立時點二選一） | **無對應——HK 已有答案**（HKFRS 15：售出＝合約負債、兌換＝認列收入）。⚠ 只剩 breakage 估計方法未定（**V-28**） | TW 是「兩制互斥、選錯就重複課稅」；HK 是「方向已定、只差估計參數」。🔴 `resolver_refuses_start_when_undecided` **不得**在 HK 生效——HK 的 `tax_event_*` 本來就永遠是 `null`，照搬會讓禮品卡永遠無法啟用（56 §E.1 G-06，危險等級最高） |
| **V-22**（抵用金：付款方式 vs 折扣） | **V-29**（合約負債 vs 退款負債） | TW 決定**發票金額**；HK 決定**收入認列金額**。差額都等於抵用金全額，但一個錯在稅、一個錯在帳。**答案不可互相套用** |
| **V-24**（爭議敗訴是否開折讓） | **V-30**（HKFRS 下如何沖銷） | 兩邊定案前的處置**相同**：不自動沖銷、開人工工單 |
| **V-20**（禮品卡／抵用金是否計入折讓基數） | **N/A**（無折讓基數這個概念） | 純 TW。但**退款回補至禮品卡 ＝ 合約負債增加**的會計面在 HK 仍在（55 T24／57 §G-07） |
| **V-23**（部分出貨開立粒度） | **N/A** 且處置有害 | 見 §D.1 G-01 最右欄 |

---

## G. 本篇驗收（對照 11 §0）

**金額正確性**
1. §A.2 的 11 條多次寫入路徑，**每一條**都有 100 執行緒併發測試，斷言「總和不突破上限」且「成功＋失敗 ＝ 請求數」。
2. `Σ captured ≤ authorized`：對同一授權發 5 筆各 30% 的 capture ⇒ 恰 3 筆成功、2 筆回 `userErrors`。
3. 同一張禮品卡在兩個 checkout 同時扣抵全額 ⇒ 恰 1 筆成功，`balance_cents` 不為負。
4. 抵用金累計上限：併發入帳至 USD 15,000 邊界 ⇒ 不得突破（`limits.store_credit.max_balance_usd`）。

**稅務正確性（🔴 5–11 全部為 `jurisdiction/tw` only）**

<!-- 依 56 §E 分流，原 55 §D 結論：本組七條驗收皆以「有政府強制憑證」為前提。
     基準法域 HK 的 `tax_invoice: none` ⇒ 折讓／作廢／在途／多發票／稅額拆分**全部不存在**，七條在 HK **一條都跑不起來**。
     🔴 標「TW only」而**不是刪除**——理由沿用 54 §P1-06：「不標註的『沒做』下一輪稽核會重新開單」。
     HK 的等價驗收是**會計正確性**（合約負債方向、breakage 不提前認列、退款回補是負債增加），見 56 §F 18–20 與 57 §G-07。
     ⚠ 兩條例外，**在 HK 仍然必須通過**：
       ① 第 5 條的**金流側**對應物（`Σ refunded ≤ maximumRefundable` 的併發上限）——那是 §A.2 M09/M10，法域無關，
          可測式子見 `16-F5.1(a)–(e)`；本條列在此處講的是稅務側的 `Σ 折讓 ≤ 發票金額`，兩者不可混為一談（56 §E.1「容易誤刪」）。
       ② 第 11 條的**後半**（多次出貨擋單）在 HK 必須**反向斷言**：HK 訂單分三次出貨 ⇒ 三次全部正常完成、不進人工佇列
          （56 §F 驗收 9、57 §G-01）。前半（禮品卡解析器拒絕啟動）在 HK **不得生效**，否則禮品卡永遠無法啟用（57 §G-06）。 -->

5. **折讓累計上限**：對同一張發票連續退款 60% ＋ 60% ⇒ 第一張折讓 60%、第二張折讓**只有 40%**（不是 60%），且 `Σ 折讓 == 發票金額` 後第三次退款轉人工佇列。
6. **作廢窗 fallback**：`window_open? == false` 時的全額退款 ⇒ 產生**全額折讓**而非失敗。
7. **在途保護**：發票 `state = 'issuing'` 時發生退款 ⇒ router 回 `:defer` 並重試，最終仍產生折讓（**不得** no-op）。
8. **多發票**：訂單編輯加收後補開第二張 ⇒ `einvoices` 該訂單 2 列（證明無 `(shop_id, order_id)` 唯一索引）；隨後退款按 §B.2 的順序沖銷。
9. **COD 退回**：未取件退回 ⇒ 產生 `einvoice/void_requested`（**不是** 0 元折讓）。
10. **稅額拆分**：含稅 105 元折讓 ⇒ 未稅 100 ＋ 稅 5，且 `未稅 + 稅 == 含稅` 對 1 ～ 1,000,000 cents 全域 property test 成立。
11. **未定案的擋下**：`limits.gift_card.tax_event_on_*` 為 `null` 時，禮品卡稅務解析器**拒絕啟動**（比照 V-02 的 shipping 解析器）；`partial_fulfillment_issue_granularity` 為 `null` 時，多次出貨 ＋ `on_fulfillment` 的組合被擋下並進人工佇列。

**防呆與防回退**
12. **§C 交叉矩陣做成 CI 檢查**：`app/services` 下任何呼叫 `einvoice/*` outbox 的類別，其對應的金流 service 必須在矩陣中有 ● 或 ○；矩陣標 `—` 的金流 service **不得**寫入 `einvoice/*`（防止有人「順手」加掛鉤）。
13. 全 repo 靜態掃描：`limits.idempotency.required_for` ＋ `required_for_platform` 清單中的每一支 mutation，其 resolver 都必須有 `idempotencyKey` 參數（schema 快照測試）。
14. 靜態掃描：`0.15`／`60`／`200000`（禮品卡面額）等常數不得出現在 `app/` 下，只能出現在 `config/limits.yml`（CLAUDE.md 鐵律 6）。
