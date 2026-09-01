# G2 步 14：內容線（Pages·Blogs·Articles·Menus）

> 取證正典＝`docs/research/98-content-line-teardown.md`（官方逐字＋admin 親點
> ＋真店 storefront）。14a＝資料層＋Admin API（本篇）；14b admin 頁、14c 前台
> 模板另包。

## 1. 14a 射程

| 件 | 落點 | 98 錨 |
| --- | --- | --- |
| blogs/articles/article_comments 三表 | migration 20260901130000＋pages.template_suffix 補欄 | §3/§4 |
| comment_policy 三值 | Blog::COMMENT_POLICIES（closed 預設＝admin Disabled 實測） | §4 |
| 可見性語義 | published_at 單閘（NULL=Hidden；官方 pageCreate default true） | §3/§4 |
| CRUD 12 支 | page/blog/article/menu ×3（typed code——鐵律 4） | §3 |
| menu 樹寫入 | Content::SaveMenu（🔴 整棵替換＝官方 menuUpdate 語義；≤3 層） | §3 |
| 預設選單防護 | Menu::DEFAULT_HANDLES（不可刪、handle 不可改） | §3/§4 |
| item 型別擴充 | MenuItem RESOURCE_TYPES＋STATIC_TYPES（官方 13 值子集） | §3 |

## 2. 防線（突變紅證 MC1–MC8）

- 發布語義雙向（MC1 default true／MC2b isPublished:false 真藏）。
- article handle 唯一域＝(shop, blog)（MC3——URL 複合形的資料層對應）。
- menuUpdate 整棵替換（MC4）；預設選單防護（MC5）；巢狀 ≤3（MC6）。
- redirectNewHandle 建 301（MC7——`source: handle_change` 走既有重導表）；
  blogDelete 連文章刪（MC8——官方沉默處的我方裁定，98 §5-3）。

## 3. v1 邊界（91 §3.64）

article image／metafields／comments 管理 API（admin Manage comments 頁隨 14b）／
MenuItemType 的 METAOBJECT·SHOP_POLICY·CUSTOMER_ACCOUNT_PAGE／blog feed／
Liquid 層（blogs/articles drops、tagged、留言 POST）＝14c。
