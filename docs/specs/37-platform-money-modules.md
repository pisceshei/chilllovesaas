# 37 — 平台後台實作手冊 · 金流線

> 本篇是 `docs/specs/35` 的分冊之一。涵蓋：計費與催繳／清結算（無資金池架構）／爭議與風控（卡組織門檻）。**三個硬約束**：不得代收代付保管資金（電支條例）、爭議率雙分母雙欄、金鑰不得明文入庫。

## 計費與催繳（波次 W1）

> **波次歸屬**：dunning 引擎與 `billing_subscriptions`／`dunning_attempts` 兩表屬 **W1**，且 33 §4 明列「M0 必須先埋」——不埋就得動大表。三層計價模型、計費 KPI、方案目錄屬 **W2**（原型 `billingplans`／`billkpi` 註釋欄標 W2）。畫面落 **M8**。

### 1. 這是什麼、給誰用、解決什麼問題

**這是平台向租戶收「平台服務費」的那條線，不是租戶收貨款的線。** 這句話必須寫進 migration 檔頭與每個 service 的類別註釋：租戶的貨款走租戶自持的通道商戶號直接入租戶帳戶（33 §2.6 台灣紅線，詳見本手冊「清結算」§1），平台永遠碰不到；本模組只處理平台自己的應收。兩者混進同一張表，就是把平台推進《電子支付機構管理條例》的特許範圍。

**給誰用**
| 角色 | 能做什麼 | 出處 |
|---|---|---|
| 平台 `owner` | 全部，含部分豁免（write-off）、費率／方案例外 | 32 §5 |
| 平台 `admin` | 批次重試、延長寬限、方案變更、帳齡表匯出 | 32 §5（對齊「上限覆寫／flags」層級） |
| 平台 `support` | 唯讀＋開工單；**不得改金額或延寬限** | 32 §5 未授權即拒（`FORBIDDEN`） |
| 平台 `read_only` | 唯讀 | 32 §5 |
| 租戶本人 | 只讀自己的帳單與發票歷史；**凍結中仍必須讀得到** | 33 §2.1 例外一 |

**解決什麼**：扣款失敗若無自動化＝人工追債＋忘記凍結＋忘記解凍＋沒有留痕。Dunning engine 把「首次失敗 → D+1／D+3／D+7／D+14 重試 → **D+28 凍結** → **凍結後 60 天**保留終止權」（33 §2.4）變成有倒數、有審計、有手動干預口、可重放的狀態機。

**三層計價**（33 §1 `planbox`／`billingplans` 註釋；對照 SHOPLINE 模組矩陣與 CYBERBIZ 1% 抽成）：
1. **方案月費**（訂閱，年繳／月繳）
2. **模組加購矩陣**（原型 SHOPLINE 對標：促銷活動／CRM 會員行銷／定期購／數據分析 Pro／網紅團購／Smart OMO／全通路進階整合…）
3. **GMV 抽成**（原型示範 1%；租戶詳情 `billsub` 顯示 `NT$(gmv30 × 1%)`）
4. 資源包超額 → 由配額三段式模組（33 §2.10）產生計費事件，本模組只負責出帳

> **待定，需使用者確認**：四個方案（網店探索者／電商戰略家／OMO 大師／全通路領航員）的實際定價、抽成 bps、加購模組單價、年繳折扣率。原型只有 demo 數字（月費 40,000／55,000／68,000 cents 級距不明確）。33 未載明。

**租戶狀態 × 計費行為**（33 §2.1，必須逐格實作，這張表就是 `InvoiceGenerator` 的分支）
| 狀態 | 出帳 | 扣款 | 帳單頁可讀 |
|---|---|---|---|
| `trial` | 否 | 否 | 是（14 天到期 → `past_due`） |
| `active` | 是 | 是 | 是 |
| `past_due` | 是 | 是（dunning 中） | 是 |
| `restricted` | **暫停計費** | 否 | 是（33 §2.1「受限期間暫停計費」，Shopify 明確做法） |
| `paused` | 待定，需使用者確認（Shopify Pause and build 為降價方案，33 未給數字） | — | 是 |
| `frozen` | 停止新出帳，既有應收續存 | 否 | **是（例外一，漏了客服會被打爆）** |
| `closed` | **本期帳單週期結束後**才失去存取 | 結清 | 是（資料保留 2 年） |

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `billkpi`（5 卡：MRR／抽成收入／加購模組／Churn／逾期應收） | 計費總覽 | 三層收入**分別計算**、與財務對帳同源（原型 DOCS `billkpi`）；MRR＝正規化為月的訂閱經常性收入（年繳 ÷ 12），**不含**抽成與加購；抽成與加購獨立卡。所有 KPI 必須從 `platform_daily_rollups` 衍生，不得另寫 SQL（CLAUDE.md 鐵律 7 數字同源） | 三態：載入 skeleton（23 §4-7）／無資料顯示「本期尚無帳單」／查詢失敗 banner＋重試。點卡＝跳對應篩選清單 |
| 「帳齡表」按鈕 | 匯出應收帳齡 CSV | 分桶 `current / 1–30 / 31–60 / 61–90 / 90+` 天（依 `invoice.due_at`，**不依 dunning 寬限**——見 §6 干預規則）；>50 筆轉背景 job＋簽名連結 24h 失效（原型 DOCS `shopexport`） | 匯出中禁重複點；連結逾期回 410 |
| 「催繳政策」按鈕 → `ovDunning` modal | 展示政策與兩條硬線 | 步驟軸：D+1 重試 → D+3 重試＋信 → D+7 重試＋橫幅 → D+14 最後通知 → **D+28 凍結**；紅框：凍結後 **60 天**保留終止權；**不提供延期、不改發票到期日**（33 §2.4） | 唯讀 modal；767px 以下轉貼底 sheet |
| `dunningtable`（催繳中清單） | 欄：商店／方案／欠款／首次失敗／重試／距凍結／動作 | **距凍結 ≤3 天標紅**（原型 DOCS `dunningtable`）；重試顯示 `n／已達上限`（上限 4＝D+1/3/7/14 四次，原型 DUN「4／已達上限」）；金額右對齊 tabular-nums、`NT$` 前綴（CLAUDE.md 鐵律 10） | 已凍結列的「距凍結」欄顯示「已凍結」並改顯示「距終止 n 天」；空清單＝「目前無逾期租戶」正向空狀態 |
| 「批次重試」按鈕 | 對選取列批次觸發扣款 | **逐筆獨立 transaction＋結果報告**（原型 DOCS `bulkops`）；每筆帶獨立 `idempotencyKey`；已達重試上限者跳過並回報 `RETRY_LIMIT_REACHED` | 批次進行中顯示進度；部分失敗不回滾成功者 |
| 列內「重試／延寬限／協商中」 | 手動干預 | 三種：延長寬限（只延**執行凍結時點**，不動 `invoice.due_at`）／部分豁免（owner 四眼）／標記協商中（暫停自動升級、**不停倒數**）。一律落審計（原型 `ovDunning`：「手動干預一律落審計」） | 未選原因不可送出；「其他」需備註（同 32 §2 慣例） |
| `billsub`（租戶詳情 › 計費 › 訂閱與帳單） | 方案／本期／應收／GMV 抽成／付款方式 | **凍結時此頁仍須可讀**（原型 DOCS `billsub`＋33 §2.1）；付款方式只顯示 brand＋last4，**卡號與 token 絕不進 GraphQL 回傳** | 扣款失敗時付款方式 badge 轉 critical |
| `dunning`（租戶詳情 › 催繳歷程 timeline） | 逐次重試與通知的時間軸 | 由 `dunning_attempts` 直出，最新在上；D+28 節點恆存在（未到則顯示「預計 MM-DD」，原型即此行為） | 無紀錄顯示「無催繳紀錄——歷史扣款皆成功」 |
| `billingplans`（平台設定 › 方案與計費模型） | 方案目錄與超額策略 | 超額策略三選一：**軟限告警／硬限阻擋／自動加購**；**降級阻擋規則**（例：連鎖版不可降單店）寫在計費引擎（原型 DOCS `billingplans`） | 方案停售不刪除（既有訂閱續存）；改價只影響新週期 |

---

### 3. 資料模型（金額欄位一律 `_cents BIGINT`）

> 多租戶鐵律：所有租戶表帶 `shop_id BIGINT NOT NULL`，複合索引以 `shop_id` 開頭（CLAUDE.md 鐵律 2）。方案目錄類表為**平台域表**、無 `shop_id`——比照 32 §7 `platform_staffs` 的既有豁免，集中列管並在 migration 檔頭註明豁免理由。

**平台域（無 shop_id，豁免）**
- `billing_plans`：`code`(uniq), `name`, `tier`, `status[active/grandfathered/retired]`, `monthly_price_cents BIGINT`, `annual_price_cents BIGINT`, `gmv_commission_bps INT`, `included_limits JSON`, `downgrade_blocked_to JSON`, `published_at`
- `billing_addons`：`code`(uniq), `name`, `monthly_price_cents BIGINT`, `depends_on_plan_codes JSON`
- `dunning_policies`：`code`(uniq), `retry_offsets_days JSON`（預設 `[1,3,7,14]`）, `final_notice_day INT`（14）, `freeze_day INT`（28）, `terminate_after_freeze_days INT`（60）, `max_grace_days INT`, `active BOOLEAN` — **政策落表而非常數**，理由見 §6 註釋（33 §9 明載 Shopify 重試節奏未公開，只有兩條硬線可查證）

**租戶域**
- `billing_subscriptions`（33 §6）：`shop_id`, `plan_id`, `interval[monthly/annual]`, `status[trialing/active/past_due/paused/canceled]`, `unit_price_cents BIGINT`, `gmv_commission_bps INT`（可覆寫，NULL＝隨方案）, `current_period_start DATE`, `current_period_end DATE`, `trial_ends_at`, `cancel_at_period_end BOOLEAN`, `billing_paused_reason`（`restricted` 暫停計費用）, `lock_version INT`
  索引：`(shop_id)` uniq（一店一訂閱）、`(status, current_period_end)`
- `billing_addon_subscriptions`：`shop_id`, `addon_id`, `qty INT`, `unit_price_cents BIGINT`, `started_on`, `ended_on`　索引 `(shop_id, addon_id, ended_on)`
- `billing_invoices`（33 §6）：`shop_id`, `number`(每平台連號，非每店——這是平台自己的發票), `period_start DATE`, `period_end DATE`, `subtotal_cents BIGINT`, `tax_cents BIGINT`, `total_cents BIGINT`, `paid_cents BIGINT DEFAULT 0`, `waived_cents BIGINT DEFAULT 0`, `currency CHAR(3) DEFAULT 'TWD'`, `issued_at`, `due_at`, `status[draft/open/paid/void/uncollectible]`, `first_failed_at`, `dunning_state`, `freeze_due_on DATE`, `terminate_eligible_on DATE`
  索引：`(shop_id, status, due_at)`、`(status, freeze_due_on)`（排程掃描用）、`(number)` uniq
  約束：`CHECK (total_cents = subtotal_cents + tax_cents)`、`CHECK (paid_cents + waived_cents <= total_cents)`
- `billing_invoice_lines`：`shop_id`, `invoice_id`, `kind[plan/addon/gmv_commission/overage/adjustment]`, `source_ref`, `quantity INT`, `unit_price_cents BIGINT`, `amount_cents BIGINT`, `metadata JSON`　索引 `(shop_id, invoice_id)`
- `billing_payment_methods`：`shop_id`, `provider`, `provider_token_ref VARCHAR`（**只存通道回傳的 token，永不存卡號／CVV**）, `brand`, `last4 CHAR(4)`, `exp_month`, `exp_year`, `status[valid/expired/failed]`, `is_default`　索引 `(shop_id, is_default)`
- `dunning_attempts`（33 §6）：`shop_id`, `invoice_id`, `attempt_no INT`, `scheduled_at`, `claimed_at`, `attempted_at`, `state[scheduled/in_flight/succeeded/failed/skipped]`, `result_code`, `provider_error_code`, `provider_error_message`, `amount_cents BIGINT`, `next_retry_at`, `idempotency_key VARCHAR(64)`
  索引：`(shop_id, invoice_id, attempt_no)` **UNIQUE**（併發兜底，11 §3 第三板斧）、`(state, scheduled_at)`（排程掃描）、`(idempotency_key)` UNIQUE
- `dunning_interventions`：`shop_id`, `invoice_id`, `kind[grace_extension/partial_waiver/mark_negotiating/manual_retry]`, `days INT`, `amount_cents BIGINT`, `reason_code`, `note TEXT`, `staff_id`, `approver_staff_id`（四眼；`partial_waiver` NOT NULL）, `created_at`　索引 `(shop_id, invoice_id, created_at)`
- `billing_gmv_rollups`：`shop_id`, `period_start DATE`, `period_end DATE`, `gmv_cents BIGINT`, `refund_cents BIGINT`, `commission_bps INT`, `commission_cents BIGINT`, `rollup_source VARCHAR`（固定 `platform_daily_rollups`）　索引 `(shop_id, period_start)` UNIQUE
- `payment_events`（通道回調去重）：`provider`, `provider_event_id`, `payload JSON`, `processed_at`　索引 `(provider, provider_event_id)` **UNIQUE**（11 §8-9）

**金額鐵律落地**：`_cents BIGINT`；`gmv_commission_bps` 用 **basis point 整數**（1% = 100 bps），抽成算式 `gmv_cents * bps / 10_000` 全整數運算，禁 `0.01` 之類浮點常數。

---

### 4. API 契約（Platform:: GraphQL）

端點 `/platform/api/{version}/graphql.json`（32 §6）；GID `gid://chilllove/BillingInvoice/{id}`、`gid://chilllove/DunningAttempt/{id}`、`gid://chilllove/BillingPlan/{id}`；cursor 分頁 ≤250、`pageInfo`；金額 `MoneyV2`（序列化層才由 cents 轉 Decimal 字串，28 §0.3）；`userErrors` HTTP 恆 200。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformBillingOverview` | query | `range: DateRange!` | `BillingOverview{ mrr: MoneyV2, commissionRevenue, addonRevenue, churnedShops: Int, overdueReceivable: MoneyV2, overdueShopCount: Int }` | — | read_only+ |
| `platformDunningQueue` | query | `first, after, filter{ daysToFreezeLte: Int, planId, state }` | `DunningEntryConnection` | — | read_only+ |
| `platformBillingSubscription` | query | `shopId: ID!` | `BillingSubscription`（含 `invoices(first)`, `dunningAttempts(first)`） | `NOT_FOUND` | read_only+ |
| `platformInvoiceRetryCharge` | mutation | `invoiceId: ID!, idempotencyKey: String!` | `{ invoice, attempt, userErrors }` | `INVOICE_ALREADY_PAID` `PAYMENT_METHOD_MISSING` `PAYMENT_METHOD_EXPIRED` `RETRY_LIMIT_REACHED` `ATTEMPT_IN_FLIGHT` `IDEMPOTENCY_KEY_REUSED` | admin+ |
| `platformDunningBulkRetry` | mutation | `invoiceIds: [ID!]!（≤250, 28 §0.3）, idempotencyKey: String!` | `{ results:[{invoiceId, ok, code}], userErrors }` | 同上（逐筆） | admin+ |
| `platformDunningGraceExtend` | mutation | `invoiceId: ID!, days: Int!, reasonCode: DunningReason!, note: String` | `{ invoice, userErrors }` | `GRACE_EXCEEDS_MAX` `GRACE_AFTER_FREEZE` `REASON_REQUIRED` | admin+ |
| `platformDunningWaive` | mutation | `invoiceId: ID!, amount: MoneyInput!, reasonCode!, note!, approverStaffId: ID!` | `{ invoice, userErrors }` | `WAIVE_EXCEEDS_BALANCE` `SECOND_APPROVER_REQUIRED` `SELF_APPROVAL_FORBIDDEN` | **owner（四眼）** |
| `platformDunningMarkNegotiating` | mutation | `invoiceId: ID!, until: Date!, note: String!` | `{ invoice, userErrors }` | `NEGOTIATION_WINDOW_EXCEEDS_FREEZE` | admin+ |
| `platformSubscriptionPlanChange` | mutation | `shopId: ID!, planId: ID!, effective: IMMEDIATE\|PERIOD_END, idempotencyKey: String!` | `{ subscription, prorationPreview, userErrors }` | `PLAN_DOWNGRADE_BLOCKED` `PLAN_RETIRED` `OUTSTANDING_INVOICE` | admin+ |
| `platformInvoiceAgingExport` | mutation | `asOf: Date!, format: CSV` | `{ jobId, userErrors }`（>50 筆走 job＋簽名連結 24h） | — | admin+ |
| `platformBillingPlanCreate/Update` | mutation | `input: BillingPlanInput!` | `{ plan, userErrors }` | `PLAN_CODE_TAKEN` `PRICE_MUST_BE_INTEGER_CENTS` | owner |

**全域**
- 未授權一律 `userErrors{code: FORBIDDEN}`（32 §9-6），不回 HTTP 403。
- 所有 mutation 記 `platform_audit_logs`，帶 `previous/next JSON`（33 §2.8）。
- **金額在 API 邊界一律 `MoneyV2`／`MoneyInput{amount: Decimal!, currencyCode}`（Decimal 是字串，不是 float，28 §0.3）；序列化層負責 `Decimal 字串 ↔ integer cents` 轉換，`_cents` 這個表示法只存在於 DB 與 service 層**。前端拿到字串直接格式化，永不參與運算（11 §8-3：JS 端也禁 float 算錢）。

---

### 5. 服務物件與背景任務

| Class | 責任 | 冪等鍵 | 重試 | outbox topic |
|---|---|---|---|---|
| `Platform::Billing::InvoiceGenerator` | 週期結算出帳：方案＋加購＋GMV 抽成（讀 `billing_gmv_rollups`）；`restricted` 跳過（33 §2.1） | `(shop_id, period_start)` UNIQUE on invoice | job 重試 3 次指數退避 | `billing/invoice_created` |
| `Platform::Billing::GmvCommissionCalculator` | 由 `platform_daily_rollups` 聚合成 `billing_gmv_rollups`；**唯一許可的抽成來源** | `(shop_id, period_start)` UNIQUE | 可重跑（upsert） | — |
| `Platform::Billing::ChargeAttempt` | 單次扣款：pending 落地 → **transaction 外**呼叫通道 → 回寫 | `dunning_attempts.idempotency_key` | 通道逾時不自動重試，交回排程（避免重複扣款） | `billing/payment_succeeded\|failed` |
| `Platform::Dunning::Scheduler`（recurring，每 15 分鐘） | 撈 `state=scheduled AND scheduled_at<=now` 的 attempt，條件式 UPDATE 認領後派工 | 條件式 UPDATE claim（11 §3 第一板斧） | at-least-once，靠唯一索引兜底 | — |
| `Platform::Dunning::Machine` | 狀態轉移唯一入口；計算 `freeze_due_on`／`terminate_eligible_on` | 轉移冪等（同態重入 no-op） | — | `billing/dunning_escalated` |
| `Platform::Dunning::EnforcementJob`（recurring，每日 03:00 shop 時區） | D+28 → 觸發 `shop_restrictions` 凍結；D+28+60 → 標 `termination_eligible`（**不自動刪店**，需人工） | `(invoice_id, milestone)` UNIQUE 於 audit | 每日重跑安全 | `shop/freeze_requested` |
| `Platform::Billing::PaymentWebhookHandler` | 通道回調：**接收層恆 200 ＋丟 job**（11 §8-9） | `payment_events(provider, provider_event_id)` UNIQUE | 通道自行重送 | `billing/payment_*` |
| `Platform::Billing::AgingExportJob` | 帳齡表 CSV → 簽名連結 24h | `(as_of, staff_id, requested_at)` | 3 次 | — |

**共通紀律**：所有 job 第一參數傳 `shop_id`，進場 `ActsAsTenant.with_tenant`（11 §8-1）；跨租戶掃描一律在 `Platform::` 內顯式 `without_tenant`（32 §0）。

---

### 6. 關鍵流程與演算法

#### 6.1 催繳排程狀態機與兩條硬線

```ruby
# app/services/platform/dunning/policy.rb
module Platform
  module Dunning
    # 催繳政策（policy object，值來自 dunning_policies 表）。
    #
    # 為什麼落表而不是寫死常數：33 §9 明載「Shopify dunning 重試次數與間隔未公開」，
    # 因此 33 §2.4 的 D+1／D+3／D+7／D+14 是**建議節奏**（可調）；
    # 而 D+28 凍結、凍結後 60 天終止是**可查證的硬線**（不可調，只能由 owner 覆寫單張）。
    # 兩者混成同一組常數，日後調節奏會不小心把硬線一起調掉。
    class Policy
      DEFAULT = {
        retry_offsets_days: [1, 3, 7, 14],   # 33 §2.4 建議；上限 4 次（原型 dunningtable「4／已達上限」）
        final_notice_day: 14,                # D+14 最後通知：email＋商家後台橫幅
        freeze_day: 28,                      # 33 §2.4 硬線一
        terminate_after_freeze_days: 60,     # 33 §2.4 硬線二（僅「保留權利」，不自動執行）
        max_grace_days: 14                   # 待定，需使用者確認（33 未載明寬限上限）
      }.freeze

      def initialize(row) = @row = row || OpenStruct.new(DEFAULT)

      # @param first_failed_on [Date] 首次扣款失敗日（= D+0）
      # @return [Date] 應執行凍結的日期
      def freeze_due_on(first_failed_on) = first_failed_on + @row.freeze_day

      # @return [Date] 凍結後保留終止權的起算日
      def terminate_eligible_on(frozen_on) = frozen_on + @row.terminate_after_freeze_days
    end
  end
end
```

```ruby
# app/services/platform/dunning/machine.rb
module Platform
  module Dunning
    # 催繳狀態機——所有轉移的**唯一入口**（禁止散落 update_column，同 32 §2 慣例）。
    #
    #   none ──首次扣款失敗──▶ retrying ──第 4 次仍失敗──▶ final_notice
    #     ▲                      │                              │
    #     └──── resolved ◀───────┴──付清／豁免──────────────────┘
    #                                                            │ D+28
    #                                                            ▼
    #                                                         frozen ──+60 天──▶ termination_eligible
    #
    #   negotiating：人工標記，**暫停自動升級但倒數不停**（原型 ovDunning：不給延期、不改到期日）
    class Machine
      STATES = %w[none retrying final_notice negotiating frozen termination_eligible resolved].freeze

      # 冪等：同態重入直接回 true，不重發事件（32 §9-2 的驗收條件）
      def transition!(invoice, to:, actor:, reason: nil)
        return true if invoice.dunning_state == to

        ApplicationRecord.transaction do
          prev = invoice.slice(:dunning_state, :freeze_due_on, :terminate_eligible_on)
          invoice.lock!                                   # 併發兩個排程同時升級 → 行鎖收斂（11 §3）
          return true if invoice.dunning_state == to      # double-check under lock
          invoice.update!(dunning_state: to)
          # outbox 與狀態變更同 transaction（11 §8）；寄信在 transaction 外由 job 處理
          Outbox.enqueue!(topic: "billing/dunning_escalated", shop_id: invoice.shop_id,
                          payload: { invoice_id: invoice.id, from: prev[:dunning_state], to: })
          Platform::AuditLog.write!(action: "billing.dunning_#{to}", shop_id: invoice.shop_id,
                                    actor:, reason:, previous: prev, next: invoice.slice(*prev.keys))
        end
        true
      end
    end
  end
end
```

```ruby
# app/services/platform/billing/charge_attempt.rb
module Platform
  module Billing
    # 單次扣款嘗試。
    #
    # 三段式的**唯一理由**：transaction 內禁外部 IO（11 §2-2、§8-2、AGENTS 鐵律 2）。
    # 通道 API 慢 → 鎖持有 → 連線池耗盡 → 全站掛，這是最常見的生產事故源。
    # 因此：①短 transaction 落 pending ②transaction 外打通道 ③短 transaction 回寫。
    class ChargeAttempt
      Result = Struct.new(:ok?, :code, :attempt, keyword_init: true)

      def call(invoice:, attempt_no:, idempotency_key:)
        attempt = claim!(invoice, attempt_no, idempotency_key)      # ① transaction 內
        return Result.new(ok?: false, code: :ATTEMPT_IN_FLIGHT) if attempt.nil?

        # ② transaction 外——通道逾時了也只是這一列停在 in_flight，不會鎖住任何東西
        res = gateway_for(invoice).charge(
          token: invoice.shop.default_payment_method.provider_token_ref,
          amount_cents: invoice.balance_cents,
          # 通道端冪等鍵＝我方 attempt 的鍵，通道重送不會重複扣款
          idempotency_key: attempt.idempotency_key
        )

        finalize!(attempt, res)                                      # ③ transaction 內
      rescue Gateway::Timeout
        # 不在此重試——重試由 Scheduler 依政策排程，否則「同時重試扣款」會變成重複扣款
        mark_unknown!(attempt)
        Result.new(ok?: false, code: :GATEWAY_TIMEOUT, attempt:)
      end

      private

      # 條件式 UPDATE 認領（11 §3 第一板斧，無鎖等待）：
      # affected_rows == 1 才是本進程搶到，否則代表另一個 worker／人工重試已在跑。
      def claim!(invoice, attempt_no, key)
        n = DunningAttempt.where(shop_id: invoice.shop_id, invoice_id: invoice.id,
                                 attempt_no:, state: "scheduled")
                          .update_all(state: "in_flight", claimed_at: Time.current,
                                      idempotency_key: key, updated_at: Time.current)
        n == 1 ? DunningAttempt.find_by!(invoice_id: invoice.id, attempt_no:) : nil
      end

      def finalize!(attempt, res)
        ApplicationRecord.transaction do
          invoice = attempt.invoice.lock!
          if res.success?
            # 金額一律整數 cents；paid_cents 有 CHECK 約束兜底（§3）
            invoice.update!(paid_cents: invoice.paid_cents + res.amount_cents,
                            status: :paid)
            attempt.update!(state: "succeeded", attempted_at: Time.current)
            Machine.new.transition!(invoice, to: "resolved", actor: :system)
          else
            attempt.update!(state: "failed", attempted_at: Time.current,
                            provider_error_code: res.code, next_retry_at: next_retry_at(attempt))
            invoice.update!(first_failed_at: invoice.first_failed_at || Time.current)
            # 首次失敗日只認第一次（D+0 錨點固定），否則每次重試都會把凍結線往後推
            invoice.update!(freeze_due_on: policy(invoice).freeze_due_on(invoice.first_failed_at.to_date))
            schedule_next!(attempt)
          end
        end
        Result.new(ok?: res.success?, code: res.code, attempt:)
      end
    end
  end
end
```

#### 6.2 手動干預：寬限只延「執行凍結」，不延「發票到期日」

```ruby
# app/services/platform/dunning/grace_extension.rb
module Platform
  module Dunning
    # 延長寬限。
    #
    # 為什麼只動 freeze_due_on 不動 due_at：33 §2.4 明文「不給延期、不改發票到期日」，
    # 但原型 ovDunning 又要求後台有「延長寬限」的手動干預口。兩者的調和是——
    # 發票到期日與應收帳齡照舊（財務數字不被人工污染），只延後「執行凍結」這個處分動作。
    # 因此帳齡表分桶依 due_at，不依 freeze_due_on（§2 帳齡表規則）。
    class GraceExtension
      def call(invoice:, days:, reason_code:, note:, actor:)
        return err(:GRACE_AFTER_FREEZE) if invoice.dunning_state.in?(%w[frozen termination_eligible])
        return err(:GRACE_EXCEEDS_MAX)  if days > policy(invoice).max_grace_days
        return err(:REASON_REQUIRED)    if reason_code.blank?

        ApplicationRecord.transaction do
          prev = invoice.slice(:freeze_due_on, :due_at)
          invoice.update!(freeze_due_on: invoice.freeze_due_on + days)  # due_at 不動
          DunningIntervention.create!(shop_id: invoice.shop_id, invoice_id: invoice.id,
                                      kind: "grace_extension", days:, reason_code:, note:,
                                      staff_id: actor.id)
          Platform::AuditLog.write!(action: "billing.grace_extend", shop_id: invoice.shop_id,
                                    actor:, previous: prev, next: invoice.slice(:freeze_due_on, :due_at))
        end
        ok
      end
    end
  end
end
```

**部分豁免（四眼）**：`partial_waiver` 必填 `approver_staff_id`，且 `approver_staff_id != staff_id`（否則 `SELF_APPROVAL_FORBIDDEN`）；豁免額累計不得超過 `total_cents - paid_cents`（DB CHECK 兜底）。對照原型角色矩陣「金流通道變更 ✓＋四眼」的同級處理。

#### 6.3 D+28／D+60 兩條線的執行

```ruby
# app/jobs/platform/dunning/enforcement_job.rb
# 每日 03:00（shop 時區換算，11 §8-5：DB 存 UTC、「今天」用 shop 時區）
class Platform::Dunning::EnforcementJob < ApplicationJob
  def perform(as_of = Date.current)
    ActsAsTenant.without_tenant do
      # 硬線一：D+28 → 凍結（不是刪店，只是狀態轉移＋六旗標）
      BillingInvoice.where(status: "open").where(freeze_due_on: ..as_of)
                    .where.not(dunning_state: %w[frozen termination_eligible resolved])
                    .find_each do |inv|
        # 凍結是租戶生命週期模組的動作，本模組只「請求」——單一入口原則（32 §2）
        Platform::Shops::Restrict.call(
          shop_id: inv.shop_id,
          flags: %i[payin trade readonly offline],       # 33 §2.2 六旗標中的四個
          reason_code: "PAYMENT_OVERDUE", actor: :system,
          # 例外一：凍結時帳單頁仍可讀（33 §2.1）——由 readonly 旗標的白名單路由保證
          readonly_allowlist: %w[/admin/billing /admin/invoices]
        )
        Platform::Dunning::Machine.new.transition!(inv, to: "frozen", actor: :system)
        inv.update!(terminate_eligible_on: policy(inv).terminate_eligible_on(as_of))
      end

      # 硬線二：凍結後 60 天 → 只標記「可終止」，**不自動終止**
      # 為什麼不自動：33 §2.4 的措辭是「保留終止帳號權利」，且 33 §2.1 closed 態有
      # 「資料保留 2 年、子網域永久不可重用」的副作用——不可由 cron 觸發。
      BillingInvoice.where(dunning_state: "frozen").where(terminate_eligible_on: ..as_of)
                    .find_each { |inv| Platform::Dunning::Machine.new.transition!(inv, to: "termination_eligible", actor: :system) }
    end
  end
end
```

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| Rails 8.1 內建 Solid Queue recurring（`config/recurring.yml`） | Rails 8.1 | Scheduler／EnforcementJob 排程 | D1/D4 決策不用 Redis，Solid Queue 已在棧內；不引入 sidekiq-cron |
| `state_machines-activerecord` | ~> 0.100 | `dunning_state` 與 invoice status 狀態機 | 純 AR、無外部依賴、支援 guard／callback；比手寫 case 更容易做「單一入口」靜態檢查。**替代方案 AASM 亦可，擇一即可，不要兩套** |
| `strong_migrations` | ~> 2.x | `billing_*` 大表 DDL 安全 | 11 §2-5 明列（上線後加索引＝停機事故） |
| `annotaterb` | ~> 4.x | 表結構註釋 | 11 §2 工具欄；配合 AGENTS 註釋強制條款 |
| Rails 8 `encrypts`（Active Record Encryption） | 內建 | `provider_token_ref` 靜態加密 | 本模組只存通道 token（非卡號），Rails 內建 deterministic/non-deterministic 已足夠；**通道憑證（HashKey/HashIV）另有更嚴格方案，見「清結算」§7** |
| 台灣工作日行事曆 | 自建 `business_calendars` 表 | 帳單到期日避開假日、T+n 計算 | `holidays` gem 對台灣行政院人事行政總處「補班日」支援不可靠（補班日是台灣特有）。**建議自建表 ＋ 每年匯入人事行政總處行事曆 CSV**。待定，需使用者確認匯入來源與維護責任人 |
| 平台自身收單通道（收租戶月費用） | — | 訂閱扣款、定期定額 | **待定，需使用者確認**：33 未指定。候選＝綠界「定期定額」／藍新「委託扣款」／Stripe Subscriptions。注意這是**平台自己的商戶號**，與租戶自持商戶號完全分離（硬約束 1） |
| 綠界／藍新 Ruby SDK | — | 通道 API 呼叫 | **官方無維護中的 Ruby SDK**（官方僅 PHP／Python／Node／Java／.NET）。建議自寫 thin client：`CheckMacValue`（綠界，SHA256）／`TradeInfo` AES-256-CBC（藍新）。待定，需使用者確認是否接受自寫 |
| `webmock` + `vcr` | ~> 3.x / ~> 6.x | 通道 API 契約測試 | 讓「通道逾時／重複回調」可重現 |

---

### 8. 實作步驟（順序化 todo）

1. **M0 埋表**：`billing_subscriptions`／`billing_invoices`／`billing_invoice_lines`／`dunning_attempts`／`dunning_policies`／`payment_events`（33 §4 明列 M0 必埋）。migration 檔頭註明對應 33 §6 條目與「這是平台收租戶的錢、不是租戶收貨款」。
2. 加 `billing_plans`／`billing_addons`／`billing_addon_subscriptions`／`billing_payment_methods`／`dunning_interventions`／`billing_gmv_rollups`。
3. `Platform::Dunning::Policy` ＋ seeds 寫入預設政策（`[1,3,7,14]`／14／28／60）。
4. `Platform::Dunning::Machine`（狀態機＋審計＋outbox），先寫測試再寫轉移。
5. `Platform::Billing::GmvCommissionCalculator`——**先確認 `platform_daily_rollups` 存在**（32 §7），抽成只能從它衍生。
6. `Platform::Billing::InvoiceGenerator`（含 §1 狀態×計費對照表的 7 個分支）。
7. `Platform::Billing::ChargeAttempt` 三段式＋條件式 UPDATE 認領＋唯一索引。
8. `Platform::Dunning::Scheduler`（recurring 15 分鐘）與 `EnforcementJob`（每日）。
9. `PaymentWebhookHandler`：接收層恆 200＋`payment_events` 去重＋丟 job。
10. GraphQL：先 query（overview／queue／subscription），再 mutation（retry → bulkRetry → grace → waive → planChange）。
11. 人工干預三件套與四眼守衛；每個 mutation 補 `platform_audit_logs` 的 previous/next。
12. 帳齡表匯出 job＋簽名連結。
13. 前端（§11）：KPI 列 → 催繳表 → 政策 modal → 租戶詳情計費分頁。
14. 併發與冪等測試（§9）跑綠，再開 PR；同 PR 附 `docs/dev/m8-platform-billing-dunning.md`（AGENTS 註釋與文檔節）。

---

### 9. 測試清單（RSpec）

**併發與冪等（必測，AGENTS 測試基準）**
- `spec/services/platform/billing/charge_attempt_spec.rb`
  - `同時重試扣款`：10 執行緒對同一 `(invoice, attempt_no)` 併發呼叫 → 恰好 1 次通道呼叫、`dunning_attempts` 恰好 1 列（唯一索引 + 條件式 UPDATE 雙保險）
  - `通道逾時後排程重試`：逾時 → 狀態停在 `in_flight`／`unknown`，Scheduler **不得**立即再打（防重複扣款）
  - `冪等鍵重放`：同 `idempotencyKey` 二次呼叫 → 回首次結果，不產生第二次扣款（28 §0.6）
- `spec/services/platform/billing/payment_webhook_handler_spec.rb`
  - `重複 webhook`：同 `provider_event_id` 送 10 次 → 只處理 1 次；`paid_cents` 不重複累加
  - `webhook 與 return_url 競態`：兩路徑同時完成同一張發票 → 恰好一次 `resolved` 轉移、一則 outbox
  - `handler 拋錯`：接收層仍回 200（11 §8-9），錯誤落 job 與 Sentry
- `spec/services/platform/dunning/machine_spec.rb`
  - `轉移冪等`：同態重入 no-op、不重發事件（32 §9-2）
  - 兩個排程同時升級同一發票 → 只有一次狀態變更（行鎖 double-check）

**業務邏輯**
- `spec/services/platform/dunning/policy_spec.rb`：D+28／凍結後 60 天日期計算含跨月、閏年、shop 時區（11 §8-5）
- `spec/jobs/platform/dunning/enforcement_job_spec.rb`：D+27 不凍結／D+28 凍結／D+29 重跑不重複凍結；凍結後帳單路由仍可讀（33 §2.1 例外一）
- `spec/services/platform/dunning/grace_extension_spec.rb`：`freeze_due_on` 前移、`due_at` **不變**；超過 `max_grace_days` 回 `GRACE_EXCEEDS_MAX`；已凍結回 `GRACE_AFTER_FREEZE`
- `spec/services/platform/billing/invoice_generator_spec.rb`：§1 對照表七態逐格；`restricted` 不出帳；`trial` 到期轉 `past_due`
- `spec/services/platform/billing/gmv_commission_calculator_spec.rb`：**表格驅動**（11 §6）——GMV × bps 的整數運算含 0、1 cent、極大值；斷言結果與 `platform_daily_rollups` 同源（數字同源鐵律）
- `spec/models/billing_invoice_spec.rb`：`paid_cents + waived_cents <= total_cents` DB CHECK 生效（繞過 model 直接 SQL 寫入也被擋）

**API／權限**
- `spec/requests/platform/graphql/billing_spec.rb`：`support` 呼叫 `platformDunningWaive` → `userErrors{code: FORBIDDEN}`＋HTTP 200；自我核准 → `SELF_APPROVAL_FORBIDDEN`；`platformDunningBulkRetry` 傳 251 筆 → 陣列上限錯誤（28 §0.3）
- `spec/system/platform/dunning_spec.rb`：距凍結 ≤3 天列標紅；批次重試部分失敗顯示逐筆結果

**金額覆蓋率**：`billing_*` 與 `dunning_*` 下所有金額路徑 **100% 覆蓋**（11 §0 維度 6）。

---

### 10. 驗收清單

對齊 33 §5-4（Dunning）與 specs/11 §0 七維度：

1. **安全**：`platformDunningWaive` 僅 owner＋四眼；卡號／CVV 全鏈路不存不記錄（`filter_parameters` 涵蓋 `card`、`token`、`hash_key`）；帳齡匯出連結簽名 24h。
2. **資料完整**：`(shop_id, invoice_id, attempt_no)` UNIQUE、`(provider, provider_event_id)` UNIQUE、`total = subtotal + tax` CHECK、`paid + waived <= total` CHECK；FK 全建。
3. **併發**：§9 三條併發測試全綠；`transaction 內無外部 IO` 靜態掃描通過（15 §驗收同款掃描）。
4. **效能**：催繳清單無 N+1（bullet 0 報警）；`(state, scheduled_at)`、`(status, freeze_due_on)` 有索引並過 EXPLAIN；後台 p95 <300ms。
5. **可觀測**：dunning 升級、扣款失敗率、webhook 解析失敗設專屬告警（11 §5-2）；日誌帶 `request_id + shop_id`。
6. **測試**：金額代碼 100% 覆蓋；至少一條 system test 快樂路徑（重試成功 → 解凍）。
7. **合規**：**D+28 凍結線與凍結後 60 天終止線可設定、倒數顯示正確、手動干預留審計**（33 §5-4 原文）；凍結中帳單頁可讀（33 §2.1 例外一）有測試；不提供延期、不改發票到期日（33 §2.4）在 UI 與 API 皆無此入口。
8. 三層收入分別計算且與 `platform_daily_rollups` 同源（CLAUDE.md 鐵律 7）——KPI 卡、催繳表、租戶詳情三處數字一致。

---

### 11. 前端（React/TS）

**元件樹**
```
BillingPage
├─ BillingKpiRow            5 張 KpiCard（MRR／抽成／加購／Churn／逾期應收）
├─ PageActions              AgingExportButton・DunningPolicyButton
└─ DunningCard
   ├─ DunningToolbar        選取計數・BulkRetryButton
   └─ DunningTable          TanStack Table（列：商店/方案/欠款/首次失敗/重試/距凍結/動作）
      └─ DunningRowActions  RetryButton・GraceExtendDialog・NegotiatingDialog
ShopDetail › BillingPane
├─ SubscriptionSummary      dl 版型（方案/本期/應收/GMV 抽成/付款方式）
└─ DunningTimeline          <ul class="tl"> 時間軸
Modals（Radix Dialog）
├─ DunningPolicyModal       唯讀步驟軸＋兩條硬線 note
├─ GraceExtendDialog        天數 select・原因 select（必填）・備註 textarea
└─ WaiveDialog              金額（cents 輸入）・第二核准人 picker（四眼）
```

**狀態**：TanStack Query（10 §工具表）——`useQuery(['platform','dunning',filter])`，mutation 後 `invalidateQueries`；批次重試用 `useMutation` 回傳逐筆結果陣列渲染。表單 react-hook-form＋zod（金額欄 schema：`z.number().int().nonnegative()`，**前端也禁 float**，11 §8-3 明列 JS 端亦禁）。

**GraphQL**：單一 `/platform/api/{version}/graphql.json`；查詢字串 colocate 在元件旁的 `.graphql.ts`；回應 `extensions.cost.throttleStatus` 餵給共用節流器（28 §0.4，前端自主節流）。

**三態**（23 §4-7 空／錯／載）
- 載入：`<TableSkeleton rows={8} />`，shimmer 1.2s；350ms 後才換真列（23 §3 Skeleton）
- 空：正向文案「目前沒有逾期租戶」＋次要按鈕「檢視全部帳單」
- 錯：`<Banner tone="critical">` 附「重試」與「回總覽」兩個動作（23 §4-7 要求錯誤 banner 提供動作）

**金額顯示**：`HK$1,480`、`tabular-nums`（CLAUDE.md 鐵律 10）；由 `MoneyV2` 的 Decimal 字串格式化，**前端不做金額運算**。
<!-- 依 2026-08-12「基準法域＝香港」裁定修正，原文示例值：`NT$1,480`。引用鐵律 10 的示例必須跟著鐵律走，否則本檔會反向鎖死舊基準。 -->

**響應式**（沿用原型斷點）
| 斷點 | 行為 |
|---|---|
| ≤1279px | KPI 5 卡 → 3 欄回流；`.idx` 表 `min-width:max-content` 改橫捲（CJK min-content 極小，寧可橫捲不擠字） |
| ≤1023px | 側欄轉抽屜；租戶詳情 detail-grid 單欄；`dl` 欄寬 100px |
| ≤767px | `html{font-size:14px}`；催繳表加 `card-table` 類 → **表轉堆疊卡片**（`td::before{content:attr(data-label)}`）；modal 轉貼底 sheet（`max-height:92dvh`＋sticky footer）；輸入 `font-size:16px` 防 iOS 聚焦放大 |
| ≤429px | KPI 單欄；`page-actions` 全寬且按鈕 `flex:1`；`dl` 單欄 |
| `pointer:coarse` | 命中區 ≥44px（WCAG 2.5.5）——用偽元素撐，不動視覺尺寸 |

**a11y**：距凍結的紅色標示**不可只靠顏色**——同時加 `<span class="badge critical">` 文字（「剩 3 天」）；批次操作結果用 `aria-live="polite"` 播報。

---

## 清結算（波次 W2）

> **波次歸屬**：33 §1 模組矩陣「金流通道／MCC／費率／清結算」與「保留金／負餘額／撥款排程」皆列 **W2**；33 §4 說明 W2 掛 **M8**——「上線後第一個月就會用到；出事沒台子＝人工救火」。

### 1. 這是什麼、給誰用、解決什麼問題

**先講最重要的一件事：這個模組管的是「別人的錢」的帳，不是「我們的錢」的池。**

依《電子支付機構管理條例》，平台若代收代付並保管資金即落入特許範圍（33 §2.6 台灣紅線，原型 `nopool` 為紅色 note-crit）。因此本模組的架構鐵律：

1. **租戶自持金流商戶號**。綠界／藍新／TapPay 的 MerchantID 由租戶自己申請、資金直接進租戶自己的銀行帳戶。
2. **平台只存代理設定**：`MerchantID`／`HashKey`／`HashIV`——用來替租戶組裝交易請求與驗簽，**不是**用來動用資金。
3. **後台不得出現「平台錢包」「提現」「餘額提領」任何字樣**。本頁只能是「對帳、分潤結算與通道治理」。程式碼層面：`wallet`、`withdraw`、`balance_topup` 這些字不准出現在 table／column／GraphQL field 名稱裡，加進 CI 的禁字掃描。
4. **一切「餘額」都是鏡像或推算，不是平台持有的資金**。負餘額＝平台對租戶的**應收債權**，180 天到期是**會計上認列損失**，不是「從平台錢包扣款」（見 §6.2 分錄）。
5. 例外只有一個：**平台自己的服務費收入**（計費模組）走平台自己的商戶號，那是平台自己的錢，與本模組完全分離。

**給誰用**
| 角色 | 能做什麼 |
|---|---|
| `owner` | 通道變更、費率覆寫（**四眼**，原型角色矩陣「金流通道變更 ✓＋四眼」）、負餘額認列、憑證輪換核准 |
| `admin` | 撥款批次查看、對帳差異調節（≤門檻）、MCC 指派申請、保留金設定申請 |
| `ops` | 對帳跑批、匯入通道回單、差異初判 |
| `support` | 唯讀＋開工單 |

**解決什麼**：通道回單與內部訂單對不起來的時候，沒有台子就是把 CSV 丟 Excel 人工比；撥款退回沒有台子就是客服電話追；負餘額沒有倒數就是平台默默吃掉損失還不知道金額。33 §2.6 明列「負餘額滿 180 天由平台餘額補平——這條決定平台的損失上限，必須有畫面」。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `nopool`（紅色宣告 note） | 架構紅線宣告，常駐頁首 | 文案固定，**不可由設定關閉**；同一段文案同時出現在 `docs/dev/` 與 migration 檔頭（33 §2.6） | 恆顯示；深色模式與列印皆保留 |
| 「通道分佈」清單 | 各通道的租戶家數與費率 | 原型：綠界 2.75%／藍新 2.8%／TapPay 2.6%／Stripe（跨境）3.4%＋NT$10。費率為**平台議價的參考費率**，逐店實際費率存 `payment_channels.fee_bps` | 家數點擊 → 租戶列表帶 `channel:` 篩選 |
| `paychannel`（租戶詳情 › 金流通道） | 通道／商戶號／MCC／對帳單顯示名／費率／3DS | 商戶號標示「（租戶自持）」；**MCC 與 descriptor 由通道指派**，平台只能提出申請（原型 DOCS `paychannel`，對照 SHOPLINE Open API 欄位）；費率覆寫需 owner 四眼 | 未開通顯示「待指派 MCC」並進「異常」清單；MCC 變更為 async（通道核准後回寫） |
| — 憑證區（`paychannel` 內） | HashKey／HashIV 管理 | **只顯示指紋（SHA-256 前 16 hex）與輪換時間，永不顯示明文**；欄位為 write-only（可覆蓋不可讀回）；輪換需雙人核准（硬約束 3，見 §6.3） | 指紋不符時顯示 critical badge；90 天未輪換顯示提醒（待定，需使用者確認輪換週期） |
| `payout`（租戶詳情 › 撥款與保留金） | 週期／下次撥款／保留金／負餘額 | 撥款週期 `manual/daily/weekly/monthly` ＋ `delay_days`（**上限 31 天**）＋每幣別最低餘額；台灣實務 **T+4 工作日**（33 §2.6，SHOPLINE）。負餘額顯示「距 180 天剩 n 天」 | 負餘額存在時強制顯示紅色 note；保留金為 0 時顯示 `NT$0` 不隱藏欄位 |
| 「今日撥款批次」清單 | 通道批次狀態 | 原型：`綠界批次 #20260811-A・NT$12.4M・486 家・已送出`。**這是通道的批次，不是平台的撥款**——平台只鏡射狀態，文案用「通道批次」不用「我方撥款」 | 三態：處理中（half pip）／已送出（full pip）／退回（critical） |
| 「異常」清單 | 對帳差異／撥款退回／MCC 待指派 | 原型三類：`對帳差異 3 筆（綠界 07-31 批次・差 NT$1,240）`／`撥款退回 1 筆（帳戶名不符）`／`MCC 待指派 2 家`。撥款退回原因碼對齊 33 §2.2 的 `BANK_NAME_MISMATCH` | 每筆可指派負責人；逾 SLA 自動升級工單 |
| `negbal`（負餘額與保留金表） | 欄：商店／類型／金額／發生於／距 180 天／處理 | **滿 180 天由平台承擔**（33 §2.6）；類型＝`爭議扣回`／`退款超出餘額`／`手續費欠繳`；「處理」欄顯示抵扣進度（原型：「已保留金抵扣 60%」） | 距 180 天 ≤30 天標紅；≤7 天升級為總覽的可行動佇列；已認列列移入歷史分頁 |
| 對帳跑批／匯入回單（工具列） | 匯入通道對帳檔並跑差異 | 匹配鍵優先 `provider_trade_no`，退階 `(order_no, amount_cents, business_date)`；金額差異容忍 **0**（integer cents 沒有浮點藉口）；手續費容忍 **≤NT$1（100 cents）進位差**記為 `FEE_ROUNDING`（待定，需使用者確認容忍值） | 重複匯入同一檔（checksum 相同）→ 拒絕並提示；部分列解析失敗仍匯入其餘列並列出錯誤行號 |

---

### 3. 資料模型（金額欄位一律 `_cents BIGINT`）

- `payment_channels`（33 §6）：`shop_id`, `provider[ecpay/newebpay/tappay/stripe]`, `merchant_no VARCHAR`, `mcc CHAR(4)`, `fee_bps INT`, `fixed_fee_cents BIGINT DEFAULT 0`, `descriptor VARCHAR(25)`, `three_ds_enabled BOOLEAN`, `status[pending_mcc/active/suspended/closed]`, `credential_version INT`, `activated_at`
  索引 `(shop_id, provider)` UNIQUE、`(status, mcc)`；**約束**：`fee_bps` 為整數 bps（2.75% = 275），禁 decimal 欄位
- `payment_channel_credentials`：`shop_id`, `payment_channel_id`, `hash_key_ciphertext BLOB`, `hash_iv_ciphertext BLOB`, `key_fingerprint CHAR(16)`（SHA-256 前 16 hex，供 UI 顯示）, `kms_key_id VARCHAR`, `version INT`, `rotated_at`, `rotated_by_staff_id`, `approved_by_staff_id`（四眼）, `retired_at`
  索引 `(shop_id, payment_channel_id, version)` UNIQUE。**無 `SELECT` 明文的 API 路徑**（見 §6.3）
- `credential_access_logs`：`shop_id`, `credential_id`, `purpose[sign_request/verify_callback/rotation]`, `actor_type[system/staff]`, `actor_id`, `request_id`, `created_at` — append-only，比照 `platform_audit_logs`（33 §2.8）
- `fee_overrides`：`shop_id`, `payment_channel_id`, `fee_bps INT`, `fixed_fee_cents BIGINT`, `reason`, `requested_by_staff_id`, `approved_by_staff_id NOT NULL`（四眼）, `effective_from DATE`, `effective_to DATE`　索引 `(shop_id, effective_from)`
- `payout_accounts`（33 §6）：`shop_id`, `bank_code CHAR(3)`, `branch_code`, `account_name`, `account_no_last5 CHAR(5)`（**只存末五碼**）, `verification_state[pending/verified/name_mismatch]`, `mirrored_at` — 註釋必寫「本表為通道端資料的**唯讀鏡像**，平台不受理帳號變更，變更請租戶至通道端辦理」
- `payout_schedules`（33 §6）：`shop_id`, `interval[manual/daily/weekly/monthly]`, `delay_days INT CHECK (delay_days <= 31)`（33 §2.6 上限）, `weekdays JSON`, `min_amount_cents BIGINT`, `currency CHAR(3)`　索引 `(shop_id, currency)` UNIQUE
- `payout_runs`（33 §6）：`shop_id`, `payment_channel_id`, `provider_batch_no`, `business_date DATE`, `gross_cents BIGINT`, `fee_cents BIGINT`, `refund_cents BIGINT`, `adjustment_cents BIGINT`, `reserve_held_cents BIGINT`, `net_cents BIGINT`, `state[scheduled/sent/paid/returned]`, `return_reason_code`, `mirrored_at`
  索引 `(shop_id, business_date)`、`(payment_channel_id, provider_batch_no)` UNIQUE
  約束 `CHECK (net_cents = gross_cents - fee_cents - refund_cents + adjustment_cents - reserve_held_cents)`
- `payout_run_items`：`shop_id`, `payout_run_id`, `order_id`, `amount_cents BIGINT`, `fee_cents BIGINT`, `kind[sale/refund/chargeback/fee/adjustment]`　索引 `(shop_id, payout_run_id)`
- `reserves`（33 §6）：`shop_id`, `kind[rolling/fixed]`, `rate_bps INT`, `amount_cents BIGINT`, `held_at_channel BOOLEAN DEFAULT TRUE`（**保留金由通道端持有**）, `release_at DATE`, `state[requested/active/releasing/released]`, `requested_by_staff_id`, `approved_by_staff_id`
- `reserve_ledger_entries`：`shop_id`, `reserve_id`, `direction[hold/release/offset]`, `amount_cents BIGINT`, `source_type`, `source_id`, `occurred_on`　索引 `(shop_id, reserve_id, occurred_on)`、`(shop_id, source_type, source_id)` UNIQUE（**同一來源只能入帳一次**——「爭議同時入帳」的併發兜底）
- `negative_balances`（33 §6）：`shop_id`, `origin[dispute_clawback/refund_exceeds_balance/fee_unpaid/other]`, `source_type`, `source_id`, `amount_cents BIGINT`, `recovered_cents BIGINT DEFAULT 0`, `offset_cents BIGINT DEFAULT 0`, `opened_on DATE`, `deadline_on DATE`（＝`opened_on + 180`，33 §2.6）, `state[open/recovering/settled/absorbed]`, `absorbed_on`, `absorption_journal_id`
  索引 `(shop_id, state, deadline_on)`、`(shop_id, source_type, source_id)` **UNIQUE**
  約束 `CHECK (recovered_cents + offset_cents <= amount_cents)`
- `platform_absorption_journals`：`shop_id`, `negative_balance_id`, `debit_account`（呆帳損失）, `credit_account`（應收帳款—租戶）, `amount_cents BIGINT`, `posted_on`, `posted_by_staff_id`, `approved_by_staff_id`　— append-only
- `settlement_statements`：`shop_id NULL`（通道級檔案可為 NULL，逐列才綁 shop）, `provider`, `business_date DATE`, `file_ref`, `checksum CHAR(64)` UNIQUE, `row_count INT`, `imported_at`, `imported_by_staff_id`
- `settlement_statement_rows`：`shop_id`, `statement_id`, `provider_trade_no`, `merchant_order_no`, `amount_cents BIGINT`, `fee_cents BIGINT`, `row_type[sale/refund/chargeback/fee/adjustment]`, `occurred_at`, `match_state[unmatched/matched/amount_mismatch/fee_mismatch/duplicate]`, `matched_order_id`
  索引 `(shop_id, provider_trade_no)`、`(statement_id, match_state)`
- `reconciliation_runs`：`shop_id NULL`, `provider`, `business_date`, `started_at`, `finished_at`, `rows_total`, `matched`, `discrepancies`, `state`
- `reconciliation_discrepancies`：`shop_id`, `run_id`, `kind[MISSING_IN_INTERNAL/MISSING_IN_STATEMENT/AMOUNT_MISMATCH/FEE_MISMATCH/DUPLICATE_ROW]`, `provider_trade_no`, `internal_amount_cents BIGINT`, `statement_amount_cents BIGINT`, `delta_cents BIGINT`, `state[open/investigating/resolved/written_off]`, `resolution[adjustment/statement_error/internal_error/tenant_action]`, `resolved_by_staff_id`, `resolution_note`, `adjustment_entry_id`
  索引 `(shop_id, state, kind)`、`(run_id, kind)`

---

### 4. API 契約（Platform:: GraphQL）

GID：`gid://chilllove/PaymentChannel/{id}`、`gid://chilllove/PayoutRun/{id}`、`gid://chilllove/NegativeBalance/{id}`、`gid://chilllove/ReconciliationDiscrepancy/{id}`。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformSettlementOverview` | query | `date: Date!` | `{ channels:[ChannelStat], payoutRuns:[PayoutRun], issues:[SettlementIssue] }` | — | read_only+ |
| `platformPaymentChannel` | query | `shopId: ID!` | `PaymentChannel`（**不含任何憑證欄位，只有 `credentialFingerprint`、`credentialRotatedAt`**） | `NOT_FOUND` | support+ |
| `platformPaymentChannelUpsert` | mutation | `shopId!, provider!, merchantNo!, descriptor, idempotencyKey!` | `{ channel, userErrors }` | `MERCHANT_NO_TAKEN` `DESCRIPTOR_TOO_LONG` `PROVIDER_UNSUPPORTED` | **owner（四眼）** |
| `platformPaymentChannelCredentialSet` | mutation | `channelId!, hashKey: String!, hashIv: String!, approverStaffId: ID!, idempotencyKey!` | `{ fingerprint: String!, version: Int!, userErrors }` — **回傳絕不含明文** | `SECOND_APPROVER_REQUIRED` `SELF_APPROVAL_FORBIDDEN` `KMS_UNAVAILABLE` `SAME_AS_CURRENT` | **owner（四眼）** |
| `platformFeeOverrideCreate` | mutation | `channelId!, feeBps: Int!, fixedFee: MoneyInput, effectiveFrom: Date!, reason!, approverStaffId!` | `{ override, userErrors }` | `FEE_BPS_OUT_OF_RANGE` `OVERLAPPING_PERIOD` `SECOND_APPROVER_REQUIRED` | **owner（四眼）** |
| `platformMccAssignRequest` | mutation | `channelId!, mcc: String!, note` | `{ request, userErrors }`（async，通道核准後 webhook 回寫） | `MCC_INVALID` `CHANNEL_NOT_ACTIVE` | admin+ |
| `platformPayoutRuns` | query | `first, after, filter{ businessDate, provider, state, shopId }` | `PayoutRunConnection` | — | read_only+ |
| `platformPayoutScheduleSet` | mutation | `shopId!, interval!, delayDays: Int!, minAmount: MoneyInput` | `{ schedule, userErrors }` | `DELAY_DAYS_EXCEEDS_31`（33 §2.6） `INTERVAL_UNSUPPORTED_BY_CHANNEL` | admin+ |
| `platformReserveRequest` | mutation | `shopId!, kind!, rateBps: Int, amount: MoneyInput, releaseAt: Date, reason!, approverStaffId!` | `{ reserve, userErrors }` | `RESERVE_NOT_SUPPORTED_BY_CHANNEL` `SECOND_APPROVER_REQUIRED` | **owner（四眼）** |
| `platformNegativeBalances` | query | `first, after, filter{ state, deadlineWithinDays: Int }` | `NegativeBalanceConnection`（含 `daysToDeadline: Int!`） | — | read_only+ |
| `platformNegativeBalanceOffset` | mutation | `id!, source: RESERVE\|PAYOUT_NETTING\|INVOICE, amount: MoneyInput!, idempotencyKey!` | `{ negativeBalance, userErrors }` | `OFFSET_EXCEEDS_OUTSTANDING` `RESERVE_INSUFFICIENT` `ALREADY_ABSORBED` | admin+ |
| `platformNegativeBalanceAbsorb` | mutation | `id!, approverStaffId!, note!, idempotencyKey!` | `{ negativeBalance, journal, userErrors }` | `NOT_YET_DUE`（未滿 180 天） `SECOND_APPROVER_REQUIRED` `ALREADY_ABSORBED` | **owner（四眼）** |
| `platformStatementImport` | mutation | `provider!, businessDate!, fileRef!, checksum!` | `{ statement, jobId, userErrors }` | `CHECKSUM_DUPLICATE` `PARSE_FAILED` `UNSUPPORTED_FORMAT` | ops+ |
| `platformReconciliationRun` | mutation | `provider!, businessDate!, idempotencyKey!` | `{ run, userErrors }` | `STATEMENT_MISSING` `RUN_IN_PROGRESS` | ops+ |
| `platformDiscrepancyResolve` | mutation | `id!, resolution!, note!, adjustment: MoneyInput` | `{ discrepancy, userErrors }` | `ADJUSTMENT_EXCEEDS_THRESHOLD`（超額需 owner） `NOTE_REQUIRED` | admin+；超門檻 owner |

**GraphQL schema 禁字檢查**：CI 掃描 schema dump，出現 `wallet`／`withdraw`／`topup`／`platformBalance` 即 fail（硬約束 1）。

---

### 5. 服務物件與背景任務

| Class | 責任 | 冪等 | 重試 | outbox |
|---|---|---|---|---|
| `Platform::Settlement::StatementImporter` | 解析通道對帳檔 → `settlement_statement_rows` | `checksum` UNIQUE；同檔重匯拒絕 | 解析失敗不重試（人工修檔） | `settlement/statement_imported` |
| `Platform::Settlement::Reconciler` | 逐列比對內部 `payment_transactions`，產生 discrepancies | `(run_id, provider_trade_no)` UNIQUE | 可重跑（先清該 run 的 open 差異） | `settlement/reconciliation_finished` |
| `Platform::Settlement::PayoutMirrorSync`（每 30 分鐘） | 拉通道撥款批次狀態 → `payout_runs`（**只讀鏡像**） | `(channel_id, provider_batch_no)` UNIQUE upsert | 指數退避 5 次 | `settlement/payout_returned`（退回才發） |
| `Platform::Settlement::NegativeBalanceOpener` | 由爭議扣回／退款超額事件開負餘額，設 `deadline_on = opened_on + 180` | `(shop_id, source_type, source_id)` UNIQUE | at-least-once 安全 | `settlement/negative_balance_opened` |
| `Platform::Settlement::NegativeBalanceRecovery`（每日 04:00） | 依抵扣順序自動抵扣；≤30 天發告警；到期進待認列佇列 | 每日重跑 idempotent（以剩餘額計算） | — | `settlement/negative_balance_due_soon` |
| `Platform::Settlement::AbsorptionPoster` | 認列平台損失，寫 `platform_absorption_journals` | `negative_balance_id` UNIQUE on journal | 不自動重試 | `settlement/negative_balance_absorbed` |
| `Platform::Channels::CredentialVault` | 憑證加解密、指紋、輪換；**唯一可觸碰明文的類別** | 版本號遞增 | — | `channel/credential_rotated`（**payload 不含明文**） |
| `Platform::Channels::RequestSigner` | 組裝綠界 `CheckMacValue`／藍新 `TradeInfo`；明文只在記憶體存活 | — | — | — |

**紀律**：`PayoutMirrorSync`、`StatementImporter` 皆為跨租戶掃描 → 必須在 `Platform::` 內 `ActsAsTenant.without_tenant`（32 §0）；逐列處理時 `with_tenant(shop)` 再寫入。

---

### 6. 關鍵流程與演算法

#### 6.1 對帳：通道回單 vs 內部訂單的差異偵測

```ruby
# app/services/platform/settlement/reconciler.rb
module Platform
  module Settlement
    # 通道對帳。
    #
    # 為什麼容忍值是 0：金額全程 integer cents（AGENTS 鐵律 2／11 §8-3），
    # 內外兩邊都是整數，**不存在浮點誤差這個藉口**——差 1 分就是真的差 1 分，必須人看。
    # 唯一例外是手續費：手續費由通道端用百分比計算後自行進位，我方重算會有 ±1 元級距差，
    # 因此手續費另設 FEE_TOLERANCE_CENTS，超過才報 FEE_MISMATCH。
    class Reconciler
      AMOUNT_TOLERANCE_CENTS = 0
      FEE_TOLERANCE_CENTS    = 100   # NT$1；待定，需使用者確認（33 未載明）

      def call(run:)
        ActsAsTenant.without_tenant do
          rows = SettlementStatementRow.where(statement_id: run.statement_id)

          rows.find_each(batch_size: 500) do |row|
            txn = match(row)

            if txn.nil?
              # 通道有、內部無：可能是內部漏建單、也可能是租戶在通道端手動開的交易
              open!(run, row, kind: "MISSING_IN_INTERNAL", statement: row.amount_cents)
              next
            end

            if (row.amount_cents - txn.amount_cents).abs > AMOUNT_TOLERANCE_CENTS
              open!(run, row, kind: "AMOUNT_MISMATCH", internal: txn.amount_cents,
                    statement: row.amount_cents)
            elsif (row.fee_cents - txn.expected_fee_cents).abs > FEE_TOLERANCE_CENTS
              open!(run, row, kind: "FEE_MISMATCH", internal: txn.expected_fee_cents,
                    statement: row.fee_cents)
            else
              row.update!(match_state: "matched", matched_order_id: txn.order_id)
            end
          end

          # 內部有、通道無：通常是「已建單但通道未入帳」（3DS 未完成／通道延遲）
          # 只掃該營業日，避免把跨日交易誤判（通道回單以通道營業日為準）
          missing_in_statement!(run)
        end
      end

      private

      # 匹配鍵優先序：
      #   ① provider_trade_no（通道交易序號，一對一，最可靠）
      #   ② (merchant_order_no)——我方訂單號，租戶可能在通道端補單而無此欄
      #   ③ (amount_cents, occurred_on, last4) 三元組——最後手段，且只標「疑似」不自動配對
      def match(row)
        PaymentTransaction.find_by(provider_trade_no: row.provider_trade_no) ||
          PaymentTransaction.find_by(shop_id: row.shop_id, order_no: row.merchant_order_no)
      end
    end
  end
end
```

**人工調節流程**（畫面上是「異常」清單 → 差異詳情 drawer）
1. `open` → `investigating`（指派負責人，SLA 待定，需使用者確認）
2. 四種結案路徑：`adjustment`（產生 `payout_run_items` 調整列，需註記金額與依據）／`statement_error`（通道端錯誤，附通道回覆工單號）／`internal_error`（開 bug issue 並回寫訂單）／`tenant_action`（租戶端操作造成，通知租戶）
3. 調整金額超過門檻（**待定，建議 NT$10,000＝1,000,000 cents**）需 owner 二次核准
4. 每次狀態變更寫 `platform_audit_logs`，帶 previous/next（33 §2.8）

#### 6.2 負餘額：180 天倒數、抵扣順序、平台承擔的入帳分錄

```ruby
# app/services/platform/settlement/negative_balance_recovery.rb
module Platform
  module Settlement
    # 負餘額回收。
    #
    # 33 §2.6：「負餘額滿 180 天由平台餘額補平——這條決定平台的損失上限，必須有畫面」。
    # 但我們**沒有平台餘額**（硬約束 1／33 §2.6 台灣紅線），所以正確的落地是：
    #   負餘額 = 平台對租戶的應收債權（receivable）
    #   滿 180 天 = 認列呆帳（accounting write-off），不是資金移動
    # 這個轉譯必須寫在這裡，否則後人會照 Stripe 文案做出一個「平台錢包」。
    class NegativeBalanceRecovery
      DEADLINE_DAYS = 180                 # 33 §2.6
      WARN_DAYS     = [30, 7].freeze      # 待定，需使用者確認告警節點

      # 抵扣順序——33 未載明，以下為**建議預設**，需使用者確認：
      #   ① reserve         通道端保留金（最直接，不需租戶配合）
      #   ② payout_netting  後續撥款淨額扣抵（需通道支援 netting）
      #   ③ invoice         開立補款帳單併入計費模組 dunning（走 D+28 那條線）
      #   ④ platform_absorb 到期認列損失
      OFFSET_ORDER = %i[reserve payout_netting invoice].freeze

      def call(as_of: Date.current)
        ActsAsTenant.without_tenant do
          NegativeBalance.where(state: %w[open recovering]).find_each do |nb|
            ActsAsTenant.with_tenant(nb.shop) do
              auto_offset!(nb)
              notify_if_due_soon!(nb, as_of)
              enqueue_for_absorption!(nb, as_of) if nb.deadline_on <= as_of && nb.outstanding_cents.positive?
            end
          end
        end
      end

      private

      def auto_offset!(nb)
        OFFSET_ORDER.each do |source|
          break if nb.outstanding_cents.zero?
          available = available_cents(nb, source)
          next if available.zero?

          take = [available, nb.outstanding_cents].min   # 全整數 cents，不會出現 0.1+0.2
          apply_offset!(nb, source:, amount_cents: take)
        end
      end

      # 併發要害：爭議 webhook 與每日回收 job 可能同時對同一筆負餘額入帳。
      # 用「條件式 UPDATE」保證不超抵（11 §3 第一板斧），再用來源唯一索引兜底（第三板斧）。
      def apply_offset!(nb, source:, amount_cents:)
        n = NegativeBalance.where(id: nb.id)
                           .where("offset_cents + recovered_cents + ? <= amount_cents", amount_cents)
                           .update_all(["offset_cents = offset_cents + ?, state = 'recovering', updated_at = ?",
                                        amount_cents, Time.current])
        return if n.zero?   # 別人先抵扣掉了，本次放棄（下次 job 會重算剩餘）

        ReserveLedgerEntry.create!(shop_id: nb.shop_id, reserve_id: reserve_id_for(nb, source),
                                   direction: "offset", amount_cents:,
                                   source_type: "NegativeBalance", source_id: nb.id,
                                   occurred_on: Date.current)
        nb.reload
        nb.update!(state: "settled") if nb.outstanding_cents.zero?
      end
    end
  end
end
```

```ruby
# app/services/platform/settlement/absorption_poster.rb
module Platform
  module Settlement
    # 平台承擔（認列呆帳）。owner 四眼、不自動執行。
    #
    # 分錄（單一貨幣 TWD，金額 integer cents）：
    #   借 6xxx 呆帳損失 Bad Debt Expense            amount_cents
    #     貸 1xxx 應收帳款—租戶 A/R – Tenant           amount_cents
    #
    # 為什麼不是「平台錢包扣款」：平台不持有資金（33 §2.6 台灣紅線）。
    # 這裡不產生任何資金移動指令，只產生會計分錄與對租戶的債權沖銷。
    # 若日後真的向租戶追回，另立「收回呆帳」分錄，不回頭改這一筆。
    class AbsorptionPoster
      def call(negative_balance:, actor:, approver:, note:)
        return err(:NOT_YET_DUE)               if negative_balance.deadline_on > Date.current
        return err(:SECOND_APPROVER_REQUIRED)  if approver.blank?
        return err(:SELF_APPROVAL_FORBIDDEN)   if approver.id == actor.id
        return err(:ALREADY_ABSORBED)          if negative_balance.state == "absorbed"

        ApplicationRecord.transaction do
          nb = negative_balance.lock!
          amount = nb.outstanding_cents
          journal = PlatformAbsorptionJournal.create!(
            shop_id: nb.shop_id, negative_balance_id: nb.id,
            debit_account: "6210_BAD_DEBT_EXPENSE", credit_account: "1140_AR_TENANT",
            amount_cents: amount, posted_on: Date.current,
            posted_by_staff_id: actor.id, approved_by_staff_id: approver.id
          )
          nb.update!(state: "absorbed", absorbed_on: Date.current, absorption_journal_id: journal.id)
          Platform::AuditLog.write!(action: "settlement.negative_balance_absorbed",
                                    shop_id: nb.shop_id, actor:, reason: note,
                                    previous: { state: "open", outstanding_cents: amount },
                                    next: { state: "absorbed", journal_id: journal.id })
        end
        ok
      end
    end
  end
end
```

#### 6.3 金鑰保管：HashKey／HashIV 不得明文入庫

**方案（三層，由內而外）**
1. **應用層**：Rails 8 Active Record Encryption（`encrypts :hash_key, deterministic: false`），金鑰材料放 `config/credentials.yml.enc`，主機只有 `RAILS_MASTER_KEY`（11 §1-2）。**這是最低標**。
2. **生產建議**：外部 KMS 信封加密（envelope encryption）——資料金鑰（DEK）加密憑證、主金鑰（KEK）留在 KMS（AWS KMS／GCP KMS／HashiCorp Vault Transit）。DB 存 `hash_key_ciphertext + kms_key_id + version`。好處：DB dump 外洩不等於憑證外洩，且輪換 KEK 不必重寫全表。**待定，需使用者確認採用哪一家 KMS**。
3. **讀取權限（四眼）**：
   - **UI 永不回傳明文**——GraphQL 只有 `credentialFingerprint`（SHA-256 前 16 hex）與 `credentialRotatedAt`；寫入為 write-only。
   - **人不能讀，只有系統能讀**：明文只在 `Platform::Channels::RequestSigner` 的記憶體中存在，用完即棄；`filter_parameters` 涵蓋 `hash_key`／`hash_iv`／`check_mac_value`（11 §5-1）。
   - **寫入與輪換需雙人核准**：`platformPaymentChannelCredentialSet` 必填 `approverStaffId` 且 `!= 操作者`（對齊原型角色矩陣「金流通道變更 ✓＋四眼」）。
   - 每次系統取用都寫 `credential_access_logs`（append-only），異常頻率觸發告警。

```ruby
# app/services/platform/channels/credential_vault.rb
module Platform
  module Channels
    # 通道憑證保管庫——**全系統唯一可以碰到明文的地方**。
    #
    # 硬約束 3：HashKey/HashIV 不得明文入庫。這裡用信封加密：
    #   DEK（資料金鑰）由 KMS 產生 → 用 DEK 加密憑證 → DEK 本身以 KEK 加密後隨列存放。
    # 為什麼不是單純 AR encrypts：AR encrypts 的金鑰在 credentials 檔裡，
    # 主機被入侵＝金鑰與密文同時到手；KMS 讓解密需要一次外部授權呼叫，留下軌跡。
    class CredentialVault
      # @return [String] 指紋（SHA-256 前 16 hex）——UI 只看得到這個
      def self.fingerprint(plaintext) = Digest::SHA256.hexdigest(plaintext).first(16)

      # 寫入（四眼已在 mutation 層驗過）
      def store!(channel:, hash_key:, hash_iv:, actor:, approver:)
        dek = kms.generate_data_key(key_id: kms_key_id)          # 外部 IO——在 transaction 外
        blobs = {
          hash_key_ciphertext: aes_gcm(dek.plaintext, hash_key),
          hash_iv_ciphertext:  aes_gcm(dek.plaintext, hash_iv)
        }
        ApplicationRecord.transaction do                          # 短 transaction，無外部 IO（11 §2-2）
          PaymentChannelCredential.where(payment_channel_id: channel.id, retired_at: nil)
                                  .update_all(retired_at: Time.current)
          PaymentChannelCredential.create!(
            shop_id: channel.shop_id, payment_channel_id: channel.id, **blobs,
            key_fingerprint: self.class.fingerprint(hash_key), kms_key_id: kms_key_id,
            version: channel.credential_version + 1, rotated_at: Time.current,
            rotated_by_staff_id: actor.id, approved_by_staff_id: approver.id
          )
          channel.increment!(:credential_version)
        end
      ensure
        dek&.plaintext&.replace("\0" * dek.plaintext.bytesize)   # 主動抹除記憶體中的 DEK
      end

      # 取用（只給 RequestSigner；每次都留軌跡）
      def with_plaintext(channel:, purpose:, request_id:)
        cred = PaymentChannelCredential.find_by!(payment_channel_id: channel.id, retired_at: nil)
        CredentialAccessLog.create!(shop_id: channel.shop_id, credential_id: cred.id,
                                    purpose:, actor_type: "system", request_id:)
        yield decrypt(cred)
      end
    end
  end
end
```

**輪換流程**：①租戶在通道端重新產生 HashKey／HashIV ②平台人員發起 `CredentialSet`（填新值）＋指定核准人 ③核准後新版本生效、舊版本 `retired_at` 標記但**保留 7 天**（通道回調可能仍用舊金鑰驗簽——驗簽時依序試 active 與 retired<7 天的版本）④7 天後硬刪除密文。**輪換週期建議 90 天，待定，需使用者確認**。

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| Rails 8 Active Record Encryption | 內建 | 憑證欄位靜態加密（最低標） | 內建、零依賴；不引入 `lockbox`／`attr_encrypted`（後者已停止維護） |
| `aws-sdk-kms` 或 `vault` gem | ~> 1.x | 信封加密 KEK | **待定，需使用者確認雲端供應商**；介面用 adapter 包一層，避免綁死 |
| 綠界 ECPay API | — | 交易建立、對帳檔下載、`CheckMacValue`（SHA-256）驗簽 | 台灣市佔最大（原型 512 家）。**官方無維護中的 Ruby SDK**——自寫 thin client，把 URL-encode 大小寫規則與參數排序寫進單元測試（這是最常見的簽章不符來源） |
| 藍新 NewebPay API | — | 同上；`TradeInfo` AES-256-CBC＋`TradeSha` SHA-256 | 原型 408 家 |
| TapPay Server SDK | — | 卡片交易 | 原型 221 家；有官方多語言 SDK，Ruby 需確認。**待定** |
| Stripe（跨境） | `stripe` ~> 13.x | 跨境租戶（原型 143 家） | 15 §F4 已有整合基礎；**注意 Connect destination charge 的爭議歸屬與台灣通道不同**（33 §2.6） |
| `roo` 或內建 CSV | ~> 2.x | 通道對帳檔解析（xlsx／csv／固定寬度） | 綠界對帳檔為 CSV／Excel 兩式 |
| 台灣工作日行事曆（自建表） | — | T+4 工作日計算（33 §2.6） | 同計費模組；**補班日**是台灣特有，第三方 gem 覆蓋不可靠 |
| `strong_migrations`、`annotaterb`、`brakeman` | 同 11 §1／§2 | DDL 安全、表註釋、安全掃描 | 11 §1-6 明列進 CI |
| CI 禁字掃描（自寫 rake task） | — | 掃 `wallet`／`withdraw`／`topup` | 硬約束 1 的機械化保證 |

---

### 8. 實作步驟（順序化 todo）

1. **先寫禁字掃描 rake task 與 CI 掛載**——這條在寫任何代碼之前，避免後面回頭改表名。
2. `payment_channels` ＋ `payment_channel_credentials` ＋ `credential_access_logs` migration（檔頭寫 33 §2.6 紅線與 §6 表定義）。
3. `Platform::Channels::CredentialVault`（先 AR encrypts 版本，KMS adapter 留介面）＋ `RequestSigner`（綠界 `CheckMacValue` 單元測試優先）。
4. `payout_accounts`／`payout_schedules`／`payout_runs`／`payout_run_items`（唯讀鏡像註釋）。
5. `PayoutMirrorSync`（每 30 分鐘）＋ 撥款退回原因碼對映（`BANK_NAME_MISMATCH` 等，33 §2.2）。
6. `reserves`／`reserve_ledger_entries`（`(shop_id, source_type, source_id)` UNIQUE 先建）。
7. `negative_balances` ＋ `NegativeBalanceOpener`（被爭議模組呼叫的入口）＋ 180 天 `deadline_on` 計算。
8. `NegativeBalanceRecovery`（抵扣順序）＋ `AbsorptionPoster`（四眼＋分錄）。
9. `settlement_statements`／`_rows` ＋ `StatementImporter`（先支援綠界格式）。
10. `Reconciler` ＋ `reconciliation_discrepancies` ＋ 人工調節狀態機。
11. GraphQL：query 先行（overview／channel／payoutRuns／negativeBalances），mutation 依風險由低到高（payoutScheduleSet → discrepancyResolve → mccAssignRequest → feeOverride → credentialSet → absorb）。
12. 前端（§11）。
13. 併發／冪等測試綠 → PR ＋ `docs/dev/m8-platform-settlement.md`。

---

### 9. 測試清單（RSpec）

**併發與冪等（必測）**
- `spec/services/platform/settlement/negative_balance_recovery_spec.rb`
  - **`爭議同時入帳`**：爭議 webhook 與每日回收 job 併發對同一 `negative_balance` 抵扣 → `offset_cents + recovered_cents <= amount_cents` 恆成立（條件式 UPDATE），且 `reserve_ledger_entries` 無重複來源列（UNIQUE）
  - 同一 dispute 事件重送 10 次 → `negative_balances` 恰好 1 列（`(shop_id, source_type, source_id)` UNIQUE）
- `spec/services/platform/settlement/statement_importer_spec.rb`：同 checksum 重複匯入 → 拒絕；併發匯入兩份同檔 → 恰好 1 份成功
- `spec/services/platform/settlement/payout_mirror_sync_spec.rb`：同 `provider_batch_no` 重複拉取 → upsert 不產生重複列
- `spec/services/platform/settlement/absorption_poster_spec.rb`：併發兩次認列 → 恰好 1 筆分錄（行鎖＋state 檢查）

**業務邏輯**
- `reconciler_spec.rb`：五種差異各一條案例；金額差 1 cent 必報 `AMOUNT_MISMATCH`（容忍 0）；手續費差 100 cents 不報、101 cents 報 `FEE_MISMATCH`
- `negative_balance_spec.rb`：`deadline_on = opened_on + 180` 含跨年；剩 30／7 天發告警；未滿 180 天呼叫 absorb → `NOT_YET_DUE`
- `payout_schedule_spec.rb`：`delay_days = 32` → `DELAY_DAYS_EXCEEDS_31`（33 §2.6）
- `credential_vault_spec.rb`：①DB 內 `hash_key_ciphertext` 不含明文子字串 ②GraphQL 回傳 JSON 全文不含明文（正則斷言）③日誌與 Sentry payload 不含明文 ④輪換後舊版本 7 天內仍能驗簽、第 8 天失敗
- `request_signer_spec.rb`：綠界 `CheckMacValue` 對官方文件範例值逐字元相符（含 `.NET URLEncode` 大小寫規則）
- `spec/lib/tasks/forbidden_terms_spec.rb`：schema／migration／GraphQL 出現 `wallet`／`withdraw` → 掃描 fail

**API／權限**
- `spec/requests/platform/graphql/settlement_spec.rb`：`admin` 呼叫 `platformPaymentChannelCredentialSet` → `FORBIDDEN`；`owner` 自我核准 → `SELF_APPROVAL_FORBIDDEN`；回傳 payload 無憑證欄位

---

### 10. 驗收清單

對齊 33 §5（§2.6 撥款與資金相關條目）與 specs/11 §0：

1. **合規（最高優先）**：全庫 schema、GraphQL schema、UI 文案皆無「平台錢包／提現」概念；CI 禁字掃描為必過關卡（33 §2.6 台灣紅線）。
2. **金鑰**：HashKey／HashIV 無明文入庫（DB 斷言）、無明文出 API（回傳斷言）、無明文進日誌（filter 斷言）；寫入與輪換四眼；每次系統取用有 `credential_access_logs`。
3. **撥款**：`delay_days ≤ 31` 強制（33 §2.6）；T+4 工作日計算含國定假日與**補班日**；撥款批次僅為鏡像（無任何「發起撥款」的 mutation）。
4. **負餘額**：`opened_on + 180` 倒數正確並顯示於畫面（33 §2.6「必須有畫面」）；抵扣順序可設定；認列需 owner 四眼且產生分錄；`recovered + offset <= amount` DB CHECK。
5. **對帳**：五類差異偵測有測試；金額容忍 0；人工調節四種結案路徑皆留審計與證據；超門檻調整需 owner。
6. **併發**：§9 四條併發測試全綠；`transaction 內無外部 IO` 靜態掃描通過（KMS 呼叫在 transaction 外）。
7. **資料完整**：所有租戶表 `shop_id` 前導複合索引；`(shop_id, source_type, source_id)` 等六個 UNIQUE 建立；`net_cents` CHECK 恆等式成立。
8. **可觀測**：對帳差異數、撥款退回數、憑證取用異常頻率各有 dashboard 與告警（11 §5）。

---

### 11. 前端（React/TS）

**元件樹**
```
SettlementPage
├─ NoPoolBanner            常駐紅色宣告（不可關閉，硬約束 1）
├─ ThreeColRow
│  ├─ ChannelDistroCard    通道／家數／費率 MiniList
│  ├─ PayoutBatchCard      通道批次（狀態 pip：處理中 half／已送出 full／退回 critical）
│  └─ SettlementIssuesCard 對帳差異／撥款退回／MCC 待指派
└─ NegativeBalanceCard
   └─ NegativeBalanceTable 商店／類型／金額／發生於／距 180 天／處理
      └─ RowActions        OffsetDialog・AbsorbDialog（四眼）
ShopDetail › PaymentPane
├─ ChannelSummary          dl（通道/商戶號「租戶自持」/MCC/descriptor/費率/3DS）
│  └─ CredentialRow        指紋 + 輪換時間 + RotateDialog（write-only 表單）
└─ PayoutSummary           週期/下次撥款/保留金/負餘額（負餘額 → 紅色 note）
ReconciliationDrawer       差異詳情：內部 vs 通道並排 diff、四種結案路徑
```

**狀態**：TanStack Query；`platformSettlementOverview` 以 `date` 為 key，30 秒 `staleTime`（批次狀態會變）。四眼類 Dialog 使用兩段式：填寫 → 選核准人 → 確認（`react-hook-form` 的 `mode:'onBlur'`＋zod refine 檢查 `approverStaffId !== me.id`）。

**GraphQL**：憑證輪換表單送出後**立即清空本地 state 與表單值**（`reset()`），且欄位設 `autoComplete="off"`、`type="password"`；不得寫入 sessionStorage。

**三態**
- 載入：三張卡各自 skeleton（不用整頁 spinner，23 §3）
- 空：「今日無撥款批次」／「目前沒有對帳差異」正向文案
- 錯：critical banner ＋「重新載入」「檢視通道狀態頁」兩動作

**金額顯示**：全部 `NT$` ＋ `tabular-nums`；負餘額用 `-NT$284,600` 並套 `color:var(--critical)`（原型 negRows 行為），**同時**加 `<span class="badge critical">` 文字避免只靠顏色。

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279px | `.three-col` → 兩欄；負餘額表橫捲（`min-width:max-content`） |
| ≤1023px | `.three-col` → 單欄；租戶詳情金流分頁 detail-grid 單欄；`dl` 100px 欄寬 |
| ≤767px | 負餘額表加 `card-table` → 堆疊卡片（`data-label` 前綴：商店／類型／金額／距 180 天）；差異 drawer 的並排 diff 改上下堆疊（`.diff{grid-template-columns:1fr}`）；輪換 Dialog 轉貼底 sheet |
| ≤429px | `dl` 單欄；`page-actions` 按鈕全寬 |
| `pointer:coarse` | MiniList 列 `min-height:48px`；所有 `btn-xs` 命中區撐到 ≥44px |

---

## 爭議與風控（波次 W2）

> **波次歸屬**：33 §1「爭議與卡組織門檻監控」列 **W2**、掛 **M8**。33 §5-5 是本模組的驗收原文：「VAMP／ECM／EFM 三制門檻各自計算，Mastercard 用上月分母；雙欄（回報值／估算值）；越線自動告警＋建議動作」。

### 1. 這是什麼、給誰用、解決什麼問題

**平台必須逐租戶監控爭議率，否則替租戶扛罰款**（33 §2.5 標題原文）。台灣模式下租戶自持商戶號，但卡組織的監控計畫是**以收單機構（acquirer）為單位**看整體表現的——一家租戶把爭議率拉爆，罰款與計畫入列會外溢到平台議價與整條通道關係上。所以這不是「幫租戶管」，是**平台自保**。

**三件事**
1. **卡組織門檻監控**（`ratemonitor`／`ratecaveat`）：逐租戶、逐制度計算爭議率，對照 VAMP／ECM／HECM／EFM／內部警戒線五組門檻，越線自動開案。
2. **爭議案件狀態機**（`disputequeue`）：`open → under_review（≤75 天）→ won／lost`，舉證窗 7–21 天，歸屬 `租戶`／`平台先扣`。
3. **風險評分與階梯處置**（`riskscore`）：四級 `Normal／Elevated／Highest／Not assessed`；階梯 **暫停撥款 → 暫停收款 → 拒絕（永久）**。

**給誰用**：`admin` 看監控表與處置；`support` 協助租戶備舉證；`owner` 核准「拒絕（永久）」這一階（不可逆，比照 32 §5 危險動作）。

**這個模組最容易寫錯的地方**（也是 33 §2.5 特別命名為「計算口徑陷阱」的原因）：
- **Visa 用同月分母；Mastercard 用「本月爭議 ÷ 上月交易筆數」**。用錯分母 → 月初交易量暴增的租戶會被誤判成安全，月底崩盤時已來不及。
- **卡組織回報值延遲約 1 個月** → 必須雙欄並列 `ratio_reported`（卡組織回報）與 `ratio_estimated`（我方即時估算），不可只存一個。
- **Mastercard 需連續 3 個月低於門檻才除名** → 必須有狀態機記錄連續月數，不能看單月就解除處分。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `ratecaveat`（黃色口徑說明 note） | 常駐頁首，防誤讀 | 固定文案：Visa 同月分母／MC 本月爭議 ÷ **上月**交易筆數／回報值延遲約 1 個月故雙欄並列／MC 連續 3 個月低於門檻才除名（33 §2.5） | 恆顯示、不可關閉 |
| 「門檻對照表」按鈕 → `ovThresholds` | 六制門檻與罰則對照 | VAMP Non-compliant `count ≥ 5 且 ratio ≥ 0.5%`（可能收費）／VAMP Excessive `ratio ≥ 1.5% 且 count ≥ 1,500`（必定收費）／ECM `100–299 筆且 1.5–2.99%`（月2–3: 1,000 → 月19+: 100,000 USD）／HECM `≥300 筆且 ≥3%`（月2: 1,000 → 月19+: 200,000 USD）／EFM `≥1,000 筆且淨詐欺 >50,000 USD 且爭議率 >0.50%`（月2: 500 → 月19+: 100,000 USD）／內部警戒線 `>0.75%`（Stripe 建議，33 §2.5） | 唯讀 modal；補充註記「VAMP 同時計 TC15 爭議與 TC40 早期詐欺警示，同一筆可能重複計兩次」（原型 ovThresholds） |
| `ratemonitor`（爭議率監控表） | 欄：商店／制度／**回報值**／**即時估算**／門檻／狀態／處置 | 估算值 ≥ 門檻時該格轉 critical 色（原型 rateRows 行為）；狀態 badge：`ok`／`noncompliant`／`excessive`／`enrolled`／`exiting(n/3)`；「處置」按鈕僅在 `st != ok` 時出現 | 分母為 0（新店無交易）→ 兩欄皆顯示「—」而非 0.00%；回報值未到 → 顯示「待回報（延遲約 1 個月）」 |
| 列內「處置」按鈕 | 越線後的處置入口 | 預設動作組合：**開違規案件＋限制提現**（原型 DOCS `ratemonitor`）；限制提現＝ `shop_restrictions.payout` 旗標（33 §2.2 六旗標之一） | 二次確認＋原因必選；處置後回寫 `dispute_program_states` |
| `disputequeue`（爭議案件表） | 欄：案件／商店／金額／狀態／舉證期限／歸屬 | 狀態機 `open → under_review（≤75 天）→ won／lost`；**舉證窗 7–21 天**；歸屬顯示「租戶」或「平台先扣」（33 §2.6：direct charge 扣租戶；destination／separate charges 一律先扣平台再向租戶追回） | 舉證期限剩 ≤3 天標紅並進總覽可行動佇列；逾期未舉證自動轉 `lost`（待定，需使用者確認是否自動） |
| `riskscore`（租戶詳情 › 風險評估） | 四級風險＋Radar 命中（30 天）＋高風險訂單佔比＋退款率 | 階梯建議：**暫停撥款（第一道）→ 暫停收款（第二道）→ 拒絕（永久）**（原型 DOCS `riskscore`）；`Highest` 時強制顯示 note 說明已執行到哪一道 | `Not assessed`（新店未評估）不得觸發任何處置；`Highest` 的「拒絕（永久）」需 owner |
| `shopdisputes`（租戶詳情 › 爭議率監控） | 雙欄＋門檻線 meter | meter 上兩條刻度線＝ 0.5%（25% 位置）與 1.5%（75% 位置），即 meter 滿刻度 2.0%（原型算式 `width = e/2*100`）；文案三態：安全／已越 Non-compliant／已越 Excessive（已自動開案並限制提現） | 估算值 >2.0% 時 meter 封頂於 100% 但數字照實顯示 |

---

### 3. 資料模型（金額 `_cents BIGINT`；**比率一律 `_bps INT`，禁 float／decimal**）

> **為什麼比率也不准用浮點**：`1.5%` 存成 float，在門檻邊界上 `1.4999999` 與 `1.5000001` 的判定會隨機翻轉，而這個判定會直接觸發「限制提現」這種對租戶生意有實質傷害的處分。全部用 **basis point 整數**（1 bps = 0.01%，1.5% = 150 bps），且**門檻判定用交叉相乘、完全不做除法**（§6.1）。

- `disputes`（33 §6）：`shop_id`, `network[visa/mastercard/jcb/amex/other]`, `provider`, `provider_case_no`, `order_id`, `payment_transaction_id`, `reason_code`, `reason_category[fraud/product_not_received/product_unacceptable/subscription_canceled/other]`, `amount_cents BIGINT`, `currency CHAR(3)`, `opened_on DATE`, `evidence_due_at DATETIME`, `state[open/under_review/won/lost/withdrawn]`, `liability[tenant/platform_advanced]`, `submitted_at`, `decided_on`, `recovered_cents BIGINT DEFAULT 0`, `counts_toward_ratio BOOLEAN DEFAULT TRUE`
  索引 `(shop_id, state, evidence_due_at)`、`(shop_id, network, opened_on)`、`(provider, provider_case_no)` **UNIQUE**（webhook 去重）
- `dispute_evidences`：`shop_id`, `dispute_id`, `kind[receipt/shipping_proof/customer_comm/refund_proof/policy_page/other]`, `file_ref`, `submitted_by[tenant/platform]`, `submitted_at`　索引 `(shop_id, dispute_id)`
- `dispute_state_transitions`：`shop_id`, `dispute_id`, `from_state`, `to_state`, `actor_type`, `actor_id`, `occurred_at`, `source[webhook/ui/job]`　append-only
- `dispute_metrics_monthly`（33 §6，本模組核心表）：
  `shop_id`, `network`, `period CHAR(6)`（`YYYYMM`）,
  `dispute_count INT`（TC15）, `fraud_alert_count INT`（TC40，VAMP 專用）,
  `tx_count_same_month INT`, `tx_count_prev_month INT`,
  `denominator_basis ENUM('same_month','prev_month')`,
  **`ratio_reported_bps INT NULL`**（卡組織回報，延遲約 1 個月才有值）,
  **`ratio_estimated_bps INT NOT NULL`**（我方即時估算）,
  `reported_at DATETIME NULL`, `reported_source VARCHAR`,
  `fraud_net_amount_usd_cents BIGINT`（EFM 用）, `fx_rate_bps INT`, `fx_rate_source VARCHAR`,
  `threshold_state VARCHAR`, `computed_at`
  索引 `(shop_id, network, period)` **UNIQUE**、`(period, threshold_state)`
  約束 `CHECK (ratio_estimated_bps >= 0)`；`tx_count_* = 0` 時 `ratio_*_bps` 允許 NULL（**分母 0 是 NULL 不是 0**）
- `dispute_program_states`：`shop_id`, `network`, `program ENUM('VAMP_NONCOMPLIANT','VAMP_EXCESSIVE','MC_ECM','MC_HECM','MC_EFM','INTERNAL_WATCH')`, `state[ok/breached/enrolled/exiting/exited]`, `entered_on DATE`, `months_in_program INT`, **`consecutive_clear_months INT DEFAULT 0`**, `exit_requires_clear_months INT`（MC=3，33 §2.5；Visa 待定）, `exit_eligible_on DATE`, `last_evaluated_period CHAR(6)`
  索引 `(shop_id, network, program)` **UNIQUE**、`(state, exit_eligible_on)`
- `risk_scores`：`shop_id`, `level[not_assessed/normal/elevated/highest]`, `score INT`, `factors JSON`, `computed_at`, `model_version`　索引 `(shop_id, computed_at)`
- `risk_actions`：`shop_id`, `action[payout_pause/payin_pause/reject_permanent]`, `trigger[auto_threshold/manual/appeal_reversal]`, `reason_code`, `applied_at`, `applied_by_staff_id`, `approved_by_staff_id`（`reject_permanent` NOT NULL）, `released_at`, `restriction_flag`（對映 33 §2.2 六旗標）　索引 `(shop_id, action, released_at)`

---

### 4. API 契約（Platform:: GraphQL）

GID：`gid://chilllove/Dispute/{id}`、`gid://chilllove/DisputeMetricMonthly/{id}`、`gid://chilllove/DisputeProgramState/{id}`、`gid://chilllove/RiskScore/{id}`。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformDisputeMetrics` | query | `first, after, filter{ period: String, network, thresholdState, shopId }` | `DisputeMetricConnection`：每筆含 **`ratioReportedBps`／`ratioEstimatedBps`／`denominatorBasis`／`thresholdBps`／`programState`／`consecutiveClearMonths`** | — | read_only+ |
| `platformDisputeThresholds` | query | — | `[ThresholdDefinition{ program, ratioBps, minCount, maxCount, extraCondition, penaltyText }]`（門檻對照表資料源，避免前端硬編） | — | read_only+ |
| `platformDisputes` | query | `first, after, filter{ state, network, evidenceDueWithinDays: Int, liability, shopId }` | `DisputeConnection` | — | read_only+ |
| `platformDisputeEvidenceSubmit` | mutation | `disputeId!, evidences: [EvidenceInput!]!（≤250）, idempotencyKey!` | `{ dispute, userErrors }` | `EVIDENCE_WINDOW_CLOSED` `DISPUTE_NOT_OPEN` `FILE_TOO_LARGE` | support+ |
| `platformDisputeStateSet` | mutation | `disputeId!, state: UNDER_REVIEW\|WON\|LOST\|WITHDRAWN, note!, idempotencyKey!` | `{ dispute, userErrors }` | `ILLEGAL_TRANSITION` `NOTE_REQUIRED` | admin+ |
| `platformDisputeLiabilitySet` | mutation | `disputeId!, liability: TENANT\|PLATFORM_ADVANCED, reason!` | `{ dispute, negativeBalance, userErrors }`（`PLATFORM_ADVANCED` 會建負餘額） | `ALREADY_SETTLED` `NEGATIVE_BALANCE_EXISTS` | admin+ |
| `platformRiskActionApply` | mutation | `shopId!, action: PAYOUT_PAUSE\|PAYIN_PAUSE\|REJECT_PERMANENT, reasonCode!, note!, approverStaffId, idempotencyKey!` | `{ riskAction, restrictions, userErrors }` | `LADDER_SKIPPED`（未依階梯順序） `SECOND_APPROVER_REQUIRED`（`REJECT_PERMANENT`） `SELF_APPROVAL_FORBIDDEN` `SHOP_NOT_ASSESSED` | admin+；`REJECT_PERMANENT` **owner 四眼** |
| `platformRiskActionRelease` | mutation | `id!, reason!, note!` | `{ riskAction, userErrors }` | `REJECT_PERMANENT_IRREVERSIBLE` | admin+ |
| `platformDisputeMetricsRecompute` | mutation | `shopId!, period!, idempotencyKey!` | `{ metric, userErrors }`（人工重算，用於回報值到達後校正） | `PERIOD_NOT_CLOSED` | ops+ |
| `platformCardNetworkReportImport` | mutation | `network!, period!, fileRef!, checksum!` | `{ jobId, userErrors }`（匯入卡組織月報 → 回填 `ratio_reported_bps`） | `CHECKSUM_DUPLICATE` `PERIOD_MISMATCH` | ops+ |

---

### 5. 服務物件與背景任務

| Class | 責任 | 冪等 | 重試 | outbox |
|---|---|---|---|---|
| `Platform::Disputes::WebhookIngestor` | 通道爭議回調 → `disputes` upsert；接收層恆 200＋丟 job | `(provider, provider_case_no)` UNIQUE ＋ `payment_events` 事件去重 | 通道自行重送 | `dispute/opened`、`dispute/updated` |
| `Platform::Disputes::Machine` | 案件狀態機唯一入口；記 `dispute_state_transitions` | 同態重入 no-op | — | `dispute/state_changed` |
| `Platform::Disputes::LiabilityRouter` | 判定歸屬；`platform_advanced` → 呼叫 `Settlement::NegativeBalanceOpener` | `(source_type='Dispute', source_id)` UNIQUE 於 `negative_balances` | at-least-once 安全 | — |
| `Platform::Disputes::RatioCalculator` | **純函式**：分母選擇、交叉相乘門檻判定 | 無副作用 | — | — |
| `Platform::Disputes::MonthlyRollupJob`（每日 05:00 ＋ 月初補算） | 重算當月與上月 `dispute_metrics_monthly.ratio_estimated_bps` | `(shop_id, network, period)` UNIQUE upsert | 可重跑 | — |
| `Platform::Disputes::ThresholdEvaluator`（緊接 rollup） | 對六制門檻判定 → 推進 `dispute_program_states`（含連續月數） | 以 `last_evaluated_period` 防重複推進 | 可重跑 | `dispute/threshold_crossed` |
| `Platform::Disputes::AutoCaseOpener` | 越線 → 開違規案件＋套 `payout` 限制旗標 | `(shop_id, program, period)` UNIQUE 於違規案件外部鍵 | — | `violation/case_opened` |
| `Platform::Disputes::NetworkReportImporter` | 匯入卡組織月報 → 回填 `ratio_reported_bps`、`reported_at` | `checksum` UNIQUE | — | `dispute/report_imported` |
| `Platform::Risk::Scorer`（每日） | 計算 `risk_scores`（factors JSON 留痕） | 以 `computed_at` 日期唯一 | 可重跑 | — |
| `Platform::Risk::LadderEnforcer` | 依階梯套處置；跳階需明示 override | `(shop_id, action)` 開啟中只允許一筆 | — | `risk/action_applied` |

---

### 6. 關鍵流程與演算法

#### 6.1 兩套分母的計算函式與門檻判定

```ruby
# app/services/platform/disputes/ratio_calculator.rb
module Platform
  module Disputes
    # 爭議率計算——純函式，無 DB、無副作用，方便表格驅動測試（11 §6）。
    #
    # 33 §2.5「計算口徑陷阱」：
    #   Visa       → 同月分母（本月爭議 ÷ 本月交易筆數）
    #   Mastercard → **本月爭議 ÷ 上月交易筆數**
    # 用錯分母的後果：月初交易暴增的租戶在 Visa 口徑下看似安全，
    # 但 MC 口徑用的是上月（較小的）分母，實際上已經越線——等卡組織回報時已延遲一個月。
    class RatioCalculator
      # 分母基準對照表——**唯一真相**，不准在別處再寫一次 if network == ...
      DENOMINATOR_BASIS = {
        "visa"       => :same_month,   # 33 §2.5
        "mastercard" => :prev_month,   # 33 §2.5（ECM／HECM／EFM 皆同）
        "jcb"        => :same_month,   # 待定，需使用者確認（33 未載明 JCB／NCCC 口徑）
        "amex"       => :same_month    # 待定，需使用者確認
      }.freeze

      # @param network [String]
      # @param tx_same_month [Integer] 本月交易筆數
      # @param tx_prev_month [Integer] 上月交易筆數
      # @return [Integer, nil] 分母；0 或未知回 nil（**不是 0**，避免除以零與「0% 看似安全」的誤導）
      def self.denominator(network:, tx_same_month:, tx_prev_month:)
        d = DENOMINATOR_BASIS.fetch(network) == :same_month ? tx_same_month : tx_prev_month
        d.to_i.positive? ? d.to_i : nil
      end

      # 顯示用比率（bps 整數，四捨五入）。
      # 注意：**顯示用**——門檻判定不得用這個值，見 crossed?。
      def self.ratio_bps(numerator:, denominator:)
        return nil if denominator.nil? || denominator.zero?
        # 半整數進位：+denominator/2 後整除，全程整數運算
        ((numerator * 10_000) + (denominator / 2)) / denominator
      end

      # 門檻判定——**交叉相乘，完全不做除法**。
      # 為什麼：除法會捨入，捨入會讓 1.4999% 與 1.5000% 在邊界上抖動；
      # 而這個布林值會觸發「限制提現」，對租戶的生意有實質傷害，必須 100% 可重現。
      #   numerator / denominator >= threshold_bps / 10_000
      #   ⇔ numerator * 10_000 >= threshold_bps * denominator
      #
      # strict 的存在理由：33 §2.5 的措辭有兩種——VAMP/ECM/HECM 是「≥」，
      # 而 EFM 與內部警戒線是「>」（「爭議率 >0.50%」「>0.75%」）。
      # 不能用「threshold_bps + 1」偷懶：真實比率不是整數 bps，
      # 0.505% 對「>0.50%」應成立、對「≥0.51%」卻不成立，兩者不等價。
      def self.crossed?(numerator:, denominator:, threshold_bps:, strict: false)
        return false if denominator.nil? || denominator.zero?
        lhs = numerator * 10_000
        rhs = threshold_bps * denominator
        strict ? lhs > rhs : lhs >= rhs
      end

      # 上界判定（ECM 的 1.5–2.99% 這種區間用）：ratio < exclusive_max_bps
      def self.below?(numerator:, denominator:, exclusive_max_bps:)
        return false if denominator.nil? || denominator.zero?
        numerator * 10_000 < exclusive_max_bps * denominator
      end

      # VAMP 分子＝TC15 爭議 ＋ TC40 早期詐欺警示（原型 ovThresholds：同一筆可能重複計兩次）
      def self.vamp_numerator(dispute_count:, fraud_alert_count:)
        dispute_count.to_i + fraud_alert_count.to_i
      end
    end
  end
end
```

```ruby
# app/services/platform/disputes/thresholds.rb
module Platform
  module Disputes
    # 六制門檻——數值全部來自 33 §2.5，改動需連帶更新該章與 ovThresholds modal。
    # 比率一律 bps（1.5% = 150 bps）；金額一律 cents。
    module Thresholds
      DEFS = [
        { program: "VAMP_NONCOMPLIANT", network: "visa",
          ratio_bps: 50,   strict: false, min_count: 5,         # 33 §2.5：count ≥ 5 且 ratio ≥ 0.5%
          penalty: "可能收費" },
        { program: "VAMP_EXCESSIVE",    network: "visa",
          ratio_bps: 150,  strict: false, min_count: 1_500,     # ratio ≥ 1.5% 且 count ≥ 1,500
          penalty: "必定收費" },
        { program: "MC_ECM",            network: "mastercard",
          ratio_bps: 150,  strict: false, ratio_exclusive_max_bps: 300, # 1.5–2.99%＝[150, 300)
          min_count: 100,  max_count: 299,                      # 100–299 筆
          penalty: "月2–3: 1,000 → 月19+: 100,000 USD" },
        { program: "MC_HECM",           network: "mastercard",
          ratio_bps: 300,  strict: false, min_count: 300,       # ≥3% 且 ≥300 筆
          penalty: "月2: 1,000 → 月19+: 200,000 USD" },
        { program: "MC_EFM",            network: "mastercard",
          ratio_bps: 50,   strict: true,  min_count: 1_000,     # **嚴格大於** 0.50%（33 §2.5 原文「>0.50%」）
          min_fraud_usd_cents: 5_000_000,                       # 淨詐欺 > 50,000 USD
          penalty: "月2: 500 → 月19+: 100,000 USD" },
        { program: "INTERNAL_WATCH",    network: :any,
          ratio_bps: 75,   strict: true,  min_count: 1,         # Stripe 內部建議 **>**0.75%（33 §2.5）
          penalty: "自動開案＋限制促銷" }
      ].freeze

      # 除名規則：Mastercard **需連續 3 個月**低於門檻（33 §2.5）。
      # Visa VAMP 的除名規則 33 未載明 → 待定，需使用者確認；暫用 1 個月並在 UI 標注「規則待確認」。
      EXIT_CLEAR_MONTHS = { "mastercard" => 3, "visa" => 1 }.freeze
    end
  end
end
```

#### 6.2 連續月數追蹤與越線自動開案

```ruby
# app/services/platform/disputes/threshold_evaluator.rb
module Platform
  module Disputes
    # 門檻判定 → 計畫狀態機推進。
    #
    #   ok ──越線──▶ breached ──次月仍越線──▶ enrolled（正式入列，開始罰款月數計算）
    #    ▲                                        │ 低於門檻
    #    │                                        ▼
    #    └───── consecutive_clear_months >= N ── exiting(n/N)
    #
    # N：Mastercard = 3（33 §2.5 明文「連續 3 個月低於門檻才除名」）；Visa 待定。
    # 為什麼要有 exiting 而不是直接回 ok：處分（限制提現）在觀察期內**不解除**，
    # 只有滿 N 個月才解除——單月回落就放行等於讓租戶用一個月的假象換回撥款。
    class ThresholdEvaluator
      def call(metric)
        Thresholds::DEFS.each do |d|
          next unless d[:network] == :any || d[:network] == metric.network

          st = DisputeProgramState.find_or_initialize_by(
            shop_id: metric.shop_id, network: metric.network, program: d[:program]
          )
          # 防重複推進：同一 period 只評估一次（job 可安全重跑）
          next if st.last_evaluated_period == metric.period

          breached = breached?(metric, d)
          breached ? advance_breach!(st, metric, d) : advance_clear!(st, metric, d)
          st.update!(last_evaluated_period: metric.period)
        end
      end

      private

      def breached?(metric, d)
        num = numerator_for(metric, d)
        den = metric.denominator          # 已依 network 選好同月／上月（§6.1）
        return false if den.nil?

        count_ok = num >= d[:min_count] && (d[:max_count].nil? || num <= d[:max_count])
        ratio_ok = RatioCalculator.crossed?(numerator: num, denominator: den,
                                            threshold_bps: d[:ratio_bps], strict: d[:strict])
        # ECM 有上界（1.5–2.99%）——達 3% 起屬 HECM，不重複計 ECM
        if d[:ratio_exclusive_max_bps]
          ratio_ok &&= RatioCalculator.below?(numerator: num, denominator: den,
                                              exclusive_max_bps: d[:ratio_exclusive_max_bps])
        end
        fraud_ok = d[:min_fraud_usd_cents].nil? ||
                   metric.fraud_net_amount_usd_cents.to_i > d[:min_fraud_usd_cents]

        count_ok && ratio_ok && fraud_ok
      end

      def advance_breach!(st, metric, d)
        prev = st.slice(:state, :consecutive_clear_months, :months_in_program)
        st.assign_attributes(
          state: st.state.in?(%w[breached enrolled]) ? "enrolled" : "breached",
          entered_on: st.entered_on || Date.strptime(metric.period, "%Y%m"),  # period 是 CHAR(6) YYYYMM
          months_in_program: st.months_in_program.to_i + 1,
          consecutive_clear_months: 0,                     # 越線即歸零，不累計
          exit_requires_clear_months: Thresholds::EXIT_CLEAR_MONTHS.fetch(metric.network, 1)
        )
        st.save!
        # 越線自動開案＋限制提現（原型 DOCS ratemonitor；審計 action 對齊原型
        # AUDIT 的 "dispute.threshold_crossed"，previous/next 帶 ratio 與 state）
        AutoCaseOpener.new.call(state: st, metric: metric, definition: d, previous: prev)
      end

      def advance_clear!(st, metric, d)
        return if st.state == "ok"
        need = st.exit_requires_clear_months.to_i
        st.consecutive_clear_months = st.consecutive_clear_months.to_i + 1
        if st.consecutive_clear_months >= need
          st.assign_attributes(state: "exited", exit_eligible_on: Date.current)
          Platform::Risk::LadderEnforcer.new.release!(shop_id: st.shop_id, action: :payout_pause,
                                                      reason: "dispute_program_exited")
        else
          st.state = "exiting"                              # UI 顯示 exiting(1/3)、處分**維持**
        end
        st.save!
      end
    end
  end
end
```

**回報值 vs 估算值的並存**：`MonthlyRollupJob` 只寫 `ratio_estimated_bps`；`NetworkReportImporter` 只寫 `ratio_reported_bps` 與 `reported_at`。**門檻判定一律用估算值**（因為回報值延遲約 1 個月，等它到才處置就來不及）；回報值到達後若與估算值差距超過 **20 bps（待定，需使用者確認）**，自動開一張「估算模型偏差」工單，用來校正模型——這是唯一能發現我方計數口徑錯誤的機制。

#### 6.3 爭議案件狀態機與歸屬

```ruby
# app/services/platform/disputes/machine.rb
module Platform
  module Disputes
    # 爭議案件狀態機（原型 disputequeue：open → under_review(≤75 天) → won／lost）。
    #
    #   open ──提交舉證──▶ under_review ──裁定──▶ won | lost
    #     │                                 ▲
    #     └──舉證窗到期未提交───────────────┘（自動轉 lost：待定，需使用者確認）
    #
    # 舉證窗 7–21 天（原型 disputequeue），實際天數由通道／卡組織給，不由平台決定，
    # 因此 evidence_due_at 一律以 webhook 帶回的值為準，**平台不得自行延長**。
    LEGAL = {
      "open"         => %w[under_review withdrawn lost],
      "under_review" => %w[won lost withdrawn],
      "won" => [], "lost" => [], "withdrawn" => []
    }.freeze
    MAX_REVIEW_DAYS = 75   # 原型 disputequeue：under_review ≤75 天，逾期告警（不自動裁定）

    class Machine
      def transition!(dispute, to:, actor:, note:)
        return err(:ILLEGAL_TRANSITION) unless LEGAL.fetch(dispute.state).include?(to)

        ApplicationRecord.transaction do
          d = dispute.lock!
          return ok if d.state == to                        # 冪等：webhook 與人工同時裁定
          prev = d.slice(:state, :liability)
          d.update!(state: to, decided_on: (%w[won lost].include?(to) ? Date.current : nil))
          DisputeStateTransition.create!(shop_id: d.shop_id, dispute_id: d.id,
                                         from_state: prev[:state], to_state: to,
                                         actor_type: actor.class.name, actor_id: actor.try(:id),
                                         source: actor == :webhook ? "webhook" : "ui",
                                         occurred_at: Time.current)
          # lost 且歸屬平台先扣 → 開負餘額（接清結算 §6.2 的 180 天倒數）
          # 33 §2.6：direct charge 扣租戶；destination／separate charges 一律先扣平台，再向租戶追回。
          # 台灣模式租戶自持商戶號＝direct charge 語義；platform_advanced 只出現在跨境 Connect。
          LiabilityRouter.new.settle!(d) if to == "lost"
          Platform::AuditLog.write!(action: "dispute.#{to}", shop_id: d.shop_id, actor:,
                                    reason: note, previous: prev, next: d.slice(:state, :liability))
        end
        ok
      end
    end
  end
end
```

#### 6.4 風險評分與階梯處置

四級對映（原型 `riskscore`）：`not_assessed`（新店未評估，**不得觸發任何處置**）／`normal`／`elevated`／`highest`。
輸入因子（原型顯示三項）：Radar 規則命中（30 天）、高風險訂單佔比、退款率；加上本模組的爭議率 bps 與 program state。
**權重與分數切點 33 未載明 → 待定，需使用者確認**。實作時 `factors JSON` 必須把每個因子的原始值與貢獻分數留痕，否則租戶申訴時無法解釋（申訴模組要引用）。

階梯（原型 DOCS `riskscore`，順序不可跳）：
1. `payout_pause` **暫停撥款**（第一道；越線自動處置預設就是這道＋開案）
2. `payin_pause` **暫停收款**（第二道；對映 33 §2.2 `payin` 旗標，注意「收款停但店可運營」是正確模型）
3. `reject_permanent` **拒絕（永久）**——不可逆，**owner 四眼**，且必須先走完前兩道（否則 `LADDER_SKIPPED`）。

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| Solid Queue recurring | Rails 8.1 內建 | 每日 rollup／評估／評分 | 棧內既有（D1/D4），不引入 sidekiq-cron |
| `state_machines-activerecord` | ~> 0.100 | 爭議狀態機、program state | 與計費模組同一套，不要兩種狀態機 gem |
| 純 Ruby Integer 運算 | — | 比率與門檻 | **明確不引入 BigDecimal／Rational／money gem**——bps 整數已足夠且可重現（§3 說明） |
| `roo` / CSV | ~> 2.x | 卡組織月報與通道爭議報表匯入 | 與清結算共用 importer 基座 |
| 匯率來源（EFM 的 USD 50,000 換算） | — | `fx_rate_bps` | **待定，需使用者確認**：台銀牌告／中央銀行／通道回報匯率。必須存 `fx_rate_source` 與當時匯率，否則事後無法重現判定 |
| `sentry-ruby` | 既有（11 §5-2） | 門檻越線、webhook 解析失敗告警 | 11 §5 明列 |
| `webmock` + `vcr` | ~> 3.x / ~> 6.x | 爭議 webhook 契約測試 | 重放與亂序測試需要 |
| Chart：`recharts` | 既有（10 §工具表） | 爭議率趨勢圖（可選） | 顏色用 `--chart:#2a78d6`（23 §1），門檻線用 `--critical` |

---

### 8. 實作步驟（順序化 todo）

1. `disputes`／`dispute_evidences`／`dispute_state_transitions` migration；`(provider, provider_case_no)` UNIQUE 先建。
2. `Platform::Disputes::WebhookIngestor`（接收層恆 200＋事件去重＋丟 job，11 §8-9）。
3. `Machine`（狀態機＋轉移表）＋ `LiabilityRouter`（接清結算 `NegativeBalanceOpener`）。
4. `RatioCalculator` **純函式先寫，先寫表格驅動測試**（這是整個模組最容易錯的地方）。
5. `Thresholds::DEFS`（六制數值逐條對 33 §2.5 核對）＋ `platformDisputeThresholds` query（前端不硬編）。
6. `dispute_metrics_monthly` migration（雙欄 reported／estimated ＋ `denominator_basis`）。
7. `MonthlyRollupJob`（估算值）；交易筆數來源必須是 `platform_daily_rollups` 衍生（數字同源鐵律）。
8. `dispute_program_states` ＋ `ThresholdEvaluator`（連續月數、exiting 不解除處分）。
9. `AutoCaseOpener`（開違規案件＋套 `payout` 旗標；審計 action 用 `dispute.threshold_crossed`）。
10. `NetworkReportImporter`（回填 reported）＋ 偏差 >20 bps 自動開工單。
11. `risk_scores`／`risk_actions` ＋ `Scorer`（factors 留痕）＋ `LadderEnforcer`（跳階擋下）。
12. GraphQL：query 先行，mutation 由低風險到高（evidenceSubmit → stateSet → liabilitySet → riskActionApply）。
13. 前端（§11）。
14. 併發／冪等測試綠 → PR ＋ `docs/dev/m8-platform-disputes-risk.md`。

---

### 9. 測試清單（RSpec）

**併發與冪等（必測）**
- `spec/services/platform/disputes/webhook_ingestor_spec.rb`
  - **`重複 webhook`**：同 `provider_case_no` 送 10 次（含亂序 `opened → won → opened`）→ `disputes` 恰好 1 列、狀態為最終態、`dispute_state_transitions` 無重複列
  - 接收層拋錯仍回 200（11 §8-9）
- `spec/services/platform/disputes/machine_spec.rb`
  - **`爭議同時入帳`**：webhook 判 `lost` 與人工判 `lost` 併發 → 恰好一次轉移、恰好一筆 `negative_balances`（`(source_type,source_id)` UNIQUE）、恰好一則 outbox
  - 非法轉移（`won → lost`）回 `ILLEGAL_TRANSITION`
- `spec/services/platform/disputes/threshold_evaluator_spec.rb`：同一 period 重跑 job 5 次 → `months_in_program` 只 +1（`last_evaluated_period` 防重）

**計算口徑（表格驅動，11 §6）**
- `spec/services/platform/disputes/ratio_calculator_spec.rb`
  - **分母選擇**：`visa` 取同月、`mastercard` 取上月——同一組數據兩種 network 產生不同結果的斷言（33 §2.5 陷阱的回歸測試）
  - **分母 0**：`denominator` 回 `nil`、`ratio_bps` 回 `nil`、`crossed?` 回 `false`；UI 顯示「—」
  - **邊界（≥）**：`149/10000`、`150/10000`、`151/10000` 對 `threshold_bps: 150, strict: false` 的判定（恰好等於門檻＝越線）
  - **邊界（>，EFM／內部警戒線）**：`50/10000` 對 `threshold_bps: 50, strict: true` **不**越線；`101/20000`（＝0.505%）**越線**——這條專門擋「用 threshold+1 偷懶」的實作
  - **無捨入抖動**：`crossed?` 與 `ratio_bps` 在 `1499/100000` 等分子分母組合上結論一致
  - **VAMP 分子**：TC15 + TC40 相加（同一筆重複計兩次是預期行為）
- `spec/services/platform/disputes/thresholds_spec.rb`：六制數值逐條對 33 §2.5（含 ECM 的 `100–299 筆／1.5–2.99%` 上下界、HECM `≥300 筆／≥3%`、EFM `≥1,000 筆／>USD 50,000／>0.50%` 三條件同時成立才觸發）
- **MC 連續 3 個月**：`月1 越線 → 月2 clear(1/3) → 月3 clear(2/3) → 月4 clear(3/3) 才 exited`；且 `月3 又越線 → consecutive_clear_months 歸零`；exiting 期間 `payout` 旗標**仍在**

**業務／API**
- `spec/services/platform/risk/ladder_enforcer_spec.rb`：未做前兩道就 `REJECT_PERMANENT` → `LADDER_SKIPPED`；`not_assessed` 店觸發處置 → `SHOP_NOT_ASSESSED`
- `spec/requests/platform/graphql/disputes_spec.rb`：`support` 呼叫 `platformRiskActionApply(REJECT_PERMANENT)` → `FORBIDDEN`；自我核准 → `SELF_APPROVAL_FORBIDDEN`；連線分頁 `first: 251` → 上限錯誤
- `spec/system/platform/dispute_monitor_spec.rb`：雙欄顯示（回報值／估算值）皆存在；估算值 ≥ 門檻該格為 critical 色且**有文字 badge**（不只靠顏色）；`exiting` 顯示 `1/3`

---

### 10. 驗收清單

對齊 **33 §5-5** 原文與 specs/11 §0：

1. **VAMP／ECM／HECM／EFM 三制（四項）門檻各自計算**，數值與 33 §2.5 逐條相符；門檻定義由 API 供給，前端不硬編。
2. **Mastercard 用上月分母**——有專門的回歸測試，同一組數據在 Visa／MC 口徑下結果不同。
3. **雙欄並列**：`ratio_reported_bps` 與 `ratio_estimated_bps` 同時存在於資料表與 API 回傳；回報值未到顯示「待回報」而非 0。
4. **越線自動告警＋建議動作**：`dispute.threshold_crossed` 審計列（帶 previous/next ratio 與 state）＋自動開違規案件＋套 `payout` 限制旗標。
5. **Mastercard 連續 3 個月低於門檻才除名**：`consecutive_clear_months` 狀態機有測試；`exiting` 期間處分不解除。
6. **爭議案件**：狀態機四態合法轉移表；舉證窗以通道回傳為準、平台不可延長；`under_review > 75 天` 有告警。
7. **歸屬**：`platform_advanced` 判 `lost` → 恰好一筆負餘額並接上 180 天倒數（跨模組整合測試）。
8. **風控階梯**：三階順序強制、`reject_permanent` 需 owner 四眼且不可逆、`not_assessed` 不觸發處置。
9. **併發**：§9 三條併發測試全綠；`transaction 內無外部 IO` 掃描通過。
10. **金額與比率**：金額 `_cents`、比率 `_bps`，全庫無 float/decimal 型別存放比率（schema 斷言）。
11. **可觀測**：越線事件、webhook 解析失敗、估算 vs 回報偏差 >20 bps 各有告警（11 §5-2）。

---

### 11. 前端（React/TS）

**元件樹**
```
DisputesPage
├─ RateCaveatNote          常駐黃色口徑說明（不可關閉）
├─ PageActions             ThresholdTableButton → ThresholdsModal
├─ RateMonitorCard
│  └─ RateMonitorTable     商店/制度/回報值/即時估算/門檻/狀態/處置
│     ├─ DualRatioCell     「回報 1.62% ／ 估算 1.71%」雙值同格（窄螢幕上下堆疊）
│     ├─ ProgramStateBadge ok / noncompliant / excessive / enrolled / exiting(n/3)
│     └─ EnforceDialog     開違規案件＋限制提現（原因必選、二次確認）
└─ DisputeQueueCard
   └─ DisputeTable         案件/商店/金額/狀態/舉證期限/歸屬
      └─ EvidenceDrawer    上傳舉證、倒數計時、逾期唯讀
ShopDetail › RiskPane
├─ RiskSummary             四級 badge＋Radar 命中／高風險訂單佔比／退款率
│  └─ LadderNote           Highest 時顯示「已執行到哪一道」
└─ DisputeMeter            meter：0.5%（25%）與 1.5%（75%）兩條刻度線，滿刻度 2.0%
```

**狀態**：TanStack Query；`platformDisputeThresholds` 用長 `staleTime`（門檻少變）並在 `ThresholdsModal` 與 `RateMonitorTable` 共用同一份 cache——**確保表格門檻欄與 modal 對照表永遠一致**（數字同源）。處置類 mutation 成功後 `invalidateQueries(['platform','disputeMetrics'])` 與 `['platform','shop',shopId]`（限制旗標會變）。

**DualRatioCell 規格**（本模組的招牌元件）
- 桌面：同格兩值 `回報 1.62%／估算 1.71%`，估算值 ≥ 門檻時 `color:var(--critical)` **並加 `<span class="badge critical">越線</span>`**（不只靠顏色，a11y）
- 回報值為 `null`：顯示 `待回報` ＋ `<Tooltip>卡組織回報延遲約 1 個月（33 §2.5）</Tooltip>`
- 分母為 `null`（新店無交易）：兩欄皆 `—`，`title` 說明「本期無可用分母」
- `denominatorBasis` 以小字標於制度欄下方：`同月分母` / `上月分母`——**讓看表的人一眼知道口徑**，這比註釋更有效

**三態**
- 載入：表格 skeleton 8 列（23 §3）
- 空：「目前所有租戶皆低於門檻」正向文案＋次要按鈕「檢視門檻對照表」
- 錯：critical banner ＋「重試」「檢視上次成功計算時間」

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279px | 兩張表 `min-width:max-content` 橫捲；DualRatioCell 保持單行 |
| ≤1023px | 租戶詳情風控分頁單欄；meter 全寬 |
| ≤767px | 兩張表加 `card-table` → 堆疊卡片；DualRatioCell 上下兩行（回報／估算各一行，各自帶 `data-label`）；ThresholdsModal 轉貼底 sheet 並允許內部橫捲（六列三欄表格） |
| ≤429px | 制度名稱換行顯示；`page-actions` 全寬 |
| `pointer:coarse` | 「處置」`btn-xs` 命中區 ≥44px；表格列 `min-height:48px` |

**a11y 與文案**：`exiting(2/3)` 需有 `aria-label="觀察期第 2 個月，共需 3 個月低於門檻才除名"`；越線列用 `role="alert"` 在首次載入時播報數量（例「3 家租戶已越線」）。
