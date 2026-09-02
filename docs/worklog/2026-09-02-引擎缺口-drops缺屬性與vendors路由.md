# 2026-09-02 引擎缺口 PR-4：Collection／Blog／Page／Article／Product drops 缺屬性＋`/collections/vendors|types`

分支 `engine/drops-gap-4`（自 PR-3 分支長出，PR-3 合併後 rebase 到 main）。配對 handoff：
`docs/handoff/2026-09-02-引擎缺口-drops缺屬性與vendors路由.md`。收口 D78 triage 已驗證項
`CollectionDrop.all_tags／featured_image／metafields`、`BlogDrop.next_article／previous_article`、
`PageDrop.metafields`、`ProductDrop.created_at`，與 gap-triage-m59 的 `sort_options／current_vendor／current_type`。

## 已完成的工作 (Done)
- `CollectionDrop`（objects/collection 逐字，取證 2026-09-02）：`sort_options`（官方輸出例九項 name／value）、
  `all_tags`（上限 1000）／`tags`（濾後檢視）／`all_types`／`all_vendors`、`current_vendor`／`current_type`
  （只有虛擬 vendor／type 系列有值）、`featured_image`（系列圖 → 第一個商品的 featured_image → nil）、
  `image`（我方無圖欄 ⇒ nil，宣告不計 miss）、`metafields`（MetafieldsRootDrop）。
- `/collections/vendors?q=`／`/collections/types?q=`（PageRenderer）：虛擬系列 title＝q、`VirtualAllCollection`
  加 vendor／product_type 成員、`CollectionProductsDrop.base_relation` 依之過濾；商家自建同 handle 真系列優先。
- `BlogDrop.next_article`（較舊）／`previous_article`（較新）以文章頁的 `current_article` 為錨（PageRenderer 文章
  分支傳入），端點與非文章頁回 nil；`BlogDrop.metafields`。
- `ArticleDrop.image`（無圖欄 ⇒ nil 宣告）、`ArticleDrop.metafields`、`PageDrop.metafields`（原 `{}` ⇒ 真根）、
  `ProductDrop.created_at`。
- filters：新增 `url_for_type`；`url_for_vendor`／`link_to_vendor`／`link_to_type` 改 percent-encoding
  （官方例逐字 `/collections/vendors?q=Polina%27s%20Potent%20Potions`，原 CGI.escape 出 `+`）。
- spec `spec/requests/storefront_drops_gap_spec.rb` G1–G5；fixture `minimal-1.0/sections/main-article.liquid`
  加 `anext`／`aprev` 兩個 span。突變輪：M1 拔 vendor 過濾 ⇒ G1＋G2 紅；M2 next 方向反 ⇒ G3 紅；
  M3 拔 sort_options 一項 ⇒ G2 紅；M4 拔 featured_image 退回 ⇒ G2 紅；M5 改回 CGI.escape ⇒ G5 紅。
- 回歸：`bundle exec rspec spec/requests/storefront_drops_gap_spec.rb spec/requests/storefront_blog_spec.rb
  spec/requests/storefront_collections_spec.rb spec/liquid/theme_conformance_spec.rb` 綠。

## 修改的檔案與核心邏輯 (Changes)
- `app/liquid/theme_engine/drops.rb`：`ProductDrop#created_at`；`CollectionDrop` 新增 `image／featured_image／
  all_tags／tags／all_types／all_vendors／current_vendor／current_type／sort_options／metafields`＋三個
  private relation helper；`VirtualAllCollection` 兩個新成員；`CollectionProductsDrop.base_relation` 的
  vendor／type 過濾；`BlogDrop` 新 `current_article:`＋`next_article／previous_article／metafields`＋
  `neighbour_article`；`ArticleDrop#image／metafields`；`PageDrop#metafields`。
- `app/liquid/theme_engine/page_renderer.rb`：`/collections/vendors|types` 分支；文章分支傳 `current_article`。
- `app/liquid/theme_engine/filters.rb`：`url_for_type`；vendor／type 連結（`url_for_vendor`／`link_to_vendor`／
  `url_for_type`／`link_to_type`）改 `ERB::Util.url_encode`。
- `spec/requests/storefront_drops_gap_spec.rb`：新檔；`spec/fixtures/theme_engine/minimal-1.0/sections/main-article.liquid`：加兩個 span。

## 尚未完成或需注意的風險 (Pending / TODO)
- `/collections/vendors`／`types` 無 `q` 時的官方形＝未取得，先照 /collections/all（全商品、title Products）並登記。
- `sort_options` 的 name 官方註明可由語言編輯器改；我方先用官方英文名，語言表隨多語言線接 storefront 字串。
- `collection.image`／`article.image` 為 nil 宣告——collections／articles 表無圖欄（schema 可複驗），圖欄隨系列線／
  內容線補；`collection.featured_image` 現只會走「第一個商品的圖」分支。
- `blog.next_article／previous_article` 只在文章頁有錨；blog 列表頁（無錨）回 nil，官方對此情境未述。
- `tags`（濾後）在有 facets 語境才與 `all_tags` 分家；本包 spec 只驗無 facets 時兩者相等。
