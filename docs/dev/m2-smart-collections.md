# M2：智慧系列求值引擎與最小地基（第 11 包，D50 案 A）

> 規格：`docs/specs/13-spec-products-inventory-media.md` §F4（本 PR 一併回寫 §F4.1 過時
> schema 塊與 V-58 結案）｜值域正典：`docs/research/95-enum-domains.md` §1｜
> 裁定：`docs/DECISIONS.md` **D50**（案 A：包 11 連最小地基一起交付）
> 計畫列：`docs/plans/2026-08-24-第20-37包整合執行規格.md` 第 11 包工作卡
> 配對 worklog：`docs/worklog/2026-08-25-第11包智慧系列引擎.md`

## 0. 一句話

商家設條件（「標籤含夏季、價格低於 200」），商品自動進出系列。本包交付：四張表
（sources／typed rules／memberships／product_tags）＋ SQL-only 求值引擎（編譯器＋
全量 rebuild＋增量 resync）＋ rules 契約（GraphQL）＋三處成員數收斂＋觸發鏈
（outbox 消費者）。**規則編輯器 UI 不在本包**（工作卡明文：包 11 只做引擎與契約）。

## 1. v1 射程（值域表；三處同步的那一份）

| 條件型別（snake_case） | relation | 值欄 | SQL 形態 |
|---|---|---|---|
| product_title／product_type／product_vendor | eq／not_eq／starts_with／ends_with／contains／not_contains | value_text | products 欄位直比；contains＝LIKE（`sanitize_sql_like` 跳脫 `%`／`_`；值 ≥3 字元）；🔴 **not_eq／not_contains 帶 `OR IS NULL`**（2026-08-26 審查 F1：可空欄的三值邏輯把未設定商品靜默剔除，而 tag 的 does_not_include 卻納入無標籤商品——空值語義統一為「未設定＝不是那個值」） |
| variant_title | 同上 | value_text | EXISTS 變體 |
| product_tag | includes／does_not_include | value_text（比對用 `Tags::Normalize.key`） | `tag_key` 等值 EXISTS——🔴 **禁 LIKE**（`red` 誤中 `red-new`）；多條件各自 EXISTS，🔴 **禁併 IN**（IN＝OR） |
| product_status | eq／not_eq | value_text（四態） | p.status 直比 |
| variant_price／variant_compare_at_price | eq／not_eq／gt／lt | **value_cents**（鐵律 3） | EXISTS 變體（任一變體——V-58 已結案的官方語義） |
| variant_compare_at_price | 另有 is_set／is_not_set | 無值 | 🔴 is_set＝**ALL variants**（官方逐字 "all variants must have a compare-at price value (including 0)"）＝NOT EXISTS 缺值變體＋至少一變體；is_not_set＝any-variant EXISTS 缺值 |
| variant_weight | eq／not_eq／gt／lt | value_int（克） | EXISTS 變體 |
| variant_inventory | eq／not_eq／gt／lt | value_int | EXISTS 變體，其跨倉 SUM(inventory_levels.available) 比對 |
| collection（**僅 exclusion**） | includes | value_int＝被引系列 id | 減去該系列 `collection_memberships` 的**最終成員**（V-140） |

**exclusion 區塊 v1 支援**：product_tag／product_type／product_vendor／collection
（canon 6 型中 product_category 不支援——無 taxonomy 樹）。
**canon 19 型中 v1 不支援**（寫入層拒收 INVALID）：metafield 七型、product_category、
unknown（passthrough 存欄就位、寫入白名單暫不放行——見 §5 延後項）。

🔴 **三處同步**：本表 ↔ `Collections::RuleCompiler` 常數 ↔ `SaveCollection` 白名單。
加型別＝三處一起動（RELATIONS tripwire spec 盯著鍵集合）。

## 2. 資料模型（migration 20260826058000）

- `collection_sources`：兩型（conditions／sub_collections）；include/exclude 是**區塊**
  不是極性（95 §1.1 的 2026-08-24 修正——四型×極性是 UI 形態不是資料模型）。
  `shareable` 欄就位、語義未取證（登記）。
- `collection_source_rules`：typed value（金額唯 value_cents）；`block` 欄＋寫入層
  per-block 白名單（單一 ENUM 表達不了「哪個區塊有哪些型別」）；`raw_payload` 為
  unknown passthrough 載體。
- `collection_memberships`：物化成員＝**前台唯一查詢對象**。🔴 `variant_key`
  產生欄（COALESCE(variant_id,0)）擋 MySQL 唯一索引的 NULL 陷阱（13 §F4.1）。
- `product_tags`：`tag_display`（顯示）＋`tag_key`（比對；collation **utf8mb4_bin** 明文
  ——DB 不得疊自己的等價規則）。寫入面＝`SaveProduct#sync_product_tags!`（同 tx diff）
  ＋migration 回填（正式環境 3 筆帶標籤商品，2026-08-25 實查）。
- `collections` ＋ `rebuild_status`（OK／PENDING／ERROR；NULL＝從未 rebuild）＋`rebuilt_at`。
- **未建**：`collection_source_members`（sources 模型的手選；手動系列仍走
  collection_products，遷入屬 UI 包）；`collection_graph_locks`（深度上限 1 之下不必建
  ——limits `source_nesting_max_depth` 修正註）。

## 3. 引擎（SQL-only；13 §F4.9「只有 SQL 一套」）

- `RuleCompiler.where_sql(source)` ⇒ products（別名 p）上的 WHERE 片段。
  注入安全兩軸：值一律 `sanitize_sql_array` 綁定；識別字只來自 frozen 常數表，
  查表 miss ⇒ `Unsupported`（fail-closed）。
- **求值公式**＝`⋃ₛ ( inclusion(s) − exclusion(s) )`（per-source 相減；
  `membership_formula`）。13 §F4.2 列三條必測，`engine_spec.rb` 釘住其中**兩條**：
  「同一來源內條件命中＋明確排除 ⇒ 不在」與關鍵的「A 排除 X＋B 包含 X ⇒ X 仍在」。
  🔴 第三條（**手動加入**＋明確排除 ⇒ 不在）在 v1 **結構上測不了**：手選成員需要
  `collection_source_members`，而該表 §2 已登記「未建」⇒ 登記為 P11-B11，隨手選成員
  的包一併補測。（2026-08-26 收斂輪 H8：原文寫「三條必測全在」是缺證的完成性聲明。）
- `Rebuild`：🔴 **整場先拿 advisory lock**（`GET_LOCK('chilllove:rebuild:<shop>:<collection>')`，
  等待預算 `rebuild_lock_wait_seconds`；2026-08-26 審查 F2——逐批列鎖不序列化整場，
  兩場同系列 rebuild 交錯時小世代覆蓋現任列＋大世代掃尾＝**整組成員被清空**，
  gated-threads 實跑重現）；等不到＝讓位，`RebuildJob` 延後重排（`rebuild_lock_requeue_delay_seconds`）。
  之後：世代戳＋id 批（`rebuild_batch_size`）＋逐批短 txn（`Collection.lock`）＋
  `INSERT…SELECT…ON DUPLICATE KEY UPDATE rebuilt_at = GREATEST(COALESCE(rebuilt_at, 世代), 世代)`
  （🔴 `COALESCE` 不可省：`rebuilt_at` 可空而 MySQL `GREATEST(NULL, x)` 回 NULL ⇒
  NULL 戳的列會變成「再也蓋不上戳、也掃不掉」的不死列；掃尾同理必須顯式收 `IS NULL`）
  （單調帶——即使鎖被繞過，舊世代也降不了現任列的戳）＋世代掃尾。
  🔴 變更判定＝`created_at >= generation`（新列）＋swept>0——**不是** affected_rows
  （ON DUPLICATE 對既有列每輪記 2 ⇒ 拿它判會讓零變更的 rebuild 白打快取，初版實測踩到）。
  編不了（unknown／unsupported）⇒ 整系列 ERROR、零寫入。
- `ResyncProduct`：同一段 WHERE ＋ `p.id = ?` 的單商品判定；逐系列短 txn ＋
  `Collection.lock`（序列化點——與規則編輯、rebuild 同一把鎖；鎖定讀讀最新已提交規則，
  REPEATABLE READ 快照陷阱的解法同 handle_change.rb）。ARCHIVED／刪除 ⇒ 移出；
  🔴 UNLISTED **不**移出（前台不可見≠不是成員，13 §F1.2(f)）。ERROR 系列跳過。
- 🔴 `Rebuild.call` 的回傳有**兩種** `:skipped`：`error: nil`＝該系列沒有 conditions
  source（正常）；`error: LOCK_TIMEOUT_ERROR`＝鎖等逾時、這一輪沒重建。**消費者必須分辨**
  ——`RebuildJob` 延後重排、`catalog:rebuild:collections` 單獨計數並非零結束
  （2026-08-26 delta 審查 F6：兜底靜默回報成功＝fail-open；守衛在
  `spec/lib/tasks/catalog_rebuild_spec.rb`）。
- 成員變動的對外面（一處實作 `Rebuild.notify_members_changed!`）：
  `CacheStamps.bump_collection_members!`（collections.products_updated_at）＋
  outbox `collections/update`（blueprint D.4；鐵律 5）。

## 4. 觸發鏈（P11-U17 的 ours 裁定；官方時機未取得 P11-U3）

`productSet`／庫存調整 → outbox（PRODUCTS_CREATE／PRODUCTS_UPDATE／INVENTORY_ADJUSTED）
→ `Events::Consumers` → `Collections::ResyncConsumer` → `ResyncProduct`。
規則編輯 → `SaveCollection#replace_sources!`（txn 內，標 PENDING）→ commit 後
`RebuildJob.perform_later`（只帶 id，執行時重讀當前規則）。
rake：`catalog:rebuild:collections`（`projection_rebuild_tasks` 的既有名額）。
代價＝秒級最終一致窗（Relay 輪詢節奏）；本尊 help 亦有 "delay products displaying in
collections on your storefront" 的旁證（P11-U3 直取未複驗）。

## 5. 已知邊界與延後項（誠實登記）

| # | 內容 |
|---|---|
| P11-B1 | **sub_collections 來源整型延後**（寫入層拒收）：深度 1 判定、SELF/CHAIN_REFERENCE 謂詞、反向傳播——13 §F4.5 的機制屬後續包。schema 欄位已就位 |
| P11-B2 | **variants 目標延後**：memberships.variant_id 恆 NULL；per-variant 納入屬後續包 |
| P11-B3 | **exclusion 的 collection 型引用手動系列時讀不到成員**（讀 memberships，手動系列的成員在 collection_products）——v1 已知邊界，engine_spec 有敘事錨；解法＝手動系列也物化（UI 包遷移時一併） |
| P11-B4 | **unknown passthrough 存欄就位、寫入白名單暫不放行**：v1 的 admin 契約拒收未知型別（商家打錯字≠向前相容）；passthrough 的進入面是日後的匯入／新版 API。引擎遇 unknown 列 ⇒ 整系列 ERROR（不靜默放寬/收窄） |
| P11-B5 | **排序未動**：sort_orders 九值與 `Collection::SORT_ORDERS` 八值硬編的三份打架（研究 §9-6）屬包 8（不回補名單）；memberships.position 恆 0，前台排序屬 30/33 |
| P11-B6 | **60 條上限口徑＝per-collection**（fail-closed；per-source 未實測＝P11-U18） |
| P11-B7 | **`shareable` 語義未取證**（95 §1.1 記載維度存在；欄就位不寫） |
| P11-B8 | 智慧系列命中數即時預覽（Add condition 旁的數字）＝UI 包（工作卡明文） |
| P11-B9 | resync 觸發面缺口：變體子頁（第 29 包）的獨立變體更新是否經 PRODUCTS_UPDATE ——**未驗證**；若否，價格條件的增量觸發漏一面（rake rebuild 兜底） |

**P11-B10（2026-08-26 收斂輪 G4 的殘留面）**：exclusion 的 `collection` 型讓系列 A 的
成員資格依賴系列 B 的物化列。`ResyncProduct` 已加第二趟（先算全部、再重算「引用了
其他系列」的那些），單向引用因此在一次事件內收斂；**互相引用**（A 排除 B ∧ B 排除 A）
需要不動點迭代，兩趟不保證收斂——該格由 `catalog:rebuild:collections` 兜底，
且 `config/recurring.yml` 目前**沒有**排這支（要排程屬 CD 包）。

**P11-B11（2026-08-26 收斂輪 H8）**：13 §F4.2 的第三條必測（手動加入＋明確排除）
在 v1 無載體可測（`collection_source_members` 未建）⇒ 隨手選成員的包補測，不得再宣稱
「三條全在」。

## 6. 三處成員數收斂（工作卡驗收項）

`Collection::MEMBER_COUNT_SELECT`（CASE by type）／GraphQL `products_count`
（smart＝memberships 計數，**未成功 rebuild 回 null**——「未求值」≠0）／前端 `—` 分支
語義更新。鐵律 7：三處同一來源（物化表）。

## 7. 寫入契約狀態矩陣（鐵律 17.4 的收斂交付物）

🔴 **這張表存在的理由**：本包三輪對抗審查共確認 10 條 finding，其中 **8 條是同一形態**
——「修法只封了被點名的那幾格，同一方法裡的鄰居欄位或同一契約的下游消費者沒跟上」。
逐格列出來，是為了讓下一個改 `SaveCollection` 的人**先看見整張表再動手**，
而不是改完一格再等審查告訴他還有九格。

判準＝`CollectionSetInput` 檔頭宣告的「缺席＝保持現值、空字串／空陣列＝清除」。

| 欄位 | 缺席(nil) | 顯式空值("" / []) | create 預設 | 守衛在哪 |
| --- | --- | --- | --- | --- |
| `title` | ⚠️ **BLANK 錯誤**（非保持現值） | BLANK 錯誤 | 必填 | 與 `SaveProduct` 逐字同款 ⇒ 家族一致的既有行為，本包不單方面改；⚪ 登記 `91` §3.16 |
| `description_html` | 保持現值 | 清除 | `""` | `normalize` 的 `.nil?` 分支＋update 的 `\|\|`；上限走 `product.description_max_bytes` ⇒ TOO_BIG |
| `handle` | 保持現值 | 保持現值（`.presence`） | 由標題生成 | `handle_changed` 判斷；改名同 txn 落 301 |
| `collection_type` | 保持現值 | — | `manual` | 🔴 **建立後不可變**：update 帶不同值＝INVALID（本尊官方語義） |
| `sort_order` | 保持現值 | — | `manual` | update 的 `\|\| collection.sort_order` |
| `seo.title` / `seo.description` | 保持現值（鍵不進 attributes） | 清除（`.presence` → nil） | 無 | `seo_attributes` 的兩個 `unless .nil?`；`seo` 整個缺席 ⇒ `return {}` |
| `product_ids` | 保持現值 | 全部移除 | 無 | `sync_members!` 的 `return if nil`；**只對 manual 生效** |
| `sources` | 保持現值 | 🔴 清除**且**物化成員被掃尾回收 | 無 | `replace_sources!` 的 `return if nil`＋`Rebuild` 對零 source 的智慧系列照樣掃尾（收斂輪 G1） |
| `translations` | 不寫任何譯文＝保持現值 | 同左 | 無 | `Array(input[:translations])` → prepare 空集合 |

**消費者影響圖**（改動下列任一生產者時，這一欄就是必須同步的清單）：

| 生產者 | 消費者 |
| --- | --- |
| `Rebuild::Result`（status／error） | `RebuildJob`（逾時延後重排）、`catalog:rebuild:collections`（`contended` 計數）、engine/rake spec |
| `collection_type` 不可變契約 | `collectionSet` mutation、**admin `CollectionDetailPage`**（下拉停用＋payload 條件化）、`m1-collections.md` |
| `RuleCompiler.where_sql` | `Rebuild`（`INSERT…SELECT`）、`ResyncProduct`（同段 WHERE ＋ `p.id = ?`）——兩者必須永遠是同一段 |
| `collection_memberships` 列 | 前台（唯一查詢對象）、`Collection::MEMBER_COUNT_SELECT`、`CollectionType#products_count`、🔴 `RuleCompiler#compile_collection_exclusion`（**別的系列**讀它） |
| 智慧系列的工作清單 | `ResyncProduct#smart_collection_ids`、`catalog.rake` ——🔴 兩者都必須是「全部智慧系列」，**不得**從 `collection_sources` 導出（收斂輪 G1） |

## 8. 驗證

```bash
bundle exec rspec spec/services/collections spec/services/tags spec/requests/smart_collections_spec.rb
```

突變表＝worklog；含「per-source 相減改全域」「tag EXISTS 改 LIKE」「is_set 改 any-variant」
「變更判定改 affected_rows」等語義級突變。
