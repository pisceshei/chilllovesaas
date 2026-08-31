# 63 — 商品資料流規格：商家後台寫入 → 前台渲染 → 平台總後台

> **本篇回答一個問題**：商家在後台按下「儲存」之後，到買家在前台看到新價格為止，中間發生了什麼；以及這條路徑上的每一段失敗時會怎樣。
>
> 上游：`docs/research/60`（產品區全模組實站拆解，特別是 §1 無變體＝隱含變體、§4 庫存五態）｜`docs/research/59`（商品詳情頁與建立頁）｜**`docs/research/61`（Shopify 官方文檔權威字典，與本篇同一輪產出——本篇已逐節與其對齊，衝突處以 61 的官方出處為準，見 §0.5）**｜`docs/research/28` §1/§3/§13/§15/§16（API 契約）｜`docs/research/06` §2/§5（資料模型與恆等式）｜`docs/specs/13`（商品／庫存／媒體）｜`docs/specs/16`（訂單／履約／退款）｜`docs/specs/14`（前台渲染與快取）｜`docs/research/25/26/27/31`（Liquid 引擎四件套）｜`docs/research/29`（Markets）｜`docs/research/30`（SEO/feed）｜`docs/specs/18`（outbox）｜`docs/specs/36/39`（平台總後台）｜`docs/specs/11` §0（七維度）。
>
> 寫法比照 `docs/specs/56`（法域可插拔）與 `docs/specs/58`（物流商對接）：先立抽象與原則，再逐段落地，最後 limits 鍵、七維度驗收、待查證。

---

## 0. 決議、範圍與出處等級

### 0.1 使用者裁定（2026-08-12）

> 「你必須深度去推理所有的後台數據在新增或者編輯之後，如何和前端或 platform 總後台去對接」
> 「你也要深度去分析和推理，後台的數據如何和前台的商品詳情頁面對接」

拆成四條可驗收的要求：

| # | 要求 | 本篇對應 |
|---|---|---|
| R1 | 後台寫入的每一筆資料，要能說出它**寫進哪張表、在哪個 transaction、發什麼事件** | §A、§B、§C |
| R2 | 前台商品詳情頁的每一個顯示值，要能說出它**從哪來、什麼時候更新、陳舊時會怎樣** | §D |
| R3 | 平台總後台的每一個跨租戶數字，要能說出它**走 rollup 還是直查、隔離怎麼保證** | §F |
| R4 | 任一環節失敗，要能說出**看得見嗎、怎麼補** | §H |

### 0.2 六條設計原則

1. **價格與庫存不是同一種資料**。價格是低頻、強一致、金額正確性資產；庫存是高頻、最終一致、併發要害。**兩者的寫入路徑、事件粒度、快取策略必須分開設計**——本篇最主要的一條軸線。
2. **商品恆有至少一個變體**（60 §1）。「無變體」只是 `variants.length == 1` 的呈現特例，不是另一種資料形狀。
3. **transaction 內只有 DB 寫**（鐵律 5）。外部 IO（S3、CDN purge、feed 推送、銷售管道 API）一律 outbox → job。
4. **快取一律 key-based expiry，永不手動 delete**（11 §4-3）。這使得「失效失敗」這個失敗模式**在設計上不存在**；風險轉移為「cache key 漏了維度」，而那是**靜態可測**的。
5. **transaction 外的一切都是投影**（快取、搜尋索引、smart collection membership、feed、銷售管道發布）。投影一律**可從當前 DB 狀態全量重建**——與冪等的 `rebuild_from_current_state`（11 §2.1）同一個哲學。這是本篇對「補償」的統一答案：商品線**沒有 saga，只有可重跑的投影**。
6. **平台總後台是聚合的消費者，不是租戶資料的查詢器**。需要租戶商品內容的平台功能，一律「**租戶推、平台不拉**」（§F.3）。

### 0.3 出處等級（在既有四級之外新增一級）

| 等級 | 意義 | 本篇用例 |
|---|---|---|
| `dev` | shopify.dev 開發文檔（46a/46b） | GraphQL 契約形狀 |
| `help` | help.shopify.com 商家文檔（46c） | 庫存五態定義 |
| `live` | 2026-08 實測畫面（44／47／59／60） | 卡片組成、GID 形態、列表欄位 |
| **`fixture`（本輪新增）** | **`test/fixtures/themes/ella-7.2.0` 原始碼實測**——golden theme 的真實 Liquid 用法。等級**高於 `ours`**：它是我方 M6 驗收標的（27 §8）的硬需求，不是推論 | `Default Title` 字串比對、`inventory_quantity` 使用面 |
| `ours` | **本專案推導**（官方未載明，或載明但我方另做決定） | 事件分層、cache_stamp、多地點指派 |

> **凡標 `ours` 者皆為本專案推導，不是查證過的事實。** 全篇 `ours` 條目在 §K 有需要覆核者的編號（V-90 起）。
> `fixture` 等級的引用**帶檔名與行號**，可重新驗證：`cd test/fixtures/themes/ella-7.2.0 && grep -rn ...`。

### 0.4 與 61 號（同一輪的官方文檔字典）的對齊聲明

61 號與本篇在同一輪產出，**它是官方文檔側的權威字典，本篇是資料流側的工程規格**。已逐節對齊，五處採 61 的結論：

| 本篇原本推導 | 61 的官方證據 | 本篇處置 |
|---|---|---|
| `Default Title` 只有 fixture 證據 | 61 §1.1（help P18）：無選項商品的變體標題**固定為** `Default Title` | 證據等級升為 `help` ＋ `fixture` 雙重（§B.2） |
| 採 60 §4 建議的「庫存頁譯名」 | 61 §3.2：**不要照 60 的建議改**——13 §F5.1 現用的 help 官方譯名才是穩的錨；此為 **V-52**（需使用者裁定） | **撤回裁定**，維持 13 §F5.1 現況（§E.1） |
| SKU 唯一性未知 | 61 §1.5（help P10）：官方要求唯一、**偵測到重複顯示警告但不阻擋** | 從「未知」改為「軟唯一」（§B.6） |
| 商品狀態三態 | 61 §1.3（dev D3/D4）：官方**四態**，多一個 `UNLISTED`（可購買、不可被發現） | 前台可見性拆成兩個 scope（§D.2） |
| 發布只有商品級 | 61 §2.2（help P16）＋ 60 §2 實測變體表有「發佈」欄 | 補**變體級發布**與 AND 規則（§H.2） |

### 0.5 骨架：一次「儲存」的完整路徑

```
【商家瀏覽器】
  商品頁表單（59 §7：建立與詳情是同一元件的兩種狀態）
   └─ SaveBar「儲存」
        │  ① 一支 GraphQL mutation（§B.4：productSet 全樹）
        ▼
【Rails｜/admin/api/2026-08/graphql.json】
  ② parse（schema 型別／≤250）          → top-level errors
  ③ normalize（Decimal 字串→cents／handle／HTML sanitize）
  ④ validate（業務規則）                 → userErrors{field,message,code}，HTTP 恆 200
  ⑤ ┌──────────── 單一 transaction（鐵律 5：內無外部 IO）────────────┐
     │ products / product_options / option_values                      │
     │ product_variants（diff，不重建）                                 │
     │ inventory_items（sku/cost/tracked/origin/hs）                    │
     │ product_tags / metafields / product_publications                 │
     │ 物化欄：min_price_cents / max_price_cents / available_for_sale   │
     │ collections.products_updated_at（14 §F1 坑：不用 touch 連鎖）     │
     │ event_outbox ×N（與業務同交易，這是「事件必達」的唯一保證）      │
     └────────────────────────────────────────────────────────────────┘
  ⑥ 回應（含 extensions.cost）
        │
        ▼
【Solid Queue dispatcher（每 5s，SKIP LOCKED）】── 18 §F1
  ├─ Storefront::CacheStampBumper   → collections.products_updated_at、shop.catalog_version
  ├─ Collections::ResyncProductJob  → smart collection membership（13 §F4）
  ├─ Search::IndexProductJob        → FULLTEXT 影子欄 body_text
  ├─ Publishing::SyncJob            → 銷售管道發布（會失敗，§H.2）
  ├─ Feeds::IncrementalJob          → GMC Merchant API 增量（30 §9-8）
  ├─ Seo::IndexNowPing              → 去抖 ≥5 分鐘（30 §9-9）
  ├─ Webhooks::Dispatcher           → products/update（對外，HMAC）
  └─ Platform::…                    → ❌ 不訂閱。平台側走 rollup（§F）
        │
        ▼
【買家瀏覽器｜下一次請求】
  Storefront Router → ThemeRuntime（25 §6，進程內，不走 HTTP）
   → fragment cache key 含 product.cache_stamp（已變）→ MISS → 重算 → 新價格
```

**一句話**：儲存＝**一個 transaction 寫 DB 與 outbox，其餘全是可重跑的投影；前台因為 cache key 帶了資料版本，所以「下一次請求」就是新價格，中間沒有失效動作、也就沒有失效失敗。**

---

## A. 寫入路徑

### A.1 四段式：parse / normalize / validate / commit

| 段 | 做什麼 | 失敗出口 | 出處 |
|---|---|---|---|
| ① parse | GraphQL schema 型別、non-null、陣列 ≤`limits.api.array_input_max_items`(250)、query cost ≤`limits.api.max_query_cost_points`(1000) | **top-level `errors`**（syntax／`MAX_COST_EXCEEDED`／`THROTTLED`／`ACCESS_DENIED`／`INTERNAL`＋requestId） | 28 §0.3 |
| ② normalize | ⑴ 金額 `Decimal` 字串 → integer cents（§A.5 唯一轉換點）⑵ handle transliterate／unicode（13 §F2）⑶ 富文本 sanitize（13 §F1 白名單）⑷ tags 去重小寫化 ⑸ GID → 內部 id 並**驗證 shop 歸屬** | 不合法輸入直接進 ③ 的 userErrors | 13 §F1/F2 |
| ③ validate | options ≤3、variants ≤2048、media ≤250、title ≤255、description ≤64KB（皆 `limits.product.*`）；handle 唯一；`compare_at_price` 與 `price` 的關係；`variants.length >= 1`（§B.1）；publication 歸屬本店 | **`userErrors{field, message, code}`，HTTP 恆 200**（鐵律 4）。code 一律從 28 §6 的泛用碼取值（`BLANK`/`TAKEN`/`TOO_LONG`/`INVALID`/`NOT_FOUND`/`INVALID_STATE`…），商品線專屬碼只有既有的 `HANDLE_TAKEN`、`VARIANT_LIMIT_EXCEEDED`，加上本篇新增的 `LAST_VARIANT_REQUIRED`（§B.1） | 28 §1、28 §6 |
| ④ commit | 單一 transaction（§A.2）；**唯一性在 transaction 內以 DB 唯一索引兜底重驗**——model validation 有競態（11 §2-1），`ActiveRecord::RecordNotUnique` 一律轉譯成與 ③ 相同的 `userErrors` code，**不得漏成 500** | `INTERNAL_ERROR`＋requestId | 11 §2 |

**驗證不得只在前端做**（14 §F2 坑的商品版）：admin SPA 只是第一道；任何人可直接打 GraphQL 端點。③ 是唯一的權威。

### A.2 transaction 邊界（鐵律 5：內禁外部 IO）

**一個業務動作＝一個 transaction**（11 §2-2）。商品儲存的 transaction 內**只准有 primary DB 的寫**：

| 在 transaction 內 | 在 transaction 外（前）| 在 transaction 外（後，走 outbox → job）|
|---|---|---|
| products / options / option_values / variants（diff）/ inventory_items / tags / metafields / publications | **媒體二進位上傳**：`stagedUploadsCreate` 取簽名 URL → 瀏覽器**直傳** S3/R2 → `fileCreate` 只寫「指向已存在 blob 的一列」（13 §F3-1） | 衍生尺寸生成、EXIF strip、webp 轉檔（13 §F3-3） |
| 物化欄（§D.2）與 `collections.products_updated_at` | 權限檢查、限流扣點 | 銷售管道發布、feed 推送、IndexNow ping、webhook 投遞、通知信 |
| `event_outbox` 插入 | — | smart collection 重算、搜尋索引 |

**為什麼一定要 outbox，不能直接 `perform_later`**〔ours〕：Rails 8 的 Solid Queue 預設使用**獨立的 `queue` database**（D1：Solid Queue/Cache，不用 Redis）。跨資料庫的 `perform_later` **不具事務性**——商品寫入 rollback 了、job 卻已入列（或反之：commit 了、入列失敗）。`event_outbox` 與業務表在**同一個 primary DB**，同交易插入才是「事件必達」的唯一保證（18 §F1-1）。
> 這條推理若 Solid Queue 被設定成與 primary 同庫則不成立，但**規格仍要求走 outbox**：同庫只是讓錯誤寫法「碰巧沒事」，架構不能建立在部署配置上。

**CDN purge 絕不進 transaction**：它是 HTTP 呼叫，且我方根本不做 delete-based 失效（§D.4）。

### A.3 冪等：商品寫入要不要帶 `idempotencyKey`

**鐵律 5 只點名「訂單成立／退款／庫存調整」。商品寫入不在其中——但不能因此一律不帶。判準不是「是不是商品」，而是「重放會不會憑空多出一個實體或一筆錢」。**

**三分類（`ours`，判準沿用 55 §D G-08 的既有邏輯：凡重放產生新副作用者一律強制）**：

| 類 | 語義 | 代表 mutation | 冪等要求 | 理由 |
|---|---|---|---|---|
| **A 宣告式覆寫**（天然冪等） | 同一份 input 執行 N 次 ＝ 執行 1 次 | `productUpdate`、`productSet`、`productVariantsBulkUpdate`、`productOptionsUpdate/Reorder`、`productChangeStatus`、`metafieldsSet`、`publishablePublish/Unpublish`、`collectionUpdate`、`inventoryItemUpdate` | **不強制 key** | 沒有累加副作用、沒有錢動。強制帶 key 只會讓 `idempotency_keys` 表在 CSV 匯入（5 萬行，13 §F6）下無謂膨脹。**但必須帶 `lock_version`**（§A.4） |
| **B 建立型**（重放憑空多實體） | 執行 N 次 ＝ N 個實體 | `productCreate`、`productDuplicate`、`productVariantsBulkCreate`、`productCreateMedia`、`collectionCreate`、`fileCreate` | 🔴 **強制 `idempotencyKey`**〔ours〕 | 商品**沒有天然業務唯一鍵**可兜底：`handle` 衝突時自動加 `-1` 後綴（13 §F2-2），title 可合法重複 ⇒ 唯一索引擋不住。重複點擊儲存／網路重試 ⇒ 兩個一模一樣的商品。這是 B 類與 A 類的唯一差別，也是唯一能擋的位置 |
| **C 增減型**（重放數量／金額錯） | 執行 N 次 ＝ 加 N 次 | `inventoryAdjustQuantities`、`inventoryMoveQuantities`、`inventorySetQuantities`、`inventorySetOnHandQuantities` | **已在 `limits.idempotency.required_for`** | 既有規定（28 §0.6） |

**落地**：新增 `limits.idempotency.required_for_catalog_create`（§I），**刻意不直接併進 `required_for`**——後者的既有註解承載「官方 17 支／我方 9 支金流／我方 4 支物流」的出處分層，B 類是第四類來源，混入會讓出處註解失真；合併是一行改動，但**必須同步更新 CI 的無條件斷言**（28 §0.6 對 `required_for_platform` 的教訓：斷言與清單語義不同步會讓快照測試紅掉）。

**三條容易做錯的細節**：

1. **`inventorySetQuantities` 看似 set 型（冪等），實際不是**。它帶 `compareQuantity` 樂觀鎖（28 §3；22 §2 實測「on hand(current) 防過期校驗」）。第一次成功後現值已變，**同一份 input 重放會因 compareQuantity 不符而失敗**——這正是需要 key 的場景：重放要回放「原請求成功」的結果（11 §2.1(b) `succeeded` ⇒ 依 `result_ref` 重建），而不是回一個假的衝突錯誤。
2. **Bulk 每 row 一把獨立 key**（`limits.idempotency.bulk_key_per_row`）。`productVariantsBulkCreate` 建 50 個變體用一把 key ⇒ 部分成功後重試會被整批視為已完成。
3. **CSV 匯入（13 §F6）是 B 類的大量版**：以 handle upsert，**存在則 update（A 類）、不存在則 create（B 類）**。create 分支的 key＝`UUID v5(namespace: catalog_import, [import_job_id, row_no])`（`limits.idempotency.key_format_scheduled`）——同一支匯入 job 重跑不會重複建商品，且不需要持久化 key。

### A.4 併發：商品寫入的要害不是超賣，是**靜默覆蓋**

超賣是庫存的要害（§E.4）；**商品資料的要害是「兩個 staff 同時編輯同一個商品，後存者靜默蓋掉先存者」**——它不會報錯、不會有任何痕跡，商家只會覺得「我改的怎麼不見了」。本專案已有同類事故的前例（`billingPage`/`setBillingPage` 分家造成的靜默覆蓋，59 §7）。

**規定**〔ours，落地 11 §3-3 的既有工具〕：

- `products` 與 `product_variants` 皆帶 `lock_version`（樂觀鎖）。
- A 類 mutation 的 input **必須帶 `lockVersion`**；不符回 `userErrors{code: STALE_OBJECT, field: ["lockVersion"]}`，訊息帶**持有者姓名與其儲存時間**（比照 16 §F8.2 C1 對 edit session 的既有做法）。
- 前端收到 `STALE_OBJECT` → SaveBar 轉為「此商品已被 {name} 修改，〔重新載入〕〔覆蓋儲存〕」；**覆蓋是顯式動作**，不是預設。
  <!-- 2026-08-15 修正（本尊考掘，Admin API 2026-07 逐頁查證）。原文用 `CONFLICT`。
       🔴 本尊的 `CONFLICT` **只存在於 `DiscountErrorCode`，語義是「折扣屬性選擇互相衝突」的
       輸入驗證**，與樂觀鎖無關。把它泛用化成樂觀鎖碼會讓同一個 token 在折扣線與商品線
       表達兩件不相干的事，前端無法用 code 分支。⇒ 改用 `STALE_OBJECT`。
       🔴 **`field: ["lockVersion"]` 不改**——考掘一度判它「傾向衝突、應改成
       `["input","lockVersion"]`」，但覆核以官方 `/mutations/productDelete` 的錯誤範例
       `"field": ["id"]`（參數就叫 `input`、id 住在 `input.id`）正面推翻：
       **本尊會把 `input` 這層外殼剝掉**。我方原本就是對的。 -->
- `productSet`（全樹）的 `lockVersion` 檢查涵蓋**商品與其所有變體**：任一 variant 的 `lock_version` 不符即整筆拒絕。
- **例外**：庫存數量寫入**不使用 lock_version**，改用條件式 UPDATE ＋ `compareQuantity`（§E.4/§E.6）——樂觀鎖在高頻扣減下會退化成互相踩踏。

> ~~`CONFLICT` 目前在 28 §8 的 `DiscountErrorCode` 39 值表中被歸類為「折扣專屬」。本篇**將其提升為泛用碼**（語義本就通用），需回頭改 28 §6 的通用碼複用鐵律那一段——登記於 §L-3。~~
>
> 🔴 **§L-3 於 2026-08-15 以相反方向結案**（本尊考掘，Admin API 2026-07）：
> 本尊的 `CONFLICT` **只存在於 `DiscountErrorCode`**，語義是「折扣屬性選擇互相衝突」的
> **輸入驗證**——它從來不是樂觀鎖碼。⇒ **28 §8 的現行分類是對的，要改的是本篇**。
> 樂觀鎖改用 **`STALE_OBJECT`**（本篇 §A.4 已改）、庫存 CAS 用 **`CHANGE_FROM_QUANTITY_STALE`**。
> 兩者都進 `Types::Errors::ConcurrencyCode` 池——那是本輪新開的類別，
> 因為 28 §6 的 20 個泛用驗證碼**結構上容不下併發語義**（它們全是欄位級輸入驗證）。
>
> 🔴 **教訓**：把一個碼「提升為泛用」之前要先查它在本尊那裡是什麼意思。
> `CONFLICT` 這個英文詞看起來當然像樂觀鎖，但本尊用它表達的是**折扣條件互斥**。
> 光看名字推語義，是本輪四題裡最容易犯的錯。

### A.5 金額入口的唯一轉換點（鐵律 3）

**線上格式是 `Decimal` 字串（28 §0.3），內部是 integer cents。轉換只准發生在一個地方。**

```ruby
# app/models/money.rb —— 全專案唯一的「字串 → cents」入口
# 為什麼尺度固定 ×100 而不看幣別：limits.currency_display.force_minor_unit_digits = 2
# ＋ storage_scale_unchanged = true（2026-08-12 裁定二）。JPY 的 ¥1,480 存 148_000。
# 🔴 送 PSP 前必須另外依該 pack 宣告的 amount_format 換算（65 §D，落地見 §G.4）——這兩件事不是同一件。
#    （依 65 §J M-8 修正，原文：「必須另外換算回 ISO minor unit」——ISO 不是換算基數，格式也不只 minor unit 一種。）
# 寫法比照 docs/specs/58 §G.3（物流商回傳的十進位字串），同一條紀律。
def self.parse_to_cents(str, currency)
  raise ArgumentError, "float forbidden" if str.is_a?(Float)      # 鐵律 3：出現 float 即 bug
  BigDecimal(str.to_s) * limits.currency_display.storage_multiplier  # 100
end
```

**禁止**：`params[:price].to_f`、JS 端 `parseFloat(price) * 100`（11 §8 坑 3 明文禁止 JS 端 float 算錢）、任何在 serializer 以外的 cents→Decimal 轉換。
**利潤／利潤率**（59 §2 的衍生唯讀欄位）：`profit_cents = price_cents - unit_cost_cents`；`margin_bp = profit_cents * 10_000 / price_cents`（**整數除法，截斷**，比照 55 §A M39 的既有做法）。`price_cents == 0` 或 `unit_cost_cents IS NULL` ⇒ 回 `null`，UI 顯示 `--` 而**不是 `0`**（59 §2、P0-17「未計算 ≠ 0」同一條原則）。

---

## B. 商品與變體的寫入語義

> **本節做錯會讓資料模型從一開始就歪。** 60 §1 的實站證據：無變體商品頁的價格／庫存／運送三張卡，分組 id 是 `product_variant_collapsible_pricing/_inventory/_shipping`；同樣三張卡、同樣的 id，在有變體商品上出現在**變體詳情頁**。名字說明了架構：**那三張卡從來都是「變體」的卡。**

### B.1 不變量：商品恆有至少一個變體

| # | 不變量 | 落地 |
|---|---|---|
| B1-1 | `products` 表**沒有** `price` / `compare_at_price` / `sku` / `barcode` / `weight` / `inventory_quantity` 欄位 | migration 檔頭註明；CI 靜態斷言（§J-2） |
| B1-2 | `COUNT(product_variants WHERE product_id = ?) >= 1` 恆成立 | service 層驗證 ＋ nightly 對帳斷言。**DB 無法用 CHECK 表達跨表基數**，所以這條靠斷言不靠約束——必須有測試 |
| B1-3 | 「無變體」＝ `product.has_only_default_variant`，判定式＝ `product_options.count == 0`（**不是**比對變體 title） | 唯一判定處：`Product#has_only_default_variant?` |
| B1-4 | 刪到最後一個變體 → `userErrors{code: LAST_VARIANT_REQUIRED}` | `productVariantsBulkDelete`；比照既有 `VARIANT_LIMIT_EXCEEDED` 的專屬碼先例 |
| B1-5 | **`ProductInput` / `ProductUpdateInput` 不得出現價格與庫存欄位** | schema 快照測試（比照 56 §F-17 的既有做法）；`limits.catalog_flow.product_input_forbidden_fields` |

> **為什麼 B1-5 要做成 schema 級斷言而不是 code review**：一旦 `ProductInput.price` 出現過一次，前端就會有人用它，之後兩套價格欄位的同步邏輯會爛掉（60 §1 逐字警告）。schema 快照測試是唯一能在 PR 階段擋下來的位置。

### B.2 `Default Title` 是硬相容契約（`help` ＋ `fixture` 雙重實證，不是推論）

**官方側**：61 §1.1 引 help P18——「無選項商品的變體標題**固定為** `Default Title`」，且 help 直接以 JSON 範例展示無變體商品仍有 `variants[0].id`。
**主題側**：內部用旗標判定（B1-3），**但 Liquid 對外必須吐 `Default Title` 字串**——golden theme 直接比對它：

```
test/fixtures/themes/ella-7.2.0：
  blocks/_color-comparison-content.liquid:20   variantCount > 1 and product.variants.first.title != 'Default Title'
  snippets/product-swatch.liquid:23            variant_count > 0 and product.variants.first.title != 'Default Title'
  snippets/card-product-flex.liquid:195        variantCount > 1 and card_product.variants[0].title != 'Default Title'
  snippets/product-card-compare.liquid:195     variantCount > 1 and product_card_product.variants[0].title != 'Default Title'
（同一份 fixture 另有 has_only_default_variant 21 處——兩種寫法並存，兩種都要支援）
```

**規定**：`VariantDrop#title` 在 `product.has_only_default_variant?` 時回傳字面值 `"Default Title"`（`limits.catalog_flow.default_variant_liquid_title`）。

- 這**不違反鐵律 9**：它是**介面契約的魔法值**，性質同 `application/json`、同 `gid://` 前綴，不是可著作權的文案。後台 UI 不得顯示這個字串（無變體商品的 UI 根本不顯示變體名，59 §3）。
- 若不做：Ella 的商品卡會把不存在的變體選擇器渲染出來，商品頁 swatch 區塊出現空選項——**這是 M6 golden theme 驗收（27 §8）的直接失敗項**。
- `product.variants.first.title` 與 `has_only_default_variant` 兩條路徑必須**判定一致**：由同一個 `has_only_default_variant?` 驅動，禁止各自實作。

### B.3 「改商品價格」實際上改的是哪一筆

**永遠是 `product_variants.price_cents`。商品層沒有價格。**

| UI 位置（59/60 實測） | 實際寫入 | mutation |
|---|---|---|
| 無變體商品頁的「價格」input（前綴 `HK$`） | 那**唯一隱含變體**的 `price_cents` | `productSet`（§B.4）或 `productVariantsBulkUpdate(variants:[{id, price}])` |
| 有變體商品頁「子類」表格內的價格 input（60 §2） | 對應那一列變體 | `productVariantsBulkUpdate`（多列一次） |
| 變體詳情頁的價格卡（60 §3） | 該變體 | 同上 |
| 「比較價格／每品項成本」pill（59 §2） | `compare_at_price_cents` 在變體；`unit_cost_cents` 在 **`inventory_items`**（§B.6） | 同上 ＋ `inventoryItemUpdate` |

**集合頁／搜尋頁顯示的 `product.price`（Ella 用 96 處）** 是 `MIN(variants.price_cents)` 的**物化欄**（§D.2），由變體寫入路徑在同一 transaction 內維護——**不是另一份價格**，是同一份的快取。

### B.4 無變體 UI 的儲存映射：一次 SaveBar ＝ 一支 `productSet`

**問題**：無變體商品頁的一次「儲存」，同時可能改到標題（product）、價格（variant）、SKU／成本（inventory_item）、SEO（product）、發布（publication）。拆成 4 支 mutation 依序打，第 3 支失敗 ⇒ **畫面呈現半儲存狀態**，與 SaveBar 的「全有或全無」語義矛盾。

**決議**〔ours〕：**admin 商品頁的儲存一律映射成一支 `productSet`（宣告式 upsert 全樹）**，服務端在單一 transaction 內拆解。無變體時 `variants[]` 恰好一筆。這也讓 59 §7 的架構結論（建立與詳情是同一元件的兩種狀態）在 API 層一致：**建立與更新是同一支 mutation，差別只在有沒有 `id`。**

```graphql
mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
  productSet(input: $input, idempotencyKey: $idempotencyKey) {
    product { id handle lockVersion variants(first: 250) { nodes { id price lockVersion } } }
    userErrors { field message code }
  }
}
```

**四條硬規則**：

1. **`productSet` 是全樹宣告式**：未列出的變體視為刪除。**前端必須送完整樹**，不得送 dirty fields。部分更新一律走 `productUpdate` ＋ `productVariantsBulkUpdate`（兩支都是 A 類，天然冪等）。
2. **刪除套用 13 §F1-4 的既有策略**：**允許硬刪，不論是否被 `order_line_items` 引用**；快照保留、關聯欄位轉 NULL。
   <!-- 2026-08-15 依 parity 查證**推翻重寫**，原文：
        「被 `order_line_items` 引用的變體不可硬刪 → 回 `userErrors`（不是靜默軟刪），
          提示商家改用封存商品。」
        🔴 本尊 `productVariantsBulkDelete` 的五個 userError code **沒有一個與訂單引用有關**；
        `CalculatedLineItem.variant` 官方逐字把「the variant has been deleted」列為
        **正常會回 null 的情形**。完整證據見 `docs/specs/13` §F1-4 的批註。
        🔴 **任何宣稱「因為有訂單所以不能刪」的 userError 一律視為 parity 違反。**
        ⚠️ 前置條件同 13 §F1-4：`fk_line_items_product_variant_id` 要先改成
        `ON DELETE SET NULL`，否則 DB 層擋著，刪不掉。 -->
3. **`productSet` 不寫庫存數量**（§B.7）。
4. `lockVersion` 涵蓋整棵樹（§A.4）。

**建立頁的差異只有預設值與空態**（59 §7 逐項）：`收取稅金` 預設 `是`、庫存區是單一「數量」input 而非逐地點表格（因為還沒有異動歷史）、右欄只有「發布」卡。**這些是同一個元件的 `isNew` 分支，不是另一個頁面、也不是另一支 mutation。**

### B.5 選項增刪時的變體身分保持（最容易做歪的一條）

**「無變體 → 有變體」不是新建變體，是把那個隱含變體升級成第一個具名變體。**

| 操作 | 錯誤做法（會斷資料） | 正確做法 |
|---|---|---|
| 加第一個選項（如「容量」，值 230ml/250ml/330ml） | 刪掉 default variant、建 3 個新變體 | **保留原變體 id**，其 option value 設為新選項的**第一個值**（230ml）；另建 2 個新變體 |
| 加第二個選項 | 笛卡兒積重建 | diff：既有變體補上新選項的第一個值；新組合才建立（13 §F1-18 既有規則） |
| 刪光所有選項 | 刪光變體再建一個 | 保留 `position` 最小的變體、其餘走刪除策略（規則 2） |

**為什麼**：變體 id 一換，`inventory_items` 換 id ⇒ **庫存 ledger 斷鏈**（13 §F5-3 的重放對帳永遠對不上）、`order_line_items` 外鍵斷、買家購物車裡的 `variant_id` 失效（cart line 存的是 variant_id）、第三方 feed 的 `id` 欄位（30 §9-8：`variant.sku → id`）全部變成新品項，Google Merchant 會判為「商品消失＋新商品出現」，歷史成效歸零。

> 本節是「選項變更時如何保住變體身分」的具體演算法。
>
> <!-- 2026-08-15 依 parity 查證改寫，原文：
>      「22 §2 已記「Shopify 改選項會重建變體（斷外部引用）」，並標「S13-F1 diff 更新
>        （不重建）——**我們刻意優於本尊的點**」。本節是那一句話的具體演算法。」
>      🔴 **前提整個錯了**：本尊預設就是 diff 更新（`LEAVE_AS_IS`），不是重建
>      ⇒ 本節不是「我們優於本尊」，而是**把本尊已有的行為寫清楚**。
>      `docs/research/22`:106 的同一句已同批修正並撤銷偏離登記。 -->
>
> ⚠️ **本節的三列表格是兩階段 diff 的「階段 A（投影）」**，不是完整的 diff 演算法。
> 階段 B（比對）必須在投影**之後**才跑：有 `id` 的列以 id 對應，沒有 `id` 的列才用
> 投影後的 `option_values_digest` 對應。
> 🔴 **跳過階段 A、直接拿新舊 digest 比對 ＝ 舊變體對不上任何新 digest ⇒ 全部 id 被換掉**
> ——那正是本節存在要防的事故（庫存 ledger 斷鏈、購物車 `variant_id` 失效、
> Google Merchant 判為商品消失＋新商品出現）。

### B.6 `InventoryItem` 是獨立實體，不是 variant 的欄位

60 §4 實測：庫存頁的 checkbox value 是 `gid://shopify/InventoryItem/51159633494251`，與 `gid://shopify/ProductVariant/...` 並列出現在同一個產品區。

**落地**：`product_variants 1:1 inventory_items`，**兩者各有自己的 GID**（`gid://chilllove/ProductVariant/{id}`、`gid://chilllove/InventoryItem/{id}`）。欄位歸屬：

| 欄位 | 掛哪 | 理由 |
|---|---|---|
| price / compare_at_price / option values / position / image | `product_variants` | 銷售面 |
| **sku** | **`inventory_items`** | 它標識的是「實體庫存單位」不是「售賣選項」；**單一權威欄位，避免雙寫漂移**（同 `on_hand` derived 不落庫的處理，13 §F5.1(a)）。Liquid 的 `variant.sku`（26 §變體 38 屬性）由 drop 從 inventory_item 讀。**本尊 `InventoryItemInput.sku` 是官方寫入面（2024-07 起）** |
| 🔴 **barcode** | 🔴 **`product_variants`（不搬）** | **2026-08-15 修正**：本尊的 `InventoryItem` 型別**根本沒有 barcode 欄位**，`InventoryItemInput` 也沒有；barcode 就在 `ProductVariant` 上 |

<!-- 2026-08-15 依 parity 查證拆列，原文是一列：
     「| **sku / barcode** | **`inventory_items`**〔ours〕 | …」
     🔴 **這是 bug——把兩個欄位綁在一起搬，但它們在本尊身上不同命。**
     sku 確實是 inventory item 的；**barcode 本尊從來沒搬過**。

     🔴🔴 **最要小心的地方：我方 `db/schema.rb` 目前是對的**
     （`product_variants.barcode` 存在、`inventory_items` 沒有 barcode）
     ⇒ **任何人「照規格去修 schema」都會把它改壞。**

     ⚠️ 這一條是本輪學到的方法論的樣本：**當「規格說 A、schema 已經是 B」時，
     先查本尊再決定改哪一邊**——不要預設規格是對的。 -->
| unit_cost（每品項成本）/ tracked / country_of_origin / harmonized_system_code | `inventory_items` | 對齊 `inventoryItemUpdate` 的既有簽名（28 §3） |
| available / committed / unavailable / incoming | `inventory_levels`（per location） | 13 §F5.1 |

**⚠ SKU 唯一性：官方是「軟唯一」，與 11 §2-1 衝突**

61 §1.5（help P10）給出了明確答案，且**兩邊都不是**：

> 官方要求**在 admin 內唯一，不得有兩個變體共用同一 SKU**；**偵測到重複會顯示警告（但不阻擋）**。Shopify Fulfillment Network 則強制唯一。長度「建議不超過 16 字元」——**建議不是技術上限**。

所以正確落地是**軟唯一**〔本篇依 61 的官方出處推導〕：

| 層 | 做法 | 為什麼不是另一種 |
|---|---|---|
| DB | **一般索引** `(shop_id, sku)`，**不是唯一索引** | 唯一索引會讓「同款不同包裝共用 SKU」與 CSV 批次匯入（合法情境）直接失敗，與官方「不阻擋」相反 |
| API | 偵測到重複 ⇒ 回一則**警告**（非阻擋）。GraphQL 的 `userErrors` 語義是「這次操作失敗」，警告不能塞在裡面 ⇒ 需要 payload 上獨立的 `warnings` 欄位〔ours〕 | 塞進 `userErrors` 會讓前端把它當失敗處理（鐵律 4：`userErrors` 是業務**錯誤**） |
| UI | 商品頁 SKU 欄位下方顯示「此 SKU 已用於 N 個其他變體〔檢視〕」 | 對齊官方行為 |
| 長度 | `limits.catalog_flow.sku_recommended_max_chars: 16`（**建議值，不驗證**） | 硬上限官方未載明，寫死會擋掉合法輸入 |

11 §2-1 把「SKU per shop」列為「業務唯一性用唯一索引兜底」的例子——**該例子錯了**，需回頭改（§L-1）。`warnings` 欄位是 28 號契約沒有的東西，需一併補（§L-9）。

### B.7 商品寫入路徑不得寫庫存數量

**分離規則**：商品樹寫入（`productSet`）與庫存帳寫入（`inventory*`）是**兩支 mutation、兩個 transaction、兩種事件、兩種冪等要求**。

理由：庫存是 C 類（增減型，強制冪等）、需要條件式 UPDATE ＋ CAS、需要 ledger、變動頻率高兩個數量級。混進 `productSet` 會讓一個低頻的宣告式覆寫背上高頻併發語義。

**唯一例外：建立頁的初始數量**（59 §7 實測建立頁有「數量」input，詳情頁沒有）。

- 建立時商品與 inventory_item 都還不存在，無法先建商品再讓使用者跳去庫存頁——那是**荒謬的 UX**。
- 落地：`ProductSetInput.variants[].initialQuantities[{locationId, quantity}]` **僅在 create 分支合法**（有 `id` 時出現即 `userErrors{code: INVALID}`）。
- 服務端在**同一 transaction** 內呼叫 `Inventory::Adjust`（13 §F5 的既有 service），`reason: correction`、`from_state: null → available`、寫 ledger。
- 冪等鍵：`UUID v5(namespace: product_set_inventory, [parent_idempotency_key, inventory_item_id])`——沿用父請求的 key 派生，不需要前端多傳一把（`limits.idempotency.key_format_scheduled` 的同款技巧）。
- 這樣是**原子的、有 ledger、有冪等**；比「先建商品、再打第二支 mutation、失敗了提示使用者自己去庫存頁補」誠實且安全。

---

## C. 事件與 outbox

<!-- 🔴 2026-08-24 更正（第 19 包執行規格 §4.0）：本章原寫表名 `events_outbox`（5 處），實物為 `event_outbox`（單數），已全數改正。表名以實物為準。 -->

### C.1 兩層事件：對外 webhook（粗粒度）／內部 outbox（細粒度）

**Shopify 沒有 `product_variants/update` 這個對外 topic**——變體變更透過 `products/update` 攜帶完整商品 payload 傳遞。28 §15 的首發 24 個 topic 照此，**本篇不改**。

但內部消費者需要細粒度：改一個變體的價格，不該讓整站商品的搜尋索引重建、也不該讓所有 collection 的 membership 重算。

**決議**〔ours，比照 18 §F1-6 已有的「內部 topic 不對外開放訂閱」先例（`einvoice/*`）〕：

| 層 | topic | 訂閱者 | 對外可訂閱 |
|---|---|---|---|
| 對外 | `products/create`、`products/update`、`products/delete`、`collections/*`、`inventory_levels/update` | 第三方 app、feed 消費者 | ✅（`webhookSubscriptionCreate`） |
| 內部 | `product.updated`、`product.variant.updated`、`product.publication.changed`、`inventory.level.changed`、`inventory.adjusted` | 快取 stamp、搜尋索引、smart collection、發布同步、feed 增量 | ❌ **不出現在可訂閱列表** |

一次 `productSet` 產生：1 筆 `product.updated`（帶 `changed_fields`）＋ 0..N 筆 `product.variant.updated`（每個實際變動的變體一筆）＋ 1 筆對外 `products/update`。全部在同一個 transaction 內插入 `event_outbox`。

### C.2 三個事件的 payload

payload 規範沿用 18 §F1-4：**只帶 ID 與必要摘要，消費時再查現值**（防 PII 蔓延與陳舊資料）。

```jsonc
// product.updated（內部）
{ "topic": "product.updated", "event_id": "uuid-v7", "occurred_at": "2026-08-12T09:14:22Z",
  "shop_id": 42,
  "resource": { "type": "Product", "id": 9874717081835,
                "gid": "gid://chilllove/Product/9874717081835" },
  "resource_version": 87,                       // = products.lock_version（§C.3 的關鍵）
  "changed_fields": ["title", "seo_description", "status"],   // 🔴 只有欄位名，沒有值
  "status_transition": { "from": "DRAFT", "to": "ACTIVE" }    // 僅 status 變更時出現
}

// product.variant.updated（內部）
{ "topic": "product.variant.updated", "event_id": "...", "occurred_at": "...", "shop_id": 42,
  "resource": { "type": "ProductVariant", "id": 49206336651499, "gid": "gid://chilllove/ProductVariant/49206336651499" },
  "parent": { "type": "Product", "id": 9874717081835 },
  "resource_version": 12,
  "changed_fields": ["price_cents", "compare_at_price_cents"],
  "price_affecting": true,           // ⇒ 觸發 IndexNow／feed 增量／JSON-LD 重算（30 §9-9 的觸發條件之一）
  "availability_flipped": false      // ⇒ 見 §E / §D.5
}

// inventory.adjusted（內部；對外對應 inventory_levels/update）
{ "topic": "inventory.adjusted", "event_id": "...", "occurred_at": "...", "shop_id": 42,
  "resource": { "type": "InventoryLevel", "id": 771,
                "inventory_item_id": 51159633494251, "location_id": 93626073323 },
  "adjustment": { "reason": "correction", "from_state": "available", "to_state": "unavailable",
                  "sub_type": "damaged", "delta": -3, "ledger_id": 99812 },
  "availability_flipped": false,     // 🔴 是否跨越「可買 ⇄ 不可買」邊界
  "coalesced_count": 1               // §C.6 合併窗內被併掉的筆數
}
```

**三條 payload 紀律**：

1. **不放金額值**。放了就會有人拿事件裡的價格去顯示／對帳，而事件可能過時（§C.3）。要金額就查 DB。
2. **不放 PII**。商品事件天然沒有，但 `changed_fields` 若含商家備註類欄位也只給欄位名。
3. **`resource_version` 必填**。這是 §C.3 全部設計的支點。

**對外 webhook 的 payload 是投遞當下重新序列化的**（28 §15：資源 snake_case JSON ＋ `admin_graphql_api_id`），與冪等的 `rebuild_from_current_state`（11 §2.1）同一哲學。**後果必須明說**：連續兩次改價可能投遞出兩個都帶第二次價格的 webhook。**消費者不得把 webhook 當審計流**——審計看 `platform_audit_logs` 與 ledger。

### C.3 順序保證：刻意不做，改為讓消費者對順序免疫

18 §F1-3 明文「順序不保證，消費者不得依賴順序」。但價格更新亂序聽起來很致命：先發的舊價格事件晚到，會不會把新價格蓋回去？

**答案：不會，前提是三條防線都做到。**〔ours〕

| 防線 | 做法 | 效果 |
|---|---|---|
| ① 事件帶 `resource_version` | 單調遞增（`lock_version`） | 消費者能判斷新舊 |
| ② 快取一律 key-based expiry | cache key 含 `cache_stamp`（§D.3），**永不手動 delete** | 亂序失效**無害**：key 是資料版本的函數，晚到的舊事件不會把 key 變回去 |
| ③ 投影寫入用 CAS | `UPDATE search_index SET ... WHERE indexed_version < :resource_version`；feed 推送同理 | 舊事件晚到 ⇒ affected rows = 0 ⇒ 靜默略過（**記一筆 metric，不記 error**） |
| ④ 消費者一律重讀當前 DB | payload 不帶值（§C.2-1） | 就算處理順序反了，讀到的也是最新值 |

**為什麼不做順序保證**：dispatcher 是多實例 ＋ `FOR UPDATE SKIP LOCKED`（18 §F1-2），要做 per-resource 串行需要額外的 advisory lock 或分區佇列——成本高、且會讓單一慢消費者卡住整個 resource 的事件流。**用版本號讓消費者免疫，比讓基礎設施保證順序便宜且更穩**。

> 這條要寫進 code review 清單：**任何商品線消費者若「讀 payload 的值來寫入」，直接打回。**

### C.4 重試與冪等

- **語義 at-least-once**（18 §F1-3）。每個消費者自行冪等：去重鍵一律 `event_id`（`processed_events(shop_id, consumer, event_id)` 唯一索引），或天然冪等操作（單調 bump、CAS 寫入）。
- 失敗 `attempts >= 8` → `status = dead` ＋ 告警 ＋ 後台可重推（18 §F1-5）。
- **對外 webhook 另有一層**：5 秒內 2xx，指數退避（28 §15）；`X-CL-Webhook-Id` 供消費者去重。
- **消費者失敗不得阻塞其他消費者**：一個 outbox 事件路由給 N 個消費者，逐消費者記錄投遞狀態（`event_deliveries(event_id, consumer, state, attempts)`），**不是整筆事件重推**——否則 feed 推送掛掉會讓快取 stamp 也一起重放。〔ours；18 §F1 原文是「逐筆路由給訂閱者→成功標 done」，單一 done 欄位做不到這件事，登記於 §L-4〕

### C.5 消費者總表（商品線）

| 消費者 | 訂閱 | 動作 | 冪等方式 | 失敗表現 |
|---|---|---|---|---|
| `Storefront::CacheStampBumper` | `product.updated`／`product.variant.updated` | bump `collections.products_updated_at`（14 §F1 坑：**不用 touch 連鎖**）、`shops.catalog_version` | 單調 bump（天然冪等） | 集合頁顯示舊的商品組合，直到下次 bump |
| `Collections::ResyncProductJob` | `product.updated` | 該商品 vs 全部 smart rules 增量進出（13 §F4-3） | `(product_id, rules_version)` CAS | membership 過時；nightly 全量對帳補 |
| `Search::IndexProductJob` | `product.updated` | 維護 `body_text` 影子欄與 FULLTEXT（14 §F4-1） | `indexed_version` CAS | 搜尋不到新商品 |
| `Publishing::SyncJob` | `product.publication.changed`／`product.updated` | 推送到銷售管道 | `(product_id, publication_id, resource_version)` | **`product_publications.status = ERROR`**（§H.2，這是 60 §5「發布錯誤」排序維度的資料來源） |
| `Feeds::IncrementalJob` | `product.variant.updated{price_affecting}`／`inventory.adjusted{availability_flipped}` | GMC Merchant API 增量推送（30 §9-8） | `(shop, item_id, version)` | feed 與 landing page 價格不一致 ⇒ **拒登／停權**（30 §6 品質硬規則），必須告警 |
| `Seo::IndexNowPing` | 同上 ＋ 狀態／URL 變更 | ping IndexNow，**去抖 ≥5 分鐘**（30 §5） | `(shop, url, last_pinged_at)` | 收錄延遲（無資料損失） |
| `Webhooks::Dispatcher` | `products/*`、`inventory_levels/update` | 對外 HMAC 投遞 | `X-CL-Webhook-Id` | 連續失敗自動刪訂閱（28 §15） |
| **平台總後台** | **不訂閱任何商品事件** | — | — | — |

> 最後一列是本篇的核心約束之一：**平台域不掛在租戶的商品事件流上**（§F.1）。

### C.6 庫存事件的合併窗

庫存變動頻率比商品資料高兩個數量級（每筆訂單 N 個 line item × M 個地點）。不處理的話 `event_outbox` 會被庫存事件淹沒。

**合併規則**〔ours〕：

- 同一 `(shop_id, inventory_item_id, location_id)` 在 `limits.catalog_flow.inventory_event_coalesce_window_ms`(1000) 內、且**仍在 `pending` 狀態**的事件，以 `dedupe_key` upsert 合併成一筆，`coalesced_count` 累加。
- **合併豁免**（`inventory_event_coalesce_exempt`）：`availability_flipped: true` 的事件**永不被合併掉**——它驅動快取 stamp、JSON-LD 的 availability、IndexNow、feed。漏掉它就是「已售罄的商品在前台還能加入購物車」。
- **ledger 不合併**。`inventory_adjustments` 是 append-only 稽核帳（13 §F5-1），每一筆都要有。合併的只有**事件**。

---

## D. 前台渲染路徑與快取

### D.1 資料怎麼到 Liquid（不走 HTTP）

28 §17 已定：Liquid SSR 渲染器使用**進程內 service objects**，drops 直讀 preloaded scope（25 §6-1）。**前台不打自己的 GraphQL Admin API**——那會讓每個商品頁多一次序列化與反序列化，且把 admin 的 cost 限流拖進買家路徑。

```
GET /products/byredo-la-selection-florale
 → ResolveShop（12 §F1，host → shop）→ ResolveMarket（29 §4 判定鏈：URL → GeoIP → backup region）
 → published theme（快取）→ templates/product.json → sections 逐個 render
 → build_drops: ProductDrop(preloaded: variants → inventory_item → inventory_levels,
                            media, options→values, metafields, collections)
 → Liquid::Template#render(context, registers: {shop:, theme:, market:, cdn:, render_flags:})
```

**N+1 防線**（11 §4-1、14 §F1-5）：每頁 SQL ≤15 條寫進 system test 斷言。商品詳情頁的 preload 是**一次**把 variants ＋ inventory_items ＋ inventory_levels 全載（一個商品最多 2048 變體，`limits.product.max_variants`——**超過 250 變體的商品其變體列表分批**，`limits.catalog_flow.variant_render_batch`）。

### D.2 渲染時查詢 vs 預先物化

| 欄位（Liquid 面） | 來源 | 為什麼 |
|---|---|---|
| `product.title/handle/description/vendor/type/tags` | 渲染時（products 一列） | 單列 |
| `product.variants[].price/compare_at_price/sku/...` | 渲染時（preload） | 商品頁本來就要全載 |
| **`product.price_min` / `price_max` / `price_varies`** | **物化** `products.min_price_cents` / `max_price_cents`（變體寫入時同 transaction 更新） | 集合頁 50 張卡不能各自 `MIN(variants.price)`。Ella 用 `price_min` 6 處、`price_varies` 5 處、`product.price` 96 處〔fixture〕 |
| **`variant.available`** | **物化** `product_variants.available_for_sale BOOLEAN` | `available` 的真值＝跨所有地點聚合 ＋ 判 policy ＋ 判 tracked。Ella 用 `.available` **106 處**〔fixture〕、`selected_or_first_available_variant` **209 處**〔fixture〕——它在**每一次渲染的熱路徑上**，不能是 join＋SUM |
| **`product.available`** | **物化** `products.available_for_sale`（由變體布林聚合） | 同上 |
| `variant.inventory_quantity` / `incoming` / `store_availabilities` | **渲染時查詢**，且標記為 volatile（§D.5） | 不能物化成「快取友善」的形式——它就是一個會一直變的數 |
| `product.selected_or_first_available_variant` | 渲染時計算（`?variant=` ∨ 第一個 `available_for_sale`） | 純函式 |
| presentment 價格（多市場） | 渲染時**批次**解析（§G） | 單一請求恆為單一市場 ⇒ N 變體 × 1 市場，一次查完，不是 N+1 |

**兩個名稱要對上官方**：Product 上的價格區間官方叫 `priceRangeV2` / `compareAtPriceRange`（61 §1.1，dev D1），且官方明載它是**衍生**的。我方的 `min_price_cents`／`max_price_cents` 是那個衍生值的物化，**GraphQL 對外仍用 `priceRangeV2` 的形狀**（`{minVariantPrice, maxVariantPrice}` MoneyBag），不得把內部欄位名洩到 API。

**🔴 前台可見性必須拆成兩個 scope**（61 §1.3，dev D3/D4：`ProductStatus` 是**四**態，多一個 `UNLISTED`）：

```
可購買（加入購物車 / 結帳）    := status IN (ACTIVE, UNLISTED) AND 已發布到該管道 AND 變體亦已發布（§H.2）
可被發現（列表 / 搜尋 / 系列 /
          推薦 / sitemap / feed / JSON-LD） := status == ACTIVE            AND 已發布到該管道 AND 變體亦已發布
```

- 13 §F1-6 現在只有一個 `Product.published` scope（「一處定義全站重用」）——**必須拆成 `purchasable` 與 `discoverable` 兩個**，否則 `UNLISTED` 商品要嘛完全買不到、要嘛會出現在搜尋與 sitemap 裡（後者是 SEO 事故：官方對 UNLISTED 明載輸出 `noindex,nofollow` 且排除於 sitemap）。
- 這對本篇的直接影響有三處：①`cache_stamp` 必須含 `products.status`（已由 `products.updated_at` 覆蓋）；②`Feeds::IncrementalJob` 與 `Seo::IndexNowPing` 的觸發條件用 `discoverable`；③`/cart/add.js` 的 guard 用 `purchasable`。**用錯一個就是「商品在搜尋裡出現但買不了」或「不該被索引的商品進了 sitemap」。**
- 登記於 §L-10（13 §F1-6 要改）。

**`available_for_sale` 的關鍵寫入策略（`flip_only`）**〔ours〕：

```
available: 5 → 4   ⇒ 只寫 inventory_levels，不寫 product_variants，不 bump updated_at
available: 1 → 0   ⇒ 跨越邊界！寫 product_variants.available_for_sale = false，bump updated_at
                     ⇒ cache_stamp 變 ⇒ 前台立即反映「已售完」
```

這一條同時解決三個問題：①避免每次扣減都讓前台快取失效（14 §F1 的 >90% 命中目標）；②「可買／不可買」是**即時**的（影響加入購物車按鈕、JSON-LD availability、feed）；③把「有界陳舊」限縮在**數量顯示**這一件事上（§D.5）。

`available_for_sale` 的判定式（唯一實作處，`Inventory::AvailabilityResolver`）：
```
available_for_sale = (NOT inventory_items.tracked)
                   ∨ (variant.inventory_policy == CONTINUE)
                   ∨ (Σ over active locations: inventory_levels.available > 0)
```

### D.3 快取階梯與 `cache_stamp`

沿用 14 §F1-3 與 25 §6-5 的四層，本篇把**商品維度的 key 組成**定死：

| 層 | key | 失效方式 |
|---|---|---|
| HTTP / CDN | 僅**靜態資產**（指紋 ＋ immutable）。**HTML 不進 CDN**（§D.4） | 指紋換檔名 |
| 頁級 fragment | `[shop_id, theme.version, template.updated_at, locale, market_id, currency, page_kind, resource_stamp]` | key-based |
| section 級 fragment | 上列 ＋ `[section_digest, 該 section 讀到的資料 stamp]` | key-based |
| AST cache | `theme_files.updated_at`（25 §6-2） | 寫檔即 bust |

**`product.cache_stamp` 的組成**（`limits.catalog_flow.cache_stamp_sources`）：

```
cache_stamp = MAX(
  products.updated_at,
  products.variants_updated_at,          -- 物化 rollup 欄，變體寫入時同 transaction 更新
  products.publications_updated_at,      -- 發布狀態變更（含 §H.2 的 ERROR）
  products.media_updated_at,
  shops.catalog_version,                 -- 全店級（分類法、稅則、metafield 定義變更）
  market_settings_version(market_id),    -- §G.5 市場繼承解析結果的版本
  price_list_updated_at(market_id)       -- §G
)
```

**兩條紀律**：

1. **`cache_stamp` 的組成必須覆蓋該 drop 實際讀過的每一張表。** 漏一個維度＝顯示舊值。這是 key-based 策略的**唯一**真實風險。
2. **對策是自檢，不是小心**：dev／staging 開啟 `render_flags` 追蹤模式——drop 每讀一張表就往 `context.registers[:touched_sources]` 註冊；render 結束後斷言 `touched_sources ⊆ cache_stamp_sources`，不符即 raise。放進 system test（§J-6）。這把「漏維度」從人工紀律變成可執行斷言。

### D.4 為什麼禁止 delete-based 失效與 HTML CDN 快取

| 策略 | 失效失敗會怎樣 | 判定 |
|---|---|---|
| **key-based expiry**（本專案唯一許可） | **不存在失效動作，也就不存在失效失敗**。舊 key 的 entry 變成孤兒，靠 LRU/TTL 自然淘汰 | ✅ |
| delete-based（`Rails.cache.delete`） | 刪除失敗／漏刪 ⇒ **前台永遠顯示舊價格，且沒有人會知道**（沒有錯誤、沒有告警、沒有自我修復） | ❌ 禁止（11 §4-3 既有規定，本篇重申並給出商品線的理由） |
| HTML 進 CDN + surrogate key purge | purge 是**跨網路的分散式操作**，會部分失敗、會延遲、會靜默。而 CDN 的 TTL 通常以小時計 | ❌ **首發不做**〔ours〕 |

**若日後要上 HTML CDN**（`limits.catalog_flow.html_cdn_cache_enabled: false`，開啟前必須先做到下列四條）：

1. surrogate key（Cache-Tag）**必須帶 shop 命名空間**：`s{shop_id}-p{product_id}`。缺了它，A 店的 purge 會清掉 B 店的快取，或更糟——purge key 碰撞導致跨租戶內容外洩。
2. purge 失敗**必須落表** `cache_purge_failures(shop_id, tag, attempts, last_error)` ＋ 告警。
3. **purge 連續失敗 ⇒ 自動降級**：該 shop 的 HTML 回應改送 `Cache-Control: max-age=0, must-revalidate`（`limits.catalog_flow.cdn_purge_failure_action: degrade_to_max_age_zero`）。**寧可全部回源，也不要顯示舊價格。**
4. 有一條「改價 → N 秒內 CDN 反映」的合成巡檢（比照 11 §5-4 的合成下單）。

### D.5 「顯示舊價格」到底是什麼等級的問題

任務裡的判斷是「顯示舊價格是**金額正確性問題**不只是體驗問題」。**這句話需要拆成兩半，兩半的結論不同**〔ours〕：

| 面向 | 會不會出錯 | 為什麼 |
|---|---|---|
| **結算金額** | **不會** | 11 §8 坑 7：一切金額 server 端重算，`PaymentIntent` 金額只來自 Calculator。cart line **存 `variant_id` 不存 price**，`/cart.js` 每次重算（25 §5）。所以前台顯示什麼，都不影響實際收多少 |
| **顯示價 ≠ 結算價** | **會，而且是雙重問題** | ①體驗：買家看 HK$938、結帳變 HK$1,200 ⇒ 直接棄單＋客訴。②**法遵**：誤導性價格標示在多數法域是消費者保護紅線（HK 為賣方基準法域，56 §B.5 明列「HK 消費者權利：不是少做一件事，是多做會出事」）——⚠ HK 具體條文未查證，V-92 |

**結論**：顯示舊價格**不是帳務錯誤，是法遵與體驗事故**。這個區分很重要，因為它決定了防線放哪：
- 帳務面的防線是 **server 端重算**（已在 15 號）。
- 顯示面的防線是 **key-based expiry ＋ cache_stamp 覆蓋自檢**（§D.3），**不是**「快取設短一點」。

**volatile 欄位的例外處置**——這是 golden theme 逼出來的：

```
test/fixtures/themes/ella-7.2.0：inventory_quantity 出現 41 次、橫跨 16 個檔案，其中包括
  snippets/card-product-flex.liquid   ← 🔴 商品卡！集合頁與輪播裡的每一張卡都讀它
  blocks/product-hot-stock.liquid / snippets/product-hot-stock-main.liquid   ←「僅剩 N 件」
  blocks/product-inventory.liquid / snippets/quantity-input.liquid
另：inventory_policy 25 處、inventory_management 18 處；incoming 與 next_incoming_date 皆 0 處
```

亦即：**照 Ella 渲染的集合頁，HTML 裡就有實際庫存數字。** 若庫存量變化不 bump cache_stamp（§D.2 的 `flip_only`），這個數字就會陳舊。

**處置（兩級 staleness 政策）**〔ours〕：

| 欄位級別 | 欄位 | 陳舊容忍 | 機制 |
|---|---|---|---|
| **price-critical** | price / compare_at / unit_price / presentment 價 / available_for_sale | **零容忍** | 這些欄位的變更都會 bump `cache_stamp` ⇒ key 變 ⇒ 下一次請求即新值。**不需要額外機制** |
| **volatile** | `inventory_quantity`、`incoming`、`next_incoming_date`、`store_availabilities` | **有界陳舊 ≤`limits.catalog_flow.volatile_section_ttl_seconds`(60)** | drop 被讀取時向 `context.registers[:render_flags]` 註冊 `:volatile`；該 fragment 的 cache entry **自動加 TTL 上限** |

```ruby
# app/liquid/drops/variant_drop.rb
# 為什麼在 drop 裡註冊而不是靠人工標註 section：
# 主題是第三方的（25 §0），我方無法要求商家的模板宣告「我讀了庫存量」。
# Liquid::Drop 在使用時會被注入 context ⇒ 這是唯一能自動偵測的位置。
def inventory_quantity
  @context.registers[:render_flags] << :volatile   # ⇒ 該 fragment TTL ≤ 60s
  @variant.inventory_levels.sum(&:available)       # preloaded，非 N+1
end
```

**這個組合的性質**：價格變更**即時**（key 變），數量變更**最多陳舊 60 秒**（TTL 兜底），兩者互不干擾——因為 key-based 與 TTL 是**兩個獨立的過期條件**，取先到者。

**必須誠實記錄的代價**：Ella 的商品卡讀 `inventory_quantity` ⇒ **集合頁的卡片 fragment 全部退化成 60 秒 TTL**，14 號的「匿名流量命中 >90%」在 Ella 下達不到。這是**相容性與快取命中率的真實對立**，我方選擇**正確性優先**，並把代價做成可觀測：
- 遙測 `liquid.volatile_render`（哪個主題、哪個 section 觸發降級），比照 25 §7 的 `liquid_method_missing` 儀表板。
- 主題匯入的 degradation report（25 §4-4）新增一節：「本主題有 N 個區塊讀取即時庫存量，這些區塊的快取時間將縮短為 60 秒」。

### D.6 三處價格必須同源（鐵律 7 的前台版）

同一個商品的價格在前台出現在**三個獨立的渲染路徑**：

| # | 路徑 | 觸發 |
|---|---|---|
| 1 | SSR 首屏 HTML | 進入商品頁 |
| 2 | **Section Rendering API 片段** | 切換變體（主題 JS 打 `?section_id=`，25 §5；Ella 的 `?view=` alternate template 亦同，27 §6.6） |
| 3 | **JSON-LD**（Product schema，14 §F5-1） | 同 1，但由 `structured_data` filter 或 SEO helper 產生 |

**規定**：三者必須呼叫**同一個** `Pricing::PresentmentResolver` ＋ **同一個** money formatter。
- 30 §6 品質硬規則：「feed 與 landing page 價格/庫存必須一致（misrepresentation → 拒登/停權）」「automatic item updates 以頁面 JSON-LD 即時校正 ⇒ **JSON-LD 與 feed 必須同一資料源生成**」。
- 加上 feed 就是**四處同源**：SSR / SRA / JSON-LD / GMC feed。
- 驗收：一支測試以同一個 variant + market 跑四條路徑，斷言四個字串完全相同（§J-6）。

### D.7 改了價格之後，前台什麼時候變（逐步時序）

| t | 發生什麼 | 買家看到 |
|---|---|---|
| t0 | 商家按儲存；transaction commit（含 `product_variants.updated_at`、`products.variants_updated_at`、outbox） | 舊價（快取中的舊 key entry 仍有效） |
| t0+ε | **下一個買家請求**：cache key 用新的 `cache_stamp` → MISS → 重算 | **新價** ✅ |
| t0+ε | 已經打開頁面的買家 | 舊價，直到重新整理。**加入購物車時以當前 DB 價重算**（金額不會錯） |
| ≤5s | dispatcher 撿走 outbox（18 §F1-2） | — |
| ≤5s | `CacheStampBumper` bump `collections.products_updated_at` | 集合頁與首頁 featured-collection **同樣在下一次請求即新價** |
| ~數秒 | `Feeds::IncrementalJob` 推 GMC Merchant API | 購物廣告價格更新（外部節奏） |
| ≥5 分鐘 | `Seo::IndexNowPing`（去抖，30 §5） | 搜尋引擎重爬 |
| 60s 內 | 讀 `inventory_quantity` 的區塊 TTL 到期 | 數量顯示更新（§D.5） |

**關鍵句**：**「前台什麼時候變」的答案是「下一次請求」，不是「失效傳播完成之後」。** 因為沒有失效動作。

---

## E. 庫存

### E.1 五態與譯名（本篇**不裁定**，維持現況）

60 §4 取得官方逐字定義（庫存頁欄位標題 tooltip）並建議「採庫存頁那套」。**61 §3.2 明確反對**：實站 UI 譯名在兩個頁面就已經不一致，說明它不穩；help 文檔的定義段落才是唯一同時給出「術語＋定義＋恆等式」的錨，而 **13 §F5.1 現用的正是 help 那套**——照 60 的建議改反而是**回退**。

| API enum（**一個都不改**） | 商品／變體頁（live） | 庫存頁（live，60 §4 建議） | **help 官方（61 §3.2）＝13 §F5.1 現況** |
|---|---|---|---|
| `unavailable` | 無法供貨 | 不可用 | **不可販售** |
| `committed` | 已承諾 | 已佔用 | **已分配** |
| `available` | 可供貨 | 可用 | **可販售** |
| `on_hand` | 現有庫存 | 現有庫存 | **現有庫存** |
| `incoming` | （不顯示） | 在途 | **待入庫** |

**本篇處置**：`limits.catalog_flow.inventory_display_terms_source: help_official`（＝維持 13 §F5.1 不動），**譯名取捨交 V-52（61 號提出）由使用者裁定**。API enum 與恆等式在三套譯名下完全相同，所以這個未決不阻擋任何實作——**唯一的要求是全站只用一套，不得逐頁不同**（那正是 Shopify 自己犯的錯）。

### E.2 恆等式的四條可執行斷言

`on_hand` 是 derived 不落庫（13 §F5.1(a)），所以「`on_hand = unavailable + committed + available`」在實作上是**定義**而非斷言。真正要守的是這四條：

| # | 斷言 | 什麼時候驗 | 既有？ |
|---|---|---|---|
| A1 | `inventory_levels.unavailable == Σ inventory_unavailable_buckets.quantity` | **每次寫入同 transaction 內**（雙寫必須一致）＋ nightly | 13 §F5.1(b) |
| A2 | `Σ ledger.delta per (level, state) == 現值` | nightly 重放對帳（連續 7 天 0 差異＝13 號驗收） | 13 §F5-3 |
| A3 | **`committed == Σ 未出貨的 fulfillment_order_line_items.quantity`（同 location）** | nightly | 🆕〔ours〕**13 與 16 都沒有這條**。committed 是唯一由訂單流程單向驅動的態（13 §F5 坑：後台不得手動改 committed），沒有這條跨聚合斷言，committed 漂移**永遠不會被發現** |
| A4 | `available >= 0` **除非** 該變體 `inventory_policy == CONTINUE`；`committed >= 0` 與 `unavailable >= 0` **無例外** | 每次寫入（條件式 UPDATE 的 WHERE）＋ nightly | 06 §5 有前半，後半為本篇補 |

**ledger 層的守恆規則**（🆕〔ours〕）：每一筆 `inventory_adjustments` 必須滿足下列之一——

```
純移動：Σ delta over states of the same adjustment == 0   （available → unavailable[damaged]）
外部進出：external = true ＋ 必填 reason ∈ limits.inventory.adjustment_reasons  （收貨、盤點、出貨）
```

這讓恆等式**在寫入當下就守住**，而不是等 nightly 才發現。沒有這條，`from_state/to_state` 只是兩個欄位，沒有任何約束力。

### E.3 每一次寫入都是狀態間移動

13 §F5.1(d) 已有完整的事件→移動對照表，本篇**不重寫**，只補上「哪支 mutation、哪個 transaction、發什麼事件」的欄位：

| 事件 | 移動（13 §F5.1(d)） | 觸發者 | 同 transaction 內 | outbox |
|---|---|---|---|---|
| 訂單成立 | `available → committed` | `Checkout::Complete`（15 號） | 地點指派 ＋ 條件式 UPDATE ＋ ledger | `inventory.level.changed`（`availability_flipped` 視情況） |
| 草稿保留 | `available → unavailable[draft_reserved]` 🔴 **不是 committed** | `draftOrderCreate` | 同上 | 同上 |
| 草稿轉正式單 | `unavailable[draft_reserved] → committed` | `draftOrderComplete` | 同上 | 同上 |
| 草稿保留到期 | `unavailable[draft_reserved] → available` | 排程 job（UUID v5 冪等鍵） | 同上 | 同上 |
| **出貨** | `committed → 出庫`（on_hand 隨之減少） | `fulfillmentCreate`（16 §F3 T9） | 同上 | `inventory.level.changed` ＋ `fulfillments/create` |
| 取消訂單（`restock: true`） | `committed → available` | `orderCancel`（**非同步 job**，28 §4） | 同上 | `orders/cancelled` |
| 取消訂單（未付款＋停用地點） | **不回補**（16 §F4.2） | 同上 | — | — |
| 建立退貨 | **不動任何數量**，僅標記待收 | `returnCreate` | delta = 0 的標記事件 | — |
| 退貨處理 `RESTOCKED` | `→ available`（選重新入庫地點） | `returnProcess`（強制冪等） | 同上 | `inventory.adjusted` |
| 後台調整 | `available ±` 或 `available ⇄ unavailable[子類]` | `inventoryAdjustQuantities`（強制冪等） | 同上 | `inventory.adjusted` |
| 轉移建立／收貨 | `→ incoming` ／ `incoming → available` | `inventoryTransfer*`（強制冪等） | 同上 | `inventory.adjusted` |

**兩條全域禁令**：

1. （13 §F5-2 既有，重申）**任何地方不准直接 `update(available:)`**，一律走 `Inventory::Adjust`；rubocop 自訂 cop 掃描。
2. 🔴 **`committed` 對 API／app 唯讀**（61 §3.5，dev D11 明載「committed 只受商家訂單的成立與履行影響」）。落地：GraphQL 的 `name` 參數不接受 `committed`；後台 UI 不給入口（13 §F5 坑既有）；ledger 中 `to_state = committed` 的列只能由訂單流程的 service 產生（service 白名單斷言）。**同一原則的另一個表現**：庫存 CSV 裡五態全部唯讀，唯一可寫的是 `On hand (new)`（61 §6.2）——**庫存的可寫入面只有 on_hand 與 available，其餘全部由事件驅動**。

**⚠ 草稿保留的目標狀態，官方正在遷移**（61 §3.3，V-53）：help（我方 13 §F5.1(d) 與 `limits.inventory.draft_reservation_target_state: unavailable` 的來源）說草稿保留進 `unavailable`；但 shopify.dev 的 **2026-08-05 changelog** 說「先前以 `reserved` 追蹤的草稿訂單、轉移與出貨庫存，正被移到 `committed`」。兩者是新舊模型的時間差，不是矛盾。
**本篇處置**：上表維持現況（`unavailable[draft_reserved]`）——我方的子桶設計比新模型**更能精準定位草稿到期回補**（13 §F5.1(c) 的既有理由）；但 §E.2 的斷言 A3（`committed == Σ 未出貨 FO 數量`）**在遷移後會需要把草稿保留量納入右式**。A3 的實作要把這個分支寫成一個開關（讀 `limits.inventory.draft_reservation_target_state`），**不要寫死**，否則 V-53 結案時要改的是斷言邏輯而不是一個設定值。

### E.4 超賣：條件式 UPDATE ＋ 多地點指派

**單地點（既有）**：

```sql
-- 一句話同時動兩態，保恆等式（不是兩句 UPDATE）
UPDATE inventory_levels
   SET available = available - :n, committed = committed + :n, updated_at = NOW()
 WHERE shop_id = :shop_id AND id = :level_id AND available >= :n;
-- affected rows == 0 ⇒ InsufficientStock（11 §3 三板斧之首：條件式 UPDATE）
```

`inventory_policy == CONTINUE` 時去掉 `available >= :n`（允許負數，13 §F5-4）。

**多地點（🆕〔ours〕，60 §3 的逐地點庫存表是它的 UI 佐證，13/16 皆未寫）**：

一張訂單的一個 line item 要從哪個地點扣？這牽出一個既有規格沒處理的競態：

> **地點指派**（決定 FulfillmentOrder 的 `assignedLocation`）**與 available 扣減若不在同一個 transaction**，兩個併發訂單可能都被指派到同一個只剩 1 件的地點，然後其中一個扣減失敗——但 FulfillmentOrder 已經建好了。結果是**一張永遠出不了貨的訂單**。

**硬規則**：

1. 地點指派與 available 扣減**必須同一 transaction**。
2. 扣減失敗（affected rows = 0）**不是整單失敗**，而是**重新指派到下一順位地點並重試**，上限 `limits.catalog_flow.location_assignment_max_retries`(3)。
3. 全部地點都失敗 ⇒ 才回 `InsufficientStock`。
4. 地點順位由既有的出貨地點規則決定（16 §F3）；**順位計算讀的是同一份 `inventory_levels`**（鐵律 7）。
5. **鎖順序全專案統一**（11 §3-2）：`shop → location → inventory_level`，避免死鎖。

**併發測試（🆕，補進 13 號驗收）**：兩個地點各 1 件、10 執行緒同時下單 2 件的商品 ⇒ **恰好 1 單成功**、`available` 皆為 0、恆等式成立、ledger 重放對得上。這是 13 號原本「100 執行緒不超賣」的多地點版，兩條都要。

### E.5 `compareQuantity` 是 CAS，不是驗證

`inventorySetQuantities(compareQuantity:)`（28 §3；22 §2 實測「on hand(current) 防過期校驗」）——這是**樂觀併發控制**，語義是「我看到的是 X，如果現在還是 X 就設成 Y」。

- 不符 ⇒ `userErrors{code: CHANGE_FROM_QUANTITY_STALE, field: ["quantities", "<i>", "changeFromQuantity"]}`，
  訊息帶**當前值**（讓 UI 直接顯示「現值已變為 7」）。
  <!-- 2026-08-15 兩處修正（本尊考掘，Admin API 2026-07）。原文：
       `userErrors{code: CONFLICT, field: ["compareQuantity"]}`。
       ① **`CONFLICT` 是折扣專屬的輸入驗證碼**（見 §A.4 的批註），庫存 CAS 用
          `CHANGE_FROM_QUANTITY_STALE`。
       ② 🔴 **`compareQuantity` 自 2026-04 起已從本尊 schema 移除**，改名
          `changeFromQuantity`（型別是 `Int` **nullable**，不是 `Int!`——changelog 說的
          「必填」是行為層要求「key 必須明確出現」，型別層做成 `Int!` 會讓官方明文的
          「傳 null＝關閉 CAS」逃生門消失）。
          ⚠ 但 enum 值**沒有**被換掉：`COMPARE_QUANTITY_STALE`／`COMPARE_QUANTITY_REQUIRED`
          在 2026-07 與 unstable 仍與 `CHANGE_FROM_QUANTITY_STALE` 並存。
       ③ **field 改成三段含索引**：單段 `["compareQuantity"]` 同時丟了層級與索引，
          `quantities` 是陣列，多筆一起送時前端無法定位是第幾筆
          （本尊實例：`["variants","0","metafields","0","value"]`）。
       🔴 本節其餘內容（CAS 不是驗證、不得先讀後寫、CSV 必須帶該欄）**完全不變**。 -->
- **不得**做成「先 SELECT 再比較再 UPDATE」——那是先讀後寫，與 28 §7 對抵用金／禮品卡的既有禁令（🔴 禁止先讀後寫）同一條紀律。正確寫法是把 compareQuantity 放進 `WHERE`。
- 庫存 CSV 匯入（60 §5 實測：**商品 CSV 與庫存 CSV 是兩套，官方明確要求分流**）**只准寫 on_hand 且必須帶 compareQuantity 欄**（22 §2 既有）。這使得「拿三天前匯出的檔案回灌」會逐行失敗而不是靜默覆蓋。

---

## F. 平台總後台（platform admin）對接

### F.1 三條硬約束

> **平台後台不得成為繞過租戶隔離的後門。** 這不是一句提醒，是三條可檢查的約束。

| # | 約束 | 檢查方式 |
|---|---|---|
| **F1-1** | **平台側的商品線指標一律走 rollup，不得直查租戶明細表**（`limits.catalog_flow.platform_product_access: rollup_only`） | CI 靜態掃描：`app/**/platform/**` 內出現 `Product`／`ProductVariant`／`InventoryLevel` 的查詢即 fail（`without_tenant` 也不放行）。比照 38 §12.3 既有的 `two_layer_isolation_spec.rb` |
| **F1-2** | **平台域 GraphQL schema 不存在任何回傳租戶商品明細的 field** | schema 快照測試（比照 56 §F-17「`Platform::` schema 中不存在跨租戶發卡 mutation」的既有做法） |
| **F1-3** | **平台不訂閱租戶的商品事件**（§C.5 最後一列） | outbox 消費者註冊表白名單；`Platform::` 下不得有 `subscribe_to :product.*` |

**唯一合法的例外通道**：`access_grants`（原型「請求存取商家後台」）——個案調閱，需原因碼 ＋ TTL ＋ 商家可見 ＋ 全程 `platform_audit_logs`（38 號）。**它是通道不是查詢**：走的是租戶自己的 admin GraphQL，帶著被授權的身分，因此天然受 `ActsAsTenant` 作用域約束。

### F.2 平台側能看到什麼（商品線的完整清單）

看原型 `docs/design/chilllove-platform-admin.html` 的 16 區：**沒有任何「商品」頁面**。全域搜尋（36 §2）可搜的是「商店／擁有者／網域／統編／訂單號／工單號」——**沒有商品**。這不是遺漏，是正確的預設。本篇把它明文化：

| 平台需求 | 資料來源 | 粒度 | 出處 |
|---|---|---|---|
| 配額用量（商品數／變體數／媒體用量） | `platform_shop_daily_rollups.products_count` 等 | 每店每日 ＋ 小時級 rollup job | 39 §配額：`Usage.current` **走 rollup，不即時 COUNT 全表** |
| 租戶列表的 GMV 級距篩選 | 同上（`gmv_30d_cents`） | 每店 | 39:2225 |
| 平台 KPI 六卡 / GMV 30 天 | `platform_daily_rollups`（**無 shop_id**，平台域表） | 每日全平台 | 36 §3 |
| **違禁品掃描命中** | `prohibited_scan_hits`（平台域） | 命中摘要，**不是商品表** | §F.3 |
| 前台合規巡檢 | 巡檢結果表 | 頁面級 | 38 號 |
| 個案調閱商品 | `access_grants` → 租戶 admin | 個案 | 38 號 |

**平台不得新增**：全平台商品搜尋、跨租戶熱銷榜、跨租戶價格比較、「所有商店的缺貨商品」列表。任何一個都需要跨租戶掃描 `products`——一旦開了，F1-1 的 CI 就得開例外，而例外會擴散。**要做這類功能，正確的路是讓租戶側 job 推聚合結果進平台域表（§F.3），不是讓平台去拉。**

### F.3 需要商品內容的功能：租戶推、平台不拉

違禁品掃描（38 號）是**唯一**需要讀租戶商品內容的平台功能。它的資料流方向必須反轉：

```
❌ 錯誤（後門）
   Platform::ProhibitedScanner
     └─ ActsAsTenant.without_tenant { Product.where("title REGEXP ?", rule) }   # 全平台掃商品表

✅ 正確（租戶推）
   Catalog::ProhibitedScanJob（每店一個 job，第一參數 shop_id，進場 with_tenant —— 11 §8 坑 1）
     └─ 在租戶作用域內比對 prohibited_rules（平台域的共用字典表，38 §12.3 已白名單）
     └─ 命中 ⇒ 寫一列 prohibited_scan_hits(shop_id, product_id, rule_id,
                                            matched_field, excerpt, detected_at)
                 excerpt ≤ limits.catalog_flow.scan_excerpt_max_chars(120)
   Platform::ViolationQueue
     └─ 只讀 prohibited_scan_hits（平台域表）。要看完整商品 ⇒ 走 access_grant
```

**為什麼這個方向重要**〔ours〕：
1. 掃描 job 在租戶作用域內跑 ⇒ **就算掃描器有 bug，它也只能看到一家店**。錯誤的爆炸半徑被 `with_tenant` 限住。
2. 平台只持有**摘要**（規則 id ＋ 命中欄位 ＋ ≤120 字節錄），不持有商品全文 ⇒ 平台域的資料外洩不等於租戶商品外洩。
3. 這條規則**可推廣**：日後任何「平台想知道租戶商品的某件事」的需求，答案都是「加一個租戶側 job 推聚合」，不是「加一個平台側查詢」。

### F.4 數字同源（鐵律 7）在商品線的落地

| 指標 | pulse 卡 | 列表 badge | 分析頁 | 平台後台 |
|---|---|---|---|---|
| 商品數 | `shops.products_count`（counter cache，寫入路徑維護） | 同一個 counter | 同一個 counter | `platform_shop_daily_rollups.products_count`（**該 counter 的快照**） |
| 缺貨商品數 | `shops.out_of_stock_count`（由 `available_for_sale` 翻轉時同 transaction 維護） | 同上 | 同上 | 同上快照 |
| 低庫存數 | 同上（閾值來自 `limits`） | 同上 | 同上 | 同上快照 |

**三條規則**：

1. **counter cache 由寫入路徑在同一 transaction 維護**，不是 `COUNT(*)`。`available_for_sale` 的 `flip_only` 策略（§D.2）讓「缺貨數」只在翻轉時變動——高頻扣減不會打到這個 counter。
2. **平台側是租戶 counter 的快照，不是重算**。任何「平台自己 COUNT 一次」的實作都同時違反鐵律 7 與 F1-1。
3. **rollup 有延遲，必須顯示 `dataFreshness`**（36 §4 既有欄位）；超過 `limits.catalog_flow.platform_rollup_staleness_warn_minutes`(60) ⇒ 顯示昨日值 ＋「資料延遲」註記，**不顯示 0**（36 §2 既有規則）。顯示 0 會讓平台人員以為租戶把商品刪光了。

### F.5 租戶隔離五層（比照 56 §B.3.2 的五層強制寫法）

| 層 | 商品線的落地 |
|---|---|
| **1 schema** | 商品線全表帶 `shop_id`，複合索引以 `shop_id` 開頭（鐵律 2）。`inventory_levels → inventory_items` 用**複合外鍵 `(shop_id, inventory_item_id)`**、`product_variants → products` 用 `(shop_id, product_id)`——比照 58 §G.1 對 `waybills` 與 56 §7.1 對 `gift_card_transactions` 的既有做法。**單欄外鍵在應用層漏檢時完全擋不住跨店關聯** |
| **2 應用** | `ActsAsTenant` 預設作用域；`without_tenant` 只准出現在 `app/**/platform/**`（36 §9 既有 CI） |
| **3 API** | `Platform::` schema 無商品明細 field（F1-2）；租戶 GraphQL 的 GID 解析**必驗 shop 歸屬**（§A.1 ②-⑸） |
| **4 資料流方向** | 需要商品內容的平台功能一律租戶推（§F.3） |
| **5 稽核** | `access_grants` 的每一次調閱落 `platform_audit_logs`（含 previous/next JSON，38 號） |

**第 6 個破口（前台側，容易被漏掉）**：14 §F2 坑已指出「`collection_picker` 等 reference 型設定要驗該 ID 屬於本店（跨租戶引用是隔離破口）」。商品線的對應：

- theme settings 的 `product` / `product_list` 型設定值（26 §settings 型別表）存的是 handle 或 GID，**渲染期解析必須帶 shop_id**。
- `all_products['handle']` drop（Liquid 的全域商品查找）的查詢**必須在租戶作用域內**——這是主題模板可以直接寫的東西，若解析器忘了帶 shop_id，一個商家在自己的主題裡寫 `all_products['competitor-product']` 就能讀到別家的商品。
- 驗收：一條 system test，A 店主題引用 B 店商品 handle ⇒ 回 `nil`（Liquid 空值，不是 500）。

### F.6 既有規格的內部矛盾（必須回頭修）

36 §3 定義的 `platform_daily_rollups` 欄位是 `date / shops_* / orders_count / gmv_cents / refunds_cents / finalized_at`，**唯一索引 `(date)`，沒有 `shop_id`**。
但 39:2225 寫 `scope.joins(:latest_rollup).where("platform_daily_rollups.gmv_30d_cents >= ?", ...)`——這需要**每店一列**，且欄位 `gmv_30d_cents` **不在 36 §3 的欄位表裡**。

**兩者不可能同時成立。** 本篇的處置：定義商品線需要的是 **`platform_shop_daily_rollups(shop_id, date, products_count, variants_count, out_of_stock_count, media_bytes, gmv_30d_cents, …)`**（**帶 `shop_id`，符合鐵律 2，不需要豁免**），與 `platform_daily_rollups`（平台日總計，平台域豁免表）是**兩張表**。39:2225 引用的欄位歸前者。登記於 §L-2 —— **本篇不改 36/39，只登記。**

---

## G. 多市場價格（presentment）

### G.1 存什麼、算什麼

| 資料 | 存哪 | 幣別 |
|---|---|---|
| 基準價 | `product_variants.price_cents` / `compare_at_price_cents` | **shop currency**（記帳幣別，29 §3.1） |
| 固定價（覆蓋） | `price_list_prices(price_list_id, variant_id, price_cents, compare_at_cents)`，只存 FIXED（29 §1.4） | price list 的幣別（＝市場幣別） |
| 百分比調整 | `price_lists.adjustment_type / adjustment_value` | — |
| 匯率 | `currency_exchange_rates` | — |
| **presentment 價** | **不存**（渲染時算） | 買家幣別 |

**訂單成立時才落地**：`MoneyBag{shopMoney, presentmentMoney}` 雙記 ＋ `orders.exchange_rate_at_order`（29 §3.1/3.4）。**商品層永遠不物化 presentment**——市場 × 變體的乘積會爆炸，且匯率變動會讓物化值全部作廢。

### G.2 解析器：`Pricing::PresentmentResolver`

```
call(variant, market, currency) →
  ① catalogs = 沿 market lineage 累加（29 §1.5(c)：catalogs 是 additive）
     └─ lineage 讀 markets.derived_parent_market_id（推導快取，非權威欄位）
  ② fixed = MIN(price_list_prices WHERE price_list ∈ catalogs.price_lists AND variant = ?)
     └─ 多 catalog 命中同商品取 MIN——照抄 28 §13b H-66 的 B2B 規則
        〔ours：官方 H-66 只講 company location；本篇延伸適用於所有市場類型，
          理由是不延伸就會有「兩個 catalog 命中時行為未定義」。V-93〕
  ③ fixed 存在 ⇒ 直接用（🔴 fixed price 不換算、不湊整，29 §3.3）
  ④ fixed 不存在 ⇒ base × (1 ± adjustment) × 匯率 × (1 + 轉換費率) → rounding
  ⑤ 全程 integer（§G.3）
```

**批次化**：單一買家請求恆為單一市場（29 §4 判定鏈），所以集合頁 50 張卡是 `50 variants × 1 market` ⇒ **一次 `WHERE variant_id IN (...)` 查完**，不是 N+1。批次結果進 Solid Cache，key ＝ `[market.settings_version, price_list.updated_at, variant_ids_digest]`。

### G.3 全程整數的算法（鐵律 3）

**中間值一律放大到 micro-cents（`cents × 10^6`）計算，只在最後一步取整一次。**

```ruby
# limits.catalog_flow.price_scale_internal: micro_cents
# limits.catalog_flow.exchange_rate_storage: rate_ppm   # 匯率存 parts-per-million 的 BIGINT
#
# 為什麼不是每一步都取整：三次連續整數除法（調整% → 匯率 → 轉換費）
# 每次截斷最多差 1 cent，三次就是 3 cents ——在 HK$1,480 上是可見的錯誤，
# 而且不同呼叫順序會得到不同結果（違反鐵律 7 數字同源）。
micro  = base_cents * 1_000_000
micro  = micro * (10_000 + adjustment_bp) / 10_000        # 百分比調整（basis points）
micro  = micro * rate_ppm / 1_000_000                      # 匯率
micro  = micro * (10_000 + conversion_fee_bp) / 10_000     # 轉換費率 150bp / 200bp（29 §3.2）
cents  = (micro + 500_000) / 1_000_000                     # 🔴 唯一一次取整（四捨五入）
cents  = Rounding.apply(cents, currency, market)           # 湊整規則（29 §3.3），僅在啟用時
```

**三條禁令**：
- ❌ `rate` 存 float／decimal 後 `to_f`——匯率必須是 `rate_ppm BIGINT`。29 §1.4 的 `currency_exchange_rates(base/quote/rate/…)` **未指定型別**，本篇補上（§L-5）。
- ❌ 逐步取整。
- ❌ 前端算 presentment。前端只顯示後端算好的字串。

### G.4 顯示兩位小數 vs PSP minor unit（🔴 救命條款）

**這是本節最容易造成 100 倍金額事故的地方。**

裁定二（2026-08-12）＋ `limits.currency_display`：**所有國家一律顯示兩位小數，儲存一律 ×100**。所以 JPY 的 ¥1,480 顯示 `¥1,480.00`、儲存 `148000`。

**但 PSP 的金額格式與參數由該 PSP pack 明文宣告**（`amount_format: minor_units | decimal_string`，65 §A R6／§D）：Stripe 收 JPY 時 `amount: 1480` 代表 ¥1,480（Stripe pack＝minor_units、JPY minor unit=1480 形態）；**Airwallex 根本不用 minor unit，收十進位主單位**<!-- 2026-08-31 更正：原文此處寫「字串 "1480"」——一手複驗為 JSON number（65 R7／§D.4）；「不用 minor unit」不變。 -->。**若把儲存的 `148000` 直接送出去，收款金額是 ¥148,000——100 倍**（兩種格式都會錯，只是字面不同）。**ISO 4217 只是 `minor_units` 格式下 pack 可以選擇的底表，不是換算基數**——Adyen 明文覆蓋 ISO、Stripe 對 HUF／TWD 另有整除約束（69 §V-188，`alt`×4＝PSP 官方文檔）。

**硬規則**：跨界轉換的唯一出口＝`Money::Storage#to_psp_amount(psp:)`，**契約全文與參考實作見 65 §D.1，本檔不再自帶代碼**——依 pack 宣告的 `amount_format` 分流為 `Money::PspMinor`（R5）或 `Money::PspDecimal`（R6），斷言 A0–A6 逐條見 65 §D.2。

<!-- 依 65 §J M-8（69 §V-188）修正（2026-08-13），原文三塊：
     ① 「但 PSP 的金額單位依 ISO 4217：Stripe 收 JPY 時 amount: 1480 代表 ¥1,480（JPY exponent = 0）。」
     ② 硬規則〔ours，新增 limits.currency_display.psp_minor_unit_follows_iso4217: true〕＋
        def self.to_psp_minor_unit(storage_cents, currency) 的完整代碼塊
        （exponent = Iso4217.exponent(currency)；divisor = 10 ** (2 - exponent)；餘數 raise；storage_cents / divisor）。
     修正理由：本節的**方向完全正確**（它是 65 號的來源之一，「儲存≠對外」的洞見不變），但成文時的世界觀是
     「PSP＝整數 minor unit，只是 exponent 各異」——69 號查到四家 PSP 四種算法後，該世界觀不完整。
     代碼塊**整個刪除、不留簡化版**：裸 (Integer, String) 簽名正是 65 §C L1–L3 要禁的形態
     （無 psp 綁定、無值物件、可被任何呼叫方拿 ISO 當基數重現 100 倍）。
     🔴 這不是放寬：本節要擋的 100 倍事故一個字都沒鬆，只是它擋的形態比原本以為的多一種（R6）。
     limits 鍵處置：psp_minor_unit_follows_iso4217 同輪改名 psp_amount_format_declared_per_pack（見 §9 鍵表與 limits.yml）。 -->

- **三位小數幣別（KWD/BHD/JOD，exponent = 3）**：**市場可建立、幣別可選**；儲存與顯示一律 2 位、精度損失明文登記（62 §L.5 的 KWD 全鏈路表）；**收款在轉換點被擋**——`minor_units` pack 宣告 exponent 3 ⇒ A2 reject；`decimal_string` pack 宣告位數 >2 ⇒ A6 使 pack 不得 enable。日後要真支援，改的是 `storage_multiplier`（全庫 migration），不是轉換函式。⚠ V-94
  <!-- 本條的修正出處是 68 §D-3（跟隨 Shopify：不擋幣別），與上方 V-188（格式維度）是兩個不同根因，故留兩條註釋。
       原文：「本篇裁定：首發不支援 exponent > 2 的幣別（limits.catalog_flow.unsupported_currency_exponents: [3]），
       market 建立時擋下並回 userErrors{code: INCLUSION}。」——「market 建立時擋」這個執法點已被 68 §D-3 移除
       （62 §L.5 已先落地，本檔至今殘留，正是 62 §L.5 警告的「規格說擋、鍵說不擋」分裂的規格側）。
       🔴 不是鐵律 3 放寬：改的是幣別清單，金額邊界的執法點（A2／A6）反而更清楚。 -->
- **餘數不為 0 ⇒ 直接 raise**，不四捨五入〔`minor_units` 分支，65 §D.2 A3；`decimal_string` 分支的對應是 A6 位數檢查〕。JPY 的 `148050`（¥1,480.50）不可表達 ⇒ 這是上游算錯了（湊整規則沒套用），要炸出來而不是悄悄抹掉 50。
- **驗收**：一支表格驅動測試涵蓋 JPY/HKD/TWD/USD/KWD × 邊界值（0、1、最小可表達、極大值）× **兩種 `amount_format` 各一個 fixture pack**（65 §H.1），斷言往返一致（§J-6）。

### G.5 與 P0-02 市場父子繼承的接縫

P0-02 剛做的市場繼承（29 §1.5）對商品價格的影響有三處：

| 維度 | 繼承語義 | 對價格解析的影響 |
|---|---|---|
| `catalogs` | **累加**（additive） | §G.2 ①：沿 lineage 收集全部 catalog ⇒ 可能多個 price list 同時命中 ⇒ 取 MIN（§G.2 ②） |
| `currencySettings` | **覆寫**（override，`NULL` ⇒ 繼承） | 決定 presentment 幣別與是否 local currencies；`market_settings['currency'] IS NULL` ⇒ 沿 lineage 上溯 |
| `priceInclusions` | **覆寫** | 含稅價／未稅價的顯示——影響 §D.6 的三處同源（三處必須用同一個 inclusion 判定） |

**cache_stamp 必須含 `market_settings_version`**（§D.3）：市場的繼承解析結果變了（例如父市場改了幣別、或 conditions 變更導致 `derived_parent_market_id` 重算），**價格就變了，但商品的 `updated_at` 一動也沒動**。漏掉這個維度＝改了市場設定前台不變——這是 §D.3 紀律 1 的最典型踩法。

`market_settings_version` 的維護：`markets` 或 `market_settings` 任一寫入 ⇒ 同 transaction 內 bump（`derived_parent_market_id` 的子樹重算已經在同 transaction，29 §1.5(a)）。

### G.6 排序：有 fixed price 的市場不能用物化欄

集合頁「價格由低到高」預設用物化的 `products.min_price_cents`（**shop currency**）。
- 只有百分比調整的市場：所有商品同比例縮放 ⇒ **排序不變** ⇒ 可用物化欄 ✅
- 有 fixed price 的市場：fixed 破壞了單調性 ⇒ **必須用該市場的解析價排序**

**做法**：`LEFT JOIN price_list_prices ON (price_list_id = :pl, variant_id) ORDER BY COALESCE(fixed_price_cents, min_price_cents * adj / 10000)`，索引 `(price_list_id, variant_id)` ＋ `(price_list_id, price_cents)`。
**不物化 `variant_market_prices` 表**——variants × markets 的乘積會爆炸，且匯率變動時全表作廢。

---

## H. 失敗與補償

### H.1 逐環節失敗表

| # | 環節 | 失敗表現 | 商家看得見嗎 | 偵測 | 補救 |
|---|---|---|---|---|---|
| 1 | GraphQL 驗證 | `userErrors`，HTTP 200，表單欄位標紅 | ✅ 即時 | — | 改正重送 |
| 2 | 樂觀鎖衝突 | `STALE_OBJECT` ＋ 持有者姓名（§A.4） | ✅ 即時 | — | 重載或顯式覆蓋 |
| 3 | transaction | 整筆 rollback，`INTERNAL_ERROR` ＋ requestId | ✅ 即時 | Sentry | 重送（B 類有 idempotencyKey 保護） |
| 4 | outbox 寫入 | **不可能單獨失敗**（同交易） | — | — | — |
| 5 | dispatcher | 事件停 `pending`；`attempts ≥ 8` ⇒ `dead` | ❌ **商家看不見** | 佇列深度告警（11 §5-3）＋ dead 事件告警 | 後台重推（18 §F1-5） |
| 6 | 快取 | 無失效動作 ⇒ 無失效失敗 | — | stamp 覆蓋自檢（§D.3） | — |
| 7 | 媒體處理 job | 圖片停在 processing | ✅ 商品頁圖格顯示「處理中／處理失敗」 | job 失敗告警 | 標「處理失敗」**不無限重試**（13 §F3 坑）；前台 fallback `placeholder_svg_tag` |
| 8 | **銷售管道發布** | `product_publications.status = ERROR` | ✅ **列表可排序、商品頁顯示原因**（§H.2） | 錯誤數告警 | 修正後重試 |
| 9 | smart collection resync | membership 過時 | ❌ | nightly 全量對帳 | 重跑 `Collections::RebuildJob` |
| 10 | 搜尋索引 | 新商品搜不到 | ❌ | 索引落後量指標 | `rake catalog:rebuild:search` |
| 11 | feed / IndexNow | 外部 4xx/5xx | ✅（30 §9-13 儀表板） | 拒登率監控 | 退避重試；429 依 `Retry-After` |
| 12 | ledger 對帳 | nightly 差異 | ✅ 告警 | 13 §F5-3 重放 | 人工調整 ＋ 稽核（`inventory_adjustments` 記 actor） |

**第 5、9、10 列是「商家看不見」的**——這三類必須有平台側的健康指標（39 號可靠性頁的佇列深度／死信卡已涵蓋 5；9 和 10 需要新增落後量指標）。

### H.2 發布到銷售管道**會失敗**，而且失敗要能被看見

60 §5 的實站證據：商品列表的排序選單有一個維度叫 **`發布錯誤`**（與產品名稱／庫存／產品類型／廠商／建立時間／更新時間並列）。

**這條實測結論反推出一個我方完全沒有的模型**：發布不是商品上的一個布林欄位，而是**跨系統的非同步操作，會失敗，且失敗要能排序**。

**發布是兩層的，不是一層**（60 §2 實測有變體表的「發佈」欄；61 §2.2 引 help P16：**可逐變體對各銷售管道／目錄發布**，且**「要在某管道顯示，父商品與該變體必須都發布到該管道」是一條 AND 規則**；**變體不能設排程發布日期**）。

**資料模型（🆕）**：

```sql
product_publications(
  shop_id, product_id, publication_id,          -- 複合外鍵 (shop_id, product_id)（§F.5 第 1 層）
  status ENUM('PENDING','PUBLISHED','ERROR','UNPUBLISHED'),
  published_at, publish_at,                     -- 排程上線（商品級才有）
  error_code, error_category, error_message, attempts, last_attempt_at,
  UNIQUE (shop_id, product_id, publication_id),
  INDEX (shop_id, status, updated_at)           -- 支撐「發布錯誤」排序（鐵律 2：shop_id 開頭）
)

variant_publications(                            -- 🆕 我方原本完全沒有變體級發布
  shop_id, product_variant_id, publication_id,
  published BOOLEAN,                             -- 🔴 沒有 publish_at：官方明載變體不可排程發布
  UNIQUE (shop_id, product_variant_id, publication_id),
  INDEX (shop_id, publication_id, published)
)
```

**AND 規則的落地**（§D.2 的兩個 scope 都要帶上這一層）：

```
變體在某管道可見 := product_publications.status == 'PUBLISHED'
                  AND variant_publications.published == true
```

- `Product.purchasable` / `discoverable` 兩個 scope **必須加變體層過濾**；只做商品級過濾會**洩漏未發布的變體**（61 §2.2 逐字警告）。
- 連帶影響 §D.2 的物化欄：`products.min_price_cents` 的 `MIN()` **必須只算該管道可見的變體**——否則會出現「集合頁顯示 HK$938 起，點進去最低只有 HK$1,200」。多管道 ⇒ 每個 publication 一組 min/max，這會讓物化欄變成 `product_publication_price_ranges(shop_id, product_id, publication_id, min_cents, max_cents)`。**首發若只有一個線上商店管道，退化成單列**，但**表要一開始就這樣建**（同 56 §7.1「schema 取聯集」的紀律：日後加管道時不必停機 migration）。
- 目錄定價的連帶規則（61 §2.2）：**未發布到某目錄的變體不套用該目錄的定價調整** ⇒ §G.2 的 `PresentmentResolver` 在收集 catalog price 時要先過 `variant_publications` 過濾。

**為什麼會失敗**〔ours〕：銷售管道各有自己的驗證——Google Merchant 要 GTIN 與圖片規格、Meta catalog 要商品分類、市場 catalog 要商品在該 catalog 的 publication 內（29 §1.3：未發佈到市場 catalog ⇒ 前台隱藏）。**這些驗證發生在我方 transaction 之外、在別人的系統裡。**

**行為**：

1. `publishablePublish` 的語義是**排入發布佇列**，回傳 `status: PENDING`，不是「已發布」。
2. `Publishing::SyncJob` 消費 `product.publication.changed` → 呼叫管道 API → 寫回 `PUBLISHED` 或 `ERROR`。
3. `ERROR` ⇒ **不重試到死**：退避重試 `limits.catalog_flow.publication_retry_max_attempts`(5)，之後停在 ERROR 等商家處理。
4. UI（對齊 60 §5）：
   - 列表排序維度「發布錯誤」＝ `ORDER BY (status = 'ERROR') DESC, updated_at DESC`。
   - 商品頁「發布」卡逐管道顯示狀態 ＋ 錯誤原因 ＋〔重試〕。
5. **`ERROR` 不影響商品本身的 `status`**：商品仍是 ACTIVE，只是某個管道沒上架。兩者是正交軸（同 06 §4 對 Order 沒有單一 status 的處理）。

### H.3 統一補救原則：投影可重建

**商品線沒有補償交易（saga）。** 所有 DB 寫入在一個 transaction 內，要嘛全成要嘛全敗；transaction 外的**每一樣東西都是投影**。

**規定**：每一個投影都必須有一支全量重建任務，且**重建結果與增量結果必須一致**（可測）：

| 投影 | 重建任務 |
|---|---|
| 快取 | 不需要（key-based，自然淘汰）；theme publish 後跑預熱（14 §F1 坑） |
| smart collection membership | `rake catalog:rebuild:collections SHOP=x` |
| 搜尋索引 | `rake catalog:rebuild:search SHOP=x` |
| 物化欄（min/max price、available_for_sale、counter cache） | `rake catalog:rebuild:materialized SHOP=x` |
| feed | `rake catalog:rebuild:feed SHOP=x MARKET=y` |
| 發布狀態 | `rake catalog:resync:publications SHOP=x`（重新查管道現況，不是重推） |
| 平台 rollup | 既有 `Platform::Metrics::DailyRollupJob`（冪等 upsert，36 §5） |

`limits.catalog_flow.projection_rebuild_tasks` 列出全清單——**新增投影必須同時新增重建任務**，CI 斷言清單與 rake task 一一對應。

**一致性測試（每個投影一條）**：建 100 個商品 → 跑增量 → 跑全量重建 → **斷言兩者結果完全相同**。這是唯一能證明「重建真的能救」的方法。

---

## I. `config/limits.yml` 新增的鍵

> 依鐵律 6，全部上限與政策值進 limits。本輪**只新增鍵，不改既有鍵的值**。

| 區塊 | 鍵 | 值 | 出處 |
|---|---|---|---|
| `idempotency` | `required_for_catalog_create` | 6 支 B 類 mutation | 63 §A.3（ours） |
| `idempotency` | `catalog_create_merge_pending` | `true` | 63 §A.3（合併進 `required_for` 需同步改 CI 斷言） |
| `currency_display` | `psp_amount_format_declared_per_pack` | `true` | 63 §G.4（ours，🔴 救命條款）<!-- 依 65 §J M-8 修正（2026-08-13），原鍵名 psp_minor_unit_follows_iso4217——minor unit 與 follows ISO 兩個字面在 V-188 後都不成立，limits.yml 同輪改名（deprecation 註釋在鍵位原處） --> |
| `catalog_flow`（新頂層區塊） | 見下 | — | 63 全篇 |

`catalog_flow` 的內容（實際已寫入 `config/limits.yml`）：

`catalog_flow` 的 45 個鍵（實際已寫入 `config/limits.yml` 第 18 區塊）：

```
B 寫入語義  product_min_variants(1) / default_variant_liquid_title("Default Title") / sku_owner(inventory_item)
            sku_unique_per_shop(false) / sku_duplicate_action(warn_not_block) / sku_recommended_max_chars(16) ⚠V-91
            product_input_forbidden_fields / product_write_entry_mutation(productSet)
            variant_price_write_mutations / initial_quantity_allowed_on_create_only(true)
D 快取      cache_strategy(key_based_expiry_only) / cache_stamp_sources(7 項) / cache_stamp_selfcheck_envs
            html_cdn_cache_enabled(false) / cdn_surrogate_key_template / cdn_purge_failure_action
            volatile_liquid_fields / volatile_section_ttl_seconds(60) ⚠V-96 / price_critical_fields_zero_staleness
E 庫存      availability_materialization(flip_only) / inventory_display_terms_source(help_official) ⚠V-52
            inventory_event_coalesce_window_ms(1000) / inventory_event_coalesce_exempt
            location_assignment_max_retries(3)
G 多市場    price_scale_internal(micro_cents) / exchange_rate_storage(rate_ppm)
            unsupported_currency_exponents([3]) ⚠V-94 / multi_catalog_price_resolution(min) ⚠V-93
H 發布      publication_retry_max_attempts(5) / publication_retry_backoff_seconds / publication_error_categories ⚠V-98
            variant_level_publishing(true) / variant_publish_scheduling_allowed(false)
            catalog_pricing_requires_variant_publication(true)
F 平台      platform_product_access(rollup_only) / platform_rollup_staleness_warn_minutes(60) / scan_excerpt_max_chars(120)
其他        admin_list_page_size(50) / variant_render_batch(250) / projection_rebuild_tasks(5 支)
```

---

## J. 本篇驗收（對照 `docs/specs/11` §0 七維度）

### 1 安全

- [ ] 商品寫入的權限在**伺服器端**強制（`write_products` scope ＋ staff 角色，12 號）；admin SPA 的欄位 disabled 不算數。
- [ ] 富文本描述存前 sanitize ＋ **前台輸出再 sanitize 一次**（13 §F1 雙保險）；XSS 測試集全數消毒。
- [ ] GID 解析必驗 shop 歸屬；theme settings 的 `product`/`product_list` 引用跨租戶 ⇒ 回 nil（§F.5 第 6 破口，一條 system test）。
- [ ] `Platform::` schema 快照測試：無任何回傳租戶商品明細的 field（F1-2）。
- [ ] CI 靜態掃描：`app/**/platform/**` 內無 `Product`/`ProductVariant`/`InventoryLevel` 查詢（F1-1）。

### 2 資料完整

- [ ] `products` 表無 price/sku/庫存欄位；`ProductInput` schema 快照無禁用欄位（B1-1、B1-5）。
- [ ] `COUNT(variants) >= 1` 斷言；刪最後一個變體回 `LAST_VARIANT_REQUIRED`（B1-2、B1-4）。
- [ ] 加／刪選項時**變體 id 不變**（§B.5）：一條測試建立無變體商品 → 加選項 → 斷言原 variant.id 與 inventory_item.id **完全相同**、ledger 連續。
- [ ] B 類 mutation 缺 `idempotencyKey` ⇒ **執行期報錯**（不是靜默通過），與既有 `required_for` 同一個檢查點（§A.3）。
- [ ] 複合外鍵：`(shop_id, product_id)`、`(shop_id, inventory_item_id)` 皆為 DB 級 FK（§F.5 第 1 層）。
- [ ] 庫存四條斷言 A1–A4 全部有 nightly job（§E.2），**含新增的 A3**（committed vs 未出貨 FO 數量），且 A3 的草稿保留分支讀 `limits.inventory.draft_reservation_target_state` **不寫死**（V-53）。
- [ ] **變體級發布**：`variant_publications` 存在；`purchasable`／`discoverable` 兩個 scope 皆含 AND 條件；一條測試「商品已發布、變體未發布」⇒ 該變體在前台不可見、不可加購、不進 feed（§H.2）。
- [ ] **`UNLISTED` 四態**：一條測試斷言 UNLISTED 商品「直連可買」但「不進搜尋／系列／sitemap／feed 且輸出 noindex」（§D.2）。

### 3 併發

- [ ] 兩個 staff 同時儲存同一商品 ⇒ 後者收 `STALE_OBJECT` ＋ 持有者資訊，**不是靜默覆蓋**（§A.4）。
- [ ] 單地點超賣測試：100 執行緒（13 號既有）。
- [ ] **多地點超賣測試（新增）**：2 地點各 1 件、10 執行緒下單 2 件 ⇒ 恰好 1 單成功，恆等式成立（§E.4）。
- [ ] `changeFromQuantity` 不符回 `CHANGE_FROM_QUANTITY_STALE` ＋ 當前值；**代碼中無「先 SELECT 再 UPDATE」**（rubocop cop）。
- [ ] 事件亂序測試：把兩個 `product.variant.updated` 反序投遞給搜尋索引消費者 ⇒ 最終索引值為**新版本**（§C.3 ③）。

### 4 效能

- [ ] 商品詳情頁 SQL ≤15 條、集合頁 ≤15 條（system test 斷言，14 §F1-5）。
- [ ] 集合頁 50 卡的 presentment 價格為**一次批次查詢**（不是 50 次，§G.2）。
- [ ] 庫存扣減 `available: 5 → 4` **不 bump** `product_variants.updated_at`（`flip_only`，§D.2）；`1 → 0` 會 bump。
- [ ] 快取命中：不含 volatile 欄位的主題 >90%；**Ella（含 volatile）的實測值記錄在案並可解釋**（§D.5 的代價）。
- [ ] 平台側 `Usage.current` 走 rollup，**斷言不對 `products` 全表 COUNT**（39 號既有斷言，本篇沿用）。

### 5 可觀測

- [ ] 結構化日誌帶 `request_id` ＋ `shop_id`（11 §5-1）；商品寫入額外帶 `product_id`、`mutation_name`、`changed_fields`。
- [ ] 指標：outbox 佇列深度與 dead 數、投影落後量（smart collection／搜尋索引）、`liquid.volatile_render` 命中、發布 ERROR 數、cache_stamp 自檢失敗數、庫存 nightly 對帳差異。
- [ ] `product_publications.status = ERROR` 的商品數有 dashboard 與告警（§H.2）。

### 6 測試

- [ ] **四處價格同源**：同一 variant × market 的 SSR HTML／SRA 片段／JSON-LD／GMC feed 四個字串完全相同（§D.6）。
- [ ] **PSP 換算表格驅動測試**：JPY/HKD/TWD/USD/KWD × 邊界值往返一致；exponent = 3 的幣別在 market 建立時被擋（§G.4）。
- [ ] **投影一致性**：每個投影跑「增量 vs 全量重建」結果相同（§H.3）。
- [ ] **cache_stamp 覆蓋自檢**：staging 開啟 `touched_sources` 追蹤，商品頁／集合頁／搜尋頁全綠（§D.3）。
- [ ] **golden theme**：Ella 7.2.0 的無變體商品渲染正確（`Default Title` 契約，§B.2），商品卡不出現空變體選擇器。
- [ ] 金額代碼 100% 覆蓋（11 §0 維度 6）——`Money.parse_to_cents`／`PresentmentResolver`／`Money::Storage#to_psp_amount` 三支尤其。<!-- 依 65 §J M-8 修正（2026-08-13），原文點名 to_psp_minor_unit——該裸簽名函式已隨 §G.4 改寫刪除；驗收清單點名不存在的函式會反向鎖死舊實作。 -->

### 7 合規／隱私

- [ ] 商品事件 payload 無 PII、無金額值（§C.2 紀律 1/2）。
- [ ] `prohibited_scan_hits.excerpt` ≤120 字（§F.3）；平台人員看完整商品必經 `access_grant` ＋ 審計。
- [ ] 顯示價 ≠ 結算價的法遵風險已登記（V-92）；HK 為賣方基準法域（56 §B.5）。
- [ ] 媒體 EXIF strip（含 GPS）在上傳處理 job 內完成（13 §F3-3）。
- [ ] `inventory_adjustments` 保留 `limits.inventory.adjustment_history_retention_days`(180) 天，有 purge 任務。

---

## K. 待查證（V-90 起）

> **編號從 V-90 而非 V-70 起**：本輪同時產出的 `docs/research/61` 與 `docs/specs/62` 已占用到 **V-76**（且兩者在 V-60～V-70 互相重疊，那是它們之間要收斂的事）。為避免第三次碰撞，本篇讓開整段，自 V-90 起編。
>
> **本篇依賴、但由 61 號登記的三條**（不重複編號，實作前一併看）：**V-52** 庫存五態的 zh-TW 譯名取捨（§E.1）｜**V-53** 草稿保留的目標狀態正在遷移（§E.3）｜**V-55** 調整原因 help 7 項 vs dev 17 項的對應表（ledger 的 `reason` 值域）。

| # | 項目 | 為什麼不能現在決定 | 暫時處置 |
|---|---|---|---|
| **V-90** | 對外是否需要 `product_variants/update` webhook topic | Shopify 只有 `products/update`（帶完整變體），但實務上有第三方 app 依賴變體級事件的說法未經查證 | 維持 28 §15 的 24 topic 不變；內部細粒度事件不對外（§C.1）。**不得**在未查證前擅自加對外 topic |
| **V-91** | **SKU 軟唯一的警告要不要做成阻擋** | 61 §1.5（help P10）已定案「官方要求唯一但**不阻擋**，只警告」⇒ DB 不建唯一索引這一半**已無爭議**。剩下的是產品決策：我方要不要比 Shopify 嚴（設定項「SKU 必須唯一」）以服務有 WMS 整合的商家 | 首發照官方：軟唯一 ＋ 警告（§B.6）。**需使用者裁定是否加設定項**；不得在未裁定前直接加唯一索引（上線後改要停機） |
| **V-92** | HK 對「網頁顯示價 ≠ 結帳價」的法規界線 | 56 §B.5 已警告 HK 消費者權利「多做會出事」，但未查證具體條文與容忍度 | 工程面按零容忍做（key-based 即時，§D.5）；**法遵風險登記不結案** |
| **V-93** | 多 catalog 命中同商品取 MIN 是否適用非 B2B 市場 | 28 §13b H-66 只講 company location | 延伸適用（§G.2 ②）並標 ours；覆核前不得改成「取最後一個」或「未定義」 |
| **V-94** | exponent = 3 的幣別（KWD/BHD/JOD）何時支援 | 儲存尺度 ×100 不足以表達 milli-unit；改 `storage_multiplier` 是全庫 migration | 首發擋下（`unsupported_currency_exponents: [3]`），market 建立時回 `INCLUSION` |
| **V-95** | Solid Queue 是否與 primary 同一個 database | §A.2 的「outbox 必要性」推理依賴此前提；同庫時 `perform_later` 碰巧具事務性 | **規格不變**（一律走 outbox）。查證只影響註解的措辭，不影響作法 |
| **V-96** | `volatile_section_ttl_seconds` 的 60 秒是否合適 | 沒有真實流量資料；太長 ⇒「僅剩 3 件」長期失真、太短 ⇒ 集合頁命中率崩 | 暫定 60；上線後以 `liquid.volatile_render` 指標與命中率調參 |
| **V-97** | 第三方主題比對 `Default Title` 的普遍程度 | 官方側已由 61 §1.1（help P18）確認**字串本身是固定的**；剩下的只是「有多少主題會硬比對它」——Ella 7.2.0 證實 4 處〔fixture〕，但這是**單一主題**的樣本 | 契約照做（§B.2）；日後匯入更多主題時擴充樣本。**此條已從「契約是否成立」降級為「樣本量」**，不阻擋實作 |
| **V-98** | 銷售管道發布失敗的錯誤碼是否需要標準化列舉 | 各管道錯誤碼各異（GMC/Meta/市場 catalog）；60 §5 只證明「有這個排序維度」，未取得錯誤內容 | `error_code` 先存管道原始碼字串 ＋ 我方分類（`VALIDATION`/`AUTH`/`RATE_LIMIT`/`UNKNOWN`）；不硬編列舉 |

---

## L. 與既有規格的衝突登記（本篇**不改**其他檔案，只登記）

| # | 衝突 | 現況 | 本篇立場 | 誰該改 |
|---|---|---|---|---|
| **L-1** | SKU 唯一性 | 11 §2-1 舉例「SKU per shop 用唯一索引兜底」 | **該例子錯了**：官方是軟唯一（警告不阻擋，61 §1.5／help P10）。DB 用一般索引，重複時回 `warnings`（§B.6） | 11 §2-1 換一個例子（handle 與折扣碼仍是好例子，SKU 不是） |
| **L-2** | `platform_daily_rollups` 的形狀矛盾 | 36 §3 定義為**無 shop_id、唯一鍵 (date)**；39:2225 卻 join 它並讀 `gmv_30d_cents`（需要每店一列，且該欄不在 36 的欄位表） | 兩張表：`platform_daily_rollups`（平台日總計，豁免表）＋ `platform_shop_daily_rollups`（**帶 shop_id**，不需豁免） | 36 §3 與 39 §2225 二選一改，並更新 `config/tenancy_exempt_tables.yml` |
| ~~**L-3**~~ | ~~`CONFLICT` 錯誤碼的分類~~ | 28 §8 把 `CONFLICT` 歸為「折扣專屬」 | ✅ **2026-08-15 以相反方向結案**：本尊的 `CONFLICT` 只存在於 `DiscountErrorCode`、語義是折扣屬性互斥的**輸入驗證**，與樂觀鎖無關 ⇒ **28 §8 是對的，改的是本篇**。樂觀鎖用 `STALE_OBJECT`、庫存 CAS 用 `CHANGE_FROM_QUANTITY_STALE`，兩者進本輪新開的 `ConcurrencyCode` 池（28 §6 的 20 個泛用碼全是欄位級輸入驗證，結構上容不下併發語義）。 | 本篇 §A.4／§E.5／驗收清單皆已改 |
| **L-4** | outbox 的投遞狀態粒度 | 18 §F1-2「逐筆路由給訂閱者 → 成功標 done」——單一 `status` 欄位 | 需要**逐消費者**的投遞狀態表，否則一個消費者失敗會連累其他消費者重放（§C.4）。🔴 **門檻（2026-08-24 第 19 包執行規格 §4.3 寫死）：第一個掛真實多消費者的包，開工前置＝先建 `event_deliveries`**——第 19 包只做零消費者的 relay 骨架，單一 status 欄在該射程內自洽 | 18 §F1（加 `event_deliveries` 表） |
| **L-5** | 匯率的儲存型別 | 29 §1.4 `currency_exchange_rates(base/quote/**rate**/fetched_at)` 未指定型別 | `rate_ppm BIGINT`（鐵律 3：float 即 bug） | 29 §1.4 |
| **L-6** | 零小數貨幣的顯示 | 29 §3.3「零小數貨幣顯示與收款一律整數；money filter 格式化**不得出現小數**」 | 被 2026-08-12 裁定二覆蓋：**顯示一律兩位小數**（`limits.currency_display`）。但 29 §3.3 講的「**收款**」那一半仍然成立且更重要（§G.4） | 29 §3.3 拆成「顯示（已被覆蓋）」與「收款（仍有效）」兩句 |
| **L-7** | ~~13 §F5.1 的 zh-TW 用詞~~ | ~~統一為 60 §4 庫存頁那套~~ | 🔴 **本篇撤回此項**：61 §3.2 指出 13 §F5.1 現用的 help 官方譯名才是穩的錨，照 60 §4 建議改是回退。**13 §F5.1 不動**，取捨交 V-52 | — |
| **L-8** | 商品 CSV 與庫存 CSV 分流 | 13 §F6 只寫「一套 CSV 匯入」 | 兩套：商品 CSV 不得更新庫存量（60 §5 匯出 modal 逐字）；**庫存 CSV 的五態全部唯讀，唯一可寫是 `On hand (new)`，且 `On hand (current)` 是官方寫在欄位語義裡的樂觀鎖**（61 §6.2）；另需支援「全狀態」與「僅可販售」兩種佈局 | 13 §F6 |
| **L-9** | GraphQL payload 沒有「警告」的位置 | 28 §0.3 只有 `userErrors`（＝業務**錯誤**，代表操作失敗） | SKU 軟唯一（§B.6）這類「成功但要提醒」需要 payload 上獨立的 `warnings{field, message, code}`。塞進 `userErrors` 會讓前端當失敗處理 | 28 §0.3（加 `warnings` 慣例） |
| **L-10** | `Product.published` 只有一個 scope | 13 §F1-6「active 且發佈到 online store channel 才出現在 storefront 查詢（做成 `Product.published` scope，一處定義全站重用）」 | 官方是**四**態（多 `UNLISTED`，61 §1.3）⇒ 必須拆成 `purchasable`（含 UNLISTED）與 `discoverable`（不含），且兩者都要加**變體級發布**的 AND 條件（§D.2、§H.2） | 13 §F1-6、13 §F1 的 status 三態那一行 |
