# 13 — 功能規格：商品、變體、媒體、集合、庫存（生產級）

> 覆蓋功能：商品 CRUD、options/variants、媒體上傳、handle 與 SEO、collections（manual/smart）、庫存帳與調整、CSV 匯入。規格對照研究 01/06，基線見 11。

## F1. 商品 CRUD 與變體

**生產級做法**：
1. 寫入包成 `Catalog::SaveProduct` service：商品欄位 + options + variants + media 排序在**單一 transaction** 內原子更新（Shopify 的 `productSet` 宣告式思路）。
2. Options ≤3 在 service 與 DB（CHECK 或驗證 + 測試）雙重限制；變體 = option values 笛卡兒積，**變體唯一性用唯一索引** `(product_id, option_values_digest)` 兜底（digest = 排序後 join 的 SHA1）。
3. 變體批量編輯（價格/庫存欄位表格）走一支 bulk endpoint，逐列驗證、回傳逐列錯誤（對齊後台表格編輯 UX）。
4. 刪除策略：商品被 line_items 引用 → 不可硬刪，只能 Archive；未被引用才允許真刪。變體同理。
5. `position` 排序欄位用整數 gap 法（100,200,300…重排時重編）；拖曳排序 endpoint 冪等。
6. status 三態（draft/active/archived）+ 前台可見性規則：active 且發佈到 online store channel 才出現在 storefront 查詢（做成 `Product.published` scope，一處定義全站重用）。

**工具**：Active Record、dnd-kit（前端拖曳）、TanStack Table（變體編輯表格）。

**⚠️ 坑**：
- 變體重生成時**不能砍掉重建**（會斷 line_items/inventory 外鍵與歷史）——diff 現有變體：match 的更新、多的軟移除、新的建立。
- price 允許 0（免費商品合法），但 compare_at_price < price 時要嘛擋、要嘛不顯示折扣（選一致的規則，Shopify 是不顯示）。
- `option_values` 順序敏感（Size/Color vs Color/Size 是不同變體識別）→ digest 前先按 option position 排序。
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

## F2. Handle 與 SEO 欄位

**生產級做法**：
1. handle 生成：標題 → transliterate 拉丁化；**中文標題不轉拼音**，改用「允許 unicode handle（URL encode）」或 fallback `product-{n}`——demo 選 unicode handle（`/products/棉質短T` 可用），SEO 欄位另存。
2. 唯一性 `(shop_id, handle)` 唯一索引；衝突自動 `-1` `-2` 後綴。
3. 改 handle → `url_redirects` 表自動寫 301（old_path → new_path），storefront 404 前先查 redirect 表。
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

## F4. Collections（manual / smart）

**生產級做法**：
1. manual：`collection_products` join 表 + position 手動排序。
2. smart：`rules` JSON（[{column, relation, condition}] + disjunctive boolean）；**匹配結果物化**進同一張 join 表（標記 source=rule），不要每次前台查詢即時算。
3. 物化時機：商品建立/更新 → `Collections::ResyncProductJob`（算該商品 vs 全部 smart rules，增量進出）；規則變更 → `Collections::RebuildJob`（全量重算該 collection，分批 in_batches）。
4. tags 用正規化表 `product_tags(product_id, tag)` + 索引，**不要存逗號字串**（否則 tag 條件永遠全表掃）。
5. 排序選項（手動/價格/新舊/暢銷）存 collection 上，前台查詢 map 到 order by；「暢銷」用 90 天銷量 rollup 欄位（analytics 餵）。

**⚠️ 坑**：rebuild 大集合時不能鎖住前台 → 分批寫 + 不包大 transaction；規則求值要和查詢語意完全一致（例如 price 條件比對的是變體最低價還是任一變體？定死：任一變體，寫進測試）；商品刪除/archive 要觸發移出所有 collection。

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

## 本篇驗收（對照 11 §0）

變體 diff 更新不破壞歷史訂單；ledger 對帳 task 連續 7 天 0 差異；併發加購 100 執行緒不超賣（測試腳本）；上傳 60MP 圖被拒；smart collection 10k 商品 rebuild <60s 且前台無感；CSV 匯入 1 萬行報告逐行可讀；富文本 XSS payload 全數被消毒（測試集跑過）。
