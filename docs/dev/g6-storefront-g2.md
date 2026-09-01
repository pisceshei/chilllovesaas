# G2 parity 步 12：前台缺口收口（12a 系列線；12b 搜尋線另補）

> 三源取證正典＝`docs/research/96-storefront-g2-teardown.md`（官方逐字＋真店親點
> ＋live payload）。本檔記實作對照與紅證。

## 1. 12a 射程（本包）

| 面 | 實作 | 96 錨 |
| --- | --- | --- |
| /collections 清單頁 | resolve 加 `list-collections` 分支＋`collections` 全域真 drop | §1 |
| `collections` 全域 | CollectionsDrop：已發布集、字母序、`[handle]`、`size`、可分頁 | §1 |
| `collection.products` | CollectionProductsDrop：discoverable 閘＋排序對映＋頁窗 | §2 |
| /collections/all | 虛擬全商品系列（title=Products）；真 handle=all 優先 | §2 |
| `all_products` | AllProductsDrop：20 唯一 handle 上限（超限 nil＋遙測） | §7 |
| `{% paginate %}` | 真分頁：by 右值可為變數、clamp 1..250、25k 深度、parts 窗 | §1 |
| `?view=` | 替代模板：存在 ⇒ `{type}.{suffix}`；不存在 ⇒ 靜默 fallback（真店實證） | §6 |

## 2. 防線（突變紅證 M1–M7）

- **發布閘**：清單＝`Collection.published_on`（M1）；商品格＝`Product.discoverable`
  （模型正典：搜尋/系列/推薦用 discoverable；M3）。
- **頁窗**：`paginate!` 未接線＝整頁全量假分頁（M2）；parts URL 必須帶 locale 前綴
  ——掉前綴的分頁連結會被 PrefixIndex 判 404（M7）。
- **排序**：URL `sort_by`（前台 9 值鍵）↔ `Collection.SORT_ORDERS` 對映表雙向
  （M4）；`best_selling` v1 降級 created_desc（91 §3.60）；`most-relevant` 對映預設。
- **快取**：`view` 必須進 `CACHE_PARAMS`——漏了＝替代模板頁與預設頁互相污染（M5）。
- **優先序**：商家自建 handle=all 真系列壓過虛擬系列（M6）。

## 3. 🔴 Liquid drop 的 `[]` 陷阱（本輪紅測實錘）

`Liquid::Drop#key?` 恆回 true ⇒ VariableLookup 對 drop **一律走 `[]`**（＝屬性
派發）。在 drop 上覆寫 `[]` 做 handle 查詢，會把 `collections.size` 劫持成
`collections['size']`。正解＝handle 查詢走 `liquid_method_missing`、不動 `[]`；
代價＝與 Enumerable 方法重名的 handle 被方法遮蔽（本尊同型限制）。

## 4. v1 邊界（91 §3.60）

best_selling 排名／paginate window_size 參數／storefront filter（filter.p.*）／
collection.image（schema 無欄）／list 頁逐卡 count N+1——全數 ⚪ 登記。
