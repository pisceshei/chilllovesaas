# 96 — 前台 G2 parity 面 teardown（/collections·/search·predictive·recommendations·?view=）

> 步 12 的三源取證檔（2026-09-01）：①官方文檔深潛（shopify.dev `.md` 原文鏡像，逐字）
> ②本尊真店親點（chill.deals，Ella 7.2.0 已發布主題；買家面公開頁）③live payload
> 抓包。實作對照＝`docs/dev/g6-storefront-g2.md`（隨步 12 PR 落地）。
> 相鄰正典：`25` §5（HTTP 相容面總表）、`83`（Section Rendering 真店契約）、
> `94` §（admin 系列面）。

## §1 /collections 集合列表頁

### 1.1 官方契約（取證 2026-09-01）

- 模板（https://shopify.dev/docs/storefronts/themes/architecture/templates/list-collections ）：
  "The `list-collections` template renders the collection list page, which lists all the
  store's collections. This page is located at the `/collections` URL of the store."
  檔案＝`templates/list-collections.json`。
- 內容："You can access the Liquid `collections` object to display the store's collections."
  預設輸出＝字母序（"outputs the collections in alphabetical order"）；自訂順序官方做法＝
  menu 迭代（"you can build a menu to host the collections in your desired order"）。
- 圖片 fallback："You should have a fallback for the case that a collection doesn't have a
  collection image. For example, you might use the image of the first product within the
  collection"（⇒ `collection.products.first.image`——列表頁**需要** products 出口）。
- `collections` 物件（https://shopify.dev/docs/api/liquid/objects/collections ）：
  "All of the collections on a store."；Global；可迭代、可 `collections['handle']` 取單個。
  🔴 `size` 屬性官方頁**未記載**（未取得）；但 Ella `main-list-collections.liquid:9`
  實測消費 `collections.size` ⇒ 我方必須提供（登記為 Ella 消費形）。
- paginate（https://shopify.dev/docs/api/liquid/tags/paginate ）："for loops are limited to
  50 iterations per page"；可分頁陣列名單**明列 `collections`**；page_size＝"between 1 and
  250"；深度＝"paginate to the 25,000th item in the array and no further"。

### 1.2 真店親點（chill.deals /collections，2026-09-01）

- 頁形＝breadcrumb（Home / Collections）＋標題 COLLECTIONS＋卡片 grid（圖＋名＋
  「1 product」計數）。頁 title＝`Collections – CHILL LOVE`。
- 🔴 **發布過濾實證**：測試店三系列中 OS 未發布的 `S9-Col-Hidden` 不出現在
  /collections（只列 HOME PAGE／S9-COL-TEST）⇒ 清單射程＝OS 管道已發布集。

## §2 /collections/all 虛擬全商品系列

- 真店親點（2026-09-01）：店內**無** handle=all 的手動系列，`/collections/all` 仍 200，
  title＝`Products – CHILL LOVE`、breadcrumb＝Home / Collections / Products、
  計數 13494 products、預設排序顯示 ALPHABETICALLY, A-Z。
- 排序 select 值域（DOM 抓取，逐字 value）：`manual`／`most-relevant`／`best-selling`／
  `title-ascending`／`title-descending`／`price-ascending`／`price-descending`／
  `created-ascending`／`created-descending`（9 值；`most-relevant` 為 2026 現值，
  搭配 filter 後的相關性排序）。
- `collection.all_products_count` vs `products_count`（https://shopify.dev/docs/api/liquid/objects/collection ）：
  前者＝"The total number of products in a collection. This includes products that have
  been filtered out of the current view."；後者＝"in the current view"。
  `collection.products` Tip＝"up to a limit of 50"（每頁上限 50——與 paginate 通用上限
  250 是兩個不同數字）。

## §3 /search 搜尋頁

### 3.1 官方契約（取證 2026-09-01）

- 模板（…/templates/search ）：表單 `action="{{ routes.search_url }}"`＋`name="q"`；
  結果＝迭代 `search.results`；高亮＝`highlight` filter（包 `<strong class="highlight">`）。
- `search` 物件（https://shopify.dev/docs/api/liquid/objects/search ）：
  `default_sort_by`＝"is `relevance`"；`performed`（boolean）；`results`（item 可為
  article/page/product，多帶 `object_type`）；`results_count`；`sort_by`（URL 參數決定）；
  `sort_options`；`terms`；`types`（"determined by the `type` query parameter"）；
  `filters`——🔴 "If the search results contain more than 1000 products, then the array
  will be empty."
- URL 參數（https://shopify.dev/docs/storefronts/themes/navigation-search/search ）：
  `q`（必填）／`type`（CSV：product,page,article，預設全部）／`page`（預設 1）／
  `options[unavailable_products]`（show|hide|last，預設 last）／`options[prefix]`
  （last|none，預設 last＝末詞部分比對）／`sort_by`（relevance|price-ascending|
  price-descending，預設 relevance）。表單紀律："Aside from the `q` parameter, none of
  the query parameters require user input, so they should be hidden inputs."
- 🔴 **官方文檔筆誤（live 定奪）**：官方原文把 price-ascending 寫成 "from high to low"
  （與 key 名相反）。真店實測 `?sort_by=price-ascending` ⇒ Sort 下拉顯示
  "Price, low to high" 且結果 $183.50→$488 遞增 ⇒ **語義照 key 名，不照官方那句散文**。

### 3.2 真店親點（chill.deals /search?q=IPSA，2026-09-01）

- 頁形＝大標 SEARCH RESULTS＋置中搜尋框（清除鈕＋放大鏡）＋"17 results found for
  “IPSA”"＋工具列（View as 六種格局／Items per page 16／Sort by）。
- 搜尋頁 sort select 值域（DOM 抓取）＝恰 3 值：`relevance`／`price-ascending`
  （Price, low to high）／`price-descending`（Price, high to low）。
- 分頁＝每頁 16（Ella items-per-page 預設）＋「Showing 1-16 of 17 products」＋SHOW MORE。
- Ella `main-search.liquid` 消費面（fixture 實讀）：`search.sort_by|default_sort_by|terms|
  performed|results_count|filters（與 empty 比較）|results（paginate by N＋item.object_type）`。

## §4 Predictive Search（雙形）

### 4.1 官方 `.json` 契約（https://shopify.dev/docs/api/ajax/reference/predictive-search ，2026-09-01）

- `GET /{locale}/search/suggest.json?q=…`；參數：
  `resources[type]`（CSV：product/page/article/collection/query；**預設
  `query,product,collection,page`——不含 article**）；`resources[limit]`（1–10，預設 10）；
  `resources[limit_scope]`（all|each，預設 all）；`resources[options][unavailable_products]`
  （show|hide|last，預設 last，僅對 product）；`resources[options][fields]`
  （值域 author/body/product_type/tag/title/variants.barcode/variants.sku/variants.title/
  vendor；預設 "title, product_type, variants.title, and vendor"）。
- 每型上限："The API returns no more than 10 predictive suggestions per request type."
- Typo tolerance＝1（前 4 字母須正確）；`seo.hidden` metafield 商品不出現；
  query suggestions 僅英文。
- 錯誤：422＝參數非法；417＝unsupported buyer locale；429＝throttled（帶 Retry-After）。

### 4.2 live payload（chill.deals suggest.json?q=IPSA，2026-09-01）

- 回應形＝`{"resources":{"results":{"products":[…],"collections":[],"pages":[],"articles":[]}}}`
  ——請求列了 4 型就回 4 鍵，無命中＝空陣列。
- product 條目恰 16 鍵（逐字鍵名）：`available/body/compare_at_price_max/
  compare_at_price_min/handle/id/image/price/price_max/price_min/tags/title/type/url/
  variants/vendor`＋`featured_image{alt,aspect_ratio,height,url,width}`。
- 🔴 金額＝**十進位字串**（`"price":"365.00"`）——與 recommendations 的整數分尺度
  不同（鐵律 3：兩個序列化出口分開處理，同 58 §G.3 物流商形）。
- 🔴 `url` 帶歸因參數：`?_pos=1&_psq=IPSA&_psid=95e5a6cac&_ss=e`（位置／query／
  session 歸因——分析漏斗用）。
- `body`＝完整 HTML（多語店官方 caution 不要輸出）。

### 4.3 section 形（Ella 實際用的那一形）

- 真店親點：header 放大鏡→輸入 IPSA，theme JS 實際請求（network 面板抓包）＝
  `GET /search/suggest?q=IPSA&resources[limit_scope]=each&section_id=predictive-search`
  （**HTML 版，不是 .json**）⇒ 200。UI＝Suggestions 查詢 chips（query 型建議，命中詞
  黃底高亮）＋Products 卡列（vendor＋title＋劃線原價＋紅色售價）＋底部
  「Search for "IPSA" →」。
- 官方（同 4.1 參考頁）：section 版參數同 .json 另加 `section_id`；"The section response
  contains the HTML of the provided section rendered with the `predictive_search` object"。
  🔴 `section_id` 只存在於 HTML 版端點。

## §5 Product Recommendations（雙形）

- 官方（https://shopify.dev/docs/api/ajax/reference/product-recommendations ，2026-09-01）：
  `GET /{locale}/recommendations/products.json?product_id=…&limit=…&intent=…`；
  `limit` 1–10 預設 10；`intent`＝related|complementary，預設 related。
  錯誤：缺 product_id⇒422；intent 非法⇒422；product 不存在或未發布 OS⇒404。
- intent 語義（…/product-merchandising/recommendations ）：related＝"You might also
  like"；complementary＝"Pair it with"；🔴 "Only related recommendations are
  auto-generated by Shopify. Complementary recommendations need to be manually set up."
  （Search & Discovery app 配置）。
- live（chill.deals，product_id=9813105639659，2026-09-01）：兩個 intent 皆回
  `{"products":[],"intent":"related"}`／`{"products":[],"intent":"complementary"}`
  ——**空陣列＋intent 回聲**＝未配置／未生成時的真實形（不是 404）。
- product 條目（官方參考頁）＝Ajax product 全形，`price: 380000`＝**整數分**；
  `url` 帶 `pr_choice/pr_prod_strat/pr_rec_pid/pr_ref_pid/pr_seq` 歸因參數。
- section 版：`GET /{locale}/recommendations/products?section_id=…`（渲染
  `recommendations` 物件；同 4.3 的 section 契約）。

## §6 `?view=` 替代模板

- 官方（…/architecture/templates/alternate-templates ，2026-09-01）：命名
  `template-name.template-suffix.{json|liquid}`；渲染＝"?view=[template-suffix]"；
  "You can't replace the default template with an alternate template."；
  另有 contextual templates（`index.context.<string>.json`，market/b2b）——不同機制。
- Ella fixture 現貨替代模板：`collection.collection-banner-adv.json`／
  `collection.collection-full-width.json` 等（`?view=collection-banner-adv` 即切換）。
- 真店親點（2026-09-01）：`?view=collection-full-width` ⇒ 渲染替代模板（版面確實
  切換：JUMP TO 選單＋每頁 8）；🔴 `?view=zzz-nonexistent`（不存在的 suffix）⇒
  **靜默 fallback 到預設模板、HTTP 200**（不是 404）——fallback 行為有真店實證。

## §7 `all_products` 物件

- 官方（https://shopify.dev/docs/api/liquid/objects/all_products ，2026-09-01，完整句）：
  "The `all_products` object has a limit of 20 unique handles per page. If you want more
  than 20 products, then consider using a collection instead."（20 個**唯一 handle**／頁）；
  未命中＝"If the product isn't found, then `empty` is returned."

## §8 未取得清單（19.3）

1. `collections.size` 官方屬性頁未記載（Ella 消費 ⇒ 我方提供，ours 登記）。
2. `list-collections` 模板頁對分頁的直接規定（僅由 paginate 名單間接證實）。
3. 儲存級 filter 參數（`filter.p.*`）完整值域——Storefront filtering 另頁，隨 filter 包。
4. /search 整頁搜尋的欄位集（title/body/vendor/tags/SKU？）官方頁未逐字列——僅
   predictive 有 fields 預設集；我方整頁搜尋欄位集＝ours（dev doc 登記）。
5. query 型建議（Suggestions chips）的生成算法（官方僅英文、內部 ML）——我方 v1
   不生成 query 建議（空陣列＝合法形，登記）。
