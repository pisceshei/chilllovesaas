# E19 `content_for_header` 完整本尊形——節點序列、頁型變體、資料節點、平台 stub 資產、compiled assets、oEmbed／Atom

> 路線圖 T10（`docs/plans/2026-09-05-全對齊路線圖.md` §2）。取證全文＝`docs/dev/external-facts.md` §G27（hoko.vip 74 頁快照＋CDN，2026-09-05）；
> 未取得／範圍外＝`docs/specs/91-pit-register.md` §3.88。worklog／handoff＝`docs/worklog/2026-09-05-content_for_header本尊形E19.md`、
> `docs/handoff/2026-09-05-content_for_header本尊形E19.md`。鐵律 9：本包所有平台 JS 本體皆我方自寫，只有節點序、tag／id／class／屬性名、
> 資料形與全域 API 名同本尊。E19a＝本檔（結構＋資料＋stub）；E19b＝行為對位（顧客隱私同意 API、驗證碼、web pixels、分析收集端）。

## 1. 這是什麼（本尊行為）

官方（objects/content_for_header）："dynamically returns all scripts required by Shopify"、須在 `<head>` 內、"shouldn't try to modify or parse the
content_for_header object because the contents are subject to change"。Ella `layout/theme.liquid` 在 `{{ content_for_header }}` 之後直接 `</head>`，
所以 hoko 的 head 從主題 `window.routes` script 之後到 `</head>` 全部是平台輸出——商品頁 38 節點＋尾段 10 節點；非商品頁 31–33；404 頁 25。

| 段 | 節點（本尊序） | 頁型變體 |
|---|---|---|
| 開頭 | perf mark start → `meta#shopify-digital-wallet` | 全頁 |
| 資源連結 | `link[rel=alternate type=atom+xml]`（自閉合）→ `link[rel=prev]` → hreflang（**x-default 首**）→ `link[rel=alternate type=json+oembed]` | atom：集合／部落格；prev：第 2 頁；hreflang：404／UNLISTED 無；oembed：商品 |
| 平台設定 | `preloads.js?locale={語言主碼}-{買家國碼}&default_configuration_id=` → `script#shopify-features` → `Shopify.*` 全域 → modules 旗標 → loadFeatures 佇列 stub → SignInWithShop 設定 → `script#shop-js-analytics` → shop-js loader＋import＋featureAssets → `script#__st` → PayPal 旗標 → `script#captcha-bootstrap` → load_feature → UA 偵測 → `script#shopify-origin-trials` → `Shopify.MCP` → webmcp adapter | 資料值隨頁（§2） |
| 動態結帳 | `dynamic.init` → `buyer_consent` → **模組形**（cleanup → module → nomodule）／**cart.bootstrap 形** → `script#scb4127`（privacy banner）→ [`link#shopify-accelerated-checkout-styles` → `style#shopify-accelerated-checkout-cart`] | 模組形＝本頁渲染了 `payment_button`（E18） |
| 編譯資產 | `script#sections-script[data-sections]` → `script#snippets-script[data-snippets]` | 只在本頁渲染到帶 `{% javascript %}` 的檔時 |
| 尾段 | `script#shopify-cfh-end` → `link[rel=dns-prefetch]` → 棄站 beacon → `__TREKKIE_SHIM_QUEUE` → web pixels loader → `ShopifyAnalytics.meta` → `script.analytics`（trekkie）→ perf-kit → `meta[shopify-y]` → `meta[shopify-s]` → `meta[new-cookie-storage-activated]` | 全頁 |

## 2. 具體功能與值域

- **hreflang**：`Seo::HreflangMatrix.entries` 依店語言序，x-default 移到首；href＝絕對路徑＋保留 `page`／`q`／`type` 的 query（`&` 出 `&amp;`；`sort_by` 不進）。
- **`shopify-features`**：`{"accessToken":{Storefront::AccessToken},"betas":["rich-media-storefront-analytics"],"domain":{host},"predictiveSearch":false,"shopId":{id},"locale":{本尊碼小寫}}`。
- **`Shopify.*` 全域**（`ThemeEngine::ShopifyGlobal`，本尊逐字）：shop／locale／currency／country／theme／theme.handle／theme.style／cdnHost（`host/cdn`）／routes.root／
  shopJsCdnBaseUrl／SignInWithShop.User.recognized；編輯器加 `designMode = true`。🔴 不再出 formatMoney／postLink／CountryProvinceSelector／bind／…（Ella global.js 自定義；
  本尊 script 沒有）。
- **`__st`**：`{"a":shop_id,"offset":店時區秒,"reqid":"{uuid}-{epoch}","pageurl":"host/path?query",["s":"pages-{id}"|"blogs-{id}",]"u":"{12hex}",["p":home|product|collection|collections|cart|searchresults|page|blog,]["rtyp":product|page|blog,"rid":id]}`
  （collection 無 rtyp／rid；404／policy 無 p）。
- **`shop-js-analytics`／perf-kit `data-page-type`**＝Liquid `request.page_type` 詞彙。
- **`ShopifyAnalytics.meta`**：`currency`；商品頁 `product{id,gid,vendor,type,handle,variants[{id,price(cents),name,public_title,sku}],remote:false}`；集合／搜尋 `products[…]`
  （上限 limits `content_for_header.analytics_listed_products_cap`）；`page{pageType,resourceType,resourceId,requestId}`；404 只有 requestId。
- **trekkie**：config（shopId／themeId／themeCityHash／contentLanguage／currency／eventMetadataId／enabledBetaFlags／S2S.apiClientId）；`track`：商品頁
  `Viewed Product{currency,variantId,productId,productGid,name,price:"188.00",sku,brand,variant,category,nonInteraction,remote,available}`、集合頁
  `Viewed Product Category{currency,category:"Collection: {handle}",collectionName,nonInteraction}`、搜尋頁 `Performed Search{query}`；`lib.page(null,{pageType,resourceType,resourceId,requestId,shopifyEmitted})`。
- **web pixels**：`Shopify.analytics.publish／subscribe／visitor` 介面＋本頁標準事件 `page_viewed`／`product_viewed`／`collection_viewed`／`search_submitted`（payload 形同本尊）。
- **每請求值**（`Storefront::RequestValues`）：頁快取存 placeholder（`__CL_REQID__`／`__CL_U__`／`__CL_Y__`／`__CL_Y_EXP__`／`__CL_S__`／`__CL_S_EXP__`／`__CL_EVMETA__`），
  controller 送出前代入；cookie `_shopify_y`（1 年）／`_shopify_s`（30 分鐘）SameSite=Lax、**host-only**（不設 domain：共用主網域跨店坑）；meta 與 cookie 同值。
- **平台 stub 資產**（`Storefront::PlatformAssets`，`app/assets/storefront/platform/*.js`）：檔名雜湊＝我方本體 SHA-256 前 8 hex（trekkie＝SHA-1 40 hex）、`integrity`＝我方 SRI；
  路徑形照本尊（`/cdn/shopifycloud/storefront/assets/storefront/load_feature-{h}.js`…）；雜湊不符 404。載入器 `load_feature.js` 給 shopify-xr／model-viewer-ui／
  video-ui／consent-tracking-api 最小實作，其餘 `callback(null)`。
- **編譯資產**（`Storefront::CompiledAssets`）：`/cdn/shop/t/{theme_id}/compiled_assets/scripts.js|snippet-scripts.js?v={摘要}{theme.updated_at}`（T12 起 29 位本尊形；E19a 原只出 10 位時間戳）；本尊格式（IIFE、`__sections__`／`__snippets__`
  門控、`Shopify.designMode` 全開、try/catch）；block JS 併入 section 門控（依 schema `blocks` 遞迴，`@theme`＝全部公開 block）。`data-sections`／`data-snippets` 只列本頁
  渲染到的檔（`SectionAssetTag` 記錄：snippet 由 `context.template_name`，section 由 `registers[:section_drop].type`）。
- **端點**：`/products/{handle}.oembed`（抓包形逐鍵；`price` 數值；`\/` 跳脫）、`/collections/{handle}.atom`／`/blogs/{handle}.atom`（本尊 XML 形；summary 表格標籤五語言
  `_platform.atom.*`）、`/sf_private_access_tokens` 401、`POST /api/collect` 200、`/{shop_id}/digital_wallets/dialog` 200（我方最小頁）、`/checkouts/internal/preloads.js` 200。

## 3. 怎樣做出來（實作落點）

| 檔 | 內容 |
|---|---|
| `app/services/storefront/content_for_header.rb` | 建構器（`Lazy` drop 延遲到 layout 渲染；節點方法逐一對應本尊節點） |
| `app/liquid/theme_engine/page_renderer.rb` | `content_for_header` 改 assign `Lazy`；移除 `</head>` 前的 ShopifyGlobal 插入與 `Seo::HeadTags`（已刪） |
| `app/liquid/theme_engine/runtime.rb`／`tags.rb`／`filters.rb`／`drops.rb` | `payment_button_rendered!`、`record_asset_file`、`SectionAssetTag#record_file`、`SectionDrop#type` |
| `app/liquid/theme_engine/shopify_global.rb` | 本尊逐字形 |
| `app/services/storefront/dynamic_checkout_head.rb` | `build(variant: :module|:cart_bootstrap)`＋`styles` |
| `app/services/storefront/{platform_assets,compiled_assets,request_values}.rb` | stub 登記／編譯／每請求值 |
| `app/assets/storefront/platform/*.js`（10 檔） | 我方自寫本體 |
| `app/controllers/storefront/platform_assets_controller.rb`／`feeds_controller.rb` | 端點 |
| `app/controllers/storefront/pages_controller.rb`／`admin/storefront_preview_controller.rb` | `RequestValues.substitute` |
| `app/services/render_parity/normalizer.rb` | 平台 CDN（`cdn.shopify.com/` ⇒ `/cdn/`）、雜湊／SRI／每請求值／身分值、自寫本體替身；收尾 PR：`compiled_assets` 路徑主題 id ⇒ `ID`（RP8，bt3 mirror 主題 7 vs hoko 2） |
| `config/routes.rb`、`config/limits.yml`（`content_for_header.*`）、`config/storefront_locales/*.yml`（`_platform.atom`） | |
| `spec/requests/storefront_content_for_header_spec.rb`（C1–C9）、fixture `product.e19.json`／`js-probe`／`js-snippet`／`_js-block`、`storefront_seo_spec.rb`（SEO1／3／8 改）、`mirror_spec.rb`（MR4 序） | |

🔴 **平台不注 canonical／JSON-LD**：包 35 的 `Seo::HeadTags` 退場（主題自出 `canonical_url`／schema snippet；fixture layout 補上 canonical）。

## 4. 跨功能／跨頁／前端影響

- 主題 JS：`Shopify.loadFeatures`／`PaymentButton`／`captcha`／`analytics` 全域改由平台節點定義；Ella 自定義的 formatMoney 等不受影響。其他主題若依賴
  `shopify_common.js` 的 `Shopify.bind` 等，走 `shopify_asset_url`（T8／T9 對表項）。
- 頁快取：placeholder 進快取、送出前代入 ⇒ 每次回應都有新 reqid／u，`_shopify_y` 跨請求穩定。
- render parity：`__head__` 段自此可對表（Normalizer 規則）；`(missing)`／多餘節點＝引擎缺口。
- SEO：hreflang 序與 query 規則改為本尊形；平台 JSON-LD 退場（主題責任）。
- 分析：所有 beacon 指向 `/api/collect`（200 不落庫）——E19b／分析包接手。

## 5. 驗證

rspec：`spec/requests/storefront_content_for_header_spec.rb` C1–C9 綠；受影響回歸（SEO1／3／4／8、i18n SF-1／SF-2／SF-10、JS2、SG1、RF8／RF15、MR4、dynamic checkout H1–H6、page_renderer）綠；閘門表見 worklog。

本機 `__head__` 逐節點對表（dev server `mirror.lvh.me:3000` mirror 店 vs hoko.vip 快照 2026-09-05；`Rails.cache.clear` 後；scratchpad `t10/head_diff.rb`＝
兩邊 content_for_header 段經 `RenderParity::Normalizer` 後逐節點比 tag／屬性／本體）：

| 頁 | hoko 節點 | 我方節點 | 相同 |
|---|---|---|---|
| `/products/acme-tee` | 48 | 48 | 48/48 |
| `/zh-hant/products/acme-tee` | 48 | 48 | 48/48 |
| `/collections/all` | 42 | 42 | 42/42（analytics products 序＝acme-tee／bolt-mug／cosy-lamp） |
| `/collections/all?page=2` | 43 | 43 | 43/43（`rel="prev"`；products 空） |
| `/collections/all?sort_by=price-ascending` | 42 | 42 | 42/42（products 序＝bolt-mug／acme-tee／cosy-lamp；hreflang 無 sort_by） |
| `/collections` | 41 | 41 | 41/41 |
| `/` | 41 | 41 | 41/41（hreflang 根形 `/zh-hant` 無尾斜線） |
| `/cart` | 41 | 41 | 41/41 |
| `/search?q=tee` | 41 | 41 | 41/41 |
| `/pages/contact` | 41 | 41 | 41/41 |
| `/products/nope`（404） | 35 | 35 | 35/35（`__st.pageurl`＝`host/404`） |

判讀：節點序、tag／屬性、資料節點（身分值抹後）與本尊逐一相同；我方自寫本體的內嵌 script 以 `[platform]` 替身比對（鐵律 9）。
未列頁型（article／policy／password／gift_card／customers）＝91 §3.88 V。

bt3 複驗（收尾 PR；main `38debcbe` 部署，`scratchpad/t10/bt3_deploy_e19.sh`＋`verify_bt3_e19.sh`；公開 `https://mirror.chilling.com.hk` 抓頁 → `head_diff.rb` 對 hoko 快照）：

| 頁 | hoko 節點 | mirror 節點 | 相同 |
|---|---|---|---|
| `/products/acme-tee` | 48 | 48 | 首跑 46/48 → Normalizer 補 RP8 後 48/48 |
| `/zh-hant/products/acme-tee` | 48 | 48 | 首跑 46/48 → 48/48 |
| `/collections/all`／`?page=2`／`?sort_by=price-ascending` | 42／43／42 | 同 | 全同 |
| `/collections`、`/`、`/cart`、`/search?q=tee`、`/pages/contact` | 41 | 41 | 全同 |
| `/products/nope`（404） | 35 | 35 | 35/35 |

首跑兩節點差＝`sections-script`／`snippets-script` 的 `src` 主題 id（hoko `/cdn/shop/t/2/`、mirror `/cdn/shop/t/7/`）：本機 mirror 店主題 id 恰為 2 才碰巧全同；主題 id 是身分值（同 shop id／theme-instance-id），
Normalizer 補 `compiled_assets` 路徑主題 id ⇒ `ID`（RP8）後重跑全同。端點（公開 mirror）：load_feature／trekkie／compiled scripts／oembed／atom／digital_wallets dialog 200、
`sf_private_access_tokens` 401、`POST /api/collect` 200；headless post-JS（`computed-parity.mjs evaljs`，等 6 秒）：`Shopify.loadFeatures`／`analytics.publish`／`captcha.protect` 為 function、
`PaymentButton` object、`window.trekkie` object、`__st` 在、`#global-shopify-accelerated-checkout-styles` 在、頁面錯誤 0。
