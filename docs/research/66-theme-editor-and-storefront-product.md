# 66 — 主題編輯器資料模型與前台商品詳情頁渲染鏈（Ella 7.2.0 原始碼解剖）

> **一句話**：主題編輯器的每一個控件、前台商品頁的每一個欄位，都不是 UI 設計出來的，是**主題原始碼的 `{% schema %}` 與 Liquid 物件讀取點決定的**。所以本篇不爬 UI，改讀原始碼。
>
> 本篇回答使用者的兩個問題：①「主題設計編輯器要做成什麼樣」②「後台的數據如何和前台的商品詳情頁面對接」。

---

## 0. 方法、來源與紅線

### 0.1 為什麼走原始碼（兩條路先失敗了，記下來免得別人重走）

| # | 嘗試 | 結果 | 為什麼 |
|---|---|---|---|
| 1 | 用瀏覽器拆實站主題編輯器 | ❌ 取不到 | 編輯器整個在**跨來源 iframe**（`online-store-web.shopifyapps.com`）內，父頁面 JS 讀不進 DOM |
| 2 | 開前台 preview URL 拆商品頁 | ❌ 取不到 | 商店有**密碼保護**，preview URL 導向密碼頁；不得代輸密碼 |
| 3 | **讀主題原始碼** | ✅ 本篇 | 實站主題就是 `ella-7-2-0-theme-source`，而 Ella 7.2.0 完整原始碼已在本倉庫 `test/fixtures/themes/ella-7.2.0` |

**第 3 條不只是「還能用的替代方案」，它本來就更好**：編輯器右欄能出現什麼控件、左欄的樹長什麼樣、商品頁讀哪些欄位——全部由 `{% schema %}` 與 Liquid 原始碼**定義**。爬 UI 只能看到「某個主題在某個頁面的當前狀態」，讀原始碼拿到的是**值域與規則本身**。

### 0.2 鐵律 9 邊界（本篇的自我約束）

`test/fixtures/themes/ella-7.2.0` 是**使用者已購買授權的測試 fixture，不得隨平台散布**（CLAUDE.md 鐵律 9）。因此本篇：

- ✅ 統計結構、歸納資料形態、記錄介面名稱（DOM 屬性名、JS 全域變數名、setting id、檔名行號）——這些是**互通契約**，不是著作內容；
- ✅ 引用 `檔案:行號` 供實作者自行查閱；
- ❌ **不貼 Ella 的 Liquid／JS 原始碼片段**，不把它的程式碼抄進我方產品或原型；
- ❌ 同樣不抄 Dawn/Horizon。

我方實作必須從本篇的**規格描述**重寫，不得以本篇為「貼上來源」。

### 0.3 出處等級

沿用 `docs/specs/63` §0.3：`〔fixture〕`＝Ella 原始碼實測（可重跑腳本驗證）｜`〔docs〕`＝既有研究文件｜`〔ours〕`＝**本專案推導**（無外部依據，實作前須覆核）。

### 0.4 數字同源聲明（鐵律 7）

本篇所有 Ella 數字由**兩支獨立寫的 walker** 各算一次並比對一致（一支走 `settings`＋`blocks[].settings` 兩層、一支走通用 stack 遞迴）。兩者皆得 **6,735**。凡與既有文件不一致者，一律列入 §C.2 勘誤表，**本篇不改既有檔案**。

### 0.5 檔案盤點（本篇基準，取代 27 §0 的部分數字）

| 資料夾 | 檔案數 | 拆解 |
|---|---|---|
| `layout` | 2 | `theme.liquid`、`password.liquid` |
| `templates` | 47 個項目 | **42 個 `.json` ＋ 4 個 `.liquid` ＋ 1 個 `customers/` 目錄（內含 7 個 `.json`）** ⇒ JSON template 合計 **49** |
| `sections` | 77 | **73 個 `.liquid`（其中 68 個有 `{% schema %}`）＋ 4 個 section group `.json`** |
| `blocks` | 245 | theme blocks 世代；**187 個 `_` 前綴＝私有**、58 個公開 |
| `snippets` | 198 | |
| `assets` | 252 | |
| `config` | 2 | `settings_schema.json`、`settings_data.json` |
| `locales` | 55 | **31 個前台 `.json` ＋ 24 個 `*.schema.json`（編輯器字串）** |

---

# A. 主題編輯器的資料模型（從 schema 推導）

## A.1 四層結構——編輯器的每一個面板都對應其中一層

```
① config/settings_schema.json   →  「佈景主題設定」全域面板（19 類、302 settings）
      值存 config/settings_data.json 的 current.*
      Liquid 取用：settings.xxx

② templates/*.json              →  左欄「區段樹」的資料本體（order 陣列 + sections map）
      每個 template 一棵樹；section 實例帶自己的 settings 與 blocks

③ sections/*.liquid {% schema %} →  section 被選中時右欄面板的「欄位定義」（68 個 schema）
      ＋ blocks[] 白名單決定「可以加什麼子卡片」

④ blocks/*.liquid {% schema %}   →  theme block 被選中時右欄面板的欄位定義（245 個 schema）
      ＋ 自己也能有 blocks[] ⇒ 樹可再往下長
```

**兩層 vs 四層的關鍵**：使用者問的「佈景主題設定與 section settings 是兩層」——在 Ella 這一代其實是**四層**（theme → template → section → block↺）。`block` 那一層會**自我遞迴**（block 的 schema 裡可再宣告 `blocks`，Ella 有 90 個 theme block 這樣做），所以編輯器的樹是**任意深度**的，不是固定三層。Ella 實際最深達 **6 層**（`templates/index.json` 的 `lookbook_q8nVmX`）〔fixture〕；平台上限 8 層〔docs：31 §ED2〕。

## A.2 Section 型別清單（73 個全表）

`presets` 欄為 `—` ＝ **不可經 picker 新增**（系統 section，只出現在對應 template）；`limit` ＝ 單例上限。

| section | 顯示名 | settings | blocks 白名單 | presets | limit | 位置閘門 |
|---|---|---|---|---|---|---|
| `age-verification-popup` | Age verification popup | 21 | — | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `announcement-bar` | t:names.announcement_bar | 6 | 3 型＋@app | 1 | 1 | enabled_on {groups: [header]} |
| `apps` | t:names.app | 1 | @app | 1 | — | — |
| `before-you-leave` | t:names.before_you_leave | 3 | — | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `blog-posts` | t:names.blog_posts | 59 | — | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `breadcrumb` | t:names.breadcrumb | 23 | — | 1 | — | disabled_on {groups: [header, footer, custom.popup, aside], templates: [index]} |
| `bulk-quick-order-list` | t:names.quick-order-list | 0 | — | — | 1 | enabled_on {templates: [product]} |
| `cart-drawer` | t:names.cart_drawer | 3 | — | — | 1 | enabled_on {groups: [custom.popup]} |
| `collection-list` | t:names.collection_list | 32 | @theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `color-swatches` | t:names.color_swatches | 0 | 1 型 | 1 | — | enabled_on {groups: [aside]} |
| `custom-liquid` | t:names.custom_liquid | 6 | — | 1 | — | disabled_on {groups: [custom.popup, aside]} |
| `editorial-collections-list` | t:names.collections_editorial | 13 | — | 1 | — | disabled_on {groups: [header, footer, custom.popup, aside]} |
| `faqs` | t:names.faqs | 36 | 5 型＋@theme＋@app | 1 | — | disabled_on {groups: [header, footer, custom.popup, aside]} |
| `featured-article` | t:names.featured_article | 24 | @theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `featured-collection` | t:names.featured_collection | 99 | @theme＋@app | 4 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `featured-collection-cate` | t:names.featured_collection_cate | 29 | 3 型＋@theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `featured-collection-list` | t:names.featured_collection_list | 132 | @theme＋@app | 4 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `featured-product` | t:names.featured_product | 10 | — | 1 | 1 | disabled_on {groups: [header, footer, custom.popup, aside], templates: [product]} |
| `featured-product-banner` | Featured product banner | 34 | — | 1 | 1 | enabled_on {templates: [product]} |
| `footer` | t:names.footer_group | 25 | 15 型＋@app | 10 | — | enabled_on {groups: [footer]} |
| `footer-bottom` | t:names.footer_bottom | 17 | — | — | — | enabled_on {groups: [footer]} |
| `header` | t:names.header | 142 | 6 型＋@app | 10 | 1 | enabled_on {groups: [header]} |
| `header_mobile` | t:names.header_mobile_multi_tab | 14 | 2 型 | 1 | — | enabled_on {groups: [header]} |
| `lookbook` | t:names.lookbook | 33 | 4 型＋@theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `main-404` | t:names.404 | 29 | 3 型＋@theme＋@app | — | — | — |
| `main-account` | t:names.account | 5 | — | — | — | — |
| `main-activate-account` | t:names.activate_account | 5 | — | — | — | — |
| `main-addresses` | t:names.addresses | 5 | — | — | — | — |
| `main-article` | t:names.blog_post | 13 | — | — | — | — |
| `main-blog` | t:names.blog | 23 | 10 型＋@theme＋@app | — | — | — |
| `main-cart` | t:names.cart | 7 | 9 型＋@theme＋@app | — | — | disabled_on {groups: [header, footer]} |
| `main-collection-banner` | t:names.collection_banner | 17 | 3 型 | — | — | — |
| `main-collection-bkup` | t:names.collection_container | 14 | — | — | — | enabled_on {templates: [collection]} |
| `main-collection-product-grid` | t:names.collection | 18 | — | — | — | — |
| `main-collection-product-grid-banner-adv` | t:names.collection | 31 | — | — | — | — |
| `main-list-collections` | t:names.collection_list_page | 21 | — | — | — | disabled_on {groups: [header, footer]} |
| `main-login` | t:names.login | 16 | — | — | — | — |
| `main-order` | t:names.order | 5 | — | — | — | — |
| `main-page` | t:names.page | 33 | 3 型 | — | — | — |
| `main-password-footer` | t:names.password_footer | 1 | — | — | — | — |
| `main-password-header` | t:names.password_header | 3 | — | — | — | — |
| `main-product` | t:names.product_information | 12 | @app | — | — | disabled_on {groups: [header, footer]} |
| `main-product-quick-add` | t:names.product_information | 8 | @app | — | — | disabled_on {groups: [header, footer]} |
| `main-register` | t:names.registration | 5 | — | — | — | — |
| `main-reset-password` | t:names.password_reset | 5 | — | — | — | — |
| `main-search` | t:names.search_results | 22 | — | — | — | — |
| `main-wishlist-page` | t:names.wishlist | 8 | 3 型 | — | — | disabled_on {groups: [header, footer, custom.popup, aside]} |
| `marquee` | t:names.marquee | 19 | 6 型 | 1 | — | disabled_on {groups: [custom.popup, aside]} |
| `media-banner` | t:names.media_banner | 14 | — | 2 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `media-gallery` | t:names.media_gallery | 31 | 4 型＋@theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `media-with-text` | t:names.media_with_text | 31 | 3 型＋@theme＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `multitab-image` | t:names.multitab_image | 52 | 1 型 | 1 | max_blocks 6 | disabled_on {groups: [header, custom.popup, aside]} |
| `multitasking-bar` | t:names.multitasking_bar | 5 | 3 型 | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `page` | t:names.page | 7 | — | 1 | — | disabled_on {groups: [header, footer, custom.popup, aside]} |
| `predictive-search-empty` | t:names.predictive_search_empty | 0 | — | — | — | — |
| `product-bundle` | t:names.product_bundle | 35 | — | 1 | — | enabled_on {templates: [product]} |
| `product-recommendations` | t:names.product_recommendations | 44 | 10 型＋@theme＋@app | 1 | 1 | enabled_on {templates: [product]} |
| `promotion-popup` | t:names.promotion_popup | 5 | 1 型 | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `quick-order-list` | t:names.quick-order-list | 14 | — | 1 | 1 | enabled_on {templates: [product]} |
| `recent-sale-popup` | t:names.recent_sale_popup | 17 | — | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `recently-viewed-products` | t:names.recently_viewed_products | 26 | — | 1 | 1 | disabled_on {groups: [header, footer, custom.popup, aside], templates: [index]} |
| `related-products` | t:names.related_products | 18 | — | — | — | — |
| `section` | t:names.section | 50 | 4 型＋@theme＋@app | 16 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `section-product-tabs` | t:names.product_tabs | 33 | 4 型 | 1 | — | enabled_on {templates: [product]} |
| `slideshow` | t:names.slideshow | 79 | 1 型 | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `sticky-notification-bar` | Sticky notification bar | 54 | — | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `toolbar-mobile` | t:names.sticky_toolbar_mobile | 7 | 5 型 | 1 | 1 | enabled_on {groups: [custom.popup]} |
| `video-carousel` | Video carousel | 19 | 2 型＋@app | 1 | — | disabled_on {groups: [header, custom.popup, aside]} |
| `cart-icon-bubble` | *(無 `{% schema %}`)* | — | — | — | — | 只能被 `{% section %}`/`{% render %}` 靜態引用 |
| `cart-live-region-text` | *(無 `{% schema %}`)* | — | — | — | — | 只能被 `{% section %}`/`{% render %}` 靜態引用 |
| `country-localization` | *(無 `{% schema %}`)* | — | — | — | — | 只能被 `{% section %}`/`{% render %}` 靜態引用 |
| `pickup-availability` | *(無 `{% schema %}`)* | — | — | — | — | 只能被 `{% section %}`/`{% render %}` 靜態引用 |
| `predictive-search` | *(無 `{% schema %}`)* | — | — | — | — | 只能被 `{% section %}`/`{% render %}` 靜態引用 |
**彙總**〔fixture〕：73 個 `.liquid` section → **68 個有 schema**、5 個沒有（`cart-icon-bubble`、`cart-live-region-text`、`country-localization`、`pickup-availability`、`predictive-search`）。**沒有 schema 的 section 不會出現在編輯器裡**，它們只能被 `{% section %}` 或其他 section 靜態引用——這是編輯器樹渲染器必須處理的分支，不能假設「每個 sections/*.liquid 都是一個可編輯節點」。

| 指標 | 值 |
|---|---|
| 有 schema 的 section | 68 |
| 有 `presets`（可經 picker 新增） | 40（共 80 個 preset 條目） |
| 無 `presets`（系統／`main-*`） | 28 |
| 有 `blocks[]` 白名單 | 33 |
| `limit`（單例） | 16 個，全為 `limit: 1` |
| `max_blocks` | **僅 1 個**（`multitab-image: 6`） |
| `enabled_on` / `disabled_on` | 21 / 27 |
| 宣告 `tag` / `class` | 21 / 38 |
| section 層 settings 小計 | 1,628 |

Theme blocks 側〔fixture〕：245 個全部有 schema；235 個有非空 `settings`、**230 個有 `presets`**、90 個有非空 `blocks[]`（可再巢狀）。

⇒ **可進 picker 的 preset 提供者合計 40 + 230 = 270**，與 27 §3 一致。

## A.3 `settings` 的 type 值域（26 型）＝ 我方主題編輯器的控件庫

這一節是**編輯器右欄要實作什麼**的權威清單。Ella 的 313 個 schema（68 section + 245 block）合計 **6,735 個 settings**，只用到 **26 種 type**。平台規格定義 35 種〔docs：26 §5〕，Ella 未用到的 9 種列在表末。

**分佈與累計覆蓋率**〔fixture〕：

| # | type | 數量 | 佔比 | 累計 |
|---|---|---|---|---|
| 1 | `range` | 2,015 | 29.9% | 29.9% |
| 2 | `select` | 1,947 | 28.9% | 58.8% |
| 3 | `header` | 873 | 13.0% | 71.8% |
| 4 | `color` | 612 | 9.1% | 80.9% |
| 5 | `checkbox` | 594 | 8.8% | 89.7% |
| 6 | `text` | 144 | 2.1% | 91.8% |
| 7 | `image_picker` | 97 | 1.4% | 93.2% |
| 8 | `color_scheme` | 75 | 1.1% | 94.4% |
| 9 | `color_background` | 73 | 1.1% | 95.5% |
| 10 | `url` | 57 | 0.8% | 96.3% |
| 11 | `video` | 44 | 0.7% | 97.0% |
| 12 | `paragraph` | 43 | 0.6% | 97.6% |
| 13 | `textarea` | 26 | 0.4% | 98.0% |
| 14 | `inline_richtext` | 25 | 0.4% | 98.4% |
| 15 | `product` | 24 | 0.4% | 98.7% |
| 16 | `richtext` | 24 | 0.4% | 99.1% |
| 17 | `collection` | 13 | 0.2% | 99.3% |
| 18 | `liquid` | 12 | 0.2% | 99.5% |
| 19 | `link_list` | 11 | 0.2% | 99.6% |
| 20 | `article` | 7 | 0.1% | 99.7% |
| 21 | `page` | 7 | 0.1% | 99.8% |
| 22 | `video_url` | 4 | 0.1% | 99.9% |
| 23 | `collection_list` | 3 | <0.1% | 99.9% |
| 24 | `product_list` | 2 | <0.1% | 100.0% |
| 25 | `number` | 2 | <0.1% | 100.0% |
| 26 | `blog` | 1 | <0.1% | 100.0% |

**兩個能直接指導排程的讀數**〔ours，由上表推導〕：

1. `header` 與 `paragraph` **不是控件**（純展示、無 `id`、無值）。扣掉這 916 個，**互動控件實例 ＝ 5,819**（獨立驗證：帶 `id` 的 setting 恰為 5,819 個）。
2. 在這 5,819 個互動控件裡，`range` + `select` + `color` + `checkbox` 四種佔 **5,168 ＝ 88.8%**。**先把這四個做到絲滑，Ella 的裝修體驗就成立了九成**；其餘 22 種是長尾正確性問題，不是體驗問題。

### A.3.1 逐控件規格——編輯器要渲染成什麼

> 「值序列化」＝存進 template JSON / settings_data.json 的形態；「Liquid 回傳」對照 26 §5。
> 標 ⛁ 者需同時支援**動態來源**（值可為 `{{ closest.product }}` 之類的引用字串，渲染期才解析，27 §6.4）。

| type | 編輯器渲染成 | 值序列化 | Ella 實測補充（決定控件細節） |
|---|---|---|---|
| `range` | **滑桿**＋數字讀數＋單位後綴 | number | 全 2,015 個**都合法**（無一超過 101 步上限）。`step` 分佈：1（1,732）／0.5（87）／2（63）／10（59）／5（39）／0.1（15）。單位：`px`（1,497）／`%`（285）／無（212）／`s`（12）／`deg`（4）／`min`（3）／`day`（2）。⇒ **step 可為小數 ⇒ 讀數不得用整數格式化**；單位是自由字串，不是列舉 |
| `select` | 選項 ≤3 → **分段按鈕組**；4–8 → 下拉；**>8 → 需搜尋框** | string | 選項數直方圖：2 個（673）、3 個（734）、4 個（321）為主，但**長尾到 62 個選項**（58/59/61/62 各數個，字型/圖示/動畫清單）。Ella **零個** select 使用 `optgroup`（`options[].group`）⇒ 分組是平台能力，Ella 不依賴 |
| `header` | 側欄**分組小標**（無值、無 `id`） | 不存值 | 873 個。是 Ella 面板的骨架——**沒實作它面板就是一大坨** |
| `color` | popover 色彩選擇器（色相條＋hex＋滴管） | `"#RRGGBB"` 或 `rgba()` | **543 個帶 `alpha: true`** ⇒ 透明度通道是主線需求不是選配 |
| `checkbox` | 勾選框（即時 patch） | boolean | 594 個 |
| `text` | 單行文字（debounce 300ms） | string | 144 個 |
| `image_picker` ⛁ | 媒體庫 modal（上傳／選取／alt／焦點） | `"shopify://shopify/files/x.png"` | 97 個。焦點需寫回 `image.presentation.focal_point` |
| `color_scheme` | 色票方案下拉（引用 scheme id） | scheme id 字串 | 75 個，**橫跨 61 個 section**（幾乎每個 section 都有）⇒ 這是 Ella 的主要配色機制，必須早做 |
| `color_background` | 背景輸入（**含漸層**） | CSS background 字串 | 73 個。值可能是 `linear-gradient(...)` ⇒ 不能用色彩選擇器代替 |
| `url` ⛁ | 資源 picker（商品／系列／頁面／blog／自訂 URL） | `/collections/x` 或 `shopify://collections/x` | 57 個。`shopify://` 需渲染期解析 |
| `video` | 媒體庫影片選擇器 | 平台影片參照 | 44 個 |
| `paragraph` | 側欄**說明文字**（無值） | 不存值 | 43 個 |
| `textarea` | 多行文字 | string | 26 個 |
| `inline_richtext` | 行內 RTE（**無 block 元素**） | 不含 `<p>` 的 inline HTML | 25 個 |
| `product` ⛁ | 商品 picker（單選） | handle | 24 個。**preset 內嵌動態來源在此出現**（`"product": "{{ closest.product }}"`，27 §2） |
| `richtext` | 迷你 RTE（b/i/link/list） | `<p>…</p>` HTML | 24 個 |
| `collection` ⛁ | 系列 picker（單選） | handle | 13 個 |
| `liquid` | CodeMirror Liquid 框 | Liquid 原始碼字串 | 12 個。渲染期執行受限子集，≤50KB |
| `link_list` | 選單 picker | menu handle | 11 個 |
| `article` ⛁ | 文章 picker | `blog-handle/article-handle` | 7 個（26 §5 原列 T2 ⇒ **Ella 用到，應提前**） |
| `page` ⛁ | 頁面 picker | handle | 7 個 |
| `video_url` | URL 輸入＋來源驗證 | 完整 URL | 4 個，全部帶 `accept`（YouTube/Vimeo） |
| `collection_list` ⛁ | 多系列（可排序） | array\<handle> | 3 個，帶 `limit` |
| `product_list` ⛁ | 多商品（可排序） | array\<handle> | 2 個 |
| `number` | 數字框（可空） | number \| nil | **僅 2 個**——Ella 幾乎全用 `range` 取代 |
| `blog` ⛁ | 部落格 picker | handle | 1 個 |

**Ella 未使用、但平台規格要求的 9 種**〔docs：26 §5〕：`html`、`radio`、`text_alignment`、`color_scheme_group`、`color_palette`、`font_picker`、`article_list`、`metaobject`、`metaobject_list`。其中 **`font_picker`（3 個）與 `color_scheme_group`（1 個）出現在 `config/settings_schema.json`**（見 §A.8）⇒ **它們不是「可以不做」，只是不出現在 section 層**。真正在 Ella 完全未出現的只有 `radio`、`text_alignment`、`color_palette`、`html`、`article_list`、`metaobject`、`metaobject_list` 7 種。

### A.3.2 setting 物件的欄位分佈（決定控件元件的 props）

〔fixture〕跨全部 6,735 個 setting 物件：

| 欄位 | 出現數 | 含義 |
|---|---|---|
| `type` | 6,735 | 必填 |
| `id` / `label` | 5,819 / 5,819 | 完全同步 ⇒ **有 id 必有 label**，可作為 schema 驗證器的斷言 |
| `default` | 5,309 | 91% 的互動控件有預設值 ⇒ preset 實例化時的填值來源 |
| **`visible_if`** | **2,999** | 見 §A.4 |
| `min`/`max`/`step` | 各 2,015 | 恰等於 `range` 數量 ⇒ 三者對 range 是**必填**，驗證器可硬性要求 |
| `options` | 1,947 | 恰等於 `select` 數量 |
| `unit` | 1,803 | range 專屬且**非必填**（2,015 − 1,803 = 212 個無單位） |
| `content` | 916 | 恰等於 `header`(873) + `paragraph`(43) |
| `alpha` | 543 | color 專屬 |
| `info` | 270 | 欄位下方灰字說明 |
| `accept` | 4 | `video_url` 專屬 |
| `limit` | 3 | list 型專屬 |

## A.4 `visible_if` — 44.5% 的設定是條件顯示，這不是選配功能

〔fixture〕**6,735 個 settings 中有 2,999 個（44.5%）帶 `visible_if`**。若不實作條件顯示引擎，Ella 的設定面板會**一次攤開將近兩倍的欄位**，等同不可用。

`visible_if` 的值是 Liquid 布林表達式字串。實測值域〔fixture〕：

| 面向 | 實測 |
|---|---|
| 運算子 | `==` 2,439｜`and` 510｜`!=` 425｜`or` 211｜`>` 7｜`<` 1。**無 `contains`、無 `>=`/`<=`** |
| 引用範圍 | `block.settings.*` 2,320 條｜`section.settings.*` 667 條｜**全域 `settings.*` 14 條** |
| 巢狀 | 有複合式（`and`/`or` 混用），但無括號分組 |

**兩個實作要點**〔ours〕：

1. **求值器不得用完整 Liquid 引擎**——它跑在**前端**（設定一改就要重算可見性，不能來回打伺服器）。做一個只支援「`{scope}.settings.{id}` 引用＋字面量＋`== != > <`＋`and or`」的安全求值器即可，值域已由上表封閉。
2. **作用域要含全域 theme settings**。那 14 條引用 `settings.logo` 之類的全域值⇒ 前端求值器的上下文**不能只餵當前 section/block 的 settings**，必須同時帶 theme settings 快照。這一條很容易漏，漏了的症狀是「少數欄位永遠不顯示」，且極難 debug。

## A.5 blocks / presets / 位置閘門

### A.5.1 三種 block 引用形態（同一棵樹上並存）

| 形態 | 白名單寫法 | 編輯器行為 | Ella 用量 |
|---|---|---|---|
| **顯式型別** | `"type": "text"` 等具名 | picker 只列這些；`_` 前綴者為私有件，**不進 @theme 泛用清單** | 50 種不同型別 |
| **`@theme`** | 開放容器 | picker 列出所有**非 `_` 前綴**的公開 theme block（58 個） | 47 處 |
| **`@app`** | app block 位點 | 我方渲染為空，**但不可炸**（graceful degrade） | 70 處 |

### A.5.2 `static` block —— 編輯器樹的「鎖定節點」

template JSON 的 block 實例可帶 `"static": true`。這種節點由 section 的 Liquid 以 `{% content_for 'block', type:…, id:… %}` **在固定位置**渲染，**不可拖拽、不可刪除、不可改順序**，只能改設定與隱藏。商品頁的 `media-gallery`／`product-details`／`sticky-atc` 三個容器都是 static。

⇒ **編輯器樹渲染器必須有兩種節點樣式**（可拖拽 vs 鎖定），且拖放校驗要把 static 節點當成「不可作為拖放目標」。這與 `block_order` 的關係是：**static block 不出現在 `block_order` 陣列裡**，只出現在 `blocks` map 中——`block_order` 只排可拖拽的那些。

### A.5.3 位置閘門（picker 過濾規則）

`enabled_on`（21 個）／`disabled_on`（27 個），值為 `{groups: [...], templates: [...]}`。實測出現的 group 名：`header`、`footer`、`aside`、**`custom.popup`**（`custom.<name>` 自訂群組的實戰用法）。實測出現的 template 名：`product`、`collection`、`index`。

⇒ picker 的過濾是**兩維**（當前 template 類型 × 當前 section group），不是單維；且 `enabled_on`（白名單）與 `disabled_on`（黑名單）**互斥使用**——Ella 無一 section 同時宣告兩者〔fixture〕。

### A.5.4 `max_blocks` 幾乎不存在

68 個 section 中**只有 1 個**宣告 `max_blocks`（`multitab-image: 6`）。⇒ 「每個 section 的子塊數上限」在真實主題裡**不是常用約束**；平台預設上限（`config/limits.yml`）才是主要防線，UI 不需為 `max_blocks` 做顯眼設計，但**必須實作**（否則那一個 section 會壞）。

## A.6 `templates/*.json` ＝ 編輯器左欄樹的資料形態

```
{
  "sections": {                      // key = 實例 id（穩定、preset 實例化時生成）
     "<instance_id>": {
        "type": "<section type>",    // 對應 sections/<type>.liquid
        "disabled": true,            // 可選：隱藏但保留（眼睛圖示）
        "name": "…",                 // 可選：使用者重新命名
        "settings": { … },           // 值 map，key = schema 的 setting id
        "blocks": {                  // 可選，子節點 map
           "<block_id>": {
              "type": "…",
              "static": true,        // 可選：鎖定節點
              "name": "…",
              "settings": { … },
              "blocks": { … },       // ← 自我遞迴
              "block_order": [ … ]   // 只排「非 static」子節點
           }
        },
        "block_order": [ … ]
     }
  },
  "order": [ "<instance_id>", … ]    // section 排序（左欄從上到下）
}
```

**七個容易做錯的地方**〔fixture 觀察 ＋ ours 推導〕：

1. **排序資訊有兩套且形態不同**：section 層用**頂層 `order` 陣列**；block 層用**節點內的 `block_order`**。不是同一個機制，序列化器要分開處理。
2. **`blocks` 是 map 不是 array**——順序由 `block_order` 決定，map 本身的 key 順序不可依賴。
3. **`block_order` 可為空陣列**（該節點只有 static 子節點時），也可**不存在**。兩者語義相同（無可拖拽子節點），但 JSON diff 會不同⇒ 儲存時要正規化，否則會產生無意義的 dirty 狀態。
4. **`static: true` 的子節點不列入 `block_order`**，但仍在 `blocks` map 中，且**必須保留**（刪掉就渲染不出來）。
5. `settings` 只存**與 default 不同**的值？——**否**，Ella 的實例把大量值寫實（`main` section 存了 10 個 settings，schema 有 12 個）。⇒ 我方不得假設「未出現＝用 default」以外的規則，讀取時一律 `instance.settings[id] ?? schema.default`。
6. **section 實例 id 有兩種風格**：語義 id（`main`、`footer`、`header_default`）與 **preset 生成 id**（`quick_order_list_XTrabM` ＝ `{type_snake}_{6碼}`）。生成器要照這個格式，否則編輯器 URL 的 `?section=` 深連結與實站不一致。
7. **`disabled: true` 是「隱藏」不是「刪除」**——Ella 的 `product.json` 就有一個（`quick_order_list_XTrabM`）。渲染器要跳過，編輯器要顯示為半透明＋斜線眼睛。

### A.6.1 Section groups（`sections/*.json`）

4 個群組檔，形態與 template JSON **幾乎相同**但多一個 `type` 且**沒有 `order` 以外的差異**：

| 檔案 | `type` | `name` | 內含 sections |
|---|---|---|---|
| `header-group.json` | `header` | Header group | 3（announcement bar、header、header_mobile） |
| `footer-group.json` | `footer` | Footer group | 2 |
| `popup-group.json` | **`custom.popup`** | Popup group | 5（multitasking bar、cart drawer、toolbar mobile、promotion popup、before you leave） |
| `general-group.json` | **`aside`** | General group | 1（color swatches） |

⇒ 編輯器左欄不是一棵樹，是**「群組區 ＋ template 樹 ＋ 群組區」的三段式**（header group → template 的 order → footer group），另加不在視覺流內的 `custom.popup` / `aside` 兩區。這正是 §A.5.3 的 group 閘門所過濾的維度。

## A.7 11 個商品 JSON 範本（實站右欄「佈景主題範本」下拉的來源）

〔fixture〕`templates/` 內 product 相關檔案共 **13** 個：**11 個 `.json`（＝下拉可選的範本）** ＋ 2 個 `.liquid`（`product.ajax_edit_cart`、`product.ajax_product_card_compare`——**不是給人選的**，是 `?view=` AJAX fragment，27 §6.6）。

| 範本 | sections | blocks 總數 | 最大深度 | 與 `product.json` 的差異落在哪 |
|---|---|---|---|---|
| `product.json`（預設） | 5 | 59 | 4 | 基準 |
| `product.product-full-width.json` | 5 | 111 | 5 | main-product：`page_width=full-width`、`equal_columns=true`；gallery：`media_presentation=grid`、`media_columns=one`、`constrain_to_viewport=false` |
| `product.product-full-width-2.json` | 5 | 67 | 5 | main-product：`page_width=full-width`、`equal_columns=true`、`gap=100`、`color_scheme=scheme-11` |
| `product.product-grid.json` | 3 | 53 | 4 | **gallery `media_presentation=grid`、`thumbnail_position=left`** |
| `product.product-image-gallery.json` | 3 | 53 | 4 | 同上（與 product-grid 的 gallery 設定完全相同） |
| `product.product-left-thumbnails.json` | 3 | 53 | 4 | gallery `thumbnail_position=left` |
| `product.product-right-thumbnails.json` | 3 | 53 | 4 | gallery `thumbnail_position=right` |
| `product.product-slider.json` | 3 | 53 | 4 | gallery `navigation=arrows` |
| `product.template-step-by-step.json` | 4 | 62 | 4 | gallery `zoom_type=inline`；另含 `section` 與 slideshow |
| `product.block_wishlist_card.json` | 1 | 9 | 3 | 不是商品頁，是 wishlist 卡片 fragment |
| `product.quick_add.json` | 1 | 10 | 3 | 用 `main-product-quick-add`，非 `main-product` |

**這張表最重要的一行是「差異落在哪」**〔fixture〕：五個外觀迥異的 gallery 範本（grid／image-gallery／left-thumbnails／right-thumbnails／slider）**在 `main-product` section 層的設定完全相同**，差異全部在 **`_product-media-gallery` 這一個 block 的 2–3 個 setting** 上。

⇒ 對我方的直接結論〔ours〕：

- **「範本」在資料上不是一種型別，只是同一棵樹的一份不同存檔**。`themeFilesUpsert` 一支 API 就能覆蓋「建立範本」＝複製 default JSON 後改檔名，不需要為範本設計獨立資料表。
- 但**範本切換必須是商品層的欄位**（後台商品頁右欄「佈景主題範本」下拉 ⇒ `products.template_suffix`），渲染器解析順序是 `templates/product.{suffix}.json` → 找不到則 fallback `templates/product.json`。這一條 14 §F1 已有，本篇只是給出**它的值域來自哪裡**：掃 `templates/` 目錄的 `product.*.json`。
- 編輯器「頁面切換器」的子選單要列這 11 個中的 **9 個**——`block_wishlist_card` 與 `quick_add` 是 fragment 用途，**不應出現在商家可選清單**。判別依據〔ours〕：其唯一 section 不是 `main-product`，或 section 數 = 1 且該 section 帶 `disabled_on: {groups:[header,footer]}`。⚠ 這個判別法是推導，Shopify 官方如何區分未查證 ⇒ **V-140**。

## A.8 `config/settings_schema.json` ＝ 全域佈景主題設定

〔fixture〕**20 個頂層項目**：第 1 個是 `theme_info`（純中繼資料，**無 settings**，編輯器不渲染），其餘 **19 個是設定分類，合計 302 個 settings**。

| 分類（`name`） | settings |
|---|---|
| `t:names.typography` | 47 |
| `Features`（**未翻譯，硬編英文**） | 31 |
| `t:names.cart` | 31 |
| `t:names.colors` | 28 |
| `t:names.buttons` | 26 |
| `t:names.product_cards` | 22 |
| `t:names.badges` | 20 |
| `t:names.multi_level_category` | 16 |
| `t:names.variant_pills` | 14 |
| `t:names.search_behavior` | 10 |
| `t:names.social_media` | 10 |
| `t:names.arrows` | 9 |
| `t:content.layout` | 8 |
| `t:names.inputs` | 7 |
| `t:names.popovers_and_modals` | 7 |
| `t:names.logo_and_favicon` | 6 |
| `t:names.preloading_screen` | 4 |
| `t:names.animations` | 3 |
| `t:names.currency_format` | 3 |

型別分佈（302）〔fixture〕：`range` 63、`select` 58、`header` 53、`color` 36、`checkbox` 35、`text` 21、`paragraph` 11、`image_picker` 4、`color_background` 4、**`font_picker` 3**、`liquid` 2、`collection` 2、`color_scheme` 2、`link_list` 2、**`color_scheme_group` 1**、`url` 1、`product` 1、`inline_richtext` 1、`page` 1、`textarea` 1。

**三個只有全域層才會遇到的實作要求**〔fixture〕：

1. **`color_scheme_group`（1 個）只能出現在這裡**——它定義的是**色票方案本身**（不是引用），對應 §A.3 的 75 個 `color_scheme` 引用。編輯器需要一個**方案管理器**（新增／編輯／刪除），而不是一般控件。
2. **`font_picker`（3 個）的資料源是平台字型庫**，不是主題資產⇒ 這是 31 §R3 的獨立基建，做不出來的話 typography 那 47 個設定裡有 3 個直接壞掉。
3. **分類名混用翻譯鍵與硬編字串**（`Features` 是英文字面量）⇒ 翻譯解析器必須是「以 `t:` 開頭才查表，否則原樣顯示」，不能無條件查表。

### A.8.1 `config/settings_data.json`

`{ current, presets }` 兩把鑰匙。`current` 有 **185 個鍵**，其中除了 302 個設定值之外還有兩個結構性成員：

- **`current.sections`**——存放**靜態渲染 section**（以 `{% section %}` tag 直接嵌在 layout 裡、不屬於任何 template JSON）的設定。Ella 用在 `main-password-header/footer`。⇒ 我方資料模型**必須留這個位置**，否則密碼頁的設定無處可存。
- **13 組 color schemes**（`scheme-1`…`scheme-13`）。
- 頂層 **`presets`**：具名整店風格（`Classic`、`Trendy Style`、`High Fashion`、`SuperMarket`、`Electronics`…）⇒ 編輯器「佈景主題設定」面板需要一個**風格切換器**：套用＝把 `presets[name]` 整份覆蓋到 `current`（破壞性操作，需確認 modal）。

## A.9 `locales/*.schema.json` ＝ 編輯器字串（不是前台字串）

〔fixture〕24 個檔案。`en.default.schema.json` 有 **1,866 個 leaf key**，分 8 組：`settings` 827、`options` 381、`names` 353、`content` 200、`info` 75、`categories` 18、`text_defaults` 11、`html_defaults` 1。`zh-TW.schema.json` 同樣 1,866 個⇒ **翻譯覆蓋是完整的**，我方 fallback 邏輯不會在 Ella 上被觸發（但仍必須實作，見下）。

**三個必須處理的坑**〔fixture〕：

1. 🔴 **這些檔案是 JSONC，不是 JSON**——`en.default.schema.json` 以 `/* … */` 區塊註解開頭，且為 CRLF。標準 `JSON.parse` / `JSON.load` **直接拋錯**。31 §IN 已寫「tolerant JSON」，本篇給出**具體證據與最小需求：需支援 `/* */` 區塊註解、`//` 行註解、尾隨逗號、UTF-8 BOM、CRLF**。
2. **前台與編輯器字串是兩套**：`xx.json`（31 個，前台，`en.default.json` 有 713 個 key，分 `products`/`accessibility`/`actions`/`cart` 等 9 組）與 `xx.schema.json`（24 個，編輯器）。`{{ '…' | t }}` 只查前者，`"label": "t:…"` 只查後者。**混用會是靜默錯誤**（顯示原始 key）。
3. **兩套語言清單不對稱**：`ar`、`hi` **只有 schema 沒有前台**；`bg`、`el`、`fi`、`hr`、`id`、`lt`、`nb`、`sk`、`sl` **只有前台沒有 schema**。⇒ 語言 fallback 必須**逐檔獨立解析**，不能用「主題支援語言集合」這個單一概念。

---

# A-bis. 動態來源（dynamic sources）——設定值裡藏 Liquid

在寫 §B 之前必須先講這個，因為**商品詳情頁的標題、描述、卡片綁定全靠它**，而它會顛覆「setting 值是純資料」的直覺。

〔fixture〕掃全部 49 個 JSON template ＋ 4 個 section group ＋ 313 個 schema 的 presets：

| 位置 | 含 Liquid 的設定值 | 涵蓋檔案 |
|---|---|---|
| template 實例的 `settings` | **467** | 36 個 template 檔 |
| schema `presets` 內的 `settings` | **148** | — |
| **合計** | **615** | — |

**但只有 15 種相異表達式**，值域完全封閉〔fixture〕：

| 表達式 | 次數（實例／preset） | 種類 |
|---|---|---|
| `{{ closest.product }}` | 378 / 115 | 資源引用 |
| `{{ closest.collection.title }}` | 21 / 9 | 純量插值 |
| `{{ closest.collection }}` | 12 / 6 | 資源引用 |
| `{{ closest.collection.description }}` | 10 / 1 | 純量插值 |
| `{{ closest.product.title }}` | 10 / 2 | 純量插值 |
| `{{ closest.page.title }}` | 7 / — | 純量插值 |
| `{{ closest.product.description }}` | 6 / 5 | 純量插值 |
| `{{ collection.image }}` | 5 / — | 資源引用（**無 `closest.` 前綴**） |
| `{{ closest.article }}` | 5 / 10 | 資源引用 |
| `{{ closest.blog.title }}` | 3 / — | 純量插值 |
| `{{ closest.page.content }}` | 3 / — | 純量插值 |
| `{{ closest.article.title }}` / `.image` / `.content` | 2 / 2 / 2 | 純量插值 |
| `{{ closest.product.vendor }}` | 1 / — | 純量插值 |

承載它們的 setting id 集中在 6 個：`product`(378)、`text`(65)、`collection`(12)、`collection_image`(5)、`article`(5)、`image`(2)。

**兩種語義必須分開實作**〔ours〕：

| 種類 | 例子 | 設定的宣告 type | 解析結果 |
|---|---|---|---|
| **資源引用** | `{{ closest.product }}` | `product` / `collection` / `article` / `image_picker` | 整個表達式**就是**該設定的值 ⇒ 解析為**資源物件本身**（不是字串）。這是商品卡「跟著上下文走」的機制 |
| **純量插值** | 運算式外面**包著 HTML 標籤**（商品標題那一筆就是 `{{ closest.product.title }}` 被一層 `h1` 包住） | `text` / `richtext` / `inline_richtext` | 表達式**嵌在 HTML 裡** ⇒ 需**渲染**該字串（Liquid 求值後輸出） |

**這帶來三個硬性後果**：

1. 🔴 **渲染器不能把 `text`/`richtext` 類設定值當純字串輸出**——必須先當 Liquid 模板求值。這是安全面（設定值是商家可控輸入）與效能面（每個 text block 多一次 parse）的雙重成本。緩解：值域封閉在上表 15 種 ⇒ **可用「白名單 pattern 比對 ＋ 直接取值」取代通用 Liquid 求值**〔ours〕，避免把任意 Liquid 執行權交給設定值。
2. **編輯器不能把它顯示成原始字串**。商家在標題欄看到一串帶大括號的 Liquid 是災難。必須渲染成**動態來源 chip**（「商品 › 標題」）＋可移除／可切回手動輸入（24 §4.1）。
3. **`closest` 是 T0 不是 T2**。26 §6.4 把 `closest` 列在 T2 長尾；但商品頁的標題與描述**在預設範本裡就依賴它**，沒有 `closest` 連 `<h1>` 都是空的。27 §1 已把它升 T0，本篇提供第二份證據並補上量化：**213 次 `closest.product` 直接引用 ＋ 615 個設定值內的動態來源**。

---

# B. 前台商品詳情頁的渲染鏈

## B.1 渲染鏈全圖

`templates/product.json`（預設範本）→ 5 個 section，其中只有 `main-product` 是商品主體：

```
GET /products/{handle}[?variant={id}]
  └─ layout/theme.liquid          ← <title>{{ page_title }}、meta description、canonical_url、content_for_header
      └─ templates/product.json   ← order: [main, quick_order_list, section_product_tabs, recently_viewed, recommendations]
          │
          ├─ ① main-product                          （12 settings；blocks 白名單只有 @app）
          │     ├─ ⚓ _product-media-gallery  (31 s)  ← content_for 'block'，static
          │     ├─ ⚓ _product-details        (19 s)  ← static；資訊欄容器
          │     │     ├─ group (68 s)
          │     │     │    ├─ text (69 s)             ← 【商品標題】通用 text block，值為動態來源（product.title，外包 h1）
          │     │     │    └─ product-info (11 s)     ← 【廠商／SKU／條碼／供貨狀態／類型】
          │     │     ├─ price (16 s)                 ← 【價格／比較價格／單位價格／分期】
          │     │     ├─ product-countdown (5 s)      ← 讀 metafield c_f.countdown
          │     │     ├─ variant-picker (8 s)         ← 【變體選項】→ snippets/variant-main-picker
          │     │     ├─ product-hot-stock (11 s)     ← 【僅剩 N 件】讀 inventory_quantity
          │     │     ├─ _perks (63 s)                ← 尺寸表／配色比較／專家詢問（含表單）
          │     │     ├─ _customization-option (5 s)  ← 【line item properties】文字/檔案欄位
          │     │     └─ buy-buttons (8 s)            ← 【加入購物車】{% form 'product' %}
          │     │           ├─ ⚓ quantity (0 s)
          │     │           ├─ ⚓ add-to-cart (17 s)
          │     │           └─ ⚓ accelerated-checkout (7 s)
          │     └─ ⚓ _sticky-add-to-cart (38 s)      ← 捲動吸底列（自帶一份變體選擇與價格）
          │
          ├─ ② quick-order-list      （"disabled": true —— 隱藏但保留）
          ├─ ③ section-product-tabs  （🔴 OS 2.0 local blocks，非 theme blocks）
          │     └─ description / html ×3             ← 【商品描述】＋自訂 HTML 分頁
          ├─ ④ recently-viewed-products
          └─ ⑤ product-recommendations
```

**⚓ ＝ static block**（不可拖拽／刪除）。巢狀最深 4 層。

### B.1.1 🔴 同一個範本裡混用兩代 block 系統

這是本篇對引擎規格最重要的單一發現〔fixture〕：

| section | block 機制 | 定義在 | 渲染方式 |
|---|---|---|---|
| `main-product` | **theme blocks**（新世代） | `blocks/*.liquid` 各自獨立檔案＋各自 schema | `{% content_for 'block', type:…, id:… %}` |
| `section-product-tabs` | **OS 2.0 local blocks**（舊世代） | section 自己的 `{% schema %}` 內 `blocks[]`（`description`/`review`/`html`/`liquid` 四型） | `{% for block in section.blocks %}` ＋ `{% case block.type %}` |

`blocks/description.liquid` 與 `blocks/html.liquid` **在磁碟上不存在**——它們是 local block 型別。⇒ **渲染器解析 template JSON 的 block 節點時，不能無條件去 `blocks/` 找檔案**：必須先查父 section schema 的 `blocks[]` 是否宣告了同名 local 型別，找不到才去 `blocks/`。搞反了的症狀是**商品描述整段消失**（因為描述就在這個 section 裡）。

〔docs：27 §1〕已記錄「section schema 內 local blocks 16 處」，本篇補上**它出現在商品頁的預設範本上**這個關鍵事實——不是邊緣案例。

### B.1.2 渲染閉包規模

從 `templates/product.json` 出發，追 `content_for 'block'` 與 `render` 的**遞移閉包**〔fixture〕：**5 個 section ＋ 39 個 block ＋ 62 個 snippet ＝ 103 個檔案**。這是我方 Liquid 引擎渲染一次商品頁要 parse／執行的最小檔案集，可直接作為 AST cache 預熱與效能預算的基準。

## B.2 ★ 後台欄位 → 前台呈現對照表

左欄的後台欄位取自實站拆解〔docs：59 §3、60、61〕，右欄為 Ella 的實際渲染點〔fixture〕。**這張表就是「後台的數據如何和前台的商品詳情頁面對接」的答案。**

### B.2.1 商品主體

| 後台欄位 | Liquid 物件 | 在哪個 section／block | 怎麼渲染 | 檔案:行 |
|---|---|---|---|---|
| **標題** | `closest.product.title` | `main-product › _product-details › group › text` | **不是專用 block**——是通用 `text` block，其 `text` 設定的值是一段**動態來源運算式**（引用 `closest.product.title`，外面包一層 `h1`）。商家可在編輯器改標籤層級、字級、對齊，甚至換成別的文字 | `templates/product.json`；`snippets/text.liquid:53,267` |
| **說明** | `product.description` | ①`section-product-tabs › description`（local block）②`blocks/_product-description.liquid` | ① 主要位置：分頁式描述，可 `truncatewords` 截斷。② 另一條路徑存在（`_product-description` block）但預設範本未用。描述輸出**未經 escape**（HTML 原樣） | `blocks/_product-description.liquid:7,9,16` |
| **多媒體檔案** | `product.media`、`product.images`、`variant.featured_media` | `main-product › ⚓_product-media-gallery` | 依 `media_type` 分派 `image`／`video`／`external_video`／`model`。**媒體排序會被變體覆寫**：若當前變體綁定了媒體，該媒體被 `concat` 提到最前（見 §B.3.3）。`media.size <= 1` 時關閉輪播；`> 15` 時分頁樣式降級 | `blocks/_product-media-gallery.liquid:11,38,50,58-73` |
| **類別（taxonomy）** | `product.category` | **無** | 🔴 **Ella 完全不讀 `product.category`**〔fixture：0 處〕。後台的「類別」驅動稅率與中繼欄位定義（59 §3），**不進前台渲染**。⇒ 我方不需為此欄位做前台面 | — |
| **商品類型** | `product.type` | `main-product › _product-details › group › product-info` | 標籤／值兩欄，`\| escape`；`type == blank` 時整行不渲染；另受 block 設定 `show_product_type` 控制 | `blocks/product-info.liquid:72-82` |
| **廠商** | `product.vendor` | 同上 | `\| link_to_vendor` ⇒ 渲染成**連到 `/collections/vendors?q=…` 的連結**，不是純文字。⇒ 我方必須實作 `link_to_vendor`／`url_for_vendor` filter，否則廠商欄變空 | `blocks/product-info.liquid:26-34` |
| **標籤** | `product.tags` | `_product-media-gallery`（徽章邏輯） | **標籤驅動徽章**：逐一 `\| handle` 後比對常數 `new` ⇒ 顯示 New 徽章。另有「上架天數 < `settings.new_badge_time`」的替代判準（二選一）。⇒ 標籤在前台**不是列表展示，是條件旗標** | `blocks/_product-media-gallery.liquid:108-121` |
| **狀態／銷售管道** | — | — | 不進 Liquid；由我方查詢層過濾（`Product.purchasable` / `discoverable`，63 §L-10） | — |
| **佈景主題範本** | `products.template_suffix` | 路由層 | 決定載入 `templates/product.{suffix}.json`（§A.7） | 路由層，非主題檔 |

### B.2.2 價格

| 後台欄位 | Liquid 物件 | 在哪個 block | 怎麼渲染 |
|---|---|---|---|
| **價格** | `variant.price`（＝`selected_or_first_available_variant.price`） | `price` block → `snippets/price.liquid` | `\| money`；若店家設定 `currency_code_enabled` 則 `\| money_with_currency` |
| **比較價格** | `variant.compare_at_price` | 同上 | **只在 `compare_at_price > price` 時**加 `price--on-sale` 類並以 `<s>` 劃線顯示。⇒ 「比較價格 ≤ 價格則不顯示」是**主題邏輯**，不是平台邏輯——我方不得在資料層擅自清空該欄 |
| 價格範圍（多變體） | `product.price_varies`、`price_min`、`price_max`、`compare_at_price_varies`、`compare_at_price_min` | 同上 | `price_varies` 為真 ⇒ 用 `from_price_html` 翻譯鍵渲染「HK$xxx 起」 |
| **單位定價** | `variant.unit_price`、`unit_price_measurement.reference_value`／`.reference_unit` | `price` block | 三個欄位一起讀；缺一則整段不渲染 |
| 量購階梯價 | `variant.quantity_price_breaks`、`.size`、`product.quantity_price_breaks_configured?` | `price` block ＋ `buy-buttons` | 設定了階梯價時**關閉 on-sale 樣式**改走 volume-pricing 樣式；並額外載入 `component-volume-pricing.css` 與 `price-per-item.js` |
| **每品項成本／利潤** | — | — | ✅ 不進前台（正確——成本不得外洩） |
| **對此商品收取稅金** | — | — | 不在商品頁；影響結帳計算 |

### B.2.3 庫存

| 後台欄位 | Liquid 物件 | 在哪個 block | 怎麼渲染 |
|---|---|---|---|
| **已追蹤庫存** | `variant.inventory_management`（`'shopify'` / blank） | `product-info`、`buy-buttons`、`_sticky-add-to-cart` | 未追蹤 ⇒ **恆顯示有貨、恆可購**（跳過所有數量判斷） |
| **可供貨數量** | `variant.inventory_quantity` | `product-hot-stock`、`buy-buttons`、`quantity-input`、`product-info` | ① 供貨狀態文案（>0 有貨／≤0 售罄）② **「僅剩 N 件」＋進度條**（`quantity ≤ block.settings.product_max_stock`，預設 20）③ 數量輸入框上限 |
| **缺貨繼續銷售** | `variant.inventory_policy`（`deny`/`continue`） | 同上 | `continue` ⇒ 供貨狀態改顯示**預購**文案且按鈕保持可用；`deny` ＋ 數量 ≤0 ⇒ 按鈕 disabled |
| 數量規則（B2B） | `variant.quantity_rule.min`／`.max`／`.increment` | `buy-buttons`、`quantity-input` | 影響數量輸入的 min/max/step；且 `quantity_rule.min > inventory_quantity` ⇒ 判定為售罄（**這條很容易漏**） |
| 門市取貨 | `variant.store_availabilities` | `pickup-availability`（**無 schema**，靜態引用） | 變體切換時由 JS 重抓 |
| 入庫中／預計到貨 | `variant.incoming`、`.next_incoming_date` | **無** | 🔴 Ella **完全不讀**〔fixture：0 處〕。與 63 §D.5 一致 |
| **地點層庫存** | — | — | Liquid 只看**加總後的** `inventory_quantity`；逐地點數字不進前台 |

### B.2.4 變體

| 後台欄位 | Liquid 物件 | 在哪個 block | 怎麼渲染 |
|---|---|---|---|
| **選項名稱／值** | `product.options_with_values`（→ `option.name`、`option.position`、`option.values`） | `variant-picker` → `snippets/variant-main-picker` + `product-variant-options` | 依 block 設定 `variant_style` 渲染成 **`dropdowns` 或 `pills`**；`pills` ＋ `show_swatches` ＋ 選項名命中 `settings.swatch` 時再升級為**色票**。`<fieldset>` ＋ radio 原生語義 |
| **選項值可用性** | `product_option_value.available`、`.selected`、`.product_url`、`.id`、`.swatch` | 同上 | 不可用值加 `label-unavailable` 隱藏文字（劃線但**仍可選**——三態機的中間態）。`value.id` 寫入 `data-option-value-id`（見 §B.3） |
| **單一變體商品** | `product.has_only_default_variant` | `variant-picker` 等 6 處 | 為真 ⇒ **整個變體選擇器不渲染**。對應 61 §1.1「無變體商品＝只有一個 `Default Title` 變體」 |
| **SKU** | `variant.sku` | `product-info`（`data-sku`） | 空值時整行 `display:none`（**不是不渲染**——留著讓 JS 在切換變體時填回） |
| **條碼** | `variant.barcode` | `product-info`（`data-barcode`）＋ JSON-LD | 同上；JSON-LD 依長度映射 `gtin8/12/13/14` |
| **變體圖片** | `variant.image`、`variant.featured_media` | media gallery、卡片、ATC 按鈕 | 17 處讀 `variant.image` ⇒ 變體切換時的圖片跳轉靠它 |
| 變體 URL | `variant.url`、`value.product_url` | 選項按鈕 `data-product-url` | 支援「不同選項值 ＝ 不同商品」的合併商品列表（`metafields.custom.combined_products_listing`） |

### B.2.5 中繼欄位（metafields）

〔fixture〕商品頁閉包內共讀 **13 個 namespace**：

| namespace | 用途 | 讀取位置 |
|---|---|---|
| `custom.custom_badge` | 自訂徽章文字 | gallery、商品卡 |
| `custom.size_chart` | 尺寸表內容 | `_size-chart` block |
| `custom.combined_products_listing`（＋`_name_color`、`_image`） | 合併商品列表（跨商品的選項值） | `variant-main-picker` |
| `c_f.countdown` | 促銷倒數結束時間 | `product-countdown` block |
| `c_f.product_card_marquee` | 卡片跑馬燈文字 | 商品卡 |
| `reviews.rating`／`.rating_count`（＋`.value`） | **Shopify 官方評論 metafield** | `product-review-rating` |
| `loox` / `yotpo` / `stamped` / `okendo` / `junip` / `reviewscouk` / `opinew_metafields` / `rivyo` | **8 家第三方評論 App 的 metafield**，逐一 fallback | `product-review-rating` |

**兩個結論**〔ours〕：

1. **metafield 讀取是「namespace.key 的動態存取」**，不是固定欄位。`section-product-tabs` 甚至用 `product.metafields.custom[block.settings.product_tab_key_metafield]` ——**key 來自設定值**。⇒ metafield drop 必須支援**任意 key 的 `[]` 存取並在不存在時回 blank**（不可拋錯），這是 31 §R7 的硬需求。
2. Ella 對 8 家評論 App 做 fallback 鏈 ⇒ **我方渲染為空是安全的**（主題自己會往下試），但 **`product.metafields.{任意}.{任意}` 必須永遠回 blank 而非炸掉**。

### B.2.6 SEO

| 後台欄位 | Liquid 物件 | 在哪 | 怎麼渲染 |
|---|---|---|---|
| **搜尋引擎標題** | `page_title` | `layout/theme.liquid:43,50` | 直接輸出到 `<title>`；且主題會判斷 `page_title contains shop.name` 決定要不要補店名 |
| **搜尋引擎說明** | `page_description` | `layout/theme.liquid:55-56` | `\| escape` 後輸出 `<meta name="description">`；空值時**整個 meta 不輸出** |
| **URL handle** | `product.url`、`product.handle` | 全站 | `canonical_url` 由平台注入（`theme.liquid:18-19`） |
| — | `content_for_header` | `theme.liquid:66` | 平台注入點 |
| 結構化資料 | — | `snippets/schema.liquid` | 見 §B.5 |

## B.3 變體選擇的前端機制

Ella 用的是 **option-value 制**（Shopify 2024+ 的新機制），不是傳統的 variant-id 制。這與我方原型註釋（`chilllove-storefront-v2.html` 的 `variantpicker`，寫的是 `?variant={id}&section_id=`）**不同**——見 §C.1。

### B.3.1 事件鏈（逐步）

| # | 步驟 | 機制 | 出處 |
|---|---|---|---|
| 1 | 商家在後台建變體 | — | — |
| 2 | SSR 渲染選項按鈕 | 每個選項值輸出 `data-option-value-id="{{ value.id }}"` 與 `data-product-url="{{ value.product_url }}"` | `snippets/product-variant-options.liquid:61,303` |
| 3 | SSR 同時輸出當前變體 JSON | `<script type="application/json" data-selected-variant>` 內含 `selected_or_first_available_variant \| json` | `snippets/variant-main-picker.liquid:163-165` |
| 4 | 使用者點選 | `<variant-selects>` 自訂元素監聽 `change`，收集 `select option[selected], fieldset input:checked` 的 `dataset.optionValueId` 成陣列 | `assets/product-info.js:1074-1146` |
| 5 | 發佈事件 | pub/sub `optionValueSelectionChange`，payload `{event, target, selectedOptionValues}` | 同上 |
| 6 | **`<product-info>` 發請求** | `GET {product_url}?section_id={sectionId}&option_values={id1,id2,…}` | `product-info.js:280-300, 367-377` |
| 7 | 回應是 **HTML 片段**（Section Rendering API） | 不是 JSON | — |
| 8 | 從回應中解析新變體 | 讀回應 DOM 裡的 `variant-selects [data-selected-variant]` 的 JSON | `product-info.js:362-365` |
| 9 | **替換 DOM** | `HTMLUpdateUtility.viewTransition` 替換整個 `<product-info>`（或 `<main>`） | `product-info.js:398-420` |
| 10 | 更新表單隱藏欄位 | 把 `variant.id` 寫進**四個** form 的 `input[name="id"]` 並派發 `change` | `product-info.js:571-583` |
| 11 | 改 URL | `history.replaceState` 寫 `?variant={id}`（**注意：URL 用 variant id，請求用 option_values**）；受 `data-update-url` 與 `includeVariantInUrl` 兩個旗標控制 | `product-info.js:585-593` |
| 12 | 更新 share button 的 URL | 同上 | — |

### B.3.2 兩個參數，兩種語義（極易做錯）

| 參數 | 出現在 | 值 | 誰消費 |
|---|---|---|---|
| `option_values=` | **請求** URL（AJAX） | 逗號分隔的 **option value id** 清單 | 伺服器：以此解析出唯一變體並設定 `product.selected_variant` |
| `?variant=` | **瀏覽器** URL（`replaceState`）＋分享連結 | variant id | 伺服器：**冷載入**時以此設定 `selected_variant` |

⇒ 我方 `/products/{handle}` 路由**必須同時支援兩種選變體方式**，且兩者要收斂到同一個「解析當前變體」的服務。只做 `?variant=` 會導致**每次點選項都選不中變體**（因為 AJAX 請求裡根本沒有 variant id）。這一條是 §C 的 G-3。

### B.3.3 切換時哪些東西要重繪

因為第 9 步是**整塊 `<product-info>` 替換**，所以理論上「全部」。但實作上有三類需要單獨注意〔fixture〕：

| 類別 | 內容 | 機制 |
|---|---|---|
| **隨 HTML 一起換** | 價格、比較價格、單位價格、SKU、條碼、供貨狀態、變體按鈕態、數量規則、媒體 gallery、量購階梯 | SRA 回應內已渲染好 |
| **JS 額外處理** | ① 「僅剩 N 件」的文字與進度條寬度（`handleHotStock`）② 門市取貨（`pickupAvailability.update(variant)`）③ 四個表單的 `input[name="id"]` ④ 瀏覽器 URL ⑤ share button | `product-info.js:571,585,676,731,809` |
| **設為不可用** | 找不到對應變體時，以 id 前綴批次清空：`price`、`Inventory`、`Sku`、`Price-Per-Item`、`Volume-Note`、`Volume`、`Quantity-Rules`（各自 `-{section.id}` 後綴） | `product-info.js:595-600` |

**媒體排序的變體聯動**〔fixture：`_product-media-gallery.liquid:58-73`〕：當前變體有綁定媒體時，gallery 會把該媒體從 `product.media` 中挑出來**排到最前**再接上其餘媒體。⇒ 我方 `product.media` drop 的**順序必須穩定且可被 `where: 'id', …` 過濾**，否則切換變體時圖片會亂跳。

### B.3.4 🔴 一個 volatile 資料的 JS 全域旁路

Ella 把庫存資料另外寫進 **JS 全域變數**（`window.product_inventory_array_{product_id}` 等三個 map，key＝variant id）：

| 全域變數 | 內容 | SSR 寫入點 | JS 增補點 |
|---|---|---|---|
| `product_inventory_array_{pid}` | variant id → 數量 | `blocks/product-hot-stock.liquid:25-29` | `product-info.js:414-427` |
| `product_inventory_policy_array_{pid}` | variant id → `deny`/`continue` | `snippets/variant-main-picker.liquid:170-175`、`sbs-variant-picker.liquid:93-98` | `product-info.js:399-411` |
| `product_inventory_management_array_{pid}` | variant id → boolean | （無 SSR 寫入） | `product-info.js:401-403` |

**必須精確**：SSR 首屏**只寫入當前選中的那一個變體**（不是全變體 map）；其餘條目由 JS 在每次變體切換的 SRA 回應中逐筆併入。⇒ **不是全目錄庫存外洩**，但**每個被瀏覽過的變體的即時庫存數字會累積在頁面 JS 記憶體中**。

對我方的三點〔ours〕：
1. 這強化 63 §D.5 的 volatile 判定——庫存數字不只出現在**文字**，還出現在 **`<script>` 內的 JSON**。純文字掃描的降級偵測器會漏掉它；正確做法仍是 63 §D.5 的「在 drop 讀取時註冊 `:volatile`」，**這個做法對 script 內的讀取同樣有效**（因為都經過 drop）。✅ 既有設計無需修改，本篇是它的第二個證據。
2. `data-selected-variant` 那個 `variant | json` 的輸出**必須與 Shopify 的變體 JSON 欄位集一致**（主題 JS 直接讀 `variant.id`、`.inventory_management`、`.inventory_policy`、`.inventory_quantity`）。⚠ Shopify 官方的 `variant | json` 是否包含 `inventory_quantity` **未查證** ⇒ **V-141**。Ella 的 JS 對此**寫了 fallback**（讀不到就去 DOM 找 `data-inventory-quantity` 屬性），這反過來暗示官方 JSON 可能不含該欄。
3. 這三個全域變數名帶 product id 後綴 ⇒ **同頁多商品**（快速加購、推薦輪播）不會互相覆蓋。我方若自寫主題，這個命名慣例值得沿用。

## B.4 庫存與價格的讀取點（接續 63 §D.5）

### B.4.1 先修正基準數字（鐵律 7）

63 §D.5 記「`inventory_quantity` 出現 41 次、橫跨 16 個檔案」。重新精確計數〔fixture〕：**41 是「命中行數」，實際出現次數是 47**，檔案數 16 正確。同段其餘數字同理：

| 符號 | 檔案數 | 命中行數 | 實際出現次數 |
|---|---|---|---|
| `inventory_quantity` | 16 | **41**（＝63 §D.5 的數） | **47** |
| `inventory_policy` | 11 | 25（＝63 §D.5 的數） | 28 |
| `inventory_management` | 13 | 18（＝63 §D.5 的數） | 18 |
| `incoming` | 0 | 0 | 0 |
| `next_incoming_date` | 0 | 0 | 0 |

⇒ 63 §D.5 的數字**不是錯的，是「行數」**。本篇不改它，只在 §C.2 登記口徑，避免日後有人用「次數」重數得到 47 而以為文件錯。

### B.4.2 商品詳情頁閉包內的 `inventory_quantity` 讀取點

103 個檔案中有 **8 個檔案**讀 `inventory_quantity`，合計 **18 行／21 次**〔fixture〕（口徑同 §B.4.1）：

| 檔案 | 出現次數 | 用途 | 妨礙快取？ |
|---|---|---|---|
| `blocks/buy-buttons.liquid` | 5 | 售罄判定（含 `quantity_rule.min` 比較） | 🔴 是——**在主要購買區** |
| `blocks/_sticky-add-to-cart.liquid` | 5 | 吸底列的同一套判定 | 🔴 是 |
| `snippets/product-hot-stock-main.liquid` | 5 | 「僅剩 N 件」文案＋進度條寬度 | 🔴 是——**數字直接印在 HTML** |
| `blocks/product-hot-stock.liquid` | 1 | 寫入 JS 全域 map | 🔴 是 |
| `snippets/quantity-input.liquid` | 2 | 數量框上限 | 🔴 是 |
| `snippets/quantity-selector.liquid` | 1 | 同上 | 🔴 是 |
| `blocks/product-info.liquid` | 1 | 供貨狀態文案 | 🔴 是 |
| `snippets/quick-order-list-row.liquid` | 1 | 批量下單列（該 section 預設 `disabled`） | 🟡 該 section 預設隱藏 |

**閉包外但同主題**的另外 8 個檔案（63 §D.5 已列的商品卡等）不在商品詳情頁的預設路徑上，但**商品卡出現在同一頁的推薦與最近瀏覽區** ⇒ 實務上同樣觸發。

### B.4.3 對快取的實際影響（本篇的新結論）

〔ours，基於 63 §D.3/§D.5 的兩級 staleness 政策〕

| 主張 | 判定 |
|---|---|
| 「只有 hot-stock 這種行銷元件讀庫存量，關掉就能恢復快取」 | ❌ **不成立**。`buy-buttons`（購買按鈕本身）與 `quantity-input`（數量框）都讀，這兩個**不能關** |
| 商品詳情頁能不能維持長 TTL | ❌ **不能**。整個 `main-product` section 的 fragment 必然帶 `:volatile` ⇒ TTL ≤ `volatile_section_ttl_seconds`（60s） |
| 那還剩什麼可以長快取 | ✅ 媒體 gallery、描述分頁、SEO/JSON-LD 這些**不讀庫存**的 fragment 仍可走 key-based 長快取——**前提是 fragment 粒度切在 block 層而不是 section 層** |

⇒ **落到規格上的一條**〔ours〕：63 §D.3 的 fragment 快取粒度若停在 section 層，商品頁等於整頁 60 秒 TTL。要保住命中率，**快取鍵必須下沉到 theme block 層**（Ella 的商品頁有 39 個 block，其中只有 6 個讀庫存）。這是既有規格未涵蓋的決策點 ⇒ **V-142**。

### B.4.4 價格讀取點

〔fixture〕商品頁閉包內價格相關讀取集中在 `snippets/price.liquid`（單一入口，被 `price` block 與 `_sticky-add-to-cart` 共用）＋ `snippets/schema.liquid`（JSON-LD）。**價格沒有 volatile 問題**——63 §D.5 已定：價格變更 bump `cache_stamp` ⇒ key 變 ⇒ 下次請求即新值。本篇未發現反例。

## B.5 JSON-LD（`snippets/schema.liquid`，88 行）

| 欄位 | 來源 |
|---|---|
| `@type: Product` / `name` / `description` / `url` | product |
| `image[]` | `product.images` **limit 10**，各 `\| image_url: width: 2048 \| prepend: 'https:'` |
| `brand` | `Brand` 物件 |
| `offers[]` | **逐變體展開**（不是只有選中的） |
| `offers[].price` | `variant.price \| divided_by: 100.0` |
| `offers[].priceCurrency` | `cart.currency.iso_code` |
| `offers[].availability` | `variant.available` → `schema.org/InStock` \| `OutOfStock` |
| `offers[].priceValidUntil` | `'now' + 31536000 秒`（＝一年後） |
| `offers[].sku` | `variant.sku \| strip` |
| `offers[].gtin8/12/13/14` | `variant.barcode`，依長度分派 |
| `offers[].mpn` | 無 barcode 時退回 sku |

**🔴 這推翻了 63 §D.6 的一個前提**。63 §D.6 說三處價格必須同源，並假設 JSON-LD「由 `structured_data` filter 或 SEO helper 產生」。**在 Ella 上不是**——JSON-LD 由**主題自己手寫的 snippet** 產生。後果〔ours〕：

1. 我方**無法從 SEO helper 側保證** JSON-LD 與 SSR 同源。能保證的只有**更底層的一件事**：`variant.price` 這個 drop 回傳的整數 cents 是同一個值。**同源的錨點必須從「同一個 formatter」下移到「同一個 drop」**。
2. `| divided_by: 100.0` ⇒ 主題自己把 cents 轉成十進位。這是**主題的除法，不是我方的**。我方能做的是保證 `variant.price` 回傳**整數 cents**（鐵律 3），並確保 `divided_by` filter 在整數 ÷ 浮點時的行為與 Shopify 一致。⚠ 若我方誤讓 `variant.price` 回傳已格式化字串或浮點，JSON-LD 會直接產生**錯誤價格**送給搜尋引擎。
3. **`priceCurrency` 讀 `cart.currency.iso_code` 而不是 `localization.market`** ⇒ 商品頁的 JSON-LD 幣別依賴 cart drop 可用。我方渲染商品頁時**必須提供 `cart` drop**（即使購物車是空的）。
4. 顯示面另有一層：鐵律 10 ＋ 裁定二要求**顯示一律 `HK$` ＋ 兩位小數**（`limits.currency_display.force_minor_unit_digits = 2`）。JSON-LD 的 `price` 是**數值**（`1480.0`）不受顯示規則約束；但 SSR 的 `| money` 輸出必須是 `HK$1,480.00`。**這兩者不一致是正常的**，不要在測試裡斷言相等。

---

# C. 對我方的落差與待辦

## C.1 落差清單

編號 `G-n`；「嚴重度」以**做錯的後果**分級，不以工作量分級。

| # | 落差 | 既有規格現況 | 本篇證據 | 嚴重度 |
|---|---|---|---|---|
| **G-1** | 🔴 **變體切換的請求參數搞錯了** | 27 §8-3 驗收寫「變體切換（SRA `?variant=&section_id=`）」；原型註釋 `variantpicker` 也寫「`?variant={id}&section_id=`」 | Ella 的 AJAX 請求送的是 **`option_values={id1,id2}`**（option value id 清單），`?variant=` 只用於 `history.replaceState` 與冷載入／分享連結〔fixture：`product-info.js:292,367-377,585-593`〕 | **高**——照現規格實作，商家每點一次選項都選不中變體 |
| **G-2** | 🔴 **同一 template 混用 theme blocks 與 local blocks** | 27 §7-12 有「三代混存」一條，但未指出它發生在**商品頁預設範本**上 | `product.json` 的 `main-product` 用 theme blocks、`section-product-tabs` 用 local blocks；`blocks/description.liquid` 與 `blocks/html.liquid` **磁碟上不存在** | **高**——解析順序搞反 ⇒ 商品描述整段消失 |
| **G-3** | 🔴 **設定值內的動態來源需要求值** | 27 §6.4 只講「preset 實例化時保留動態來源字串」；31 §ED3 只在 `image_picker`/`url` 兩列標了動態來源 | **615 處**（template 實例 467＋preset 148），承載於 6 個 setting id，**商品標題與描述都靠它** | **高**——不做則 `<h1>` 是空的；做錯則設定值變成任意 Liquid 執行點 |
| **G-4** | **`visible_if` 是面板引擎不是一個控件** | 31 §ED3 把它放在 30 列控件表的**最後一列** | **2,999 / 6,735 ＝ 44.5%** 的設定帶它；且 **14 條引用全域 theme settings**（求值器上下文需含 theme settings 快照） | **高**——不做面板不可用；作用域漏了則「少數欄位永不顯示」且極難 debug |
| **G-5** | **fragment 快取粒度須下沉到 block 層** | 63 §D.3 的快取階梯未明訂粒度；§D.5 只處理 volatile 標記 | 商品頁 39 個 block 中**只有 6 個讀 `inventory_quantity`**，但其中包含 `buy-buttons` 與 `quantity-input`（**不可關閉**）⇒ 粒度停在 section 層 ⇒ 整個 `main-product` 退化成 60s TTL | **中高**——影響 14 §F1 的命中率目標 |
| **G-6** | **JSON-LD 由主題產生，同源錨點須下移** | 63 §D.6 假設 JSON-LD「由 `structured_data` filter 或 SEO helper 產生」，並要求四處同源 | Ella 用自寫的 `snippets/schema.liquid`（88 行），價格走 `variant.price \| divided_by: 100.0` | **中高**——同源斷言要從「同一 formatter」改成「同一 drop 回傳同一整數 cents」，否則測試會寫成永遠失敗或永遠通過 |
| **G-7** | **`link_to_vendor` / `url_for_vendor` 應提前到 T0** | 26 §3.13 標 **T1** | 商品頁 `product-info` block 的**廠商欄直接用它**〔fixture：`blocks/product-info.liquid:32`〕；不實作則廠商顯示為空 | **中**——商品頁可見缺漏 |
| **G-8** | **locales 檔也需要 tolerant parser** | 27 §7-4 的寬容解析只涵蓋 **schema/settings JSON** | `locales/*.schema.json` 以 `/* */` 區塊註解開頭且為 CRLF ⇒ 標準 parser 直接拋錯 | **中**——匯入時炸在最後一步，症狀是「主題匯入失敗但錯誤訊息指向語系檔」 |
| **G-9** | **商品範本下拉的可選集合缺篩選規則** | 14 §F1 有 `template_suffix` 解析；31 §ED9 有「模板清單＋子選單」 | 11 個 `product.*.json` 中有 2 個是 fragment 用途（`quick_add`、`block_wishlist_card`），**不應出現在商家可選清單** | **中**——商家選到會得到破碎頁面 ⇒ **V-140** |
| **G-10** | **無 schema 的 section 不是編輯器節點** | 24/31 的樹規格假設 `sections/*.liquid` ↔ 可編輯節點 | 73 個中有 **5 個沒有 `{% schema %}`**（`pickup-availability`、`predictive-search` 等） | **中**——樹渲染器會產生 5 個空節點或崩潰 |
| **G-11** | **`main-product` 的 section 層 blocks 白名單只有 `@app`** | 31 §ED7 的 block picker 規格假設「白名單 ∪ @theme」 | 商品頁**所有可拖拽結構都在 static block 的子樹裡**；section 層本身幾乎加不了東西 | **中**——picker 在商品頁會顯示成空的，商家以為壞了。需要「在子容器上顯示新增入口」的 UI |
| **G-12** | **我方原型商品頁缺 5 類控件** | `docs/design/chilllove-storefront-v2.html` 的註釋登記表有 14 項商品頁控件 | 對照 Ella 預設範本的 38 種 block 型別，我方原型**無對應**者：①**個人化欄位輸入**（`_customization-option` → `_text-field`/`_file-field`，line item properties 的 **UI**——原型只在 ATC 註釋裡提到 `properties[]` 是 POST 欄位，沒有收集它的控件）②**吸底加購列**（`_sticky-add-to-cart`，38 settings）③**廠商／SKU／條碼／類型資訊列**（`product-info`）④**促銷倒數**（`product-countdown`）⑤**加速結帳按鈕**（`accelerated-checkout`／`payment_button`） | **中**——M6 驗收「商品頁卡片裝修」時會發現原型沒有可拖的東西 |
| **G-13** | ✅ **`product.category` 不需要前台面** | — | Ella **0 處**讀取 | **無**——這是「確認不用做」的結論，登記以免日後有人補做 |

## C.2 既有文件數字勘誤（鐵律 7；本篇不改檔案，只登記）

| # | 檔案 | 現述 | 實測〔fixture〕 | 性質 |
|---|---|---|---|---|
| **E-1** | `27` §4、`31` §6 矩陣 | section/block settings 合計 **6,687** | **6,735**。且 **27 §4 自己那份型別分佈逐項相加正好是 6,735** ⇒ 分佈表對、總數錯 | 算術錯誤 |
| **E-2** | `27` §0 | locales「**28 前台 ＋ 27** `*.schema.json`」 | **31 前台 ＋ 24 schema**（合計 55 正確，拆分錯） | 拆分錯誤 |
| **E-3** | `27` §0 | templates「47 ｜ **43 JSON ＋ 4 .liquid**」 | `templates/` 的 47 個項目 ＝ **42 JSON ＋ 4 .liquid ＋ 1 個 `customers/` 目錄**；含子目錄則 JSON 共 **49** | 口徑不明＋off-by-one |
| **E-4** | `27` §0 | 「含 **product×7**」 | product JSON 範本 **11 個**（＋2 個 `.liquid` fragment）。使用者說的「10+ 個商品範本」是對的 | 數字錯誤 |
| **E-5** | `27` §1 | `content_for` **268**（`block`×164、`blocks`×105） | 分項正確，但 164+105 ＝ **269** | 算術錯誤 |
| **E-6** | `27` §8-6 | 「Add section picker **49 個**可加 section」 | 全域是 **40 個 section／80 個 preset 條目**。49 可由「**商品範本**情境下的可用 preset 條目」重建（27 個 section／49 條）〔ours 重建〕⇒ 數字大概率正確但**缺情境標註** | 口徑缺失 |
| **E-7** | `63` §D.5 | 「`inventory_quantity` 出現 **41 次**、橫跨 16 個檔案」 | 41 是**命中行數**；實際出現次數 **47**；檔案數 16 正確。`inventory_policy` 25／28、`inventory_management` 18／18 同理 | 口徑（非錯誤） |

**已核對無誤者**（一併登記，避免重複查證）：`@app` 70／`@theme` 47｜私有 block 187｜`limit:1` ×16｜`max_blocks` 僅 1（multitab-image:6）｜`enabled_on` 21／`disabled_on` 27｜無 preset 的系統 section 28｜可進 picker 的 preset 提供者 270（40 section＋230 block）｜theme settings 19 類 302 個｜color schemes 13 組｜demo presets 16 組｜`current.sections` 存 `main-password-header/footer`｜`closest.*` 引用 269（product 213／collection 43／article 13）。

## C.3 待查證（V-140 起）

> 起編說明：倉庫現有最大編號為 **V-127**（`docs/specs/63` §K 用到 V-98，其餘散見於 59/60/61/62）。本篇自 **V-140** 起編，留 12 號緩衝避免碰撞。

| # | 項目 | 為什麼不能現在決定 | 暫時處置 |
|---|---|---|---|
| **V-140** | 商品範本下拉如何排除 fragment 用途的 `product.*.json` | Ella 有 2 個（`quick_add`、`block_wishlist_card`）明顯不是給商家選的，但**主題沒有任何欄位標記這件事**；Shopify 官方如何區分未查證 | 暫用啟發式〔ours〕：**唯一 section 不是 `main-product` ⇒ 不列入**。此規則對 Ella 100% 正確但樣本只有一個主題。**不得**把它寫死成不可設定的行為；匯入報告要列出被排除的範本供商家覆核 |
| **V-141** | Shopify 的 `variant \| json` 是否包含 `inventory_quantity` | Ella 的 JS 對此**寫了 fallback**（讀不到就去 DOM 找 `data-inventory-quantity`）⇒ 反向暗示官方 JSON 可能不含該欄。我方若擅自加入，等於**把全部被瀏覽變體的即時庫存塞進 HTML** | 依 26 §1.1 的 variant 屬性表照抄官方欄位集；**在查證前不主動加入 `inventory_quantity`**。加了拿不掉（主題會開始依賴） |
| **V-142** | fragment 快取鍵要不要下沉到 theme block 層 | 下沉能救命中率（39 個 block 只有 6 個 volatile），但會把快取項目數乘上一個數量級，且 block 層的 key 組成（含 `closest` 上下文）比 section 層複雜得多 | 首發**維持 section 層**（照 63 §D.3），並把 `liquid.volatile_render` 遙測加上 **block 型別維度**，用真實資料決定要不要下沉。**不得**在無資料時直接下沉 |
| **V-143** | 設定值內的動態來源要用「白名單 pattern」還是「通用 Liquid 求值」 | 白名單安全且快（值域封閉在 15 種），但主題若用了表格外的表達式就靜默失效；通用求值完整但把任意 Liquid 執行權交給設定值 | 首發**白名單 ＋ 未命中時記 `liquid.dynamic_source_miss` 遙測並原樣輸出**（不執行、不報錯）。此決策要在匯入更多主題後複審 |
| **V-144** | `section-product-tabs` 這類 local block 的**編輯器**行為是否與 theme block 完全一致 | 渲染面已清楚（`{% for block in section.blocks %}`），但編輯器面的差異未查證：local block 能不能巢狀？能不能 rename？`static` 概念適用嗎？ | 樹渲染器對兩者**一致對待**（同樣可拖拽／隱藏／改名），但**不允許 local block 巢狀**（Ella 的 16 處 local block 皆為單層）〔fixture〕。查證後再放寬 |
| **V-145** | `enabled_on` 與 `disabled_on` 是否真的互斥 | Ella 無一 section 同時宣告兩者〔fixture〕，但這可能只是主題作者的慣例而非平台約束 | schema 驗證器**只警告不拒收**；兩者並存時的解析順序暫定「`enabled_on` 先過濾，`disabled_on` 再排除」〔ours〕 |
| **V-146** | 我方是否要支援 Ella 未使用的 7 種 setting 型別 | `radio`、`text_alignment`、`color_palette`、`html`、`article_list`、`metaobject`、`metaobject_list` 在 Ella 零出現；但 26 §5 依官方 schema 列了 35 種，Dawn/Horizon 可能用到 | 36 種控件**全部實作**（schema 解析器一次做完，26 §6.1 已如此估算），但**排程放 M6b**；不得因為「Ella 沒用」就從清單刪除 |

---

## 附錄：本篇的可重跑驗證

所有 Ella 數字皆由對 `test/fixtures/themes/ella-7.2.0` 的靜態掃描產生，方法如下（供覆核者重跑；**腳本本身不入庫**，因為它的唯一輸入是授權 fixture）：

1. **schema 抽取**：正則取 `{%- schema -%}…{%- endschema -%}` 區塊 → 去尾隨逗號 → `json.loads`。73 個 section `.liquid` 中 68 個成功、5 個無 schema、**0 個解析失敗**；245 個 block **全部成功**。
2. **settings 計數**：兩支獨立 walker（一支明確走 `settings` ＋ `blocks[].settings` 兩層；一支用通用 stack 遞迴任意深度），兩者皆得 **6,735**，且型別直方圖總和同為 6,735。
3. **渲染閉包**：自 `templates/product.json` 的 section 型別與 block 型別出發，遞移追 `content_for 'block', type:'…'` 與 `render '…'`，得 5 sections ＋ 39 blocks ＋ 62 snippets ＝ **103 個磁碟檔案**（另有 2 個 block 型別 `description`／`html` 無對應檔案，即 §B.1.1 的 local blocks）。
4. **物件屬性掃描**：**先移除 `{% schema %}` 區塊、再移除所有單雙引號字串字面量**，然後才比對 `(closest.)?(product|variant|…)\.prop` ——這一步不做的話會把翻譯鍵（如 `'products.product.add_to_cart' | t`）誤計為屬性讀取，初次掃描即因此虛報 171 個路徑，去除後為 **96 個路徑／336 次讀取**。
5. **行數 vs 次數**：`grep -c` 回傳的是**命中行數**；本篇凡標「次數」者一律以 `grep -o | wc -l` 計，兩者在 §B.4.1 分列。
