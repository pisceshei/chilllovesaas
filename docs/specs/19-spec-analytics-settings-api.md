# 19 — 功能規格：分析報表、Settings、對外 API（生產級）

> 覆蓋功能：指標定義與 rollup、dashboard、sessions 追蹤、Settings 各域與稽核、公開 API（token/scope/限流/分頁/版本化）。規格對照研究 04 §5 / 05 / 09，基線見 11。

## F1. 指標定義（先於一切圖表）

**生產級做法**：
1. 寫一份 `metrics.md` 指標辭典，每個指標三要素：公式、口徑、反例。起步集：
   - 🔴 **總銷售額（Total sales）＝ 銷售總額 − 折扣 − 撤銷款項 ＋ 稅額 ＋ 關稅 ＋ 運費 ＋ 費用**
     <!-- 2026-08-14 依 71-R11-V14 修訂（全文＝docs/specs/86）。原文：
          「Total sales = Σ(訂單總計) − Σ(退款) −（取消單全額）——含稅運費（毛口徑…）」
          兩個問題：①**漏了訂單編輯**這一項——F1.1 自己補了但主公式沒同步，讀主公式的人會漏掉
          ②用「退款」當被減項名稱，但退款只是撤銷款項的**四個來源之一**（退款/退貨/取消/編輯）。 -->
     - **撤銷款項（`sales_reversals`）的組成見 `docs/specs/86` §3.2**。不變量：
       🔴 **`refunds` 擁有「真的動了的錢」的全部，其他每一項只補「沒有走退款的那一部分」**
       ——取消與訂單編輯**都會走 F5 退款流程**（16 §F4、16 §F8.1 第 576 列）。
       各項**計入自己的發生日**。
       <!-- 2026-08-14 修正（PR #22 Codex review 第 1 條）。原文寫「取消單**全額**」，
            但 16 §F4 的取消流程帶 `refundMethod` 時**會實際建一筆 refund** ⇒ 那筆錢
            同時落在「退款」與「取消單全額」兩項，**撤銷算兩倍、總銷售額被低估**。
            🔴 三項必須互斥，全文與驗算表＝86 §3.2。 -->
     - 🔴 **實體退貨不獨立計入金額**：伴隨退款者已由退款計入，換貨（無退款）金額淨影響為零。
       把退貨也加進金額聚合會**雙重扣除**（86 §3.2）。
     - 🔴 **總銷售額可以是負數**（撤銷 > 銷售的日子，官方明列）——一致性測試不得假設非負
       （§A G25）。
   - Orders = 成立訂單數（不含 draft 未完成、含取消但另列 cancelled 數）
   - 🔴 **AOV ＝（銷售總額 − 折扣）/ 訂單數，且分子刻意排除 post-order adjustments**
     <!-- 2026-08-14 依 §A G25 修訂。原文「AOV = Total sales / Orders」是錯的：
          本尊的 AOV 分子排除訂單後編輯/換貨/退貨，因此 **AOV ≠ net_sales / orders**，
          它有自己的分子、不與 net_sales 同源——這是鐵律 7「數字同源」的具名例外。 -->
   - Conversion = 完成訂單 sessions / 總 sessions
2. **時區**：一切「按日」聚合用 shop 時區——MySQL `CONVERT_TZ(created_at, 'UTC', shop.tz)`；**部署 checklist：先灌 MySQL 時區表**（`mysql_tzinfo_to_sql /usr/share/zoneinfo`，11 §8 經典坑）。
3. 比較期：本期 vs 前一等長期間 / 去年同期，區間邊界含頭不含尾（[start, end)）統一全站。
4. **訂單編輯的歸屬口徑（P1-22／H-93）——本專案刻意與本尊不同，見下方 F1.1。**

**⚠️ 坑**：退款計入「退款發生日」而不是原訂單日（現金流視角，跟本尊一致）；測試訂單（test mode 金流）標記 `test: true` 並排除於一切指標；幣別未統一前不做跨店聚合。

### F1.1 訂單編輯在報表中的歸屬口徑（P1-22／H-93）

> <!-- 依 46c:477 補寫，原文（H08 zh-TW / H09 en 逐字）：「**若您在訂單成立日之後編輯訂單，該編輯會在報表中顯示為一筆獨立訂單**」，
>      影響 `Orders over time`、`Sales over time`、`Average order value`。
>      我方 19 §F1 指標辭典原本**完全沒有這條口徑** → 訂單編輯後報表數字與訂單詳情頁對不上，且沒人知道是刻意還是 bug。 -->

**本尊行為**：跨日編輯 → 報表多出一筆「幽靈訂單」，`Orders`／`Sales over time`／`AOV` 三個指標同時被污染，且**不可逆**（46c:476 逐字「報表污染不可逆」）。

**本專案決策：不復刻幽靈訂單，改為「原訂單日歸屬 ＋ 編輯增量獨立可查」。**

| 指標 | 口徑 |
|---|---|
| `Orders`（訂單數） | **編輯不產生新訂單** → 計數恆為 1；`orders.edited = true` 只是旗標 |
| `Sales over time` | 編輯造成的金額差額計入**編輯發生日**（現金流視角，與「退款計入退款發生日」同一原則），**不回頭改原訂單日的數字**（否則已結算的歷史報表會浮動） |
| `Total sales` | ＝ Σ訂單**商品段**總計 − Σ**撤銷款項（商品段口徑，86 §3.2）** ＋ 稅/運費/關稅/費用各分量**淨值**（已退部分在各分量內取淨，**不入撤銷款項**） **＋ Σ編輯增量（正向）**（各項帶自己的發生日）。（2026-08-17 更正，PR #52 第 18 輪）：86 §3.2 於第 12 輪改商品段口徑後，原式「Σ訂單總計 − Σ撤銷款項」變成單邊改制——訂單總計仍含稅/運費而撤銷款項不再含，全退 HK$100 商品＋$10 稅會留 $10 在 Total sales；分量拆分須與 90-blueprint/14 §B total_sales 公式一致。**編輯的負向差額已在撤銷款項裡**，本項只補正向增量，不得再減一次 |
| `AOV` | 🔴 **分子＝（銷售總額 − 折扣），刻意排除 post-order adjustments**（含本節的編輯增量）；分母＝`Orders`，不含幽靈訂單。**不是 `Total sales / Orders`**——見下方修正註 |
| 稽核 | `order_edit_deltas(order_id, session_id, delta_cents, occurred_on)` 物化表；報表可下鑽看「哪些編輯造成本期差額」 |

<!-- 🔴 2026-08-14 修正（PR #22 Codex review 第 2 條）。本表 `AOV` 原文是
     「＝ `Total sales / Orders`；分母不含幽靈訂單 → **AOV 不被編輯污染**（這是本專案優於本尊的點）」，
     `Total sales` 原文是「Σ訂單總計 − Σ退款 ＋ Σ編輯增量」。
     問題：**同一份檔案裡出現兩個互相矛盾的 AOV 定義**——本節上方 §F1 第 21 行已依 §A G25 改成
     「分子刻意排除 post-order adjustments」，但本表仍規範性地寫 `Total sales / Orders`，
     而 `Total sales` 是**含**撤銷與編輯增量的。照本表實作與照 §F1 實作會得到**兩個不同的 AOV**。
     🔴 修正時把「優於本尊」的範圍收窄到**分母**：本尊的幽靈訂單讓 `Orders` +1（分母污染），
     我方不產生幽靈訂單 ⇒ 分母乾淨。**分子口徑本來就與本尊一致（都排除 post-order adjustments）**，
     那不是我方的優勢，原文把兩件事混成一句話講成了「AOV 全面優於本尊」。 -->

**為什麼不照抄**：本尊的幽靈訂單是實作副作用（編輯走一條類似新建訂單的路徑），不是刻意的商業口徑——46c 自己把它寫在「常見錯誤情境／不可逆風險」段而不是指標定義段。照抄會讓 `Orders` 與 `AOV` 兩個核心指標失真。**此為 13-F1「刻意優於本尊」的同類決策，必須在指標辭典明文標註差異**，否則從 Shopify 遷移過來的商家會以為我們算錯。

🔴 **差異僅在分母**：`AOV` 的分子（排除 post-order adjustments）與本尊相同，我方的改善是
**分母不含幽靈訂單**。不要把這條讀成「我方的 AOV 定義整體不同」。

**必測**：①跨日編輯後 `Orders` 不變；②編輯增量落在編輯日、原訂單日的歷史數字不變（重跑 rollup 後仍不變）；③`Total sales` ＝ 三項相加；④`order_edit_deltas` 與 `orders.total_cents` 的變化量對帳零差異；⑤🔴 **`AOV × Orders ≠ Total sales`**——編輯／退款／退貨存在時兩者本來就不等，一致性測試**不得**斷言相等（鐵律 7 的 G25 具名例外）。

## F2. Rollup 與 Dashboard

**生產級做法**：
1. 兩層架構：`daily_rollups`（shop_id、date、metric、value——nightly job 算昨日 + 今日增量每 5 分鐘）+ 即時層（今日直接聚合，資料量小）。查詢永遠打 rollup，**不對 orders 表做大範圍即時聚合**。
2. rollup 冪等可重算：`rake analytics:rebuild SHOP=x FROM=2026-01-01`（資料修正後重跑）；nightly 對帳（隨機抽 3 天全量重算 vs rollup 比對，漂移告警）。
3. Dashboard API：一支 endpoint 回全部卡片（單次往返），含本期/比較期/走勢陣列；recharts 畫線，空資料給空狀態不給 0 假線。
4. Top products/暢銷榜：rollup 表帶 dimension 欄（metric=units_sold, dimension=product_id）。

**⚠️ 坑**：日界線在 shop 時區換日瞬間的訂單歸屬要有測試（23:59:59 vs 00:00:00）；rollup 寫入用 upsert（`ON DUPLICATE KEY UPDATE`）保冪等；「今日」卡片與 rollup 銜接處別重複計（today 從即時層、歷史從 rollup，邊界=今日 00:00 shop 時區）。

## F3. Sessions 追蹤（轉換率的分母）

**生產級做法**：demo 用第一方輕量方案——storefront 注入 3 行 script 打自家 `/collect` 端點（session_id = 簽名 cookie 30 分鐘滑動）；記錄：pageview、add_to_cart、reached_checkout、purchase 四事件（漏斗即成）；bot 過濾（UA 黑名單 + 無 cookie 者不計）；**不用第三方分析（隱私與依賴）**；IP 不落庫（只取國別後丟棄）。

**⚠️ 坑**：cookie 同意（EU 流量）——第一方必要性 cookie 論證可行但要寫進隱私政策；/collect 要限流與 payload 白名單（會被灌垃圾）；轉換率分母口徑（session vs visitor）寫進指標辭典。

## F4. Settings 框架與稽核

**生產級做法**：
1. 兩類儲存：結構化域（shipping/taxes/users/notifications/domains…專屬表 + 專屬 service）與輕量開關（`shops.settings` JSON，**逐鍵 schema 驗證**——settings key 註冊表：型別/預設/驗證，防 JSON 欄變垃圾場）。
2. 所有 Settings 寫入走 `Settings::Update` service → 逐鍵 diff → audit_logs（before/after，12-F3）；危險變更（關店、改金流模式、改網域）二次確認 + 額外事件。
3. 權限：settings 各域對應 permission key（`settings.payments` 等，05 研究的顆粒度）。
4. General 域的幣別/時區：**建店後改幣別要鎖**（有訂單後不可改，只能 P2 的 Markets 處理）；改時區允許但註記「影響報表日界線」。

**⚠️ 坑**：幣別可隨意改 = 歷史金額語意全毀（最常見的電商 SaaS 資料事故之一）；JSON settings 沒 schema = 半年後沒人知道哪些 key 活著；audit 漏 Settings = 出事無法追責。

## F5. 對外 API（token / scope / 限流 / 分頁 / 版本）

**生產級做法**：
1. Token：`api_tokens`（token_digest SHA-256、prefix 明文前 8 碼供識別、scopes JSON、last_used_at、expires_at nullable）；**明文只在建立時顯示一次**；比對 `secure_compare`；格式 `cl_live_xxxx` / `cl_test_xxxx`。
2. Scope：`read_products/write_products/read_orders/…`（照 09 命名）；controller concern `require_scope!("read_orders")`；403 帶所缺 scope 名。
3. 限流：rack-attack 令牌桶（每 token 120 req/min 起步）+ 回應頭 `X-RateLimit-Limit/Remaining/Reset`；429 帶 `Retry-After`。
4. 分頁：cursor（Base64 編碼 `[sort_value, id]`）+ `page_info.has_next`，排序固定帶 id tiebreaker（11 §4）；limit 上限 250。
5. 錯誤封套統一：`{"errors":[{"code":"not_found","message":"...","field":null}]}`；code 表列管（文件化、永不改語意）。
6. 版本：`/api/v1/` 凍結合約；棄用欄位先加 `Sunset`/`Deprecation` header 與 changelog，≥6 個月後移除（09 的節奏精神）。
7. 文件：rswag 從 request spec 生 OpenAPI → `/api/docs`；附 `llms.txt`（對 AI 工具友善，09 結論）。
8. 安全：API 全域 HTTPS、token 不入 log（filter）、寫操作記 audit（actor=token）、大 payload 上限 1MB。

**代碼**：

```ruby
class Api::BaseController < ActionController::API
  before_action :authenticate_token!, :set_tenant_from_token
  def authenticate_token!
    raw = request.headers["Authorization"]&.delete_prefix("Bearer ")
    tok = raw && ApiToken.active.find_by(token_digest: Digest::SHA256.hexdigest(raw))
    head :unauthorized unless tok
    @api_token = tok.tap { _1.touch_last_used }   # 節流 touch：>5 分鐘才寫
  end
  def require_scope!(s) = @api_token.scopes.include?(s) || render_error(:forbidden, "missing_scope: #{s}")
end
```

**⚠️ 坑**：
- token 明文入庫/入 log 是最常見洩漏路徑——digest + filter + 建立頁「只顯示一次」三件套。
- `last_used_at` 每請求 UPDATE 會把讀 API 變寫熱點——節流更新（>5 分鐘才寫）。
- cursor 分頁若排序鍵可變（updated_at）會漏/重列——公開 API 只提供 created_at/id 排序。
- 版本化「盡量不破壞」比「勤發新版」重要；v1 發布前用內部消費者（自家 admin 部分讀路徑）先吃 3 個月狗糧。
- CORS：公開 API 預設不開瀏覽器 CORS（server-to-server 定位），開了就要重新審視 token 保管模型。

## 本篇驗收（對照 11 §0）

指標辭典三要素齊全且 rollup 對帳連續 7 天零漂移；換日邊界測試綠；/collect 濫灌測試被擋；改幣別在有訂單後被拒；API：token 洩漏演練（log 掃描無明文）、429/scope/404 封套一致、cursor 翻頁 10 萬筆無漏重、OpenAPI 文件與實際行為 diff 為零（rswag 保證）；Settings 全部變更可在 audit log 還原前後值。
