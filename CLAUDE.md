# CLAUDE.md — 專案共用規則（Claude 在本倉庫的任何工作都遵守）

> 分工：**Codex 實作**（守則見 `AGENTS.md`）、**Claude 審核驗收**（依本檔與 docs 規格）。完整上下文入口：`HANDOFF.md`。

## 專案是什麼

CHILL LOVE——多租戶電商 SaaS，功能邏輯與交互 1:1 對齊 Shopify 2026 春季版，視覺用自有設計語言。第一階段（研究＋規格＋高保真原型＋Liquid PoC）已完成；現在做第二階段實作，里程碑 M0–M6 見 `HANDOFF.md` §5。

## 技術鐵律（違反＝退回修改）

1. **技術棧（D1/D4）**：Rails 8.1 + MySQL 8 + Vite/React(TS) admin + Liquid 相容前台；Solid Queue/Cache，不用 Redis；不引入未討論的重型依賴。
2. **多租戶**：全表帶 `shop_id`，且複合索引以 `shop_id` 開頭。
3. **金額**：全程 **integer cents**，出現 float 即 bug；序列化層才轉 `MoneyV2` / `MoneyBag`。
4. **API-first（D5）**：admin SPA 只打 `/admin/api/{version}/graphql.json`；命名 `resourceVerb`；業務錯誤走 `userErrors{field,message,code}`（HTTP 恆 200）；分頁用 cursor＋`pageInfo`（≤250）；GID 格式 `gid://chilllove/{Type}/{id}`。契約見 `docs/research/28`。
5. **冪等與事件**：訂單成立／退款／庫存調整必帶 `idempotencyKey`；transaction 內禁外部 IO；事件走 outbox。
6. **上限值**：一律引用 `config/limits.yml`（常數表見 `docs/research/22` §9.4），不得硬編碼。
7. **數字同源**：同一指標在 pulse／列表 badge／分析頁必須來自同一 rollup 查詢。
8. **UI 值**：一律取自 `docs/design/23-interaction-css-spec.md` §1 的 tokens，不自創色值與尺寸；icon 用 Lucide（MIT）。
9. **法律紅線**：不用 `@shopify/polaris`、不抄 Dawn/Horizon 代碼與 Shopify 的 CSS/圖片/文案/商標；Liquid gem、theme-check、theme-liquid-docs 為 MIT 可用；`test/fixtures/themes/ella-7.2.0` 是使用者已購授權的測試 fixture，僅供測試、不得隨平台散布。
10. **文案**：繁體中文為主、技術名詞保留英文；金額顯示 `NT$1,480`（tabular-nums）。

## 驗收基準

- 每個功能過 `docs/specs/11` §0 七維度（安全／資料／併發／效能／可觀測／測試／合規）；各 spec 末尾有該模組驗收清單。
- 畫面對照 `docs/research/22` 逐按鈕打勾；原型 `docs/design/chilllove-admin-v2.html`（開「⌗ 註釋模式」可看每個控件的功能／邏輯／實作）。
- 主題引擎 golden theme＝Ella：`docs/research/27` §8 十條、`docs/research/31` §6 矩陣；Liquid API 面對照 `docs/research/26`。
- 併發要害必須有測試：超賣、折扣用量、退款上限。
- **註釋與文檔強制驗收**（缺了一律 🔴 打回）：public 介面缺文檔註釋；複雜邏輯（金額/併發/冪等/Liquid 相容）缺「為什麼」註釋與規格出處；新增功能 PR 缺 `docs/dev/m{N}-{功能}.md`（規範見 `AGENTS.md` 註釋與文檔節、模板見 `docs/dev/README.md`）。

## 文件地圖

`docs/research/00-10` 模組研究｜`21/22` 實測與按鈕表｜`24` 編輯器與結帳 teardown｜`25/26/27/31` Liquid 引擎四件套｜`28` API 契約｜`29` Markets 國際化｜`30` SEO 與 feed｜`docs/specs/11-19` 生產級規格｜`docs/design/20/23` UI 方案與 tokens｜`poc/liquid-engine` 引擎 PoC。

## 工作方式

- **每次工作結束前，一律寫交接文件**：`docs/handoff/YYYY-MM-DD-<主題>.md`，並與該次改動一起 commit。四段固定：①我改了什麼 ②為什麼這樣改（含被推翻的假設）③還有什麼沒解決 ④下一個人要注意什麼。這是硬性規則，不是選配。
- **原型改動後跑 `python3 scripts/lint-prototype.py`**（ERROR 必須為 0）。它把 49/51/53 號稽核的不變量固化了，每條規則都註明對應事故——尤其「同檔頂層函式不得重名」，那次事故是整頁功能靜默消失。
- 開新畫面前先讀 `docs/research/22` 對應章節與相關 spec；規格沒寫到的才問使用者。
- 分支 `m{里程碑}/{功能}`，PR 描述附「對應規格章節＋自測結果＋假設清單」；不直接推 main。
- 不確定時在 PR 註明假設，不要靜默猜測。
