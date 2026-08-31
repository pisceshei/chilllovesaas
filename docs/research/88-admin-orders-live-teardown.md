# 88 — 訂單線 admin 六層實測 teardown（G6-6 步 3/4/5 的量測基準）

> 取證：2026-09-01，測試店 chill-love-u5q5mnzq（本地 Chrome 親自點擊；鐵律 12/13/14）。
> 店內實料：7 張訂單（Fecify app 通道×4＋Draft Orders 通道×3；JPY/HKD/MYR/USD 四幣；
> 含已取消單、已封存單、tracking 單、無顧客單）＋3 張草稿單＋1 筆棄單。
> 官方 API 逐字取證（shopify.dev latest=2026-07，取證 2026-09-01）另存本輪研究檔
> （session scratchpad ord-0~3；正典結論已併入本檔 §7）。
> 🔴 字重量測皆經 `font-bolder-style` 污染消融（450/550 為真值）。

## §1 架構（URL 路由樹與頁面層級）

```
/orders                    列表（訂單根）
  ?savedViewId=…&query=…&order=<key>+<asc|desc>&selectedColumns=A,B,…
                           ← 列表狀態全量 URL 編碼（saved view／搜尋／排序／欄集）
/orders/:id                詳情
/orders/:id/refund         退款表單頁
/orders/:id/return         Return and exchange 表單頁
/draft_orders              草稿列表（側欄「Drafts」）
/shipping_labels           運送標籤
/checkouts                 棄單列表（側欄「Abandoned checkouts」）
```
- GID 形：`gid://shopify/Order/<id>`／`DraftOrder/<id>`／`AbandonedCheckout/<id>`
  （列 checkbox 的 aria-label 逐字曝露）。
- 預設排序＝`order=processed_at desc`（URL 實測）＝官方 orders query 預設
  sortKey `PROCESSED_AT`（§7 對表吻合）。
- `selectedColumns` enum 名（URL 逐字）：ORDER_DATE、CUSTOMER_NAME、FULFILL_BY、
  CHANNEL、TOTAL_PRICE、FINANCIAL_STATUS、FULFILLMENT_STATUS、ITEM_COUNT、
  DELIVERY_STATUS、DELIVERY_METHOD、ORDER_TAGS。

## §2 列表頁按鈕級與值域窮舉

- **頂列**：Export／More actions ⌄（值域恰一項：Show analytics bar）／Create order。
- **Export modal**（逐控件）：範圍 radio 五值＝Current page✓／All orders／
  Selected: N orders（未選時 disabled）／N orders matching your search／Orders by date；
  格式 radio 二值＝CSV for Excel, Numbers, or other spreadsheet programs✓／
  Plain CSV file；底鈕＝Cancel／Export transaction histories／Export orders(primary)。
- **檢視列**：「All」view chip＋Search and filter 輸入框＋（query 態）Save 鈕＋
  Reset view；欄位/排序面板鈕（右端 icon）。
- **篩選維度 24 項**（下拉全量，DOM 收割）：Order status／Payment status／
  Fulfillment status／Delivery status／Return status／Label status／
  Chargeback and inquiry status／Order total／Delivery method／Destination／
  Address validation／Number of items／Total product weight／Product／
  Discount code／App／Channel／B2B／Payout action required／Fraud risk／
  Customer request／Credit card (last 4 digits)／Tagged with／Fulfill by。
  逐維度展開的 enum（每項附 Is/Is not 運算子）：
  | 維度 | 值域（逐字） |
  |---|---|
  | Order status | Open／Archived／Canceled（3）|
  | Payment status | Authorized／Due／Expired／Paid／Partially paid／Partially refunded／Pending／Refunded／Unpaid／Voided（10）|
  | Fulfillment status | Fulfilled／Unfulfilled／Partially fulfilled／Scheduled／On hold／Request declined（6）|
  | Delivery status | In transit／Out for delivery／Attempted delivery／Delayed／Failed delivery／Delivered／Ready for pickup／Tracking added／No status（9）|
  | Return status | Return requested／Return in progress／Return closed（3）|
  | Label status | No label／Draft created／Purchased／Printed（4）|
  | Chargeback and inquiry status | Open／Submitted／Won／Lost（4）|
  其餘維度＝資料驅動 picker（Product/App/Channel/Tagged with…）或數值/日期
  區間（Order total/Number of items/Fulfill by…），未逐一展開（V-88-1）。
  🔴 **層差登記**：篩選的 Payment status 10 值 ⊃ API enum
  `OrderDisplayFinancialStatus` 8 值（官方 §7）——「Due／Unpaid」是列表篩選層
  聚合值，不在 API enum；兩層都是真值，實作時篩選器走 10 值、資料欄走 8 值。
- **欄位/排序面板**：Sort by（鍵 12 值逐字：Order／Date✓／Customer／Channel／
  Total／Fulfillment status／Payment status／Items／Destination／PO number／
  Fulfill by／Label status；方向 Oldest first／Newest first✓）＋
  Group by batch toggle（預設開）＋Hide archived toggle（預設關）＋
  Columns 15 項可拖曳排序＋眼睛顯隱（預設顯 11：Date/Customer/Fulfill by/Channel/
  Total/Payment status/Fulfillment status/Items/Delivery status/Delivery method/
  Tags；預設隱 4：Destination/Return status/PO number/Label status）。
  表頭 aria 另證 9 個可點排序欄（name/ORDER_DATE/CUSTOMER_NAME/FULFILL_BY/
  CHANNEL/TOTAL_PRICE/FINANCIAL_STATUS/FULFILLMENT_STATUS/ITEM_COUNT）。
- **列 anatomy**：checkbox（aria=GID）｜單號（app 單=尾碼截斷「…1907646655815」、
  draft 單=#1006）｜Flags（獎章 icon）｜Date｜Customer（No customer 空態）｜
  Fulfill by｜Channel｜Total（幣別符號＋code）｜Payment status badge｜
  Fulfillment status badge（黃）｜Items（N items＋hover View items）｜
  Delivery status chip（Tracking added／+1 疊加）｜Delivery method
  （Shipping not required／運送）｜Tags pills（+N 溢出）。
  已取消單＝整列刪除線。列 hover 鈕：View customer／View items／
  View Delivery Status／View Address issues。
- **空態（搜尋無果）**：放大鏡插圖＋「No orders found」＋
  「Try changing the filters or search terms for this view」＋
  「Clear search and filters」鈕。

## §3 詳情頁（兩狀態實測）

**佈局**：主欄 638px＋右欄 347px（23 號詳情頁雙欄模型）。

**頭列**：麵包屑（icon › 單號）＋badges（Paid●／Fulfilled●／Archived）＋
副標「August 21, 2026 at 9:39 pm from Fecify (via import)」＋動作鈕組＋前後單導航 ⌃⌄。
- 有已付金額單：Refund／Return／More actions ⌄。
- $0 已付單（#1006）：Edit／More actions ⌄（🔴 無 Refund/Return——按鈕存在性
  是金額狀態函數）。
- **More actions 值域**（已封存單）：Search actions 搜尋框＋Edit／Duplicate／
  Unarchive／View order status page／Delete order＋〔Print〕Print order page／
  Print packing slips＋〔Apps〕Create Shipping Labels。

**主欄卡片序**：
1. **Fulfillment 卡**：
   - fulfilled 態：標題「Fulfilled (N)」＋fulfillment ID（`<單號>-F1`）＋⋯選單；
     日期列／「Shipping not required」／tracking URL＋「tracking: <號>」；
     行項（縮圖＋標題＋SKU＋單價 × 數量＋行小計 幣別）。
   - unfulfilled 態：黃 badge「Unfulfilled」＋配送方式列（運送）＋行項＋
     主鈕 **Mark as fulfilled ⌄ 分裂鈕**（chevron 值域：Mark as in progress／
     Mark as on hold）。
2. **Paid 卡**：badge＋列：Subtotal（N items｜金額）／Discount（折扣碼｜-金額）／
   Shipping（名稱＋重量註記「(0.0 kg: Items 0.0 kg, Package 0.0 kg)」｜金額）／
   Total／分隔／Paid。
3. **Timeline**：composer（頭像＋Leave a comment...＋emoji/@/#/附件 icon＋Post）
   ＋「Only you and other staff can see comments」＋日期分組事件流（實測事件形：
   This order was archived.／Fecify marked 9 items as fulfilled from Shop location.／
   ShipAny edited the details of this order.／A ¥109,250 JPY payment was processed
   on Fecify:Airwallex.／Confirmation #XXX was generated for this order.／
   <顧客> placed this order on Fecify.／You created this order from draft order #D3.）。

**右欄卡片序**：Notes（No notes from customer＋✎）→ Additional details
（custom attributes 鍵值對＋✎）→ Channel Information（Channel／Order ID）→
Customer（⋯選單＋名字連結＋「N order(s)」＋Contact information email＋
Shipping address〔🔴 條件警示 chip「⚠ Review address issues」〕＋地址＋電話＋
View map＋Billing address「Same as shipping address」；無顧客態＝
「Search or create a customer」combobox＋No email provided／
No shipping address provided／No billing address provided）→
Conversion summary（There aren't any conversion details available for this order＋
Learn more）→ Order risk（Analysis not available）→ Tags（Find or create tags）。

## §4 退款頁（/orders/:id/refund）

- Fulfilled 卡＋info banner（可關）：退款後不能再建退貨——要退貨先 create a return
  （連結）再退款。
- 行項：縮圖＋標題＋SKU＋單價＋**數量步進器「0 / N」**＋行退款額 ¥0。
- Refund shipping 卡：checkbox＋「Shipping & Handling · ¥3,620 JPY」＋金額輸入
  （未勾時 disabled 顯示原額）。
- Reason for refund 卡：文字輸入＋「Only you and other staff can see this reason」。
- 右欄：Summary（No items selected）→ Refund method select（Original payment）→
  Refund amount：閘道名（Fecify:Airwallex）＋金額輸入＋
  🔴 上限句「¥109,250 JPY available for refund」→
  主鈕「**Refund ¥0 JPY**」（金額活字；0 時 disabled）。

## §5 Return and exchange 頁（/orders/:id/return）

- 藍 banner：Save time with self-serve returns＋Go to self-serve returns 鈕。
- Select quantity to return 卡：fulfillment ID＋「Shipped from Shop location」＋
  行項數量步進器。
- Exchange items 卡：副標（換貨品不預留庫存直到處理退貨）＋🔴 條件不可用 info：
  「Unable to add exchange items」＋兩理由逐字（the order was placed through an
  app／the order is not in your store's currency）。
- Return shipping options 卡：radio 三形＝Create a return label in Shopify
  （disabled＋理由：主地點與顧客地址都在 US 才可）／Upload a return label✓
  （Add files dropzone，Accepts .pdf, .png, and .jpg＋Use return label URL instead
  連結）／＋Tracking number 輸入＋Shipping carrier select。
- 右欄：Summary（No items selected）＋Create return 黑鈕。

## §6 CSS 量測（消融後真值）

- 列表：cell 12px/450 lh~ 高 32px 字色 `#303030`；表頭 12px/550 `#616161`
  底 `#f7f7f7`；頁面底 `#f1f1f1`；badge 文字 12px（Paid=灰底 pill、
  Unfulfilled=黃底 pill——pill 級精確色值以我方 token 對映，V-88-2）。
- 詳情：主欄 638／右欄 347；卡片白底圓角（我方 .cl-card 既有 token 對映）。
- admin 字重體系＝450（regular）/550（semibold）——非 400/600。

## §7 官方 API 對表（研究輪逐字取證的正典結論；來源與日期見研究檔）

- `OrderDisplayFinancialStatus` 8 值：AUTHORIZED/EXPIRED/PAID/PARTIALLY_PAID/
  PARTIALLY_REFUNDED/PENDING/REFUNDED/VOIDED。
- `OrderDisplayFulfillmentStatus` 10 值：FULFILLED/IN_PROGRESS/ON_HOLD/OPEN(舊)/
  PARTIALLY_FULFILLED/PENDING_FULFILLMENT(舊)/REQUEST_DECLINED/RESTOCKED(舊)/
  SCHEDULED/UNFULFILLED——三個舊值官方標記已被取代；我方實作採現行 7 值＋
  文檔註記舊值不採（ours，登記）。
- `OrderCancelReason` 6 值：CUSTOMER/DECLINED/FRAUD/INVENTORY/OTHER/STAFF。
- orders query：sortKey 預設 `PROCESSED_AT`（與 §1 URL 實測互證）；
  first/after/last/before/reverse/query。
- 金額＝MoneyBag{shopMoney, presentmentMoney}（我方 v1 單幣 ⇒ 兩者同值，
  型別面照出——G6-7 MoneyV2Type 直接複用）。
- transactions/fulfillments＝list 非 connection；customer 可 null（guest）。

## §8 V 項（未取得／待補）

- V-88-1：數值/日期/資料驅動篩選維度的 UI 形（Order total 區間輸入形等）未逐一展開。
- V-88-2：badge pill 精確底色值（灰/黃）以 zoom 截圖比色未做——實作以我方
  token 系統對映（鐵律 8），視覺比對輪校準。
- V-88-3：Edit order（訂單編輯 session）頁未實測（Edit 鈕未點入——編輯流程屬
  20 步外的 orderEdit* 系列）。
- V-88-4：Shipping labels 頁只取路由未深入（屬步 5 外掛能力）。
- V-88-5：saved view 建立/重新命名流（Save 鈕後續）未走完。
- V-88-6：本尊 admin 走 persisted GraphQL（14.3）：query 全文不可觀測，
  本輪以 UI/URL 形取證為準。
