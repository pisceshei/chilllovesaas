# G2 parity 步 12：前台缺口收口（12a 系列線＋12b 搜尋線）

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

## 4. 12b 射程（搜尋線）

| 面 | 實作 | 96 錨 |
| --- | --- | --- |
| /search 頁 | SearchDrop（九屬性；filters 恆空）＋SearchResultsDrop（混型頁窗） | §3 |
| suggest `.json` | 官方參數全驗（422 fail-closed）＋16 鍵條目＋decimal 字串＋`_pos/_psq/_psid/_ss` | §4.1/4.2 |
| suggest section 形 | `section_id`＝**檔名**直渲染＋`predictive_search` 物件（Ella header 實際打的形） | §4.3 |
| recommendations 雙形 | 官方三錯誤逐字；related v1＝共同系列成員（ours）；complementary＝空（未配置真實形） | §5 |

- 🔴 兩個金額出口不同尺度（鐵律 3）：suggest＝decimal 字串（`"188.00"`，divmod）；
  recommendations＝`as_storefront_json` 整數分。不得共用序列化。
- /search 頁**不進頁快取**（q 鍵空間無界——S6b 同型防灌爆）；`type` 進
  CACHE_PARAMS（兼 renderer 參數白名單）。
- price 排序官方句：非商品結果推到結果陣列尾（混型窗＝商品段先、頁面段後）。
- section 檔名直渲染 fallback 落在 `section_data_for` 第三層（先 template 實例、
  再 layout 群組、後檔名）——Dawn/Ella 的 cart-drawer/predictive-search/
  related-products 全是檔名請求（25 §5）。

## 5. v1 邊界（91 §3.60/§3.61）

best_selling 排名／paginate window_size 參數／storefront filter（filter.p.*）／
collection.image（schema 無欄）／list 頁逐卡 count N+1——⚪ 3.60。
搜尋欄位集 ours／prefix·unavailable_products 不改變匹配／query 建議恆空／
relevance 排序 ours／422 body 細形對位 cart 三鍵形／suggest section 形 locale
用預設字典——⚪ 3.61。
