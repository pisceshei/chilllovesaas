# 100 — 本尊主題編輯器逐面板實測 teardown（2026-09，D79 的 E1）

> 對標＝admin.shopify.com 主題編輯器（2026 春季版）。實測店＝pnrjnw-sy（使用者全權授權，操作一律在
> 現行主題的 Duplicate 副本上）；補走 `docs/research/24` §1（2026-08 Horizon 局部實測）未覆蓋的層。
> 六層：⓪載入紀律 ①按鈕級功能與交互 ②值域窮舉 ③架構深度 ④CSS 量測三段式 ⑤help 雙源 ⑥條件控件三源。
> 🔴 編輯器本體在跨域 iframe（online-store-web.shopifyapps.com）：DOM 不可讀，量測走「截圖＋zoom」；
> 編輯器 CSS bundle 這一路本輪未取得（見 §V）。每項標明來源與取證日期。
>
> 取證方式（全篇同）：claude-in-chrome 擴充功能在使用者本機 Chrome 前景分頁操作，逐控件點擊／hover／
> 右鍵／快捷鍵，截圖框 1568×750（CSS 視口 2048×978、DPR 1.875，換算係數 ≈1.306）；
> 文中引號內為本尊 UI 逐字（英文介面）。取證日期 2026-09-03（HKT 晚間）。
> 截圖本身不落倉（工具只回傳影像給操作端，無檔案輸出）——這是工具限制，登記 §V。

## 0. 操作紀錄（時間序，含 URL 去 token）

| # | 動作 | 觀察 |
|---|---|---|
| 1 | 開 `https://admin.shopify.com/store/pnrjnw-sy/themes`，等待載入 | 主題頁在 iframe `https://online-store-web.shopifyapps.com/themes`（query 帶 hmac／host／id_token／locale／session／shop／timestamp／_signed_params，簽名短期票證，不可獨立開啟） |
| 2 | 現行主題卡「…」→ `Duplicate` | 選單項：View／Rename／Duplicate／Edit code／Edit default theme content／Download theme file／Version 7.2.0；toast「Theme duplicated」；草稿列出現「Copy of ella-7-2-0-theme-source · Copying your theme」，複製約四分鐘後才可 Edit theme |
| 3 | 副本列「Edit theme」 | 進 `https://admin.shopify.com/store/pnrjnw-sy/themes/143506604135/editor`（副本 theme id 143506604135）；分頁標題「我的商店 3 · Edit Copy of ella-7-2-0-theme-source · Shopify」 |
| 4 | 頂欄每個控件 hover／點擊、四個下拉展開、快捷鍵表 | §1／§6 |
| 5 | 左樹逐列 hover／點擊／右鍵、Add block／Add section、鍵盤 | §2／§4 |
| 6 | 右欄逐控件展開（select／link_list／color／color_scheme／font_picker／image_picker／url／code） | §3／§7 |
| 7 | 主題設定分類逐一展開；App embeds 面板 | §7 |
| 8 | 預覽：hover／點選／右鍵／「+」插入點／inspector 關閉／手機檢視／全寬預覽 | §5 |
| 9 | 隱藏 Announcement bar → Ctrl+S（副本被存成隱藏）→ 再點眼睛還原 → Ctrl+S | §6；副本終態＝與原主題相同（Announcement bar 可見），Save 鈕灰 |
| 10 | 模板選擇器切到 Products › Default product，再切回 Home page | URL 加 `previewPath=%2Fproducts%2Facme-tee`；分頁標題變「我的商店 3 · Products · Acme Tee · Shopify」 |
| 11 | Publish 鈕（只看確認框，按 Escape 取消）；Exit（只看離開確認框，按 Stay） | §6；**未發布副本**，hoko.vip 現行主題不動 |

副本 `Copy of ella-7-2-0-theme-source` 保留在草稿列供 E2–E7 續用（未刪）。

## 1. Shell／頂欄

版面＝全高三欄：頂欄（全寬）＋左欄（面板切換器 + 當前面板）＋預覽（中）＋右欄（僅在選中 section／block、
或開啟 scheme／font 等次面板時出現）。預覽區與左右欄之間各有一條細分隔線；預覽本體有自己的捲軸。

頂欄由左至右（tooltip 逐字；快捷鍵以 tooltip 內的鍵帽呈現，`⊞` 為平台修飾鍵圖示，見 §6 註）：

| 位置 | 控件 | tooltip／形態 | 行為 |
|---|---|---|---|
| 左 1 | Exit（門＋箭頭 icon） | "Exit" | 有未存變更 ⇒ 開 "Leave page with unsaved changes?" 對話框（§6）；否則回主題頁 |
| 左 2–4 | 面板切換器三顆 icon 鈕（分隔線右側） | "Sections ⊞ CTRL 1"／"Theme settings ⊞ CTRL 2"／"App embeds ⊞ CTRL 3" | 切換左欄面板；**再點已啟用的那顆 ⇒ 收合左右欄成全寬預覽**（URL `previewMode=fullscreen`），再點一次還原 |
| 中 1 | 主題 chip：主題 icon + 名稱（過長截斷「Copy of ella-7-2-0-theme-so…」）+ 徽章 "Draft" | hover 顯示完整名稱 tooltip；點擊無選單 | 純顯示 |
| 中 2 | 市場選擇器：店 icon + "Store default" + ⌄ | 展開 popover：搜尋框 "Search markets"；"Store default ✓"；小標 "Customizable market"；市場列（本店＝"台灣"，地球 icon） | 切換預覽／客製的市場語境（§9.4） |
| 中 3 | 模板選擇器：模板 icon + "Home page" + ⌄ | 展開 popover（§1.1） | 切換模板；URL 加 `previewPath=` |
| 右 1 | Sidekick（面具 icon） | "Open Sidekick ⊞ ." | AI 助理，**不在我方射程**（§V） |
| 右 2 | Inspector 切換（虛線框＋游標 icon，預設**已啟用**呈按下態） | "Deactivate inspector ⊞ SHIFT I" | 關閉後預覽無 hover／選取覆疊（§5） |
| 右 3 | 手機檢視（手機 icon） | "Show mobile view ⊞ CTRL I" | 預覽縮成手機寬置中（§5）；再點回桌機 |
| 右 4–5 | Undo／Redo | "Undo ⊞ Z"／"Redo ⊞ Y"；無可撤銷時灰 | 只作用於未儲存變更（§9.4） |
| 右 6 | "…" 選單 | 項目：Edit code／Edit default theme content／Preview／View documentation／Keyboard shortcuts／Get support；底部灰字「Ella 7.2.0」＋「Developed by Halothemes」 | Keyboard shortcuts ⇒ §6 對話框 |
| 右 7 | "Publish"（次要鈕） | 開 "Save and publish …?" 對話框（§6） | 草稿主題才有此鈕（現行主題在主題頁另有 Publish） |
| 右 8 | "Save"（主要鈕；無變更時灰） | "Save ⊞ S" | 儲存；儲存中頂欄下方出現藍色進度條，完成 toast "Changes saved." |

### 1.1 模板選擇器（值域窮舉）

popover 頂部搜尋框 "Search online store"；第一層清單（含 icon）：

- Home page
- Products ›
- Collections ›
- Collections list
- Gift card
- （分隔線）
- Cart
- Checkout and customer accounts（點擊離開主題編輯器，本輪未點；§V）
- （分隔線）
- Pages ›
- Blogs ›
- Blog posts ›
- （分隔線）
- Search
- Password
- 404 page
- （分隔線）
- "+ Create metaobject template"（藍字）⇒ 對話框 "Create metaobject template"：插圖＋"Build pages with metaobjects"＋
  "Easily create groups of pages such as store locations or brands. Learn more"＋鈕 "+ Add definition"

子清單（點 › 進入；頂部 "‹ Products" 可返回；**再次打開 popover 會停在上次的子清單**）：

- Products：星形 icon 的 "Default product — Assigned to 3 products"；模板 icon 的替代模板每列兩行
  「名稱／Assigned to N products」：block_wishlist_card、product-full-width-2、product-full-width、product-grid、
  product-image-gallery、product-left-thumbnails、product-right-thumbnails、product-slider、quick_add、
  template-step-by-step（本店皆 0）；底部 "+ Create template"。
- Collections："Default collection — Assigned to 1 collection"、collection-banner-adv、collection-full-width-2、
  collection-full-width、collection-right-sidebar、"+ Create template"。
- Pages："Default page — Assigned to 0 pages"、about-2、about、brands、contact（Assigned to 1 page）、faqs、get-json、
  ⋯（清單較長，未捲到底；§V）。
- Blogs："Default blog — Assigned to 1 blog"、blog-balance、blog-simple、"+ Create template"。
- Blog posts：整個子清單**灰化不可點**（"Default blog post — Assigned to 0 blog posts"、article_with_product、
  "Create template"）——本店沒有文章可預覽（條件控件三源：實測灰化＋店狀態無文章；help 未查此條，§V）。

"Create template" 對話框："Create a template"；說明 "Create a template to customize how your content is displayed.
After it's published, assign it in the Shopify admin."；欄位 Name（右側計數 "0/25"）、Based on（select，預設
"Default product"）；鈕 Cancel／"Create template"（名稱空白時灰）。

切到資源模板後，左欄標題變成模板名（"Default product"），標題下多一列 **Preview 資源列**（§2.1）。

## 2. 左欄：面板切換器＋sections 樹

寬度≈300px（§8）。標題列＝當前模板名（"Home page"）。內容依 `layout/theme.liquid` 的 section group 與模板
JSON 分組，每組有灰色小標與末尾 "⊕ Add section"（藍字）：

- Header group：Announcement bar／Header - Default／Header mobile multi-tab／Add section
- Popup group：Multitasking bar／Cart drawer／Sticky toolbar mobile／Promotion popup／Before you leave／Add section
- General group：Color Swatches／Add section
- Template：Slideshow／Collection list／Custom section／Lookbook／Collection list／Testimonial／Custom section／
  Marquee／Media gallery／Marquee／Add section
- Footer group：**Add section 在最上面**、Footer - Home default、Footer bottom（灰字＋眼睛斜線＝已隱藏）

（產品模板的 Template 組：Product information／Quick order list（隱藏）／Product tabs／Recently viewed products／
Recommended products／Add section。）

### 2.1 資源模板的 Preview 列

"Preview"（小灰字）＋資源名 "Acme Tee"，右端鉛筆 icon；hover 時名稱右側出現 ⌃⌄。
- 點列本體 ⇒ popover：搜尋框 "Search"、資源清單（Acme Tee／Bolt Mug／Cosy Lamp，各帶產品 icon）、"+ Create product"。
- 點鉛筆 ⇒ **整個 admin 產品編輯表單以 modal 開在編輯器上**（標題 "Acme Tee · Active"，Title／Description 富文本／
  Media／Category／Price／Inventory…，右欄 Status／Publishing／Sales／Product organization／Theme template；右上 "Close"）。

### 2.2 列的解剖（section 列與 block 列同構）

`[chevron] [type icon] 名稱 ……… [hover 動作：drag handle 取代 type icon ｜ 垃圾桶 ｜ 眼睛]`

- chevron：有子項才顯示；展開後子項縮排一級，每級縮排≈16px（§8）。
- type icon：section＝「兩層框」icon；section group 內的 section 同；block 依型別：link icon（Mega menu / Menu item）、
  資料夾（Group）、虛線方框（靜態／theme block 容器：Announcement／Collection items／Details／Slide）、圖片 icon（Image）、
  T（Heading）、≡（Text／Announcement text）、油漆桶（Color Swatches section）。
- 名稱：block 列可帶摘要「名稱 – 摘要」（摘要斜體灰，如 "Announcement text – End …"、"Heading – Menu"、"Menu item – Home"）。
- hover：整列淺灰底；出現 drag handle（⋮⋮，取代 type icon）、垃圾桶（Remove）、眼睛（Hide／Show）。
- 選中：section 列＝藍底白字；用鍵盤 Shift+↓ 選到的列＝藍色外框（非實心）。
  🔴 **2026-09-03 更正（E3b，1:1 截圖）**：點選中的 section 列＝**淺灰底（#f1f1f1 級）、深色文字、圓角 8、列底 28**，**不是藍底白字**——原句是 E1 在 JPEG 截圖下的誤記（藍色只出現在預覽外框與 chip）。鍵盤選取的藍框形態本輪未複驗，維持原記錄。
- 隱藏：名稱灰化，眼睛斜線 icon **常駐**顯示（不需 hover）。
- 展開的 section／容器 block 第一個子列＝"⊕ Add block"（藍字）；巢狀最深實測到四層（section → Collection items →
  Group → Group: Basic）。
- 右鍵 section 列 ⇒ 選單：Paste（灰）／Rename／Hide（右側鍵帽 "CtrlShiftH"）／Add section before（灰）／
  Add section after（灰）／Edit code（灰化原因未驗證：該列在 section group 內；§V）。

### 2.3 鍵盤（左樹有焦點時，逐一實測）

- Shift+↓／Shift+↑：選下一個／上一個項目（會走進子 block，右欄同步）。
- Ctrl+Shift+O：全部展開；Ctrl+Shift+P：全部收合。
- Ctrl+Shift+H：隱藏／顯示選中項；Shift+⌫：移除；Shift+Enter：開啟選中元素（設定面板）。
- 拖曳重排：本尊支援（§9.1），自動化的 `left_click_drag` 只選到文字、未觸發重排——工具限制，§V。

### 2.4 跨模板的選取狀態

切換模板後右欄仍顯示上一個模板選中的 block（"Group"），URL 的 `section=`／`block=` 也保留；直到在新頁點選
才更新。⇒ 選取狀態掛在 URL，不隨模板切換清除。

## 3. 右欄：設定面板（逐控件型別）

寬度≈300px（§8）。結構：

- 標題列：type icon＋名稱＋"…"＋"×"。"…"（section）：Copy／Duplicate／Rename／Hide／Edit code／Remove（紅）；
  "…"（block）：Copy／Duplicate／Rename／Hide（已隱藏時 "Show"）／Edit code／Remove。"×"＝取消選取（Escape 同）。
- Rename ⇒ **就地改名**：標題文字變成已全選的文字輸入框，Enter 確定、Escape 取消（無 modal）。
- 內容：兩欄列（左標籤、右控件），`header` 型設定＝粗體小標分段，`paragraph`＝灰色說明文；資訊句如
  "Displays variants from parent product" 與連結句 "Edit variant styling in theme settings"（連到主題設定該分類）。
- 尾部（section）：可收合的 "Theme Settings"（列出該 section 引用到的全域設定，如 X / Twitter、Facebook…文字欄，
  可在此直接改）與 "Custom CSS"（見 3.13）；最後 "🗑 Remove section"（紅）。block 尾部＝"🗑 Remove block"。
- 面板本體可捲動，標題列固定。

逐型別（名稱＝Shopify 設定 `type`；形態＝本尊實際呈現；來源＝本輪實測的 section／block）：

1. **range**：滑桿（軌道有刻度點）＋右側數字輸入框＋單位後綴（px／day／s／%）。例：Header "Gap 12 px"、
   Promotion popup "Show again after 1 day"、"Delay time 10 s"、Image "Custom width 100 %"。
2. **select**：帶 ⌃⌄ 的下拉；展開為原生選單（Align items：Top／Center／Bottom）。例：Size "16px"、Text weight "Default"、
   Case "Uppercase"、Image ratio "Adapt to image"、Enable parallax scroll "None"。
3. **radio**（分段）：藥丸式分段控制，選中段白底。例：Position "Left｜Center｜Right"、Row "Top｜Bottom"、
   Width "Fit｜Fill｜Custom"、Unit "Pixel｜Percent"、Line height "Tight｜Normal｜Loose"、Case "Default｜Uppercase"。
4. **checkbox**：右對齊 toggle 開關（開＝黑底）。例："Reveal logo on sticky"、"Open link in new tab"、"Hide on mobile"、
   "Show currency codes"、"Enable right to left"（附長說明文）。
5. **color**：色票＋HEX 文字（"#D62828"）＋右側資料庫 icon；點開 popover：飽和度／明度方塊、HEX 輸入（前綴 "#"、
   右側滴管 icon）、色相滑桿、透明度滑桿。透明色顯示為棋盤格＋"Transparent"。**Escape 不關閉此 popover**（實測），
   點外部才關。
6. **color_scheme**：控件顯示「Aa」小預覽＋"Scheme 1"＋⌃⌄；popover 列出全部 scheme（縮圖＋"Scheme N"），
   選中者打勾並在下方多一行 "Edit" 連結。
7. **color_scheme_group**（只在主題設定 Colors）：小標 "Schemes"＋說明 "Color schemes can be applied to sections
   throughout your online store."＋三欄縮圖格（每格 "Aa" 與兩顆按鈕色丸；透明 scheme 為棋盤格）＋虛線 "+" 格與
   "Add Scheme" 連結。點某格 ⇒ 右欄開 "Editing Scheme 1"：頂部大縮圖、句子 "Editing this scheme's colors will affect
   all sections that use this scheme."、角色列（Background／Background gradient（select "No color cho…"＋說明
   "Background gradient replaces background where possible"）／Headings／Text／Links／Hover links／Borders／Shadow；
   小標 Primary button：Background／Background gradient／Text／Borders／Hover background／Hover background gradient／
   Hover text／Hover borders；Secondary button 同組；Inputs：Background／Text／Borders／Hover background；
   Carousel：Arrow color／Arrow background／Arrow border／Hover arrow color／Hover arrow background／Pagination color／
   Pagination active color）；尾部 "🗑 Remove color scheme"；"…" 只有 Remove。URL 加
   `category=gid://shopify/OnlineStoreThemeSettingsCategory/Colors?theme_id=…&first_setting_id=color_schemes&colorScheme=scheme-1`。
8. **font_picker**：控件「A」icon＋字型名（Jost／Poppins）＋⌃⌄；點開 ⇒ 右欄整面 "Select Body font"：搜尋框 "Search"；
   小標 "SYSTEM FONTS"＋"These fonts load faster and might appear differently on various devices."（SF Mono／
   Helvetica／New York／system_ui）；小標 "OTHER FONTS"＋"These fonts are downloaded onto a visitor's computer and
   might cause slower load times."（Abel／Abril Fatface／Acme／Alegreya／…，每列以該字型渲染）；底部固定區：選中字型名
   "Jost"＋字重 select "Regular"＋"Done" 鈕。Typography 分類頂部另有說明 "Selecting a different font can affect the
   speed of your store." 與連結 "Learn more about system fonts."。
9. **image_picker**：虛線框內 "Select" 鈕＋資料庫 icon，下一行 "Explore free images" 連結；框下灰字說明（如 "Images for
   desktop use are recommended to be 395 x 498px."、"Will be scaled down to 32 x 32px"）。"Select" ⇒ modal（標題＝設定
   標籤，如 "Default logo"）：搜尋 "Search files"、篩選 chip "File size ⌄／Used in ⌄／Product ⌄"、右上 "Sort"＋檢視切換；
   空態：放大鏡插圖＋"No results found"＋"Edit your search criteria, or upload a new image."＋鈕 "Upload image"（主要）
   與 "Generate image"（AI）；底部 Cancel／Done（灰）。
10. **link_list**：控件＝清單 icon＋選單名（主選單）＋⌃⌄；點開 ⇒ 小選單 Replace／Edit ↗（外開）／Remove menu（紅）；
    Replace ⇒ popover：搜尋 "Search"、選單清單（主選單 ✓／頁尾選單／顧客帳號主選單）、"+ Create menu"。
11. **url**：標籤右側資料庫 icon；輸入框 placeholder "Paste a link or search"。
12. **text**：單行輸入框（Social accounts 的 Facebook "https://facebook.com/shopify" 等；空值顯示灰 placeholder）。
    **textarea**：多行框（"SVG logo"、"SVG logo inverse"）。
13. **liquid／html／custom CSS 型**：帶行號的程式碼編輯器（等寬字，placeholder 灰碼 `h2 { font-size: 32px; }`）。
    section 級 "Custom CSS" 收合區說明 "Adds custom styles to this section only. To add custom styles to your entire
    online store, go to theme settings." 與連結 "Learn more about custom CSS"；展開狀態寫進 URL `customCss=true`。
14. **header**／**paragraph**：分段粗體小標／灰說明（Layout 分類 "Grid"＋"Affects areas with multiple columns or rows."）。
15. 條件顯示：Image block 的 "Custom width" 列只在 Desktop width＝Custom 時有意義（本輪未切換驗證是否隱藏；§V）。

本輪 Ella 面板**未出現**、留待 E4 補實測的型別：richtext、inline_richtext、number、video、video_url、product、
product_list、collection、collection_list、blog、article、page、text_alignment、metaobject、metaobject_list、
style.*（§V）。

### 3.1 實測到的 section／block 面板內容（供 E4 的 fixture）

- Header - Default：Layout（Gap range／Align items select）、Logo（Position／Row／Reveal logo on sticky）、Menu（Menu
  link_list／Position／Row／Icon None｜Caret／Gap）、Menu link level 1（Font Heading｜Body／Size／Text weight／Case）、
  Menu link level 2…。
- Announcement bar：Color scheme；Spacing（Spacing bottom）；Section padding（Top／Bottom）；Theme Settings；Custom CSS。
- Promotion popup：Show again after（day）／Delay time（s）；Appearance（Color scheme／Image + 說明）；Theme Settings；
  Custom CSS。
- Product information（產品主 section）：Layout（Width Page｜Full｜Custom／Page width 1170 px／Media position Left｜Right／
  Equal columns／Product details overlay on scroll (mobile)／Gap 60 px／Color scheme）；Padding Top／Bottom；子樹：
  Media、Details（靜態容器：Header ›、Price、Countdown、Variant picker、Product Hot Stock、Perks ›…）。
- Group（theme block）：Link／Open link in new tab／Hide on tablet／Hide on mobile；Layout（Direction／Mobile direction／
  Alignment／Position select／Mobile alignment／Mobile position select／Gap）；Size（Width／Tablet width／Mobile width 各
  Fit｜Fill｜Custom／Height select）；Appearance（Inherit color scheme／Background media None｜Image｜Video／Image／
  Image position Cover｜Fit／Content overlay／Match image height to overlay content／Image ratio／Borders None｜Solid／
  Background overlay）；Animation（Enable parallax scroll）；Shadow（Shadow color／Horizontal offset／Vertical offset／
  Blur／Spread）；Margin（Top／Top margin on mobile／Bottom／Bottom margin on mobile／Left／…／Right margin on mobile）；
  Padding（Top／Bottom／Left／Right）；Remove block。
- Image（block）：Image／Link／Hide on mobile；Size（Image ratio／Desktop width Fit｜Custom／Unit Pixel｜Percent／
  Custom width／Tablet width…／Mobile width…／Height Fit｜Auto｜Fill／Image position Cover｜Contain）；Border…。
- Variant picker（block）："Displays variants from parent product"／"Edit variant styling in theme settings"；Style
  Dropdowns｜Pills；Swatches toggle；Swatch size 34 px；Alignment；Padding 四向；Remove block。
- Price（block）："Displays price from parent product"／"Edit price formatting in theme settings"；Show sale price first／
  Installments／Tax information；Typography（Preset select "Custom"＋"Edit presets in theme settings"／Width Fit｜Fill／
  Alignment／Font select／Size／Weight／Line height／Letter spacing／Case／Color Text｜Heading｜Link）；Padding。

## 4. 區段 picker／區塊 picker

兩者同一元件（popover，左清單＋右預覽兩欄）：

- 錨點：左樹 "Add section"／"Add block" ⇒ popover 貼在左欄右緣、與該列同高；預覽內「+」插入點 ⇒ popover 貼在插入線
  正下方（§5）。
- 頂部：搜尋框（"Search sections"／"Search blocks"）；分頁 "Sections｜Apps"（"Blocks｜Apps"）。
- 首列 "Generate"（AI 星芒 icon）。
- 清單：先是**該群組／該模板可用**的扁平清單（群組限定 `enabled_on`：Header group 只列 Header - Classic (1/1)、
  Header - High Fashion (1/1)、Header - Jewelry (1/1)、Header mobile multi-tab、Header- Shoes (1/1)…；Popup group 列
  Age verification popup、Before you leave (1/1)、Multitasking bar (1/1)、Promotion popup (1/1)、Recent sale popup、
  Sticky notification bar、Sticky toolbar on mobile (1/1)；產品模板列 Quick order list (1/1)、Featured product banner、
  Product tabs、Recently viewed products (1/1)、Recommended products (1/1)），再依分類收合區（標題＋⌃）：Banners
  （Large logo／Marquee／Slideshow／Split showcase）、Blog（Blog posts／Featured article）、Collections（Collections:
  Editorial）、Forms（Email signup／Email signup banner）、Layout（Custom liquid／Custom section／Page）、Links
  （Breadcrumb）、Products（Lookbook／Product bundle／Product list: Carousel／Category／Duo／Editorial／Grid／Tabs
  carousel／Tabs grid／Vertical／Widget…）、其後分類未捲完（§V）。
- 已達上限者灰化並加後綴 "(1/1)"（`max: 1` 或 `limit`）。清單初次載入有骨架（skeleton）佔位。
- 右欄：hover 項目時顯示預覽（Ella 大多 "No preview available"；部分項目出現小幅線框縮圖）；"Generate" 選中時右欄是
  宣傳輪播 "Have an idea? Let's bring it to life"。
- Apps 分頁："No app blocks available for this section"＋"Recommended apps"（Shopify Forms 4.5★ Free，安裝 icon）。
- 區塊 picker（Header - Default）：Menu tab／Mega menu style #1／#2／#3／Vertical menu；（產品 Details 容器）：
  Breadcrumb／Product tabs，分類 Basic（Button／Heading／Icon／Image／Text／Video）、Layout（Accordion／Divider…）。

## 5. 預覽：裝置切換、inspector、hover 工具列、插入點

- **hover（inspector 開）**：目標 section／block 藍色外框；左上角標籤 chip（type icon＋名稱，藍底白字）；section 上下邊界
  各一顆藍色圓形「+」（tooltip "Add section"），點擊 ⇒ 區段 picker 錨在該邊界線下方。
- **點選**：預覽點到誰，左樹展開並捲到該列、右欄開其面板、URL 更新 `section=`（與 `block=`）。點選 section 時預覽捲到
  該 section（Promotion popup 被選中時彈窗直接彈出）。
- **浮動工具列**（選中元素下方置中）："Ask for changes"（Sidekick，面具 icon）｜複製 icon（Duplicate；群組 section／主
  section 灰）｜眼睛斜線（tooltip "Hide"）｜垃圾桶（tooltip "Remove"）。
- **右鍵**（預覽內的 block）：Copy／Paste（灰）／Duplicate／Rename／Hide（鍵帽 CtrlShiftH）／Add block before／Add block
  after／Edit code／Remove（鍵帽 Shift⌫）。
- **inspector 關**（頂欄鈕或 Ctrl+Shift+I）：hover 無任何覆疊，預覽如一般商店頁；再點鈕還原。
- **手機檢視**：預覽縮成置中手機寬（截圖框 274px ⇒ 換算≈358px CSS，推定為 375px 級裝置框；§V）、有獨立捲軸，
  chip／工具列照常運作。
- **全寬預覽**：見 §1 面板切換器；URL `previewMode=fullscreen`。
- 預覽右緣的圓形浮鈕（時鐘＝最近瀏覽、分享、回頂）是 **Ella 主題自己的**，不是編輯器 UI。

## 6. 儲存／發布／undo-redo／快捷鍵／URL 狀態

- Save：有未存變更時黑底主要鈕，否則灰；Ctrl+S 或點鈕 ⇒ 頂欄下方藍色進度條 → toast "Changes saved."（深色、置底
  置中、右側 ×）；儲存期間 Publish 鈕短暫灰化。
- Undo／Redo：改動後 Undo 亮；Undo 後 Save 仍為亮（實測一次；是否「撤回到乾淨即灰」未驗證，§V）；儲存後 Undo／Redo
  皆灰（與 §9.4 一致）。
- Publish（草稿）⇒ 對話框標題 "Save and publish Copy of ella-7-2-0-theme-source?"，內文 "Your customers will see this
  theme when they visit your online store."，鈕 Cancel／Publish（主要）。
- Exit 有未存變更 ⇒ 對話框 "Leave page with unsaved changes?"，內文 "Leaving this page will delete all unsaved
  changes."，鈕 Stay／"Leave page"（紅色危險鈕）；右上 ×。
- 快捷鍵對話框（"…" → Keyboard shortcuts，或 Ctrl+/）標題 "Keyboard Shortcuts"，四組：
  - General：Undo CTRL Z／Redo CTRL Y／Save CTRL S／See all shortcuts CTRL /
  - Tools：Preview inspector CTRL SHIFT I／Preview mode ⊞ CTRL I／Sidekick CTRL .
  - Navigation：Sections ⊞ CTRL 1／Theme Settings ⊞ CTRL 2／App Embeds ⊞ CTRL 3
  - Sections & Blocks：Hide & show CTRL SHIFT H／Remove SHIFT ⌫／Select previous SHIFT ↑／Select next SHIFT ↓／
    Open selected element SHIFT ENTER／Expand all sections CTRL SHIFT O／Collapse all sections CTRL SHIFT P
  - 註：`⊞` 是本尊在 Windows 上渲染的修飾鍵圖示；實測 Ctrl+2 與 Alt+Ctrl+2 都未切換面板（可能是焦點在 iframe 外），
    帶 ⊞ 的組合實際鍵位**未取得**（§V）。不帶 ⊞ 的組合（Ctrl+S、Ctrl+Z、Ctrl+Shift+O/P、Shift+↓）已實測有效。
- URL 狀態（皆為 query 參數，可直接分享／重載還原）：`section=<完整 section id>`（如
  `sections--19774792466535__header_default`、`template--19774791385191__collection_list_jUH9xq`）、
  `block=<section id>__<靜態 block id>__<block id>`（如 `…__static-collection-list__group_PKPLG8`、
  `…__main__product-details__price_wUxKFf`）、`previewMode=fullscreen`、`context=theme|apps`（左欄面板）、
  `category=gid://shopify/OnlineStoreThemeSettingsCategory/<分類名，空白以 + 編碼>?theme_id=…&first_setting_id=<首個設定 id>`、
  `colorScheme=scheme-1`、`customCss=true`、`previewPath=/products/acme-tee`（首頁時無此參數）。
- 分頁標題：`我的商店 3 · Edit Copy of ella-7-2-0-theme-source · Shopify`；切到產品後
  `我的商店 3 · Products · Acme Tee · Shopify`。

## 7. 佈景主題設定（全域 settings）與 app embeds

主題設定面板（左欄，URL `context=theme`）：標題 "Theme settings"；手風琴分類（來自 Ella settings_schema）：
Logo and favicon／Colors／Typography／Layout／Features／Animations／Buttons／Inputs／Arrows／Badges／Cart／
Variant pills／Product cards／Popovers and modals／Multi-level category／Search behavior／Currency format／
Social media／Preloading screen／Custom CSS／Theme style。展開一個分類時其餘不自動收合（本輪都手動收合；§V）。

實測到的內容：
- Logo and favicon：連結 "Manage store name"；Default logo（image_picker）；SVG logo（textarea）；Inverse logo
  （image_picker，說明 "Used when transparent header background is set to Inverse"）；SVG logo inverse；Favicon
  （說明 "Will be scaled down to 32 x 32px"）。
- Colors：Schemes（color_scheme_group，§3.7）＋色彩設定分段 Hot stock（Color）／Sale badge（Color／Background）／
  Sold out badge／New badge／Custom badge／Wishlist／Quick view／Compare（各 Color＋Background）…。
- Typography：Fonts（Body／Heading／Subheading 三個 font_picker）；Text presets（"Sizes automatically scale for all
  screen sizes"）：Body（Size select／Line height select）；Heading 1（Font Heading｜Body／Size 60px／Line height／
  Letter spacing／Case Uppercase）；Heading 2（50px）；Heading 3…。
- Layout：Page width（range 1770 px）／Space between template sections（range）；Grid（Horizontal gap 30 px／Vertical
  gap 30 px）；Right to left（Enable right to left toggle＋長說明列舉語言代碼）。
- Currency format：小標 "Currency codes"＋"Cart and checkout prices always show currency codes. Example: $1.00 USD."＋
  "Show currency codes" toggle。
- Social media：小標 "Social accounts"；Facebook／Instagram／YouTube／TikTok／X / Twitter／Snapchat／Pinterest／Tumblr…
  各一個文字欄（placeholder 為官方範例 URL）。
- Custom CSS："Adds custom styles to your entire online store."＋CSS 程式碼編輯器＋"Learn more about custom CSS"。
- Theme style：點分類 ⇒ 右欄 "Change theme style"：預設清單（Classic／Trendy Style／High Fashion／SuperMarket／
  Electronics／Pet supplies／Jewelry／Automotive／Shoes／Single Product／Chic Couture／Yoga／Pod Store／Gym／
  Industrial Tool／Swimwear）＋說明 "Changing your theme's style will affect both the settings and look and feel of your
  store." "Some settings will be lost when you change your style, but you will not lose any content from your store"＋
  底部 Cancel／"Change style"（未選時灰）。

App embeds 面板（URL `context=apps`）：標題 "App embeds"；搜尋 "Search app embeds"；說明 "You don't have any apps with
embeds installed. Find apps built for themes on the Shopify App Store."；小標 "Recommended apps with embeds"：
Shopify Forms（4.5★ Free）、Shopify Inbox（4.6★ Free），各帶安裝 icon。

## 8. CSS 量測（token 值表 → 元件量測 → 我方 token 映射）

量測法＝截圖像素 × 1.306（2048 / 1568）；JPEG 截圖無法讀色值與字重，**下列尺寸誤差 ±2px、色值一律 V**。
編輯器 CSS bundle（原計畫從 network 面板取 cdn 上的 CSS 原文）本輪未取得（擴充功能的 network 工具抓不到 iframe 資源），
故本節只有「元件量測」一段；token 值表與精確色值留待 E2 以本機 Chrome DevTools 補（§V）。

| 元件 | 截圖 px | 換算 CSS px | 備註 |
|---|---|---|---|
| 頂欄高 | 42 | ≈55 | 推定 56 |
| 左欄寬（含分隔線） | 232 | ≈303 | 推定 300＋分隔線 |
| 右欄寬 | 230 | ≈300 | |
| 左樹列距（行高） | 23 | ≈30 | 群組小標到首列亦同 |
| 左樹每級縮排 | 12–13 | ≈16 | |
| 設定面板列距 | 37 | ≈48 | 兩欄式列（標籤／控件） |
| 頂欄 icon 鈕 | 24 × 24 | ≈32 × 32 | 啟用態淺灰圓角底 |
| 手機預覽寬 | 274 | ≈358 | 推定 375 級裝置（§V） |
| 預覽選取外框 | 1–2 | 2 | 藍色，chip 貼左上角 |

色彩（目視，V）：選取／強調＝Shopify admin 藍（左樹選中底、預覽外框、chip）；Save 主要鈕＝近黑；Remove／Leave page
＝紅；面板底＝白、頁面底＝淺灰；分隔線＝淺灰。字級（目視，V）：左樹列與設定標籤約 12–13px，面板標題約 13px 半粗，
群組小標約 12px 灰。

我方映射原則（E2 動手時對照 `docs/design/23-interaction-css-spec.md` §1 tokens）：尺寸照上表換算取整到 4px 網格
（頂欄 56、側欄 300、樹列 30→32 或 28 擇一並登記、面板列 48、縮排 16）；色值用我方 tokens（鐵律 8／9：結構對齊、視覺自有）。

### 8.1 2026-09-03 1:1 量測（E3b；取代上表的 ±2px 估值）

量測法：使用者 Chrome 的 admin 分頁為 125% 頁面縮放（DPR 2.1875＝系統 1.75 × 1.25），`innerWidth` 1573；擴充功能截圖
寬 1254px ⇒ 1573／1254÷1.25 ≈ 1.00 ⇒ **截圖像素≈設計 px**。分頁必須在前景（`visibilityState` visible）才截得到。
色值仍取 JPEG 目視（V），尺寸誤差 ±1px。

| 元件 | 設計 px | 備註 |
|---|---|---|
| 頂欄高 | 56 | 與 §8 一致 |
| 面板切換 icon 鈕 | 32×32，間距 4，icon 20 | 啟用態淺灰圓角底、藍 icon |
| 左欄 | 灰底（#f1f1f1 級）上白卡：卡 x 8–290（寬 282）＋兩側 8 邊距＝300；圓角≈12；hairline 邊 | E2 的「白底＋右邊線」形態不符 |
| 卡片標題列「Home page」 | 高 36、左內距 8、16px 半粗、底 hairline | |
| 帶小標「Header group」 | 14px 深色 450、列高 30、左內距 0（＝body 8） | 不是灰色小字 |
| 列距 | 30＝列底 28（圓角 8）＋上下 1 | |
| 列內排位（相對卡左緣） | body 8 → row 內距 4 → chevron 16 盒（glyph≈8）@12–28 → 2 → type icon 16 @30–46 → 7 → 名稱 @53 | |
| 名稱 | 14px/20px 450 深色 | 選中列同字重 |
| 選中列 | 淺灰底（#f1f1f1 級） | hover 更淺 |
| 分帶分隔線 | hairline 滿卡寬；帶 padding 上 8 下 6 | |
| Add section | circle-plus 16 與 type icon 同 x；文字 14px 藍 550 | |
| 區段 picker | popover 貼左欄右緣、與該列同高；清單寬≈250＋灰預覽欄≈390；搜尋框 focus 藍框；Sections｜Apps 分段；Generate（紫星芒）；列 icon 16；達上限灰化 "(1/1)" | E5 |
| 插入線 | 藍 2px 橫線＋中央 ⊕ 圓標，位於目標插入位 | |

未取得（工具限制）：hover 動作列與右鍵選單（iframe 不吃擴充功能的合成 hover／右鍵）；右欄（本視窗 1258 設計 px 點選
section 未出右欄，需更寬視窗）。

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
- 實測對照：Add section／Add block／眼睛／垃圾桶／右鍵 Duplicate／Remove 全部與 §2、§5 一致；drag handle 實測形態為 ⋮⋮（六點）而非文字說的平行橫線（§V 登記差異）。

### 9.2 theme-settings（`/manual/online-store/themes/theme-structure/theme-settings`）
- 開啟：Online Store > Edit theme → sidebar 的 **Theme settings** icon（gear）。
- 分類（Horizon 世代命名）：Logo／Colors／Typography／Layout／Animations／Visual elements／Social media／
  Search behavior／Currency format／Cart／Custom CSS（"Enter your own CSS code, for example to customize the
  appearance of your online store's buttons"）／Theme style。分類實際由主題 settings_schema 決定。
- 儲存："Changes require clicking the **Save** button to apply store-wide updates across all pages."
- 實測對照：Ella 的分類見 §7（由其 settings_schema 決定）；Custom CSS／Theme style 兩個平台級分類形態見 §7。

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
- 實測對照：三面板、inspector、mobile、全寬預覽、template menu、market menu、Undo/Redo 行為、Save、Sidekick、快捷鍵表
  全部在 §1／§5／§6 實測到；help 沒寫的：面板切換器再點一次即全寬預覽、URL 狀態參數、右鍵選單完整項目、就地改名。

### 9.5 shopify.dev 編輯器契約（tools/online-editor＋sections/integrate-sections-with-the-theme-editor）
- `Shopify.designMode`："set to `true` when viewing the theme editor. Otherwise, it's set to `undefined`."（⇒ 我方公開頁
  輸出 `designMode = false` 是差異：本尊為 undefined，登記修）；另有 `Shopify.inspectMode`／`Shopify.visualPreviewMode`；
  Liquid 側 `{% if request.design_mode %}`。
- 事件（bubble，target＝section／block 元素）：`shopify:section:load` {sectionId}（"A section has been added or
  re-rendered"，主題須重跑該 section 的 JS）；`shopify:section:unload` {sectionId}；`shopify:section:select`
  {sectionId, load}；`shopify:section:deselect`；`shopify:section:reorder`；`shopify:block:select` {blockId, sectionId,
  load}；`shopify:block:deselect`；`shopify:inspector:activate`／`deactivate`。
- Block 定位：主題須在 block 父元素手動輸出 `{{ block.shopify_attributes }}`。
- 實測對照：URL 的 `section=`／`block=` 值即事件用的 sectionId／blockId 形（完整 id 含 `template--N__key` 與
  `__<static>__<block>` 串接）；選中 Promotion popup 時彈窗自動彈出＝主題對 `shopify:section:select` 的回應。

## V. 待驗證／工具限制

- V1 截圖不落倉：claude-in-chrome 的截圖只回傳給操作端，無檔案輸出；本檔以逐字轉錄替代，E2 起改用本機 Chrome 手動
  截圖入倉（資產目錄隨 E2 引入）。
- V2 編輯器 CSS bundle 未取得：iframe 資源不在擴充功能 network 面板；§8 只有截圖換算尺寸，色值／字級／字重全部待
  本機 DevTools 量測。
- V3 帶 `⊞` 的快捷鍵實際鍵位未取得（Ctrl+2／Alt+Ctrl+2 皆無反應；可能是焦點問題）。
- V4 拖曳重排：自動化拖曳未觸發（只選到文字）；本尊行為以 §9.1 為準，我方實作 E3 時以本機手動驗證。
- V5 模板選擇器 Pages 子清單未捲到底；區段 picker 分類 Products 之後的分類未捲完。
- V6 "Checkout and customer accounts"、"Edit code"、"Edit default theme content"、"Preview"、"View documentation"、
  "Get support" 這幾個離開編輯器的入口未點（本輪只記入口）。
- V7 Blog posts 子清單灰化的官方條件（推定＝店內無文章）未查 help。
- V8 手機預覽的精確寬度（推定 375px 級）與是否有平板檔位；三寬度（鐵律 13）對本尊編輯器本體的 RWD 形態本輪未量
  （E7 前補）。
- V9 Undo 撤回到乾淨狀態時 Save 是否轉灰；主題設定手風琴是否互斥（單開）。
- V10 Escape 不關 color popover（實測一次），其他 popover 皆可 Escape 關閉——待複驗是否穩定。
- V11 未出現的設定型別清單見 §3 末段（E4 以其他 section 或 Horizon 草稿補）。
- V12 §9.1 說 drag handle 是 "parallel horizontal lines"，實測 icon 為六點 ⋮⋮；以實測為準、登記差異。
- V13 Sidekick／"Ask for changes"／"Generate"／"Generate image" 這些 AI 入口不在我方射程（D79 未含 AI），E2 起以
  「留位不實作」處理，待使用者裁定。
