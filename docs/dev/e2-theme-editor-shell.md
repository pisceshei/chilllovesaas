# 主題編輯器 shell＋頂欄（D79 E2）

## 概述
admin 主題編輯器（`/admin/themes/:id/editor`）的外殼與頂欄，依本尊 2026 編輯器逐控件實測
（`docs/research/100-theme-editor-live-teardown.md` §1／§5／§6／§7）重做：三欄版面（左欄面板切換器＋當前面板／
預覽／右欄只在選取時掛載）、頂欄全部控件（Exit、面板切換器、主題 chip、市場與模板選擇器、inspector、手機檢視、
Undo／Redo、「…」選單、Publish、Save）、四個對話框（快捷鍵表／離開確認／發布確認／建立模板）、快捷鍵單一表、
URL 狀態參數，以及全部走 tokens 的 CSS。給商家在後台客製主題用；對應 Shopify「Customize」進入的主題編輯器。

## 規格出處
- `docs/DECISIONS.md` D79（重做裁定與 E1–E7 序列）
- `docs/research/100-theme-editor-live-teardown.md` §1（頂欄逐控件與值域）、§1.1（模板選擇器）、§5（預覽模式）、
  §6（儲存／發布／快捷鍵／URL 參數）、§7（佈景設定手風琴、app embeds 空態）、§8（尺寸換算）、§V（未取得項）
- `docs/research/24` §1、`docs/research/66` A.3（既有資料模型與控件表，本包沿用）
- 本尊 help（100 §9.4）："You can use the undo and redo buttons to undo or redo unsaved customizations. After you save
  your changes, you can no longer redo or undo."

## 架構與資料流
- 前端入口 `app/frontend/admin/pages/ThemeEditorPage.tsx`（狀態源：draft／群組 draft／佈景設定 draft／快照棧／
  選取／面板／全寬／inspector／手機／對話框開關），頂欄與對話框拆到 `app/frontend/admin/editor/`：
  - `EditorTopBar.tsx`：三區版面與全部頂欄控件；面板切換器再點已啟用者 ⇒ `onFullscreen`。
  - `EditorIconButton.tsx`：32×32 icon 鈕＋純 CSS tooltip（名稱＋鍵帽）。
  - `TemplateSwitcher.tsx`：搜尋＋兩層清單（`templateKeys` ∪ `templateAssignments`）；`splitTemplateKey`。
  - `MarketSwitcher.tsx`：Store default（市場清單預留 prop，資料面待 Markets 包）。
  - `ShortcutsDialog.tsx`／`editorShortcuts.ts`：快捷鍵單一表（tooltip 鍵帽、對話框、綁定三處共用）。
  - `CreateTemplateDialog.tsx`：Name（≤25，`[A-Za-z0-9_-]`）＋Based on。
- 後端：`Types::ThemeType#template_keys`（來源 `templates/*.json` ∪ DB `Template` 列）、
  `#template_assignments`（各資源型依 `template_suffix` 分組計數；無該欄的型全數計入預設）。
- 預覽：既有 `POST /admin/store/preview/:theme_id/draft_section`／`draft_page` 與 postMessage 橋不變；
  新增 parent→iframe 的 `cl:inspector {active}`（E6 的橋消費，本包只維持狀態）。
- URL 狀態（`useSearchParams`，replace）：`template`／`section`／`block`／`context=theme|apps`／
  `previewMode=fullscreen`／`previewPath`／`category`。初載還原一次（`restoredRef`）。
- 儲存：`save()` 回傳布林；Publish＝有變更先 `save()` 再 `themePublish`；建立模板＝讀 base `templateJson`
  → `themeTemplateUpsert(key: "type.name")` → 切到新 key（`load` 隨 `template` 參數重跑，DB key 進 `templateKeys`）。

## API
- 既有：`themeEditorBootstrap` query（本包加 `templateKeys`、`templateAssignments` 兩欄）、
  `themeTemplateUpsert`／`themeSettingsUpsert`／`themeFileUpsert`。
- 本包接上：`themePublish(id)`（包 30 既有 mutation；本尊對位 `themePublish`）。
- 新 query `themeEditorBaseTemplate($id,$key){ theme { templateJson(key) } }`（建立模板讀 base）。

## 資料表
無 schema 變更。讀 `templates`（Template 列）、`products`／`collections`／`pages`／`blogs`／`articles` 的
`template_suffix`（後三者有此欄；前兩者無——`db/schema.rb`）。

## 關鍵取捨
- **右欄只在選取時掛載**（本尊兩欄形態），舊版常駐的「請選取」提示面板刪除；`cl-editor--with-panel` 切三欄。
- **佈景設定改到左欄手風琴**（本尊 100 §7），不再佔右欄；展開分類寫 `category=`。
- **快捷鍵鍵位**：本尊帶 `⊞` 的組合實際鍵位未取得（100 §V V3）⇒ 我方 Ctrl+Alt+1/2/3 與 Ctrl+Alt+I，避開
  Chrome 保留的 Ctrl+1..8；其餘照本尊逐字。modal 開著時全部不攔（`#admin-root` inert 或 `[role=dialog][aria-modal]`）。
- **Publish 先存再發布**：本尊對話框逐字 "Save and publish …?"；存失敗（STALE）就不發布。
- **CSS 全走 tokens**：舊 27 條硬編碼色值／尺寸移除；幾何取 100 §8 換算取整（頂欄 `--topbar-h`、側欄 300、
  樹列 32、設定列 48、縮排 16），色值 `--surface*`／`--text*`／`--border`／`--link`／`--sem-*`。
- **不做**：Sidekick／AI 入口（100 §V V13）、"Checkout and customer accounts"／"Create metaobject template"／
  "View documentation"／"Get support" 入口（無目標頁）、市場預覽切換（需 Markets GraphQL 面）。

## 測試
- 前端：`app/frontend/admin/pages/ThemeEditorPage.test.tsx` ED1–ED27（既有；ED1／ED3／ED9／ED14／ED16／ED18／
  ED19／ED22 隨 UI 改）＋ED28–ED34（面板切換與全寬、模板選擇器與建立模板、右欄掛載、離開確認、發布順序、
  快捷鍵、`block=`／`category=`）。跑法：`pnpm -s vitest run app/frontend/admin/pages/ThemeEditorPage.test.tsx`。
- 後端：`spec/requests/theme_editor_bootstrap_spec.rb` E9（templateKeys 含 DB-only key、不含 customers/）、
  E10（assignments 分組與無欄回落）。
- 突變輪（worklog 表）：fullscreen 不寫 URL、Publish 不先存、modal 開著仍攔鍵、建立模板空內容、右欄常駐、
  離開不確認——各自轉紅的測試在 worklog 逐項列。
- 手動：本機 admin 需登入（不得在表單輸入密碼），本包以 DOM 斷言替代目視；合併部署後在 bt3 以 demo 帳號
  （`/etc/chilllove/env`）由使用者目視。

## 已知限制與 TODO
- 市場選擇器只有 Store default；市場清單與預覽前綴待 Markets GraphQL 面。
- inspector 切換只送訊息，預覽側的 hover 覆疊開關在 E6。
- 左樹列解剖（chevron／type icon／drag handle／右鍵選單）與區段 picker 兩欄形態在 E3／E5。
- 手機預覽寬 390px 為既有值；本尊精確寬度未取得（100 §V V8）。

## 變更記錄
- 2026-09-04 E2：建立（分支 `editor/e2-shell-topbar`）
