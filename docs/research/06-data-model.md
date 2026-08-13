# 06 — 整合資料模型與狀態機總表

> 本篇把 01–05、09 的研究收斂成一張可實作的資料模型：核心 ER 圖、各狀態機、多租戶與金額處理原則。命名對齊 Shopify Admin GraphQL API，方便回查官方文件。

## 1. 多租戶原則（先於一切）

- **所有業務表帶 `shop_id`**，複合索引一律 `(shop_id, ...)` 開頭；應用層 middleware 強制注入租戶條件（或 Postgres RLS）。
- Shop 表本身承載：名稱、myshopify 子網域、自訂網域、store currency、時區、方案、feature flags。
- 金額欄位用**整數最小幣值單位**（cents）+ currency code；為未來多幣別預留 `presentment_*` 欄位（demo 可先只填 shop 幣別）。
- ID：bigint 自增即可；對外 API 可包裝成 `gid://` 風格全域 ID。

## 2. 商務核心 ER 圖

```mermaid
erDiagram
    SHOP ||--o{ PRODUCT : has
    PRODUCT ||--o{ PRODUCT_OPTION : "options (≤3)"
    PRODUCT_OPTION ||--o{ OPTION_VALUE : values
    PRODUCT ||--o{ PRODUCT_VARIANT : variants
    PRODUCT ||--o{ MEDIA : media
    PRODUCT_VARIANT ||--|| INVENTORY_ITEM : "1:1"
    INVENTORY_ITEM ||--o{ INVENTORY_LEVEL : "per location"
    LOCATION ||--o{ INVENTORY_LEVEL : holds
    INVENTORY_LEVEL ||--o{ INVENTORY_ADJUSTMENT : ledger
    COLLECTION }o--o{ PRODUCT : "manual join / smart rules"

    CUSTOMER ||--o{ CUSTOMER_ADDRESS : addresses
    CUSTOMER ||--o{ ORDER : places

    CHECKOUT ||--o| ORDER : "completes into"
    ORDER ||--o{ LINE_ITEM : contains
    LINE_ITEM }o--|| PRODUCT_VARIANT : references
    ORDER ||--o{ ORDER_TRANSACTION : "auth/capture/refund chain"
    ORDER ||--o{ FULFILLMENT_ORDER : "work units"
    FULFILLMENT_ORDER ||--o{ FULFILLMENT_ORDER_LINE_ITEM : "planned work"
    FULFILLMENT_ORDER ||--o| FULFILLMENT_ORDER : "replacement / remaining (self-ref)"
    FULFILLMENT_ORDER ||--o{ FULFILLMENT_HOLD : "≤10 active"
    FULFILLMENT_ORDER ||--o{ FULFILLMENT : shipments
    FULFILLMENT ||--o{ FULFILLMENT_LINE_ITEM : "shipped units"
    FULFILLMENT_LINE_ITEM ||--o{ RETURN_LINE_ITEM : "returnable after delivered"
    ORDER ||--o{ REFUND : refunds
    ORDER ||--o{ RETURN : returns
    RETURN ||--o{ RETURN_LINE_ITEM : "returned units"
    RETURN ||--o{ EXCHANGE_LINE_ITEM : "exchange items"
    RETURN ||--o{ REVERSE_FULFILLMENT_ORDER : "inbound work units"
    REVERSE_FULFILLMENT_ORDER ||--o{ REVERSE_DELIVERY : "labels + tracking"
    ORDER_LINE_ITEM ||--|| RETURN_POLICY_SNAPSHOT : "purchase-time snapshot"
    ORDER ||--o{ EVENT : timeline
    DISCOUNT ||--o{ DISCOUNT_APPLICATION : "applied to"
    ORDER ||--o{ DISCOUNT_APPLICATION : has
    DRAFT_ORDER ||--o| ORDER : "converts to"
```

要點：

- **LineItem 快照原則**：下單當下把 title、variant title、SKU、單價、稅率複製進 line item——商品之後改名改價不影響歷史訂單。
- **OrderTransaction 鏈**：authorization → capture(parent) → refund(parent)；金流所有動作都是一筆 transaction，不直接改 order 欄位；order 的 financial status 由 transactions 推導。
- **FulfillmentOrder**：訂單成立時按出貨地點拆出 1..n 個 FulfillmentOrder（demo 單地點 = 1 個），出貨動作掛在它上面——這是 Shopify 現行模型，先進 schema 未來不用重構。**自參照外鍵 `parent_fulfillment_order_id` 為必要欄位**：`fulfillmentOrderCancel` 會產生「替代單」、部分 hold／move 會產生「剩餘單」，沒有這條關聯，剩餘品項會憑空消失（規格見 16-F3.2）。
  <!-- 依 46a:236、46a:354、46a:358–366 補寫，原文：`fulfillmentOrderCancel`＝「Cancels order and creates replacement for remaining work」；hold/move 回傳 `remainingFulfillmentOrder` -->
- **🔴 RETURN_LINE_ITEM 的外鍵指向 FULFILLMENT_LINE_ITEM，不是 ORDER_LINE_ITEM**：只有「已出貨且已送達」的單位才能退。
  <!-- 依 46a:519、46a:627、46a:648、46a:1034 修正，原文：`ReturnLineItemInput.fulfillmentLineItemId: ID!` 逐字「The ID of the fulfillment line item to be returned」；`returnableFulfillments` 前提逐字「A returnable fulfillment is an order that has been delivered」。
       🔴 此處原本寫錯：本 ER 圖原本只有 `ORDER ||--o{ RETURN`，退貨掛在訂單層——這是 schema 級錯誤，上線後改不得，且會允許退未出貨品項。任何人翻舊版都不要改回去。 -->
- **RETURN_POLICY_SNAPSHOT**：退貨與取消規則**綁購買時點**，`order_line_items.return_policy_snapshot_id` 為 NOT NULL；規則被改不影響既有訂單（規格見 16-F7.4）。
  <!-- 依 46c:422–426、44:437 補寫（三方一致），原文：「對退貨規則所做的變更僅適用於未來的訂單」 -->
- **ReverseFulfillmentOrder / ReverseDelivery**：逆向履行層，原本整層不存在。disposition **不是一次性終態**（`PROCESSING_REQUIRED` 是中間態），同一 line item 允許多筆 disposition 紀錄、取最新（46a:671–680）。
- **Inventory ledger**：InventoryLevel 存各狀態量（available/committed/on_hand），每次變動寫一筆 INVENTORY_ADJUSTMENT（reason + delta + reference）——對帳、稽核、除錯全靠它。
- **CHECKOUT 表**：進結帳即落一筆（含 email、line items snapshot、金額組成、recovery token）；完成→關聯 order；未完成→就是棄單列表的資料來源。

## 3. 內容與平台 ER（第二張）

```mermaid
erDiagram
    SHOP ||--o{ THEME : "library ≤20"
    THEME ||--o{ TEMPLATE : "JSON templates"
    TEMPLATE ||--o{ SECTION_INSTANCE : "sections + order"
    SECTION_INSTANCE ||--o{ BLOCK_INSTANCE : blocks
    THEME ||--|| THEME_SETTINGS : "global settings"
    SHOP ||--o{ MENU : navigation
    MENU ||--o{ MENU_ITEM : "nested items"
    SHOP ||--o{ PAGE : pages
    SHOP ||--o{ BLOG : blogs
    BLOG ||--o{ ARTICLE : articles
    SHOP ||--o{ FILE_ASSET : files

    SHOP ||--o{ STAFF_MEMBER : users
    STAFF_MEMBER }o--o{ ROLE : has
    ROLE }o--o{ PERMISSION : grants
    SHOP ||--o{ SHIPPING_PROFILE : "1 general + custom"
    SHIPPING_PROFILE ||--o{ SHIPPING_ZONE : zones
    SHIPPING_ZONE ||--o{ SHIPPING_RATE : "flat / conditional"
    SHOP ||--o{ TAX_SETTING : "per region + overrides"
    SHOP ||--o{ NOTIFICATION_TEMPLATE : "liquid-like templates"
    SHOP ||--o{ METAFIELD_DEFINITION : defines
    METAFIELD_DEFINITION ||--o{ METAFIELD : values
    SHOP ||--o{ EVENT_OUTBOX : "domain events"
    SHOP ||--o{ DISCOUNT : discounts
    SHOP ||--o{ SEGMENT : "customer segments"
```

- **Theme = 資料不是程式碼**：template 是 JSON（section 實例 + 順序 + 每個實例的 settings），section 型別對應前端元件註冊表；theme editor 就是這份 JSON 的視覺化編輯器（見 03、07）。
- **EVENT_OUTBOX**：與業務寫入同交易插入（topic = `orders/create` 風格），單一 dispatcher 消費——先支撐站內通知信，之後開放對外 webhook 直接沿用（見 09）。

## 4. 狀態機總表

> **本表只列「有哪些狀態」**。完整的**合法轉移＋非法轉移＋每個轉移的前置條件與副作用**寫在對應 spec：
> FulfillmentOrder → `docs/specs/16` F3.1；Return / Exchange → `16` F7.1；Order 取消 → `16` F4.1/F4.2。

| 資源 | 欄位 | 狀態流 |
|---|---|---|
| Product | status | DRAFT → ACTIVE ⇄ ARCHIVED |
| Order | ~~status~~ **（無單一 status）** | 🔴 **Order 沒有單一 status 欄位**，由四條**正交軸**組成：`displayFinancialStatus` × `displayFulfillmentStatus` × 生命週期旗標（`closed`/`cancelled` 等 11 個布林） × `returnStatus`。`closed` 判定式＝**所有 line item 已履行或已取消 AND 所有金流交易完成**；**`VOIDED` 不使訂單 closed** |
| Order | financial_status | **8 值**：PENDING → AUTHORIZED →（PARTIALLY_PAID）→ PAID → PARTIALLY_REFUNDED → REFUNDED；另 VOIDED、EXPIRED。**VOIDED / EXPIRED / REFUNDED 為終態不可逆**；`AUTHORIZED → PARTIALLY_PAID → PAID` 為多次部分請款路徑（需 `capture_payments_for_orders` 權限） |
| Order | fulfillment_status | **現行 7 值**：UNFULFILLED / ON_HOLD / SCHEDULED / IN_PROGRESS / PARTIALLY_FULFILLED / FULFILLED / **REQUEST_DECLINED**；另 3 個 deprecated（OPEN / PENDING_FULFILLMENT / RESTOCKED，GraphQL enum 保留標 deprecated、**不落地**）。**derived 不可寫入**；`ON_HOLD`/`SCHEDULED` 的定義是「***所有*** unfulfilled items 皆處於該狀態」 |
| Order | return_status | **6 值**（聚合、derived）：NO_RETURN / RETURN_REQUESTED / IN_PROGRESS / INSPECTION_COMPLETE / RETURNED / RETURN_FAILED |
| **FulfillmentOrder** | **status** | **7 值**：OPEN / IN_PROGRESS / SCHEDULED / ON_HOLD / CLOSED / INCOMPLETE / CANCELLED。**CLOSED、CANCELLED 為終態**；🔴 `fulfillmentOrderClose → INCOMPLETE`（**不是 CLOSED**） |
| **FulfillmentOrder** | **requestStatus**（第二條正交軸） | **8 值**：UNSUBMITTED / SUBMITTED / ACCEPTED / REJECTED / CANCELLATION_REQUESTED / CANCELLATION_ACCEPTED / CANCELLATION_REJECTED / CLOSED。**不變量：未指派 fulfillment service 的 FO 恆為 `UNSUBMITTED`** |
| **FulfillmentOrder** | **supportedActions**（計算欄位） | **12 值**：CREATE_FULFILLMENT / REQUEST_FULFILLMENT / CANCEL_FULFILLMENT_ORDER / REQUEST_CANCELLATION / HOLD / RELEASE_HOLD / MOVE / SPLIT / MERGE / MARK_AS_OPEN / REPORT_PROGRESS / EXTERNAL。**伺服器端計算，admin 按鈕啟用完全由它驅動** |
| **FulfillmentHold** | reason | **8 值**：AWAITING_PAYMENT / **AWAITING_RETURN_ITEMS**（換貨專用）/ HIGH_RISK_OF_FRAUD / INCORRECT_ADDRESS / INVENTORY_OUT_OF_STOCK / UNKNOWN_DELIVERY_DATE / ONLINE_STORE_POST_PURCHASE_CROSS_SELL / OTHER。每張 FO **≤10 個 active hold** |
| **Fulfillment** | status | **現行 4 值** SUCCESS / CANCELLED / ERROR / FAILURE ＋ 2 deprecated（OPEN / PENDING） |
| DraftOrder | status | open → invoice_sent → completed |
| Checkout | — | active → completed（轉 order）／ abandoned（留 email 後 **10 分鐘**未完成）→ 90 天清除 |
| Return | status | **5 值**：REQUESTED / OPEN / DECLINED / CLOSED / **CANCELED（單 L）**。**DECLINED、CANCELED 為終態** |
| **ReverseFulfillmentOrder** | status | **3 值**：OPEN / CLOSED / CANCELED |
| **ReverseFulfillmentOrderLineItem** | dispositionType | **4 值**：RESTOCKED / NOT_RESTOCKED / MISSING / **PROCESSING_REQUIRED（中間態，可多次 disposition）** |
| **Refund** | **（刻意無 status）** | 🔴 **Refund 是不可變帳務紀錄，不建 `refunds.status` 欄位**；退款是否成功看底下 OrderTransaction |
| Transfer | status | draft → ordered/in_transit → partially_received → received / canceled |
| Discount | status | scheduled → active → expired（由起訖時間推導） |
| Transaction | kind/status | authorization/sale/capture/void/refund × pending/success/failure |
| Theme | role | draft ⇄ published（每店僅一個 published） |
| Payout（若做） | status | scheduled → in_transit → paid / failed |

<!-- 依 46a:136–152、46a:1045 修正，原文：Order 由四條正交軸組成、無單一 status。
     🔴 此處原本寫錯：本表原有一列 `| Order | status | open → archived / canceled |`，把 Order 寫成單一 status 欄位，與官方直接衝突。任何人翻舊版都不要改回去。 -->
<!-- 依 46a:438–482、46c:1021–1033（C-07）修正，原文：`ReturnStatus` 5 值（REQUESTED/OPEN/DECLINED/CLOSED/CANCELED）。
     🔴 此處原本寫錯：本表原寫 `requested → in_progress → inspection_complete → returned`（help 的 4 態展示狀態），
     缺 DECLINED/CANCELED 兩個終態；help 的「檢查完成」在 dev 是 OPEN 底下的子進度，不是獨立狀態。任何人翻舊版都不要改回去。 -->
<!-- 依 46a:213–290、46a:383–392 補寫：FulfillmentOrder（status/requestStatus/supportedActions）、FulfillmentHold、Fulfillment、
     ReverseFulfillmentOrder、Refund（刻意無 status）六列原本完全不存在 -->

推導規則（重要）：
- financial_status 從 transaction 聚合推導（sum captured vs order total vs refunded）。
- fulfillment_status 從 fulfillment orders / line item 已出數量推導。
- 各條狀態機**互相獨立**（可以 paid+unfulfilled、pending+fulfilled 並存；FulfillmentOrder 的 `status` 與 `requestStatus` 亦互相獨立）。
- **狀態機違規的統一錯誤碼＝`INVALID_STATE`**（源自 `ReturnErrorCode` 26 值，全專案沿用）。

## 5. 庫存數量恆等式

```
on_hand   = available + committed + unavailable(damaged/qc/safety/draft_reserved/app_reserved/other)
incoming  獨立計（在途，不入 on_hand）
下單:        available -= n ; committed += n            (reason: order_created)
出貨:        committed -= n ; on_hand  -= n             (reason: fulfillment)
訂單草稿保留: available -= n ; unavailable[draft_reserved] += n   🔴 不是 committed
草稿轉正式單: unavailable[draft_reserved] -= n ; committed += n
建立退貨:     不動任何數量（僅標記「待收退貨品項」）
退貨處理入庫: available += n                             (reason: return_restock)
退款+回補:    available += n                             (reason: restock)
盤點/調整:    available ±= n                             (reason: correction…)
編輯 on_hand: available 等量變動（on_hand 為 derived）
```

<!-- 依 46c:546–549、46c:895 補寫，原文：「訂單草稿保留庫存 → 進 Unavailable 狀態（不是 Committed）」；
     46c:296、46c:330：「建立退貨當下庫存不變，品項標記『待收退貨品項』」；46c:594–595：編輯連動規則。
     恆等式本身（06:111）原本就對，但 13-F5 只實作 available/committed 兩欄 → 恆等式恆不成立。落地規格見 13-F5.1 -->

**恆等式是 nightly 對帳 job 的斷言，不是註解**：`13-F5.1` 是它的唯一落地規格；`inventory_levels` 必須有 `available / committed / unavailable / incoming` 四個實體欄位 ＋ `inventory_unavailable_buckets` 子分類表，且 `Σ buckets.quantity == unavailable`。

超賣控制：`UPDATE inventory_level SET available = available - n WHERE available >= n`（inventoryPolicy=CONTINUE 時免 WHERE 保護、允許負數）。

## 6. 金額計算管線（訂單金額的唯一真相）

```
subtotal(line items Σ)
→ product/order discounts（按 class + combinesWith 規則，分攤到 line）
→ shipping（zone/rate 引擎）+ shipping discounts
→ taxes（稅率表；含稅價則反推）
→ total
→ transactions（authorized / captured / refunded 累計）
→ balance（應收餘額）
```

實作成純函式模組（輸入 cart/order + 設定，輸出金額明細與分攤），checkout、draft order、訂單編輯、退款計算全部重用同一個引擎——這是 Shopify「到處金額都對得上」的關鍵。

## 7. 建議的表清單（demo 範圍）

<!-- 依 D1（MySQL 8）批註修正標題，原文：「## 7. 建議的表清單（demo 範圍，Postgres）」。本節成文早於 D1 定案。 -->
> ⚠ 本節草擬時假設 Postgres；**D1 已定 MySQL 8**——型別與索引語法一律以 MySQL 8 為準。
> 特別注意 MySQL 特有陷阱：nullable 欄位進 UNIQUE 索引等於沒約束（NULL≠NULL，見 SESSION-EXPORT §5.8）、
> 部分唯一要用生成欄位（`COALESCE`/`IF` 形態，m0/rails-skeleton 已有先例）。

shops, staff_members, roles, role_permissions；products, product_options, option_values, product_variants, media, collections, collection_products, collection_rules；inventory_items, locations, inventory_levels, inventory_adjustments；customers, customer_addresses；checkouts, orders, line_items, order_transactions, fulfillment_orders, fulfillments, refunds, refund_line_items, events(timeline)；discounts, discount_applications；themes, templates, theme_settings, menus, menu_items, pages, files；shipping_profiles, shipping_zones, shipping_rates；tax_settings；notification_templates；metafield_definitions, metafields；segments；event_outbox；sessions/api_tokens。約 40 張表——這就是「早期 Shopify 骨幹」的實際大小。

**P0 修正後**必須補的表（15 張，缺任一即對應 P0 無處落地）：

| 表 | 為什麼必要 | P0 |
|---|---|---|
| `fulfillment_order_line_items` | FO 的計畫工作量；拆單不變量的計算基礎 | P0-04/05 |
| `fulfillment_line_items` | **出貨單位**——`return_line_items` 的外鍵目標 | P0-08 |
| `fulfillment_holds` | 8 種 reason ＋ 每 FO ≤10 active | P0-05 |
| `returns` | 5 態狀態機 ＋ `return_shipping_fee_cents`（per return，presentment 幣別） | P0-02/06 |
| `return_line_items` | FK → `fulfillment_line_items`；`restocking_fee_bp`（per line） | P0-02/08 |
| `exchange_line_items` | 換貨品項；驅動 `ON_HOLD` + `AWAITING_RETURN_ITEMS` 的 FO | P0-09 |
| `reverse_fulfillment_orders` | 逆向履行層（3 態） | P0-06 |
| `reverse_fulfillment_order_line_items` | disposition 可多筆、取最新 | P0-06 |
| `reverse_deliveries` | 退貨標籤與追蹤 | P0-06 |
| `return_rules` | 多條規則 ＋ 按市場切換 | P0-10 |
| `return_policy_snapshots` | **immutable append-only**；`order_line_items.return_policy_snapshot_id` NOT NULL | P0-10 |
| `return_rule_final_sale_targets` | 最終銷售以 collection／product 為粒度 | P0-10 |
| `inventory_unavailable_buckets` | `unavailable` 六子分類；草稿保留與待收退貨的落腳處 | P0-15 |
| `pickup_point_providers` / `order_pickup_points` | 超商取貨 admin 側（門市快照） | P0-13 |
| `store_credit_accounts` / `store_credit_transactions` | `refundMethods` 的 store credit（原型已標「06 §7 待補」） | P0-01（退款方式） |

`idempotency_keys` 的欄位定義改為「存 `result_ref` 指標」而非 `response_body` 快照——見 `docs/specs/11` §2.1（P0-11）。

**P1 修正後**再補的表（8 張，見 `docs/specs/54-p1-logic-fixes.md`）：

| 表 | 為什麼必要 | P1 |
|---|---|---|
| `order_edit_sessions` | 訂單編輯 session；**部分唯一索引 `(order_id) WHERE committed_at IS NULL AND abandoned_at IS NULL`**＝單一 open session 鎖 | P1-17（16-F8.2） |
| `calculated_orders` | **CalculatedOrder 暫存區**；commit 前原訂單零變動；`snapshot_json` 內每個元素帶 `staged_status`(ADDED/REMOVED/UNCHANGED) | P1-16（16-F8.1） |
| `order_edit_deltas` | 編輯增量的報表歸屬（`order_id, session_id, delta_cents, occurred_on`）——不產生幽靈訂單 | P1-22（19-F1.1） |
| `companies` | **只有** `name` / `note` / `default_role_id` / `main_contact_id`（掛載鐵律） | P1-33（29 §10） |
| `company_locations` | catalog／payment terms／tax／checkout 設定／currency／locale／地址 **一律掛這裡** | P1-33 |
| `company_contacts` | **`customer_id` 外鍵 → 復用 `customers`**（contact 不是獨立帳號）；角色走 `company_contact_role_assignments`（contact × location × role） | P1-33（H-68） |
| `market_settings` | `(market_id, key, value JSON)`，**`value IS NULL` ＝ 繼承**；取代原本權威的 `parent_market_id` | P1-32（29 §1.5） |
| `cod_settlement_rows` | COD 對帳檔匯入（`carrier, statement_id, row_no` 唯一索引 ⇒ 重覆匯入冪等） | P1-08（16-F4.4） |

### 7.1 法域 schema（**取所有 pack 的聯集**，不是取當前 pack）

<!-- 依 docs/specs/57 §G-04 補寫（原 55 §D G-04 的結論一字未改，只是加上法域維度）。
     依 56 §E 分流，原 55 §D 結論：「一訂單多發票；**不得**對 `einvoices(shop_id, order_id)` 建唯一索引」
     ——該結論的**稅務理由**在 HK 為 N/A（`tax_invoice: none`，該表恆空），但**結論保留**。
     🔴 這是本輪唯一「schema 級、上線後改不得」的一條，與 P0-08（`return_line_items` 外鍵）同性質：
        HK 首發上線時 `einvoices` 一列資料都不會有，建表的人**沒有任何動機**去想索引怎麼建；
        等到日後啟用 tw pack 才發現索引建錯，就要停機做 migration。
     56 §0.2 原則 3 只寫了「schema 取聯集」的原則，裁決值 `multiple_invoices_per_order_allowed: true`
     留在 `jurisdictions.tw.tax_invoice` 底下——但 `tw.enabled: false`，**建表時沒有人會去讀一個未啟用的 pack**。
     已在 `limits.jurisdiction.schema_union_rules` 補上核心層的列舉（57 §G-04 的 limits 改動）。 -->

**建表鐵律**：schema 決定一律取**所有 pack 的聯集**（`limits.jurisdiction.schema_is_union_of_all_packs: true`），**行為**才取當前 pack。基準法域是 HK，但 HK 首發的 migration **必須**把下列 tw pack 的表一起建出來。

| 表 | 當前（HK）狀態 | 建表要求 | 出處 |
|---|---|---|---|
| `einvoices` | **恆空**（`tax_invoice: none`，全部事件回 `no_document`） | 🔴 **不得**對 `(shop_id, order_id)` 建唯一索引 | 55 §D G-04；`limits.jurisdiction.schema_union_rules.forbidden_unique_indexes` |
| `einvoice_allowances` | 恆空 | `Σ amount_cents(per einvoice_id) ≤ einvoices.total_cents`，條件式 UPDATE | 55 §D G-02（tw only） |
| `jurisdiction_capability_skips` | **HK 首發即大量寫入** | `(shop_id, jurisdiction, capability, event_kind, source_write_point, reason, occurred_at)`。每一次 `documented_no_op` 落一列 | 56 §A.3 |
| `contract_liability_entries` | **HK 首發即使用** | `(shop_id, source_type, source_id, direction, amount_cents, recognised_at, basis)`；唯一鍵 `(shop_id, source_type, source_id, direction)` | 56 §B.3.1 J-01；57 §G-07 |

**`jurisdiction_capability_skips` 為什麼是表不是 log**：它的唯一目的是讓「什麼都沒做」變成**看得見的一列資料**（56 §A.3）。寫進 log 就只是「可以 grep 的字串」，做不出 nightly 斷言——而 HK 下 20 條稅務事件全部走這條路（56 §B.2.1），沒有斷言就等於沒有覆蓋。

**既有表的欄位變更（P1）**：
- `orders`：補 **`seller_jurisdiction` / `buyer_jurisdiction`**（訂單成立即快照；`limits.jurisdiction.snapshot_on_order: true`）。🔴 **一筆交易有兩個法域**——賣方決定稅制／憑證／儲值監管，買方決定隱私／取貨／幣別／消費者權利；混成一個 `country` 欄位，跨境單必錯（56 §A.0）。
- `gift_card_transactions`：外鍵改為**複合外鍵 `(shop_id, gift_card_id)`**，不是單欄 `gift_card_id`。單欄外鍵在應用層漏檢時完全擋不住跨店扣抵。理由自 2026-08-12 起從「SVF 法遵」改為**多租戶資料隔離**（CLAUDE.md 鐵律 2）——**技術動作不變，只是理由換了**（56 附錄 Z）。
- `gift_cards`：補 `redeemable_scope`（列舉只有 `issuing_shop_only`）；`shop_id NOT NULL`。
- `markets`：`parent_market_id` → **`derived_parent_market_id`（推導快取，非權威）**；conditions 變更時同 transaction 重算子樹。
- `notification_templates`：補 `event_key` / `group_key` / `channel` / **`toggleable`（種子決定、唯讀）** / `enabled` / `locale` / `implemented`（18-F2.1）。
- `discount_combines_with`：唯一鍵 `(discount_id, target_class)`，且**寫入 `(shipping 類折扣, shipping)` 一律拒絕**（17-F1 第 4 點）。
- `shipping_rates`：補 `cod_fee_cents`（15-F2.3）。
- `return_rules`：補 `tw_statutory_exemption_claimed`（16-F7.4(b)）。
- `orders`：補 `cod_expected_cents`；`edited`（bool）由 F8 commit 寫入。
