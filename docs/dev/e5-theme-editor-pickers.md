# 主題編輯器區段／區塊 picker（D79 E5）

## 概述
admin 主題編輯器的「Add section」／「Add block」改成本尊形態（`docs/research/100-theme-editor-live-teardown.md` §4＋§8.1
1:1 量測）：popover 貼左欄右緣、與該列同高；左欄＝搜尋框（"Search sections"／"Search blocks"）→ "Sections｜Apps"
（"Blocks｜Apps"）分段 → 首列 "Generate"（登記形，不可用）→ 該群組／模板可用的扁平清單（達 `limit`／`max_blocks` 灰化並標
"(n/limit)"）→ 依 preset／block schema `category` 的分類收合區；右欄＝預覽（目前一律 "No preview available"）；Apps 分頁＝
空態句。目標位置在左樹以插入線（藍 2px＋⊕）標示。後端 catalog 改列**每個 preset**（本尊清單以 preset 為單位：Ella `section`
一支 16 個 preset＝Custom section／FAQ／Video…），preset 的 blocks 兩形（array 含巢狀／hash map＋`block_order`）在前端實例化。

## 規格出處
- `docs/DECISIONS.md` D79；`docs/research/100` §4（兩者同一元件、錨點、頂部搜尋、分段、Generate、扁平可用清單→分類收合、
  "(1/1)" 灰化、右欄預覽、Apps 空態、區塊 picker 分類）、§8.1（清單≈250＋灰預覽欄≈390、搜尋 focus 藍框、分段白底選中、
  插入線藍 2px＋⊕）、§V（分類未捲完、預覽多為 "No preview available"）。
- `docs/research/24` §2.4（presets：name／category／settings／blocks）、`docs/research/25` §5（block id 形
  `{type 底線化}_{6 碼 base62}`、picker 規則：section 有 presets 才可加、category 分組）、§6（block 白名單 ∪ `@theme`）。
- Ella fixture 事實（2026-09-03 runner 統計）：多 preset 的 section 6 支（section 16／footer 10／header 10／
  featured-collection 4／featured-collection-list 4／media-banner 2）；preset 鍵＝name 80／settings 44／category 45／blocks 66／
  block_order 45；preset blocks 形＝hash 64／array 2／nil 14；block schema 亦帶 `category`（product 45／layout 15／basic 15…）。

## 架構與資料流
- `app/frontend/admin/editor/SectionPicker.tsx`：`SectionPicker({kind, items, anchorRef, open, onPick, onClose, renderPreview})`
  ——搜尋（本地）、分段（main／apps）、Generate（`aria-disabled`）、扁平清單（無 category）＋分類收合區（有 category，
  預設展開、可收合）、hover 項目 ⇒ 右欄預覽（無 `renderPreview` ⇒ "No preview available"）。`PickerItem {key,name,category,
  disabled,suffix,icon}`。
- `app/frontend/admin/components/Popover.tsx`：新 prop `placement: "right-start"`（貼錨點右側 +8、頂對齊；超出視窗底整體上移）。
- `app/frontend/admin/editor/SectionsTree.tsx`：`onAddSection(band, atIndex, anchor)`（Add section 列／右鍵 before-after 帶錨點）、
  `onOpenBlockPicker(band, sectionId, parentPath, anchor)`（取代 E3 的 inline add list）、`insertAt` ⇒ 目標列 `data-insert`
  （before＝該列上緣、after＝最後一列下緣）。
- `app/frontend/admin/pages/ThemeEditorPage.tsx`：`pickerFor {band, atIndex, anchor}`／`blockPicker {band, sectionId, parentPath,
  anchor}`；`pickerItems`（key＝`type#presetIndex`；(n/limit) 灰化；category）；`blockPickerItems`（`addBlockOptions`；category＝
  本地 def 的 category ?? 同型 theme block 的 category）；`addSection` 以 `instantiatePresetBlocks` 實例化 preset blocks
  （array：逐項生 id `{type}_{6 base62}`、巢狀遞迴、`static` 者不進 `block_order`；hash：原鍵為 id、無 `block_order` 依鍵序
  排除 static）。
- 後端 `app/graphql/types/theme_type.rb`：`section_catalog` 每 preset 一項 `{type, presetIndex, name（preset name 翻譯，退回 schema
  name）, category（翻譯）, preset{settings, blocks, block_order}}`；`block_defs_for`／`theme_block_defs` 加 `category`（翻譯）。

## API
- `themeEditorBootstrap` 的 `sectionCatalog` 形擴充（`presetIndex`／`category`／`preset.block_order`）；`sectionSchemas[].blocks[]`
  與 `themeBlocks[]` 加 `category`。無新 mutation。

## 資料表
無 schema 變更。

## 關鍵取捨
- **清單以 preset 為單位**：本尊 picker 的 "Header - Classic (1/1)"／"Product list: Carousel" 都是 preset 名（100 §4 實測＋fixture）。
- **(n/limit) 仍在頁面算**（E3 既有 `pickerEntries`），picker 只吃 items——避免兩份過濾邏輯。
- **預覽一律 "No preview available"**：本尊多數項目也是此形（100 §4）；以 `draft_section` 渲染縮圖需 CSS 語境，另包評估。
- **Generate 登記形**：本尊 AI 入口（100 §V V13），我方顯示但 `aria-disabled`。**E11（2026-09-04）：只在 section picker**——
  真店兩層 block picker 皆無此列（external-facts §G16）；section 級是否仍有待驗（91 §3.78）。
- **block id 形**：25 §5 觀察形 `{type}_{6 碼 base62}`；本尊逐字未取得；前導底線保留（Ella 私有 block `_parent`）。
- **不做**：Apps 分頁內容（無 app 層）、"Recommended apps"、分類排序照本尊（未取得 ⇒ 字母序、無分類殿後）。

## 測試
- `app/frontend/admin/pages/ThemeEditorPage.test.tsx`：ED7／ED12／ED23／ED35 隨 picker 形態改；新增 ED52（兩欄形態、分段、
  Generate、扁平＋分類收合、Apps 空態、同型多 preset）、ED53（第二個 preset 的 settings；array 實例化：id 形、巢狀、static；
  hash 照 block_order）、ED54（block picker 分類＋搜尋 focus、選取進容器、右鍵 after 的插入線、Escape 關閉）。
- 後端 `spec/requests/theme_editor_bootstrap_spec.rb` E18（每 preset 一項、category 翻譯、blocks 原樣）。
- 突變 M36–M44（worklog 表）。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）
- URL 契約不變；模板 JSON 新增 section 時 block id 形改為 `{type}_{6 base62}`（E3 前為 `{type}`／`{type}-n`）。
- E6 預覽「+」插入點要開同一 `SectionPicker`（`placement` 換成插入線正下方）；E4b 資源 picker 可沿用兩欄形。
- i18n：`editor.searchSections`／`searchBlocks`／`pickerSections`／`pickerBlocks`／`pickerApps`／`generate`／`noPreview`／
  `noAppBlocks`／`noAppSections`／`uncategorized`。
- CSS：`.cl-picker__*`（tokens）、`.cl-tree__item[data-insert]` 插入線。
