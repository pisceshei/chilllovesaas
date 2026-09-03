# 主題編輯器左樹（D79 E3）

## 概述
admin 主題編輯器左欄的 sections 樹，依本尊 2026 編輯器逐控件實測（`docs/research/100-theme-editor-live-teardown.md`
§2／§2.1／§2.2／§2.3／§4）重做：依 `layout/theme.liquid` 的 section group 位置分帶（Template 帶上方＝header 類、
下方＝footer 類）、列解剖（chevron／type icon／名稱＋摘要／hover 動作：drag handle、垃圾桶、眼睛）、隱藏列灰化＋眼睛
常駐、展開後第一個子列 "⊕ Add block"、theme block 巢狀（最深 8 層）、右鍵選單（Paste／Rename／Hide-Show／Add section
before-after／Edit code）、就地改名寫進 JSON `name`、鍵盤導航（Shift+↑↓／Shift+Enter／Ctrl+Shift+O／P）、每帶各自的
"Add section"（依 `enabled_on`／`disabled_on`／`limit` 過濾與灰化）、資源模板的 Preview 列，以及 `block=` 路徑化的
URL 狀態。給商家在後台客製主題用；對應 Shopify「Customize」左欄。

## 規格出處
- `docs/DECISIONS.md` D79（重做裁定與 E1–E7 序列）
- `docs/research/100-theme-editor-live-teardown.md` §2（分帶與群組小標、footer 帶 Add section 在最上面）、§2.1
  （Preview 列）、§2.2（列解剖、隱藏態、右鍵選單、巢狀）、§2.3（鍵盤）、§2.4（選取狀態掛 URL）、§4（picker 的
  群組限定與 "(1/1)" 灰化）、§8（列高 32／縮排 16）、§V（未取得項）
- 本尊 help（100 §9.1 摘錄）：theme block 巢狀 "**Eight levels maximum** for nested blocks"。
- Shopify section schema 官方文檔（<https://shopify.dev/docs/storefronts/themes/architecture/sections/section-schema>，
  取證 2026-09-03）逐字：`limit`＝"By default, there's no limit to how many times a section can be added to a template
  or section group. You can specify a limit of 1 or 2 with the `limit` attribute"；`max_blocks`＝"There's a limit of 50
  blocks per section. You can specify a lower limit with the `max_blocks` attribute."；`enabled_on`＝"You can restrict
  a section to certain template page types and section group types by specifying them through the `enabled_on`
  attribute."，`templates` 可為 "`["*"]` (all template page types)"、`groups` 可為 "`["*"]` (all section group types)"；
  `disabled_on`＝"You can prevent a section from being used on certain template page types and section group types by
  setting them in the `disabled_on` attribute."；"You can use only one of `enabled_on` or `disabled_on`."（兩者並存時
  我方 `sectionAllowedIn` 先看 `disabled_on`——官方不允許並存，此順序只是容錯，不是語義）。
- `docs/research/24` §2.4（section schema 與 theme block schema 欄位表：`limit(1|2)`、`max_blocks`、
  `enabled_on|disabled_on(templates[]/groups[])`）、`docs/research/66` §A.3（既有資料模型，本包沿用）；
  `docs/research/66` 另記 Ella 實測出現的 group 名 `header`／`footer`／`aside`／`custom.popup`。

## 架構與資料流
- 資料模型 `app/frontend/admin/editor/treeModel.ts`（純函式，無 React）：
  - `BlockPath = string[]`（section 內從第一層 block 到目標的 id 序列）；`encodeBlockPath`／`decodeBlockPath` 以 `__`
    串進 URL `block=`（`block=p1__l1`）；`MAX_BLOCK_DEPTH = 8`。
  - `getBlock(section, path)`／`getContainer`／`findBlockPath(section, leafId)`（預覽 `cl:select` 只帶葉 id 時反查路徑）。
  - `summaryOf(entry, defs)`：第一個 text／textarea／richtext／inline_richtext／html 型設定值，去 tag、40 字截斷——
    block 列「名稱 – 摘要」的來源（100 §2.2）。
  - `iconKindFor(type, name)`：關鍵字對映 type icon 種類（group／image／video／heading／link／button／text／block）。
  - `visibleBlockIds(container)`：`block_order` 內的可拖列 ＋ 不在其中的 `static: true` block（附在後）。Ella
    `templates/product.json` 的 media-gallery／product-details／sticky-atc 就是這種節點（只在 `blocks` map，不在
    `block_order`；`docs/research/66` §A.5.2）——只迭代 `block_order` 會讓整個靜態容器從樹上消失。
  - `TreeBand {band,label,position,groupType,tpl}`／`rowKey(band,sectionId,path)`／`flattenRows(bands, expanded)`
    （可視列扁平化：Shift+↑↓ 走的就是這張表，收合的子層不在其中）／`allExpandableKeys(bands)`（Ctrl+Shift+O）。
  - `sectionAllowedIn(availability, {templateType} | {groupType})`：`disabled_on` 先擋、`enabled_on` 有列才准、都沒寫＝准。
- 樹元件 `app/frontend/admin/editor/SectionsTree.tsx`（純展示，狀態全由頁面持有）：
  - 每帶一個 `<section>`：小標（群組 JSON `name`，無則檔名人性化）→ 列 → "⊕ Add section"；`position === "after"`
    的帶（footer 類）Add section 在列之上（100 §2）。
  - section 列與 block 列同構（`renderSectionRows`／`renderBlockRows`，block 列遞迴）：chevron 只在「有子項或可加子項」
    時顯示；type icon 在 hover 時被 drag handle（⋮⋮）取代；名稱鈕 `aria-pressed`＝選中；hover 動作垃圾桶（Remove）／
    眼睛（Hide／Show）；隱藏列 `is-hidden`（灰字）且眼睛 `is-persistent`（常駐）。static block 列：鎖 icon 取代 drag
    handle（`aria-label`＝「靜態區塊（固定位置）」）、`draggable=false`、無垃圾桶、不可作 drop 目標；仍可選取、改設定、隱藏。
  - 展開的 section／容器 block 的第一個子列＝"⊕ Add block"（點開列出可加型別；section 層依 schema `blocks` 且受
    `max_blocks`；容器層依 theme block 的 `blocks` 接受清單，`@theme`＝全部 theme blocks，深度 ≥ 8 不再列）。
  - 拖放：section 只在同帶內重排、block 只在同容器內重排（跨帶／跨容器 drop 忽略）。
  - 右鍵選單（`role=menu`）：Paste（灰）／Rename／Hide 或 Show（鍵帽 Ctrl Shift H）／section 列另有 Add section before／
    after／Edit code。Escape 或 pointerdown 選單外關閉。
- 資源列 `app/frontend/admin/editor/PreviewResourceRow.tsx`：`product`／`collection`／`page`／`blog`／`article` 模板時
  出現在標題下（"Preview"＋當前資源標題＋⌃⌄）；點列 ⇒ popover（搜尋＋清單，各型打既有 connection 取 25 筆）；
  選取 ⇒ `previewPath`；命中者右端鉛筆 ⇒ 開該資源的後台編輯頁（新分頁）。
- 頁面 `app/frontend/admin/pages/ThemeEditorPage.tsx`（狀態源）：
  - `bands`：`sectionGroups` 依後端 `position` 排在 Template 帶前後；`selectedPath: BlockPath`、`expanded: Set<rowKey>`、
    `renaming`／`renameValue`、`pickerFor {band, atIndex}`。
  - `blockDef(sectionType, path, type)`：第一層先找 section schema 本地 block 定義、否則 theme block；更深層先 theme
    block。`addBlockOptions(band, sectionId, parentPath)` 如上。
  - `selectNode(band, sectionId, path)`：寫 state＋URL（`section`、`block`），展開祖先（`expandTo`）。初載還原
    `?section=&block=` 時同樣展開祖先。
  - 操作全部走既有 `applyOp` 快照棧（undo／redo）：`toggleNodeDisabled`／`removeNode`／`moveNode`／`addBlockAt`
    （id＝型別名，重複則加 `-n` 尾碼；預設值取定義 `default`）／`commitRename`（`name` 寫入或清除）／`removeNode`
    對 static block 直接返回（面板底部的「移除 block」也不渲染）／`addSection`
    （插到 `pickerFor.atIndex`，`null`＝帶尾端）。
  - 快捷鍵表 `app/frontend/admin/editor/editorShortcuts.ts` 加 `selectPrev`（Shift+↑）／`selectNext`（Shift+↓）／
    `openSelected`（Shift+Enter：焦點進右欄第一個控件）／`expandAll`（Ctrl+Shift+O）／`collapseAll`（Ctrl+Shift+P）；
    Esc 在改名中先取消改名、否則取消選取。輸入控件內不攔導航類。
  - Add section 候選：`sectionCatalog` × `sectionAllowedIn`（Template 帶用模板型、群組帶用群組 `type`）；同帶同型
    數量達 `limit` ⇒ 灰化並標 "(n/limit)"（100 §4）。
- 後端 `app/graphql/types/theme_type.rb`：
  - `section_groups` 每組加 `label`（JSON `name`）、`type`（JSON `type`，無則檔名去 `-group`）、`position`
    （`{% sections 'x' %}` 在 `content_for_layout` 之前＝`before`、之後＝`after`）。
  - `section_schemas[type]` 加 `enabled_on`／`disabled_on`／`limit`。
  - `theme_blocks`：`blocks/*.liquid` 的 `{type, name, settings, blocks: 可接受子型別}`（保留 `@theme` 字面給前端展開；
    `@app` 略）。

## API
- 既有 `themeEditorBootstrap` query 加 `themeBlocks`（E2 已加 `templateKeys`／`templateAssignments`）；`sectionGroups`
  與 `sectionSchemas` 的 JSON 形擴欄如上。無新 mutation；儲存仍走 `themeTemplateUpsert`／`themeFileUpsert`。
- Preview 列讀既有 `products(first, query)`／`collections(first)`／`pages(first, query)`／`blogs`／
  `articles(first, query)`（Article 只有 `blogId`，前端以 `blogs { id handle }` 對出路徑）。

## 資料表
無 schema 變更。

## 關鍵取捨
- **樹只讀 `expanded` 集合、不自持狀態**：Shift+↑↓、Ctrl+Shift+O／P、URL 還原、`cl:select` 直開 block 都要改同一份
  展開狀態，放頁面才不會各持一份漂移。
- **顯示名＝JSON `name` ?? schema `name`**：本尊 Rename 的落點就是模板 JSON 的 `name`（Ella 匯出的 block 即帶此欄）；
  舊版顯示 section id（`hero`）與本尊不符，一律改掉。
- **Preview 列的鉛筆開後台編輯頁而非 modal**：本尊是整個產品表單以 modal 疊在編輯器上（100 §2.1）；modal 內嵌整份
  表單超出本包射程，先連到編輯頁，登記差異（下方「未做」）。
- **右鍵 Paste 恆灰**：本尊 Paste 只在複製過之後可用；Copy 在右欄「…」（E4），本包沒有剪貼簿來源 ⇒ 灰化。
- **鍵盤選中與點選同一實心底**：本尊以 Shift+↓ 選到的列是藍框、點選是實心（100 §2.2）；本包先同一形態，E7 RWD／視覺
  細修時補。
- **type icon 以關鍵字對映**：本尊 icon 由 schema 決定的規則未取得（100 §V）；我方以型別／名稱關鍵字對映到 Lucide。
- **不做**（留 E4／E5／E6）：右欄「…」（Copy／Duplicate／Rename／Hide／Edit code／Remove）、兩欄 picker（預覽欄、
  分類收合區、Generate、Apps 分頁）、預覽「+」插入點與 hover 工具列對接、Preview 列的 "+ Create product"。

## 測試
- 前端 `app/frontend/admin/pages/ThemeEditorPage.test.tsx`：既有 ED1／ED2／ED8／ED10–ED13／ED18–ED21／ED25–ED27／
  ED30／ED33／ED33b／ED34 隨樹改（顯示名、預設收合、帶小標、Add block 列）；新增 ED35（巢狀 block＋`block=p1__l1`＋
  容器內新增進 payload）、ED36（右鍵選單全項＋Rename 寫 `name`＋Add section after 插位）、ED37（Shift+↑↓ 跳過收合子層、
  Shift+Enter 聚焦、Ctrl+Shift+O／P）、ED38（群組 picker 依 `enabled_on.groups` 過濾、`limit` 灰化 "(1/1)"、footer 帶
  Add section 在列之上、Template 帶只列模板可用者）、ED39（Preview 列選產品 ⇒ `previewPath`＋編輯連結）、ED40
  （URL 還原展開祖先＋隱藏 block 灰列與眼睛常駐）、ED41（static block 列在樹上：鎖 icon、不可拖、無垃圾桶、Shift+⌫
  不刪、可隱藏、save 保留且不進 `block_order`）。
  跑法：`pnpm -s vitest run app/frontend/admin/pages/ThemeEditorPage.test.tsx`。
- 後端 `spec/requests/theme_editor_bootstrap_spec.rb`：E11（群組 label／type／position）、E12（`enabled_on`／`limit`）、
  E13（theme block 可接受子型別）。跑法：`bundle exec rspec spec/requests/theme_editor_bootstrap_spec.rb`。
- 突變輪（生產碼各改一處 → 對應測試轉紅 → 還原）：見 worklog 表。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）
- 模板 JSON：`name` 欄開始被寫入（Rename）；Liquid 引擎照舊忽略它（Ella fixture 本來就帶）。`static: true` 的 block
  由樹顯示但不動它的順序與存在（引擎以 `content_for 'block'` 固定位置渲染）。
- URL 契約：`block=` 由單一 id 變成 `__` 串接的路徑；E6 預覽橋的 `cl:select {id, blockId}` 仍只帶葉 id，頁面以
  `findBlockPath` 反查（葉 id 在 section 內重複時取第一個命中——登記為已知限制）。
- E4 右欄：標題已用顯示名；「…」選單的 Rename 應呼叫同一個 `startRename`。E5 picker：候選過濾與 `(n/limit)` 灰化邏輯
  在頁面 `pickerEntries`，E5 只換呈現層。E6：`cl:op` 的 remove／duplicate 已映射到 `removeNode`／`duplicateSection`。
- i18n：新增 `editor.addBlock`／`rename`／`paste`／`addSectionBefore`／`addSectionAfter`／`expand`／`collapse`／
  `previewLabel`／`searchResources`／`editResource`／`renamePrompt`／`shortcuts.show|hide|expandAll|collapseAll|selectPrev|
  selectNext|openSelected`；移除無消費者舊鍵（`editor.selectHint`／`saveComing`／`headerBand`／`footerBand`／`blockUp`／
  `blockDown`／`moveUp`／`moveDown`／`sectionType`／`mobilePreview`）。
- CSS：`.cl-tree__*` 一族（列高 `--editor-row-h`、縮排 `--editor-indent`、hover／active／hidden 態、右鍵選單、Preview 列），
  全部取 `app/assets/tokens.css` tokens。
