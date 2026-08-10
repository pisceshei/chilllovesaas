# 01 — 後台核心商務模組（Products / Inventory / Orders / Customers / Discounts）

> 本篇拆解 Admin 五大核心商務模組的功能邏輯、畫面結構、資料物件與狀態機。物件命名以 Shopify Admin GraphQL API 為準，可直接對照 06 的整合資料模型。標註「(待確認)」者為研究中未能完全確定的細節。

## 1. Products 商品

**目的與定位**：商品是所有銷售通路（Online Store、POS、B2B、社群）共用的單一商品主檔，承載定價、媒體、SEO、分類與變體結構，並作為庫存（經 InventoryItem）與訂單 line item 的來源。

**主要畫面與資訊架構**

- 列表頁：欄位含縮圖+Title、Status、Inventory（「X in stock for Y variants」彙總）、Category/Type、Vendor、Sales channels；tabs 為 All / Active / Draft / Archived（可另存自訂 view）；可依 vendor、tag、status、gift card 等篩選，支援 bulk edit 與 CSV 匯入匯出。
- 詳情頁卡片（由上而下）：Title + Description（富文本編輯器）、Media（圖片/影片/3D model，可拖曳排序，首圖為 featuredMedia）、Category（Shopify Standard Product Taxonomy）、Pricing（price、compare-at price、cost per item → 自動算 margin、charge tax 勾選）、Inventory（SKU、barcode、track quantity、continue selling when out of stock）、Shipping（是否實體、重量、海關 HS code）、Variants（選項與變體表）、Search engine listing（SEO title、meta description、URL handle）；右欄：Status、Publishing（sales channels 與 markets）、Product organization（type / vendor / collections / tags）、Theme template；已 pin 的 metafield definitions 顯示在頁面下方。

**核心資料物件**

- `Product`：id、title、handle、descriptionHtml、status（`ACTIVE` / `DRAFT` / `ARCHIVED`）、vendor、productType、category、tags、options、variants、media、seo、publishedAt、isGiftCard、totalInventory、metafields。
- `ProductOption` / optionValues：每商品最多 **3 個 options**；option 值組合展開成變體。
- `ProductVariant`：price、compareAtPrice、sku、barcode、selectedOptions、position、taxable、image、inventoryPolicy（`DENY` / `CONTINUE` = 售罄是否可續賣）、1:1 對應 `InventoryItem`。變體上限已從舊制 100 提升為 **2048**（2025-10-15 起對全商家開放）。
- `Collection`：manual（手動挑選）與 smart/automated（規則自動納入）。Smart 條件最多 **60 條**，可選 all/any 匹配；條件欄位含 tag、title、type、category、vendor、price、compare-at、weight、inventory stock、variant title 與 metafields（完整清單待確認）。automated 建立後不可改成 manual (待確認)。2025–2026 正在推出「統一 collections 模型」：單一 collection 可同時混用條件納入/排除與手動加入/移除。
- Gift cards：`isGiftCard=true` 的特殊商品，面額以變體表示；可被顧客購買或由商家直接發行，各卡有 code 與餘額，結帳時作為付款方式折抵；到期規則受當地法規限制。
- Metafields：`namespace.key` + type + value 的自訂欄位，掛在 Product/Variant/Order/Customer 等資源上；建立 definition 後可在 admin 編輯、驗證型別並用於篩選；多欄位的獨立資料結構用 metaobjects（見 05）。

**關鍵流程**：建立商品（預設 Draft）→ 填基本資料與媒體 → 新增 options 產生變體 → 逐變體設價格/SKU/各地點庫存 → 設定 SEO 與 sales channels → 切 Active 發佈。

**邊界案例**：Archived 不出現在通路但保留訂單關聯；handle 需唯一、改 handle 會斷舊連結（可自動建 301 redirect）；3 options 比 2048 變體更常成為實務瓶頸；未勾 track quantity 的商品不做庫存管控。

## 2. Inventory 庫存

**目的與定位**：以「品項 × 地點」為粒度管理可售數量，防止超賣，支援多倉/門市與進貨、調撥流程。

**主要畫面**：Inventory 頁以地點為篩選，每列一個變體，數量欄位為 **Unavailable / Committed / Available / On hand / Incoming**；可直接編輯 available 或 on hand 並選擇調整原因；每筆變更寫入 adjustment history 供稽核。Transfers、Purchase orders 為獨立頁。

**核心資料物件與狀態**

- `InventoryItem`：變體的庫存實體（tracked、sku、cost、原產國/HS code）。`tracked=false` 即 untracked，不追蹤也不擋售。
- `InventoryLevel`：InventoryItem 在某 `Location` 的數量集合；`Location` 為實體或邏輯地點，可停用某地點的個別品項。
- 數量狀態（互斥）：`available`（可售）、`committed`（已成立未出貨訂單占用）、`reserved`、`damaged`、`safety_stock`、`quality_control`（後四者在 admin 合併顯示為 Unavailable）；`on_hand` = available + committed + unavailable 各項總和；`incoming`（在途，未入 on hand）。
- 調整原因（API `reason`）：`correction`、`cycle_count_available`（盤點）、`damaged`、`received`、`restock`（退貨回補）、`shrinkage`（失竊/損耗）、`promotion`、`quality_control`、`safety_stock`、`reservation_created/updated/deleted`、`movement_*`（transfer/PO 觸發）、`other`。API 以 delta 調整並可附 `referenceDocumentUri` 做 ledger 稽核；**committed 不可直接經 API 調整**，只能由訂單流程變動。

**關鍵流程**：下單 → available−、committed+；fulfill → committed−、on hand−；退款勾 restock → available+。Transfer：建立（origin → destination）→ 產生 shipment、目的地顯示 incoming → in transit → 收貨時逐行 accept/reject、可部分收 → received 後 incoming 轉入 on hand/available；狀態約為 Draft → Ordered/In transit → Partially received → Received/Canceled（確切狀態名待確認）。

**邊界案例**：多地點時訂單依 fulfillment 地點優先序分配；inventoryPolicy=CONTINUE 可讓 available 變負數；untracked 商品在報表與庫存頁無數字。

## 3. Orders 訂單

**目的與定位**：訂單是付款、出貨、退款退貨的狀態機中樞；訂單詳情頁整合金流、物流、風險與溝通紀錄。

**主要畫面**

- 列表頁：欄位 Order（#編號）、Date、Customer、Channel、Total、Payment status、Fulfillment status、Items、Delivery method、Tags；預設 tabs：All / Unfulfilled / Unpaid / Open / Archived（可存自訂 view）；中高風險訂單在單號旁顯示警示 icon；bulk 動作含 fulfill、capture、archive、加 tag、列印。
- 詳情頁：左主欄 = 依 fulfillment 狀態分組的 line items 卡（Unfulfilled 卡有 Fulfill 按鈕；Fulfilled 卡顯示 tracking）、Payment 卡（小計/運費/稅/總計、已付與餘額，動作：Capture、Send invoice、Refund）、Timeline（系統事件 + 僅內部可見的留言與附件）；右側欄 = Notes、Customer（聯絡資訊、shipping/billing address）、Fraud analysis、Conversion summary、Tags。頂部動作：Refund、Return、Edit、More（Cancel / Archive / Duplicate / Print）。
- Abandoned checkouts 為 Orders 下獨立列表（詳見 04 第 3 節）。

**狀態機**

- Order status：`open` → `archived`（手動或自動封存）／`canceled`（cancelledAt + cancelReason；取消不等於已退款）。
- Financial（`displayFinancialStatus`）：`pending`、`authorized`、`paid`、`partially_paid`、`partially_refunded`、`refunded`、`voided`、`expired`；admin 的「Unpaid」是 authorized/pending/expired/partially_paid 的集合概念。
- Fulfillment（`displayFulfillmentStatus`）：`unfulfilled` → `in progress` / `on hold` / `scheduled` → `partially fulfilled` → `fulfilled`；另有 fulfillment not required。
- Return status：return requested → return in progress → inspection complete → returned。
- 關鍵物件：`Order`（lineItems、transactions、note、tags、events、risk、closedAt）、`FulfillmentOrder`（出貨工作單元：指派地點、hold、split——是實際執行 fulfill 的對象）、`Fulfillment`、`Refund`、`Return`、`OrderTransaction`（kind：authorization / sale / capture / void / refund）、`DraftOrder`（狀態 `OPEN` → `INVOICE_SENT` → `COMPLETED`，命名待確認）。

**關鍵流程**

- Draft order：加商品/custom item → 綁顧客與市場幣別 → 套折扣運費 → 可 reserve items → 收款（send invoice 付款連結／代輸卡號／mark as paid／payment due later）→ 完成後轉正式 Order。
- Fulfill：在 Unfulfilled 卡選數量 → 填 tracking → 通知顧客 → committed 釋放、狀態推進；支援部分出貨。
- 訂單編輯：加/減品項、改數量、對新增項目給折扣 → 系統重算：差額為正 → send invoice 或直接收款；為負 → 退差額；已出貨項目與部分通路訂單有編輯限制 (待確認細節)。
- Refund / Return / Exchange：Refund 面板逐行選退數量、勾 restock、退運費、填原因、選是否通知。Return：選退貨品項與原因 → 提供退貨運送方式（產生/上傳 label 或無需寄回）→ 可加 exchange items（補收或退差額）→ 收貨後 mark as returned 並 restock → 開退款。支援顧客自助退貨與退貨規則。
- Fraud analysis：以 AVS、CVV、IP、多卡嘗試等指標給 low/medium/high 風險與建議；Shopify Payments 商家另有 Shopify Protect 詐欺保障 (適用範圍待確認)。

## 4. Customers 顧客

**目的與定位**：顧客檔案聚合身分、消費統計、同意狀態與訂單歷史，是分眾行銷與折扣資格判斷的基礎。首次下單或註冊即自動建檔（guest checkout 也會建檔）。

**主要畫面**：列表頁欄位約為 Customer name、Email subscription、Location、Orders、Amount spent，篩選以 segment 語法為底；詳情頁：最近訂單卡、Customer 卡（email/電話、行銷訂閱狀態）、Address book（多地址、default address）、Tax exemptions、Tags、Notes、Timeline、Metafields，右上顯示 amount spent / orders 數與 predicted spend tier。可合併重複檔案（`mergeable`）。

**核心資料物件**

- `Customer`：defaultEmailAddress、defaultPhoneNumber、addresses/defaultAddress、tags、note、taxExempt/taxExemptions、state（`ENABLED`/`DISABLED`/`INVITED`/`DECLINED`，新版 customer accounts 已弱化此概念 (待確認)）、amountSpent、numberOfOrders、verifiedEmail、statistics、mergeable。
- Marketing consent：`emailMarketingConsent` 與 `smsMarketingConsent` 各自含 marketingState（`SUBSCRIBED` / `NOT_SUBSCRIBED` / `PENDING` / `UNSUBSCRIBED`…）、optInLevel（single/confirmed opt-in）與 consentUpdatedAt——email 與 SMS 是**獨立**的同意狀態。
- Customer segments：以類 ShopifyQL 的 filter 語法建立**動態名單**：`filter名稱 operator 值`，支援 AND/OR 與括號、相對日期；常用 filter 如 amount_spent、number_of_orders、last_order_date、customer_added_date、customer_tags、email_subscription_status、products_purchased(id:)、abandoned_checkout_date、地區、predicted_spend_tier（個別拼寫待確認）。成員自動進出；可直接用於 Email 行銷與折扣的 customer eligibility。
- B2B（簡述）：`Company` + `CompanyLocation` 代表企業與據點，顧客經 contact profile 關聯為公司聯絡人；每公司可指定 catalogs（專屬選品與價格）、付款條件（net terms）；完整功能屬 Plus 級 (待確認)。

**邊界案例**：訂閱狀態只能記錄顧客明示同意（POS/匯入需注意）；刪除顧客受既有訂單限制。

## 5. Discounts 折扣

**目的與定位**：單一 Discounts 區統一管理四類折扣，決定價格計算、資格與可疊加性；折扣在稅前套用於小計。

**主要畫面**：列表頁欄位：標題（含 code 或 automatic 標記）、Status（Active / Scheduled / Expired）、Method、Type、Combinations、Used 次數；建立時先選類型再選 method。

**類型與類別（class）**

| 類型 | class | 說明 |
|---|---|---|
| Amount off products | product | % 或固定金額，適用指定 products/collections |
| Amount off order | order | 整筆訂單 % 或固定金額 |
| Buy X get Y | product | customer buys（最低數量/金額之指定商品）→ customer gets（指定商品 × 免費或 % off），可設每單套用次數上限 |
| Free shipping | shipping | 可限國家、可排除運費高於某金額的運送方式 |

**方法與條件**：discount code（顧客輸入，碼需唯一）vs automatic discount（符合條件自動套用）。共通設定：minimum requirements（無/最低金額/最低件數）、customer eligibility（所有顧客/指定 segments/指定顧客）、usage limits（總次數上限、每人一次）、active dates（起訖時間）、combinations。上限：同時啟用的 automatic discounts 至多 25 個；每店 code 總量上限約 20,000,000 (官方數字待確認)。

**組合規則（combinations）**：每個折扣以 `combinesWith`（productDiscounts / orderDiscounts / shippingDiscounts 三個布林）宣告可與哪些 class 疊加，**雙方都允許才會疊加**。shipping 折扣彼此不可疊（一單只取一個）；同一 line item 不疊加時取折扣較大者（best discount wins）；結帳同時生效的折扣數有上限（約 5 個 product/order + 1 個 shipping，待確認）；疊加時後續折扣以折後價續算。

**核心資料物件**：GraphQL 以 `DiscountNode` 包裝 `DiscountCodeBasic` / `DiscountCodeBxgy` / `DiscountCodeFreeShipping` / `DiscountAutomaticBasic` / `DiscountAutomaticBxgy` / `DiscountAutomaticFreeShipping` / `DiscountCodeApp`（Functions 自訂邏輯）；舊 `PriceRule` REST API 已走向棄用 (時程待確認)。訂單上以 discountApplications / allocations 記錄分攤到各 line 的金額。

**邊界案例**：折扣不套用於 gift card 商品；BxGy 的免費品仍佔庫存；code 與顧客 eligibility 綁定時須登入或 email 相符；排程折扣到 end date 自動轉 Expired。

## 6. 復刻要點 Checklist（本篇 → 工程）

1. 商品：options（≤3）× 變體展開器、Draft/Active/Archived 三態、collections 兩種型態（demo 可先做 manual + 簡化 smart 規則）。
2. 庫存：從第一天就用「數量狀態帳」模型（available/committed/on_hand + 調整原因 ledger），否則之後訂單流程會重寫。demo 可先單一 location。
3. 訂單：financial status 與 fulfillment status 是**兩條獨立狀態機**，列表 badge、詳情卡片、bulk 動作都掛在這兩條線上；Timeline 事件表從第一天記。
4. 顧客：email/SMS 同意狀態分開存；amount_spent / orders_count 做成可查詢的統計欄位（segments 的基礎）。
5. 折扣：用 class + combinesWith 模型設計，不要寫死「一單一折扣」；demo 先做 code × (order % / free shipping) 兩型。
