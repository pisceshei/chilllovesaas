# HANDOFF — CHILL LOVE 專案交接文件（給接手的工程代理 / Codex）

> 你接手的是一個「復刻 Shopify 功能邏輯與交互、使用自有品牌視覺」的多租戶電商 SaaS 專案。**第一階段（研究＋規格＋高保真原型）已完成，你的任務是第二階段：把它蓋出來。** 本文件是唯一入口——照著讀完（約 15 分鐘），你就有完整上下文。

## 0. 十五分鐘上手路徑

1. 讀本文件（總覽、決策、紅線、工作規約）
2. 打開 `docs/design/chilllove-admin-v2.html`（瀏覽器直開）→ 點頂部列 **⌗ 圖示**開啟「開發註釋模式」→ 點虛線元素——**原型即規格書**，每個控制項的「功能／邏輯／實作」都在裡面
3. 讀 `docs/research/22-admin-button-inventory.md`（按鈕級對照表——你開發每一頁時的驗收清單）
4. 讀 `docs/design/23-interaction-css-spec.md`（design tokens 與交互規格——你寫每一行 CSS 的依據）
5. 動工前讀 `docs/research/10-implementation-playbook.md`（技術棧與 M0 開工清單）+ `docs/specs/11-production-baseline.md`（品質底線）
6. 其餘文件按需查閱（檔案地圖見 §6）

## 1. 專案是什麼

- **產品**：CHILL LOVE——多租戶電商 SaaS。商家註冊開店 → 後台管理（商品/訂單/顧客/折扣/分析/設定）→ 買家前台（主題化商店）→ one-page 結帳（Stripe）。
- **對標**：功能邏輯、頁面結構、交互行為 1:1 對齊 Shopify 2026 春季版後台（已實測走訪，見 `docs/research/21`）；視覺用自有設計語言（不是 Polaris）。
- **三階段**：研究（✅ 完成）→ demo 原型（🚧 M0 已建立，接續 M1–M6）→ 真產品。

## 2. 已鎖定的決策（不要重新辯論，除非使用者本人改變主意）

| 決策 | 內容 | 出處 |
|---|---|---|
| D1 技術棧 | **Rails 8.1 + MySQL 8 + Vite/React(TS) 後台 + Rails SSR/Hotwire 前台**；Stripe test mode；Solid Queue/Cache（不用 Redis） | `docs/DECISIONS.md` |
| D2 路線 | A→B→C：先成交閉環（M0–M3）→ 後台深化（M4–M5）→ 主題編輯器（M6） | 同上 |
| D3 品牌 | 平台名 **CHILL LOVE**，做成單一變數可改名 | 同上 |
| D4 前台引擎 | **Liquid 相容主題引擎**：liquid gem（MIT）＋自實作平台層與端點，第三方 Shopify 主題可匯入（授權 gate 必備）。取代 07/10 的 ViewComponent 簡化案 | `docs/research/25` |
| D5 API-first | admin SPA 與服務端**只走 GraphQL Admin API**（1:1 仿 Shopify 慣例：GID/cursor/userErrors/cost/MoneyBag/webhooks HMAC） | `docs/research/28` |
| D6 基建對映 | 全面走 Shopify 路線：demo 形態→生產路線對照表（MySQL→Vitess、Solid Queue→Kafka、ngram→OpenSearch、imgproxy CDN、獨立 renderer） | `docs/DECISIONS.md` D6 |
| D7 國際化與 SEO | Markets P0→P2 路線（29 號）；SEO 合規內建 storefront；GMC 規格 feed 生成器＋Merchant API；IndexNow；Simprosys 雙軌 | `docs/research/29/30` |
| 架構原則 | 單體 monorepo；全表 `shop_id`；金額 integer cents；寫路徑冪等；outbox 事件 | `docs/research/08` §7、`docs/specs/11` |

## 3. 法律紅線（絕對不可越）

1. **不可使用** `@shopify/polaris`、Polaris icons/插圖、**Dawn/Horizon 主題代碼**——Polaris 授權限 Shopify 整合應用；Dawn/Horizon 的 LICENSE 明文「僅限與 Shopify 互通、其他用途一律禁止」（**非純 MIT**，2026-06 Shopify v. SHOPLINE 和解先例證明會執法；見 `docs/research/25` §8）。icon 用 **Lucide（MIT）**。
2. 不可抄 Shopify 的 CSS 源碼、圖片資產、品牌與文案；**可以**實作相同的功能邏輯、佈局結構、交互行為（不受著作權保護），視覺值用我們自己的 token 表（23 號文件）。
3. 例外：**Liquid gem、theme-check（TS）、theme-liquid-docs 是標準 MIT**——這是 D4 主題引擎的法律基礎，可自由使用。
4. Theme Store 主題授權限「單一 Shopify 商店」：平台**不預載、不散布**任何 Shopify 主題；第一方預設主題從零自寫；商家匯入第三方主題必須通過**授權聲明 gate**（25 §8 產品義務）。**例外：Ella 7.2.0 使用者已購授權**——已入倉作 golden theme 測試 fixture（`test/fixtures/themes/ella-7.2.0`，倉庫保持私有），開發與測試放心用；仍不得散布給其他商家。
5. 產品內不得出現 Shopify 字樣或其品牌視覺；行銷話術用「相容 Shopify 主題格式」。

## 4. UI 與交互的單一真相（你的 CSS 從哪來）

- **Token 表**：`docs/design/23-interaction-css-spec.md` §1——admin 與 storefront 兩套完整 CSS 變數，直接複製進專案，不要自創值。
- **交互規格**：同文件 §3–§5——每個元件的狀態、鍵盤、ARIA、動效參數。
- **視覺對照**：三個高保真原型就是驗收基準（像素級照抄它們）：
  - `chilllove-admin-v2.html`——後台全導航樹（2026 結構：淺色頂列、pulse 首頁、AI 框、檢視下拉、訂單詳情、分析、設定 12 分頁）
  - `chilllove-admin-preview.html`——v1（商品詳情頁的 save bar 交互看這裡）
  - `chilllove-storefront-preview.html`——前台品牌方向（cart drawer、免運進度條）
- **圖表**：一律遵守 dataviz 規格（單系列 #2a78d6、2px 線、10% 面積、髮絲網格、hover 十字、附數據表格；色板已過對比驗證）。

## 5. 開發路線與驗收

| 里程碑 | 內容 | 驗收 |
|---|---|---|
| M0 地基 | Rails 骨架、40 表 migration（`docs/research/06` §7）、`config/limits.yml`（22 §9.4 常數表）、tokens.css、第一批元件、admin shell、多租戶 middleware、staff 認證 | 登入看到 CHILL LOVE shell + 商品空狀態 |
| M1 商品線 | Products CRUD＋變體 diff 更新＋媒體＋系列＋庫存 ledger | 22 §2 逐行打勾；併發加購不超賣測試 |
| M2 前台線 | **Liquid 引擎接入**（31 號 M2a/M2b：T0 filters/drops＋圖片管線＋字型庫＋搜尋推薦後端）＋自寫預設主題＋`/cart/*.js` 家族與 SRA＋**i18n P0**（29 號：locales/translations/多幣顯示）＋**SEO 基線**（30 §9：canonical/JSON-LD/sitemap/robots/410） | 預設主題全站可逛、cart drawer 走相容端點；Rich Results 測試通過；切語言雙層翻譯生效 |
| M3 成交線 | one-page checkout＋金額引擎＋Stripe test＋訂單成立 | `docs/specs/15` 驗收清單全綠（併發 50 執行緒恰好 1 單等） |
| M4 履約線 | 訂單詳情全功能（出貨/退款/取消/編輯/時間軸）＋顧客 | 22 §1b guard 清單全實作 |
| M5 增長線 | 折扣引擎＋分析 rollup＋設定八域＋通知信＋**Markets P1**（29 號：市場模型/市場定價/hreflang 全量）＋**feed 生成器**（30 §9-8：GMC 規格＋Merchant API＋IndexNow） | `docs/specs/17/19` 驗收＋GMC 測試 feed 零錯誤 |
| M6 編輯器 | **31 號 M6a–M6c 全計畫**：編輯器 ED1–ED12（三面板/巢狀拖拽/30 控件/預覽橋 8 事件/draft 渲染/picker/佈景設定/代碼編輯/主題庫）＋安裝管線 IN＋R 線 T1 補完 | **31 §6 驗收矩陣全綠**（Ella/Dawn 復現版/OS 2.0 舊主題 × 十項；含 27 §8 十條） |
| M7 部署線 | **生產部署（真產品階段開始）**：Docker 化（web/worker/renderer 分離）＋Kamal 2 部署 staging＋production（`docs/research/10` 部署節）；secrets 管理；每日全量備份＋binlog 歸檔＋還原演練腳本（11 §2）；strong_migrations 上線 DDL 安全；租戶子網域萬用憑證＋自訂網域 CNAME 對應與 DNS 驗證（07 §租戶路由、28 §網域）＋平台子網域→自訂網域 301（30 §9-3） | staging 一鍵部署可重複執行；測試店以子網域與自訂網域皆可逛完前台＋下單；備份還原演練通過；`/up` 綠 |
| M8 運營線 | **可運營**：結構化日誌（request_id＋shop_id）＋錯誤上報＋關鍵指標 dashboard＋合成下單巡檢（11 §5）；Solid Queue 佇列監控與死信告警；webhook 投遞監控＋重試；成本型限流全面啟用（28 §0）＋登入/結帳防濫用；`Platform::` 平台後台（specs/12）：租戶列表/開停店/跨租戶監控；註冊開店流程（07 §租戶）；PII 遮罩＋審計日誌 | 11 §5 可觀測基線逐條就位；壓測下限流生效且 Retry-After 正確；平台後台可開/停店；巡檢告警可實際觸發 |
| M9 上線線 | **生產驗收**：全模組 11 §0 七維度終審；負載測試（結帳併發/瀏覽尖峰/`/cart/*.js` 突刺）＋EXPLAIN 慢查詢抽查；brakeman 0 高危＋bullet 0 報警；資安複核（session/CSRF/webhook HMAC/秘鑰輪換）；運營 runbook（部署/回滾/備份還原/事故分級）；法遵頁面模板（隱私/條款/退換貨） | **11 §9 上線前 checklist 全綠一條不缺**；併發 50 結帳恰好 1 單在生產拓撲重測通過；合成下單連續 24h 無失敗 |
| 貫穿 | **API-first 鐵律（D5）**：每個 admin 功能先寫 28 號對應操作，SPA 只打 GraphQL；schema lint 擋裸 float 金額與 offset 分頁 | 28 §18 六條驗收 |

每個功能上線前過 `docs/specs/11` §0 的**七維度驗收表**（安全/資料/併發/效能/可觀測/測試/合規）。各 specs 文件末尾都有該模組的具體驗收清單。

> **階段對應**：M0–M6＝第二階段 demo 原型（功能完整）；M7–M9＝第三階段真產品（可部署、可運營、生產級）。M9 全綠＝可上線運營的 SaaS。方案/計費屬 07 §7 P2 範圍，暫不在 M7–M9 內。

## 6. 檔案地圖

```
HANDOFF.md                ← 你在這裡
README.md                 ← 專案索引
docs/DECISIONS.md         ← 三大決策
docs/research/00–09       ← Shopify 逐模組研究（功能邏輯的百科）
docs/research/10          ← 實作手冊（工具/代碼草稿/M0 清單）
docs/research/21          ← 2026 春季版實測 teardown（結構差異）
docs/research/22          ← ★按鈕級對照表（每頁開發時的驗收清單）
docs/research/24          ← 主題編輯器＋結帳系統實測 teardown（Horizon/checkout editor）
docs/research/25          ← ★Liquid 相容層架構（D4 引擎/匯入管線/端點規格/授權紅線/編輯器契約摘要）
docs/research/26          ← ★Liquid API 全量 checklist（138 objects/30 tags/154 filters 分層）
docs/research/27          ← ★Golden theme：Ella 案例研究（卡片系統解剖/編輯器 8 事件契約/M6 十條驗收）
docs/research/28          ← ★API 契約（D5：慣例＋逐模組操作表＋webhooks＋前台面＋對接矩陣）
docs/research/29          ← 多語言/多貨幣/多市場（Markets 全機制＋表結構＋P0-P2）
docs/research/30          ← SEO/Merchant Center/社媒 feed/Simprosys（官方要求＋平台落地清單）
docs/research/31          ← ★主題引擎與編輯器完整補齊計畫（R/E/ED/IN/D 五線工作包＋驗收矩陣＋排期）
docs/specs/11–19          ← ★生產級規格（做法/代碼/坑/驗收）
docs/design/20            ← UI 方案（診斷/參考對象/工藝清單）
docs/design/23            ← ★tokens 與交互規格（CSS 單一真相）
docs/design/*.html        ← ★三個高保真原型（驗收基準；v2 含註釋模式）
docs/design/critique-*    ← 設計評審紀錄
```

## 7. 工作規約（每次開發循環）

1. **開新畫面前**：先讀 22 對應章節 + 打開 v2 註釋模式對照；先寫/更新註釋再寫代碼——註釋即規格。
2. **鐵律**：全表帶 `shop_id` 且複合索引開頭；金額全程 integer cents（出現 float 即 bug）；transaction 內禁外部 IO；一切上限引用 `config/limits.yml`；出現在 UI 的數字必須同源對帳（pulse=分析頁=列表 count）。
3. **每完成一段**：跑測試 → 對照 specs 驗收清單 → commit（訊息格式 `M1: products CRUD with variant diff`）→ push。
4. **註釋與文檔強制**：public 介面文檔註釋＋複雜邏輯「為什麼」註釋（引用規格出處）＋每個功能一篇 `docs/dev/m{N}-{功能}.md`（規範見 `AGENTS.md`、模板見 `docs/dev/README.md`）；驗收逐項檢查，缺了打回。
4. **不確定時**：查 docs 對應章節；仍不確定 → 在 PR/commit 註明假設，不要靜默猜。
5. 文案語言：繁體中文為主，技術名詞保留英文；金額顯示 `NT$1,480`（tabular-nums）。

## 8. 目前倉庫狀態

- Git 歷史：Phase 1 docs → teardown → v2 原型 → 按鈕對照+註釋模式 → 本交接包（見 `git log`）。
- GitHub：`https://github.com/pisceshei/chilllovesaas`（private）。以倉庫內容為準；若你拿到的是 zip，解壓後即完整專案。
- M0 應用程式地基已建立：Rails 8.1/MySQL 8、Solid Queue/Cache、租戶與 staff auth、版本化 Admin GraphQL、React Admin shell、48 張業務表；實作與驗證細節見 `docs/dev/m0-rails-skeleton.md`。

有問題先查文件；文件沒有答案的，才是真正需要問使用者的問題。祝順利。
