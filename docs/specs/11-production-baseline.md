# 11 — 生產級基線（所有功能共用的標準與全域坑）

> 「生產級」在本專案的定義：一個功能要同時通過下面 **7 個維度**才算完成。12–19 的每份功能規格都引用本篇，不再重複。

## 0. 七維度驗收表（每個功能上線前逐項打勾）

| 維度 | 最低標準 |
|---|---|
| 1 安全 | 認證+授權伺服器端強制、輸入輸出淨化、密鑰不進 repo、有限流 |
| 2 資料完整 | FK + NOT NULL + 唯一索引兜底、交易邊界正確、寫入冪等 |
| 3 併發 | 有併發測試；競態用「條件式 UPDATE / 鎖 / 唯一索引」三選一處理 |
| 4 效能 | 無 N+1、查詢有索引、p95 預算（前台快取命中 <200ms、後台 <300ms） |
| 5 可觀測 | 結構化日誌（帶 request_id + shop_id）、錯誤上報、關鍵指標有 dashboard |
| 6 測試 | 服務層單元測試 + request spec + 至少一條 system test 快樂路徑；金額代碼 100% 覆蓋 |
| 7 合規/隱私 | PII 有清單、日誌過濾、保存期限有 purge 任務 |

## 1. 安全基線

**做法**：
1. 全站 `force_ssl` + HSTS；Kamal 部署自帶 Let's Encrypt。
2. 密鑰用 Rails credentials（`config/credentials.yml.enc`），CI/主機只放 `RAILS_MASTER_KEY`；Stripe/SMTP 金鑰全走這裡，**絕不進 git**。
3. CSP header（`config/initializers/content_security_policy.rb`）：script-src 只允許自站 + Stripe.js；後台與前台分開設定。
4. Cookie 三原則：`Secure` + `HttpOnly` + `SameSite=Lax`；**admin session cookie 與 storefront buyer cookie 用不同名稱、host-only（不設 domain=）**——這是多租戶子網域架構的第一大坑（見 §8）。
5. SPA 的 CSRF：Rails CSRF token 放 `<meta>`，前端 fetch 統一帶 `X-CSRF-Token`；API token 認證的路由才 `skip_forgery_protection`。
6. 靜態掃描進 CI：`brakeman`（Rails 安全）、`bundler-audit` + `npm audit`（依賴 CVE）、`rubocop`。
7. 登入/註冊/找回密碼/折扣碼嘗試全部掛 rack-attack 限流。

**工具**：brakeman、bundler-audit、rack-attack、Rails credentials。
**文檔**：Rails Security Guide（guides.rubyonrails.org/security.html）——整份都要讀。

## 2. 資料完整性基線

**做法**：
1. 每個外鍵都建 DB 級 FK 約束；業務唯一性（handle、討code、SKU per shop）用**唯一索引**兜底，不能只靠 model validation（validation 有競態）。
2. 交易邊界收在 service 物件內：一個業務動作 = 一個 transaction；**transaction 內絕不呼叫外部 API**（Stripe/寄信/HTTP）——這是最常見的生產事故源（外部慢 → 鎖持有 → 連線池耗盡 → 全站掛）。外部呼叫放 transaction 前後或丟 job。
3. 冪等：`idempotency_keys(key, shop_id, response_digest, created_at)` 表 + controller concern；checkout 提交、webhook 接收、金流回調必掛。
4. MySQL 全庫 `utf8mb4` + `utf8mb4_0900_ai_ci`（商品標題會有 emoji 與中文）。
5. **`strong_migrations` gem 強制上線後的 DDL 安全**：大表加欄位/索引要用 online DDL，禁止鎖表操作直接跑。
6. 備份：每日全量（mysqldump --single-transaction）+ binlog 連續歸檔（可 point-in-time 還原）；**每季做一次還原演練**——沒演練過的備份等於沒有備份。

**代碼**：

```ruby
# 冪等 concern（用法：include Idempotent; idempotent_action key: -> { params[:checkout_token] }）
def with_idempotency(key)
  digest = IdempotencyKey.find_by(shop: Current.shop, key:)
  return render(json: JSON.parse(digest.response_body), status: digest.status) if digest
  yield.tap { |resp| IdempotencyKey.create!(shop: Current.shop, key:, response_body: resp.to_json, status: 200) }
end
```

**工具**：strong_migrations、annotaterb。

## 3. 併發基線

**做法**（三板斧，按優先序）：
1. **條件式 UPDATE**（首選，無鎖等待）：`UPDATE ... SET x = x - n WHERE x >= n`，看 affected rows 判成敗——庫存、折扣使用次數、餘額全用這招。
2. **行鎖**（需要讀-算-寫的複合操作）：`SELECT ... FOR UPDATE`，鎖的順序全專案統一（先 shop 級資源再明細，避免死鎖）；鎖內不做任何 IO。
3. **唯一索引**（最後防線）：即使代碼有 bug，DB 也擋住重複（訂單號、redemption、SKU）。

**坑**：
- MySQL REPEATABLE READ 下的 gap lock 容易造成插入死鎖——高併發插入的表（events、line_items）考慮把該連線改 READ COMMITTED（Shopify 也是這麼做的，見 08）。
- `update_all` / 條件式 UPDATE 會**跳過 model callback 與 updated_at**——需要的話手動補。
- 樂觀鎖 `lock_version` 用在後台編輯衝突（兩個 staff 同時改同一商品→後改的收到 StaleObject 提示重載）。

## 4. 效能基線

**做法**：
1. 開發/測試環境掛 `bullet` gem，N+1 直接紅字報錯；storefront 每頁的查詢數上限 15 條寫進 system test 斷言。
2. 每支新查詢過一次 `EXPLAIN`；慢查詢日誌 (>100ms) 開著、每週看。
3. 快取階梯：HTTP cache（assets 指紋 + immutable）→ 前台 fragment cache（Russian doll）→ Solid Cache 查詢級。**cache key 永遠 key-based expiry**（帶 updated_at/version），不手動 delete。
4. 快取雪崩：熱 key 用 `race_condition_ttl`；預熱腳本在 theme publish 後跑。
5. 分頁一律 keyset/cursor（`WHERE (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC`），**禁止深 OFFSET**。
6. 圖片：上傳後背景預生成常用尺寸，前台只出 CDN URL + width/height 防 CLS。

**坑**：`touch: true` 連鎖（variant→product→collection）會造成寫入放大與鎖鏈——只在必要的一層用，其餘靠 cache key 組合。

## 5. 可觀測基線

**做法**：
1. `lograge` JSON 單行日誌，全域 tag：request_id、shop_id、staff_id；`filter_parameters` 過濾密碼/token/卡號欄位名。
2. 錯誤上報 Sentry（免費額度夠 demo→小量產）；job 失敗、payment webhook 解析失敗設專屬告警。
3. OpenTelemetry traces（rails + mysql2 + net-http instrumentation）→ 任一託管後端；指標最低集：checkout 開始/成功數、job 佇列深度與延遲、5xx 率、DB 連線池使用率。
4. Uptime 監控打 `/up`（Rails 8 內建 health endpoint）+ 一條「合成下單」巡檢（每 10 分鐘測試店跑一次 checkout，測試卡）。

**工具**：lograge、sentry-ruby、opentelemetry-rails、Uptime Kuma/Betterstack。

## 6. 測試基線

**做法**：金字塔——服務層單元（最多）→ request spec（API 合約）→ system test（每里程碑的快樂路徑 + 3 條核心災難路徑：付款成功但庫存不足、webhook 重放、折扣碼併發用完）。金額引擎用**表格驅動測試**（幾十組輸入輸出含四捨五入邊界）+ property-based（隨機 cart 驗證「分攤總和=折扣總額」不變量）。CI：GitHub Actions 跑 rubocop + brakeman + rspec（MySQL service container）。

**工具**：rspec、factory_bot、capybara（無頭 Chromium 工作區已裝）、simplecov。

## 7. 合規/隱私基線

1. PII 清單建檔（email、姓名、地址、電話、IP）：出現在哪些表/日誌/信件。
2. Purge 任務：棄單 90 天、日誌 30 天、閒置 session 30 天。
3. 顧客資料匯出與刪除（軟需求先做成 rake task，P2 做成自助）。
4. 信件：交易信與行銷信分離，行銷信必附退訂（見 18）。

## 8. 全域十大坑（每個功能規格都會再點名）

1. **Job 內遺失租戶**：Solid Queue job 不繼承 `Current.shop` → 所有 job 第一個參數傳 shop_id、進場 `ActsAsTenant.with_tenant`；寫一支 lint/測試掃「job 沒 set tenant 就查表」。
2. **transaction 內打外部 API**（Stripe/HTTP/寄信）→ 鎖持有時間爆炸。永遠分離。
3. **浮點數算錢**：全程 integer cents；前端顯示才除 100。JS 端也禁 float 運算金額。
4. **Cookie domain 設成 `.主網域`** → A 店的 buyer session 漂到 B 店。admin/storefront cookie 一律 host-only + 不同名。
5. **時區**：DB 存 UTC；分析與「今天」用 shop 時區換算；**MySQL 的 CONVERT_TZ 需要先灌 tz 表**（`mysql_tzinfo_to_sql`），新機器預設是空的（經典坑）。
6. **深 OFFSET 分頁**與無 tiebreaker 排序（同秒建立的列會跳/重複）→ keyset + (created_at, id)。
7. **信任前端金額/價格**：一切金額 server 端重算；PaymentIntent 金額只來自 Calculator。
8. **merchant 內容 XSS**：商品描述/主題設定/通知模板都是「租戶輸入、買家瀏覽」→ 白名單 sanitize + Liquid drops 白名單（見 14、18）。
9. **webhook/回調不冪等**：Stripe 會重送、我們的 outbox 是 at-least-once → 一切 handler 以唯一鍵去重。
10. **上線後鎖表 DDL**：沒有 strong_migrations 的 `ADD INDEX` 在大表上= 停機事故。

## 9. 上線前 checklist（M 里程碑通用）

`brakeman 0 高危 → bullet 0 報警 → rspec 全綠 → EXPLAIN 抽查 → 備份還原演練過 → Sentry 收得到測試錯誤 → /up 綠 → 合成下單通過 → PII/限流/冪等三件套就位`
