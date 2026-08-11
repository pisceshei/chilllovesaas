# AGENTS.md — 給 Codex（實作代理）的工作守則

> 你是本專案的**實作方**。驗收方＝Claude（依 docs 規格審核）。分工鐵律：你寫代碼開 PR，不自行合併；規格有疑義以文檔為準，文檔沒有答案才問使用者。

## 開工前（每個任務都要）

1. 先讀 `HANDOFF.md`（15 分鐘上手路徑、決策 D1–D7、法律紅線、里程碑 M0–M6）。
2. 開發某畫面/功能前，讀對應章節：`docs/research/22`（按鈕級驗收清單）、`docs/specs/11–19`（生產級做法與坑）、`docs/research/28`（API 契約——**admin 一切走 GraphQL**）、`docs/research/31`（主題引擎工作包）。
3. UI 一律以 `docs/design/23-interaction-css-spec.md` 的 tokens 為準；對照 `docs/design/chilllove-admin-v2.html` 原型（開「⌗ 註釋模式」看每個控件的規格）。

## 工作流

- **分支**：`m{里程碑}/{功能}`（例 `m0/rails-skeleton`、`m1/products-crud`）。**永不直接 push main**。
- **PR**：一個 PR 對應一個可驗收單元；描述必附「對應規格章節＋自測結果＋假設清單」。
- **commit 格式**：`M1: products CRUD with variant diff`。
- **驗收**：PR 開出後由 Claude 對照 specs 驗收清單審核（跑測試＋逐條打勾）；修改意見回到 PR，通過才合併。

## 技術鐵律（違反即打回）

1. 技術棧：Rails 8.1 + MySQL 8 + Vite/React(TS) admin + Liquid 相容前台（D1/D4）；不引入未討論的重型依賴。
2. 全表帶 `shop_id` 且複合索引開頭；金額全程 **integer cents**（出現 float 即 bug）；transaction 內禁外部 IO；上限引用 `config/limits.yml`。
3. admin SPA 只打 `/admin/api/{version}/graphql.json`（28 號慣例：GID/cursor 分頁/userErrors/MoneyBag）；業務錯誤走 userErrors 不走 HTTP 4xx。
4. 寫路徑冪等（訂單成立/退款/庫存調整必帶 idempotencyKey）；事件走 outbox。
5. **法律紅線**：不用 `@shopify/polaris`、不抄 Dawn/Horizon 代碼與 Shopify CSS/資產/文案；icon 用 Lucide；Liquid gem（MIT）可用。`test/fixtures/themes/ella-7.2.0` 是使用者已購授權的測試 fixture——僅限測試，不得散布。
6. 文案繁體中文；金額顯示 `NT$1,480`（tabular-nums）。

## 測試與驗收基準

- 每功能過 `docs/specs/11` §0 七維度；併發場景（超賣/折扣用量/退款上限）必須有測試。
- 主題引擎相關：golden theme＝Ella（`docs/research/27` §8 十條、31 §6 矩陣）；Liquid API 面對照 `docs/research/26` 清單。
- 跑 `bundle exec rspec`＋`npm test` 綠了才開 PR。
