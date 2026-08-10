# 03 — 前台商店與主題系統（Online Store / Themes / Liquid）

> 本篇拆解買家看到的前台：主題架構（OS 2.0）、主題編輯器交互、官方參考主題 Dawn 的頁面解剖、Liquid 模板語言、導航/多語系/SEO。這是第二階段做「前台 + 主題編輯器」的規格基礎。

## 1. Online Store 2.0 主題架構

### 1.1 檔案結構（固定目錄樹）

- `layout/`：外層版型。`theme.liquid` 必備，含 `{{ content_for_header }}`（平台注入 script/meta）與 `{{ content_for_layout }}`（模板內容插入點）；`password.liquid` 給密碼頁。
- `templates/`：每種資源一個模板（index、product、collection、page、blog、article、cart、search、404、list-collections、password；`customers/` 放帳號頁；`metaobject/` 給 metaobject 頁）。同一資源可有多個 alternate template（如 `product.pre-order.json`），在後台編輯資源時指派。
- `sections/`：可重用、可在編輯器調整的區塊模組（`.liquid`），以及 section groups 的 `.json`（`header-group.json`、`footer-group.json`）。
- `blocks/`：跨 section 重用的 theme blocks（較新機制）。
- `snippets/`：`{% render 'name' %}` 引入的片段。
- `config/`：`settings_schema.json`（定義全站 Theme settings）與 `settings_data.json`（商家選擇的值）。
- `locales/`：翻譯 JSON；storefront 字串用 `{{ 'key' | t }}`。
- `assets/`：CSS/JS/圖片。

### 1.2 JSON templates 與 sections everywhere

OS 2.0 核心：template 是一份 JSON 資料檔——`sections`（section ID → type/settings/blocks/block_order/disabled）+ `order`（渲染順序）。限制：每 template ≤25 sections、每 section ≤50 blocks、每 theme ≤1000 個 JSON templates。所有頁面都能加 section；header/footer 用 section groups 同樣可增刪排序。

### 1.3 Section schema

section 檔內 `{% schema %}` 定義：name、tag、class、limit、settings、blocks（各 block 有 type/name/settings；`@app` 允許商家插 app blocks）、max_blocks、presets（有 presets 才出現在「Add section」清單）、default、enabled_on/disabled_on、locales。

### 1.4 Theme settings

`settings_schema.json` 是分類陣列（theme_info + 各分類 settings[]）。設定型別：input 類（text、textarea、richtext、select、radio、checkbox、range、color、color_scheme、font_picker、image_picker、video、url、collection、product、blog、page、link_list、liquid…）與說明類（header、paragraph）。值存入 `settings_data.json`，Liquid 以全域 `settings` 讀取；section/block 各自以 `section.settings`、`block.settings` 讀取。

### 1.5 Liquid 核心

- **Objects**（`{{ }}` 輸出）：`shop`、`product`（title、price、variants、selected_or_first_available_variant、compare_at_price、media、options_with_values）、`collection`（products、filters、sort_options）、`cart`（items、total_price、note、attributes）、`customer`、`search`、`paginate`、`section`/`block`、`settings`、`routes`（多語系必用的動態路徑）、`localization`、`linklists`。
- **Tags**（`{% %}` 邏輯）：if/unless/case、for（limit/offset）、assign/capture、render、sections（渲染 section group）、section（靜態渲染）、form（`{% form 'product', product %}`、`{% form 'localization' %}`）、paginate、schema、style/javascript。
- **Filters**（`|` 串接）：money（依幣別格式化）、image_url + image_tag、t（翻譯）、asset_url、link_to、default、escape、where/map/sort、payment_button（動態結帳鈕）。
- 型別注意：只有 nil/false 是 falsy（空字串是 truthy，要用 blank 判斷）；運算子由右至左、無括號。
- Handle 索引：`pages['about-us'].title`。

## 2. 主題編輯器（Theme Editor）交互

進入：Admin → Online Store → Themes → Customize。三欄佈局：

- **左欄 section 樹**：依序 Header group / Template sections / Footer group，section 可展開看 blocks。操作：拖曳排序（block 也可拖）、眼睛 icon 隱藏（= JSON `disabled: true`，不刪資料）、刪除、「Add section」開可搜尋清單（= 有 presets 的 sections + app sections，受 enabled_on 過濾）、section 內「Add block」。
- **中間預覽**：即時渲染；頂欄有頁面/template 切換下拉（可搜尋，切到 product 等並選預覽用的具體商品）、裝置切換（desktop/mobile/全螢幕）、undo/redo；點預覽元素會同步選中左樹節點。
- **右欄設定面板**：當前 section/block 的 schema.settings 表單；未選中時可進 Theme settings（全站設定：color schemes、字體、layout、cart type…）。視窗 <1600px 時右欄併入左側。

**儲存與發佈**：改動按 Save 寫入 theme 的 JSON/settings_data；編輯已發佈 theme 則 Save 即上線。Theme library ≤20 個、僅一個 published；draft theme 可預覽後 Publish，原主題退回 library。

## 3. Dawn 頁面解剖（官方參考主題，開源）

Dawn 原則：HTML-first、JS 按需、伺服器端 Liquid 渲染、漸進增強。

- **首頁**：預設 sections 依序 image-banner（圖 + heading/text/button blocks）、rich-text、featured-collection（選 collection、桌機 4 欄/手機 2 欄、hover 換第二張圖）、collage、video、multicolumn；常用另有 slideshow、image-with-text、featured-product、collection-list、newsletter。
- **Collection 頁**：banner + 商品卡格線（card snippet：圖、標題、價格、sale/sold-out badge）+ paginate 分頁。**篩選**：商家在 Search & Discovery 定義 filters（≤25 個：Availability、Price、Category、Product type、Vendor、Tags、變體選項、metafields；每 filter ≤100 值；>5000 商品的集合不顯示篩選）；theme 以 `collection.filters` 渲染（active/inactive 值 + 計數）；URL 參數格式 `filter.{p|v}.屬性=值`（如 `filter.v.option.color=red&filter.v.price.lte=50`）；filter 間 AND、同 filter 值間 OR；桌機橫排或側欄、手機收 drawer。**排序**：`sort_by=` manual / best-selling / title-asc/desc / price-asc/desc / created-asc/desc。
- **Product 頁**：左媒體畫廊（image/video/external_video/3D model；stacked/carousel/thumbnail 佈局、zoom）；右資訊欄由可排序 blocks 組成：vendor、title、price、variant_picker（pills/swatch 或 dropdown）、quantity_selector、buy_buttons、description、collapsible_tab、share、complementary products、app blocks。**變體交互**：切換選項時以 Section Rendering API 重抓該 section HTML（URL 帶 `?variant=ID&section_id=…`）更新價格/庫存/媒體/按鈕；不存在的組合標 unavailable（劃線/淡化）、售罄組合按鈕 Sold out + disabled。**價格**：compare_at_price > price 時顯示劃線原價 + 現價 + Sale badge。**Buy buttons**：`{% form 'product' %}` 內 Add to cart（POST /cart/add）；可加 dynamic checkout button（Buy it now 直進 checkout，或依買家裝置/紀錄顯示 Shop Pay/PayPal/Apple Pay/Google Pay，僅單一 variant）。**推薦**：related products 延遲呼叫 `/recommendations/products?product_id=&intent=related`；complementary 需在 Search & Discovery 設定。
- **Cart**：Theme settings 選 **page / drawer / notification** 三種型態。互動走 Cart Ajax API：`GET /cart.js`、`POST /cart/add.js`、`/cart/change.js`、`/cart/update.js`；請求可帶 `sections` 參數一次取回更新後的 section HTML（如 cart-drawer、cart-icon-bubble）做局部更新。Cart note 開關 → `cart.note` 隨訂單送出；另有 cart attributes。小計旁慣例顯示「Taxes and shipping calculated at checkout」；免運門檻進度條是主題/app 常見自製慣例（讀 cart.total_price 與門檻比較）。
- **Predictive search**：header 搜尋展開 modal，輸入即打 `/search/suggest`（q + resources[type]=product,collection,page,article,query + limit），下拉分組顯示（建議詞/商品/頁面）；submit 進 `/search?q=` 完整結果頁（支援 filters）。
- **其他頁**：blog/article（文末 `{% form 'new_comment' %}` 留言，可設審核）、pages、policies（後台 Settings > Policies 填寫 → 自動生成 `/policies/*` 頁）、404、password page（Preferences 開密碼保護時全站顯示，可自訂）。

## 4. 導航與選單

後台 Content → Menus（舊：Online Store → Navigation）。預設 main menu + footer menu；項目可連 collection/product/page/blog/policy/外部 URL；拖曳縮排建巢狀（頂層下最多兩層）；theme 以 `linklists[handle].links` 遞迴渲染；Dawn header 提供 dropdown 與 **mega menu** 兩種桌機樣式，手機收 drawer；header 慣例含 logo、搜尋、帳號、購物車 icon（badge = `cart.item_count`）。

## 5. 多語系與多幣別（前台面）

- Markets 決定各市場幣別/價格/網域（詳見 05）；啟用後前台以買家市場的當地幣別顯示（`money` filter 與 `cart.currency` 自動反映 presentment currency）。
- 切換 UI：`{% form 'localization' %}` 做 country selector（`localization.available_countries`）與 language selector（`localization.available_languages`），僅多於一個選項時顯示，慣例放 footer/header。
- 翻譯：theme 靜態字串在 `locales/*.json`；商家內容（商品/頁面）用翻譯 app/API 存多語版本；啟用語言後 URL 加子資料夾（/fr），theme 需用 `routes` 組 URL；自動輸出 hreflang。

## 6. 網域與 SEO

primary domain（預設 `*.myshopify.com`，可綁自訂網域、其餘 301）。**Handle** 由標題自動生成（小寫、連字號、重複加 -1），可手動改、改時可自動建 301。URL 結構固定：`/products/{handle}`、`/collections/{handle}`（集合內商品頁 canonical 指向 `/products/*`）、`/pages/`、`/blogs/{blog}/{article}`、`/policies/`、`/search`、`/cart`。平台自動生成 sitemap.xml 與 robots.txt（theme 可用 `robots.txt.liquid` 覆寫）、canonical tag；每頁可編輯 title/meta description；og tags 由 theme 輸出（meta-tags snippet）。

## 7. Headless（簡述）

Storefront API（GraphQL，面向買家、可公開 token）→ 自建前端；Hydrogen（官方 React 框架）+ Oxygen（免費邊緣部署）。與 Liquid theme 是平行道路：要復刻「theme editor 體驗」，對應的是 Liquid/OS 2.0 這條路；demo 原型可以先用一般 React SSR 實作前台、把「theme = JSON 設定 + section 元件」的心智模型抽象進資料庫（見 07）。

## 8. 復刻要點 Checklist（本篇 → 工程）

1. 把「theme」抽象成資料：`templates`（JSON：sections + order）+ `settings`（全站）存 DB；section 對應前端元件註冊表——這樣 theme editor（左樹/中預覽/右設定）就是對這份 JSON 的編輯器。
2. Demo 先做 6–8 個 section 型別：announcement bar、header、image banner、featured collection、rich text、product grid、newsletter、footer。
3. 前台頁面優先序：collection 頁（含排序）→ product 頁（variant picker + add to cart）→ cart drawer → 首頁 sections。篩選（filters）可簡化為 availability + price + 選項。
4. Cart 用「Ajax API + 局部重渲染」模式（回傳更新後的 HTML 片段或 JSON），還原 Dawn 的加購體驗。
5. URL 結構照抄慣例（/products/handle、/collections/handle），handle 生成器 + 301 表從第一天做。
6. 多幣別/多語系 demo 階段先不做，但 money 格式化函式與字串表抽象先留好。
