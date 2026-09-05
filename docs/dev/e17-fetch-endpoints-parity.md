# E17 Ella 全部 fetch／Ajax 端點的逐字對表（2026-09-05）

> 規範：鐵律 22（D82／D83）——前台輸出與本尊逐位元組對位；使用者 2026-09-05 裁定「必須完成全部的對齊」⇒ 本包把主題會**動態**打的每個端點
> 都做 HTML／JSON 逐字 diff（E8 工具；`docs/dev/e8-render-parity.md` §2e）。取證＝`docs/dev/external-facts.md` §G25；未取得／範圍外＝
> `docs/specs/91-pit-register.md` §3.86。

## 概述

E8／E12 只對整頁與 E16 的頁首段。Ella 7.2.0 另有 `section-fetcher`（header／header_mobile／cart_drawer／before_you_leave／mega menu）、
recently-viewed（`/search?section_id&type=product&q=id:… OR id:…`）、predictive search（`/search/suggest`＋空態段）、recommendations、product-info
（`?section_id`／`?variant=`）、facets（`?section_id={grid}&sort_by/filter.*`）、cart Ajax（`sections`）、view 模板（`?view=quick_add`／
`ajax_product_card_compare`／`block_wishlist_card`／`ajax_edit_cart`／`cart?view=ajax_side_cart`）與 `/products/{handle}.js|.json`。
本包對 hoko.vip 逐一取回（scratchpad `e17/e17_fetch.py`，53 對）、以 `RenderParity::Report` 批次 diff（`e17_diff.rb`），修掉全部引擎缺口。

## 這是什麼／具體功能（鐵律 12.4 ①②）

| 端點／物件 | 本尊形（§G25） | 我方（本包後） |
|---|---|---|
| `url` 型 setting（`bl_stts.link`） | 值可直接輸出、也回應 `.url`（`href="{{ link.url }}"` ⇒ `#`／外部 URL）；空值 blank | `UrlSettingDrop`（`to_s`／`url`）；空值 nil |
| `{{ localization.country }}` | 字串化＝國名（`icon-flag--台湾`） | `CountryDrop#to_s`＝name |
| `country \| image_url: width: 32` | `//cdn.shopify.com/static/images/flags/tw.svg?width=32`（4:3 SVG） | `//{店主機}/cdn/static/images/flags/tw.svg?width=32`；圖檔＝MIT `flag-icons` 4x3（`AssetsController#flag`） |
| `all_country_option_tags` | option 之間換行、末尾無換行 | `join("\n")`；`---` 後亦換行 |
| `collection.sort_options` / `search.sort_options` 的 `name` | 平台翻譯（zh-CN／zh-TW／en／fr／ja 逐字，§G25） | `config/storefront_locales/{locale}.yml` `_platform.sort_options`／`search_sort_options`；缺鍵 ⇒ 官方英文 |
| 搜尋零結果 | `search.filters == empty`（只出 `<p role="status">`，無 facets） | `SearchDrop#facets` 對空結果集回 nil |
| `q=id:A OR id:B`（type=product） | 只回這些 id；序＝relevance（created_at DESC），與 query 序無關 | `SearchQuery.id_terms` ⇒ `where(id:)`；序不變 |
| 搜尋結果的 `product.url` | `/products/{handle}?_pos={序}&_sid={9 hex}&_ss=r` | `SearchResultsDrop` 對每個商品 drop 傳 `url_params:`；`_sid` 每回應一個 |
| `product.collections` | 含手動系列（compare 表系列欄「首頁」） | `collection_memberships ∪ collection_products` |
| predictive search（zh／ja 買家語言） | 417：section 形 `text/html` `Expectation failed: Unsupported buyer locale`；JSON 形三鍵 | `SearchController::SUPPORTED_LANGUAGES`（官方 44 種）；非清單 ⇒ 417 |
| predictive JSON 商品條目 | 無 compare 價 ⇒ `"0.00"`；無圖 ⇒ `featured_image` 五鍵 null 物件；`\/`／`&` 跳脫 | `product_suggestion_json`＋`Storefront::AjaxJson.dump` |
| `img_url` 對 nil | `//host/cdn/shopifycloud/storefront/assets/no-image-2048-a2addb12_{size}.gif`（非 Liquid error） | `Filters#img_url`（獨立於 `image_url`）；`AssetsController#no_image`（自繪 1×1 灰 gif） |
| `date` 濾鏡時區 | 店時區（`priceValidUntil` 落在 +08:00 的日期） | `registers[:time_zone]`＝`shop.timezone`；`Filters#liquid_time_zone` |
| `/products/{handle}.js` | 商品 JSON（url 在 options 後、無 content、變體 22 鍵、時戳 `+08:00`、預設變體仍出 Title 選項、`\/` 跳脫） | `ProductsController#ajax_js`＋`Storefront::ProductAjaxJson.js_form` |
| `/products/{handle}.json` | REST 形 `{"product":{…}}` | `ProductsController#rest_json` |
| recommendations JSON 商品形 | 官方例 url 在 options 後；本尊對此店回 `[]`（V） | 同 `.js` 形（`drop_json`） |
| cart 售罄 422 訊息 | zh-CN `产品“Acme Tee”已售罄。` | `_platform.cart_errors.sold_out`（zh-Hans）；其他語言未取得 ⇒ 既有文案 |
| 平台功能（不在引擎射程） | 動態結帳按鈕骨架、新版顧客帳戶連結、`__head__` 平台注入、recommendations 演算法 | 91 §3.86 ⚪ |

## 怎樣做出來（鐵律 12.4 ③）

- `ThemeEngine::SettingsDrop#coerce` `when "url"` ⇒ `UrlSettingDrop`；`ThemeEngine::CountryDrop`（`Storefront::LocalizationContext#drop` 包裝
  `country`／`available_countries`）；`Filters#image_url` 對 `CountryDrop` 出國旗 URL；`AssetsController#flag` 從 `node_modules/flag-icons/flags/4x3`
  供檔（MIT，LICENSE 隨套件；`package.json` 釘 `flag-icons@7.5.0`）。
- `ThemeEngine::CountryOptionTags.render` `join("\n")`、`all` 在 `---` 後補換行。
- `Storefront::PlatformStrings` 字典（`config/storefront_locales/{en,zh-Hans,zh-Hant,fr,ja}.yml`）新增 `_platform:` 命名空間：`sort_options`、
  `search_sort_options`、`cart_errors.sold_out`（只有 zh-Hans）；`CollectionDrop#sort_options`／`SearchDrop#sort_options`／`CartWriter#sold_out_message` 讀之。
- `SearchDrop#facets`：`base.exists?` 為假 ⇒ nil；`Storefront::SearchQuery.id_terms`（`/\Aid:\d+(\s+OR\s+id:\d+)*\z/i`）⇒ 四種資源 `where(id:)`；
  `SearchResultsDrop#drops` 傳 `url_params: "?_pos=…&_sid=#{search_sid}&_ss=r"`；`ProductDrop#url` 接 `@url_params`。
- `ProductDrop#collections`：`CollectionMembership` 與 `CollectionProduct` 的 collection_id 聯集（後者＝手動系列真相，`collection_product.rb` 檔頭）。
- `Storefront::SearchController`：`SUPPORTED_LANGUAGES`／`unsupported_locale?` ⇒ 417（section：`render html:` text/html；JSON：三鍵）；
  predictive 條目 `compare_at_price_*` 用 `decimal_string(… || 0)`、`featured_image` 恆物件。
- `Storefront::AjaxJson.dump`＝`ActiveSupport::JSON.encode` ＋ `/` ⇒ `\/`（`&` ⇒ `&` 為 Rails 既有）；用於 products .js／.json、predictive JSON、
  recommendations JSON（cart JSON 未取證，未改）。
- `Storefront::ProductsController`（routes 裸與 `:locale_prefix` 兩形 `products/:handle.js|.json`）；`Storefront::ProductAjaxJson.js_form`（reorder、去 content、
  變體 22 鍵、店時區時戳、預設變體 Title 選項）；REST 形在 controller 內組。
- `ThemeEngine::Filters#img_url`／`#no_image_url`；`#date` 用 `liquid_time_zone`（`Runtime#base_registers` 新 `host`／`time_zone`）。
- `RenderParity::Normalizer`：`TEMPLATE_ID_RE` 容許單底線段、`_sid`／`_psid`、`data-product-card-id`／`data-product-compare-id`／`data-cart-edit-id`／
  `data-compare-item`／`data-section`、`product-edit-*`、`{6 碼}-{id}-{index}`、`{id}A{17}__`、`template--T__…-{id}"`、國旗 CDN 主機。

## 跨功能／跨頁／前端影響（鐵律 12.4 ④）

- 全部 `{% form 'localization' %}`／`country_option_tags` 的輸出多出換行（HTML 語義不變，位元組對位）。
- 搜尋結果頁與 recently-viewed／predictive 的商品連結帶歸因參數；`_sid` 隨機 ⇒ 頁快取的搜尋頁本就 no-store（`/search` 不進頁快取），
  recently-viewed 走 `/search?section_id`（no-store）。
- 中文／日文買家的預測搜尋改回 417（與本尊一致）：Ella 的 predictive-search.js 對非 2xx 回應 `throw` ⇒ 搜尋抽屜不出建議（本尊同形）。
- `product.collections` 對手動系列不再為空 ⇒ 任何依它的主題邏輯（麵包屑、compare、相關系列）行為改變。
- 新路由：`/products/:handle.js|.json`、`/cdn/static/images/flags/:cc.svg`、`/cdn/shopifycloud/storefront/assets/no-image-*.gif`（皆租戶 host 內、catch-all 之前）。
- 新依賴：`flag-icons@7.5.0`（MIT）。
- Mirror／bt3：部署後須重跑對表（`e17_fetch.py` 對 `mirror.chilling.com.hk` ＋ `e17_diff.rb`）；`drops.rb` 不在 dev autoload ⇒ 本機 dev server 改後必重啟。

## 測試

`spec/liquid/e17_fetch_parity_spec.rb` U1–U11；`spec/requests/storefront_fetch_parity_spec.rb` F1–F9；既有更新：`drops_spec` J1／J2 不動（Liquid json
形），`storefront_display_wiring_spec` W4 系列（換行）、`render_parity_pages_spec` PP12（店時區）、`storefront_i18n_spec` SF-9／SF-9b（417）、
`localization_context_spec` LC1／LC5（CountryDrop）。突變見 worklog。

## 對表結果（本機 dev server vs hoko.vip 快照；bt3 部署後複驗見 worklog）

| 端點 | 整份相似度 | 最差段 | differ | 備註 |
|---|---|---|---|---|
| `sf_home_header_mobile` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_cart_drawer` | 0.998 | 0.998 | 1 | 1 differ＝新版顧客帳戶登入連結（⚪ 91 §3.83） |
| `sf_home_before_you_leave` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_multitasking` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_promotion` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_toolbar_mobile` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_announcement` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_color_swatches` | 1.000 | 1.000 | 0 | 全同 |
| `sf_home_footer` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_header_mobile` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_cart_drawer` | 0.998 | 0.998 | 1 | 同上 |
| `sf_product_before_you_leave` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_multitasking` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_promotion` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_toolbar_mobile` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_announcement` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_color_swatches` | 1.000 | 1.000 | 0 | 全同 |
| `sf_product_footer` | 1.000 | 1.000 | 0 | 全同 |
| `rv_drawer_empty` | 1.000 | 1.000 | 0 | 全同 |
| `rv_drawer_items` | 1.000 | 1.000 | 0 | 全同 |
| `rv_product_items` | 1.000 | 1.000 | 0 | 全同 |
| `rv_product_empty` | 1.000 | 1.000 | 0 | 全同 |
| `rv_collection_items` | 1.000 | 1.000 | 0 | 全同 |
| `ps_tee` | 1.000 | - | 0 | 全同 |
| `ps_none` | 1.000 | - | 0 | 全同 |
| `ps_mug` | 1.000 | - | 0 | 全同 |
| `ps_empty_state_home` | 1.000 | 1.000 | 0 | 全同 |
| `ps_empty_state_product` | 1.000 | 1.000 | 0 | 全同 |
| `recs_acme` | 1.000 | 1.000 | 0 | 全同 |
| `recs_mug` | 1.000 | 1.000 | 0 | 全同 |
| `pi_main` | 0.990 | 0.990 | 6 | 6 differ 全為 `payment_button` 骨架（⚪ §3.86） |
| `pi_main_variant` | 0.990 | 0.990 | 6 | 同上 |
| `pi_tabs` | 1.000 | 1.000 | 0 | 全同 |
| `pi_mug_main` | 0.990 | 0.990 | 6 | 同上 |
| `facets_sort` | 1.000 | 1.000 | 0 | 全同 |
| `facets_avail` | 1.000 | 1.000 | 0 | 全同 |
| `facets_price` | 1.000 | 1.000 | 0 | 全同 |
| `facets_frontpage` | 1.000 | 1.000 | 0 | 全同 |
| `facets_breadcrumb` | 1.000 | 1.000 | 0 | 全同 |
| `search_tee_section` | 1.000 | 1.000 | 0 | 全同 |
| `search_tee_sorted` | 1.000 | 1.000 | 0 | 全同 |
| `search_none_section` | 1.000 | 1.000 | 0 | 全同 |
| `view_quick_add` | 0.933 | 0.925 | 10 | `__head__` 平台注入＋登入連結＋付款鈕（⚪）；其餘段全同 |
| `view_compare` | 1.000 | - | 0 | 全同 |
| `view_wishlist` | 0.934 | 0.925 | 10 | 同上 |
| `view_edit_cart` | 1.000 | - | 0 | 全同 |
| `view_side_cart` | 0.986 | - | 1 | 1 differ＝登入連結（⚪） |
| `page_bolt_mug` | 0.923 | 0.922 | 16 | 同上（整頁基線同 e12） |
| `page_cosy_lamp` | 0.922 | 0.922 | 16 | 同上 |

cart Ajax 九對（`cart_add`…`cart_clear`）：hoko 側為售罄 422／Cloudflare 挑戰頁，無可比對回應（91 §3.86 V，下一包）。


## 已知限制與 TODO

見 `docs/specs/91-pit-register.md` §3.86。

## 變更記錄

- 2026-09-05 E17 首版（本檔）。
