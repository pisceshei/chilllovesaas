# 主題編輯器預覽互動（D79 E6）

## 概述
預覽 iframe 內的互動依本尊（`docs/research/100-theme-editor-live-teardown.md` §5／§9.5）重做：inspector 開時 hover 目標
section／block 出藍框＋左上 chip（顯示名同左樹）；section 上下邊界各一顆藍色圓形「+」（tooltip "Add section"）點擊 ⇒ 區段
picker 開在該位置並在左樹標插入線；點選 ⇒ 父頁選中（左樹展開、右欄開面板、URL）並回推選中框＋浮動工具列（Duplicate／
Hide／Remove）；預覽內右鍵 ⇒ 左樹同款選單開在對應座標；inspector 關 ⇒ 無任何覆疊（頂欄鈕或 Ctrl+Shift+I）；橋派官方
`shopify:section:*`／`shopify:block:*`／`shopify:inspector:*` 事件（主題 JS 依賴）；`Shopify.designMode` 改官方語義（非編輯器
＝undefined）。橋腳本抽成獨立檔，引擎注入與 vitest（jsdom）執行同一份。

## 規格出處
- `docs/DECISIONS.md` D79；`docs/research/100` §5（hover／點選／浮動工具列／右鍵／inspector／手機檢視）、§6（URL）、§9.5
  （shopify.dev 編輯器契約逐字：`Shopify.designMode`＝"set to `true` when viewing the theme editor. Otherwise, it's set
  to `undefined`."；事件 `shopify:section:load`（"A section has been added or re-rendered"）／`unload`／`select`／`deselect`／
  `reorder`、`shopify:block:select`／`deselect`、`shopify:inspector:activate`／`deactivate`，bubble、target＝section／block
  元素；block 定位靠 `{{ block.shopify_attributes }}`）。
- `docs/research/14` §F3（postMessage 契約：同源、origin 嚴格比對）。
- 佐證（2026-09-03 curl `https://hoko.vip/` 公開頁 HTML）：整份不含 `Shopify.designMode`——與官方「Otherwise, it's set to
  `undefined`」一致；我方公開頁自本包起同樣不輸出該鍵。

## 架構與資料流
- `app/assets/javascripts/editor-bridge.js`（IIFE；契約在檔頭）：
  - 父 → 子：`cl:highlight {id, blockId}`（選中框＋捲到＋工具列＋派 select／前者 deselect）、`cl:replace {id, html}`（unload →
    replaceWith → load；選中段跟到新元素）、`cl:inspector {active}`（關 ⇒ hideAll＋派 deactivate）、`cl:names {sections, blocks,
    labels}`（chip 文字＋工具列／插入點文字跟 admin 語系）。
  - 子 → 父：`cl:select {id, blockId}`、`cl:op {op: duplicate|hide|remove, id, blockId}`、`cl:insert {id, position}`、
    `cl:contextmenu {id, blockId, x, y}`、`cl:navigate {path}`。
  - 覆疊件全部 `position:absolute`（捲動位移）＋inline `display:none` 初始；視覺自有（藍＝`--link` #005bd3、工具列 #303030）。
- 引擎：`ThemeEngine::Runtime::EDITOR_BRIDGE_JS`＝載入時 `File.read` 該檔包 `<script>`；`PageRenderer` 只在 design_mode 注入
  （既有）；`ShopifyGlobal.script` 只在 design_mode 輸出 `Shopify.designMode = true;`。
- 頁面 `ThemeEditorPage.tsx`：訊息處理加 `cl:insert`（band／index ⇒ `pickerFor`，錨點＝iframe）、`cl:contextmenu`（iframe 座標
  ＋預覽內座標 ⇒ `treeRef.openMenuAt`）、`cl:op` 帶 blockId／`hide`（`duplicateNode`／`toggleNodeDisabled`／`removeNode`）；
  `cl:names` 由 `bands` 推（顯示名＝實例 name（t: 翻譯）?? schema／def name）＋iframe `onLoad` 重推（連同 `cl:inspector`）。
- `SectionsTree`：`forwardRef`＋`openMenuAt(band, sectionId, path, x, y, disabled)`；`Popover`：`edgeRef`（E5b：picker 貼左欄
  卡片右緣）；`SectionPicker` 透傳 `edgeRef`。

## API
無 GraphQL 變更；postMessage 契約如上。

## 資料表
無 schema 變更。

## 關鍵取捨
- **橋抽檔**：Ruby 常數字串無法前端測；抽成 JS 檔後 vitest 以 `?raw` 載入在 jsdom 執行（6 例），引擎仍注入同一份。
- **cl:insert 的 picker 錨點**：本尊貼插入線正下方；我方錨在 iframe（x 貼左欄右緣、y 頂對齊）——登記差異（E7 視覺細修）。
- **右鍵座標**：iframe 左上＋預覽內 clientX/Y（同一視窗，未考慮 iframe 內縮放）。
- **事件派發時機**：select／deselect 在父頁 `cl:highlight` 回推時派（父頁是選取真相源）；`load` 在 `cl:replace` 換段後派。
- **不做**：Sidekick "Ask for changes"（100 §V V13）、`shopify:section:reorder`（拖放重排走整頁 draft 刷新）、手機檢視寬度
  （維持 390；本尊換算≈358⇒375 級，§V）。

## 測試
- `app/frontend/admin/editor/editorBridge.test.ts` B1–B6（hover／insert／select／navigate／contextmenu／highlight 事件／工具列
  op／inspector／replace／異 origin）。
- `app/frontend/admin/pages/ThemeEditorPage.test.tsx` ED55（cl:insert ⇒ picker＋插入線＋插到 index）、ED56（cl:contextmenu ⇒
  同款選單、block 專屬項）、ED57（cl:op hide／duplicate／remove 帶 blockId、異 origin）、ED58（onLoad 推 cl:names＋labels＋
  cl:inspector；改名重推）。
- 後端 `spec/requests/theme_shopify_global_spec.rb` SG1（公開頁不輸出 designMode）、`theme_editor_bootstrap_spec.rb` BR3
  （橋只在 editor 預覽注入）。
- 突變 M45–M54（worklog 表）。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）
- 主題 JS：`shopify:section:select` 等事件開始有真的派發（Ella Promotion popup 選中即彈）；`Shopify.designMode` 在公開頁改為
  undefined（主題以 `if (Shopify.designMode)` 判斷者不受影響；以 `=== false` 判斷者會變）。
- 左樹：`data-insert` 插入線也由預覽「+」觸發；右鍵選單可由預覽開啟。
- 後續 E7 RWD／視覺細修：picker 錨點貼插入線、手機檢視寬、chip 帶 type icon。

## §E9 全頁草稿改 token 重載（2026-09-03，使用者實測「改設定後預覽整頁錯亂」）

- 根因：srcdoc 文件繼承 admin 頁嚴格 CSP（91 §3.76；external-facts §G13）。
- 現行流程：改設定 → 400ms `draft_section`（片段 `cl:replace`，不變）→ 600ms `draft_page` **只存草稿回 `{token}`**
  → `previewSrc` 加 `&draft=token` 重載 iframe（真實 URL、ThemeCsp）→ `onPreviewLoad` 還原捲動與重送 `cl:names`／`cl:inspector`。
- 契約：`show?editor=1&draft=<token>`；token＝`SecureRandom.urlsafe_base64(18)`，cache 鍵 `editor-draft/v1/{shop}/{theme}/{token}`，
  TTL 20 分；非 editor、錯 token、跨主題一律不套（DT2–DT4）。
