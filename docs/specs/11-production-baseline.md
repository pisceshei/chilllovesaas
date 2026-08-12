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
3. 冪等：見 §2.1 完整規格（表結構、TTL、回放語義、錯誤碼、參數指紋）；checkout 提交、webhook 接收、金流回調、**退款、庫存調整、訂單取消**必掛。
4. MySQL 全庫 `utf8mb4` + `utf8mb4_0900_ai_ci`（商品標題會有 emoji 與中文）。
5. **`strong_migrations` gem 強制上線後的 DDL 安全**：大表加欄位/索引要用 online DDL，禁止鎖表操作直接跑。
6. 備份：每日全量（mysqldump --single-transaction）+ binlog 連續歸檔（可 point-in-time 還原）；**每季做一次還原演練**——沒演練過的備份等於沒有備份。

### 2.1 冪等完整規格（P0-11）

> <!-- 依 46a:781–794、46a:1000–1016 修正，原文：
>      ①回放逐字「Successfully cached responses are **constructed from current database state**, so on rare occasions, the cached GraphQL response may not be the same as the original one.」（46a:791、46a:1009）
>      ②保留期逐字「The retention window is **24 hours** from the original request. After this period, idempotency keys expire and retries are treated as separate operations.」（46a:789、46a:1006）
>      ③兩個錯誤碼 `IDEMPOTENCY_CONCURRENT_REQUEST` / `IDEMPOTENCY_KEY_PARAMETER_MISMATCH`（46a:763–764、46a:1010–1011）
>      ④指紋逐字「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」（46a:793、46a:816）
>      🔴 此處原本寫錯：11:45–48 的 `with_idempotency` 把 `response_body` 存起來**原樣回放**，與官方語義**相反**。
>      官方是「重跑 serializer、由當前 DB 狀態重建」。任何人翻舊版看到 `response_body` 原樣回放都不要改回去。 -->

**(a) 表結構（取代原本存 `response_body` 的設計）**

```sql
idempotency_keys(
  shop_id, key,                  -- 唯一索引 (shop_id, key)
  mutation_name,                 -- 用於錯誤訊息與稽核
  params_fingerprint CHAR(64),   -- 見 (d)，偵測同 key 不同參數
  state ENUM('processing','succeeded','failed'),
  result_ref_type, result_ref_id,-- 🔴 存「結果物件的指標」而非回應快照
  created_at, expires_at         -- expires_at = created_at + limits.idempotency.ttl_hours(24h)
)
```

**(b) 回放語義：由當前 DB 狀態重建，不存回應快照**
| state | 行為 |
|---|---|
| 無此 key | 建 `processing` 列（唯一索引搶佔）→ 執行 → 寫 `succeeded` ＋ `result_ref` |
| `succeeded` | **依 `result_ref` 重新載入物件、重跑同一支 serializer** 產生回應。**不讀任何快取的 body** |
| `processing` | 回 `IDEMPOTENCY_CONCURRENT_REQUEST`，呼叫端 exponential backoff 後**用同一把 key** 重試 |
| `failed` | 視為未執行，允許以同一把 key 重試 |
| 已過 `expires_at` | **視為全新操作**（TTL 24h，`limits.idempotency.ttl_hours`） |
| `result_ref` 指向的物件已被刪除 | 回網域性 `*_NOT_FOUND`（如 `LOCATION_NOT_FOUND`），語義＝「原請求成功，但關聯資料隨後被刪除」 |

> 為什麼照抄「重建」而非「快照」：①與 Shopify 行為一致；②不必為每支 mutation 維護回應版本；③回應必然反映最新狀態（不會回放過期金額）。副作用是**回放的回應可能與原始回應不同**（官方明示可接受）。

**(c) 錯誤碼（進 28 §0.3 的 typed code enum）**
| code | 何時 | 呼叫端該做什麼 |
|---|---|---|
| `IDEMPOTENCY_CONCURRENT_REQUEST` | 同一把 key 有另一個請求正在處理 | 退避後**用同一把 key** 重試（不可換 key） |
| `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` | 同一把 key 但 `params_fingerprint` 不同 | 這是呼叫端 bug，換新 key 或修正參數 |

**(d) 參數指紋正規化（不做會誤判 mismatch 而卡死）**
```
fingerprint = SHA256( canonical_json(input) )
canonical_json：① 物件 key 遞迴**字典序排序** ② 移除 null 欄位 ③ 陣列**保持原順序**（順序有語義）
                ④ 數字一律整數 cents ⑤ 不含 idempotencyKey 本身
```
逐字依據：「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」——**輸入欄位順序會影響指紋**，必須先排序再 hash。

**(e) 適用範圍與 key 產生**
- 強制帶 key 的 mutation 清單見 `config/limits.yml` 的 `idempotency.required_for`（含 Shopify 2026-04 起強制的 17 個，以 refund／inventory 為主；缺 key **執行期直接報錯**，不是靜默通過）。
- 額外由**本專案**強制（Shopify 文檔未載明）：`returnProcess`（內含退款）、`orderCancel`（非同步 job）。
- key 格式：互動請求 UUID v4/v7；**背景排程用 UUID v5**（namespace ＋ job 參數 → 同一 job ＋ 同變數永遠產生相同 key，免持久化）。
- **送出前先持久化 key**（防當機後重送換 key）；成功後才產生新 key。
- **Bulk 操作每個 JSONL row 一把獨立 key，絕不共用**（`limits.idempotency.bulk_key_per_row`）。

**代碼**：

```ruby
# 冪等 concern（用法：include Idempotent; idempotent_action key: -> { params[:idempotency_key] }）
# 為什麼是「重建」而非「回放快照」：46a:791/46a:1009 逐字——Shopify 的 cached response
# 「constructed from current database state」。存 response_body 原樣回放與官方語義相反（原 11:45–48 的錯誤）。
def with_idempotency(key, mutation:, input:)
  fp  = Idempotency.fingerprint(input)                    # §2.1(d) canonical_json → SHA256
  rec = IdempotencyKey.claim!(shop: Current.shop, key:, mutation:, fingerprint: fp)
        # claim! 以唯一索引搶佔：搶到 → processing；已存在 → 依 state 回 (b) 表的分支
  return Idempotency.rebuild(rec) if rec.succeeded?       # 重載 result_ref + 重跑 serializer
  raise Idempotency::Concurrent  if rec.processing?       # → IDEMPOTENCY_CONCURRENT_REQUEST
  raise Idempotency::Mismatch    if rec.fingerprint != fp # → IDEMPOTENCY_KEY_PARAMETER_MISMATCH

  yield.tap { |obj| rec.succeed!(result: obj, expires_at: 24.hours.from_now) }
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
