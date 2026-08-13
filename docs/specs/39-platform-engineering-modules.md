# 39 — 平台後台實作手冊 · 平台工程

> 本篇是 `docs/specs/35` 的分冊之一。涵蓋：可靠性與事故（含對外狀態頁）／發布與灰度（flag 生命週期）／環境與備份／公告與棄用／平台設定。

# 平台總控後台實作手冊 — D 段：平台工程（可靠性／發布／環境／公告／設定）

> 適用範圍：`chilllove-platform-admin.html` 的 **可靠性與事故**、**發布與灰度**、**環境與備份**、**公告與棄用通知**、**平台設定** 五區。
> 上游規格：`docs/design/33-platform-admin-benchmark.md`（以下簡稱 33）、`docs/design/32-platform-admin-spec.md`（32）、`docs/specs/11-production-baseline.md`（11）、`docs/specs/18-spec-messaging-events-webhooks.md`（18）、`docs/research/28-api-contract.md`（28）、`docs/design/23-interaction-css-spec.md`（23）、`AGENTS.md`／`CLAUDE.md` 技術鐵律。
> 本段所有表：**除明確標註「平台域表（豁免多租戶鐵律）」者外，全表帶 `shop_id` 且複合索引以 `shop_id` 開頭**；金額 integer cents；業務錯誤走 `userErrors`（HTTP 恆 200）；GID `gid://chilllove/{Type}/{id}`；跨租戶讀寫一律 `Platform::` 命名空間 ＋ 顯式 `ActsAsTenant.without_tenant`（32 §0）；**transaction 內禁外部 IO**（11 §2.2）。

---

## 可靠性與事故（波次 W3；佇列／webhook 監控為 P0）

### 1. 這是什麼、給誰用、解決什麼問題

**是什麼**：把「內部可觀測資料」與「對外承諾」接在同一條管線上的營運台。左半邊是內部視角（Solid Queue 佇列深度／p95／死信、24h webhook 投遞失敗、限流吃滿 Top、慢查詢），右半邊是對外視角（`status.chilllove.tw` 的 7 個元件狀態＋30 天歷史條、事故四階段、維護視窗）。中間夾一道**公告門檻**——內部告警不是全部都對外講。

**給誰用**：
- `ops`（SRE 線）：日常盯佇列與死信、手動重試 webhook、排維護視窗、開事故並推進階段。
- `admin`／`owner`：核准影響 Checkout 的維護視窗、發布事後檢討、決定要不要對外承認事故。
- **對外**：租戶、租戶的整合商、B2B 採購方的續約盡職調查（33 §5-11 明列「B2B 續約檢查項」）。

**解決什麼問題**：
1. **事件遺失／重放風暴**（本段第一硬要求）。維護期間如果只停 app 不停 webhook 投遞，兩件壞事必發生其一：投遞打到正在重啟的自己 → 大量 5xx → 訂閱被自動停用（18 F4：24h 持續失敗即 disable）；或維護結束後累積的 outbox 一次沖出去 → 對租戶端點形成 DDoS。所以「維護視窗」與「webhook 投遞閘門」必須是**同一個交易寫下的兩件事**，不能靠人記得去按第二顆按鈕。
2. **對外可信度**。競品掃描（33 §1）顯示對外狀態頁只有 Shopify 與 Stripe 有；華語 SaaS 全缺。這是續約談判桌上的一格。
3. **內部訊號與對外承諾的分離**。內部 5xx 0.42% 是正常波動，對外講就是製造恐慌；反過來，結帳掛了 12 分鐘卻沒對外公告，會被當成隱瞞。門檻必須是**寫死的規則**而不是當班判斷。

**不做什麼**：不做 APM／trace UI（那是 OpenTelemetry 後端的事，11 §5）；不做日誌檢索（走 Sentry／日誌串流）；本頁只做「可行動」的四張表與對外發布。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `queues`（Solid Queue 佇列表：佇列／深度／p95／死信） | 5 列，每列可點進 job 明細 | 深度＝`solid_queue_ready_executions` count；p95＝近 15 分鐘完成 job 的 `finished_at − created_at` p95；死信＝`solid_queue_failed_executions` count。**死信 > 0 即告警**（DOCS `queues`）。佇列延遲 > 60s 告警、dead set 新增告警、recurring 漏跑 heartbeat 告警（18 F5-3）。原型 5 列＝`default／webhooks／feeds（GMC/Merchant API）／einvoice／mailers` | 空態：無 job 顯示「近 15 分鐘無任務」而非 0 列。死信欄 > 0 → 該格紅字＋整卡右上出現「查看死信」。p95 無樣本時顯示 `—` 不顯示 `0s`（避免誤讀為「很快」）。**與總覽 `health` 第一格「佇列深度／死信 37 / 0」同源**（數字同源鐵律，CLAUDE.md §7） |
| `webhookfails`（Webhook 失敗 24h 清單＋「重試」鈕） | 每列＝一個 (shop, topic) 失敗聚合，附「HTTP 500 ×4・最後 12 分鐘前」 | 自動重試＝指數退避 8 次／約 4 小時（18 F4-3；28 §15 註「demo 3 次」）；24h 窗口持續失敗 → 訂閱 `disabled` ＋通知商家（18 F4-3）。**手動重試落審計**（DOCS `webhookfails`），action＝`webhook.manual_retry` | 手動重試在**投遞閘門關閉時**（維護中）→ 不直接投遞，改排入 backfill 佇列並 toast「維護視窗結束後投遞」。同一 delivery 重試需帶原 `X-CL-Webhook-Id`（28 §15 去重 header），否則租戶端去重失效。列表對租戶名稱只在**內部**顯示（狀態頁不得出現，見 §6.4） |
| `statuspage`（對外狀態頁卡：全系統 badge＋7 元件列＋30 天歷史條＋「發布更新」鈕） | 內部預覽對外看到的東西 | 元件 **5 種狀態**（33 §5-11「5 元件狀態」＝Statuspage 模型的 5 個 component status）：`operational／degraded_performance／partial_outage／major_outage／under_maintenance`。原型 7 個元件：Admin／Checkout／Storefront／API／背景任務／電子發票／金流通道。頂層 badge 由元件狀態彙總（取最嚴重者）。歷史條 30 格＝每格一天 | **元件數與事故 modal 的元件下拉不一致**（見附錄 A 衝突 C3）。歷史條在 ≤767 只顯示 15 格（`sp-bars i:nth-child(n+16){display:none}`），≤429 整條隱藏（CSS 已定義）。「發布更新」在無進行中事故時 disabled |
| `incidents`（事故清單） | 進行中＋歷史 | 四階段 `investigating → identified → monitoring → resolved`（DOCS `incidents`／33 §5-11）。**resolved 後須發布事後檢討**（DOCS `incidents`）。原型列：「2026-08-04 電子發票延遲｜identified・影響 4 元件・已發布 3 則更新」 | `resolved` 但事後檢討未發布 → 該列顯示 attention badge「待發布檢討」，並計入總覽可行動佇列。事後檢討發布期限 **待定，需使用者確認**（33 未給天數；建議 resolved 後 5 個工作日） |
| `slowqueries`（限流 Top／慢查詢） | 辨識濫用與缺索引 | 限流：cost 制 leaky bucket（28 §0.4，bucket 2,000／restore 100 points/s），統計「吃滿次數／1h」並標來源；慢查詢：**疑缺 `shop_id` 前導索引自動提示開 issue**（DOCS `slowqueries`）。MySQL `long_query_time` 依 11 §4-2 設 **100ms**，本卡只列 **>1s** 的抽樣（32 §3-4）——兩個數字是「記錄門檻」與「呈現門檻」，不是衝突 | 「開 issue」按鈕需接 GitHub API；未設定 token 時降級為「複製 issue 內容」。限流 Top 顯示租戶名稱＝內部欄位，匯出 CSV 時同樣受 PII 過濾（11 §7） |
| `ovMaint`（排維護視窗 modal） | 開始／結束時間、影響元件三選、**「維護期間暫停 webhook 投遞」預設勾選**、「提前 72 小時公告並通知訂閱者」預設勾選 | 「暫停 webhook 投遞」的說明文字已寫死在原型：「漏做會造成事件遺失或重放風暴」。72 小時提前量與原型公告列一致（`ANN` 第一列：8/18 02:00 的視窗，08-15 09:00 發送＝72h）。勾選 Checkout 時原型顯示提示「影響成交，建議避開」 | **「暫停 webhook 投遞」不得可被靜默取消**：取消勾選須跳二次確認並要求填理由（寫審計）。若 `ends_at − starts_at > ` 閾值（**待定，需使用者確認**；建議 4 小時）→ 要求 `admin+` 核准。跨日／跨時區：DB 存 UTC，UI 用台北時間（11 §8-5） |
| `ovInc`（開事故 modal） | 標題、影響等級（Minor／Major／Critical）、階段（investigating／identified／monitoring）、受影響元件、**「同步發布至對外狀態頁並通知訂閱者」預設勾選** | 影響等級三檔為原型定義。勾選「同步發布」→ 走 §6.4 Redactor 檢查後才允許送出 | 標題與更新內文送出前跑敏感字掃描；命中 → `userErrors code: CONTAINS_SENSITIVE_DATA`，紅框標出命中片段，**不自動改寫**（自動改寫會讓人以為過了） |
| 總覽 `health` 四格（佇列深度／死信、5xx 錯誤率 15 分、Webhook 失敗 24h、合成下單巡檢） | 全平台健康列 | 口徑對齊 11 §5；合成下單巡檢 **每 10 分鐘**跑一次（11 §5-4）；`/up` 為 Rails 8 內建 health endpoint（11 §5-4）。任一紅點 → 頂列橫幅（DOCS `health`） | 四格數字必須與本頁四張卡同源（同一 rollup 查詢）；驗收時逐格比對 |

---

### 3. 資料模型

> 事故／狀態頁／維護視窗是**平台域**概念（不屬於任何單一租戶），因此下列 5 張表**豁免 `shop_id` 鐵律，須在 migration 檔頭註明「平台域表，對照 32 §7 `platform_staffs` 先例」**。凡與租戶掛鉤的表（webhook 投遞、backfill）一律帶 `shop_id`。

```ruby
# db/migrate/xxxx_create_platform_status_components.rb
# 平台域表（無 shop_id）——對照 32 §7 platform_staffs 先例；元件是全平台共用概念
create_table :platform_status_components do |t|
  t.string  :key,   null: false          # admin / checkout / storefront / api / jobs / einvoice / payments
  t.string  :name,  null: false          # 對外顯示名（繁中）
  t.integer :status, null: false, default: 0  # enum: operational/degraded_performance/partial_outage/major_outage/under_maintenance（33 §5-11「5 元件狀態」）
  t.integer :position, null: false, default: 0
  t.boolean :public, null: false, default: true   # false = 只在內部監控出現，不上狀態頁
  t.timestamps
end
add_index :platform_status_components, :key, unique: true

# 每日一列，供 30 天歷史條；30 格 = 30 列（原型 .sp-bars 30 個 <i>）
create_table :platform_status_component_days do |t|
  t.references :component, null: false, foreign_key: { to_table: :platform_status_components }
  t.date    :on_date, null: false
  t.integer :worst_status, null: false, default: 0
  t.integer :downtime_seconds, null: false, default: 0
end
add_index :platform_status_component_days, %i[component_id on_date], unique: true

create_table :platform_incidents do |t|
  t.string   :title, null: false                 # 對外標題（已過 Redactor）
  t.string   :internal_title                     # 內部標題，可含租戶名／錯誤訊息，永不對外
  t.integer  :impact, null: false                # enum: minor/major/critical（原型 ovInc）
  t.integer  :stage,  null: false, default: 0    # enum: investigating/identified/monitoring/resolved（33 §5-11）
  t.boolean  :published, null: false, default: false  # 是否已上對外狀態頁
  t.json     :component_keys, null: false        # 受影響元件 key 陣列
  t.datetime :started_at, null: false
  t.datetime :detected_at
  t.datetime :resolved_at
  t.datetime :postmortem_published_at            # DOCS incidents：resolved 後須發布事後檢討
  t.text     :postmortem_body
  t.references :opened_by, null: false, foreign_key: { to_table: :platform_staffs }
  t.string   :threshold_rule_key                 # 觸發公告門檻的規則（§6.3），人工開立則為 'manual'
  t.timestamps
end
add_index :platform_incidents, %i[stage started_at]
add_index :platform_incidents, %i[published started_at]

create_table :platform_incident_updates do |t|
  t.references :incident, null: false, foreign_key: { to_table: :platform_incidents }
  t.integer  :stage, null: false
  t.text     :body, null: false                  # 對外文字
  t.boolean  :notify_subscribers, null: false, default: true
  t.references :author, null: false, foreign_key: { to_table: :platform_staffs }
  t.datetime :published_at
  t.timestamps
end
add_index :platform_incident_updates, %i[incident_id published_at]

create_table :platform_maintenance_windows do |t|
  t.string   :title, null: false
  t.datetime :starts_at, null: false             # UTC（11 §8-5）
  t.datetime :ends_at,   null: false
  t.integer  :state, null: false, default: 0     # enum: scheduled/in_progress/verifying/completed/cancelled
  t.json     :component_keys, null: false
  t.boolean  :pause_webhooks, null: false, default: true   # 硬要求 1：預設 true
  t.text     :pause_webhooks_waiver_reason       # 取消勾選必填，寫審計
  t.integer  :announce_lead_hours, null: false, default: 72 # 原型 ovMaint／ANN 第一列
  t.references :announcement, foreign_key: { to_table: :platform_announcements } # 見「公告」模組
  t.datetime :actual_started_at
  t.datetime :actual_ended_at
  t.datetime :webhooks_paused_at
  t.datetime :webhooks_resumed_at
  t.references :created_by, null: false, foreign_key: { to_table: :platform_staffs }
  t.timestamps
end
add_index :platform_maintenance_windows, %i[state starts_at]

# 投遞閘門：單列狀態機，全平台唯一真相。用表而非 Solid Cache——快取不是權威值，
# 重啟／驅逐後閘門若「預設開」就會在維護中偷偷投遞（見 §6.1「為什麼」）。
create_table :platform_delivery_gates do |t|
  t.string   :channel, null: false               # webhook / email / feed（維護視窗只動 webhook）
  t.boolean  :paused,  null: false, default: false
  t.string   :paused_by_kind                     # maintenance_window / manual / incident
  t.bigint   :paused_by_id
  t.datetime :paused_at
  t.integer  :drain_rate_per_min                 # 恢復期節流；nil = 不節流
  t.integer  :version, null: false, default: 0   # 每次變更 +1，供 app 進程輪詢（§6.1）
  t.timestamps
end
add_index :platform_delivery_gates, :channel, unique: true

# 對外訂閱者（PII：email）——列入 11 §7 PII 清單
create_table :platform_status_subscribers do |t|
  t.string   :email                              # 或 endpoint（webhook 型訂閱）
  t.string   :endpoint_url
  t.integer  :kind, null: false, default: 0      # email / webhook / rss(不落表)
  t.json     :component_keys                     # nil = 全訂閱
  t.string   :confirm_token, null: false         # double opt-in
  t.datetime :confirmed_at
  t.datetime :unsubscribed_at
  t.timestamps
end
add_index :platform_status_subscribers, :email, unique: true, where: "email IS NOT NULL"
```

**帶 `shop_id` 的表**（webhook 投遞側，複合索引一律 `shop_id` 前導）：

```ruby
# 既有（18 F4）：webhook_subscriptions(shop_id, topic, url, secret, status, failure_count)
# 既有（18 F1）：events_outbox(uuid, shop_id, topic, payload, status, attempts, locked_at)
# 本段增補：
create_table :webhook_deliveries do |t|
  t.bigint   :shop_id, null: false
  t.references :webhook_subscription, null: false
  t.string   :event_id, null: false              # = outbox uuid；對應 X-CL-Event-Id
  t.string   :webhook_id, null: false            # 對應 X-CL-Webhook-Id（28 §15 去重鍵），重試不變
  t.string   :topic, null: false
  t.integer  :state, null: false, default: 0     # pending/delivering/succeeded/failed/dead/held/expired/compacted
  t.integer  :attempts, null: false, default: 0
  t.integer  :last_status_code
  t.integer  :duration_ms
  t.text     :response_excerpt                   # 上限 64KB 截斷（18 F4-2）
  t.datetime :occurred_at, null: false           # 事件原始發生時間 → X-CL-Triggered-At
  t.datetime :next_attempt_at
  t.datetime :held_by_gate_at                    # 被閘門攔下的時刻
  t.timestamps
end
add_index :webhook_deliveries, %i[shop_id webhook_subscription_id event_id], unique: true, name: "idx_wd_dedupe"
add_index :webhook_deliveries, %i[shop_id state next_attempt_at], name: "idx_wd_dispatch"
add_index :webhook_deliveries, %i[shop_id created_at], name: "idx_wd_recent"
# 保留 7 天供除錯（18 F4-3）→ purge job
```

**enum 一覽**（GraphQL 與 DB 共用同一份，避免兩邊漂移）：
`IncidentStage{INVESTIGATING,IDENTIFIED,MONITORING,RESOLVED}`、`IncidentImpact{MINOR,MAJOR,CRITICAL}`、`ComponentStatus{OPERATIONAL,DEGRADED_PERFORMANCE,PARTIAL_OUTAGE,MAJOR_OUTAGE,UNDER_MAINTENANCE}`、`MaintenanceState{SCHEDULED,IN_PROGRESS,VERIFYING,COMPLETED,CANCELLED}`。

---

### 4. API 契約（Platform:: GraphQL）

端點 `/platform/api/{version}/graphql.json`（32 §6）；`platform_staffs` session＋CSRF，bot 走 token；cursor 分頁 ≤250；業務錯誤 `userErrors{field,message,code}` HTTP 200。

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformQueueStats(window: Duration)` | query | 預設 15m | `[QueueStat{name, depth, p95Ms, deadCount}]` | — | 全部（含 read_only） |
| `platformWebhookFailures(first, after, shopId, topic)` | query | cursor 分頁 | `WebhookFailureConnection`（聚合列＋`deliveries` 明細） | — | 全部 |
| `platformWebhookRetry(deliveryIds: [ID!]!)` | mutation | ≤250（28 §0.3 陣列上限） | `{ deliveries, queuedCount, heldCount, userErrors }` | `NOT_FOUND`／`ALREADY_SUCCEEDED`／`GATE_PAUSED`（改排 backfill，非錯誤時回 `heldCount`） | owner／admin／support／ops（原型 RM「webhook 重試／佇列」四角色） |
| `platformStatusPage` | query | — | `{ overall, components[{key,name,status,days30[]}], activeIncidents, scheduledMaintenance }` | — | 全部；**同一 resolver 亦供對外匿名頁**（同源，見 §6.3） |
| `platformIncidentCreate(input: IncidentCreateInput!)` | mutation | `{title, internalTitle, impact, stage, componentKeys, publishExternally, body}` | `{ incident, userErrors }` | `CONTAINS_SENSITIVE_DATA`（附命中片段於 `field`）／`INVALID_COMPONENT`／`FORBIDDEN` | **待定，需使用者確認**（32 §5／原型 RM 無此列）；建議 `ops+` |
| `platformIncidentUpdate(id, stage, body, notifySubscribers)` | mutation | 階段只准前進，`resolved` 為終態 | `{ incident, update, userErrors }` | `STAGE_REGRESSION`／`CONTAINS_SENSITIVE_DATA` | 同上，建議 `ops+` |
| `platformIncidentPostmortemPublish(id, body)` | mutation | 僅 `resolved` 可用 | `{ incident, userErrors }` | `NOT_RESOLVED`／`CONTAINS_SENSITIVE_DATA` | **待定**；建議 `admin+` |
| `platformMaintenanceWindowSchedule(input!)` | mutation | `{title, startsAt, endsAt, componentKeys, pauseWebhooks(預設 true), pauseWebhooksWaiverReason, announceLeadHours(預設 72), announce}` | `{ window, announcement, userErrors }` | `WAIVER_REASON_REQUIRED`（`pauseWebhooks:false` 未附理由）／`OVERLAPPING_WINDOW`／`LEAD_TIME_TOO_SHORT`／`FORBIDDEN` | **待定**；建議 `ops+`，影響 `checkout` 元件者 `admin+` |
| `platformMaintenanceWindowStart(id)` / `...Verify(id)` / `...Complete(id)` / `...Cancel(id, reason!)` | mutation | 狀態機四轉移 | `{ window, gate, userErrors }` | `INVALID_TRANSITION` | 同上 |
| `platformDeliveryGateSet(channel!, paused!, reason!)` | mutation | 手動閘門（脫離維護視窗的緊急煞車） | `{ gate, userErrors }` | `REASON_REQUIRED` | 建議 `ops+`（**待定**） |
| `platformBackfillPreview(gateChannel!)` | query | 恢復前預覽 | `{ pendingCount, compactableCount, estimatedDrainMinutes, byShop[{shopId, count}] }` | — | 同上 |
| `platformSlowQueries(first, after, minMs: 1000)` | query | 預設 1000ms（32 §3-4） | `SlowQueryConnection{ digest, p95Ms, count, suspectedMissingIndex, suggestedIssueBody }` | — | 全部 |
| `platformRateLimitTop(first, window)` | query | cost 制吃滿排行（28 §0.4） | `[{shop, hits, source}]` | — | 全部 |
| `platformStatusSubscriberCreate(email!, componentKeys)` | mutation | **對外匿名端點**，非 platform_staffs 認證 | `{ subscriber, userErrors }` | `EMAIL_INVALID`／`ALREADY_SUBSCRIBED`／`RATE_LIMITED` | 匿名（rack-attack 限流，11 §1-7） |

> **權限對映說明**：原型角色矩陣（`RM`）只有 9 列，未涵蓋事故／維護／狀態頁。上表凡標「待定」者皆需使用者確認；未確認前 Codex **以 `admin+` 實作並在 PR 假設清單註明**，避免先鬆後緊。

---

### 5. 服務物件與背景任務

| 類別 | 職責 | 觸發 |
|---|---|---|
| `Platform::Reliability::DeliveryGate` | 閘門讀寫的唯一入口；`paused?(:webhook)`、`pause!/resume!`、版本號遞增 | 同步呼叫 |
| `Platform::Reliability::GateSnapshot` | 進程級快取（每 2s 輪詢 `version`），讓熱路徑不打 DB | 進程常駐執行緒 |
| `Platform::Webhooks::OutboxDispatcher` | 從 `events_outbox` 撈 pending → 展開訂閱 → 建 `webhook_deliveries` | Solid Queue recurring，每 5s（18 F1-2） |
| `Platform::Webhooks::DeliverJob` | 單筆投遞；執行前**再驗一次閘門**；SSRF 二次解析（18 F4-1） | 由 dispatcher enqueue |
| `Platform::Webhooks::BackfillPlanner` | 恢復時的壓縮＋節流＋抖動排程（§6.2） | `MaintenanceWindow#verify!` 觸發 |
| `Platform::Webhooks::BackfillDrainJob` | 依 token bucket 每分鐘釋放 N 筆 | recurring 每 60s，閘門恢復期才活躍 |
| `Platform::StatusPage::ThresholdEvaluator` | 掃內部指標 → 產生「建議公告」候選 | recurring 每 60s |
| `Platform::StatusPage::Redactor` | 對外文字敏感資料掃描（§6.4） | 同步，publish 前 |
| `Platform::StatusPage::Renderer` | 產生對外靜態快照（HTML＋`/api/v2/status.json`＋RSS）推到獨立 CDN | 每次 publish＋每 60s 心跳 |
| `Platform::StatusPage::NotifySubscribersJob` | 分批寄送訂閱通知，批次 500／分（**待定，需使用者確認**） | publish 後 |
| `Platform::Reliability::SyntheticCheckoutJob` | 合成下單巡檢 | recurring **每 10 分鐘**（11 §5-4） |
| `Platform::Reliability::SlowQueryDigestJob` | 解析慢查詢日誌 → digest 聚合 → 判斷是否缺 `shop_id` 前導索引 | recurring 每 5 分鐘 |
| `Platform::Reliability::WebhookDeliveryPurgeJob` | 投遞紀錄保留 7 天（18 F4-3） | recurring 每日 |

**佇列歸屬**：以上 job 全部進 `low` 佇列，**唯獨 `DeliverJob` 與 `BackfillDrainJob` 進 `default`**——理由：18 F5-1 規定 `critical` 保留給金流回調與訂單成立後續，監控類 job 不得與之爭 worker。

---

### 6. 關鍵流程與演算法

#### 6.1 維護視窗 ⇄ webhook 投遞閘門（硬要求 1）

**語意定義**（三句話講完，寫進 `docs/dev/`）：
1. **暫停的是「投遞」，不是「產生」**。`events_outbox` 照常在業務 transaction 內寫入（18 F1-1／11 §8-2）——這是事件必達的唯一保證，任何「維護期間不寫 outbox」的設計都等於資料遺失。
2. **閘門要雙層檢查**：dispatcher 撈取時檢查一次（省下大量無效 job），`DeliverJob` 執行時**再檢查一次**（暫停前已 enqueue 的 job 可能晚幾秒才跑到）。只做第一層，就會有幾十筆漏網投遞打在正在重啟的服務上。
3. **恢復不是「打開開關」，是「進入排水狀態」**。恢復瞬間全量沖出＝重放風暴，所以 `MaintenanceWindow` 有 `verifying` 態：閘門開但 `drain_rate_per_min` 受限，觀察成功率達標才轉 `completed` 並解除節流。

```ruby
# app/services/platform/reliability/delivery_gate.rb
module Platform
  module Reliability
    # 投遞閘門：webhook / email / feed 三個獨立 channel 的暫停開關。
    # 為什麼用 DB 表而不用 Solid Cache 當權威值：快取可被驅逐、可在重啟後為空，
    # 而「空 = 未暫停」會讓維護期間偷偷投遞（硬要求 1 明列的事故）。
    # 快取只做「讀取加速」，且以 version 欄位做失效偵測（見 GateSnapshot）。
    class DeliveryGate
      CHANNELS = %i[webhook email feed].freeze

      class << self
        # 熱路徑：每個 DeliverJob 都會呼叫，必須 O(1) 且不打 DB。
        def paused?(channel) = GateSnapshot.current.paused?(channel)

        # 授權節流速率（筆/分）；nil 代表不節流。
        def drain_rate(channel) = GateSnapshot.current.drain_rate(channel)

        # @param by [ApplicationRecord, nil] 觸發來源（維護視窗／事故），供審計與自動恢復
        # 為什麼 version 要 +1：app 進程靠輪詢 version 決定是否重讀，
        # 這讓 kill-switch 級的變更在 ≤2 秒內全機群生效，而不用 Redis pub/sub（鐵律：不用 Redis）。
        def pause!(channel, by:, actor:, reason:)
          gate = record_for(channel)
          gate.with_lock do
            return gate if gate.paused?
            gate.update!(paused: true, paused_at: Time.current, drain_rate_per_min: nil,
                         paused_by_kind: by&.class&.name, paused_by_id: by&.id,
                         version: gate.version + 1)
          end
          Platform::Audit.record!(action: "delivery_gate.pause", target: gate,
                                  actor:, reason:, previous: { paused: false }, next: { paused: true })
          gate
        end

        # @param drain_rate_per_min [Integer, nil] verifying 階段給節流值；completed 時給 nil
        def resume!(channel, actor:, reason:, drain_rate_per_min: nil)
          gate = record_for(channel)
          gate.with_lock do
            gate.update!(paused: false, drain_rate_per_min:, version: gate.version + 1)
          end
          Platform::Audit.record!(action: "delivery_gate.resume", target: gate, actor:, reason:,
                                  previous: { paused: true }, next: { paused: false, drain_rate_per_min: })
          gate
        end

        def record_for(channel)
          raise ArgumentError, "unknown channel #{channel}" unless CHANNELS.include?(channel.to_sym)
          Platform::DeliveryGateRecord.find_or_create_by!(channel: channel.to_s)
        end
      end
    end

    # 進程常駐快照：每 2 秒讀一列（SELECT channel, paused, drain_rate_per_min, version），
    # 成本 ≈ 每進程 30 QPM，可忽略；換來 kill-switch ≤2s 生效。
    class GateSnapshot
      POLL_INTERVAL = 2.seconds
      def self.current = (@current ||= new.tap(&:start!))
      # ...（省略：Concurrent::Map + 背景 Thread；at_exit 停止）
    end
  end
end
```

```ruby
# app/services/platform/webhooks/outbox_dispatcher.rb
module Platform
  module Webhooks
    # 每 5 秒跑一次（18 §F1-2）。SKIP LOCKED 是多實例並發的唯一防重派發手段。
    class OutboxDispatcher
      BATCH = 100

      def call
        # 為什麼閘門檢查放在「撈取前」：暫停期間完全不撈，避免製造上萬筆 held delivery，
        # 恢復時的 backfill 直接以 outbox 為來源做壓縮（§6.2），比逐筆改 delivery 狀態便宜得多。
        return :gated if Reliability::DeliveryGate.paused?(:webhook)

        ActsAsTenant.without_tenant do
          EventsOutbox.pending.order(:id).limit(BATCH).lock("FOR UPDATE SKIP LOCKED").each do |event|
            fan_out(event)
          end
        end
      end

      private

      def fan_out(event)
        subs = WebhookSubscription.where(shop_id: event.shop_id, topic: event.topic, status: :active)
        # transaction 內只寫本地表；HTTP 投遞一律丟 job（11 §2-2 鐵律）
        ApplicationRecord.transaction do
          subs.each do |sub|
            d = WebhookDelivery.create_or_find_by!(
              shop_id: event.shop_id, webhook_subscription_id: sub.id, event_id: event.uuid
            ) do |row|
              row.webhook_id  = SecureRandom.uuid   # X-CL-Webhook-Id：重試時不變（28 §15 去重鍵）
              row.topic       = event.topic
              row.occurred_at = event.occurred_at
            end
            d.pending!
          end
          event.dispatched!
        end
        subs.each { |sub| DeliverJob.perform_later(event.shop_id, event.uuid, sub.id) }
      end
    end
  end
end
```

```ruby
# app/jobs/platform/webhooks/deliver_job.rb
class Platform::Webhooks::DeliverJob < ApplicationJob
  queue_as :default

  # shop_id 一律第一個參數並進場設租戶（11 §8-1）
  def perform(shop_id, event_id, subscription_id)
    ActsAsTenant.with_tenant(Shop.find(shop_id)) do
      delivery = WebhookDelivery.find_by!(shop_id:, event_id:, webhook_subscription_id: subscription_id)
      return if delivery.succeeded?

      # 第二層閘門：本 job 可能在 pause 之前就已 enqueue。
      # 不 raise、不重排 exponential backoff——直接標 held，交給 BackfillPlanner 統一排程，
      # 否則每筆各自退避會在恢復瞬間形成無序爆量（＝重放風暴）。
      if Platform::Reliability::DeliveryGate.paused?(:webhook)
        return delivery.update!(state: :held, held_by_gate_at: Time.current)
      end

      Platform::Webhooks::HttpDeliverer.new(delivery).call
    end
  end
end
```

**維護視窗狀態機與副作用**（單一入口，冪等）：

| 轉移 | 前置 | 副作用 |
|---|---|---|
| `scheduled` | 建立時 | 若 `announce`：建立公告（受眾＝全部租戶）排在 `starts_at − announce_lead_hours`（預設 72h）；建立 `platform_incidents` 的 maintenance 型記錄並上狀態頁「Scheduled Maintenance」 |
| `scheduled → in_progress` | 到 `starts_at`（recurring job）或人工提前 | `pause_webhooks` 為真 → `DeliveryGate.pause!(:webhook, by: window)`；元件狀態改 `under_maintenance`；狀態頁發布更新；`webhooks_paused_at` 記時 |
| `in_progress → verifying` | 人工按「維護完成」 | `BackfillPlanner.plan!` 產生排程；`DeliveryGate.resume!(:webhook, drain_rate_per_min: 計算值)`；元件狀態改 `operational`（或 `degraded_performance`） |
| `verifying → completed` | backlog 排空 **且** 近 N 筆投遞成功率達標（門檻**待定，需使用者確認**；建議 95%／近 200 筆） | `DeliveryGate.resume!(drain_rate_per_min: nil)` 解除節流；`webhooks_resumed_at` 記時；狀態頁發「維護完成」 |
| `any → cancelled` | 需 `reason` | 若已 pause → 立即 resume（走 verifying 同樣的排水邏輯，因為 backlog 已經存在） |

> **冪等**：四個轉移都用 `with_lock` ＋ 狀態前置判斷；重複呼叫回同一結果、不重複發公告（對照 32 §2「凍結/解凍必須冪等」的同一原則）。

#### 6.2 恢復後的補投與去重（硬要求 1 下半）

三個規則，缺一不可：

**(a) 壓縮（compaction）——只對「狀態快照型」topic**
18 F1-4 規定 payload「只帶 ID 與必要摘要，消費時再查現值」。這條讓壓縮成為安全操作：同一 `(shop_id, topic, resource_id)` 的 5 筆 `products/update` 壓成最後 1 筆，消費者查到的現值完全一樣。
- **可壓縮**（snapshot 語意）：`products/update`、`collections/update`、`inventory_levels/update`、`customers/update`、`shop/update`、`themes/publish`。
- **禁止壓縮**（事實語意，每一筆都是獨立事實）：`orders/create|paid|cancelled|fulfilled|edited`、`refunds/create`、`fulfillments/create|update`、`draft_orders/*`、`app/uninstalled`、`checkouts/create|update`。
- 壓掉的列標 `state: :compacted` 並保留（審計可查「這筆為什麼沒投」），不刪除。

**(b) 節流排水（token bucket）＋(c) 抖動（jitter）**

```ruby
# app/services/platform/webhooks/backfill_planner.rb
module Platform
  module Webhooks
    # 維護結束後的補投規劃器。
    # 為什麼要規劃而不是直接放行：暫停 2 小時的平台可能累積 10 萬筆事件，
    # 一次沖出去對租戶端點就是 DDoS，且會踩到 18 §F4-3「24h 持續失敗即停用訂閱」，
    # 等於我們自己把租戶的訂閱關掉——這正是硬要求 1 說的「重放風暴」。
    class BackfillPlanner
      COMPACTABLE_TOPICS = %w[
        products/update collections/update inventory_levels/update
        customers/update shop/update themes/publish
      ].freeze

      # 最大陳舊度：超過此值的可壓縮事件直接標 expired 不投。
      # 待定，需使用者確認（33 未定義；建議 24 小時，且不得超過 outbox 30 天保留期 18 §F1-5）
      MAX_STALENESS = 24.hours

      def initialize(window:) = @window = window

      def plan!
        backlog = collect_backlog
        compacted = compact(backlog)
        rate = drain_rate_for(compacted.size)
        schedule(compacted, rate)
        @window.update!(backfill_planned_count: compacted.size, backfill_rate_per_min: rate)
        Platform::Reliability::DeliveryGate.resume!(
          :webhook, actor: @window.created_by, reason: "maintenance #{@window.id} verifying",
          drain_rate_per_min: rate
        )
      end

      private

      def collect_backlog
        ActsAsTenant.without_tenant do
          EventsOutbox.pending.where(occurred_at: @window.webhooks_paused_at..).order(:id).to_a +
            WebhookDelivery.where(state: :held).order(:id).to_a
        end
      end

      # 壓縮：可壓縮 topic 只留每組最後一筆；事實型 topic 全留。
      def compact(rows)
        keep, seen = [], {}
        rows.reverse_each do |row|                        # 由新到舊掃，先看到的就是最後一筆
          if COMPACTABLE_TOPICS.include?(row.topic)
            key = [row.shop_id, row.topic, row.resource_id]
            if seen[key]
              mark_compacted!(row); next
            end
            if row.occurred_at < MAX_STALENESS.ago
              mark_expired!(row); next                    # 過期的快照型事件投了也無意義
            end
            seen[key] = true
          end
          keep << row
        end
        keep.reverse                                       # 還原時間順序（at-least-once 不保證順序，但盡量近似）
      end

      # 排水速率：不得超過「維護前的常態吞吐」，否則就是拿補投打租戶。
      # 常態吞吐取暫停前 7 天同時段 p50（避免用尖峰值高估）。倍率 1.5 為 待定，需使用者確認。
      def drain_rate_for(_count)
        baseline = Platform::Metrics.webhook_throughput_p50_per_min(lookback: 7.days)
        [(baseline * 1.5).ceil, 60].max
      end

      # 抖動：同一分鐘內的釋放時間打散到 [0,60) 秒，且同一 host 的投遞再散開，
      # 否則 1,000 家租戶共用同一個 SaaS 端點（例如同一家 ERP）時仍會瞬間打爆對方。
      def schedule(rows, rate)
        rows.each_slice(rate).with_index do |slice, minute|
          slice.each do |row|
            at = Time.current + minute.minutes + rand(0...60).seconds
            row.update!(state: :pending, next_attempt_at: at)
          end
        end
      end
    end
  end
end
```

**去重契約（對租戶側的承諾，寫進消費端指南 18 F4-4）**：
- 每筆投遞帶 `X-CL-Webhook-Id`（去重鍵，**重試與補投都不變**）與 `X-CL-Event-Id`（outbox uuid）。
- 補投額外帶 **`X-CL-Delayed-Delivery: true`** 與原始 `X-CL-Triggered-At`，讓消費者能區分「即時事件」與「維護後補投」（例如補投時不再重寄顧客信）。此 header 為 28 §15 既有 header 集的擴充，**待定，需使用者確認**。
- 我方側去重靠 `idx_wd_dedupe`（`shop_id, webhook_subscription_id, event_id` 唯一索引）——即使 planner 有 bug 重複排程，DB 也擋住第二筆（11 §3 三板斧之「唯一索引最後防線」）。

**與租戶凍結的關係（重要邊界）**：32 §2 規定 `frozen` 時「webhook 停發」，解凍時「全部恢復」。本段定義：租戶級停發把事件標 **`suppressed`（非 `held`）**，且 **解凍時不做 backfill**，只恢復向前投遞——因為一家店凍結 28 天（33 §2.4 dunning 線）後補投 28 天的事件毫無意義且必然打爆對方。**「解凍是否補投」33 與 32 皆未明文，待定，需使用者確認**（建議：不補投，並在解凍通知信告知「維護／凍結期間事件請以 API 重新拉取」）。

#### 6.3 公告門檻：內部訊號 → 對外事故（硬要求 2 上半）

**同源**：對外狀態頁與內部監控讀同一組 rollup（`platform_status_components.status` 由 `ThresholdEvaluator` 寫入）。**分離**在於：內部訊號跨過「告警門檻」只 page 值班；跨過「**公告門檻**」才產生「建議對外公告」候選，且**永遠需要人按下 publish**（唯一例外：預先排定的維護視窗，已在 72 小時前公告過，到點自動上「Under Maintenance」）。

| 規則 key | 訊號（來源） | 內部告警門檻 | 對外公告門檻 | 對應元件 |
|---|---|---|---|---|
| `synthetic_checkout_fail` | 合成下單巡檢（11 §5-4，每 10 分鐘） | 1 次失敗 | **連續 2 次失敗**（＝20 分鐘無法完成下單） | Checkout → `major_outage` |
| `queue_latency` | 佇列延遲（18 F5-3） | > 60s | 延遲 > 60s **持續 15 分鐘**（倍率／持續時間 **待定，需使用者確認**） | 背景任務 → `degraded_performance` |
| `dead_letter` | 死信新增（DOCS `queues`：死信 > 0 告警） | > 0 | 死信 > 0 **且** 影響 topic 屬訂單／金流線（範圍判定 **待定**） | 背景任務 |
| `admin_p95` | 後台 p95（11 §4 預算 <300ms） | 超預算 | 超預算 **2 倍持續 10 分鐘**（倍率與時間 **待定，需使用者確認**） | Admin → `degraded_performance` |
| `storefront_p95` | 前台快取命中 p95（11 §4 預算 <200ms） | 超預算 | 同上 | Storefront |
| `http_5xx` | 5xx 率（原型 health「5xx 錯誤率（15 分）」） | **待定**（33／11 未給數值） | **待定，需使用者確認** | 依受影響路由對映元件 |
| `einvoice_track` | 字軌餘量（33 §2.14／DOCS `einvoice`：15% 門檻） | 餘量 < 15% | **不對外**（單店議題，走公告與工單，不是平台事故） | — |
| `mail_auth_fail` | SPF／DKIM／DMARC 任一失效（DOCS `mailsender`） | 立即 | **對外**（通知信全停＝租戶會發現顧客收不到信） | Admin／背景任務（**待定**：對映哪個元件） |
| `maintenance` | 維護視窗到點 | — | 自動（已預告） | 視窗指定元件 → `under_maintenance` |

```ruby
# app/services/platform/status_page/threshold_evaluator.rb
module Platform
  module StatusPage
    # 每 60 秒跑一次。產生「建議公告」而非直接公告——
    # 為什麼不自動公告：狀態頁是對外承諾，誤報一次的信任成本高於晚 3 分鐘公告。
    # 唯一自動化的是預先排定的維護視窗（72 小時前已公告過，見 §6.1）。
    class ThresholdEvaluator
      def call
        RULES.each do |rule|
          signal = rule.measure                                    # 讀 rollup，不重算
          next unless rule.crosses_publication_threshold?(signal)
          next if Platform::Incident.open.exists?(threshold_rule_key: rule.key)  # 同規則不重複建候選

          Platform::IncidentCandidate.create!(
            rule_key: rule.key, component_keys: rule.component_keys,
            suggested_impact: rule.impact, evidence: signal.to_h   # evidence 只在內部顯示
          )
          Platform::Notifier.page_oncall!(rule)                    # 值班先收到，人再決定 publish
        end
      end
    end
  end
end
```

#### 6.4 對外可揭露／絕不可揭露（硬要求 2 下半）

| 分類 | 可對外 | 絕不可對外 | 強制手段 |
|---|---|---|---|
| 身分 | 元件名稱（Admin／Checkout／…） | **租戶名稱、子網域、自訂網域、統一編號、擁有者 email**、租戶 GID | Redactor 比對 `shops.name / subdomain / custom_domains` 全表 |
| 技術 | 「部分請求逾時」「背景任務延遲」等**行為描述** | 具體錯誤訊息、stack trace、SQL、exception class、`request_id`、`shop_id`、內部主機名／IP／queue 名／DB 名 | Redactor 正則：`/\.rb:\d+/`、`/[A-Z]\w+::[A-Z]\w+Error/`、`/\b\d{1,3}(\.\d{1,3}){3}\b/`、`/gid:\/\/chilllove\//`、UUID、`/SELECT |UPDATE |FROM /i` |
| 量級 | **質性描述**：「部分商店」「多數商店」「全部商店」 | **精確受影響租戶數／平台商店總數／GMV**（洩漏商業規模） | 白名單：對外欄位只准 `impact_scope enum{some, many, all}`；`affected_shop_count` 標 `internal_only` 不進對外 schema |
| 指標 | 元件 5 狀態、30 天歷史條、事故起訖時間 | 原始 5xx 率、p95 毫秒數、佇列深度 | 對外 resolver 不 expose 這些欄位（型別層阻擋，而非靠人記得） |
| 供應商 | 若上游供應商已自行公告 → 可提「上游服務商」 | 未公告時指名供應商（綠界／藍新／Stripe）＝把責任外推且可能違反合約 | 人工複核清單，Critical 事故需第二人核准（四眼，對照 32 §5 金流變更慣例） |
| 事後檢討 | 時間線、根因的**架構層描述**、改善項與期限 | 內部人名、工單號、程式碼片段、租戶個案 | 同一 Redactor＋`admin+` 發布權限 |

```ruby
# app/services/platform/status_page/redactor.rb
module Platform
  module StatusPage
    # 對外文字守門員。命中即擋下並回 userErrors，不做自動改寫——
    # 自動改寫會讓發布者以為「系統幫我處理好了」，下次就更不小心。
    class Redactor
      PATTERNS = {
        ip:          /\b\d{1,3}(?:\.\d{1,3}){3}\b/,
        email:       /\b[\w.+-]+@[\w-]+\.[\w.-]+\b/,
        gid:         %r{gid://chilllove/}i,
        uuid:        /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
        ruby_error:  /\b[A-Z]\w*(?:::[A-Z]\w*)*Error\b|\.rb:\d+/,
        sql:         /\b(SELECT|INSERT INTO|UPDATE|DELETE FROM)\b/i,
        tax_id:      /\b\d{8}\b/                       # 台灣統編 8 碼
      }.freeze

      Finding = Struct.new(:kind, :snippet, keyword_init: true)

      def initialize(text) = @text = text.to_s

      # @return [Array<Finding>] 空陣列代表可發布
      def findings
        f = PATTERNS.filter_map { |kind, re| (m = @text[re]) && Finding.new(kind:, snippet: m) }
        f + tenant_identifier_findings
      end

      private

      # 租戶識別字比對：把文字切詞後一次查 DB（不逐一 LIKE，避免 N 次全表掃）。
      # 為什麼要查 DB 而不是靜態黑名單：租戶名每天在變，黑名單必然過期。
      def tenant_identifier_findings
        tokens = @text.scan(/[\p{Han}\p{Alnum}][\p{Han}\p{Alnum}_.-]{1,63}/).uniq.first(200)
        return [] if tokens.empty?
        hits = ActsAsTenant.without_tenant do
          Shop.where(name: tokens).or(Shop.where(subdomain: tokens)).pluck(:name, :subdomain) +
            ShopDomain.where(host: tokens).pluck(:host)
        end
        hits.flatten.compact.uniq.map { |h| Finding.new(kind: :tenant_identifier, snippet: h) }
      end
    end
  end
end
```

**狀態頁的失效域隔離（必寫進實作步驟）**：狀態頁若與主平台同機群，主平台掛掉時狀態頁也掛掉＝零價值。因此 `Renderer` 每次 publish（與每 60 秒心跳）產出**靜態產物**（`index.html` ＋ `/api/v2/status.json` ＋ `/history.rss`）推到**與主應用不同的託管與 DNS 區**。具體供應商選擇見 §7。

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本／用途 | 為何選它 |
|---|---|---|
| `solid_queue` | Rails 8.1 內建（DB-backed） | 鐵律：不用 Redis。佇列狀態就在 MySQL，監控頁直接查表即可，不需要額外的 metrics exporter |
| `mission_control-jobs` | 掛 `/platform/jobs`，`owner` only（18 F5-3） | Solid Queue 官方運維 UI；我們自建的 `queues` 卡只做聚合與告警，明細直接跳 Mission Control，不重造輪子 |
| `lograge` ＋ `filter_parameters` | 結構化 JSON 單行日誌，全域 tag `request_id`／`shop_id`／`staff_id`（11 §5-1） | 慢查詢與限流卡的資料來源；tag 讓「哪個租戶把限流吃滿」一查就到 |
| `sentry-ruby` / `sentry-rails` | 錯誤上報；job 失敗與 webhook 解析失敗設專屬告警（11 §5-2） | 已在 11 定案，不另選 |
| `opentelemetry-rails`（＋`mysql2`、`net-http` instrumentation） | traces；指標最低集：checkout 開始/成功、job 佇列深度與延遲、5xx 率、DB 連線池（11 §5-3） | 公告門檻的訊號源必須與 11 §5 同一組，否則對外承諾與內部指標會漂移 |
| `rack-attack` | 對外狀態頁訂閱端點限流（11 §1-7） | 訂閱表單是匿名端點，不限流就是垃圾註冊入口 |
| Uptime 監控（Uptime Kuma／Betterstack） | 打 `/up`（11 §5-4） | **必須跑在平台之外**，否則平台掛了監控也掛了 |
| HTTP client（`faraday` ＋ `faraday-retry`，或 `net-http` 直用） | webhook 投遞：timeout 5s、**禁 redirect**、response 讀取上限 64KB、SSRF 二次解析（18 F4-1/2） | 18 已定規則；重點是「禁 redirect」與「投遞時再解析 DNS」兩項要在 client 層強制，不能靠呼叫端記得 |
| **狀態頁：自建 vs Atlassian Statuspage** | 見下方決策 | — |

**狀態頁自建 vs 買 Statuspage（33 §10 列了 Statuspage 為調研對象，但未指定採用）**：

| 面向 | 自建（本手冊設計） | Atlassian Statuspage |
|---|---|---|
| 失效域 | 需自行推靜態產物到獨立託管才隔離 | 天生隔離（別人的機房） |
| 訂閱通知 | 要自己做 double opt-in／退訂／分元件訂閱（工作量約 3–5 人日） | 內建 email／SMS／Slack／webhook |
| 資料主權與 Redactor | **可在 publish 前強制跑 Redactor**（§6.4）——這是我們的硬要求，SaaS 做不到 | 只能靠人守紀律 |
| 平台治理 API | 與 `Platform::` GraphQL 同源，對應 33 §7-1 差異化「day 1 就給 Platform:: 全量操作」 | 需另接他們的 API |
| 成本 | 人力成本 | 訂閱費（依方案） |

**建議**：**自建資料模型與 Redactor（不可外包，硬要求 2 綁死），對外渲染產物推到獨立靜態託管**（Cloudflare Pages／S3+CloudFront 之類），DNS 用與主站不同的 zone。**具體託管商與 DNS 供應商 待定，需使用者確認**（33 未指定；11 §1 只說 Kamal 自帶 Let's Encrypt）。

---

### 8. 實作步驟（順序化 todo）

1. **M0 埋表**：`platform_delivery_gates`（先建，其他模組會依賴）、`webhook_deliveries`（含三個索引）。`events_outbox` 補 `occurred_at`、`resource_id`、`dispatched_at` 欄位（壓縮演算法需要 `resource_id`）。`strong_migrations` 檢查通過（11 §2-5）。
2. `Platform::Reliability::DeliveryGate` ＋ `GateSnapshot`（含 2s 輪詢執行緒、`at_exit` 停止）。單元測試先行：pause/resume 冪等、version 遞增、快照 ≤2s 生效。
3. 改造 `Platform::Webhooks::OutboxDispatcher`：加入撈取前閘門檢查（第一層）。
4. 改造 `DeliverJob`：加入執行前閘門檢查（第二層）→ 標 `held`。
5. `platform_maintenance_windows` 表 ＋ 狀態機（四轉移，`with_lock` 冪等）＋ 審計串接。
6. `BackfillPlanner`（壓縮 → 節流 → 抖動）＋ `BackfillDrainJob`。**這一步的測試最重要**（§9）。
7. `platform_status_components` ／ `_days` ／ `platform_incidents` ／ `_updates` 表 ＋ seeds（7 個元件，對照原型 `SP`）。
8. `Redactor`（先寫測試集：把 §6.4 每一列都寫成一條 spec）。
9. `IncidentCreate/Update/PostmortemPublish` mutations，publish 路徑強制過 Redactor。
10. `ThresholdEvaluator` ＋ `IncidentCandidate`（先做 `synthetic_checkout_fail` 與 `maintenance` 兩條，其餘待門檻確認）。
11. `Renderer`：靜態產物 ＋ 推送到獨立託管；`status.chilllove.tw` DNS 與憑證（依賴「平台設定」模組）。
12. `platform_status_subscribers` ＋ double opt-in ＋ 退訂 ＋ `NotifySubscribersJob`（分批）。
13. `SlowQueryDigestJob`（缺 `shop_id` 前導索引偵測：解析 `EXPLAIN` 的 `key` 欄與 `WHERE` 是否含 `shop_id`）。
14. 前端頁面（§11）。
15. 全鏈路演練：排一個 5 分鐘維護視窗 → 觀察閘門 → 灌 500 筆事件 → 恢復 → 驗證壓縮率與排水速率 → 驗證租戶端收到的 `X-CL-Webhook-Id` 未變。

---

### 9. 測試清單

```
spec/services/platform/reliability/delivery_gate_spec.rb
  - pause! 冪等：連續呼叫兩次只寫一筆審計、version 只 +1
  - resume! 後 GateSnapshot 在 2 秒內回報 paused? == false
  - 快取被清空／進程重啟後，paused? 仍為 true（權威值在 DB，不是快取）  ← 硬要求 1

spec/services/platform/webhooks/outbox_dispatcher_spec.rb
  - 閘門關閉時不撈取任何 outbox 列（回 :gated），outbox 列維持 pending
  - SKIP LOCKED：兩個 dispatcher 並發不重複派發（threads + 真 DB）

spec/jobs/platform/webhooks/deliver_job_spec.rb
  - 已 enqueue 但閘門在執行前關閉 → 標 held，未發出任何 HTTP（WebMock 斷言 0 次）  ← 硬要求 1
  - held 的 delivery 不消耗 attempts、不觸發指數退避

spec/services/platform/webhooks/backfill_planner_spec.rb
  - 壓縮：同 (shop, products/update, resource) 5 筆 → 1 筆 pending + 4 筆 compacted
  - 不壓縮：orders/create 5 筆 → 5 筆全留            ← 事實型事件不得遺失
  - 過期：可壓縮且 occurred_at 超過 MAX_STALENESS → expired，不投遞
  - 節流：backlog 1,000 筆 / rate 100 → 排程跨 10 分鐘，任一分鐘不超過 100
  - 抖動：同一分鐘的 next_attempt_at 秒數分佈不集中（同秒 ≤ 上限）
  - 補投的 X-CL-Webhook-Id 與暫停前產生的值相同（去重契約）  ← 硬要求 1
  - 唯一索引兜底：planner 重複執行不產生第二筆 delivery（ActiveRecord::RecordNotUnique 被吞）

spec/models/platform/maintenance_window_spec.rb
  - scheduled→in_progress 自動 pause 閘門；狀態機四轉移冪等
  - pause_webhooks:false 未附 waiver_reason → 驗證失敗
  - in_progress→verifying 觸發 BackfillPlanner 且閘門帶 drain_rate
  - cancelled（已 pause 過）仍走排水路徑，不直接全開

spec/services/platform/status_page/redactor_spec.rb
  - §6.4 每一列各一條：租戶名／子網域／自訂網域／email／統編／IP／GID／UUID／stack trace／SQL
  - 中文租戶名（「北緯 25 選品」）能被切詞命中
  - 乾淨文字回空陣列

spec/requests/platform/graphql/incidents_spec.rb
  - publishExternally + 含租戶名 → userErrors code CONTAINS_SENSITIVE_DATA，HTTP 200（鐵律）
  - stage 倒退 → STAGE_REGRESSION
  - 未 resolved 就發布事後檢討 → NOT_RESOLVED
  - 對外 status query 的回傳型別不含 affected_shop_count / p95 / 5xx（schema 層斷言）

spec/requests/platform/graphql/maintenance_windows_spec.rb
  - 排定 → 產生 announcement，schedule_at == starts_at - 72h
  - 權限：read_only 呼叫 → FORBIDDEN

spec/system/platform/reliability_spec.rb
  - 快樂路徑：排維護 → 開始 → webhook 卡出現「投遞已暫停」橫幅 → 完成 → 排水進度條
  - 三態：載入 skeleton／空佇列／查詢失敗紅 banner 附重試（23 §4-7）

spec/jobs/platform/reliability/synthetic_checkout_job_spec.rb
  - 連續 2 次失敗 → 建立 IncidentCandidate（公告門檻），1 次失敗不建立
```

---

### 10. 驗收清單（對得上 specs/11 §5 與 §9）

- [ ] **11 §5-1**：本頁所有查詢的日誌帶 `request_id`＋`shop_id`（跨租戶查詢帶 `staff_id`），`filter_parameters` 過濾 token。
- [ ] **11 §5-2**：Sentry 收得到本頁觸發的測試錯誤；job 失敗與 webhook 投遞失敗有專屬告警規則。
- [ ] **11 §5-3**：佇列深度與延遲、5xx 率兩項指標在 OTel 後端有 dashboard，且與本頁 `queues`／`health` **數值一致**（同源驗收）。
- [ ] **11 §5-4**：`/up` 綠；合成下單巡檢 10 分鐘一次且失敗會出現在總覽 `health` 第四格。
- [ ] **11 §9**：`brakeman` 0 高危（Redactor 的正則與 DB 查詢無注入）；`bullet` 0 報警（webhook 失敗聚合列不得 N+1）；`rspec` 全綠；`EXPLAIN` 抽查 `idx_wd_dispatch`／`idx_wd_recent` 有被使用。
- [ ] **硬要求 1**：維護視窗開始後 60 秒內，實際 HTTP 投遞數為 0（以 WebMock／真實測試端點量測）；恢復後每分鐘投遞數不超過規劃速率；補投的 `X-CL-Webhook-Id` 與原值相同。
- [ ] **硬要求 2**：對外 GraphQL schema 不含任何內部欄位（schema diff 測試）；Redactor 測試集 100% 通過；狀態頁靜態產物可在主應用完全停機時仍可存取（演練驗證）。
- [ ] 33 §5-11 逐條：5 元件狀態齊備、事故四階段、維護視窗預告同時暫停 webhook、訂閱分發可用。
- [ ] 死信 > 0 時總覽出現紅點與頂列橫幅。
- [ ] 每個平台寫入動作（重試、排維護、開事故、發布、閘門變更）在 `platform_audit_logs` 有 `previous`/`next` JSON（33 §2.8）。

---

### 11. 前端（React/TS）

**元件樹**
```
<ReliabilityPage>
  ├ <PageHead title="可靠性與事故" sub="口徑對齊 docs/specs/11 §5">
  │   └ actions: <Button sec onClick=openMaintenance>排維護視窗</Button>
  │              <Button crit onClick=openIncident>開事故</Button>
  ├ <GateBanner/>                      // 閘門暫停中才出現（critical banner，含剩餘時間與排水進度）
  ├ <TwoCol>
  │   ├ <QueueStatsCard/>              // data-doc="queues"；IndexTable，死信欄 > 0 紅字
  │   └ <WebhookFailuresCard/>         // data-doc="webhookfails"；MiniList + RetryButton
  ├ <StatusPageCard/>                  // data-doc="statuspage"；<ComponentRow>×7 + <History30/>
  ├ <TwoCol>
  │   ├ <IncidentsCard/>               // data-doc="incidents"
  │   └ <PerfCard/>                    // data-doc="slowqueries"
  ├ <MaintenanceModal/>  <IncidentModal/>  <PublishUpdateModal/>
```

**狀態管理**：Apollo（或 urql）＋ 三個 query。`platformQueueStats` 與 `platformWebhookFailures` 用 `pollInterval: 15000`；`platformStatusPage` 用 `pollInterval: 60000`。**閘門狀態（`GateBanner`）走 `pollInterval: 5000`**——因為它決定「重試鈕會不會真的投遞」，UI 不能落後太多。所有 mutation 用 `optimisticResponse: undefined`（23 §4-5：金流／庫存／訂單一律等伺服器回應；webhook 投遞同級，不做樂觀更新）。

**GraphQL 片段**
```graphql
fragment QueueStatFields on QueueStat { name depth p95Ms deadCount }
fragment ComponentFields on StatusComponent { key name status days30 { onDate worstStatus } }

query ReliabilityDashboard {
  platformQueueStats(window: "PT15M") { ...QueueStatFields }
  platformDeliveryGate(channel: WEBHOOK) { paused pausedAt drainRatePerMin backlogCount }
  platformWebhookFailures(first: 50) {
    nodes { shop { id name } topic failureCount lastFailedAt sampleStatus deliveryIds }
    pageInfo { hasNextPage endCursor }
  }
  platformStatusPage { overall components { ...ComponentFields } activeIncidents { id title stage impact } }
}

mutation RetryWebhooks($ids: [ID!]!) {
  platformWebhookRetry(deliveryIds: $ids) {
    queuedCount heldCount
    userErrors { field message code }   # code 為 typed enum（28 §0.3）
  }
}
```

**三態**（23 §4-7，每張卡各自獨立，不做整頁 spinner）
- **載入**：`<Skeleton rows={5}/>`，shimmer 1.2s linear（23 §5）；首載 350ms 後才換真列。
- **空**：`queues` → 「近 15 分鐘無任務」；`webhookfails` → 「24 小時內無失敗」＋綠 pip；`incidents` → 「目前無進行中事故」＋連結到歷史。
- **錯**：紅 banner「無法載入佇列狀態」＋「重試」按鈕（23 §4-1 回饋三件套）。**特別規則**：`platformStatusPage` 查詢失敗時，卡片顯示「內部監控暫時無法讀取——對外狀態頁仍由獨立管線服務」＋外連 `status.chilllove.tw`，避免值班誤以為對外頁也掛了。

**響應式**（斷點與 CSS 已在原型定義）
| 斷點 | 行為 |
|---|---|
| ≤1279 | `.two-col` 維持兩欄；`.queues` 由 4 欄轉 2 欄；表格 `min-width:max-content` 改橫捲（CJK min-content 極小，寧可橫捲不擠字） |
| ≤1023 | 側欄轉抽屜；`.two-col` 塌成單欄；狀態頁元件列的 badge 與 bars 同列不換行（`sp-name` `flex:1`） |
| ≤767 | `html{font-size:14px}`；佇列表轉 `.card-table` 堆疊卡片（`td::before` 用 `data-label` 顯示欄名）；**歷史條只顯示 15 格**（`sp-bars i:nth-child(n+16){display:none}`）；modal 轉貼底 sheet（`sheetUp .22s`），`modal-foot` sticky ＋ `env(safe-area-inset-bottom)`；input `font-size:16px; height:40px` 防 iOS 聚焦放大 |
| ≤429 | `.queues` 單欄；`.page-actions` 全寬且按鈕 `flex:1`；**歷史條整條隱藏**（`.sp-bars{display:none}`）——只留元件名與狀態 badge |

**a11y**：元件狀態不得只靠顏色——每個 `<ComponentRow>` 同時有 `h-dot` 色點、文字 badge（Operational／Degraded Performance…）與 `aria-label`；歷史條每格 `<i title="08-04 partial_outage">` 並提供「以表格檢視」切換（對照 23 §3 圖表的表格切換慣例）。「重試」為 icon-free 文字鈕，無需 aria-label；modal 用 `role="dialog" aria-modal` ＋ 焦點移入，Esc 分層關閉（23 §3 Modal 列）。

---

## 發布與灰度（波次 W3）

### 1. 這是什麼、給誰用、解決什麼問題

**是什麼**：LaunchDarkly 的 flag 生命週期模型（33 §2.11）＋ Vercel Rolling Releases 的逐階段批准狀態機（同節），落成兩張卡：上卡「進行中的分階段發布」（步驟軸＋批准／中止），下卡「Feature flags」（狀態／生命週期／定向／覆蓋租戶）。

**給誰用**：
- 工程／`ops`：把新功能推給 5% → 25% → 50% → 100%（原型 `rolloutBody` 的五段步驟軸），每階段看錯誤率再批准。
- `admin`／`owner`：kill switch（一鍵中止回滾至 0%）。
- 技術債治理：卡右上「技術債 3」＝可清理的 flag 數（原型 `flags` 卡）。

**解決什麼問題**：
1. **flag 墳場**。沒有生命週期治理的 feature flag 系統，18 個月後會有 200 支永遠 `true` 的 flag 與對應的死代碼分支，每一支都是一條 if 分支、一組不再被測試的路徑。33 §2.11 的 30 天窗 ＋ code reference 掃描就是為了自動指出「這支可以刪了」。
2. **狀態靠人維護必然過期**。所以 4 態**不是欄位、是推導結果**——由「近 7 天是否被評估／是否只服務單一變體／設定變更時間」即時算出（硬要求 3）。
3. **百分比灰度不夠用**。33 §2.11 明確：「定向維度用 **cohort**（方案／地區／GMV 級距／beta 名單），不是純百分比」。原型兩個實例：`new_editor_beta` → cohort beta 名單 42 家；`checkout_v3` → cohort GMV ≥ NT$1M／月 186 家。
4. **出事要能一秒關掉**。kill switch 的傳播延遲必須是秒級且不依賴 Redis pub/sub（鐵律）。

**不做什麼**：不做 A/B 實驗統計（那是分析線）；不做多變體實驗（首版只支援 on/off 二變體，多變體結構預留但 **待定，需使用者確認**）。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `rollout`（進行中的分階段發布卡） | flag 名＋`rolling release` badge＋「批准下一階段」＋「中止」＋五段步驟軸＋定向與錯誤率摘要 | 狀態機 `configured → started → approved（逐階段人工批准）→ completed`，`aborted` ＝ kill switch（33 §2.11／DOCS `rollout`）。原型階梯：`configured / started 5% / approved 25% / 50% / completed 100%`。摘要行：「定向 cohort：beta 名單 42 家・錯誤率 0.21%（基線 0.19%）・逐階段需人工批准，**批准動作本身寫入審計**」（DOCS `rollout`） | 無進行中 rollout → 空態「目前沒有進行中的分階段發布」＋「建立」CTA。`aborted` 後該卡改顯示紅色摘要與中止人／時間，保留 24 小時後移入歷史（保留時長 **待定，需使用者確認**）。「批准下一階段」在最後一階顯示為「完成發布」。錯誤率無樣本（階段剛開始）→ 顯示 `—` 並禁用批准鈕（**待定**：最小觀察樣本數／時間） |
| `flags`（Feature flags 表：Flag／狀態／生命週期／定向／覆蓋租戶／動作） | 全平台 flag 索引 | **狀態 4 態自動推導（7 天窗）**：`New`／`Active`／`Launched`（近 7 天只服務單一變體且為 on）／`Inactive`（≥7 天未被評估）——33 §2.11。**生命週期（30 天窗）**：`Live → Ready for code removal → Ready to archive → Deprecated → Archived → Deleted`（必須先 archive）——同節。覆蓋租戶欄格式「42（25%）」＝目標命中數（分母＝全平台商店數 1,284） | 動作欄依生命週期切換：`Ready to archive` → 「archive」鈕；其餘 → 「編輯」鈕（原型 `flagRows` 的三元式）。`Inactive` 且 `permanent` 型 → **不**推進生命週期（permanent flag 本來就可能長期不評估，例如 kill switch 類）。covering 0 家的 flag 仍顯示（不隱藏），否則沒人記得清 |
| 卡頭「技術債 N」鈕 | 顯示可清理數 | N ＝ `lifecycle IN (ready_for_code_removal, ready_to_archive)` 的計數；原型 toast「3 支 flag 可清理（Ready to archive）」 | 點擊＝套用生命週期篩選（不是開 modal） |
| 「建立 flag」（page-actions） | 建立 temporary／permanent | 型別二選一，**`temporary` 才進 30 天生命週期推進**（33 §2.11：「temporary、所有關鍵環境已 Launched、≥30 天、仍有 code reference」） | key 格式：小寫蛇形，唯一；建立後不可改 key（改 key ＝ code reference 斷掉）。key 命名衝突 → `userErrors code: KEY_TAKEN` |
| 定向編輯（「編輯」鈕 → modal） | cohort 條件＋百分比 | cohort 維度：方案／地區／GMV 級距／beta 名單（33 §2.11）。百分比為 cohort **之內**的再抽樣，不是全平台百分比 | 同時設 cohort 與百分比時，UI 必須寫明「42 家中的 25%」而非「25% 的租戶」——否則營運會誤判影響面 |
| kill switch（「中止」鈕） | 立即回滾至 0% | `aborted`＝立即中止並回滾至 0%（DOCS `rollout`）；紅色 destructive 按鈕＋二次確認＋「無法復原（需重新建立 rollout）」明示（23 §4-6） | 中止必須 **O(1)**：只寫一列 ＋ 版本號 +1，不得逐租戶迴圈（1,284 家 × N flag 的迴圈在事故當下就是第二場事故）。中止在 `completed` 之後不可用（已無 rollout，改用「停用 flag」） |

---

### 3. 資料模型

> flag 與 rollout 是**平台域**概念（一支 flag 服務全平台），因此下列表**豁免 `shop_id` 鐵律，migration 檔頭須註明**。**唯一帶 `shop_id` 的是逐店覆寫表 `shop_feature_flag_overrides`。**

```ruby
# 平台域表（無 shop_id）——33 §6：feature_flags / flag_targets（cohort 條件）/ rollouts（stage, approved_by）
create_table :feature_flags do |t|
  t.string   :key,  null: false                 # 小寫蛇形，建立後不可改
  t.string   :name, null: false
  t.text     :description
  t.integer  :kind, null: false, default: 0     # temporary / permanent（33 §2.11：只有 temporary 進生命週期推進）
  t.boolean  :enabled, null: false, default: false   # 全域主開關（off = 全部服務 off 變體）
  t.string   :default_variant, null: false, default: "off"
  t.integer  :lifecycle, null: false, default: 0  # live/ready_for_code_removal/ready_to_archive/deprecated/archived
  t.datetime :lifecycle_entered_at, null: false   # 30 天窗的計時起點
  t.datetime :launched_since                      # 進入 Launched 態的時間（推進 ready_for_code_removal 用）
  t.datetime :settings_changed_at, null: false    # 「近 7 天是否改過設定」的來源（33 §2.11 三項推導條件之一）
  t.datetime :last_evaluated_at                   # 由 flag_evaluation_daily 彙總回寫（非熱路徑寫入）
  t.integer  :code_ref_count, null: false, default: 0
  t.datetime :code_ref_last_seen_at
  t.datetime :killed_at                           # kill switch 觸發時間
  t.integer  :config_version, null: false, default: 0  # 每次任何設定變更 +1（見 §6.5 傳播）
  t.timestamps
end
add_index :feature_flags, :key, unique: true
add_index :feature_flags, %i[lifecycle lifecycle_entered_at]

create_table :flag_targets do |t|                 # 33 §6：flag_targets（cohort 條件）
  t.references :feature_flag, null: false, foreign_key: true
  t.integer  :position, null: false, default: 0   # 由上而下第一個命中者勝
  t.integer  :cohort_kind, null: false            # plan / region / gmv_tier / beta_list / shop_ids / all
  t.json     :cohort_value, null: false           # {plan_keys:[...]} / {min_gmv_cents: 100_000_00} / {shop_ids:[...]}
  t.integer  :percentage, null: false, default: 100 # cohort「之內」的抽樣百分比
  t.string   :variant, null: false, default: "on"
  t.timestamps
end
add_index :flag_targets, %i[feature_flag_id position]

create_table :rollouts do |t|                     # 33 §6：rollouts（stage, approved_by）
  t.references :feature_flag, null: false, foreign_key: true
  t.integer  :state, null: false, default: 0      # configured/started/completed/aborted（33 §2.11 狀態機）
  t.bigint   :cohort_target_id                    # 對應 flag_targets 的定向
  t.integer  :current_stage_ordinal, null: false, default: 0
  t.datetime :aborted_at
  t.text     :abort_reason
  t.references :created_by, null: false, foreign_key: { to_table: :platform_staffs }
  t.timestamps
end

create_table :rollout_stages do |t|
  t.references :rollout, null: false, foreign_key: true
  t.integer  :ordinal, null: false                # 0..n
  t.integer  :percentage, null: false             # 原型階梯 5 / 25 / 50 / 100
  t.integer  :state, null: false, default: 0      # pending/active/approved/skipped
  t.datetime :started_at
  t.datetime :approved_at
  t.references :approved_by, foreign_key: { to_table: :platform_staffs }
  t.json     :metrics_snapshot                    # {error_rate: 0.0021, baseline: 0.0019, samples: 18402}
  t.timestamps
end
add_index :rollout_stages, %i[rollout_id ordinal], unique: true

# 評估事件的彙總表——刻意「無 shop_id」（平台域表）：
# 4 態推導只需要「有沒有被評估」與「服務了哪些變體」，不需要逐租戶歸因（見 §6.2 為什麼）。
create_table :flag_evaluation_daily do |t|
  t.string  :flag_key, null: false
  t.date    :on_date,  null: false
  t.string  :variant,  null: false
  t.bigint  :count,    null: false, default: 0
  t.datetime :last_seen_at, null: false
end
add_index :flag_evaluation_daily, %i[flag_key on_date variant], unique: true
add_index :flag_evaluation_daily, :on_date                     # 7 天窗掃描與 purge 用

# 可選的逐租戶抽樣（除錯用，預設關閉）——見 §6.2「取樣策略」
create_table :flag_evaluation_samples do |t|
  t.bigint  :shop_id, null: false
  t.string  :flag_key, null: false
  t.string  :variant, null: false
  t.datetime :evaluated_at, null: false
end
add_index :flag_evaluation_samples, %i[shop_id flag_key evaluated_at]   # shop_id 前導（鐵律）

create_table :flag_code_references do |t|         # code reference 掃描結果（硬要求 3）
  t.references :feature_flag, null: false, foreign_key: true
  t.string  :repo, null: false
  t.string  :git_ref, null: false                 # main / release-*
  t.string  :path, null: false
  t.integer :line, null: false
  t.string  :commit_sha, null: false
  t.bigint  :scan_id, null: false                 # 同 repo+ref 的最新 scan_id 以外的列即為已刪除
  t.datetime :first_seen_at, null: false
  t.datetime :last_seen_at,  null: false
end
add_index :flag_code_references, %i[feature_flag_id repo git_ref]
add_index :flag_code_references, %i[repo git_ref scan_id]

create_table :flag_code_scans do |t|              # 一次 CI 掃描
  t.string  :repo, null: false
  t.string  :git_ref, null: false
  t.string  :commit_sha, null: false
  t.integer :flags_scanned, null: false
  t.integer :references_found, null: false
  t.datetime :scanned_at, null: false
end
add_index :flag_code_scans, %i[repo git_ref scanned_at]

# 唯一帶 shop_id 的表（鐵律：複合索引 shop_id 前導）
create_table :shop_feature_flag_overrides do |t|
  t.bigint  :shop_id, null: false
  t.string  :flag_key, null: false
  t.string  :variant, null: false                 # on / off
  t.references :set_by, foreign_key: { to_table: :platform_staffs }
  t.text    :reason
  t.timestamps
end
add_index :shop_feature_flag_overrides, %i[shop_id flag_key], unique: true
```

**解析優先序（precedence）**——33 未明文，**待定，需使用者確認**；本手冊實作採：
`1. shop_feature_flag_overrides（逐店覆寫，32 §6 platformShopFlagSet）` → `2. flag.killed_at 存在 → off（kill switch 壓過一切）` → `3. flag.enabled == false → off` → `4. flag_targets 由 position 由小到大第一個命中者（含 percentage 抽樣）` → `5. flag.default_variant`。
> 為什麼 kill switch 排在逐店覆寫**之後**：逐店覆寫是支援人員為單一租戶做的臨時處置（例如「這家店暫時關掉新編輯器」），不應被全域 kill switch 蓋掉方向相反的意圖；但 kill switch 必須壓過 targets 與 rollout。**此排序需使用者確認**。

---

### 4. API 契約（Platform:: GraphQL）

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformFeatureFlags(first, after, state, lifecycle, kind, query)` | query | cursor ≤250 | `FeatureFlagConnection{ nodes { id key name state lifecycle kind targeting { summary } coverage { shops percent } codeRefCount lastEvaluatedAt } }` | — | 全部（含 read_only） |
| `platformFeatureFlag(id \| key)` | query | — | `FeatureFlag`（含 `targets`、`evaluationDaily(last:7)`、`codeReferences(first:50)`、`rollouts`） | — | 全部 |
| `platformFeatureFlagCreate(input!)` | mutation | `{key!, name!, description, kind!(TEMPORARY\|PERMANENT), defaultVariant}` | `{ featureFlag, userErrors }` | `KEY_TAKEN`／`KEY_INVALID_FORMAT` | owner／admin（原型 RM「上限覆寫／flags」） |
| `platformFeatureFlagUpdate(id, name, description, enabled)` | mutation | 不可改 key | `{ featureFlag, userErrors }` | `KEY_IMMUTABLE` | owner／admin |
| `platformFlagTargetsSet(flagId!, targets: [FlagTargetInput!]!)` | mutation | 宣告式 upsert（28 §0.3 `*Set` 慣例），陣列 ≤250 | `{ featureFlag, coverage, userErrors }` | `COHORT_INVALID`／`PERCENTAGE_OUT_OF_RANGE` | owner／admin |
| `platformShopFlagSet(shopId!, key!, variant!, reason!)` | mutation | 逐店覆寫（32 §6 既有操作，本段補 `reason` 必填） | `{ override, userErrors }` | `FLAG_NOT_FOUND`／`REASON_REQUIRED` | owner／admin |
| `platformRolloutCreate(flagId!, cohortTargetId, stages: [Int!]!)` | mutation | `stages` 預設 `[5,25,50,100]`（原型階梯） | `{ rollout, userErrors }` | `ROLLOUT_ALREADY_ACTIVE`／`STAGES_NOT_ASCENDING` | owner／admin |
| `platformRolloutStart(id!)` | mutation | `configured → started` | `{ rollout, userErrors }` | `INVALID_TRANSITION` | owner／admin |
| `platformRolloutApproveStage(id!, stageOrdinal!, note)` | mutation | 逐階段人工批准 | `{ rollout, stage, userErrors }` | `INVALID_TRANSITION`／`STAGE_NOT_ACTIVE`／`INSUFFICIENT_SAMPLES` | **原型審計顯示 `ops` 角色曾批准，但 RM 矩陣為 owner／admin — 見附錄 A 衝突 C2，待定** |
| `platformRolloutAbort(id!, reason!)` | mutation | **kill switch**；冪等 | `{ rollout, featureFlag, userErrors }` | `REASON_REQUIRED`／`ALREADY_COMPLETED` | owner／admin（危險動作） |
| `platformFlagArchive(id!)` | mutation | 僅 `ready_to_archive` 可用（33 §2.11：必須先 archive 才能 delete） | `{ featureFlag, userErrors }` | `NOT_READY_TO_ARCHIVE`（附 `codeRefCount`） | owner／admin |
| `platformFlagDelete(id!)` | mutation | 僅 `archived` 可用 | `{ deletedId, userErrors }` | `MUST_ARCHIVE_FIRST` | owner |
| `platformFlagCodeReferencesSync(input!)` | mutation | CI 專用：`{repo!, gitRef!, commitSha!, references: [{key, path, line}]}`（陣列 ≤250／批） | `{ scan { id referencesFound }, lifecycleAdvanced { key from to }, userErrors }` | `UNKNOWN_FLAG_KEY`（回警告不擋）／`SCAN_STALE`（commitSha 早於已記錄者） | CI bot token（`read_write_flags` scope；**新 scope，待定，需使用者確認**） |

> **鐵律檢查**：全部 mutation 業務錯誤走 `userErrors`／HTTP 200；`platformFlagCodeReferencesSync` 是 CI 呼叫的高頻操作，`references` 分批送，每批 ≤250（28 §0.3 陣列上限）。

---

### 5. 服務物件與背景任務

| 類別 | 職責 | 觸發 |
|---|---|---|
| `Platform::Flags::Snapshot` | 進程級 flag 設定快照；每 2s 輪詢 `config_version` 最大值決定是否重載 | 進程常駐執行緒 |
| `Platform::Flags::Evaluator` | 熱路徑求值：`Flags.on?(:checkout_v3, shop:)`；O(1)、零 DB | 同步 |
| `Platform::Flags::EvaluationRecorder` | 進程內累計 → 每 60s flush 到 `flag_evaluation_daily`（UPSERT） | 常駐執行緒 ＋ `at_exit` |
| `Platform::Flags::StateDeriver` | 4 態推導（7 天窗） | 讀取時即時算＋每小時回寫 `last_evaluated_at` 快取欄 |
| `Platform::Flags::LifecycleAdvancerJob` | 30 天窗推進（Live → Ready for code removal → Ready to archive） | recurring 每日 06:00 |
| `Platform::Flags::CoverageCalculatorJob` | 依 `flag_targets` 算覆蓋租戶數與百分比 | recurring 每小時＋targets 變更後即時 |
| `Platform::Rollouts::StageApprover` | 批准一階段：檢查樣本量 → 寫 `approved_by/at` → 更新 target percentage → **寫審計** | 同步（mutation） |
| `Platform::Rollouts::KillSwitch` | 中止：寫 `aborted`、`flags.killed_at`、`config_version += 1` | 同步（mutation） |
| `Platform::Flags::MetricsSamplerJob` | 每階段的錯誤率／基線快照寫入 `rollout_stages.metrics_snapshot` | recurring 每 5 分鐘（rollout 進行中才活躍） |
| `Platform::Flags::EvaluationPurgeJob` | `flag_evaluation_daily` 保留 90 天、`flag_evaluation_samples` 保留 7 天 | recurring 每日 |
| `bin/flag_scan`（CI 側，非 Rails runtime） | 掃 repo → 呼叫 `platformFlagCodeReferencesSync` | GitHub Actions：push to main ＋ nightly |

---

### 6. 關鍵流程與演算法

#### 6.1 4 態自動推導（硬要求 3 第一項）

33 §2.11 給的三個判準：**近 7 天是否被評估** / **是否只服務單一變體（且為 on）** / **近 7 天是否改過設定**。

```ruby
# app/services/platform/flags/state_deriver.rb
module Platform
  module Flags
    # Flag 4 態推導器。狀態不是欄位、是推導結果——
    # 為什麼：手動維護的狀態欄位在三個月後必定與現實脫節（33 §2.11 採 LaunchDarkly 模型的理由）。
    class StateDeriver
      WINDOW = 7.days   # 33 §2.11：「狀態 4 態（7 天窗）」

      Result = Struct.new(:state, :evidence, keyword_init: true)

      # @param flag [FeatureFlag]
      # @param rows [Array<FlagEvaluationDaily>] 近 7 天該 flag 的彙總列（呼叫端批次預載，避免 N+1）
      def self.call(flag, rows)
        since   = WINDOW.ago
        recent  = rows.select { |r| r.last_seen_at >= since }
        variants = recent.map(&:variant).uniq

        state =
          if recent.empty?
            # 「≥7 天未被評估」（33 §2.11）。但剛建立且從未評估者歸 New——
            # New 的精確定義 33 未展開，此處採 LaunchDarkly 原義：建立 ≤7 天且無任何 evaluation。
            # 待定，需使用者確認。
            flag.created_at >= since && flag.last_evaluated_at.nil? ? :new : :inactive
          elsif variants.size == 1 && variants.first == "on"
            # 「近 7 天只服務單一變體且為 on」→ Launched（33 §2.11 字面定義）
            :launched
          else
            # 其餘皆 Active：包含「多變體並行」與「只服務單一 off 變體」。
            # 後者（長期只吐 off）被歸為 Active 是 33 字面推得的結果，語感偏怪——
            # 待定，需使用者確認是否要新增 "Off" 態。
            :active
          end

        Result.new(state:, evidence: {
          window_days: 7, evaluated_recently: recent.any?, variants:,
          settings_changed_recently: flag.settings_changed_at >= since   # 33 第三個判準：供 UI 顯示「近期有變更」標記
        })
      end
    end
  end
end
```

> **「近 7 天是否改過設定」用在哪**：33 把它列為推導輸入，但四個態的定義本身沒用到它。本手冊的處理：它**不參與態的判定**，而是作為 UI 上的 `recently_changed` 標記與 **生命週期推進的否決條件**——近 7 天改過設定的 flag 不得自動推進到 `ready_for_code_removal`（剛改過就說可以刪代碼，顯然是誤判）。**此用法為推論，待定，需使用者確認**。

#### 6.2 evaluation 事件怎麼收（硬要求 3 第三項：取樣策略）

**問題**：flag 求值發生在每一次請求、每一次 job。1,284 家店 × 每天數百萬次求值，每次寫一列 DB ＝ 寫入放大到不可用（而且我們沒有 Redis 可以當計數器，鐵律）。

**關鍵洞察（讓問題變簡單的那一步）**：4 態推導只需要兩個**布林／集合**事實——「近 7 天有沒有被評估」與「服務了哪些變體」。它**不需要精確計數，也不需要逐租戶歸因**。而「覆蓋租戶 42（25%）」那一欄是從 `flag_targets` **算**出來的（cohort 條件套在 `shops` 上），不是從評估事件統計出來的。所以評估紀錄可以無 `shop_id`、可以是聚合值。

**做法：進程內聚合 ＋ 定時 flush（不是隨機取樣）**

```ruby
# app/services/platform/flags/evaluation_recorder.rb
module Platform
  module Flags
    # 評估事件收集器：進程內 in-memory 累計，每 60 秒 flush 一次。
    #
    # 為什麼不是「每次評估寫 DB」：flag 求值在熱路徑，寫入放大會直接吃掉連線池（11 §8-2 同一類坑）。
    # 為什麼不是「隨機取樣 1%」：取樣會讓低頻 flag（一天被評估 3 次）在 7 天窗內看起來像 Inactive，
    #   而低頻 flag 正是最需要正確判定的那一群（它們是清理候選）。聚合是精確的，取樣不是。
    # 為什麼不用 Solid Cache 做計數器：Solid Cache 也是 DB，increment 一樣要打 DB；
    #   而且快取可被驅逐，flush 前遺失就等於評估事件消失。
    class EvaluationRecorder
      FLUSH_INTERVAL = 60.seconds

      def initialize
        @buffer = Concurrent::Map.new     # { [flag_key, variant] => count }
        @mutex  = Mutex.new
      end

      # 熱路徑：純記憶體操作，無 IO、無鎖競爭（Concurrent::Map 內部分段）。
      def record(flag_key, variant)
        @buffer.compute([flag_key, variant]) { |c| (c || 0) + 1 }
        SampleSink.maybe_record(flag_key, variant) if SampleSink.enabled?
      end

      # 每 60 秒由常駐執行緒呼叫；亦在 at_exit / Puma on_worker_shutdown 呼叫一次。
      # 遺失最後 60 秒的資料是可接受的：7 天窗只在意「有沒有」，不在意少 60 秒的計數。
      def flush!
        snapshot = @mutex.synchronize do
          taken = @buffer.each_pair.to_h
          taken.each_key { |k| @buffer.delete(k) }
          taken
        end
        return if snapshot.empty?

        today = Date.current
        now   = Time.current
        rows = snapshot.map do |(key, variant), count|
          { flag_key: key, on_date: today, variant:, count:, last_seen_at: now }
        end
        # 一次 UPSERT 全部（MySQL 8 ON DUPLICATE KEY UPDATE）。
        # 每進程每分鐘 1 次寫入、列數 = 該進程這分鐘碰到的 (flag, variant) 組合數（通常 <40）。
        FlagEvaluationDaily.upsert_all(
          rows, unique_by: %i[flag_key on_date variant],
          on_duplicate: Arel.sql("count = count + VALUES(count), last_seen_at = VALUES(last_seen_at)")
        )
      end
    end

    # 逐租戶歸因（除錯用，預設關閉）：這裡才用真正的取樣。
    # 取樣率 1/1000 為 待定，需使用者確認；保留 7 天。
    module SampleSink
      RATE = 1_000
      def self.enabled? = Rails.configuration.x.flags.sample_per_shop
      def self.maybe_record(flag_key, variant)
        return unless rand(RATE).zero?
        shop_id = ActsAsTenant.current_tenant&.id or return
        FlagEvaluationSample.insert_all!([{ shop_id:, flag_key:, variant:, evaluated_at: Time.current }])
      end
    end
  end
end
```

**寫入量估算**（給 Codex 做 sanity check）：8 個 app 進程 × 每分鐘 1 次 UPSERT × 1,440 分 ＝ **11,520 次 UPSERT／日**，每次帶 20–40 列小列。相較「每次評估一列」的數百萬列，差三個數量級。若日後進程數大增，把 `FLUSH_INTERVAL` 拉到 300 秒即可線性下降（7 天窗完全不受影響）。

**flush 不得在請求的 transaction 內執行**——由獨立執行緒跑（鐵律：transaction 內禁外部 IO 的同一精神，避免拉長鎖持有時間）。

#### 6.3 code reference 掃描怎麼做（硬要求 3 第二項）

**在 CI 跑，不在 runtime 跑**——runtime 的容器裡沒有 repo。

```yaml
# .github/workflows/flag-scan.yml（節錄）
name: flag-scan
on:
  push: { branches: [main] }
  schedule: [{ cron: "0 18 * * *" }]   # UTC 18:00 = 台北 02:00（cron 一律 UTC 寫並註記，18 §F5 坑）
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 1 }
      - run: ruby bin/flag_scan --repo "$GITHUB_REPOSITORY" --ref "${GITHUB_REF_NAME}" --sha "$GITHUB_SHA"
        env: { PLATFORM_API_TOKEN: "${{ secrets.PLATFORM_FLAG_SCAN_TOKEN }}" }
```

```ruby
#!/usr/bin/env ruby
# bin/flag_scan —— CI 專用：掃 repo 的 flag 使用點並回報平台。
#
# 為什麼掃描結果是「生命週期」的推進依據而不是「狀態」的依據：
#   33 §2.11 把兩件事分開——狀態（4 態）看執行期行為（是否被評估）；
#   生命週期看「代碼裡還有沒有人用」。一支 flag 可以是 Launched（線上只吐 on）
#   但代碼裡還有 if 分支 → Ready for code removal；分支刪掉後 → Ready to archive。
require "json"; require "open3"; require "net/http"

EXCLUDE = %w[
  vendor/ node_modules/ tmp/ log/ coverage/ public/assets/
  docs/ db/seeds.rb db/migrate/ spec/fixtures/ test/fixtures/
  config/feature_flags.yml            # ← 關鍵：flag 宣告檔本身不算 reference，否則每支 flag 永遠有 1 個 ref
].freeze

# 1. 向平台取 flag key 清單（不從本地檔案讀——平台才是 flag 的真相來源）
keys = GraphQL.call(<<~Q)["data"]["platformFeatureFlags"]["nodes"].map { _1["key"] }
  { platformFeatureFlags(first: 250) { nodes { key } } }
Q

# 2. ripgrep 一次掃完（--fixed-strings --word-regexp 避免 checkout_v3 誤命中 checkout_v30）
#    JSON 輸出便於精確取 path/line；-f 從檔案讀 pattern 清單避免命令列長度上限。
File.write("/tmp/flag_keys.txt", keys.join("\n"))
args = ["rg", "--json", "--fixed-strings", "--word-regexp", "-f", "/tmp/flag_keys.txt", "."]
EXCLUDE.each { |g| args += ["--glob", "!#{g}"] }
out, = Open3.capture2(*args)

refs = out.each_line.filter_map do |line|
  ev = JSON.parse(line) rescue next
  next unless ev["type"] == "match"
  d = ev["data"]
  matched = d["submatches"].map { _1.dig("match", "text") }.uniq
  matched.map { |k| { key: k, path: d.dig("path", "text").delete_prefix("./"), line: d["line_number"] } }
end.flatten

# 3. 分批回報（每批 ≤250，28 §0.3 陣列上限）；平台端以 scan_id 做「本次沒出現＝已刪除」判定
refs.each_slice(250).with_index do |batch, i|
  GraphQL.call(MUTATION, variables: {
    input: { repo: ARGV_REPO, gitRef: ARGV_REF, commitSha: ARGV_SHA,
             references: batch, final: (i == (refs.size / 250.0).ceil - 1) }
  })
end
```

**掃描的五個坑與對策**（每一條都要寫進 `docs/dev/`）：

| 坑 | 後果 | 對策 |
|---|---|---|
| **動態 key**：`Flags.on?("checkout_#{ver}")` | 掃不到 → 誤判「無 code reference」→ 被 archive → 線上炸 | 自訂 RuboCop cop `ChillLove/StaticFlagKey`（禁止 `Flags.on?` 首參數為插值字串／變數）；確有需要者在 flag 上設 `dynamic: true`，**該 flag 的生命週期改為手動推進** |
| **前端 TS 用法**：`useFlag("checkout_v3")` / `flags.checkoutV3` | 只掃 Ruby 會漏 | ripgrep 掃全 repo（含 `.ts/.tsx`）；駝峰別名一律禁止（cop 同步管 TS 端，或在 `useFlag` 型別上用字面量聯集強制原字串） |
| **flag 宣告檔自我命中** | 每支 flag 永遠 ≥1 ref，`ready_to_archive` 永不到達 | `EXCLUDE` 排除宣告檔、migration、seeds、docs、fixtures |
| **舊分支還在用** | 只掃 main 就把 flag archive 掉，舊分支 merge 回來即 500 | 掃 `main` **與所有 `release-*` 分支**；`ready_to_archive` 要求**所有被掃 ref 皆為 0** |
| **CI 掛掉沒回報** | `code_ref_last_seen_at` 停滯 → 誤以為「沒人用」 | 生命週期推進的前置條件加一條：`code_ref_last_seen_at >= 48.hours.ago`，否則跳過並在後台顯示「掃描資料過期」 |

#### 6.4 生命週期 30 天窗推進

```ruby
# app/jobs/platform/flags/lifecycle_advancer_job.rb
class Platform::Flags::LifecycleAdvancerJob < ApplicationJob
  queue_as :low
  WINDOW = 30.days   # 33 §2.11：「生命週期（30 天窗）」

  def perform
    ActsAsTenant.without_tenant do
      FeatureFlag.where(lifecycle: %i[live ready_for_code_removal]).find_each do |flag|
        advance!(flag)
      end
    end
  end

  private

  def advance!(flag)
    return if flag.permanent?                                   # 33：只有 temporary 進推進（permanent 如 kill switch 類長期存在）
    return if flag.dynamic?                                     # 動態 key，掃描不可信（§6.3）
    return if flag.code_ref_last_seen_at.nil? ||
              flag.code_ref_last_seen_at < 48.hours.ago         # 掃描資料過期 → 不推進（§6.3 第五坑）

    case flag.lifecycle.to_sym
    when :live
      # 33 §2.11：temporary、所有關鍵環境已 Launched、≥30 天、仍有 code reference
      #   「≥30 天」的起算點 33 未明說，此處採「自進入 Launched 起算」——待定，需使用者確認。
      #   「關鍵環境」的定義 33 未給，此處採 production——待定，需使用者確認。
      return unless launched_in_key_envs?(flag)
      return unless flag.launched_since && flag.launched_since <= WINDOW.ago
      return unless flag.code_ref_count.positive?
      return if flag.settings_changed_at >= 7.days.ago          # 近 7 天改過設定 → 不推進（§6.1 註）
      move!(flag, :ready_for_code_removal)

    when :ready_for_code_removal
      # 33 §2.11：已無 code reference → Ready to archive
      move!(flag, :ready_to_archive) if flag.code_ref_count.zero?
    end
  end

  # 推進本身寫審計（每個平台寫入動作皆須有審計列，33 §2.8）
  def move!(flag, to)
    from = flag.lifecycle
    flag.update!(lifecycle: to, lifecycle_entered_at: Time.current)
    Platform::Audit.record!(action: "flag.lifecycle_advance", target: flag, actor: :system,
                            source: "自動化", previous: { lifecycle: from }, next: { lifecycle: to })
    Platform::Notifier.flag_cleanup_candidate(flag) if to == :ready_to_archive
  end
end
```

**`Ready to archive → Deprecated → Archived → Deleted` 三段**：33 §2.11 列出這三態但未給推進條件。本手冊實作為**全人工**（`platformFlagArchive` 只允許從 `ready_to_archive`；`platformFlagDelete` 只允許從 `archived`，符合 33 的「Deleted（必須先 archive）」）。`Deprecated` 態的觸發條件與 `Archived → Deleted` 的保留期 **待定，需使用者確認**。

#### 6.5 Rolling release 與 kill switch

```ruby
# app/services/platform/rollouts/stage_approver.rb
module Platform
  module Rollouts
    # 逐階段人工批准（33 §2.11 Vercel 模型）。
    # 批准動作本身寫審計——DOCS rollout 明列；原型審計列 flag.rollout_approve 即為此。
    class StageApprover
      def initialize(rollout:, ordinal:, actor:, note: nil)
        @rollout, @ordinal, @actor, @note = rollout, ordinal, actor, note
      end

      def call
        stage = @rollout.stages.find_by!(ordinal: @ordinal)
        return failure(:STAGE_NOT_ACTIVE) unless stage.active?
        return failure(:INSUFFICIENT_SAMPLES) unless enough_samples?(stage)

        ApplicationRecord.transaction do
          stage.update!(state: :approved, approved_by: @actor, approved_at: Time.current)
          target = @rollout.cohort_target
          target.update!(percentage: stage.percentage)        # 定向是 cohort「之內」的百分比（§2）
          @rollout.update!(current_stage_ordinal: @ordinal + 1,
                           state: (@ordinal + 1 >= @rollout.stages.count ? :completed : :started))
          @rollout.feature_flag.increment!(:config_version)   # ← 讓全機群 ≤2 秒內看到新百分比
        end
        # 審計與通知在 transaction 外（鐵律：transaction 內禁外部 IO）
        Platform::Audit.record!(action: "flag.rollout_approve", target: @rollout.feature_flag, actor: @actor,
                                previous: { stage: "#{prev_pct}%", state: "started" },
                                next: { stage: "#{stage.percentage}%", state: "approved", approver: @actor.name })
        success(stage)
      end

      # 最小樣本量門檻：待定，需使用者確認（33 未給；建議「該階段至少觀察 30 分鐘且 ≥1,000 次評估」）
      def enough_samples?(stage) = stage.metrics_snapshot.to_h["samples"].to_i >= 1_000
    end

    # Kill switch：必須 O(1)。
    # 為什麼不逐租戶迴圈關閉：事故當下對 1,284 家店做 UPDATE 是第二場事故；
    # 只寫「一列 flag + config_version+1」，各進程靠 §6.6 的版本輪詢在 ≤2 秒內全部翻轉。
    class KillSwitch
      def self.call(rollout:, actor:, reason:)
        flag = rollout.feature_flag
        ApplicationRecord.transaction do
          rollout.update!(state: :aborted, aborted_at: Time.current, abort_reason: reason)
          flag.update!(killed_at: Time.current, config_version: flag.config_version + 1)
        end
        Platform::Audit.record!(action: "flag.rollout_abort", target: flag, actor:, reason:,
                                previous: { state: "started" }, next: { state: "aborted", percentage: 0 })
        flag
      end
    end
  end
end
```

#### 6.6 熱路徑求值與傳播（為什麼不用 Redis 也能秒級生效）

```ruby
# app/services/platform/flags/evaluator.rb
module Platform
  module Flags
    # 求值：全部走進程內快照，零 DB。
    # 傳播機制：每個進程有一條背景執行緒，每 2 秒執行
    #   SELECT MAX(config_version) FROM feature_flags
    # 一列彙總查詢（覆蓋索引即可），若與快照版本不同才重載整份 flag 設定（通常 <200 列）。
    # 為什麼這樣夠：kill switch 的可接受延遲是「秒」不是「毫秒」；
    #   每進程 30 QPM 的成本遠低於引入 Redis（鐵律禁止）或 long-polling 通道的複雜度。
    class Evaluator
      def self.on?(key, shop:) = variant_for(key, shop:) == "on"

      def self.variant_for(key, shop:)
        snap = Snapshot.current
        flag = snap.flag(key) or return "off"          # 未知 key 一律 off（fail closed）
        variant =
          snap.shop_override(shop.id, key) ||          # 1. 逐店覆寫
          (flag[:killed_at] && "off") ||               # 2. kill switch
          (!flag[:enabled] && "off") ||                # 3. 全域主開關
          match_target(snap, flag, shop) ||            # 4. cohort targets（含 percentage 抽樣）
          flag[:default_variant]                       # 5. 預設
        EvaluationRecorder.instance.record(key, variant)
        variant
      end

      # percentage 抽樣必須「穩定」：同一家店每次求值結果一致，否則同一租戶會在兩個分支間跳動。
      # 用 CRC32("#{key}:#{shop_id}") % 100 而不是 rand。
      def self.bucket(key, shop_id) = Zlib.crc32("#{key}:#{shop_id}") % 100
    end
  end
end
```

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本／用途 | 為何選它 |
|---|---|---|
| **不引入 flag SaaS（LaunchDarkly／Flipper Cloud）** | — | 33 §2.11 是「照 LaunchDarkly 的**模型**做」，不是「買 LaunchDarkly」。外部 SaaS 會把租戶 cohort（方案／GMV 級距）送到第三方，且求值需要網路往返或 SDK 常駐；我們的 cohort 條件直接查自己的 `shops` 表更快也更合規 |
| `flipper` gem？ | **不採用** | Flipper 的 actor 模型與我們的 cohort（方案／地區／GMV 級距）不對盤，且 `flipper-active_record` 的每次求值查 DB 與 §6.6 的快照策略衝突；自建約 400 行，可控性更高。**若使用者傾向用 Flipper，需重新設計 §6.6，待確認** |
| `concurrent-ruby` | 已是 Rails 依賴；`Concurrent::Map` 做進程內計數 | 免新增依賴；分段鎖，熱路徑無全域鎖競爭 |
| `ripgrep`（CI runner 內建／`apt install ripgrep`） | code reference 掃描 | `--json` 輸出可精確取 path/line；`-f patterns.txt` 避開命令列長度上限；比 `grep -r` 快一個量級（monorepo 掃 200 個 key 約 1–2 秒） |
| `rubocop`（已在 11 §1-6 CI） | 自訂 cop `ChillLove/StaticFlagKey` | 動態 key 是掃描機制的唯一致命傷，必須在 CI 擋 |
| Solid Queue recurring | `LifecycleAdvancerJob`（每日）、`CoverageCalculatorJob`（每小時）、`MetricsSamplerJob`（每 5 分） | 鐵律不用 Redis；recurring 自帶唯一性（18 §F5 坑） |
| `zlib`（stdlib） | 穩定分桶 `CRC32` | 無依賴、速度快；不用 MD5（沒必要的密碼學成本） |

---

### 8. 實作步驟（順序化 todo）

1. `config/feature_flags.yml` 定義 flag **宣告**（key／name／kind／description），M0 種子把原型 4 支預設 flag（`liquid_engine_v2`／`markets_p1`／`einvoice_auto`／`ai_assistant`）與原型 flag 表 5 支灌進 DB。
2. 建表：`feature_flags` / `flag_targets` / `shop_feature_flag_overrides`（shop_id 前導索引）/ `flag_evaluation_daily` / `flag_code_references` / `flag_code_scans`。
3. `Snapshot` ＋ `Evaluator`（含穩定分桶）＋ `EvaluationRecorder`（含 flush 執行緒與 `at_exit`）。**先做這三個，其他一切依賴它**。
4. `Flags.on?` 的全站 API 定案並寫進 `AGENTS.md` 風格指南；RuboCop cop `ChillLove/StaticFlagKey`。
5. `StateDeriver`（純函式，先寫 spec 再寫實作）。
6. `bin/flag_scan` ＋ `platformFlagCodeReferencesSync` mutation ＋ GitHub Actions workflow。**先讓掃描跑起來累積資料**，再做生命週期推進（否則第一天跑推進會因 `code_ref_last_seen_at` 為 nil 而全數跳過，看不出對錯）。
7. `LifecycleAdvancerJob`（含五個否決條件）。
8. `rollouts` / `rollout_stages` ＋ `StageApprover` ＋ `KillSwitch` ＋ `MetricsSamplerJob`。
9. `CoverageCalculatorJob`（cohort → shops 的查詢要走索引；GMV 級距用 `platform_daily_rollups` 而非即時算，避免全表掃）。
10. Platform:: GraphQL 型別與 mutation（含 typed error code enum）。
11. 前端兩張卡（§11）。
12. 演練：建一支 temporary flag → 灌評估事件 → 驗 4 態 → 刪掉代碼引用 → 驗生命週期在次日推進 → 建 rollout 走完四階 → 中止並量測傳播延遲。

---

### 9. 測試清單

```
spec/services/platform/flags/state_deriver_spec.rb
  - 近 7 天無評估 → inactive；建立 ≤7 天且從未評估 → new
  - 近 7 天只有 "on" → launched
  - 近 7 天有 on 與 off → active
  - 近 7 天只有 "off" → active（33 字面定義，附註解說明此為刻意行為）
  - 邊界：last_seen_at 恰為 7 天前的那一刻（用 freeze_time）

spec/services/platform/flags/evaluation_recorder_spec.rb
  - record 不打 DB（斷言 ActiveRecord query count == 0）
  - flush! 產生 UPSERT，同 (key,date,variant) 第二次 flush 累加 count 而非新增列
  - 多執行緒並發 record 後 flush，總數等於呼叫次數（Concurrent::Map 正確性）
  - at_exit flush（模擬 worker shutdown）

spec/lib/flag_scan_spec.rb（或 bin 的整合測試）
  - 排除清單生效：config/feature_flags.yml 內的 key 不算 reference
  - --word-regexp：checkout_v3 不會命中 checkout_v30
  - .tsx 內的 useFlag("key") 能命中
  - 空結果（flag 已無引用）正確回報 references: []

spec/jobs/platform/flags/lifecycle_advancer_job_spec.rb
  - live → ready_for_code_removal：temporary + launched 滿 30 天 + code_ref_count > 0
  - 未滿 30 天不推進；permanent 不推進；dynamic 不推進
  - code_ref_last_seen_at 超過 48h → 跳過並標「掃描資料過期」
  - 近 7 天改過設定 → 不推進
  - ready_for_code_removal + code_ref_count == 0 → ready_to_archive
  - 每次推進都有一列 platform_audit_logs（previous/next JSON）

spec/services/platform/rollouts/kill_switch_spec.rb
  - abort 後 Evaluator.on? 全部回 false（含原本命中 cohort 的店）   ← 硬要求：kill switch
  - abort 只寫 2 列（rollout + flag），不對 shops 做任何 UPDATE（query count 斷言）
  - config_version 遞增；Snapshot 在 2 秒內反映（用可注入的 clock，不睡 2 秒）
  - abort 冪等：連呼兩次不產生第二列審計
  - abort 後 platformRolloutApproveStage → userErrors code ALREADY_COMPLETED/INVALID_TRANSITION

spec/services/platform/rollouts/stage_approver_spec.rb
  - 批准寫 approved_by/at 並更新 target percentage 為該階段值
  - 樣本不足 → INSUFFICIENT_SAMPLES
  - 批准動作寫審計 action = flag.rollout_approve（對照原型審計列）

spec/services/platform/flags/evaluator_spec.rb
  - 優先序五層逐層測（逐店覆寫 > kill > enabled > targets > default）
  - 穩定分桶：同一 shop_id 呼叫 100 次結果一致；不同 shop 分佈近似均勻（±5%）
  - 未知 key → off（fail closed）

spec/requests/platform/graphql/feature_flags_spec.rb
  - archive 非 ready_to_archive → NOT_READY_TO_ARCHIVE（HTTP 200）
  - delete 非 archived → MUST_ARCHIVE_FIRST
  - read_only 呼叫 mutation → FORBIDDEN
```

---

### 10. 驗收清單

- [ ] **33 §5-12 逐條**：4 態自動推導 ✓／rolling release 逐階段批准 ✓／kill switch 一鍵 ✓／cohort 定向 ✓。
- [ ] **11 §5**：flag 求值不產生額外日誌噪音；`config_version` 變更事件上報 Sentry breadcrumb；rollout 各階段錯誤率進 OTel 指標，與卡片顯示同源。
- [ ] **11 §4**：`Evaluator.on?` 在 benchmark 下 p99 < 50µs（純記憶體）；`CoverageCalculatorJob` 的 cohort 查詢 `EXPLAIN` 無全表掃。
- [ ] **11 §9**：`bullet` 0 報警（flag 表 5 列不得對 `flag_targets` N+1）；`rspec` 全綠。
- [ ] **鐵律**：`shop_feature_flag_overrides` 複合索引 `shop_id` 前導；其餘 flag 表在 migration 檔頭註明「平台域表」豁免理由。
- [ ] kill switch 傳播延遲實測 ≤2 秒（多進程環境）。
- [ ] CI 的 `flag-scan` job 在 main 每次 push 後 5 分鐘內把 `code_ref_last_seen_at` 更新。
- [ ] 「技術債 N」計數與表格篩選結果一致（數字同源）。
- [ ] 所有 flag 寫入動作（建立／改定向／批准／中止／archive／逐店覆寫）在 `platform_audit_logs` 有列。

---

### 11. 前端（React/TS）

**元件樹**
```
<ReleasesPage>
  ├ <PageHead title="發布與灰度" sub="flag 生命週期・cohort 定向・kill switch">
  │   └ actions: <Button pri>建立 flag</Button>
  ├ <RolloutCard/>                     // data-doc="rollout"
  │   ├ <FlagName/> <Badge ai>rolling release</Badge>
  │   ├ <Button sec>批准下一階段</Button> <Button danger>中止</Button>
  │   ├ <Steps/>                       // 5 段：done/done/cur/pending/pending
  │   └ <RolloutSummary/>              // cohort・錯誤率 vs 基線・「批准動作寫審計」提示
  ├ <FlagsCard/>                       // data-doc="flags"
  │   ├ head: <TechDebtButton count={n}/>
  │   └ <IndexTable columns={[Flag, 狀態, 生命週期, 定向, 覆蓋租戶, 動作]}/>
  ├ <TargetingModal/> <AbortConfirmModal/> <CreateFlagModal/>
```

**狀態管理**：`platformFeatureFlags` `pollInterval: 60000`（狀態是推導值，不需要即時）；`platformRollout` `pollInterval: 15000`（進行中的 rollout 要看錯誤率變化）。**中止（abort）不做樂觀更新**（23 §4-5：危險動作等伺服器回應），但成功後**立即 `refetch` 全表**——因為 kill switch 會改變其他 flag 的覆蓋數顯示。

**GraphQL**
```graphql
query Releases {
  platformRollouts(state: STARTED, first: 5) {
    nodes {
      id state currentStageOrdinal
      featureFlag { id key name }
      cohortTarget { summary matchedShops }
      stages { ordinal percentage state approvedBy { name } metricsSnapshot { errorRate baseline samples } }
    }
  }
  platformFeatureFlags(first: 100) {
    nodes {
      id key state lifecycle kind
      targeting { summary }            # "cohort：beta 名單 42 家" / "全部租戶"
      coverage { shops percent }       # 42 / 25
      codeRefCount
    }
    pageInfo { hasNextPage endCursor }
  }
}
mutation AbortRollout($id: ID!, $reason: String!) {
  platformRolloutAbort(id: $id, reason: $reason) {
    rollout { id state abortedAt }
    featureFlag { id key state coverage { shops percent } }
    userErrors { field message code }
  }
}
```

**TS 型別（狀態與生命週期為 union，不用 string）**
```ts
type FlagState = "New" | "Active" | "Launched" | "Inactive";                    // 33 §2.11 4 態
type FlagLifecycle = "Live" | "ReadyForCodeRemoval" | "ReadyToArchive"
                   | "Deprecated" | "Archived";                                  // 33 §2.11
type RolloutState = "Configured" | "Started" | "Completed" | "Aborted";
```
> 狀態 badge 配色沿用原型 `flagRows` 的三元式：`Active → info`、`Launched → success`、其餘（`New`／`Inactive`）→ 無色 default（23 §1 語意色對）。生命週期欄用 `.sub` 灰字，不搶視覺。

**三態**
- **載入**：兩張卡各自 skeleton；`Steps` 用灰色骨架 5 段。
- **空**：`rollout` → 「目前沒有進行中的分階段發布」＋「建立 rollout」CTA；`flags` → 「尚未建立任何 flag」＋說明「flag 在 `config/feature_flags.yml` 宣告後由 CI 同步」。
- **錯**：紅 banner ＋ 重試。**特別規則**：kill switch 的 mutation 失敗必須用 **紅色 Banner 而非 toast**——toast 2.6 秒就消失（23 §3），事故當下漏看等於以為關掉了。

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279 | flag 表 `min-width:max-content` ＋橫捲；步驟軸維持橫排 |
| ≤1023 | 卡頭的「批准／中止」按鈕組換行到第二列（`card-head` `flex-wrap`）；步驟軸開始出現橫捲 |
| ≤767 | flag 表轉 `.card-table` 堆疊卡片，`data-label` 為「狀態／生命週期／定向／覆蓋租戶」；**步驟軸換行**（`.steps{gap:6px 0}`、`.step-line{min-width:10px}`，CSS 已定義）；中止確認 modal 轉貼底 sheet；`.modal-foot .btn{flex:1}` |
| ≤429 | `.page-actions{width:100%}` ＋按鈕 `flex:1`；「覆蓋租戶」欄位在堆疊卡中改為「42 家（25%）」單行；`RolloutSummary` 的三段資訊改為三行 |

**a11y**：步驟軸每一步 `aria-current="step"`（當前階段）＋文字狀態，不只靠 `.cur` 的顏色；「中止」按鈕 `aria-describedby` 指向「此操作會立即回滾至 0%，無法復原」說明；switch 型控件（若定向 modal 用到）`role="switch" aria-checked`（對照原型 `defaultflags` 的實作）。

---

## 環境與備份（波次 W4）

### 1. 這是什麼、給誰用、解決什麼問題

**是什麼**：企業方案租戶的**環境模型**（production／staging／preview）、**備份與自助還原**、**版本部署與回滾**三件事，加上一條寫在頁首的安全預設宣告（原型 `envrule` note）。上游模型：SFCC 的 code deployment（保留 10 版、Transfer→Publish）、Adobe Commerce Cloud 的 snapshot（還原耗時估算）、Saleor Cloud 的環境（還原後停 webhook／app）——33 §2.12。

**給誰用**：
- 企業方案租戶的技術窗口（透過商家後台的「環境」分頁，資料源同此頁）。
- 平台 `ops`：排 sync、看誰的備份太大、執行還原。
- `owner`：production 還原這種不可逆操作的最終核准。

**解決什麼問題**：
1. **33 §7-3 明列的差異化**：「Adobe 的 Pro 環境有備份卻**不給自助還原**（要開工單），Medusa 才剛做到 export/import」——自助還原是我們的賣點，但自助的前提是**使用者知道要等多久**（硬要求 4）。一個沒有耗時估算的還原按鈕，會讓人在 3 小時的還原中途以為當機而重按。
2. **「還原資料」與「回滾程式」是兩件事**。原型 `envrule` 寫死：「備份含 DB＋媒體、**不含程式碼**（程式碼在 git，還原資料與回滾程式是兩件事）」。混為一談會造成「還原了資料庫但 schema 版本對不上」的災難。
3. **非正式環境是資料外洩與誤發信的第一大源頭**。所以三件事是**預設而非選項**（DOCS `envrule`）：關閉對外 email、擋搜尋引擎、還原後自動停用 webhook／app。
4. **production 直接改的誘惑**。SFCC 的解法：production 只准寫 inactive 版本再切換（Transfer → Publish 兩段式）——把「部署」與「生效」拆開，讓回滾變成一次切換而不是一次重新部署。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `envrule`（頁首 info note） | 宣告三個安全預設與備份範圍 | 原文（原型寫死）：「非正式環境**預設**：關閉對外 email、擋搜尋引擎、還原後自動停用 webhook／app（Saleor 做法）。備份含 DB＋媒體、**不含程式碼**」——33 §2.12 | 這是**規範文字不是提示**：三個預設在建立環境時即寫入 `shop_environments`，UI 上對 `staging/preview` **禁止關閉**（toggle 為 disabled ＋ tooltip 說明）；要關必須 `owner` 走 API 並填理由（**待定，需使用者確認是否允許**） |
| `envlist`（環境表：環境／型別／Region／版本／狀態／最後活動／動作） | 環境索引 | 卡片欄位對照 33 §2.12：`name/type/region/status/last activity`；動作 `Branch / Merge / Sync / Redeploy`（同節）。**環境數是計費維度**（同節）。原型列：`n25-select / production｜production｜ap-northeast-1｜v2026.08.1｜運行中｜3 分鐘前`、`pr-482｜preview｜…｜branch m6/editor｜運行中｜22 分鐘前` | 型別 badge 配色（原型）：`production → critical`、`staging → warning`、`preview → info`。preview 環境的「版本」欄顯示 branch 名而非版本號。**建立環境會影響帳單** → 建立 modal 必須顯示新增後的月費差額（金額 integer cents，顯示 `HK$1,480` tabular-nums<!-- 依 2026-08-12 基準法域＝香港裁定修正，原文：NT$1,480 -->）。刪除環境 → 備份**寬限 7 天**（33 §2.12）後才真刪，UI 顯示倒數 |
| `envlist` 的「Sync」動作 | 從上游環境同步資料下來 | Sync ＝ 把 production 的 DB＋媒體複製到 staging／preview | Sync **等同一次還原**：三個安全預設全部生效（含停用 webhook／app），且同樣顯示耗時估算。Sync 到 production **一律禁止**（`userErrors code: CANNOT_SYNC_TO_PRODUCTION`） |
| `backups`（備份卡：每日自動＋手動快照，含「還原」鈕） | 備份清單 | 卡頭寫死「每日自動・**保留 7 天**（14 天＋PITR 為加價檔）」——33 §2.12「保留 7 天為業界基準線」。原型列：「n25-select production｜每日自動・08-11 03:00・**42.8 GB**｜保留至 08-18」。實作：每日全量 `mysqldump --single-transaction` ＋ binlog 連續歸檔（11 §2-6） | **「還原」鈕必開確認 modal 並顯示估算耗時**（硬要求 4）——原型 toast 已寫明「42.8GB ≈ 45 分鐘」。備份大小 0／進行中的備份 → 「還原」disabled。跨環境還原（把 production 備份還原到 staging）＝允許；把 staging 備份還原到 production ＝**禁止**（`userErrors code: RESTORE_DOWNGRADE_BLOCKED`） |
| 還原確認 modal（硬要求 4） | 顯示：來源備份、目標環境、資料量、**估算耗時**、三個副作用清單、輸入環境名確認 | 估算函式見 §6.1（Adobe 基準 60GB≈1h／150GB≈2.5h／200GB+≈5h，33 §2.12）；顯示規則「無條件進位到 5 分鐘」（由原型 42.8GB→45 分鐘反推）。副作用清單：①**webhook 訂閱自動停用**②app／整合 token 自動停用③非正式環境的對外 email 維持關閉 | 估算為「單一數字」而非區間，直到累積足夠實測（校準見 §6.2）。>200GB 時附註「超出基準區間，實際可能更久」。還原中：整個環境列鎖定、顯示進度與**已耗時 vs 估算**對照條；還原失敗 → 環境維持還原前狀態（**待定，需使用者確認**：是否支援還原中止／快照回退） |
| `deploys`（版本與回滾卡） | 版本清單＋「回滾」鈕 | 卡頭寫死「**保留 10 版**・production 只准寫 inactive 再切換」——33 §2.12（SFCC 預設 10，可設 3–20）。原型列：`v2026.08.1（active）｜08-05 發布・目前生產版本`／`v2026.07.4｜07-22 發布・可一鍵回滾`／`v2026.07.3｜07-08 發布`。**Transfer → Publish 兩段式**；**active 與前一版永不清**（同節） | 「回滾」鈕只出現在**前一版**（原型 `deployRows` 的 `i===1` 判斷）。回滾 ＝ 一次 Publish 切換（不重新 build）。保留數超過上限時，清理**跳過** active 與 active 前一版。回滾與資料還原是**獨立操作**，UI 上不得放在同一顆按鈕 |
| 升級（33 §2.12，原型未出控件） | patch／minor／major 三種節奏 | **patch 全自動／minor 租戶自選時機／major 手動遷移**；**不可跳版**，升級路徑由平台計算；每租戶顯示支援狀態四態（**Maintained／Extended support／Security fixes only／EOL**）——33 §2.12 | **原型無此區塊**，本手冊視為 W4 的第二批（見 §8 步驟 11）。minor 的「租戶自選時機」與維護視窗共用同一套排程與 webhook 暫停語意（可靠性模組 §6.1） |

---

### 3. 資料模型

> 環境／備份屬於**租戶資源**（企業方案租戶自己的環境），**必須帶 `shop_id` 且複合索引 `shop_id` 前導**。只有 `platform_releases`（平台版本本身）是平台域表。

```ruby
create_table :shop_environments do |t|
  t.bigint   :shop_id, null: false
  t.string   :name, null: false                  # "production" / "staging" / "pr-482"
  t.integer  :env_type, null: false              # enum: production / staging / preview
  t.string   :region, null: false, default: "ap-northeast-1"
  t.string   :git_branch                         # 分支對映式（33 §2.12）；preview 綁 PR 分支
  t.bigint   :active_release_id                  # → platform_releases
  t.bigint   :staged_release_id                  # Transfer 完成、尚未 Publish 的版本（SFCC 兩段式）
  t.integer  :status, null: false, default: 0    # provisioning/running/restoring/deploying/suspended/deleting
  t.datetime :last_activity_at
  # 三個安全預設（33 §2.12；非正式環境預設 true，UI 對 staging/preview 禁止關閉）
  t.boolean  :block_outbound_email, null: false, default: true
  t.boolean  :block_search_engines, null: false, default: true
  t.boolean  :disable_webhooks_after_restore, null: false, default: true
  t.decimal  :monthly_price_cents_placeholder     # 佔位：環境數是計費維度（33 §2.12），實際計價待 W2 計費引擎
  t.datetime :deleted_at
  t.datetime :backups_purge_after                # 環境刪除後備份寬限 7 天（33 §2.12）
  t.timestamps
end
add_index :shop_environments, %i[shop_id name], unique: true
add_index :shop_environments, %i[shop_id env_type status]
add_index :shop_environments, %i[shop_id last_activity_at]

create_table :environment_backups do |t|
  t.bigint   :shop_id, null: false
  t.references :shop_environment, null: false, foreign_key: true
  t.integer  :kind, null: false, default: 0      # daily_auto / manual_snapshot / pre_restore（還原前自動快照）
  t.integer  :state, null: false, default: 0     # running / ready / failed / expired / purged
  t.bigint   :db_bytes,    null: false, default: 0
  t.bigint   :media_bytes, null: false, default: 0   # 備份含 DB＋媒體、不含程式碼（33 §2.12）
  t.string   :db_object_key                      # 物件儲存位置（mysqldump.gz）
  t.string   :media_manifest_key                 # 媒體清單（增量引用，不重複複製）
  t.string   :binlog_position                    # PITR 用（11 §2-6 binlog 連續歸檔）
  t.datetime :taken_at, null: false
  t.datetime :retain_until, null: false          # 預設 taken_at + 7 天（33 §2.12；14 天為加價檔）
  t.string   :checksum_sha256, null: false
  t.timestamps
end
add_index :environment_backups, %i[shop_id shop_environment_id taken_at], name: "idx_backup_recent"
add_index :environment_backups, %i[shop_id retain_until]

create_table :restore_runs do |t|
  t.bigint   :shop_id, null: false
  t.references :environment_backup, null: false, foreign_key: true
  t.references :target_environment, null: false, foreign_key: { to_table: :shop_environments }
  t.integer  :state, null: false, default: 0     # queued/restoring_db/restoring_media/post_actions/succeeded/failed
  t.bigint   :total_bytes, null: false
  t.integer  :estimated_minutes, null: false     # 送出當下的估算值（硬要求 4）——回填校準的樣本
  t.integer  :estimate_model_version, null: false
  t.integer  :actual_seconds
  t.json     :phase_durations                    # {db: 1820, media: 640, post: 45}
  t.json     :post_actions_result                # {webhooks_disabled: 12, apps_disabled: 3}
  t.references :requested_by, foreign_key: { to_table: :platform_staffs }
  t.text     :failure_reason
  t.timestamps
end
add_index :restore_runs, %i[shop_id created_at]
add_index :restore_runs, %i[shop_id state]

# 估算模型（平台域表，無 shop_id——校準曲線是全平台共用）
create_table :restore_estimate_models do |t|
  t.integer :version, null: false
  t.json    :anchors, null: false                # [[0,0],[60,60],[150,150],[200,300]]（GB, 分鐘）33 §2.12
  t.integer :sample_n, null: false, default: 0
  t.string  :source, null: false                 # "adobe_baseline" / "fitted"
  t.datetime :fitted_at
end
add_index :restore_estimate_models, :version, unique: true

# 平台版本（平台域表，無 shop_id——版本是全平台共用的程式碼構建物）
create_table :platform_releases do |t|
  t.string   :version, null: false               # "v2026.08.1"
  t.string   :commit_sha, null: false
  t.integer  :semver_kind, null: false           # patch / minor / major（33 §2.12 三種節奏）
  t.integer  :state, null: false, default: 0     # building / built / transferred / published / superseded / purged
  t.datetime :built_at
  t.datetime :published_at
  t.boolean  :protected, null: false, default: false  # active 與前一版永不清（33 §2.12）
  t.timestamps
end
add_index :platform_releases, :version, unique: true
add_index :platform_releases, %i[state published_at]

# 逐租戶支援狀態（33 §2.12 四態）
create_table :shop_support_statuses do |t|
  t.bigint  :shop_id, null: false
  t.bigint  :platform_release_id, null: false
  t.integer :level, null: false                  # maintained / extended_support / security_fixes_only / eol
  t.datetime :eol_at
  t.timestamps
end
add_index :shop_support_statuses, %i[shop_id level]
```

---

### 4. API 契約（Platform:: GraphQL）

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformEnvironments(shopId, first, after)` | query | cursor ≤250 | `ShopEnvironmentConnection{ nodes { id name envType region gitBranch activeRelease { version } status lastActivityAt safeDefaults { blockOutboundEmail blockSearchEngines disableWebhooksAfterRestore } } }` | — | 全部 |
| `platformEnvironmentCreate(shopId!, name!, envType!, region, gitBranch)` | mutation | 環境數是計費維度 → payload 回 `billingDelta: MoneyV2` | `{ environment, billingDelta, userErrors }` | `NAME_TAKEN`／`ENV_QUOTA_EXCEEDED`（走配額三段式，見「平台設定」§6.2）／`PLAN_NOT_ELIGIBLE` | **待定**；建議 `admin+`（動到計費） |
| `platformEnvironmentSync(sourceId!, targetId!)` | mutation | Branch/Merge/Sync/Redeploy 四動作之一 | `{ restoreRun, estimatedMinutes, userErrors }` | `CANNOT_SYNC_TO_PRODUCTION`／`SOURCE_BUSY` | **待定**；建議 `ops+` |
| `platformEnvironmentDelete(id!, confirmName!)` | mutation | 需輸入環境名（對照 32 §5 危險動作慣例） | `{ deletedId, backupsPurgeAfter, userErrors }` | `NAME_MISMATCH`／`CANNOT_DELETE_PRODUCTION` | **待定**；建議 `owner` |
| `platformBackups(shopId, environmentId, first, after)` | query | — | `EnvironmentBackupConnection{ nodes { id kind takenAt dbBytes mediaBytes totalBytes retainUntil state } }` | — | 全部 |
| `platformBackupCreate(environmentId!, note)` | mutation | 手動快照 | `{ backup, userErrors }` | `BACKUP_IN_PROGRESS`／`STORAGE_QUOTA_EXCEEDED` | 建議 `ops+` |
| **`platformRestoreEstimate(backupId!, targetEnvironmentId!)`** | **query** | **硬要求 4：對話框開啟時呼叫** | `{ totalBytes, estimatedMinutes, modelVersion, modelSource, band { p50Minutes p90Minutes } }`（`band` 校準前為 null） | — | 全部（唯讀估算不需高權限） |
| `platformRestoreStart(backupId!, targetEnvironmentId!, confirmName!, acknowledgePostActions!)` | mutation | `acknowledgePostActions` 必為 true（使用者已看過「將停用 webhook／app」） | `{ restoreRun, userErrors }` | `NAME_MISMATCH`／`POST_ACTIONS_NOT_ACKNOWLEDGED`／`RESTORE_DOWNGRADE_BLOCKED`／`TARGET_BUSY`／`BACKUP_EXPIRED` | **待定**；建議：非 production `ops+`；**production 需 `owner` ＋四眼**（對照 32 §5 金流變更慣例） |
| `platformRestoreRun(id)` | query | 進度輪詢 | `{ state phase progressPercent elapsedSeconds estimatedMinutes postActionsResult }` | — | 全部 |
| `platformReleases(first, after)` | query | — | `PlatformReleaseConnection{ nodes { id version semverKind state publishedAt protected } }` | — | 全部 |
| `platformReleaseTransfer(environmentId!, releaseId!)` | mutation | 兩段式第一段：寫入 inactive slot | `{ environment, userErrors }` | `ALREADY_STAGED`／`BUILD_NOT_READY` | 建議 `ops+` |
| `platformReleasePublish(environmentId!, releaseId!)` | mutation | 兩段式第二段：切換 active | `{ environment, previousRelease, userErrors }` | `NOT_STAGED`（production 只准寫 inactive 再切換）／`SKIP_VERSION_BLOCKED`（不可跳版） | **待定**；建議 production `admin+` |
| `platformReleaseRollback(environmentId!)` | mutation | 一鍵回滾至前一版；冪等 | `{ environment, rolledBackTo, userErrors }` | `NO_PREVIOUS_RELEASE` | 同 Publish |
| `platformUpgradePlan(shopId!, targetVersion!)` | query | 平台計算升級路徑（不可跳版） | `{ steps [{ version semverKind requiresMaintenanceWindow }], totalEstimatedMinutes }` | — | 全部 |

> **金額欄位**：`billingDelta` 走 `MoneyV2{amount: Decimal, currencyCode}`（28 §0.3），內部仍 integer cents。

---

### 5. 服務物件與背景任務

| 類別 | 職責 | 觸發 |
|---|---|---|
| `Platform::Environments::RestoreEstimator` | 依資料量算耗時（§6.1） | 同步（query） |
| `Platform::Environments::EstimateCalibratorJob` | 用 `restore_runs` 實測值重擬合模型（§6.2） | recurring 每週日 |
| `Platform::Environments::RestoreOrchestrator` | 還原編排：pre_restore 快照 → DB → 媒體 → **post actions** | job（長任務切階段自排下一棒，18 F5-2） |
| `Platform::Environments::PostRestoreActions` | **停用 webhook 訂閱／app token**、套用安全預設（§6.3） | 由 orchestrator 呼叫 |
| `Platform::Environments::DailyBackupJob` | `mysqldump --single-transaction` ＋媒體 manifest ＋ checksum | recurring 每日 03:00（原型備份時間戳） |
| `Platform::Environments::BackupPurgeJob` | `retain_until` 到期清理；**環境刪除後寬限 7 天** | recurring 每日 |
| `Platform::Environments::BackupDrillJob` | **每季還原演練**（11 §2-6：「沒演練過的備份等於沒有備份」） | recurring 每季 |
| `Platform::Deploys::TransferService` / `PublishService` / `RollbackService` | 兩段式部署與回滾 | 同步（mutation）＋ job |
| `Platform::Deploys::ReleasePruneJob` | 保留 10 版；跳過 `protected`（active 與前一版） | 每次 publish 後 |
| `Platform::Upgrades::PathPlanner` | 計算不可跳版的升級路徑；標記需要維護視窗的步驟 | 同步 |
| `Platform::Upgrades::PatchAutoApplyJob` | patch 全自動套用 | recurring 每日 |

---

### 6. 關鍵流程與演算法

#### 6.1 還原耗時估算函式（硬要求 4）

**基準資料**（33 §2.12，Adobe Commerce Cloud）：60GB≈1h、150GB≈2.5h、200GB+≈5h。
換算成分鐘與速率：60GB/60min ＝ **1.0 GB/min**；150GB/150min ＝ **1.0 GB/min**；200GB/300min ＝ 0.667 GB/min。
→ 曲線是**分段線性**：0–150GB 斜率 1.0 分鐘/GB；150–200GB 斜率 (300−150)/(200−150) ＝ **3.0 分鐘/GB**（大於 150GB 後每 GB 貴三倍——符合直覺：超過某個量之後 IO 與索引重建成為瓶頸）。

**顯示規則驗證**：原型 toast「42.8GB ≈ 45 分鐘」。42.8 × 1.0 ＝ 42.8 分鐘，**無條件進位到 5 分鐘** ＝ 45。✅ 模型與原型自洽，且進位規則自然產生 5 分鐘下限（不需要額外定義最小值）。

```ruby
# app/services/platform/environments/restore_estimator.rb
module Platform
  module Environments
    # 還原耗時估算。硬要求 4：還原對話框必須顯示依資料量估算的耗時。
    #
    # 基準來自 33 §2.12（Adobe Commerce Cloud 實務值）：
    #   60GB ≈ 1h / 150GB ≈ 2.5h / 200GB+ ≈ 5h
    # 反推得分段線性：0–150GB 斜率 1.0 min/GB；150–200GB 斜率 3.0 min/GB。
    # 進位到 5 分鐘的規則由原型「42.8GB ≈ 45 分鐘」反推驗證（42.8 → 45）。
    #
    # 為什麼一定要顯示：自助還原（33 §7-3 的差異化賣點）若不告知耗時，
    # 使用者會在 3 小時的還原中途以為卡住而重按或聯絡客服——把差異化變成客訴來源。
    class RestoreEstimator
      GB = 1024.0**3
      ROUND_TO_MINUTES = 5

      # @param total_bytes [Integer] DB + 媒體（不含程式碼——程式碼在 git，33 §2.12）
      # @return [Integer] 估算分鐘數
      def self.minutes_for(total_bytes, model: EstimateModel.current)
        gb = total_bytes / GB
        raw = interpolate(gb, model.anchors)
        (raw / ROUND_TO_MINUTES.to_f).ceil * ROUND_TO_MINUTES
      end

      # 分段線性內插；超出最後一個 anchor 時以最後一段斜率外推。
      # 為什麼外推而不是「200GB 以上一律 5h」：33 寫的是「200GB+≈5h」，
      # 但 500GB 顯然不會也是 5h；平坦外推會嚴重低估並在 UI 上失信。
      # 超出基準區間時 UI 另加註記（見 §2 還原 modal）。
      def self.interpolate(gb, anchors)
        anchors.each_cons(2) do |(x1, y1), (x2, y2)|
          return y1 + (gb - x1) * (y2 - y1) / (x2 - x1) if gb <= x2
        end
        (x1, y1), (x2, y2) = anchors[-2], anchors[-1]
        y2 + (gb - x2) * (y2 - y1) / (x2 - x1)
      end

      # 校準後才提供區間；校準前只給單一數字（見 §6.2）。
      def self.band_for(total_bytes, model: EstimateModel.current)
        return nil unless model.fitted?
        Calibration.percentile_band(total_bytes, model)   # { p50Minutes:, p90Minutes: }
      end
    end
  end
end
```

**估算值的三個組成（UI 上要分行顯示，讓人知道時間花在哪）**：
| 階段 | 佔比來源 | 說明 |
|---|---|---|
| DB 還原 | `db_bytes` 走上述曲線 | mysqldump 匯入＋索引重建，主要成本 |
| 媒體還原 | `media_bytes` 走同一曲線（**待定，需使用者確認**：媒體是物件複製，理論上比 DB 快，但 33 未給分開的基準值） | 若日後量測出媒體較快，`anchors` 拆成兩組 |
| Post actions | 固定 1 分鐘（**待定**） | 停用 webhook／app、套安全預設，時間與資料量無關 |

#### 6.2 量測與校準（硬要求 4 下半）

```ruby
# app/jobs/platform/environments/estimate_calibrator_job.rb
class Platform::Environments::EstimateCalibratorJob < ApplicationJob
  queue_as :low
  MIN_SAMPLES = 5           # 樣本數門檻：待定，需使用者確認
  MAX_SLOPE_DRIFT = 0.25    # 每次重擬合斜率變動上限 ±25%：待定，需使用者確認

  # 為什麼要校準：Adobe 的基準是「別人的機器、別人的資料形狀」。
  # 我們的 MySQL 8 + 物件儲存 + region 組合，實際速率必然不同。
  # 為什麼要限制單次漂移：一次 IO 異常的還原（例如同時在跑 binlog 歸檔）會把曲線帶歪，
  # 用中位數 + 漂移上限做穩健化，避免估算值在兩週間劇烈跳動而失去可信度。
  def perform
    runs = RestoreRun.succeeded.where(created_at: 90.days.ago..).to_a
    return if runs.size < MIN_SAMPLES

    current = EstimateModel.current
    fitted  = current.anchors.map do |gb, minutes|
      bucket = runs.select { |r| in_bucket?(r, gb) }
      next [gb, minutes] if bucket.size < MIN_SAMPLES
      observed = median(bucket.map { |r| r.actual_seconds / 60.0 })
      [gb, clamp(observed, minutes)]     # 漂移上限
    end

    EstimateModel.create!(version: current.version + 1, anchors: fitted,
                          sample_n: runs.size, source: "fitted", fitted_at: Time.current)
  end

  def clamp(observed, baseline)
    lo, hi = baseline * (1 - MAX_SLOPE_DRIFT), baseline * (1 + MAX_SLOPE_DRIFT)
    observed.clamp(lo, hi).round
  end
end
```

**量測點**：`RestoreOrchestrator` 在每個階段結束時寫 `restore_runs.phase_durations`，結束時寫 `actual_seconds`。**估算送出時的 `estimated_minutes` 與 `estimate_model_version` 一併存下**——這讓我們能回答「當時我們說 45 分鐘，實際 62 分鐘，用的是哪版模型」，這是校準能持續改善的前提。
**UI 回饋**：還原進度條同時顯示「已耗時 18 分 / 估算 45 分」；超過估算 120% 時進度條轉黃並顯示「比估算久，仍在進行中」（**120% 為待定，需使用者確認**）——比默默超時好得多。

#### 6.3 還原後的自動停用（硬要求 4 第三項）

```ruby
# app/services/platform/environments/post_restore_actions.rb
module Platform
  module Environments
    # 還原完成後的強制副作用。33 §2.12（Saleor 做法）：
    #   非正式環境預設「關閉對外 email、擋搜尋引擎、還原後自動停用 webhook／app」。
    #
    # 本手冊把「還原後停用 webhook／app」擴大到 **所有環境型別**（含 production），理由：
    #   還原會把備份時點的 webhook 訂閱與 app token 一併帶回來，其中可能包含
    #   ①已被租戶刪除的訂閱 ②已輪換的 secret ③備份時點之後才失效的端點。
    #   直接恢復投遞 = 對舊端點重放歷史事件（與可靠性模組硬要求 1 同一類事故）。
    # production 的此開關 **不可關閉**（UI force-locked），非正式環境亦預設 true。
    # 註：33 原文只把此規則綁在「非正式環境預設」，本擴大解釋為推論——待使用者確認。
    class PostRestoreActions
      def initialize(run:) = @run = run

      def call
        env  = @run.target_environment
        shop = env.shop
        result = { webhooks_disabled: 0, apps_disabled: 0 }

        ActsAsTenant.with_tenant(shop) do
          # 1. 停用 webhook 訂閱（不是刪除——租戶要能看到「這些被停用了，請確認後重新啟用」）
          result[:webhooks_disabled] =
            WebhookSubscription.where(shop_id: shop.id, status: :active)
                               .update_all(status: :disabled_after_restore, updated_at: Time.current)

          # 2. 停用 app / 整合 token（clat_ 長效 token，28 §0.2）
          result[:apps_disabled] =
            AccessToken.where(shop_id: shop.id, revoked_at: nil)
                       .update_all(suspended_at: Time.current, updated_at: Time.current)

          # 3. 非正式環境的另外兩個安全預設（重申，因為備份可能來自 production）
          unless env.production?
            env.update!(block_outbound_email: true, block_search_engines: true)
          end

          # 4. 還原帶進來的 outbox 舊事件一律標 expired，不投遞。
          #    為什麼：這些事件在備份時點就已經投過了；再投一次就是重放。
          EventsOutbox.where(shop_id: shop.id, status: :pending)
                      .update_all(status: :expired, updated_at: Time.current)
        end

        @run.update!(post_actions_result: result)
        # 外部 IO（通知信）在 transaction 外（鐵律）
        Platform::Notifier.restore_completed(@run, result)
        result
      end
    end
  end
end
```

> `update_all` 會跳過 callback 與 `updated_at`（11 §3 坑）——所以上面每一處都手動補 `updated_at`。

#### 6.4 Transfer → Publish 兩段式與回滾

```
build（CI）→ platform_releases.state = built
   ↓ platformReleaseTransfer            寫入 environment.staged_release_id（inactive slot）
transferred
   ↓ platformReleasePublish             檢查：staged 存在？不可跳版？→ 原子切換 active_release_id
published（前一版標 protected，倒數第三版起才進 prune 候選）
   ↓ platformReleaseRollback            active ⇄ previous 對調（不重新 build，秒級）
```

**三條硬規則**：
1. **production 只准寫 inactive 再切換**（33 §2.12）：`PublishService` 若發現 `staged_release_id.nil?` → `userErrors code: NOT_STAGED`，**不提供「直接 publish」捷徑**。
2. **不可跳版**（33 §2.12）：`PathPlanner` 計算 `active → target` 的版本序列，若中間有 major 未套用 → `SKIP_VERSION_BLOCKED` 並回傳建議路徑。
3. **保留 10 版且 active 與前一版永不清**（33 §2.12）：`ReleasePruneJob` 的 SQL 一律 `WHERE protected = false AND id NOT IN (active, previous)`。

**升級節奏**（33 §2.12）：
| 類型 | 節奏 | 維護視窗 |
|---|---|---|
| patch | **全自動** | 不需要（除非含 DDL） |
| minor | **租戶自選時機** | 需要 → 走可靠性模組 §6.1 的維護視窗（含 webhook 暫停） |
| major | **手動遷移** | 需要 ＋ 逐租戶溝通（走公告模組） |

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本／用途 | 為何選它 |
|---|---|---|
| `mysqldump --single-transaction` | 每日全量備份（11 §2-6） | InnoDB 一致性快照且不鎖表；已在 11 定案不另選 |
| MySQL binlog 歸檔 | PITR（11 §2-6；33 §2.12「14 天＋PITR 為加價檔」） | 7 天保留是基準檔用全量即可；PITR 是加價檔的差異化功能 |
| 物件儲存（S3 相容） | 備份與媒體 | 備份不含程式碼（33 §2.12），只有 dump 與媒體；媒體用 manifest 增量引用避免重複複製 |
| `strong_migrations` | 上線後 DDL 安全（11 §2-5） | 升級路徑含 DDL 時，minor 升級必須先過 online DDL 檢查 |
| Kamal | 部署與滾動重啟（11 §1-1） | 已定案；`ReleasePublish` 對映 Kamal 的流量切換 |
| Solid Queue（`low` 佇列） | 備份、還原、prune 全部長任務 | 鐵律不用 Redis；長任務切階段自排下一棒（18 §F5-2：單任務 <60s） |
| `aws-sdk-s3`（或相容 client） | 物件操作與 multipart | 備份檔可達數十 GB，必須 multipart ＋ checksum |
| **不引入**專用備份 SaaS | — | 33 §7-3 的差異化是「自助還原」，把備份外包給第三方會讓「顯示估算耗時」與「還原後停 webhook」這兩個硬要求失去控制點 |

---

### 8. 實作步驟（順序化 todo）

1. 建表（五張＋`restore_estimate_models` seed 一列 `version: 1, anchors: [[0,0],[60,60],[150,150],[200,300]], source: "adobe_baseline"`）。
2. `RestoreEstimator`（純函式）＋ spec，**用原型的 42.8GB → 45 分鐘當第一條測試**。
3. `DailyBackupJob`（dump ＋ 媒體 manifest ＋ checksum ＋ `retain_until = taken_at + 7.days`）。
4. `BackupPurgeJob`（含環境刪除後寬限 7 天的分支）。
5. `shop_environments` CRUD ＋ 三個安全預設（建立時寫入，`staging/preview` 不可關閉）。
6. `RestoreOrchestrator`（分階段 job，每階段回寫 `phase_durations`）。
7. **`PostRestoreActions`**（停 webhook／app／expire outbox／重申安全預設）——與可靠性模組的 `EventsOutbox` 狀態機對齊。
8. `platformRestoreEstimate` query ＋ 還原確認 modal（**這一步就要能顯示估算**，不要等到最後）。
9. `EstimateCalibratorJob` ＋ `restore_runs` 回填。
10. `platform_releases` ＋ Transfer／Publish／Rollback／Prune。
11. 升級三節奏 ＋ `PathPlanner` ＋ 四態支援狀態（**原型無對應控件，需先與使用者確認 UI 位置**）。
12. `BackupDrillJob`（每季還原演練——11 §9 checklist 有「備份還原演練過」一項，必須是自動化的，不能靠人記得）。
13. 前端（§11）。

---

### 9. 測試清單

```
spec/services/platform/environments/restore_estimator_spec.rb
  - 42.8 GB → 45 分鐘（原型 toast 的錨點）              ← 硬要求 4
  - 60 GB → 60 分鐘 / 150 GB → 150 分鐘 / 200 GB → 300 分鐘（33 §2.12 三個基準）
  - 0.1 GB → 5 分鐘（進位規則自然產生下限）
  - 300 GB → 外推 600 分鐘（不平坦）
  - 使用 fitted 模型時取新 anchors；band_for 在未校準模型回 nil

spec/jobs/platform/environments/estimate_calibrator_job_spec.rb
  - 樣本 < MIN_SAMPLES 不建新模型
  - 中位數擬合；單一極端值不會讓斜率漂移超過 ±25%
  - 新模型 version 遞增且 source == "fitted"

spec/services/platform/environments/post_restore_actions_spec.rb
  - 還原後所有 active webhook_subscriptions → disabled_after_restore   ← 硬要求 4
  - 還原後所有未撤銷 access_tokens → suspended_at 有值
  - 還原帶進來的 pending outbox → expired（不投遞；WebMock 斷言 0 次 HTTP）
  - production 環境同樣停用（force-locked 不可關）
  - staging 環境的 block_outbound_email / block_search_engines 被重新設為 true
  - update_all 有補 updated_at（11 §3 坑）

spec/services/platform/environments/restore_orchestrator_spec.rb
  - 還原前自動建立 pre_restore 快照
  - phase_durations 三階段都有值；actual_seconds 寫回
  - 失敗時 target_environment 狀態回到 running（不卡在 restoring）

spec/requests/platform/graphql/restores_spec.rb
  - acknowledgePostActions: false → POST_ACTIONS_NOT_ACKNOWLEDGED（HTTP 200）
  - confirmName 不符 → NAME_MISMATCH
  - staging 備份還原到 production → RESTORE_DOWNGRADE_BLOCKED
  - 過期備份 → BACKUP_EXPIRED
  - platformRestoreEstimate 不需寫入權限即可呼叫（read_only 可用）

spec/services/platform/deploys/publish_service_spec.rb
  - 未 Transfer 直接 Publish → NOT_STAGED（production 只准寫 inactive 再切換）
  - 跳版 → SKIP_VERSION_BLOCKED，回傳建議路徑
  - Publish 後前一版 protected == true
  - Rollback 冪等：連呼兩次結果相同，只有一列審計

spec/jobs/platform/deploys/release_prune_job_spec.rb
  - 保留 10 版；第 11 版起清理
  - active 與前一版即使超出保留數也不清（protected）

spec/jobs/platform/environments/backup_purge_job_spec.rb
  - retain_until 到期 → purged
  - 環境已刪除 → 寬限 7 天後才清（33 §2.12）

spec/system/platform/envs_spec.rb
  - 快樂路徑：點「還原」→ modal 顯示「42.8 GB・約 45 分鐘」＋三條副作用 → 輸入環境名 → 進度條
  - 三態：載入 skeleton／無環境空態／查詢失敗 banner
```

---

### 10. 驗收清單

- [ ] **硬要求 4**：還原 modal 一定顯示估算耗時（無估算即擋下送出）；估算函式通過 33 §2.12 三個基準與原型 42.8GB 錨點；`restore_runs` 記錄估算與實際供校準；校準 job 有測試。
- [ ] **硬要求 4 續**：還原後 webhook 訂閱與 app token 全部停用，且有測試證明 0 次 HTTP 投遞。
- [ ] **33 §2.12 逐條**：保留 7 天 ✓／備份含 DB＋媒體不含程式碼 ✓（備份物件內無 `app/`、`Gemfile`）／環境刪除後寬限 7 天 ✓／保留 10 版且 active 與前一版永不清 ✓／production 只准寫 inactive 再切換 ✓／Transfer→Publish ✓／一鍵 Rollback ✓／patch 自動 minor 排程 major 手動 ✓／四態支援狀態 ✓／非正式環境三個安全預設 ✓。
- [ ] **11 §2-6**：每日全量 ＋ binlog 歸檔可用；**每季還原演練是自動化 job 且有告警**。
- [ ] **11 §9 checklist**：「備份還原演練過」一項有機器可驗的證據（`BackupDrillJob` 最近一次成功時間 < 100 天）。
- [ ] **11 §5**：還原 job 的結構化日誌帶 `shop_id` 與 `restore_run_id`；還原失敗上報 Sentry 專屬告警。
- [ ] **鐵律**：`shop_environments`／`environment_backups`／`restore_runs`／`shop_support_statuses` 複合索引 `shop_id` 前導；`platform_releases`／`restore_estimate_models` 在 migration 檔頭註明平台域表豁免。
- [ ] `billingDelta` 走 MoneyV2，內部 integer cents，UI 顯示 `NT$` ＋ tabular-nums。

---

### 11. 前端（React/TS）

**元件樹**
```
<EnvsPage>
  ├ <PageHead title="環境與備份" sub="企業方案租戶・W4 波次"/>
  ├ <SafeDefaultsNote/>                // data-doc="envrule"（note note-info，非可關閉提示）
  ├ <EnvironmentsCard/>                // data-doc="envlist"
  │   └ <IndexTable columns={[環境, 型別, Region, 版本, 狀態, 最後活動, 動作]}/>
  │       └ <EnvActionsMenu/>          // Branch / Merge / Sync / Redeploy
  ├ <TwoCol>
  │   ├ <BackupsCard/>                 // data-doc="backups"；MiniList + RestoreButton
  │   └ <DeploysCard/>                 // data-doc="deploys"；MiniList + RollbackButton（僅前一版）
  ├ <RestoreConfirmModal/>             // ★ 硬要求 4 的主角
  ├ <RestoreProgressDrawer/>  <CreateEnvModal/>  <DeleteEnvModal/>
```

**`<RestoreConfirmModal>` 規格（逐項）**
```tsx
/**
 * 還原確認對話框。硬要求 4：必須顯示依資料量估算的耗時。
 * 開啟時立即呼叫 platformRestoreEstimate（不等使用者操作），估算未回來前
 * 主按鈕維持 disabled + 「計算中…」——絕不讓人在不知道要等多久的情況下按下去。
 */
<Modal width={520} destructive>
  <Head>還原環境</Head>
  <Body>
    <DL>
      <dt>來源備份</dt><dd>n25-select production・每日自動・08-11 03:00</dd>
      <dt>目標環境</dt><dd>n25-select / staging <Badge warning>staging</Badge></dd>
      <dt>資料量</dt><dd className="num">42.8 GB<span className="sub">（DB 38.1 GB ＋ 媒體 4.7 GB・不含程式碼）</span></dd>
      <dt>預估耗時</dt><dd className="num strong">約 45 分鐘</dd>   {/* estimatedMinutes */}
    </DL>
    <Note warn title="還原後將自動執行">
      <li>停用全部 webhook 訂閱（{n} 個）——需人工確認後重新啟用</li>
      <li>停用全部 app／整合 token（{m} 個）</li>
      <li>維持關閉對外 email 與搜尋引擎索引（非正式環境預設）</li>
    </Note>
    <Checkbox required>我了解上述副作用</Checkbox>
    <Input label="輸入環境名稱以確認" placeholder="n25-select / staging"/>
  </Body>
  <Foot><Button sec>取消</Button><Button crit disabled={!ready}>開始還原</Button></Foot>
</Modal>
```

**狀態管理**：`platformEnvironments` ＋ `platformBackups` ＋ `platformReleases` 一個 query 打包，`pollInterval: 30000`。**還原進行中時**改為 `platformRestoreRun` `pollInterval: 5000` 並在頁面頂部掛 `<RestoreProgressDrawer>`（不阻擋其他操作，但目標環境列鎖定）。進度條顯示「已耗時 / 估算」雙數字。

**GraphQL**
```graphql
query RestoreEstimate($backupId: ID!, $targetId: ID!) {
  platformRestoreEstimate(backupId: $backupId, targetEnvironmentId: $targetId) {
    totalBytes estimatedMinutes modelVersion modelSource
    band { p50Minutes p90Minutes }        # 校準前為 null
    breakdown { dbBytes mediaBytes postActionMinutes }
    postActionsPreview { webhookSubscriptions appTokens }
  }
}
mutation StartRestore($backupId: ID!, $targetId: ID!, $name: String!) {
  platformRestoreStart(backupId: $backupId, targetEnvironmentId: $targetId,
                       confirmName: $name, acknowledgePostActions: true) {
    restoreRun { id state estimatedMinutes }
    userErrors { field message code }
  }
}
```

**三態**
- **載入**：環境表 skeleton 4 列；備份卡 skeleton 3 列；**估算未回來時 modal 顯示「計算預估耗時…」的 inline skeleton**（不是整個 modal 空白）。
- **空**：無環境 → 「此租戶尚未建立環境」＋「新增環境」CTA ＋ 一句「環境數是計費維度」；無備份 → 「首次備份將於今晚 03:00 執行」。
- **錯**：估算 query 失敗 → modal 內紅字「無法計算預估耗時，請重試」＋**主按鈕維持 disabled**（硬要求 4：沒有估算就不准還原）。

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279 | 環境表橫捲（7 欄放不下）；`.two-col`（備份／版本）維持兩欄 |
| ≤1023 | `.two-col` 塌成單欄；環境表動作欄改為 icon-only menu（含 `aria-label`） |
| ≤767 | 環境表轉 `.card-table` 堆疊卡（`data-label`：型別／Region／版本／狀態／最後活動）；**還原 modal 轉貼底 sheet**，`modal-foot` sticky ＋ 兩顆按鈕 `flex:1`；`.dl` 兩欄改 `100px 1fr`（≤1023）→ 單欄（≤429） |
| ≤429 | `.page-actions{width:100%}`；`<DL>` 單欄（`dt` 12px 灰字在上、`dd` 在下）；資料量與預估耗時仍**同屏可見**（不得被摺疊到需捲動才看得到——這是硬要求 4 的驗收點） |

**a11y**：進度條 `role="progressbar" aria-valuenow/aria-valuemin/aria-valuemax` ＋文字「已耗時 18 分，預估 45 分」；destructive modal 主按鈕焦點**不自動聚焦**（避免 Enter 誤觸），初始焦點落在確認輸入框；環境型別除色票外必附文字 badge。

---

## 公告與棄用通知（波次 W3）

### 1. 這是什麼、給誰用、解決什麼問題

**是什麼**：兩張卡。上卡「公告」＝分眾／排程／已讀追蹤（33 §6 `announcements(audience_query, schedule, read_receipts)`）；下卡「API 版本與棄用」＝版本支援期表 ＋ 影響面（多少 app／整合在用）＋ **逐租戶 API health report**（DOCS `deprecation`：「這是唯一被驗證能大規模推動升級的做法（Shopify）」）。

**給誰用**：`admin`（發公告）、產品／DevRel（管版本棄用）、`support`（查「這家店收到過什麼公告、讀了沒」）。

**解決什麼問題**：
1. **全站廣播是垃圾訊息製造機**。1,284 家店裡只有 37 家字軌快用完（原型 `ANN` 第二列），對其他 1,247 家發這則公告會訓練他們忽略所有公告。所以分眾條件（方案／地區／GMV／flag cohort，DOCS `announcements`）是必需品不是加分項。
2. **維護視窗預告要有地方發**。可靠性模組的 `MaintenanceWindow` 在 `starts_at − 72h` 建立的公告，就走這條管線（原型 `ANN` 第一列與 `ovMaint` 的 72 小時勾選互相對應）。
3. **API 版本棄用推不動**。單純寄信沒用；Shopify 的做法是**告訴每家租戶「你自己踩到哪些棄用欄位」**——具體、可行動、無法辯解。這需要在 GraphQL 層做欄位級用量歸因。
4. **已讀率是唯一能證明「我們通知過了」的證據**。棄用爭議、維護造成的損失爭議，最後都會回到「你有沒有通知我」。`read_receipts` 是法務資產。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| 「建立公告」（page-actions） | 分眾／排程／已讀追蹤三件事 | 原型 toast：「建立公告——分眾／排程／已讀追蹤」 | 建立流程三步：①內容（標題／正文／嚴重度）②受眾（條件建構器＋即時預覽命中數）③排程（立即／指定時間／相對於某事件前 N 小時）。**受眾預覽的命中數必須與實際發送數一致**（同一 resolver，數字同源鐵律） |
| `announcements`（公告表：標題／受眾／排程／狀態／已讀率） | 公告索引 | 原型三列：`8/18 維護視窗預告｜全部租戶｜08-15 09:00 發送｜已排程｜—`／`電子發票字軌即將用罄提醒｜字軌餘量 <15% 的 37 家｜已發送 08-10｜已發送｜68%`／`結帳 v3 beta 招募｜GMV ≥ NT$1M／月・186 家｜已發送 08-06｜已發送｜54%`。分眾條件可用**方案／地區／GMV／flag cohort**（DOCS `announcements`） | 狀態 badge：`已發送 → success + pip full`；`已排程 → info + pip half`（原型 `annRows` 三元式）。已排程者已讀率顯示 `—`。**受眾條件在排程時「凍結」還是「發送時重算」？** 本手冊採**發送時重算**（例：08-15 發送時字軌 <15% 的可能已變成 41 家），並在列表顯示「預估 37 家 / 實發 41 家」。**此決策 33 未寫，待定，需使用者確認** |
| 公告詳情（點列） | 分眾條件／排程／已讀追蹤明細 | 原型 toast：「公告詳情——分眾條件／排程／已讀追蹤」 | 已讀明細表：商店／送達時間／已讀時間／通路（站內／email）。已讀率分母 ＝ **送達數**不是命中數（送達失敗的不計入分母，否則信箱壞掉的租戶會拉低數字並誤導判斷） |
| `deprecation`（API 版本與棄用卡） | 版本支援期與影響面 | 卡頭寫死「**季度發版・每版至少支援 12 個月・相鄰版重疊 9 個月**（Shopify 模型）」。原型四列：`2026-10（unstable）｜開發中｜—`／`2026-07（stable，目前預設）｜支援至 2027-07｜864 個 app／整合`／`2026-04（stable）｜支援至 2027-04｜311 個`／`2026-01（stable，即將終止）｜支援至 2027-01・剩 5 個月｜88 個・已寄棄用通知` | **與 28 §0.1 的首版 `2026-08` 衝突**（季度發版應為 01/04/07/10）——見附錄 A 衝突 C1。剩餘月數 ≤6 → 該列轉黃；≤3 → 轉紅並自動排公告（門檻 **待定，需使用者確認**）。「已寄棄用通知」為狀態標記，需連到寄送紀錄 |
| API health report（卡底 info note） | 逐租戶告知踩到哪些棄用欄位 | 原文（原型寫死）：「每租戶提供 **API health report**：告訴他們自己踩到哪些棄用欄位——這是唯一被驗證能大規模推動升級的做法（Shopify）」 | 報告頻率 **待定，需使用者確認**（建議每月 1 日寄出，且棄用版本剩 ≤3 個月時改每週）。**報告內容含租戶自己的欄位使用明細＝PII 邊界內**（是他們自己的資料，可寄給他們；但不得跨租戶比較） |

---

### 3. 資料模型

```ruby
# 平台域表（無 shop_id）——公告本身是平台發出的一則訊息
create_table :platform_announcements do |t|
  t.string   :title, null: false
  t.text     :body_html, null: false             # Liquid 沙箱渲染（18 §F2）；變數限白名單 Drop
  t.integer  :severity, null: false, default: 0  # info / warning / critical
  t.integer  :category, null: false, default: 0  # maintenance / deprecation / feature / compliance / billing
  t.json     :audience_query, null: false        # 33 §6：audience_query（條件 DSL，見 §6.1）
  t.integer  :state, null: false, default: 0     # draft / scheduled / sending / sent / cancelled
  t.datetime :scheduled_at
  t.datetime :sent_at
  t.integer  :estimated_recipients                # 排程當下的預估命中數
  t.integer  :actual_recipients                   # 發送時重算的實際數
  t.json     :channels, null: false               # ["in_app", "email"]
  t.references :created_by, null: false, foreign_key: { to_table: :platform_staffs }
  t.bigint   :maintenance_window_id               # 維護視窗預告（可靠性模組 §6.1）
  t.timestamps
end
add_index :platform_announcements, %i[state scheduled_at]

# 收件端：帶 shop_id（鐵律：複合索引 shop_id 前導）
create_table :announcement_recipients do |t|
  t.bigint   :shop_id, null: false
  t.references :platform_announcement, null: false, foreign_key: true
  t.integer  :state, null: false, default: 0     # queued / delivered / bounced / read / dismissed
  t.datetime :delivered_at
  t.datetime :read_at                            # 33 §6：read_receipts
  t.string   :read_channel                       # in_app / email_pixel / api
  t.bigint   :read_by_staff_id                   # 商家端哪位 staff 讀的（商家域 staff，非 platform_staffs）
  t.timestamps
end
add_index :announcement_recipients, %i[shop_id platform_announcement_id], unique: true, name: "idx_ar_dedupe"
add_index :announcement_recipients, %i[shop_id state], name: "idx_ar_unread"
add_index :announcement_recipients, %i[platform_announcement_id state], name: "idx_ar_readrate"

# API 版本（平台域表）
create_table :platform_api_versions do |t|
  t.string   :handle, null: false                # "2026-07"
  t.integer  :stability, null: false             # unstable / release_candidate / stable
  t.date     :released_on
  t.date     :supported_until                    # 每版至少支援 12 個月（DOCS deprecation）
  t.boolean  :default_version, null: false, default: false
  t.timestamps
end
add_index :platform_api_versions, :handle, unique: true

create_table :api_deprecations do |t|            # schema 上被 @deprecated 標記的欄位（28 §0.1）
  t.string   :field_path, null: false            # "Order.totalPrice" / "productVariantUpdate.input.sku"
  t.string   :reason, null: false                # @deprecated(reason:)
  t.string   :replacement
  t.string   :introduced_in                      # 哪一版開始標棄用
  t.string   :removed_in                         # 哪一版移除（nil = 未定）
  t.timestamps
end
add_index :api_deprecations, :field_path, unique: true

# 逐租戶棄用欄位命中（health report 的資料源）——帶 shop_id，前導索引
create_table :api_deprecation_hits_daily do |t|
  t.bigint  :shop_id, null: false
  t.date    :on_date, null: false
  t.string  :api_version, null: false
  t.string  :field_path, null: false
  t.bigint  :count, null: false, default: 0
  t.string  :sample_client                       # User-Agent 摘要，幫租戶定位是哪支整合（不含 token）
  t.datetime :last_seen_at, null: false
end
add_index :api_deprecation_hits_daily,
          %i[shop_id on_date api_version field_path], unique: true, name: "idx_adhd_uniq"
add_index :api_deprecation_hits_daily, %i[shop_id on_date], name: "idx_adhd_shop_date"
```

---

### 4. API 契約（Platform:: GraphQL）

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformAnnouncements(first, after, state, category)` | query | cursor ≤250 | `AnnouncementConnection{ nodes { id title severity category audienceSummary state scheduledAt sentAt estimatedRecipients actualRecipients readRate } }` | — | 全部 |
| `platformAnnouncementAudiencePreview(audienceQuery!)` | query | **與實際發送共用同一 resolver**（數字同源） | `{ matchedShops, sample: [Shop!]! (前 10 筆) }` | — | 全部 |
| `platformAnnouncementCreate(input!)` | mutation | `{title!, bodyHtml!, severity, category, audienceQuery!, channels!, scheduledAt}` | `{ announcement, estimatedRecipients, userErrors }` | `AUDIENCE_QUERY_INVALID`／`LIQUID_SYNTAX_ERROR`（模板儲存時即 parse，18 §F2-3）／`SCHEDULE_IN_PAST` | **待定**；建議 `admin+` |
| `platformAnnouncementUpdate(id, ...)` | mutation | 僅 `draft`／`scheduled` 可改 | `{ announcement, userErrors }` | `ALREADY_SENT` | 同上 |
| `platformAnnouncementCancel(id!, reason!)` | mutation | 僅 `scheduled` 可取消 | `{ announcement, userErrors }` | `ALREADY_SENT`／`REASON_REQUIRED` | 同上 |
| `platformAnnouncementSendNow(id!)` | mutation | 冪等（重複呼叫不重發） | `{ announcement, actualRecipients, userErrors }` | `ALREADY_SENT` | 同上 |
| `platformAnnouncementRecipients(id!, first, after, state)` | query | 已讀明細 | `RecipientConnection{ nodes { shop { id name } state deliveredAt readAt readChannel } }` | — | 全部 |
| `platformApiVersions` | query | — | `[ApiVersion{ handle stability releasedOn supportedUntil monthsRemaining defaultVersion integrationsCount }]` | — | 全部 |
| `platformApiVersionSetSupportWindow(handle!, supportedUntil!)` | mutation | 調整支援期 | `{ apiVersion, userErrors }` | `WINDOW_TOO_SHORT`（< 12 個月，DOCS `deprecation`）／`OVERLAP_TOO_SHORT`（相鄰版重疊 < 9 個月） | **待定**；建議 `owner` |
| `platformApiHealthReport(shopId!, range)` | query | 逐租戶 health report | `{ shop, apiVersion, deprecatedFields [{ fieldPath reason replacement hits lastSeenAt sampleClient }], upgradeBlockers }` | — | 全部；**同一 resolver 亦供商家後台**（租戶看自己的） |
| `platformApiHealthReportSend(shopIds: [ID!], apiVersion)` | mutation | 批次寄送 | `{ queuedCount, userErrors }` | `NO_DEPRECATED_USAGE`（該店沒踩到，不寄） | **待定**；建議 `admin+` |

---

### 5. 服務物件與背景任務

| 類別 | 職責 | 觸發 |
|---|---|---|
| `Platform::Announcements::AudienceResolver` | `audience_query` DSL → `shop_id` 集合；**預覽與發送共用** | 同步 |
| `Platform::Announcements::DispatchJob` | 到排程時間 → 重算受眾 → 批次建 `announcement_recipients` → 逐店丟 `DeliverJob` | recurring 每分鐘 |
| `Platform::Announcements::DeliverJob` | 站內通知＋email（走 18 §F2 Liquid 沙箱與 §F3 壓制表） | 由 dispatch 排入 |
| `Platform::Announcements::ReadReceiptRecorder` | 站內已讀（API 呼叫）／email 開信 pixel | 同步 |
| `Platform::Api::DeprecationRecorder` | GraphQL 執行期記錄 `@deprecated` 欄位命中（進程內聚合，同 flag 模式） | GraphQL instrumentation |
| `Platform::Api::HealthReportJob` | 每月／每週寄逐租戶報告 | recurring |
| `Platform::Api::VersionSunsetJob` | 支援期剩 N 個月 → 自動排公告 | recurring 每日 |

---

### 6. 關鍵流程與演算法

#### 6.1 分眾（audience_query DSL）

```ruby
# app/services/platform/announcements/audience_resolver.rb
module Platform
  module Announcements
    # 受眾解析器。預覽與實際發送**共用這一個類**——
    # 為什麼：原型公告表同時顯示「37 家」與已讀率，若預覽與發送各寫一套查詢，
    # 兩個數字必然在某次改動後分岔（CLAUDE.md §7 數字同源鐵律）。
    #
    # DSL（JSON）：{ all: [...] } / { any: [...] }，葉節點形如
    #   { plan_in: ["omo_master","strategist"] }
    #   { region_in: ["TW","JP"] }
    #   { gmv_30d_cents_gte: 100_000_00 }        ← 金額 integer cents（鐵律）
    #   { flag_cohort: "checkout_v3" }           ← 直接復用發布模組的 cohort（DOCS announcements）
    #   { einvoice_track_remaining_pct_lt: 15 }  ← 原型第二列的條件（33 §2.14 的 15% 門檻）
    #   { status_in: ["active","trial"] }
    #   { shop_ids: [1,2,3] }
    class AudienceResolver
      MAX_PREVIEW_SAMPLE = 10

      def initialize(query) = @query = query.deep_symbolize_keys

      # @return [ActiveRecord::Relation<Shop>]
      def relation
        ActsAsTenant.without_tenant { compile(@query, Shop.all) }
      end

      def count = relation.count
      def sample = relation.limit(MAX_PREVIEW_SAMPLE).to_a

      private

      def compile(node, scope)
        return node[:all].reduce(scope) { |s, c| compile(c, s) } if node[:all]
        return scope.where(id: node[:any].flat_map { |c| compile(c, Shop.all).ids }.uniq) if node[:any]
        leaf(node, scope)
      end

      # 白名單編譯：每個 key 對應一段寫死的 scope，**絕不把使用者輸入拼進 SQL**
      #（11 §1「白名單欄位編譯 SQL 防注入」；32 §3-2 同一原則）
      def leaf(node, scope)
        key, value = node.first
        case key
        when :plan_in    then scope.where(plan_key: Array(value))
        when :region_in  then scope.where(region_code: Array(value))
        when :status_in  then scope.where(status: Array(value))
        when :shop_ids   then scope.where(id: Array(value))
        when :gmv_30d_cents_gte
          # 走 rollup 不即時算（避免全表掃 orders；與 KPI 同源，32 §8）
          scope.joins(:latest_rollup).where("platform_daily_rollups.gmv_30d_cents >= ?", value.to_i)
        when :flag_cohort
          scope.where(id: Platform::Flags::Coverage.shop_ids_for(value))
        when :einvoice_track_remaining_pct_lt
          scope.joins(:einvoice_track).where("einvoice_tracks.remaining_pct < ?", value.to_i)
        else raise ArgumentError, "unsupported audience key: #{key}"
        end
      end
    end
  end
end
```

**發送時重算 vs 排程時凍結**：本手冊採**發送時重算**，列表同時顯示「預估 37 / 實發 41」。理由：分眾條件多半是動態的（字軌餘量、GMV 級距），排程時凍結會漏掉三天內新符合條件的租戶。**此決策 33 未寫，待定，需使用者確認**。**例外**：`maintenance` 類公告一律「全部租戶」，不受此影響。

**發送冪等**：`announcement_recipients` 的 `idx_ar_dedupe`（`shop_id + announcement_id` 唯一）保證重複執行 dispatch 不會重寄（11 §3 三板斧之唯一索引）。`DispatchJob` 用 `insert_all(..., unique_by:)` 批次寫入，衝突略過。

#### 6.2 已讀追蹤

| 通路 | 記錄方式 | 可靠度 |
|---|---|---|
| 站內通知 | 商家後台開啟公告 → `announcementRead(id)` mutation | 高（明確動作） |
| Email | 追蹤 pixel（18 §F3 有「開信（P1 pixel）」的既有設計） | 低（圖片封鎖普遍）——**只當補充，不當主指標** |
| API | 租戶用 API 拉取公告後標讀 | 高 |

**已讀率分母 ＝ `delivered`（不含 `bounced`）**。`bounced` 走 18 §F3 的 `email_suppressions` 壓制表，並在公告詳情頁單列「送達失敗 N 家」——這幾家要走工單而不是被算進未讀率。

#### 6.3 API 棄用欄位命中記錄（health report 的資料源）

```ruby
# app/graphql/platform/deprecation_recorder.rb
module Platform
  module Api
    # GraphQL 執行期的棄用欄位命中記錄器。
    #
    # 為什麼用「進程內聚合 + 定時 flush」而不是每次命中寫 DB：
    #   與 flag evaluation 完全同一個理由（發布模組 §6.2）——這是熱路徑，
    #   每次 resolver 命中就 INSERT 會吃掉連線池。
    # 為什麼不能取樣：health report 要對租戶說「你用了 Order.totalPrice 共 18,402 次」，
    #   取樣後的數字無法對帳，租戶會質疑報告可信度。聚合是精確的。
    #
    # 掛在 GraphQL::Schema 的 field instrumentation 上，只對帶 @deprecated 的欄位生效
    # （沒標棄用的欄位完全零成本——不進 buffer、不做 hash 計算）。
    class DeprecationRecorder
      FLUSH_INTERVAL = 60.seconds

      def initialize = @buffer = Concurrent::Map.new  # { [shop_id, api_version, field_path] => {count:, ua:} }

      def record(shop_id:, api_version:, field_path:, user_agent:)
        @buffer.compute([shop_id, api_version, field_path]) do |v|
          v ||= { count: 0, ua: user_agent }
          v.merge(count: v[:count] + 1)
        end
      end

      def flush!
        rows = drain.map do |(shop_id, ver, path), v|
          { shop_id:, on_date: Date.current, api_version: ver, field_path: path,
            count: v[:count], sample_client: v[:ua]&.truncate(120), last_seen_at: Time.current }
        end
        return if rows.empty?
        ApiDeprecationHitDaily.upsert_all(
          rows, unique_by: :idx_adhd_uniq,
          on_duplicate: Arel.sql("count = count + VALUES(count), last_seen_at = VALUES(last_seen_at)")
        )
      end
    end
  end
end
```

**回應 header**：除 28 §0.1 既有的 `X-CL-API-Version` 外，命中棄用欄位時另加 `X-CL-API-Deprecated-Reason`（值為該請求命中的棄用欄位摘要，長度上限 512 字元），讓整合商在開發時就看得到，不必等月報。**此 header 為 28 的擴充，待定，需使用者確認**。

#### 6.4 版本支援期與棄用排程

規則（DOCS `deprecation`）：**季度發版**、**每版至少支援 12 個月**、**相鄰版重疊 9 個月**。

```
2026-01  released ─────────────── supported_until 2027-01
2026-04       released ─────────────── 2027-04     重疊 = 2026-04 ~ 2027-01 = 9 個月 ✅
2026-07            released ─────────────── 2027-07
2026-10                 released ─────────────── 2027-10
```
`platformApiVersionSetSupportWindow` 的驗證：`supported_until − released_on >= 12.months`（否則 `WINDOW_TOO_SHORT`）且 `previous.supported_until − self.released_on >= 9.months`（否則 `OVERLAP_TOO_SHORT`）。

`VersionSunsetJob`（每日）：某版剩餘 ≤6 個月 → 對**該版仍有流量的租戶**排公告（`audience_query: {all:[{api_version_in:["2026-01"]}]}`，需在 DSL 增一個 leaf）；剩 ≤3 個月 → health report 由月報改週報。**6／3 兩個月數為建議值，33 未給，待定，需使用者確認**。

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本／用途 | 為何選它 |
|---|---|---|
| `liquid` gem（MIT，CLAUDE.md §9 允許） | 公告正文模板（變數如 `{{ shop.name }}`、`{{ maintenance.starts_at }}`） | 與通知信同一套沙箱（18 §F2）；**必須用白名單 Drop**，絕不把 AR 物件丟進 context |
| `premailer-rails` | email 版公告的 CSS inline（18 §F2-4） | 已在 18 定案 |
| Resend／SES（既有） | email 通路；bounce/complaint webhook → `email_suppressions`（18 §F3-3） | 公告是行銷型還是交易型？**維護／棄用類屬交易型**（不可退訂）、**功能招募類屬行銷型**（必附 List-Unsubscribe，18 §F3-2）。此分類需在 `category` 上強制 |
| `graphql-ruby` 的 field instrumentation | 棄用欄位命中記錄 | 官方機制，零額外依賴；只對 `@deprecated` 欄位生效 |
| Solid Queue recurring | `DispatchJob`（每分鐘）、`HealthReportJob`、`VersionSunsetJob` | 鐵律不用 Redis |
| **不引入** Customer.io／Braze 這類訊息 SaaS | — | 分眾條件要查 `shops`／`platform_daily_rollups`／flag cohort，把租戶商業資料同步到第三方是合規負擔（33 §2.13 台灣個資辦法：平台須訂定守則並要求租戶遵守），且分眾預覽與發送必須同源 |

---

### 8. 實作步驟（順序化 todo）

1. 建表五張（`platform_announcements`／`announcement_recipients`／`platform_api_versions`／`api_deprecations`／`api_deprecation_hits_daily`）。
2. `AudienceResolver`（白名單編譯，先寫注入測試）。
3. `platformAnnouncementAudiencePreview` query ＋ 條件建構器前端（**先做預覽再做發送**，否則沒法驗證分眾對不對）。
4. `DispatchJob` ＋ `DeliverJob` ＋ 冪等（`insert_all unique_by`）。
5. 站內通知的商家端 API（`announcementRead`）＋ 商家後台的通知中心（跨模組，需與商家後台團隊對齊）。
6. Email 通路 ＋ 交易型／行銷型分流 ＋ 壓制表檢查。
7. 已讀率彙總（`idx_ar_readrate` 索引 ＋ counter cache 或每分鐘 rollup——避免每次列表都 `COUNT`）。
8. 維護視窗自動排公告（接可靠性模組 §6.1 的 `scheduled` 轉移）。
9. `api_deprecations` 由 schema 自動同步（CI job 讀 `@deprecated(reason:)` → upsert，同 flag code scan 的模式）。
10. `DeprecationRecorder` instrumentation ＋ flush。
11. `platformApiHealthReport` query ＋ 商家後台的自助頁面（33 §7-4「租戶端透明」的同一精神）。
12. `HealthReportJob`／`VersionSunsetJob`。
13. 前端兩張卡（§11）。

---

### 9. 測試清單

```
spec/services/platform/announcements/audience_resolver_spec.rb
  - 每個 leaf 各一條：plan_in / region_in / status_in / shop_ids / gmv_30d_cents_gte /
    flag_cohort / einvoice_track_remaining_pct_lt
  - all / any 巢狀組合
  - 未知 key → ArgumentError（不得靜默忽略導致發給全部租戶）  ← 這是最危險的失敗模式
  - 注入嘗試：value 帶 "1) OR 1=1--" → 以參數綁定處理，結果為空集合
  - preview.count 與 dispatch 實際建立的 recipient 數一致（同源）

spec/jobs/platform/announcements/dispatch_job_spec.rb
  - 到排程時間才發；未到不發
  - 重複執行不重複建 recipient（唯一索引兜底）
  - 發送時重算受眾：排程後新符合條件的租戶會收到；estimated 與 actual 都被記錄
  - maintenance 類公告受眾恆為全部租戶
  - bounced 的 email 不計入已讀率分母

spec/services/platform/announcements/deliver_job_spec.rb
  - Liquid 模板語法錯誤在 **儲存時** 就被擋（18 §F2-3），不留到寄信時炸
  - 惡意模板（億次迴圈／巨輸出）被 resource limits 擋下（18 §F2-2）
  - 行銷型公告含 List-Unsubscribe header；交易型不含
  - 命中 email_suppressions 的收件者不寄 email 但仍建站內通知

spec/graphql/platform/api/deprecation_recorder_spec.rb
  - 命中 @deprecated 欄位才記錄；未標棄用的欄位 buffer 為空（零成本斷言）
  - flush 產生 UPSERT 且同 (shop,date,version,field) 累加
  - sample_client 不含 token（PII/密鑰過濾，11 §5-1）

spec/requests/platform/graphql/api_versions_spec.rb
  - supported_until 少於 12 個月 → WINDOW_TOO_SHORT（HTTP 200）
  - 相鄰版重疊少於 9 個月 → OVERLAP_TOO_SHORT
  - platformApiHealthReport 只回該租戶自己的資料（跨租戶洩漏測試）

spec/system/platform/announcements_spec.rb
  - 快樂路徑：建立 → 條件建構器即時顯示命中數 → 排程 → 列表出現「已排程」
  - 三態：載入／無公告空態／查詢錯誤 banner
```

---

### 10. 驗收清單

- [ ] **數字同源**：`platformAnnouncementAudiencePreview` 的命中數與 `DispatchJob` 建立的 recipient 數，在同一時刻查詢必須一致（自動化測試）。
- [ ] **11 §7 合規**：公告 email 的行銷型必附退訂並寫回 consent；`announcement_recipients` 含商家 staff id → 列入 PII 清單；purge 任務有涵蓋（保留期 **待定，需使用者確認**）。
- [ ] **18 §F2**：公告正文走 Liquid 白名單 Drop 沙箱；儲存時 parse；resource limits ＋ 3s timeout。
- [ ] **18 §F3**：壓制表生效；bounce 不計入已讀率分母。
- [ ] **11 §5**：`DeliverJob` 失敗有 Sentry 專屬告警；`DispatchJob` 為 recurring，漏跑有 heartbeat 檢查（18 §F5-3）。
- [ ] **11 §4**：公告列表的已讀率不得對 `announcement_recipients` 做即時 `COUNT` 全掃（`EXPLAIN` 驗證走 `idx_ar_readrate` 或 counter cache）。
- [ ] **33 §5** 相關：維護視窗預告在 `starts_at − 72h` 自動排程並可在此頁看到（跨模組整合測試）。
- [ ] DOCS `deprecation` 三條數值（季度發版／12 個月支援／9 個月重疊）在 mutation 層有驗證。
- [ ] 逐租戶 API health report 可產出且**只含該租戶自己的資料**（跨租戶洩漏測試通過）。
- [ ] 每則公告的建立／排程／取消／發送在 `platform_audit_logs` 有列（含 `previous`/`next`）。

---

### 11. 前端（React/TS）

**元件樹**
```
<AnnouncePage className="narrow">        // 原型此 view 帶 .narrow（版寬 998，23 §1）
  ├ <PageHead title="公告與棄用通知">
  │   └ actions: <Button pri>建立公告</Button>
  ├ <AnnouncementsCard/>                 // data-doc="announcements"
  │   └ <IndexTable columns={[標題, 受眾, 排程, 狀態, 已讀率]} onRowClick={openDetail}/>
  ├ <DeprecationCard/>                   // data-doc="deprecation"
  │   ├ <ApiVersionRow/>×4               // usage-row grid: 1fr 160px auto
  │   └ <Note info>每租戶提供 API health report…</Note>
  ├ <CreateAnnouncementWizard/>          // 三步：內容 → 受眾 → 排程
  ├ <AnnouncementDetailDrawer/>          // 分眾條件／排程／已讀明細
```

**`<AudienceBuilder>`（受眾條件建構器）**：`all`／`any` 群組 ＋ 葉節點下拉；**每次條件變更 debounce 400ms 後打 `platformAnnouncementAudiencePreview`**，右側常駐顯示「命中 37 家」＋前 10 筆商店名 chips。命中 0 家 → 主按鈕 disabled ＋紅字「此條件目前無任何租戶符合」。命中 ≥ 全平台 80% → 黃字提示「將發送給多數租戶，確認不需要分眾？」（80% 門檻 **待定，需使用者確認**）。

**GraphQL**
```graphql
query Announcements {
  platformAnnouncements(first: 50) {
    nodes { id title severity category audienceSummary state scheduledAt sentAt
            estimatedRecipients actualRecipients readRate }
    pageInfo { hasNextPage endCursor }
  }
  platformApiVersions {
    handle stability releasedOn supportedUntil monthsRemaining defaultVersion integrationsCount
  }
}
query AudiencePreview($q: JSON!) {
  platformAnnouncementAudiencePreview(audienceQuery: $q) { matchedShops sample { id name } }
}
```

**三態**
- **載入**：公告表 skeleton 3 列；版本卡 skeleton 4 列；受眾預覽用 inline spinner（不換整塊）。
- **空**：無公告 → 「尚未建立任何公告」＋CTA；無棄用欄位命中 → 「此租戶未使用任何已棄用欄位 ✓」（綠色，這是好消息要正面表述）。
- **錯**：紅 banner ＋重試。受眾預覽失敗 → 顯示「無法預覽受眾」且**主按鈕 disabled**（不准在不知道會發給誰的情況下送出）。

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279 | `.narrow` 版寬已限 998，此斷點基本無變化；版本卡 `usage-row` 三欄維持 |
| ≤1023 | 受眾建構器由「條件 / 預覽」兩欄改為上下堆疊，預覽區 sticky 在底部 |
| ≤767 | 公告表轉 `.card-table` 堆疊卡（`data-label`：受眾／排程／狀態／已讀率）；建立精靈的三步改為全螢幕 sheet，步驟軸換行（`.steps{gap:6px 0}`）；`usage-row` 由 `1fr 160px auto` 塌成單欄 |
| ≤429 | `.page-actions{width:100%}`；版本列的「支援至 2027-01・剩 5 個月」與整合數改為兩行；已讀率改用進度條 ＋ 百分比並排 |

**a11y**：已讀率不只用進度條顏色，附文字百分比；版本剩餘月數的黃／紅狀態附文字（「剩 5 個月」「即將終止」）；受眾預覽的命中數變動用 `aria-live="polite"` 播報（避免螢幕閱讀器使用者不知道數字變了）。

---

## 平台設定（波次：`platformdomain` M7 交付／`mailsender` M8／`defaultflags` P0／`quotapolicy` W2）

### 1. 這是什麼、給誰用、解決什麼問題

**是什麼**：四張設定卡（＋一張 W2 計費佔位，不在本段範圍）。這一頁的共同性質是：**每一項設定失效都會造成全平台級的靜默故障**——憑證過期＝全部租戶前台掛掉、DMARC 失效＝全部通知信進垃圾桶、預設 flag 設錯＝所有新店開起來就是壞的、配額政策設成 `log_only`＝超賣資源沒人擋。所以這一頁的設計原則是**每一項都要有「到期／失效」的主動告警，不能靠人記得來看**。

**給誰用**：`owner`（網域、信件、配額政策）、`admin`（預設 flags）。`support`／`ops`／`read_only` 唯讀。

**解決什麼問題**：
1. **憑證與 DNS 是「一年才動一次」的東西**，所以必然沒人記得——`platformdomain` 卡把四個網域的憑證與狀態放在同一屏，並在**到期 30 天前告警**（DOCS `platformdomain`）。
2. **信件驗證是隱形的**：SPF／DKIM／DMARC 任一失效不會報錯，只會讓送達率無聲下滑到 0。DOCS `mailsender` 的規則很硬：**任一失效 → 通知信全停並告警**。
3. **新店預設 flags 決定「開箱體驗」**，且改它**不應該回頭影響存量店**（否則等於對 1,284 家店做未經灰度的全域變更）——這一點原型沒寫，本手冊補上明確語意。
4. **配額三段式**（33 §2.10）是資源治理的骨架：`log_only`（只記錄）→ `warn`（**60% 門檻**上儀表板）→ `error`（**100% 擋下並拋例外**）；紅／橘／綠燈；**每日違規摘要 email**。

---

### 2. 畫面與控件逐項表

| 控件（data-doc key） | 功能 | 邏輯規則（含數值與出處） | 狀態／邊界情況 |
|---|---|---|---|
| `platformdomain`（平台網域卡，`dl` 四列） | 主網域／商店子網域／平台後台／狀態頁 | 原型四列：`chilllove.tw`／`{store}.mychilllove.com` ＋ **萬用憑證有效・2027-06-01 到期・自動續**／`platform.chilllove.tw` ＋ **robots noindex**（32 §0）／`status.chilllove.tw`。**憑證到期 30 天前告警**（DOCS `platformdomain`） | 萬用憑證 `*.mychilllove.com` **必須用 DNS-01 ACME 挑戰**（HTTP-01 不支援萬用字元）——與 11 §1「Kamal 部署自帶 Let's Encrypt」（kamal-proxy 走 HTTP-01 逐 host）**不相容**，見附錄 A 衝突 C4。租戶自訂網域（如 `hanami.tw`）走**逐域按需簽發**，不在此卡（在租戶詳情 `domains`）。四個網域任一 DNS 解析失敗 → 該列紅 badge ＋ 頂列橫幅 |
| `mailsender`（信件寄送卡） | 寄件網域 ＋ SPF／DKIM／DMARC 三個 badge ＋ 退信率 | 原型：`mail.chilllove.tw` ＋三個 success badge；**退信率（7 天）0.3%**。規則：**任一失效 → 通知信全停並告警**（DOCS `mailsender`）。18 §F3-5：**bounce > 5% 告警**；18 §F3-1：用子網域隔離主網域信譽 | **18 §F3-1 寫的是 `mail.chilllove.com`，原型寫 `mail.chilllove.tw`**——見附錄 A 衝突 C5。「全停」是核彈級動作 → 必須有 `owner` 專用的 break-glass 覆寫（勾選「已知風險，暫時繼續寄送」＋填理由＋全域告警＋自動 4 小時後失效；**4 小時為待定，需使用者確認**）。退信率 >5% → badge 轉黃並列出 top bounce 網域 |
| `defaultflags`（新店預設 Feature Flags 卡，4 個 switch） | 新商店的預設功能組合 | 原型四項：`liquid_engine_v2`（Liquid 相容引擎 D4）**on**／`markets_p1`（多市場多幣 29 號 P1）**on**／`einvoice_auto`（電子發票自動開立，出貨時）**on**／`ai_assistant`（後台 AI 助理 P2）**off**。「逐店可覆寫；**變更落審計**」（DOCS `defaultflags`） | **改預設值不影響存量店**（見 §6.3）——UI 上必須明講「僅套用於此後建立的商店；既有商店請用『發布與灰度』的 cohort 推送」，否則營運會誤以為按下去就全平台生效。`einvoice_auto` 的「出貨時開立」對應 33 §2.14「開立時機三選一（付款／**出貨（建議）**／收貨）」。switch 為 `role="switch" aria-checked`（原型已實作） |
| `quotapolicy`（配額 enforcement 政策卡，三列） | 三段式政策 | 原型三列（33 §2.10）：`log_only` 只記錄不干預（badge：開發環境）／`warn` 達 **60%** 上儀表板＋每日摘要 email（badge warning：生效中）／`error` 達 **100%** 擋下並回 429／userErrors（badge critical：生效中） | **「回 429／userErrors」的措辭與 28 §0.4 不一致**——見附錄 A 衝突 C6。三段可**逐環境**設定（開發環境 `log_only`）與**逐配額項**覆寫（例：`products` 用 error，`api_cost` 用 warn）。紅／橘／綠燈與每日摘要 email 為 33 §2.10 明列 |
| 配額項清單（原型未展開，來自 33 §2.10 與 22 §9.4） | 各項配額的上限與現況 | 配額量級參考（33 §2.10）：SFCC Sites 100／Catalogs 200／Custom Objects 400,000／Promotions 10,000；commercetools query fetch 500／max offset 10,000／GraphQL complexity 20,000／Stores 300,000。**我們自己的上限一律引用 `config/limits.yml`**（CLAUDE.md §6；常數表 22 §9.4：自動折扣 25／折扣碼 2,000 萬／變體 2048／選項 3／媒體 250／智慧系列 5,000／地點 10/200／CSV 15MB／描述 64KB…） | 33 §2.10 給的是**別人的量級參考**，不是我們的值——**我們自己的配額表以 `config/limits.yml` 為準**，本手冊不自創數值。逐店覆寫走 `limits_overrides`（32 §7）＋審計 |

---

### 3. 資料模型

```ruby
# 全部為平台域表（無 shop_id）——這是「平台自己」的設定；migration 檔頭須註明豁免理由
create_table :platform_domains do |t|
  t.string   :role, null: false                  # primary / store_subdomain / admin / status_page
  t.string   :host, null: false                  # chilllove.tw / *.mychilllove.com / platform.chilllove.tw / status.chilllove.tw
  t.boolean  :wildcard, null: false, default: false
  t.boolean  :robots_noindex, null: false, default: false   # platform.* 為 true（32 §0）
  t.integer  :dns_state, null: false, default: 0            # unknown/ok/misconfigured/unreachable
  t.datetime :dns_checked_at
  t.integer  :cert_state, null: false, default: 0           # none/valid/expiring/expired/failed
  t.datetime :cert_expires_at
  t.boolean  :cert_auto_renew, null: false, default: true
  t.string   :acme_challenge_kind                           # http-01 / dns-01（萬用憑證必須 dns-01）
  t.timestamps
end
add_index :platform_domains, :role, unique: true
add_index :platform_domains, :cert_expires_at              # 到期 30 天前告警的掃描索引

create_table :platform_mail_senders do |t|
  t.string   :domain, null: false                # mail.chilllove.tw
  t.string   :provider, null: false              # resend / ses
  t.integer  :spf_state,   null: false, default: 0   # unknown/pass/fail
  t.integer  :dkim_state,  null: false, default: 0
  t.integer  :dmarc_state, null: false, default: 0
  t.string   :dkim_selector, null: false
  t.datetime :checked_at
  t.decimal  :bounce_rate_7d, precision: 6, scale: 4, default: 0   # 顯示為百分比；非金額故不用 cents
  t.boolean  :halted, null: false, default: false                  # 任一失效 → 通知信全停
  t.datetime :halt_waiver_until                                    # break-glass 覆寫到期時間
  t.text     :halt_waiver_reason
  t.references :halt_waiver_by, foreign_key: { to_table: :platform_staffs }
  t.timestamps
end
add_index :platform_mail_senders, :domain, unique: true

create_table :platform_default_flags do |t|
  t.string   :flag_key, null: false              # 對應 feature_flags.key
  t.string   :variant, null: false, default: "off"
  t.integer  :position, null: false, default: 0
  t.references :updated_by, foreign_key: { to_table: :platform_staffs }
  t.timestamps
end
add_index :platform_default_flags, :flag_key, unique: true

create_table :quota_policies do |t|
  t.string   :scope, null: false, default: "global"   # global / environment:development / quota:products
  t.integer  :mode,  null: false, default: 1          # log_only / warn / error（33 §2.10 三段式）
  t.integer  :warn_threshold_pct,  null: false, default: 60    # 33 §2.10：warn 60%
  t.integer  :error_threshold_pct, null: false, default: 100   # 33 §2.10：error 100%
  t.boolean  :daily_digest, null: false, default: true         # 33 §2.10：每日違規摘要 email
  t.references :updated_by, foreign_key: { to_table: :platform_staffs }
  t.timestamps
end
add_index :quota_policies, :scope, unique: true

# 配額違規事件（帶 shop_id，前導索引）——log_only 模式下唯一的產出，也是 warn/error 的稽核軌跡
create_table :quota_violations do |t|
  t.bigint   :shop_id, null: false
  t.string   :quota_key, null: false             # products / variants_per_product / api_cost / environments…
  t.bigint   :limit_value, null: false
  t.bigint   :observed_value, null: false
  t.integer  :level, null: false                 # warn / error
  t.integer  :action_taken, null: false          # logged / warned / blocked
  t.string   :request_id                         # 11 §5-1 結構化日誌的關聯鍵
  t.datetime :occurred_at, null: false
end
add_index :quota_violations, %i[shop_id occurred_at], name: "idx_qv_shop_time"
add_index :quota_violations, %i[shop_id quota_key level], name: "idx_qv_shop_key"
```

> `shops.feature_flags JSON`／`shops.limits_overrides JSON` 為 32 §7 既有欄位，本段不重複定義；逐店 flag 覆寫的權威表是發布模組的 `shop_feature_flag_overrides`（**兩者擇一，見附錄 A 衝突 C7**）。

---

### 4. API 契約（Platform:: GraphQL）

| 操作 | 型別 | 參數 | 回傳 | userErrors code | 權限角色 |
|---|---|---|---|---|---|
| `platformDomains` | query | — | `[PlatformDomain{ role host wildcard robotsNoindex dnsState certState certExpiresAt daysUntilExpiry acmeChallengeKind }]` | — | 全部 |
| `platformDomainRecheck(role!)` | mutation | 立即重驗 DNS＋憑證 | `{ domain, userErrors }` | `CHECK_IN_PROGRESS` | 建議 `ops+`（**待定**） |
| `platformDomainCertRenew(role!)` | mutation | 手動觸發續簽 | `{ domain, userErrors }` | `RENEW_TOO_EARLY`／`ACME_FAILED`（附 detail） | 建議 `owner`（**待定**） |
| `platformMailSender` | query | — | `{ domain provider spfState dkimState dmarcState dkimSelector bounceRate7d halted haltWaiverUntil }` | — | 全部 |
| `platformMailSenderRecheck` | mutation | 立即重驗三項 DNS | `{ mailSender, userErrors }` | — | 建議 `ops+` |
| `platformMailHaltWaive(reason!, hours!)` | mutation | **break-glass**：暫時忽略「任一失效即全停」 | `{ mailSender, userErrors }` | `REASON_REQUIRED`／`HOURS_EXCEEDS_MAX`／`NOT_HALTED` | `owner` only（危險動作，二次確認＋全域告警） |
| `platformDefaultFlags` | query | — | `[DefaultFlag{ flagKey variant flag { name description } }]` | — | 全部 |
| `platformDefaultFlagSet(flagKey!, variant!)` | mutation | **只影響此後建立的商店**（§6.3） | `{ defaultFlag, affectedExistingShops: 0, userErrors }` | `FLAG_NOT_FOUND`／`FLAG_ARCHIVED` | owner／admin（原型 RM「上限覆寫／flags」） |
| `platformQuotaPolicies` | query | — | `[QuotaPolicy{ scope mode warnThresholdPct errorThresholdPct dailyDigest }]` | — | 全部 |
| `platformQuotaPolicySet(scope!, mode!, warnThresholdPct, errorThresholdPct, dailyDigest)` | mutation | 三段式（33 §2.10） | `{ policy, userErrors }` | `THRESHOLD_OUT_OF_RANGE`（warn 必須 < error，兩者 1–200）／`SCOPE_INVALID` | `owner`（**待定**；改此值影響全平台阻擋行為） |
| `platformQuotaViolations(first, after, shopId, quotaKey, level)` | query | 違規稽核 | `QuotaViolationConnection` | — | 全部 |
| `platformShopLimitsOverride(shopId!, key!, value!)` | mutation | 32 §6 既有；寫 `limits_overrides` ＋審計 | `{ shop, userErrors }` | `UNKNOWN_LIMIT_KEY`（key 必須存在於 `config/limits.yml`）／`VALUE_OUT_OF_RANGE` | owner／admin |

---

### 5. 服務物件與背景任務

| 類別 | 職責 | 觸發 |
|---|---|---|
| `Platform::Settings::DomainChecker` | DNS 解析 ＋ 憑證鏈檢查 ＋ `cert_expires_at` 回寫 | recurring 每 15 分鐘（**間隔待定，需使用者確認**） |
| `Platform::Settings::CertExpiryAlertJob` | **到期 30 天前告警**（DOCS `platformdomain`）；21／14／7／1 天遞增提醒（遞增節奏 **待定**） | recurring 每日 |
| `Platform::Settings::AcmeRenewJob` | 萬用憑證 DNS-01 續簽 | recurring 每日（到期 <30 天才動作） |
| `Platform::Settings::MailAuthChecker` | SPF／DKIM／DMARC 三筆 TXT 查詢 ＋ provider API 驗證狀態 | recurring 每 15 分鐘（**間隔待定**） |
| `Platform::Settings::MailHaltEnforcer` | 任一失效 → `halted = true`；ActionMailer interceptor 攔截所有寄送 | 由 checker 觸發 |
| `Platform::Settings::BounceRateRollupJob` | 7 天退信率（18 §F3-5：>5% 告警） | recurring 每小時 |
| `Platform::Settings::DefaultFlagsApplier` | 新店建立時把預設 flags 快照寫進該店（§6.3） | `Shop` 建立的 after_commit |
| `Platform::Quotas::Enforcer` | 三段式檢查（§6.2） | 同步，寫入路徑呼叫 |
| `Platform::Quotas::DailyDigestJob` | **每日違規摘要 email**（33 §2.10） | recurring 每日 09:00 |
| `Platform::Quotas::UsageRollupJob` | 各配額項的現用量（供儀表板紅橘綠燈） | recurring 每小時 |

---

### 6. 關鍵流程與演算法

#### 6.1 信件驗證與「任一失效 → 全停」

```ruby
# app/services/platform/settings/mail_auth_checker.rb
module Platform
  module Settings
    # SPF / DKIM / DMARC 檢查器。
    # 為什麼要主動檢查而不是等寄信失敗：DNS 記錄被誤刪不會讓寄信「失敗」，
    # 只會讓信默默進垃圾桶（18 §F3 坑：「沒設 DMARC 就大量寄 → 直接進垃圾桶且難翻身」）。
    # 送達率是累積資產，發現得晚就補不回來。
    class MailAuthChecker
      def call(sender = PlatformMailSender.sole)
        spf   = check_spf(sender.domain)
        dkim  = check_dkim(sender.domain, sender.dkim_selector)
        dmarc = check_dmarc(sender.domain)

        sender.update!(spf_state: spf, dkim_state: dkim, dmarc_state: dmarc, checked_at: Time.current)

        # DOCS mailsender：「任一失效 → 通知信全停並告警」。
        # 這是刻意的核彈級規則——寧可停寄也不要在信譽崩壞的狀態下繼續大量發信。
        # 但它同時會停掉「訂單確認信」這種商業關鍵信，所以必須配 break-glass（見 mutation）。
        failing = { spf:, dkim:, dmarc: }.select { |_, v| v == :fail }
        if failing.any? && !waived?(sender)
          sender.update!(halted: true)
          Platform::Notifier.page_oncall!(:mail_auth_failed, detail: failing.keys)
          Platform::Audit.record!(action: "mail_sender.halt", target: sender, actor: :system,
                                  source: "自動化", previous: { halted: false },
                                  next: { halted: true, failing: failing.keys })
        elsif failing.empty? && sender.halted?
          sender.update!(halted: false, halt_waiver_until: nil)
        end
        sender
      end

      # DNS TXT 查詢：三筆各自的判準
      #  SPF   : 根網域 TXT 含 "v=spf1" 且包含 provider 的 include 機制
      #  DKIM  : "#{selector}._domainkey.#{domain}" TXT 存在且公鑰與 provider 回報一致
      #  DMARC : "_dmarc.#{domain}" TXT 含 "v=DMARC1" 且 p= 非 none（p=none 視為 warn 不是 fail —— 待定，需使用者確認）
    end
  end
end
```

**攔截點**：`ActionMailer::Base.register_interceptor` 在 `halted` 時丟棄並記錄（不是 raise——raise 會讓每一支寄信 job 進 dead set，製造第二場事故）。交易信與行銷信一律都停（DOCS 寫的是「通知信全停」）。**「全停」是否包含平台自己給 `platform_staffs` 的告警信？** 本手冊實作為**不含**（告警信走另一個寄件網域或 provider 的 fallback），否則郵件掛掉時我們自己也收不到告警。**此例外 33 未寫，待定，需使用者確認**。

#### 6.2 配額三段式 enforcement（33 §2.10）

```ruby
# app/services/platform/quotas/enforcer.rb
module Platform
  module Quotas
    # 配額三段式（33 §2.10，SFCC Quota Status 模型）：
    #   log_only（只記錄）→ warn（60% 門檻上儀表板 + 每日摘要 email）→ error（100% 擋下）
    #
    # 為什麼要三段而不是單一硬限：
    #   單一硬限的體驗是「昨天還好好的，今天突然不能建商品了」。
    #   60% 的 warn 給了租戶（與我們的客服）一個月以上的緩衝去談升級方案。
    class Enforcer
      Result = Struct.new(:allowed, :level, :used_pct, :limit, keyword_init: true)

      # @param quota_key [Symbol] 對應 config/limits.yml 的 key（CLAUDE.md §6：不得硬編碼）
      # @param shop [Shop]
      # @param delta [Integer] 本次要新增的數量
      def self.check!(quota_key, shop:, delta: 1)
        limit  = Limits.for(shop, quota_key)          # limits.yml 值，再套 shops.limits_overrides（32 §7）
        used   = Usage.current(shop, quota_key)       # 走 rollup，不即時 COUNT 全表（11 §4）
        policy = Policy.resolve(quota_key, shop)      # scope 優先序：quota: > environment: > global

        after_pct = ((used + delta).to_f / limit * 100).round(2)

        level =
          if after_pct >= policy.error_threshold_pct   then :error   # 33：100%
          elsif after_pct >= policy.warn_threshold_pct then :warn    # 33：60%
          end

        record_violation!(shop, quota_key, limit, used + delta, level, policy) if level

        allowed = !(level == :error && policy.error?)
        Result.new(allowed:, level:, used_pct: after_pct, limit:)
      end

      # log_only 模式下仍然記錄——這是「先觀測再收緊」的前提資料。
      def self.record_violation!(shop, key, limit, observed, level, policy)
        action = policy.log_only? ? :logged : (level == :error && policy.error? ? :blocked : :warned)
        QuotaViolation.create!(shop_id: shop.id, quota_key: key.to_s, limit_value: limit,
                               observed_value: observed, level:, action_taken: action,
                               request_id: Current.request_id, occurred_at: Time.current)
      end
    end
  end
end
```

**擋下時回什麼**（把附錄 A 衝突 C6 的結論寫死）：

| 情境 | 回應 | 出處 |
|---|---|---|
| **entitlement 配額**（商品數、環境數、地點數…）達 100% | GraphQL **HTTP 200** ＋ `userErrors{ code: QUOTA_EXCEEDED, field, message }` | CLAUDE.md §4 鐵律：業務錯誤走 userErrors、HTTP 恆 200 |
| **API cost 限流**（28 §0.4 leaky bucket）吃滿 | GraphQL **HTTP 200** ＋ `errors[0].extensions.code = "THROTTLED"` ＋ `extensions.cost.throttleStatus` | 28 §0.4（top-level errors 承載 THROTTLED，非 userErrors） |
| **前台 Ajax 面**（買家端）限流 | **HTTP 429 ＋ `Retry-After`** | 28 §0.4 最後一條 |

> 原型 `quotapolicy` 寫「達 100% 擋下並回 **429／userErrors**」——這句合併了三種情境，實作時**必須按上表分開**，不能對 GraphQL Admin/Platform API 回 429。

**紅橘綠燈**（33 §2.10）：`< 60% 綠`／`60–99% 橘`／`≥100% 紅`。與租戶詳情 `usage` 卡（32 §3-3 寫「≥80% 黃／≥95% 紅」）**門檻不同**——見附錄 A 衝突 C8。

#### 6.3 新店預設 flags 的套用語意（原型未定義，本手冊補齊）

```ruby
# app/services/platform/settings/default_flags_applier.rb
module Platform
  module Settings
    # 新店建立時，把「當下的」預設 flags 快照寫進該店的覆寫表。
    #
    # 為什麼是「快照」而不是「即時參照預設值」：
    #   若新店的 flag 值即時參照 platform_default_flags，那麼日後改預設值
    #   就會回頭改變所有「用預設值開起來的」既有商店 —— 這是一次未經灰度的全平台變更，
    #   而灰度是「發布與灰度」模組的職責（rollout + cohort），不是設定頁的職責。
    #   兩條路徑必須分開：defaultflags = 新店初始值；rollout/cohort = 存量店推送。
    #
    # 對照 DOCS defaultflags：「逐店可覆寫；變更落審計」——覆寫的載體即此快照。
    class DefaultFlagsApplier
      def self.call(shop)
        rows = PlatformDefaultFlag.pluck(:flag_key, :variant).map do |key, variant|
          { shop_id: shop.id, flag_key: key, variant:, reason: "新店預設（快照）",
            created_at: Time.current, updated_at: Time.current }
        end
        ShopFeatureFlagOverride.insert_all(rows, unique_by: %i[shop_id flag_key]) if rows.any?
      end
    end
  end
end
```

**UI 必寫的一句話**：「此設定僅套用於**此後建立**的商店。既有 1,284 家商店請改用『發布與灰度』的 cohort 推送。」——沒有這句話，營運遲早會按錯。

#### 6.4 憑證與網域檢查

```
DomainChecker（每 15 分鐘）
  ├ DNS：A/AAAA/CNAME 解析是否指向我方（misconfigured / unreachable）
  ├ TLS：建連取憑證 → notAfter → cert_expires_at；鏈驗證失敗 → cert_state = failed
  └ robots：platform.chilllove.tw 抓 /robots.txt 驗證含 noindex（32 §9-12 驗收項）

CertExpiryAlertJob（每日）
  └ cert_expires_at - now <= 30 天 → 告警（DOCS platformdomain）
     遞增提醒 21/14/7/1 天（節奏待定，需使用者確認）

AcmeRenewJob（每日）
  └ 萬用憑證 *.mychilllove.com 必須 DNS-01：
      向 DNS provider API 寫 _acme-challenge TXT → 等傳播 → 完成挑戰 → 部署新憑證
      （HTTP-01 不支援萬用字元；與 11 §1 的 Kamal 內建續簽不相容 → 見附錄 A 衝突 C4）
```

---

### 7. 需要的工具、gem 與外部依賴

| 依賴 | 版本／用途 | 為何選它 |
|---|---|---|
| `resolv`（stdlib） | DNS TXT／A 查詢（SPF／DKIM／DMARC／`_acme-challenge`） | 無新依賴；需**指定權威 resolver 並繞過本機快取**，否則剛改的記錄查不到 |
| `acme-client` gem | ACME v2（Let's Encrypt）DNS-01 萬用憑證簽發 | 萬用憑證只能 DNS-01；kamal-proxy 的內建續簽做不到（衝突 C4）。**是否採用 acme-client 自建 vs 改用 Cloudflare／CDN 代管 TLS，待定，需使用者確認** |
| DNS provider API（Cloudflare／Route53／…） | DNS-01 挑戰寫 TXT | **供應商待定，需使用者確認**（33／11 未指定） |
| Resend／SES 的 domain verification API | 交叉驗證 SPF／DKIM 狀態（不只信 DNS 查詢） | provider 端的驗證狀態才是實際生效的判準；兩邊都查可以抓到「DNS 對但 provider 未重新驗證」的狀態 |
| `actionmailer` interceptor（`Mail::Interceptor`） | `halted` 時攔截；非 production 一律改寄內部信箱（18 §F3 坑：「開發環境誤寄真人」，第一天就裝） | 已在 18 定案 |
| `config/limits.yml` | 全部配額上限的單一真相（CLAUDE.md §6；常數表 22 §9.4） | 硬編碼上限是驗收打回項 |
| Solid Cache | `Limits.for` 與 `Policy.resolve` 的讀取快取（TTL 短） | 配額檢查在寫入熱路徑上，不能每次讀 DB；Solid Cache 是 DB-backed 但有本地層 |
| `rack-attack` | 平台後台登入防爆破（32 §9-11） | 已在 11 §1-7 定案 |

---

### 8. 實作步驟（順序化 todo）

1. 建表五張；`config/limits.yml` 若尚未建立則本步驟一併建（M0 應已有，CLAUDE.md §6）。
2. `quota_policies` seed：`global → warn`（33 §2.10 的預設生效組合，對照原型 badge「生效中」）；`environment:development → log_only`。
3. `Platform::Quotas::Enforcer` ＋ `Limits.for` ＋ `Usage.current`（rollup）。**先在 `log_only` 跑兩週收集 `quota_violations`，再開 warn／error**——這是三段式存在的意義。
4. 把 `Enforcer.check!` 掛進寫入路徑（商品建立、環境建立、地點新增…），統一用一個 controller/service concern，禁止散落。
5. `DailyDigestJob`（每日違規摘要 email，33 §2.10）。
6. `platform_domains` seed 四列（對照原型四個網域）＋ `DomainChecker` ＋ `CertExpiryAlertJob`。
7. **憑證方案決策**（衝突 C4）：與使用者確認萬用憑證走 `acme-client` DNS-01 自建，或改由 CDN／反代代管 TLS。決策後才實作 `AcmeRenewJob`。
8. `platform_mail_senders` ＋ `MailAuthChecker` ＋ `MailHaltEnforcer` ＋ interceptor ＋ break-glass mutation。
9. `BounceRateRollupJob`（7 天退信率，>5% 告警）。
10. `platform_default_flags` seed 四列（對照原型）＋ `DefaultFlagsApplier` 掛在 `Shop` 的 `after_commit on: :create`。
11. Platform:: GraphQL 型別與 mutation。
12. 前端四張卡（§11）。
13. 上線前逐項驗證：DNS 四筆、憑證到期日、SPF/DKIM/DMARC 三個 pass、robots noindex（32 §9-12）。

---

### 9. 測試清單

```
spec/services/platform/quotas/enforcer_spec.rb
  - log_only：達 100% 仍 allowed == true，但寫入 quota_violations（action_taken: logged）
  - warn：達 60% → level == :warn、allowed == true            ← 33 §2.10 的 60%
  - error：達 100% → level == :error、allowed == false        ← 33 §2.10 的 100%
  - 邊界：59.99% 不觸發、60.00% 觸發；99.99% 不擋、100.00% 擋
  - policy scope 優先序：quota:products 覆寫 global
  - limits_overrides 生效（32 §7）且上限來自 config/limits.yml（不得硬編碼——用 stub 換值驗證）
  - Usage.current 走 rollup（斷言不對 products 全表 COUNT）

spec/requests/platform/graphql/quota_enforcement_spec.rb
  - entitlement 超額 → HTTP 200 + userErrors{code: QUOTA_EXCEEDED}   ← 鐵律
  - API cost 吃滿 → HTTP 200 + errors[0].extensions.code == "THROTTLED"（28 §0.4）
  - 前台 Ajax 面吃滿 → HTTP 429 + Retry-After（28 §0.4）
  - 三者不得混用（明確斷言 Admin/Platform GraphQL 永不回 429）

spec/services/platform/settings/mail_auth_checker_spec.rb
  - SPF fail → halted == true 且寫審計
  - DKIM fail → halted；三項皆 pass 後自動解除 halted
  - halted 期間 ActionMailer 送出的信被 interceptor 丟棄（斷言 deliveries 為空）
  - halted 期間平台告警信仍能寄出（例外路徑）
  - break-glass waiver 生效期間不 halt；到期自動恢復 halt
  - DMARC p=none → warn 不 fail（依 §6.1 待定決策；若使用者改判則同步改測試）

spec/services/platform/settings/default_flags_applier_spec.rb
  - 新店建立後 shop_feature_flag_overrides 有四列且值等於當下預設
  - **改預設值不影響既有商店**（建店 → 改預設 → 既有店的解析值不變）  ← 本手冊補齊的語意
  - platformDefaultFlagSet 回傳 affectedExistingShops == 0
  - 變更落審計（DOCS defaultflags）

spec/services/platform/settings/domain_checker_spec.rb
  - 憑證到期 <30 天 → cert_state == expiring 並產生告警（DOCS platformdomain）
  - DNS 解析失敗 → dns_state == unreachable
  - platform.chilllove.tw 的 robots.txt 含 noindex（32 §9-12）

spec/system/platform/settings_spec.rb
  - 四張卡的三態
  - defaultflags switch 有 role="switch" aria-checked，切換後出現 SaveBar／Toast（23 §4-1）
  - quotapolicy 三列的紅橘綠 badge 與政策一致
```

---

### 10. 驗收清單

- [ ] **33 §5-8**：60% warn／100% error 三段式 ✓；儀表板紅橘綠 ✓；每日摘要 ✓。
- [ ] **鐵律／28 §0.4**：Admin 與 Platform GraphQL **永不回 429**；entitlement 超額走 `userErrors`（HTTP 200）；限流走 `extensions.code=THROTTLED`；只有前台 Ajax 面回 429＋`Retry-After`。
- [ ] **CLAUDE.md §6**：所有上限值引用 `config/limits.yml`，靜態掃描無硬編碼數字（新增一條 CI lint）。
- [ ] **DOCS `platformdomain`**：四個網域狀態可見；憑證到期 30 天前告警可觸發（用假到期日驗證）；`platform.chilllove.tw` robots 全域 noindex（32 §9-12）。
- [ ] **DOCS `mailsender`**：SPF／DKIM／DMARC 任一失效 → 通知信全停並告警；break-glass 有審計與自動到期。
- [ ] **18 §F3-5**：7 天退信率 >5% 告警。
- [ ] **DOCS `defaultflags`**：逐店可覆寫；變更落審計；**改預設不影響存量店**且 UI 有明示。
- [ ] **11 §5**：配額違規事件帶 `request_id`（可與結構化日誌對接）；`quota_violations` 有 `shop_id` 前導索引。
- [ ] **11 §9 checklist**：`/up` 綠、PII／限流／冪等三件套就位（本頁的限流即配額 enforcement）。
- [ ] 五張表在 migration 檔頭註明「平台域表（豁免多租戶鐵律）」，`quota_violations` 除外（有 `shop_id`）。

---

### 11. 前端（React/TS）

**元件樹**
```
<SettingsPage className="narrow">          // 原型此 view 帶 .narrow
  ├ <PageHead title="平台設定"/>
  ├ <PlatformDomainCard/>     // data-doc="platformdomain"；<DL> 四列 + Badge 群
  ├ <MailSenderCard/>         // data-doc="mailsender"；三個 auth Badge + 退信率
  ├ <DefaultFlagsCard/>       // data-doc="defaultflags"；<FlagRow>×4（switch）
  ├ <QuotaPolicyCard/>        // data-doc="quotapolicy"；三列 usage-row + Badge
  └ <BillingPlansCard/>       // data-doc="billingplans"（W2 佔位，不在本段）
```

**狀態管理**：一個 `PlatformSettings` query 打包四張卡，`pollInterval: 300000`（5 分鐘——設定不常變，但憑證／DNS 狀態要能自動更新）。**所有變更用 SaveBar 模式**（23 §3：右下浮動組）：表單 dirty → 浮出「儲存／捨棄」；儲存 → 按鈕 loading → Toast（23 §4-1 回饋三件套）。**`platformQuotaPolicySet` 與 `platformMailHaltWaive` 為危險動作** → 二次確認 modal ＋紅主鈕（23 §4-6）。

**GraphQL**
```graphql
query PlatformSettings {
  platformDomains { role host wildcard robotsNoindex dnsState certState certExpiresAt daysUntilExpiry }
  platformMailSender { domain provider spfState dkimState dmarcState bounceRate7d halted haltWaiverUntil }
  platformDefaultFlags { flagKey variant flag { name description } }
  platformQuotaPolicies { scope mode warnThresholdPct errorThresholdPct dailyDigest }
}
mutation SetDefaultFlag($key: String!, $variant: String!) {
  platformDefaultFlagSet(flagKey: $key, variant: $variant) {
    defaultFlag { flagKey variant }
    affectedExistingShops                 # 恆為 0，UI 用它渲染「不影響既有商店」的說明
    userErrors { field message code }
  }
}
```

**三態**
- **載入**：四張卡各自 skeleton；`<DL>` 用灰條佔位。
- **空**：不會有空態（設定恆存在）；但 `platformDefaultFlags` 為空時顯示「尚未設定任何預設 flag」＋「從 Feature flags 加入」CTA。
- **錯**：紅 banner；**憑證／DNS 檢查失敗要用 `critical` 而非 `warning`**（這是全平台級故障的前兆，不能用弱化配色）。

**響應式**
| 斷點 | 行為 |
|---|---|
| ≤1279 | `.narrow` 已限 998 寬，無變化 |
| ≤1023 | `.dl` 由 `140px 1fr` 改 `100px 1fr`（CSS 已定義）；`<FlagRow>` 的名稱＋描述與 switch 維持同列 |
| ≤767 | `html{font-size:14px}`；`.usage-row`（配額三列）由 `1fr auto` 保持；`input{font-size:16px;height:40px}` 防 iOS 放大；危險確認 modal 轉貼底 sheet |
| ≤429 | `.dl` 塌成單欄（`dt` 12px 灰字在上、`dd` 在下，CSS 已定義）；網域列的多個 badge 換行；配額三列的門檻數字與 badge 換行成兩行 |

**a11y**：三個 mail auth badge 除色票外必附文字（SPF／DKIM／DMARC ＋ `aria-label="SPF 驗證通過"`）；switch 用 `role="switch" aria-checked`（原型已實作）並在切換後以 `aria-live` 播報結果；憑證到期日用 `<time datetime="2027-06-01">` 語意標籤；紅橘綠燈不得只靠顏色，`log_only／warn／error` 三列各有文字狀態 badge。

---

## 附錄：規格衝突與待確認清單

### A. 發現的規格衝突（需使用者裁決）

| 編號 | 衝突 | 兩方說法 | 本手冊的暫行處理 |
|---|---|---|---|
| **C1** | **API 版本編號與發版節奏** | 28 §0.1：「version＝日期制 `YYYY-MM`（**首版 `2026-08`**）」「demo 期單版本」；原型 `APIV` ＋ DOCS `deprecation`：**季度發版**，版本為 `2026-01 / 2026-04 / 2026-07 / 2026-10`。`2026-08` 不落在季度線上 | 以 33／原型的季度制為目標態（12 個月支援、9 個月重疊），把 `2026-08` 視為 demo 期的過渡版本。**需確認：正式版第一個季度版是 2026-10 還是回溯改為 2026-07？** |
| **C2** | **rollout 批准的角色** | 32 §5／原型 `RM`：「上限覆寫／flags」＝ owner／admin；原型 `AUDIT` 第五列：`吳思穎`（`STAFF` 中角色為 **ops**，且狀態「待啟用」）執行 `flag.rollout_approve` | 實作以 RM 為準（owner／admin）。**需確認：rollout 批准是否要開放給 ops？** 若要，RM 需新增一列「rollout 批准」 |
| **C3** | **狀態頁元件數 vs 事故 modal 元件下拉** | 狀態頁 `SP` 有 **7** 個元件（Admin／Checkout／Storefront／API／背景任務／電子發票／金流通道）；事故 modal `ovInc` 的「受影響元件」下拉只有 **5** 個（缺電子發票、金流通道） | 以 7 個為準，補齊 modal 下拉。（註：33 §5-11 的「5 元件狀態」指的是 **5 種 status**，不是 5 個元件——不構成衝突） |
| **C4** | **萬用憑證的簽發方式** | 11 §1-1：「Kamal 部署自帶 Let's Encrypt」（kamal-proxy 走 HTTP-01 逐 host）；原型 `platformdomain`：`*.mychilllove.com` **萬用憑證**。HTTP-01 **不支援萬用字元** | 萬用憑證必須改走 **DNS-01**（`acme-client` 自建，或由 CDN／反代代管 TLS）。**需確認採哪一條路徑與 DNS 供應商** |
| **C5** | **寄件網域 TLD** | 18 §F3-1：`mail.chilllove.com`；原型 `mailsender`：`mail.chilllove.tw` | 以原型（`.tw`）為準——平台域一律 `.tw`（`chilllove.tw`／`platform.chilllove.tw`／`status.chilllove.tw`），只有商店子網域用 `.com`（`{store}.mychilllove.com`）。**需確認並回頭修 18** |
| **C6** | **配額／限流超額的 HTTP 回應** | 原型 `quotapolicy`：「達 100% 擋下並回 **429／userErrors**」；32 §3-3：「API 成本制吃滿 **429+Retry-After**」；28 §0.4：節流回應是 **HTTP 200 ＋ `errors[0].extensions.code="THROTTLED"`**，只有**前台 Ajax 面**才 429＋Retry-After；CLAUDE.md §4：業務錯誤走 userErrors、**HTTP 恆 200** | 依「平台設定」§6.2 的三情境表分開實作（entitlement→userErrors／API cost→THROTTLED／前台 Ajax→429）。**32 §3-3 與原型措辭需修正** |
| **C7** | **逐店 flag 覆寫的載體** | 32 §7：`shops.feature_flags JSON` 欄位；33 §6 與本手冊：獨立表 `flag_targets`／`shop_feature_flag_overrides` | 以獨立表為權威（可加 `set_by`／`reason`／審計，JSON 欄位做不到）。`shops.feature_flags` 降級為讀取快取或直接移除。**需確認** |
| **C8** | **用量告警門檻不一致** | 33 §2.10／原型 `quotapolicy`：**warn 60%／error 100%**；32 §3-3 租戶詳情 `usage` 卡：「**≥80% 黃／≥95% 紅**」 | 以 33 的 60/100 為配額 **enforcement** 門檻；32 的 80/95 視為**視覺提示**門檻——但兩套門檻並存會讓「橘燈」與「黃燈」在同一產品裡代表不同事。**建議統一為 60/100，需確認** |
| **C9** | **Solid Queue 佇列命名** | 18 §F5-1：三個**優先級**佇列 `critical／default／low`，worker 配比 **2:2:1**；原型 `QUEUES`：五個**領域**佇列 `default／webhooks／feeds／einvoice／mailers` | 兩者不相容（worker 配比要綁在優先級上）。建議：**物理佇列維持 `critical/default/low`（配比 2:2:1）**，監控頁的五列改為依 job class 家族聚合的「邏輯佇列」。**需確認**（若要五個物理佇列，18 §F5-1 的配比規則需重寫） |

### B. 標「待定，需使用者確認」的完整清單

**可靠性與事故**
1. 事後檢討（postmortem）的發布期限（建議 resolved 後 5 個工作日）。
2. 維護視窗需 `admin+` 核准的時長門檻（建議 > 4 小時）。
3. `verifying → completed` 的成功率門檻與樣本數（建議 95%／近 200 筆）。
4. 補投的最大陳舊度 `MAX_STALENESS`（建議 24 小時）。
5. 排水速率的倍率（建議常態吞吐 p50 × 1.5）。
6. `X-CL-Delayed-Delivery` header 是否加入 28 §15 的 header 集。
7. **租戶解凍後是否補投**凍結期間的事件（建議不補投）。
8. 公告門檻的數值：`queue_latency` 持續時間、`dead_letter` 的影響範圍判定、`admin_p95`／`storefront_p95` 的倍率與持續時間、`http_5xx` 的門檻、`mail_auth_fail` 對映哪個元件。
9. 訂閱通知的分批速率（建議 500／分）。
10. 狀態頁靜態產物的託管商與 DNS 供應商。
11. 事故／維護／狀態頁相關操作的角色（RM 矩陣未涵蓋）。

**發布與灰度**
12. `New` 態的精確定義（採 LaunchDarkly：建立 ≤7 天且從未評估）。
13. 「只服務單一 **off** 變體」是否該有獨立態（目前依 33 字面歸 `Active`）。
14. 「近 7 天是否改過設定」的用途（本手冊用作生命週期推進的否決條件，非態的判準）。
15. `Live → Ready for code removal` 的「≥30 天」起算點（本手冊採「自進入 Launched 起算」）。
16. 「關鍵環境」的定義（本手冊採 production）。
17. `Ready to archive → Deprecated` 的觸發條件、`Archived → Deleted` 的保留期。
18. flag 解析優先序（本手冊：逐店覆寫 > kill switch > 全域開關 > targets > 預設）。
19. rollout 階段批准的最小樣本量（建議 30 分鐘且 ≥1,000 次評估）與自動 abort 門檻。
20. `aborted` rollout 在卡片上的保留時長（建議 24 小時）。
21. 逐租戶評估取樣率（建議 1/1000）。
22. CI bot 的新 scope `read_write_flags`。
23. 是否採用 `flipper` gem（本手冊建議自建）。
24. 是否支援多變體（首版只做 on/off）。

**環境與備份**
25. 媒體還原是否用與 DB 相同的耗時曲線（33 只給合計基準）。
26. post actions 的固定耗時（建議 1 分鐘）。
27. 校準的最小樣本數（建議 5）與單次斜率漂移上限（建議 ±25%）。
28. 還原超時的黃燈門檻（建議估算值的 120%）。
29. 還原失敗是否支援中止／快照回退。
30. **「還原後停用 webhook／app」是否適用 production**（33 原文只綁「非正式環境預設」；本手冊擴大至全部並對 production force-lock）。
31. `staging/preview` 的三個安全預設是否允許 `owner` 以 API 關閉。
32. 環境／備份／還原相關操作的角色（建議 production 還原需 `owner` ＋四眼）。
33. 升級三節奏的 UI 位置（原型無此控件）。

**公告與棄用**
34. 受眾是「排程時凍結」還是「發送時重算」（本手冊採發送時重算）。
35. API health report 的寄送頻率（建議每月；棄用剩 ≤3 個月改每週）。
36. `VersionSunsetJob` 的自動排公告門檻（建議剩 ≤6 個月）。
37. `X-CL-API-Deprecated-Reason` header 是否加入 28 §0.1。
38. 公告命中率過高（≥80%）的提醒門檻。
39. `announcement_recipients` 的保留期（PII purge，11 §7）。
40. 公告相關操作的角色。

**平台設定**
41. DMARC `p=none` 算 warn 還是 fail。
42. 「通知信全停」是否包含平台自己的告警信（本手冊：不含）。
43. break-glass waiver 的最長時數（建議 4 小時）。
44. `DomainChecker`／`MailAuthChecker` 的檢查間隔（建議 15 分鐘）。
45. 憑證到期提醒的遞增節奏（建議 30／21／14／7／1 天）。
46. 萬用憑證方案（`acme-client` DNS-01 自建 vs CDN 代管）與 DNS 供應商。
47. 平台設定各項變更的角色（建議 `owner`）。
