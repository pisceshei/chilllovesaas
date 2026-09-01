# 95 號：Analytics teardown（步 10 補課；實測＋官方雙源）

> 取證 2026-09-01。實測＝測試店 chill-love-u5q5mnzq 親點（§1–§3）；官方逐字＝
> help.shopify.com（§4–§6，每句帶 URL）。第三方（非 GPL）＝§7。

## §1 Analytics 主頁（實測）

- 路由 `/analytics`；header：期間選擇器［Today ⌄］＋比較期［Aug 31, 2026 ⌄］＋
  幣別［USD $ ⌄］＋「⋯」＋Try targets＋**New exploration**。
- Dashboard 頂條四卡（本店現形）：Gross sales／Returning customer rate／
  Orders fulfilled／Orders。
- 🔴 **Total sales breakdown 卡＝官方組成的畫面實錘**（列序逐字）：Gross sales／
  Discounts／**Sales reversals**／Net sales／Shipping charges／**Return fees**／
  Taxes／Total sales——與 §4 公式互證；現行術語是 sales reversals（非 returns）、
  Return fees 獨立列。
- 其他卡：Total sales over time（Today 粒度＝逐時；比較期虛線）／Total sales by
  sales channel／Average order value over time／Total sales by product／Sessions
  over time／Conversion rate over time／**Conversion rate breakdown**（漏斗四階：
  Sessions→Added to cart→Reached checkout→Completed checkout，各帶 %）。
- 側欄：Analytics → **Reports**／**Live View**。

## §2 期間選擇器（實測值域）

- 頂層：Today／Yesterday／**Last ▸**／**Period to date ▸**／Black Friday／
  Cyber Monday／**Quarters ▸**／Custom range＋雙月曆＋Cancel/Apply。
- Last ▸ 全 11 值：Last 30 minutes／Last 12 hours／Last 7 days／Last 30 days／
  Last 90 days／Last 365 days／Last week／Last month／Last quarter／
  Last 12 months／Last year。
- Period to date ▸／Quarters ▸ 未展開（V-238）。

## §3 Reports 頁（實測）

- 路由 `/analytics/reports`；搜尋框＋Created by/Category 兩 filter＋表（Name/
  Category/Last viewed/Created by）＋分頁 1-50；全部 Created by Shopify。
- Category filter 可見 11 值（往下未捲盡，V-239）：Acquisition/Behavior/Customers/
  Finances/Fraud/Inventory/Marketing/Orders/Performance/Profit Margin/Retail Sales
  ——與 §6 官方 11 類對照（官方用單數 Order/Finance/Profit/Sales；filter 用
  複數形＋Profit Margin/Retail Sales，兩處措辭不同照登）。
- 與我方相關的存在實錘：RFM customer analysis／RFM customer list（詳情頁 KPI 第
  四格的資料源）；Predicted spend tiers。

## §4 指標定義（官方逐字；sales-report 頁＋analytics-fields 頁）

- Gross sales＝"product price x quantity (before taxes, shipping, discounts, and
  sales reversals)"；含未付款單（discrepancies 頁："Canceled, pending, and unpaid
  orders are included."）。
- Net sales＝"gross sales - discounts - sales reversals"。
- **Total sales＝"gross sales - discounts - sales reversals + taxes + duties +
  shipping charges + fees"**（sales 頁）。🔴 Finance 頁版本**無 duties**——兩頁
  公式不一致，照登不裁（實作取含 duties 版；91 §3.59）。Tips 不進 total sales
  （Finance summary 獨立區塊）。
- Shipping＝"shipping charges - shipping discounts - refunded shipping amounts"。
- Returns＝"The value of goods returned by a customer. Returns display as a
  negative number on the date the return was processed."
- **Sales reversal 定義**："A reversal is any type of order adjustment that
  results in a negative value… Sales reversals include the value of returned
  items, as well as order cancellations, edits, adjustments to shipping, taxes,
  fees, and discounts."（returns 欄位已被 sales reversals 取代——shopify.dev
  changelog 同記）。
- 🔴 **AOV＝"((gross sales - discounts ) / orders)", excluding post-order
  adjustments such as edits or exchanges**——分子結構上**不含 taxes/shipping/
  duties/returns**。fields 頁："Average value of orders placed, excluding any
  post-order adjustments"。
- Net items sold＝"Number of items in the given sale, with reversed quantity
  factored in"；Ordered item quantity＝"…excluding reversed quantity"。

## §5 落日與時區（官方）

- 🔴 落日雙軌（sales 頁逐字，rollup 設計核心句）："Sales display in your sales
  reports as a positive value for the day that they were made, and reversals
  display as a negative value for the day that they were processed."
- 訂單編輯獨立列："If you edit an order after the day the order was placed, then
  the edit displays as a separate order on the Total sales over time report."
  （我方訂單編輯落地時的 rollup 契約——91 §3.59）。
- 日界線＝店時區的總則句＝未取得；旁證：Live View "Information in the Live View
  is displayed in your store's local time."＋analytics-updates "timestamp fields
  are all converted to your shop's timezone"。

## §6 儀表板與報表（官方）

- 卡片自訂："The dashboard includes customizable metric cards for every available
  report."＋"You can add any number of the available cards to your dashboard, but
  each card can be included only one time."——🔴 **無 16 卡上限**（72 號舊記錄的
  16 指標形＝舊版儀表板；本條更正之）。加卡＝"the metric library sidebar" 拖放。
- 資料新鮮度："updated within about 1 minute"；今日含在滾動範圍（"today is
  included as part of the 'last 7 days' by default"；可取消 Include current
  period）。預設範圍＝"the default date range of the last 90 days"。
- 比較期："Compare your metric data across 2 different time periods."（Previous
  period／Previous year 預置）。
- 預設報表 11 類（default-reports 索引頁）：Acquisition/Behavior/Customers/
  Finance/Fraud/Inventory/Marketing/Order/Profit/Retail sales/Sales。
- ShopifyQL：語言仍在（"ShopifyQL is a query language for commerce."）；GraphQL
  `shopifyqlQuery` 已沙汰（2024-07 release notes 逐字）；Notebooks 專文已從
  help 消失（正式沙汰句未取得）。

## §7 第三方 rollup 參考（非 GPL）

- Apache Druid（Apache-2.0）Rollup："Rolling up data can dramatically reduce the
  size of data to be stored and reduce row counts by potentially orders of
  magnitude."——(時間桶×維度) 預聚合＝daily_rollups 正典形。
- ClickHouse（Apache-2.0）Materialized Views："shift the cost of computation from
  query time to insert time"——聚合成本移寫入側。

## §8 我方落點與差異登記

1. 🔴 **AOV 分子修正**（本補課包）：官方公式分子＝gross−discounts＝我方
   subtotal_cents；步 10 首版誤用 order total（含運費稅）——研究補課抓到的
   實質口徑錯，已修＋spec 釘住。
2. shipping 組成：官方 Shipping 淨掉 shipping discounts；我方 orders.shipping_cents
   ＝折前、運費折扣在 discount_cents——total 恆等但組成切分與官方不同
   （91 §3.59，隨訂單編輯/報表細分包對齊）。
3. 「16 指標挑選器」框架撤下（§6 更正）；dashboard 完整版走 metric library 形。
4. V-238（Period to date/Quarters 子值域）／V-239（Category filter 未捲盡）。
