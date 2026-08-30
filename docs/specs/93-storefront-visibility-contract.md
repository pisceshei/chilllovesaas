# 93 — 前台消費介面的可見性契約（S9；W6 的前置）

> 產出脈絡：`docs/plans/2026-08-26-發布與可見性-分步執行方案.md` §S9。
> 消費者＝W6 全部前台包（30/33/34/35）與未來的 Storefront API。
> 可執行落點＝`app/services/storefront/lookup.rb`（直連面）＋既有
> `Product.purchasable/.discoverable`、`Collection.published_on`（scope 面）。
> 實測全記錄＝`docs/research/82-admin-channels.md` §20（2026-08-30，本檔僅引結論）。

## §A 官方錨（四條；逐字，取證 2026-08-30）

| # | 逐字 | 來源 |
|---|---|---|
| A1 | `Unpublished products will behave just like they were archived or deleted: they will be omitted from connections and not found when queried by handle or ID`；查單筆 `that product field returns null` | https://shopify.dev/docs/api/storefront/latest/queries/product |
| A2 | Liquid `product` 物件屬性共 **44 個**，**沒有 `status`**（有 `published_at`） | https://shopify.dev/docs/api/liquid/objects/product |
| A3 | `In private mode, all of your online store's pages are hidden from visitors and search engines, and your online store displays a customizable landing page instead.`＋`When you first register for a Shopify plan, your store access is restricted to private mode by default.`＋`Select Restrict access to B2B customers only to limit your store's access to B2B customers` | https://help.shopify.com/en/manual/online-store/themes/password-page |
| A4 | UNLISTED：`The product is active but you need a direct link to view it… It will be returned in Storefront API and Liquid only when referenced individually by handle, id, or metafield reference.` | https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus（已錄 PR-C 裁定書 §外部證據 A；2026-08-27） |

## §B 兩個消費形態的「查無」語義不同（同一判準、兩種包裝）

| 消費形態 | 查無時 | 依據 |
|---|---|---|
| Storefront API（未來） | 單筆欄位回 **null**（HTTP 200）；connection **整筆省略**——不是 404、不是 errors | A1 |
| Liquid 前台頁 | 主題化 **404** 頁（HTTP 404） | 實測 82 §20（`/products/<不存在>` 與 draft/archived/取消發布同形態） |

⇒ `Storefront::Lookup` 統一回 **record／nil**；包裝層各自決定 404 或 null。
🔴 W6 紅線：**不得**在 Liquid 面回「空頁 200」，也不得在 API 面回 404。

## §C 資源層判準（兩軸：直連 vs 發現）

| 狀態×發布 | 直連（handle/id/metafield 引用） | 發現面（搜尋/系列/推薦/sitemap/feed） | 實測格 |
|---|---|---|---|
| active＋已發布 | ✅ | ✅ | A（200；suggest 收錄） |
| **unlisted**＋已發布 | ✅（A4） | 🔴 **排除** | QC（直連 200；suggest 與全文搜尋皆 0） |
| draft | ❌ | ❌ | B（404；suggest 排除） |
| archived | ❌ | ❌ | D（404；≤6s 生效） |
| active＋未發布本管道 | ❌（A1） | ❌ | C（見 §F 預覽站例外） |
| 排程未到點 | ❌（到點起 ✅） | 同左 | spec S1 |
| 變體全數未發布 | ❌（product_spec 既有格） | ❌ | — |

- 直連面判準＝`purchasable`（含 unlisted）；發現面判準＝`discoverable`（僅 active）。
  恆等不變量 `discoverable ⊆ purchasable`（limits `discoverable_subset_of_purchasable`）。
- Collection 無 status 欄 ⇒ 單閘（發布層）；「系列頁列哪些商品」另用 `discoverable`。
- UNLISTED 直連頁的 meta robots＝limits `unlisted_meta_robots: "noindex,nofollow"`
  （D4 裁定＝**ours**；本尊實際值因預覽站全域 noindex 而**未取得**，見 §F）。

## §D Liquid 相容層紅線（包 30/34 驗收項）

1. 🔴 `product` drop **不得**新增 `status` 屬性（A2；44 屬性白名單＝該頁清單）。
   後台語義（draft/unlisted）**不外洩**到前台物件——可見性由 lookup 前置決定。
2. `published_at` **是**合法屬性（A2 清單內）。
3. 查無資源的 Liquid 變數＝nil（模板可 `{% if product %}`），路由層 404。

## §E 店級閘門（先於資源層；包 30/33 射程，本契約僅定行為）

實測（chill.deals 密碼模式，curl，2026-08-30；82 §20）：

| 路徑 | 行為 |
|---|---|
| `/`、`/products/*`、`/collections/*`、`/search/suggest.json`、`/cart.js` | **302 → `/password`**（HTML 與 JSON 一視同仁） |
| `/password` | 200（表單 `action="/password"`） |
| `/robots.txt` | 🔴 仍 **200** 且 `Allow: /`——「hidden from search engines」是靠 302 實現，不是 robots |
| `/sitemap.xml` | 🔴 **404** ＋ `location: /password` 頭（非常規組合，照登記） |

五道閘（82 §9.6a 總表）：①development/密碼保護（店級，A3）②B2B-only（店級，A3）
③商品 status ④publication（本層）⑤catalog（M5）。
W6 順序：**店級閘在 controller before_action，先於任何 lookup**；閘住時一切內容路徑
302 到密碼頁（含 JSON 端點），robots.txt 照常 200。

## §F 已知未取得（誠實登記；91 §3.46）

1. **預覽站不執行管道發布閘**：admin Preview（`*.shopifypreview.com`＋`preview_key`）
   對「active＋取消發布 OS」的商品在 +6s/+51s/+120s 仍回 200，而同 session 的
   status 變更 ≤6s 生效 ⇒ 傾向「預覽站語義＝商家視角，不含 publication 閘」；
   但無法完全排除 publication 傳播獨立且 >2min。**真店面行為以 A1 為準**。
2. **unlisted 的真店面 noindex**：預覽站對 active 商品同樣輸出 `noindex,nofollow`
   （控制組），無從歸因；真店面被密碼牆擋住。D4 之 ours 裁定維持。
3. `/collections/all` 在該主題輸出無 `<a href="/products/…">` 可抽 ⇒ 系列頁排除面
   由 suggest／全文搜尋兩面代證，系列頁本身**未直測**。
