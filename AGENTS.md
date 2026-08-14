# AGENTS.md — 給 Codex（實作代理）的工作守則

> 你是本專案的**實作方**。驗收方＝Claude（依 docs 規格審核）。分工鐵律：你寫代碼開 PR，不自行合併；規格有疑義以文檔為準，文檔沒有答案才問使用者。

## 開工前（每個任務都要）

1. 先讀 `HANDOFF.md`（15 分鐘上手路徑、決策 D1–D7、法律紅線、里程碑 M0–M6）。
2. 開發某畫面/功能前，讀對應章節：`docs/research/22`（按鈕級驗收清單）、`docs/research/71`（parity 總登記簿：§A 保護清單＋§F 差異登記）、`docs/research/7x` 該模組 teardown（72 首頁指標/73 財務帳單/74 顧客線/75 折扣…逐輪增補）、`docs/specs/11–19`（生產級做法與坑）、`docs/research/28`（API 契約——**admin 一切走 GraphQL**）、`docs/research/31`（主題引擎工作包）。
3. UI 一律以 `docs/design/23-interaction-css-spec.md` 的 tokens 為準；對照 `docs/design/chilllove-admin-v2.html` 原型（開「⌗ 註釋模式」看每個控件的規格）。
4. 🔴 **鐵律 12（Shopify 對齊鐵律，2026-08-13 使用者裁定）——實作方同樣受約束**：
   - **親自點擊、禁止猜 URL**：每個頁面/按鈕/欄位/選單/下拉都要點過；導航一律用真實 `href`。
   - **不存在「有問題的頁面」或 404**：只可能是①沒載完（等＋**重載 1–3 次**）或②你在猜路徑；
     **不得寫「本尊沒有這頁/這功能」**。
   - **測試店可寫入**：`chill-love-u5q5mnzq` 資料全假，使用者授權新增/編輯/刪除——**要走完整
     操作流程**（建立→修改→刪除）才算拿到狀態機與副作用；避免真實費用與對外發信。
   - **註釋四件事**（DOCS 與 `docs/dev/` 皆適用）：①這是什麼 ②具體功能與**完整值域** ③怎麼做出
     這效果（邏輯/狀態機/出處/limits 引用）④🔴**跨功能・跨頁・前端影響（預先對接）**。
5. 🔴 **階段對齊標準（2026-08-13 使用者裁定，硬性；六層）**：每個階段的實作必須與 Shopify 本尊保持一致性——
   **按鈕級完全複製功能邏輯與交互邏輯**（每個按鈕/欄位/值域/空態/錯誤態/狀態機）＋
   🔴 **值域窮舉**（所有下拉選單/下拉欄位/選擇器/autocomplete/⋯選單/分段控制的選項**全量**照抄，
   含原文、預設值、條件顯示規則——**enum 不得自創、不得省略**；7x teardown 檔是唯一權威值域來源）＋
   🔴 **依 7x 的架構圖實作**（URL 路由樹含 302 與 query 語義／頁面層級容器歸屬／跨頁共用元件家族——
   共用元件改一處要同步所有掛載點）＋**對照 CSS 量測**（7x 檔 §CSS 三段式：本尊量測值 → 我方 token
   映射；實作只用我方 tokens，鐵律 8/9）＋**結合 help.shopify.com 說明文檔**（實測＋help 雙源；
   上限值引 `config/limits.yml` 不硬編）＋**條件性控件三源判定**。
   與本尊的差異只有兩種合法形態：71 §A 保護清單（使用者裁定）或 §F 登記的 V——其餘一律做到一致；
   拿不準是否「本尊如此」時查對應 7x teardown，7x 沒寫的在 PR 標假設，不要靜默猜。

## 工作流

- **分支**：`m{里程碑}/{功能}`（例 `m0/rails-skeleton`、`m1/products-crud`）。**永不直接 push main**。
- **PR**：一個 PR 對應一個可驗收單元；描述必附「對應規格章節＋自測結果＋假設清單」。
- **commit 格式**：`M1: products CRUD with variant diff`。
- **驗收**：PR 開出後由 Claude 對照 specs 驗收清單審核（跑測試＋逐條打勾）；修改意見回到 PR，通過才合併。

## 技術鐵律（違反即打回）

1. 技術棧：Rails 8.1 + MySQL 8 + Vite/React(TS) admin + Liquid 相容前台（D1/D4）；不引入未討論的重型依賴。
2. **業務資料**全表帶 `shop_id` 且複合索引開頭；金額全程 **integer cents**（出現 float 即 bug）；transaction 內禁外部 IO；上限引用 `config/limits.yml`。
   <!-- 2026-08-14 裁定：身分與權限走**組織層白名單豁免**（71 §A G24 逐表列舉：organizations／
        users／roles／role_permissions／user_roles／user_groups／user_group_roles／
        user_store_assignments），白名單以外照舊。🔴 豁免的是「表有沒有 shop_id 欄」，
        **不是「查詢可不可以不帶 shop_id」**——跨店存取仍須先解析出可及 shop_id 集合再逐表帶條件。
        新增白名單表要改 CLAUDE.md 鐵律 2 與 71 §A G24，並在 PR 描述標明。 -->
3. admin SPA 只打 `/admin/api/{version}/graphql.json`（28 號慣例：GID/cursor 分頁/userErrors/MoneyBag）；業務錯誤走 userErrors 不走 HTTP 4xx。
4. 寫路徑冪等（訂單成立/退款/庫存調整必帶 idempotencyKey）；事件走 outbox。
5. **法律紅線**：不用 `@shopify/polaris`、不抄 Dawn/Horizon 代碼與 Shopify CSS/資產/文案；icon 用 Lucide；Liquid gem（MIT）可用。`test/fixtures/themes/ella-7.2.0` 是使用者已購授權的測試 fixture——僅限測試，不得散布。
6. 文案繁體中文；金額顯示 `HK$1,480`（tabular-nums），實際符號與小數位由市場的 locale 決定，不得硬編。
   <!-- 依 2026-08-12「基準法域＝香港」裁定（CLAUDE.md 鐵律 10/11）修正，原文：「金額顯示 `NT$1,480`（tabular-nums）。」
        🔴 台灣預設時代的殘留。Codex 以本檔為守則，示例值錯了會直接產出錯的基準。 -->

## 註釋與文檔（強制——缺了即打回，與技術鐵律同級）

> 目的：任何工程師或代理隨時接手，讀註釋與 `docs/dev/` 即可上手。把「以後有人接手」當成驗收標準來寫代碼。

1. **文檔註釋**：所有 public class/module/方法必須有文檔註釋——用途、參數、回傳、副作用（Ruby 用 YARD 風格，TS/React 用 TSDoc；繁體中文為主、術語保留英文）。React 元件註明 props 與對應 `docs/design/23` tokens 章節。
2. **「為什麼」註釋**：複雜業務邏輯（金額計算、併發控制、冪等、庫存 ledger、Liquid 相容行為、快取失效）必須註明設計原因並引用規格出處，例：`# 併發扣庫存用悲觀鎖，見 docs/specs/14 §3`。migration 檔頭註明對應 `docs/research/06` §7 的表定義條目。
3. **功能文檔**：每個新增功能的 PR 必須同時新增 `docs/dev/m{N}-{功能}.md`（模板與規則見 `docs/dev/README.md`）：概述、規格出處、架構與資料流、API 對應、資料表、關鍵取捨、測試、已知限制。修 bug／重構的 PR 則更新受影響的既有篇章。
4. PR 描述加一欄「文檔」：列出本 PR 的 docs/dev 變更；沒有變更要寫明理由（例：純 CI 修改）。

## 測試與驗收基準

- 每功能過 `docs/specs/11` §0 七維度；併發場景（超賣/折扣用量/退款上限）必須有測試。
- 主題引擎相關：golden theme＝Ella（`docs/research/27` §8 十條、31 §6 矩陣）；Liquid API 面對照 `docs/research/26` 清單。
- 跑 `bundle exec rspec`＋`npm test` 綠了才開 PR。
