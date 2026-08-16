# 03. 購物車與結帳（Cart / Checkout / Abandoned）

> 本章對 Shopify 官方文檔（shopify.dev ＋ help.shopify.com）做深度考掘，覆蓋 cart 物件與行為、Ajax Cart API、one-page checkout、庫存保留、棄單、express checkout、deferred purchase options、checkout validation、cart transform，以及 checkout 下游的訂閱履約子域（SubscriptionContract／BillingCycle／BillingAttempt，A.7／B.6／D.7——D.6 餘額後收的承載物件）。所有規則性斷言附來源（G 節），取證日期 2026-08-14。與倉庫既有裁定的差異見 F 節。

---

## A. 領域物件模型

### A.1 物件總覽與 cardinality

```
Shop 1 ──< Cart（線上商店購物車；Storefront API 可無限建立）
Cart 1 ──< CartLine（上限 500 行）
Cart 1 ──  0..1 Checkout（buyer 按 checkout 進入；cart.checkoutUrl）
Checkout 1 ── 0..1 Order（完成付款才成立）
Checkout（未完成＋已留 email）1 ── 1 AbandonedCheckout
AbandonedCheckout 1 ──< AbandonedCheckoutLineItem
Abandonment 1 ── 0..1 AbandonedCheckout（abandonedCheckoutPayload）
Abandonment N ── 1 Customer
CartLine N ── 0..1 SellingPlan（訂閱／預購／TBYB；透過 selling_plan_allocation）
Order（origin）1 ──< SubscriptionContract（checkout 完成且行含 SUBSCRIPTION plan 時建立）
SubscriptionContract 1 ──< SubscriptionBillingCycle（index 自 1 遞增，契約編輯不重置）
SubscriptionBillingCycle 1 ── 0..N SubscriptionBillingAttempt（成功的 attempt 1 ── 1 Order）
```

- 「一 shop 或一 customer 可建立無限多個 cart」；**checkout 完成時 Shopify 自動刪除該 cart**（G-7）。
- Cart 是**買家幣別（presentment currency）**的物件：「All monetary properties are returned in the customer's presentment currency」（Ajax cart.js，G-1）。

### A.2 Cart（Ajax API 形態，前台主題用）

| 欄位 | 型別／說明 |
|---|---|
| `token` | cart 識別字串（可含 `?key=` 簽名段） |
| `note` | cart 備註（結帳後轉為訂單 note） |
| `attributes` | 鍵值對；`__` 前綴＝私有（Liquid `cart.attributes` 與 Ajax API 均不可見，利於頁面快取）（G-1） |
| `original_total_price` / `total_price` / `total_discount` / `items_subtotal_price` | 整數（presentment 幣別最小單位） |
| `total_weight` | 克 |
| `item_count` | 總件數 |
| `currency` | ISO 幣別碼 |
| `requires_shipping` | bool（任一行需配送即 true） |
| `items[]` | 行項目（見 A.3） |
| `cart_level_discount_applications[]` | 訂單級折扣分攤 |

### A.3 CartLine（Ajax `items[]` 元素）

| 欄位 | 說明 |
|---|---|
| `key` | `"{variant_id}:{hash}"`；**非終身穩定**——properties／折扣分攤等特徵變動時 key 會變（G-1） |
| `id` / `variant_id` / `product_id` | 識別 |
| `quantity` | 數量 |
| `price` / `original_price` / `discounted_price` | 單價（整數） |
| `line_price` / `original_line_price` / `line_level_total_discount` | 行金額 |
| `properties` | line item properties；`_` 前綴＝私有（結帳頁不顯示、admin 訂單頁可見）（G-1） |
| `selling_plan_allocation` | 見 A.6；含 `price`、`compare_at_price`、`per_delivery_price`、`price_adjustments[]`、`selling_plan{...}` |
| `quantity_rule` | `{min, max, increment}`（B2B quantity rules 才有非預設值） |
| `has_components` / `parent_id` | bundle（cart transform）相關 |
| `unit_price` / `unit_price_measurement` | 單位價格（歐盟法規顯示） |
| 其餘 | `sku`、`grams`、`vendor`、`taxable`、`gift_card`、`url`、`featured_image`、`variant_options`、`options_with_values`、`line_level_discount_allocations` |

### A.4 Cart（Storefront API GraphQL 形態，headless／checkout 前身）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | ID! | 全域唯一 |
| `checkoutUrl` | URL! | 導向 Shopify web checkout 完成購買——**cart→checkout 的唯一過渡機制**（G-8） |
| `lines` | connection | 上限 **500** 行；單次 mutation（cartLinesAdd）最多 **250** 行（G-6、G-7） |
| `attributes` | [Attribute!]! | 上限 **250** 個（G-8） |
| `buyerIdentity` | CartBuyerIdentity! | 決定 international pricing 與 checkout 預填；登入態可帶入 checkout（G-7） |
| `cost` | CartCost! | `subtotalAmount`／`totalAmount`／`totalTaxAmount`／`totalDutyAmount`／**`checkoutChargeAmount`**（deferred purchase 結帳當下應收金額）（G-8） |
| `deliveryGroups` | connection | 按配送地址分組的可選配送方式；`withCarrierRates` 參數需 `@defer`（G-8） |
| `discountCodes` | [CartDiscountCode!]! | 大小寫不敏感；每個 code 有 **`applicable`** 旗標（是否真的作用於目前 cart）（G-8） |
| `appliedGiftCards` | [AppliedGiftCard!]! | 已套用禮品卡 |
| `note` / `totalQuantity` / `createdAt` / `updatedAt` / `metafields` | — | — |

### A.5 AbandonedCheckout / Abandonment（Admin GraphQL）

**AbandonedCheckout**（G-4）：`id`、`name`（商家面編號）、**`abandonedCheckoutUrl`**（買家恢復結帳連結）、`createdAt`、`updatedAt`、**`completedAt`**（null＝未完成）、`note`、`customer`、`billingAddress`、`shippingAddress`、`lineItems`（connection，快照當下品項與價格）、`customAttributes`、`discountCodes`、`subtotalPriceSet`／`totalLineItemsPriceSet`／`totalDiscountSet`／`totalTaxSet`／`totalDutiesSet`／`totalPriceSet`（皆 MoneyBag 雙幣別）、`taxLines`、`taxesIncluded`、`defaultCursor`。查詢 `abandonedCheckouts` 支援 filter：`email_state`／`recovery_state`／`status`／`created_at`／`updated_at`。

**Abandonment**（G-13）：`abandonmentType`／`mostRecentStep`（enum 見 B.3）、`abandonedCheckoutPayload`、`app`、`cartUrl`、`customer`、`emailState`（enum 見 B.3）、`emailSentAt`、`hoursSinceLastAbandonedCheckout`、`daysSinceLastAbandonedCheckout`、`inventoryAvailable`、`customerHasNoOrderSinceAbandonment`、`customerHasNoDraftOrderSinceAbandonment`、`isMostSignificantAbandonment`、`isFromOnlineStore`／`isFromShopApp`／`isFromShopPay`／`isFromCustomStorefront`、`lastBrowseAbandonmentDate`／`lastCartAbandonmentDate`／`lastCheckoutAbandonmentDate`、`productsAddedToCart`／`productsViewed`（connection）、`visitStartedAt`。

### A.6 SellingPlan（purchase options；cart／checkout 形態）

官方核可的 selling plan 分類（G-11、G-12）：

| category | 說明 |
|---|---|
| `SUBSCRIPTION` | pay-per-delivery（每次配送收款）或 pre-paid（一次付清多次配送） |
| `PRE_ORDER` | 未發售商品先下單；可收訂金 |
| `TRY_BEFORE_YOU_BUY` | 先試用後付款；可收訂金 |
| `OTHER` | 需向 Shopify 申請 |

政策四件套（G-11）：**pricing**（價格調整）、**billing**（下單→收款的時間間隔）、**delivery**（下單→出貨的時間）、**inventory**（庫存在建單時或履行時 commit）。訂閱用 pricing＋billing＋delivery；deferred purchase 四者全用。delivery 與 billing 政策必須**全 recurring 或全 fixed**；預購／TBYB 用 fixed（G-12）。

### A.7 SubscriptionContract／BillingCycle／BillingAttempt（訂閱履約子域，checkout 下游）

D.6 的「付款方式 vault、餘額後收」不是懸空機制——本尊承載它的物件是 **SubscriptionContract** 家族（G-26、G-28、G-29）。M0–M6 不實作訂閱，但「schema 預留 selling_plan 欄位」（F.2#12）必須以本模型為藍本，否則預留欄位會與本尊不同構，D.6 一旦實作必然自創機制。

- **SubscriptionContract**（G-28）核心欄位：`status`（enum 五值，見 B.6）、`nextBillingDate`、`billingPolicy`／`deliveryPolicy`（自 selling plan **快照**到契約，之後獨立於 plan 演化）、`deliveryPrice`、`currencyCode`、`customerPaymentMethod`（**vault 的付款方式掛這裡**——契約層引用的是 CustomerPaymentMethod；PaymentMandate 是金流 app 層的授權概念，D.6 原句的 vault 對象落地即此欄位）、`originOrder`（起源訂單）、`lines`／`orders`／`billingAttempts`／`discounts`（connections）、`lastPaymentStatus`、`lastBillingAttemptErrorType`、`customAttributes`／`note`（帶到每張生成訂單）。建約路徑：checkout 完成且行含 SUBSCRIPTION plan 由平台自動建，或 app 走 `subscriptionContractAtomicCreate`。
- **SubscriptionBillingCycle**（G-29）：`index` 自 **1** 遞增、契約編輯**不重置**，可唯一定位一個週期；`skipped` 旗標（skip/unskip mutation 直接翻轉，API 2024-01 起）。**單週期編輯**走 `subscriptionBillingCycleContractEditCalculate` → commit 的草稿流程，只影響該週期；官方明文兩條約束：編輯範圍限「**當前週期起至一年內**」；「契約有已 commit 單週期編輯的當前／未來週期時，**不得更新母契約**」。skip 語義＝該週期 **billing 與 delivery 一起跳過**（不建 attempt、不生訂單）。
- **SubscriptionBillingAttempt**（G-28）：`idempotencyKey`（**必填**，client 生成防重複扣款——與鐵律 5 同構）、`originTime`（覆蓋計費時點，官方明文用途＝「避免 fulfillment 被推遲到下一個 anchor 日」）、`respectInventoryPolicy`（是否尊重商家庫存政策）、`state`、`transactions`、`paymentGroupId`／`paymentSessionId`（重試串接）。舊欄位 `errorCode`／`errorMessage`／`processingError`／`ready`／`order` 已 **deprecated**——錯誤改由 `state` 與契約上的 `lastBillingAttemptErrorType` 表達，抄舊教學讀 errorCode 是錯的。attempt 成功 ⇒ 生成一張 Order（pay-per-delivery 每期一張；pre-paid 一張訂單配多個 SCHEDULED FulfillmentOrder，見 D.7）。

---

## B. 狀態機

### B.1 Cart 生命週期

| 狀態 | 進入條件 | 離開轉移 |
|---|---|---|
| `active` | 首次加入品項（Ajax add.js／cartCreate）；發 `carts/create` webhook | ①更新（發 `carts/update`）仍 active；②結帳完成→`deleted`；③閒置 30 天→`expired` |
| `expired` | 「未使用與被棄置的 cart 於建立後 30 天內自動過期」（Storefront API，G-7） | 終態 |
| `deleted` | 「checkout 完成時 Shopify 自動刪除 cart」（G-7） | 終態 |

無孤兒狀態：active 唯一活態，兩個終態皆可達。⚠️ Ajax（cookie cart）的存續期官方未載明——僅 Storefront API cart 明文 30 天（openQuestion）。

### B.2 Checkout 生命週期（含棄單）

**可直轉 enum 的儲存狀態只有三個**：`open` → `completed` ｜ `deleted`。`abandoned` 是 open 之上的**時間旗標**（`abandoned_at` 時戳＋AbandonedCheckout 實體化），`recovered` 是 completed 之上的**推導屬性**（completed 且曾 abandoned），兩者都**不是**獨立狀態值——本尊報表把 recovered 當 completed 的子集計（G-3）。

| 狀態／旗標 | 進入條件（觸發） | 前置條件 | 副作用 |
|---|---|---|---|
| `open` | buyer 由 cart 進入 checkout | cart 非空 | 發 `checkouts/create` webhook；後續每次欄位更新發 `checkouts/update` |
| `open`＋`abandoned` 旗標 | 留下 email 後 **10 分鐘**仍未完成（G-3） | 已留 email（僅留電話→不進挽回信流程）；**疑似盜卡測試／bot 的 checkout 不建棄單**（G-14） | `abandoned_at` 寫入；建 AbandonedCheckout（含 `abandonedCheckoutUrl`）；進入挽回信排程判定 |
| `completed` | 付款成功、訂單成立 | 庫存 hold 成功＋付款成功 | `completedAt` 寫入；發 `orders/create`；**cart 刪除** |
| `completed`＋`recovered` 推導 | completed 且 `abandoned_at` 非空——經挽回連結**或自行**完購皆算（G-3） | — | 挽回報表計入；不另存狀態值，報表層以 `completed_at IS NOT NULL AND abandoned_at IS NOT NULL` 推導 |
| `deleted` | abandoned 滿 **3 個月**自動刪除；admin **不可手動刪除單筆**棄單（G-3） | — | 發 `checkouts/delete` webhook |

轉移圖：`open → completed`；`open(+abandoned) → completed(＝recovered) ｜ deleted`。無孤兒狀態。
⚠️ `checkouts/delete` 的「主動刪除」路徑：現行 admin 無單筆刪除介面（G-3 明文不可手動刪）；歷史上銷售渠道 app 可經已落日的 Checkout API 刪自己建的 checkout，現行是否仍有主動刪除入口**官方未明文，待實測**。我方裁定：只實作「3 個月自動 purge」一條刪除路徑。

### B.3 Abandonment 相關 enum（值域窮舉）

| enum | 全部值 |
|---|---|
| `AbandonmentAbandonmentType`（＝`abandonmentType`／`mostRecentStep`） | `BROWSE`、`CART`、`CHECKOUT`（G-13a） |
| `AbandonmentEmailState` | `NOT_SENT`、`SCHEDULED`、`SENT`（G-13b）；轉移：NOT_SENT→SCHEDULED（排程）→SENT（寄出）；NOT_SENT→SENT（手動立即寄）；mutation `abandonmentEmailStateUpdate` 可改 |

### B.4 結帳期庫存 hold 子狀態機

| 狀態 | 轉移 | 官方原文依據 |
|---|---|---|
| `not_held` | buyer 走過 checkout 各步驟：每步**檢查**庫存但不 hold | 官方轉述：顧客每完成結帳的任一步驟，購物車都會與商店庫存量比對一次（G-5） |
| `held` | **提交付款資訊那一刻**才 hold | 「Inventory is held only when the customer submits their payment information」（G-5） |
| `released` | 付款失敗 → 釋放，直到 buyer 再回到付款步驟 | 官方轉述：付款失敗即釋放 hold，直到顧客再次進入付款方式頁才重新保留（G-5） |
| `committed` | 付款成功（＝checkout 路徑的「訂單成立」同刻）→ 永久扣減 | commit 的一般化觸發＝**訂單成立**（02 B.1）；非 checkout 路徑的分支見 C.7-3 |

⚠️ hold 的**確切時長**官方 help 未載明數字；Shopify 工程 blog（官方，2026）描述為「付款開始時保留數分鐘」，第三方轉述為約 10 分鐘窗口——時長不得寫成規格事實（openQuestion）。

### B.5 挽回信排程狀態（設定層）

後台 Settings→Checkout 的舊版「未完成結帳作業電子郵件」與新版 Marketing automation 並存（新版為建議路徑，G-3、G-15）。自動化寄信延遲可設 **1–24 小時**區間內的選項；建立**第二個**棄單自動化時預設 **10 小時**且僅寄給**已訂閱行銷**的顧客（G-15）。舊版設定頁 radio 實測值＝1／6／10（建議）／24 小時（倉庫 24 §5 實測，與 help 的 1–24 區間相容）。

### B.6 SubscriptionContract 狀態機（訂閱契約，checkout 下游）

`SubscriptionContractSubscriptionStatus` 值域（**窮舉，現行五值**，G-26）：

| 狀態 | 官方語義 | 進入轉移 |
|---|---|---|
| `ACTIVE` | 契約照政策持續執行中 | checkout 完成建約即 ACTIVE；或 `subscriptionContractActivate`（自 PAUSED／FAILED 恢復） |
| `PAUSED` | 暫停、預期未來恢復 | `subscriptionContractPause`；dunning 終局動作之一（G-30） |
| `CANCELLED` | 因**非預期的顧客動作**終止（終態） | `subscriptionContractCancel`；dunning 終局動作之一 |
| `EXPIRED` | 照**預期**走完——所有 billing／delivery cycle 已執行完畢（終態） | 走完約定週期數；`subscriptionContractExpire` |
| `FAILED` | 「billing 失敗且**不再預期有後續 billing attempt**」而終止 | `subscriptionContractFail`；dunning 重試耗盡後由 app 判定 |

- 🔴 **`STALE` 已於 API 2024-01 移除**（G-27）：既有 STALE 契約讀回為 CANCELLED，不可再寫入。任何把 STALE 排進 enum 的 schema 都是抄舊文檔——我方 enum 只做五值。
- **契約轉 FAILED 不是平台自動判的**：billing attempt 失敗只發 `SUBSCRIPTION_BILLING_ATTEMPTS_FAILURE`（Flow trigger 同名，G-33），**重試（dunning）策略由訂閱 app 自定**。官方 Shopify Subscriptions app 的可設參數（G-30）：重試次數、重試間隔天數、全部重試失敗後的終局動作（值域窮舉：`skip`／`pause`／`cancel`，各情形皆寄顧客通知）；**付款失敗與庫存不足兩類失敗各自獨立可設**。⚠️ 重試次數／間隔的上下限值官方未明文，待實測。
- `SUBSCRIPTION_BILLING_ATTEMPTS_CHALLENGED`＝付款被 3DS 類驗證挑戰攔下，需顧客介入完成驗證後才能繼續（G-33）。
- 顧客層推導：`Customer.productSubscriberStatus` 六值（08 §B.4 的引用處，G-28a）由該顧客**全部契約狀態**推導——`ACTIVE`（至少一張 ACTIVE）／`PAUSED`（至少一張 PAUSED 且無 ACTIVE）／`CANCELLED`／`EXPIRED`／`FAILED`（最後一張契約落在該終態且無 ACTIVE/PAUSED）／`NEVER_SUBSCRIBED`（從未有契約）。

---

## C. 業務規則與不變量

### C.1 行合併規則（line merging）——add.js 語義

加入品項時，與既有行**合併**（數量相加為新總量）的條件：`variant_id` 相同**且** `properties` 相同**且** `selling_plan` 相同**且**價格相同（自動折扣可使同 variant 價格不同）。官方轉述：同一品項若價格、properties 或 selling plan 任一不同，就會被拆成各自獨立的行（G-1）。⚠️ `parent_id`（bundle 組件）納入合併鍵屬合理推斷（文檔在請求參數列出 parent_id，但 split 條件原文未點名它）——標注待驗證。

**推論不變量**：一個 cart 可有多行同 `variant_id`；因此**行的唯一識別是 `key` 不是 `variant_id`**；用 variant_id 操作 update/change 會誤中多行之一，官方建議一律用 key（G-1）。

### C.2 Ajax Cart API 行為規則（值域與錯誤碼窮舉）

| endpoint | method | 行為要點 |
|---|---|---|
| `/cart/add.js` | POST | 多品項一次加入；超過庫存→**加到可用上限**並回錯誤；全售罄→不加入。錯誤格式 `{status:422, message:"Cart Error", description:"..."}` |
| `/cart.js` | GET | 回全 cart JSON |
| `/cart/update.js` | POST | `updates{key或variant_id: qty}`／`updates[陣列]`；`note`；`attributes`；`discount`（逗號分隔多碼；空字串＝清除全部折扣碼）。🔴 **update.js 不驗證已在 cart 內品項的數量**——可加超過庫存的量（G-1 原文 Caution） |
| `/cart/change.js` | POST | 一次只能改**一行**；以 `id`（key／variant_id）或 `line`（1-based 序號）定位；qty=0＝移除。**properties 整包覆寫**（既有鍵值全部清掉）；且 properties 一旦有值**不可再設回空物件**。改 `selling_plan` 時**只能用 `line` 定位**且應帶 `quantity`（缺省視為 1）；`selling_plan: null`＝移除 selling plan。錯誤：`{status:"bad_request", message:"no valid id or line parameter"}`（HTTP 400） |
| `/cart/clear.js` | POST | 全部行數量歸零；**不清除 note 與 attributes**（G-1） |
| `/cart/prepare_shipping_rates.json` | POST | 以目的地參數啟動運費試算，回 `null` |
| `/cart/async_shipping_rates.json` | GET | 未算完回 `null`；算完回 `shipping_rates[]`（name/price/source/delivery_days…） |
| `/cart/shipping_rates.json` | GET | 同步版，**受 throttle**，官方建議用前兩者 |

HTTP 狀態碼全集：200 成功／400 參數錯誤（含 `sections_url` 不以 `/` 開頭）／404 variant 不存在（update.js）／422 Cart Error（庫存不足、售罄）（G-1）。

**Bundled section rendering**：add/change/clear/update 可帶 `sections`（最多 **5** 個 section id）＋`sections_url`；渲染失敗的 section 回 `null`，**不影響 API 本體的成敗**（G-1）。

### C.3 私有欄位規約

- line item property 鍵以 `_` 開頭＝私有：結帳頁不顯示、admin 訂單詳情可見（G-1）。
- cart attribute 鍵以 `__` 開頭＝私有：Liquid `cart.attributes` 與 Ajax API 都拿不到、不影響頁面渲染（可快取）（G-1）。

### C.4 上限值總表（落 `config/limits.yml`）

| 項目 | 值 | 來源 |
|---|---|---|
| cart 行數上限 | **500** | G-6、G-7 |
| cartLinesAdd 單次上限 | **250** 行 | G-6 |
| cart attributes 上限 | **250** 個 | G-8 |
| add-to-cart limit（每 variant 每單） | 商家可設；<250 筆銷售預設建議 **50**；≥250 筆依訂單資料計算（含高量單餘裕），定期更新 | G-9 |
| add-to-cart limit 例外（**窮舉**） | POS 建立的 cart／draft order／B2B catalog 有 quantity rules／B2B 顧客登入／未開啟庫存追蹤／開啟「缺貨繼續銷售」 | G-9 |
| bundled sections | 單次 **5** 個 | G-1 |
| validation functions 啟用數 | 每店 **25** 個 | G-10 |
| cart transform | 每 app 每店 **1** 個 | G-16 |
| 折扣碼／checkout | 同一訂單最多 **5** 個商品／訂單折扣碼＋**1** 個運費折扣碼（需開 combinations） | G-17 |
| 小費 presets | 最多 **3** 個百分比 preset＋自訂欄；上限 **USD $1,000**（preset 與自訂皆是）且不得超過訂單總額 **100%**；基數＝**稅前、運費前小計** | G-18 |
| checkout 設定生效延遲 | 最長 **30 秒** | G-19 |
| 棄單判定 | 留 email 後 **10 分鐘**未完成 | G-3 |
| 棄單保存期 | **3 個月**自動刪除 | G-3 |
| Storefront cart 過期 | 未使用 **30 天** | G-7 |
| 挽回信延遲 | 1–24 小時；第二個自動化預設 10 小時 | G-15 |

### C.5 Checkout 表單欄位值域（窮舉，G-19）

| 欄位 | 全部選項 | 聯動規則 |
|---|---|---|
| 顧客聯絡方式 | `Phone number or email` ／ `Email only` | 開啟「要求登入」⇒ **強制 email-only** 且停用部分加速結帳（如 Apple Pay） |
| 姓名 | `Only require last name` ／ `Require first and last name` | — |
| 公司名稱 | `Don't include` ／ `Optional` ／ `Required` | Required ⇒ 部分加速結帳不顯示 |
| VAT 編號 | `Don't include` ／ `Optional`（**無 Required**） | EU/UK 跨境反向課稅邏輯 |
| 地址第 2 行 | `Don't include` ／ `Optional` ／ `Required` | Required 或 Don't include 都可能讓部分顧客無法完成結帳（官方警語） |
| 運送地址電話 | `Don't include` ／ `Optional` ／ `Required` | 只在有運送步驟時生效 |
| email 行銷同意 | 顯示位置：checkout／sign-in／both；預勾地區：`Shopify-recommended` 或自選清單 | — |
| SMS 行銷同意 | 可提供 opt-in；**不可預勾**（合規） | — |
| B2B 例外 | B2B checkout 不受顧客資訊必填設定約束 | — |

### C.6 金額計算與 rounding

- Ajax API 金額全部是**整數**（本尊尺度見下條）；`line_price = price × quantity`。**cart 階段 total 公式（完整項次，無省略）**：`total_price = items_subtotal_price − Σ(cart 級折扣分攤)`——cart 階段**不含**運費、外加稅、小費、關稅（皆為 checkout 階段才出現的項次；cart 頁本尊固定文案即「taxes 與 shipping 於 checkout 計算」）；稅內含定價（taxes_included）時稅已隱含於 price、不另列項。**checkout 階段完整公式**：`total = (line items 小計 − 折扣) ＋ 運費 ＋ 外加稅 ＋ 關稅 ＋ 小費`——逐項定義與 rounding 以 `docs/specs/15` **F2 Calculator 的公式編號為唯一權威**，本檔只鎖定**項次全集**不重複維護細節；AbandonedCheckout 的 `totalLineItemsPriceSet`→`totalDiscountSet`→`totalTaxSet`→`totalDutiesSet`→`totalPriceSet` 欄位族即此組成的快照證據（G-4）。各 Ajax 欄位為快照值非公式輸出。
- 🔴 **我方 cart JSON 尺度宣告（鐵律 3：格式與參數任一未宣告一律 reject，本條即宣告）**：我方前台 cart API 所有金額欄位＝**內部儲存尺度直通，一律 ×100 不看幣別**（`Money::Storage`；欄位後綴 `_cents`；回應必附 `currency`）。顯示轉換由前台 money formatter 依 jurisdiction pack 的 `currency_format` 處理（JPY：`148000` → 顯示 `¥1,480`）；此值**不得**直送 PSP／物流（65 §C 型別已擋）。本尊佐證三則同向：①Ajax 官方文檔只寫 presentment 幣別、**未寫 exponent 處理**；②社群實測 JPY 在 cart.js 回傳 ×100（¥8,900 → `890000`，G-26a，非官方）；③09 §C.3 已證實 carrier 回呼一律 ×100——皆指向本尊內部「一律 ×100」。⚠️ Ajax 的 zero-decimal 尺度官方未明文，待測試店以 JPY presentment 實測定案；**無論實測結果為何，我方對外宣告以本條為準**。
- 小費：`tip = round(subtotal_pre_tax_pre_shipping × preset%)`，上限 min(USD $1,000, 100% 訂單總額)（G-18）。rounding 到幣別最小顯示位；官方未載明 rounding 模式（⚠️ openQuestion，我方依鐵律 3 用 integer cents 計算後取半銀行家或四捨五入須自定並全域一致）。
- deferred purchase 的 `checkoutChargeAmount`＝結帳當下應收（訂金或 0～全額）；餘額後收（G-8、G-12）。
- 多幣別：AbandonedCheckout 金額全部 MoneyBag（shop ＋ presentment 雙值）（G-4）。

### C.7 併發要害

1. **update.js 不驗庫存**（G-1）——server 端結帳前必須全量重驗，不能信任 cart 數量。
2. 同 token 多分頁併發加購——行級 upsert＋唯一鍵防重複行（倉庫 15-F1 已定）。
3. 庫存 hold 只發生在付款提交（G-5）⇒ cart 階段永不扣庫存；超賣防線＝**「訂單成立」那一刻的原子扣減**。checkout 路徑下訂單成立與付款成功同刻（D.3），但**手動付款（COD／bank deposit，05 C.12：下單即成單、金流 PENDING）與 B2B payment terms（04 B.4）、admin orderCreate 的 PENDING 單（04 C.2）都是「訂單已成立、付款未成功」**，庫存照樣要 commit——02 B.1 的觸發本來就是「訂單成立」；deferred 的 `ON_FULFILLMENT` 例外見 D.7-5。寫成「付款成功才扣」會漏掉 COD 與 Net terms 訂單的庫存占用。
4. 挽回信寄出前要**重查**不寄條件（品項是否恢復庫存、是否已完購）——條件是時變的。
5. `key` 會隨行特徵變動（G-1）⇒ 前端持有的 key 可能過期，change.js 應以最新 cart.js 回應的 key 為準。

### C.8 挽回信不寄條件（窮舉，G-3）

①寄出前已完成購買；②付款處理錯誤型棄單；③商店無法配送到該地址；④只留電話沒留 email；⑤所有品項皆無庫存；⑥全部品項免費且無運費。另：疑似盜卡測試／bot 的結帳**根本不建**棄單（G-14）。

### C.9 Functions 業務語義

**Cart & checkout validation**（G-10）：server-side 驗證，失敗＝**阻擋**結帳前進（非警告）。錯誤顯示於 checkout（含 Shop Pay/PayPal/Google Pay/Apple Pay 等 express 路徑）、cart 頁模板、Storefront API Cart 物件。輸出＝`ValidationAddOperation{message, target}`；target 值域（窮舉）：`$.cart`、`$.cart.buyerIdentity.email`、`$.cart.buyerIdentity.phone`、`$.cart.deliveryGroups[0].deliveryAddress.{address1,address2,city,company,countryCode,firstName,lastName,phone,provinceCode,zip}`、`$.cart.billingAddress.{同上}`、`$.cart.poNumber`、`$.cart.localizedFields.{key}`。**不支援**：Create Order API、Order Edit、POS、pre-order/TBYB、subscriptions。輸入含 buyer journey 階段（cart 互動／checkout 互動／checkout 完成），可做「只在完成時驗」。UI extension 側的 `useBuyerJourneyIntercept` 需商家授予 `block_progress`；未授權時 `behavior:'block'` 被降級為 `allow`（G-20）。

**Cart transform**（G-16）：三種操作（窮舉）——`lineExpand`（一行展開成組件）、`linesMerge`（多行合併成 bundle）、`lineUpdate`（改單行價格／標題／圖片）。約束：**不能改數量**；**行上有 selling plan 時三種操作一律被 Shopify 拒絕**；expand/merge 限 dev store 或 Plus；每 app 每店 1 個。定價：`FixedPricePerUnit` 或百分比調整；先套的折扣分攤被保留。

### C.10 Express checkout（dynamic checkout buttons，G-21）

- 兩型：**unbranded**（"Buy it now"，跳過 cart 直進 Shopify Checkout；可調色與字體）與 **branded**（錢包 logo，走該加速付款流程；不可自訂樣式）。
- branded 錢包值域（窮舉）：Shop Pay、Apple Pay、Google Pay、PayPal、Amazon Pay、Venmo。
- 顯示哪顆按鈕由系統動態決定，因素：商家付款設定、Shop Promise（優先 Shop Pay）、買家瀏覽器、裝置、付款歷史。商家只能顯示／隱藏，不能自訂排序。
- 限制：dynamic checkout button 一次只能買**單一 variant**（不能同時大 T 恤＋小 T 恤）；未啟用任何第三方錢包時只顯示 unbranded。
- Shop Pay 流程（G-22）：首次結帳 opt-in 儲存 email＋付款＋地址 → 之後任何 Shopify 店輸入 email → SMS 六碼驗證 → 全欄位預填一鍵付款。

### C.11 Cart permalink（G-23）

格式 `https://{store}/cart/{variant_id}:{qty}[,{variant_id}:{qty}...]`；query 參數：`discount=`（折扣碼）、`payment=shop_pay`（直達 Shop Pay）、`storefront=true`（落在 cart 頁而非直進 checkout）、`channel=buy_button`（歸因）；另支援預填 email／地址與 line item properties（參數名文檔未逐一載明，⚠️）。預設**直接落地 checkout**；同一連結可重複使用、每個顧客各建新 checkout。

---

## D. 關鍵流程

### D.1 加入購物車（Ajax）

1. buyer 按「加入購物車」→ 前端 POST `/cart/add.js`（items＋可選 sections）。
2. 系統：庫存粗檢——足量→建行或併行（C.1 合併鍵）；不足→**加到可上限**並回 422 description；售罄→不加入回 422。
3. add-to-cart limit 生效（每 variant 每單上限，例外見 C.4）。
4. 回應含最新行（含 key）＋（可選）重渲染的 sections HTML。
5. webhook：`carts/create`（首次）／`carts/update`（其後）——**僅線上商店 cart** 支援（G-24）。

### D.2 Cart → Checkout 過渡

1. buyer 按 Check out（或 cart permalink／dynamic checkout button 直達）。
2. 系統建 checkout（URL `/checkouts/...`），發 `checkouts/create`；cart 品項、note、attributes、折扣碼帶入。
3. one-page 版式（預設；可切 three-page，兩者收集**相同**欄位、共用同一套自訂與分析）（G-25）。左欄順序：Express 按鈕列 → Contact → Delivery → Shipping method → Payment（含 billing）→ Pay now。
4. buyer 每完成一步：欄位驗證＋**庫存檢查**（不 hold）；庫存不足→錯誤訊息（G-5）；發 `checkouts/update`。

### D.3 完成付款（含失敗分支）

1. buyer 填完付款→ 按 Pay now 提交付款資訊 → **此刻庫存 hold**（G-5）。
2. 付款成功 → 訂單成立（`orders/create`）、`completedAt` 寫入、cart 刪除、庫存 commit（此路徑下付款成功＝訂單成立同刻；commit 的一般化觸發是「訂單成立」，非 checkout 路徑的分支見 C.7-3）。
3. 付款失敗 → **hold 釋放**；buyer 回到付款步驟時重新 hold（G-5）；checkout 留在 in_progress。
4. buyer 離開且已留 email → 10 分鐘後轉 abandoned（D.4）。

### D.4 棄單建立與挽回

1. 留 email 後 10 分鐘未完成 → 建 AbandonedCheckout（快照品項與金額；bot／盜卡測試不建）。
2. 自動化（Flow trigger `Customer abandons checkout`）或舊版設定觸發排程：`emailState: NOT_SENT → SCHEDULED`。
3. 到點寄信前**重查**不寄條件（C.8）；通過→寄出（`SENT`，`emailSentAt` 寫入），信含 `abandonedCheckoutUrl`。
4. buyer 點連結恢復結帳（原品項＋價格快照）或自行完購 → `completedAt` 寫入，報表推導為 **recovered**（completed 的子集，非獨立狀態，B.2）。
5. 3 個月未完成 → 自動刪除（`checkouts/delete`）。
6. 商家亦可在 admin 棄單列表**手動寄**單筆挽回信（G-3）。

### D.5 Express checkout 分流

1. 商品頁／cart 頁／checkout 頂部顯示 dynamic checkout buttons（顯示邏輯 C.10）。
2. unbranded：跳過 cart 直建 checkout（單 variant）。
3. branded：喚起錢包 → 錢包回傳地址＋付款資訊 → 跳到確認；validation functions 的錯誤在 express 路徑同樣阻擋（G-10）。
4. Shop Pay：email 辨識→SMS 六碼→預填→一鍵付款（G-22）。

### D.6 Deferred purchase（預購／TBYB）結帳

1. 行上有 selling plan → checkout 顯示付款拆分：當下收 `checkoutChargeAmount`（訂金或 0），餘額後收（G-8、G-12）。
2. 付款方式**vault** 成 `PaymentMandate`——「儲存顧客付款方式，商家不必再聯絡顧客即可收餘款」（G-12）。
3. 餘額觸發：`EXACT_TIME`（指定日）或 `TIME_AFTER_CHECKOUT`（結帳後 X 天）；出貨政策：`ASAP`／`EXACT_TIME`／`UNKNOWN`；庫存 commit：`ON_SALE`（建單時）／`ON_FULFILLMENT`（履行時）（G-12）。
4. 注意互斥：有 selling plan 的行不能被 cart transform 動（C.9）；小費不支援含 selling plan 的 cart（G-18）；validation functions 不支援 pre-order/TBYB 面（G-10）。
5. 餘額後收的承載物件＝SubscriptionContract 家族（A.7）；排程與履約鏈條見 D.7。

### D.7 訂閱後收與履約排程（anchor → billing cycle → SCHEDULED FulfillmentOrder）

補 09 §B.1-2「訂閱單＝下一 anchor 日」一句話背後的完整鏈條（G-31、G-32）：

1. **anchor 決定週期節律**：selling plan 的 recurring billing／delivery policy 各可設 anchor（每週某日／每月某日等）；`cutoff`＝anchor 前的緩衝窗；`preAnchorBehavior` 兩值（**窮舉**，G-31）：`ASAP`＝下單即可出（落在 cutoff 窗內則改到下一 anchor）；`NEXT`＝一律排下一 anchor（落在 cutoff 窗內則**跳過**下一個、排到再下一個）。
2. **billing cycle 到點 → app 發起 billing attempt**（帶必填 `idempotencyKey`；`originTime` 可校正計費時點、官方明文用途是防 fulfillment 被推遲到下一 anchor）。成功 → 生成訂單；失敗 → dunning（B.6）。cycle 可被 skip（billing＋delivery 一起跳過）、可單週期編輯（A.7）。
3. **訂單的 FulfillmentOrder 排程**：官方明文「fulfillment order 的排程履約日由 selling plan 的 delivery anchor＋後續 billing attempt 的 originTime 決定」（G-32）。pre-paid 訂閱＝**一張訂單＋N 個 `SCHEDULED` 狀態 FulfillmentOrder**（各帶 `fulfillAt`＝各期 anchor 日）；全部 FO 皆 SCHEDULED 時訂單 displayFulfillmentStatus＝SCHEDULED（G-32）。
4. **fulfillAt 到點**：官方明文「到達 fulfillAt 時**庫存 commit**、FO 轉 `OPEN`」成為可履約；SCHEDULED FO **不參與自動履約**（唯一例外：首個 FO 以 OPEN 建立則可自動履約）；改期走 `fulfillmentOrderReschedule`（G-32）。
5. **庫存 commit 落點（接 02 章 8 態模型）**：selling plan inventory policy 兩值（G-12）——`ON_SALE`＝建單即 `available→committed`（與 02 B.1「訂單成立」觸發一致）；`ON_FULFILLMENT`＝建單時**不進 committed**，等 fulfillAt 到點 FO 轉 OPEN 那一刻才 `available→committed`（G-32 的 pre-paid 行為即此形態）。⚠️ `ON_SALE` 與 SCHEDULED FO 並存時（收全款但延後出貨的預購）兩者交集的 committed 時點官方未明文，待實測。

---

## E. 跨模組耦合

### E.1 Webhook topics（本域相關，值域窮舉，G-24）

| topic | 觸發 | 備註 |
|---|---|---|
| `CARTS_CREATE` | 線上商店 cart 建立 | 「其他型態的 cart 不支援」；scope `read_orders` |
| `CARTS_UPDATE` | 線上商店 cart 更新 | 同上 |
| `CHECKOUTS_CREATE` | checkout 建立 | scope `read_orders` |
| `CHECKOUTS_UPDATE` | checkout 更新 | 同上 |
| `CHECKOUTS_DELETE` | checkout 刪除 | 同上 |
| `ORDERS_CREATE` | 訂單成立 | scope `read_orders` 或 `read_marketplace_orders` |

無「abandoned checkout」專屬 webhook topic——棄單偵測靠 checkouts 系列＋Admin API 查詢（G-24）。

**訂閱子域 topics（值域窮舉，15 個；註冊表歸 13 章 §A.3，本表補觸發語義，G-24、G-26–G-33）**：

| topic | 觸發語義 |
|---|---|
| `SUBSCRIPTION_CONTRACTS_CREATE` ／ `_UPDATE` | 契約建立（checkout 完成建約或 `subscriptionContractAtomicCreate`）／契約欄位變更 |
| `SUBSCRIPTION_CONTRACTS_ACTIVATE` ／ `_PAUSE` ／ `_CANCEL` ／ `_EXPIRE` ／ `_FAIL` | `status` 轉入 B.6 對應狀態那一刻各發一次 |
| `SUBSCRIPTION_BILLING_ATTEMPTS_SUCCESS` | billing attempt 成功（該期訂單已生成） |
| `SUBSCRIPTION_BILLING_ATTEMPTS_FAILURE` | attempt 失敗；是否重試由 app 的 dunning 策略決定，**平台不自動重試**（B.6） |
| `SUBSCRIPTION_BILLING_ATTEMPTS_CHALLENGED` | 付款被要求顧客驗證（3DS challenge），須顧客介入（G-33） |
| `SUBSCRIPTION_BILLING_CYCLES_SKIP` ／ `_UNSKIP` | 單一 billing cycle 的 `skipped` 旗標翻轉（A.7） |
| `SUBSCRIPTION_BILLING_CYCLE_EDITS_CREATE` ／ `_UPDATE` ／ `_DELETE` | 單週期編輯 commit／再修改／刪除（A.7 草稿流程） |

### E.2 依賴方向

- **消費（上游）**：商品／變體（價格、庫存追蹤旗標、quantity rules）；折扣（碼驗證、combinations）；運送（zones/rates→deliveryGroups）；Markets（presentment 幣別、地址格式）；顧客（buyerIdentity、行銷同意）。
- **產出（下游）**：訂單（checkout completed→order）；庫存（hold/release/commit 事件）；行銷自動化（Flow trigger `Customer abandons checkout`，掛 Customer＋Abandonment 物件）；分析（conversion funnel：added to cart → reached checkout → converted）；通知（order confirmation；abandoned checkout email）。
- **擴充點**：cart transform（bundle 呈現）→ 影響行結構與價格；validation functions → 阻擋 gate；delivery/payment customization functions（各限 25 個啟用，屬運送／金流域）；checkout UI extensions（buyer journey intercept）。

---

## F. 落地對應

### F.1 對應倉庫文件

| 本章節 | 倉庫既有 |
|---|---|
| A.2/A.3、C.1–C.4、D.1 | `docs/specs/15` F1（cart）、`docs/research/04` §1 |
| C.5、D.2/D.3 | `docs/specs/15` F3／F3.2、`docs/research/24` §5 |
| C.6 | `docs/specs/15` F2（Calculator）＋ `docs/specs/65`（金額契約） |
| B.2、C.8、D.4 | `docs/specs/15` F7、`docs/research/04` §3 |
| C.9 | `docs/research/24` §6.4（Functions 掛載） |
| C.10、D.5 | `docs/research/04` §1.4/§1.5 |
| E.1 | `docs/research/28`（API 契約）outbox 事件命名參照 |
| A.7、B.6、D.7 | 倉庫**無既有文件**（訂閱子域首次成文）；下游引用：08 §B.4（productSubscriberStatus）、09 §B.1-2（anchor／SCHEDULED FO）、13 §A.3（webhook 註冊表）、02 §B.1（commit 落點） |

### F.2 本尊 vs 我方裁定（逐條）

| # | 本尊原貌 | 我方裁定 | 出處 |
|---|---|---|---|
| 1 | Ajax API 金額＝整數；官方未明文 zero-decimal 尺度，社群實測＋09 §C.3 佐證本尊一律 ×100（C.6 第二條）；GraphQL 走 MoneyV2/MoneyBag | **內部一律 integer cents ×100 不看幣別**；**我方 cart JSON 對外亦明文宣告 ×100（`_cents` 後綴＋`currency`，C.6 第二條）**；序列化層才轉 MoneyV2/MoneyBag；送 PSP 依 pack 宣告格式 | 鐵律 3、`docs/specs/65`、C.6 |
| 2 | Storefront cart 30 天過期 | 我方 cart 90 天未動 purge（15-F1）——**比本尊寬**，需在 F1 標注差異或改為 30 天對齊（建議對齊） | G-7 vs 15-F1 |
| 3 | cart 上限 500 行；無每行數量官方上限（僅 add-to-cart limit） | 我方防呆：每行 999、行數 100（**比本尊嚴**）＋ `cart_item_limit` 官方概念並存 | G-6/G-9 vs 15-F1 |
| 4 | add-to-cart limit 預設建議 50、≥250 銷售後動態計算 | `limits.cart.item_limit_suggested: 50`；動態計算不做（P2） | G-9 |
| 5 | 庫存 hold 在付款提交時；時長未公開；commit 的一般化觸發＝訂單成立（02 B.1） | 我方：cart/checkout 全程軟檢查、**訂單成立時原子扣庫存**——checkout 路徑＝付款成功同刻；COD／bank deposit／payment terms 單「成單即 commit、金流 PENDING」（C.7-3）；**不做 hold 機制**，以原子扣減防超賣；15-F5 的「付款成功才扣」措辭需同步修正為「訂單成立」 | G-5 vs 15-F5、02 B.1 |
| 6 | 挽回信自動化 1–24h；第二自動化預設 10h 僅訂閱者 | `abandoned{enabled, audience, delay_hours}`，radio 1/6/10/24（對齊實測） | G-15、24 §5 |
| 7 | 稅務欄位（VAT、taxLines、taxesIncluded）內建於 checkout | 稅務憑證走 **jurisdiction pack**（HK 基準：無銷售稅）；核心只發稅務事件 | 鐵律 11 |
| 8 | express checkout＝Shop Pay＋六錢包，平台級跨店 | 我方不做跨店錢包；等價體驗可用 Stripe Link 或先不做 | 04 §1.5 |
| 9 | Ajax 錯誤格式 `{status, message, description}`（422/404/400） | 前台 cart API 對齊 Ajax 慣例（15-F1）；admin API 一律 `userErrors{field,message,code}`、code 必填（**我方加嚴**） | 鐵律 4 |
| 10 | checkout.liquid 已落日；終局＝UI extensions＋Branding API＋Functions | 直接復刻終局形態，不做 checkout.liquid | 24 §6.4 |
| 11 | cart transform／validation functions＝Wasm functions | 復刻為同步 Ruby service objects，模仿 input/output JSON 合約 | 24 §6.4 |
| 12 | 訂閱／預購／TBYB＝selling plans 全家桶；後收與續期由 SubscriptionContract／BillingCycle／BillingAttempt 承載（A.7／B.6／D.7） | 未排入 M0–M6 主線；schema 預留**以 A.7 模型為藍本**：`selling_plan` 引用欄位、`checkoutChargeAmount` 語義、契約 status 五值 enum（**無 STALE**，G-27）、`next_billing_date`、attempt 層 `idempotency_key`；cart 行合併鍵勿漏 selling_plan；**實作 D.6 餘額後收時不得自創與本尊不同構的機制** | 本章 A.7／B.6／D.7、C.1 |
| 13 | 棄單 10 分鐘判定、3 個月刪除 | 相同（15-F7 已對齊）；另補「bot/盜卡測試不建棄單」到 F7 | G-3、G-14 |
| 14 | 取貨點（pickup point）非官方 checkout 主線概念 | 我方 `delivery_method_type` 三分法＋超商快照欄位（TW pack 素材） | 15-F3.1 |

### F.3 開發驗收要點

1. **行合併鍵測試**：同 variant＋不同 properties／selling_plan／價格 → 必須分行；相同 → 必須併行且數量相加。key 隨特徵變動的行為要有測試。
2. **update.js 不驗庫存**的對齊決策要明文：我方 server 端結帳 gate 全量重驗（15-F3 第 4 點），cart 寫入 API 是否仿本尊放行需在 PR 標注假設。
3. **limits.yml 條目**：本章 C.4 表逐條落檔並帶來源註釋；缺一即 🔴。
4. **狀態機測試**：B.2 全轉移覆蓋；特別是 abandoned→completed（recovered）與付款失敗→hold 釋放→重付。
5. **挽回信 job**：寄前重查 C.8 六條件；audience／delay 可配置；3 個月 purge job。
6. **併發測試**：超賣（**訂單成立**原子扣減 <!-- 2026-08-17 更正：原寫「付款成功」，同 D-32 -->）、同 token 併發加購 upsert、棄單 job 與完購競態（先到先贏，冪等）。
7. **金額**：cart→checkout→order 全程同一 Calculator；小費基數＝稅前運費前小計；zero-decimal 幣別進測試矩陣（65 §H）。
8. **validation gate**：仿 validation function 語義——錯誤帶 target 路徑、cart 頁與 checkout 都要能顯示、express 路徑同樣阻擋。
9. **訂閱 schema 預留（僅預留不實作）**：遷移檔含 `selling_plan` 引用欄位與契約／attempt 佔位設計（或明文推遲決議並記入 worklog Pending）；欄位命名與 enum 對照 A.7／B.6；預留 enum **不含 STALE**。
10. **cart JSON 尺度測試**：JPY／TWD／KRW fixture 下 cart API 回應必須是 ×100 值且帶 `currency`；顯示位數依 58 §G.3 的 `currency_format`——此測試即 100 倍事故的入口閘，掛進 65 §H 金額矩陣。
11. **checkout 狀態機落 enum**：儲存態只有 `open`／`completed`／`deleted` 三值；`abandoned_at` 為時戳欄位、`recovered` 為報表推導——測試需覆蓋「abandoned 後自行完購仍計 recovered」與「3 個月 purge 不誤刪已完成單」。

---

## G. 來源

| # | URL | 取證 |
|---|---|---|
| G-1 | https://shopify.dev/docs/api/ajax/reference/cart | 2026-08-14 |
| G-3 | https://help.shopify.com/en/manual/promoting-marketing/create-marketing/abandoned-checkouts | 2026-08-14 |
| G-4 | https://shopify.dev/docs/api/admin-graphql/latest/objects/AbandonedCheckout | 2026-08-14 |
| G-5 | https://help.shopify.com/en/manual/checkout-settings （Shopify Checkout 總覽：庫存檢查與 hold） | 2026-08-14 |
| G-6 | https://shopify.dev/docs/api/storefront/latest/mutations/cartlinesadd | 2026-08-14 |
| G-7 | https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/cart | 2026-08-14 |
| G-8 | https://shopify.dev/docs/api/storefront/latest/objects/Cart | 2026-08-14 |
| G-9 | https://help.shopify.com/en/manual/checkout-settings/add-to-cart-limit | 2026-08-14 |
| G-10 | https://shopify.dev/docs/api/functions/reference/cart-checkout-validation | 2026-08-14 |
| G-11 | https://shopify.dev/docs/apps/build/purchase-options | 2026-08-14 |
| G-12 | https://shopify.dev/docs/apps/build/purchase-options/deferred | 2026-08-14 |
| G-13 | https://shopify.dev/docs/api/admin-graphql/latest/objects/Abandonment | 2026-08-14 |
| G-13a | https://shopify.dev/docs/api/admin-graphql/latest/enums/AbandonmentAbandonmentType | 2026-08-14 |
| G-13b | https://shopify.dev/docs/api/admin-graphql/latest/enums/AbandonmentEmailState | 2026-08-14 |
| G-14 | https://help.shopify.com/en/manual/shopify-flow/reference/triggers/customer-abandons-checkout | 2026-08-14 |
| G-15 | https://help.shopify.com/en/manual/promoting-marketing/create-marketing/migrate-abandoned-checkout （＋abandoned-checkouts 自動化節） | 2026-08-14 |
| G-16 | https://shopify.dev/docs/api/functions/reference/cart-transform | 2026-08-14 |
| G-17 | https://help.shopify.com/en/manual/discounts/discount-combinations | 2026-08-14 |
| G-18 | https://help.shopify.com/en/manual/checkout-settings/tips | 2026-08-14 |
| G-19 | https://help.shopify.com/en/manual/checkout-settings/checkout-form-options | 2026-08-14 |
| G-20 | https://shopify.dev/docs/api/checkout-ui-extensions/latest/target-apis/checkout-apis/buyer-journey-api | 2026-08-14 |
| G-21 | https://help.shopify.com/en/manual/online-store/dynamic-checkout | 2026-08-14 |
| G-22 | https://help.shopify.com/en/manual/payments/shop-pay | 2026-08-14 |
| G-23 | https://help.shopify.com/en/manual/checkout-settings/cart-permalink | 2026-08-14 |
| G-24 | https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic | 2026-08-14 |
| G-25 | https://help.shopify.com/en/manual/checkout-settings/customize-checkout-configurations/one-page-checkout | 2026-08-14 |
| G-26 | https://shopify.dev/docs/api/admin-graphql/latest/enums/SubscriptionContractSubscriptionStatus | 2026-08-14 |
| G-26a | https://community.shopify.dev/t/clarification-on-cart-js-money-values-minor-vs-major-units-and-decimal-places-per-currency/32824 （社群，非官方；cart.js zero-decimal ×100 實例佐證） | 2026-08-14 |
| G-27 | https://shopify.dev/changelog/subscriptions-contracts-apis-deprecate-subscriptioncontract-stale-status （STALE 於 2024-01 移除、讀回 CANCELLED） | 2026-08-14 |
| G-28 | https://shopify.dev/docs/api/admin-graphql/latest/objects/SubscriptionContract ＋ …/objects/SubscriptionBillingAttempt | 2026-08-14 |
| G-28a | https://shopify.dev/docs/api/admin-graphql/latest/enums/CustomerProductSubscriberStatus | 2026-08-14 |
| G-29 | https://shopify.dev/docs/apps/build/purchase-options/subscriptions/billing-cycles ＋ …/mutations/subscriptionBillingCycleSkip | 2026-08-14 |
| G-30 | https://help.shopify.com/en/manual/products/purchase-options/subscriptions/shopify-subscriptions/manage-subscriptions/manage-app-settings （Billing attempts／dunning 設定：重試次數、間隔、終局 skip/pause/cancel） | 2026-08-14 |
| G-31 | https://shopify.dev/docs/apps/build/purchase-options/subscriptions/selling-plans （anchor／cutoff／preAnchorBehavior） | 2026-08-14 |
| G-32 | https://shopify.dev/docs/apps/build/purchase-options/subscriptions/fulfillments ＋ https://help.shopify.com/en/manual/fulfillment/fulfilling-orders/subscriptions-fulfillment （SCHEDULED FO／fulfillAt 到點 commit＋轉 OPEN） | 2026-08-14 |
| G-33 | https://help.shopify.com/en/manual/shopify-flow/reference/triggers/subscription-billing-attempt-failure ＋ …/subscription-billing-attempt-challenged | 2026-08-14 |
