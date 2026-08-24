# 95 — 擋住 migration 的 enum 值域導出（2026-08-24）

> **為什麼有這份檔**：`docs/plans/2026-08-24-三道裁定-本尊對照.md` §六 依鐵律 12.3 立了閘門——
> 系列條件×運算子、庫存錯誤碼兩組 enum 的值域結案前不得寫 migration。本檔是那道閘門的結案文件。
>
> **方法**：四路平行導出 ＋ 四路對抗驗證（預設立場「導出是錯的／不完整的」，逐頁實抓覆核）。
> API 版本一律取 **`2026-07`**，取證日 **2026-08-24**。
>
> **對抗驗證的判定**：`complete` 1 份、`incomplete` 1 份、`wrong` 2 份。**被推翻的內容不在本檔內。**
> 驗證方自述的兩項方法學細節值得留存：①先用假 URL `/interfaces/CollectionSourceZzzFake` 取證，
> 回 **HTTP 404**（非 soft-200）⇒ 確認 shopify.dev 對不存在型別確實回 404，本家族頁面為真實存在；
> ②`possibleTypes` 區塊是 client-side render，純 markdown 轉換抓不到，必須瀏覽器渲染後由 DOM 導出。

---

## §1 系列：**新舊兩套條件模型並存，不要混用**

🔴 **本節最重要的一件事**：`CollectionRuleColumn` / `CollectionRuleRelation` 是**舊模型**
（搭配已 deprecated 的 `Collection.ruleSet`）。**2026-07 的 sources 模型有自己一整套條件型別階層。**
拿舊 enum 的值域去推論新模型會直接推錯——本輪的對抗驗證就是這樣抓到兩條錯誤斷言的（見 §1.4）。

### 1.1 新模型：`CollectionSource` 家族

| 型別 | 種類 | 說明 |
|---|---|---|
| `CollectionSource` | interface | 欄位 `app(App)` / `description(String)` / `id` … |
| `CollectionConditionsSource` | object，implements `CollectionSource, Node` | 條件 ＋ 手選共存 |
| `CollectionSubCollectionsSource` | object，implements `CollectionSource, Node` | 成員來自一個或多個其他系列 |
| `CollectionSourceInclusion` | object | 欄位 `conditions` / `matchType` / `selections` |
| `CollectionSourceExclusion` | object | 同上 |
| `CollectionSourceInclusionCondition` | interface | inclusion 條件的共同介面 |
| `CollectionSourceExclusionCondition` | interface | exclusion 條件的共同介面 |
| `CollectionSourceInclusionConditionMetafield` | interface | 🔴 第四個介面，由 7 個 Metafield* inclusion 條件共同實作；欄位 `definition: MetafieldDefinition!` / `id: ID!` |

**enum**：
- `CollectionSourceTargetType` ＝ `PRODUCTS`（任一變體符合則整個商品納入）／`VARIANTS`（逐變體納入）
- `CollectionConditionMatchType` ＝ `ALL`／`ANY`
- `SubCollectionIneligibleReason` ＝ `CHAIN_REFERENCE`（被參照的系列自己也擁有 sub-collection 來源）／
  `INVALID_COLLECTION_REFERENCE`／`SELF_REFERENCE`

### 1.2 inclusion 條件 possibleTypes（19 種）

`MetafieldBoolean` ／ `MetafieldDecimal` ／ `MetafieldInteger` ／ `MetafieldMetaobject` ／
`MetafieldMetaobjectList` ／ `MetafieldString` ／ `MetafieldStringList` ／
`ProductCategory` ／ **`ProductStatus`** ／ `ProductTag` ／ `ProductTitle` ／ `ProductType` ／
`ProductVendor` ／ **`Unknown`** ／ `VariantCompareAtPrice` ／ `VariantInventory` ／
`VariantPrice` ／ `VariantTitle` ／ `VariantWeight`
（前綴一律 `CollectionSourceInclusionCondition`）

### 1.3 exclusion 條件 possibleTypes（**只有 6 種**）

**`Collection`** ／ `ProductCategory` ／ `ProductTag` ／ `ProductType` ／ `ProductVendor` ／ **`Unknown`**
（前綴一律 `CollectionSourceExclusionCondition`）

🔴 **兩個不對稱，都不是巧合**：
1. **exclusion 的條件集合是 inclusion 的子集**（6 vs 19）——沒有價格、庫存、狀態、metafield 類排除。
   我方 schema 若用**單一** `field ENUM` ＋ `mode ENUM('inclusion','exclusion')`，
   就沒有任何東西阻止在 exclusion 列寫 `price`。值域不是「有哪些欄位」，是「**哪個區塊有哪些欄位**」。
2. **`Collection` 只在 exclusion 側**——inclusion 側要「取另一個系列的成員」走的是
   `CollectionSubCollectionsSource`（一個獨立的 source 型別），不是條件。

### 1.4 🔴 `...ConditionUnknown` ＝ 本尊自備的向前相容型別

官方描述逐字：「An inclusion condition introduced in a newer API version that is not modeled by…」
⇒ union 裡有一個顯式的 Unknown 成員，讓舊客戶端遇到新條件型別時不會炸。
**我方模型應該有等價物**：遇到不認識的條件型別要**保留原樣**而不是 reject 或丟棄。

### 1.5 實機 × API 交叉驗證（兩邊獨立取得，結果吻合）

`docs/research/94` §1.4 實機點開「Add condition」導出 **11 個屬性**：
Category ／ Compare at price ／ Inventory stock ／ Price ／ Status ／ Tag ／ Title ／ Type ／
Variant title ／ Vendor ／ Weight。

這正好等於 §1.2 的 19 種 **扣掉 7 個 Metafield\* 與 Unknown**：
`ProductCategory`→Category、`VariantCompareAtPrice`→Compare at price、`VariantInventory`→Inventory stock、
`VariantPrice`→Price、`ProductStatus`→Status、`ProductTag`→Tag、`ProductTitle`→Title、
`ProductType`→Type、`VariantTitle`→Variant title、`ProductVendor`→Vendor、`VariantWeight`→Weight。

metafield 類沒出現，是因為測試店沒有 `useAsCollectionCondition = true` 的 metafield 定義。
⇒ **UI 與 API 的兩份導出互相證實，且解釋了差額的成因。**

### 1.6 舊模型（legacy，`ruleSet` 用）的值域——僅供相容讀取

`CollectionRuleColumn` **15 值**：`IS_PRICE_REDUCED` ／ `PRODUCT_CATEGORY_ID` ／
`PRODUCT_CATEGORY_ID_WITH_DESCENDANTS` ／ `PRODUCT_METAFIELD_DEFINITION` ／
`PRODUCT_TAXONOMY_NODE_ID`（**已宣告淘汰**，changelog 2024-09-11 起由 `PRODUCT_CATEGORY_ID` 取代）／
`TAG` ／ `TITLE` ／ `TYPE` ／ `VARIANT_COMPARE_AT_PRICE` ／ `VARIANT_INVENTORY` ／
`VARIANT_METAFIELD_DEFINITION` ／ `VARIANT_PRICE` ／ `VARIANT_TITLE` ／ `VARIANT_WEIGHT` ／ `VENDOR`

`CollectionRuleRelation` **10 值**：`CONTAINS` ／ `ENDS_WITH` ／ `EQUALS` ／ `GREATER_THAN` ／
`IS_NOT_SET` ／ `IS_SET` ／ `LESS_THAN` ／ `NOT_CONTAINS` ／ `NOT_EQUALS` ／ `STARTS_WITH`

🔴 **column ↔ relation 的對應不寫在 enum 頁，而是一支執行期 query**：
`collectionRulesConditions` 回 `[CollectionRuleConditions!]!`，每筆帶
`ruleType` / `allowedRelations` / `defaultRelation` / `ruleObject`。
⇒ **我方對應實作也應提供一支同語義的 API 給 admin SPA 動態渲染，而不是前端硬編對應表**——
因為 metafield 條件的 `allowedRelations` **依 metafield 型別逐筆而定**（數值型給
`[EQUALS, GREATER_THAN, LESS_THAN]`、文字/布林/list 型給 `[EQUALS]`），硬編表達不了。

官方範例裡幾個容易照直覺做錯的：

| ruleType | allowedRelations | 預設 |
|---|---|---|
| `TAG` | **只有 `[EQUALS]`**（沒有 CONTAINS／NOT_EQUALS） | EQUALS |
| `IS_PRICE_REDUCED` | **`[IS_SET, IS_NOT_SET]`**（不是 EQUALS true/false） | IS_SET |
| `VARIANT_INVENTORY` | `[EQUALS, GREATER_THAN, LESS_THAN]`（**無 NOT_EQUALS**） | GREATER_THAN |
| `TITLE`／`VARIANT_TITLE` | `[EQUALS, NOT_EQUALS, STARTS_WITH, ENDS_WITH, CONTAINS, NOT_CONTAINS]` | CONTAINS |
| `TYPE`／`VENDOR` | 同上六個 | EQUALS |
| `VARIANT_PRICE`／`VARIANT_COMPARE_AT_PRICE`／`VARIANT_WEIGHT` | `[EQUALS, NOT_EQUALS, GREATER_THAN, LESS_THAN]` | GREATER_THAN |

---

## §2 庫存數量狀態（8 個 name）

`available` ／ `committed` ／ `damaged` ／ `incoming` ／ `on_hand` ／ `quality_control` ／
`reserved` ／ `safety_stock`（一律小寫底線）

- `on_hand.comprises` ＝ `[available, committed, damaged, quality_control, reserved, safety_stock]`
  （**六項，不含 `incoming`**）
- 其餘六項的 `belongsTo` ＝ `[on_hand]`；`incoming.belongsTo` ＝ `[]`、`on_hand.belongsTo` ＝ `[]`
- ⇒ 與 `docs/research/94` §2.2 實機 tooltip「This is the sum of unavailable, committed, and available
  items」一致（UI 的 `unavailable` ＝ API 的 damaged＋quality_control＋reserved＋safety_stock 四項的彙總顯示）

### 🔴 `isInUse` 的語義不是「平台支不支援」

官方定義逐字：「Whether the quantity name has been **used by the merchant**.」
⇒ 它是**該商家用過沒有**的使用旗標，**不是** per-shop 功能開關。
官方範例裡 false 的三個是 `damaged`／`quality_control`／`safety_stock`；true 的五個是
`available`／`committed`／`incoming`／`on_hand`／`reserved`。

**對我方的意義**：這一條原本被誤讀成「本尊有每店開關，我方要不要跟」——**不是**。
正確的 parity 行為是：**未被使用過的狀態不主動在庫存表格露出欄位**。這是顯示邏輯，不是設定項。

`displayName` 是 **已本地化**字串（原文「translated into applicable language」）
⇒ 我方繁中介面必須自備對照表，**不得**把 API 回的英文 `displayName` 當顯示值。

---

## §3 庫存調整原因：**API 17 個，admin UI 只露 7 個**

兩支 mutation 的 `reason` 描述連到**同一個錨點**，共用同一份 17 值全集，官方未給 per-mutation 子集限制。

### 3.1 UI 7 個 → API 識別字的對應（🔴 五個對不上直覺）

| admin UI | API 識別字 |
|---|---|
| Correction | `correction` |
| Count | **`cycle_count_available`** |
| Received | `received` |
| Return restock | **`restock`** |
| Damaged | `damaged` |
| Theft or loss | **`shrinkage`** |
| Promotion or donation | **`promotion`** |

### 3.2 API 多出的 10 個（UI 手動下拉沒有，是系統事件用的）

`other` ／ `quality_control` ／ `safety_stock` ／
`movement_created` ／ `movement_updated` ／ `movement_received` ／ **`movement_canceled`**（美式單 l）／
`reservation_created` ／ `reservation_updated` ／ `reservation_deleted`

⇒ **`docs/plans/2026-08-24-三方向執行順序.md` §6 的「reason 取 7 值還是 17 值」不是二選一**：
API 面 17 個（`movement_*` 由調撥/採購單觸發、`reservation_*` 由第三方保留觸發），
UI 手動下拉 7 個。兩者是**同一份值域的兩個投影**，都要。

---

## §4 庫存 mutation 的併發與冪等（🔴 更正一條先前的誤述）

| mutation | CAS 參數 | 說明 |
|---|---|---|
| `inventorySetQuantities` | `compareQuantity` ＋ `ignoreCompareQuantity` | **兩者在 `2026-07` 仍然存在**（複驗：mutation 頁）。`ignoreCompareQuantity` 官方警告「Opting out of the compareQuantity check can lead to inaccurate inventory quantities if multiple requests are made concurrently.」 |
| `inventoryAdjustQuantities` | `changeFromQuantity`（Int，傳 `null` 可跳過） | 失敗回 `CHANGE_FROM_QUANTITY_*` 系列 |

🔴 **更正**：先前一份研究回報稱「`changeFromQuantity` 取代已移除的 `compareQuantity`」——**那是錯的**。
兩者是**兩支不同 mutation 各自的 CAS 參數**，不是替換關係。已於 2026-08-24 對
`https://shopify.dev/docs/api/admin-graphql/2026-07/mutations/inventorySetQuantities` 複驗。

**冪等**：兩支 mutation 皆自 **`2026-04` 起 `@idempotent` 的 key 為必填**（先前版本選填）。
錯誤碼含 `IDEMPOTENCY_CONCURRENT_REQUEST` ／ `IDEMPOTENCY_KEY_PARAMETER_MISMATCH` ／
`IDEMPOTENCY_PREVIOUS_ATTEMPT_FAILED`。

**`name` 是 `String!` 不是 enum**；`InventorySetQuantitiesInput.name` 原文
「The only accepted values are: `available` or `on_hand`.」
非法值走 userErrors（HTTP 200），但**兩支的碼不同名**：
adjust → `INVALID_QUANTITY_NAME`；set → `INVALID_NAME`。

**`ledgerDocumentUri` 規則**：除 `available` 外**全部必填**，且不得用 `gid://shopify/*`。
對應三個碼：`INVALID_AVAILABLE_DOCUMENT`（調 available 時不得帶）／
`INVALID_QUANTITY_DOCUMENT`（調 available 以外時必須帶）／`MAX_ONE_LEDGER_DOCUMENT`。

---

## §5 可直接落 `config/limits.yml` 的官方數字

| 鍵 | 值 | 出處原文 |
|---|---|---|
| adjust 的數量上限 | **2,000,000,000** | `INVALID_QUANTITY_TOO_HIGH` = "The quantity can't be higher than 2,000,000,000." |
| adjust 的數量下限 | **−2,000,000,000** | `INVALID_QUANTITY_TOO_LOW` 同句反向 |
| set 的總量上限 | **1,000,000,000** | `INVALID_QUANTITY_TOO_HIGH` = "The **total** quantity can't be higher than 1,000,000,000." |

🔴 **adjust 與 set 的邊界不同**（2e9 vs 1e9），且 set 的措辭是「total」。
照一個數字實作會在其中一支上放行不該放行的值。

---

## §6 仍未結案（V 項）

- **V-95.1** `PRODUCT_CATEGORY_ID` 與 `PRODUCT_CATEGORY_ID_WITH_DESCENDANTS` 的
  `allowedRelations`／`defaultRelation`：官方 `collectionRulesConditions` 範例回應**未包含**這兩個
  ruleType（範例仍是舊的 `PRODUCT_TAXONOMY_NODE_ID` 時代）。合理推測是 `[EQUALS]`，
  **但無證據，不得寫入規格**——需對測試店實打一次 `collectionRulesConditions`。
- **V-95.2** 新模型各 inclusion/exclusion 條件型別**各自的 relation enum 值域**
  （例如 `CollectionSourceInclusionConditionProductStatusRelation`）本輪未逐型導出。
- **V-95.3** 60 條件的尺度（per source vs per collection）——見 94 §3，仍需實測。
