# 46b — 折扣／Shopify Functions／Checkout UI Extensions／Markets／B2B 權威功能邏輯字典

> **來源**：全部由 WebFetch 實際抓取 shopify.dev / help.shopify.com（查證日 **2026-08-11**）。**每條標出處 URL**。
> **原則**：文檔沒寫的一律標「**文檔未載明**」，不推測、不補腦。小模型摘要疑似推測而未二次驗證者，標「**未驗證**」。
> **當時最新 API 版本**：Admin GraphQL / Functions / Checkout UI Extensions 皆為 `2026-07`（來源：<https://shopify.dev/docs/api/functions>、<https://shopify.dev/docs/api/checkout-ui-extensions>）。
> **銜接**：Markets 面與 `29-markets-i18n.md` 互補（本文以 API 型別與繼承語意為主）；API 契約併入 `28-api-contract.md`；上限值須落到 `config/limits.yml`（CLAUDE.md 鐵律 6）。

---

## 目錄

1. [Shopify Functions（平台層）](#1-shopify-functions平台層)
2. [折扣 Discounts](#2-折扣-discounts)
3. [結帳規則 Cart & Checkout Validation](#3-結帳規則-cart--checkout-validation)
4. [Checkout UI Extensions](#4-checkout-ui-extensions)
5. [Markets 國際化](#5-markets-國際化)
6. [B2B](#6-b2b)
7. [全域限制值總表](#7-全域限制值總表)
8. [文檔未載明清單（待實測補齊）](#8-文檔未載明清單待實測補齊)

---

## 1. Shopify Functions（平台層）

### ① 模型

Function = 用任何可編譯成 WebAssembly 的語言寫的後端擴充；「You can write functions in any language that can compile to WebAssembly (Wasm), although Rust is recommended and strongly preferred.」（<https://shopify.dev/docs/api/functions>）

兩種 target 型態（同上）：

| target 型態 | 定義（原文） |
|---|---|
| **run target** | 「An extension point that enables you to customize Shopify's backend with custom business logic.」 |
| **fetch target** | 「A mechanism for retrieving the data from a third party provider and passing the data to the run target.」限 Enterprise 自訂 app（需 network access 核可） |

TOML 設定形態：`target = "<target_name>.run"` 搭配 `input_query` 與 `export`（<https://shopify.dev/docs/api/functions>）。

**結帳時的執行順序（官方 7 步，來源 <https://shopify.dev/docs/api/functions>）**：

```
1. Cart Transform            → 改 cart line（bundle 展開／合併／改價改標題）
2. Discount（cart lines）     → 商品／訂單折扣
3. Fulfillment Constraints + Order Routing Location Rule → 決定出貨群組與地點優先序
4. Delivery Customization    → 產生／改寫配送選項
5. Discount（delivery）       → 運費折扣
6. Payment Customization     → 付款方式
7. Cart and Checkout Validation → 最後驗證，可擋結帳
```

> **關鍵推論**：折扣被切成 **兩段**（第 2 步與第 5 步）跑，運費折扣是在配送選項產生之後才算的。CHILL LOVE 的結帳 pipeline 必須照這個順序排，否則「滿額免運」這種跨階段規則會算錯。

### ② 狀態／列舉：完整 Function API 與 target handle

| Function API | target handle | 出處 |
|---|---|---|
| Cart Transform | `cart.transform.run` | <https://shopify.dev/docs/api/functions/latest/cart-transform> |
| Discount（cart lines） | `cart.lines.discounts.generate.run` | <https://shopify.dev/docs/api/functions/latest/discount> |
| Discount（delivery） | `cart.delivery-options.discounts.generate.run` | 同上 |
| Delivery Customization | `cart.delivery-options.transform.run` | <https://shopify.dev/docs/api/functions/latest/delivery-customization> |
| Payment Customization | `cart.payment-methods.transform.run` | <https://shopify.dev/docs/api/functions/latest/payment-customization> |
| Cart and Checkout Validation | `cart.validations.generate.run` | <https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation> |
| Fulfillment Constraints | 頁面列於 API 清單，handle 文檔未於清單頁載明 | <https://shopify.dev/docs/api/functions> |
| Order Routing Location Rule | 同上 | 同上 |
| **Discounts Allocator**（developer preview） | `purchase.discounts-allocator.run` | <https://shopify.dev/docs/api/functions/unstable/discounts-allocator> |
| Pickup Point / Local Pickup Delivery Option Generator | unstable，handle 文檔未於清單頁載明 | <https://shopify.dev/docs/api/functions> |

### ③ 約束與限制值（**全部為官方明列數字**，來源 <https://shopify.dev/docs/api/functions>）

**固定限制（所有 function 共通）**

| 資源 | 限制 |
|---|---|
| Compiled binary size | **256 kB** |
| Runtime linear memory | **10,000 kB** |
| Runtime stack memory | **512 kB** |
| Logs written | **1 kB（truncated）** |

**動態限制（up to 200 line items）**

| 資源 | 限制 |
|---|---|
| Execution instruction count | **11 million instructions** |
| Function input | **128 kB** |
| Function output | **20 kB** |

**Input query 限制**

| 項目 | 限制 |
|---|---|
| Maximum query size | **3000 bytes** |
| Metafield value limit | **10,000 bytes** |
| List field arguments | 不得超過 **100 elements** |
| Maximum query cost | **30** |

**每店啟用數上限**

| Function 類型 | 上限 | 出處 |
|---|---|---|
| Discount | **25 discount functions on each store** | <https://shopify.dev/docs/api/functions/latest/discount> |
| Cart & Checkout Validation | **25 validation functions on each store** | <https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation> |
| Delivery Customization | **25 delivery customization functions on each store** | <https://shopify.dev/docs/api/functions/latest/delivery-customization> |
| Payment Customization | **25 payment customization functions on each store** | <https://shopify.dev/docs/api/functions/latest/payment-customization> |
| Cart Transform | **每 app 每店最多 1 個**（多 app 可並存） | <https://shopify.dev/docs/api/functions/latest/cart-transform> |
| Discounts Allocator | **每店最多 1 個** | <https://shopify.dev/docs/api/functions/unstable/discounts-allocator> |

**方案限制**：public app（App Store 上架）→ All plans；**custom app 內含 Function API → 僅 Shopify Plus**（「Only stores on a Shopify Plus plan can use custom apps that contain Shopify Function APIs.」<https://shopify.dev/docs/apps/build/functions>）。

**Cart Transform 附加限制**（<https://shopify.dev/docs/api/functions/latest/cart-transform>）：
- 操作三種：`lineExpand`、`linesMerge`、`lineUpdate`
- `lineUpdate` 限 development stores 或 Shopify Plus
- 「Shopify rejects `lineExpand`, `linesMerge`, and `lineUpdate` operations if a selling plan is present」
- POS 需 `ProductVariant.requiresComponents = true`

### ④ API 操作表

| 動作 | 介面 |
|---|---|
| 註冊 function-backed 折扣 | `discountAutomaticAppCreate` / `discountCodeAppCreate`（<https://shopify.dev/docs/apps/build/discounts>） |
| 更新／刪除 | `discountAutomaticAppUpdate` / `discountAutomaticDelete`；`discountCodeAppUpdate` / `discountCodeDelete`（同上） |
| 註冊 Discounts Allocator | `discountsAllocatorFunctionRegister`（<https://shopify.dev/docs/api/admin-graphql/unstable/mutations/discountsAllocatorFunctionRegister>） |
| 設定傳遞 | metafields（慣例 namespace `function-configuration`），亦可用 input query 讀 metafield（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticAppCreate>） |

### ⑤ 錯誤碼

- Function 執行失敗時的 fallback 行為：**文檔未載明**（`https://shopify.dev/docs/apps/build/functions` 未描述）。
- 折扣相關 function 註冊錯誤走 `DiscountErrorCode`，見 §2⑤（其中 `MISSING_FUNCTION_IDENTIFIER`、`MULTIPLE_FUNCTION_IDENTIFIERS`、`MAX_APP_DISCOUNTS` 專屬 function 折扣）。

### ⑥ 對 CHILL LOVE 的實作結論

1. **不做 Wasm**。CHILL LOVE 用 Rails，直接把七步做成**伺服器端 pipeline 的 7 個 hook 點**，順序照 §1① 那張表，介面用 Ruby class（`ChillLove::Functions::DiscountGenerate` 等）。這樣未來要換成沙箱執行也只需替換 adapter。
2. **限制值照抄**是有價值的：把 `128 kB input / 20 kB output / 11M instructions` 換算成 CHILL LOVE 的等價護欄——**cart line 上限 200**、單次 pipeline 執行 **時間上限**（建議 50 ms，需壓測定案）、輸出 payload 上限 20 kB。全部進 `config/limits.yml`。
3. **每類 25 個**這個數字要在 admin 建立第 26 個時擋下並回 `userErrors.code = EXCEEDED_MAX`。
4. **cart transform 每 app 1 個**：CHILL LOVE 若做 app 生態，這條要進 app 安裝驗證。
5. **執行順序必須有測試**：`運費折扣在配送選項生成後` 這條寫成 pipeline 的 golden test。

---

## 2. 折扣 Discounts

### ① 模型

**兩條建立路徑**（<https://shopify.dev/docs/apps/build/discounts>）：
- **GraphQL Admin API 原生折扣**：Basic / Bxgy / FreeShipping，自動或需輸入代碼兩種 method
- **Shopify Functions 折扣**：「custom discount functionality that isn't offered out of the box with Shopify」，例如同時商品＋運費折扣、階梯量價

**Access scope**：`write_discounts`「Required」（同上）。

**四型 × 兩 method 的 mutation 矩陣**：

| 型別 | 自動（Automatic） | 代碼（Code） |
|---|---|---|
| 金額／百分比 off（商品 or 訂單） | `discountAutomaticBasicCreate` | `discountCodeBasicCreate` |
| Buy X Get Y | `discountAutomaticBxgyCreate` | `discountCodeBxgyCreate` |
| 免運 | `discountAutomaticFreeShippingCreate` | `discountCodeFreeShippingCreate` |
| Function 折扣 | `discountAutomaticAppCreate` | `discountCodeAppCreate` |

> **注意「四型」的真實形狀**：Shopify 沒有獨立的「訂單折扣 mutation」。**商品折扣與訂單折扣共用 `Basic`**，靠 `customerGets.items`（`all: true` = 全單）與 `discountClasses` 區分。這點與我們實測畫面上「四張卡」的心智模型不同，復刻時 UI 分四型、後端存一張表＋class 欄位即可。

**輸入型別（`DiscountAutomaticBasicInput`，<https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBasicCreate>）**：

```graphql
DiscountAutomaticBasicInput {
  title: String!                      # required
  startsAt: DateTime!                 # required
  endsAt: DateTime
  minimumRequirement: DiscountMinimumRequirementInput {
    subtotal: DiscountMinimumSubtotalInput { greaterThanOrEqualToSubtotal: String }
    # quantity: DiscountMinimumQuantityInput（免運頁有列，見下）
  }
  customerGets: DiscountCustomerGetsBasicInput! {
    value: DiscountCustomerGetsValueInput! {
      discountAmount: DiscountAmountInput { amount: String, appliesOnEachItem: Boolean }
      percentage: Float                # 0–1 區間
    }
    items: DiscountItemsInput! { all: Boolean, ... }
  }
  combinesWith: DiscountCombinesWithInput {
    productDiscounts: Boolean
    shippingDiscounts: Boolean
    orderDiscounts: Boolean
  }
  context: DiscountContextInput {
    customerSegments: { add: [ID] }
    markets: { add: [ID] }
  }
}
```

> **`percentage` 是 0–1 的 Float**（不是 0–100）。這是最容易寫錯的一條。

**`DiscountAutomaticBxgyInput`**（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBxgyCreate>）：
`title`(必), `startsAt`(必), `endsAt`, `customerBuys: DiscountCustomerBuysInput!{ items, value(quantity 整數 或 amount 金額) }`, `customerGets: DiscountCustomerGetsInput!{ items, value: DiscountOnQuantityInput(quantity + effect: percentage 0–1 或固定金額) }`, `usesPerOrderLimit: Int`, `combinesWith`, `context`。

**`DiscountAutomaticFreeShippingInput`**（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticFreeShippingCreate>）：
`title`(必), `startsAt`, `endsAt`, `destination: DiscountShippingDestinationSelectionInput{ all: Boolean, countries: DiscountCountriesInput{ add: [...] } }`, `minimumRequirement{ subtotal | quantity }`, `maximumShippingPrice: Money`, `appliesOnOneTimePurchase`, `appliesOnSubscription`, `recurringCycleLimit`, `combinesWith{ orderDiscounts, productDiscounts }`, `context`。

> **免運的 `combinesWith` 只有 order/product 兩個旗標**（沒有 shippingDiscounts）——這與 help center「Multiple shipping discounts can't apply to the same order」一致。

**`DiscountCodeBasicInput`**（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountCodeBasicCreate>）比 automatic 多：`code`(必)、`usageLimit: Int`、`appliesOncePerCustomer: Boolean`、`customerSelection`（已 deprecated，見下）。

**讀取物件 `DiscountCodeBasic`**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountCodeBasic>）：

| 欄位 | 型別 | 說明（原文摘） |
|---|---|---|
| `title` | `String!` | 商家後台與顧客可見名稱 |
| `status` | `DiscountStatus!` | availability / expiration / pending activation |
| `startsAt` | `DateTime!` | |
| `endsAt` | `DateTime` | 「For discounts without a fixed expiration date, specify `null`」 |
| `usageLimit` | `Int` | 「For unlimited usage, specify `null`」 |
| `appliesOncePerCustomer` | `Boolean!` | |
| `asyncUsageCount` | `Int!` | 「updated asynchronously and might be lower than the actual count until the process completes」 |
| `recurringCycleLimit` | `Int` | 「If `0`, the discount applies indefinitely」 |
| `codes` | `DiscountRedeemCodeConnection!` | 支援 after/before/first/last/query/sortKey/reverse/savedSearchId |
| `codesCount` | `Count` | |
| `customerGets` | `DiscountCustomerGets!` | |
| `minimumRequirement` | `DiscountMinimumRequirement` | |
| `combinesWith` | `DiscountCombinesWith!` | |
| `discountClasses` | `[DiscountClass!]!` | |
| `context` | `DiscountContext!` | 「The context defining which buyers can use the discount.」 |
| `summary` / `shortSummary` | `String!` | 系統產生的人話描述 |
| `shareableUrls` | `[DiscountShareableUrl!]!` | |
| `totalSales` | `MoneyV2` | |
| `tags` | `[String!]!` | |
| `hasTimelineComment` | `Boolean!` | |
| ~~`customerSelection`~~ | `DiscountCustomerSelection!` | **Deprecated** |
| ~~`discountClass`~~ | `MerchandiseDiscountClass!` | **Deprecated**（單數版） |

> **`asyncUsageCount` 是非同步的**——這一條對「用量上限」的併發正確性至關重要：Shopify 自己承認計數會落後。CHILL LOVE 若要**強一致**扣用量，必須自己做行鎖／原子遞增，不能照抄非同步模型（見 ⑥）。

### ② 狀態／列舉

**`DiscountClass`**（<https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountClass>）：
- `ORDER` — 「The discount is combined with an order discount class.」
- `PRODUCT` — 「…product discount class.」
- `SHIPPING` — 「…shipping discount class.」

**`DiscountCombinesWith`**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountCombinesWith>）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `orderDiscounts` | `Boolean!` | 「Whether the discount combines with the order discount class.」 |
| `productDiscounts` | `Boolean!` | 「Whether the discount combines with the product discount class.」 |
| `shippingDiscounts` | `Boolean!` | 「Whether the discount combines with the shipping discount class.」 |
| `productDiscountsWithTagsOnSameCartLine` | `[String!]` | **僅 Shopify Plus**，且 `productDiscounts` 必須為 true；需雙方 tag「mutual-match」才可同 cart line 疊加 |

**語意**：這是「**我允許和哪一類疊**」的白名單旗標。設 `orderDiscounts: true` 即代表本折扣**可以**與訂單類折扣同時生效。

**`context` / `DiscountContextInput`**（2025-10 起，<https://shopify.dev/changelog/discount-eligibility-management>）：
- 「starting with API version 2025-10, use `context` to specify whether code or automatic discounts are eligible for all customers, specific customers, or customer segments」
- **取代 `customerSelection`**：「`customerSelection` is now marked as deprecated and will be removed in a future version」
- **自動折扣首次支援客群限定**（以前只有 code 折扣有）
- 向後相容陷阱：「Automatic discounts with customer or customer segment eligibility applied will be **filtered out from queries prior to 2025-10**」

**`context.markets`**（2026-07 起，<https://shopify.dev/changelog/target-discounts-to-specific-markets>）：
- 用 `DiscountContextInput.markets` 把折扣限定到市場
- 適用「Basic, BXGY, App, and Free Shipping discounts (both automatic and code-based)」
- **市場與客群互斥**：「you can target either markets OR customer segments, but not both simultaneously」
- 每折扣可綁市場數上限：**文檔未載明**

### ③ 約束與限制值

| 項目 | 值 | 出處 |
|---|---|---|
| 同時 active 的自動折扣 | **25** | `DiscountErrorCode.ACTIVE_PERIOD_OVERLAP`：「At any given time, only 25 automatic discounts can be active.」<https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountErrorCode> |
| 每店累計唯一折扣碼 | **20,000,000** | 「There's a cumulative limit of 20,000,000 unique discount codes for each store.」<https://help.shopify.com/en/manual/discounts/discount-methods/discount-codes> |
| 單一折扣碼可指定的顧客／商品／變體 | **100** | 「A discount code can apply to up to 100 specific customers, products, and variants.」同上 |
| 顧客單次結帳可用代碼數 | **5 個商品/訂單折扣碼 ＋ 1 個運費碼** | <https://help.shopify.com/en/manual/discounts/discount-combinations> |
| `productDiscountsWithTagsOnSameCartLine` tag 數 | **最多 10** | `TOO_MANY_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE`：「exceeds maximum of 10」 |
| 一般 tags 數 | **最多 5** | `TOO_MANY_TAGS`：「The number of tags exceeds the maximum of 5.」 |
| tag 長度 | **255 字元** | `INVALID_TAG_LENGTH`：「exceeds the maximum length of 255 characters」 |
| Function 折扣數 | **25 / store** | <https://shopify.dev/docs/api/functions/latest/discount> |
| `percentage` 值域 | **0–1 Float** | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBasicCreate> |
| Function 折扣 candidate `message` 長度 | **文檔未載明**（初次抓取小模型稱 100 字元，二次驗證無法在頁面找到該敘述 → 標為**未驗證**，勿引用） | — |

**疊加規則矩陣**（<https://help.shopify.com/en/manual/discounts/discount-combinations>）：

| 組合 | 可否 | 備註 |
|---|---|---|
| Product + Order | ✅ | 「Product discounts apply before the subtotal is calculated, and then the order discounts apply to the subtotal.」 |
| Product + Product（**不同** cart line） | ✅ | 各自作用於不同品項 |
| Product + Product（**同一** cart line） | ⚠️ 僅 Plus | 需雙方 tag 互相匹配；「Percentage discounts are applied before fixed amount discounts.」 |
| Product + Shipping | ✅ | |
| Order + Order | ✅ | 多個百分比折扣「both percentages are calculated on the original subtotal」（10% + 20% = 30%，**非**複利 28%） |
| Order + Shipping | ✅ | |
| **Shipping + Shipping** | ❌ | 「Multiple shipping discounts can't apply to the same order.」 |

**套用順序**：`Product → Order（作用於折後 subtotal）→ Shipping`。

**額外資格條件**（同上）：要讓 product 與 order 折扣可組合，需**無 `checkout.liquid` 客製**、且**未安裝 Licensify app**。

### ④ API 操作表

| 動作 | Mutation / Query | 出處 |
|---|---|---|
| 建立自動 Basic 折扣 | `discountAutomaticBasicCreate(automaticBasicDiscount: DiscountAutomaticBasicInput!)` | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBasicCreate> |
| 建立自動 BXGY | `discountAutomaticBxgyCreate` | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBxgyCreate> |
| 建立自動免運 | `discountAutomaticFreeShippingCreate` | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticFreeShippingCreate> |
| 建立 Function 自動折扣 | `discountAutomaticAppCreate`（`functionId` 必填；設定走 `metafields`） | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticAppCreate> |
| 建立代碼折扣 | `discountCodeBasicCreate` / `discountCodeBxgyCreate` / `discountCodeFreeShippingCreate` / `discountCodeAppCreate` | <https://shopify.dev/docs/apps/build/discounts> |
| 更新／刪除 | `discountAutomaticAppUpdate`、`discountAutomaticDelete`、`discountCodeAppUpdate`、`discountCodeDelete` | 同上 |
| 回傳 payload | `automaticDiscountNode: DiscountAutomaticNode { id, automaticDiscount }` + `userErrors: [DiscountUserError!]!{ field, code, message }` | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBasicCreate> |

**Function 折扣輸出（`cart.lines.discounts.generate.run`）**（<https://shopify.dev/docs/api/functions/latest/discount>、<https://shopify.dev/docs/api/functions/2025-10/discount>）：

```
CartLinesDiscountsGenerateRunResult { operations: [Operation!]! }   # 有序執行

Operation（union）:
  - enterDiscountsPhase
  - productDiscountsAdd  { selectionStrategy, candidates: [ProductDiscountCandidate] }
  - orderDiscountsAdd    { selectionStrategy, candidates: [OrderDiscountCandidate] }
  - deliveryDiscountsAdd { selectionStrategy, candidates: [...] }        # 用於 delivery target
  - enteredDiscountCodesAccept / enteredDiscountCodesReject             # 代碼驗證

Candidate: { targets, value(Percentage | FixedAmount{appliesToEachItem}), message, conditions, associatedDiscountCode }
Target types: CartLineTarget | OrderSubtotalTarget | DeliveryGroupTarget
SelectionStrategy: FIRST | MAXIMUM（product/order）；ALL 僅 delivery
DiscountClass: PRODUCT | ORDER | SHIPPING（於 extension TOML 宣告）
```

**執行語意**：「All discount functions run **concurrently**, and have **no knowledge of each other**」；疊加最後由「the combination and stacking rules set on the discount node」決定（<https://shopify.dev/docs/api/functions/latest/discount>）。

### ⑤ 錯誤碼：`DiscountErrorCode` 全 39 值

出處：<https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountErrorCode>

| Code | 說明（原文） |
|---|---|
| `ACTIVE_PERIOD_OVERLAP` | 「The active period overlaps with other automatic discounts. At any given time, only 25 automatic discounts can be active.」 |
| `APPLIES_ON_NOTHING` | 「A discount cannot have both appliesOnOneTimePurchase and appliesOnSubscription set to false.」 |
| `BLANK` | 「The input value is blank.」 |
| `CONFLICT` | 「The attribute selection contains conflicting settings.」 |
| `DISCOUNT_NOT_COMPATIBLE_WITH_CONDITION_TYPES` | 「Discounts and condition types are not compatible with each other.」 |
| `DUPLICATE` | 「The input value is already present.」 |
| `END_DATE_BEFORE_START_DATE` | 「The end date should be after the start date.」 |
| `EQUAL_TO` | 「The input value should be equal to the value allowed.」 |
| `EXCEEDED_MAX` | 「The value exceeded the maximum allowed value.」 |
| `GREATER_THAN` | 「The input value should be greater than the minimum allowed value.」 |
| `GREATER_THAN_OR_EQUAL_TO` | 「…greater than or equal to the minimum value allowed.」 |
| `IMPLICIT_DUPLICATE` | 「The value is already present through another selection.」 |
| `INCLUSION` | 「The input value isn't included in the list.」 |
| `INTERNAL_ERROR` | 「Unexpected internal error happened.」 |
| `INVALID` | 「The input value is invalid.」 |
| `INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS` | 「The `combinesWith` settings are invalid for the discount class.」 |
| `INVALID_DISCOUNT_CLASS_FOR_PRICE_RULE` | 「The discountClass is invalid for the price rule.」 |
| `INVALID_PRODUCT_DISCOUNTS_FALSE_WITH_EXISTING_TAGS_ON_SAME_CART_LINE` | 「The `productDiscounts` field can't be set to false when `productDiscountsWithTagsOnSameCartLine` tags exist.」 |
| `INVALID_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_FOR_DISCOUNT_CLASS` | 「…only valid for PRODUCT discount class.」 |
| `INVALID_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_WITHOUT_PRODUCT_DISCOUNTS` | 「…can only be specified when `productDiscounts` is true.」 |
| `INVALID_TAG_LENGTH` | 「The tag title exceeds the maximum length of 255 characters.」 |
| `LESS_THAN` | 「The input value should be less than the maximum value allowed.」 |
| `LESS_THAN_OR_EQUAL_TO` | 「…less than or equal to the maximum value allowed.」 |
| `MAX_APP_DISCOUNTS` | 「The active period overlaps with too many other app-provided discounts. There's a limit on active app discounts.」 |
| `MINIMUM_SUBTOTAL_AND_QUANTITY_RANGE_BOTH_PRESENT` | 「Specify a minimum subtotal or a quantity, but not both.」 |
| `MISSING_ARGUMENT` | 「Missing a required argument.」 |
| `MISSING_FUNCTION_IDENTIFIER` | 「Either function ID or function handle must be provided.」 |
| `MULTIPLE_FUNCTION_IDENTIFIERS` | 「Only one of function ID or function handle is allowed.」 |
| `MULTIPLE_RECURRING_CYCLE_LIMIT_FOR_NON_SUBSCRIPTION_ITEMS` | 「Recurring cycle limit must be 1 when discount does not apply to subscription items.」 |
| `PRESENT` | 「The input value needs to be blank.」 |
| `PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_NOT_ENTITLED` | 「The shop's plan does not allow setting `productDiscountsWithTagsOnSameCartLine`.」 |
| `RECURRING_CYCLE_LIMIT_NOT_A_VALID_INTEGER` | 「…must be a valid integer greater than or equal to 0.」 |
| `TAKEN` | 「The input value is already taken.」 |
| `TOO_LONG` | 「The input value is too long.」 |
| `TOO_MANY_ARGUMENTS` | 「Too many arguments provided.」 |
| `TOO_MANY_PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE` | 「…exceeds maximum of 10.」 |
| `TOO_MANY_TAGS` | 「The number of tags exceeds the maximum of 5.」 |
| `TOO_SHORT` | 「The input value is too short.」 |
| `VALUE_OUTSIDE_RANGE` | 「The value is outside of the allowed range.」 |

### ⑥ 對 CHILL LOVE 的實作結論

1. **資料模型**：一張 `discounts` 表（`shop_id`, `method: AUTOMATIC|CODE`, `type: BASIC|BXGY|FREE_SHIPPING|APP`, `discount_classes: SET(PRODUCT,ORDER,SHIPPING)`），子表 `discount_codes`（unique `[shop_id, code]`）、`discount_combines_with`、`discount_contexts`。**不要**照 Shopify 分四張表。
2. **`percentage` 存 basis points（integer）**，不存 float（CLAUDE.md 鐵律 3）。API 序列化時再除以 10000 輸出 0–1 Float 以對齊 Shopify 語意。
3. **用量計數要強一致**：Shopify 的 `asyncUsageCount` 是弱一致的、會低估。CHILL LOVE 走 `UPDATE discounts SET used_count = used_count + 1 WHERE id = ? AND (usage_limit IS NULL OR used_count < usage_limit)` 的原子條件更新＋affected_rows 判斷，並在 `docs/specs` 補「折扣用量併發測試」（CLAUDE.md 驗收基準已列此項）。同時仍**保留 `asyncUsageCount` 這個欄位名**供 API 相容。
4. **疊加引擎照 §2③ 矩陣實作**，重點三條：(a) 套用順序 Product→Order→Shipping；(b) 多個 order 百分比折扣以**原始 subtotal** 為基數相加，不是複利；(c) **運費折扣不可疊運費折扣**（硬規則，非旗標可控）。
5. **`customerSelection` 直接不做**，一開始就上 `context{ customerSegments | markets }`，且實作互斥檢查（markets XOR customerSegments）。
6. **`combinesWith` 驗證**要回 `INVALID_COMBINES_WITH_FOR_DISCOUNT_CLASS`；Plus-only 的 `productDiscountsWithTagsOnSameCartLine` 在我們這邊對應「進階方案」旗標，違反回 `PRODUCT_DISCOUNTS_WITH_TAGS_ON_SAME_CART_LINE_NOT_ENTITLED`。
7. **`DiscountErrorCode` 39 值全部照抄**進 `userErrors.code` 列舉——這是最省事的相容性資產，直接進 `28-api-contract.md`。
8. **`summary` / `shortSummary` 是系統產生的**（不是使用者輸入）：需要一個「折扣描述產生器」把結構化條件轉成中文人話，出現在 admin 列表與顧客端。這是容易漏做的一塊。

---

## 3. 結帳規則 Cart & Checkout Validation

### ① 模型

**Target**：`cart.validations.generate.run`（<https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation>）

**用途**：「run on Shopify's servers and can block checkout progress when business rules aren't met」，例：訂單上限、限制配送地、忠誠度規則（<https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation>）。

**求值時機**：由 input 的 `buyerJourney.step` 表達，可跑於購物車互動、結帳互動與結帳完成三個階段：「available for online store carts, carts built for custom storefronts, and throughout the checkout process」（同上）。

**支援面（surfaces）**：B2B、Cart、Checkout、Draft Orders（Admin/Checkout）、Shopify Admin、Storefront、Accelerated Checkout（<https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation>）。

> **重點**：validation 在 **Accelerated Checkout（Shop Pay / Apple Pay 等）也生效**，這代表它不是前端檢查，是伺服器端 gate。CHILL LOVE 的快速結帳路徑必須共用同一個驗證管線。

**輸入**（同上）：root type `Input`，只回傳查詢過的欄位；可用 `buyerJourney`、`cart`（buyer identity / costs / lines / delivery groups / attributes / billing address / customer / product variants / metafields）。

**輸出**：

```
CartValidationsGenerateRunResult {
  operations: [ { validationAdd: { errors: [ { message: String, target: String } ] } } ]
}
```

錯誤物件兩個必填欄位（同上）：
- `message`（String）—「A description of the validation error」
- `target`（String）— JSONPath，指定要標在哪個結帳欄位

**錯誤如何呈現給買家**（<https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation>、<https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation/create-checkout-validation>）：
- 「Errors from validation functions are exposed to the Storefront API's `Cart` object, in themes using the `cart` template and during checkout.」
- Storefront `Cart.userErrors` 帶 **`code: "VALIDATION_CUSTOM"`** ＋ 自訂 message
- 結帳頁以警告訊息呈現；`target` 讓錯誤附著到特定欄位，阻止流程前進

### ② 狀態／列舉

**`buyerJourney.step`**（<https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation>）：
- `CART_INTERACTION`
- `CHECKOUT_INTERACTION`
- `CHECKOUT_COMPLETION`

**支援的 checkout field targets（完整表，同上）**：

| 欄位 | JSONPath target |
|---|---|
| cart（全域） | `$.cart` |
| email | `$.cart.buyerIdentity.email` |
| phone | `$.cart.buyerIdentity.phone` |
| deliveryAddress.address1 | `$.cart.deliveryGroups[0].deliveryAddress.address1` |
| deliveryAddress.address2 | `$.cart.deliveryGroups[0].deliveryAddress.address2` |
| deliveryAddress.city | `$.cart.deliveryGroups[0].deliveryAddress.city` |
| deliveryAddress.company | `$.cart.deliveryGroups[0].deliveryAddress.company` |
| deliveryAddress.countryCode | `$.cart.deliveryGroups[0].deliveryAddress.countryCode` |
| deliveryAddress.firstName | `$.cart.deliveryGroups[0].deliveryAddress.firstName` |
| deliveryAddress.lastName | `$.cart.deliveryGroups[0].deliveryAddress.lastName` |
| deliveryAddress.phone | `$.cart.deliveryGroups[0].deliveryAddress.phone` |
| deliveryAddress.provinceCode | `$.cart.deliveryGroups[0].deliveryAddress.provinceCode` |
| deliveryAddress.zip | `$.cart.deliveryGroups[0].deliveryAddress.zip` |
| billingAddress.address1 | `$.cart.billingAddress.address1` |
| billingAddress.address2 | `$.cart.billingAddress.address2` |
| billingAddress.city | `$.cart.billingAddress.city` |
| billingAddress.company | `$.cart.billingAddress.company` |
| billingAddress.countryCode | `$.cart.billingAddress.countryCode` |
| billingAddress.firstName | `$.cart.billingAddress.firstName` |
| billingAddress.lastName | `$.cart.billingAddress.lastName` |
| billingAddress.phone | `$.cart.billingAddress.phone` |
| billingAddress.provinceCode | `$.cart.billingAddress.provinceCode` |
| billingAddress.zip | `$.cart.billingAddress.zip` |
| poNumber | `$.cart.poNumber` |
| localizedFields | `$.cart.localizedfield.key` |

> `billingAddress.*` 與 `poNumber` 是 **2026-04 才加入**的（<https://shopify.dev/changelog/cart-and-checkout-validation-adds-billing-address-and-po-number-error-targets>）：「all standard address subfields」＋`$.cart.poNumber`。`poNumber` 的存在直接說明這條路徑是為 **B2B** 打通的。

### ③ 約束與限制值

| 項目 | 值 | 出處 |
|---|---|---|
| 每店可啟用 validation function | **25** —「You can activate a maximum of 25 validation functions on each store.」 | <https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation> |
| 單次回傳 errors 數上限 | **文檔未載明** | — |
| `message` 字元上限 | **文檔未載明** | — |
| Plus 限制 | 該 API 本身無 Plus-only 註記；但**自訂 app 內含 Function 需 Plus** | <https://shopify.dev/docs/apps/build/functions> |
| 舊版 API | 「The Cart Checkout Validation Function API isn't supported in the latest API version.」（舊 `cart-checkout-validation` 路徑已廢，改用 `cart-and-checkout-validation`） | <https://shopify.dev/docs/api/functions/latest/cart-checkout-validation> |
| 最低 api_version | tutorial 用 `api_version = "2025-07"` 或更高 | <https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation/create-checkout-validation> |

### ④ API 操作表

| 動作 | 介面 |
|---|---|
| 宣告 | `shopify.extension.toml`：`type = "function"`、`target = "cart.validations.generate.run"`、`api_version` |
| 輸入 | `query Input { cart { ... } buyerJourney { step } }`（JS 版 query 名為 `CartValidationsGenerateRunInput`） |
| 輸出 | `{ operations: [{ validationAdd: { errors: [{ message, target }] } }] }` |
| 讀取結果（前台） | Storefront API `Cart.userErrors`（`code: VALIDATION_CUSTOM`） |
| 商家設定 UI | Admin UI extension（`https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation/create-complex-validation-rules/build-complex-validation-function`） |

### ⑤ 錯誤碼

- 買家端唯一錯誤碼：**`VALIDATION_CUSTOM`**（Storefront `Cart.userErrors.code`），來源 <https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation/create-checkout-validation>
- 註冊／啟用階段的 userErrors 型別：**文檔未載明**（未見專屬 ErrorCode enum）

### ⑥ 對 CHILL LOVE 的實作結論

1. **「結帳規則」不是一個獨立功能，是 validation function 的商家 UI 外殼**。實測畫面上的「結帳規則」列表 = 已啟用的 validation function 清單（上限 25）。我們要做的是：規則 CRUD ＋ 一個內建規則引擎（DSL/JSON 條件），而不是讓商家寫程式。
2. **`target` JSONPath 白名單照抄 25 條**進 `config/limits.yml` 或常數表；不在白名單的 target 一律拒絕（回 `INVALID`）。這是把錯誤精準標到欄位的唯一辦法。
3. **三段求值 `CART_INTERACTION` / `CHECKOUT_INTERACTION` / `CHECKOUT_COMPLETION` 必須全部實作**。只在提交時驗證會導致買家填完整個表單才被擋，體驗差且與 Shopify 不一致。
4. **快速結帳（Shop Pay 等價物）必須走同一管線**——這是最容易漏的安全洞。
5. **`$.cart.poNumber` 要預留**：B2B 的 PO number 欄位在 cart 層，不是 order 層。資料模型要現在就開好。
6. **錯誤碼固定 `VALIDATION_CUSTOM`**，message 由規則自帶（需支援多語，走 §5 的 translations 表）。

---

## 4. Checkout UI Extensions

### ① 模型

「Extensions add custom UI and logic into any step of the Shopify checkout experience.」（<https://shopify.dev/docs/api/checkout-ui-extensions>）

**三種 target 型態**（<https://shopify.dev/docs/api/checkout-ui-extensions>、<https://shopify.dev/docs/api/checkout-ui-extensions/latest/extension-targets-overview>）：

| 型態 | 定義（原文） |
|---|---|
| **Static targets** | 「render immediately before or after most core checkout features」；只有在對應的核心功能有渲染時才出現 |
| **Block targets** | 「render between core checkout features」，且「**always rendered, regardless of what other checkout elements are present**」；由商家在 checkout editor 中擺放 |
| **Runnable targets** | 不渲染 UI，只提供資料/功能（例：address autocomplete） |

**設定檔 `shopify.extension.toml`**（<https://shopify.dev/docs/api/checkout-ui-extensions>）：
必填 `api_version`、`[[extensions]]`（`type`, `name`, `handle`, `uid`）、`[[extensions.targeting]]`（`target` + `module`）；選填 `capabilities`、`metafields`、`settings`。

**全域物件**：`shopify`（ESLint 需 `globals: { shopify: 'readonly' }`），提供 `shopify.cost`、`shopify.buyerIdentity`，以及 `applyAttributeChange`（寫 cart attributes）、`applyMetafieldChange`（寫 cart metafields）等方法（同上）。

**元件**：Web components，含表單輸入、按鈕、overlay 與版面原語「stack, grid, and section」，遵循 Shopify 設計系統（同上）。

### ② 狀態／列舉：**完整 extension targets 清單（31 個）**

出處：<https://shopify.dev/docs/api/checkout-ui-extensions/latest/targets>（與 `latest/extension-targets-overview` 交叉一致）

**Checkout — Address（runnable）**
- `purchase.address-autocomplete.suggest`
- `purchase.address-autocomplete.format-suggestion`

**Checkout — Block**
- `purchase.checkout.block.render`

**Checkout — Footer**
- `purchase.checkout.footer.render-after`

**Checkout — Header**
- `purchase.checkout.header.render-after`

**Checkout — Information**
- `purchase.checkout.contact.render-after`

**Checkout — Local Pickup**
- `purchase.checkout.pickup-location-list.render-before`
- `purchase.checkout.pickup-location-list.render-after`
- `purchase.checkout.pickup-location-option-item.render-after`

**Checkout — Navigation**
- `purchase.checkout.actions.render-before`

**Checkout — Order Summary**
- `purchase.checkout.cart-line-item.render-after`
- `purchase.checkout.cart-line-list.render-after`
- `purchase.checkout.reductions.render-after`
- `purchase.checkout.reductions.render-before`

**Checkout — Payment**
- `purchase.checkout.payment-method-list.render-after`
- `purchase.checkout.payment-method-list.render-before`

**Checkout — Pickup Points**
- `purchase.checkout.pickup-point-list.render-after`
- `purchase.checkout.pickup-point-list.render-before`

**Checkout — Shipping**
- `purchase.checkout.delivery-address.render-after`
- `purchase.checkout.delivery-address.render-before`
- `purchase.checkout.shipping-option-item.details.render`
- `purchase.checkout.shipping-option-item.render-after`
- `purchase.checkout.shipping-option-list.render-after`
- `purchase.checkout.shipping-option-list.render-before`

**Thank You — Announcement**
- `purchase.thank-you.announcement.render`

**Thank You — Block**
- `purchase.thank-you.block.render`

**Thank You — Footer**
- `purchase.thank-you.footer.render-after`

**Thank You — Header**
- `purchase.thank-you.header.render-after`

**Thank You — Information**
- `purchase.thank-you.customer-information.render-after`

**Thank You — Order Summary and Details**
- `purchase.thank-you.cart-line-item.render-after`
- `purchase.thank-you.cart-line-list.render-after`

> **重要邊界**：這份清單 **只有 checkout 與 thank-you 兩組**。**Order Status Page / 客戶帳戶（customer account）的 targets 不在此 API**，屬於獨立的 Customer Account UI Extensions API（`customer-account.*`）。實測時若在編輯器看到「訂單狀態頁」區塊，其擴充來源是另一套 API。
>
> `extension-targets-overview` 頁面另有提到的區塊分類（Information / Shipping / Payment / Order summary / Shop Pay / Split shipping / Local Pickup / Pickup Points / Overlays / One-page checkout；Thank You 的 Order details / Order summary / Overlays）是**版面分區概念**，不是額外的 target 字串。

**Block placements**：`purchase.checkout.block.render`「supports **fourteen placements**」，文檔僅舉例 `INFORMATION1`、`DELIVERY1`、`PAYMENT1`「and more」——**完整 14 個字串文檔未載明**（已查 latest / 2025-07 / 2024-10 / unstable 四個版本頁面，皆未逐一列出）。出處：<https://shopify.dev/docs/api/checkout-ui-extensions/latest/extension-targets-overview>

### ③ 約束與限制值

| 項目 | 值 | 出處 |
|---|---|---|
| 編譯後 bundle 大小 | 「Your compiled UI extension bundle can't exceed **64 KB**」 | <https://shopify.dev/docs/api/checkout-ui-extensions> |
| 同一 block target location 的擴充數 | 「supports up to **three** extensions to the same block target location」 | 同上 |
| `settings` 定義數 | 「up to **20** per definition」 | 同上 |
| `purchase.checkout.block.render` placements | **14** | <https://shopify.dev/docs/api/checkout-ui-extensions/latest/extension-targets-overview> |
| 最新穩定版 | `2026-07`；「Each stable version is supported for a minimum of **12 months**」 | <https://shopify.dev/docs/api/checkout-ui-extensions> |
| 變更頻率 | 「Rate limits may apply to extensions that make too many changes during a checkout」（具體數字**文檔未載明**） | 同上 |
| 受保護顧客資料 | 「Apps that wish to access protected customer data must submit an application」 | 同上 |

### ④ API 操作表

| 動作 | 介面 |
|---|---|
| 宣告 target | `[[extensions.targeting]]` → `target = "<identifier>"`, `module = "./src/X.jsx"` |
| 讀 cart 成本 | `shopify.cost` |
| 讀買家身份 | `shopify.buyerIdentity` |
| 寫 cart attribute | `applyAttributeChange` |
| 寫 cart metafield | `applyMetafieldChange` |
| 商家設定 | `settings`（≤20），於 checkout editor 呈現 |
| 商家擺位 | Block target → checkout editor 拖放；Static target → 固定位置 |

### ⑤ 錯誤碼

**文檔未載明**（Checkout UI Extensions 無專屬 error code enum；買家端阻擋走 §3 的 validation function 或 `useBuyerJourneyIntercept` 類 API）。

### ⑥ 對 CHILL LOVE 的實作結論

1. **實測「編輯器沒有內建 block、全部來自 app extension」是對的，而且這是 Shopify 的刻意設計**：checkout 的可編輯性 = static target（固定錨點）＋ block target（商家自由擺放）。CHILL LOVE 的結帳編輯器要照這個二分法做：**核心結帳流程不可拆解，只開 31 個錨點**。
2. **31 個 target 字串直接照抄**成 CHILL LOVE 的錨點常數表，命名保持 `purchase.*` 前綴（相容性資產，未來要接第三方 app 生態時省事）。
3. **三個硬限制寫進 `config/limits.yml`**：bundle 64 KB、同一 block 位置 3 個擴充、settings 20 個。
4. **thank-you 與 checkout 是兩套 target**，訂單狀態頁／客戶帳戶要另開一組（`customer-account.*`），不要混在同一張表。
5. **14 個 block placement 字串查不到** → 需要用實測（登入 dev store 開 checkout editor，看 DOM/network payload）補齊。列入 §8 待辦。
6. **`applyAttributeChange` / `applyMetafieldChange` 是擴充唯一的寫入口**——CHILL LOVE 要把「擴充只能寫 cart attribute/metafield，不能直接改價」寫成安全紅線；改價必須走 Function（§2）。

---

## 5. Markets 國際化

### ① 模型

**定義**：market 是「a group of buyers that a merchant targets with a specific buying experience」；由 **conditions** 決定買家是否命中（地區、零售地點、公司地點），**不只由地理決定**（<https://shopify.dev/docs/apps/build/markets>）。

**父子與繼承（回答問題 1）**——出處 <https://shopify.dev/docs/apps/build/markets/market-inheritance>：

> 「A market can have **one or more parent markets**. If a market does not define a customization, it will **inherit the customization from its parents, or the store defaults** if no customization is defined on any parent.」

**關鍵：parent 不是手動指定的，是自動推導的（lineage inference）**：
- 子市場的 region 是父市場 condition 的**嚴格子集** → 成立父子
- 子市場的 location（POS 或 company）落在父市場的 region 內 → 成立父子
- **具體地點列舉不參與 lineage 計算**（例：「Companies A and B」 vs 「Companies A, B, and C」不會因此成為父子）

**市場優先序（specificity stack）**（同上，買家同時命中多市場時）：

```
1. Company Location   （最特定）
2. Retail Location
3. Region
4. Store Default      （最一般）
```

**繼承語意：additive vs override（4 種官方 customization）**（同上）：

| Customization | 繼承行為 | 原文 |
|---|---|---|
| `Catalogs` | **累加（additive）** | 「Inherited Catalogs and WebPresences are **added to** the child market.」 |
| `WebPresences` | **累加（additive）** | 同上 |
| `CurrencySettings` | **覆寫（override）** | 「Currency Settings and PriceInclusions are **overridden**.」 |
| `PriceInclusions` | **覆寫（override）** | 同上 |

**API 上「繼承 vs 覆寫」怎麼表達**：**用 null 表達繼承**。最明確的證據在 `MarketDeliveryConfigurations.shipping`：

> 「The shipping configuration for this market. **Null means the market inherits shipping from its parent.**」
> — <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketDeliveryConfigurations>

即：**欄位為 null = 未定義該 customization = 沿 lineage 往上找第一個有定義的（多個父市場時取最特定者），都沒有就用 store default**。**沒有 `inherited: Boolean` 這種顯式旗標，也沒有 `parentMarketId` 欄位**（Market 物件無 parent/child 欄位，見 §5②）。

### ② 狀態／列舉

**`MarketType`**（<https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketType>）：

| 值 | 說明（原文） |
|---|---|
| `REGION` | 「The market applies to the visitor based on region.」 |
| `COMPANY_LOCATION` | 「…based on the company location.」 |
| `LOCATION` | 「…based on the location.」（POS 零售） |
| `CHANNEL` | 「…based on the channel.」 |
| `NONE` | 「The market does not apply to any visitor.」 |

**`MarketStatus`**（<https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketStatus>）：`ACTIVE`（「The market is active.」）、`DRAFT`（「The market is in draft.」）

**條件與型別對應**（<https://shopify.dev/docs/apps/build/markets/market-types>）：

| Market type | 支援的 conditions |
|---|---|
| REGION | `regionsCondition` |
| COMPANY_LOCATION | `companyLocationsCondition` |
| LOCATION | `locationsCondition`, `regionsCondition` |

**`applicationLevel`**：`SPECIFIED`（列舉特定地點）｜`ALL`（wildcard，依 region 自動納入）（同上）

**`Market` 物件完整欄位**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/Market>）：

| 欄位 | 型別 | 備註 |
|---|---|---|
| `id` | `ID!` | |
| `handle` | `String!` | 商家可改的唯一識別 |
| `name` | `String!` | 內部名稱，不對顧客顯示 |
| `type` | `MarketType!` | |
| `status` | `MarketStatus!` | 取代已 deprecated 的 `enabled` |
| `conditions` | `MarketConditions` | 買家匹配條件 |
| `currencySettings` | `MarketCurrencySettings` | |
| `priceInclusions` | `MarketPriceInclusions` | |
| `delivery` | `MarketDeliveryConfigurations!` | |
| `catalogs` | `MarketCatalogConnection!` | after/before/first/last/reverse |
| `catalogsCount` | `Count` | |
| `webPresences` | `MarketWebPresenceConnection!` | after/before/first/last/reverse |
| `discounts` | `DiscountNodeConnection` | **市場層可讀折扣** |
| `discountsCount` | `Count` | |
| `metafield` / `metafields` | | |
| `assignedCustomization` | `Boolean!` | 參數 `customizationId`，查某 customization 是否指派給本市場 |
| ~~`enabled`~~ | `Boolean!` | Deprecated |
| ~~`primary`~~ | `Boolean!` | Deprecated |
| ~~`regions`~~ | `MarketRegionConnection!` | Deprecated |
| ~~`priceList`~~ | `PriceList` | Deprecated |
| ~~`webPresence`~~ | `MarketWebPresence` | Deprecated（單數版） |
| ~~`metafieldDefinitions`~~ | | Deprecated |

> **注意：`Market` 上沒有任何 `parentMarket` / `childMarkets` / `inheritedFrom` 欄位。** 父子關係完全由 conditions 推導，不可在 API 上直接讀寫。

**子物件**：

`MarketCurrencySettings`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketCurrencySettings>）
- `baseCurrency: CurrencySetting!` —「The currency which this market's customers must use if local currencies are disabled.」
- `localCurrencies: Boolean!` —「If enabled, then prices will be converted to give each customer the best experience based on their region. If disabled, then all customers in this market will see prices in the market's base currency.」
- `roundingEnabled: Boolean!` —「Whether or not rounding is enabled on multi-currency prices.」

`MarketPriceInclusions`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketPriceInclusions>）
- `adaptivePricingEnabled: Boolean` —「Only applicable to Managed Markets and must be ignored otherwise.」
- `inclusiveDutiesPricingStrategy: InclusiveDutiesPricingStrategy` —「determines if prices include duties」
- `inclusiveTaxPricingStrategy: InclusiveTaxPricingStrategy` —「determines if prices include taxes」

`MarketWebPresence`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketWebPresence>）
- `id`, `alternateLocales`, `defaultLocale`, `domain`, `subfolderSuffix`, `rootUrls`, `market`, `markets`
- `domain` 與 `subfolderSuffix` **互斥**；`defaultLocale` = 網域根提供的語言；`alternateLocales`「When a domain is used, these locales will be available as language-specific subfolders.」
- **不含 checkout profile 或 theme 欄位**

`MarketDeliveryConfigurations` → `shipping: ShippingConfiguration`（**null = 繼承自父市場**）
`ShippingConfiguration`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/ShippingConfiguration>）
- `isEnabled: Boolean!` —「When false, customers in this market won't see any shipping options.」
- `optionDefinitions: DeliveryOptionDefinitionConnection!`（參數 `active`/分頁）
- `optionDefinitionsCount: Count!`

### ③ 約束與限制值

| 項目 | 值 | 出處 |
|---|---|---|
| Wildcard 市場 | 「A maximum of **100 total wildcard markets** is enforced for each shop, regardless of the market type.」 | <https://shopify.dev/docs/apps/build/markets/market-types> |
| 相同 regions 的市場 | 「**Only one market with the same set of regions can be active at a time.**」 | 同上 |
| 每店市場總數上限 | **文檔未載明**（`market-types` 頁明言「No limits」於 Country/Region markets） | <https://help.shopify.com/en/manual/markets/getting-started/market-types> |
| B2B 市場 catalog 指派 | Basic/Grow/Advanced：**3 active catalog assignments across all B2B markets**；Plus：unlimited | 同上 |
| 巢狀層數上限 | **文檔未載明** | <https://shopify.dev/docs/apps/build/markets/market-inheritance> |
| 每市場 regions 數上限 | **文檔未載明** | — |
| Retail markets catalog 客製 | 需 Shopify POS Pro 或 Plus | <https://help.shopify.com/en/manual/markets/getting-started/market-types> |

**目錄行為**：「Products that are excluded from a market's catalog are **hidden from storefronts, omitted from search results, and blocked from being added to cart**.」（<https://shopify.dev/docs/apps/build/markets>）

### ④ API 操作表

| 動作 | 介面 | 出處 |
|---|---|---|
| 建立市場 | `marketCreate(input: MarketCreateInput!)`：`name`, `handle`, `conditions{ regionsCondition{ regions[{countryCode}] } / companyLocationsCondition{ applicationLevel: "ALL" \| companyLocationIds } / locationsCondition{ applicationLevel } }`, `currencySettings`, `catalogs`, `webPresences` | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/marketCreate> |
| 回傳 | `MarketCreatePayload { market, userErrors: [MarketUserError!]!{ field, message, code } }` | 同上 |
| 更新幣別 | `marketCurrencySettingsUpdate` | <https://shopify.dev/docs/apps/build/markets> |
| 查詢 | `markets`（<https://shopify.dev/docs/api/admin-graphql/latest/queries/markets>）、`Market` 物件 | |
| 檢查客製指派 | `Market.assignedCustomization(customizationId:)` | <https://shopify.dev/docs/api/admin-graphql/latest/objects/Market> |
| 讀市場折扣 | `Market.discounts` / `Market.discountsCount` | 同上 |
| 折扣綁市場 | `DiscountContextInput.markets`（2026-07+） | <https://shopify.dev/changelog/target-discounts-to-specific-markets> |

### ⑤ 錯誤碼

`MarketUserError { field, message, code }`（<https://shopify.dev/docs/api/admin-graphql/latest/mutations/marketCreate>）。
**完整 `MarketUserErrorCode` 列舉值：文檔未載明**（marketCreate 頁未展開 enum）。

### ⑥ 對 CHILL LOVE 的實作結論（含 8 維度對照）

**實測到的 8 個「可繼承維度」對上官方 API 的結果**：

| # | 實測維度 | 官方 API 對應 | 繼承語意 | 出處 / 狀態 |
|---|---|---|---|---|
| 1 | 幣別 | `Market.currencySettings: MarketCurrencySettings` | **覆寫** | market-inheritance ✅ |
| 2 | 目錄 | `Market.catalogs: MarketCatalogConnection!` | **累加** | market-inheritance ✅ |
| 3 | 折扣 | `Market.discounts`（寫入面 `DiscountContextInput.markets`） | **文檔未載明繼承語意** | Market 物件有欄位，但 inheritance 頁未列入 4 種 customization ⚠️ |
| 4 | 主題 | 無對應 API 欄位 | **文檔未載明** | ⚠️ |
| 5 | 結帳設定檔 | `CheckoutProfile` **無任何 market 欄位** | **文檔未載明** | <https://shopify.dev/docs/api/admin-graphql/latest/objects/CheckoutProfile>（欄位僅 id/name/isPublished/createdAt/editedAt/updatedAt/typOspPagesActive）⚠️ |
| 6 | 網域＋語言 | `Market.webPresences: MarketWebPresenceConnection!` | **累加** | market-inheritance ✅ |
| 7 | 稅與關稅 | `Market.priceInclusions: MarketPriceInclusions` | **覆寫** | market-inheritance ✅ |
| 8 | 退貨規則 | 無對應 API 欄位（`MarketDeliveryConfigurations` **只有 `shipping`**） | **文檔未載明** | <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketDeliveryConfigurations> ⚠️ |

> **結論**：**8 個實測維度中只有 4 個在公開 API 上有繼承定義**（幣別、目錄、網域+語言、稅與關稅），另外「配送」是官方文檔明說 null=繼承的第 5 個維度但沒進 inheritance 頁的表。折扣／主題／結帳設定檔／退貨規則四項屬於 **admin UI 已上線、公開 API 未跟上**（Shopify 常見狀況）。

**實作決策**：

1. **繼承用 null 表達，不要加 `inherited` 布林欄位**。所有 market customization 欄位可空；解析時沿 lineage 往上找。這與 Shopify 完全一致，也讓「回到繼承」＝把欄位設回 null，語意乾淨。
2. **lineage 自動推導，不存 `parent_market_id`**（或存為快取欄位但標明 derived）。推導規則：region 嚴格子集，或 location/company location 落在父 region 內；**具體地點列舉不參與推導**。這條要寫成純函式＋單元測試。
3. **實作 additive vs override 兩種 merge 策略**：`catalogs` / `web_presences` 走 union（累加）；`currency_settings` / `price_inclusions` / `shipping_configuration` 走 first-wins（最特定者覆寫）。
4. **命中解析照 4 層優先序**：Company Location > Retail Location > Region > Store Default。這條直接進 `Markets::Resolver` 並寫 golden test。
5. **另外 4 個維度（折扣/主題/結帳設定檔/退貨規則）由我們自己定繼承語意**，建議：折扣＝累加（一個市場可有多個折扣）、主題＝覆寫、結帳設定檔＝覆寫、退貨規則＝覆寫。**在 spec 中明確標注「Shopify 文檔未載明，CHILL LOVE 自定」**，避免日後誤以為是抄來的。
6. **`domain` XOR `subfolderSuffix`** 用 DB check constraint 落實（`29-markets-i18n.md` §1.4 已有此設計，一致）。
7. **限制值**：wildcard 市場 100、相同 regions 只能一個 active、B2B catalog 指派方案上限（3 / unlimited）進 `config/limits.yml`。
8. **`Market.assignedCustomization(customizationId:)` 這個 API 形狀值得抄**——它是「這個市場有沒有自己定義某項客製」的查詢，正好是 admin UI 上「繼承 / 已覆寫」徽章的資料來源。

---

## 6. B2B

### ① 模型

**三個核心物件**（<https://shopify.dev/docs/apps/build/b2b>）：

| 物件 | 定義（原文） |
|---|---|
| `Company` | 「Information about the business entity that makes a B2B purchase. A company contains locations and contacts.」 |
| `CompanyLocation` | 「A single location or branch of the company」，帶 billing/shipping 地址；可指派 catalogs、tax exemptions、payment terms |
| `CompanyContact` | 「A person that acts on behalf of the company. A company contact is **associated with a retail customer record**.」 |

> **關鍵**：company contact **不是獨立帳號，是掛在 retail customer 上的角色**。CHILL LOVE 的 customers 表要能同時扮演 B2C 顧客與 B2B 聯絡人。

**company vs company_location 掛什麼（回答問題 5）**：

| 設定 | 掛在哪 | 出處 |
|---|---|---|
| **Catalog（含 price list / publication）** | **僅 company_location**（「Catalogs attach exclusively to company locations, not companies.」） | <https://shopify.dev/docs/apps/build/b2b> |
| **Payment terms** | **company_location**（透過 `buyerExperienceConfiguration.paymentTermsTemplateId`）；admin 可從 company 頁**批次套用到所有 location** | <https://shopify.dev/docs/apps/build/b2b/manage-client-company-locations>、<https://help.shopify.com/en/manual/b2b/companies-and-customers/creating-companies> |
| **Tax（tax ID / VAT / exemptions / collection）** | **僅 company_location**（「some information, such as tax IDs and exemptions, is **location-specific and must be updated from the location page**」） | <https://help.shopify.com/en/manual/b2b/companies-and-customers/creating-companies> |
| **Checkout 設定（checkoutToDraft / editableShippingAddress / deposit）** | **company_location**（`buyerExperienceConfiguration`）；company 頁可批次 | 同上 + <https://shopify.dev/docs/api/admin-graphql/latest/objects/BuyerExperienceConfiguration> |
| **Currency** | **company_location**（`currency: CurrencyCode!`「The location's currency based on the shipping address」） | <https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyLocation> |
| **Billing / shipping 地址** | **company_location** | 同上 |
| **Locale** | **company_location**（`locale: String`） | 同上 |
| **Checkout profile** | **無 company/location 欄位 → 文檔未載明** | <https://shopify.dev/docs/api/admin-graphql/latest/objects/CheckoutProfile> |
| **Default role** | **company**（`Company.defaultRole: CompanyContactRole`「The role proposed by default for a contact at the company.」） | <https://shopify.dev/docs/api/admin-graphql/latest/objects/Company> |
| **Market 關聯** | `CompanyLocation.market: Market!` — **已 Deprecated**（改由 `COMPANY_LOCATION` 型 market 的 `companyLocationsCondition` 反向匹配） | <https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyLocation> |

**`Company` 欄位**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/Company>）：
`id`, `name`, `externalId`, `note`, `createdAt`, `updatedAt`, `customerSince: DateTime!`, `lifetimeDuration: String!`（「Examples: `2 days`, `3 months`, `1 year`」）, `mainContact`, `contacts`（after/before/first/last/query/reverse/sortKey）, `contactsCount`, `defaultRole`, `contactRoles`, `locations`, `locationsCount`, `orders`, `ordersCount`（「across all its locations」）, `draftOrders`, `totalSpent: MoneyV2!`, `metafield(s)`, `events`, `hasTimelineComment`, `defaultCursor`。
Scope：`read_customers` 或 `read_companies`；**需 B2B 方案**。

**`CompanyLocation` 欄位**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyLocation>）：
`id`, `externalId`, `name`, `note`, `phone`, `locale`, `createdAt`, `updatedAt`, `billingAddress: CompanyAddress`, `shippingAddress: CompanyAddress`, `currency: CurrencyCode!`, `catalogs: CatalogConnection!`, `catalogsCount`, `inCatalog(catalogId:): Boolean!`, `buyerExperienceConfiguration`, `taxSettings: CompanyLocationTaxSettings!`, `totalSpent: MoneyV2!`, `orders`, `ordersCount`, `draftOrders`, `company: Company!`, `roleAssignments: CompanyContactRoleAssignmentConnection!`, `staffMemberAssignments: CompanyLocationStaffMemberAssignmentConnection!`, `storeCreditAccounts`, `metafield(s)`, `events`, `hasTimelineComment`, `defaultCursor`。
Deprecated：`market`, `taxExemptions`, `taxRegistrationId`, `metafieldDefinitions`。

**`BuyerExperienceConfiguration`**（<https://shopify.dev/docs/api/admin-graphql/latest/objects/BuyerExperienceConfiguration>）：

| 欄位 | 型別 | 說明（原文） |
|---|---|---|
| `checkoutToDraft` | `Boolean!` | 「Whether to checkout to draft order for merchant review.」 |
| `editableShippingAddress` | `Boolean!` | 「Whether to allow customers to use editable shipping addresses.」 |
| `paymentTermsTemplate` | `PaymentTermsTemplate` | 「Represents the merchant configured payment terms.」 |
| `deposit` | `DepositConfiguration`（union） | 「The portion required to be paid at checkout.」 |
| ~~`payNowOnly`~~ | `Boolean!` | **Deprecated** |

**訂單審核流（draft order submission，回答問題 5 後半）**：

*API 側（<https://shopify.dev/docs/apps/build/b2b/draft-orders>）四步：*
```
1. draftOrderCalculate      → 預覽 totals / taxes / pricing
2. draftOrderCreate         → 帶 purchasingEntity { companyId, companyLocationId, companyContactId }
3. draftOrderInvoiceSend    → 寄發票給 company contact
4. draftOrderComplete       → 轉成正式訂單
```

*買家側（<https://help.shopify.com/en/manual/b2b/checkout>）：*
- 當 checkout 設為「**Only allow draft orders**」（= `checkoutToDraft: true`）→ 買家按 **Submit for approval**
- 訂單落到 admin **Drafts 頁**
- 完成條件二選一：商家按 **Create order**，或買家收到 invoice 後付款
- 付款條件三態：
  - **無 payment terms** → 買家輸入信用卡、按 **Pay now**
  - **Net terms** → 買家按 **Submit**，訂單顯示 **Payment pending**
  - **Net terms + deposit** → 買家按 **Submit now** 並**立即支付訂金**；訂單狀態為 **Partially paid** 或 **Payment pending**（視是否自動請款）
- 地址：結帳地址預填且「can't be edited during the checkout process」，除非該 location 的聯絡人有 **Location admin** 角色，或已開啟 editable shipping address

### ② 狀態／列舉

**B2B 聯絡人角色**（<https://help.shopify.com/en/manual/b2b/companies-and-customers/adding-customers>）：

| 角色 | 權限（原文） |
|---|---|
| **Ordering only** | 「Place orders for the assigned company locations and view your own order history.」 |
| **Location admin** | 「Place orders for the company location, view the list of orders that all customers have placed for that location, and edit billing and shipping addresses.」 |

`CompanyContactRole`（<https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyContactRole>）：`id: ID!`、`name: String!`（「For example, `admin` or `buyer`.」）、`note: String`。

**`PaymentTermsType`**（<https://shopify.dev/docs/api/admin-graphql/latest/enums/PaymentTermsType>）：

| 值 | 說明（原文） |
|---|---|
| `FIXED` | 「It's due on a specified date.」 |
| `FULFILLMENT` | 「…due on fulfillment.」 |
| `NET` | 「It's due a number of days after issue.」（搭配 `dueInDays`） |
| `RECEIPT` | 「…due on receipt.」 |
| `UNKNOWN` | 「The type … is unknown.」 |

`PaymentTermsTemplate` 欄位（<https://shopify.dev/docs/api/admin-graphql/latest/objects/PaymentTermsTemplate>）：`id`, `name`, `description`, `dueInDays`, `paymentTermsType`, `translatedName`。
**標準 NET 7/15/30/45/60/90 的內建清單：文檔未載明**（只給泛用 `dueInDays`）。

### ③ 約束與限制值

| 項目 | 值 | 出處 |
|---|---|---|
| 每店 companies 數 | **Unlimited**（「You can have an unlimited number of companies」） | <https://help.shopify.com/en/manual/b2b/companies-and-customers/creating-companies> |
| 每 company 的 locations | **10,000** | 同上 |
| 每 company 的 customers（contacts） | **10,000** | 同上 + <https://help.shopify.com/en/manual/b2b/companies-and-customers/adding-customers> |
| 每 company **location** 的 customers | **50** | <https://help.shopify.com/en/manual/b2b/companies-and-customers/creating-companies> |
| 每 company location 的 catalogs | **25** | 同上 |
| `priceListFixedPricesAdd` 單次上限 | 「a maximum of **250 prices** for each request」 | <https://shopify.dev/docs/apps/build/b2b/manage-catalogs> |
| 一個 customer 可屬幾家 company | 「can add a customer **only to one company**」（但可指派到該 company 內多個 location） | <https://help.shopify.com/en/manual/b2b/companies-and-customers/adding-customers> |
| B2B market catalog 指派 | Basic/Grow/Advanced **3**；Plus unlimited | <https://help.shopify.com/en/manual/markets/getting-started/market-types> |
| 方案要求 | **Shopify Plus 才有 B2B**（dev stores 與 Plus Partner sandbox org 例外） | <https://shopify.dev/docs/apps/build/b2b> |
| 不支援的購買選項 | subscriptions、pre-orders、try-before-you-buy | 同上 |

**多 catalog 解析規則**（<https://shopify.dev/docs/apps/build/b2b/start-building>、<https://shopify.dev/docs/apps/build/b2b/manage-catalogs>）：
- 「Multiple catalogs can be associated with the same company location. If a customer is logged into a B2B customer account that's eligible for multiple catalogs that contain the same product, then they receive the **lowest listed price** within those catalogs.」
- 商品「must be published in at least one applicable publication to be visible」

### ④ API 操作表

| 動作 | Mutation / Query | 出處 |
|---|---|---|
| 建立公司 | `companyCreate`（必填三塊：`name`、`companyLocation`、`companyContact`） | <https://shopify.dev/docs/apps/build/b2b/start-building> |
| 建立／更新 location | `companyLocationCreate`、`companyLocationUpdate`（含 `buyerExperienceConfiguration{ paymentTermsTemplateId, checkoutToDraft, editableShippingAddress, deposit }`） | <https://shopify.dev/docs/apps/build/b2b/manage-client-company-locations> |
| 指派免稅 | `companyLocationAssignTaxExemptions`（例：`CA_BC_RESELLER_EXEMPTION`, `CA_STATUS_CARD_EXEMPTION`） | 同上 |
| 建立付款條件範本 | `paymentTermsCreate` | 同上 |
| 建立 catalog | `catalogCreate`（`context` 帶 company location ID） | <https://shopify.dev/docs/apps/build/b2b/start-building> |
| 價目表 | `priceListCreate`（`PERCENTAGE_INCREASE` / `PERCENTAGE_DECREASE` 調整）、`priceListFixedPricesAdd`（≤250/次）、`priceListFixedPricesDelete` | <https://shopify.dev/docs/apps/build/b2b/manage-catalogs> |
| 發佈 | `publicationCreate`、`publicationUpdate`（`publishablesToAdd` / `publishablesToRemove`） | 同上 |
| B2B 草稿訂單 | `draftOrderCalculate` → `draftOrderCreate(purchasingEntity{companyId, companyLocationId, companyContactId})` → `draftOrderInvoiceSend` → `draftOrderComplete` | <https://shopify.dev/docs/apps/build/b2b/draft-orders> |
| 匯入外部 B2B 訂單 | 見 `https://shopify.dev/docs/apps/build/b2b/import-orders` | <https://shopify.dev/docs/apps/build/b2b> |
| Scopes | `unauthenticated_read_customers`, `unauthenticated_write_customers`, `read_products`, `write_products`, `read_draft_orders`, `write_draft_orders`；讀 Company 需 `read_customers` 或 `read_companies` | <https://shopify.dev/docs/apps/build/b2b/start-building>、<https://shopify.dev/docs/api/admin-graphql/latest/objects/Company> |

### ⑤ 錯誤碼

- B2B 專屬的 userError code enum：**文檔未載明**（各 mutation 頁未展開）
- 草稿訂單狀態（`DraftOrderStatus`）的 B2B 專屬值：**文檔未載明**（`b2b/draft-orders` 頁未列 enum）

### ⑥ 對 CHILL LOVE 的實作結論

1. **資料模型三張表 + 兩張關聯表**：`companies`（shop_id, name, external_id, note, default_role_id, main_contact_id）、`company_locations`（company_id, name, locale, currency, billing/shipping address, buyer_experience_configuration JSON 或展開欄位, tax_settings）、`company_contacts`（company_id, **customer_id** 外鍵 → 復用 customers 表）；關聯：`company_contact_role_assignments`（contact × location × role）、`company_location_catalogs`。
2. **「掛在哪一層」的鐵律照抄**：catalog / payment terms / tax / checkout 設定 / currency / 地址 **一律掛 location**；company 層只有 name / note / default_role / main_contact。**Admin UI 提供「從 company 頁批次套到所有 location」的便利操作，但資料仍寫進每個 location**——這正是 Shopify 的作法，能避免「company 值 vs location 值誰贏」的繼承地獄。
3. **`checkoutToDraft` 是 B2B 審核流的唯一開關**。實作：結帳完成時若該 location `checkout_to_draft = true`，不建 order 而建 draft_order（狀態 `OPEN`），前台按鈕文案改成「送出待審核」。這一條要和 §3 的 validation pipeline 明確分工：validation 是**擋**，checkoutToDraft 是**轉向**。
4. **付款條件三態的訂單狀態對應**要做對：無 terms → 立即付款；NET → `payment_pending`；NET + deposit → `partially_paid`（收訂金）。訂金 union（`DepositConfiguration`）先做百分比一種。
5. **兩個角色照抄**：`ordering_only` / `location_admin`。權限差異三點：看不看得到同 location 其他人的訂單、能不能改帳單/送貨地址、地址可編輯性。角色是 **contact × location** 的指派（不是 contact 的全域屬性）——這點很容易做錯。
6. **多 catalog 取最低價**：`SELECT MIN(price)` across applicable catalogs，且商品必須至少在一個 applicable publication 內才可見。寫成 `B2b::PriceResolver` 並測「同商品多 catalog」case。
7. **`$.cart.poNumber`（§3）＋ B2B**：PO number 是 B2B 結帳的一級欄位，要開在 cart 層並可被 validation 規則檢查。
8. **限制值進 `config/limits.yml`**：10,000 locations/company、10,000 contacts/company、**50 contacts/location**、25 catalogs/location、250 prices/request、1 company/customer。
9. **`CompanyLocation.market` 已 deprecated**：不要建 location → market 的正向外鍵；改成由 `COMPANY_LOCATION` 型 market 的 condition 反查（與 §5 的 conditions 模型一致）。

---

## 7. 全域限制值總表

> 直接可進 `config/limits.yml`。**每一條都有出處**；沒出處的不列。

| Key | 值 | 領域 | 出處 |
|---|---|---|---|
| `function.binary_size_kb` | 256 | Functions | api/functions |
| `function.linear_memory_kb` | 10000 | Functions | api/functions |
| `function.stack_memory_kb` | 512 | Functions | api/functions |
| `function.log_bytes` | 1024 | Functions | api/functions |
| `function.instructions` | 11_000_000 | Functions（≤200 line items） | api/functions |
| `function.input_kb` | 128 | Functions（≤200 line items） | api/functions |
| `function.output_kb` | 20 | Functions（≤200 line items） | api/functions |
| `function.input_query_bytes` | 3000 | Functions | api/functions |
| `function.metafield_value_bytes` | 10000 | Functions | api/functions |
| `function.list_arg_elements` | 100 | Functions | api/functions |
| `function.max_query_cost` | 30 | Functions | api/functions |
| `function.discount.max_per_shop` | 25 | Functions | api/functions/latest/discount |
| `function.validation.max_per_shop` | 25 | Functions | api/functions/latest/cart-and-checkout-validation |
| `function.delivery_customization.max_per_shop` | 25 | Functions | api/functions/latest/delivery-customization |
| `function.payment_customization.max_per_shop` | 25 | Functions | api/functions/latest/payment-customization |
| `function.cart_transform.max_per_app_per_shop` | 1 | Functions | api/functions/latest/cart-transform |
| `function.discounts_allocator.max_per_shop` | 1 | Functions | api/functions/unstable/discounts-allocator |
| `discount.active_automatic.max` | 25 | 折扣 | enums/DiscountErrorCode |
| `discount.codes_per_shop.max` | 20_000_000 | 折扣 | help/discount-codes |
| `discount.code_entities.max` | 100 | 折扣（顧客/商品/變體） | help/discount-codes |
| `discount.codes_per_checkout.product_order` | 5 | 折扣 | help/discount-combinations |
| `discount.codes_per_checkout.shipping` | 1 | 折扣 | help/discount-combinations |
| `discount.same_cart_line_tags.max` | 10 | 折扣（Plus） | enums/DiscountErrorCode |
| `discount.tags.max` | 5 | 折扣 | enums/DiscountErrorCode |
| `discount.tag_length.max` | 255 | 折扣 | enums/DiscountErrorCode |
| `checkout_ui_extension.bundle_kb` | 64 | Checkout UI | api/checkout-ui-extensions |
| `checkout_ui_extension.per_block_location` | 3 | Checkout UI | api/checkout-ui-extensions |
| `checkout_ui_extension.settings_per_definition` | 20 | Checkout UI | api/checkout-ui-extensions |
| `checkout_ui_extension.block_placements` | 14 | Checkout UI | extension-targets-overview |
| `market.wildcard.max_per_shop` | 100 | Markets | markets/market-types |
| `market.b2b_catalog_assignments.non_plus` | 3 | Markets | help/markets/market-types |
| `b2b.locations_per_company.max` | 10000 | B2B | help/b2b/creating-companies |
| `b2b.contacts_per_company.max` | 10000 | B2B | help/b2b/creating-companies |
| `b2b.contacts_per_location.max` | 50 | B2B | help/b2b/creating-companies |
| `b2b.catalogs_per_location.max` | 25 | B2B | help/b2b/creating-companies |
| `b2b.fixed_prices_per_request.max` | 250 | B2B | b2b/manage-catalogs |
| `b2b.companies_per_customer.max` | 1 | B2B | help/b2b/adding-customers |

---

## 8. 文檔未載明清單（待實測補齊）

| # | 項目 | 已查頁面 | 補齊方式 |
|---|---|---|---|
| 1 | `purchase.checkout.block.render` 的 14 個 placement 字串 | checkout-ui-extensions latest / 2025-07 / 2024-10 / unstable 的 extension-targets-overview | 登入 dev store 開 checkout editor，抓 network payload 或 DOM |
| 2 | Function 折扣 candidate `message` 字元上限 | api/functions/latest/discount、2025-10/discount | 實測送超長 message 看回錯 |
| 3 | validation function 單次 errors 數上限、message 長度上限 | api/functions/latest/cart-and-checkout-validation | 實測 |
| 4 | 每店 markets 總數上限 | markets/market-types（dev + help） | 實測建到報錯為止（社群有「50 markets」說法，**未經官方文檔證實，勿引用**） |
| 5 | market 巢狀層數上限、每 market regions 數上限 | markets/market-inheritance、market-types | 實測 |
| 6 | `MarketUserErrorCode` 完整列舉值 | mutations/marketCreate | GraphQL introspection |
| 7 | 主題／結帳設定檔／退貨規則的 per-market API | Market 物件、CheckoutProfile、MarketDeliveryConfigurations | GraphQL introspection 找 unstable 版新欄位 |
| 8 | 折扣在 market 間的繼承語意（additive or override） | markets/market-inheritance（未列入 4 種 customization） | 實測：父市場設折扣，看子市場是否生效 |
| 9 | 內建 payment terms 範本清單（NET 7/15/30/45/60/90） | objects/PaymentTermsTemplate | 查 `paymentTermsTemplates` query 實際回傳 |
| 10 | `DraftOrderStatus` 的 B2B 專屬值 | b2b/draft-orders | GraphQL introspection |
| 11 | Function 執行失敗時的 fallback 行為 | apps/build/functions | 實測（拔掉 function 或讓它 panic） |
| 12 | 單一 discount 可綁的 markets 數上限 | changelog/target-discounts-to-specific-markets | 實測 |
| 13 | Fulfillment Constraints / Order Routing / Pickup Point Generator 的 target handle | api/functions 清單頁 | 各自的 reference 頁再抓一輪 |
| 14 | Checkout UI Extensions 的 rate limit 具體數字 | api/checkout-ui-extensions | 實測 |

---

## 附錄：本次抓取的全部來源 URL

**Functions**
- <https://shopify.dev/docs/api/functions>
- <https://shopify.dev/docs/apps/build/functions>
- <https://shopify.dev/docs/api/functions/latest/discount>
- <https://shopify.dev/docs/api/functions/2025-10/discount>
- <https://shopify.dev/docs/api/functions/latest/cart-transform>
- <https://shopify.dev/docs/api/functions/latest/delivery-customization>
- <https://shopify.dev/docs/api/functions/latest/payment-customization>
- <https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation>
- <https://shopify.dev/docs/api/functions/latest/cart-checkout-validation>（已廢版本說明）
- <https://shopify.dev/docs/api/functions/unstable/discounts-allocator>

**Discounts**
- <https://shopify.dev/docs/apps/build/discounts>
- <https://shopify.dev/docs/apps/build/discounts/build-discount-function>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBasicCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticBxgyCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticFreeShippingCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountAutomaticAppCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/discountCodeBasicCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountCodeBasic>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/DiscountCombinesWith>
- <https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountClass>
- <https://shopify.dev/docs/api/admin-graphql/latest/enums/DiscountErrorCode>
- <https://shopify.dev/changelog/discount-eligibility-management>
- <https://shopify.dev/changelog/target-discounts-to-specific-markets>
- <https://help.shopify.com/en/manual/discounts/discount-combinations>
- <https://help.shopify.com/en/manual/discounts/discount-methods/discount-codes>

**Checkout validation / UI extensions**
- <https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation>
- <https://shopify.dev/docs/apps/build/checkout/cart-checkout-validation/create-checkout-validation>
- <https://shopify.dev/changelog/cart-and-checkout-validation-adds-billing-address-and-po-number-error-targets>
- <https://shopify.dev/docs/api/checkout-ui-extensions>
- <https://shopify.dev/docs/api/checkout-ui-extensions/latest/extension-targets-overview>
- <https://shopify.dev/docs/api/checkout-ui-extensions/latest/targets>
- <https://shopify.dev/docs/api/checkout-ui-extensions/2024-10/extension-targets-overview>

**Markets**
- <https://shopify.dev/docs/apps/build/markets>
- <https://shopify.dev/docs/apps/build/markets/overview>
- <https://shopify.dev/docs/apps/build/markets/market-inheritance>
- <https://shopify.dev/docs/apps/build/markets/market-types>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/Market>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketWebPresence>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketCurrencySettings>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketPriceInclusions>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/MarketDeliveryConfigurations>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/ShippingConfiguration>
- <https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketType>
- <https://shopify.dev/docs/api/admin-graphql/latest/enums/MarketStatus>
- <https://shopify.dev/docs/api/admin-graphql/latest/mutations/marketCreate>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/CheckoutProfile>
- <https://help.shopify.com/en/manual/markets/getting-started/market-types>

**B2B**
- <https://shopify.dev/docs/apps/build/b2b>
- <https://shopify.dev/docs/apps/build/b2b/start-building>
- <https://shopify.dev/docs/apps/build/b2b/manage-client-company-locations>
- <https://shopify.dev/docs/apps/build/b2b/manage-catalogs>
- <https://shopify.dev/docs/apps/build/b2b/draft-orders>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/Company>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyLocation>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/CompanyContactRole>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/BuyerExperienceConfiguration>
- <https://shopify.dev/docs/api/admin-graphql/latest/objects/PaymentTermsTemplate>
- <https://shopify.dev/docs/api/admin-graphql/latest/enums/PaymentTermsType>
- <https://help.shopify.com/en/manual/b2b/checkout>
- <https://help.shopify.com/en/manual/b2b/companies-and-customers/creating-companies>
- <https://help.shopify.com/en/manual/b2b/companies-and-customers/adding-customers>
