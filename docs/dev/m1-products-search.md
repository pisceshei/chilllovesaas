# m1 — 商品伺服器端搜尋與篩選（排程第 1 包）

> 依據：`docs/research/28` §1（`products(first, query, sortKey)` 契約與搜尋語法）；
> `docs/research/22` §1（白名單欄位編譯 SQL 防注入）；
> `docs/plans/2026-08-24-三方向執行順序.md` 塊 A 第 1 包。
> 本尊語法邊界取證 2026-08-24：shopify.dev/docs/api/usage/search-syntax
> （AND/OR、`-`/`NOT` 否定、隱含 AND、五個比較運算子、`*` 萬用、括號分組）。

## 1. 這是什麼

`products(query: String)` 參數 ＋ `Products::SearchScope`（白名單語法子集 → Arel 條件），
前端商品列表的搜尋框改打伺服器、新增狀態篩選下拉。

**修掉的現存缺陷**：舊版是前端對已載入的一頁（50 筆）做記憶體過濾——第 51 筆之後的
關鍵字永遠搜不到；且過濾邏輯引用的 `vendor`／`productType` 根本沒被 query 選取（恆 undefined），
等於只有 title 真的在被搜。

## 2. 值域（v1 支援）

| 語法 | 語義 |
|---|---|
| 裸詞／引號片語（單雙皆可） | `title` CONTAINS；多詞 **AND**（本尊「未指定連接詞＝AND」） |
| `status:<v>` | 等值；值域＝`Product::STATUSES`（大小寫不敏感）；**非法值 ⇒ 整查詢空集**（回錯資料比回空集糟，且 products query 沒有 userErrors 通道） |
| `vendor:<v>`／`product_type:<v>` | 等值（`utf8mb4_0900_ai_ci` ⇒ `=` 天然大小寫不敏感） |
| 未知 prefix（如 `tag:red`） | **整個 token 當字面文字**對 title 搜尋——不猜、不半支援 |

同欄位出現兩次＝AND（本尊語義：`orders_count:>16 orders_count:<=30`）⇒ `status:active status:draft` 恆空。

前端狀態下拉＝**四值全列**（ACTIVE／DRAFT／ARCHIVED／UNLISTED，值域窮舉），
選取後組成 `status:<小寫>` 併入 query 送出；300ms 去抖。

## 3. 怎麼做（含兩個防呆）

- token 化 → 逐條 AND 進 Arel；**不用字串內插組 SQL**（Brakeman fail-closed；keyset 前例）。
- 🔴 **LIKE 的 `%`／`_` 經 `sanitize_sql_like` 跳脫**——商品標題本身就可能含 `%`（「100% cotton」），
  不跳脫則使用者輸入 `0%` 萬用匹配整表。守衛已做突變驗證（移除跳脫 ⇒ spec 轉紅）。
- 空態分流：**店空**（無商品、無條件）與**查無**（有條件、零結果）是兩個不同的真相，
  各自有各自的空態；「清除搜尋」同時清 status 篩選。

## 4. 跨功能影響

- 與 `Products::KeysetConnection` 組合：filter 先於 cursor 套用，同一 query 跨頁傳遞時 keyset 語義不變。
- `PRODUCTS_QUERY` 補選 `vendor`／`productType` ⇒ 列表「類型」「廠商」兩欄從恆「—」變真值。
  「庫存」欄仍顯示未追蹤——`totalInventory` 屬排程第 16 包（需庫存後端），本包不碰。
- **`sortKey` 刻意不在本包**：keyset 的排序鍵一般化屬排程第 21 包，在這裡做等於把該包拆散。

## 5. v1 未支援（登記 V，不靜默）

`tag:`（等值集合運算需 `product_tags` 正規化表＝排程第 9 包；在那之前做 JSON LIKE 就是
13 §F4.3 禁止的子字串比對）、`created_at:>` 等比較運算子、`-`/`NOT` 否定、`OR`、括號分組、
`*` 萬用字元、`title:` 顯式前綴。全部落在未知 prefix 的字面文字路徑上，行為可預測。
