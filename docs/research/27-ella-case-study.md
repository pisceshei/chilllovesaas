# 27 — Ella 7.2.0 案例研究：第三方主題「完全套用」的驗收基準

> 使用者提供了 **Ella 7.2.0**（Halothemes 出品、Theme Store 長銷主題）完整原始碼作為驗收標的：必須能完全套用此主題、使用它的所有卡片（sections/blocks）、在主題編輯器任意拖拽裝修，且裝修語言同樣適用於商品詳情頁。本文＝對 Ella 的逐檔解剖 ＋ 編輯器運行時契約研究 ＋ 對 25 號相容規格的差距修訂。**Ella 從此是我們的 golden theme：M6 的驗收就是「Ella 在 CHILL LOVE 上完整可裝修」**（授權注意：Ella 是商業主題，僅作內部相容性測試標的，絕不隨平台散布——見 25 §8）。

## 0. 檔案盤點

| 資料夾 | 數量 | 備註 |
|---|---|---|
| layout | 2 | theme.liquid（僅 116 行）＋ password.liquid |
| templates | 47 | 43 JSON ＋ 4 個 **.liquid alternate**（作 AJAX fragment 用，見 §7.4）；含 product×7、collection×5、page×14（landing/lookbook/FAQ/brands/store-locator…）、customers/×7（JSON） |
| sections | 77 | 其中 4 個 **section group JSON**（header/footer/popup/general）；28 個 `main-*` 系統 section 無 presets（不可經 picker 新增） |
| **blocks** | **245** | theme blocks 世代！**187 個 `_` 前綴＝私有 block**（不進 @theme picker，僅顯式白名單引用） |
| snippets | 198 | render 圖規模大（`render` 呼叫 1,121 次） |
| assets | 252 | js/css/svg；無第三方 app 硬依賴（外部只有 shopify CDN 與社群連結） |
| config | 2 | settings_schema.json **92KB**、settings_data.json **528KB** |
| locales | 55 | 28 前台 ＋ 27 `*.schema.json`（editor 字串） |

## 1. 世代判定：三代混合（我們的引擎必須同時吃）

| 證據 | 數字 | 含義 |
|---|---|---|
| `/blocks` 檔案 | 245 | **theme-blocks 世代**（Horizon 同代）為主體 |
| `{% content_for %}` | 268（`"block"`×164、`"blocks"`×105） | 靜態 block ＋ 子 block 渲染管線遍地都是 |
| `closest.*` 引用 | 269（product 213/collection 43/article 13） | 靜態 block 靠 `closest` 取得資源上下文——**closest 升級為 T0 必需** |
| section schema 內 local blocks | 16 處 | OS 2.0 遺產仍在（同引擎並存） |
| `.liquid` alternate templates | 4 | vintage 技法作 AJAX fragment（§7.4） |
| `@theme` 引用 | 47 | 開放式容器 |
| `@app` 引用 | 70 | app blocks 位點極多——我們平台渲染為空但**不可炸**（graceful） |

## 2. 商品詳情頁解剖（使用者點名的頁面）

`templates/product.json`＝5 sections：`main`（main-product）→ quick-order-list → product-tabs → recently-viewed → recommendations。

**main-product 的樹**（卡片系統核心示範；⚓＝static block，不可拖拽/刪除，只可設定與隱藏）：

```
main-product
 ⚓ media-gallery        (_product-media-gallery, 31 settings)
 ⚓ product-details      (_product-details, 19 settings)      ← 資訊欄容器
    ├ group              (group, 68s)                        ← 可拖拽子卡片開始
    │   ├ text           (text, 69s)
    │   └ product-info   (product-info, 11s)
    ├ price              (price, 16s)
    ├ product-countdown  (5s)
    ├ variant-picker     (8s)
    ├ product-hot-stock  (11s)
    ├ perks              (_perks, 63s)
    ├ customization-option (_customization-option, 5s)       ← 商品個人化
    │   ├ text-field     (_text-field)                       ← line item property 輸入
    │   └ file-field     (_file-field)
    └ buy-buttons        (8s)
 ⚓ sticky-atc           (_sticky-add-to-cart, 38 settings)
```

- **巢狀 4 層**（section → product-details → group → text）；每層皆可在編輯器選中/設定/拖拽（static 除外）。
- 商品資訊欄的順序＝block_order——商家把「價格移到標題上面」就是拖一下。**這就是「裝修語言適用於商品詳情頁」的具體形態。**

**卡片（product card）的可裝修結構**：recently-viewed 與 recommendations section 各含一個 ⚓`product-slide-item`（type `card-product-flex`），其子 blocks＝卡片本身的構成：

```
⚓ product-slide-item (card-product-flex, tag:null → 根元素帶 block.shopify_attributes)
   ├ _card-product-media-flex     （圖，preset 設定 "product": "{{ closest.product }}" ← 動態來源！）
   ├ _card-product-information ×N （資訊行容器，可多個）
   │   ├ _card-product-title-flex / _card-product-price-flex / _card-product-variant-flex
   └ _card-product-button-flex
```

- `card-product-flex` schema 的 blocks 白名單：`@app` ＋ spacer ＋ 8 個 `_card-product-*` 私有件。
- **preset 內嵌動態來源**：`"settings": {"product": "{{ closest.product }}"}`——preset 實例化時把 closest 引用寫進 instance settings，渲染期解析。復刻的 preset 實例化器與動態來源 resolver 都要支援。
- 意義：**商品卡不是寫死的 snippet，而是一組可拖拽 blocks**——列表頁/輪播裡的每張卡都跟著這個 static block 的子樹裝修結果變。

## 3. 卡片（sections/blocks）系統統計

- 270 個 schema 帶 presets（可進 picker）；**presets 依 name 字母排序、category 分組**（picker 規格）。
- 28 個無 presets 的 `main-*`/系統 section（main-product、main-cart、cart-drawer、predictive-search-empty…）＝只出現在對應 template，**不可新增**。
- `limit: 1` 單例 section ×16（header、announcement-bar、cart-drawer、各種 popup、toolbar-mobile…）。
- `max_blocks` 僅 1 處（multitab-image: 6）。
- `enabled_on` 21 / `disabled_on` 27——picker 按 template/group 過濾。
- 顯式 block 白名單高頻：`_divider`×42、`text`×32、`group`×26、`spacer`×26、`button`×20、`icon`×17——**通用排版件**（divider/spacer/group/text/button/icon/image/video/logo/_heading/_marquee/_breadcrumb）構成 Ella 的「萬用卡片庫」。
- section groups：header（3 sections）、footer（2）、**custom.popup（5：multitasking-bar、cart-drawer、toolbar-mobile、promotion-popup、before-you-leave）**、aside（general-group：color-swatches）——`custom.<name>` group 實戰用法；popup/drawer 類全掛在 popup-group，靠編輯器 select 事件開合演示。

## 4. 設定面統計

- section/block schemas 合計 **6,687 個 settings**；型別分佈：range 2015、select 1947、header 873、color 612、checkbox 594、text 144、image_picker 97、color_scheme 75、color_background 73、url 57、video 44、paragraph 43、textarea 26、inline_richtext 25、richtext 24、product 24、collection 13、liquid 12、link_list 11、page 7、article 7、video_url 4、collection_list 3、product_list 2、number 2、blog 1。→ **編輯器控件優先序**：range/select/color/checkbox 四種做到絲滑＝覆蓋 77% 的互動。
- theme settings（settings_schema.json）：19 分類、302 settings；分類名用 **`t:names.*` 翻譯鍵**（由 `locales/*.schema.json` 解析）——編輯器必須支援 schema 翻譯。
- settings_data.json（528KB）：`current`（302 值 ＋ **13 組 color_schemes**（scheme-1…13，每組 background/background_gradient/foreground_heading/foreground/primary/primary_hover/border/shadow…）＋ **current.sections**：`main-password-header/footer` 的設定——**靜態渲染 section（`{% section %}` tag）的設定存放處**，我們的資料模型要留這個位置）＋ 頂層 `presets`：**16 個具名 demo 風格**（Classic、Trendy Style、High Fashion、SuperMarket、Electronics、Jewelry…）——主題的「整店換裝」庫。

## 5. Ella 實際使用的 Liquid API 面（＝「Ella 相容集」）

對照 26 號全量清單，Ella 真正用到的（靜態掃描 522 個 .liquid）：

- **Tags（gem 外）**：`content_for`×268、`form`×45、`style`×18、`javascript`×9、`paginate`×8、`sections`×5、`stylesheet`×4、`layout`×4（`layout none`）、`section`×2；`{% doc %}`×61（LiquidDoc 註解——parse 得掉就行）。gem 內建的用量：if 4504、assign 4405、render 1121、liquid 521、capture 507、for 363、echo 135。
- **Filters：103 個唯一**（含少量 JS 管道誤判噪音如 `this/window/0`——正則掃描時 `|` 出現在 `{% javascript %}` 內；實際平台 filters ≈90）。T0 重點與用量：`t` 1333、`inline_asset_content` **370**（讀 SVG asset 內聯——新世代主題的 icon 機制，**必做**）、`asset_url` 240、`image_url` 160、`json` 154、`money` 87、`stylesheet_tag` 82、`handle/handleize` 91、`image_tag` 52、`placeholder_svg_tag` 42、`money_with_currency` 40、`font_face` 15、`font_modify` 12、`file_url` 13、`time_tag` 13、`item_count_for_variant` 10（cart 內某變體數）、`external_video_tag/url` 12、`link_to_vendor`/`url_for_vendor` 7、`format_address` 4、`line_items_for` 4（B2B quick order）、`payment_button` 2、`login_button` 2（Sign in with Shop——渲染空）、`payment_type_svg_tag` 2、`structured_data` 1、`model_viewer_tag` 1、`unit_price_with_measurement` 1、`color_brightness/color_modify` 3、`default_errors` 1、`pluralize` 1、`img_url` 6（deprecated 但仍在用——**要支援**）。
- **Objects**：block 1415、section 838、settings 752、product 284、forloop 232、form 196、media 89、article 88、cart 86、shop 74、request 67、routes 60、collection 58、line_item 46、paginate 40、localization 36、predictive_search 30、customer 24、search 24、order 26、**closest 39 處引用（值傳遞 269 次）**、recommendations 6、gift_card 9、filter（faceted search）91。
- **routes**：16/19 屬性（cart_url、search_url、root_url、account_*、cart_add/update/change_url、predictive_search_url、product_recommendations_url、all_products_collection_url、blogs_url…）。
- **JS 全域**：window.routes、window.Shopify（designMode 23 處）、Shopify.PaymentButton、Shopify.CountryProvinceSelector、Shopify.ModelViewerUI、Shopify.loadFeatures、Shopify.postLink、**ShopifyXR**×11（3D/AR——T2，stub 不炸即可）。
- **端點**（JS 內）：`/cart/add|update|change` ＋ `cart.js`、`section_id=`×8（SRA）、`?view=`×3、predictive search、`variant=`×6、**`/cart/shipping_rates`×3**（運費試算——要實作）。

## 6. 編輯器運行時契約（研究代理＋Ella 原始碼雙重驗證）

這是「編輯器與 Shopify 完全一樣」的硬規格——主題 JS 監聽這些介面，錯一個 Ella 的互動就壞。

### 6.1 八個 DOM 事件（bubbles: true, cancelable: false，派發於預覽 iframe 內）

| 事件 | target | detail | 時機 |
|---|---|---|---|
| `shopify:section:load` | `#shopify-section-{id}` wrapper | `{sectionId}` | 新增/重渲染插入 DOM 後（主題在此重新初始化 JS） |
| `shopify:section:unload` | 舊 wrapper | `{sectionId}` | 刪除/重渲染前/隱藏時（主題清理） |
| `shopify:section:select` | wrapper | `{sectionId, load}` | 選中；`load:true`＝重渲染後補發、`false`＝使用者點選 |
| `shopify:section:deselect` | wrapper | `{sectionId}` | 取消選中 |
| `shopify:section:reorder` | wrapper | `{sectionId}` | 拖拽排序（只動 DOM、不重渲染） |
| `shopify:block:select` | 帶 `data-shopify-editor-block` 的元素 | `{blockId, sectionId, load}` | 選中 block |
| `shopify:block:deselect` | 同上 | `{blockId, sectionId}` | 取消 |
| `shopify:inspector:activate/deactivate` | — | — | preview inspector 開關 |

**Ella 的實際監聽**（＝驗收樣本）：`theme-editor.js`（unload 時 `[data-section="${sectionId}"]` 清理被搬到 body 的殘留節點；load 時「複製 script 節點再替換」強制重跑——**證明編輯器插入的 HTML 不自動執行 script**）、`cart-drawer.js`（select 且 `target.matches('.section-cart-drawer')` → 開 drawer、deselect 關）、`details-disclosure.js`（mega-menu `<details>` 在自身監聽 block:select 展開）、`promotion-popup.js`/`before-you-leave.js`/`age-verification-popup.js`（designMode 停 idle timer、select/deselect 控開合）、`animations.js`（load/reorder 重掃動畫）。

### 6.2 標記與旗標

- wrapper：`<{schema.tag||div} id="shopify-section-{fullId}" class="shopify-section {schema.class}">`；design mode 加 `data-shopify-editor-section='{"id","type"}'`（平台自動）。
- `{{ block.shopify_attributes }}` → `data-shopify-editor-block='{"id":"…","type":"…"}'`（**僅 design mode 有值**；每 block 只能一個元素帶它；tag:null 的 theme block 由作者手放——Ella 的 card-product-flex 即是）。
- `Shopify.designMode`/`Shopify.inspectMode` JS 旗標 ↔ `request.design_mode` Liquid；Ella 的 main-product 只在 design mode 載入 theme-editor.js。
- inspector 描框＝對 `data-shopify-editor-*` 元素取 `getBoundingClientRect()`。

### 6.3 重渲染與即時 patch

- 改 setting（commit）→ 私有渲染通道以**草稿 JSON** 渲染單 section → `unload` → outerHTML 替換（script 不執行）→ `load` → 若仍選中補發 `select(load:true)`。
- 即時通道（不重渲染）：color setting 在 `{% style %}` 內 → CSS variable 直接改；text 值若是父元素唯一 child → 改文字節點。（與 21 號實測「調色即時全頁變色」一致。）
- 公開 SRA **不能傳未儲存設定** → 編輯器必須有自己的 draft-render 端點（Rails: `POST /editor/render_section`，body＝draft template JSON＋section id）。

### 6.4 ID 規則與 preset 實例化

- 現行 ID 生成：`{type 之 - 換 _}_{6 碼 base62}`（Ella 全部如此：`slideshow_tyrRgz`、`price_wUxKFf`）；舊世代（timestamp+hex、UUID）要能**讀**。
- 渲染期 fullId：`template--{template 內部 id}__{key}`、group `sections--{n}__{key}`；`section.id` 回 fullId；`section.index` 在編輯器/SRA 回 nil。
- block id 唯一範圍＝section 內（Ella 兩個 section 都有 `product-slide-item`）。
- preset 實例化：深拷貝 settings（缺的補 schema default）→ 遞迴實例化 preset blocks（含巢狀）→ 生成 block_order 與新 ID；**preset settings 可含動態來源字串**（`{{ closest.product }}`）原樣寫入。
- duplicate＝全樹深拷貝＋全部 ID 重生。

### 6.5 揀選器（picker）規則

- Add section：僅列有 presets 的 section（Ella：77−28=49 個可加）；preset name 字母排序、category 分組；受 enabled_on/disabled_on 過濾；插入點＝側欄底部＋選中 section 上下緣 `＋`。
- Add block：容器 schema `blocks` 白名單 ∪ `@theme`（**排除 `_` 前綴私有**）；顯式列出者為 recommended、其餘收 Show all；巢狀同規則遞迴；跨 section 拖動需目標容器相容。
- 靜態 block：不可拖/刪/複製，可設定/隱藏；未渲染時側欄虛線眼睛。
- 預覽內無自由拖拽（Shopify 也沒有）：選中 toolbar＝Move 上/下、Duplicate、Hide、Delete。

### 6.6 `?view=` alternate template 機制（Ella 的 AJAX 基座）

| 檔案 | 用法 |
|---|---|
| `product.ajax_edit_cart.liquid` | `{% layout none %}` → cart 內「編輯」彈窗抓 `{item.url}&view=ajax_edit_cart` 裸 fragment |
| `cart.ajax_side_cart.liquid` | `{% layout none %}` → side cart HTML |
| `product.quick_add.json` | JSON alternate → quick-add.js fetch `?view=quick_add` 整頁後前端剪節點 |
| `product.block_wishlist_card.json` | wishlist 卡片 fragment |
| `product.ajax_product_card_compare.liquid` | 比較功能 fragment |

→ 復刻 router：`{type}.{suffix}.{json|liquid}` 解析 `?view=` ＋ 支援 `{% layout none %}`。**這 5 個檔案就是驗收用例。**

## 7. 差距清單（25 號規格需要的修訂——已回寫）

1. **`closest` 物件升級 T0**（Ella 269 處；preset 動態來源也引用它）。
2. **`inline_asset_content` filter 升級 T0**（370 處——icon 全靠它）。
3. **靜態 section 設定存放**：`settings_data.current.sections`（Ella 的 password header/footer）——資料模型補位。
4. **寬容解析**：schema/settings JSON 帶註解與尾逗號（官方 admin 會清掉，但**原始碼包直接匯入時必遇**）→ 匯入管線用 tolerant parser＋規範化落庫。
5. **缺 group 檔寬容**：theme.liquid `{% sections 'toolbar-mobile' %}` 引用不存在的 group JSON——渲染空＋警告，不炸。
6. **schema 翻譯鍵**：`t:names.*` 在 name/label/options → 編輯器用 `locales/*.schema.json` 解析（含 fallback en）。
7. **`{% doc %}` tag**：gem 5.8+ 已支援，確認開啟。
8. **`/cart/shipping_rates.json`**：Ella 用了——列入 M2 端點。
9. **`?view=` 路由與 `{% layout none %}`**：升級 M2（原以為 M6 可延後——cart 編輯彈窗依賴它）。
10. **app blocks graceful**：70 處 `@app`——渲染空、picker 顯示「無可用 app」，不報錯。
11. **ShopifyXR / PaymentButton / loadFeatures stub**：提供 no-op 全域，避免 JS 炸。
12. **三代混存**：同一主題同時有 theme blocks＋local blocks＋liquid templates——引擎不可假設單一世代。
13. **img_url（deprecated）仍需實作**（Ella 6 處）。
14. **編輯器 rename**：section/block 可改名（存 instance `name`）——資料模型補欄位。

## 8. M6 驗收（golden theme 版）

在 CHILL LOVE 匯入 Ella 後，以下全綠才算「完全套用」：

1. 首頁/商品頁/系列頁/購物車/搜尋 SSR 渲染無 Liquid 錯誤（103 filters/9 tags/全 objects 至少 stub）。
2. cart drawer 加購→改量→移除全鏈路走 `/cart/*.js`＋SRA 局部更新。
3. 商品頁：變體切換（SRA `?variant=&section_id=`）、quick add（`?view=quick_add`）、cart 內編輯（`?view=ajax_edit_cart`）、推薦（`/recommendations/products`）、最近瀏覽。
4. 編輯器：左欄樹完整呈現 4 層巢狀；main-product 的 price 拖到 title 上方，儲存後前台生效。
5. 編輯器：product card static block 內拖拽子卡片（media/title/price/button 重排）——**卡片裝修**。
6. 編輯器：Add section picker 49 個可加 section 分類正確、私有 block 不出現在 @theme、白名單容器可加 `_divider` 等。
7. 編輯器事件：選 cart-drawer section 自動開 drawer、選 mega-menu block 自動展開、改 slideshow 設定後輪播重新初始化（unload/load＋script 重跑）。
8. 佈景主題設定：19 分類（翻譯鍵解析）、13 color schemes 編輯、302 settings 全控件可操作。
9. 16 個 demo presets 一鍵換裝（settings_data.presets → current）。
10. 隱藏/顯示、duplicate、undo/redo、儲存後 dirty 清零——與 24 號 §3 六原子操作一致。

—— 以上每條都可寫成 E2E 測試（headless）；第 4/5/7 條是「和 Shopify 完全一樣」的核心體感。

## 9. PoC 實證（已完成——`poc/liquid-engine/`）

驗收第 1 條的雛形已在本 repo 以可跑代碼證明：liquid gem（MIT）＋自實作平台層（content_for/blocks 機制、~70 filters、schema 型別感知 drops、動態來源 resolver），渲染 **Ella 未經修改的原始檔案＋真實實例資料**，0 Liquid errors：

1. announcement-bar（header-group 實例、4 層 blocks 樹、color scheme）；
2. 商品卡 card-product-flex ×4（recommendations 實例子樹；closest.product 逐卡切換；變體感知按鈕；cents→money 劃線價）；
3. main-product 商品詳情頁（⚓×3 靜態卡槽＋9 巢狀卡片：動態來源 H1、hot-stock 庫存條、個人化欄位、quantity/subtotal）。

過程中實測抓到兩個文檔讀不出來的一級坑（ActiveSupport `blank?` 依賴、color 設定物件化），已回寫 25 號坑清單 #14/#15。PoC 即 M2 引擎起點；跑法見 `poc/liquid-engine/README.md`。
