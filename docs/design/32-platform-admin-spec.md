# 32 — 平台總控後台（Platform Admin）規格

> 服務端（SaaS 營運方）管理所有租戶的總後台。原型：`docs/design/chilllove-platform-admin.html`（開「⌗ 註釋模式」看每個控件的 功能/邏輯/實作，data-doc key 與本文件章節一一對應）。歸屬里程碑：**M8 運營線**（部分依賴 M7 的網域/憑證交付）；上游依據：`docs/specs/12`（Platform:: 命名空間）、`docs/research/07` §7（租戶 P0–P2）、`docs/specs/11` §5（可觀測）、`docs/research/28` §0（API 慣例）。

## 0. 定位與邊界

- **獨立入口**：`platform.chilllove.tw`，與商家後台（`{store}.mychilllove.com/admin`）完全分離；**獨立認證域**（`platform_staffs`，與商家 staff 無關）；2FA 強制（72h 寬限後鎖定）。
- **視覺區分**：同一套 tokens（23 §1），但**頂列深色**（#141518）＋紫色「平台總控」膠囊——防止支援人員在代登入場景混淆身分。商家後台＝淺色頂列。
- **跨租戶查詢紅線**：一切跨租戶讀寫集中在 `Platform::` 命名空間並顯式 `ActsAsTenant.without_tenant`（specs/12 §96），散落他處＝驗收打回。
- 不含：方案/計費（07 §7 P2，設定頁佔位）、多店組織（P2）。

## 1. 資訊架構

六區：**總覽**（KPI/健康/GMV 圖/最新註冊/審計尾）→ **租戶**（列表/詳情）→ **監控**（佇列/webhook/限流/慢查詢）→ **審計日誌** → **平台人員** → **平台設定**（網域/信件/flags/計費佔位）。監控 badge＝24h webhook 失敗數，與監控頁同源。

## 2. 租戶生命週期狀態機（核心）

```
trial ──付款/轉正──▶ active ──凍結──▶ frozen ──解凍──▶ active
  │                    │                │
  └──14天到期未轉──▶ expired(=frozen 子型)│
                       └──關閉──▶ closed ──30 天寬限──▶ deleted（不可逆）
```

| 轉移 | 誰可做 | 前置條件 | 副作用（全部冪等） |
|---|---|---|---|
| trial→active | 系統（自動） | 轉正條件成立 | 事件 `shop.activated`；解除試用上限 |
| active→frozen | admin+ | **原因必選**（付款逾期/濫用/法遵/商家要求/其他→備註必填） | 前台 503＋noindex＋「暫停服務」頁；商家後台唯讀＋橫幅；排程 job 暫停；feed 停推；webhook 停發；審計 |
| frozen→active | admin+ | — | 全部恢復；審計 |
| active/frozen→closed | admin+（二次確認） | — | 前台 **410**（30 §9 死鏈規範）；admin 唯讀 30 天；子網域保留防重註冊 |
| closed→deleted | owner（輸入商店名確認） | 關閉滿 30 天 | 資料不可逆刪除（GDPR）；審計永久保留（去識別化 shop 名） |

- 狀態存 `shops.status`；所有轉移走 state machine 單一入口（禁止散落 `update_column`）。
- **凍結/解凍必須冪等**：重複請求回相同結果，不重複發事件。

## 3. 按鈕級清單（對照原型 data-doc）

### 3-1 總覽
| 元素 | 功能 | 邏輯 | 實作 |
|---|---|---|---|
| KPI 六卡（`kpis`） | 商店總數/活躍/試用/凍結/今日訂單/今日 GMV | 點卡＝跳租戶列表帶對應篩選；GMV 口徑＝已付款訂單，與圖表**同源** | P0・`platform_daily_rollups` |
| 健康列（`health`） | 佇列深度/5xx/webhook 失敗/合成巡檢 | 任一紅點→頂列橫幅；口徑對齊 11 §5 | P0・`/up`＋合成下單 job（10 分鐘） |
| GMV 圖（`gmvchart`） | 30 天單系列折線 | dataviz 全套：2px 線/10% 面積/髮絲網格/hover 十字/末端點/表格切換 | P0・#2a78d6 |
| 最新註冊（`signups`）/審計尾（`audittail`） | 動態尾巴 | 與對應頁同源 | P0 |

### 3-2 租戶列表
| 元素 | 功能 | 邏輯 | 實作 |
|---|---|---|---|
| 篩選 chips＋搜尋（`shopsearch`） | 狀態篩選＋名稱/子網域/email 即時過濾 | 白名單欄位編譯 SQL（11 §1 防注入）；空結果附「清除搜尋」 | P0 |
| 租戶表（`shoptable`） | 跨租戶索引 | 整列點進詳情；狀態 badge pip 語意（實圈活躍/半圈試用/空圈凍結）；cursor 分頁 ≤250（28 §0） | P0 |
| saved views（`shopviews`）/匯出（`shopexport`）/代建（`createshop`） | 同商家後台慣例 | 匯出>50 筆轉 job＋簽名連結 | P1 |

### 3-3 租戶詳情
| 元素 | 功能 | 邏輯 | 實作 |
|---|---|---|---|
| 凍結/解凍（`freeze`） | 生命週期核心 | §2 狀態機；modal 原因必選、「其他」備註必填、紅主鈕、loading→toast | P0 |
| 代登入（`impersonate`） | 支援進入商家後台 | §4 全文 | P1 |
| 基本資料（`basicinfo`） | 子網域/主網域/幣別時區/GID | GID `gid://chilllove/Shop/{id}` | P0 |
| 用量與上限（`usage`） | 五項用量 vs `config/limits.yml` | ≥80% 黃/≥95% 紅；**覆寫**寫入 `limits_overrides`＋審計；API 成本制吃滿 429+Retry-After（28 §0） | P0 |
| 網域（`domains`） | 平台域＋自訂域 DNS 狀態 | TXT 挑戰＋CNAME 檢查；失敗可重驗；301 收斂（30 §9-3） | P1（依賴 M7） |
| 本店操作記錄（`shopaudit`） | 平台對本店做過什麼 | 全域審計 WHERE shop_id；append-only | P0 |
| 擁有者卡（`owner`） | 聯絡＋重寄驗證信＋重設 2FA | 重設 2FA 需 owner 覆核（四眼原則） | P0/P1 |
| 危險區（`danger`） | 關店/排程刪除 | §2；紅鈕＋輸入商店名確認＋「無法復原」明示 | P0 |

### 3-4 監控／審計／人員／設定
- 佇列（`queues`）：Solid Queue 各佇列深度/p95/死信；死信>0 告警。P0
- Webhook 失敗（`webhookfails`）：24h 清單＋手動重試（落審計）；自動重試指數退避。P0
- 限流 Top（`ratelimit`）：吃滿次數排行，辨識濫用；點列進該店。P1
- 慢查詢（`slowqueries`）：>1s 抽樣；疑似缺 `shop_id` 前導索引自動提示。P1
- 審計表（`audittable`）：時間/人員/動作/對象/原因/IP；**不可刪改**；匯出簽名連結。P0
- 人員（`stafftable`/`staffinvite`）：邀請 24h 有效；2FA 強制；角色變更僅 owner；bot 帳號 API token 可輪換。P0
- 設定：平台網域＋萬用憑證（到期 30 天前告警）、信件 SPF/DKIM/DMARC（失效→通知信全停＋告警）、預設 feature flags（逐店覆寫在租戶詳情；變更落審計）、計費佔位（P2）。P0

## 4. 代登入（Impersonation）規格

1. 事由**必填**→寫入雙方審計＋email 通知商家 owner。
2. 產生 `impersonation_sessions`（staff_id, shop_id, reason, expires_at＝60 分鐘, revoked_at）；到期或手動撤銷即失效。
3. 代登入期間：商家後台頂部持續顯示「平台支援存取中」橫幅（商家端可見）；每個寫入動作 events 追加 `impersonated: true` 與 staff 標識。
4. 權限＝該店 owner 等價，但**禁止**：改商家密碼/email、發起退款超過單筆 NT$10,000（需商家覆核）、刪除商店。
5. 角色：support 以上可用；read_only 不可。

## 5. 角色權限矩陣

| 動作 | owner | admin | support | ops | read_only |
|---|---|---|---|---|---|
| 檢視全部 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 凍結/解凍/關店 | ✓ | ✓ | — | — | — |
| 排程刪除 | ✓ | — | — | — | — |
| 上限覆寫/flags | ✓ | ✓ | — | — | — |
| 代登入 | ✓ | ✓ | ✓ | — | — |
| webhook 重試/佇列操作 | ✓ | ✓ | ✓ | ✓ | — |
| 人員管理/角色變更 | ✓ | — | — | — | — |
| 審計匯出 | ✓ | ✓ | — | — | — |

危險動作（凍結/關店/刪除/重設 2FA）一律：二次確認＋原因寫審計；刪除另需輸入商店名。

## 6. Platform:: API 契約（依 28 §0 全部慣例）

端點：`/platform/api/{version}/graphql.json`（與 admin API 分離；`platform_staffs` session 認證＋CSRF；bot 走 token）。GID：`gid://chilllove/PlatformStaff/{id}`、`gid://chilllove/PlatformAuditLog/{id}`。分頁 cursor ≤250；業務錯誤 `userErrors{field,message,code}`（HTTP 恆 200）；金額 MoneyV2；成本制限流同 28 §0。

| 操作 | 型別 | 說明 |
|---|---|---|
| `platformShops(query,status,first,after)` | query | 租戶列表（搜尋語法同 22 §0） |
| `platformShop(id)` | query | 詳情（含 usage、domains、auditLogs connection） |
| `platformShopFreeze(id, reason!, note)` | mutation | §2；reason enum；冪等 |
| `platformShopUnfreeze(id)` | mutation | 冪等 |
| `platformShopClose(id)` / `platformShopScheduleDeletion(id, confirmName!)` | mutation | §2 |
| `platformShopLimitsOverride(id, key!, value!)` | mutation | 寫 `limits_overrides`＋審計 |
| `platformShopFlagSet(id, key!, enabled!)` | mutation | 逐店 flag |
| `platformImpersonationStart(shopId, reason!)` / `platformImpersonationRevoke(id)` | mutation | §4 |
| `platformAuditLogs(query,actor,action,first,after)` | query | 審計 |
| `platformStaffInvite(email!, role!)` / `platformStaffRoleSet(id, role!)` | mutation | §5 |
| `platformMetrics(range)` | query | KPI/健康（rollup 同源） |
| `platformWebhookRetry(deliveryId)` | mutation | 落審計 |

## 7. 資料模型增補（06 §7 之外）

- `platform_staffs`（email, name, role enum, otp_secret, last_active_at）——**無 shop_id**（平台域表，豁免多租戶鐵律，集中列管）。
- `platform_audit_logs`（staff_id, action, shop_id?, target, reason, note, ip, created_at）——append-only：無 update/delete 路徑，DB 權限層面禁止。
- `impersonation_sessions`（§4）。
- `shops` 增補：`status` enum、`frozen_reason`、`limits_overrides` JSON、`feature_flags` JSON、`closed_at`、`delete_after`。
- `platform_daily_rollups`（date, shops_total/active/trial/frozen, orders_count, gmv_cents BIGINT）——金額 integer cents。

## 8. 數字口徑

- 平台 GMV＝已付款訂單金額（退款不回沖當日，另列 refunds 指標）；與商家分析頁口徑差異要在指標辭典寫明。
- KPI 卡、GMV 圖、租戶列表 count **三處同源**＝`platform_daily_rollups`＋當日即時層；驗收時三處數字必須一致。

## 9. M8 驗收清單（平台後台部分）

1. 凍結後：前台 503＋noindex＋暫停頁；商家後台唯讀＋橫幅；job/feed/webhook 停；解凍全恢復——**各有測試**。
2. 凍結/解凍冪等（重放請求不重複發事件）。
3. 關店→前台 410；30 天後可執行刪除、之前不可；刪除需輸入商店名。
4. 每個平台寫入動作在 `platform_audit_logs` 有對應列（抽測 100%）；審計表無 update/delete 權限。
5. 代登入：60 分鐘自動失效；商家端橫幅可見；動作帶 impersonated 標記；§4 禁止動作被阻擋。
6. 權限矩陣 §5 逐格測試（未授權動作回 `userErrors code:FORBIDDEN`）。
7. 上限覆寫立即生效且落審計；API 吃滿回 429＋Retry-After。
8. KPI/圖表/列表三處數字同源一致。
9. 跨租戶查詢全部位於 `Platform::` 命名空間（靜態掃描）。
10. UI 對照原型逐控件打勾；tokens 全部來自 23 §1；深色頂列＋平台膠囊存在。
11. 平台後台自身有 2FA 強制與登入防爆破（限流）。
12. `platform.chilllove.tw` robots 全域 noindex。

## 10. 原型對應

`chilllove-platform-admin.html` 的每個 `data-doc` key 對應本文件章節（§3 表格「元素」欄）；原型的凍結 modal、代登入 modal、用量條、DNS badge、審計時間軸為交互驗收基準。視覺值一律 23 §1 tokens——原型未引入任何新 token。
