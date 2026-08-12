# 18 — 功能規格：通知信、Liquid 模板、事件系統、Webhooks、背景任務（生產級）

> 覆蓋功能：outbox 事件、通知信管線、Liquid 模板沙箱、email 送達性、對外 webhooks、Solid Queue 運維。規格對照研究 04 §6 / 08 §5 / 09 §5，基線見 11。

## F1. Outbox 事件系統（一切通知與自動化的地基）

**生產級做法**：
1. `events_outbox`（uuid、shop_id、topic「資源/動詞」、payload JSON、status、attempts、locked_at）——**與業務同 transaction 寫入**（11 §8），這是「事件必達」的唯一保證。
2. Dispatcher：Solid Queue recurring job 每 5s `SELECT ... WHERE status='pending' ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED` → 逐筆路由給訂閱者（寄信、統計、之後的 webhook）→ 成功標 done。
3. 語意 **at-least-once**：每個消費者自行冪等（processed 去重表或天然冪等操作）；順序不保證，消費者不得依賴順序。
4. payload 規範：`{topic, event_id, occurred_at, resource: {type, id}, diff?}`——只帶 ID 與必要摘要，消費時再查現值（防 PII 蔓延與陳舊資料）。
5. 保留 30 天 purge；失敗 attempts ≥8 → status=dead + 告警 + 後台可重推。
6. **topic 清單的單一真相＝28 §15**（首發 24 個）。本輪新增**三個內部 topic（不對外開放訂閱）**：`einvoice/issue_requested`、`einvoice/void_requested`、`einvoice/refund_routed`——由 16-F5.5 的退款／取消／出貨三處寫入，消費者為 38 號的 `IssueJob` / `VoidJob` / `AllowanceJob`。
   <!-- 依 38:876–877、38:1338–1356、38:1103–1104 補寫，原文：「全額取消**自動作廢**、部分退貨**自動折讓**」；落地物 `Platform::Einvoice::RefundRouter`（== 作廢／< 折讓／> 作廢）與三支 job。
        原本 18-F1 與 28 §15 的 topic 清單皆無 `einvoice/*` → 退款不會觸發作廢／折讓 ＝ 稅務錯誤（50 號 TW-5）。 -->
   **內部 topic 不進 `webhookSubscriptionCreate` 的可訂閱列表**（發票資料含統編等敏感欄位，不對外投遞）。

**⚠️ 坑**：dispatcher 多實例並發靠 `SKIP LOCKED`（沒有它會重複派發）；locked_at 超時回收（worker 死掉的孤兒事件）；事件寫在 transaction 外 = 「訂單建了事件丟了」的隱形事故——code review 死盯。

## F2. 通知信管線與 Liquid 沙箱

**生產級做法**：
1. `notification_templates`（shop_id、**`event_key`**、**`group_key`**、**`channel`**（email/sms）、**`toggleable`**、**`enabled`**、`locale`、subject、body_html——subject/body 皆 Liquid）；種子提供預設模板（自寫文案），商家可改、可「還原預設」。**完整範本與可關閉性規格見 F2.1。**
2. 渲染：**Liquid gem 嚴格沙箱**——只暴露白名單 Drops（OrderDrop/ShopDrop/CustomerDrop/LineItemDrop，逐屬性手工暴露）；`Liquid::Template.parse(source, error_mode: :strict)`；render 帶 **resource limits**（render 長度 256KB、迭代上限）與 3s timeout（Timeout 包 job 層級）。
3. 模板儲存時即 parse 驗證，語法錯誤即時回報編輯器（不留到寄信時炸）。
4. 寄送：事件 → NotificationJob（transaction 外）→ 渲染 → Action Mailer → Resend/SES；每封記 `email_deliveries`（template key、to hash、message_id、狀態）。
5. 預覽：後台模板編輯頁「用最近一筆訂單預覽」+ 寄測試信給自己。

**⚠️ 坑**：
- Drop 白名單是安全邊界——**絕不把 AR 物件直接丟進 Liquid context**（等於把整個 model 的方法暴露給租戶模板）；新增屬性走 Drop 逐一加。
- 商家模板可以寫死迴圈/巨大輸出 → resource limits + timeout 缺一不可。
- HTML 信件相容性：table 佈局 + inline CSS（premailer-rails 自動內聯）；純文字版一併生成（multipart）。
- subject 也是 Liquid → 同樣沙箱；別忘 escape（信頭注入：subject 含換行要清）。
- **把所有範本都做成可關閉是合規事故**——交易性通知強制寄，見 F2.1。

### F2.1 通知範本註冊表與 `toggleable`（P1-28／H-116，合規約束）

> <!-- 依 44:449–469 補寫，原文：後台 `/settings/notifications/customer` 實測**顧客通知範本共 45+ 個、12 個事件分組**（訂單處理／到店取貨／當地配送／禮品卡／商店抵用金／訂單異常／付款／POS／運送資訊更新／退貨與取消／帳號與外展行銷／行銷訊息雙重確認加入＋Shop 再行銷）；
>      逐字結論：「`notification_templates` 需要 `(event_key, group_key, channel, toggleable, locale)`；**只有部分範本可關閉**（當地配送／運送狀態更新／雙重確認／Shop 再行銷），交易性範本強制寄——這是一條**合規約束，不是 UI 偏好**」。
>      44:447 另記 Webhook 被歸在「通知」IA 下且支援 XML 與 JSON 兩種格式（我方 28:279 只設計 JSON；XML 屬 P2，此處僅記錄不實作）。
>      我方 18-F2 原本的 `notification_templates` 只有 (shop_id, key, subject, body_html) **四欄，沒有分組、沒有 toggleable**，
>      22:189 只寫「模板分類+個別開關」→ 照現有規格會做成**全部可關**（合規風險：關掉訂單確認信、退款通知信是不能允許的）。 -->

**(a) `toggleable` 是白名單，不是預設值**——預設 `toggleable = false`（強制寄），只有下列**四個分組**的範本 `toggleable = true`：

| 可關閉的分組 | 範本（44 實測） | 預設 |
|---|---|---|
| 當地配送 | 訂單開始當地配送／訂單已完成當地配送／訂單錯過當地配送 | 開 |
| 運送資訊更新 | 運送資訊更新／配送中／已送達 | 開 |
| 行銷訊息雙重確認加入 | 顧客行銷訂閱確認 | **關** |
| 透過 Shop 再行銷（本專案對應「站外再行銷」） | 購物車提醒／重新補貨／降價／瀏覽後離開 | 開 |

其餘 **8 個分組**（訂單處理／到店取貨／禮品卡／商店抵用金／訂單異常／付款／POS／退貨與取消／帳號與外展行銷）一律 `toggleable = false`。

**(b) 硬要求**
1. `toggleable` **由種子資料決定，商家與 API 皆不可改**（`notificationTemplateUpdate` 只收 `subject` / `bodyLiquid` / `enabled`，且 `enabled` 寫入時先驗 `toggleable = true`，否則回 `userErrors`）。
2. 前端關閉開關**必須灰化 + tooltip**（「此為交易性通知，依法必須寄送」），不是隱藏——商家要知道為什麼不能關。
3. 範本清單以 **`event_key` 為主鍵語義**，新增範本走 migration 種子，**不允許商家自建 event_key**（Liquid 沙箱的 Drop 白名單綁 event_key，見 F2 第 2 點）。
4. `channel` 分 email／sms；**SMS 行銷同意永不可預先勾選**（15-F3.2 L2）與此處的 `toggleable` 是兩件事，不要混。

**(c) 範圍**：44 實測 45+ 個範本是 Shopify 的完整清單；CHILL LOVE **M1–M4 先落地 12 個交易性範本**（訂單確認／出貨確認／退款／取消／發票／退貨四種／取貨點三種），其餘進種子表但標 `implemented = false`——**表結構一次做對，範本逐步補**，避免日後為了加 `toggleable` 改 schema。
**⚠ 待查證（來源未載明）**：44 的 45+ 範本清單為 UI 實測，Shopify 官方文檔未提供完整 event_key 列表；本專案的 `event_key` 命名為自定（見 §待查證 V-18）。

## F3. Email 送達性（deliverability）

**生產級做法**：
1. 網域認證三件套：**SPF + DKIM + DMARC**（Resend/SES 後台生成 DNS 記錄，上線 checklist 驗證）；寄件網域用子網域（`mail.chilllove.com`）隔離主網域信譽。
2. 交易信/行銷信分流：不同寄件位址（orders@ vs news@）、行銷信必附 **List-Unsubscribe header + 退訂連結**（一鍵退訂寫回 consent）。
3. bounce/complaint webhook（Resend/SES 事件）→ `email_suppressions` 壓制表——hard bounce 與投訴者永不再寄（連交易信都要重試前檢查）。
4. 每店寄送配額（demo：行銷 500/日）+ 平台級速率控制，防單店濫發拖累全平台 IP 信譽。
5. 監控：送達率/開信（P1 pixel）/bounce 率 dashboard；bounce >5% 告警。

**⚠️ 坑**：沒設 DMARC 就大量寄 → 直接進垃圾桶且難翻身（信譽是累積資產）；壓制表漏查 = 對投訴者持續寄信（法規風險）；開發環境誤寄真人——非 production 一律 letter_opener / 攔截器改寄內部信箱（`Mail::Interceptor`，第一天就裝）。

## F4. 對外 Webhooks（P1，規格先立）

**生產級做法**：
1. `webhook_subscriptions`（shop_id、topic、url、secret、status、failure_count）；URL 建立時驗證：HTTPS only + **SSRF 防護**——解析 DNS 後拒絕私網/loopback/link-local/雲 metadata（169.254.169.254）IP，**投遞時再驗一次**（DNS rebinding），且 HTTP client 禁 redirect。
2. 投遞：outbox 事件 → 訂閱匹配 → DeliverWebhookJob；header：`X-CL-Topic`、`X-CL-Event-Id`、`X-CL-Hmac-Sha256`（secret 對 raw body HMAC，Base64）；timeout 5s；回應 body 讀取上限 64KB。
3. 重試：指數退避 8 次/約 4 小時（照研究 09 規格）；24 小時窗口持續失敗 → 訂閱 disabled + 通知商家；投遞紀錄表（狀態碼、耗時、截斷回應）保留 7 天供除錯。
4. 消費端指南文件：驗 HMAC（constant-time compare）、以 event_id 去重、5 秒內回 2xx（先 200 再處理）。

**⚠️ 坑**：SSRF 是這個功能的頭號安全風險（商家填 `http://169.254.169.254/` 偷雲憑證）——防護做在 resolve 層而不是字串黑名單；HMAC 比對用 `ActiveSupport::SecurityUtils.secure_compare`；重試風暴：對同一失效端點的多 topic 訂閱要共享熔斷（circuit breaker per host）。

## F5. 背景任務運維（Solid Queue）

**生產級做法**：
1. 佇列分級：`critical`（金流回調處理、訂單成立後續）、`default`（通知信、事件派發）、`low`（報表、purge、rebuild）——worker 配比 2:2:1，critical 永不被 low 餓死。
2. 任務規約（寫進 CONTRIBUTING）：參數只傳 ID（shop_id 第一位，12-F4）、必冪等、單任務 <60s（長任務切 batch 自排下一棒——job-iteration 思想，08）、retry_on 明確列舉可重試例外、其餘進 dead set。
3. 監控：Mission Control — Jobs 掛後台（/admin/jobs，owner only）；告警三指標：佇列延遲 >60s、dead set 新增、recurring 任務漏跑（heartbeat 檢查）。
4. 部署安全：Kamal 滾動時 worker 收 TERM → Solid Queue 優雅停止（in-flight 完成或釋放回佇列）；deploy 後煙霧測試跑一顆 no-op job 驗證 worker 活著。

**⚠️ 坑**：任務丟大物件（AR instance/整包 JSON）→ 序列化炸裂與陳舊資料，只傳 ID；`retry_on StandardError` 是反模式（把 bug 當暫時性錯誤無限重試）；recurring 任務在多 worker 下重複執行 → Solid Queue recurring 自帶唯一性，但自寫排程要加分散鎖；時區——recurring 的 cron 全用 UTC 寫並註記。

## 本篇驗收（對照 11 §0）

kill -9 worker 後事件零丟失（outbox 重放驗證）；惡意 Liquid 模板（億次迴圈/巨輸出/挖 model 方法）全被沙箱擋下；SSRF 測試集（私網 IP、rebinding、redirect 到內網）全拒；DMARC 對齊通過（mail-tester ≥9/10）；壓制表生效（hard bounce 後不再寄）；critical 佇列在 low 積壓 10 萬任務時延遲 <5s；webhook 重試/停用/重啟全流程可在後台觀測。
