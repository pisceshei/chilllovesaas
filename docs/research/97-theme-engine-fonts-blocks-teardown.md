# 97 — 主題引擎補完面 teardown（字型管線·2026 blocks·色階群組）

> 步 13 的三源取證檔（2026-09-01）：①官方文檔深潛（shopify.dev，agent 逐字報告）
> ②真店親點（chill.deals 已發布 Ella 7.2.0 的實際 CSS 輸出，DOM 抓取）③本地
> 復現（Ella fixture 逐檔＋我方引擎 parse 實測）。實作對照＝`docs/dev/` 步 13 篇。

## §1 字型管線

### 1.1 官方契約（shopify.dev，取證 2026-09-01）

- `font_face`（…/filters/font_face）："Generates a CSS `@font_face` declaration to
  load the provided font."；可選 `font_display` 參數（傳了才輸出該行；未傳時的
  預設行為官方未記載——未取得）。
- `font_url`（…/filters/font_url）："Returns the CDN URL for the provided font in
  `woff2` format."；可傳 `'woff'`——文檔僅示範 woff2/woff 兩值。
- `font_modify`（…/filters/font_modify）：兩參數（屬性、新值）；
  style 值域＝normal/italic/oblique；weight 值域＝100–900/normal(=400)/bold(=700)/
  +100–+900/-100–-900/lighter/bolder（"applying the rules used by the CSS
  `font-weight` property"）。🔴 "If the `font_modify` filter tries to create a font
  variant that doesn't exist, then it returns `nil`."（回 nil 不是原 font、不是 error）。
- `font` object（…/objects/font）七屬性：`baseline_ratio`（number）／
  `fallback_families`（string）／`family`／`style`／`system?`（boolean）／
  `variants`（array of font）／`weight`（number）。
- `font_picker` setting：儲存值＝font handle（官方範例 `"default": "helvetica_n4"`；
  default 必填）；讀值＝"data is returned as a `font` object."
  🔴 handle 後綴規則（n4=normal 400 之類）官方**無專節定義**——僅實例可觀察
  （helvetica_n4／playfair_i7），本檔按觀察形實作並標 V。
- 字型庫："includes system fonts and a selection of Google fonts. These fonts are
  free to use on all Shopify online stores, and are provided in both WOFF and
  WOFF2 formats."；system fonts＝已裝在使用者機器、不需下載。

### 1.2 真店實測（chill.deals，DOM 抓取 2026-09-01）

- 實際 @font-face 輸出（逐字，hash 截短）：
  `@font-face { font-family: Jost; font-weight: 400; font-style: normal;
  font-display: swap; src: url("//chill.deals/cdn/fonts/jost/jost_n4.<40hex>.woff2")
  format("woff2"), url("…jost_n4.<40hex>.woff") format("woff"); }`
  ——family 無引號、URL protocol-relative、woff2 前 woff 後雙 src、
  `/cdn/fonts/{family}/{handle}.{hash}.{ext}` 路徑形。
- 全頁 15 個 @font-face、家族恰 jost＋poppins；`body` computed font＝
  "Jost, sans-serif"（fallback_families 生效形）。
- Ella 消費鏈（fixture `snippets/global-style.liquid:3-27`）：
  `settings.type_body_font | font_modify: 'weight','bold'`／`'600'`／
  `'style','italic'`，逐一 `| font_face: font_display: 'swap'`——italic 變體
  不存在 ⇒ font_modify 回 nil ⇒ font_face(nil) 輸出空（live 無 italic face 即此形）。
- 現行主題 current preset 字型（fixture settings_data）：type_body_font=jost_n4／
  type_header_font=jost_n7／type_subheading_font=poppins_n5。

### 1.3 我方落點（ours）

- 自 host woff2 最小集＝Jost n4/n5/n6/n7＋Poppins n4/n5/n6/n7（Google Fonts，
  **OFL 授權**，latin subset）→ `public/fonts/{family}/{handle}.woff2` 靜態服務。
- 只 host woff2：font_url 的 'woff' 請求回 woff2 URL（Ella 只用預設；⚪ 登記）；
  @font-face 單 src（live 是雙 src——woff 退路對 2026 瀏覽器面可忽略，⚪）。
- 未知 handle ⇒ system 形 fallback drop（family 由 handle 前段推、system?=true、
  無檔 ⇒ font_face 空輸出）＋miss 遙測。

## §2 2026 theme blocks（`{% render block %}` 與巢狀）

- 官方（agent 報告 §3）：theme blocks 巢狀 ≤8 層；子層渲染官方正典＝
  `{% content_for 'blocks' %}`；`{% render block %}` 官方記載於 app blocks 情境
  （`{% for block in section.blocks %}{% render block %}`）。
- 🔴 本地實測（2026-09-01）：Ella `blocks/_editorial_list.liquid:22-26`
  `{% for child_block in block.blocks %}…{% render child_block %}`——我方引擎
  **parse fatal**：`Syntax error in tag 'render' - Template name must be a quoted
  string`（Liquid 5.13 原生 render 只收字串字面量）⇒ 整檔編譯失敗、該 block
  渲染缺席。live 同段落正常渲染 ⇒ 真引擎接受變數形 render 且值可為 block。
- 我方缺口二：`block.blocks`（子 block drop 陣列）BlockDrop 未暴露——
  迴圈靜默空轉。

## §3 色階群組（color_scheme / color_scheme_group）

- 官方：`color_scheme` setting 讀值＝"the selected `color_scheme` object from
  `color_scheme_group`"（無效值回 default）；`color_scheme` object＝`id`＋
  `settings`；`color_scheme_group` 迭代範例（objects/color_scheme_group 頁逐字）：
  `{% for scheme in settings.color_schemes %} .color-{{ scheme.id }} {
  --color-background: {{ scheme.settings.background }}; … {% endfor %}`；
  "Color schemes can be added only in `settings_schema.json`."
- 真店實測：`.color-scheme-1 { --color-background: rgb(255 255 255 / 1.0);
  --color-background-rgb: 255 255 255; --color-foreground: …}`（八 scheme 逐一
  emit CSS 變數；元素掛 `color-scheme-7` 類）。
- 我方現狀：SettingsDrop 對 color_scheme／color_scheme_group 無 coerce 分支——
  settings_data 的 `color_schemes` hash 裸傳 Liquid（scheme.id／scheme.settings.*
  全 nil）。fixture current 有 scheme-1…scheme-8，每個 settings 含 background／
  foreground／primary／…等鍵。

## §4 未取得清單（19.3）

1. font_face 未傳 font_display 的預設行為（官方沉默；我方＝不輸出該行，同官方示範差集）。
2. font handle 後綴命名正式規則（觀察形 `{family}_{n|i}{weight/100}`——標 V）。
3. font_url 對 woff2/woff 以外值的行為（官方未列；我方 whitelist 外回 woff2）。
4. `{% render block %}`（theme block 變數形）的官方文檔記載——app blocks 頁有
   `{% render block %}`；theme block 情境無專文，但 live Ella 實渲染成立（§2 實測）。
5. system font 的 font_face 輸出（官方未示範；我方＝空輸出——系統字型無需下載）。
