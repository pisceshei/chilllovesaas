# 36 — 平台後台實作手冊 · 營運線

> 本篇是 `docs/specs/35` 的分冊之一。索引、共通約定、決策登記簿見 35 號。涵蓋：總覽／租戶列表與詳情十分頁（12 態狀態機・六級處置・授權式代登入）／審核佇列 KYC／工單。

## 總覽（波次 W1）

> 對應原型：`docs/design/chilllove-platform-admin.html` `#v-overview`；`data-doc` key：`topbar`／`search`／`staffchip`／`sidenav`／`actionqueues`／`kpis`／`health`／`gmvchart`／`signups`／`audittail`。
> 規格出處：`32 §1`（資訊架構）、`32 §3-1`（按鈕級清單）、`32 §8`（數字口徑）、`33 §3`（16 區 IA）、`specs/11 §5`（可觀測基線）、`28 §0`（API 慣例）。

### 1. 這是什麼、給誰用、解決什麼問題

平台總控後台的首頁。**它不是 BI 儀表板，是派工台**——33 §3 把總覽定義為「可行動佇列儀表板」，DOCS `actionqueues` 寫得很直白：「這是總覽的核心——不是看數字，是看『今天要處理什麼』」。

使用者是平台營運方的**當班人員**（角色 `owner`／`admin`／`support`／`ops`／`read_only`，見 32 §5）。他一天的工作起點是這一頁：四張佇列卡告訴他今天的待處理量與最急的那一件，六張 KPI 卡告訴他平台體量有沒有異常，健康列告訴他系統本身有沒有出事。

解決的問題有三個：
1. **逾期件被淹沒**——催繳快到 D+28 凍結線（33 §2.4）、KYC 已 `past_due`（33 §2.3）、爭議率越過 VAMP 1.5%（33 §2.5）、DSR 快到 GDPR 30 天（33 §2.13）這四類事件都有法定或商業硬時限，漏了就是罰款或客訴。佇列卡是這四條線的**唯一入口**。
2. **數字打架**——同一個「今日 GMV」在 KPI 卡、圖表、租戶列表出現三次，若各自查各自的表就會不一致。鐵律：三處同源（CLAUDE.md 鐵律 7、32 §8）。
3. **系統出事沒人知道**——健康列口徑對齊 `specs/11 §5`，任一紅點升級為頂列橫幅。

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值） | 狀態／邊界情況 |
|---|---|---|---|
| `topbar` 深色頂列 | 平台模式視覺標識，含「平台總控」紫色膠囊與 `demo` 環境徽章 | 頂列底色 `#141518`（32 §0），商家後台為淺色頂列；膠囊色用 `--ai:#6d28d9`（23 §1）。**存在性列入驗收**（32 §9-10） | 代登入工作階段進行中時，膠囊右側追加「支援存取中 · 剩 NN 分」倒數（33 §2.9 的 60 分鐘 TTL） |
| `search` 全域搜尋 | 跨租戶搜尋商店／擁有者／網域／統編／訂單號／工單號 | 白名單欄位編譯 SQL（`specs/11 §1` 防注入）；跨租戶查詢一律 `Platform::` namespace ＋顯式 `ActsAsTenant.without_tenant`（`specs/12 §F4`）；`Ctrl+K` 開啟 | 無結果→顯示「沒有符合的結果」＋建議語法；輸入 8 位純數字自動判定為統編查詢；≤1023px 收成 44px icon 鈕（原型 `@media (max-width:1023px)`） |
| `staffchip` 人員 chip | 顯示當前身分、角色、JIT 提權剩餘時間 | 零常設權限（ZSP）：高危動作須臨時提權、過期自動撤銷 | **待定，需使用者確認**：DOCS 引用「33 §B・jit_elevations 表」，但 33 號全文沒有 §B 章節——JIT 的提權門檻、核准人數、TTL、可提權動作清單皆無出處，本手冊不編造，僅預留 `jit_elevations` 表位置 |
| `sidenav` 導航（16 區 · 5 群） | 營運／金流／信任安全／平台工程／治理 | badge 數字與各區佇列**同源**（同一個 `Platform::Metrics::Overview` 呼叫）；本手冊負責的四項：租戶（總數）／審核佇列（待處理件數）／工單（open 數） | ≤1023px 轉抽屜（`transform:translateX(-100%)`＋遮罩，原型 CSS）；badge 為 0 時不渲染膠囊 |
| `actionqueues` 可行動佇列 | 四張卡：催繳中即將凍結／審核逾期未補／爭議率越線／DSR 待處理 | 卡片嚴重度：`crit`（催繳、爭議）／`warn`（KYC）／`info`（DSR）。副標帶「最急的那一件」：催繳「N 家 ≤3 天到 D+28 凍結線」（33 §2.4 ＋ DOCS `dunningtable`「距凍結 ≤3 天標紅」）、KYC「past_due 優先，最久 N 天」（33 §2.3 排序）、爭議「N 家已達 VAMP Excessive 1.5%」（33 §2.5）、DSR「最近到期 N 天（GDPR 30 天）」（33 §2.13） | 佇列為 0 → 卡片降級為中性色並顯示「目前無待處理」，**不隱藏**（隱藏會讓人以為壞了）；查詢逾時 → 卡片顯示 skeleton ＋「重新載入」，不阻塞整頁 |
| `kpis` 平台 KPI 六卡 | 商店總數／活躍／試用中／逾期受限／今日訂單／今日 GMV | 點卡＝跳租戶列表帶對應 `status` 篩選（32 §3-1）；GMV 口徑＝**已付款訂單金額，退款不回沖當日**（32 §8）；`delta` 比較基準＝前一同長度期間 | 今日資料來自「rollup ＋當日即時層」；當日即時層失敗時顯示昨日值＋「資料延遲」註記，**不顯示 0** |
| `health` 系統健康列 | 佇列深度／死信、5xx 錯誤率（15 分）、Webhook 失敗（24h）、合成下單巡檢 | 口徑對齊 `specs/11 §5`；合成下單巡檢每 **10 分鐘**跑一次（32 §3-1）；死信 > 0 即告警（32 §3-4）；任一紅點 → 頂列橫幅（32 §3-1） | 三色：`ok`／`warn`／`crit`。巡檢逾 20 分鐘無回報 → 視為 `crit`（連監控自己都掛了） |
| `gmvchart` 平台 GMV 30 天 | 單系列折線＋hover 十字＋表格切換 | dataviz 全套：2px 線／10% 面積／髮絲網格／無圖例／末端點／附數據表格；線色 `--chart:#2a78d6`（23 §1，已過對比與 CVD 驗證） | 空資料（新平台）→ 顯示空狀態文案而非空座標軸；「表格」鈕切換為 `<table>`，供螢幕閱讀器與匯出 |
| `signups` 最新註冊 | 自助開店清單＋「審核佇列」入口 | 與審核佇列同源（同一 `kyc_submissions` 查詢）；顯示 `pending_review` 徽章 | 空 → 「今日尚無新註冊」 |
| `audittail` 最近平台操作 | 審計日誌尾巴（4 筆）＋「審計日誌」入口 | 與審計頁同源；append-only（33 §2.8） | 事件顏色語意：`crit`＝凍結/查封、`ai`＝代登入、`warn`＝灰度批准、`ok`＝解凍 |

### 3. 資料模型

**既有表增補**

| 表 | 欄位 | 說明 |
|---|---|---|
| `platform_daily_rollups`（32 §7 已定義，本節增補） | `date DATE NOT NULL`、`shops_total INT`、`shops_active INT`、`shops_trial INT`、`shops_frozen INT`、`shops_past_due INT`、`shops_restricted INT`、`orders_count INT`、`gmv_cents BIGINT`、`refunds_cents BIGINT`、`finalized_at DATETIME` | 金額 `BIGINT` integer cents（CLAUDE.md 鐵律 3）。唯一索引 `uniq_platform_daily_rollups_date (date)`。`finalized_at` 為 NULL 代表當日尚在滾動更新 |

**新表（本手冊提出，33 §6 未列）**

```sql
-- 平台域表：無 shop_id，須列入 config/tenancy_exempt_tables.yml 白名單
CREATE TABLE platform_metric_snapshots (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  kind          VARCHAR(40)  NOT NULL,   -- action_queue / health
  key_name      VARCHAR(64)  NOT NULL,   -- dunning_near_freeze / kyc_past_due / dispute_over_threshold / dsr_due
  value_int     BIGINT       NOT NULL,
  detail        JSON         NULL,       -- {worst_days:3, worst_shop_id:5}
  captured_at   DATETIME(3)  NOT NULL,
  KEY idx_kind_key_time (kind, key_name, captured_at)
) ENGINE=InnoDB;
```

> **為什麼要快照表**：四張佇列卡的即時查詢會掃 `dunning_attempts`／`kyc_requirements`／`dispute_metrics_monthly`／`dsr_requests` 四張表，在 1,284 家租戶量級尚可即時算，但總覽是每個人每天第一個打開的頁面，QPS 集中。策略：**即時算 ＋ Solid Cache 60 秒**，快照表只用來畫趨勢與事後追查（「昨天下午佇列為什麼爆掉」）。不是主查詢路徑。

**多租戶鐵律例外聲明**：`platform_daily_rollups`、`platform_metric_snapshots`、`platform_staffs`、`platform_audit_logs`、`platform_idempotency_keys` 為**平台域表**，不帶 `shop_id`（`platform_audit_logs.shop_id` 存在但可為 NULL）。全部登記在 `config/tenancy_exempt_tables.yml`，由 `spec/architecture/tenancy_guard_spec.rb` 靜態檢查（見 §9）。

### 4. API 契約（Platform:: GraphQL）

端點 `POST /platform/api/2026-08/graphql.json`（32 §6）；`platform_staffs` session cookie ＋ CSRF；bot 走 token。GID `gid://chilllove/{Type}/{id}`（28 §0.3）。

| 操作名 | query/mutation | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformMetrics` | query | `range: DateRangeInput!`（預設 `LAST_30_DAYS`）、`compareTo: DateRangeInput` | `PlatformMetrics{ kpis{ shopsTotal, shopsActive, shopsTrial, shopsPastDue, ordersToday, gmvToday: MoneyV2, deltas }, series{ date, gmv: MoneyV2, orders }, dataFreshness{ rollupThrough: DateTime, liveLayerAt: DateTime } }` | 無（唯讀） | 全部（含 `read_only`） |
| `platformActionQueues` | query | 無 | `[ActionQueue{ key, label, count, severity: CRITICAL\|WARNING\|INFO, headline, targetView }]` | 無 | 全部 |
| `platformHealth` | query | 無 | `PlatformHealth{ queueDepth, deadLetters, error5xxRate, webhookFailures24h, webhookFailingShops, syntheticCheckout{ status, checkedAt } }` | 無 | 全部 |
| `platformAuditLogs` | query | `first ≤250`、`after`、`actor`、`action`、`source`、`query` | `PlatformAuditLogConnection` | 無 | 全部（匯出限 `owner`/`admin`，32 §5） |

**慣例遵守點**（28 §0）：
- 分頁一律 connection ＋ `pageInfo{hasNextPage,hasPreviousPage,startCursor,endCursor}`，`first` 上限 250。
- 每個回應帶 `extensions.cost{requestedQueryCost, actualQueryCost, throttleStatus}`；bucket 2,000／restore 100 points/s；單請求上限 1,000 points。
- 金額一律 `MoneyV2{amount: Decimal(字串), currencyCode}`，內部仍 integer cents，序列化層才轉。
- `platformMetrics` 是 connection-free 的 object 查詢，成本按 object=1、connection 按 `first` 計。`series` 30 筆固定，計 30 points。

### 5. 服務物件與背景任務

| Class | 單一責任 | 冪等策略 | 失敗與重試 | outbox |
|---|---|---|---|---|
| `Platform::Metrics::Overview` | **唯一**的總覽數字來源：KPI／series／queues／health 全部由它出（數字同源鐵律，32 §8） | 純讀，天然冪等 | 內部四個子查詢各自 `rescue` → 該區塊回 `nil` ＋ `degraded: true`，不整頁失敗 | 否 |
| `Platform::Metrics::DailyRollupJob` | 把 `orders`／`shops` 聚合寫入 `platform_daily_rollups` | `INSERT ... ON DUPLICATE KEY UPDATE`（唯一鍵 `date`） | Solid Queue 重試 3 次指數退避；連續失敗 → Sentry 告警 | 否 |
| `Platform::Metrics::FinalizeRollupJob` | 每日 00:15（Asia/Taipei）把前一日 rollup 標 `finalized_at` | 已 finalized 直接 return | 同上 | 否 |
| `Platform::SyntheticCheckoutJob` | 每 10 分鐘在測試店跑一次完整 checkout（32 §3-1、`specs/11 §5`） | 每次獨立訂單，不需冪等；用固定測試店＋Stripe test card | 失敗即寫 `platform_metric_snapshots(kind:"health")` ＋ Sentry；連續 2 次失敗升級頂列橫幅 | 否 |

**排程**（Solid Queue recurring，不用 Redis，D1）：

```yaml
# config/recurring.yml
platform_daily_rollup:
  class: Platform::Metrics::DailyRollupJob
  schedule: every 5 minutes          # 當日即時層：5 分鐘刷新一次（待定，需使用者確認：33 未定義刷新頻率）
platform_finalize_rollup:
  class: Platform::Metrics::FinalizeRollupJob
  schedule: every day at 00:15 Asia/Taipei
platform_synthetic_checkout:
  class: Platform::SyntheticCheckoutJob
  schedule: every 10 minutes          # 32 §3-1
```

**Job 租戶規約**（`specs/11 §8` 坑 1、`specs/12 §F4`）：所有 job 第一參數 `shop_id`，`around_perform` 統一 `ActsAsTenant.with_tenant`。**平台級 job 是例外**——它們本來就跨租戶，必須顯式 `ActsAsTenant.without_tenant` 並且**只能定義在 `app/jobs/platform/` 目錄下**，由靜態檢查強制。

### 6. 關鍵流程與演算法

#### 6.1 數字同源：單一聚合入口

```ruby
# app/services/platform/metrics/overview.rb
module Platform
  module Metrics
    # 平台總覽的唯一數字來源。
    #
    # 為什麼要有這個類別：CLAUDE.md 鐵律 7 與 docs/design/32 §8 規定
    # 「KPI 卡、GMV 圖、租戶列表 count 三處同源」。過去這類需求最常見的爛法是
    # 各元件自己寫一段 count，上線兩週後三個數字就對不起來。這裡把四個口徑
    # 收成一個物件，所有 resolver 只准呼叫它。
    #
    # @param range [Range<Date>] 查詢區間（shop 時區已在 controller 換算為 UTC 邊界）
    # @return [Platform::Metrics::Overview]
    class Overview
      CACHE_TTL = 60.seconds  # 總覽是所有人每天第一個打開的頁面，60s 快取足以削峰又不至於讓佇列卡失真
      LIVE_LAYER_WINDOW = 5.minutes

      def initialize(range:, compare_to: nil)
        @range = range
        @compare_to = compare_to
      end

      # KPI 六卡。今日值＝已 finalize 的 rollup ＋ 當日即時層。
      # 口徑：GMV = 已付款訂單金額，退款不回沖當日（32 §8），另列 refunds。
      def kpis
        Rails.cache.fetch(cache_key(:kpis), expires_in: CACHE_TTL) do
          ActsAsTenant.without_tenant do   # 跨租戶讀取必須顯式宣告（specs/12 §F4）
            rollup = PlatformDailyRollup.where(date: @range).order(:date)
            live   = today_live_layer
            {
              shops_total:     Shop.where.not(status: %w[deleted]).count,
              shops_active:    Shop.where(status: "active").count,
              shops_trial:     Shop.where(status: "trial").count,
              shops_past_due:  Shop.where(status: %w[past_due restricted]).count,
              orders_today:    (rollup.where(date: Date.current).sum(:orders_count) + live[:orders_count]),
              gmv_today_cents: (rollup.where(date: Date.current).sum(:gmv_cents) + live[:gmv_cents]),
            }
          end
        end
      end

      # 當日即時層：rollup job 每 5 分鐘跑一次，中間的缺口由這裡補。
      # 為什麼不直接即時算全部：orders 是全平台最大的表，每次總覽載入都做全表聚合會拖垮 p95（specs/11 §4）。
      def today_live_layer
        cutoff = PlatformDailyRollup.find_by(date: Date.current)&.updated_at || Date.current.beginning_of_day
        ActsAsTenant.without_tenant do
          scope = Order.where(financial_status: "paid").where("paid_at > ?", cutoff)
          { orders_count: scope.count, gmv_cents: scope.sum(:total_price_cents) }
        end
      end

      # 四張可行動佇列卡。每張卡的 count 與其目標頁面的預設篩選結果必須一致——
      # 驗收時逐卡點進去比對（33 §5-1 精神：可行動佇列不能是裝飾）。
      def action_queues
        Rails.cache.fetch(cache_key(:queues), expires_in: CACHE_TTL) do
          ActsAsTenant.without_tenant do
            [
              dunning_near_freeze_card,   # 33 §2.4：距 D+28 凍結線 ≤3 天標紅
              kyc_past_due_card,          # 33 §2.3：past_due 優先
              dispute_over_threshold_card,# 33 §2.5：VAMP 0.5% / 1.5%
              dsr_due_card,               # 33 §2.13：GDPR 30 天 / CCPA 45 天
            ]
          end
        end
      end

      private

      # 快取鍵帶上 rollup 的最大 updated_at → key-based expiry（specs/11 §4-3），永不手動 delete。
      def cache_key(part)
        stamp = PlatformDailyRollup.maximum(:updated_at)&.to_i || 0
        ["platform/overview", part, @range.first, @range.last, stamp].join("/")
      end
    end
  end
end
```

#### 6.2 佇列卡：以「最急的那一件」為副標

```ruby
# app/services/platform/metrics/overview.rb（承上）
FREEZE_DEADLINE_DAYS = 28  # 33 §2.4：首次扣款失敗起 28 天未付即凍結
NEAR_FREEZE_ALERT_DAYS = 3 # DOCS dunningtable：距凍結 ≤3 天標紅

def dunning_near_freeze_card
  # 以「首次扣款失敗日 + 28 天」推凍結日，而不是存一個 freeze_at 欄位——
  # 因為手動干預（延長寬限）會改變基準，存欄位會與 dunning_attempts 產生兩份真相。
  rows = BillingInvoice
    .joins(:dunning_attempts)
    .where(state: "past_due")
    .group("billing_invoices.id")
    .select("billing_invoices.*, MIN(dunning_attempts.attempted_at) AS first_failed_at")

  scored = rows.map do |inv|
    days_left = (inv.first_failed_at.to_date + FREEZE_DEADLINE_DAYS + inv.grace_extension_days) - Date.current
    [inv, days_left.to_i]
  end
  urgent = scored.count { |(_, d)| d <= NEAR_FREEZE_ALERT_DAYS }
  worst  = scored.min_by { |(_, d)| d }

  {
    key: "dunning_near_freeze",
    label: "催繳中・即將凍結",
    count: scored.size,
    severity: urgent.positive? ? :critical : :warning,
    headline: urgent.positive? ? "#{urgent} 家 ≤#{NEAR_FREEZE_ALERT_DAYS} 天到 D+#{FREEZE_DEADLINE_DAYS} 凍結線" : "最近一家還有 #{worst&.last} 天",
    target_view: { view: "billing", filter: { state: "past_due", sort: "days_to_freeze_asc" } },
  }
end
```

> **邊界情況**：`grace_extension_days` 來自手動干預（33 §2.4「延長寬限」），每次干預都寫 `platform_audit_logs`。Shopify 明文不給延期、不改發票到期日——我們保留這個欄位是為了**協商中**的例外處置，UI 上必須標示「已延長 N 天（操作人／時間）」，不能靜默延長。

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| `graphql`（graphql-ruby） | ~> 2.3 | `Platform::` schema、connection、cost 分析 | 28 §0 全部慣例（GID／cursor／userErrors／cost）都能用內建 `GraphQL::Analysis` 與 `Connections` 實作，不需自造輪子 |
| `solid_queue` | Rails 8.1 內建 | rollup／合成巡檢排程 | D1 決策：不用 Redis |
| `solid_cache` | Rails 8.1 內建 | 總覽 60 秒快取 | 同上 |
| `lograge` ＋ `sentry-ruby` | 最新穩定 | 結構化日誌（帶 `request_id`／`shop_id`／`staff_id`）與錯誤上報 | `specs/11 §5` 指定 |
| `opentelemetry-rails` | 最新穩定 | trace，健康列的 p95 來源 | `specs/11 §5` 指定 |
| `strong_migrations` | ~> 2.0 | `platform_daily_rollups` 等表上線後加索引不鎖表 | `specs/11 §2-5`、§8 坑 10 |
| `annotaterb` | ~> 4.x | model 檔頭自動標欄位 | `specs/11 §2` 指定；配合 AGENTS.md 註釋強制規範 |

前端見 §11。**不引入**：Chartkick／Highcharts（圖表自繪 SVG，見 §11）、任何 Redis-based 排程。

### 8. 實作步驟（Codex 逐條做）

1. `rails g migration CreatePlatformDailyRollups`——依 §3 欄位；檔頭註明對應 `docs/design/32 §7`。加唯一索引 `(date)`。
2. `rails g migration CreatePlatformMetricSnapshots`——依 §3 DDL。
3. 建 `config/tenancy_exempt_tables.yml`，寫入 5 張平台域表；建 `spec/architecture/tenancy_guard_spec.rb`（見 §9-1）。**先寫這支測試再建其他表**，否則後面每加一張表就要回頭補。
4. 建 `app/services/platform/metrics/overview.rb`，實作 `kpis`／`series`／`action_queues`／`health` 四個 public 方法（§6.1、§6.2）。四個方法各自 `rescue StandardError` → 回 `degraded: true`。
5. 建 `app/jobs/platform/metrics/daily_rollup_job.rb`＋`finalize_rollup_job.rb`；寫入 `config/recurring.yml`（§5）。
6. 建 `app/jobs/platform/synthetic_checkout_job.rb`——指定測試店 subdomain 由 credentials 讀取，**不硬編碼**。
7. 建 `app/graphql/types/platform/` 下的 `platform_metrics_type.rb`／`action_queue_type.rb`／`platform_health_type.rb`；resolver 全部只呼叫 `Platform::Metrics::Overview`。
8. 掛 cost 分析器：`GraphQL::Analysis::MaxQueryComplexity`（1,000）＋自寫 `throttle_status` extension（28 §0.4）。
9. 前端：`src/platform/pages/OverviewPage.tsx` 及其子元件（§11）。
10. 寫 `docs/dev/m8-platform-overview.md`（AGENTS.md 註釋與文檔節強制；模板見 `docs/dev/README.md`）。
11. 跑 `bundle exec rspec spec/services/platform spec/requests/platform spec/architecture` ＋ `npm test`，全綠才開 PR。

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/architecture/tenancy_guard_spec.rb` | ①遍歷 `ActiveRecord::Base.connection.tables`，每張表必須有 `shop_id` 欄位，除非列在 `config/tenancy_exempt_tables.yml`；②每張非豁免表的所有複合索引第一欄必須是 `shop_id`；③`grep` 全 repo，`ActsAsTenant.without_tenant` 只准出現在 `app/**/platform/**` 與 `app/jobs/platform/**`（32 §9-9 靜態掃描要求） |
| `spec/services/platform/metrics/overview_spec.rb` | ①**數字同源**：建 3 家 active、2 家 trial、1 家 frozen ＋ 若干 paid orders，斷言 `kpis[:shops_active]` 等於 `Platform::ShopQuery.new(status:"active").count`；②`gmv_today_cents` 等於 rollup ＋ live layer 且**不含退款回沖**（32 §8）；③rollup 表為空（新平台）時回 0 而非 nil；④其中一個子查詢 raise 時其餘三個仍回值且 `degraded == true` |
| `spec/services/platform/metrics/action_queues_spec.rb` | ①`dunning_near_freeze` 的 `count` 與 `Platform::BillingQuery.new(state:"past_due").count` 一致；②首次失敗日 = 25 天前 → `days_left == 3` 且 `severity == :critical`；③`grace_extension_days = 5` 時 `days_left == 8` 且降為 `:warning`；④四張卡皆為 0 時仍回 4 個元素（不隱藏） |
| `spec/jobs/platform/metrics/daily_rollup_job_spec.rb` | ①**冪等**：連跑兩次，`platform_daily_rollups` 只有一列且值相同；②併發：`Array.new(4){ Thread.new { described_class.perform_now } }`，斷言唯一索引擋住重複列（`ActiveRecord::RecordNotUnique` 被 `ON DUPLICATE KEY UPDATE` 吸收），最終列數 == 1 |
| `spec/requests/platform/graphql/metrics_spec.rb` | ①未登入 → top-level `errors[0].extensions.code == "ACCESS_DENIED"`；②`read_only` 角色可讀（32 §5）；③回應含 `extensions.cost`；④`first: 300` 於 `platformAuditLogs` → `MAX_COST_EXCEEDED`（28 §0.4，上限 250） |
| `spec/system/platform/overview_spec.rb` | 快樂路徑：登入 → 看到四張佇列卡 → 點「催繳中」→ 落在租戶／計費頁且篩選已套用 → 數字與卡片一致 |

**併發測法範本**（`specs/11 §3` 三板斧之「唯一索引兜底」）：

```ruby
it "同時 4 個 rollup job 只會產生一列（唯一索引兜底）" do
  ActiveRecord::Base.connection_pool.with_connection { } # 預熱連線池，避免 thread 內第一次連線的延遲干擾競態
  threads = 4.times.map do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Platform::Metrics::DailyRollupJob.perform_now
      end
    end
  end
  threads.each(&:join)
  expect(PlatformDailyRollup.where(date: Date.current).count).to eq(1)
end
```

### 10. 驗收清單

- [ ] KPI 卡、GMV 圖、租戶列表 count **三處數字一致**（32 §9-8）——抽查 5 次，每次改動資料後重驗。
- [ ] 四張佇列卡的 count 點進目標頁後與該頁預設篩選結果一致。
- [ ] GMV 口徑＝已付款訂單、退款不回沖當日；`refunds` 另列（32 §8）。
- [ ] 健康列四項口徑對齊 `specs/11 §5`；死信 > 0 觸發告警；任一紅點升頂列橫幅。
- [ ] 合成下單巡檢每 10 分鐘一次、有時間戳、逾 20 分鐘無回報視為 crit。
- [ ] 跨租戶查詢全部位於 `Platform::` 命名空間（靜態掃描通過，32 §9-9）。
- [ ] 平台域表全部登記於白名單，`tenancy_guard_spec` 綠。
- [ ] 深色頂列＋「平台總控」膠囊存在（32 §9-10）；`platform.chilllove.tw` 全域 `noindex`（32 §9-12）。
- [ ] tokens 全部取自 `23 §1`，未自創色值。
- **七維度（`specs/11 §0`）**：
  - [ ] 1 安全：`read_only` 以上才可讀；rack-attack 掛在平台登入；輸出無 PII 外洩（審計尾巴顯示人名但不顯示 email）。
  - [ ] 2 資料完整：`platform_daily_rollups` 唯一索引 `(date)`；rollup job 冪等。
  - [ ] 3 併發：rollup 併發測試通過。
  - [ ] 4 效能：總覽 p95 < 300ms（後台預算）；bullet 零報警；四個子查詢皆有 EXPLAIN 記錄。
  - [ ] 5 可觀測：lograge 帶 `request_id`／`staff_id`；overview `degraded` 進 Sentry breadcrumb。
  - [ ] 6 測試：§9 全綠。
  - [ ] 7 合規：總覽不落地任何顧客 PII；審計尾巴讀 `platform_audit_logs`（12 個月保留，33 §2.8）。

### 11. 前端（React/TS）

**元件樹**

```
OverviewPage
├─ PageHead（標題／期間切換 chip）
├─ ActionQueueGrid            → ActionQueueCard × 4      [data-doc="actionqueues"]
├─ KpiGrid                    → KpiCard × 6              [data-doc="kpis"]
├─ HealthStrip                → HealthItem × 4           [data-doc="health"]
├─ GmvChartCard               → LineChartSvg / ChartDataTable  [data-doc="gmvchart"]
└─ TwoColumn
   ├─ SignupsCard             → MiniList                 [data-doc="signups"]
   └─ AuditTailCard           → Timeline                 [data-doc="audittail"]
```

**狀態管理**
- 伺服器狀態：`@tanstack/react-query`（`docs/research/10` 已選定的 admin npm 集合）。三個 query key：`['platform','metrics',range]`、`['platform','actionQueues']`、`['platform','health']`。
- `staleTime`：metrics 60s（與後端快取一致）、actionQueues 30s、health 15s；`refetchOnWindowFocus: true`（當班人員切回分頁要看到最新佇列）。
- UI 狀態（期間選擇、圖表/表格切換）走 URL searchParams（`react-router`），重新整理後保持。
- **不用 Apollo**：專案沒有 normalized cache 需求，一支 `platformGql<T>()` fetch wrapper ＋ TanStack Query 足夠，也避免多一個重型依賴（AGENTS.md 技術鐵律 1）。

```ts
// src/platform/api/client.ts
/**
 * Platform GraphQL 呼叫器。
 * - 端點固定 /platform/api/2026-08/graphql.json（32 §6），與商家 admin API 分離。
 * - 業務錯誤走 userErrors（HTTP 恆 200，28 §0.3），只有 syntax/THROTTLED/ACCESS_DENIED/INTERNAL 走 top-level errors。
 * - THROTTLED 依 extensions.cost.throttleStatus.restoreRate 自主退避重試（28 §0.4）。
 */
export async function platformGql<T>(query: string, variables?: Record<string, unknown>): Promise<T> { /* … */ }
```

**GraphQL 呼叫**

```graphql
query PlatformOverview($range: DateRangeInput!) {
  platformMetrics(range: $range) {
    kpis { shopsTotal shopsActive shopsTrial shopsPastDue ordersToday gmvToday { amount currencyCode } }
    series { date orders gmv { amount currencyCode } }
    dataFreshness { rollupThrough liveLayerAt }
  }
  platformActionQueues { key label count severity headline targetView }
  platformHealth { queueDepth deadLetters error5xxRate webhookFailures24h syntheticCheckout { status checkedAt } }
}
```

**三態**

| 狀態 | 呈現 |
|---|---|
| 載入 | 每個區塊獨立 skeleton（佇列卡 4 個灰塊、KPI 6 個灰塊、圖表 200px 灰塊）。**不做整頁 spinner**——四個區塊各自的 query 獨立，先到先顯示 |
| 空 | 佇列卡 count=0 → 中性灰卡＋「目前無待處理」；`signups` 空 → 「今日尚無新註冊」；GMV series 空 → 「尚無資料，平台上線後將於此顯示」 |
| 錯誤 | 區塊級錯誤卡：「載入失敗」＋「重試」鈕（觸發該 query 的 `refetch`）。`degraded: true` 時在卡片角落顯示「資料延遲」小徽章並附 `dataFreshness` 時間 |

**響應式**（斷點取自原型 CSS，與商家後台同一套）

| 斷點 | 行為 |
|---|---|
| ≥1280px | `kpis` 6 欄、`queues`/`health` 4 欄、`two-col` 兩欄；main padding 24/32 |
| ≤1279px | `kpis` 3 欄、`queues`/`health` 2 欄；表格 `min-width:max-content` 橫捲（CJK min-content 極小，寧可橫捲不擠字） |
| ≤1023px | sidebar 轉抽屜（`translateX(-100%)`＋遮罩＋`aria-expanded`）；搜尋收成 44px icon 鈕；`two-col` 轉單欄 |
| ≤767px | `html{font-size:14px}`；`kpis`/`queues`/`health` 全 2 欄；input `font-size:16px`（防 iOS 聚焦放大）；modal 轉貼底 sheet |
| ≤429px | `kpis`/`queues`/`health` 單欄；`page-actions` 滿寬且按鈕等分；logo 只留 mark |
| `pointer:coarse` | 命中區用偽元素撐到 ≥44px（WCAG 2.5.5），視覺尺寸不變 |
| `prefers-reduced-motion` | 全域動效降到 0.01ms |

**圖表**：自繪 SVG（原型 `drawChart()` 為參考實作），不引 recharts——單系列折線 ＋ hover 十字 ＋ 末端點的需求不值得一個依賴，且 dataviz 規格（2px 線／10% 面積／髮絲網格 `--grid:#ececef`／線色 `--chart:#2a78d6`）需要精確控制。必附 `<table>` 切換供螢幕閱讀器（`role="img"` ＋ `aria-label`）。

---

## 租戶列表與租戶詳情十分頁（波次 W1）

> 對應原型：`#v-shops`（列表）、`#v-shop-detail`（詳情十分頁）、`#ovRestrict`（處置 modal）、`#ovAccess`（授權式代登入 modal）。
> `data-doc` key：`shopexport`／`bulkops`／`createshop`／`shopviews`／`shopsearch`／`shoptable`／`sdtabs`／`accessrequest`／`restrict`／`moreactions`／`lifecycle`／`basicinfo`／`restrictions`／`owner`／`planbox`／`shophealth`／`danger`／`kycreq`／`kycdocs`／`usage`／`billsub`／`dunning`／`paychannel`／`payout`／`domains`／`shopenvs`／`riskscore`／`shopdisputes`／`shopcompliance`／`shopinvoice`／`shopaudit`。
> 規格出處：`33 §2.1`（12 態）、`33 §2.2`（六級處置＋駁回原因碼）、`33 §2.9`（授權式代登入）、`33 §2.10`（配額三段式）、`32 §2`（狀態機轉移表）、`32 §3-2/3-3`（按鈕級）、`32 §4`（代登入禁止動作）、`32 §5`（權限矩陣）、`32 §6`（API 契約）、`32 §7`（資料模型）。

### 1. 這是什麼、給誰用、解決什麼問題

**租戶列表**是跨租戶索引，是平台唯一能「一眼掃過 1,284 家店」的地方。**租戶詳情十分頁**是單店的完整治理面：概覽／資質 KYC／用量配額／計費／金流／網域與環境／風控／合規／工單／審計（33 §3）。

分十頁而不是塞單頁的理由（DOCS `sdtabs`）：**每一頁對應一條治理線**，每條線有自己的資料來源、自己的角色權限、自己的波次。營運人員處理催繳只看計費頁，風控人員處理爭議只看風控頁，互不干擾。

本模組的**三個核心機制**（也是整份手冊最需要寫細的部分）：

1. **12 態生命週期狀態機**（33 §2.1）——每一態定義前台 HTTP／商家後台可讀寫／金流／資料時效四個維度的副作用；轉移走**單一入口**且**冪等**。
2. **六級分級處置**（33 §2.2）——`payin`／`payout`／`trade`／`readonly`／`offline`／`banned` 六個**獨立**旗標，可組合、可設到期自動解除。店匠的關鍵洞察：補件期間「收入暫停但店鋪仍可運營」——**單一 boolean 凍結是錯的模型**。
3. **授權式代登入**（33 §2.9）——4 位數授權碼 ＋ 逐項權限勾選 ＋ 商家核准 ＋ 60 分鐘 TTL ＋ 90 天閒置失效 ＋ 商家端持續橫幅 ＋ 雙寫審計 ＋ 禁止動作硬擋。**取代**無條件 impersonate。

> **範圍聲明**：計費／金流／風控／合規四個分頁在本模組只寫「租戶詳情頁的讀取面與租戶級干預動作」；全域的計費與催繳頁、清結算頁、爭議與風控頁、合規頁屬金流線與信任安全線，見該兩份手冊。

### 2. 畫面與控件逐項表

#### 2-A 租戶列表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值） | 狀態／邊界情況 |
|---|---|---|---|
| `shopsearch` 租戶搜尋 | 名稱／子網域／email／統編即時過濾 | **白名單欄位編譯 SQL**（`specs/11 §1` 防注入）：允許欄位僅 `name`／`subdomain`／`owner_email`／`tax_id`／`primary_domain`；輸入 8 位純數字自動判為統編精確比對，其餘走 `LIKE '%kw%'`（`name` 走 ngram 索引） | 空結果→空狀態卡＋「清除搜尋與篩選」鈕（原型 `#shopEmpty`）；輸入 <2 字不查（避免全表掃） |
| 狀態篩選 chips | 全部／活躍／試用／待審／逾期／受限／凍結／已關閉 | chips 對應 `shops.status`，與 12 態的**可見子集**（`draft`／`rejected`／`info_required`／`paused`／`deleted` 收在「更多狀態」下拉，避免 12 個 chip 撐爆列） | 選中 chip 反映在 URL searchParams，可分享連結；與 KPI 卡點擊帶入的篩選同一組參數 |
| `shoptable` 租戶表 | 欄位：商店（名＋子網域）／擁有者（名＋email）／狀態／風險／30 天 GMV／爭議率／用量峰值／建立於 | 狀態 badge 用 **pip 語意**：實圈＝活躍、半圈＝試用/逾期/受限/待審、空圈＝凍結/駁回（原型 `ST` 表）。爭議率 **≥0.5% 轉黃、≥1.5% 轉紅**（33 §2.5 VAMP 門檻）。用量峰值 **≥60% 轉黃、≥95%... 見下方裁決**。cursor 分頁 ≤250（28 §0.3） | 整列可點進詳情；`deleted` 狀態不出現在任何列表（只在審計可查）；GMV 為 0 顯示 `—` 不顯示 `NT$0` |
| `shopviews` saved views | 儲存目前篩選為檢視 | 同商家後台慣例（22 §0）；**預設檢視唯讀**（不可刪改） | **待定，需使用者確認**：預設檢視清單（原型只有「全部商店」） |
| `shopexport` 匯出 CSV | 匯出租戶清單 | **>50 筆轉背景 job**（22 §9.4「匯出同步門檻 50 筆」、32 §3-2）＋簽名連結，**24h 失效**（DOCS `shopexport`） | 匯出中顯示「處理中，完成後寄信給你」；同一 staff 同時只准 1 個匯出 job（避免刷爆） |
| `bulkops` 批次操作 | 加入 cohort／批次公告／批次覆寫上限 | **批次寫入逐筆獨立 transaction ＋結果報告**（DOCS `bulkops`）——一筆失敗不影響其他筆；上限 250 筆/次（28 §0.3 陣列型 input 上限） | 結果報告列出成功/失敗筆數與每筆失敗原因碼；全部落審計（每筆一列，共用同一 `transaction_id`，33 §2.8） |
| `createshop` 代建商店 | 平台代開（少用） | `admin` 以上（32 §5 未列此動作 → 比照「凍結/解凍/關店」層級） | **待定，需使用者確認**：代建商店的預設方案、是否跳過 KYC、是否直接進 `trial` 或 `pending_review` |

> **規格衝突裁決 #1（用量顏色門檻）**：32 §3-3 寫「≥80% 黃／≥95% 紅」，33 §2.10 寫配額三段式「warn 60%／error 100%」。33 §8 明示「§2 狀態機被本篇 §2.1 取代」但沒說 §3-3；然而顏色若與 enforcement 門檻不一致，營運會誤判。**裁決：一律採 33 §2.10 的 60%／100%**，meter 的門檻線畫在 60%（原型 `.thr{left:60%}` 已如此實作）。32 §3-3 的 80/95 作廢，需回寫 32 號。

#### 2-B 詳情頁頭部與概覽分頁

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值） | 狀態／邊界情況 |
|---|---|---|---|
| `accessrequest` 請求存取 | 授權式代登入入口 | 見 §6.4 全流程。4 位數授權碼、逐項權限、**60 分鐘**工作階段、**90 天**未使用自動失效、單一請求方 pending 上限 **10**（33 §2.9）；禁止：改商家密碼/email、單筆退款 > **NT$10,000**、刪除商店（32 §4-4）；角色 `support` 以上，`read_only` 不可（32 §4-5、§5） | 商家尚未核准 → 鈕顯示「等待商家核准（已送出 N 分鐘）」；已有生效 grant → 鈕變「進入商家後台（剩 NN 分）」；`banned` 旗標開啟時鈕禁用 |
| `restrict` 處置… | 六旗標分級處置 modal | 六個 checkbox 獨立勾選；**原因必選**（7 個選項）；選「其他」時**備註必填**（32 §3-3）；自動解除下拉：不自動解除／7 天／14 天／30 天；通知商家：立即 email＋站內／僅站內／不通知（**不通知需 owner 覆核**） | 未勾任何旗標＝解除全部（modal 底部即時摘要「未選任何限制＝解除全部」）；勾 `banned` 觸發二次確認（輸入商店名）；`read_only`／`ops`／`support` 角色看不到此鈕（32 §5「凍結/解凍/關店」僅 owner/admin） |
| `moreactions` ⋯ | 重寄驗證信／重驗網域／匯出資料／擁有權轉移 | 擁有權轉移：發起方重驗＋受讓方 email 接受＋欠款歸屬規則＋阻擋條件（DOCS `moreactions`） | **待定，需使用者確認**：欠款歸屬規則的具體條文、阻擋條件清單 |
| `lifecycle` 生命週期 | 12 態狀態機視覺化（步驟軸） | 每態定義**前台 HTTP／商家後台可讀寫／金流／webhook** 四維度（DOCS `lifecycle`）；轉移走單一入口且冪等 | 步驟軸只畫主幹 6 態（`pending_review→trial→active→past_due→frozen→closed`）；分支態（`restricted`／`paused`／`info_required`／`rejected`）以橫幅呈現，避免軸線爆炸 |
| `basicinfo` 基本資料 | 子網域／主網域／統一編號／幣別時區／Shop GID | GID 格式 `gid://chilllove/Shop/{id}`（28 §0.3）；**統編未驗證＝稅籍未完成，前台揭露義務不成立**（DOCS `basicinfo`；33 §2.14 要求銷售網頁揭露營業人名稱與統編） | 統編為空 → badge「未完成稅籍」（`attention`）；已驗證 → `success`。統編驗證來源與時機 **待定，需使用者確認**（33 §2.14 只寫「須辦稅籍登記並揭露」，未寫平台如何驗） |
| `restrictions` 限制旗標 | 六級處置目前狀態 | 每旗標一列，顯示 ON/OFF ＋說明文；可設到期自動解除；**每次變更落審計並通知商家**（DOCS `restrictions`） | 有到期時間的旗標顯示「N 天後自動解除」；已過期但 job 尚未跑到 → UI 顯示「已到期，解除處理中」 |
| `owner` 擁有者卡 | 聯絡資訊＋重寄驗證信／重設 2FA／轉移擁有權 | **驗證網域擁有權後可自助重設 2FA**（33 §2.15，「這條能砍掉大量客服工單」）；重設 2FA 需 **owner 覆核（四眼原則）**（32 §3-3） | 商家未啟用 2FA → 「重設 2FA」鈕禁用並顯示原因；網域未驗證 → 鈕禁用並提示先驗網域 |
| `planbox` 方案與模組 | 三層計價顯示：方案月費＋模組加購＋GMV 抽成 | 對照 SHOPLINE 14 模組／CYBERBIZ 1% 抽成（33 §1、DOCS `planbox`） | 試用中顯示「試用 14 天・剩 N 天」（33 §2.1）；已關閉顯示 `—` |
| `shophealth` 單店健康 | webhook 失敗／5xx／限流吃滿／爭議率 | 與監控頁**同源**（DOCS `shophealth`） | 任一紅 → 概覽頁頂部橫幅 |
| `danger` 危險區 | 關閉商店／排程刪除資料 | 關店＝前台 **410**（30 §9 死鏈規範、32 §2）＋admin 唯讀至**本期帳單週期結束**（33 §2.1）＋**資料保留 2 年**可復店＋**子網域永久不可重用**（33 §2.1）；刪除需**關閉滿 30 天**（32 §2）且**輸入商店名確認**；**legal hold 命中時阻擋**（DOCS `danger`；33 §5-9「erasure 與 legal hold 衝突時 hold 優先」） | 「排程刪除」在未滿 30 天時禁用並顯示「還有 N 天可執行」；命中 legal hold 顯示 hold 案號與建立人；刪除僅 `owner` 可做（32 §5） |

#### 2-C 其餘九個分頁（本模組負責的讀取面與租戶級動作）

| 分頁 | 控件 | 邏輯規則（含具體數值） | 狀態／邊界 |
|---|---|---|---|
| 資質 KYC | `kycreq`／`kycdocs` | requirements 五分類排序：**平台資訊請求 → past_due → currently_due → future → eventually_due**（33 §2.3）；三種補救路徑：代租戶提交／產生補件連結寄租戶（**7 天有效**，原型按鈕文案）／升級為工單。文件**僅能經後台上傳**（禁 email/chat），**有效期須大於 90 天**（DOCS `kycdocs`） | 已通過的店顯示「資質已通過（核准日）」＋主體類型；**主體變更不走編輯，須走店鋪過戶流程並簽轉讓協議**（原型文案，有贊模型） |
| 用量配額 | `usage` | 七項用量對 `config/limits.yml`：商品數／變體數／員工席次／媒體儲存／API 成本每分／Webhook 端點／自訂網域。三段式 `log_only`／`warn 60%`／`error 100%`（33 §2.10）。覆寫寫入 `limits_overrides` ＋審計（32 §3-3）。API 成本吃滿回 **429＋Retry-After**（28 §0.4） | meter 門檻線畫在 60%；達 100% 的項目在列表頁「用量峰值」欄轉紅；覆寫後**立即生效**（32 §9-7） |
| 計費 | `billsub`／`dunning` | **凍結時此頁仍須可讀**（33 §2.1 兩個必須保留的例外之一）。催繳歷程顯示兩條硬線：**D+28 凍結**、**凍結後 60 天終止**（33 §2.4）；重試節奏建議 **D+1／D+3／D+7／D+14**（33 §2.4，節奏自定） | `past_due` 橫幅顯示「距 D+28 凍結線剩 N 天，已重試 M 次」；**受限期間暫停計費**（33 §2.1 `restricted`） |
| 金流 | `paychannel`／`payout` | **租戶自持商戶號，平台只存 MerchantID／HashKey／HashIV 做代理設定**（33 §2.6 台灣紅線：《電子支付機構管理條例》）。撥款 **T+4 工作日**（33 §2.6）；`delay_days` 上限 **31 天**；負餘額**滿 180 天由平台餘額補平**＝平台損失曝險上限。費率覆寫需**四眼**（DOCS `paychannel`） | 後台**不得出現「平台錢包／提現」字樣**（33 §2.6）——文案驗收項；負餘額距 180 天 ≤30 天顯示紅色警語 |
| 網域與環境 | `domains`／`shopenvs` | TXT 挑戰＋CNAME 檢查；主域 **301 收斂**（30 §9-3）。非正式環境**預設**：擋搜尋引擎＋停對外 email＋還原後自動停用 webhook／app（33 §2.12，「這三件事是預設而非選項」） | DNS 驗證失敗可重驗；環境為 W4 波次，非企業方案顯示佔位卡 |
| 風控 | `riskscore`／`shopdisputes` | 四級風險 `Normal`／`Elevated`／`Highest`／`Not assessed`；風險階梯：**暫停撥款 → 暫停收款 → 拒絕（永久）**（DOCS `riskscore`）。爭議率**雙欄並列**：卡組織回報值／我方即時估算值（33 §2.5，回報值延遲約 1 個月）；Visa 同月分母、**Mastercard 本月爭議 ÷ 上月交易筆數** | 越 0.5% 轉黃、越 1.5% 轉紅並**自動開案＋限制提現**（DOCS `ratemonitor`）；MC 需**連續 3 個月**低於門檻才除名 |
| 合規 | `shopcompliance`／`shopinvoice` | 前台合規巡檢六項（台灣）：營業人名稱與統編揭露／隱私權政策／退換貨政策／七天鑑賞期告知／鑑賞期例外商品標示／稅籍登記網域一致。**每日 06:00 自動掃，不合格自動開工單**（DOCS `shopcompliance`）。電子發票：字軌餘量 **15% 門檻**主動通知（DOCS `einvoice`）、工商憑證**效期 5 年、到期前 60 天內須重新申請**（33 §2.14）、開立時機建議**出貨時** | 字軌耗盡＝無法開立（台灣最常見事故）→ 越門檻自動開工單並上總覽佇列 |
| 工單 | 本店工單 | 見「工單」模組；此處只列該店 open 工單＋「代客建立工單」 | 空 → 「目前沒有工單」 |
| 審計 | `shopaudit` | 全域審計 `WHERE shop_id = ?`；append-only；**租戶端亦可見**（33 §7-4 信任差異化） | 時間軸；點列展開 previous/next JSON diff（33 §2.8） |

### 3. 資料模型

#### 3.1 既有表增補：`shops`

```ruby
# db/migrate/20260812000001_add_lifecycle_to_shops.rb
# 對應 docs/design/33 §2.1（12 態）與 §4（M0 必須先埋的欄位清單）。
# 為什麼在 M0 就埋：33 §4 明示「否則 W1 落地時要動大表」——shops 是全平台最熱的表，
# 上線後加 enum 欄位會鎖表（specs/11 §8 坑 10）。
class AddLifecycleToShops < ActiveRecord::Migration[8.1]
  def change
    change_table :shops, bulk: true do |t|
      t.string   :status, null: false, default: "draft", limit: 20   # 12 態，見 ShopLifecycle::STATUSES
      t.string   :status_reason, limit: 40                            # 原因碼（非自由文字）
      t.string   :restricted_from_status, limit: 20                   # 處置前的狀態，解除時回復用
      t.datetime :status_changed_at
      t.datetime :trial_ends_at                                       # 33 §2.1：trial 14 天
      t.datetime :closed_at
      t.datetime :deletable_after                                     # closed_at + 30 天（32 §2）
      t.datetime :data_retention_until                                # closed_at + 2 年（33 §2.1）
      t.boolean  :subdomain_permanently_reserved, null: false, default: false  # 33 §2.1：子網域永久不可重用
      t.string   :tax_id, limit: 8                                    # 統編（法規要求前台揭露 → 非機密，不加密）
      t.datetime :tax_id_verified_at
    end
    add_index :shops, [:status, :id]
    add_index :shops, [:status, :trial_ends_at]
    add_index :shops, :tax_id
  end
end
```

> **為什麼 `status` 用 `string` 而非 MySQL `ENUM`**：MySQL ENUM 改值要 `ALTER TABLE`（12 態未來還會加），且 Rails 端 `enum` 已提供型別安全。約束靠 model 層 `validates :status, inclusion:` ＋ `CHECK` constraint（MySQL 8 支援）。
>
> **為什麼 `restricted_from_status` 存在 shops 而非 restrictions**：解除全部旗標時要知道回到哪一態；存在旗標列上會有「多個旗標各記一個來源態」的歧義。

#### 3.2 新表（33 §6 已列，本節給完整 DDL）

```sql
-- 六級分級處置（33 §2.2、§6）。旗標是「列」不是 shops 的六個 boolean 欄位，
-- 因為每個旗標各有 reason / expires_at / created_by，而且要查得到歷史。
CREATE TABLE shop_restrictions (
  id           BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id      BIGINT      NOT NULL,
  flag         VARCHAR(16) NOT NULL,   -- payin/payout/trade/readonly/offline/banned
  reason_code  VARCHAR(40) NOT NULL,   -- 見 §6.3 REASON_CODES
  note         TEXT        NULL,
  expires_at   DATETIME    NULL,       -- NULL = 不自動解除
  created_by   BIGINT      NOT NULL,   -- platform_staffs.id
  released_at  DATETIME    NULL,
  released_by  BIGINT      NULL,
  created_at   DATETIME    NOT NULL,
  updated_at   DATETIME    NOT NULL,
  -- 同一 shop 同一 flag 只能有一筆「生效中」：用 generated column + 唯一索引兜底（specs/11 §3 第三板斧）
  active_key   VARCHAR(24) GENERATED ALWAYS AS (IF(released_at IS NULL, flag, NULL)) STORED,
  UNIQUE KEY uniq_shop_active_flag (shop_id, active_key),
  KEY idx_shop_created (shop_id, created_at),
  KEY idx_expiry (expires_at),                    -- 到期掃描用；平台級 job 查詢，不以 shop_id 開頭 → 需白名單註記
  CONSTRAINT fk_shop_restrictions_shop FOREIGN KEY (shop_id) REFERENCES shops(id)
) ENGINE=InnoDB;
```

> **索引鐵律說明**：`idx_expiry (expires_at)` **不以 `shop_id` 開頭**，因為它服務的是平台級到期掃描 job（`WHERE expires_at <= NOW() AND released_at IS NULL`）。此索引須登記在 `config/tenancy_exempt_tables.yml` 的 `exempt_indexes` 區段並附理由，否則 `tenancy_guard_spec` 會紅。**這是白名單的正確用法：例外要留下書面理由，不是關掉檢查。**

```sql
-- 授權式代登入（33 §2.9、§6）。平台域 + 租戶關聯表。
CREATE TABLE access_grants (
  id                BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id           BIGINT       NOT NULL,
  staff_id          BIGINT       NOT NULL,        -- platform_staffs.id（請求方）
  code_digest       VARCHAR(64)  NOT NULL,        -- HMAC-SHA256(4 位數碼)，不存明碼
  scopes            JSON         NOT NULL,        -- ["orders:read","products:read",...]
  reason            TEXT         NOT NULL,        -- 事由必填（32 §4-1）
  ticket_id         BIGINT       NULL,            -- DOCS tickettable：代登入必須綁工單編號
  state             VARCHAR(16)  NOT NULL,        -- pending/approved/rejected/revoked/expired
  requested_at      DATETIME     NOT NULL,
  approved_at       DATETIME     NULL,
  approved_by       BIGINT       NULL,            -- 商家端 staff id
  rejected_at       DATETIME     NULL,
  revoked_at        DATETIME     NULL,
  revoked_by        VARCHAR(16)  NULL,            -- platform / merchant / system
  last_used_at      DATETIME     NULL,            -- 90 天未使用自動失效的計時基準
  expires_at        DATETIME     NOT NULL,        -- approved_at + 90 天
  failed_code_tries INT          NOT NULL DEFAULT 0,
  created_at        DATETIME     NOT NULL,
  updated_at        DATETIME     NOT NULL,
  KEY idx_shop_state (shop_id, state, requested_at),
  KEY idx_staff_state (staff_id, state),          -- pending 上限 10 的計數查詢（平台級 → 白名單）
  CONSTRAINT fk_access_grants_shop FOREIGN KEY (shop_id) REFERENCES shops(id)
) ENGINE=InnoDB;

-- 單次工作階段（32 §7 已列）。一個 grant 可開多次 session，每次 60 分鐘。
CREATE TABLE impersonation_sessions (
  id             BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id        BIGINT      NOT NULL,
  grant_id       BIGINT      NOT NULL,
  staff_id       BIGINT      NOT NULL,
  reason         TEXT        NOT NULL,
  token_digest   VARCHAR(64) NOT NULL,
  started_at     DATETIME    NOT NULL,
  expires_at     DATETIME    NOT NULL,   -- started_at + 60 分鐘（33 §2.9 / 32 §4-2）
  revoked_at     DATETIME    NULL,
  last_action_at DATETIME    NULL,
  actions_count  INT         NOT NULL DEFAULT 0,
  created_at     DATETIME    NOT NULL,
  UNIQUE KEY uniq_token (token_digest),
  KEY idx_shop_started (shop_id, started_at),
  CONSTRAINT fk_imp_sessions_grant FOREIGN KEY (grant_id) REFERENCES access_grants(id)
) ENGINE=InnoDB;
```

```sql
-- 上限覆寫（33 §4 M0 清單列為表；取代 32 §7 的 shops.limits_overrides JSON 欄位）
-- 為什麼改表不改 JSON：每筆覆寫要有 reason / created_by / expires_at 並可查歷史，
-- JSON 欄位做不到，而且無法對「哪些店覆寫了 products 上限」建索引。
CREATE TABLE limits_overrides (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id     BIGINT       NOT NULL,
  key_name    VARCHAR(64)  NOT NULL,     -- 對應 config/limits.yml 的鍵
  value_int   BIGINT       NOT NULL,
  reason      TEXT         NOT NULL,
  created_by  BIGINT       NOT NULL,
  expires_at  DATETIME     NULL,
  revoked_at  DATETIME     NULL,
  created_at  DATETIME     NOT NULL,
  updated_at  DATETIME     NOT NULL,
  active_key  VARCHAR(72)  GENERATED ALWAYS AS (IF(revoked_at IS NULL, key_name, NULL)) STORED,
  UNIQUE KEY uniq_shop_active_key (shop_id, active_key),
  KEY idx_shop_created (shop_id, created_at)
) ENGINE=InnoDB;

-- 配額三段式的 warn 事件（33 §2.10）。每日摘要 email 的資料來源。
CREATE TABLE quota_events (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id     BIGINT       NOT NULL,
  key_name    VARCHAR(64)  NOT NULL,
  mode        VARCHAR(12)  NOT NULL,     -- log_only / warn / error
  used_value  BIGINT       NOT NULL,
  limit_value BIGINT       NOT NULL,
  ratio_bp    INT          NOT NULL,     -- 使用率，basis point（6000 = 60.00%）。整數，不用 float。
  occurred_at DATETIME(3)  NOT NULL,
  KEY idx_shop_key_time (shop_id, key_name, occurred_at)
) ENGINE=InnoDB;
```

> **為什麼 `ratio_bp` 用 basis point 整數**：`specs/11 §8` 坑 3 說金額禁 float；使用率雖非金額，但同樣會進比較與門檻判斷，float 的 `59.999999%` 會讓 60% 門檻抖動。統一整數化。

```sql
-- 審計日誌（32 §7 已列，本節依 33 §2.8 增補欄位）
ALTER TABLE platform_audit_logs
  ADD COLUMN previous       JSON        NULL,
  ADD COLUMN `next`         JSON        NULL,
  ADD COLUMN transaction_id CHAR(36)    NULL,     -- 同一操作多事件串接（Okta 維度）
  ADD COLUMN source         VARCHAR(12) NOT NULL DEFAULT 'ui',   -- ui / api / automation
  ADD COLUMN outcome        VARCHAR(12) NOT NULL DEFAULT 'success',
  ADD COLUMN user_agent     VARCHAR(255) NULL,
  ADD COLUMN request_id     CHAR(36)     NULL,
  ADD COLUMN session_id     CHAR(36)     NULL,
  ADD COLUMN target_type    VARCHAR(40)  NULL,
  ADD COLUMN target_id      BIGINT       NULL,
  ADD COLUMN impersonated   TINYINT(1)   NOT NULL DEFAULT 0;     -- 33 §2.9：代登入動作雙寫標記
ALTER TABLE platform_audit_logs
  ADD INDEX idx_shop_created (shop_id, created_at),
  ADD INDEX idx_txn (transaction_id),
  ADD INDEX idx_actor_created (staff_id, created_at),
  ADD INDEX idx_action_created (action, created_at);
```

> **append-only 落實**（33 §2.8「DB 層不授權 update/delete」）：
> 1. 應用層：`PlatformAuditLog#readonly?` 永遠回 `true`，並移除 `destroy`。
> 2. DB 層：`REVOKE UPDATE, DELETE ON chilllove_production.platform_audit_logs FROM 'app'@'%';` 寫進 `db/grants.sql` 並在部署 checklist 執行。
> 3. 保留期 **12 個月，最近 3 個月須可立即查詢**（PCI DSS 10.5.1，33 §2.8）→ 3 個月以上的分區搬到冷表 `platform_audit_logs_archive`（MySQL 8 分區或月表）；purge job 刪 12 個月以上（`specs/11 §7-2` purge 任務要求）。

#### 3.3 平台冪等表

```sql
-- 平台寫入型 mutation 的冪等（AGENTS.md 技術鐵律 4、28 §0.6）。
-- 與商家域的 idempotency_keys（specs/11 §2-3）分開，因為平台操作沒有 shop_id 語意
-- （批次操作跨多店），且要記錄 staff_id 以便追責。
CREATE TABLE platform_idempotency_keys (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  idem_key      VARCHAR(64) NOT NULL,
  staff_id      BIGINT      NOT NULL,
  operation     VARCHAR(64) NOT NULL,
  request_digest CHAR(64)   NOT NULL,    -- SHA256(規範化後的參數)；同 key 不同參數 → 回 IDEMPOTENCY_KEY_CONFLICT
  response_json JSON        NULL,
  state         VARCHAR(12) NOT NULL,    -- in_flight / done
  created_at    DATETIME(3) NOT NULL,
  updated_at    DATETIME(3) NOT NULL,
  UNIQUE KEY uniq_idem_key (idem_key),
  KEY idx_created (created_at)           -- purge：保留 30 天
) ENGINE=InnoDB;
```

### 4. API 契約（Platform:: GraphQL）

端點與慣例同前（32 §6、28 §0）。權限欄對照 **32 §5 權限矩陣**。

| 操作名 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformShops` | query | `query: String`、`status: [ShopStatus!]`、`riskLevel`、`first ≤250`、`after`、`sortKey` | `ShopConnection{ nodes{ id, name, subdomain, status, riskLevel, gmv30d: MoneyV2, disputeRatioBp, usagePeakPct, createdAt }, pageInfo }` | — | 全部 |
| `platformShop` | query | `id: ID!` | `PlatformShop`（含 `lifecycle`、`restrictions`、`kyc`、`usage`、`billing`、`payments`、`domains`、`risk`、`compliance`、`tickets`、`auditLogs` connection） | `NOT_FOUND` | 全部 |
| `platformShopFreeze` | mutation | `id: ID!`、`reason: FreezeReason!`、`note: String`、`idempotencyKey: String!` | `{ shop, userErrors }` | `FORBIDDEN`／`INVALID_STATE_TRANSITION`／`NOTE_REQUIRED`／`IDEMPOTENCY_KEY_CONFLICT` | owner／admin |
| `platformShopUnfreeze` | mutation | `id: ID!`、`idempotencyKey: String!` | 同上 | `FORBIDDEN`／`INVALID_STATE_TRANSITION` | owner／admin |
| `platformShopPause` / `platformShopResume` | mutation | `id: ID!`、`reason`、`idempotencyKey: String!` | 同上 | `FORBIDDEN`／`INVALID_STATE_TRANSITION` | owner／admin |
| `platformShopClose` | mutation | `id: ID!`、`reason: CloseReason!`、`confirmName: String!`、`idempotencyKey: String!` | 同上 | `CONFIRM_NAME_MISMATCH`／`FORBIDDEN`／`INVALID_STATE_TRANSITION` | owner／admin（二次確認） |
| `platformShopScheduleDeletion` | mutation | `id: ID!`、`confirmName: String!`、`idempotencyKey: String!` | `{ shop, deletionScheduledAt, userErrors }` | `GRACE_PERIOD_NOT_ELAPSED`／`LEGAL_HOLD_ACTIVE`／`CONFIRM_NAME_MISMATCH`／`FORBIDDEN` | **僅 owner**（32 §5） |
| `platformShopRestrictionsSet` | mutation | `id: ID!`、`flags: [RestrictionFlag!]!`（宣告式全集，`*Set` 語義 28 §0.3）、`reasonCode: RestrictionReason!`、`note: String`、`expiresAt: DateTime`、`notify: NotifyMode!`、`idempotencyKey: String!` | `{ shop, restrictions, userErrors }` | `FORBIDDEN`／`REASON_REQUIRED`／`NOTE_REQUIRED`／`BANNED_REQUIRES_CONFIRMATION`／`OWNER_APPROVAL_REQUIRED`（notify=NONE 時） | owner／admin |
| `platformShopLimitsOverride` | mutation | `id: ID!`、`key: String!`、`value: Int!`、`reason: String!`、`expiresAt`、`idempotencyKey: String!` | `{ shop, override, userErrors }` | `UNKNOWN_LIMIT_KEY`／`VALUE_OUT_OF_RANGE`／`FORBIDDEN` | owner／admin |
| `platformShopFlagSet` | mutation | `id: ID!`、`key: String!`、`enabled: Boolean!` | `{ shop, userErrors }` | `UNKNOWN_FLAG`／`FORBIDDEN` | owner／admin |
| `platformAccessGrantRequest` | mutation | `shopId: ID!`、`code: String!`（4 碼）、`scopes: [AccessScope!]!`、`reason: String!`、`ticketId: ID` | `{ grant, userErrors }` | `CODE_INVALID`／`CODE_EXPIRED`／`PENDING_LIMIT_EXCEEDED`／`TOO_MANY_ATTEMPTS`／`SHOP_BANNED`／`FORBIDDEN` | owner／admin／support（32 §5） |
| `platformAccessGrantRevoke` | mutation | `id: ID!` | `{ grant, userErrors }` | `NOT_FOUND`／`FORBIDDEN` | owner／admin／support |
| `platformAccessSessionStart` | mutation | `grantId: ID!` | `{ session{ id, expiresAt, entryUrl }, userErrors }` | `GRANT_NOT_APPROVED`／`GRANT_EXPIRED`／`GRANT_REVOKED`／`FORBIDDEN` | owner／admin／support |
| `platformAccessSessionRevoke` | mutation | `id: ID!` | `{ session, userErrors }` | `NOT_FOUND` | owner／admin／support |
| `platformShopsExport` | mutation | `query`、`status`、`format: CSV` | `{ job{ id, state }, userErrors }` | `EXPORT_ALREADY_RUNNING`／`FORBIDDEN` | owner／admin（審計匯出僅 owner/admin，32 §5） |
| `platformShopsBulkAction` | mutation | `ids: [ID!]!`（≤250）、`action: BulkAction!`、`payload: JSON`、`idempotencyKey: String!` | `{ results[{ id, ok, code, message }], userErrors }` | `TOO_MANY_IDS`／`FORBIDDEN` | owner／admin |

**ShopStatus enum（12 值，33 §2.1）**：`DRAFT`／`PENDING_REVIEW`／`INFO_REQUIRED`／`REJECTED`／`TRIAL`／`ACTIVE`／`PAST_DUE`／`RESTRICTED`／`PAUSED`／`FROZEN`／`CLOSED`／`DELETED`。

**RestrictionFlag enum（六級，33 §2.2）**：`PAYIN`／`PAYOUT`／`TRADE`／`READONLY`／`OFFLINE`／`BANNED`。

**未授權一律回 `userErrors{code:"FORBIDDEN"}` 且 HTTP 200**（32 §9-6、28 §0.3）——**不回 403**。存在性洩漏防護：跨權限查不到的資源回 `NOT_FOUND` 而非 `FORBIDDEN`（`specs/12 §F4-3` 同精神）。

### 5. 服務物件與背景任務

| Class | 單一責任 | 冪等策略 | 失敗與重試 | outbox |
|---|---|---|---|---|
| `Platform::Shops::TransitionService` | **12 態轉移的唯一入口**。驗證轉移合法性、寫 status、寫審計、排副作用 job | `platform_idempotency_keys` ＋「目標態已達成即 no-op」雙保險（32 §9-2） | transaction 內只做 DB；副作用 `after_commit` 派 job | **是**：`shop.status_changed`、`shop.frozen`、`shop.unfrozen`、`shop.closed` |
| `Platform::Shops::ApplyStatusEffectsJob` | 執行狀態副作用矩陣（前台 HTTP／後台權限／金流／webhook／排程 job／搜尋索引／計費） | 每個副作用各自冪等（設定值寫入為宣告式，重跑同值） | Solid Queue 重試 5 次；最終失敗 → `platform_audit_logs` 記 `outcome:"partial_failure"` ＋ Sentry ＋ 佇列卡告警 | 否（它是 outbox 的消費者） |
| `Platform::Shops::RestrictionService` | 六旗標宣告式 set（diff add/remove）、到期時間、通知、審計 | 宣告式：傳入的 flags 陣列即最終狀態，重放同陣列＝no-op | 同上 | **是**：`shop.restrictions_changed` |
| `Platform::Shops::RestrictionExpiryJob` | 掃 `expires_at <= NOW() AND released_at IS NULL` 自動解除 | 條件式 UPDATE（`WHERE released_at IS NULL`），看 affected rows | 每小時跑；失敗重試 | 是 |
| `Platform::AccessGrants::RequestService` | 驗授權碼、檢查 pending 上限 10、建 grant、通知商家 | `(shop_id, staff_id, state:"pending")` 條件式插入 ＋ 冪等鍵 | 通知寄信在 commit 後 | **是**：`access_grant.requested` |
| `Platform::AccessGrants::StartSessionService` | 開 60 分鐘工作階段、產 token、寫審計 | 同一 grant 已有未過期 session → 回既有 session（不重開） | — | **是**：`access_session.started` |
| `Platform::AccessGrants::ExpiryJob` | 90 天未使用的 grant 轉 `expired`；過期 session 標記 | 條件式 UPDATE | 每日跑 | 是 |
| `Platform::AuditLogger` | 寫 `platform_audit_logs`，統一欄位集與 PII 過濾 | 純 insert，由呼叫方保證只呼叫一次（在同一 transaction 內） | 寫失敗即整個 transaction 回滾——**審計寫不進去就不准改資料** | 否 |
| `Platform::Quota` | 配額三段式檢查（60% warn／100% error） | 純檢查 | warn 寫 `quota_events`（best-effort，失敗不阻塞） | 否 |
| `Platform::Shops::ExportJob` | >50 筆的 CSV 匯出、上傳、簽名連結（24h）、寄信 | 同 staff 同時 1 個（advisory 條件） | 失敗寄失敗通知 | 否 |

### 6. 關鍵流程與演算法

#### 6.1 12 態狀態機：轉移表與副作用矩陣

```ruby
# app/models/concerns/shop_lifecycle.rb
module ShopLifecycle
  extend ActiveSupport::Concern

  # 12 態（docs/design/33 §2.1）。
  #
  # 為什麼不引 state_machines-activerecord / AASM：
  # 這些 gem 的 callback 預設跑在 save 的 transaction 內，而我們的轉移副作用包含
  # 寄信、CDN purge、webhook 停發等外部 IO——一旦被寫進 callback 就違反
  # docs/specs/11 §8 坑 2（transaction 內禁外部 IO）。這裡把「合法轉移」與「副作用」
  # 拆成兩張純資料表，轉移由 TransitionService 執行、副作用由 after_commit job 執行。
  STATUSES = %w[
    draft pending_review info_required rejected trial active
    past_due restricted paused frozen closed deleted
  ].freeze

  # 合法轉移表。key = 來源態，value = 允許的目標態。
  # 未列出的組合一律回 userErrors code:"INVALID_STATE_TRANSITION"。
  TRANSITIONS = {
    "draft"          => %w[pending_review deleted],
    "pending_review" => %w[info_required rejected trial active],
    "info_required"  => %w[pending_review rejected],
    "rejected"       => %w[pending_review],
    "trial"          => %w[active past_due restricted paused closed],
    "active"         => %w[past_due restricted paused frozen closed],
    "past_due"       => %w[active frozen restricted closed],
    "restricted"     => %w[active past_due frozen closed],
    "paused"         => %w[active closed],
    "frozen"         => %w[active closed],
    "closed"         => %w[active deleted],   # closed→active＝復店（33 §2.1「資料保留 2 年可復店」）
    "deleted"        => [].freeze,            # 終態，不可逆（32 §2）
  }.freeze

  # 每一態的四維度副作用（33 §2.1 表格逐格落地）。
  # ApplyStatusEffectsJob 讀這張表決定要做什麼——宣告式，所以重跑安全。
  #
  # storefront:  200=正常 / 503=暫停服務頁+noindex / 410=永久移除（30 §9 死鏈規範）/ nil=未開通
  # admin:       full / readonly / limited（可看帳單+提申訴+換銀行帳號）/ billing_only / none
  # payments:    live / test / off
  # webhooks:    on / off
  # jobs:        on / paused
  # billing:     charging / paused / settled / none
  EFFECTS = {
    "draft"          => { storefront: nil, admin: :form_only,   payments: :off,  webhooks: :off, jobs: :paused, billing: :none },
    "pending_review" => { storefront: nil, admin: :readonly,    payments: :off,  webhooks: :off, jobs: :paused, billing: :none },
    "info_required"  => { storefront: nil, admin: :form_only,   payments: :off,  webhooks: :off, jobs: :paused, billing: :none },
    "rejected"       => { storefront: nil, admin: :readonly,    payments: :off,  webhooks: :off, jobs: :paused, billing: :none },
    "trial"          => { storefront: 200, admin: :full,        payments: :test, webhooks: :on,  jobs: :on,     billing: :none },
    "active"         => { storefront: 200, admin: :full,        payments: :live, webhooks: :on,  jobs: :on,     billing: :charging },
    "past_due"       => { storefront: 200, admin: :full,        payments: :live, webhooks: :on,  jobs: :on,     billing: :charging },
    # restricted：前台「依處分」＝由六旗標決定，不由 status 決定（33 §2.2 的核心洞察）
    "restricted"     => { storefront: :by_flags, admin: :limited, payments: :off, webhooks: :on, jobs: :on,    billing: :paused },
    # paused：商品可看、結帳關閉；折扣／棄單挽回／禮品卡／第三方通路停（33 §2.1）
    "paused"         => { storefront: 200, admin: :full,        payments: :off,  webhooks: :on,  jobs: :on,     billing: :none },
    "frozen"         => { storefront: 503, admin: :billing_only, payments: :off, webhooks: :off, jobs: :paused, billing: :charging },
    "closed"         => { storefront: 410, admin: :readonly,    payments: :off,  webhooks: :off, jobs: :paused, billing: :settled },
    "deleted"        => { storefront: 410, admin: :none,        payments: :off,  webhooks: :off, jobs: :paused, billing: :none },
  }.freeze

  # 兩個「漏了客服會被打爆」的例外（33 §2.1 明列）：
  # ① frozen 時帳單與發票歷史仍可讀 → EFFECTS["frozen"][:admin] == :billing_only（不是 :none）
  # ② frozen 滿 30 天後，顧客的「訂單狀態頁」自動恢復可查
  FROZEN_ORDER_STATUS_PAGE_RESTORE_DAYS = 30
  TRIAL_DAYS = 14                      # 33 §2.1
  DRAFT_AUTO_PURGE_DAYS = 30           # 33 §2.1「30 天未提交自動清」
  CLOSED_DELETABLE_AFTER_DAYS = 30     # 32 §2「關閉滿 30 天」
  CLOSED_DATA_RETENTION_YEARS = 2      # 33 §2.1「資料保留 2 年可復店」
end
```

**完整轉移表（誰可做／前置條件／副作用／冪等）**

| # | 轉移 | 誰可做 | 前置條件 | 副作用 | 冪等要點 |
|---|---|---|---|---|---|
| 1 | `draft → pending_review` | 商家（自助） | KYC 表單必填齊 | 建 `kyc_submissions`；佇列 +1；通知審核組 | 重送同一 submission 回既有件 |
| 2 | `draft → deleted` | 系統 | `created_at + 30 天`且未提交（33 §2.1） | 硬刪 draft 資料；審計去識別化 | 已 deleted → no-op |
| 3 | `pending_review → info_required` | admin／support | 至少一項 requirement 標 `currently_due` | 通知商家＋補件連結（7 天）；**同時套 `payin` 旗標**（33 §2.2「收入暫停但店鋪仍可運營」） | 旗標已存在 → 不重複建列 |
| 4 | `pending_review → rejected` | admin | 至少一個駁回原因碼（8 選 1，33 §2.2） | 通知商家（列原因）；可重送 | — |
| 5 | `pending_review → trial` | admin／系統 | KYC 全通過 | `trial_ends_at = now + 14 天`；解 `payin`；`shop.activated` 事件 | — |
| 6 | `pending_review → active` | admin | KYC 全通過且已付款 | 同上但不設 `trial_ends_at` | — |
| 7 | `info_required → pending_review` | 商家 | 全部 `currently_due`／`past_due` 已補 | 回審核佇列 | — |
| 8 | `info_required → rejected` | 系統 | 逾期未補（33 §2.1） | 同 #4 | — |
| 9 | `trial → active` | 系統 | 付款成功 | 解除試用上限；`shop.activated` | 重放不重發事件（32 §9-2） |
| 10 | `trial → past_due` | 系統 | `trial_ends_at` 到期未轉正（33 §2.1） | 催繳橫幅；dunning 起算 | — |
| 11 | `active → past_due` | 系統 | 首次扣款失敗 | 建 `dunning_attempts`；橫幅；**D+28 倒數起算**（33 §2.4） | 同一發票只起算一次 |
| 12 | `past_due → active` | 系統／admin | 付清 | 清橫幅；停 dunning | — |
| 13 | `past_due → frozen` | 系統／admin | `first_failed_at + 28 天 + grace`（33 §2.4） | 見 EFFECTS["frozen"]；**帳單頁仍可讀**；排 30 天後恢復訂單狀態頁 job | 已 frozen → no-op，不重發事件 |
| 14 | `active/trial/past_due → restricted` | owner／admin | **原因必選**；至少一個旗標 | 記 `restricted_from_status`；**暫停計費**（33 §2.1）；依旗標套副作用 | 旗標 set 為宣告式 |
| 15 | `restricted → active` | owner／admin | 全部旗標解除 | 回復 `restricted_from_status`；恢復計費 | — |
| 16 | `active → paused` | owner／admin／商家 | — | 結帳關閉；折扣／棄單挽回／禮品卡／第三方通路停（33 §2.1）；**無時限** | — |
| 17 | `paused → active` | owner／admin／商家 | 須重選方案（33 §2.1 復業） | 全部恢復 | — |
| 18 | `frozen → active` | 系統／admin | 付清；**超 30 天須重選方案**（33 §2.1） | 全部恢復；`shop.unfrozen` | 32 §9-2 冪等 |
| 19 | `frozen → closed` | owner／admin | 凍結後 60 天未付（33 §2.4「保留終止帳號權利」） | 見 #20 | — |
| 20 | `active/frozen/… → closed` | owner／admin（二次確認＋輸入商店名） | — | 前台 **410**；admin 唯讀**至本期帳單週期結束**；`deletable_after = now + 30 天`；`data_retention_until = now + 2 年`；**子網域永久保留不可重用** | — |
| 21 | `closed → active` | owner | `now < data_retention_until`（2 年內） | 復店 | **待定，需使用者確認**：復店是否沿用原子網域（33 §2.1 只說「子網域永久不可重用」，未區分原租戶復用 vs 他人重註冊） |
| 22 | `closed → deleted` | **僅 owner**（輸入商店名） | `now >= deletable_after`（滿 30 天，32 §2）**且無 legal hold**（33 §5-9） | 資料不可逆刪除（GDPR）；審計永久保留但**去識別化 shop 名**（32 §2） | 已 deleted → no-op |

> **待定，需使用者確認**：`data_retention_until`（closed + 2 年）到期後，若 owner 從未執行「排程刪除」，系統是否**自動** purge？33 §2.1 只寫「資料保留 2 年可復店」，沒寫 2 年後怎麼辦。建議預設自動 purge 並提前 30 天通知，但需確認。

#### 6.2 TransitionService（可直接貼進專案）

```ruby
# app/services/platform/shops/transition_service.rb
module Platform
  module Shops
    # 租戶狀態轉移的唯一入口。
    #
    # 設計約束（docs/design/32 §2）：
    #   「所有轉移走 state machine 單一入口（禁止散落 update_column）」
    #   「凍結/解凍必須冪等：重複請求回相同結果，不重複發事件」
    #
    # 併發策略（docs/specs/11 §3 三板斧之「行鎖」）：
    #   讀-判-寫的複合操作 → SELECT ... FOR UPDATE。鎖順序全專案統一「先 shop 再明細」。
    #   鎖內不做任何 IO：寄信、CDN purge、webhook 停發全部丟到 after_commit 的 job。
    #
    # @example
    #   Platform::Shops::TransitionService.new(
    #     shop: shop, to: "frozen", actor: current_staff,
    #     reason_code: "payment_past_due", note: nil,
    #     idempotency_key: params[:idempotencyKey], request: request
    #   ).call
    class TransitionService
      Result = Struct.new(:shop, :changed, :user_errors, keyword_init: true) do
        def ok? = user_errors.empty?
      end

      # 需要備註的原因碼：選「其他」時備註必填（32 §3-3）
      NOTE_REQUIRED_REASONS = %w[other].freeze

      def initialize(shop:, to:, actor:, reason_code: nil, note: nil,
                     idempotency_key:, request: nil, source: :ui)
        @shop = shop
        @to = to.to_s
        @actor = actor
        @reason_code = reason_code
        @note = note
        @idempotency_key = idempotency_key
        @request = request
        @source = source
      end

      def call
        Platform::Idempotency.wrap(
          key: @idempotency_key, staff: @actor, operation: "shop.transition.#{@to}",
          fingerprint: [@shop.id, @to, @reason_code]
        ) do
          run
        end
      end

      private

      def run
        errors = validate_upfront
        return Result.new(shop: @shop, changed: false, user_errors: errors) if errors.any?

        outcome = nil
        ActiveRecord::Base.transaction do
          # 鎖住這一列，避免兩個 staff 同時凍結／解凍造成事件重複發送。
          shop = ::Shop.lock.find(@shop.id)

          # 冪等第一層：目標態已達成 → 直接回成功且 changed:false，不寫審計、不發事件。
          # 這是 32 §9-2「重放請求不重複發事件」的實作點。
          if shop.status == @to
            # 什麼都不做，讓 transaction 正常結束（沒有寫入就沒有副作用）。
            # 不能用 return——在 transaction block 內 return 會觸發隱式 commit 且跳過後續清理。
            outcome = Result.new(shop: shop, changed: false, user_errors: [])
          else
            unless ShopLifecycle::TRANSITIONS.fetch(shop.status, []).include?(@to)
              outcome = Result.new(shop: shop, changed: false, user_errors: [
                { field: ["id"], code: "INVALID_STATE_TRANSITION",
                  message: "無法從 #{shop.status} 轉為 #{@to}" }
              ])
              raise ActiveRecord::Rollback
            end

            previous = snapshot(shop)
            apply_status!(shop)
            apply_side_effect_columns!(shop)
            shop.save!

            # 審計與業務變更同一 transaction：審計寫不進去就不准改資料（33 §2.8 append-only 的前提）。
            txn_id = SecureRandom.uuid
            Platform::AuditLogger.record!(
              action: "tenant.#{@to}", actor: @actor, shop: shop,
              previous: previous, next_state: snapshot(shop),
              reason: @reason_code, note: @note,
              source: @source, transaction_id: txn_id, request: @request
            )

            # outbox 與業務同 transaction 寫入——這是「事件必達」的唯一保證（specs/18 §F1）。
            EventsOutbox.create!(
              shop_id: shop.id, topic: "shop/status_changed",
              payload: { from: previous[:status], to: @to, reason_code: @reason_code,
                         transaction_id: txn_id }
            )
            outcome = Result.new(shop: shop, changed: true, user_errors: [])
          end
        end

        # 副作用一律在 commit 之後派 job：transaction 內禁外部 IO（specs/11 §8 坑 2）。
        if outcome.changed?
          Platform::Shops::ApplyStatusEffectsJob.perform_later(@shop.id, @to)
          Platform::Shops::NotifyMerchantJob.perform_later(@shop.id, "status_changed", @to)
        end
        outcome
      end

      # 前置驗證：權限、原因必填、備註必填、二次確認。
      # 全部走 userErrors（HTTP 恆 200，28 §0.3），不 raise、不回 4xx。
      def validate_upfront
        errs = []
        errs << { field: [], code: "FORBIDDEN", message: "權限不足" } unless authorized?
        if requires_reason? && @reason_code.blank?
          errs << { field: ["reason"], code: "REASON_REQUIRED", message: "原因必選" }
        end
        if NOTE_REQUIRED_REASONS.include?(@reason_code) && @note.blank?
          errs << { field: ["note"], code: "NOTE_REQUIRED", message: "選「其他」時備註必填" }
        end
        errs
      end

      # 權限矩陣見 docs/design/32 §5：凍結/解凍/關店＝owner+admin；排程刪除＝僅 owner。
      def authorized?
        case @to
        when "deleted" then @actor.owner?
        when "frozen", "closed", "restricted", "paused", "active" then @actor.owner? || @actor.admin?
        else @actor.owner? || @actor.admin? || @actor.support?
        end
      end

      def requires_reason?
        %w[frozen restricted closed paused].include?(@to)
      end

      def apply_status!(shop)
        shop.restricted_from_status = shop.status if @to == "restricted"
        shop.status = @to
        shop.status_reason = @reason_code
        shop.status_changed_at = Time.current
      end

      # 各態專屬的時間欄位。全部是「宣告式賦值」，重跑同值 → 冪等。
      def apply_side_effect_columns!(shop)
        case @to
        when "trial"
          shop.trial_ends_at = ShopLifecycle::TRIAL_DAYS.days.from_now
        when "closed"
          shop.closed_at = Time.current
          shop.deletable_after = ShopLifecycle::CLOSED_DELETABLE_AFTER_DAYS.days.from_now
          shop.data_retention_until = ShopLifecycle::CLOSED_DATA_RETENTION_YEARS.years.from_now
          shop.subdomain_permanently_reserved = true   # 33 §2.1：子網域永久不可重用
        when "active"
          shop.status_reason = nil
          shop.restricted_from_status = nil
        end
      end

      def snapshot(shop)
        { status: shop.status, status_reason: shop.status_reason,
          restrictions: shop.shop_restrictions.active.pluck(:flag).sort }
      end
    end
  end
end
```

**排程刪除的額外守門**（`platformShopScheduleDeletion`）：

```ruby
# app/services/platform/shops/schedule_deletion_service.rb
# 三道關卡，缺一不可（32 §2/§3-3、DOCS danger、33 §5-9）：
#   ① 關閉滿 30 天（shops.deletable_after）
#   ② 輸入商店名完全相符（防手滑；比對前先 strip + 全形轉半形）
#   ③ 無 legal hold 命中——erasure 與 legal hold 衝突時 hold 優先（33 §5-9）
def call
  return err("GRACE_PERIOD_NOT_ELAPSED", "關閉未滿 30 天，還有 #{days_left} 天") if @shop.deletable_after.future?
  return err("CONFIRM_NAME_MISMATCH", "商店名稱不符")                        unless name_matches?
  hold = LegalHold.active.find_by(shop_id: @shop.id)
  return err("LEGAL_HOLD_ACTIVE", "命中法務保全 #{hold.reference}，無法刪除")  if hold
  # …轉 deleted，審計 action:"tenant.delete_scheduled"
end
```

#### 6.3 六級分級處置：宣告式 set ＋ 到期自動解除

```ruby
# app/services/platform/shops/restriction_service.rb
module Platform
  module Shops
    # 六級分級處置（docs/design/33 §2.2）。
    #
    # 為什麼是宣告式 set 而不是 add/remove 兩支 API：
    #   28 §0.3 的 *Set 慣例（metafieldsSet / productSet）——前端傳「最終應該生效的旗標全集」，
    #   後端算 diff。這讓重放天然冪等（同一陣列重送 = no-op），也避免前端漏送 remove 造成殘留旗標。
    #
    # 為什麼旗標與 status 要耦合、怎麼耦合（本手冊裁決，33 未明文，待使用者確認）：
    #   33 §2.2 說六旗標「獨立、可組合」，33 §2.1 又有 restricted 這一態。
    #   裁決：① 套上任一旗標且 status ∈ {active,trial,past_due} → 轉 restricted（記 restricted_from_status）
    #        ② 解除全部旗標且 status == restricted → 回復 restricted_from_status
    #        ③ banned 旗標強制 status → closed，且需 owner + 二次確認
    #   理由：restricted 態帶有「暫停計費」與「有限後台」兩個副作用（33 §2.1），
    #        若旗標與 status 完全脫鉤，這兩件事就沒有觸發點。
    class RestrictionService
      FLAGS = %w[payin payout trade readonly offline banned].freeze

      # 原因碼字典（32 §3-3 modal 的 7 個選項 → 碼化，不存自由文字）
      REASON_CODES = %w[
        payment_past_due kyc_overdue dispute_threshold prohibited_content
        legal_request merchant_request other
      ].freeze

      def initialize(shop:, flags:, reason_code:, note: nil, expires_at: nil,
                     notify: :email_and_inapp, actor:, idempotency_key:, request: nil)
        # …
      end

      def call
        Platform::Idempotency.wrap(key: @idempotency_key, staff: @actor,
                                   operation: "shop.restrictions_set",
                                   fingerprint: [@shop.id, @flags.sort, @reason_code]) do
          run
        end
      end

      private

      def run
        errs = validate
        return failure(errs) if errs.any?

        txn_id = SecureRandom.uuid
        result = nil
        ActiveRecord::Base.transaction do
          shop = ::Shop.lock.find(@shop.id)
          current = shop.shop_restrictions.active.pluck(:flag)
          to_add    = @flags - current
          to_remove = current - @flags

          # 冪等：diff 為空 → 不寫審計、不發通知、不發事件。
          if to_add.empty? && to_remove.empty?
            result = success(shop, changed: false)
            next
          end

          previous = { restrictions: current.sort, status: shop.status }

          to_add.each do |flag|
            # 唯一索引 uniq_shop_active_flag 是最後防線（specs/11 §3 第三板斧）：
            # 即使兩個 staff 同時套同一旗標，DB 也只會有一筆生效中。
            shop.shop_restrictions.create!(
              flag: flag, reason_code: @reason_code, note: @note,
              expires_at: @expires_at, created_by: @actor.id
            )
          end
          # 條件式 UPDATE（無鎖等待，specs/11 §3 首選）
          shop.shop_restrictions.active.where(flag: to_remove)
              .update_all(released_at: Time.current, released_by: @actor.id)

          reconcile_status!(shop, txn_id)

          Platform::AuditLogger.record!(
            action: "tenant.restrictions_set", actor: @actor, shop: shop,
            previous: previous,
            next_state: { restrictions: @flags.sort, status: shop.status },
            reason: @reason_code, note: @note, transaction_id: txn_id, request: @request
          )
          EventsOutbox.create!(shop_id: shop.id, topic: "shop/restrictions_changed",
                               payload: { added: to_add, removed: to_remove,
                                          reason_code: @reason_code, transaction_id: txn_id })
          result = success(shop, changed: true)
        end

        if result.changed?
          Platform::Shops::ApplyRestrictionEffectsJob.perform_later(@shop.id)
          Platform::Shops::NotifyMerchantJob.perform_later(@shop.id, "restrictions_changed", @notify) unless @notify == :none
        end
        result
      end

      def validate
        errs = []
        errs << e("FORBIDDEN", "權限不足") unless @actor.owner? || @actor.admin?
        errs << e("REASON_REQUIRED", "原因必選", ["reasonCode"]) if @reason_code.blank?
        errs << e("NOTE_REQUIRED", "選「其他」時備註必填", ["note"]) if @reason_code == "other" && @note.blank?
        errs << e("UNKNOWN_FLAG", "未知旗標", ["flags"]) if (@flags - FLAGS).any?
        # 「不通知」需 owner 覆核（32 §3-3 modal 規格）
        errs << e("OWNER_APPROVAL_REQUIRED", "不通知商家需 owner 覆核", ["notify"]) if @notify == :none && !@actor.owner?
        # banned 是最終手段：僅 owner 且需二次確認（33 §2.7「查封帳戶」）
        errs << e("FORBIDDEN", "查封帳戶僅 owner 可執行", ["flags"]) if @flags.include?("banned") && !@actor.owner?
        errs
      end

      # 旗標 → status 的耦合規則（見類別註釋的裁決）
      def reconcile_status!(shop, txn_id)
        active = shop.shop_restrictions.active.pluck(:flag)
        target =
          if active.include?("banned") then "closed"
          elsif active.any? && %w[active trial past_due].include?(shop.status) then "restricted"
          elsif active.empty? && shop.status == "restricted" then (shop.restricted_from_status.presence || "active")
          end
        return if target.nil? || target == shop.status

        # 走同一個 TransitionService，維持「單一入口」（32 §2）。
        # 這裡帶 same_transaction: true，讓它復用外層的 transaction 與鎖。
        Platform::Shops::TransitionService.new(
          shop: shop, to: target, actor: @actor, reason_code: @reason_code,
          idempotency_key: "#{@idempotency_key}:status", source: :automation
        ).call_within_transaction!(transaction_id: txn_id)
      end
    end
  end
end
```

**到期自動解除**：

```ruby
# app/jobs/platform/shops/restriction_expiry_job.rb
# 每小時跑。條件式 UPDATE（specs/11 §3 首選，無鎖等待），看 affected rows 判成敗。
# 為什麼不用 expires_at 在讀取時「動態判定已失效」：因為解除要發通知、要落審計、
# 要恢復前台——這些都是副作用，必須有明確的執行時點。
class Platform::Shops::RestrictionExpiryJob < ApplicationJob
  queue_as :low

  def perform
    ActsAsTenant.without_tenant do
      ShopRestriction.where(released_at: nil)
                     .where.not(expires_at: nil)
                     .where(expires_at: ..Time.current)
                     .find_in_batches(batch_size: 200) do |batch|
        batch.group_by(&:shop_id).each do |shop_id, rows|
          Platform::Shops::RestrictionService.new(
            shop: Shop.find(shop_id),
            flags: ShopRestriction.active.where(shop_id: shop_id).where.not(id: rows.map(&:id)).pluck(:flag),
            reason_code: "auto_expiry", actor: PlatformStaff.system,
            idempotency_key: "restriction_expiry:#{shop_id}:#{Date.current}"
          ).call
        end
      end
    end
  end
end
```

#### 6.4 授權式代登入：完整授權流

**流程（33 §2.9 逐條落地，Shopify collaborator ＋ Stripe 時效）**

```
【租戶端】商家後台「支援存取」頁 → 產生 4 位數授權碼
          └ 重新產生即失效舊碼（code_digest 覆寫）
                     ↓ 商家用電話/工單把碼給支援人員（out-of-band）
【平台端】租戶詳情 → 「請求存取」→ 輸入 4 位碼 ＋ 逐項勾選權限 ＋ 事由（必填）＋ 綁工單號
          └ 驗碼（constant-time）→ 檢查 pending 上限 10 → 建 access_grant(state:pending)
                     ↓ email ＋ 站內通知商家
【租戶端】商家看到「依請求權限自動生成的角色」→ 接受／拒絕
          └ 接受 → state:approved，expires_at = now + 90 天
                     ↓
【平台端】「進入商家後台」→ 開 impersonation_session（60 分鐘）
          └ 商家後台頂部持續橫幅「平台支援存取中」
          └ 每個寫入動作 impersonated:true 雙寫審計（商家 audit + platform_audit_logs）
          └ 禁止動作硬擋：改密碼/email、單筆退款 > NT$10,000、刪除商店
                     ↓
【失效】60 分鐘到期 ／ 手動撤銷（雙方皆可）／ 90 天未使用 ／ 商家撤回授權
```

```ruby
# app/services/platform/access_grants/request_service.rb
module Platform
  module AccessGrants
    # 授權式代登入的請求端（docs/design/33 §2.9）。
    #
    # 為什麼不做無條件 impersonate：33 §2.9 明示「取代無條件 impersonate」。
    # 無條件代登入在稽核上站不住腳（SOC 2 / 個資法），也讓商家無從得知誰進過他的店。
    # 這裡照抄 Shopify collaborator request 模型 + Stripe 的時效控制。
    class RequestService
      PENDING_LIMIT = 10          # 33 §2.9：單一請求方 pending 上限 10
      GRANT_TTL_DAYS = 90         # 33 §2.9：90 天未使用自動失效
      MAX_CODE_TRIES = 5          # 待定，需使用者確認：33 未定義試錯上限。
                                  # 4 位數 = 10,000 組，無上限即可暴力破解，故必須設；
                                  # 暫定 5 次/15 分鐘，超過鎖定並通知商家 owner。
      CODE_TRY_WINDOW = 15.minutes

      def call
        errs = validate
        return failure(errs) if errs.any?

        grant = nil
        ActiveRecord::Base.transaction do
          shop = ::Shop.lock.find(@shop.id)

          # pending 上限：在鎖內計數，避免兩個請求同時通過檢查（specs/11 §3）。
          pending = AccessGrant.where(staff_id: @actor.id, state: "pending").count
          if pending >= PENDING_LIMIT
            return failure([e("PENDING_LIMIT_EXCEEDED", "待核准請求已達 #{PENDING_LIMIT} 筆上限")])
          end

          grant = AccessGrant.create!(
            shop: shop, staff_id: @actor.id,
            code_digest: digest(@code),          # 只存 HMAC，不存明碼
            scopes: @scopes, reason: @reason, ticket_id: @ticket_id,
            state: "pending", requested_at: Time.current,
            expires_at: GRANT_TTL_DAYS.days.from_now
          )
          Platform::AuditLogger.record!(
            action: "tenant.access_grant_requested", actor: @actor, shop: shop,
            previous: { grants: [] }, next_state: { scopes: @scopes, reason: @reason, ticket_id: @ticket_id },
            target_type: "AccessGrant", target_id: grant.id, request: @request
          )
          EventsOutbox.create!(shop_id: shop.id, topic: "access_grant/requested",
                               payload: { grant_id: grant.id, scopes: @scopes })
        end

        # 通知在 commit 之後（transaction 內禁外部 IO，specs/11 §8 坑 2）
        Platform::AccessGrants::NotifyMerchantJob.perform_later(grant.id)
        success(grant)
      end

      private

      def validate
        errs = []
        # 角色：support 以上可用；read_only 不可（32 §4-5、§5）
        errs << e("FORBIDDEN", "權限不足") unless @actor.owner? || @actor.admin? || @actor.support?
        errs << e("SHOP_BANNED", "帳號已查封，不可請求存取") if @shop.restricted?("banned")
        errs << e("REASON_REQUIRED", "事由必填", ["reason"]) if @reason.blank?
        errs << e("SCOPES_REQUIRED", "至少勾選一項權限", ["scopes"]) if @scopes.blank?
        errs.concat(verify_code)
        errs
      end

      # 授權碼驗證。
      # ① constant-time 比較，防時序攻擊（ActiveSupport::SecurityUtils）
      # ② 失敗計數 + 時間窗鎖定，防暴力破解（4 位數只有 10,000 組）
      # ③ 碼由商家端產生，重新產生即失效舊碼（33 §2.9）——這裡只驗當前碼
      def verify_code
        setting = @shop.support_access_setting
        return [e("CODE_INVALID", "商家尚未產生授權碼", ["code"])] if setting.nil? || setting.code_digest.blank?
        if setting.failed_tries >= MAX_CODE_TRIES && setting.last_failed_at > CODE_TRY_WINDOW.ago
          return [e("TOO_MANY_ATTEMPTS", "嘗試次數過多，請 15 分鐘後再試")]
        end
        if ActiveSupport::SecurityUtils.secure_compare(setting.code_digest, digest(@code))
          setting.update_columns(failed_tries: 0)
          []
        else
          setting.increment!(:failed_tries)
          setting.update_columns(last_failed_at: Time.current)
          [e("CODE_INVALID", "授權碼不正確", ["code"])]
        end
      end

      def digest(code)
        OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{@shop.id}:#{code}")
      end
    end
  end
end
```

```ruby
# app/services/platform/access_grants/start_session_service.rb
module Platform
  module AccessGrants
    # 開啟 60 分鐘工作階段（33 §2.9 疊 Stripe 時效；32 §4-2）。
    class StartSessionService
      SESSION_TTL = 60.minutes    # 33 §2.9 / 32 §4-2

      def call
        return failure([e("GRANT_NOT_APPROVED", "商家尚未核准")]) unless @grant.state == "approved"
        return failure([e("GRANT_EXPIRED", "授權已逾 90 天未使用而失效")]) if @grant.expires_at.past?
        return failure([e("GRANT_REVOKED", "授權已撤銷")]) if @grant.revoked_at

        # 冪等：同一 grant 已有未過期 session → 回既有的，不重開。
        # 重開會讓「剩餘時間」被無限續期，等同繞過 60 分鐘限制。
        existing = @grant.impersonation_sessions.where(revoked_at: nil)
                         .where("expires_at > ?", Time.current).first
        return success(existing) if existing

        token = SecureRandom.urlsafe_base64(32)
        session = nil
        ActiveRecord::Base.transaction do
          session = ImpersonationSession.create!(
            shop_id: @grant.shop_id, grant: @grant, staff_id: @grant.staff_id,
            reason: @grant.reason, token_digest: Digest::SHA256.hexdigest(token),
            started_at: Time.current, expires_at: SESSION_TTL.from_now
          )
          # 90 天閒置計時的基準：每次「使用」都更新 last_used_at（33 §2.9）
          @grant.update!(last_used_at: Time.current)
          Platform::AuditLogger.record!(
            action: "tenant.access_session_started", actor: @grant.staff, shop: @grant.shop,
            previous: nil, next_state: { scopes: @grant.scopes, ttl_min: 60, reason: @grant.reason },
            target_type: "ImpersonationSession", target_id: session.id, impersonated: true
          )
          EventsOutbox.create!(shop_id: @grant.shop_id, topic: "access_session/started",
                               payload: { session_id: session.id, staff_id: @grant.staff_id })
        end
        success(session, token: token)   # token 只在此回傳一次，之後只存 digest
      end
    end
  end
end
```

**代登入期間的禁止動作硬擋**（商家 admin API 側）：

```ruby
# app/controllers/concerns/impersonation_guard.rb
module ImpersonationGuard
  extend ActiveSupport::Concern

  # 代登入期間的禁止動作（docs/design/33 §2.9 + 32 §4-4）。
  # 這是「伺服器端強制」（specs/11 §0 維度 1）——UI 隱藏不算數，必須在 resolver 前擋。
  FORBIDDEN_MUTATIONS = %w[
    staffMemberUpdate shopOwnerEmailUpdate shopOwnerPasswordUpdate shopDelete
  ].freeze
  REFUND_APPROVAL_THRESHOLD_CENTS = 1_000_000   # NT$10,000（32 §4-4）；integer cents，鐵律 3

  included do
    around_action :with_impersonation_context
  end

  def guard_impersonated_mutation!(name, args)
    return unless Current.impersonation_session

    if FORBIDDEN_MUTATIONS.include?(name)
      raise Platform::ImpersonationForbidden.new(
        code: "ACTION_FORBIDDEN_IN_IMPERSONATION",
        message: "代登入期間不可執行此操作（改密碼／email、刪除商店）"
      )
    end
    # 超額退款需商家覆核，不是直接禁止（32 §4-4「需商家覆核」）
    if name == "refundCreate" && args.dig(:input, :amount_cents).to_i > REFUND_APPROVAL_THRESHOLD_CENTS
      raise Platform::ImpersonationForbidden.new(
        code: "REFUND_REQUIRES_MERCHANT_APPROVAL",
        message: "單筆退款超過 NT$10,000，需商家覆核"
      )
    end
    # scope 檢查：只准做 grant 裡勾選的事（最小必要原則）
    required = Platform::AccessScopes.for_mutation(name)
    unless (required - Current.impersonation_session.grant.scopes).empty?
      raise Platform::ImpersonationForbidden.new(code: "SCOPE_NOT_GRANTED", message: "此授權未包含所需權限")
    end
  end
end
```

**雙寫審計**（33 §2.9「每個動作 `impersonated:true` 雙寫審計」）：

```ruby
# app/services/audit/writer.rb（商家域審計）的 after hook
# 商家域寫一筆（讓商家自己看得到誰動過什麼——33 §7-4 的信任差異化），
# 平台域寫一筆（讓平台稽核追得到）。兩筆共用同一 transaction_id 串接（33 §2.8 Okta 維度）。
if Current.impersonation_session
  Platform::AuditLogger.record!(
    action: "impersonated.#{action}", actor: Current.impersonation_session.staff,
    shop: Current.shop, previous: previous, next_state: next_state,
    impersonated: true, source: :ui,
    transaction_id: Current.audit_transaction_id,
    target_type: target_type, target_id: target_id
  )
  Current.impersonation_session.increment!(:actions_count)
  Current.impersonation_session.update_columns(last_action_at: Time.current)
end
```

#### 6.5 配額三段式 enforcement（用量分頁）

```ruby
# app/services/platform/quota.rb
module Platform
  # 配額三段式 enforcement（docs/design/33 §2.10，SFCC Quota Status 模型）。
  #   log_only → 只記錄不干預（開發環境）
  #   warn     → 達 60% 上儀表板 + 每日摘要 email
  #   error    → 達 100% 擋下並拋例外
  #
  # 為什麼上限值一定要走 config/limits.yml：CLAUDE.md 鐵律 6「不得硬編碼」。
  # 逐店覆寫走 limits_overrides 表（覆寫立即生效並落審計，32 §9-7）。
  class Quota
    WARN_RATIO_BP  = 6_000    # 60.00%
    ERROR_RATIO_BP = 10_000   # 100.00%

    class Exceeded < StandardError
      attr_reader :key, :limit
      def initialize(key:, limit:) = (@key = key; @limit = limit; super("quota exceeded: #{key}"))
    end

    # @param shop [Shop]
    # @param key [String] limits.yml 的鍵，例 "products"
    # @param delta [Integer] 本次要新增的量
    # @raise [Platform::Quota::Exceeded] mode == :error 且會超過 100%
    def self.check!(shop:, key:, delta: 1, used: nil)
      limit = resolve_limit(shop, key)
      used ||= Usage.for(shop, key)
      after = used + delta
      ratio_bp = limit.zero? ? 0 : (after * 10_000 / limit)
      mode = mode_for(shop)

      # warn 段：寫事件供每日摘要，但不阻擋。best-effort，寫失敗不影響業務。
      if ratio_bp >= WARN_RATIO_BP && mode != :log_only
        QuotaEvent.insert_all([{ shop_id: shop.id, key_name: key, mode: mode.to_s,
                                 used_value: after, limit_value: limit, ratio_bp: ratio_bp,
                                 occurred_at: Time.current }]) rescue nil
      end
      # error 段：擋下。呼叫端在 GraphQL 層轉為 userErrors{code:"QUOTA_EXCEEDED"}（HTTP 200，28 §0.3）。
      raise Exceeded.new(key: key, limit: limit) if mode == :error && ratio_bp >= ERROR_RATIO_BP
      { used: after, limit: limit, ratio_bp: ratio_bp, mode: mode }
    end

    # 覆寫 > limits.yml 預設。覆寫可設到期（expires_at），到期自動回落預設值。
    def self.resolve_limit(shop, key)
      override = LimitsOverride.active.find_by(shop_id: shop.id, key_name: key)
      override&.value_int || Rails.application.config_for(:limits).fetch(key.to_sym)
    end
  end
end
```

> **API 成本制是另一條線**：`api_cost_per_minute` 這一項不走 `Quota::Exceeded`，而是走 28 §0.4 的 leaky bucket → HTTP 200 ＋ `errors[0].extensions.code="THROTTLED"`；前台 Ajax 面才是 429＋`Retry-After`（28 §0.4、32 §3-3）。UI 上兩者都顯示在同一張用量表，但提示文案不同。

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| `acts_as_tenant` | ~> 1.0 | 租戶隔離；平台查詢顯式 `without_tenant` | `specs/12 §F4` 已指定 |
| `graphql` | ~> 2.3 | `Platform::` schema | 同前 |
| `strong_migrations` | ~> 2.0 | `shops` 是最熱的表，加欄位/索引必須 online DDL | `specs/11 §8` 坑 10 |
| `annotaterb` | ~> 4.x | model 檔頭欄位註解 | AGENTS.md 註釋規範 |
| `rack-attack` | ~> 6.7 | 授權碼試錯限流、平台登入防爆破（32 §9-11） | `specs/11 §1-7` 已指定 |
| `rotp` ＋ `rqrcode` | 最新穩定 | 平台人員 2FA 強制（32 §0，72h 寬限後鎖定） | 純 Ruby TOTP，無外部服務 |
| `bcrypt` | ~> 3.1 | 已在 Rails 預設；此處用於商家端授權碼的替代方案 | 本手冊用 HMAC-SHA256 而非 bcrypt——4 位數碼需要 constant-time 比較與快速驗證，bcrypt 的慢雜湊在這裡沒有意義（碼本身有試錯上限保護） |
| **不引入** `state_machines-activerecord` / `aasm` | — | — | 見 §6.1 註釋：callback 會把外部 IO 拉進 transaction（`specs/11 §8` 坑 2）；12 態轉移表用凍結 Hash 表達已足夠，且更好測試 |
| **不引入** `paper_trail` | — | — | 審計要求的欄位集（Vercel 10 欄 ＋ Okta 5 個關聯維度，33 §2.8）與 paper_trail 的 versions 表差距大，且 paper_trail 預設允許 delete，違反 append-only |
| Active Storage ＋ 私有 bucket | Rails 內建 | KYC 文件（身分證、存摺封面）儲存 | 文件是高敏 PII：私有 ACL ＋ 短 TTL 簽名 URL（≤5 分鐘），**不進 DB**、**不進 CDN 快取** |

### 8. 實作步驟（Codex 逐條做）

1. **M0 埋表**（33 §4 明列的 W1 表）：`AddLifecycleToShops`、`CreateShopRestrictions`、`CreateAccessGrants`、`CreateImpersonationSessions`、`CreateLimitsOverrides`、`CreateQuotaEvents`、`CreatePlatformIdempotencyKeys`、`AlterPlatformAuditLogs`。每支 migration 檔頭註明對應 `docs/design/33 §6` 或 `32 §7` 的條目（AGENTS.md 註釋規範 2）。
2. 更新 `config/tenancy_exempt_tables.yml`：加入 `exempt_indexes` 區段，登記 `shop_restrictions.idx_expiry`、`access_grants.idx_staff_state` 並附理由字串。跑 `tenancy_guard_spec` 確認綠。
3. 建 `app/models/concerns/shop_lifecycle.rb`（`STATUSES`／`TRANSITIONS`／`EFFECTS` 三張凍結表）；`Shop` include 它，加 `validates :status, inclusion: { in: STATUSES }` ＋ DB `CHECK` constraint。
4. 建 `Platform::Idempotency`（wrap 方法：`in_flight` 佔位 → 執行 → 寫 `response_json` ＋ `state:"done"`；同 key 不同 `request_digest` 回 `IDEMPOTENCY_KEY_CONFLICT`）。
5. 建 `Platform::AuditLogger`（欄位集依 33 §2.8；`filter_parameters` 過濾 password/token/卡號，`specs/12` 坑）。`PlatformAuditLog#readonly? = true`；寫 `db/grants.sql` 的 REVOKE 語句。
6. 建 `Platform::Shops::TransitionService`（§6.2 骨架），含 `call_within_transaction!` 變體供 RestrictionService 復用。
7. 建 `Platform::Shops::ApplyStatusEffectsJob`——讀 `ShopLifecycle::EFFECTS`，逐項執行：前台路由狀態（寫 `shops.storefront_mode`，由 storefront 中介層讀取）、admin 權限模式、金流開關、webhook 投遞開關（`specs/18`）、Solid Queue 排程暫停、搜尋索引 noindex。**每一項都要能單獨重跑**。
8. 建 `Platform::Shops::FrozenOrderStatusPageRestoreJob`——凍結滿 30 天後恢復顧客訂單狀態頁（33 §2.1 例外②）。排程每日跑，掃 `status="frozen" AND status_changed_at <= 30.days.ago`。
9. 建 `Platform::Shops::RestrictionService` ＋ `RestrictionExpiryJob`（§6.3）。
10. 建 `Platform::AccessGrants::{RequestService, ApproveService, StartSessionService, RevokeService, ExpiryJob}`（§6.4）；商家端 `SupportAccessSetting` model（產碼／重產碼）。
11. 建 `ImpersonationGuard` concern 並掛到商家 GraphQL controller 的 `before` hook；建 `Platform::AccessScopes.for_mutation` 對照表（**待定，需使用者確認**：完整 scope 詞彙表；原型只給 4 項）。
12. 建 `Platform::Quota` ＋ `Platform::Usage`；`config/limits.yml` 加入七項用量鍵（商品數／變體數／員工席次／媒體儲存 MB／API 成本每分／Webhook 端點／自訂網域），數值取自 `22 §9.4`（變體 2048、媒體 250 等），未列者標待定。
13. 建 `Platform::ShopQuery`（白名單欄位編譯 SQL，`specs/11 §1`）＋ cursor 分頁（keyset `(created_at, id)`，`specs/11 §4-5` 禁深 OFFSET）。
14. GraphQL：`app/graphql/mutations/platform/` 下逐個 mutation；統一 base class 處理 `idempotencyKey`、`userErrors`、權限檢查。
15. 前端：`src/platform/pages/ShopsPage.tsx`、`ShopDetailPage.tsx` 與十個 tab 元件（§11）。
16. 寫 `docs/dev/m8-platform-tenant-lifecycle.md`（AGENTS.md 強制）。
17. 全套測試綠 → 開 PR。

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/models/concerns/shop_lifecycle_spec.rb` | ①`STATUSES.size == 12`；②`TRANSITIONS` 的所有 key 與 value 都在 `STATUSES` 內（防打錯字）；③`EFFECTS` 覆蓋全部 12 態；④`deleted` 為終態（value 為空陣列） |
| `spec/services/platform/shops/transition_service_spec.rb` | ①**12 態逐一測四維度**（33 §5-1）：對每個 status 斷言 `EFFECTS` 的 storefront／admin／payments／webhooks 值；②非法轉移回 `INVALID_STATE_TRANSITION`；③`frozen` 時 `admin == :billing_only`（例外①）；④凍結滿 30 天後訂單狀態頁恢復（例外②，跑 `FrozenOrderStatusPageRestoreJob` 後斷言）；⑤`reason` 未填回 `REASON_REQUIRED`；⑥`reason == "other"` 且無 note 回 `NOTE_REQUIRED`；⑦`support` 角色凍結回 `FORBIDDEN`（32 §5） |
| `spec/services/platform/shops/transition_idempotency_spec.rb` | ①同一 `idempotencyKey` 送兩次 freeze → 第二次 `changed == false`，`platform_audit_logs` 只有 1 列，`events_outbox` 只有 1 列（32 §9-2）；②已是 `frozen` 再 freeze → `changed == false` 且不發事件；③同 key 不同參數 → `IDEMPOTENCY_KEY_CONFLICT` |
| `spec/services/platform/shops/transition_concurrency_spec.rb` | **併發測法**：兩條 thread 同時對同一 shop 呼叫 freeze（不同 idempotencyKey），斷言最終 `status == "frozen"`、`platform_audit_logs` 恰 1 列、`events_outbox` 恰 1 列。實作見下方範本 |
| `spec/services/platform/shops/restriction_service_spec.rb` | ①六旗標可獨立設定；②可組合（`payin + readonly`）；③宣告式：重送同一陣列 → `changed == false`；④「補件中收款停但店可運營」場景：`flags: ["payin"]` 後斷言 `storefront == 200` 且 `payments == :off`（33 §5-2 指定場景）；⑤`expires_at` 到期後 `RestrictionExpiryJob` 自動解除並落審計；⑥`banned` 非 owner → `FORBIDDEN`；⑦解除全部 → 回復 `restricted_from_status` |
| `spec/services/platform/shops/restriction_concurrency_spec.rb` | 兩條 thread 同時套 `payin` → `shop_restrictions` 生效中的 `payin` 恰 1 列（唯一索引 `uniq_shop_active_flag` 兜底） |
| `spec/services/platform/access_grants/request_service_spec.rb` | ①錯碼 → `CODE_INVALID`；②連錯 5 次 → `TOO_MANY_ATTEMPTS` 且商家收到通知；③pending 已 10 筆 → `PENDING_LIMIT_EXCEEDED`（33 §2.9）；④`read_only` 角色 → `FORBIDDEN`（32 §4-5）；⑤商家重產碼後舊碼失效；⑥`reason` 空 → `REASON_REQUIRED` |
| `spec/services/platform/access_grants/start_session_service_spec.rb` | ①session `expires_at == started_at + 60 分鐘`；②61 分鐘後存取回 `GRANT_EXPIRED`／session 失效；③同一 grant 重複開 → 回既有 session（不續期）；④90 天未使用 → `ExpiryJob` 後 `state == "expired"` |
| `spec/requests/platform/impersonation_guard_spec.rb` | 逐條測 32 §4-4 禁止動作：①`shopOwnerPasswordUpdate` → `ACTION_FORBIDDEN_IN_IMPERSONATION`；②`refundCreate` 金額 1,000,001 cents → `REFUND_REQUIRES_MERCHANT_APPROVAL`；1,000,000 cents 剛好放行；③`shopDelete` 被擋；④未在 grant scopes 內的 mutation → `SCOPE_NOT_GRANTED`；⑤所有動作在**雙方**審計各留一列且 `impersonated == true`、`transaction_id` 相同 |
| `spec/system/platform/impersonation_banner_spec.rb` | 代登入期間商家後台頂部橫幅可見、含剩餘分鐘、撤銷後立即消失（32 §9-5） |
| `spec/services/platform/quota_spec.rb` | ①59.99% 不 warn、60.00% warn；②99.99% 放行、100.00% raise；③`mode == :log_only` 時 100% 也放行但寫 event；④覆寫立即生效（32 §9-7）；⑤覆寫到期後回落預設值 |
| `spec/requests/platform/graphql/shop_permissions_spec.rb` | **32 §5 權限矩陣逐格測試**（5 角色 × 9 動作 = 45 格），未授權一律 `userErrors{code:"FORBIDDEN"}` 且 HTTP 200（32 §9-6） |
| `spec/services/platform/shops/schedule_deletion_service_spec.rb` | ①未滿 30 天 → `GRACE_PERIOD_NOT_ELAPSED`；②商店名不符 → `CONFIRM_NAME_MISMATCH`；③有 legal hold → `LEGAL_HOLD_ACTIVE`（hold 優先，33 §5-9）；④滿足三條件才成功 |
| `spec/models/platform_audit_log_spec.rb` | ①`readonly?` 為 true，`update!` raise；②`destroy` 不存在；③DB 層 REVOKE 生效（用受限帳號連線嘗試 UPDATE 應失敗）；④每個平台寫入動作都有對應列（掃描 `Platform::` 下所有 service 的 spec，斷言各自產生審計） |
| `spec/requests/platform/graphql/shops_query_spec.rb` | ①`first: 251` → cost 錯誤；②搜尋非白名單欄位（如 `password:x`）不生效且不 raise；③cursor 分頁前後翻頁不重不漏（同秒建立的兩列用 `(created_at, id)` tiebreaker，`specs/11 §8` 坑 6） |

**併發測法範本**：

```ruby
# spec/services/platform/shops/transition_concurrency_spec.rb
it "兩個 staff 同時凍結同一家店，只產生一筆審計與一個事件" do
  shop = create(:shop, status: "active")
  a, b = create(:platform_staff, role: :admin), create(:platform_staff, role: :admin)

  # 為什麼要 with_connection：RSpec 預設用 transactional fixtures，thread 內若共用同一條連線
  # 會看不到彼此的鎖，測不出真實競態。這裡每條 thread 拿獨立連線，並改用 truncation 清理。
  threads = [a, b].map do |actor|
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Platform::Shops::TransitionService.new(
          shop: shop, to: "frozen", actor: actor, reason_code: "payment_past_due",
          idempotency_key: SecureRandom.uuid
        ).call
      end
    end
  end
  threads.each(&:join)

  expect(shop.reload.status).to eq("frozen")
  expect(PlatformAuditLog.where(shop_id: shop.id, action: "tenant.frozen").count).to eq(1)
  expect(EventsOutbox.where(shop_id: shop.id, topic: "shop/status_changed").count).to eq(1)
end
```

### 10. 驗收清單

**對應 33 §5**
- [ ] **§5-1 狀態機**：12 態逐一測前台 HTTP／後台可讀寫／金流／webhook 四維度；兩個例外（凍結仍可讀帳單、30 天後訂單狀態頁恢復）**各有測試**。
- [ ] **§5-2 分級凍結**：六旗標可獨立、可組合、可設到期自動解除；「補件中收款停但店可運營」場景有測試。
- [ ] **§5-6 代登入**：授權碼機制、逐項權限、60 分鐘 TTL、90 天閒置失效、商家端橫幅、禁止動作被擋、雙寫審計——**逐條測**。
- [ ] **§5-7 審計**：每個平台寫入動作皆有列且含 before/after；12 個月保留、3 個月可立即查；無 update/delete 權限；可匯出 CSV。
- [ ] **§5-8 配額**：60% warn／100% error 三段式；儀表板紅橘綠；每日摘要。

**對應 32 §9**
- [ ] 凍結後：前台 503＋noindex＋暫停頁；商家後台唯讀＋橫幅；job/feed/webhook 停；解凍全恢復（各有測試）。
- [ ] 凍結/解凍冪等（重放不重複發事件）。
- [ ] 關店→前台 410；30 天後可刪除、之前不可；刪除需輸入商店名。
- [ ] 每個平台寫入動作在 `platform_audit_logs` 有對應列（抽測 100%）。
- [ ] 權限矩陣 §5 逐格測試，未授權回 `userErrors code:FORBIDDEN`。
- [ ] 上限覆寫立即生效且落審計；API 吃滿回 429＋Retry-After（前台面）／THROTTLED（GraphQL 面）。
- [ ] 跨租戶查詢全部位於 `Platform::` 命名空間（靜態掃描）。
- [ ] UI 對照原型逐控件打勾；tokens 全部來自 23 §1。

**七維度（`specs/11 §0`）**
- [ ] 1 安全：權限伺服器端強制（不只擋 UI）；授權碼 constant-time ＋試錯限流；KYC 文件私有 bucket ＋短 TTL 簽名 URL；`filter_parameters` 過濾審計中的密碼/token。
- [ ] 2 資料完整：`shop_restrictions` 唯一索引 `uniq_shop_active_flag`；`limits_overrides` 唯一索引；全部 FK 建立；冪等表就位。
- [ ] 3 併發：狀態轉移、旗標設定、pending 上限三處各有併發測試。
- [ ] 4 效能：租戶列表 keyset 分頁（禁深 OFFSET）；`shops` 列表查詢有 `(status, id)` 索引；bullet 零 N+1（詳情頁十個 tab 用 lazy loading，不一次撈全部）。
- [ ] 5 可觀測：每次狀態轉移寫結構化日誌（`request_id`／`shop_id`／`staff_id`／`transaction_id`）；`ApplyStatusEffectsJob` 部分失敗上 Sentry。
- [ ] 6 測試：§9 全綠；權限矩陣 45 格全測。
- [ ] 7 合規：KYC 文件與擁有者 email 進 PII 清單；`platform_audit_logs` 12 個月 purge job；`deleted` 態的審計去識別化。

### 11. 前端（React/TS）

**元件樹**

```
ShopsPage                                   [列表]
├─ PageHead（匯出 CSV / 批次操作 / 建立商店）
└─ Card
   ├─ ListBar（SavedViewChip / StatusFilterChips / SearchInput）
   ├─ ShopTable（TanStack Table；欄位見 §2-A）
   ├─ EmptyState（清除搜尋與篩選）
   └─ CursorPagination

ShopDetailPage                              [詳情]
├─ DetailHead（返回 / 名稱 / 狀態 badge / 風險 badge / 請求存取 / 處置… / ⋯）
├─ StatusBanner（依 status 切換 5 種橫幅文案）
├─ TabBar（10 個 tab，URL 同步 ?tab=ov|kyc|usage|bill|pay|net|risk|comp|tick|aud）
└─ <Suspense> TabPane（lazy import，每個 tab 一個 chunk）
   ├─ OverviewPane   → LifecycleSteps / BasicInfoDl / RestrictionFlagList / OwnerCard / PlanCard / HealthCard / DangerZone
   ├─ KycPane        → RequirementList / DocumentList
   ├─ UsagePane      → UsageMeterList（門檻線 60%）
   ├─ BillingPane    → SubscriptionDl / DunningTimeline
   ├─ PaymentsPane   → ChannelDl / PayoutList
   ├─ NetworkPane    → DomainList / EnvironmentList
   ├─ RiskPane       → RiskScoreCard / DisputeRatioMeter（雙欄）
   ├─ CompliancePane → ComplianceScanList / EinvoiceDl
   ├─ TicketsPane    → TicketMiniList
   └─ AuditPane      → AuditTimeline（點列開 DiffModal）
Modals（Radix Dialog）
├─ RestrictModal（六 checkbox / 原因 select / 到期 select / 通知 select / 備註 textarea / 即時摘要）
├─ AccessRequestModal（4 位碼 input / 事由 input / scope checkbox 群）
├─ CloseShopModal（輸入商店名確認）
└─ AuditDiffModal（previous/next JSON 並排）
```

**狀態管理**
- TanStack Query：`['platform','shops',filters]`（列表，`keepPreviousData: true` 讓翻頁不閃）、`['platform','shop',gid]`（詳情主體）、`['platform','shop',gid,tab]`（各 tab 獨立 query，**進入該 tab 才發請求**——十個 tab 一次全撈會拖垮 p95）。
- Mutation 後 `invalidateQueries(['platform','shop',gid])` ＋ `['platform','shops']`；狀態轉移類 mutation 額外 invalidate `['platform','actionQueues']`（總覽佇列卡數字要同步）。
- 表單：`react-hook-form` ＋ `zod`。處置 modal 的 schema 直接編碼業務規則：`reasonCode` required、`reasonCode === "other"` 時 `note` required（與後端 `NOTE_REQUIRED` 對齊，前後端同一份規則兩地實作，後端為準）。
- 冪等鍵：每個 mutation 表單在**首次開啟時**產生一個 `crypto.randomUUID()` 存在 form state，重試（含使用者連點）沿用同一把 → 後端天然去重。**送出成功後才換新的**。

**GraphQL 呼叫**

```ts
// src/platform/api/shops.ts
/** 租戶列表。cursor 分頁，first 上限 250（28 §0.3）。 */
export const SHOPS_QUERY = /* GraphQL */ `
  query PlatformShops($query: String, $status: [ShopStatus!], $first: Int!, $after: String) {
    platformShops(query: $query, status: $status, first: $first, after: $after) {
      nodes { id name subdomain status riskLevel usagePeakPct disputeRatioBp createdAt
              owner { name email }
              gmv30d { amount currencyCode } }
      pageInfo { hasNextPage endCursor }
    }
  }`;

/** 分級處置。宣告式 flags 全集（*Set 語義）＋ idempotencyKey（AGENTS.md 鐵律 4）。 */
export const RESTRICTIONS_SET = /* GraphQL */ `
  mutation PlatformShopRestrictionsSet($id: ID!, $flags: [RestrictionFlag!]!, $reasonCode: RestrictionReason!,
                                       $note: String, $expiresAt: DateTime, $notify: NotifyMode!, $idempotencyKey: String!) {
    platformShopRestrictionsSet(id: $id, flags: $flags, reasonCode: $reasonCode, note: $note,
                               expiresAt: $expiresAt, notify: $notify, idempotencyKey: $idempotencyKey) {
      shop { id status restrictions { flag expiresAt reasonCode } }
      userErrors { field message code }
    }
  }`;
```

**三態**

| 狀態 | 呈現 |
|---|---|
| 載入 | 列表：8 列 skeleton row（保留欄寬避免 CLS）。詳情：頭部先出（從列表 cache 拿 name/status），tab 內容各自 skeleton |
| 空 | 列表無結果 → `<EmptyState>`「找不到符合的商店」＋「清除搜尋與篩選」鈕（原型 `#shopEmpty`）。各 tab 空狀態文案逐一指定：KYC「資質已通過」、工單「目前沒有工單」、環境「目前方案不含額外環境」 |
| 錯誤 | ①top-level `errors`（THROTTLED／ACCESS_DENIED）→ 全頁錯誤卡＋重試；②`userErrors` → **綁到對應欄位**（`field` 陣列對應 form 欄位名），無 `field` 的顯示在 modal 頂部 note 條；③mutation 失敗後**不關閉 modal**，保留使用者輸入 |

**危險動作的交互規格**（32 §5「危險動作一律二次確認＋原因寫審計」）
- 紅色主鈕 `btn-crit`；loading 態文字改「套用中…」並禁用（23 §3 Button 規格）。
- 關店／刪除：輸入商店名確認，**比對前 trim ＋ 全形轉半形**，不符時鈕維持禁用。
- 成功 → toast（`role="status" aria-live="polite"`，2.8s）＋ 重新載入詳情。
- modal 開啟時焦點移入第一個可聚焦元素，Esc 關閉，關閉後焦點回到觸發鈕（Radix Dialog 預設行為，需驗證）。

**響應式**（斷點同總覽）

| 斷點 | 本模組特有行為 |
|---|---|
| ≤1279px | 租戶表 `min-width:max-content` 橫捲，並在容器右緣顯示漸層捲動提示（原型 `refreshScrollHints()`） |
| ≤1023px | `detail-grid` 兩欄轉單欄，**但右側欄內部改為 2 欄 grid**（原型 `.detail-grid>div:last-child{grid-template-columns:1fr 1fr}`）——擁有者/方案/健康/危險區四張小卡兩兩並排，不至於過度拉長 |
| ≤767px | 十個 tab 轉橫向捲動 ＋ `scroll-snap-type:x proximity`，tab 高 40px；租戶表轉**堆疊卡片**（`.card-table` 的 `td::before{content:attr(data-label)}` 模式，每列一張卡）；所有 modal 轉貼底 sheet（`max-height:92dvh`＋sticky footer） |
| ≤429px | `usage-row` 轉單欄（meter 獨佔一行、數字左對齊）；`dl` 轉單欄；`page-actions` 三個鈕等分滿寬 |
| `pointer:coarse` | checkbox 放大到 20px；`.switch` 用偽元素撐命中區；`mini-list li` 最小高 48px |

**無障礙**：狀態 badge 不只用顏色（pip 形狀：實圈/半圈/空圈 ＋ 文字）；meter 用 `role="progressbar"` ＋ `aria-valuenow/valuemin/valuemax`；tab 用 Radix Tabs（自帶 `role="tablist"`／方向鍵切換）；六旗標 checkbox 群用 `<fieldset><legend>`。

---

## 審核佇列（KYC）（波次 W1）

> 對應原型：`#v-kyc`；`data-doc` key：`kycorder`（佇列排序規則）、`kycboard`（四欄看板）、頁首「原因碼字典」鈕；租戶詳情側的 `kycreq`／`kycdocs`。
> 規格出處：`33 §2.1`（`pending_review`／`info_required`／`rejected` 三態的時效）、`33 §2.2`（駁回原因碼字典 8 條）、`33 §2.3`（requirements 五分類、排序、三種補救路徑）、`33 §5-3`（驗收）、`33 §6`（三張表定義）。

### 1. 這是什麼、給誰用、解決什麼問題

自助註冊的商店在能收錢之前必須通過資質審核（KYC）。這一頁是**審核組的工作台**——四欄看板：待審／補件中／逾期未補／本週已決。

給誰用：`admin`（可決策核准／駁回）、`support`（可要求補件、代租戶提交、寄補件連結、升級為工單）。

解決三個問題：

1. **逾期件被淹沒**——33 §2.3 明訂佇列排序為「平台資訊請求 → `past_due` → `currently_due` → future → `eventually_due`」，照 Stripe「Actions required」的邏輯排，讓已逾期的件永遠浮在最上面。DOCS `kycorder` 講得很白：「避免逾期件被淹沒」。
2. **補件無止境**——每筆 requirement 有 `deadline`；逾期自動轉 `past_due` 並**停收款但不停店**（DOCS `kycboard`；33 §2.2 店匠洞察）。
3. **駁回理由講不清**——8 條原因碼字典（33 §2.2），不准自由文字。理由碼化才能統計「哪一類退件最多」，才能回頭改註冊流程。

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值） | 狀態／邊界情況 |
|---|---|---|---|
| 頁首 SLA 說明 | 「N 件待處理・目標 SLA 5–7 工作天」 | **5–7 工作天**為 `pending_review` 的目標處理時間（33 §2.1，SHOPLINE 實測值）。工作天計算需扣除週末與國定假日 | **待定，需使用者確認**：國定假日表來源（台灣行政院行事曆需每年更新）；SLA 超時是否升級告警 |
| 「原因碼字典」鈕 | 展示 8 條駁回原因碼 | `SITE_INFO_INCOMPLETE` 官網未揭露公司資訊／`NO_PRIVACY_POLICY` 缺隱私權政策／`SCOPE_MISMATCH` 營業項目與實售不符／`SITE_NOT_LIVE` 網站未上線／`BANK_NAME_MISMATCH` 撥款帳戶名稱與登記名不符／`DOC_EXPIRED` 文件過期／`DOC_UNREADABLE` 文件不清晰／`UBO_MISSING` 缺最終受益人（33 §2.2） | 字典為唯讀常數（`config/kyc_reject_codes.yml`），新增原因碼需改設定檔＋更新文案，不可由 UI 新增 |
| `kycorder` 佇列排序規則說明條 | 說明五分類排序與三種補救路徑 | 排序鍵：`platform_request(0) → past_due(1) → currently_due(2) → future(3) → eventually_due(4)`，同分類內按 `deadline ASC, submitted_at ASC`（33 §2.3） | 說明條為 `note note-info`，不可摺疊（新人第一天就要看到） |
| `kycboard` 四欄看板 | 待審／補件中／逾期未補／本週已決 | 欄位對應：`kyc_submissions.state ∈ {submitted}` ／ `{info_required}` ／ `{info_required 且有 past_due requirement}` ／ `{approved, rejected 且 decided_at 在本週}`。卡片顯示：商店名／主體類型／時間／待審項數或缺件原因碼 | 逾期欄卡片顯示「逾期 N 天・past_due・已停收款」；已決欄只留本週（避免無限增長）；每欄 >50 筆時顯示「查看全部」進列表模式 |
| `kycreq` 補件需求（詳情頁） | 五分類 requirements ＋期限＋錯誤碼 | 每筆顯示 bucket badge（`past_due` 紅／`currently_due` 黃／`pending_verification` 藍／`eventually_due` 灰）＋ requirement key（`bank_account.statement` 等）＋人話說明＋期限。每筆都有**三個補救動作鈕**：代提交／寄連結（**7 天有效**）／升級工單（33 §2.3「三種補救路徑（每筆都要有）」） | 已通過的店顯示「資質已通過（核准日）」＋主體類型；**主體變更不走編輯，須走店鋪過戶流程並簽轉讓協議**（原型文案，有贊模型） |
| `kycdocs` 已提交文件 | 文件清單與驗證狀態 | 文件種類（33 §6）：公司登記／負責人證件／UBO／存摺封面／網域證明／稅籍函。**僅能經後台上傳（禁 email/chat）**；**文件有效期須大於 90 天**（DOCS `kycdocs`） | 狀態四態：未提交／審核中／已驗證／退件（退件顯示原因碼）；`expires_at` 距今 <90 天 → 標「效期不足」並擋核准 |
| 決策動作（詳情頁） | 核准／要求補件／駁回 | 核准需**全部 `currently_due` 與 `past_due` 為空**；要求補件需至少勾一項 requirement；駁回需選 ≥1 個原因碼 | 決策一律二次確認；決策後寫 `decided_at`／`reviewed_by`／`decision`／`reject_codes[]` 並落審計 |

### 3. 資料模型

**新表（33 §6 已列，本節給完整 DDL）**

```sql
-- KYC 提交件（33 §6）
CREATE TABLE kyc_submissions (
  id             BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id        BIGINT      NOT NULL,
  subject_type   VARCHAR(24) NOT NULL,   -- individual / sole_proprietor / limited / joint_stock / foundation
                                         -- （33 §6：個人/獨資/有限公司/股份/財團法人）
  legal_name     VARCHAR(120) NOT NULL,
  tax_id         VARCHAR(8)   NULL,      -- 統編；個人主體為 NULL
  state          VARCHAR(20)  NOT NULL,  -- draft/submitted/info_required/approved/rejected/withdrawn
  submitted_at   DATETIME     NULL,
  reviewed_by    BIGINT       NULL,      -- platform_staffs.id
  decided_at     DATETIME     NULL,
  decision       VARCHAR(12)  NULL,      -- approved / rejected
  reject_codes   JSON         NULL,      -- ["SITE_NOT_LIVE","UBO_MISSING"]，字典見 33 §2.2
  disabled_reason VARCHAR(48) NULL,      -- rejected.fraud / rejected.listed / rejected.terms_of_service /
                                         -- rejected.incomplete_verification / rejected.other（33 §2.3）
  current_deadline DATETIME   NULL,      -- requirements 的最近期限（冗餘欄，供看板排序，由 service 維護）
  created_at     DATETIME     NOT NULL,
  updated_at     DATETIME     NOT NULL,
  KEY idx_shop_created (shop_id, created_at),
  KEY idx_state_deadline (state, current_deadline),   -- 平台級看板查詢 → 白名單
  CONSTRAINT fk_kyc_submissions_shop FOREIGN KEY (shop_id) REFERENCES shops(id)
) ENGINE=InnoDB;

-- 補件需求（33 §2.3 照抄 Stripe Connect requirements 模型；33 §6）
CREATE TABLE kyc_requirements (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id       BIGINT      NOT NULL,    -- 冗餘存放，讓「本店 KYC」查詢不必 join（複合索引以 shop_id 開頭，鐵律 2）
  submission_id BIGINT      NOT NULL,
  key_name      VARCHAR(64) NOT NULL,    -- bank_account.statement / identity.ubo / domain.ownership /
                                         -- company.registration / tax.invoice_permit …（原型可見的 5 個）
  bucket        VARCHAR(24) NOT NULL,    -- platform_request / past_due / currently_due /
                                         -- pending_verification / eventually_due / future（33 §2.3）
  deadline      DATETIME    NULL,
  error_code    VARCHAR(40) NULL,        -- 對應 33 §2.2 原因碼字典
  error_reason  TEXT        NULL,
  satisfied_at  DATETIME    NULL,
  created_at    DATETIME    NOT NULL,
  updated_at    DATETIME    NOT NULL,
  active_key    VARCHAR(72) GENERATED ALWAYS AS (IF(satisfied_at IS NULL, key_name, NULL)) STORED,
  UNIQUE KEY uniq_submission_active_key (submission_id, active_key),
  KEY idx_shop_bucket (shop_id, bucket, deadline),
  KEY idx_bucket_deadline (bucket, deadline),          -- 逾期掃描 job → 白名單
  CONSTRAINT fk_kyc_requirements_sub FOREIGN KEY (submission_id) REFERENCES kyc_submissions(id)
) ENGINE=InnoDB;

-- 已提交文件（33 §6）
CREATE TABLE kyc_documents (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id       BIGINT      NOT NULL,
  submission_id BIGINT      NOT NULL,
  kind          VARCHAR(32) NOT NULL,    -- company_registration / owner_id / ubo / bank_statement /
                                         -- domain_proof / tax_permit（33 §6）
  file_ref      VARCHAR(255) NOT NULL,   -- Active Storage blob key；私有 bucket，短 TTL 簽名 URL
  original_name VARCHAR(255) NOT NULL,
  byte_size     BIGINT      NOT NULL,
  content_type  VARCHAR(64) NOT NULL,
  checksum      CHAR(64)    NOT NULL,    -- SHA256，用來偵測「同一份文件重複上傳」
  expires_at    DATE        NULL,        -- 文件有效期；<90 天視為效期不足（DOCS kycdocs）
  state         VARCHAR(16) NOT NULL,    -- pending / verified / rejected
  reject_code   VARCHAR(40) NULL,
  uploaded_by   VARCHAR(16) NOT NULL,    -- merchant / platform_staff（代租戶提交）
  uploaded_by_id BIGINT     NOT NULL,
  verified_by   BIGINT      NULL,
  verified_at   DATETIME    NULL,
  created_at    DATETIME    NOT NULL,
  updated_at    DATETIME    NOT NULL,
  KEY idx_shop_kind (shop_id, kind, created_at),
  KEY idx_submission (submission_id),
  CONSTRAINT fk_kyc_documents_sub FOREIGN KEY (submission_id) REFERENCES kyc_submissions(id)
) ENGINE=InnoDB;
```

**新表（本手冊提出，33 §6 未列）**

```sql
-- 補件連結（33 §2.3 三種補救路徑之二：「產生補件連結寄給租戶」）
-- 為什麼要獨立表：連結是對外可存取的憑證，必須能撤銷、能查誰產生、能限次數。
CREATE TABLE kyc_remediation_links (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id       BIGINT      NOT NULL,
  submission_id BIGINT      NOT NULL,
  token_digest  CHAR(64)    NOT NULL,    -- 只存 digest，明碼只在寄信當下存在
  requirement_keys JSON     NOT NULL,    -- 這條連結涵蓋哪幾項
  created_by    BIGINT      NOT NULL,
  expires_at    DATETIME    NOT NULL,    -- created_at + 7 天（原型按鈕文案「有效 7 天」）
  used_at       DATETIME    NULL,
  revoked_at    DATETIME    NULL,
  created_at    DATETIME    NOT NULL,
  UNIQUE KEY uniq_token (token_digest),
  KEY idx_shop_created (shop_id, created_at)
) ENGINE=InnoDB;
```

**requirements 模板**（`config/kyc_requirement_templates.yml`）：依 `subject_type` 決定該產生哪些 requirement。原型顯示的件數為：個人 6 項／獨資 6 項／有限公司 9 項／股份有限公司 11 項。

> **待定，需使用者確認**：原型只給了 5 個 requirement key（`bank_account.statement`／`identity.ubo`／`domain.ownership`／`company.registration`／`tax.invoice_permit`）與四種主體的件數（6/6/9/11），**沒有完整清單**。實作前需補齊：每種主體的完整 requirement key 清單、各自的 bucket 初值與 deadline 天數、財團法人主體的項目。33 §6 只定義了表結構，沒定義模板內容。

### 4. API 契約（Platform:: GraphQL）

| 操作名 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformKycQueue` | query | `state: [KycState!]`、`bucket: [RequirementBucket!]`、`first ≤250`、`after` | `KycSubmissionConnection{ nodes{ id, shop{id,name}, subjectType, state, submittedAt, currentDeadline, requirementSummary{ platformRequest, pastDue, currentlyDue, pendingVerification, eventuallyDue }, topRequirement{ keyName, bucket, deadline, errorCode } }, pageInfo }` | — | 全部 |
| `platformKycBoard` | query | 無 | `{ columns[ { key, label, count, cards[≤50] } ] }`——四欄看板專用，避免前端打四次 | — | 全部 |
| `platformKycSubmission` | query | `id: ID!` | `KycSubmission`（含 `requirements` 全集、`documents`、`decisionHistory`） | `NOT_FOUND` | 全部 |
| `platformKycRequestInfo` | mutation | `submissionId: ID!`、`requirements: [KycRequirementInput!]!`（`keyName`、`bucket`、`deadline`、`errorCode`、`errorReason`）、`notify: Boolean!`、`idempotencyKey: String!` | `{ submission, userErrors }` | `FORBIDDEN`／`INVALID_STATE`／`EMPTY_REQUIREMENTS`／`UNKNOWN_REQUIREMENT_KEY`／`UNKNOWN_ERROR_CODE` | owner／admin／support |
| `platformKycApprove` | mutation | `submissionId: ID!`、`note: String`、`idempotencyKey: String!` | `{ submission, shop, userErrors }` | `FORBIDDEN`／`OUTSTANDING_REQUIREMENTS`／`DOCUMENT_EXPIRING_SOON`／`INVALID_STATE` | owner／admin |
| `platformKycReject` | mutation | `submissionId: ID!`、`rejectCodes: [KycRejectCode!]!`、`disabledReason: DisabledReason!`、`note: String`、`idempotencyKey: String!` | `{ submission, shop, userErrors }` | `FORBIDDEN`／`REJECT_CODE_REQUIRED`／`INVALID_STATE` | owner／admin |
| `platformKycDocumentUpload` | mutation | `submissionId: ID!`、`kind: DocumentKind!`、`stagedUploadPath: String!`、`expiresAt: Date`、`onBehalfOfMerchant: Boolean!` | `{ document, userErrors }` | `FORBIDDEN`／`FILE_TOO_LARGE`／`UNSUPPORTED_TYPE`／`DOCUMENT_EXPIRED` | owner／admin／support |
| `platformKycDocumentVerify` | mutation | `documentId: ID!`、`verified: Boolean!`、`rejectCode: KycRejectCode` | `{ document, userErrors }` | `FORBIDDEN`／`REJECT_CODE_REQUIRED` | owner／admin／support |
| `platformKycRemediationLinkCreate` | mutation | `submissionId: ID!`、`requirementKeys: [String!]!`、`sendEmail: Boolean!` | `{ link{ id, expiresAt, maskedUrl }, userErrors }` | `FORBIDDEN`／`EMPTY_REQUIREMENTS` | owner／admin／support |
| `platformKycEscalateToTicket` | mutation | `submissionId: ID!`、`priority: TicketPriority!`、`summary: String!` | `{ ticket, userErrors }` | `FORBIDDEN` | owner／admin／support |

**KycRejectCode enum（8 值，33 §2.2）**：`SITE_INFO_INCOMPLETE`／`NO_PRIVACY_POLICY`／`SCOPE_MISMATCH`／`SITE_NOT_LIVE`／`BANK_NAME_MISMATCH`／`DOC_EXPIRED`／`DOC_UNREADABLE`／`UBO_MISSING`。

**DisabledReason enum（5 值，33 §2.3）**：`REJECTED_FRAUD`／`REJECTED_LISTED`／`REJECTED_TERMS_OF_SERVICE`／`REJECTED_INCOMPLETE_VERIFICATION`／`REJECTED_OTHER`。

**RequirementBucket enum（6 值，33 §2.3）**：`PLATFORM_REQUEST`／`PAST_DUE`／`CURRENTLY_DUE`／`PENDING_VERIFICATION`／`FUTURE`／`EVENTUALLY_DUE`。

### 5. 服務物件與背景任務

| Class | 單一責任 | 冪等策略 | 失敗與重試 | outbox |
|---|---|---|---|---|
| `Platform::Kyc::QueueQuery` | 佇列排序演算法（§6.1）的唯一實作；看板與列表共用 | 純讀 | — | 否 |
| `Platform::Kyc::RequestInfoService` | 建立/更新 requirements、轉 `info_required`、**同時套 `payin` 旗標**、通知商家 | requirement 唯一索引 `uniq_submission_active_key`；重送同一組 → no-op | 通知在 commit 後 | **是**：`kyc/info_required` |
| `Platform::Kyc::ApproveService` | 核准 → 呼叫 `TransitionService` 轉 `trial`／`active`、解 `payin` 旗標 | 已 approved → no-op | — | **是**：`kyc/approved` |
| `Platform::Kyc::RejectService` | 駁回 → 寫 `reject_codes`／`disabled_reason`、轉 `rejected`、通知 | 已 rejected → no-op | — | **是**：`kyc/rejected` |
| `Platform::Kyc::DocumentService` | 上傳（含代租戶）、驗證/退件、效期檢查（<90 天擋核准） | `checksum` 相同且同 kind → 回既有文件不重存 | 上傳失敗回 userErrors | 否 |
| `Platform::Kyc::RemediationLinkService` | 產補件連結（7 天）、寄信、撤銷 | 同一組 `requirement_keys` 24h 內重複產生 → 回既有連結（避免商家收到一堆信） | 寄信失敗記錄但連結仍有效 | 否 |
| `Platform::Kyc::OverdueSweepJob` | 每小時掃 `deadline < NOW()` 的 `currently_due` → 轉 `past_due`；**套 `payin` 旗標但不停店** | 條件式 UPDATE（`WHERE bucket='currently_due' AND deadline < NOW()`），看 affected rows | 每小時；失敗重試 | 是 |
| `Platform::Kyc::FutureRequirementsPromoteJob` | `future_requirements` 到期整批搬進 `requirements`（33 §2.3） | 條件式 UPDATE | 每日 | 是 |
| `Platform::Kyc::DraftPurgeJob` | `draft` 狀態滿 30 天未提交 → 自動清（33 §2.1） | 條件式刪除 | 每日 | 是 |

### 6. 關鍵流程與演算法

#### 6.1 佇列排序（33 §2.3 的核心）

```ruby
# app/services/platform/kyc/queue_query.rb
module Platform
  module Kyc
    # KYC 佇列排序。
    #
    # 排序規則來自 docs/design/33 §2.3：
    #   「平台資訊請求 → past_due → currently_due → future → eventually_due」
    # 照 Stripe「Actions required」的邏輯排——目的是讓已逾期的件永遠浮在最上面，
    # 而不是被新進件淹沒（DOCS kycorder）。
    #
    # 為什麼把排序權重寫在 SQL 的 CASE 而不是 Ruby：看板一次要排 1,000+ 件，
    # 在 Ruby 排就得先全撈（N+1 與記憶體都爆）。CASE + 索引 (bucket, deadline) 可走索引排序。
    class QueueQuery
      # 數字越小越優先。與 RequirementBucket enum 一一對應。
      BUCKET_PRIORITY = {
        "platform_request"     => 0,   # 平台主動要資料，最優先（我們自己欠人家的）
        "past_due"             => 1,   # 已逾期 → 會觸發停權
        "currently_due"        => 2,   # 現在就要
        "future"               => 3,   # future_requirements，有自己的 deadline
        "eventually_due"       => 4,   # 之後要
        "pending_verification" => 5,   # 已交待審——不需要商家動作，排最後
      }.freeze

      ORDER_SQL = <<~SQL.squish.freeze
        CASE kyc_requirements.bucket
          WHEN 'platform_request'     THEN 0
          WHEN 'past_due'             THEN 1
          WHEN 'currently_due'        THEN 2
          WHEN 'future'               THEN 3
          WHEN 'eventually_due'       THEN 4
          ELSE 5
        END ASC,
        kyc_requirements.deadline ASC,
        kyc_submissions.submitted_at ASC,
        kyc_submissions.id ASC
      SQL
      # 最後補 id ASC 作為 tiebreaker——同秒提交的兩件在 cursor 分頁時會跳/重複
      # （specs/11 §8 坑 6）。

      def call(states: %w[submitted info_required], first: 50, after: nil)
        ActsAsTenant.without_tenant do   # 跨租戶查詢集中在 Platform::（specs/12 §F4）
          scope = KycSubmission
                    .joins(:kyc_requirements)
                    .where(state: states)
                    .where(kyc_requirements: { satisfied_at: nil })
                    .select("kyc_submissions.*, MIN(#{bucket_priority_sql}) AS top_priority")
                    .group("kyc_submissions.id")
                    .order(Arel.sql(ORDER_SQL))
          Platform::CursorPaginator.new(scope, first: first, after: after, key: %i[id]).call
        end
      end
    end
  end
end
```

#### 6.2 逾期自動轉 past_due：停收款但不停店

```ruby
# app/jobs/platform/kyc/overdue_sweep_job.rb
# 每小時跑。
#
# 為什麼「停收款但不停店」：docs/design/33 §2.2 引店匠的關鍵洞察——
# 「補件期間收入暫停但店鋪仍可運營」。單一 boolean 凍結是錯的模型：
# 商家還在補件就把整家店關掉，他連自救的動力都沒有，而且他的顧客會炸客服。
# 正確做法是只套 payin（收款凍結）這一個旗標，前台、後台、出貨全部照常。
class Platform::Kyc::OverdueSweepJob < ApplicationJob
  queue_as :default

  def perform
    ActsAsTenant.without_tenant do
      # 條件式 UPDATE（specs/11 §3 首選，無鎖等待）。看 affected rows 決定要不要往下走。
      overdue = KycRequirement.where(bucket: "currently_due", satisfied_at: nil)
                              .where(deadline: ...Time.current)
      overdue.find_in_batches(batch_size: 200) do |batch|
        batch.group_by(&:shop_id).each { |shop_id, rows| sweep_shop(shop_id, rows) }
      end
    end
  end

  private

  def sweep_shop(shop_id, rows)
    shop = Shop.find(shop_id)
    changed = KycRequirement.where(id: rows.map(&:id), bucket: "currently_due")
                            .update_all(bucket: "past_due", updated_at: Time.current)
    return if changed.zero?   # 已被別的 worker 掃過 → 冪等

    # 套 payin 旗標（宣告式 set：把既有旗標帶上，只加 payin）。
    current = shop.shop_restrictions.active.pluck(:flag)
    Platform::Shops::RestrictionService.new(
      shop: shop, flags: (current + %w[payin]).uniq,
      reason_code: "kyc_overdue", actor: PlatformStaff.system,
      idempotency_key: "kyc_overdue:#{shop_id}:#{Date.current}", notify: :email_and_inapp
    ).call

    Platform::AuditLogger.record!(
      action: "kyc.requirements_past_due", actor: PlatformStaff.system, shop: shop,
      previous: { bucket: "currently_due", keys: rows.map(&:key_name) },
      next_state: { bucket: "past_due", keys: rows.map(&:key_name), restriction: "payin" },
      source: :automation
    )
  end
end
```

#### 6.3 核准的前置檢查（三道）

```ruby
# app/services/platform/kyc/approve_service.rb
module Platform
  module Kyc
    # KYC 核准。
    #
    # 三道前置檢查，缺一不可：
    #   ① 沒有未滿足的 currently_due / past_due / platform_request requirement
    #      （eventually_due 可以留著——它本來就是「之後要」，例如統一發票購票證是開通金流後 30 天內）
    #   ② 所有必要文件已 verified
    #   ③ 文件效期 > 90 天（DOCS kycdocs：「文件有效期須大於 90 天」）
    #      為什麼：核准後如果文件三天後就過期，等於沒審。
    class ApproveService
      DOCUMENT_MIN_VALIDITY_DAYS = 90
      BLOCKING_BUCKETS = %w[platform_request past_due currently_due].freeze

      def call
        errs = validate
        return failure(errs) if errs.any?

        result = nil
        ActiveRecord::Base.transaction do
          sub = KycSubmission.lock.find(@submission.id)
          if sub.state == "approved"     # 冪等：重放不重複轉態、不重複發事件
            result = success(sub, changed: false)
            next
          end

          previous = { state: sub.state, decision: sub.decision }
          sub.update!(state: "approved", decision: "approved",
                      decided_at: Time.current, reviewed_by: @actor.id)

          # 解除 payin 旗標（補件期間套上的）。宣告式：把 payin 從現有集合移除。
          shop = sub.shop
          remaining = shop.shop_restrictions.active.pluck(:flag) - %w[payin]
          Platform::Shops::RestrictionService.new(
            shop: shop, flags: remaining, reason_code: "kyc_approved",
            actor: @actor, idempotency_key: "#{@idempotency_key}:unrestrict"
          ).call_within_transaction!

          # 轉態：未付款 → trial（14 天）；已付款 → active。走 TransitionService 單一入口（32 §2）。
          target = shop.billing_subscription&.paid? ? "active" : "trial"
          Platform::Shops::TransitionService.new(
            shop: shop, to: target, actor: @actor, reason_code: "kyc_approved",
            idempotency_key: "#{@idempotency_key}:transition"
          ).call_within_transaction!

          Platform::AuditLogger.record!(
            action: "kyc.approved", actor: @actor, shop: shop,
            previous: previous, next_state: { state: "approved", shop_status: target },
            note: @note, target_type: "KycSubmission", target_id: sub.id
          )
          EventsOutbox.create!(shop_id: shop.id, topic: "kyc/approved",
                               payload: { submission_id: sub.id, shop_status: target })
          result = success(sub, changed: true)
        end
        Platform::Kyc::NotifyMerchantJob.perform_later(@submission.id, "approved") if result.changed?
        result
      end

      private

      def validate
        errs = []
        errs << e("FORBIDDEN", "僅 owner／admin 可核准") unless @actor.owner? || @actor.admin?
        outstanding = @submission.kyc_requirements.where(satisfied_at: nil, bucket: BLOCKING_BUCKETS)
        if outstanding.exists?
          errs << e("OUTSTANDING_REQUIREMENTS",
                    "尚有 #{outstanding.count} 項未滿足：#{outstanding.pluck(:key_name).join('、')}",
                    ["requirements"])
        end
        expiring = @submission.kyc_documents.where(state: "verified")
                              .where(expires_at: ..DOCUMENT_MIN_VALIDITY_DAYS.days.from_now)
        if expiring.exists?
          errs << e("DOCUMENT_EXPIRING_SOON",
                    "文件效期不足 #{DOCUMENT_MIN_VALIDITY_DAYS} 天：#{expiring.pluck(:kind).join('、')}",
                    ["documents"])
        end
        errs
      end
    end
  end
end
```

#### 6.4 三種補救路徑（33 §2.3「每筆都要有」）

| 路徑 | 服務 | 關鍵規則 |
|---|---|---|
| **代租戶提交** | `Platform::Kyc::DocumentService#upload(on_behalf_of_merchant: true)` | 文件 `uploaded_by = "platform_staff"`，審計 `action:"kyc.document_uploaded_on_behalf"`。**必須在商家同意下進行**——建議綁工單號（與代登入同樣的問責邏輯）。**待定，需使用者確認**：是否強制綁工單 |
| **寄補件連結** | `Platform::Kyc::RemediationLinkService#create` | token 只存 digest；**7 天有效**；連結頁只顯示該次涵蓋的 requirement，不暴露其他資料；用過即 `used_at`（可重複開啟直到過期，但每次開啟記錄）；商家在連結頁上傳的文件同樣進 `kyc_documents`（`uploaded_by = "merchant"`） |
| **升級為工單** | `Platform::Kyc::EscalateService` → 建 `tickets`（分類 `kyc_remediation`） | 工單自動帶入 submission 連結與未滿足 requirement 清單；工單關閉時回寫 submission 備註 |

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| Active Storage ＋ 私有 S3 相容 bucket | Rails 內建 | KYC 文件儲存 | 身分證/存摺封面是最高敏 PII：私有 ACL、簽名 URL TTL ≤5 分鐘、**不進 CDN**、`Cache-Control: no-store` |
| `marcel` | Rails 內建依賴 | 檔案 MIME 偵測 | **不信任前端傳的 content_type**（`specs/11 §0` 維度 1「輸入淨化」）；只允許 `image/jpeg`／`image/png`／`application/pdf` |
| `image_processing` ＋ `libvips` | ~> 1.12 | 文件縮圖（審核員預覽用） | 縮圖在私有 bucket；**不做 OCR**（會把 PII 送到第三方） |
| `clamav`（可選，掃毒） | — | 上傳檔案掃毒 | **待定，需使用者確認**：33 未要求；但接受商家上傳檔案的系統通常要掃毒，且 SOC 2 會問 |
| `holidays` gem 或自建行事曆表 | — | 5–7「工作天」SLA 計算 | **待定，需使用者確認**：台灣國定假日（含補班日）每年公告，gem 的台灣資料未必即時；建議自建 `business_calendars` 表由營運維護 |

### 8. 實作步驟（Codex 逐條做）

1. Migration：`CreateKycSubmissions`／`CreateKycRequirements`／`CreateKycDocuments`／`CreateKycRemediationLinks`（§3 DDL）。檔頭註明對應 `docs/design/33 §6`。
2. `config/kyc_reject_codes.yml`（8 條，33 §2.2）＋ `config/kyc_requirement_templates.yml`（**先建骨架，內容標 TODO 待確認**，見 §3 待定）。
3. `config/tenancy_exempt_tables.yml` 加 `kyc_submissions.idx_state_deadline`、`kyc_requirements.idx_bucket_deadline` 的索引例外與理由。
4. Model：`KycSubmission`／`KycRequirement`／`KycDocument`；`enum` 定義 state／bucket／kind；`validates` 對照 enum 白名單。
5. `Platform::Kyc::QueueQuery`（§6.1）——**先寫這支的 spec 再寫實作**，排序是本模組最容易寫錯的地方。
6. `Platform::Kyc::{RequestInfoService, ApproveService, RejectService, DocumentService, RemediationLinkService, EscalateService}`。
7. `Platform::Kyc::{OverdueSweepJob, FutureRequirementsPromoteJob, DraftPurgeJob}` ＋ `config/recurring.yml` 排程（掃描每小時、promote 與 purge 每日）。
8. GraphQL：`platformKycQueue`／`platformKycBoard`／`platformKycSubmission` ＋ 6 個 mutation（§4）。
9. Active Storage 私有 service 設定：`config/storage.yml` 加 `kyc_private`，`public: false`；`KycDocument` 用 `has_one_attached :file, service: :kyc_private`。
10. 補件連結的公開端點：`GET /kyc/remediate/:token`（**不在 Platform 域，在商家域**），驗 token digest → 顯示該批 requirement 的上傳表單；掛 rack-attack 限流。
11. 前端：`src/platform/pages/KycQueuePage.tsx` ＋ 看板元件（§11）。
12. 寫 `docs/dev/m8-platform-kyc-queue.md`。
13. 測試全綠 → PR。

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/kyc/queue_query_spec.rb` | ①**排序正確性**（33 §5-3 首要驗收）：建 6 件涵蓋六個 bucket，斷言回傳順序為 `platform_request → past_due → currently_due → future → eventually_due → pending_verification`；②同 bucket 內按 `deadline ASC`；③deadline 相同時按 `submitted_at ASC`；④`submitted_at` 也相同時按 `id ASC`（tiebreaker，防 cursor 分頁跳漏）；⑤cursor 翻頁前後不重不漏（建 120 件，翻 3 頁比對 id 集合） |
| `spec/services/platform/kyc/overdue_sweep_job_spec.rb` | ①`deadline` 昨天的 `currently_due` → 掃描後變 `past_due`；②同時套上 `payin` 旗標；③**店仍可運營**：斷言 `shop.status` 未變、`EFFECTS[status][:storefront] == 200`（33 §5-2 指定場景）；④重跑 job → 不重複套旗標、不重複寫審計（冪等）；⑤`deadline` 為 NULL 的不受影響 |
| `spec/services/platform/kyc/approve_service_spec.rb` | ①有未滿足 `currently_due` → `OUTSTANDING_REQUIREMENTS`；②只剩 `eventually_due` → 可核准；③文件效期 89 天 → `DOCUMENT_EXPIRING_SOON`；91 天 → 放行；④核准後 `payin` 旗標解除；⑤未付款 → `trial` 且 `trial_ends_at == now + 14 天`；已付款 → `active`；⑥`support` 角色 → `FORBIDDEN`；⑦重複核准 → `changed == false`，審計與 outbox 各只一列 |
| `spec/services/platform/kyc/reject_service_spec.rb` | ①未給 `rejectCodes` → `REJECT_CODE_REQUIRED`；②給不在字典內的碼 → GraphQL enum 層擋下；③駁回後 `shop.status == "rejected"` 且商家可重送（`rejected → pending_review` 合法） |
| `spec/services/platform/kyc/document_service_spec.rb` | ①content_type 由 `marcel` 實際偵測，前端謊報 `image/png` 的 `.exe` 被拒；②同 checksum 同 kind 重傳 → 回既有文件；③代租戶上傳 `uploaded_by == "platform_staff"` 且審計 action 不同；④簽名 URL TTL ≤5 分鐘且 bucket 為私有 |
| `spec/services/platform/kyc/remediation_link_service_spec.rb` | ①連結 `expires_at == created_at + 7 天`；②過期後端點回 410；③撤銷後立即失效；④24h 內同一組 keys 重複產生 → 回既有連結（不重複寄信）；⑤token 只存 digest（DB 中查不到明碼） |
| `spec/requests/kyc/remediation_endpoint_spec.rb` | ①錯 token → 404（不洩漏存在性）；②rack-attack：同 IP 20 次/分鐘後 429；③頁面只顯示該批 requirement，不含其他店資料 |
| `spec/requests/platform/graphql/kyc_permissions_spec.rb` | `support` 可 `RequestInfo`／`DocumentUpload`／`RemediationLink`／`Escalate`，但 `Approve`／`Reject` 回 `FORBIDDEN`；`read_only` 全部只能讀 |
| `spec/services/platform/kyc/concurrency_spec.rb` | 兩條 thread 同時核准同一件 → `kyc_submissions.decided_at` 只寫一次、`shop.status` 只轉一次、outbox 恰 1 列（行鎖 ＋ 狀態守衛） |
| `spec/system/platform/kyc_board_spec.rb` | 快樂路徑：看板四欄顯示 → 點逾期卡 → 進詳情 → 「寄補件連結」→ toast → 商家信箱收到（`ActionMailer::Base.deliveries`）|

### 10. 驗收清單

**對應 33 §5-3**
- [ ] requirements 五分類**排序正確**（含 `platform_request` 最優先、`pending_verification` 最後）。
- [ ] **三種補救路徑皆可用**：代租戶提交／寄補件連結（7 天）／升級為工單——每筆 requirement 都有這三個鈕。
- [ ] 駁回原因碼字典**完整 8 條**且不可自由輸入。
- [ ] 補件計時與逾期自動轉態：`currently_due` 過 deadline → `past_due` ＋ 套 `payin` ＋ **不停店**。

**其他**
- [ ] 佇列 count 與看板四欄數字、與總覽「審核佇列・逾期未補」卡片同源一致。
- [ ] 文件僅能經後台/補件連結上傳（沒有 email/chat 通道）；效期 <90 天擋核准。
- [ ] 每個決策動作（核准/駁回/要求補件）在 `platform_audit_logs` 有列且含 previous/next。
- [ ] 主體變更不可經編輯完成（需走過戶流程）——UI 上主體類型欄位為唯讀並附說明。

**七維度（`specs/11 §0`）**
- [ ] 1 安全：文件私有 bucket ＋短 TTL；MIME 實際偵測；補件連結端點限流；`support` 不可核准（伺服器端強制）。
- [ ] 2 資料完整：`uniq_submission_active_key` 唯一索引；FK 齊全；核准/駁回冪等。
- [ ] 3 併發：同時核准的併發測試通過。
- [ ] 4 效能：佇列排序走索引（`EXPLAIN` 無 filesort 於 1,000 件量級）；看板四欄一次查詢（不打四次）。
- [ ] 5 可觀測：逾期掃描 job 每次記錄處理筆數；SLA 超時件數進指標。
- [ ] 6 測試：§9 全綠。
- [ ] 7 合規：KYC 文件與 UBO 資料進 PII 清單（`specs/11 §7-1`）；駁回件的文件保留期限 **待定，需使用者確認**（33 未定義）。

### 11. 前端（React/TS）

**元件樹**

```
KycQueuePage
├─ PageHead（標題／「N 件待處理・目標 SLA 5–7 工作天」／「原因碼字典」鈕）
├─ OrderRuleNote                      [data-doc="kycorder"]  ← 固定顯示，不可摺疊
├─ KanbanBoard                        [data-doc="kycboard"]
│  └─ KanbanColumn × 4（待審／補件中／逾期未補／本週已決）
│     └─ KycCard（商店名／主體類型／時間／待審項數 or 原因碼 badge）
└─ RejectCodeDictionaryModal（8 條表格）

KycSubmissionDrawer（點卡開右側抽屜，不離開看板）
├─ SubmissionHeader（商店／主體類型／提交時間／目前 state）
├─ RequirementList                    [data-doc="kycreq"]
│  └─ RequirementRow（bucket badge／key／說明／deadline／三個補救鈕）
├─ DocumentList                       [data-doc="kycdocs"]
│  └─ DocumentRow（種類／上傳時間／狀態／預覽鈕／驗證·退件鈕）
└─ DecisionBar（要求補件／駁回／核准，各自二次確認）
```

> **為什麼用抽屜不用新頁**：審核是高重複性的批次作業，審一件回一次看板會讓人瘋掉。抽屜保留看板上下文，鍵盤 `J`／`K` 可切上下一件（**待定，需使用者確認**：是否要做鍵盤快捷）。

**狀態管理**
- `['platform','kyc','board']`（看板，`refetchInterval: 60s`——審核組多人同時作業，別人處理掉的件要消失）。
- `['platform','kyc','submission',id]`（抽屜內容，開啟才查）。
- Mutation 後 `invalidateQueries(['platform','kyc'])` ＋ `['platform','actionQueues']`（總覽佇列同步）。
- **樂觀更新**：核准/駁回後立即把卡片從當前欄移到「本週已決」，失敗則回滾並顯示錯誤 toast。理由：審核是連續操作，等 round trip 會斷節奏。

**GraphQL 呼叫**

```graphql
query PlatformKycBoard {
  platformKycBoard {
    columns {
      key label count
      cards { id shop { id name } subjectType submittedAt currentDeadline
              topRequirement { keyName bucket deadline errorCode }
              requirementSummary { pastDue currentlyDue } }
    }
  }
}

mutation PlatformKycApprove($submissionId: ID!, $note: String, $idempotencyKey: String!) {
  platformKycApprove(submissionId: $submissionId, note: $note, idempotencyKey: $idempotencyKey) {
    submission { id state decidedAt }
    shop { id status }
    userErrors { field message code }
  }
}
```

**三態**

| 狀態 | 呈現 |
|---|---|
| 載入 | 四欄各 3 張 skeleton 卡（保留欄寬） |
| 空 | 單欄空 → 欄內顯示「目前沒有件」淡字（**保留欄位**，不摺疊——欄數固定才不會讓人誤以為功能壞了）；全部四欄皆空 → 頁面級空狀態「目前沒有待審件，做得好」 |
| 錯誤 | 看板級錯誤卡＋重試；抽屜內錯誤只影響抽屜。`OUTSTANDING_REQUIREMENTS` 這類 userErrors 直接**高亮對應的 requirement 列**（`field: ["requirements"]`）而不只是彈 toast |

**響應式**

| 斷點 | 行為 |
|---|---|
| ≥1280px | 看板 4 欄（`.kanban{grid-template-columns:repeat(4,1fr)}`）；抽屜寬 480px |
| ≤1279px | 看板 2 欄（原型 CSS）；抽屜寬 440px |
| ≤1023px | 看板仍 2 欄；抽屜轉全寬 overlay |
| ≤767px | 看板**單欄**（原型 `.kanban{grid-template-columns:1fr}`）；四個欄改為橫向 tab 切換（避免無限下捲）；抽屜轉貼底 sheet（`max-height:92dvh`＋sticky 決策列） |
| ≤429px | 卡片內 meta 換行；決策列三鈕等分滿寬 |

**文案與無障礙**：bucket badge 不只用顏色——`past_due` 顯示「past_due 逾期」文字（原型 `BK` 對照表）；requirement key 用 `<code>` 呈現（工程師與審核員都要看得懂）；抽屜開啟時焦點移入、Esc 關閉、關閉後焦點回卡片。

---

## 工單（波次 W2）

> 對應原型：`#v-tickets`；`data-doc` key：`tickettable`；租戶詳情「工單」分頁的本店工單清單。
> 規格出處：`33 §1`（模組矩陣列「工單／客服」為 W2）、`33 §4`（W2 波次掛 M8）、`33 §6`（`tickets`／`ticket_messages`）、DOCS `tickettable`（SLA 數值與代登入綁定規則）、`32 §5`（權限矩陣）。

### 1. 這是什麼、給誰用、解決什麼問題

平台側的客服工單系統。**它不是要取代 Zendesk，是要讓「平台操作」與「客服對話」發生在同一個資料庫裡**——這樣才能做到 DOCS `tickettable` 那條關鍵規則：**「代登入必須綁工單編號」**。

給誰用：`support`（主要）、`admin`／`owner`（升級與覆核）、`ops`（技術類工單）。

解決三個問題：

1. **代登入無憑無據**——33 §2.9 要求代登入有事由，但「事由」如果只是一行自由文字，稽核時無法追溯。綁工單號之後，每次代登入都能回答「為了哪一件事、商家怎麼說的、後來解決了沒」。
2. **SLA 沒有錶**——P1 2h／P2 8h／P3 1 工作天（DOCS `tickettable`）；逾 SLA 的件要在總覽與工單頁都紅起來。
3. **跨模組的事沒地方收**——KYC 補件升級、違規申訴、計費爭議、前台合規巡檢不合格自動開單（DOCS `shopcompliance`：「不合格自動開工單」）、電子發票字軌告警——這些自動化產生的待辦需要一個統一的收納處。

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含具體數值） | 狀態／邊界情況 |
|---|---|---|---|
| 頁首「N open・逾 SLA M」 | 總量與逾期量 | `open` = state ∉ {resolved, closed}；逾 SLA = `sla_due_at < NOW()` 且未 resolved | 逾 SLA > 0 時數字標紅 |
| 「SLA 政策」鈕 | 展示 SLA 表 | **P1 2 小時／P2 8 小時／P3 1 工作天**（DOCS `tickettable`）。P1/P2 為**自然小時**還是**工作時間**？→ **待定，需使用者確認** | 政策 modal 唯讀 |
| 篩選 chips | 全部／逾 SLA／待我處理／等待商家 | 「待我處理」= `assignee_id = current_staff AND state = 'in_progress'`；「等待商家」= `state = 'waiting_customer'` | chips 反映在 URL searchParams |
| 搜尋 | 工單號／商店 | 白名單欄位：`number`／`shop.name`／`shop.subdomain`／`subject`（`specs/11 §1`） | 輸入 `#5102` 或 `5102` 皆可命中 |
| `tickettable` 工單表 | 欄位：工單／商店／分類／優先／狀態／SLA／負責人 | 分類（原型可見 6 類）：計費爭議／風控申訴／API 限流／出貨異常／KYC 補件／違規申訴。狀態（原型可見 4 態）：處理中／等待商家／已回覆／待審理。SLA 欄顯示「剩 Nh」或「逾 SLA Nh」（逾期紅底 badge） | 整列可點進工單詳情；逾 SLA 列的 SLA badge 為 `critical`；未指派負責人顯示 `—` |
| 工單詳情（本手冊補充，原型未畫） | 對話串＋內部備註＋動作區 | 訊息分三種可見性：`public`（商家看得到）／`internal`（僅平台）／`system`（自動事件）。動作區：指派／改優先／改狀態／關聯代登入／解決 | 內部備註底色與公開訊息**明顯區別**（誤把內部備註發給商家是這類系統最經典的事故） |
| 租戶詳情「本店工單」 | 該店 open 工單清單＋「代客建立工單」 | 只顯示該 `shop_id` 的工單 | 空 → 「目前沒有工單」 |

### 3. 資料模型

**新表（33 §6 已列 `tickets`／`ticket_messages`，本節給完整 DDL）**

```sql
CREATE TABLE tickets (
  id             BIGINT PRIMARY KEY AUTO_INCREMENT,
  number         BIGINT      NOT NULL,          -- 對外工單號，全域連號
  shop_id        BIGINT      NULL,              -- 可為 NULL＝平台內部工單（非租戶相關）
  subject        VARCHAR(200) NOT NULL,
  category       VARCHAR(32) NOT NULL,          -- billing_dispute / risk_appeal / api_rate_limit /
                                                -- fulfillment_issue / kyc_remediation / violation_appeal /
                                                -- compliance_scan / einvoice_alert / other
  priority       VARCHAR(4)  NOT NULL,          -- P1 / P2 / P3
  state          VARCHAR(20) NOT NULL,          -- new / in_progress / waiting_customer / answered /
                                                -- pending_review / resolved / closed
  source         VARCHAR(16) NOT NULL,          -- merchant / platform_staff / automation
  requester_type VARCHAR(16) NULL,              -- merchant_staff / platform_staff / system
  requester_id   BIGINT      NULL,
  assignee_id    BIGINT      NULL,              -- platform_staffs.id
  sla_due_at     DATETIME    NULL,              -- 依 priority 計算；waiting_customer 期間的處理見 §6.2
  sla_paused_at  DATETIME    NULL,
  sla_paused_ms  BIGINT      NOT NULL DEFAULT 0,-- 累計暫停毫秒數
  first_response_at DATETIME NULL,
  resolved_at    DATETIME    NULL,
  closed_at      DATETIME    NULL,
  related_type   VARCHAR(40) NULL,              -- KycSubmission / ViolationCase / Dispute / BillingInvoice
  related_id     BIGINT      NULL,
  created_at     DATETIME    NOT NULL,
  updated_at     DATETIME    NOT NULL,
  UNIQUE KEY uniq_number (number),
  KEY idx_shop_created (shop_id, created_at),           -- 本店工單（複合索引以 shop_id 開頭，鐵律 2）
  KEY idx_state_sla (state, sla_due_at),                -- 逾 SLA 掃描（平台級 → 白名單）
  KEY idx_assignee_state (assignee_id, state),
  KEY idx_related (related_type, related_id),
  CONSTRAINT fk_tickets_shop FOREIGN KEY (shop_id) REFERENCES shops(id)
) ENGINE=InnoDB;

CREATE TABLE ticket_messages (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  shop_id     BIGINT      NULL,          -- 冗餘自 tickets，讓本店查詢不必 join
  ticket_id   BIGINT      NOT NULL,
  visibility  VARCHAR(10) NOT NULL,      -- public / internal / system
  author_type VARCHAR(16) NOT NULL,      -- merchant_staff / platform_staff / system
  author_id   BIGINT      NULL,
  body        MEDIUMTEXT  NOT NULL,      -- 純文字或受限 Markdown；渲染時白名單 sanitize（specs/11 §8 坑 8）
  attachments JSON        NULL,          -- Active Storage blob keys
  created_at  DATETIME    NOT NULL,
  KEY idx_ticket_created (ticket_id, created_at),
  KEY idx_shop_created (shop_id, created_at),
  CONSTRAINT fk_ticket_messages_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id)
) ENGINE=InnoDB;
```

**既有表關聯**：`access_grants.ticket_id` → `tickets.id`（代登入綁工單，DOCS `tickettable`）。

**工單號產生**：全域連號。

> **待定，需使用者確認**：起始號。原型顯示 `#5079`–`#5102`（demo 資料）。28 §4 的訂單號慣例是「`#1001` 起連號 per shop」，工單建議也用 `#1001` 起但**全域**（不 per shop，因為平台側要唯一）。實作用 MySQL `AUTO_INCREMENT` 起始值設 1001 或獨立的 `sequences` 表（後者可避免 InnoDB 重啟後 auto_increment 回退的歷史問題；MySQL 8.0 已持久化 auto_increment，故直接用 AUTO_INCREMENT 即可）。

### 4. API 契約（Platform:: GraphQL）

| 操作名 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformTickets` | query | `query: String`、`state: [TicketState!]`、`priority: [TicketPriority!]`、`assigneeId: ID`、`overdueOnly: Boolean`、`shopId: ID`、`first ≤250`、`after` | `TicketConnection{ nodes{ id, number, shop{id,name}, subject, category, priority, state, slaDueAt, slaRemainingSeconds, overdue, assignee{id,name} }, pageInfo }` | — | 全部 |
| `platformTicket` | query | `id: ID!` | `Ticket`（含 `messages` connection、`relatedResource`、`accessGrants`） | `NOT_FOUND` | 全部（`internal` 訊息對 `read_only` **不可見**——見 §6.3） |
| `platformTicketCreate` | mutation | `shopId: ID`、`subject: String!`、`category: TicketCategory!`、`priority: TicketPriority!`、`body: String!`、`visibility: MessageVisibility!`、`relatedType`、`relatedId`、`idempotencyKey: String!` | `{ ticket, userErrors }` | `FORBIDDEN`／`SHOP_NOT_FOUND`／`BODY_REQUIRED` | owner／admin／support／ops |
| `platformTicketReply` | mutation | `ticketId: ID!`、`body: String!`、`visibility: MessageVisibility!`、`attachments: [ID!]`、`idempotencyKey: String!` | `{ ticket, message, userErrors }` | `FORBIDDEN`／`TICKET_CLOSED`／`BODY_REQUIRED` | owner／admin／support／ops |
| `platformTicketAssign` | mutation | `ticketId: ID!`、`assigneeId: ID` | `{ ticket, userErrors }` | `FORBIDDEN`／`STAFF_NOT_FOUND`／`TICKET_CLOSED` | owner／admin／support |
| `platformTicketPrioritySet` | mutation | `ticketId: ID!`、`priority: TicketPriority!`、`reason: String!` | `{ ticket, userErrors }` | `FORBIDDEN`／`REASON_REQUIRED` | owner／admin／support |
| `platformTicketStateSet` | mutation | `ticketId: ID!`、`state: TicketState!`、`note: String`、`idempotencyKey: String!` | `{ ticket, userErrors }` | `FORBIDDEN`／`INVALID_STATE_TRANSITION` | owner／admin／support／ops |
| `platformTicketResolve` | mutation | `ticketId: ID!`、`resolutionNote: String!`、`notifyMerchant: Boolean!`、`idempotencyKey: String!` | `{ ticket, userErrors }` | `FORBIDDEN`／`RESOLUTION_NOTE_REQUIRED`／`ALREADY_RESOLVED` | owner／admin／support |

**TicketPriority enum**：`P1`／`P2`／`P3`。**TicketState enum**：`NEW`／`IN_PROGRESS`／`WAITING_CUSTOMER`／`ANSWERED`／`PENDING_REVIEW`／`RESOLVED`／`CLOSED`。**MessageVisibility enum**：`PUBLIC`／`INTERNAL`／`SYSTEM`（`SYSTEM` 僅系統可寫，API 傳入即 `FORBIDDEN`）。

**商家端對應**（商家後台，非 Platform 域，走 `/admin/api/{version}/graphql.json`）：`supportTickets`／`supportTicket`／`supportTicketCreate`／`supportTicketReply`——商家只看得到 `visibility: PUBLIC` 與 `SYSTEM` 的訊息。

### 5. 服務物件與背景任務

| Class | 單一責任 | 冪等策略 | 失敗與重試 | outbox |
|---|---|---|---|---|
| `Platform::Tickets::CreateService` | 建工單、算 `sla_due_at`、指派預設負責人、發首則訊息 | `platform_idempotency_keys`；自動化來源另加「同 `related_type/related_id` 24h 內不重開」規則 | 通知在 commit 後 | **是**：`ticket/created` |
| `Platform::Tickets::ReplyService` | 發訊息、更新 `first_response_at`、狀態流轉、SLA 時鐘 | 冪等鍵；同 body ＋同 author 5 秒內視為重送 | 附件失敗不阻擋文字送出 | **是**：`ticket/replied`（僅 public） |
| `Platform::Tickets::SlaClock` | 計算 `sla_due_at`／`sla_remaining_seconds`／`overdue`，含暫停累計 | 純計算 | — | 否 |
| `Platform::Tickets::StateMachine` | 七態轉移合法性 | 目標態已達成 → no-op | — | 是 |
| `Platform::Tickets::OverdueSweepJob` | 每 5 分鐘掃逾 SLA → 告警（Slack／email）＋上總覽 | 同一工單 24h 內只告警一次（`alerted_at`） | 重試 | 是 |
| `Platform::Tickets::AutoOpenService` | 供其他模組呼叫：合規巡檢不合格、字軌低於 15%、爭議率越線、KYC 升級 → 自動開單 | **關鍵**：以 `(related_type, related_id, category)` 為冪等鍵，避免每日巡檢重複開單 | — | 是 |

### 6. 關鍵流程與演算法

#### 6.1 SLA 時鐘

```ruby
# app/services/platform/tickets/sla_clock.rb
module Platform
  module Tickets
    # SLA 時鐘。
    #
    # 目標（DOCS tickettable）：P1 2h／P2 8h／P3 1 工作天。
    #
    # 待定，需使用者確認（兩個都會影響數字，不可自行決定）：
    #   ① P1/P2 的「2 小時 / 8 小時」是自然小時（24×7）還是工作時間（例 09:00–18:00）？
    #      本實作預設「自然小時」——平台 SaaS 的 P1 通常是 24×7，但需確認營運人力。
    #   ② 「等待商家」（waiting_customer）期間 SLA 時鐘是否暫停？
    #      本實作預設「暫停」——球在商家手上時算平台逾期並不合理，這也是業界通例，
    #      但 33 號沒寫，需確認。程式已把暫停做成可關閉（PAUSE_ON_WAITING_CUSTOMER）。
    SLA_TARGETS = { "P1" => 2.hours, "P2" => 8.hours, "P3" => :one_business_day }.freeze
    PAUSE_ON_WAITING_CUSTOMER = true
    PAUSING_STATES = %w[waiting_customer].freeze

    class SlaClock
      def initialize(ticket) = @ticket = ticket

      # 建單當下計算截止時間。
      def self.due_at_for(priority, from: Time.current)
        target = SLA_TARGETS.fetch(priority)
        target == :one_business_day ? BusinessCalendar.add_business_days(from, 1) : from + target
      end

      # 有效截止時間 = 原始截止 + 累計暫停時間（含當前這段尚未結算的暫停）。
      # 為什麼存「累計暫停毫秒」而不是每次重算 sla_due_at：
      #   重算會讓歷史 due_at 被覆寫，事後無法回答「當初承諾幾點」。累計欄位是可加總、可稽核的。
      def effective_due_at
        return nil if @ticket.sla_due_at.nil?
        paused = @ticket.sla_paused_ms
        paused += ((Time.current - @ticket.sla_paused_at) * 1000).to_i if @ticket.sla_paused_at
        @ticket.sla_due_at + (paused / 1000.0).seconds
      end

      def remaining_seconds = effective_due_at.nil? ? nil : (effective_due_at - Time.current).to_i
      def overdue? = !@ticket.resolved_at && remaining_seconds.to_i.negative?

      # 狀態轉移時呼叫：進入暫停態記時點，離開暫停態結算累計。
      def on_state_change!(from:, to:)
        return unless PAUSE_ON_WAITING_CUSTOMER
        if !PAUSING_STATES.include?(from) && PAUSING_STATES.include?(to)
          @ticket.sla_paused_at = Time.current
        elsif PAUSING_STATES.include?(from) && !PAUSING_STATES.include?(to) && @ticket.sla_paused_at
          @ticket.sla_paused_ms += ((Time.current - @ticket.sla_paused_at) * 1000).to_i
          @ticket.sla_paused_at = nil
        end
      end
    end
  end
end
```

#### 6.2 自動開單的冪等（最容易出事的地方）

```ruby
# app/services/platform/tickets/auto_open_service.rb
module Platform
  module Tickets
    # 自動開單。供合規巡檢、字軌告警、爭議率監控、KYC 升級呼叫。
    #
    # 為什麼冪等是這裡最重要的事：
    #   前台合規巡檢「每日 06:00 自動掃，不合格自動開工單」（DOCS shopcompliance）。
    #   如果沒有冪等，同一家店同一個不合格項會**每天開一張單**——一個月後客服看到 30 張
    #   一模一樣的單，這個功能就廢了。
    #
    # 冪等鍵：(related_type, related_id, category) 且 state 未 resolved/closed。
    # 已有開啟中的同源工單 → 不新開，改為在既有工單追加一則 system 訊息（「今日巡檢仍不合格」）。
    class AutoOpenService
      def call(shop:, category:, priority:, subject:, body:, related_type:, related_id:)
        existing = Ticket.where(shop_id: shop&.id, category: category,
                                related_type: related_type, related_id: related_id)
                         .where.not(state: %w[resolved closed])
                         .order(:id).first
        if existing
          # 追加 system 訊息即可，並把 updated_at 推新讓它回到列表上方。
          TicketMessage.create!(ticket: existing, shop_id: shop&.id, visibility: "system",
                                author_type: "system", body: body)
          existing.touch
          return existing
        end

        Platform::Tickets::CreateService.new(
          shop: shop, subject: subject, category: category, priority: priority,
          body: body, visibility: "system", source: "automation",
          related_type: related_type, related_id: related_id,
          actor: PlatformStaff.system,
          idempotency_key: "auto_ticket:#{category}:#{related_type}:#{related_id}"
        ).call.ticket
      end
    end
  end
end
```

#### 6.3 內部備註不可外洩（本模組的第一大事故源）

```ruby
# app/graphql/types/platform/ticket_type.rb
# 三層防護，缺一不可：
#   ① GraphQL 層：messages 依角色過濾（read_only 看不到 internal——它常是外包/實習帳號）
#   ② 商家域 API：supportTicket 的 resolver 硬編碼 visibility: PUBLIC/SYSTEM，
#      不接受任何來自參數的 visibility 過濾條件
#   ③ 通知信：寄給商家的信件模板只渲染 public 訊息，且模板變數由 service 組好才傳入，
#      不把整個 ticket 物件丟進 Liquid 沙箱（specs/18 通知信 Liquid 沙箱）
field :messages, Types::Platform::TicketMessageType.connection_type, null: false
def messages
  scope = object.ticket_messages.order(:created_at)
  # read_only 角色不得閱讀內部備註。這是伺服器端強制，不是 UI 隱藏（specs/11 §0 維度 1）。
  scope = scope.where(visibility: %w[public system]) if context[:staff].read_only?
  scope
end
```

#### 6.4 代登入綁工單

```ruby
# app/services/platform/access_grants/request_service.rb（承前，補一段驗證）
# DOCS tickettable：「代登入必須綁工單編號」。
#
# 待定，需使用者確認：是否**強制**（所有代登入都必須有 ticket_id），或僅「支援類」強制。
# 本實作預設：category 屬於 merchant-facing 的請求必須綁；平台內部排查可用 reason 說明。
# 先做成 config 開關 REQUIRE_TICKET_FOR_ACCESS，預設 true。
if Platform.config.require_ticket_for_access && @ticket_id.blank?
  errs << e("TICKET_REQUIRED", "代登入必須綁工單編號", ["ticketId"])
elsif @ticket_id.present?
  ticket = Ticket.find_by(id: @ticket_id)
  errs << e("TICKET_NOT_FOUND", "工單不存在", ["ticketId"])            if ticket.nil?
  errs << e("TICKET_SHOP_MISMATCH", "工單不屬於此商店", ["ticketId"])  if ticket && ticket.shop_id != @shop.id
  errs << e("TICKET_CLOSED", "工單已結案，無法用於代登入", ["ticketId"]) if ticket&.closed_at
end
```

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本 | 用途 | 為何選它 |
|---|---|---|---|
| `commonmarker` 或 `redcarpet` | 最新穩定 | 工單訊息的受限 Markdown 渲染 | 客服要貼代碼片段與清單。**必須配 sanitize 白名單**——工單訊息是「商家輸入、平台人員瀏覽」，是 XSS 的典型路徑（`specs/11 §8` 坑 8）。**待定，需使用者確認**：是否需要富文本，純文字 + 換行也可行，能省一個依賴 |
| `rails-html-sanitizer` | Rails 內建 | 白名單 sanitize | 同上 |
| Active Storage | Rails 內建 | 工單附件 | 附件同樣走私有 bucket ＋簽名 URL |
| `sentry-ruby` | 已有 | 逾 SLA 告警的一個出口 | `specs/11 §5` |
| **不引入** Zendesk／Intercom SDK | — | — | 33 §1 把工單列為平台自建模組；外部 SaaS 無法做到「代登入綁工單」與「審計同庫」 |

### 8. 實作步驟（Codex 逐條做）

1. Migration：`CreateTickets`／`CreateTicketMessages`（§3 DDL）；`tickets.number` 用 `AUTO_INCREMENT` 起始 1001（**待定確認後執行**）。
2. `config/tenancy_exempt_tables.yml`：`tickets.shop_id` 可為 NULL（平台內部工單）→ 登記例外與理由；`tickets.idx_state_sla` 索引例外。
3. Model：`Ticket`／`TicketMessage`；`enum` 定義 category／priority／state／visibility；`Ticket#overdue?` 委派 `SlaClock`。
4. `Platform::Tickets::SlaClock`（§6.1）＋ `BusinessCalendar`（工作天計算，**待定：假日表來源**）。
5. `Platform::Tickets::{CreateService, ReplyService, StateMachine, AutoOpenService, ResolveService}`。
6. `Platform::Tickets::OverdueSweepJob` ＋ `config/recurring.yml`（每 5 分鐘）。
7. GraphQL：Platform 域 7 個操作（§4）＋商家域 4 個對應操作；`TicketType#messages` 的角色過濾（§6.3）。
8. 在 `Platform::AccessGrants::RequestService` 加入 `ticket_id` 驗證（§6.4）。
9. 讓既有自動化呼叫 `AutoOpenService`：前台合規巡檢、電子發票字軌 15% 門檻、爭議率越線、KYC 升級。
10. 前端：`src/platform/pages/TicketsPage.tsx`＋`TicketDetailPage.tsx`（§11）。
11. 寫 `docs/dev/m8-platform-tickets.md`。
12. 測試全綠 → PR。

### 9. 測試清單

| 檔案 | 案例 |
|---|---|
| `spec/services/platform/tickets/sla_clock_spec.rb` | ①P1 建單 → `sla_due_at == created_at + 2h`；P2 → +8h；P3 → 下一個工作天（跨週末驗證：週五建單 → 下週一）；②轉 `waiting_customer` 後時鐘暫停：凍結時間前進 3h，`remaining_seconds` 不變；③轉回 `in_progress` 後累計 3h 寫入 `sla_paused_ms` 且 `effective_due_at` 後延 3h；④`resolved` 後 `overdue?` 恆為 false；⑤`PAUSE_ON_WAITING_CUSTOMER = false` 時時鐘不暫停（開關有效） |
| `spec/services/platform/tickets/auto_open_service_spec.rb` | ①**冪等要害**：同一 `(related_type, related_id, category)` 連呼叫 30 次（模擬 30 天巡檢）→ `Ticket.count == 1`，`TicketMessage.count == 30`（29 則 system 追加）；②原工單 `resolved` 後再呼叫 → 開**新單**（問題復發要有新單）；③不同 `related_id` → 各自開單 |
| `spec/services/platform/tickets/reply_service_spec.rb` | ①第一則平台回覆寫入 `first_response_at`，第二則不覆寫；②`visibility: "system"` 由 API 傳入 → `FORBIDDEN`；③已 `closed` 的工單回覆 → `TICKET_CLOSED`；④相同 body 5 秒內重送 → 只建一則（防連點） |
| `spec/requests/platform/graphql/ticket_visibility_spec.rb` | ①`read_only` 角色查工單 → 回傳的 messages 不含 `internal`；②`support` 可見全部；③**商家域** `supportTicket` 查同一工單 → 只回 `public`＋`system`，即使傳入 `visibility: INTERNAL` 參數也不生效（參數不存在於 schema） |
| `spec/mailers/ticket_reply_mailer_spec.rb` | 寄給商家的通知信內容**不含**任何 internal 訊息文字（用一段哨兵字串驗證） |
| `spec/services/platform/access_grants/ticket_binding_spec.rb` | ①`require_ticket_for_access = true` 且未傳 `ticketId` → `TICKET_REQUIRED`；②工單屬於別家店 → `TICKET_SHOP_MISMATCH`；③工單已結案 → `TICKET_CLOSED`；④綁定成功後 `access_grants.ticket_id` 有值且工單詳情頁可看到該次代登入紀錄 |
| `spec/jobs/platform/tickets/overdue_sweep_job_spec.rb` | ①逾期工單觸發告警；②24h 內重跑不重複告警；③已 resolved 的逾期工單不告警 |
| `spec/requests/platform/graphql/tickets_query_spec.rb` | ①`overdueOnly: true` 的結果與頁首「逾 SLA M」數字一致；②cursor 分頁不重不漏；③搜尋 `#5102` 與 `5102` 皆命中 |
| `spec/system/platform/ticket_flow_spec.rb` | 快樂路徑：建單 → 指派 → 內部備註（商家看不到）→ 公開回覆（商家收到信）→ 等待商家（時鐘暫停）→ 商家回覆 → 解決 |

### 10. 驗收清單

- [ ] SLA：P1 2h／P2 8h／P3 1 工作天正確計算；逾期在工單頁與總覽同步標紅且數字一致。
- [ ] **代登入必須綁工單編號**（DOCS `tickettable`）——未綁時 `TICKET_REQUIRED`；工單詳情可看到關聯的代登入紀錄（誰、何時、哪些權限、做了什麼）。
- [ ] 內部備註**三層防護**皆有測試：GraphQL 角色過濾、商家域 API 硬編碼過濾、通知信不含 internal。
- [ ] 自動開單冪等：同一問題不重複開單，改為追加 system 訊息。
- [ ] 工單狀態轉移走單一入口；每次狀態/優先/指派變更落 `platform_audit_logs`。
- [ ] 租戶詳情「工單」分頁只顯示該店工單（跨租戶隔離）。

**七維度（`specs/11 §0`）**
- [ ] 1 安全：訊息 body 白名單 sanitize；附件私有 bucket；`read_only` 看不到 internal（伺服器端強制）。
- [ ] 2 資料完整：`uniq_number` 唯一索引；FK 齊全；建單與回覆冪等。
- [ ] 3 併發：兩人同時指派同一工單 → 最後寫入者勝且審計有兩列（樂觀鎖 `lock_version` 或條件式 UPDATE，`specs/11 §3`）。
- [ ] 4 效能：列表查詢走 `idx_state_sla`／`idx_assignee_state`；訊息串分頁（長工單不一次全撈）；bullet 零 N+1。
- [ ] 5 可觀測：逾 SLA 數量、首次回應中位數、各分類件數進指標 dashboard。
- [ ] 6 測試：§9 全綠。
- [ ] 7 合規：工單訊息可能含顧客 PII（商家貼訂單資訊）→ 進 PII 清單；保留期限與 purge 任務 **待定，需使用者確認**。

### 11. 前端（React/TS）

**元件樹**

```
TicketsPage
├─ PageHead（「N open・逾 SLA M」／「SLA 政策」鈕）
└─ Card
   ├─ ListBar（篩選 chips：全部／逾 SLA／待我處理／等待商家 ＋ 搜尋）
   ├─ TicketTable（TanStack Table）   [data-doc="tickettable"]
   │  └─ SlaCell（倒數／逾期 badge，每 30 秒本地重算，不重打 API）
   └─ CursorPagination

TicketDetailPage
├─ TicketHeader（#號／商店連結／分類／優先／狀態／SLA 倒數）
├─ ActionBar（指派 / 改優先 / 改狀態 / 解決）
├─ MessageThread
│  └─ MessageBubble（public 白底／internal 黃底＋鎖 icon／system 灰底細字）
├─ ReplyComposer（visibility 切換：公開回覆 ↔ 內部備註）
└─ SidePanel（關聯資源卡：KYC 件／違規案／爭議案／發票；代登入紀錄清單）
```

**狀態管理**
- `['platform','tickets',filters]`（列表，`refetchInterval: 60s`）；`['platform','ticket',id]`（詳情，`refetchInterval: 30s`——多人協作要看到同事的回覆）。
- SLA 倒數**在前端本地計算**：後端回 `slaDueAt`（絕對時間）與 `slaRemainingSeconds`，前端用 `setInterval(1000)` 遞減顯示，每 60s 才對齊一次伺服器值。理由：每秒打 API 是災難；但只信前端時鐘會因裝置時間錯亂而失準，故定期對齊。
- ReplyComposer 的 `visibility` 用 `localStorage` 記住上次選擇？**不要**——記住「內部備註」再誤發成公開是事故；**每次開啟都重設為「公開回覆」，並在切到內部備註時整個編輯區換成黃底 ＋ 顯示「僅平台人員可見」標籤**。

**GraphQL 呼叫**

```graphql
query PlatformTickets($state: [TicketState!], $overdueOnly: Boolean, $first: Int!, $after: String) {
  platformTickets(state: $state, overdueOnly: $overdueOnly, first: $first, after: $after) {
    nodes { id number subject category priority state slaDueAt slaRemainingSeconds overdue
            shop { id name } assignee { id name } }
    pageInfo { hasNextPage endCursor }
  }
}

mutation PlatformTicketReply($ticketId: ID!, $body: String!, $visibility: MessageVisibility!, $idempotencyKey: String!) {
  platformTicketReply(ticketId: $ticketId, body: $body, visibility: $visibility, idempotencyKey: $idempotencyKey) {
    message { id visibility body createdAt author { name } }
    ticket { id state slaDueAt slaRemainingSeconds }
    userErrors { field message code }
  }
}
```

**三態**

| 狀態 | 呈現 |
|---|---|
| 載入 | 列表 8 列 skeleton；詳情頭部先出（從列表 cache）＋訊息串 3 個氣泡 skeleton |
| 空 | 「目前沒有工單」；套用篩選後為空 → 「沒有符合條件的工單」＋「清除篩選」鈕 |
| 錯誤 | 列表級錯誤卡；ReplyComposer 送出失敗 → **保留輸入內容**、顯示錯誤、允許重試（冪等鍵不變，不會重複發送） |

**響應式**

| 斷點 | 行為 |
|---|---|
| ≥1280px | 詳情頁兩欄（訊息串 1fr ＋ 側欄 300px） |
| ≤1279px | 工單表橫捲；詳情仍兩欄 |
| ≤1023px | 詳情轉單欄，側欄關聯資源卡移到訊息串**上方**（先看脈絡再看對話） |
| ≤767px | 工單表轉堆疊卡片（`td::before{content:attr(data-label)}`）；篩選 chips 換行、搜尋 `flex:1 1 100%; order:9`；ReplyComposer 固定貼底（`position:sticky; bottom:0`）＋`env(safe-area-inset-bottom)` |
| ≤429px | ActionBar 摺成「⋯」下拉；優先/狀態 badge 縮為單字母＋色塊（附 `aria-label` 全稱） |

**無障礙與文案**：SLA 逾期不只用紅色——badge 文字寫「逾 SLA 1h」；倒數用 `<time>` 元素 ＋ `aria-live="off"`（每秒更新的內容不該一直朗讀）；內部備註氣泡加 `aria-label="內部備註，商家不可見"`。
