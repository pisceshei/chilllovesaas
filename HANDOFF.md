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
- **三階段**：研究（✅ 完成）→ demo 原型（🔜 你負責，里程碑 M0–M6）→ 真產品。

## 2. 已鎖定的決策（不要重新辯論，除非使用者本人改變主意）

| 決策 | 內容 | 出處 |
|---|---|---|
| D1 技術棧 | **Rails 8.1 + MySQL 8 + Vite/React(TS) 後台 + Rails SSR/Hotwire 前台**；Stripe test mode；Solid Queue/Cache（不用 Redis） | `docs/DECISIONS.md` |
| D2 路線 | A→B→C：先成交閉環（M0–M3）→ 後台深化（M4–M5）→ 主題編輯器（M6） | 同上 |
| D3 品牌 | 平台名 **CHILL LOVE**，做成單一變數可改名 | 同上 |
| 架構原則 | 單體 monorepo；全表 `shop_id`；金額 integer cents；寫路徑冪等；outbox 事件 | `docs/research/08` §7、`docs/specs/11` |

## 3. 法律紅線（絕對不可越）

1. **不可使用** `@shopify/polaris`、Polaris icons/插圖、Dawn 主題代碼——Polaris 授權限制用於 Shopify 整合應用（見 `docs/research/02` §1）。icon 用 **Lucide（MIT）**。
2. 不可抄 Shopify 的 CSS 源碼、圖片資產、品牌與文案；**可以**實作相同的功能邏輯、佈局結構、交互行為（不受著作權保護），視覺值用我們自己的 token 表（23 號文件）。
3. 例外：**Liquid gem 是 MIT**，通知信模板可直接用。
4. 產品內不得出現 Shopify 字樣或其品牌視覺。

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
| M2 前台線 | Storefront SSR＋theme JSON 渲染＋cart drawer（Turbo） | storefront-preview 還原度 |
| M3 成交線 | one-page checkout＋金額引擎＋Stripe test＋訂單成立 | `docs/specs/15` 驗收清單全綠（併發 50 執行緒恰好 1 單等） |
| M4 履約線 | 訂單詳情全功能（出貨/退款/取消/編輯/時間軸）＋顧客 | 22 §1b guard 清單全實作 |
| M5 增長線 | 折扣引擎＋分析 rollup＋設定八域＋通知信 | `docs/specs/17/19` 驗收 |
| M6 編輯器 | 三欄主題編輯器 | `docs/specs/14`-F3 |

每個功能上線前過 `docs/specs/11` §0 的**七維度驗收表**（安全/資料/併發/效能/可觀測/測試/合規）。各 specs 文件末尾都有該模組的具體驗收清單。

## 6. 檔案地圖

```
HANDOFF.md                ← 你在這裡
README.md                 ← 專案索引
docs/DECISIONS.md         ← 三大決策
docs/research/00–09       ← Shopify 逐模組研究（功能邏輯的百科）
docs/research/10          ← 實作手冊（工具/代碼草稿/M0 清單）
docs/research/21          ← 2026 春季版實測 teardown（結構差異）
docs/research/22          ← ★按鈕級對照表（每頁開發時的驗收清單）
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
4. **不確定時**：查 docs 對應章節；仍不確定 → 在 PR/commit 註明假設，不要靜默猜。
5. 文案語言：繁體中文為主，技術名詞保留英文；金額顯示 `NT$1,480`（tabular-nums）。

## 8. 目前倉庫狀態

- Git 歷史：Phase 1 docs → teardown → v2 原型 → 按鈕對照+註釋模式 → 本交接包（見 `git log`）。
- GitHub：`https://github.com/pisceshei/chilllovesaas`（private）。以倉庫內容為準；若你拿到的是 zip，解壓後即完整專案。
- 尚未有任何應用程式代碼——M0 從零開始，這是刻意的：規格先行。

有問題先查文件；文件沒有答案的，才是真正需要問使用者的問題。祝順利。
