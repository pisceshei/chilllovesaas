# M1 — 變體 × 選項 join 表 ＋ `option_values_digest`（D12）

## 概述

把「這個變體在哪些選項上取了哪些值」變成**可查詢、可約束**的資料，並用一個物化的
`option_values_digest` 當唯一性兜底。這是 `productCreate` 的前置閘門——D12 原文：
「擋 `productCreate` 的 input shape，必須在第一支商品 mutation 之前落地」。

## 規格出處

| 項目 | 出處 |
|---|---|
| 裁定本體 | `docs/DECISIONS.md` D12 |
| 唯一性與 digest | `docs/specs/13` §F1-2 |
| 變體身分保持 | `docs/specs/63` §B.5 |
| digest 用 id 不用字串 | `docs/specs/67` §B.3-4 |
| match key 是 variant id | `config/limits.yml` `variant_identity_id_wins: true`、`63` §B.4 |
| 上限值 | `config/limits.yml` `product.max_variants: 2048` |

## 架構與資料流

```
products
  └─ product_options (Size, Color…)        position＝可拖曳的顯示順序
       └─ option_values (S, M, L…)         🔴 孤立值合法（本尊：values not assigned to any variants）
  └─ product_variants
       ├─ option_values_digest             ← 由 join 列算出，唯一性兜底
       └─ product_variant_option_values    ← 座標：一個變體對一個選項恰好一列
```

`ProductVariant#before_validation` 依 `effective_option_value_pairs` 重算 digest——
那是「記憶體中的關聯狀態（新建／已編輯／標記刪除）＋ DB 既有列」的合成視圖，
唯一產生處是 `Catalog::OptionValuesDigest`。（初版直接 pluck DB，驗收輪抓到
兩層靜默資料遺失後改成現狀，見下方「驗收輪修正」。）

### digest 的定義

依 `product_option_id` 升冪 → 每對編碼成 `"選項id:值id"` → 以 `,` 相接 → SHA1 → 40 字元小寫 hex。
無選項變體 ＝ 空集合的 SHA1（`NO_OPTIONS`），對應本尊的 `Default Title`。

| 事件 | digest |
|---|---|
| 選項值**改名**（Red → Crimson） | **不變**（`option_values.id` 沒動） |
| 選項**重排** position | **不變**（排序鍵是 id 不是 position） |
| 加／刪選項、換座標 | **變**（由寫入 service 在同一 transaction 重算） |

## API 對應

**本輪不出任何 mutation。** 這一層是 schema 與 model 地基。

🔴 **`option_values_digest` 不得出現在 Admin GraphQL 的 `ProductVariant` 型別上**——
本尊沒有這個概念（型別上只有 `title` 與 `selectedOptions`）。

## 資料表

`product_variant_option_values`：`shop_id` / `product_id` / `product_variant_id` /
`product_option_id` / `option_value_id` ＋ timestamps。

索引與外鍵逐條理由見 migration 檔頭與 inline 註釋（支數不寫死，以 migration 為準；
2026-08-16 補 `ix_pvov_by_value [shop_id, option_value_id]`——`OptionValue` 刪除前
`restrict_with_error` 的存在性反查，三支既有索引對此查詢都只能用到 shop 前綴）。

## 關鍵取捨

### 為什麼 join 表存 `option_value_id` 而不是值字串

`67` §B.3-4 逐字：「譯文掛在 `product_option_values.id` 上，不是掛在字串上…**若變體以
「選項值字串」比對，切語言就會找不到變體**」。這是規格層裁定，不是效能取捨。

### 為什麼有兩個「冗餘」欄位

`product_id` 與 `product_option_id` 都可以由別的欄位推導，但它們是**約束載體**：

- MySQL 的 CHECK **不能跨表**（子查詢 ⇒ ERROR 3815）⇒ 擋「跨商品掛選項」只能靠複合外鍵，
  而複合外鍵需要本表有 `product_id`；
- 唯一索引**只能跨本表欄位** ⇒ 表達「一個變體在一個選項上只能有一個值」需要本表有
  `product_option_id`。

🔴 **推導得出來 ≠ DB 擋得住。**

### MySQL 8.4 的複合外鍵限制（會讓 migration 直接寫錯）

`restrict_fk_on_non_standard_key = 1`（編譯預設）⇒ 被指向的欄位組必須
**逐字、同順序等於某支 UNIQUE／PRIMARY 索引的完整清單**。最左前綴、欄序不同都是 `ERROR 6125`。
⇒ migration 先在三張父表各補一支唯一索引，**那是外鍵建得起來的必要條件**。

### 為什麼排序鍵是 `product_option_id` 不是 `position`

`position` 使用者拖曳就會改（本尊有 `productOptionsReorder`）。照它排序的話，
每次重排都要重算該商品所有變體的 digest，漏一條路徑就是靜默的身分斷裂。

### digest 不是身分

primary match key 是 `variants[].id`。`63` §B.5 的身分保持會讓 digest 變（加選項時
既有變體補上第一個值）——**digest 變了、身分沒變**，這證明兩者是不同的東西。

## 驗收輪修正（2026-08-16，ce83cdb 起）

### 🔴 兩層靜默資料遺失（digest 與記憶體狀態脫節）

初版 digest 直接 pluck DB ⇒ ①`assoc.build` 出來尚未落庫的列不進 digest；
②已載入、改了座標但還沒 save 的列用舊值算。配套三個 Rails 邊界（都實測復現）：

- **預設 `has_many` 不會自動存「已持久化但變髒」的子物件**——必須顯式 `autosave: true`；
- **未載入關聯上 `.first` 回的是脫離的查詢物件**，改它不影響關聯快取；
- **`assoc.build` 不會把 `loaded?` 變 true**——要讀記憶體狀態得走 `assoc.target`。

修法＝`effective_option_value_pairs`：`target` 裡的新建列（排除標記刪除）＋已編輯列
＋ DB 列（排除已刪／已編輯的 id），驗證與 digest 共用同一份視圖。

### 🔴 digest 對 Float 靜默截斷

`Integer(1.9)` 回 `1` ⇒ `[[1.9, 2.9]]` 與 `[[1, 2]]` 同 digest。改嚴格
`is_a?(Integer)`，Float 與可轉字串（`"7"`）一律 `TypeError`——兜底對輸入寬鬆就不是兜底。

### 🔴 `restrict_with_error` 反查無索引

見上方資料表節：補 `ix_pvov_by_value`。migration 未合併，就地改（schema.rb 重生流程
的坑登記在 worklog）。

## 🔴 跨功能／跨頁／前端影響

| 受影響 | 影響 |
|---|---|
| **`productCreate`／`productSet`**（未實作） | input 必須帶 `optionValues`；diff 走兩階段（先投影再比對），**跳過投影會換掉所有 variant id** |
| **變體刪除**（未實作） | `fk_line_items_product_variant_id` 目前**無 `on_delete` ⇒ RESTRICT**，DB 層擋著。要改 `ON DELETE SET NULL` |
| **商品表單的選項矩陣**（M1 UI） | 直接讀 join 表；`ProductOption#first_value` 是 §B.5 的「第一個值」 |
| **多語言**（M5） | 譯文掛 `option_value_id`；digest 用 id ⇒ 切語言不影響變體身分 |
| **前台 Liquid**（M2） | `variant.option1/2/3` 由 join 表推導；**不得**回頭加冗餘欄 |
| **feed／SEO**（M5） | digest **不得**外洩成 feed id 或 URL |
| **既有測試** | `product_variant_spec` 三條改過形態（理由見該檔註釋）——🔴 **與 SKU 軟唯一無關** |

## 測試

- `spec/models/product_variant_option_value_spec.rb`：四條 DB 不變量（各自繞過 model 驗 DB）
  ＋ 座標唯一性四條 ＋ digest 穩定性三條
- `spec/services/catalog/option_values_digest_spec.rb`：順序無關、值域、單射性、
  與 migration 字面量一致

**負面驗證**：拆掉 `fk_pvov_value` ⇒ 不變量③紅；拿掉 digest 的排序 ⇒ 順序無關那條紅。

驗收輪回歸（2026-08-16）：`product_variant_spec` 頂層回歸塊三條（build 後 save 座標不失蹤／
已載入編輯後 digest 用新值／繞過 model 直寫 DB 也反映）；`option_values_digest_spec`
補 Float 與可轉字串兩組 `TypeError` 斷言。

## 已知限制

- 🔴 **沒有任何寫入 service**。join 列與 digest 的「同一 transaction 內一起寫」目前
  **只有 model callback 覆蓋正常路徑**；`insert_all`／`upsert_all` 繞過它
  （但 `option_values_digest` 是 `null: false` 且**刻意無 default** ⇒ 會大聲失敗）。
- 🔴 **兩階段 diff 尚未實作**，只寫進規格。
- ⚠️ `product_variants.title` 的衍生規則仍未裁定（本尊 title 是選項值 join 而來，
  我方目前是獨立的 `null: false` 欄）。**不擋 D12，擋第一支 `productSet`。**
- ⚠️ **部分**刪除選項時的塌縮 tie-break 沒有規格（`63` §B.5 只裁定「刪光所有選項」）。
- ⚠️ `effective_option_value_pairs` 每次驗證兩次呼叫＝兩次 pluck（digest＋驗證各一）。
  可記憶化到單次 save 週期，但要處理失效時機；量級（每變體 ≤ 選項數列）不值得先做。
- ⚠️ `inventory_items.product_variant_id` 是 `NOT NULL + UNIQUE`，把 1:1 焊在
  inventory_item 這一側；本尊 changelog（2025-12-02）已宣告要支援
  「多個 variant 共用一個 inventory item」。**方向問題，尚未裁定。**
