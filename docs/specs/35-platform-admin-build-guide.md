# 35 — 平台總控後台實作手冊 · 索引與決策登記簿

> 給 **Codex** 的：這是平台後台從零到生產的施工圖。分冊 36–39 各含 11 節固定結構（是什麼／控件逐項表／資料模型／API 契約／服務物件與 job／關鍵演算法含 Ruby 骨架／工具與依賴／實作步驟／測試清單／驗收清單／前端）。**動工前先讀本篇 §2 共通約定與 §4 決策登記簿**——分冊裡的設計都以這兩節為前提。
>
> 上游：原型 `docs/design/chilllove-platform-admin.html`（開 ⌗ 註釋模式）｜定位與權限 `docs/design/32`｜競品拆解與機制數值 `docs/design/33`｜響應式 `docs/design/34`｜API 慣例 `docs/research/28` §0｜品質底線 `docs/specs/11` §0。

## 1. 分冊索引

| 分冊 | 模組 | 波次 | 主要風險 |
|---|---|---|---|
| **36 營運線** | 總覽／租戶列表與詳情十分頁／審核佇列 KYC／工單 | W1（工單 W2） | 12 態狀態機與六級處置的耦合；代登入授權流 |
| **37 金流線** | 計費與催繳／清結算／爭議與風控 | W1 表・W2 畫面 | 電支條例（無資金池）；爭議率雙分母；金鑰保管 |
| **38 信任安全與治理** | 違規處置／申訴／合規（DSR・發票・個資・巡檢）／審計日誌／人員與權限 | W1–W3 | 審計 append-only 真做到；DSR 法定時限；發票字軌 |
| **39 平台工程** | 可靠性與事故（狀態頁）／發布與灰度／環境與備份／公告與棄用／平台設定 | W3–W4 | 維護視窗須暫停 webhook；狀態頁對外揭露邊界 |

**M0 必須先埋的表**（否則 W1 落地要動大表，違反 strong_migrations）：`shops.status` 多態 enum、六個限制旗標、`kyc_submissions`／`kyc_requirements`／`kyc_documents`、`platform_audit_logs`（含 `previous`/`next` JSON）、`access_grants`、`billing_subscriptions`／`dunning_attempts`、`limits_overrides`。詳見 33 §4。

## 2. 共通約定（所有分冊的前提）

### 2.1 命名與目錄

```
app/models/platform/          平台域 model（無 shop_id 的表）
app/services/platform/        服務物件，一個檔一個責任
app/jobs/platform/            背景任務，第一參數恆為可還原 tenant 的 id
app/graphql/platform/         Platform:: schema、types、mutations、resolvers
config/limits.yml             所有上限的單一真相（禁硬編碼）
docs/dev/m{N}-{功能}.md       每個功能一篇（AGENTS.md 強制）
```

### 2.2 多租戶鐵律與其例外

全業務表帶 `shop_id`、複合索引以 `shop_id` 開頭。**平台域表是唯一例外**（`platform_staffs`、`platform_audit_logs`、`platform_daily_rollups`、`jit_elevations`、`dispute_program_states` 等，分冊 38 §12.3 有完整白名單共 21 張）。例外表必須：① migration 檔頭註明理由 ② 列入 CI 靜態檢查白名單 ③ 位於 `Platform::` namespace。

跨租戶查詢**只准**出現在 `Platform::` 命名空間並顯式 `ActsAsTenant.without_tenant`；CI 掃描其他路徑出現 `without_tenant` 即 fail。

### 2.3 API 慣例（28 §0，逐條落地）

- 端點 `/platform/api/{version}/graphql.json`，與 `/admin/api/...` 分離；`platform_staffs` session 認證＋CSRF；bot 走 token。
- GID `gid://chilllove/{Type}/{id}`；分頁 cursor＋`pageInfo`（≤250）；陣列參數 ≤250。
- **業務錯誤走 `userErrors{field,message,code}`，HTTP 恆 200**；transport 層錯誤才用 HTTP 狀態碼。
- 金額 `MoneyV2`（Decimal 字串，**絕不 float**）；DB 一律 `_cents BIGINT`。
- 成本制限流：`extensions.cost`；超限回 `THROTTLED`（GraphQL 面）／429＋`Retry-After`（前台 Ajax 面）。
- 寫入型操作帶 `idempotencyKey`。

### 2.4 統一的 userErrors code 表

| code | 意義 | 使用時機 |
|---|---|---|
| `FORBIDDEN` | 角色不足 | 權限矩陣未授權 |
| `NOT_FOUND` | 對象不存在或跨租戶不可見 | **不可區分兩者**（避免探測） |
| `INVALID_STATE` | 狀態機不允許此轉移 | 例：closed 店再凍結 |
| `MISSING_REASON` | 危險動作缺原因碼 | 凍結／關店／覆寫 |
| `LIMIT_EXCEEDED` | 超出 `config/limits.yml` | 配額 error 段 |
| `IDEMPOTENCY_CONFLICT` | 同 key 不同 payload | 冪等衝突 |
| `PRECONDITION_FAILED` | 前置條件未滿足 | 例：關店未滿 30 天就刪除 |
| `THROTTLED` | 成本制限流 | — |
| `REQUIRES_SECOND_APPROVAL` | 四眼原則待核 | 金流變更、刪除排程 |
| `LEGAL_HOLD` | 被法律保全阻擋 | DSR erasure 撞 hold |

### 2.5 危險動作的統一規約

任何「不可逆或影響租戶營運」的操作一律：**原因碼必選 → 二次確認（刪除類需輸入商店名）→ 落審計（含 before/after）→ 通知租戶 → 可申訴**。四眼原則適用於：金流通道／費率變更、排程刪除、重設租戶 2FA、break-glass 使用。

### 2.6 測試慣例

- 每個 mutation 至少四個案例：happy／權限不足（`FORBIDDEN`）／狀態不允許（`INVALID_STATE`）／冪等重放。
- 併發要害必測：重複 webhook、同時重試扣款、爭議與退款同時入帳、狀態轉移競態。
- 審計不可竄改要有測試（嘗試 update/destroy 應拋錯，且 DB 帳號無權限）。
- 響應式六寬度驗證進 CI（34 §6）。

## 3. 三端對接的位置（本手冊的邊界）

平台後台的動作會穿到另外兩端，這些跨端效應寫在各分冊的「副作用」欄，實作時**必須同時改三端**：

| 平台動作 | 商家後台 | 買家前台 |
|---|---|---|
| 凍結（offline 旗標） | 唯讀＋橫幅；帳單頁仍可讀 | 503＋noindex＋暫停頁；30 天後訂單狀態頁恢復 |
| 關店 | 唯讀至本期結束 | **410**（30 §9 死鏈規範） |
| 收款凍結（payin） | 顯示原因橫幅 | 結帳頁停用，商品頁照常 |
| 暫停營業（paused） | 折扣／棄單挽回／禮品卡停用 | 商品可看、**結帳關閉** |
| 上限覆寫 | 用量頁即時反映 | — |
| flag 逐店覆寫 | 功能出現／消失 | 主題功能出現／消失 |
| 維護視窗 | 唯讀＋預告橫幅 | 維護頁；**webhook 投遞暫停** |

## 4. 決策登記簿（動工前必讀）

四位撰稿者在寫作過程中發現 **17 條規格衝突**與 **127 項待定**。以下是已裁決的部分；未裁決者標「⚠️ 需使用者確認」，Codex 遇到時**在 PR 註明假設，不要靜默猜測**（AGENTS.md 工作規約）。

### 4.1 已裁決（分冊依此撰寫，並回寫上游文件）

| # | 衝突 | 裁決 | 回寫 |
|---|---|---|---|
| D1 | 配額門檻：33 §2.10 的 60%/100% vs 32 §3-3 的 80%/95% | **採 60%/100%**（SFCC 三段式模型較完整） | 32 §3-3 作廢 |
| D2 | 審計保留：33 §2.8 的 12 個月（PCI） vs 33 §2.13 台灣個資軌跡 5 年 | **`retention_class` 分流，未分類預設 5 年**（法規較嚴者優先；只做 12 個月即違法） | 33 §2.8 補註 |
| D3 | GDPR「1 個月」vs 原型寫「30 天」 | **雙時鐘並存，取嚴者為準**（曆月 ≠ 30 天） | 原型文案改 |
| D4 | 配額超額回 429 vs GraphQL HTTP 恆 200 | **GraphQL 面回 `THROTTLED`（extensions.cost），429 只給前台 Ajax 面** | 32 §3-3 補註 |
| D5 | `shops.feature_flags JSON`（32 §7） vs 獨立 flag 表（33 §6） | **獨立表為權威**（要支援 cohort 定向與審計，JSON 做不到） | 32 §7 改 |
| D6 | 寄件網域 `mail.chilllove.com`（specs/18 §F3） vs `.tw`（原型） | **`.tw`** | 18 §F3 改 |
| D7 | 角色矩陣 8 列（32 §5） vs 9 列（原型 RM） | **以原型 9 列為準**（多「金流通道變更 ✓＋四眼」） | 32 §5 補 |
| D8 | 「兩層權限不繼承」語意 | **平台層 ↔ 租戶層不繼承**（32 §0 已明訂獨立認證域）；商家組織層↔商店層屬未來多店組織範圍 | 33 §2.15 補註 |
| D9 | 用量顏色門檻 80/95 vs 60/100 | 同 D1 | — |
| D10 | 旗標與 status 的耦合關係未明文 | **套任一旗標且 status ∈ {active,trial,past_due} → 轉 `restricted`（記 `restricted_from_status`）；全解除→回復；`banned` 強制 `closed` 且僅 owner**。原型 `doRestrict()` 的 demo 推導寫法不可照抄（會破壞狀態機單一入口） | 33 §2.2 補 |
| D11 | 審計表無外鍵 vs specs/11 §2「每個外鍵都建 FK」 | **刻意違反**（MySQL 分割表不支援 FK，且刪店後審計須留存）；migration 檔頭註明 | 11 §2 加例外 |
| D12 | Kamal 自帶 Let's Encrypt（HTTP-01）**無法簽發** `*.mychilllove.com` 萬用憑證 | **必須改 DNS-01**（這是實作阻擋級發現） | 11 §1 修正 |
| D13 | 狀態頁 7 元件 vs 事故 modal 5 元件 | **補齊為 7**；33 的「5 元件狀態」指 5 種 status 值，非數量 | 原型改 |
| D14 | 佇列：specs/18 §F5 三優先級（2:2:1） vs 原型五領域 | **物理三佇列＋邏輯聚合顯示** | — |

### 4.2 ⚠️ 需使用者確認（阻擋開發的優先項）

**必須先答，否則會寫錯**：

1. **JIT 提權規格全缺**——原型引用「33 §B」但 33 號無此章節。需定義：可提權的動作清單、TTL 上限、核准人數（一人或兩人）、核准逾時處理。
2. **方案定價與計費模型**——四個方案月費／年費、GMV 抽成 bps、14 個加購模組單價、年繳折扣。33 只有競品數字，我們自己的未定。
3. **KYC requirements 完整清單**——原型只給 5 個 key 與四種主體的件數（個人 6／獨資 6／有限公司 9／股份 11），完整項目、各項 bucket 初值與 deadline 天數未定。
4. **申訴 SLA 範圍**——33 §2.7 的「3–7 工作天」原文是知識產權專屬，原型套到全部申訴（含 KYC 駁回、限流誤判）。是否一律套用？
5. **公告門檻**（哪些事故對外發布）——39 §6.3 的門檻表全部待填。
6. **API 版本起點**——28 §0.1 首版 `2026-08`（M0 已實作）vs 季度制 `01/04/07/10`。建議：admin API 保留 `2026-08`，平台 API 首版 `2026-10`，此後統一季度制。
7. **台灣工作日曆資料源**（補班日為台灣特有，第三方 gem 不可靠）——影響所有 SLA 與撥款 T+N 計算。
8. **平台自身收單通道**（收租戶月費用哪家）：綠界定期定額／藍新委託扣款／Stripe Subscriptions。
9. **KMS 供應商**（AWS KMS／GCP KMS／Vault Transit）——影響金鑰保管實作。
10. **`closed` 滿 2 年後**是否自動 purge？復店是否沿用原子網域？

**可先用建議預設值開發**（分冊已標建議值，日後可調）：授權碼試錯上限 5 次/15 分鐘、寬限延長上限 14 天、手續費對帳容忍 ≤NT$1、人工調整二次核准門檻 NT$10,000、負餘額抵扣順序（reserve → payout netting → invoice → absorb）、憑證輪換 90 天、回報值 vs 估算值偏差告警 20 bps。

**完整 127 項待定清單**分列於各分冊附錄：36 號 23 項｜37 號 26 項｜38 號 §12.2 共 31 項｜39 號 附錄 B 共 47 項。

## 5. 施工順序建議

1. **M0 併入**：33 §4 的必埋表（空表零成本，事後加欄位是生產風險）＋ `Platform::` 路由骨架 ＋ 兩套認證域分離 ＋ 審計表與其 DB 權限（38 號的四層防護要在第一版就對，事後補等於重來）。
2. **W1**：36 號全部 ＋ 38 號的審計與人員權限 ＋ 37 號的計費表與 dunning 引擎。
3. **W2**：37 號畫面 ＋ 38 號違規與申訴 ＋ 36 號工單 ＋ 配額三段式。
4. **W3**：38 號合規四線 ＋ 39 號可靠性／狀態頁／灰度／公告。
5. **W4**：39 號環境與備份。

每完成一個模組：跑該模組第 9 節測試清單 → 對第 10 節驗收逐條打勾 → 寫 `docs/dev/m{N}-{功能}.md` → 開 PR（Claude 會自動驗收）。
