# 01. 商品與目錄（Products / Variants / Collections / Publishing）

> **性質**：Shopify 官方文檔考掘（shopify.dev `latest`＝2026-07 版 GraphQL Admin API ＋ help.shopify.com），供 CHILL LOVE 落地開發。全部規則性斷言附來源（§G），除特別標注外**取證日一律 2026-08-14**。
> **與倉庫的關係**：本檔是 `docs/research/61`（2026-08-12 考掘）的同域增量更新——61 已確立的事實不重抄，只補新證據、解衝突、標差異；裁定衝突以 `docs/specs/13`／`63`／`88` 與 CLAUDE.md 鐵律為準（差異全列 §F）。
> **本檔的兩個新結論**（61 沒有的）：①Collection 於 **2026-07 版轉為 sources 新模型**，`ruleSet` 正式棄用（§A.5）；②**exclude 恆勝過一切 include 已由官方明文化**，倉庫 V-57 假設獲證實（§C.5）。
  <!-- 🔴 2026-08-25 更正（第 11 包）：上句已被 13 §F4.2 的 2026-08-24 修訂推翻——official
       原文「evaluated per source and reconciled…」⇒ per-source 相減，V-57 撤銷；
       全域相減是靜默錯誤（A 排除 X＋B 包含 X 時判反）。正典＝13 §F4.2＋limits
       membership_formula。本句保留供沿革，不得再引用。 -->

---

## A. 領域物件模型

### A.1 物件總覽與 cardinality

| 關係 | Cardinality | 依據 |
|---|---|---|
| Product → ProductVariant | 1 : **1..2048**（恆有 ≥1，無選項時唯一變體＝`Default Title`） | G1、G7；61 §1.1 |
| Product → ProductOption | 1 : **0..3**（上限 per-shop 可查，見 §C.1） | G1、G12 |
| ProductOption → ProductOptionValue | 1 : N（N 上限存在但數字未公布，V-50 未解） | G3 |
| ProductVariant → SelectedOption | 1 : 選項數（笛卡兒積座標） | G2 |
| ProductVariant → InventoryItem | **1 : 1**（庫存屬性掛 InventoryItem，非 variant 欄位） | G2；63 §B.6 |
| Product → Media | 1 : **0..250** | 61 P14/P51（2026-08-12） |
| ProductVariant → Media | 1 : 0..1 圖片（不支援影片/3D） | 61 P21（2026-08-12） |
| Collection ↔ Product | M : N（經 sources 求值＋手動；同品多來源命中**只顯示一次**） | G15 |
| Collection → CollectionSource | 1 : N（**2026-07 新模型**，取代單一 ruleSet） | G13、G14 |
| Publication ↔ Publishable | M : N（經 ResourcePublication；Publishable＝Product／Collection／**ProductVariant**） | G8、G9 |
| Publication → Catalog | 1 : 0..1（catalog 可無 publication；目錄型別 MARKET／APP／COMPANY_LOCATION） | G8、G2 |
| CombinedListing：parent → child | 1 : **1..60**；child 只能屬於**一個** combined listing | G10、G11 |
| ProductVariant（bundle 父）→ ProductVariantComponent | 1 : **0..30**（組件＝`{productVariant, quantity}`） | G30、G34 |
| SellingPlanGroup → SellingPlan | 1 : **1..31** | G18 |
| SellingPlanGroup ↔ Product／Variant | M : N（商品數無上限） | G17、G18 |
| Product → TaxonomyCategory | N : **0..1**（每商品至多一個類別） | G1；61 P6 |

### A.2 Product 關鍵欄位（GraphQL `Product`，G1）

| 欄位 | 型別 | 要點 |
|---|---|---|
| `status` | `ProductStatus!` | 四值 enum，控制**跨所有管道**的可見性（§B.1） |
| `handle` | `String!` | 唯一；字元集＝小寫字母/數字/連字號、無空白；生成規則見 §C.2 |
| `options` | `[ProductOption!]!` | 上限由 shop resource limits 決定 |
| `variants` | connection | 單商品 root 查詢一次可取 **2048**；一般分頁上限 250 |
| `hasOnlyDefaultVariant` | `Boolean!` | 「無變體商品」的官方判定式 |
| `priceRangeV2` / `compareAtPriceRange` | 衍生 | **Product 無 price 欄位**——價格只存在於 variant，商品層只有 min/max 衍生區間 |
| `category` | `TaxonomyCategory` | nullable；Standard Product Taxonomy 單選 |
| `combinedListingRole` | `CombinedListingsRole` | `PARENT`／`CHILD`；null＝不屬於任何合併刊登 |
| `isGiftCard` / `requiresSellingPlan` | `Boolean!` | `requiresSellingPlan=true` 的商品**只能發布到 online store**（G16） |
| `resourcePublications` | connection | 發布層（§A.6） |
| `publishedAt` | nullable | 語義＝「發布到 online store 的時間」；deprecated 家族（`publishedOnChannel` 等）一律改走 publication 模型 |
| `tags` | `[String!]!` | 上限與正規化見 §C.4 |
| `templateSuffix` | nullable | 主題模板後綴 |
| deprecated | — | `bodyHtml`、`images`、`priceRange`、`productCategory`、`featuredImage`、`storefrontId` 等，新代碼不得使用 |

### A.3 ProductVariant 關鍵欄位（G2）

| 欄位 | 型別 | 要點 |
|---|---|---|
| `price` | `Money!` | **non-null**：變體必有價格（商店預設幣別） |
| `compareAtPrice` | `Money` | nullable；「折後原價」 |
| `sku` / `barcode` | nullable | SKU **區分大小寫**；接 fulfillment service 才必填 |
| `position` | `Int!` | 變體清單順序，**從 1 起算** |
| `selectedOptions` | `[SelectedOption!]!` | 變體＝選項值組合的座標 |
| `inventoryItem` | `InventoryItem!` | 1:1；庫存查詢入口 |
| `inventoryPolicy` | enum | `DENY`（缺貨不可買）／`CONTINUE`（缺貨可買）——**全集只有這兩值** |
| `inventoryQuantity` | `Int` | 可售總量（nullable） |
| `taxable` | `Boolean!` | 售出時是否計稅 |
| `media` | connection | 取代 deprecated 的 `image` |
| `unitPrice` / `unitPriceMeasurement` / `showUnitPrice` | — | 單位定價（公式 §C.3） |
| `requiresComponents` / `productVariantComponents` | — | bundle：`requiresComponents=true` 只能作為父 bundle 的一部分被購買；固定 bundle 完整模型見 §A.10 |
| `resourcePublications` / `resourcePublicationsV2` / `publishedOnPublication` / `unpublishedPublications` | — | **變體級發布層真實存在**（V2 依 catalog 型別 APP／COMPANY_LOCATION／MARKET 篩選） |
| `sellingPlanGroups` | connection | 訂閱掛載點 |

### A.4 ProductOption 與 Media（G3、G22）

- `ProductOption`：`id` / `name` / `position` / `values`（字串）/ `optionValues`（**含未被任何變體使用的值**）/ `linkedMetafield`（選項可連結 metafield——即 category metafields 驅動的結構化選項，§D.6）。
- Media 家族：圖片／影片／外部影片（僅 YouTube/Vimeo）／3D 模型，處理為**非同步**，狀態機見 §B.3。規格上限見 §C.1。

### A.5 Collection——2026-07 sources 新模型（G13、G14、G15）

- **`Collection.ruleSet` 已正式 deprecated，改為 `Collection.sources`**；`collectionCreate(input:)`／`collectionUpdate(input:)` 的 `input` 引數同步棄用，改用 `collection:` 引數（`CollectionCreateInput`，含 `sources`）。舊引數仍可用（非破壞式），但**表達不了多來源與排除條件**。
- **API 版本邊界**：用了新特性的 collection 在 **2026-07 之前的 API 版本會被過濾掉不回傳**（舊 shape 表達不了）——同步器必須跑 2026-07+。
- 來源兩個具體型別：
  1. `CollectionConditionsSource`：typed `conditions`（`matchType: ALL | ANY`）＋手動 `selections`（productId ＋可選 variantIds）＋可選排除條件；`targetType: PRODUCTS | VARIANTS`（enum `CollectionSourceTargetType`）；`shareable=true` 時可被多個 collection 連結（app 建立的可重用來源）。
  2. `CollectionSubCollectionsSource`：成員來自一或多個被參照的 collection（系列套系列）。
- 新 mutations：`collectionConditionsSourceCreate/Update/Delete`、`collectionCreate(collection:)`、`collectionUpdate(collection:)`。
- Functions 側新增 `ProductVariant.inAnyCollection(ids)` 與 `inCollections(ids)`。
- `Collection.handle`：不給則由 title 自動生成；**改 title 不會自動改 handle**（與 Product 同規則）。

### A.6 發布模型：Publication × ResourcePublication × Catalog（G8、G9、G16）

| 物件 | 關鍵欄位 | 語義 |
|---|---|---|
| `Publication` | `autoPublish: Boolean!` | 「新商品是否自動發布到本 publication」 |
| | `supportsFuturePublishing: Boolean!` | 是否支援排程發布 |
| | `catalog: Catalog`（nullable） | publication 對 catalog **是可選的**；管道可自行決定可用性 |
| `ResourcePublication` | `publishable: Publishable!` | 實作者＝Product／Collection／ProductVariant |
| | `publishDate: DateTime!` | 已發布或**將要**發布的時間；未發布回 epoch |
| | `isPublished: Boolean!` | 🔴 **已排程（未來時間）也回 true**——判「現在可見」不能只看這個欄位，要 `isPublished ∧ publishDate ≤ now` |
| `publishablePublish` mutation | `id` ＋ `input:[{publicationId, publishDate?}]` | `publishDate` 即排程；**只有 online store 管道支援排程發布** |

三層 AND（help 口徑，G21）：商品要在某管道可得＝**「在指派給該管道市場的 catalog 內」∧「已發布到該管道」**——兩個獨立條件，即倉庫 `docs/specs/88` 的模型。

### A.7 CombinedListing（G10、G11）

- 一組既有商品（child）依某個選項（顏色/型號/尺寸）合併成單一刊登；**parent 商品自動建立**、不可購買、無庫存、無銷售數據；結帳與訂單只出現 child，**parent 永不出現**。
- child 保留獨立 URL handle 與圖片，可獨立 merchandise。
- 角色 enum `CombinedListingsRole`：`PARENT` / `CHILD`（全集兩值）。

### A.8 SellingPlan 概觀（G16、G17、G18）

- `SellingPlanGroup`（容器，掛 products/variants）→ `SellingPlan`（如「每週配送」）。
- `category` 核准值全集：`SUBSCRIPTION` / `PRE_ORDER` / `TRY_BEFORE_YOU_BUY`（其他需申請，佔位用 `OTHER`）。
- 政策四類：pricing（改價）／billing（下單→收款間隔）／delivery（下單→交付間隔）／inventory（庫存在下單時或履行時 commit）。訂閱用 pricing＋delivery＋billing；預購與先試後買另加 inventory。
- `Product.requiresSellingPlan=true`＝只能搭配 selling plan 購買，且**只能發布到 online store**。

### A.9 Taxonomy 與 category metafields（G19、G20）

- 商品指定 Standard Product Taxonomy 類別後，系統**啟用該類別對應的 category metafields**（如 Shirts → size／neckline／sleeve length），部分由 Shopify Magic 預測自動加入、部分為建議候選。
- category metafields 附**預設 metaobject entries**（可直接用或自訂）；可**連結到變體選項**（`ProductOption.linkedMetafield`），entries 對應選項值——改 entry（black→graphite）會全域同步所有使用處；色彩 entry 可驅動前台 swatch。
- 用途：稅率判定、管道資格、前台/市集/搜尋引擎的結構化發現。

### A.10 固定 Bundle（原生 productVariantComponents 模型，G29–G34）

- **模型**：父 variant 經 `productVariantComponents` connection 掛組件，每個 `ProductVariantComponent`＝`{productVariant, quantity}`（`quantity`＝組成一份 bundle 所需件數，整數；查詢 scope `read_products`，G34）。
- **組件數上限：30／bundle**（G30）→ 已進 §C.1 上限表。
- **不可巢狀**：一個商品不能同時「有組件」又「作為別人的組件」（G30）；help 側同口徑：bundle 不能包含 bundle（G31）。
- 🔴 **父項庫存＝組件推導的唯讀值**（本節是 02 章 `NON_MUTABLE_INVENTORY_ITEM` 錯誤碼的推導規則側）：
  - 公式：`bundle 可售數 = min_i ⌊組件i可售量 ÷ quantity_i⌋`，**向下取整**（G31 官方例：椅×2 存 15、桌×1 存 8 ⇒ min(⌊15/2⌋, ⌊8/1⌋) = 7）。
  - **未追蹤庫存或 `inventoryPolicy=CONTINUE` 的組件不進此計算**（G31）。⚠️ 全部組件皆被排除時父項可售數的行為官方未明文，待實測。
  - API 直寫父項庫存 ⇒ `NON_MUTABLE_INVENTORY_ITEM`，官方描述明指「例如 inventory item 是 parent bundle」（G33）。**資料模型上父項庫存必須是衍生欄位，不得做成可寫欄位**。
- **互斥／限制清單（窮舉，缺一即漏驗證）**：
  1. **不可與 selling plans 並用**（訂閱／預購／先試後買，G29）。
  2. **不可與 combined listing 並用**：官方明文在 combined listing 側（child 不得是 bundle，G10/G11；§B.4、§D.5）；bundle 側文檔未重述 ⇒ 我方互斥驗證**兩邊都要擋**。
  3. **不可設 final sale**：bundle 層無此開關，退貨資格由各組件商品自身的 final sale 設定決定（G31；06 章 §C.5 同源）。
  4. 不支援匯入／匯出／批量編輯；改組件 SKU＝整個 bundle 刪除重建；不可用於換貨（exchange）（G31）。
  5. 銷售管道：Online Store／Shop／POS／custom storefront 四種（G29）；店鋪資格經 `BundlesFeature` 物件查詢，不合格店鋪的 bundle 商品被阻止發布到管道（G29）。
- **寫入路徑是非同步 operation**：`productBundleCreate`／`productBundleUpdate` 回傳 `ProductBundleOperation`，需輪詢 `productOperation` 查詢取結果（G30、G32）——與商品同步 CRUD 不同形態，實作不得假設 mutation 回傳時 bundle 已就緒。
- `requiresComponents=true`＝該 variant 不可脫離父 bundle 單獨購買；自訂 bundle（cart transform 路線）用同一旗標（G29）。

---

## B. 狀態機

### B.1 ProductStatus（G4、G5、G6）

**狀態全集（四值，無其他）**：

| 狀態 | 可購買 | 可被發現 | 直接 URL | SEO |
|---|:---:|:---:|---|---|
| `ACTIVE` | ✅ | ✅ | 200 | 正常收錄 |
| `UNLISTED` | ✅ | ❌ | 200 | `noindex,nofollow` ＋ 排除 sitemap ＋ 排除 Shopify Catalog |
| `DRAFT` | ❌ | ❌ | 不可及 | — |
| `ARCHIVED` | ❌ | ❌ | 不可及 | — |

`UNLISTED` 補充（G5，較 61 新增的細節）：可達路徑除直接 URL／metafield 參照（`product_reference`、`variant_reference`）／分享連結外，還包括 **Storefront API 以 id/handle 查詢、Liquid `all_products[handle]`、Cart AJAX API**——「不可被發現」是**列表面的過濾，不是讀取權限**。**Shop app 不支援 unlisted**。2025-10 之前的 API 版本把 unlisted 回成 `active`。

**轉移表**（狀態由 `productUpdate`／`productSet` 的 `status` 欄位直接寫入。官方**未載明任何轉移禁令**——但這只支撐「無明文禁止」，不足以斷言全連通：表中 ARCHIVED 的既證出邊來自 admin「Unarchive」動作面（僅 ACTIVE/DRAFT），**ARCHIVED→UNLISTED 無任何官方頁面正反面提及**（G5 只說 unlisted 經 `ProductStatus` enum 讀寫，未提轉移限制）⚠️ 官方未明文，待實測。故準確斷言是：**無孤兒狀態（四態皆有進出邊）；API 面推定兩兩可達、UI 動作面不是**——直接照表轉 enum 轉移表者，須把 ARCHIVED→UNLISTED 標為「推定合法待驗證」而非硬禁）：

| 轉移 | 觸發動作 | 前置條件 | 副作用 |
|---|---|---|---|
| ∅ → DRAFT/ACTIVE/UNLISTED | 建立商品（admin 預設 DRAFT ⚠️ 依 61 實測；API 可指定） | — | ACTIVE 且有 autoPublish publication ⇒ 自動發布 |
| ∅ → DRAFT/ACTIVE/UNLISTED | **複製商品**（duplicate 時三選一，**不含 ARCHIVED**） | 原品存在 | 除 3D 模型與影片外全部複製；選 ACTIVE ⇒ 發布到與原品相同管道 |
| ACTIVE ↔ UNLISTED | status 更新 | API ≥ 2025-10 | 進出搜尋/系列/推薦/sitemap；publication 關聯不變 |
| ACTIVE/UNLISTED → DRAFT | status 更新 | — | 全管道下架（不可購買） |
| 任意 → ARCHIVED | 「Archive」動作 | — | 移入 Archived 分頁、全管道不可得；**是否保留 publication 記錄官方未載明**（⚠️ §openQuestions） |
| ARCHIVED → ACTIVE/DRAFT | 「Unarchive」（admin 動作面僅此兩目標） | — | **是否還原先前發布設定官方未載明** ⚠️ |
| ARCHIVED → UNLISTED | ⚠️ 僅可能經 API 直寫 status；官方未明文，待實測 | API ≥ 2025-10 | 若可行，推定同 ACTIVE→UNLISTED 的列表面過濾語義 |
| 任意 → ∅ | 刪除 | — | **永久、不可還原**；歷史訂單行項保留快照（訂單域規則） |

🔴 **不變量（可測）**：`discoverable ⊆ purchasable`——四態表中不存在「可被發現但不可購買」的組合；任何實作出現該組合即 soft-404 bug（倉庫 13 §F1.2(b) 已落為斷言）。

### B.2 發布狀態機（每一組 publishable × publication 一台）

| 狀態 | 判定 | 進入動作 |
|---|---|---|
| 未發布 | 無 ResourcePublication 記錄（`publishDate`＝epoch） | 初始／`publishableUnpublish` |
| **已排程** | `isPublished=true ∧ publishDate > now` | `publishablePublish` 帶未來 `publishDate` |
| 已發布 | `isPublished=true ∧ publishDate ≤ now` | `publishablePublish`（即時）或排程時間到（系統自動，無事件粒度保證 ⚠️） |

前置條件（官方明載，G16）：①排程發布**只有 online store 支援**（`supportsFuturePublishing`）；②商品要在管道顯示必須維持 `ACTIVE`（⇒ 排程到點時若非 ACTIVE 則不生效——與倉庫 88 §2.2 的「排程要求 Active」一致）；③**變體級**：變體要在管道可見，**父商品與該變體都必須發布到該管道**（AND，61 P16）；④**變體不可排程發布**（61 P16）。

### B.3 MediaStatus（G22）

```
UPLOADED（已上傳未處理）→ PROCESSING（處理中）→ READY（可顯示）
                                        └────→ FAILED（處理失敗，終態；重試＝重新上傳）
```
全集四值。上傳→READY 是**非同步**流程：商品建立 mutation 回傳時 media 可能仍在 PROCESSING，前台渲染必須容忍缺圖窗口。無孤兒態（FAILED 出口＝刪除或重傳）。

### B.4 CombinedListingsRole

```
null（普通商品）→ CHILD（被納入合併刊登；一次只能屬於一個）
null → PARENT（建立合併刊登時自動生成；初始 status = DRAFT）
CHILD → null（自合併刊登移除）
PARENT → null（解散合併刊登）
```
約束：parent 不可購買；combined listing 不可巢狀（parent 不能當另一個的 child）；不可與 bundle／訂閱並用（G10、G11；bundle 側對照 §A.10 互斥清單第 2 條——官方只在本側明文，驗證要兩邊都擋）。

---

## C. 業務規則與不變量

### C.1 上限值總表（一律進 `config/limits.yml` 帶出處；鐵律 6）

| 項目 | 值 | 來源 |
|---|---|---|
| 選項數／商品 | **3**（per-shop 可查 `ShopResourceLimits.maxProductOptions`） | G12；61 P14/D6 |
| 變體數／商品 | **2048**（2025-10-15 起全體商家；per-shop 可查 `maxProductVariants`） | G1、G12；61 D12 |
| 選項值數／選項 | **有上限、數字未公布**（`OPTION_VALUES_OVER_LIMIT` 錯誤碼存在） | 61 D7；V-50 未解 |
| 媒體數／商品 | **250** | 61 P14/P51 |
| 圖片 | ≤20MB、≤5000×5000（25MP）；格式 PNG/JPEG/PSD/TIFF/BMP/GIF/SVG/HEIC/WebP | G23 |
| 影片（自託管） | ≤10 分鐘、≤1GB、≤4K；mp4/mov/webm；外嵌僅 YouTube/Vimeo | G23 |
| 3D 模型 | ≤500MB；GLB/USDZ；>15MB 自動壓縮 | G23 |
| 變體圖 | 每變體 1 張，僅圖片 | 61 P21 |
| 單日新增變體（>50 萬變體店，Plus 豁免） | 10,000／24h | 61 P14/P54 |
| `productVariantsBulkCreate` 單次 | 2048（`REMOVE_STANDALONE_VARIANT` 策略才滿額；否則 2047＋自動 standalone） | G7 |
| 單商品 root 查變體 | 2048；一般 connection 分頁 ≤250 | G1、G7 |
| `collectionReorderProducts` 單次 | 250 | G7 |
| 含條件的系列／店 | 5,000 | G15 |
| 含變體（手動或自動）的系列／店 | 100 | G15 |
| 內含其他系列的系列／店 | 50 | G15 |
| 排除其他系列的系列／店 | 5 | G15 |
| 條件數／系列 | 60 | G24 |
| 系列品項區每頁 | 60 | 61 P23 |
| combined listing：child 數 | 60 | G11 |
| combined listing：全 child 變體**選項值**總數 | **2,000**（G11 逐字「variant option values」；G10 的摘要作 “variants”——以 help 逐字引句為準 ⚠️） | G11 |
| combined listing：parent 選項數 | 3（在各 child 自身選項之外） | G11 |
| bundle：組件數／bundle | **30** | G30 |
| metafield 定義／資源型別 | app 256 ＋ 商家 256；pinned 50 | G25 |
| metafield 值 | 多數型別 64KB；`json` 128KB（2026-04-01 前既有 app 保留 2MB）；`id`/`url` 2KB | G25 |
| metafield list 型別 | 128 項（metaobject reference list 256 項）；單行文字預選值 128 個 | G25 |
| 可驅動 smart collection 的 metafield 定義 | 128（`useAsCollectionCondition`） | G25 |
| Functions 讀 metafield | >10,000 bytes 回 null（值仍保存） | G25 |
| selling plans／group | 31（2023-01 起；官方建議分頁勿依賴定值） | G18 |
| selling plan group 選項 | 3 | G17 社群+文檔口徑 ⚠️ |
| 標籤／商品 | 250；單標籤 255 字元（訂單域 40 字元） | 61 P9/D16 |
| 商品標題/描述、type、vendor 字元上限 | **官方未載明** | 61 §1.2/§1.5 |

🔴 `ShopResourceLimits`（掛在 `Shop.resourceLimits`）四欄全集：`locationLimit: Int!`／`maxProductOptions: Int!`／`maxProductVariants: Int!`／`redirectLimitReached: Boolean!`（G12）⇒ 上限是 **per-shop 資料不是全域常數**；我方 limits.yml 應定位為「預設值＋允許 per-shop 覆寫」（61 §2.1 同結論）。

### C.2 Handle 規則（G1）

- 生成公式：取 title → 全小寫 → 空白與特殊字元替換為 `-` → **連續多個替換為單一 `-`**。
- 字元集：字母／數字／連字號，無空白。
- 🔴 **建立後改 title 不會改 handle**（Product 與 Collection 同規則，G14）。
- 唯一性：欄位描述明言 unique；**同名衝突時的消歧規則（尾綴 -1？）官方未載明** ⚠️ → openQuestions。
- help 補充：不宜頻繁改 handle（影響搜尋引擎收錄，G6）；改 handle 的舊 URL redirect 是否自動建立，本域文檔未載明（Redirect 屬 online store 域）⚠️。

### C.3 計算公式

| 公式 | 內容 | 來源 |
|---|---|---|
| 利潤率 | `(價格 − 每品項成本) ÷ 價格 × 100`；顯示條件＝「有填成本 ∧ 未勾收稅」；衍生唯讀 | 61 P4 |
| 單位定價 | `單位價格 = (價格 ÷ 總數量) × 基準計量`；單位同類相配；排除 `t`/`cg`/`st`；**是否法定要求＝法域能力**（→ jurisdiction pack） | 61 P12 |
| priceRangeV2 | min/max 為變體價格的衍生 rollup，**不落地為可寫欄位** | G1 |
| bundle 可售數 | `min_i ⌊組件i可售量 ÷ quantity_i⌋`，**向下取整**；未追蹤／`CONTINUE` 組件不計入；父項唯讀衍生（§A.10） | G31、G33 |
| rounding | 利潤率與單位定價官方**未載明捨入規則** ⚠️（bundle 可售數官方已明文向下取整）；我方裁定：內部以 integer cents 運算；**利潤率（百分比）**顯示兩位小數四捨五入；**單位定價（金額）**顯示走市場 locale 的幣別格式器與其小數位——zero-decimal 幣別（JPY/KRW）無小數，套「固定兩位」會渲染出 `¥1,480.00`（鐵律 3/10，§F）（2026-08-17 更正，PR #52 第 18 輪：原句把百分比與金額兩種顯示併成同一條兩位小數規則） |

### C.4 標籤與 SKU

- 標籤特殊字元**等價**：`red_new`／`red+new`／`red&new`／`red-new` 視為同一標籤 ⇒ 寫入前必過唯一正規化函式（倉庫 13 §F4.4 `Tags::Normalize`）。
- 標籤條件（系列）是**集合運算** `includes`/`does not include`，不是子字串 `contains`（G24）——SQL 形態＝正規化鍵等值 `EXISTS`，禁 `LIKE`（13 §F4.3）。
- SKU：admin 內要求唯一但**重複只警告不阻擋**；區分大小寫（G2）；「16 字元」是官方建議非硬上限（61 P10）。

### C.5 Collection 求值規則（本檔核心更新）

**條件欄位×運算子矩陣（admin 口徑，G24；GraphQL enum 對照 G26/G27）**：

| 欄位（admin） | 運算子（全集） | GraphQL column |
|---|---|---|
| Product title / Variant title / Type / Vendor | is equal to／is not equal to／starts with／ends with／contains／does not contain | TITLE / VARIANT_TITLE / TYPE / VENDOR |
| Product tag | **includes／does not include** | TAG |
| Product category | is equal to／is not equal to | PRODUCT_CATEGORY_ID（另有 **PRODUCT_CATEGORY_ID_WITH_DESCENDANTS**＝含所有子孫類別） |
| Product status | is equal to／is not equal to | ⚠️ dev enum 未見對應值（admin 有此條件；GraphQL CollectionRuleColumn 15 值中無 status）→ openQuestions |
| Price / Weight / Inventory stock | is equal to／is not equal to／is greater than／is less than | VARIANT_PRICE / VARIANT_WEIGHT / VARIANT_INVENTORY |
| Compare-at price | 上四者 ＋ **is set／is not set** | VARIANT_COMPARE_AT_PRICE（`IS_PRICE_REDUCED` 為其衍生布林欄位） |
| Metafield 布林/單行文字 | is equal to | PRODUCT_METAFIELD_DEFINITION（需 `useAsCollectionCondition`） |
| Metafield 整數/小數/評分 | is equal to／is greater than／is less than | 同上；變體側＝VARIANT_METAFIELD_DEFINITION |
| Metaobject 參照 | is equal to | 同上 |

`CollectionRuleRelation` enum 全集（10 值，G26）：`CONTAINS` / `NOT_CONTAINS` / `EQUALS` / `NOT_EQUALS` / `GREATER_THAN` / `LESS_THAN` / `STARTS_WITH` / `ENDS_WITH` / `IS_SET` / `IS_NOT_SET`。
`CollectionRuleColumn` enum 全集（15 值，G27）：`IS_PRICE_REDUCED` / `PRODUCT_CATEGORY_ID` / `PRODUCT_CATEGORY_ID_WITH_DESCENDANTS` / `PRODUCT_METAFIELD_DEFINITION` / `PRODUCT_TAXONOMY_NODE_ID` / `TAG` / `TITLE` / `TYPE` / `VARIANT_COMPARE_AT_PRICE` / `VARIANT_INVENTORY` / `VARIANT_METAFIELD_DEFINITION` / `VARIANT_PRICE` / `VARIANT_TITLE` / `VARIANT_WEIGHT` / `VENDOR`。

**邏輯連接**：ALL（match all）／ANY（match any），**無混合 AND/OR、無括號分組**；新模型中每個 conditions source 各帶自己的 `matchType`（G13）。

**求值優先序（官方已明文，取證 2026-08-14）**：
1. 🔴 **「Product exclusions always override any manual or automatic product inclusions」**（G15 逐字）——**exclude 恆勝**，倉庫 V-57 的假設（13 §F4.2 第 1 層）**獲官方證實，可結案**。
2. 手動加入除非手動移除否則恆在（61 P23）——條件重算不得踢出手動項。
3. 條件納入。
4. 同品多來源命中 ⇒ 去重只顯示一次（G15）。

**排除的能力邊界（新發現，G24）**：以「條件」做排除**只支援 category／tag／type／vendor 四種欄位**（手動排除不限）；`targetType=VARIANTS` 來源支援全部條件欄位。

**排序方式全集**（`CollectionSortOrder`，9 值，G28）：`ALPHA_ASC` / `ALPHA_DESC` / `BEST_SELLING` / `CREATED` / `CREATED_DESC` / `MANUAL` / `MOST_RELEVANT` / `PRICE_ASC` / `PRICE_DESC`。（BEST_SELLING 官方定義＝全期訂單數，61 P26。）

### C.6 併發要害與邊界案例

| 要害 | 內容 |
|---|---|
| 變體笛卡兒積 | 為既有選項加值 ⇒ 自動生成所有新組合；兩人同時加值可能超過 2048 ⇒ 上限檢查必須在 transaction 內以 DB 計數為準，不能信 UI 快照 |
| 選項增刪的變體身分 | 增刪選項時既有變體的 id 必須保持（63 §B.5）；官方 `productOptionsReorder` 存在但重排對 position 的副作用未載明 ⚠️ |
| 系列重算 | 商品欄位變更 → 所有引用該欄位的 conditions source 重算；系列套系列（sub-collection source）有遞迴風險 ⇒ 環偵測＋深度上限（13 §F4.5，官方未載明環規則 ⚠️） |
| 靜默覆蓋 | 商品寫入的併發要害不是超賣而是 last-write-wins 蓋掉他人編輯（63 §A.4） |
| 排程發布到點 | 到點時 status 非 ACTIVE ⇒ 不生效；實作上排程 job 必須重驗 status，不能發布「排程當下」的快照 |
| 隱藏缺貨 | 用 `Inventory stock > 0` 條件隱藏缺貨**只在 ALL 模式有效**，ANY 模式下無效（61 P38）——UI 應在 ANY＋此條件組合時警示 |
| unlisted 洩漏面 | `all_products`、Storefront API by handle、Cart AJAX 都取得到 unlisted ⇒ 「不可發現」只能實作在列表查詢層，不能實作在讀取層（G5） |

---

## D. 關鍵流程

### D.1 建立商品（操作者：商家／app）

1. 寫入 title（必填）等欄位；未給 handle ⇒ 依 §C.2 公式生成。
2. 無選項 ⇒ 系統建立唯一預設變體（`Default Title`，`hasOnlyDefaultVariant=true`）；有選項 ⇒ 依選項值笛卡兒積生成變體（bulk 上限 §C.1）。
3. 每變體同步建立 1:1 `InventoryItem`；多地點下自動指派到所有地點、數量 0（61 P36）。
4. media 進入 UPLOADED→PROCESSING 非同步管線（§B.3）。
5. status=ACTIVE 時，對每個 `autoPublish=true` 的 publication 自動建立 ResourcePublication。
6. 發事件：webhook `products/create`；失敗分支：選項超限（`OPTIONS_OVER_LIMIT`）、選項值超限（`OPTION_VALUES_OVER_LIMIT`）、變體超 2048 ⇒ userErrors，整體不落地。

### D.2 狀態變更／複製／刪除（§B.1 轉移表的流程面）

- Archive：列表移入 Archived 分頁；全管道不可得。Unarchive 是否還原發布設定未載明 ⚠️ ⇒ 我方實作需自定並標注（建議：保留 ResourcePublication 不刪，讓 unarchive 自然還原——與「archived 期間 publication 記錄保留」的假設綁定，需測本尊）。
- Duplicate：複製除 3D/影片外全部；狀態三選一（ACTIVE/DRAFT/UNLISTED，**無 ARCHIVED**）；選 ACTIVE ⇒ 繼承原品發布管道（G6）。handle 消歧規則未載明 ⚠️。
- Delete：永久不可復原（G6）；發 `products/delete`。

### D.3 發布與排程（操作者：商家）

1. `publishablePublish(id, [{publicationId, publishDate?}])`；scope `write_publications`。
2. 帶未來 `publishDate` ⇒ 排程（僅 online store；商品必須到點時仍 ACTIVE）。
3. 變體級：`publishablePublish` 對 ProductVariant 同樣適用（Publishable 實作者）；可見性＝父商品發布 ∧ 變體發布（AND）。
4. 市場維度：管道市場設了 catalog ⇒ 該管道顯示的商品還必須在 catalog 內（三層 AND，G21）。
5. 失敗分支：不支援排程的管道帶 publishDate、`requiresSellingPlan` 商品發往非 online store ⇒ userErrors。

### D.4 系列成員重算（系統）

1. 觸發：商品/變體欄位變更、tag 增刪、metafield（`useAsCollectionCondition`）變更、來源本身 CRUD、sub-collection 成員變化（遞迴傳播）。
2. 求值：各 include 來源（conditions ALL/ANY＋selections）聯集 → 減去排除（條件排除限 4 欄位＋手動排除）→ 去重。
3. 排序：依 `sortOrder`（MANUAL 時用商家排序，`collectionReorderProducts` 單次 ≤250）。
4. 發事件：`collections/update`；storefront 快取失效。

### D.5 建立 combined listing（操作者：Plus 商家經 app）

1. 前置：Plus/enterprise 方案＋Combined Listings app；child 商品必須已存在、非 bundle、未屬於其他 combined listing。
2. 建立 ⇒ parent 自動生成、status=DRAFT、掛 1..60 個 child、parent 選項 ≤3、全 child 選項值總數 ≤2000。
3. 前台：單一商品頁呈現 parent 選項；child 有獨立 URL；unlisted child 仍作為選項值顯示；僅 online store 管道。
4. 結帳/訂單只出現 child。

### D.6 類別 → category metafields → 結構化選項（操作者：商家）

1. 商品指定 taxonomy 類別（單選）⇒ 解鎖該類別 attributes（部分自動加入）。
2. category metafield 帶預設 metaobject entries；商家可自訂。
3. 將 metafield 連結到 `ProductOption.linkedMetafield` ⇒ 選項值改為引用 metaobject entries（改 entry 全域生效；色彩 swatch）。
4. 換類別後既有 metafields 的去留**官方未載明** ⚠️。

---

## E. 跨模組耦合

### E.1 事件（webhook topics，本域發出）

| Topic | 觸發 | 備註 |
|---|---|---|
| `products/create` / `products/update` / `products/delete` | 商品 CRUD | unlisted 狀態需 2025-10+ 版 webhook 才回真值（G5） |
| `collections/create` / `collections/update` / `collections/delete` | 系列 CRUD 與成員重算 | 新 sources 模型下需 2026-07+ 才能完整表達 |
| `publications` 相關（`product_listings/*` 為舊管道模型） | 發布變更 | ⚠️ 官方現行 topic 全集本輪未逐一取證 → openQuestions |

倉庫側（63 §C）：對外 webhook 粗粒度＋內部 outbox 細粒度（`product.updated` 帶 diff、`variant.price_changed` 等），消費者對順序免疫。

### E.2 依賴方向

| 對方領域 | 方向 | 耦合點 |
|---|---|---|
| 庫存 | 商品→庫存（建變體⇒建 InventoryItem）；庫存→系列（`VARIANT_INVENTORY` 條件、totalInventory）；bundle 父項庫存＝組件推導唯讀（§A.10 ↔ 02 章 `NON_MUTABLE_INVENTORY_ITEM`） | 1:1 InventoryItem；商品寫入路徑禁寫庫存量（63 §B.7） |
| 訂單/結帳 | 訂單→商品（行項引用 variant 快照）；`inventoryPolicy` 決定缺貨可否下單 | 刪商品不影響歷史訂單（快照） |
| 市場/目錄（M5） | 發布→catalog（三層 AND 第三層）；contextualPricing 依市場 | 88 §3.2：catalog 是讀取過濾，可後補 |
| 稅 | category 驅動稅率；`taxable`／taxCode（Plus） | 法域 pack 消費「稅務事件」 |
| 主題/Liquid | 前台經 drop 讀商品；`templateSuffix` 選模板；`all_products` 可及 unlisted | 快取失效鏈（63 §D） |
| SEO/feed | UNLISTED ⇒ noindex＋出 sitemap；handle 變更影響 URL | 30 號規格 |
| Metafields/metaobjects | 條件引擎（`useAsCollectionCondition` ≤128）；linked options；disclosures（metaobject＋jurisdictions 欄位） | 61 §1.2 |
| 訂閱（selling plans） | 商品/變體 ↔ groups；`requiresSellingPlan` 限 online store 發布 | 本檔僅概觀，深挖屬結帳/訂閱域 |

---

## F. 落地對應

### F.1 對應倉庫文檔

| 本檔節 | 倉庫文檔 |
|---|---|
| A.2–A.4、C.1–C.4 | `docs/specs/13` §F1–F3、`docs/research/61` §1–2、`docs/specs/63` §B |
| A.5、C.5、D.4 | `docs/specs/13` §F4（sources 模型）；61 §4 |
| A.6、B.2、D.3 | `docs/specs/88`（publication 模型）、`docs/research/82` §0.2 |
| B.1 | 13 §F1.2（四態＋兩維） |
| A.7、D.5 | 61 §2.1（合併刊登上限） |
| C.1 | `config/limits.yml`（鐵律 6） |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊原貌 | 我方裁定 | 依據 |
|---|---|---|---|
| 1 | 金額＝`Money`（十進位、商店幣別） | 內部一律 **integer cents ×100 不看幣別**；序列化層才轉 MoneyV2；PSP 依 pack 宣告格式另換算 | 鐵律 3、specs/65 |
| 2 | 上限為 per-shop 動態（ShopResourceLimits） | `limits.yml` 靜態值＝**預設**，架構上允許 per-shop 覆寫 | 61 §2.1 |
| 3 | BEST_SELLING＝全期訂單數 | 我方用 **90 天銷量 rollup**（刻意，效能取捨） | 13 §F4.8 標注 |
| 4 | exclude 優先序 2026-08-14 已官方明文 | 13 §F4.2 第 1 層原標「我方假設（V-57）」⇒ **應改標官方事實並結案 V-57**；第 2 層（manual 恆在）雙方一致 | 本檔 §C.5 |
| 5 | Collection 條件另有 `Product status` 欄位（admin） | 13 §F4.7 需補；⚠️ GraphQL enum 無對應值，先僅入 UI 值域 | §C.5 |
| 6 | `ruleSet` 已 deprecated（2026-07） | 13 §F4 已採 sources 模型 ✅；**API 版本過濾行為**（舊版看不到新系列）我方單版本 API 不適用，但匯入器需知 | §A.5 |
| 7 | 發布＝Publication×ResourcePublication×Catalog 三層 | 88 已採，catalog 層刻意延到 M5（讀取過濾可後補） | 88 §3.2 |
| 8 | 變體級發布真實存在（Publishable 含 ProductVariant） | 我方已建多型 `resource_publications`，變體級行為 M1 展開（88 §5#5）；**變體不可排程**已落 validation | 88 §2.2 |
| 9 | `userErrors` 泛用型無 code | 我方全 mutation typed code enum（刻意加嚴，非照抄） | CLAUDE.md 鐵律 4 |
| 10 | 單租戶語義 | 全業務表帶 `shop_id`、複合索引 shop_id 開頭；系列求值 SQL 一律帶租戶條件 | 鐵律 2 |
| 11 | 單位定價法定要求「某些地區」；disclosures 帶 jurisdictions | 一律 jurisdiction pack 能力旗標，核心只提供欄位與計算 | 鐵律 11 |
| 12 | 商品刪除即永久 | 我方同語義，但訂單行項持快照（63）；平台側軟刪除策略屬平台域另訂 | G6 |
| 13 | unlisted 讀取層可及（all_products 等） | 我方「不可發現」實作於列表查詢層（discoverable scope），讀取層放行——**必須照抄本尊**，否則 metafield 參照場景會壞 | §C.6 |
| 14 | 標籤特殊字元等價（隱式） | 我方顯式 `Tags::Normalize` 唯一實作，寫入與查詢共用 | 13 §F4.4 |

### F.3 開發驗收要點

1. **enum 不得縮水**：ProductStatus 四值、CollectionRuleRelation 十值、CollectionRuleColumn 十五值、CollectionSortOrder 九值、MediaStatus 四值、CombinedListingsRole 兩值、inventoryPolicy 兩值——CI 對照本檔值域表。
2. **不變量測試**：商品恆有 ≥1 變體；products 表無 price/sku/barcode/weight 欄；`discoverable ⊆ purchasable`；exclude 恆勝（含手動加入被排除）；手動加入不被條件重算踢出；同品多來源去重；**bundle 五不變量**——父項庫存不可直寫（寫入必拒，語義同 `NON_MUTABLE_INVENTORY_ITEM`）、可售數＝min-floor 推導（含 CONTINUE/未追蹤組件排除案例）、組件 ≤30、不巢狀、不得為 combined listing child／掛 selling plan／設 final sale（§A.10）。
3. **併發測試**：雙人同時加選項值撞 2048 上限；系列 sub-collection 環；排程發布到點時 status 已非 ACTIVE。
4. **邊界測試**：tag `includes` 對 `red` 不得命中 `red-new`；`contains` 的 `%`/`_` 跳脫；ANY 模式＋庫存>0 條件的警示；unlisted 商品在 sitemap/搜尋/推薦缺席但直接 URL 200。
5. **上限全部引 `limits.yml`**，缺 §C.1 表中任一鍵即補。

---

## G. 來源（全部取證 2026-08-14，除註明外）

| # | URL | 用途 |
|---|---|---|
| G1 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Product | Product 欄位/handle 規則/2048 查詢上限 |
| G2 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ProductVariant | 變體欄位/inventoryPolicy/變體級發布 |
| G3 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ProductOption | 選項欄位/linkedMetafield |
| G4 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus | 四態 enum |
| G5 | https://shopify.dev/docs/apps/build/product-merchandising/unlisted-products | unlisted 完整行為/可達路徑/Shop app 不支援 |
| G6 | https://help.shopify.com/en/manual/products/add-update-products | archive/duplicate/delete/handle 建議 |
| G7 | https://shopify.dev/docs/apps/build/graphql/migrate/new-product-model | bulk 2048/REMOVE_STANDALONE_VARIANT/reorder 250 |
| G8 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Publication | autoPublish/supportsFuturePublishing/catalog 可選 |
| G9 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ResourcePublication | publishDate/isPublished 語義 |
| G10 | https://shopify.dev/docs/apps/build/product-merchandising/combined-listings | 合併刊登模型/Plus 限定 |
| G11 | https://help.shopify.com/en/manual/products/combined-listings-app | 60/2000 選項值/3 選項/狀態行為 |
| G12 | https://shopify.dev/docs/api/admin-graphql/latest/objects/shopresourcelimits | per-shop 上限四欄 |
| G13 | https://shopify.dev/changelog/new-collection-model-and-apis-now-available | 2026-07 sources 模型/棄用清單 |
| G14 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/collectionCreate | CollectionCreateInput/sources input 形狀 |
| G15 | https://help.shopify.com/en/manual/products/collections/create-collection | 四項系列上限/exclude 恆勝（逐字）/去重 |
| G16 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishablePublish | 排程限 online store/requiresSellingPlan 限制 |
| G17 | https://shopify.dev/docs/apps/build/purchase-options | selling plan 類別/政策四類 |
| G18 | https://shopify.dev/changelog/selling-plan-group-limit-increase | 31 plans/group（2023-01） |
| G19 | https://help.shopify.com/en/manual/custom-data/metafields/category-metafields | category metafields/預設 entries/linked options |
| G20 | https://shopify.dev/docs/apps/build/product-merchandising/products-and-collections/metafield-linked | metafield-linked options |
| G21 | https://help.shopify.com/en/manual/online-sales-channels/channel-markets | 三層 AND（catalog ∧ published） |
| G22 | https://shopify.dev/docs/api/admin-graphql/latest/enums/MediaStatus | 媒體四態 |
| G23 | https://help.shopify.com/en/manual/products/product-media/product-media-types | 媒體規格上限 |
| G24 | https://help.shopify.com/en/manual/products/collections/conditions | 條件×運算子矩陣/60 條/排除限 4 欄位 |
| G25 | https://shopify.dev/docs/apps/build/custom-data/metafields/metafield-limits | metafield 上限全表 |
| G26 | https://shopify.dev/docs/api/admin-graphql/latest/enums/CollectionRuleRelation | 10 值 |
| G27 | https://shopify.dev/docs/api/admin-graphql/latest/enums/CollectionRuleColumn | 15 值 |
| G28 | https://shopify.dev/docs/api/admin-graphql/latest/enums/CollectionSortOrder | 9 值 |
| G29 | https://shopify.dev/docs/apps/build/product-merchandising/bundles | bundle 概觀：selling plan 互斥/管道四種/BundlesFeature 資格/requiresComponents |
| G30 | https://shopify.dev/docs/apps/build/product-merchandising/bundles/add-product-fixed-bundle | 30 組件上限/不可巢狀/組件庫存決定 bundle 庫存/非同步輪詢 |
| G31 | https://help.shopify.com/en/manual/products/bundles/eligibility-and-considerations | min-floor 庫存公式/CONTINUE 與未追蹤排除/final sale 不可設/換貨與批量編輯限制 |
| G32 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/productBundleCreate | 非同步 ProductBundleOperation/`productOperation` 輪詢 |
| G33 | https://shopify.dev/docs/api/admin-graphql/latest/enums/InventorySetQuantitiesUserErrorCode | `NON_MUTABLE_INVENTORY_ITEM`（官方描述例示 parent bundle） |
| G34 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ProductVariantComponent | 組件物件 `{productVariant, quantity}` |
| （61） | `docs/research/61-shopify-docs-products.md` 所引 help 頁（P4/P9/P10/P12/P14/P16/P21/P23/P26/P36/P38/P51/P54） | 取證 2026-08-12，本檔沿用處均已標注 |
