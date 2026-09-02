# 100 — 本尊主題編輯器逐面板實測 teardown（2026-09，D79 的 E1）

> 對標＝admin.shopify.com 主題編輯器（2026 春季版）。實測店＝pnrjnw-sy（使用者全權授權，操作一律在
> 現行主題的 Duplicate 副本上）；補走 `docs/research/24` §1（2026-08 Horizon 局部實測）未覆蓋的層。
> 六層：⓪載入紀律 ①按鈕級功能與交互 ②值域窮舉 ③架構深度 ④CSS 量測三段式 ⑤help 雙源 ⑥條件控件三源。
> 🔴 編輯器本體在跨域 iframe（online-store-web.shopifyapps.com）：DOM 不可讀，量測走「截圖＋zoom」與
> 編輯器 CSS bundle（network 面板取 cdn.shopify.com 的 CSS 檔原文）兩路；每項標明來源與取證日期。

## 0. 操作紀錄（時間序，含 URL 去 token）

（逐步填寫）

## 1. Shell／頂欄

## 2. 左欄：面板切換器＋sections 樹

## 3. 右欄：設定面板（逐控件型別 26 型）

## 4. 區段 picker／區塊 picker

## 5. 預覽：裝置切換、inspector、hover 工具列、插入點

## 6. 儲存／發布／undo-redo／快捷鍵／URL 狀態

## 7. 佈景主題設定（全域 settings）與 app embeds

## 8. CSS 量測（token 值表 → 元件量測 → 我方 token 映射）

## 9. help.shopify.com 雙源對照

取證 2026-09-03（WebFetch 摘錄，逐字句以引號標示）。

### 9.1 sections-and-blocks（`/manual/online-store/themes/theme-structure/sections-and-blocks`）
- 新增區段：Online Store > Edit theme → sidebar 的 **"Add section"**，可從清單選或用 search field 找；行動版：tap **Sections** → **Add section**。
- 新增區塊：hover 區段 → **"Add block"**，可瀏覽或搜尋 block 型別。
- 重排：按住 **drag handle icon**（parallel horizontal lines）拖到目標位置（section／block 皆可）。
- 隱藏：hover 名稱 → **hide button（eye icon）**；行動版走選單。
- 複製：**Right-click** 區段或區塊 → **Duplicate**（含全部設定）。
- 移除：right-click 選 delete/remove，或 hover 點 **delete button**。
- 上限："Maximum of **25 sections per template**"、"Up to **1,250 blocks total across all sections**"、"**Eight levels maximum** for nested blocks"。

### 9.2 theme-settings（`/manual/online-store/themes/theme-structure/theme-settings`）
- 開啟：Online Store > Edit theme → sidebar 的 **Theme settings** icon（gear）。
- 分類（Horizon 世代命名）：Logo／Colors／Typography／Layout／Animations／Visual elements／Social media／
  Search behavior／Currency format／Cart／Custom CSS（"Enter your own CSS code, for example to customize the
  appearance of your online store's buttons"）／Theme style。分類實際由主題 settings_schema 決定。
- 儲存："Changes require clicking the **Save** button to apply store-wide updates across all pages."

### 9.3 customizing-themes 總覽
- "With the theme editor, you can preview your theme, make changes to your theme settings, and add, remove, edit,
  and rearrange content."（細節在 features-overview 子頁，另列 §9.4）

### 9.4 features-overview（`/manual/online-store/themes/customizing-themes/theme-editor/features-overview`）
- Sidebar 三個面板："Sections"（sections 與 blocks）、"Theme settings"（colors／typography 等全域）、"App embeds"。
- 預覽：desktop preview／mobile preview button；"preview inspector"；收合 sidebar ⇒ "a full-width preview of your storefront"。
- 頁面導航：template menu "navigate between different page templates in your theme"。
- Undo／Redo："You can use the undo and redo buttons to undo or redo unsaved customizations. After you save your
  changes, you can no longer redo or undo."
- Save 鈕；Sidekick（AI "assist you with theme customizations"）；market menu "preview and customize your theme for
  different markets"；快捷鍵總表入口 `CTRL + /`／`⌘ + /`。

### 9.5 shopify.dev 編輯器契約（tools/online-editor＋sections/integrate-sections-with-the-theme-editor）
- `Shopify.designMode`："set to `true` when viewing the theme editor. Otherwise, it's set to `undefined`."（⇒ 我方公開頁
  輸出 `designMode = false` 是差異：本尊為 undefined，登記修）；另有 `Shopify.inspectMode`／`Shopify.visualPreviewMode`；
  Liquid 側 `{% if request.design_mode %}`。
- 事件（bubble，target＝section／block 元素）：`shopify:section:load` {sectionId}（"A section has been added or
  re-rendered"，主題須重跑該 section 的 JS）；`shopify:section:unload` {sectionId}；`shopify:section:select`
  {sectionId, load}；`shopify:section:deselect`；`shopify:section:reorder`；`shopify:block:select` {blockId, sectionId,
  load}；`shopify:block:deselect`；`shopify:inspector:activate`／`deactivate`。
- Block 定位：主題須在 block 父元素手動輸出 `{{ block.shopify_attributes }}`。

## V. 待驗證／工具限制
