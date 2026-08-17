# 13 — 功能規格：商品、變體、媒體、集合、庫存（生產級）

> 覆蓋功能：商品 CRUD、options/variants、媒體上傳、handle 與 SEO、collections（**sources 模型**）、庫存帳與調整、CSV 匯入。規格對照研究 01/06，基線見 11。

<!-- 依 61 號 §4.1 修正，原文：「collections（manual/smart）」。官方已把 manual／smart 二分法標為 **legacy**
     （P22 有「Legacy smart collections」與「Legacy manual collections」兩個獨立頁面），
     新模型是四型來源 × include/exclude 的 sources 模型（§F4）。
     🔴 任何人翻舊版看到「manual/smart」都不要改回去——那個二分法表達不了 exclude、
     表達不了 collection 套 collection、表達不了 variants 來源，是**資料模型層級**的落差。 -->

## F1. 商品 CRUD 與變體

**生產級做法**：
1. 寫入包成 `Catalog::SaveProduct` service：商品欄位 + options + variants + media 排序在**單一 transaction** 內原子更新（Shopify 的 `productSet` 宣告式思路）。
2. Options 上限走 `config/limits.yml`（鐵律 6，**不用 DB CHECK**）；變體是**選項組合的稀疏集合**，**變體唯一性用唯一索引** `(shop_id, product_id, option_values_digest)` 兜底（digest ＝ 排序後 join 的 SHA1）。
   <!-- 2026-08-15 依 parity 查證修正三處，原文：
        「Options ≤3 在 service 與 DB（CHECK 或驗證 + 測試）雙重限制；變體 = option values 笛卡兒積，
          **變體唯一性用唯一索引** `(product_id, option_values_digest)` 兜底（digest = 排序後 join 的 SHA1）。」
        ① 🔴 **「笛卡兒積」是錯的**。本尊 `productOptions` 的 `optionValues` 官方明載包含
           "values not assigned to any variants" ⇒ **稀疏組合是合法狀態**；笛卡兒積展開只是
           `ProductOptionCreateVariantStrategy: CREATE` 的**顯式 opt-in**，預設是 `LEAVE_AS_IS`
           （官方逐字：「No additional variants are created in response to the added options.
            Existing variants are updated with the first option value of each option added.」）。
           照原文實作 ⇒ 每次加選項都強制展開全笛卡兒積，商家不要的組合也會被建出來。
        ② **DB CHECK 移除**：上限值一律引 limits.yml（鐵律 6），且本尊的上限是
           per-shop 可查詢的（`shop.resourceLimits`），焊進 DB CHECK 就改不動。
        ③ 唯一索引補 `shop_id`（鐵律 2：複合索引一律以 shop_id 開頭）。原文是省略寫法。
        🔴 **另補一句 D12 落地時才確立的事**：`option_values_digest` 是**我方內部實作，
           本尊沒有這個概念**（本尊 `ProductVariant` 型別上只有 `title` 與 `selectedOptions`）
           ⇒ **不得對外曝露**：不進 GraphQL 型別、不進 GID／feed／URL／CSV。
           因為它不外露，任何時候都可以一句 UPDATE 全表重算 ⇒ 不需要版本前綴欄。
           **這兩件事綁在一起，不得只留其一。**
        🔴 **digest 的輸入是 `option_value_id` 不是選項值字串**（67 §B.3-4：譯文掛在 id 上，
           用字串比對會讓切語言時找不到變體）。 -->
3. 變體批量編輯（價格/庫存欄位表格）走一支 bulk endpoint，逐列驗證、回傳逐列錯誤（對齊後台表格編輯 UX）。
4. 刪除策略：**商品與變體一律允許硬刪，不論是否被 line_items 引用**；刪除不可復原。line_item 對 variant／product 是**可空弱引用**，刪除後轉 NULL，訂單靠自己的快照欄位獨立成立。Archive 是**建議非強制**，不得實作成 userErrors 硬擋。
   <!-- 2026-08-15 依 parity 查證**推翻重寫**，原文：
        「刪除策略：商品被 line_items 引用 → 不可硬刪，只能 Archive；未被引用才允許真刪。變體同理。」
        🔴 **這條是 bug——以為在照抄本尊，但抄錯了。** 三項官方證據：
        ① `productVariantsBulkDelete` 的 userError enum **只有五個值**
           （AT_LEAST_ONE_VARIANT_DOES_NOT_BELONG_TO_THE_PRODUCT／CANNOT_DELETE_LAST_VARIANT／
            PRODUCT_DOES_NOT_EXIST／PRODUCT_SUSPENDED／UNSUPPORTED_COMBINED_LISTING_PARENT_OPERATION），
           **沒有任何一個與訂單引用有關**。擋點是結構與狀態，不是引用關係。
           https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductVariantsBulkDeleteUserErrorCode
        ② `CalculatedLineItem.variant` 官方逐字：「The value is null for custom line items and
           items where **the variant has been deleted**.」⇒ 本尊把「變體已被刪除」當成
           line item 上的**正常狀態**，不是要防的事。
           https://shopify.dev/docs/api/admin-graphql/latest/objects/CalculatedLineItem
        ③ `productDelete` 官方逐字：「Previously completed orders that included this product
           aren't affected. The product information in completed orders is preserved for
           record-keeping, and **existing refunds for this product remain valid and processable**.」
           並明說「Consider archiving」是**建議**（Consider），不是強制。
           https://shopify.dev/docs/api/admin-graphql/latest/mutations/productDelete
        🔴 **本尊的 `ProductVariant` 型別上沒有任何狀態欄位**（無 status／archived／archivedAt／
           deletedAt，也沒有 ProductVariantStatus enum）⇒ **變體沒有軟刪除這個概念**。
           「不想賣但想留著」的官方替代方案是 **publishing 控制**（help 逐字：「you can
           **manage publishing** for your product variants instead of deleting variants」），
           不是第三態。
        ⚠️ **前置條件（尚未做）**：`fk_line_items_product_variant_id` 目前**沒有 `on_delete`**
           ⇒ MySQL 預設 RESTRICT ⇒ **DB 層現在根本刪不掉變體**。要改成 `ON DELETE SET NULL`
           （欄位已是 nullable）。**這一條沒做完之前不得開放刪除路徑。**
        同批修正：`docs/specs/63` §B.4 硬規則 2 的同一條敘述。

        ✅ **2026-08-16 測試店實測確認（T-1 結案）**，`docs/worklog/2026-08-16-T1實測-變體刪除語義.md`：
           建含變體 A 的正式訂單 #1006（A 的可售數量變 −1，引用關係成立）
           → 刪除變體 A → **成功，無任何錯誤**。
           確認 modal 逐字：「選項值為「A」的子類將從您的商店中刪除。此動作無法復原。」
           ——**完全沒有提到訂單**。
           刪除後訂單 #1006：商品名、**變體標題「A」照常顯示**、金額與狀態全不變
           ⇒ **line item 是快照**，證實上面第②項的官方說法。
           🔴 上面那些官方文檔本來只是**證據方向**（mutation 頁對此完全沉默）；
              現在是**親自跑過**。這條前置條件解除，可以往下走。 -->
5. `position` 排序欄位用整數 gap 法（100,200,300…重排時重編）；拖曳排序 endpoint 冪等。
6. status **四態**（`ACTIVE` / `DRAFT` / `ARCHIVED` / **`UNLISTED`**，值域＝`limits.product.status_values`）＋ 前台可見性拆成**兩個獨立維度**：`Product.purchasable` 與 `Product.discoverable`（**不再有 `Product.published` 這個 scope**）。四個狀態是這兩維的組合，真值表、變體層 AND 規則與全站影響面見 **§F1.2**。

<!-- 依 61 號 §1.3（dev D3 `ProductStatus` 四值 / D4 unlisted-products）與 63 號 §D.2、§H.2、§L-10 修正，
     原文：「6. status 三態（draft/active/archived）+ 前台可見性規則：active 且發佈到 online store channel
     才出現在 storefront 查詢（做成 `Product.published` scope，一處定義全站重用）。」
     🔴 兩處錯：①狀態是四態不是三態（2025-10 引入 `UNLISTED`）；②更嚴重的是
     「一處定義全站重用」的那個**單一** scope ——`UNLISTED` 的存在證明「可購買」與「可被發現」
     是兩個獨立維度，一個 scope 兼管兩件事，補 UNLISTED 時一定會撞：
     要嘛 UNLISTED 商品完全買不到（`published` 排除它），要嘛它出現在搜尋與 sitemap 裡
     （`published` 納入它）——後者是 SEO 事故，官方對 UNLISTED 明載 `noindex,nofollow` 且排除於 sitemap。
     ✅ **63 §L-10 於本節結案**（63 為唯讀，結案記錄留在此處）。
     🔴 任何人翻舊版看到「三態」或 `Product.published` 都不要改回去。 -->

**工具**：Active Record、dnd-kit（前端拖曳）、TanStack Table（變體編輯表格）。

**⚠️ 坑**：
- 變體重生成走 diff：match 的更新、**多的依策略刪除**、新的建立。破壞性一律是**明文 opt-in**。
  <!-- 2026-08-15 依 parity 查證修正兩處，原文：
       「變體重生成時**不能砍掉重建**（會斷 line_items/inventory 外鍵與歷史）——diff 現有變體：
         match 的更新、多的**軟移除**、新的建立。」
       ① 🔴 **「軟移除」刪掉**——本尊變體沒有第三態（見 §F1-4 的批註）。
       ② 🔴 **理由句「會斷 line_items 外鍵」刪掉**：那是**我方 FK 設定**的問題，不是本尊的約束。
          本尊 line item 是快照＋可空弱引用，刪變體不會斷歷史。
          正確的理由是：**保住庫存帳與外部引用**（app／feed／推薦／購物車裡的 variant_id），
          **不是因為 line_items 擋著**。
       ③ 「不能砍掉重建」改為**策略參數化**，對齊本尊三個 enum：
          `ProductOptionCreateVariantStrategy`：LEAVE_AS_IS（預設，既有變體補第一個值）／CREATE
          `ProductOptionUpdateVariantStrategy`：LEAVE_AS_IS（需刪變體時**回 error**）／MANAGE（連帶刪）
          `ProductOptionDeleteStrategy`：DEFAULT／NON_DESTRUCTIVE（只有不刪到變體才成功）／
            POSITION（重複時**保留 position 較低者**，官方逐字「Remaining variants will be
            deleted, **highest `position` first**」）
          另：`productSet` 是**全量覆寫**（官方逐字「deletes existing entries that aren't
          included in the mutation's input」）。 -->
- price 允許 0（免費商品合法）；**`compare_at_price` 一律照存照回，核心層不得擋、不得改寫**。
  <!-- 2026-08-15 依 parity 查證修正，原文：「但 compare_at_price < price 時要嘛擋、
       要嘛不顯示折扣（選一致的規則，Shopify 是不顯示）」。
       🔴 **本尊試過「擋」並主動全版本撤回**：2020-04 上線過這條 validation，
       2021-01-27 changelog「Pricing validations removed from all API versions」**回溯撤除**。
       ⇒ `< price`、`== price`、`= 0`（🔴 0 ≠ 空值）**全部合法可儲存**。
       折扣判定是 **Liquid theme 層**的事（Dawn 用 `compare_at_price > price`），不是核心欄位；
       **不得**提供 `on_sale` 衍生布林當唯一真相。
       admin 可顯示**非阻斷提示**，但不得是 userErrors。
       ⚠️ 與 `docs/research/22`:104「系列頁 Sale 標籤需全變體 compare-at 一致」互引。 -->
- `option_values` 順序敏感（Size/Color vs Color/Size 是不同變體識別）→ digest 前先按 **`product_option_id`** 排序。
  <!-- 2026-08-15 修正排序基準，原文：「digest 前先按 **option position** 排序」。
       🔴 `position` 是使用者**拖曳就會改**的顯示順序（本尊有 `productOptionsReorder`），
       **身分鍵不得由可變資料決定**。照 position 排序的話，每次重排選項都必須在同一
       transaction 內重算該商品**所有**變體的 digest——任何一條路徑忘記重算就是靜默的
       身分斷裂，而那正是 `63` §B.5 存在要防的事故形態。
       ⚠️ **本條的原意（順序敏感 ⇒ 先正規化再 hash）完整保留**，只換排序基準。
       🔴 **這不算偏離本尊**——本尊根本沒有 digest 這個概念（見 §F1-2 的批註），
       排序鍵是我方內部實作的自由度。 -->
- 富文本描述是租戶輸入、買家可見 → 存前 sanitize（rails-html-sanitizer 白名單：p/br/strong/em/ul/ol/li/a[href 限 http(s)]/img[src 限自家 CDN]），**前台輸出處再 sanitize 一次**（雙保險）。

### F1.1 最終銷售品項與退貨規則的商品側掛載（P0-10 的商品端）

<!-- 依 46c:427–432、44:433、44:439 補寫，原文：「最終銷售品項」以 **collection 或 product** 為粒度指定（44 實測為 radio 二選一）；
     逐字「Your customers can't submit return or cancellation requests for final sale items.」＝入口層擋掉，不是提交後被拒；
     且「套裝組合（bundles）不能設為最終銷售品項」。我方原本 13／16／42 皆無 -->

| # | 規則 | 實作 |
|---|---|---|
| 1 | 最終銷售的**指定粒度為二選一**：`商品系列(collection)` 或 `商品(product)` | `return_rules.final_sale_scope` enum ＋ `return_rule_final_sale_targets(rule_id, target_type, target_id)` |
| 2 | 命中即**前台完全不出現退貨/取消申請入口** | 判定放在 `Product.returnable?` 與 line item 層，前台入口與 API 兩處都擋 |
| 3 | **bundles 不可設為最終銷售** | 儲存時驗證：target 為 bundle → userError |
| 4 | 判定**一律讀下單當下的快照**，不是現行規則 | 見 16-F7.4：`order_line_items.return_policy_snapshot_id` |
| 5 | 退貨規則關閉時，最終銷售整卡 disabled/灰化 | 44 實測行為，UI 照做 |

### F1.2 商品狀態四態，與「可購買 / 可被發現」兩個獨立維度

<!-- 依 61 號 §1.3（dev D3：`ProductStatus` 四值；dev D4：unlisted-products 完整行為）
     與 63 號 §D.2（兩個 scope 的判定式）、§H.2（變體級發布的 AND 規則）、§L-10（衝突登記）補寫。
     🔴 本節是 63 §L-10 的結案處置。原 13 §F1-6 的單一 `Product.published` scope 已作廢。 -->

**核心洞見（本節存在的理由）**：`UNLISTED` 不是「多一個 enum 值」，它是一個**證據**——證明**「可購買」與「可被發現」是兩個獨立的維度**。我方原本用一個 `Product.published` scope 兼管兩件事，那個設計在只有三態時剛好不出錯（因為三態下兩維完全同步），補 `UNLISTED` 時必然撞牆。

#### (a) 四態定義

| 值 | 語義（依官方導出，非逐字轉貼） | 可購買 | 可被發現 | 直接 URL |
|---|---|:---:|:---:|---|
| `ACTIVE` | 可販售，可發布到各銷售管道與 app | ✅ | ✅ | 200 |
| **`UNLISTED`** | **商品是 active 的，但需要直接連結才看得到**；不出現在搜尋、商品系列與商品推薦中 | ✅ | ❌ | 200 ＋ `noindex,nofollow` |
| `DRAFT` | 尚未備妥，顧客在任何管道都取用不到 | ❌ | ❌ | 404 |
| `ARCHIVED` | 已停售，顧客在任何管道都取用不到 | ❌ | ❌ | 404（`ARCHIVED` 可回 **410**〔本專案推導〕：曾存在、已永久停售，410 讓爬蟲更快移除索引） |

`UNLISTED` 的完整行為（61 §1.3 引 dev D4）：購物車／結帳／訂單／購後流程與 `ACTIVE` 相同；**不進**商品系列、站內搜尋、預測搜尋、商品推薦；輸出 `noindex,nofollow` 且**排除於 sitemap**；可達路徑只有直接 URL、metafield 參照、分享連結。引入版本 `2025-10`。

#### (b) 兩維真值表（`limits.product.purchasable_statuses` / `discoverable_statuses`）

```
purchasable  := status ∈ {ACTIVE, UNLISTED}
                ∧ 商品已發布到該管道       （product_publications.status = 'PUBLISHED'）
                ∧ 該變體已發布到該管道     （variant_publications.published = true）   ← §(c) 的 AND

discoverable := status = ACTIVE
                ∧ 商品已發布到該管道
                ∧ 該變體已發布到該管道
```

| status | 已發布 | 變體已發布 | purchasable | discoverable |
|---|:---:|:---:|:---:|:---:|
| ACTIVE | ✅ | ✅ | ✅ | ✅ |
| ACTIVE | ✅ | ❌ | ❌（該變體） | ❌（該變體） |
| ACTIVE | ❌ | 任意 | ❌ | ❌ |
| **UNLISTED** | ✅ | ✅ | **✅** | **❌** |
| UNLISTED | ✅ | ❌ | ❌ | ❌ |
| UNLISTED | ❌ | 任意 | ❌ | ❌ |
| DRAFT | 任意 | 任意 | ❌ | ❌ |
| ARCHIVED | 任意 | 任意 | ❌ | ❌ |

🔴 **恆等不變量（可執行斷言，`limits.product.discoverable_subset_of_purchasable`）**：

```
discoverable ⊆ purchasable        # 恆成立
```

任何實作若讓某商品 `discoverable` 但不 `purchasable`，就是 bug——那等於**把買家從搜尋結果送進一個買不了的頁面**（soft-404，30 §1.1 嚴禁）。這條不變量比真值表本身更有價值：它是**一條可以寫進測試的性質**，而真值表只是一張要人去對照的表。

#### (c) 變體也有獨立發布層——兩層是 AND，不是 OR

官方明載（61 §2.2 引 help P16）：可**逐變體**對各銷售管道／目錄發布或取消發布，且**「要在某管道顯示，父商品與該變體必須都發布到該管道」**。另：**不能為個別變體設定排程發布日期**（排程只有商品級）。

```
變體 v 在管道 c 可見 := product_publications(product, c).status = 'PUBLISHED'
                       ∧ variant_publications(v, c).published = true

商品 p 在管道 c purchasable  := p.status ∈ {ACTIVE, UNLISTED} ∧ ∃v ∈ p.variants : v 在 c 可見
商品 p 在管道 c discoverable := p.status = ACTIVE              ∧ ∃v ∈ p.variants : v 在 c 可見
```

- **商品級 scope 需要「至少一個變體可見」**，不是「商品已發布」就夠——一個所有變體都被取消發布的商品，頁面上沒有任何東西可買。
- 表結構見 63 §H.2（`product_publications` ＋ `variant_publications`；後者**沒有** `publish_at` 欄位，因為官方明載變體不可排程）。`limits.catalog_flow.variant_level_publishing: true`、`variant_publish_scheduling_allowed: false`。
- 🔴 **連帶影響物化欄**：`products.min_price_cents` 的 `MIN()` **必須只算該管道可見的變體**，否則會出現「集合頁顯示 HK$938 起，點進去最低只有 HK$1,200」（63 §H.2 已定 `product_publication_price_ranges`）。
- 🔴 **連帶影響目錄定價**：未發布到某目錄的變體**不套用**該目錄的定價調整（`limits.catalog_flow.catalog_pricing_requires_variant_publication: true`）⇒ `Pricing::PresentmentResolver`（63 §G.2）收集 catalog price 前必須先過 `variant_publications` 過濾。

#### (d) scope 的 SQL 形態（一處定義，全站重用）

```sql
-- Product.purchasable(channel) —— 鐵律 2：複合索引以 shop_id 開頭
WHERE p.shop_id = :shop_id
  AND p.status IN ('ACTIVE','UNLISTED')                 -- ← discoverable 版本此處為 = 'ACTIVE'
  AND EXISTS (SELECT 1 FROM product_publications pp
              WHERE pp.shop_id = p.shop_id AND pp.product_id = p.id
                AND pp.publication_id = :channel AND pp.status = 'PUBLISHED')
  AND EXISTS (SELECT 1 FROM product_variants v
              JOIN variant_publications vp
                ON vp.shop_id = v.shop_id AND vp.product_variant_id = v.id
                AND vp.publication_id = :channel AND vp.published = TRUE
              WHERE v.shop_id = p.shop_id AND v.product_id = p.id)
```

**兩個 scope 只差 `status` 那一行**——所以實作上是同一支 scope 產生器吃不同的 status 集合（`limits.product.purchasable_statuses` / `discoverable_statuses`），**不是兩份複製貼上的 SQL**。複製貼上的第三個消費者出現時，一定只有一份會被改到。

#### (e) 影響面掃描：`UNLISTED` 不得出現在這些地方，但直接連結必須能買

| # | 消費者 | 用哪個 scope | `UNLISTED` 的正確行為 | 出處 |
|---|---|---|---|---|
| 1 | sitemap（四分片） | `discoverable` | **不入 sitemap** | 62 §C.1「只列 canonical 且回 200 的 URL」＋ 61 §1.3 |
| 2 | hreflang 矩陣 | `discoverable` | 不入矩陣（否則違反 62 §0.2 原則 4 的可達性不變量） | 62 §I |
| 3 | `<head>` robots | — | 輸出 `noindex,nofollow`（`limits.product.unlisted_meta_robots`） | 61 §1.3 |
| 4 | **Product / Offer JSON-LD** | `discoverable` | **不輸出**〔本專案推導〕：一個宣告 `noindex` 的頁面同時提供 rich-result 標記是自相矛盾，且會讓 AI 代理把它當可推薦商品 | 62 §A、本節推導 |
| 5 | 站內搜尋索引 | `discoverable` | 不進索引；`ACTIVE → UNLISTED` 必須觸發**移除**（不是等下次全量重建） | 61 §1.3 |
| 6 | 預測搜尋 / 商品推薦 | `discoverable` | 不出現 | 61 §1.3 |
| 7 | **商品系列（前台）** | `discoverable` | 不出現在任何前台系列頁；見 §(f) 的成員資格例外 | 61 §1.3、§F4.6 |
| 8 | GMC / Meta feed | `discoverable` | 不進 feed（進了＝把 noindex 的商品送去做購物廣告） | 62 §A.3、30 §6 |
| 9 | **AI 代理端點**（`/agents.md`、代理 catalog） | `discoverable` | **不得出現**。🔴 這一格最容易漏：代理是「可被發現」的**新通路**，官方的 noindex 在代理面完全不生效，必須由我方自己擋 | 62 §H.4 |
| 10 | IndexNow ping | `discoverable` | `ACTIVE → UNLISTED` 轉換時**主動 ping 一次**（讓爬蟲盡快看到 noindex 並移除） | 62 §C-3、30 §9-9 |
| 11 | `/cart/add.js`、結帳 | **`purchasable`** | **必須能買**——這是 `UNLISTED` 的全部意義 | 61 §1.3 |
| 12 | 商品頁本身（直接 URL） | **`purchasable`** | 回 200，完整可購買 | 61 §1.3 |
| 13 | `products.min_price_cents` 物化 | 該管道可見的變體 | 同 §(c) | 63 §H.2 |
| 14 | admin 商品列表／搜尋 | **不套任何 scope** | 四態全顯示，並提供 status 篩選 | 60 §5 |

**狀態轉換的副作用（`Catalog::StatusTransition` 一處實作）**：

| 轉換 | 必須連帶做什麼 |
|---|---|
| `ACTIVE → UNLISTED` | 移出搜尋索引／sitemap／feed／代理 catalog；IndexNow ping；系列的**前台**計數變動；**購物車內既有品項不受影響**（`purchasable` 仍為 true） |
| `UNLISTED → ACTIVE` | 反向全部加回；IndexNow ping |
| `* → DRAFT / ARCHIVED` | 上述全部移除 **＋ 購物車內既有品項標記不可購買**（`purchasable` 轉 false，結帳前必須擋下） |

#### (f) 成員資格（admin）vs 前台可見性——兩個數字會不一樣，這是刻意的

〔本專案推導〕商品系列的**成員資格**不過濾 status（否則 61 §4.2 的 `Product status` 條件本身無法表達，且商家在後台看不到自己加進去的草稿商品）；**前台的系列頁一律再套 `discoverable`**。

⇒ 後台顯示「本系列 120 件商品」、前台只有 113 件。**兩個數字不同不是 bug，但商家一定會問** ⇒ 後台列表必須標注「（前台可見 113）」。這不違反鐵律 7（數字同源）——它們是**兩個不同的指標**，鐵律 7 要求的是同一指標處處同源，不是把兩個指標壓成一個。

#### (g) 刻意偏離官方的一條：不做「舊 API 版本降級成 ACTIVE」

官方行為（61 §1.3 引 dev D4）：**早於 `2025-10` 的 API 版本會把 unlisted 商品的 status 回成 `active`**；REST Product 資源目前仍只列三值（D16）。

🔴 **我方刻意不做這個降級**（`limits.product.unlisted_downgrade_on_old_api_version: false`）。理由：降級會讓舊版整合把 `UNLISTED` 當 `ACTIVE` 處理，再把它送進自己的 feed／索引——**官方的 noindex 就此完全失效**，而且失效得無聲無息。我方 enum 一次到位四值，任何 API 版本一律照實回 `UNLISTED`；舊版整合看到未知 enum 值應報錯（那是**正確的失效方向**：吵鬧地壞掉，勝過安靜地洩漏）。
**這是「本尊有、我方刻意不做」的一條**，比照 15 §F4.2 的先例明文標註，避免下一輪稽核當成遺漏重新開單。

#### (h) 遷移

既有三態資料一列不動；`UNLISTED` 為**新增**的 enum 值（DB 端 `ENUM`／`CHECK` 加值，不需要回填）。真正的工作量在**把 `Product.published` 的每一處呼叫點逐一判定該換成 `purchasable` 還是 `discoverable`**——這正是 63 §D.2 所說「改它會牽動整個 storefront 查詢」的部分。
**遷移期紀律**：`Product.published` 直接刪除，**不保留為別名**。保留別名會讓「沒判定過的呼叫點」繼續編譯通過，而那正是我們要找出來的東西。

## F2. Handle 與 SEO 欄位

**生產級做法**：
1. handle 生成：標題 → transliterate 拉丁化；**中文標題不轉拼音**，改用「允許 unicode handle（URL encode）」或 fallback `product-{n}`——demo 選 unicode handle（`/products/棉質短T` 可用），SEO 欄位另存。
2. 唯一性 `(shop_id, handle)` 唯一索引；衝突自動 `-1` `-2` 後綴。
3. 改 handle → `url_redirects` 表自動寫 301（old_path → new_path），storefront **資源不可用回應（404 與 unpublish 410）前**先查 redirect 表（範圍同 90-blueprint/12 C.5 <!-- 2026-08-17 更正（PR #52 第 14 輪）：原「404 前」漏 410 形 -->）。
4. SEO title/description 欄位留空時 fallback 到標題/描述截斷（view helper 一處實作）。

**⚠️ 坑**：URL encode 後的 unicode handle 在部分分享場景很醜——給商家「編輯 handle」欄位即可自救；redirect 表要防循環（A→B→A），寫入時檢查目標是否也在表裡。

## F3. 媒體上傳與圖片管線

**生產級做法**：
1. Active Storage + S3 相容儲存（R2）；**direct upload**（瀏覽器直傳，presigned）避免大檔過 Rails；bucket 私有，前台出圖走 CDN + 簽名 URL 或 public-read 的衍生圖 bucket。
2. 驗證：content_type 白名單（jpeg/png/webp/gif/mp4）、大小上限（圖 20MB/影片 200MB）、**像素上限（如 50MP）防解壓炸彈**——`image_processing` + libvips 讀 header 先驗尺寸再處理。
3. 上傳完成 → job 預生成常用尺寸（thumb 160、card 533、detail 1200、og 1200×630）、strip EXIF（隱私：照片 GPS）、轉 webp。
4. 前台 `<img>` 一律帶 width/height + `loading="lazy"`（防 CLS）；首圖 `fetchpriority="high"`。
5. alt text 欄位進後台表單（無障礙 + SEO）。

**工具**：Active Storage、image_processing（libvips）、R2/S3。
**⚠️ 坑**：libvips 對損壞檔案會拋例外 → 處理 job 要 rescue 標記「處理失敗」而不是無限重試；direct upload 的 CORS 設定只允許自家 origin；刪商品要連動清 blob（purge_later），否則儲存費用悄悄長大。

## F4. Collections（**sources 模型**）

<!-- 依 61 號 §4.1（help P25 manage-sources）、§4.2（P24 條件運算子）、§4.3（P23 上限）、§4.4（P26 排序）
     與 §1.5（P9 標籤等價）重寫，原文：
       「## F4. Collections（manual / smart）
        1. manual：`collection_products` join 表 + position 手動排序。
        2. smart：`rules` JSON（[{column, relation, condition}] + disjunctive boolean）；**匹配結果物化**
           進同一張 join 表（標記 source=rule），不要每次前台查詢即時算。
        3. 物化時機：…ResyncProductJob…RebuildJob…
        4. tags 用正規化表 `product_tags(product_id, tag)` + 索引，**不要存逗號字串**…
        5. 排序選項（手動/價格/新舊/暢銷）…「暢銷」用 90 天銷量 rollup 欄位（analytics 餵）。
        **⚠️ 坑**：…price 條件比對的是變體最低價還是任一變體？定死：任一變體，寫進測試…」
     🔴 三處結構性落差，都不是加欄位能補的：
       ①官方已把 manual／smart 標為 **legacy**，新模型是四型來源（products／variants／
         **其他商品系列**／apps）× include/exclude —— 原本的 `rules` JSON ＋ 單一 join 表
         **表達不了後三者**；
       ②`Product tag` 的運算子是 `includes`／`does not include`（**集合運算**），
         與字串類的 `contains` 是不同東西 —— 實作成 `LIKE '%red%'` 會讓 `red` 誤中 `red-new`；
       ③「暢銷」官方定義是**全期**訂單數，原文的「90 天 rollup」是我方自訂且與官方不同（61 §10 C-8）。
     🔴 原文「定死：任一變體」其實**無官方依據**（61 §4.2 ⚠ V-58），本輪改標為我方假設。
     🔴 任何人翻舊版看到「manual/smart 二分法」或「LIKE」都不要改回去。 -->

### F4.1 資料模型：四型來源 × include/exclude

**一個商品系列由若干「來源（source）」組成**（`limits.collection.source_types`）。每個來源有三個正交屬性：**型別**（products／variants／collections／apps）、**模式**（include／exclude）、**選法**（manual／conditions）。

```sql
collections(shop_id, id, title, handle, sort_order, published_at, publish_at,
            template_suffix, seo_title, seo_description, updated_at,
            rebuild_status ENUM('OK','PENDING','ERROR'), rebuilt_at)

collection_sources(
  shop_id, id, collection_id,
  source_type ENUM('products','variants','collections','apps'),
  mode        ENUM('include','exclude'),
  selection   ENUM('manual','conditions'),
  logic       ENUM('all','any') DEFAULT 'all',   -- 該來源**內部**條件的 AND/OR
  app_id      NULL,                              -- 僅 source_type='apps'
  position    INT,
  INDEX (shop_id, collection_id, position),      -- 鐵律 2
  INDEX (shop_id, source_type, mode)             -- 支撐 §F4.5 的 per-shop 上限計數
)

collection_source_members(                       -- selection='manual'
  shop_id, collection_source_id,
  member_type ENUM('product','variant','collection'),
  member_id, position,
  UNIQUE (shop_id, collection_source_id, member_type, member_id)
)

collection_source_rules(                         -- selection='conditions'
  shop_id, collection_source_id, position,
  field    ENUM(…§F4.7 的 17 個值…),
  relation ENUM(…§F4.7…),
  value_text VARCHAR(255) NULL, value_cents BIGINT NULL,   -- 金額一律 R1（鐵律 3／65 §A）
  value_int BIGINT NULL, value_bool BOOLEAN NULL,
  metafield_definition_id NULL,
  UNIQUE (shop_id, collection_source_id, position)
)

collection_memberships(                          -- 物化結果，**前台唯一查詢對象**
  shop_id, collection_id, product_id,
  variant_id NULL,                               -- NULL ＝整個商品；非 NULL ＝ variants 來源
  variant_key BIGINT AS (COALESCE(variant_id, 0)) STORED,   -- 🔴 見下方 MySQL 陷阱
  origin ENUM('manual','conditions','nested_collection','app'),
  origin_source_id, position, rebuilt_at,
  UNIQUE (shop_id, collection_id, product_id, variant_key),
  INDEX (shop_id, collection_id, position)
)
```

🔴 **MySQL 陷阱（`variant_key` 那一行的理由）**：MySQL 的唯一索引把 `NULL` 視為**彼此相異**，所以 `UNIQUE (shop_id, collection_id, product_id, variant_id)` 在 `variant_id IS NULL` 時**擋不住重複列**——同一個商品會被同一個 rebuild 寫進去很多次。必須用產生欄位 `COALESCE(variant_id, 0)` 進唯一索引（同 58 §D.5(b) 對「非終態運單唯一」的處置，MySQL 8 無部分索引的通用解法）。

**四型來源分別是什麼**（61 §4.1 引 help P25）：

| 型別 | include 的意思 | exclude 的意思 | 我方原模型能表達嗎 |
|---|---|---|---|
| `products` | 把商品納入（手動或條件） | **排除特定商品** | ✅ include ／ ❌ exclude |
| `variants` | 把**個別變體**納入 | 排除變體 | ❌ **完全不能** |
| `collections` | 把**另一個商品系列的成員**整批納入 | 整批排除 | ❌ **完全不能**（且帶來遞迴風險，§F4.5） |
| `apps` | 由 app 決定成員 | 排除 app 來源的成員 | ❌ |

### F4.2 求值管線與 include/exclude 的優先順序

```
候選集 = ⋃ 各 include 來源的求值結果          （四型來源各自求值後聯集）
最終集 = 候選集 − ⋃ 各 exclude 來源的求值結果  （exclude 最後套用）
```

**三層優先序**（`limits.collection.source_precedence`）：

| 層 | 規則 | 依據 |
|---|---|---|
| 1（最高） | **exclude 勝過所有 include**（含手動加入） | 🔴 **我方假設**，見下 |
| 2 | **manual include 勝過 conditions** | ✅ **官方明載**：手動加入的商品／變體「除非手動移除，否則永遠留在該商品系列內」（61 §4.1 引 help P23）⇒ 條件重算不得把手動加入的踢出去 |
| 3 | conditions include | — |

> 🔴 **這是我方假設，不是官方事實**（61 §11 登記為 **V-57**）：官方 P25 只說 `Products` 來源可以排除特定商品，**未載明 exclude 與 include／manual 的交互與求值次序**。
> **本規格選定「exclude 最後套用、勝過一切」**，理由是失效方向正確——排除通常出於下架、法遵、地區限制這類「不該賣」的原因，讓它被一條條件覆蓋掉的代價，遠高於少賣一件商品。
> **這個假設做成一個 limits 鍵是刻意的**：官方日後澄清為別的順序時，改的是 `source_precedence` 這一個鍵 ＋ 求值器的排序，**不動任何資料模型**。
> **rebuild 測試必須覆蓋這個假設的三條**：①手動加入 ＋ 明確排除同一商品 ⇒ 不在系列內；②條件命中 ＋ 明確排除 ⇒ 不在系列內；③手動加入 ＋ 條件不命中 ⇒ **仍在系列內**（第 2 層）。

### F4.3 🔴 標籤條件是集合運算，不是子字串

官方對 `Product tag` 用的運算子是 **`包括／不包括`（`includes` / `does not include`）**，與字串類欄位（標題／類型／廠商／變體標題）的 **`包含`（`contains`）是不同的運算子**（61 §4.2 引 help P24）。

**錯誤實作與它的後果**：

```sql
-- ❌ 絕對不可以
WHERE tags LIKE '%red%'      -- 條件 `red` 會誤中 `red-new`、`bright-red`、`tired`
```

**正確的 SQL 形態**：

```sql
-- Product tag includes 'red'
EXISTS (SELECT 1 FROM product_tags pt
        WHERE pt.shop_id = p.shop_id AND pt.product_id = p.id
          AND pt.tag_key = :tag_key)          -- 等值比對，不是 LIKE

-- Product tag does not include 'red'
NOT EXISTS (SELECT 1 FROM product_tags pt
            WHERE pt.shop_id = p.shop_id AND pt.product_id = p.id
              AND pt.tag_key = :tag_key)
```

三條配套（每一條都擋住一個具體的錯法）：

1. **`:tag_key` 是正規化後的鍵**（§F4.4），不是商家在條件輸入框打的原字串。查詢端與寫入端**共用同一支正規化函式**——兩邊各寫一次必然漂移。
2. **多個 tag 條件各自一個 `EXISTS`，不得合併成 `IN (...)`**。`tag_key IN ('red','new')` 的語義是 OR；當來源的 `logic = 'all'`（AND）時這是**錯的答案**，而且在多數資料上看起來還很像對的。
3. **索引**：`product_tags(shop_id, tag_key, product_id)`（給條件求值走）＋ `(shop_id, product_id, tag_key)`（給商品頁列標籤走）。鐵律 2：兩個都以 `shop_id` 開頭。

**字串類欄位的 `contains` 才是子字串**，用 `LIKE`，且 **`%` 與 `_` 必須跳脫**（`limits.collection.string_contains_requires_wildcard_escape`）——商家輸入 `50%` 不跳脫就變成萬用字元，`50%` 會命中 `50X 特惠`。

### F4.4 標籤正規化（寫入前，唯一實作 `Tags::Normalize`）

官方明載：建議只用一般字母、數字與連字號；**特殊字元會被忽略或視為等價**——`red_new`、`red+new`、`red&new` 與 `red-new` **被當成同一個標籤**（61 §1.5 引 help P9）。
不做正規化 ⇒ `product_tags` 會出現兩列，條件比對結果與 Shopify 不一致（61 §10 C-7），而且**從 Shopify 匯入的資料一進來就分裂**。

```
product_tags(shop_id, product_id,
             tag_display VARCHAR(255),                      -- 商家原字串，顯示用
             tag_key     VARCHAR(255) COLLATE utf8mb4_bin)  -- 正規化鍵，比對用
```

**正規化步驟**（`limits.collection.tag_normalize_*`）：

| # | 步驟 | 依據 |
|---|---|---|
| 1 | Unicode **NFKC** 正規化（全形轉半形） | 〔**本專案推導**〕與 13 §F6 的 CSV 全形數字清洗同一族問題 ⇒ ⚠ **V-136** |
| 2 | 去前後空白；內部連續空白壓成單一 `-` | 〔**本專案推導**〕⚠ V-136 |
| 3 | **`_`、`+`、`&` → `-`** | ✅ **官方明載**（P9，四者等價） |
| 4 | 連續 `-` 壓成單一 `-`；去除前後 `-` | 〔**本專案推導**〕⚠ V-136 |
| 5 | Unicode **casefold**（大小寫摺疊） | 〔**本專案推導**〕⚠ V-136——官方未載明標籤是否區分大小寫 |
| 6 | 長度校驗 `limits.product.tag_max_chars`（255）；超過 ⇒ `userErrors{code: TOO_LONG}`，**不截斷** | ✅ 官方值（P9、dev D16） |

- `tag_display` 保留原字串；同一個 `tag_key` 底下**只保留第一次寫入的 display**，後續視為同一標籤、不覆蓋〔本專案推導〕。
- 🔴 **`tag_key` 的 collation 明文宣告 `utf8mb4_bin`，不依賴 schema 預設。** 理由：正規化只有一處實作，**DB 不得再加自己的等價規則**。若沿用預設的 `utf8mb4_0900_ai_ci`，DB 會自己把大小寫與**重音**也視為相同，於是「等價規則」變成兩套（一套在 Ruby、一套在 collation），而且在不同環境的 schema 預設下行為不同。
- 🔴 **遷移**：既有 `product_tags` 需回填 `tag_key`；回填時若兩列正規化後相同 ⇒ **合併並記錄一列稽核**，不得靜默丟掉其中一列（商家會發現商品少了標籤而不知道為什麼）。
- 🔴 **訂單標籤的字元上限是 40，不是 255**（`limits.order.tag_max_chars`）——兩者共用一個常數會讓訂單標籤寫得進本站、匯去 Shopify 時整批被拒。

### F4.5 「其他商品系列」當來源：遞迴風險、環偵測與深度上限

`collections` 型來源會產生**有向圖**，而圖會有環（A 含 B、B 含 A）。環的後果不是資料錯誤，是 **rebuild job 無限遞迴 ⇒ 打爆 worker**。

**(a) 上限（全部進 `limits.collection.*`，規格不寫死數字）**

| 上限 | 鍵 | 出處 |
|---|---|---|
| 每店**內含**另一系列的系列數 | `max_containing_collection_per_shop`（50） | ✅ 官方（help P23） |
| 每店**排除**另一系列的系列數 | `max_excluding_collection_per_shop`（5） | ✅ 官方（help P23） |
| 每店含**變體**的系列數 | `max_with_variants_per_shop`（100） | ✅ 官方（help P23） |
| 每店含**任何條件**的系列數 | `max_smart_collections_per_shop`（5000） | ✅ 官方（help P23） |
| 單一系列的條件總數 | `max_rules_per_collection`（60） | ✅ 官方（help P23、P24） |
| **巢狀深度** | `source_nesting_max_depth`（5） | 🔴 **官方未載明，本專案推導** ⇒ ⚠ **V-135** |

> 深度上限是本專案自訂的理由：官方只給了 per-shop 的**家數**，沒給**深度**。而家數擋不住深度——5 個系列就能串出深度 5 的鏈。每加一層，rebuild 的扇出與失效傳播成本乘一次，且商家無從察覺為什麼系列頁變慢。

**(b) 寫入期環偵測**：新增／修改 `source_type='collections'` 的來源時，在**同一 transaction 內**沿 `collection_sources` 做可達性檢查（自 target 出發能否走回 source）。命中 ⇒ `userErrors{code: CYCLIC_REFERENCE}`（`limits.collection.cycle_detection_error_code`）。

**(c) 🔴 純檢查擋不住併發成環——必須加圖鎖**

> 兩個 transaction 同時寫：T1 加邊 `A→B`、T2 加邊 `B→A`。**兩者各自的可達性檢查都會通過**（檢查時對方的邊還沒 commit），commit 後就成環了。這是典型的「檢查與寫入之間有時間差」的併發缺陷，加索引、加 CHECK 都擋不住。

**唯一擋得住的做法**：以 **shop 粒度的圖鎖**序列化圖的寫入——`collection_graph_locks(shop_id)` 單列表，寫入前 `SELECT ... FOR UPDATE`（`limits.collection.source_graph_lock_table`）。鎖的粒度是「一家店的整張系列圖」，因為環可以由任意兩條邊構成，鎖單一 collection 沒有用。
代價：同一家店的系列來源編輯被序列化。可以接受——這是低頻的後台設定操作，不是結帳路徑。

**(d) 求值期的第二道保險**：`Collections::RebuildJob` 的求值器帶 `visited` 集合與深度計數（`limits.collection.rebuild_cycle_guard`）。重訪或超過深度 ⇒ **中止該系列的 rebuild、標 `rebuild_status = 'ERROR'`、告警，不得部分寫入**。理由：圖鎖擋的是「新產生的環」，擋不住「資料修復、匯入、既有髒資料」帶進來的環。

**(e) 巢狀語義**〔本專案推導，⚠ **V-140**〕：來源系列 B 貢獻給 A 的是 **B 的最終成員**（＝ B 自己的 exclude 套用後的結果），**不是** B 的候選集（`limits.collection.nested_source_uses_final_membership`）。
理由：B 的 exclude 通常代表「這些不該賣」，讓它在被 A 引用時失效，等於排除規則可以被繞過——與 §F4.2 選定 exclude 優先的理由一致。

**(f) 失效傳播**：B 的成員變動 ⇒ 所有引用 B 的系列都要重算。維護反向索引（`collection_sources` 的 `(shop_id, source_type, member_id)`），**逐層向上**傳播並去抖；傳播深度同樣受 `source_nesting_max_depth` 約束。

### F4.6 物化與重算

1. **前台永遠只查 `collection_memberships`**，不即時求值條件。前台查詢再套 `Product.discoverable`（§F1.2 影響面第 7 列）。
2. **增量**：商品建立／更新／狀態變更／標籤變更 → `Collections::ResyncProductJob`（算該商品 vs 全店來源，增量進出）。
3. **全量**：來源或條件變更 → `Collections::RebuildJob`（分批 `in_batches`，**不包大 transaction**，rebuild 期間前台仍讀舊物化列）。
4. **巢狀傳播**：見 §F4.5(f)。
5. 商品刪除／`ARCHIVED` ⇒ 觸發移出所有系列的物化列（成員資格層；`UNLISTED` **不移出**，它只是前台不可見，見 §F1.2(f)）。

### F4.7 條件欄位與運算子值域（補齊 61 §4.2 的四處缺漏）

| 條件欄位 | 運算子 | 我方原狀 |
|---|---|---|
| 商品標題／變體標題／類型／廠商 | 等於／不等於／開頭為／結尾為／**包含**／不包含（字串子字串，`LIKE` ＋ 跳脫） | ✅ |
| **商品類別（Product category）** | 等於／不等於 | 🔴 **原缺** |
| **商品狀態（Product status）** | 等於／不等於（值域＝**四態**，§F1.2） | 🔴 **原缺** |
| 商品標籤 | **包括／不包括**（集合運算，§F4.3） | 🔴 **原本會做錯** |
| 價格／重量／庫存數量 | 等於／不等於／大於／小於 | ✅ |
| **比較價格** | 等於／不等於／大於／小於／**未設定／已設定**（兩個一元運算子） | 🔴 **原缺一元運算子** |
| 中繼欄位（布林／整數／小數／評分／單行文字） | 等於／大於／小於（依型別） | ✅ |
| **Metaobject 參照** | 等於／不等於 | 🔴 **原缺** |

- **邏輯連接只有「符合所有條件（AND）／符合任一條件（OR）」**；官方**未提供**混合 AND/OR 或分組括號（`limits.collection.condition_grouping_supported: false`）。不要自作主張加分組——加了就不是 1:1 對齊，而且匯入 Shopify 時無法表達。
- 🔴 **`Price` / `Weight` / `Inventory stock` 的比對基準＝任一變體**〔**我方假設**〕。原文寫「定死：任一變體」讀起來像官方規則，其實官方 P24 只列運算子、**未定義多變體時的比對基準**（61 §4.2 ⚠ **V-58**）。本輪改標為假設並寫進測試。

### F4.8 排序（`limits.collection.sort_orders`，九種）

| 排序 | 定義 | 備註 |
|---|---|---|
| 最相關（most relevant） | 依銷售表現 | 🔴 **我方原缺**（P26） |
| **最暢銷（best selling）** | **全期訂單數**（`limits.collection.best_selling_window: all_time`） | 🔴 **修正**：原文寫「90 天銷量 rollup」＝我方自訂且與官方不同（61 §10 C-8）。鐵律 7 下，系列頁與分析頁用兩套窗口會直接露餡 |
| 字母 A-Z／Z-A | — | 🔴 **我方原缺**（P26） |
| 價格由高到低／由低到高 | 見 63 §G.6：**有 fixed price 的市場不能用物化欄排序** | 多市場的要害 |
| 日期由新到舊／由舊到新 | — | ✅ |
| 手動 | 拖曳，或「移到最前／移到最後／移到指定位置」（`limits.collection.manual_move_actions`） | ✅ 補齊三個移動操作 |

### F4.9 ⚠️ 坑

- rebuild 大系列時**不能鎖住前台** → 分批寫 ＋ 不包大 transaction（前台讀舊物化列直到批次寫完）。
- **規則求值與前台查詢的語意必須完全一致**——同一條件在 rebuild 時用 Ruby 求值、在前台用 SQL 求值，兩套實作必然漂移。做法：**只有 SQL 一套**，rebuild 也走 SQL（`INSERT ... SELECT`）。
- 商品刪除／`ARCHIVED` 要觸發移出所有系列（§F4.6-5）。
- **`exclude` 來源為空時不等於「沒有 exclude」**——一個 `mode='exclude'` 但成員為空的來源，求值結果是空集合，減掉空集合等於不變。不要把「空 exclude 來源」誤判成「該系列不設限」而在 UI 上隱藏它，商家會以為排除設定不見了。
- 系列的**前台可見性**與**掛不掛在選單上**是兩件事（P26 官方特別提醒）——UI 不要把兩者做成一個開關。

## F5. 庫存帳（ledger）與調整

**生產級做法**：
1. 模型照 06：`inventory_levels`（**available / committed / unavailable / incoming 四欄 ＋ unavailable 子分類明細表**，見 F5.1）+ `inventory_adjustments`（append-only ledger：delta、**from_state / to_state**、reason、reference、actor）。
   <!-- 依 46c:891–927、06:111、44:150 修正，原文：官方頂層五態＝現有/可販售/已分配/不可販售/待入庫，`不可販售` 底下四子分類（損壞/品質控管/安全庫存/其他），`待入庫不計入現有`。
        🔴 此處原本寫錯：13:59 原寫「`inventory_levels`（available/committed 兩欄起步）」——與 06:111 的恆等式和 44:150 的實測四欄對不上，
        草稿單保留庫存（46c:546–549 逐字「進 Unavailable，不是 Committed」）與「待收退貨品項」（46c:296）皆無處可存 → 恆等式恆不成立、nightly 對帳永遠告警、且會超賣。
        任何人翻舊版看到「兩欄起步」都不要改回去。 -->
2. 一切變動走 `Inventory::Adjust` service（條件式 UPDATE + ledger 同 transaction）；**任何地方不准直接 `update(available:)`**（rubocop 自訂 cop 掃）。
3. 對帳工具：rake task 重放 ledger 驗證 `SUM(delta) == 現值`，nightly 跑、不一致告警——這是庫存系統的黑盒測試。
4. 售罄可續賣（policy CONTINUE）時 available 允許負數；前台顯示「缺貨」但可下單（明確文案）。
5. 低庫存（≤ 閾值）事件進 outbox → 後台通知（P1）。

**代碼**：

```ruby
class Inventory::Adjust
  def call(level_id:, delta:, reason:, ref: nil, allow_negative: false)
    guard = allow_negative ? "" : "AND available + ? >= 0"
    rows = InventoryLevel.where(id: level_id)
             .where("1=1 #{guard}", *([delta] unless allow_negative))
             .update_all(["available = available + ?, updated_at = NOW()", delta])
    raise InsufficientStock if rows.zero?
    InventoryAdjustment.create!(inventory_level_id: level_id, delta:, reason:, reference: ref, staff_id: Current.staff&.id)
  end
end
```

**⚠️ 坑**：
- ledger 與數量更新不同 transaction → 對不上帳；必須同交易。
- 退款 restock 重複觸發（webhook 重放/重複點擊）→ restock 以 refund_line_item id 冪等（唯一索引 `refund_line_item_id`）。
- 訂單取消 vs 出貨的競態：取消動作要先搶 fulfillment_order 狀態（條件式 UPDATE status='open'→'cancelled'），搶不到就報「已出貨不可取消」。
- committed 只能由訂單流程動（下單+、出貨−、取消−），後台手動調整只准動 available——UI 直接不給入口。

### F5.1 庫存頂層五態與 unavailable 子分類（P0-15）

> <!-- 依 46c:891–927 補寫（H18/H19/H20 zh-TW＋en 逐字），並與 06 §5 恆等式、44:150 實測四欄對齊 -->

**(a) 頂層五態（`limits.inventory.top_level_states`）**

| 狀態 | zh-TW 官方用詞 | 定義（46c:891–907 逐字節錄） | 落庫方式 |
|---|---|---|---|
| `on_hand` | 現有庫存 | 「由已分配、不可販售與可販售庫存的總和組成」 | **derived，不落庫**（避免雙寫漂移） |
| `available` | 可販售 | 「不會分配至任何訂單，也不會保留給任何訂單草稿；不包含被視為待入庫的庫存」 | `inventory_levels.available` |
| `committed` | 已分配 | 「已納入訂單但尚未履行的單位數。**若單位屬於訂單草稿…在該草稿轉為訂單之前，不會計入已分配庫存**」 | `inventory_levels.committed` |
| `unavailable` | 不可販售 | 「因訂單草稿保留、由 app 保留，或其他擱置原因而被保留的單位數」 | `inventory_levels.unavailable` ＋ 子分類明細表 |
| `incoming` | 待入庫 | 「從庫存轉移或 app 正在運送至您地點的庫存」 | `inventory_levels.incoming`，**不計入 on_hand** |

**(b) 恆等式（nightly 對帳 job 的斷言，與 06 §5 一致）**

```
on_hand  = available + committed + unavailable          # incoming 不在其中
unavailable = Σ inventory_unavailable_buckets.quantity  # 子分類加總必須等於彙總欄
incoming    獨立計（在途，不入 on_hand）
```

**(c) `unavailable` 的子分類（`limits.inventory.unavailable_subtypes`）**
`damaged`（損壞）／`quality_control`（品質控管）／`safety_stock`（安全庫存）／**`draft_reserved`（訂單草稿保留）**／`app_reserved`（app 保留）／`other`（其他）。
表：`inventory_unavailable_buckets(shop_id, inventory_level_id, subtype, quantity)`，唯一索引 `(inventory_level_id, subtype)`。
> 46c:925–927 官方列四子分類（損壞/品質控管/安全庫存/其他）；`draft_reserved` 與 `app_reserved` 由 46c:891–907 的 `Unavailable` 定義逐字導出（「因訂單草稿保留、由 app 保留」），拆出獨立 bucket 是為了讓草稿到期回補可精準定位。

**(d) 狀態間移動（每一筆都寫 ledger，帶 `from_state` / `to_state`）**

| 事件 | 移動 | reason |
|---|---|---|
| 訂單成立 | `available → committed` | `order_created` |
| 出貨 | `committed → 出庫`（on_hand 隨之減少） | `fulfillment` |
| 取消訂單（restock:true） | `committed → available` | `order_cancelled` |
| **訂單草稿保留庫存** | **`available → unavailable[draft_reserved]`**（**不是 committed**） | `draft_reservation` |
| 草稿轉正式訂單 | `unavailable[draft_reserved] → committed` | `draft_converted` |
| 草稿保留到期 | `unavailable[draft_reserved] → available` | `reservation_expired` |
| 建立退貨（待收退貨品項） | **不動任何數量**（僅標記），退貨處理時才進 `available` | `return_created`（delta = 0 的標記事件） |
| 退貨處理 disposition = RESTOCKED | `→ available`（選重新入庫地點） | `return_restock` |
| 標記損壞/品管/安全庫存 | `available ⇄ unavailable[子分類]` | 對應 reason |
| 庫存轉移建立／收貨 | `→ incoming` ／ `incoming → available` | `transfer_created` / `received` |

<!-- 依 46c:546–549、46c:895 修正，原文：「訂單草稿保留庫存 → 進 Unavailable 狀態（不是 Committed）；草稿單位在轉正式訂單前不計入 Committed」 -->
<!-- 依 46c:296、46c:330 補寫，原文：「建立退貨當下庫存不變，品項標記『待收退貨品項』；處理時才選重新入庫地點」 -->

**(e) 編輯連動規則**（46c:594–595、46c:909–911 逐字）
- 編輯 **現有庫存（on_hand）** → **可販售等量變動**（因為 on_hand 是 derived，實作上是改 `available`）。
- 編輯 **可販售（available）** → **現有庫存等量變動**（自然成立）。
- **後台不得直接編輯 `committed`**（只能由訂單流程驅動）——UI 不給入口。

**(f) 調整原因七項（`limits.inventory.adjustment_reasons`，第一項為預設）**
`correction`（更正，預設）／`count`（盤點）／`received`（已收件）／`return_restock`（退貨重新入庫）／`damaged`（損壞）／`theft_or_loss`（遭竊或遺失）／`promotion_or_donation`（促銷或捐贈）。
> <!-- 依 46c:608–617 修正，原文：官方七項清單。我方原本兩處清單不同且不完整——28:63 的枚舉含官方沒有的 `sold`（已移除，出庫由 fulfillment 事件表達，不是調整原因）。 -->

**(g) 調整記錄事件型別**：手動 7 種（＝(f) 七原因）＋ 系統 6 種（訂單成立/出貨/取消/退貨入庫/轉移收貨/草稿保留）＋ **狀態間移動型**（如「移至安全庫存」）。ledger 的 `from_state`/`to_state` 就是為此而設。保留 `limits.inventory.adjustment_history_retention_days`（180 天）。

## F6. CSV 匯入/匯出

**生產級做法**：
1. 匯入：上傳 → job 逐行處理（`in_batches`、每行獨立 transaction）→ 產出逐行結果報告（成功/失敗+原因）→ 完成通知；欄位對齊 Shopify CSV 格式（遷移友好）。
2. 大檔 streaming parse（CSV.foreach）不整檔載入；上限 5 萬行、超過拒收提示分割。
3. 匯出：`find_each` streaming 寫檔 → Active Storage → 簽名下載連結，過期 24h。
4. 語意：以 handle upsert（存在→更新、不存在→建立）；dry-run 模式先驗證不寫入。

**⚠️ 坑**：Excel 存的 CSV 常帶 BOM 與 Big5/CP950 編碼 → 讀檔先偵測 BOM、強制轉 UTF-8、失敗行報「編碼錯誤」而不是整檔炸；數字欄位的「1,299」千分位與全形數字要清洗；匯入不是即時的——UI 明確顯示背景任務進度（polling job 狀態），不要讓人重複上傳。

## 本篇新增的待查證（V-135 起）

> 沿用 52 §附錄 A 的規則：**無明確出處一律不自補規則；當前處置一律是保守失效**。
> V-130～V-134 在 `docs/specs/65`（金額單位邊界）；V-50～V-70 在 `docs/research/61` §11，其中
> **V-57**（exclude 與 include 的優先序）、**V-58**（Price/Weight/Inventory 的比對基準）、
> **V-59**（單一系列可手動加入的商品數）三條由本篇引用並選定處置，**未結案**。

| # | 待查證項目 | 為什麼查不到 | 當前處置 | 影響 |
|---|---|---|---|---|
| **V-135** | 巢狀商品系列的**深度上限**官方值 | help P23 只給了 per-shop 的家數（內含 50／排除 5），未給深度 | `limits.collection.source_nesting_max_depth: 5`〔本專案推導〕；求值期第二道保險照跑 | §F4.5 |
| **V-136** | **標籤正規化的完整規則**：官方只明載 `_` `+` `&` 與 `-` 等價，未載明是否區分**大小寫**、是否做 Unicode 正規化、連續分隔符如何處理 | help P9 只給了四者等價的例子，未給規則本身 | 依 §F4.4 六步實作，第 1／2／4／5 步標為本專案推導；**正規化函式集中一處**，日後若官方澄清，改一支函式 ＋ 一次 `tag_key` 回填 | §F4.4 |
| **V-137** | `ARCHIVED` 商品的直接 URL 應回 **404 還是 410** | 官方只說「顧客在任何管道都取用不到」，未載明 HTTP 狀態碼 | 先回 404（與 DRAFT 一致，行為單純）；410 列為日後最佳化 | §F1.2(a) |
| **V-138** | `UNLISTED` 商品是否應輸出 Product／Offer **JSON-LD** | 官方只載明 `noindex,nofollow` 與排除於 sitemap，未提結構化資料 | **不輸出**〔本專案推導〕：noindex 頁面提供 rich-result 標記自相矛盾，且會讓 AI 代理當成可推薦商品 | §F1.2(e) 第 4 列 |
| **V-139** | 商品系列的**成員資格**是否納入 `UNLISTED`／`DRAFT`（官方說「UNLISTED 不進商品系列」指的是前台顯示還是連成員都不算？） | 官方 D4 的措辭未區分這兩層；而 P24 又把 `Product status` 列為可用的條件欄位，暗示非 ACTIVE 商品**可以**是成員 | 成員資格不過濾 status、前台再套 `discoverable`（§F1.2(f)）；後台列表標注「（前台可見 N）」 | §F1.2(f)、§F4.6 |
| **V-140** | 巢狀來源取的是被引用系列的**最終成員**還是**候選集**（後者會讓被引用系列的 exclude 失效） | help P25 只說可以把另一個系列當來源，未定義求值語義 | 取**最終成員**〔本專案推導〕，與 §F4.2 選定 exclude 優先同一理由 | §F4.5(e) |

## 本篇驗收（對照 11 §0）

**既有項**：變體 diff 更新不破壞歷史訂單；ledger 對帳 task 連續 7 天 0 差異；併發加購 100 執行緒不超賣（測試腳本）；上傳 60MP 圖被拒；商品系列 10k 商品 rebuild <60s 且前台無感；CSV 匯入 1 萬行報告逐行可讀；富文本 XSS payload 全數被消毒（測試集跑過）。

**本輪新增（§F1.2 商品狀態）**：

1. **四態 × 兩 scope 的真值表逐格有測試**（8 列全覆蓋），且 `UNLISTED` 那兩列是必測——它們是唯一「兩維不同步」的格子。
2. **不變量 `discoverable ⊆ purchasable`** 以 property test 斷言（隨機生成 status × 發布狀態組合）。
3. `UNLISTED` 商品：sitemap／搜尋索引／feed／**代理 catalog**／JSON-LD 五處**均查無**該商品；同時 `/cart/add.js` 對它**成功**。**五處只要有一處漏，這條就是紅的。**
4. 變體級發布：父商品已發布、變體未發布 ⇒ 該變體在前台**不出現**，且 `products.min_price_cents` **不含**它的價格。
5. `ACTIVE → UNLISTED` 轉換：觸發搜尋索引移除 ＋ IndexNow ping；**購物車內既有品項仍可結帳**。
6. 全庫 grep `Product.published` **命中數為 0**（§F1.2(h)：直接刪除，不留別名）。

**本輪新增（§F4 商品系列）**：

7. **標籤條件不是子字串**：建立條件 `tag includes "red"`，商品 A 標籤 `red`、商品 B 標籤 `red-new` ⇒ **只有 A 入列**。這條是 §F4.3 的直接斷言，紅了就是有人寫了 `LIKE`。
8. **標籤等價**：以 `red_new` / `red+new` / `red&new` / `red-new` 四種寫法寫入 ⇒ `product_tags` 只有**一列**，且四種寫法的條件都命中。
9. **優先序假設**（§F4.2 三條）：手動＋排除 ⇒ 不在；條件命中＋排除 ⇒ 不在；手動＋條件不命中 ⇒ **仍在**。
10. **環偵測**：A 含 B 後再讓 B 含 A ⇒ `CYCLIC_REFERENCE`；**併發版本**——兩執行緒同時各加一條邊，結束後圖中無環（證明圖鎖有效，光靠可達性檢查這條會紅）。
11. **深度上限**：建構深度 = `source_nesting_max_depth + 1` 的鏈 ⇒ 寫入被拒；既有髒資料造出的超深鏈 ⇒ rebuild 標 `ERROR` 並告警，**且無部分寫入**。
12. **exclude 傳播**：B 排除商品 X，A 以 B 為來源 ⇒ X **不在** A 內（§F4.5(e)）。
13. `collection_memberships` 的唯一索引在 `variant_id IS NULL` 時**確實擋住重複**（連跑兩次 rebuild，列數不變）——這條專門測 §F4.1 的 MySQL NULL 陷阱。
