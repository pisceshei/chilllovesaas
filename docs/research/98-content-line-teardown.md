# 98 — 內容線 teardown（Pages·Blogs·Articles·Menus）

> 步 14 的三源取證檔（2026-09-01）：①官方文檔深潛（agent 報告，shopify.dev＋
> help.shopify.com 逐字）②測試店 admin 親點（chill-love-u5q5mnzq，全權寫入授權）
> ③真店 storefront 實測（chill.deals）。實作對照＝`docs/dev/` 步 14 篇。

## §1 Liquid 物件契約（官方逐字，取證 2026-09-01）

- `blog` 14 屬性：all_tags／articles／articles_count（"doesn't include hidden
  articles"）／comments_enabled?／handle／id／metafields／moderated?／
  next_article（"next (older)"）／previous_article（"previous (newer)"）／tags／
  template_suffix／title／url。
- `article` 21 屬性：author／comment_post_url／comments（"The **published**
  comments"）／comments_count／comments_enabled?／content／created_at／excerpt／
  excerpt_or_content（有摘要回摘要、無則回內容）／handle／id／image／metafields／
  moderated?／published_at／tags／template_suffix／title／updated_at／url／user。
  - 🔴 `article.id` 官方型別＝**string**（blog.id 是 number）。
  - 🔴 `article.handle` Liquid 層＝**複合形** `{blog-handle}/{article-handle}`
    （官方範例值）；Admin GraphQL `Article.handle`＝裸 handle——兩層不同。
- `blogs` global：by handle 存取（`blogs.potion-notions.articles`）。
- `comment.status`："**Always returns `published`.**"——Liquid 層看不到待審／spam；
  狀態機在 admin 層（§4）。
- `linklist`：handle/levels/links/title；🔴 "There's a maximum of 3 levels."
- `link` 12 屬性（含 data_sharing_opt_out_icon）；`link.type` 13 值：article_link／
  blog_link／catalog_link／collection_link／collections_link／
  customer_account_page_link／frontpage_link／http_link／metaobject_link／
  page_link／policy_link／product_link／search_link。

## §2 URL 與模板

- blog＝`/blogs/{blog-handle}`；article＝`/blogs/{blog-handle}/{article-handle}`
  （官方直述句未取得——由 tagged 範例 URL 與 comment_post_url 範例間接證實；
  真店親點直接證實：S14 Probe Post ⇒ `chill.deals/blogs/news/s14-probe-post` 200）。
- tag 過濾（官方逐字）："appending `/tagged/[tag-handle]` to the blog URL"；
  多 tag＝"combining the handleized tags with a `+`"（`/tagged/news+breaking`）。
  `current_tags` 於 blog／collection 模板可用。
- 留言：`{% form 'new_comment', article %}`；欄位 comment[author]/[email]/[body]；
  comments 分頁 "limit of 50 per page"。
- 🔴 **真店抓包（comment form DOM，2026-09-01）**：
  action＝`https://chill.deals/blogs/news/s14-probe-post/comments#comment_form`、
  method=post、fields＝form_type=new_comment／utf8=✓／comment[author]／
  comment[email]／comment[body]／**h-captcha-response**（hCaptcha 欄位在場）。
  ⚠️ 提交回應三層（payload/HTTP/UI）**未取證**——提交會觸發 CAPTCHA（紅線不碰），
  登記 V；moderated 提示文案（Ella 讀 blog.moderated?）＝"Please note, comments
  need to be approved before they are published."（實測逐字）。

## §3 Admin GraphQL（官方，取證 2026-09-01）

- Page：body(HTML!)/bodySummary（"first 150 characters…truncated by ellipses"）/
  handle/isPublished/publishedAt/templateSuffix/title…；pageCreate（title 必填；
  isPublished "Defaults to `true` if no publish date is specified."）；pageUpdate
  多 **redirectNewHandle**（改 handle 自動建轉址）；pageDelete 永久刪。
- Blog：commentPolicy(CommentPolicy!)＝**AUTO_PUBLISHED／CLOSED／MODERATED**
  （逐字描述見 agent 報告）；tags＝"200 most recent blog articles" 的 tags；
  blogCreate（title 必填）；blogDelete——🔴 底下 articles 下場官方沉默（未取得）。
- Article：author(ArticleAuthor)/blog!/body(HTML!)/handle（裸）/isPublished/
  publishedAt/summary(HTML)/tags/templateSuffix…；articleCreate（blogId!/body!/
  title!）；articleUpdate 多 redirectNewHandle；articleDelete。
- Menu：isDefault（"handle for default menus can't be updated and default menus
  can't be deleted."）；MenuItem 恰 7 欄（id/items/resourceId/tags/title/type/url）；
  menuCreate 三參數皆必填（title!/handle!/items!）；🔴 menuUpdate＝**整棵替換不是
  合併**（語義取得）；MenuItemType 13 值＝ARTICLE/BLOG/CATALOG/COLLECTION/
  COLLECTIONS/CUSTOMER_ACCOUNT_PAGE/FRONTPAGE/HTTP/METAOBJECT/PAGE/PRODUCT/
  SEARCH/SHOP_POLICY（↔ link.type 一一對應）。

## §4 admin 親點（chill-love-u5q5mnzq，2026-09-01）

- 導航：Content 下＝Metaobjects／Files／Menus／Blog posts（**Blogs 管理**經
  Blog posts 頁右上「Manage blogs」）；**Pages 在 /pages**（Online Store 頻道側）。
- Add blog post 表單：Title（AI 鈕）／Content 富文本／Excerpt／SEO 區（可改
  handle）／Visibility **預設 Hidden**，選 Visible 顯示 "As of {日期時間} GMT+8"
  ＋鉛筆（排程）／Image／Organization{Author=店主預設、Blog select 預設 News、
  Tags}／Theme template（"Default blog post"）。建立後 header：View／Manage
  comments／More actions；成功 banner "S14 Probe Post created"。
- 文章 admin URL＝/content/articles/{id}（596366491883 實例）。
- Blogs 列表：欄＝Title/Comments/Updated；預設一個 **News** blog、Comments 欄
  顯示 **Disabled**（＝CLOSED 預設）。
- Blog 編輯頁：Title（**4/255** 計數器＝255 上限實證）／Comments 三 radio
  **逐字＝Disabled／Allowed, pending moderation／Allowed**／Theme template
  （"Default blog"）；"Default blog" 徽章。
- 啟用 moderation 後 storefront 文章頁出現 LEAVE A COMMENT（Name*/Email*/
  Comment*＋moderation 提示＋POST COMMENT）；已復原 Disabled。
- 文章頁 byline 實測形："On Sep 01, 2026 By KEN LEE / 0 comments"。
- Menus：**三個預設選單**＝Main menu（Home, Catalog, Contact）／Footer menu
  （Search, Your Privacy Choices）／**Customer account main menu**（Orders,
  Profile）——第三個是 2026 現值（研究缺口 #6 的實測補位）。選單編輯：
  Name＋Handle 唯讀顯示（default menu）＋項目列（拖曳把手）＋inline Add
  （Label＋Link「Search or paste link」）。
- 🔴 Link 目標 picker 值域（親點窮舉）：**Online store**{Home page／Search／
  Collections›／Products›／Pages›／Blogs›／Blog posts›／Policies›}＋
  **Customer accounts**{Orders／Profile}＋**Apps›**；外部 URL＝直接貼進搜尋欄。
  **無 Metaobject 項**（GraphQL enum 有 METAOBJECT——admin 未露出，照登差異）。
- Pages 列表（/pages）：欄＝Title/Visibility/Content/Updated；預設兩頁
  "Your Privacy Choices"＋"Contact"（Visible）。

## §5 未取得清單（19.3）

1. blog/article URL pattern 官方直述句（真店實測已補位）。
2. blog 每頁文章數預設值（paginate 通用 1–250；未設 by 時官方數字未取得）。
3. blogDelete 後 articles 下場（官方沉默）——我方裁定隨 dev doc。
4. 留言提交回應三層（CAPTCHA 紅線擋道）——V 項；本尊 spam 判定機制內部。
5. `blog.tags` vs `all_tags` 語義差異明文（兩欄皆存在；歷史 tagged 過濾差異說
   未證實，不得引用）。
6. current_tags 回傳型別明文（合理推定 array of string——標 V）。
7. 測試店 fixture：S14 Probe Post（article 596366491883，blog News 107152474347）
   留存為長期 fixture（後續 blog 線量測用——勿刪）。
