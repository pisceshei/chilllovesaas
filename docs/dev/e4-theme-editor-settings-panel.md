# 主題編輯器右欄設定面板（D79 E4）

## 概述
admin 主題編輯器右欄的設定面板依本尊 2026 編輯器逐控件實測（`docs/research/100-theme-editor-live-teardown.md` §3／§3.1）
重做：標題列（type icon＋顯示名＋「…」＋「×」）、「…」選單（Copy／Duplicate／Rename／Hide-Show／Edit code／Remove）、
就地改名、兩欄列（標籤／控件／說明，`header`／`paragraph` 分段）、`visible_if` 條件顯示、逐型別控件（range／select／radio／
checkbox／color／color_scheme／color_scheme_group 縮圖／font_picker／image_picker／link_list／url／text／textarea／number／
html／liquid／richtext／inline_richtext／video_url／text_alignment）、section 尾部「佈景主題設定」收合區（該 section 引用到
的全域設定）與「自訂 CSS」收合區（展開寫 URL `customCss=true`）、紅色 Remove；佈景設定手風琴共用同一控件庫；
font_picker 整面選字型；image_picker 檔案庫 modal。給商家在後台客製主題用；對應 Shopify「Customize」右欄。

## 規格出處
- `docs/DECISIONS.md` D79；`docs/research/100` §3（右欄結構逐字＋15 型形態）、§3.1（fixture 素材）、§8（面板列距 48）、§V
- Shopify input settings 官方頁（<https://shopify.dev/docs/storefronts/themes/architecture/settings/input-settings>，取證
  2026-09-03；逐字全文 `docs/dev/external-facts.md` §F7）：checkbox "If `default` is unspecified, then the value is `false`
  by default."；radio／select "If `default` is unspecified, then the first option is selected by default."；range "The
  `default` attribute is required. The `min`, `max`, `step`, and `default` attributes can't be string values."；
  text_alignment "If you don't specify the default attribute, then the `left` option is selected by default."；font_picker
  "The `default` attribute is required."；video_url `accept` 必填（youtube／vimeo）；richtext＝Bold/Italic/Underline/Link/
  Paragraph/Unordered list；inline_richtext "doesn't support line breaks (`<br />`) or underline in editor."；liquid
  "Content entered in these settings can't exceed 50kb."；link_list default 只收 `main-menu`／`footer`。
- `visible_if` 官方（settings 頁，取證 2026-09-03）：語法 `"visible_if": "{{ block.settings.layout_style == 'flex' }}"`；
  "Conditional settings cannot access runtime context or resolved data source values."；運算子清單與隱藏值行為＝未取得
  ⇒ 值域取 Ella fixture 實測（`docs/research/66` §A.4：`== != > < and or`，引用 block／section／settings）。
- Liquid operators 官方（<https://shopify.dev/docs/api/liquid/basics/operators>，取證 2026-09-03）："When using more than
  one operator in a tag, the operators are evaluated from right to left, and you can't change this order."；"Parentheses
  `()` aren't valid characters within Liquid tags."；只有 `false` 與 `nil` 為假，"empty strings are truthy"。
- `docs/research/66` §A.3.1（Ella 各型用量）、§A.3.2（欄位分佈：`alpha` 543、`visible_if` 2,999）。

## 架構與資料流
- `app/frontend/admin/editor/visibleIf.ts`：`evaluateVisibleIf(expr, {block, section, settings})`——tokenizer＋
  `clause (and|or clause)*`，比較 `== != > < >= <= contains`，字面量 `'x'`／數字／`true`／`false`／`nil`／`blank`／`empty`；
  邏輯由右往左結合（官方）；真假值只有 false／nil 為假；無表達式／解析失敗 ⇒ 顯示（fail-open）；隱藏欄位值不清。
- `app/frontend/admin/editor/SettingControls.tsx`：`SettingRow`（兩欄列；`header`／`paragraph`）＋逐型別控件；
  `effectiveValue(def, value)` 照官方 default 規則；`parseColor`／`formatColor`（alpha<1 ⇒ `rgba()`）；`CodeControl`
  （行號＋等寬）；`RichTextControl`（contentEditable＋工具列；inline 不允許 Enter）；`ControlContext`＝schemes／fonts／
  menus／onEditScheme／onOpenFontPicker／onOpenImagePicker。
- `app/frontend/admin/editor/SettingsPanel.tsx`：面板殼（標題列＋「…」Popover＋就地改名＋本體捲動）；`visible_if` 過濾；
  section 專屬 `themeSettings`（引用到的全域設定）與 `customCss`；static block 不出 Duplicate／Remove（官方 F4）；
  `FontPickerPanel`（SYSTEM FONTS／OTHER FONTS＋字重＋Done）。
- `app/frontend/admin/editor/ImagePickerModal.tsx`：既有 `files` connection（搜尋＋格狀＋Done）⇒ 值 `shopify://shopify/files/{filename}`。
- 頁面 `app/frontend/admin/pages/ThemeEditorPage.tsx`：`controlCtx`（schemes＝`color_scheme_group` 值 × `role` 對映；
  fonts＝`fontLibrary`；menus＝`menus` root query）；ops `duplicateNode`／`copyNode`／`pasteNode`（剪貼簿 ⇒ 左樹右鍵
  Paste 解灰）；佈景設定手風琴走 `SettingRow`＋`visible_if`（scope 只有 settings）；佈景設定面板點 font_picker ⇒ 頁面在
  右欄承接整面選字型；Editing Scheme 入口寫 URL `category`＋`colorScheme`（子面板本體＝E4b）。
- 後端 `app/graphql/types/theme_type.rb`：`translate_defs` 保留 `visible_if`／`alpha`／`accept`／`definition`／`role`／
  `metaobject_type`（options 的 `group` 隨 options 原樣）；`section_schemas[type].theme_settings`＝section liquid 內
  `settings.<id>` 引用（排除 `section.settings.`／`block.settings.`；本尊判定法未取得 ⇒ ours）；`font_library`＝
  `config/storefront_fonts.yml` 三段扁平化。

## API
- `themeEditorBootstrap` 加 `fontLibrary`；同文件加 root `menus { handle title }`；`sectionSchemas` 的 def 多帶上述鍵、
  section 多帶 `theme_settings`。`editorImagePicker`＝既有 `files(first, query)`。無新 mutation。

## 資料表
無 schema 變更。

## 關鍵取捨
- **`visible_if` 在前端求值**：設定一改就要重算可見性（66 §A.4 要點①）；作用域必含全域 settings（要點②）。
- **隱藏欄位不清值**：官方未說明；清值會讓切回時遺失使用者輸入，保守保留（ED43 鎖定）。
- **color 值形**：alpha=1 ⇒ `#rrggbb`、alpha<1 ⇒ `rgba(r, g, b, a)`；Ella 543 個 `alpha: true`（66 §A.3.2）。
- **font_picker 由 panel／頁面承接整面**：本尊右欄整面切換（100 §3.8），非 popover。
- **theme_settings 引用判定＝ours**：本尊「Theme Settings」收合區列哪些設定的規則未取得。
- **不做（E4b／E5）**：product／collection／page／blog／article（含 *_list）、video、metaobject* 的 picker（唯讀顯示現值）；
  color_scheme_group 的 Editing Scheme 子面板（縮圖格已出、點擊寫 URL）；image_picker 的篩選 chip／Sort／上傳／
  Generate／焦點；url 的資源 picker；Explore free images。

## 測試
- `app/frontend/admin/editor/visibleIf.test.ts` V1–V6；`SettingControls.test.ts` S1–S3；
  `app/frontend/admin/pages/ThemeEditorPage.test.tsx` ED8／ED9／ED12／ED14／ED21 隨控件形態改；新增 ED43（visible_if）、
  ED44（基本控件）、ED45（color alpha）、ED46（color_scheme＋Edit）、ED47（font_picker）、ED48（link_list）、ED49（「…」：
  副本／複製貼上／隱藏／static）、ED50（佈景設定收合區＋customCss URL）、ED51（image_picker）。
- 後端 `spec/requests/theme_editor_bootstrap_spec.rb` E15（visible_if／alpha／group）、E16（theme_settings）、E17（fontLibrary）。
- 突變 M24–M35（worklog 表）。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）
- URL 契約新增 `customCss=true`（100 §3.13）與 `colorScheme=<id>`（100 §3.7）。
- 模板 JSON：color 值可為 `rgba()` 字串（引擎 `ColorDrop` 已收 `#` 開頭；`rgba` 走原值——引擎側 `color` 型 coerce 只在
  `#` 開頭包 ColorDrop，`rgba(` 字串進主題 Liquid 的 `| color_*` filter 行為＝E4b 驗）。
- i18n：`editor.*` 新鍵（change／select／exploreFreeImages／urlPlaceholder／videoUrlInvalid／none／transparent／hex／hue／alpha／
  replace／removeMenu／createMenu／bold／italic／underline／link／linkUrl／paragraph／bulletList／richtext／duplicate／selectFont／
  customCssHelp／systemFonts／systemFontsNote／otherFonts／otherFontsNote／fontWeight／searchFiles／noResults／noResultsHint／
  files／schemeLabel）與 `common.edit`／`common.copy`／`common.back`。
- CSS：`.cl-panel__*`／`.cl-ctl-*`／`.cl-colorpicker__*`／`.cl-fontpicker__*`／`.cl-imagepicker__*`（tokens）。
