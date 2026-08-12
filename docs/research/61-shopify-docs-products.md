# 61 — Shopify 商品／變體／庫存／商品系列／採購單／禮品卡／CSV 權威功能邏輯字典

> **用途**：產品線（M2「商品線」）的官方文檔權威來源。上限值、狀態機、欄位定義以本檔為準；本檔沒寫的才去問使用者或另行研究。
> **研究方法**：2026-08-12 以 WebFetch 從 `help.shopify.com/zh-TW/manual/products` 目錄逐頁往下抓（zh-TW 為主、en 為輔，因 zh-TW 部分頁面為簡化版）；涉及數字與列舉值時，再以 `shopify.dev`（`latest` = 2026 版 API）交叉驗證。每條結論後方標出處編號，編號對應 §0 來源表。
> **法律邊界（CLAUDE.md 鐵律 9）**：本檔記錄**功能邏輯與數值事實**，不整段轉貼官方文案。少數逐字引述僅限於**列舉值語義**與**恆等式**這類「換句話說就會失真」的定義，長度均在一句以內。Shopify 的行銷文案、教學步驟、商標一律不抄。
> **法域（鐵律 11）**：本檔為法域中立描述。禮品卡到期、商品揭露、單位定價的**法規面**一律標為法域能力，交由 jurisdiction pack 處理，核心規格不直接綁定任一地區。
> **對應**：`docs/research/59`／`60`（實站拆解）、`docs/specs/13`（商品規格）、`docs/research/06`（資料模型）、`config/limits.yml` §7/§8。

---

## 0. 來源清單（全部實抓）

### 0.1 help.shopify.com（商家說明文檔）

| # | URL | 結果 |
|---|---|---|
| P1 | https://help.shopify.com/zh-TW/manual/products | ✅ 目錄，18 個子區 |
| P2 | https://help.shopify.com/en/manual/products | ✅ 同上（en 交叉驗證，子區一一對應） |
| P3 | https://help.shopify.com/en/manual/products/add-update-products | ✅ |
| P4 | https://help.shopify.com/en/manual/products/details/product-details-page | ✅ |
| P5 | https://help.shopify.com/zh-TW/manual/products/details | ✅（目錄） |
| P6 | https://help.shopify.com/en/manual/products/details/product-category | ✅ |
| P7 | https://help.shopify.com/en/manual/products/details/product-type | ✅ |
| P8 | https://help.shopify.com/en/manual/products/details/product-descriptions | ✅（內容偏寫作建議，無技術限制） |
| P9 | https://help.shopify.com/en/manual/products/details/tags | ✅ |
| P10 | https://help.shopify.com/en/manual/products/details/sku | ✅ |
| P11 | https://help.shopify.com/en/manual/products/details/product-pricing | ✅（目錄） |
| P12 | https://help.shopify.com/en/manual/products/details/product-pricing/unit-pricing | ✅ |
| P13 | https://help.shopify.com/zh-TW/manual/products/variants | ✅（目錄） |
| P14 | https://help.shopify.com/en/manual/products/variants/add-variants | ✅ **上限值主要來源** |
| P15 | https://help.shopify.com/en/manual/products/variants/edit-variants | ✅ |
| P16 | https://help.shopify.com/en/manual/products/variants/publish-variants | ✅ |
| P17 | https://help.shopify.com/en/manual/products/variants/searching-filtering | ✅ |
| P18 | https://help.shopify.com/en/manual/products/variants/find-variant-id | ✅ |
| P19 | https://help.shopify.com/en/manual/products/product-media | ✅（目錄） |
| P20 | https://help.shopify.com/en/manual/products/product-media/product-media-types | ✅ **媒體上限主要來源** |
| P21 | https://help.shopify.com/en/manual/products/product-media/add-images-variants | ✅ |
| P22 | https://help.shopify.com/en/manual/products/collections | ✅（目錄） |
| P23 | https://help.shopify.com/en/manual/products/collections/create-collection | ✅ **商品系列上限主要來源** |
| P24 | https://help.shopify.com/en/manual/products/collections/conditions | ✅ **條件運算子完整清單** |
| P25 | https://help.shopify.com/en/manual/products/collections/manage-sources | ✅ |
| P26 | https://help.shopify.com/en/manual/products/collections/collection-layout | ✅ |
| P27 | https://help.shopify.com/en/manual/products/collections/collection-settings | ✅ |
| P28 | https://help.shopify.com/en/manual/products/inventory | ✅（目錄） |
| P29 | https://help.shopify.com/en/manual/products/inventory/fundamentals | ✅（目錄） |
| P30 | https://help.shopify.com/en/manual/products/inventory/fundamentals/inventory-states | ✅ **五態定義主要來源** |
| P31 | https://help.shopify.com/zh-TW/manual/products/inventory/fundamentals/inventory-states | ✅ **zh-TW 官方譯名主要來源** |
| P32 | https://help.shopify.com/en/manual/products/inventory/setup | ✅（目錄） |
| P33 | https://help.shopify.com/en/manual/products/inventory/setup/set-up-inventory-tracking | ✅ |
| P34 | https://help.shopify.com/en/manual/products/inventory/setup/selling-when-out-of-stock | ✅ |
| P35 | https://help.shopify.com/en/manual/products/inventory/setup/inventory-csv | ✅ **庫存 CSV 欄位主要來源** |
| P36 | https://help.shopify.com/en/manual/products/inventory/setup/multi-managed-inventory | ✅ |
| P37 | https://help.shopify.com/en/manual/products/inventory/setup/bin-locations | ✅ |
| P38 | https://help.shopify.com/en/manual/products/inventory/setup/hide-out-of-stock | ✅ |
| P39 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory | ✅（目錄） |
| P40 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/viewing-inventory | ✅ |
| P41 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/adjusting-inventory-quantities | ✅ **調整原因清單** |
| P42 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/adjustment-history | ✅ **180 天保留期** |
| P43 | https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/bulk-editing-inventory | ✅ |
| P44 | https://help.shopify.com/en/manual/products/inventory/purchase-orders | ✅（目錄） |
| P45 | https://help.shopify.com/en/manual/products/inventory/purchase-orders/creating-purchase-orders | ✅ |
| P46 | https://help.shopify.com/en/manual/products/inventory/purchase-orders/creating-inventory-transfers | ✅ **PO↔轉移關係** |
| P47 | https://help.shopify.com/en/manual/products/inventory/purchase-orders/managing-suppliers | ✅（欄位必填性未載明） |
| P48 | https://help.shopify.com/en/manual/products/inventory/inventory-transfers | ✅（目錄） |
| P49 | https://help.shopify.com/en/manual/products/inventory/inventory-transfers/creating-and-managing-transfers | ✅ **轉移狀態機主要來源** |
| P50 | https://help.shopify.com/en/manual/products/import-export | ✅（目錄） |
| P51 | https://help.shopify.com/en/manual/products/import-export/using-csv | ✅ **商品 CSV 欄位主要來源** |
| P52 | https://help.shopify.com/en/manual/products/import-export/import-products | ✅ |
| P53 | https://help.shopify.com/en/manual/products/import-export/export-products | ✅ |
| P54 | https://help.shopify.com/en/manual/products/import-export/common-import-issues | ✅ |
| P55 | https://help.shopify.com/en/manual/products/searching-filtering | ✅ **列表篩選／排序／每頁 50** |
| P56 | https://help.shopify.com/en/manual/products/product-disclosures | ✅ |
| P57 | https://help.shopify.com/en/manual/products/gift-card-products | ✅（目錄） |
| P58 | https://help.shopify.com/en/manual/products/gift-card-products/overview | ✅ **禮品卡金額上限** |
| P59 | https://help.shopify.com/en/manual/products/gift-card-products/add-update-gift-card-products | ✅ |
| P60 | https://help.shopify.com/en/manual/products/gift-card-products/issue-gift-card | ✅ |
| P61 | https://help.shopify.com/en/manual/products/gift-card-products/modify-gift-card-settings | ✅ |
| P62 | https://help.shopify.com/en/manual/products/managing-vendor-info | ✅ |
| P63 | https://help.shopify.com/en/manual/products/bundles | ✅（目錄） |
| P64 | https://help.shopify.com/en/manual/products/bundles/eligibility-and-considerations | ✅ **組合庫存公式** |
| P65 | https://help.shopify.com/en/manual/products/purchase-options | ✅ |
| P66 | https://help.shopify.com/en/manual/products/combined-listings-app | ✅ **合併刊登上限** |
| P67 | https://help.shopify.com/en/manual/products/digital-service-product | ✅（目錄，技術細節在下層） |
| P68 | https://help.shopify.com/en/manual/products/analytics | ✅ |
| P69 | https://help.shopify.com/en/manual/shopify-admin/productivity-tools/bulk-editing | ✅（上限未載明） |
| P70 | https://help.shopify.com/en/manual/shopify-admin/productivity-tools/bulk-actions | ✅ |
| P71 | https://help.shopify.com/en/manual/custom-data/metafields | ✅（目錄，上限不在此頁） |
| P72 | https://help.shopify.com/en/manual/promoting-marketing/seo/adding-keywords | ✅ **SEO 字元上限** |

**未讀（低優先，與本任務主題弱相關）**：`/products/dropshipping`、`/products/pivoting-your-product-line`、`/products/details/product-insights`、`/products/details/product-pricing/determine-pricing`、`/products/details/product-pricing/sale-pricing`、`/products/details/product-pricing/smart-pricing`、`/products/bundles/scripts`、`/products/bundles/shopify-bundles`、`/products/purchase-options/{subscriptions,pre-orders,try-before-you-buy}` 下層、`/products/product-media/{product-photography,change-thumbnail,expert-3d-model,3d-scanner}`、`/products/collections/{make-collections-findable,search-view,smart-collections,manual-shopify-collection}`、`/products/inventory/transitioning-from-stocky`、`/products/inventory/adjusting-inventory/abc-analysis`、`/products/inventory/inventory-transfers/{viewing-transfers,barcode-scanner}`。

### 0.2 shopify.dev（交叉驗證用）

| # | URL | 結果 |
|---|---|---|
| D1 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Product | ✅ **`hasOnlyDefaultVariant` 關鍵證據** |
| D2 | https://shopify.dev/docs/api/admin-graphql/latest/objects/ProductVariant | ✅ |
| D3 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductStatus | ✅ **四值，含 UNLISTED** |
| D4 | https://shopify.dev/docs/apps/build/product-merchandising/unlisted-products | ✅ |
| D5 | https://shopify.dev/docs/api/admin-graphql/latest/objects/shopresourcelimits | ✅ |
| D6 | https://shopify.dev/docs/api/admin-graphql/latest/mutations/productOptionsCreate | ✅ |
| D7 | https://shopify.dev/docs/api/admin-graphql/latest/enums/ProductOptionUpdateUserErrorCode | ✅ |
| D8 | https://shopify.dev/docs/apps/build/graphql/migrate/new-product-model | ✅ |
| D9 | https://shopify.dev/docs/api/admin-graphql/latest/queries/inventoryProperties | ✅ **8 個 quantity name 權威清單** |
| D10 | https://shopify.dev/docs/apps/build/orders-fulfillment/inventory-management-apps | ✅ |
| D11 | https://shopify.dev/docs/apps/build/orders-fulfillment/inventory-management-apps/manage-quantities-states | ✅ **狀態轉換與 17 個 reason** |
| D12 | https://shopify.dev/changelog/the-product-variant-limit-is-now-2048-for-all-merchants | ✅ |
| D13 | https://shopify.dev/changelog/draft-order-and-transfer-shipment-inventory-is-moving-from-reserved-to-committed | ✅ 🔴 **2026-08-05，與我方 limits.yml 直接衝突** |
| D14 | https://shopify.dev/changelog/new-inventory-states-safety-stock-damaged-and-quality-control | ✅ |
| D15 | https://shopify.dev/docs/apps/build/custom-data/metafields/metafield-limits | ✅ |
| D16 | https://shopify.dev/docs/api/admin-rest/latest/resources/product | ✅（REST，僅列三態，見 §1.3） |
| D17 | https://shopify.dev/docs/apps/build/orders-fulfillment/inventory-management-apps/quantities-states | ❌ **404**，等價內容見 D11 |

---

## 1. 商品主體（Product）

### 1.1 ⭐ 裁定驗證一：無變體商品 ＝ 只有一個預設變體的商品

**60 號 §1 的結論成立，且官方文檔有直接證據。**

| 證據 | 官方定義 | 出處 |
|---|---|---|
| `Product.hasOnlyDefaultVariant` 欄位存在 | 語義為「商品是否只有一個**帶預設選項與預設值**的變體」 | D1 |
| Product **沒有** `price` 欄位 | Product 上只有 `priceRangeV2` 與 `compareAtPriceRange` 兩個**衍生區間**；單一價格在 ProductVariant | D1 |
| `ProductVariant.price` 為 **non-null** `Money!` | 變體必有價格 | D2 |
| `ProductVariant` 承載 `sku` / `barcode` / `inventoryItem!` / `inventoryPolicy!` / `taxable!` / `position!` / `selectedOptions!` | 價格、庫存、稅、排序全部掛在變體 | D2 |
| 無選項商品的變體標題固定為 `Default Title` | help 直接以 JSON 範例展示無變體商品仍有 `variants[0].id` | P18 |
| 刪除商品的最後一組選項時，官方措辭是「刪除**所有**變體選項與值，**包含預設的那一組**」 | 即：預設選項是一個真實存在、可被刪除的物件 | P15 |

**結論（可直接寫進規格）**：
```
商品恆有 ≥ 1 個變體。
「無變體商品」= hasOnlyDefaultVariant == true，其唯一變體的 selectedOptions 為預設值。
價格 / SKU / 條碼 / 庫存 / 重量 / 稅 一律只存在於 ProductVariant，Product 上不得有第二份。
Product 層只能有「衍生的」價格區間（min/max），且必須是查詢時算出來或 rollup 出來的。
```

- **60 號的補強**：實站觀察到的 pill 分組 id `product_variant_collapsible_*`（59 號 §2）與「有變體時商品頁三張卡消失」（60 號 §1）在官方文檔側得到對應——P4 明確說**價格／庫存／運送三區只在商品沒有變體時顯示在商品頁上**。所以那不是版面偏好，是資料模型的直接投影。
- **我方是否已涵蓋**：🟡 **部分**。`docs/research/06` 已有 `PRODUCT_VARIANT ||--|| INVENTORY_ITEM : "1:1"`，方向正確；但 `docs/specs/13` §F1 未把「恆有預設變體」寫成不變量，原型 `productPage()` 也仍把價格卡當成商品層欄位（59 號 §5 A-1）。**建議在 13 號 F1 加一條建表期不變量：`products` 表不得有 price/sku/barcode/weight 欄位**。

### 1.2 商品詳情頁的區塊組成（官方口徑）

| 區塊 | 官方定義／行為 | 我方是否已涵蓋 | 出處 |
|---|---|---|---|
| 標題 | 顧客看到的商品名稱；CSV 中 `Title` 為必填 | ✅ | P4、P51 |
| 說明 | 富文本；官方建議不要照抄製造商文案（會影響搜尋排名）。**字元上限官方文檔未載明** | ✅ | P4、P8 |
| 多媒體 | 圖片／影片／3D 模型 | ✅ | P4 |
| 類別（Category） | 取自 Shopify Standard Product Taxonomy，**每個商品只能有一個**。三個作用：①決定稅率 ②解鎖該類別的中繼欄位 ③影響銷售管道資格與篩選 | 🟡 部分（59 號 A-6：我方只有搜尋框，缺樹狀 picker 與「驅動稅率」語義） | P4、P6 |
| 定價 | 見 §1.4 | 🟡 | P4 |
| 庫存 | 見 §3 | 🟡 | P4 |
| 運送 | 勾選「實體商品」後才出現：重量、包材、原產國、HS 代碼 | 🟡 | P4 |
| 變體（子類） | 見 §2 | ✅ | P4 |
| 中繼欄位 | 自訂資料欄；類別會自動帶出類別中繼欄位 | ✅ | P4、P6 |
| 購買選項 | 一次性／訂閱／預購／先試後買，見 §8 | ✅ | P4、P65 |
| 商品揭露（Disclosures） | 法規警語，以 metaobject 實作，**帶 `Jurisdictions` 欄位指定必須顯示的國家／地區** | ❌ **我方完全沒有**（59 號 A-7） | P56 |
| 搜尋引擎產品資訊 | 標題／描述／handle 三欄 ＋ 預覽 | ✅ | P4 |
| 狀態 | 見 §1.3 | 🔴 **缺 UNLISTED** | P4、D3 |
| 發布 | 銷售管道 ＋ 市場 | ✅ | P4 |
| 商品組織分類 | 商品類型／廠商／商品系列／標籤 | ✅ | P4 |
| 佈景主題範本 | 指定該商品用哪個 template | ✅ | P4 |
| 深入分析（Insights） | 售出數量、顧客數、淨銷售額 | ✅ | P4 |

> ⚠️ **官方明列「商品組織分類」包含 Collections**——即從商品頁可以直接把商品加進商品系列。這是雙向關係，不只是從商品系列那頭加。

### 1.3 🔴 商品狀態：官方是**四**態，不是三態

`ProductStatus` 列舉（D3）：

| 值 | 官方語義（摘要，非逐字轉貼） | 前台可見性 |
|---|---|---|
| `ACTIVE` | 可販售，可發布到各銷售管道與 app | 完全可見 |
| `DRAFT` | 尚未備妥，顧客在任何管道都取用不到 | 完全不可見 |
| `ARCHIVED` | 已停售，顧客在任何管道都取用不到 | 完全不可見 |
| **`UNLISTED`** | **商品是 active 的，但需要直接連結才看得到**；不出現在搜尋、商品系列與商品推薦中 | **可購買，但不可被發現** |

`UNLISTED` 的完整行為（D4）：

- **可購買**：購物車、結帳、訂單、購後流程都與 active 相同。
- **不可被發現**：不進商品系列、站內搜尋、預測搜尋、商品推薦。
- **對搜尋引擎**：輸出 `noindex,nofollow`，**且排除於 sitemap 之外**，也排除於 Shopify Catalog。
- **可達路徑**：直接 URL、metafield 參照、分享連結。
- **引入版本**：`2025-10` GraphQL Admin API。**早於 2025-10 的 API 版本會把 unlisted 商品的 status 回成 `active`**（D4）。REST Product 資源目前仍只列 `active`/`archived`/`draft` 三值（D16）——這是 API 版本落差，不是矛盾。

**我方是否已涵蓋**：🔴 **未涵蓋，且已寫死成三態**。`docs/specs/13` 第 13 行逐字寫「status 三態（draft/active/archived）」。這是一個**列舉值缺漏**，補起來成本低（多一個 enum 值 ＋ 前台可見性規則多一個分支），但漏了之後補很痛——因為 `Product.published` scope 是「一處定義全站重用」，改它會牽動整個 storefront 查詢。

**建議的可見性規則（依 D4 導出）**：
```
可購買（可加入購物車 / 可結帳） := status IN (ACTIVE, UNLISTED) AND 已發布到該管道
可被發現（列表 / 搜尋 / 商品系列 / 推薦 / sitemap / feed） := status == ACTIVE AND 已發布到該管道
```
→ 我方目前把這兩件事當成同一個 scope，**必須拆成兩個**。

### 1.4 定價欄位

| 欄位 | 官方定義／規則 | 我方是否已涵蓋 | 出處 |
|---|---|---|---|
| 價格 | 以商店幣別（設定 > 一般）計；CSV 中留白會導致匯入失敗（「Blank price field」為常見錯誤） | ✅ | P4、P54 |
| 比較價格 | 折扣前的原價。**「必須大於價格」這條規則官方文檔未載明** | ✅ | P4 |
| 每品項成本 | 商家取得該品項的成本；**禮品卡不適用此欄** | 🟡 | P4 |
| 利潤／利潤率 | **衍生唯讀**。官方明載顯示條件為「有填每品項成本 **且** 未勾選『對此商品收取稅金』」。利潤率公式：`(價格 − 成本) ÷ 價格 × 100` | 🔴 我方無此兩欄（59 號 A-2）；**且顯示條件我方原先不知道** | P4 |
| 對此商品收取稅金 | 布林；建立商品時**預設為「是」**（60 號實站觀察，與文檔不衝突） | ✅ | P4、60 號 §7 |
| 稅務代碼 | **Shopify Plus 限定** | ❌ | P4 |
| 單位定價 | 四欄：`總數量` / `總數量單位` / `基準計量` / `基準單位`。公式：`(價格 ÷ 總數量) × 基準計量 = 單位價格`。單位型別必須同類相配（重量對重量、容量對容量）。官方明列**排除**的單位：`t`（噸）、`cg`（厘克）、`st`（英石） | 🟡（59 號 A-5 只記到「其他顯示價格」，單位定價四欄我方缺） | P12 |

> **單位定價的法域性**：官方措辭是「在某些地區顯示單位價格是法定要求」，但**未列出是哪些地區**。依鐵律 11，這應該做成 jurisdiction pack 的能力旗標（`unit_pricing_required: bool`），核心只提供欄位與計算，不硬編哪一國要。

### 1.5 商品類型 / 廠商 / 標籤 / SKU

| 項目 | 官方定義 | 上限 | 出處 |
|---|---|---|---|
| 商品類型（Product type） | 自由文字的自訂分類，非必填；**每個商品只能有一個**。與 Category 是兩個不同欄位——Category 來自標準分類法且驅動稅率，Type 純自訂 | 字元上限**官方文檔未載明** | P7、P6 |
| 廠商（Vendor） | **每個商品只能指定一個廠商**。可用大量編輯器或 CSV 批次改。與「採購單的供應商」是**不同的東西**，兩者不連動 | 字元上限**官方文檔未載明** | P62 |
| 標籤（Tags） | 官方建議只用一般字母、數字與連字號；**特殊字元會被忽略或視為等價**（`red_new`、`red+new`、`red&new` 與 `red-new` 被當成同一個標籤） | **每個商品 250 個**；商品／顧客／轉移／網誌文章的單一標籤 **255 字元**；訂單與訂單草稿的單一標籤 **40 字元** | P9、D16 |
| SKU | 非必填。官方要求**在 admin 內唯一，不得有兩個變體共用同一 SKU**；偵測到重複會顯示警告（但不阻擋）。Shopify Fulfillment Network 則強制唯一 | 官方建議「不超過 16 字元」——**這是建議不是技術上限**，硬上限官方文檔未載明 | P10 |

> 🔴 **標籤特殊字元等價**這條我方沒有。若照做，`product_tags` 正規化表（13 號 §F4.4）在寫入前必須先做**標籤正規化（normalize）**，否則 `red_new` 與 `red-new` 會變成兩列，條件比對結果與 Shopify 不一致。

---

## 2. 變體（子類）

### 2.1 ⭐ 上限值（本檔最重要的一節）

| 項目 | 數值 | 出處（**URL 直接可查**） |
|---|---|---|
| 每個商品的**選項**數上限 | **3** | P14；D6 錯誤碼 `OPTIONS_OVER_LIMIT` 的範例訊息即「最多只能指定 3 個選項」 |
| 每個商品的**變體**數上限 | **2,048** | P14、D12 |
| 上述變體上限的生效日與適用範圍 | **2025-10-15 起，適用全體 Shopify 商家**（先前歷史上限為 100） | D12 |
| 每個商品的**多媒體**數上限 | **250** | P14、P51 |
| **每個選項的選項值**數上限 | 🔴 **官方文檔未載明具體數字**。錯誤碼 `OPTION_VALUES_OVER_LIMIT`（語義為「選項值數量超過允許上限」）確實存在，證明**有**這個上限，但數字未公布 → **V-50** | D7 |
| 每個變體可掛的圖片數 | **1**（官方明載變體不支援 3D 模型與影片，且每個變體只能掛一張圖） | P21 |
| 單日可新增的變體數（>500,000 變體的商店；Plus 豁免） | **10,000**／24 小時；計時窗自當日首次上傳起算 | P14、P54 |
| 單次 `productVariantsBulkCreate` 可帶入的變體數 | **2,048** | D8 |
| 單一查詢可取回的變體數 | **2,048** | D1、D8 |
| 合併刊登（combined listing）可納入的商品數 | **60** | P66 |
| 合併刊登跨所有子商品的變體選項值總數 | **2,000** | P66 |
| 合併刊登本身可加的選項數 | **3** | P66 |

**Plus 差異**：`ShopResourceLimits` 物件同時暴露 `maxProductOptions`（每店可用的選項數上限）與 `maxProductVariants`（每商品變體上限）兩個 Int!（D5）——這代表**上限是 per-shop 可查詢的，不是全域常數**。我方 `config/limits.yml` 用靜態值是可以的，但**應該把它宣告成「預設值」並允許 per-shop 覆寫**，否則之後接 Plus 級租戶會撞牆。

### 2.2 變體的生成、排序與發布

| 功能 | 官方定義 | 我方是否已涵蓋 | 出處 |
|---|---|---|---|
| 變體生成 | 選項值的**笛卡兒積**。給既有選項加一個新值，會自動生出它與其他選項的所有組合 | ✅ | P14 |
| 選項排序 | 選項本身可拖曳重排（drag handle） | 🟡 我方原型有 dnd-kit 但未確認套在選項上 | P15 |
| 選項值排序 | 選項值也可拖曳重排（進「編輯」後拖） | 🟡 | P15 |
| 變體排序 | `ProductVariant.position` 為 non-null Int，語義是「該變體在變體清單中的順序」。**help 未載明變體本身可否直接拖曳重排**，只載明選項與選項值可以 → **V-51** | 🟡 | D2、P15 |
| 變體分組 | 商品頁的變體表**自動依變體選項分組**並顯示每組變體數；多選項時可用「Group by」改依哪個選項分組；**預設依第一個選項** | ❌ 我方變體矩陣是平表，無分組 | P17 |
| 變體篩選 | 每個選項可下一個篩選條件；多個篩選為 **AND**（只顯示全部符合的變體）。另可依地點篩選以看該地點庫存 | ❌ | P17 |
| 變體發布 | 可**逐變體**對各銷售管道／目錄發布或取消發布。**關鍵規則：要在某管道顯示，父商品與該變體必須都發布到該管道**。**不能為個別變體設定排程發布日期**。目錄自訂定價時，未發布到該目錄的變體**不會**套用該目錄的定價調整 | 🔴 **我方完全沒有變體級發布**（我方只有商品級） | P16 |
| 刪除最後一個變體 | 若要停售整個商品，需刪除所有變體選項與值**包含預設那組**；否則前台仍會顯示變體下拉選單 | 🟡 | P15 |

> 🔴 **「父商品與變體都要發布」是一條 AND 規則**，我方的 `Product.published` scope 若不加變體層過濾，會在有變體級發布的租戶上洩漏未發布變體。這與 §1.3 的可見性拆分是同一件事的兩面。

---

## 3. 庫存

### 3.1 ⭐ 裁定驗證二：五態恆等式與官方定義

**60 號 §4 的恆等式成立，官方文檔正式背書。**

`On hand`（現有庫存）的定義即為「Committed ＋ Unavailable ＋ Available 三者之和」（P30、P31 均逐字如此）。

**zh-TW 官方譯名（P31，權威）**：

| 英文 quantity name | zh-TW 官方譯名 | 官方定義（摘述） | 是否計入現有庫存 |
|---|---|---|---|
| `on_hand` | **現有庫存** | 某地點擁有的所有庫存單位 | —（本身即總和） |
| `available` | **可販售** | 可供銷售；**不分配至任何訂單、不保留給任何訂單草稿、不含待入庫** | ✅ |
| `committed` | **已分配** | 已納入訂單但尚未履行的單位數 | ✅ |
| `unavailable` | **不可販售** | 因訂單草稿保留、app 保留或其他擱置原因（損壞／品管／安全庫存）而保留的單位 | ✅ |
| `incoming` | **待入庫** | 從庫存轉移或 app 正在運往該地點；收到並轉為可販售前不可銷售 | ❌ **不計入** |

```
現有庫存 = 已分配 + 不可販售 + 可販售
待入庫 不在恆等式內
```

### 3.2 🔴 三套譯名並存——我方必須挑一套

| 概念 | 商品／變體頁（實站，60 號） | 庫存頁（實站，60 號） | **help 官方文檔（P31）** |
|---|---|---|---|
| unavailable | 無法供貨 | 不可用 | **不可販售** |
| committed | 已承諾 | 已佔用 | **已分配** |
| available | 可供貨 | 可用 | **可販售** |
| on_hand | 現有庫存 | 現有庫存 | **現有庫存** |
| incoming | （不顯示） | 在途 | **待入庫** |

**60 號建議採「庫存頁那套」，本檔建議改採「help 官方文檔那套」**，理由：實站 UI 譯名在兩個頁面就已經不一致（60 號 §4 已指出），說明它不是穩定的；而 help 文檔的定義段落是唯一同時給出**術語＋定義＋恆等式**的地方，是更穩的錨。**這是一條需要使用者裁定的取捨，不是我單方面能定的** → 記入 **V-52**。

> 我方 `docs/specs/13` §F5.1 目前用的是「可販售／已分配／不可販售／待入庫」——**與 help 官方文檔那套一致**。所以實際上 13 號已經選對了，反倒是 60 號的建議會造成回退。**不要照 60 號 §4 的建議改。**

### 3.3 🔴🔴 最重大衝突：草稿訂單／轉移保留的目標狀態正在遷移中

| 來源 | 說法 | 日期 |
|---|---|---|
| help 文檔 zh-TW（P31） | 草稿訂單保留的庫存 → **不可販售（Unavailable）**；草稿在轉為正式訂單前**不計入已分配** | 2026-08-12 抓取，仍是此說法 |
| help 文檔 en（P30） | 同上 | 同上 |
| **shopify.dev changelog（D13）** | 「先前以 `reserved` 狀態追蹤的**草稿訂單、轉移與出貨**庫存，正被移到 `committed` 狀態」 | **2026-08-05 發布** |

changelog 補充事實（D13）：
- 這是**一次性資料遷移**，只影響遷移執行時仍持有庫存的**進行中草稿訂單**與**未結案轉移／出貨**。
- `available` 與 `on_hand` **不受影響**；總庫存不變，只是在**兩個「不可販售」桶之間**移動。
- app 若讀 `reserved`，往後應改讀 `committed`；查詢語法不需改，只是數值位置變了。
- 報表上會看到 reserved 值遷移到 committed，**外加一筆一次性校正分錄**。

**判讀**：這是**一週前**（相對本檔撰寫日 2026-08-12）發布的變更，help 文檔尚未跟上。兩者不是矛盾，是**新舊模型的時間差**。

**我方衝突點（🔴 必須處理）**：

```yaml
# config/limits.yml 現況（第 424 行附近）
  # 訂單草稿保留庫存的去向＝unavailable（**不是 committed**）。出處：46c:546–549、46c:895（help）
  draft_reservation_target_state: unavailable
```
`docs/specs/13` §F5.1(d) 也寫死了：
```
訂單草稿保留庫存 → available → unavailable[draft_reserved]（不是 committed）
草稿轉正式訂單 → unavailable[draft_reserved] → committed
```

**這兩處都是照 46c（help 口徑）寫的，而 help 口徑正在被廢棄。** 我方若照現況實作，會做出一個**與 2026-08-05 之後的 Shopify 行為不一致**的庫存帳——而「肌肉記憶不能斷」正是 59 號定下的驗收標準。

**但我不建議現在就改**，理由有二：①遷移是否已對所有商店完成、admin UI 的「不可用」欄是否仍包含草稿保留，官方未載明；②我方的 `unavailable[draft_reserved]` 子桶設計（13 號 §F5.1）其實**比 Shopify 的新模型更能精準定位草稿到期回補**，貿然合併進 committed 會失去這個能力。→ 記入 **V-53**，在結案前 `draft_reservation_target_state` 維持現值但**必須加註「官方正在遷移」**。

> 順帶：D13 把 `reserved` 稱為「兩個 unavailable 桶之一」，這佐證了 `reserved` 在 Shopify 的模型裡本來就是 `unavailable` 的**子態**，與我方 13 號 §F5.1 的子分類設計同構。

### 3.4 權威 quantity name 清單（8 個）

`inventoryProperties` 查詢回傳的完整集合（D9）：

`available` / `committed` / `damaged` / `incoming` / `on_hand` / `quality_control` / `reserved` / `safety_stock`

- 其中 `damaged` / `quality_control` / `safety_stock` 是後加的（D14），三者**都歸屬 `on_hand` 之下**，在 admin 顯示為「不可用／不可販售」。
- `reserved` 是第四個 unavailable 子桶（D13 稱之）。
- **我方 `limits.yml` 的 `unavailable_subtypes` 目前是 `[damaged, quality_control, safety_stock, draft_reserved, app_reserved, other]`** —— 與官方的 `[damaged, quality_control, safety_stock, reserved]` 相比，我方多切了 `draft_reserved` / `app_reserved` / `other`。這是**刻意的細化**（13 號已註明理由），不算錯，但要知道：**這三個不是官方 quantity name，不能拿去對 API**。

### 3.5 狀態轉換（誰動誰）

| 事件 | 官方載明的轉換 | 出處 |
|---|---|---|
| 訂單成立 | `available → committed` | D11 |
| 訂單履行（出貨） | **減少 `committed`**（官方措辭只說減少 committed，未說 on_hand 何時減——依恆等式必然同步減 on_hand） | D11 |
| 訂單取消 | `committed → available` | D11 |
| 退貨重新入庫 | **增加 `available`** | D11 |
| 轉移收貨 | 增加收貨地點的數量（`incoming → available`，見 §5.2） | D11、P49 |
| 待入庫收到 | 狀態**自動變為可販售** | P30 |
| 編輯「現有庫存」 | 「可販售」等量變動 | P30 |
| 編輯「可販售」 | 「現有庫存」等量變動 | P30 |
| available ↔ 不可販售子態 | 由 app／商家以「調整」操作明確搬移 | D11、P41 |

🔴 **`committed` 對 app 是唯讀的**：官方明載「committed 狀態的庫存數量只受商家訂單的成立與履行影響」（D11）。→ **我方的 API 契約也應該把 committed 設成不可直接寫入**，只能由訂單事件驅動，否則庫存帳一定會對不平。

**官方未載明的轉換**（不要用常識補）：
- 部分履行時 committed 的扣減粒度。
- 退貨入庫是進 `available` 還是可選進 `quality_control`（P41 有 `return_restock` 這個調整原因，但未說預設落點）。
- 超賣（available 為負）時各態的算術行為。
→ 併入 **V-54**。

### 3.6 調整原因：help 7 項 vs dev 17 項

**help 給商家看的 7 項**（P41、P42）：
`Correction`（校正）／`Count`（盤點）／`Received`（收貨）／`Return restock`（退貨重新入庫）／`Damaged`（損壞）／`Theft or loss`（遭竊或遺失）／`Promotion or donation`（促銷或捐贈）

**dev 給 app 看的 17 項**（D11）：
`correction` / `cycle_count_available` / `damaged` / `movement_created` / `movement_updated` / `movement_received` / `movement_canceled` / `other` / `promotion` / `quality_control` / `received` / `reservation_created` / `reservation_deleted` / `reservation_updated` / `restock` / `safety_stock` / `shrinkage`

**判讀**：這**不是兩份清單打架**，是一份給人選的短清單 ＋ 一份含系統事件的長清單。`movement_*` 四項對應轉移生命週期、`reservation_*` 三項對應草稿保留、`cycle_count_available` 對應盤點、`shrinkage` 對應遭竊或遺失。

- **我方是否已涵蓋**：🟡 `limits.yml` 的 `adjustment_reasons` 是 help 那 7 項，**這對 UI 是對的**；但 13 號 §F5.1(g) 說「系統 6 種」——實際官方系統事件是 **10 種**（`movement_*` 4 ＋ `reservation_*` 3 ＋ `cycle_count_available` ＋ `shrinkage` ＋ `other`）。ledger 的 `reason` 值域要照 dev 那份長清單建，UI 下拉才照短清單。**兩者的對應表官方未提供** → **V-55**。

### 3.7 調整歷史

| 項目 | 官方定義 | 出處 |
|---|---|---|
| 保留期 | **180 天**（逐字：只能查看商品或變體最近 180 天的庫存調整歷史） | P42、P33 |
| 超過 180 天 | 走「庫存調整變更報表」，可依 SKU／地點／員工／app／調整原因篩選 | P42 |
| 記錄欄位 | 日期／活動（造成調整的事件）／建立者（員工、app 或銷售管道）／以及五態各自的**調整量與調整後總量** | P42 |
| 系統活動型別 | `Data correction`、`Transfer created`、`Removed from location`、`Reservation created`、`Reservation updated`、`Reservation deleted` | P42 |

- **我方是否已涵蓋**：✅ `limits.yml` 已有 `adjustment_history_retention_days: 180`（出處原記 `22:81` 實站，本檔補上官方出處 P42）。
- 🟡 **「建立者」三型別（員工／app／銷售管道）**我方 ledger 是否有這個欄位需確認——13 號 §F5 未明列。

### 3.8 庫存追蹤與超賣

| 功能 | 官方定義 | 我方是否已涵蓋 | 出處 |
|---|---|---|---|
| 追蹤庫存 | 開啟後才會記錄數量與歷史 | ✅ | P33 |
| 無庫存時繼續銷售 | **必須先開啟庫存追蹤，這個選項才會出現**。開啟後顧客可在數量為 0 **或以下**時購買 | 🟡 | P34 |
| POS 例外 | 「無庫存時繼續銷售」**不適用於 Shopify POS 下的訂單**；POS 店員仍可低於 0 銷售但會收到警告 | ❌ 我方無此規則 | P34 |
| 負庫存機制 | **官方文檔未載明**負數的上下界與前台顯示 | — | P34 |
| 未追蹤庫存時的行為 | **官方文檔未載明** | — | P34 |
| 隱藏缺貨商品 | 官方作法是用**自動商品系列條件**：`庫存數量 > 0`。⚠️ 官方明載此法**在「符合任一條件」模式下無效**，必須用「符合所有條件」 | ❌ | P38 |

> 🔴 「無庫存時繼續銷售不適用 POS」是一條**通路差異規則**。我方若做 POS，這條要進超賣 guard 的分支表。

### 3.9 多地點與置物格

| 項目 | 官方定義 | 上限 | 出處 |
|---|---|---|---|
| 地點指派 | 建立商品時**自動指派到所有地點，起始數量 0** | — | P36 |
| 可販售條件 | 商品**至少要在 1 個地點啟用**才可販售 | — | P36 |
| 啟用/停用地點 | 隨時可切換，**不影響該地點的庫存數量** | — | P36 |
| 庫存頁的列 | 「每個變體都會在**每一個啟用中的地點**列出，即使該地點不履行該變體」；不履行的地點其「可販售」顯示為破折號，但**仍可檢視與更新現有庫存** | — | P40 |
| 訂單路由 | 由訂單路由設定決定哪個地點履行 | — | P36 |
| 地點數上限 | `ShopResourceLimits.locationLimit`（Int!）存在，但**具體數值官方文檔未公布**（依方案而定）→ **V-56** | ? | D5、P36 |
| 置物格（Bin） | 每個變體**在每個地點只能指派到 1 個置物格**；多個 SKU 可共用同一置物格；**置物格名稱在地點內必須唯一** | 名稱字元上限**未載明** | P37 |
| 置物格設定方式 | 主要靠 CSV 匯入建立，之後可用大量編輯器改 | — | P37 |

> ❌ **置物格（Bin location）我方完全沒有**。它出現在庫存 CSV 的必要欄位裡（§6.2），且是庫存頁的一個顯示欄（P40）——不做的話庫存 CSV 就無法與 Shopify 對齊。

---

## 4. 商品系列（Collections）

### 4.1 ⭐ 新模型：sources（來源）而不只是 manual/smart

**這是 2026 版的結構性變更，我方 13 號 §F4 的 manual/smart 二分法已經過時。**

官方現在的模型（P25）：一個商品系列由若干**來源（source）**組成，來源型別有四種——
1. 主商品清單（Products）
2. 商品變體（Variants）
3. **其他既有的商品系列**（collection 套 collection）
4. app 來源

每個來源可以用**條件**納入，也可以**手動**指定；`Products` 來源另可**排除**特定商品（P25）。

- 手動加入的商品／變體：官方明載「除非手動移除，否則永遠留在該商品系列內」（P23）——即**手動加入優先於條件**。
- 🔴 **排除（exclude）與納入條件的優先順序，官方文檔未明確載明** → **V-57**。60 號 §6 觀察到建立頁有 `排除` 按鈕，本檔確認它是 `Products` 來源的能力，但語義未載明。
- 官方另有「Legacy smart collections」與「Legacy manual collections」兩個獨立頁面（P22）——**證實舊的 manual/smart 二分法已被官方標為 legacy**。

**我方是否已涵蓋**：🔴 **未涵蓋**。13 號 §F4 的 `rules` JSON + `collection_products` join 表只能表達「條件納入 ＋ 手動納入」，**表達不了**：①排除 ②collection 套 collection ③variants 來源。後兩者是資料模型層級的差異（需要 `collection_sources` 表），不是加個欄位就能補。

### 4.2 條件運算子完整清單（P24）

| 條件欄位 | 運算子 |
|---|---|
| 商品標題（Product title） | 等於／不等於／開頭為／結尾為／包含／不包含 |
| 變體標題（Variant title） | 等於／不等於／開頭為／結尾為／包含／不包含 |
| 商品類型（Type） | 等於／不等於／開頭為／結尾為／包含／不包含 |
| 廠商（Vendor） | 等於／不等於／開頭為／結尾為／包含／不包含 |
| **商品類別（Product category）** | 等於／不等於 |
| 商品標籤（Product tag） | **包括／不包括**（`includes` / `does not include`，**與字串類的「包含」是不同運算子**） |
| **商品狀態（Product status）** | 等於／不等於 |
| 價格（Price） | 等於／不等於／大於／小於 |
| 比較價格（Compare at price） | 等於／不等於／大於／小於／**未設定／已設定** |
| 重量（Weight） | 等於／不等於／大於／小於 |
| 庫存數量（Inventory stock） | 等於／不等於／大於／小於 |
| 中繼欄位（布林） | 等於 |
| 中繼欄位（整數） | 等於／大於／小於 |
| 中繼欄位（小數） | 等於／大於／小於 |
| 中繼欄位（評分） | 等於／大於／小於 |
| 中繼欄位（單行文字） | 等於 |
| **Metaobject 參照** | 等於／不等於 |

**邏輯連接**：「符合所有條件」（AND）／「符合任一條件」（OR）。**官方未提供混合 AND/OR 或分組括號的能力**。

**與我方的落差**：
- 🔴 我方 13 號 §F4 的 `rules` JSON 只有 `[{column, relation, condition}] + disjunctive boolean`——結構對，但**欄位值域缺**：`Product category`、`Product status`、`Metaobject reference`、以及 `Compare at price` 的 `is set`/`is not set` 兩個一元運算子我方都沒有。
- 🔴 **`Product tag` 用的是 `includes`/`does not include`，不是字串的 `contains`**——這是集合運算不是子字串比對。我方若把 tag 條件實作成 `LIKE '%x%'`，行為會與 Shopify 不同（`red` 會誤中 `red-new`）。這正好呼應 §1.5 的標籤正規化問題。
- 🟡 13 號 §F4 的「⚠️坑」提到「price 條件比對的是變體最低價還是任一變體？定死：任一變體」——官方文檔**未載明**這一點，我方的定法是自訂約定，**要在規格裡標明是我方假設** → **V-58**。

### 4.3 商品系列上限（P23，全部逐字有數字）

| 項目 | 數值 |
|---|---|
| 每店**含任何條件**的商品系列上限 | **5,000** |
| 每店**含手動或自動加入之變體**的商品系列上限 | **100** |
| 每店**內含另一個商品系列**的商品系列上限 | **50** |
| 每店**排除另一個商品系列**的商品系列上限 | **5** |
| 單一商品系列的**條件總數**上限 | **60** |
| 商品系列品項區的**每頁顯示數** | **60** |
| 單一商品系列可手動加入的商品數 | **官方文檔未載明** → **V-59** |

- **我方是否已涵蓋**：🟡 `limits.yml` 已有 `max_smart_collections_per_shop: 5000` 與 `max_rules_per_collection: 60`（✅ 與官方吻合），**缺後四項**。

### 4.4 排序方式（P26）

`最相關（Most relevant）` / `最暢銷（Best selling，全期訂單數）` / `字母 A-Z` / `字母 Z-A` / `價格由高到低` / `價格由低到高` / `日期由新到舊` / `日期由舊到新` / `手動`

手動排序的操作：拖曳，或用「移動」下拉選 `移到最前`／`移到最後`／`移到指定位置`（輸入數字）。

- 🔴 **「最相關」我方沒有**（官方說是依銷售表現）。13 號 §F4.5 列的是「手動/價格/新舊/暢銷」四類，**缺「最相關」與「字母」**。
- 🟡 「最暢銷」官方定義是**全期訂單數**；我方 13 號寫「用 90 天銷量 rollup」——**這是我方自訂，與官方不同**，要標明。

### 4.5 商品系列的其他欄位（P23、P27）

標題／說明（富文本）／精選圖片／銷售管道可見性／**發布排程日期時間**／佈景主題範本／搜尋引擎產品資訊（標題 ≤70 字元、描述 ≤320 字元）／排序方式。

> 官方特別提醒：讓商品系列對線上商店可見**不會自動把它掛到選單上**，這是兩件事。

---

## 5. 採購單與轉移

### 5.1 ⭐ 採購單只有兩個狀態

**60 號沒拆到狀態機，本檔補齊——而且答案比預期簡單得多。**

| 狀態 | 官方定義 | 出處 |
|---|---|---|
| **草稿（Draft）** | 採購單正在建立或審核中；可編輯所有細節、增刪商品 | P45 |
| **已訂購（Ordered）** | 已送交供應商；此時才可以為它建立庫存轉移 | P45 |

🔴 **官方明載「可以在任何時候編輯採購單的任何細節，包含標記為『已訂購』之後」**——供應商、收貨地、商品、成本全部隨時可改（P45）。

**沒有** `partially received` / `received` / `closed` 這些狀態，因為——

### 5.2 ⭐ 收貨不發生在採購單上，發生在轉移上

官方架構（P46，本檔最重要的架構發現之一）：

```
採購單（Purchase order）＝ 商業協議的紀錄
       ↓ 建立轉移時預先帶入相同的供應商、品項與數量
庫存轉移（Inventory transfer）＝ 出貨、收貨與成本調整的載體
```

- **收貨在「與採購單連結的庫存轉移」上進行，不在採購單本身**——官方明示這是為了「讓商業協議與實際庫存移動分離」。
- 連結之後，**兩份紀錄各自獨立；改其中一份不會自動更新另一份**。
- 供應商分批出貨時，**每批到貨可各自收貨**。

**60 號 §7 觀察到「轉移建立頁有『連結採購單』」，方向是對的，但因果反了**：不是「採購單→轉移→庫存」的三段鏈，而是「採購單是帳，轉移是貨」——兩條平行的紀錄，靠連結關聯。

- **我方是否已涵蓋**：🔴 **完全未涵蓋**。13 號沒有採購單與轉移。若照 60 號的鏈式理解去建模，會把收貨狀態掛在採購單上，與官方相反。

### 5.3 轉移狀態機（P49）

| 狀態 | 官方定義 | 對庫存的作用 |
|---|---|---|
| **草稿（Draft）** | 已建立但未標記為可出貨 | **草稿轉移中的庫存不被保留** |
| **可出貨（Ready to ship）** | 已標記為可出貨 | 庫存**在出貨地被保留** |
| **進行中（In progress）** | 轉移進行中 | 庫存在**收貨地標記為待入庫**，可以收貨 |
| **已轉移（Transferred）** | 轉移完成，所有品項已收並在收貨地可販售 | 收貨地 → **可販售** |
| **已取消（Canceled）** | 已取消 | 出貨地被保留的品項**回到可販售** |

**收貨時的三個動作**（P49）：

| 動作 | 官方定義的帳務效果 |
|---|---|
| **接受（Accept）** | 庫存在收貨地變為**可販售** |
| **拒收（Reject）** | **記錄在轉移上，但不改變任何地點的庫存數量** |
| **取消（Cancel，針對未出貨品項）** | 被取消的庫存**退回出貨地** |

🔴 **採購單來源的轉移有例外**（P46）：因為採購單的來源是**供應商**（不是自家地點），所以取消的庫存是**直接移除**，不是退回某個地點。

- **拒收數量的會計歸屬**：官方只說「記錄但不改庫存」，**未載明拒收數量後續如何處置**（退回供應商？索賠？）→ **V-60**。
- **部分收貨**：官方確認可分批收（P46、P49），但**未載明部分收貨後轉移停留在哪個狀態**（`In progress` 還是有 `Partially received`？）。P49 列的五態中沒有 partially received → **V-61**。

### 5.4 採購單／供應商欄位

**採購單欄位**（P45）：供應商／收貨地／商品（含數量）／供應商 SKU（選填）／成本與稅率百分比／參考編號／給供應商的備註／付款條件／**供應商幣別**／標籤／成本摘要與總計。

> 🔴 **採購單自帶幣別**（60 號 §7 已從實站觀察到，本檔以文檔確認）。這對鐵律 3（integer cents）是硬約束：採購單的金額**不能**用商店 presentment 幣別存，必須帶自己的 currency code，且與訂單金額不可混算。

**供應商欄位**（P47）：聯絡資訊／地址／供應商幣別／付款條件。🔴 **哪些必填、字元上限、供應商數量上限——官方文檔全部未載明** → **V-62**。

**標籤字元上限的矛盾**：P9 把 `transfers` 歸在 255 字元那一組，但 60 號實站在採購單建立頁量到計數器顯示 `0/40`（訂單那一組的上限）。**採購單本身不在 P9 的清單裡** → **V-63**。

---

## 6. CSV 匯入匯出

### 6.1 商品 CSV（P51、P52、P53、P54）

**檔案規格**：UTF-8 編碼、LF 換行、第一行為欄位標題、逗號分隔；**檔案大小上限 15 MB**（超過須拆檔）。**列數上限官方文檔未載明**。

**必填欄**：`Title`（商品標題）、`URL handle`（新增變體時必填）。另 CSV 常見錯誤明列 `Price` 留白會失敗、有 handle 就必須有 title（P54）。

**欄位分組**（P51，共約 38 欄）：

| 分組 | 欄位 |
|---|---|
| 商品層（變體列須留白） | `Title`、`Description`、`Vendor`、`Product category`、`Type`、`Tags`、`Published on online store`、`Status` |
| 識別 | `URL handle`（**變體列必須重複填**） |
| 變體層 | `Option1/2/3 name`、`Option1/2/3 value`、`SKU`、`Barcode`、`Price`、`Compare-at price`、`Cost per item`、`Weight value (grams)`、`Weight unit for display` |
| 庫存與履行 | `Inventory tracker`（`shopify`/`shipwire`/`amazon_marketplace_web`）、`Inventory quantity`（**僅單一地點**）、`Continue selling when out of stock`（`deny`/`continue`）、`Charge tax`、`Requires shipping`、`Fulfillment service` |
| 市場 | `Included / [Primary]`、`Included / International`、`Price / International`、`Compare-at price / International` |
| 媒體與 SEO | `Product image URL`、`Image position`、`Image alt text`、`Variant image URL`、`SEO title`、`SEO description` |
| 其他 | `Gift card`、`Google Shopping / Google Product Category`、`Collection`（**僅匯入**）、中繼欄位 |

**多變體如何表達成多列**（P51，這正是任務要問的）：

```
第 1 列：商品層全部欄位 ＋ 第 1 個變體的變體層欄位
第 2 列起：URL handle「必須重複」；
          Title / Description / Vendor / Product category / Type / Tags /
          Status / Published on online store 「必須留白」；
          只填該變體的 Option 值、SKU、Price、Weight、圖片等
```

🔴 **官方警告（逐字語義）**：改動 `Option1/2/3 value` 欄位會**刪除既有的變體 ID 並產生新的變體 ID**。→ 這意味著**變體的身分是由選項值組合決定的，不是由一個穩定主鍵決定的**。我方若要做 Shopify 匯入器（60 號 §5 指出這是「吸引 Shopify 客戶轉投」的關鍵路徑），必須複製這個語義，否則客戶搬過來後訂單歷史會對不上。

**匯入行為**（P52）：
- 選項「以相同 handle 覆寫商品」——啟用後，**CSV 裡有的欄位一律覆寫，空白儲存格會把既有資料洗掉**；CSV 裡**沒有的欄位**則保持不變。
- **匯入一旦開始就無法取消**。
- 部分失敗的行為**官方文檔未載明** → **V-64**。

**匯出行為**（P53）：
- 四種選取範圍：本頁／全部／已選取／符合搜尋與篩選。
- 兩種格式：試算表用 CSV／純 CSV。
- 🔴 **交付方式的數字門檻**：只要**任一商品的變體數超過 100**，檔案就用 **email** 寄送；若全部商品變體數都少於 100，才由瀏覽器直接下載。
- 官方警告：在試算表軟體裡排序 CSV 會讓變體或圖片 URL 脫鉤。

### 6.2 庫存 CSV（P35）——與商品 CSV 是兩套

**檔案大小上限 15 MB**（與商品 CSV 相同）。**列數上限未載明**。

| 欄位 | 必填 | 語義 |
|---|---|---|
| `Handle` | ✅ | 商品的唯一名稱（字母、連字號、數字，不含空格） |
| `Title` | ❌ | 可留白，僅供閱讀 |
| `Option 1/2/3 Name` | ❌ | **僅供閱讀，不會更新選項名稱** |
| `Option 1 Value` | ✅ | 用來識別具體變體 |
| `Option 2/3 Value` | 條件必填 | 變體有用到第 2/3 個選項時必填 |
| `SKU` | ❌ | **不會更新變體的 SKU**（要改 SKU 得用商品 CSV） |
| `HS Code` | ❌ | 可更新 |
| `COO` | ❌ | 原產國，ISO 代碼；可更新 |
| `Location` | ✅ | **地點名稱大小寫敏感，必須與 Shopify 地點名稱完全一致** |
| `Bin name` | ❌ | 置物格 |
| `Incoming` | — | **不可編輯** |
| `Unavailable` | — | **不可編輯** |
| `Committed` | — | **不可編輯** |
| `Available` | — | **不可編輯** |
| `On hand (current)` | 選填 | 匯出當下的快照，供驗證用 |
| `On hand (new)` | 選填 | 要設定的新數量 |

🔴 **`On hand (current)` 是樂觀鎖**：官方明載這兩欄一起用是為了**安全驗證**，**省略 current 值會停用該保護**。→ 這是官方文檔裡少見的、直接寫在 CSV 欄位語義裡的併發控制，我方 CSV 匯入必須複製（對照鐵律 5 的冪等要求）。

🔴 **五態欄位在庫存 CSV 裡全部唯讀，唯一可寫的是 `On hand (new)`**。這與 §3.5「committed 對 app 唯讀」是同一條原則的不同表現：**庫存的可寫入面只有 on_hand 與 available，其餘全部由事件驅動**。

**地點的兩種表達法**（P35）：
- 「全狀態」格式：`Location` 是一個欄，**每個變體 × 每個地點一列**。
- 「僅可販售」格式：**地點名稱直接當欄位標題**，底下放可販售數量。

→ 我方匯出要同時支援這兩種佈局，否則商家從 Shopify 搬過來的檔案讀不進。

### 6.3 大量編輯器（Bulk editor）

| 項目 | 官方說法 | 出處 |
|---|---|---|
| 支援的資源 | 商品與商品變體、商品系列、顧客、庫存。**已不再支援**網誌文章、頁面、URL 轉址 | P69 |
| 可編輯欄位（庫存情境） | 價格、比較價格、每品項成本、收取稅金、SKU、條碼、無庫存時繼續銷售、追蹤數量、庫存所在地點（多地點店）、重量、需要運送、HS 代碼、原產國、各地點數量 | P43 |
| 🔴 **關鍵語義** | 大量編輯器設定的是**絕對數量**，不指定來源與目的地，**因此不會產生庫存異動的稽核軌跡** | P43 |
| 筆數上限 | **主頁未載明**；P36 在多地點情境下提到「大量編輯支援一次 50 個商品」 → 數字有出處但只出現一次，**未在大量編輯器主頁確認** → **V-65** | P69、P36 |

> 🔴 「大量編輯器不產生稽核軌跡」與我方 13 號 §F5「每一筆都寫 ledger」**直接衝突**。Shopify 在此刻意留了一個繞過 ledger 的後門。**我方不應照抄這個後門**——但要知道：照抄 Shopify 的人會期待「大量編輯不留痕」。建議我方仍寫 ledger，但 `reason` 標為 `bulk_edit_absolute_set`，把差異記錄下來而不是隱藏。這條要進 PR 假設清單。

### 6.4 大量動作（Bulk actions，P70）

商品可用的大量動作：設為可販售／設為不可販售／刪除所選商品／新增標籤／移除標籤／加入商品系列／從商品系列移除／app 功能／執行自動化工作流程（需 Shopify Flow）。

| 項目 | 數值 |
|---|---|
| 桌機一次可選 | **不限**（可選取全店或全部篩選結果） |
| **行動裝置一次可選** | **25** |
| 商品列表每頁 | **50** |

---

## 7. 禮品卡

### 7.1 兩條完全不同的路徑（60 號 §7 的判斷正確）

| | **禮品卡商品** | **後台直接建立禮品卡** |
|---|---|---|
| 是什麼 | 可在店面販售的商品 | 直接發給顧客的一張卡 |
| 面額怎麼設 | **以變體表達**——每個面額是一個變體；**至少要有一個面額** | 建立時填「初始金額」 |
| 金額上限 | **> 0，最高 10,000 USD 或等值當地幣別**（官方註明**此上限不可調高**） | **> 0，最高 2,000 USD 或等值當地幣別** |
| 建立時機 | 顧客完成購買後，系統**產生**一張對應面額的禮品卡，列入後台「禮品卡」區 | 商家在後台直接建立 |
| 出處 | P58、P59 | P58、P60 |

🔴 **「面額 ＝ 變體」是一個結構事實**，不是 UI 選擇。這意味著禮品卡商品**吃 §2.1 的所有變體上限**（3 選項、2,048 變體）。我方 56/57 號的禮品卡會計討論只涵蓋「直接發卡」（60 號 §7 已指出），**現在再加一條：禮品卡商品要走商品/變體的完整資料路徑，不能另建一張表**。

### 7.2 到期與其他

| 項目 | 官方定義 | 出處 |
|---|---|---|
| 預設到期行為 | **預設不到期**，官方理由逐字語義為「某些國家禮品卡到期是違法的」 | P61 |
| 啟用到期後的預設值 | **5 年**，可自訂 | P61 |
| 法規責任 | 官方一律導向「請諮詢當地稅務或法律專家」，**不列出具體國家清單** | P58、P60、P61 |
| 後台直接建卡的欄位 | 初始金額／幣別（預設商店幣別，可選市場設定裡的當地幣別）／顧客（姓名、電話或 email）／到期日（選填）／內部備註 | P60 |
| 代碼可見性 | 商家**只看得到代碼的最後四碼** | P58、P60 |
| 代碼格式與長度、可否自訂 | **官方文檔未載明** → **V-66** | P60 |
| 是否課稅／是否需要運送 | **官方文檔未在這幾頁載明**（僅說要諮詢專家）；P4 另提到禮品卡**不適用「每品項成本」欄位** | P58、P4 |
| 可否退款／停用 | **官方文檔未在這幾頁載明** → **V-66** | P61 |

**法域對應（鐵律 11）**：官方自己就把禮品卡到期做成「商家自負責任、預設關閉」——這與我方的 jurisdiction pack 設計同構。HK 的 PSSVFO/SVF 單一用途豁免（CLAUDE.md 鐵律 11）決定的是**禮品卡不得跨租戶通用**，這一層 Shopify 文檔完全沒有對應概念（Shopify 是單商店模型，沒有跨租戶問題）——**這是我方多租戶架構獨有的約束，不能從 Shopify 文檔推導，也不會與之衝突**。

---

## 8. 其他模組（掃過，供索引）

| 模組 | 官方要點 | 我方是否已涵蓋 | 出處 |
|---|---|---|---|
| 商品組合（Bundles） | 🔴 **組合不能包含組合**。可售組合數公式：對每個元件算 `該元件可販售量 ÷ 組合所需數量`，**取最小值並向下取整** | ❌ | P64 |
| 組合的元件數上限 | **官方文檔未載明** → **V-67** | — | P64 |
| 購買選項 | 一次性／訂閱（週期扣款）／預購（**先收款、後履行**）／先試後買（**先履行、後於指定日期收款**） | ✅（原型有卡片） | P65 |
| 合併刊登 | 父商品連結子商品；子商品在前台**顯示為變體**，但可帶變體層通常沒有的商品細節。父層選項與子商品自身的變體選項**是分開疊加的** | ❌ | P66 |
| 數位商品 | 索引頁；技術細節（不需運送、檔案大小上限）在未讀的下層頁 | 🟡 | P67 |
| 商品分析 | 商品列表頂部分析列三個指標：售出率（近 30 天，`售出量 ÷ (售出量 + 在庫量)`）、剩餘庫存天數（`在庫量 ÷ 期間日均售出量`）、庫存價值 ABC 分析（A≈營收 80%、B≈15%、C≈5%） | 🟡 我方有分析圖但公式未對齊 | P68 |
| 商品列表篩選欄位 | 廠商／標籤／狀態／類別／銷售管道／地區目錄／B2B 目錄／公司地點目錄／零售目錄／未指派目錄／類型／商品系列／**發布錯誤**／禮品卡／合併刊登／中繼欄位 | 🟡 | P55 |
| 商品列表排序 | 商品 A-Z/Z-A／建立時間／更新時間／庫存／商品類型／**發布（Publishing）**／廠商 | 🟡 | P55 |
| 封存 vs 刪除 | 封存**可還原**；刪除**永久且不可還原** | ✅ | P3 |
| 複製商品 | 可設新標題、設狀態、**勾選要複製哪些細節**；**3D 模型與影片一律自動複製**（不可勾選） | 🟡 | P3 |
| 中繼欄位上限 | 每個 app 每種資源型別 **256** 個定義；商家每種資源型別 **256** 個定義；釘選 **50** 個／資源型別。值大小：多數型別 **64KB**，`id` 與 `url` 為 **2KB**，`json` 為 **128KB**。list 型別最多 **128** 項（metaobject 參照為 **256** 項）。單行文字的選項清單上限 **128** 個值。可用於 smart collection 的定義上限 **128**；可用於 admin 篩選：商品/公司/地點/metaobject **50**、訂單 **5** | ❌ 我方 limits.yml 無中繼欄位段 | D15 |
| SEO 欄位 | 頁面標題**最多 70 字元**（官方建議 ≤60 以免被截斷）；中繼描述在 SEO 主頁建議 160 字元，在 CSV 與商品系列設定頁則標**最多 320 字元** | 🟡 | P72、P27、P51 |

---

## 9. ⭐ 數字與上限總表（給 `config/limits.yml`）

> **本表所有數字都有 URL 出處，沒有一個是估計值。** 「未載明」欄位一律不填數字。
> 建議的 YAML 鍵名以我方既有結構為準；**本檔不改 `limits.yml`**，只提供素材。

### 9.1 商品與變體

| 建議鍵 | 值 | 出處 | limits.yml 現況 |
|---|---:|---|---|
| `product.max_options` | 3 | P14、D6 | ✅ 已有，吻合 |
| `product.max_variants` | 2048 | P14、D12 | ✅ 已有，吻合 |
| `product.max_media` | 250 | P14、P51 | ✅ 已有，吻合 |
| `product.max_tags` | 250 | P9、D16 | ❌ **缺** |
| `product.tag_max_chars` | 255 | P9、D16 | ❌ **缺**（discount 段有 tag_max_chars 255，商品段沒有） |
| `order.tag_max_chars` | 40 | P9 | ❌ **缺** |
| `product.daily_variant_upload_limit` | 10000 | P14、P54 | ✅ 已有，吻合 |
| `product.daily_variant_upload_plus_exempt` | true | P14 | ✅ 已有 |
| `product.daily_variant_upload_applies_above_variants` | 500000 | P14、P54 | 🟡 註解有，未成鍵 |
| `product.variant_bulk_create_max` | 2048 | D8 | ❌ 缺 |
| `product.variant_query_max` | 2048 | D1、D8 | ❌ 缺 |
| `product.max_images_per_variant` | 1 | P21 | ❌ **缺** |
| `product.title_max_chars` | **官方未載明** | — | 🔴 現有 255 **出處不明** → V-68 |
| `product.description_max_bytes` | **官方未載明** | — | 🔴 現有 65536 **出處不明** → V-68 |
| `product.max_option_values_per_option` | **官方未載明**（錯誤碼存在） | D7 | → V-50 |
| `product.max_products_per_shop` | **官方未載明** | — | → V-69 |
| `combined_listing.max_child_products` | 60 | P66 | ❌ 缺 |
| `combined_listing.max_option_values_total` | 2000 | P66 | ❌ 缺 |
| `combined_listing.max_options` | 3 | P66 | ❌ 缺 |

### 9.2 媒體

| 建議鍵 | 值 | 出處 | 現況 |
|---|---:|---|---|
| `media.image_max_px` | 5000 × 5000 | P20、P54 | ❌ 缺 |
| `media.image_max_megapixels` | 25 | P20、P54 | ❌ 缺 |
| `media.image_max_file_mb` | 20 | P20 | ❌ 缺 |
| `media.image_formats` | PNG, JPEG, PSD, TIFF, BMP, GIF, SVG, HEIC, WebP（GIF/WebP 支援動畫） | P20 | ❌ 缺 |
| `media.video_max_minutes` | 10 | P20 | ❌ 缺 |
| `media.video_max_file_gb` | 1 | P20 | ❌ 缺 |
| `media.video_max_resolution` | 4096 × 2160 | P20 | ❌ 缺 |
| `media.video_formats` | mp4, mov, webm（另支援 YouTube/Vimeo 嵌入） | P20 | ❌ 缺 |
| `media.model3d_max_file_mb` | 500 | P20 | ❌ 缺 |
| `media.model3d_auto_optimize_above_mb` | 15 | P20 | ❌ 缺 |
| `media.model3d_formats` | GLB, USDZ | P20 | ❌ 缺 |
| `media.alt_text_max_chars` | 512（官方另建議 ≤125） | P51 | ❌ 缺 |

> ⚠️ **官方自相矛盾**：同一頁（P54）先寫「最大 5000 × 5000 px 或 25 megapixels」，錯誤訊息卻寫「超過 **20** megapixel 上限」。**兩個數字都是官方的**，取捨需裁定 → **V-70**。（附註：我方 13 號驗收清單有「上傳 60MP 圖被拒」，60MP 兩種標準下都會被拒，所以該測試不受影響。）

### 9.3 商品系列

| 建議鍵 | 值 | 出處 | 現況 |
|---|---:|---|---|
| `collection.max_with_conditions_per_shop` | 5000 | P23 | ✅ 已有（名為 `max_smart_collections_per_shop`） |
| `collection.max_conditions_per_collection` | 60 | P23、P24 | ✅ 已有（名為 `max_rules_per_collection`） |
| `collection.max_with_variants_per_shop` | 100 | P23 | ❌ **缺** |
| `collection.max_containing_collection_per_shop` | 50 | P23 | ❌ **缺** |
| `collection.max_excluding_collection_per_shop` | 5 | P23 | ❌ **缺** |
| `collection.items_page_size` | 60 | P26 | ❌ 缺 |

### 9.4 庫存

| 建議鍵 | 值 | 出處 | 現況 |
|---|---:|---|---|
| `inventory.top_level_states` | on_hand, available, committed, unavailable, incoming | P30、P31 | ✅ 已有，吻合 |
| `inventory.api_quantity_names` | available, committed, damaged, incoming, on_hand, quality_control, reserved, safety_stock（**8 個**） | D9 | ❌ **缺**（與 top_level_states 是不同的東西，兩者都要有） |
| `inventory.unavailable_subtypes_official` | damaged, quality_control, safety_stock, reserved | D9、D14、D13 | 🟡 我方是 6 個自訂子桶，需標明「非官方 quantity name」 |
| `inventory.adjustment_reasons_ui` | 7 項（correction, count, received, return_restock, damaged, theft_or_loss, promotion_or_donation） | P41、P42 | ✅ 已有，吻合 |
| `inventory.adjustment_reasons_api` | 17 項（見 §3.6） | D11 | ❌ **缺** |
| `inventory.adjustment_history_retention_days` | 180 | P42、P33 | ✅ 已有；**本檔補上官方出處**（原記錄只有實站出處） |
| `inventory.committed_writable_by_app` | false | D11 | ❌ 缺（重要不變量） |
| `inventory.csv_max_upload_mb` | 15 | P35 | ✅ 已有（`media.csv_max_upload_mb`） |
| `inventory.max_bins_per_variant_per_location` | 1 | P37 | ❌ 缺 |
| `inventory.max_locations_per_shop` | **官方未載明**（欄位存在，值依方案） | D5 | → V-56 |
| `inventory.draft_reservation_target_state` | 🔴 **遷移中**（help=unavailable，dev changelog 2026-08-05=committed） | P30/P31 vs D13 | 🔴 現值 `unavailable`，**須加註** → V-53 |

### 9.5 CSV 與批次

| 建議鍵 | 值 | 出處 | 現況 |
|---|---:|---|---|
| `csv.product_max_upload_mb` | 15 | P52 | ✅ 已有 |
| `csv.inventory_max_upload_mb` | 15 | P35 | ✅ 同上 |
| `csv.product_max_rows` | **官方未載明** | P51/P52 | 🟡 我方自訂 5 萬行（13 號 §F6.2），須標明為我方值 |
| `csv.export_email_threshold_variants` | 100（任一商品變體數 > 100 即改 email 寄送） | P53 | ❌ **缺** |
| `csv.collection_column_max_chars` | 255 | P51 | ❌ 缺 |
| `bulk.mobile_max_selection` | 25 | P70 | ❌ **缺** |
| `bulk.desktop_max_selection` | 不限 | P70 | ❌ 缺 |
| `bulk.editor_max_items` | 50（**僅在 P36 出現一次，未於編輯器主頁確認**） | P36 | → V-65 |
| `product.list_page_size` | 50 | P55 | 🟡 60 號已從實站記錄，本檔補官方出處 |

### 9.6 SEO / 中繼欄位 / 禮品卡

| 建議鍵 | 值 | 出處 | 現況 |
|---|---:|---|---|
| `seo.page_title_max_chars` | 70（建議 ≤60） | P72、P27 | ❌ 缺 |
| `seo.meta_description_max_chars` | 320（SEO 主頁另建議 160） | P27、P51、P72 | ❌ 缺 |
| `metafield.max_definitions_per_owner_type` | 256（app 與商家各 256） | D15 | ❌ 缺 |
| `metafield.max_pinned_per_owner_type` | 50 | D15 | ❌ 缺 |
| `metafield.value_max_bytes_default` | 65536（64KB） | D15 | ❌ 缺 |
| `metafield.value_max_bytes_json` | 131072（128KB） | D15 | ❌ 缺 |
| `metafield.value_max_bytes_id_url` | 2048（2KB） | D15 | ❌ 缺 |
| `metafield.list_max_items` | 128（metaobject 參照為 256） | D15 | ❌ 缺 |
| `metafield.single_line_text_max_choices` | 128 | D15 | ❌ 缺 |
| `metafield.max_definitions_usable_in_smart_collection` | 128 | D15 | ❌ 缺 |
| `metafield.max_definitions_usable_in_admin_filter_product` | 50 | D15 | ❌ 缺 |
| `metafield.max_definitions_usable_in_admin_filter_order` | 5 | D15 | ❌ 缺 |
| `gift_card.max_value_product_usd` | 10000（官方註明不可調高） | P58、P59 | ❌ 缺 |
| `gift_card.max_value_admin_created_usd` | 2000 | P58、P60 | ❌ 缺 |
| `gift_card.default_expiry_years_when_enabled` | 5 | P61 | ❌ 缺 |
| `gift_card.expires_by_default` | false | P61 | ❌ 缺 |
| `gift_card.code_visible_suffix_chars` | 4 | P58、P60 | ❌ 缺 |

---

## 10. 與我方既有規格的衝突清單

> 排序依「改起來的痛苦程度 × 錯了的傷害」。

| # | 衝突 | 我方現況 | 官方 | 嚴重度 |
|---|---|---|---|---|
| **C-1** | **草稿訂單／轉移保留的目標狀態** | `limits.yml: draft_reservation_target_state: unavailable`；13 號 §F5.1(d) 寫死「不是 committed」 | dev changelog 2026-08-05：正遷移到 `committed`；help 尚未更新 | 🔴 **P0**，但**先不改**，見 V-53 |
| **C-2** | **商品狀態數量** | 13 號第 13 行「status 三態」 | 四態，多一個 `UNLISTED`（2025-10 引入） | 🔴 **P0**，牽動 `Product.published` scope |
| **C-3** | **可購買 ≠ 可被發現** | 我方一個 scope 兼管兩件事 | `UNLISTED` 明確拆開這兩件事 | 🔴 **P0**，是 C-2 的必然結果 |
| **C-4** | **商品系列的來源模型** | 13 號 §F4 manual/smart 二分 | sources 模型（products / variants / collections / apps），且 manual/smart 被官方標為 legacy；另有 exclude | 🔴 **P0**，資料模型層級 |
| **C-5** | **變體級發布** | 我方只有商品級發布 | 逐變體 × 逐管道／目錄發布；父商品與變體**都要**發布才顯示 | 🔴 **P0** |
| **C-6** | **標籤條件是集合運算不是子字串** | 13 號未指定；若用 LIKE 會錯 | `Product tag` 用 `includes` / `does not include` | 🔴 **P0**，會產生錯誤的商品系列成員 |
| **C-7** | **標籤特殊字元等價** | 我方 `product_tags` 直接存原字串 | `_`、`+`、`&` 等與 `-` 等價 | 🟠 P1，需正規化層 |
| **C-8** | **「最暢銷」的定義** | 13 號「90 天銷量 rollup」 | 官方為**全期**訂單數 | 🟠 P1，數字同源（鐵律 7）會露餡 |
| **C-9** | **大量編輯器不留稽核軌跡** | 13 號 §F5「每一筆都寫 ledger」 | 官方明載大量編輯**不產生**異動軌跡 | 🟠 P1，**建議不照抄**，但要在 PR 標為刻意偏離 |
| **C-10** | **採購單的收貨在轉移上** | 我方無此模組；60 號的鏈式理解會導向錯誤建模 | 採購單＝帳、轉移＝貨，兩份獨立紀錄；收貨只在轉移上 | 🟠 P1（新模組，趁還沒做先定對） |
| **C-11** | **利潤／利潤率的顯示條件** | 59 號 A-2 只記「缺這兩欄」 | 顯示條件是「有填成本 **且** 未勾選收取稅金」 | 🟡 P2 |
| **C-12** | **庫存五態譯名** | 13 號用「可販售／已分配／不可販售／待入庫」（**與官方文檔一致**） | 同左 | ✅ **無衝突**——但 60 號 §4 建議改用實站庫存頁譯名（可用／已佔用／不可用／在途），**照做會回退**，本檔建議否決該建議 |
| **C-13** | **CSV 列數上限** | 13 號 §F6「上限 5 萬行」 | 官方只有 15 MB，未載明列數 | 🟡 P2，我方值需標為自訂 |
| **C-14** | **無庫存時繼續銷售 × POS** | 我方無通路分支 | 該設定**不適用於 POS 訂單** | 🟡 P2（我方尚無 POS） |
| **C-15** | **置物格（Bin）** | 我方完全沒有 | 庫存 CSV 的欄位之一、庫存頁的顯示欄之一 | 🟡 P2，但**做 Shopify 匯入器時是必須的** |

---

## 11. 待查證登記簿（V-50 起）

> 承 `docs/specs/58` 的 V-37 ~ V-49。**未結案前一律不得用常識填值。**

| # | 待查證項目 | 為什麼查不到 | 結案前怎麼辦 | 影響 |
|---|---|---|---|---|
| **V-50** | **每個選項的選項值數上限**具體數字 | 錯誤碼 `OPTION_VALUES_OVER_LIMIT` 存在（D7），但 help 與 dev 皆未公布數字；`ShopResourceLimits` 也沒有對應欄位（D5 只有 `maxProductOptions` / `maxProductVariants`） | `limits.yml` 該鍵留 `null`，UI 不做前端上限提示，靠後端錯誤碼回報 | §2.1 |
| **V-51** | **變體本身可否直接拖曳重排**，以及 `position` 在重排後如何重編號 | help 只載明「選項」與「選項值」可拖曳（P15），未提變體列；`ProductVariant.position` 存在但語義只說「順序」（D2） | 假設變體順序由選項值順序的笛卡兒積決定（**不是**獨立可排），但**寫進規格時標為假設** | §2.2 |
| **V-52** | **庫存五態的 zh-TW 譯名要採哪一套**（help 文檔／實站庫存頁／實站商品頁三套並存） | 這不是查證問題，是**使用者裁定問題** | 沿用 13 號現況（＝help 文檔那套），**不照 60 號 §4 的建議改** | §3.2 |
| **V-53** | **草稿訂單／轉移保留庫存的最終目標狀態**：遷移是否已對所有商店完成？admin UI 的「不可用」欄是否仍含草稿保留？我方的 `unavailable[draft_reserved]` 子桶要不要併進 committed？ | dev changelog 為 2026-08-05 發布（本檔撰寫日前 7 天），help 文檔尚未更新；官方未給遷移完成時程 | `draft_reservation_target_state` **維持 `unavailable`** 但在 `limits.yml` 加註「官方正在遷移，見 61 號 §3.3」；**不要現在改值**（改了若遷移未完成會兩頭不對） | §3.3、C-1 |
| **V-54** | **官方未載明的庫存轉換**：部分履行時 committed 的扣減粒度、退貨入庫的預設落點（available 還是 quality_control）、超賣時（available 為負）各態的算術 | D11 只給了四條主幹轉換，細節未展開 | 依恆等式自行推導並**在規格標為我方推導**；併發測試（鐵律「超賣必須有測試」）以我方定義為準 | §3.5 |
| **V-55** | **help 的 7 個調整原因 與 dev 的 17 個 reason 的對應表** | 兩份清單分別給商家與 app 看，官方未提供映射 | ledger 的 `reason` 值域用 dev 那 17 個（是超集），UI 下拉只露 help 那 7 個 | §3.6 |
| **V-56** | **每店地點數上限** | `ShopResourceLimits.locationLimit` 欄位存在（D5）但數值依方案，官方未公布 | `limits.yml` 留 `null`，改為 per-shop 查詢；不硬編 | §3.9 |
| **V-57** | **商品系列「排除」與「納入條件」的優先順序與求值次序** | P25 只說 Products 來源可排除特定商品，未說與條件的交互 | 假設 `排除` 為最後一道過濾（exclude 勝過所有 include），**標為假設**；rebuild 測試覆蓋這個假設 | §4.1 |
| **V-58** | **商品系列的 `Price` / `Weight` / `Inventory stock` 條件比對的是變體最低值還是任一變體** | P24 只列運算子，未定義多變體時的比對基準 | 沿用 13 號的「任一變體」約定，但**改標為我方假設**（原文寫「定死」，其實無官方依據） | §4.2 |
| **V-59** | **單一商品系列可手動加入的商品數上限** | P23 只給了四個 per-shop 上限，未給 per-collection 的品項數 | 不設上限，靠分頁（每頁 60）與效能測試把關 | §4.3 |
| **V-60** | **轉移收貨時「拒收」數量的後續處置**（退回供應商？索賠？留在哪個帳上？） | P49 只說「記錄在轉移上但不改變任何地點的庫存數量」 | 拒收數量只寫 ledger 的 `movement_*` 記錄，**不落任何 inventory_level** | §5.3 |
| **V-61** | **部分收貨後轉移停留在哪個狀態**（是否有 `Partially received`？） | P49 列的五態沒有它；P46 確認可分批收 | 假設停在 `In progress` 直到全收，**標為假設** | §5.3 |
| **V-62** | **供應商的欄位必填性、字元上限、每店供應商數上限** | P47 全部未載明 | 不設上限；必填性依 UI 觀察（60 號未拆到）另行實測 | §5.4 |
| **V-63** | **採購單標籤的字元上限**：P9 把 `transfers` 歸 255 那組，但採購單不在清單裡，實站計數器顯示 `0/40` | 官方標籤格式頁未涵蓋採購單 | 取**較嚴的 40**（失效方向正確：寫不進去比截斷好） | §5.4 |
| **V-64** | **CSV 匯入部分失敗的官方行為**（已成功的列是否保留？是否可回滾？） | P52 只說「開始後無法取消」 | 我方採「每行獨立 transaction ＋ 逐行結果報告」（13 號 §F6.1 已如此），**與官方是否一致未知** | §6.1 |
| **V-65** | **大量編輯器一次可編輯的最大筆數** | 「50 個商品」只在 P36（多地點頁）出現一次，編輯器主頁 P69 未載明，只說「改越多越慢」 | `limits.yml` 留 `null`，不做前端硬限制 | §6.3 |
| **V-66** | **禮品卡代碼格式／長度／可否自訂；禮品卡可否退款與停用；是否課稅、是否需要運送** | P58/P60/P61 三頁均只導向「諮詢當地專家」 | 代碼生成用我方自有方案；課稅與退款規則交由 jurisdiction pack，核心只發稅務事件（鐵律 11） | §7.2 |
| **V-67** | **商品組合的元件數上限、每元件數量上限** | P64 只給了「不能巢狀」與庫存公式，無數字 | 不設上限；庫存公式照官方（取 `floor(min(元件可販售量 ÷ 所需量))`） | §8 |
| **V-68** | **商品標題與說明的字元上限**：`limits.yml` 現有 `title_max_chars: 255` 與 `description_max_bytes: 65536`，**官方文檔查無出處** | help 與 dev 的商品欄位頁均未載明；REST Product 資源也沒寫（D16） | 兩值**改標為「我方自訂，非官方值」**，不要繼續掛「出處：46c/22」 | §9.1 |
| **V-69** | **每店商品數上限** | 官方文檔未載明 | 不設上限 | §9.1 |
| **V-70** | **圖片像素上限 20MP 還是 25MP**：同一頁（P54）兩個數字並存 | 官方自相矛盾 | 取**較嚴的 20MP**（失效方向正確） | §9.2 |

---

## 12. 給下一個人的三句話

1. **最急的不是補上限值，是 §10 的 C-1 到 C-6 六條結構性衝突**——上限值漏了只是少擋一次，`UNLISTED` 少一個 enum 值、商品系列少一個 sources 表、變體少一層發布，是之後要動 migration 的。
2. **V-53（草稿保留庫存的目標狀態）是本輪唯一一條「官方自己正在改」的**。changelog 只比本檔早七天。**不要因為 dev 比 help 新就直接改值**——先確認遷移範圍，這是 §3.3 特別寫長的原因。
3. **60 號 §4 建議把庫存譯名改成實站庫存頁那套，本檔建議否決**（§3.2、V-52）。13 號現在用的就是官方文檔那套，改了是回退。這是本檔唯一一處與 60 號結論相左的地方，其餘（無變體＝隱含變體、五態恆等式、採購單自帶幣別、禮品卡兩條路徑）全部驗證通過。
