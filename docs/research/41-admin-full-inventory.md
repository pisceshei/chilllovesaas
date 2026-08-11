# 41 — Admin 全頁面功能盤點（高保真原型與開發手冊的底冊）

> 目的：把 22 號「精華級按鈕表」深化到**全頁面、全控件、全流程**。每頁列出：佈局區塊、控件逐項表（控件／功能／邏輯與數值／操作流程／邊界情況）、與其他模組的關聯。已被既有文件覆蓋的部分標 `[22§x]`／`[21§x]`／`[24§x]`／`[29§x]` 並**只補新資訊**，不照抄。來源：help.shopify.com／shopify.dev／changelog.shopify.com（2026-08 逐頁查證）＋ 21 號 2026 春季版實測。原型狀態對照 `docs/design/chilllove-admin-v2.html`（v2）與 `chilllove-admin-preview.html`（v1）。

---

## 0. 頁面總表

編號規則：模組序－頁序。路徑為 Shopify admin 相對路徑（近似）。狀態：**完整**＝v2/v1 已有高保真頁；**佔位**＝v2 以 renderModule 通用殼呈現；**缺**＝原型完全沒有。

| # | 頁面 | 路徑 | 原型狀態 |
|---|---|---|---|
| 0-1 | 首頁（pulse＋Sidekick＋任務卡） | `/` | 完整（v2） |
| 0-2 | 全域搜尋 overlay | （CTRL K） | 佔位（殼有輸入框） |
| 0-3 | 通知中心 Alerts feed | （鈴鐺） | 缺 |
| 1-1 | 訂單列表 | `/orders` | 完整（v2） |
| 1-2 | 訂單詳情 | `/orders/:id` | 完整（v2） |
| 1-3 | 草稿訂單列表 | `/draft_orders` | 佔位 |
| 1-4 | 草稿訂單建單器 | `/draft_orders/new` | 缺 |
| 1-5 | 棄單列表＋詳情 | `/checkouts` | 佔位 |
| 1-6 | 運送標籤／批次出貨 | `/shipping_labels` | 缺 |
| 1-7 | 退貨建立 flow（訂單內） | `/orders/:id/returns/new` | 缺 |
| 1-8 | 退款 flow（訂單內） | `/orders/:id/refund` | 缺 |
| 1-9 | 編輯訂單 flow | `/orders/:id/edit` | 缺 |
| 2-1 | 商品列表 | `/products` | 完整（v2） |
| 2-2 | 商品詳情 | `/products/:id` | 完整（v1；v2 需移植） |
| 2-3 | 變體詳情（單變體頁） | `/products/:id/variants/:vid` | 缺 |
| 2-4 | Bulk editor（試算表） | `/bulk?resource=…` | 缺 |
| 2-5 | 系列列表 | `/collections` | 佔位 |
| 2-6 | 系列詳情（手動/智慧/新模型） | `/collections/:id` | 缺 |
| 2-7 | 庫存頁 | `/products/inventory` | 佔位 |
| 2-8 | 庫存調整歷史 | `/products/inventory/adjustments` | 缺 |
| 2-9 | 轉移列表＋詳情 | `/products/transfers` | 佔位（列表）/缺（詳情） |
| 2-10 | 採購單 | `/products/purchase_orders` | 佔位 |
| 2-11 | 禮品卡列表＋發卡＋詳情 | `/gift_cards` | 佔位 |
| 3-1 | 顧客列表 | `/customers` | 佔位（v2 有 AI 分群列殼） |
| 3-2 | 顧客詳情 | `/customers/:id` | 缺 |
| 3-3 | 分群列表＋分群編輯器 | `/customers/segments` | 缺 |
| 3-4 | B2B 公司列表＋詳情 | `/companies` | 佔位（列表）/缺（詳情） |
| 4-1 | Metaobjects 定義＋條目 | `/content/metaobjects` | 佔位 |
| 4-2 | 檔案庫 | `/content/files` | 佔位 |
| 4-3 | 選單（含轉址） | `/content/menus` | 佔位 |
| 4-4 | 部落格貼文列表＋編輯器 | `/content/articles` | 佔位 |
| 5-1 | 市場列表 | `/markets` | 佔位（v2 有 AI 建議行殼） |
| 5-2 | 市場詳情 | `/markets/:id` | 缺 |
| 5-3 | 目錄 Catalogs | `/catalogs` | 佔位 |
| 6-1 | 財務總覽 | `/finances` | 佔位 |
| 6-2 | 收款 Payouts | `/finances/payouts` | 缺 |
| 6-3 | 帳單 Billing | `/finances/billing` | 缺 |
| 7-1 | 分析 Dashboards | `/analytics` | 完整（v2） |
| 7-2 | 報告庫＋單一報告 | `/analytics/reports` | 佔位 |
| 7-3 | Live View | `/analytics/live` | 缺 |
| 8-1 | 行銷總覽（成長） | `/marketing` | 佔位 |
| 8-2 | 行銷活動 campaigns | `/marketing/campaigns` | 缺 |
| 8-3 | 自動化 automations | `/marketing/automations` | 缺 |
| 9-1 | 折扣列表 | `/discounts` | 佔位 |
| 9-2 | 折扣建立（四型表單） | `/discounts/new` | 缺 |
| 10-1 | 主題庫 | `/themes` | 佔位 |
| 10-2 | 頁面 Pages | `/pages` | 佔位 |
| 10-3 | 偏好設定 Preferences | `/online_store/preferences` | 佔位 |
| 10-4 | 主題編輯器 | `/themes/:id/editor` | 缺（規格在 24/31） |
| 11-x | 設定 20 分頁 | `/settings/*` | 12 分頁完整（v2）、其餘缺 |
| 12-1 | Checkout 編輯器 | `/settings/checkout/editor` | 缺（規格在 24§6） |

共 45 個可導航頁面（不含 modal/flow 級 7 個）。

---

## 1. 通用 Shell 與橫切機制

### 1.1 全域搜尋 [22§0]

補充（22 未載）：

| 控件 | 邏輯 | 流程／邊界 |
|---|---|---|
| 開啟 | `CTRL/⌘+K` 或點頂列搜尋框 | overlay 全螢幕置中 |
| 分類過濾 | 結果可按資源類別過濾（Orders、Products、Customers、Apps…），每類顯示**結果數量徽章** | 點類別 chip 縮小範圍 |
| 建議篩選 suggested filters | 輸入時系統推薦結構化篩選（帶預估筆數） | 點選直接跳轉到帶篩選的列表頁 |
| 最近搜尋 | 保留歷史、可一鍵清除 | 本機/帳號級儲存 |
| Sidekick 接手 | 無結果或複雜問題時顯示「Ask Sidekick」入口，把 query 轉給 AI 助理 | 2026 版把搜尋與 AI 打通的關鍵交互 |

### 1.2 通知中心（Alerts feed）

| 控件 | 邏輯 |
|---|---|
| 鈴鐺 icon（頂列） | 開啟 Alerts 側欄 feed |
| Alert 類型 | ①任務提醒（如未出貨）②服務中斷 disruption ③合規通知 ④交易確認 ⑤長流程完成（匯入/匯出 done） |
| 已讀管理 | 單則切換已讀/未讀；「全部標為已讀」 |
| 關聯 | 背景 job（CSV 匯入、批次動作、報告匯出）完成一律落 Alerts＋email，是「>50 筆轉背景」機制的回報面 |

### 1.3 檢視系統 saved views [22§0]

補充：2026 版存在**兩代列表頭**並存——

- **Enhanced search bar**（新，13 種資源：Abandoned Checkouts／Collections／Companies／Customers／Discounts／Draft Orders／Files／Gift Cards／Inventory／Metaobjects／Orders／Products／Transfers）：檢視切換器下拉（「全部 ⌄」）＋搜尋篩選一體欄；建自訂檢視＝先改預設 All 檢視再「Save view as」命名。
- **Tabbed views**（舊，8 種資源：Blog Posts／Catalogs／Customer Segments／Marketing Automations／Marketing Campaigns／Purchase Orders／Reports／Shipping Labels）：tab 列＋「+」新增檢視。
- 篩選語法：**空格＝AND、逗號＝OR**（`payment-status:Partially paid,Unpaid`）；支援 `is`/`is not`。
- **欄位編輯僅四頁支援**：Orders、Inventory、Transfers、Metaobjects——欄位設定存在檢視上、不影響其他檢視。
- **排序不隨檢視保存**：離開頁面即重設為預設排序（照抄此取捨可省 sort 持久化）。
- 預設檢視唯讀（不可改名/刪除）；自訂檢視改名/複製（帶原篩選）/刪除（不可復原）。

### 1.4 Bulk editor（批次編輯器）[22§0]

補充細節：

| 面向 | 邏輯 |
|---|---|
| 支援資源 | Products＋variants、Collections、Customers、Inventory（獨立進入點）；**不支援** blog posts/pages/redirects |
| 進入 | 列表勾選 → 「Bulk edit」；帶著勾選集合開試算表 |
| 欄位管理 | 「Columns」按鈕增減屬性欄；欄寬可拖曳 |
| 鍵盤/滑鼠 | 方向鍵移動；拖曳選相鄰多格；`Alt/⌘+點擊` 選不相鄰格；直接打字編輯；多格同時改（文字/數字/checkbox/下拉皆可）；**fill handle 垂直拖曳填滿** |
| 儲存 | 顯式 Save；先驗證後提交；錯誤訊息「Update the invalid values, then save again」——**錯誤可能在隱藏欄位**（SKU 必填、metafield 驗證失敗），要能自動展開出錯欄 |
| 邊界 | 多 SKU 變體的庫存只能在 Inventory 版 bulk editor 改；Edge 瀏覽器 URL 長度問題（勾選集合以 URL 傳遞的實作痕跡——我們改 POST 即可）；大量編輯建議走 CSV |

### 1.5 CSV 匯入匯出 [22§0]

**商品 CSV 全欄位**（匯入格式；UTF-8＋LF；15MB 上限）：

| 欄 | 約束/行為 |
|---|---|
| Handle | 變體列的分組鍵；字母/數字/連字號、無空格；同 handle 多列＝同商品的變體與圖片列 |
| Title | **新增商品唯一必填欄**；變體延續列留空 |
| Body (HTML) / Vendor / Tags | 變體延續列留空；Tags ≤250 個、逗號分隔 |
| Product Category | 標準 taxonomy 全路徑或 category ID |
| Type | 自訂類型字串 |
| Published | true/false（預設 true） |
| Option1/2/3 Name＋Value | ≤3 選項；**改 Option Value 會刪舊變體 ID 生新 ID（斷外部引用）**——我們 diff 更新策略優於此，註記差異 |
| Variant SKU | 用自訂 fulfillment service 時必填 |
| Variant Grams | 整數克；預設 0 |
| Variant Inventory Tracker | `shopify`/第三方名/空 |
| Variant Inventory Qty | 僅單地點店可用；預設 0 |
| Variant Inventory Policy | `deny`(預設)/`continue` |
| Variant Fulfillment Service | `manual`(預設)/自訂服務名 |
| Variant Price / Compare At Price | 純數字無幣symbol；預設 0.00 |
| Variant Requires Shipping / Taxable | true(預設)/false |
| Variant Barcode | ISBN/UPC/GTIN |
| Image Src / Position / Alt Text | 公開 `https://` URL，匯入時下載；Position 從 1；Alt ≤512 字（建議 ≤125）；≤250 張 |
| Variant Image | 該變體圖 URL |
| Variant Weight Unit | g/kg(預設)/lb/oz |
| Variant Tax Code | Plus＋第三方稅務服務用 |
| Cost per item | 成本 |
| Gift Card | true/false；**CSV 不能建新禮品卡商品，只能改** |
| SEO Title / Description | ≤70 / ≤320 字；fallback 用 Title/Body |
| Google Shopping / * | GMC 落欄（category、gender、age group、MPN、condition、custom labels…） |
| Included / [市場名]、Price / [市場]、Compare At Price / [市場] | 每市場發布開關＋固定價 |
| Status | `active`(預設)/`draft`/`archived` |

匯入語意 [22§0]：勾「Overwrite matching handles」時**留空欄＝清空、整欄省略＝保留**；依賴欄缺失會連帶刪除。顧客 CSV：訂單數/消費額唯讀不可匯入。庫存 CSV：僅 On hand 可寫＋防過期校驗欄。

### 1.6 鍵盤快捷

- `?` 開啟快捷清單 overlay（`esc` 關）。序列鍵**左到右、約 1 秒內按完**（例：`A` `P` = 新增商品；反序無效）。`CTRL/⌘+K` 搜尋。官方不再提供完整清單網頁（藏在 admin 內）——原型做 `?` overlay＋十個常用即可。

### 1.7 行動版差異（Shopify app）

- 權限鏡像 desktop（無 Home 權限 → app 不顯示 Home tab）。
- 推播：新訂單/出貨/重要警示/timeline @提及；iOS 專屬：app badge 顯示未處理訂單數、可換 app icon。
- app 內獨立語言覆寫設定。行銷自動化在 mobile 只有部分模板。相機直接拍商品圖；POS 為獨立 app。
- 原型策略：admin 做 responsive（34 號規格），推播列入 P2。

---

## 2. 訂單模組

### 2.1 訂單列表（/orders）[22§1a][21§2]

**佈局**：頁頭（標題＋匯出／更多動作／建立訂單）→ 檢視列（檢視下拉＋搜尋篩選一體欄＋排序＋欄位設定）→ 表格（勾選欄＋資料欄）→ 分頁。另有「批次處理近期訂單」按鈕（跳 1-6 批次出貨）。

**欄位全集**（可經欄位設定增減，存在檢視上）[21§2]：訂單號／日期／顧客／總計／付款狀態／出貨狀態／品項數／配送狀態／配送方式／標籤／管道／出貨期限／目的地／風險。取消單整列劃線；多幣別顯示 presentment 金額。

**篩選 24 維全集**（22 只列舉部分，此為全量）：

| 篩選 | 值域 |
|---|---|
| Order status | Open／Archived／Canceled |
| Payment status | Authorized／Due／Expired／Paid／Partially paid／Partially refunded／Pending／Refunded／Unpaid／Voided |
| Fulfillment status | Fulfilled／Unfulfilled／Partially fulfilled／Scheduled／On hold／Request declined |
| Delivery status | In transit／Out for delivery／Attempted delivery／Delayed／Failed delivery／Delivered／Tracking added／No status |
| Return status | Return requested／Return in progress／Return closed |
| Label status | No label／Draft created／Purchased／Printed |
| Chargeback status | Open／Submitted／Won／Lost |
| Order total | 精確值或區間 |
| Delivery method | In store／Local delivery／Pickup in store／Pickup point／Shipping |
| Destination | 洲/國/州省/無目的地 |
| Address validation | Has issues／No issues／Not validated |
| Number of items | 精確或區間 |
| Total product weight | 精確或區間 |
| Product | 指定商品 |
| Discount code | 指定碼 |
| App | 指定 app／Draft Orders／Online Store |
| Channel | 指定管道 |
| B2B | Include／Exclude |
| Payout action required | Action required／No action |
| Fraud risk | High／Medium／Low |
| Credit card last 4 | 精確 |
| Tagged with / Not tagged with | 標籤 |
| Date | Today／Last 7/30/90 days／Last 12 months／自訂 |
| （另）Metafield 篩選 | 需先 pin 訂單 metafield definition |

批次動作、匯出對話框見 [22§1a][22§0]。地點切換器（多地點店）作用於所有檢視。

**關聯**：付款狀態源自金流模組；出貨期限與 Shipping labels 頁互通；風險欄連 Fraud analysis；B2B 篩選連 Companies。

### 2.2 訂單詳情（/orders/:id）[22§1b][21§2]

**佈局區塊圖**：

```
麵包屑 ＋ #訂單號 ＋ [付款badge][出貨badge][退貨badge?] ＋ 日期/管道
右上：退款 | 編輯 | 更多動作⌄ | ↑↓上下筆
────────────────主欄────────────────┬──────側欄──────
① 出貨卡（未出貨/已出貨/on hold，可多張   │ ⑤ 備註 Notes
   ：品項列+數量+「標記為已出貨⌄」split） │ ⑥ 其他詳細資訊（metafields）
② 付款卡（小計/折扣/運費/稅/總計/已付；   │ ⑦ 管道資訊
   Authorized 時有 Capture 區）          │ ⑧ 顧客卡（連結+訂單數）
③ 退貨卡（有退貨時：狀態+品項+處理鈕）    │    聯絡資訊/收件地址/帳單地址
④ 時間軸 Timeline（留言框+事件流）        │ ⑨ 轉換摘要 Conversion summary
                                        │ ⑩ 訂單風險 Fraud analysis
                                        │ ⑪ 標籤 Tags
```

**更多動作⌄ 清單**：Duplicate／Cancel／Archive(Unarchive)／View order status page／列印裝箱單／Edit（＝頂部同款）／Print order。

各按鈕邏輯（Refund/Edit/Duplicate/Cancel/Archive/Fulfill/Capture/Collect payment/顧客區）全在 [22§1b]，不重複。**補充**：

| 控件 | 補充邏輯 |
|---|---|
| 出貨卡 hold | on hold 有原因 enum＋手動 hold ≤10 個；split button 展開：標記為已出貨／購買運送標籤／請求出貨（第三方 fulfillment service） |
| 時間軸事件型別 | 下單/付款/授權/capture/退款/出貨/配送狀態更新/編輯差異/退貨事件/風險評估/通知寄送（含 email 送達狀態）/app 動作/員工留言 |
| Conversion summary | 首次工作階段來源→下單 session 鏈（第 N 次造訪下單）；點開看完整 session 歷程 |
| Fraud analysis | 指標紅綠清單（AVS/CVV/IP 距離/嘗試卡數…）＋「查看完整分析」；高風險建議顯示於頂部 banner |
| 退貨卡 | 進行中退貨顯示：品項＋退貨原因＋運送方式（標籤/追蹤）＋「處理退貨」CTA；outstanding balance banner 顯示待收/待退差額 |
| 側欄地址 | 收件地址可編（觸發稅重算差額流 [22§1b]）；帳單地址唯讀；「查看地圖」外鏈 |

**關聯**：退款→金流＋庫存 restock；出貨→庫存 committed 釋放；時間軸 events 是分析與通知的資料源；tags 進全域標籤系統。

### 2.3 草稿訂單（/draft_orders）[22§1c]

**列表**：欄＝草稿號/日期/顧客/狀態（**Open／Invoice sent／Completed**）/總計；批次動作：刪除、加/移標籤。**2025-04-01 後建立的草稿，閒置 1 年自動刪除**（新規）。

**建單器佈局**：主欄＝①商品卡（搜尋+Browse／加自訂品項）②付款卡（小計/折扣/運費/稅/總計＋收款區）；側欄＝③顧客卡④市場/幣別⑤備註⑥標籤（每個 ≤40 字）。

**控件逐項**（[22§1c] 之外的補充）：

| 控件 | 邏輯與流程 |
|---|---|
| 品項列編輯 | 每列可改單價（鉛筆 icon）、數量、行級折扣（金額/%＋原因）；移除 |
| Reserve items | 選到期日**含時間**；Available→Unavailable；到期自動釋放 |
| 折扣 | 可套**既有折扣碼**或自動折扣，也可自訂 order 級 amount off（值+原因）；行級與單級可並存 |
| 運費 | 三來源：店內費率（需先有顧客+地址）／Local delivery／Local pickup／自訂（名稱+價格） |
| 稅 | 預設按店稅設定自動算；可整單勾掉 charge taxes |
| 市場/幣別 | 啟用國際銷售時可選市場 → 以該市場定價與幣別；**匯率在開發票那刻鎖定** |
| Payment due later | 條款 enum：Due on receipt／Due on fulfillment／Net 7/15/30/45/60/90／固定日期；**Plus 可加 % 訂金 deposit** |
| 收款三途 | Send invoice（自訂訊息＋允許折扣碼開關＋忽略結帳驗證勾選）→顧客走結帳連結；Enter credit card（代輸卡號）；Mark as paid |
| B2B 草稿 | 選 company location 後帶入其 catalog 價格、付款條件、稅設定 |
| 完成轉正式單 | 付款完成或 mark as paid → 產生訂單（保留草稿號關聯）；狀態 Completed |

**關聯**：折扣引擎共用；結帳連結複用 checkout；B2B 連 companies/catalogs；reserve 寫 inventory ledger。

### 2.4 棄單（/checkouts）[22§1d]

補充：列表欄含 **Email status**（已寄/未寄挽回信）與 **Recovery status**（Not recovered／Recovered）；可與訂單一起匯出。手動挽回流程＝開單一棄單→點顧客 email→開本機郵件客戶端帶結帳連結（**不是站內寄信**——站內自動信走行銷自動化）。自動挽回信已遷移至 **Shopify Messaging 自動化**（見 §9.3；舊版通知設定 legacy 併存，有 opt-in 遷移頁）。不寄信的邊界：付款處理錯誤／地址不支援配送／只留電話沒 email／庫存全無／全免費商品。保留 3 個月自動刪；可轉草稿留存。

### 2.5 運送標籤／批次出貨（/shipping_labels）

2025-2026 的新一級頁（訂單子導航「運送標籤」）。

| 控件 | 邏輯與流程 |
|---|---|
| 批次 batch | 兩種建法：①自動批次＝**近 14 天未出貨單**一鍵成批 ②列表勾選→Create batch；**每批 ≤250 個 fulfillments** |
| 工作流步驟 | 預設三步可自訂：**Pick**（產撿貨單 pick list PDF）→ **Print**（買標籤＋裝箱單＋報關文件）→ **Pack**（掃碼核對） |
| Buy shipping labels（批次） | 表格式逐單確認：包裹尺寸/重量/服務等級可逐列改→一次購買全批標籤；費用記平台帳單 [22§1b 買標籤欄位] |
| 列印 | 標籤/裝箱單/撿貨單成 PDF 文件列表，隨時重印 |
| Group by batch | 訂單列表欄位設定裡的開關，把列表按批次分組 |
| 檢視 | 本頁屬 tabbed views 家族（§1.3） |

**關聯**：購買標籤自動標記出貨＋回填追蹤碼；費用進 §6 帳單；label status 回填列表篩選。

### 2.6 本地配送與取貨（履約面）

設定面在 §12（運送分頁），這裡是訂單操作面：

| 流程 | 邏輯 |
|---|---|
| Local delivery 單 | 訂單標 delivery method=Local delivery → 出貨卡變「準備配送」：標記 Out for delivery（寄通知）→ Delivered；可用 Shopify 的 Local Delivery app 排路線（地圖+順序+司機分享） |
| Pickup 單 | 出貨卡變「準備取貨」：**Ready for pickup**（自動寄「可取貨」通知，含地點指示）→ 顧客到店 → **Mark as picked up**（可選寄確認信）；跨店調貨用「Transfer to pickup location」 |
| 邊界 | 取貨單不可買運送標籤；配送單無追蹤碼欄（用 out-for-delivery 狀態流） |

### 2.7 退貨與換貨（Return + Exchange）[22§1d]

**建立流程**（訂單詳情 → Return）：

```
① 選品項+數量（僅已出貨未退款項）→ 每項選退貨原因（按品類動態：服飾=Too big/Too small…）
② Summary 區：restocking fee（可按整單或逐項改）＋ return shipping fee（僅整單級）——預設值來自 return rules
③ （可選）Exchange：Add products 加換購品項（不可自訂品項；可加 product 級折扣；不可套 order 級折扣）
④ 退貨運送三選一：Shopify 產生退貨標籤（限美國寄件+收件）／上傳標籤（PDF/PNG/JPEG 或 URL＋追蹤碼+carrier）／No shipping required
⑤ Create return → 訂單掛 Return in progress badge
```

**處理流程**：收貨後「處理退貨」→ 逐項選 receive 數量＋restock 地點（可部分，多次處理）→ 退款（當下或稍後）。**restocking fee 按實際處理數量計**；return shipping fee 只在第一次處理時收；**部分多次處理與一次全處理的金額結果可能不同**（照抄此語意）。財務三情境：應退→退款；應收（換購差額）→寄發票或事後收款；等額→直接沖銷。**換購品項在處理前不佔庫存**。

**狀態機**：Return requested（自助退貨申請）→ Return in progress → Returned/Closed（全項處理+restock 自動關；可手動關/重開）。**Cancel return** 僅限：未退款、未 restock、未標 returned、無平台標籤、fulfillment 未取消；取消後不可重開。

**邊界**：退款後不能再建退貨；含關稅 (duties) 的訂單不能加換購；權限分離（Return／Refund to original／Refund to store credit 三權限）。

**Return rules（設定 → 政策區）**：退貨窗 14/30/90/無限/自訂天，起算點二選一（**逐品項送達日** vs **整單最後一項送達日**）＋「順延週末假日到下個工作日」勾選；退運費三選（免費/固定費每退一次/顧客自購標籤）；restocking fee %勾選；Final sale 排除清單（**商品或系列擇一，不可混**）；**可按市場覆寫**；適用含 B2B 單。自助退貨（customer accounts）開關為店級。

**關聯**：return rules 與 Markets 聯動；自助退貨連顧客帳號；restock 寫 inventory ledger（reason=return）；退款連金流。

---

## 3. 商品模組

### 3.1 商品列表（/products）[22§2][21§2]

欄：商品（縮圖+名）/狀態/庫存（「N in stock for M variants」；0 紅字）/類別/類型/供應商/管道數/市場數。篩選：狀態/管道/市場/類別/類型/供應商/tag/gift card/庫存量/發布錯誤。批次動作：bulk edit（§1.4）／設為 active/draft/archive／刪除／加管道/移管道／加tag/移tag／加入系列/移出系列。頁頭：匯出/匯入/更多動作（產生分類建議等）/新增商品。50 筆/頁。

### 3.2 商品詳情（/products/:id）[22§2][21§2]

**佈局區塊圖**：

```
──────主欄──────────────────────┬──────側欄──────
① 標題（≤255）                   │ ⑨ 狀態（Active/Draft/Archived
② 說明（富文本 64KB+✨AI+HTML 切換）│    +Unlisted [22§2]）
③ 多媒體（≤250；首格=精選圖）      │ ⑩ 發布（管道+市場清單、
④ 類別（taxonomy 自動建議）        │    排程、B2B catalogs）
⑤ 定價（price/compare-at/         │ ⑪ 商品整理（type/vendor/
   cost/margin/profit/charge tax） │    collections/tags）
⑥ 庫存（SKU/條碼/track/继续销售/   │ ⑫ 佈景主題範本
   五狀態量 per location）         │ ⑬ 銷售紀錄卡 Insights
⑦ 運送（實體勾/重量/包裹/報關）    │
⑧ 子類（變體）→ §3.3              │
⑭ 商品中繼欄位 metafields ＋ Disclosures
⑮ 搜尋引擎（SERP 預覽+編輯）
浮動 Save bar（dirty 才亮）[v1 原型已做]
```

各區塊邏輯 [22§2] 已覆蓋主幹。**補充**：

| 區塊 | 補充 |
|---|---|
| 定價 | Margin/Profit 即時算：`(price−cost)/price×100`；cost 不對外；**Tax code 欄**（Plus＋第三方稅服務才顯示）；**Unit pricing**（歐盟單位價：每 100ml 之類，特定市場強制） |
| 類別 | 選定後解鎖 **category metafields**（如服飾解鎖 size/color/material 標準欄），可綁定variant 選項；影響稅則與通路 feed |
| 運送 | 「這是實體商品」勾掉→隱藏重量/報關；Package 選預設包裹；報關＝Country/Region of origin＋HS code（摺疊） |
| Disclosures | 法規揭露區（安全警語/能源標章等，按市場法規）——2025 新增 |
| Insights 卡 | 銷售件數/顧客數/淨銷售額＋跳分析報告 |
| 發布 | 每管道可設**排程上線時間**；B2B catalogs 並列；變體層級可單獨排除於管道 |
| Product ID | admin URL 尾碼即 ID（客服/外部引用用） |

### 3.3 變體矩陣操作 [22§2]

**選項→變體生成**：

| 操作 | 邏輯 |
|---|---|
| 新增選項 | 「+ 新增尺寸/顏色等選項」→ 選項名（可連 category metafield 標準值）＋值列表（拖曳排序、inline 改名）；≤3 選項 |
| 變體生成 | 選項值笛卡兒積自動生成 ≤2048 變體；生成後逐列顯示於「子類」表：縮圖/選項值/價格/庫存量/SKU |
| 分組顯示 | 表頭「Group by」按任一選項分組摺疊；組級顯示合計庫存與價格區間 |
| 列內編輯 | 價格/庫存直接 inline 改；點列進**單變體頁**（2-3）：完整欄位（價格/compare-at/cost/SKU/條碼/重量/報關/圖片綁定/per-location 庫存）＋左側變體切換清單 |
| 批次操作 | 勾選變體→批次改價/庫存/刪除，或「Edit in bulk editor」開試算表（§1.4） |
| 變體圖片 | 變體綁媒體庫中一張圖；同選項值可一鍵套同圖 |
| 邊界 | 改選項名/值在 Shopify=重建變體（斷 ID）[22§2 我們用 diff 更新]；刪選項值→連帶刪變體（確認對話框）；每變體可獨立設「實體商品」與稅 |

### 3.4 Purchase options（訂閱／預購／TBYB）

商品頁「購買選項」區塊＋app 承載：

| 類型 | 邏輯 |
|---|---|
| Subscriptions | 訂閱方案＝名稱+頻率（週/月/自訂）+折扣%；一商品可多方案；由 Subscriptions app（官方或第三方）寫入 selling plan；前台購買選項 widget 顯示單購 vs 訂閱價；**存卡由平台託管，商家不可見全卡號** |
| Pre-orders | 預購=先收全款或訂金（deposit %）+ 預計出貨日；下單即建訂單但 fulfillment hold |
| Try before you buy | 先出貨後扣款：下單時 authorize/存卡，試用期滿 capture；像一般單出貨 |
| 通用 | 三者皆為 **deferred purchase options**（selling plans 模型）；折扣的 purchase type 欄（§10）與此聯動 |

**關聯**：草稿單/折扣的 purchase type；訂閱連顧客 payment methods；預購連 fulfillment hold。

### 3.5 系列 Collections（/collections）[22§2]

**2026 重大變化：新集合模型**（gradual rollout，legacy 手動/智慧並存）：

| 面向 | 新模型 | Legacy [22§2] |
|---|---|---|
| 類型 | **單一統一類型**：同一系列可同時有規則+手動 | 手動 vs 智慧不可互轉 |
| 來源 sources | 多來源並集：①規則自動含入 ②手動加商品 ③**嵌套其他系列** ④app 寫入 | 單一來源 |
| 排除 | 規則自動排除＋手動排除清單 | 無排除概念 |
| 遷移 | 既有系列自動轉換；未 rollout 的店維持 legacy | — |

**條件引擎**（legacy 智慧系列，仍是規則語意基準）[22§2]：≤60 條件、any/all 切換、全店智慧系列 ≤5,000。條件欄位×運算子（is equal to／is not equal to／is greater than／is less than／starts with／ends with／contains／does not contain／is not empty…按欄位型別出現）：Title／Type／Category／Vendor／Price／Tag／Compare-at price／Weight／Inventory stock／Variant's title／Metafield（需先建 definition）。

**系列詳情頁**：標題/描述（富文本）/商品區（手動=拖曳排序；規則=條件編輯器）/排序 8 種（手動排序僅手動系列）/搜尋引擎/發布（管道+排程）/圖片/佈景主題範本/metafields。

### 3.6 庫存頁（/products/inventory）[22§2]

五欄帳（Unavailable/Committed/Available/On hand/Incoming）、Adjust by vs Set to、原因 7 種（Correction (default)／Cycle count／Damaged／Promotion or donation／Quality control／Received／Theft or loss…）、180 天調整歷史、CSV 規則——[22§2] 全覆蓋。**補充**：Unavailable 可展開子原因（draft reserve／return in progress／safety stock?／app hold）；地點切換器決定顯示哪個 location 帳；**盤點無獨立頁**——實務=匯出 CSV 盤點後以 Set to+Cycle count 原因回寫（POS 端另有盤點工具，不在 admin 範圍）。

### 3.7 轉移 Transfers（/products/transfers）

比 [22§2] 完整的狀態機與 shipments 子模型：

| 狀態 | 語意 |
|---|---|
| Draft | 不佔庫存；唯一可刪狀態；可改起訖點 |
| Ready to ship | **起點庫存轉 reserved**（可選狀態，可跳過） |
| In progress | 建 shipment（s）；目的地記 **Incoming** |
| Transferred | 全部收貨完成，目的地轉 Available |
| Canceled | reserved 釋放回起點 |

| 控件 | 邏輯 |
|---|---|
| 起訖點 | 皆可留空（=外部供應商/外部目的地） |
| 商品 | 搜尋加入＋「Move」欄填量；顯示兩端即時庫存影響；支援 CSV 匯入變體清單 |
| Metadata | Reference name／Notes／Tags／metafields |
| Shipments | 一轉移可多 shipment（各自 ID）：追蹤碼（自動辨識 carrier）＋預計到達日＋**條碼（≤250 字元，供掃碼收貨）**＋成本調整欄（運費/關稅攤提） |
| 收貨 | 逐項 Accept（轉 Available）/Reject（記錄不動帳）/部分收（維持 In progress）；可批次全收/全拒；可留 comment；收錯用「Manage received items」改收/拒/取消量 |
| 處理後編輯 | 已處理不可改起訖點；仍可加減商品與調量、改追蹤 |

### 3.8 採購單 Purchase orders [22§2]

補：PO 欄位=供應商（供應商檔案：公司+地址+聯絡人）/目的地 location/付款條件（Net…）/幣別/預計到貨；行=變體+supplier SKU+成本+數量+稅%；Mark as ordered 後記 Incoming；收貨介面同轉移（accept/reject）；tabbed views 家族。

### 3.9 禮品卡（/gift_cards）[22§2]

補充列表與詳情：列表欄＝末4碼/顧客/餘額/狀態（**啟用中/已停用/已過期/已用罄**）/建立日/到期日；篩選同 enhanced search bar 家族。發卡表單 [22§2]：面額（≤$2,000）/自動或自訂碼/顧客（必填 email 或電話）/到期日（法規提示：多數地區禁過期）/內部備註。詳情頁：餘額+交易列表（單號連結/日期/金額）/重寄/停用（**永久**）/改到期日。設定分頁另有「禮品卡到期」全域政策＋Apple Wallet 開關。

**關聯**：結帳可用卡支付（gift card 支付列於付款卡）；餘額變動寫 transactions；分群可用 store_credit（店內額度另一系統）。

---

## 4. 顧客模組

### 4.1 顧客列表（/customers）[22§3][21§2]

欄（可選）：名/姓/email/電話/email 訂閱狀態/SMS 訂閱/地點/訂單數/消費金額/tags/metafields/**CLV 預測**。批次：加減 tag/改名改姓/三通道行銷同意/metafields/合併/刪除（不合格者靜默跳過）。頂部 **AI 分群輸入列**（自然語言→segment 草稿）[21§1.6]。搜尋支援名/email/電話/卡末四碼。

### 4.2 顧客詳情（/customers/:id）[22§3]

**佈局**：主欄＝①指標列（總消費/訂單數/顧客時長）②最後訂單卡③時間軸（事件+留言；**通知寄送含送達狀態、自動信可重寄，手動信不可**）；側欄＝④顧客卡（語言/email/電話→「Change contact information」dialog）⑤預設地址（多地址管理：新增/編輯/設預設）⑥行銷同意（email/SMS/WhatsApp 三通道；顯示同意來源與時間）⑦稅務（**免稅三態＋VAT 號自動驗證**；加拿大特例豁免清單）⑧付款方式（存卡：寄更新連結 or 代換卡）⑨店內額度 Store credit（發放/扣減，帶到期日）⑩標籤（合併時上限 250）⑪備註（≤5,000 字）⑫metafields。

**刪除/合併/匿名化**規則 [22§3]。補：合併阻擋清單新增 multipass 登入與 pending redaction；刪除阻擋：有訂單/待遮蔽/訂閱/排程禮品卡。

### 4.3 分群 Segments（/customers/segments）[22§3]

**編輯器**：程式碼式輸入（語法高亮+自動完成 chips）＋左側 filter 目錄面板＋模板 gallery＋「Apply filter」即時人數與成員預覽。存檔後動態成員（即時計算，非快照）。tabbed views 家族。

**過濾器全集**（[22§3] 只有精華；此為逐項）：

| Filter | 運算子 | 值 |
|---|---|---|
| `abandoned_checkout_date`、`customer_added_date`、`first_order_date`、`last_order_date` | `= != < <= > >= BETWEEN IS NULL/NOT NULL` | `YYYY-MM-DD` 或相對偏移 `-7d/-4w/-10y` |
| `amount_spent`、`number_of_orders` | 比較全套+BETWEEN | 數字（無幣符） |
| `orders_placed()` 函式 | `MATCHES/NOT_MATCHES/IS NULL` | 參數：`app_id, location_id, count, amount, sum_amount, date` |
| `products_purchased()` 函式 | 同上 | 參數：`id（≤500 個）, quantity, sum_quantity, date, tag` |
| `storefront.product_viewed()`/`.collection_viewed()` | 同上 | `id(≤500), date, count, tag` |
| `shopify_email.{bounced/clicked/delivered/marked_as_spam/opened/unsubscribed}()` | 同上 | `activity_id, count, date` |
| `customer_within_distance()` | 同上 | `coordinates`＋`distance_km/mi` |
| `store_credit_accounts()` | 同上 | `balance, currency, next_expiry_date, last_credit_date` |
| `anniversary()` | `= != BETWEEN IS NULL` | 事件日（如 `metafields.facts.birth_date`）；**忽略年份** |
| `customer_cities/customer_countries/customer_regions` | `CONTAINS/NOT CONTAINS/IS NULL` | `國-州-城市` 碼／ISO |
| `customer_tags` | `CONTAINS/NOT CONTAINS/IS NULL` | 不分大小寫 |
| `customer_email_domain` | `= !=` | `'gmail.com'` |
| `customer_language` | `= !=` | `'en'/'en-US'` |
| `email_subscription_status` | `= !=` | `SUBSCRIBED/NOT_SUBSCRIBED/PENDING/INVALID/UNSUBSCRIBED/REDACTED` |
| `sms_subscription_status` | `= !=` | 同上（無 INVALID） |
| `customer_account_status` | `= !=` | `DECLINED/DISABLED/ENABLED/INVITED` |
| `predicted_spend_tier` | `= !=` | `HIGH/MEDIUM/LOW` |
| `rfm_group` | `= !=` | `CHAMPIONS/LOYAL/ACTIVE/NEW/PROMISING/NEEDS_ATTENTION/AT_RISK/ALMOST_LOST/PREVIOUSLY_LOYAL/DORMANT/PROSPECTS`（11 組） |
| `product_subscription_status` | `= !=` | `SUBSCRIBED/CANCELED/EXPIRED/FAILED/NEVER_SUBSCRIBED/PAUSED` |
| `companies`（Plus） | `CONTAINS` | company ID |
| `created_by_app_id` | `= !=` | app ID |
| Metafield filters | 依型別 | 需 pin 顧客 metafield definition |

布林組合：`AND/OR/()` 巢狀。分群用途出口：Shopify Email 受眾／折扣資格／顧客列表篩選。

### 4.4 B2B 公司（/companies，Plus）

| 面向 | 邏輯 |
|---|---|
| Company | 名稱（必填）＋Company ID（外部 ERP 同步鍵）＋主聯絡人＋稅 ID；**≤10,000 locations、≤10,000 customers** |
| Company location | 每 location 獨立：收/帳地址、稅 ID+免稅、付款條件（Net terms+**% deposit**）、**≤25 catalogs**、**≤50 customers**、結帳設定（下單即成單 vs **送審為草稿**、允許臨時運送地址開關） |
| 成員權限 | 兩角色：**Ordering only**（下單+看自己訂單）／**Location admin**（下單+看全 location 訂單+改地址） |
| 列表 | enhanced search bar 家族；欄=公司/locations 數/成員數/訂單數/消費額 |
| 訂購流 | B2B 顧客登入 → 選 location → 看 catalog 價 → 下單（依 location 設定成單或送審）；admin 端可代建 B2B 草稿單 |

**關聯**：catalogs（§5.3）、付款條件（同草稿單 terms）、customer accounts（新版必須）、market 型別 COMPANY_LOCATION [29§1]。

---

## 5. 內容模組（Content）

### 5.1 Metaobjects（/content/metaobjects）[22§6]

| 控件 | 邏輯 |
|---|---|
| 定義列表 | 欄=名稱/type ID/條目數/使用位置 |
| 建定義 | 名稱→自動生成 **type**（存檔前可改，存後鎖定）；欄位（fields）逐個加：名稱+型別（§12.15 全型別表）+描述+驗證（字數/min-max/regex/預設值集）；**Display name** 指定一個 text 欄（預設第一個 text 欄，無則自動編號） |
| 能力開關 | 每定義四開關：後台可見／**Storefronts**（Liquid+Storefront API 讀取）／**Web pages**（條目生成 URL＋可選 template，`/pages/{handle}` 型路由＋SEO 欄）／Translations |
| 條目列表 | 每定義一個條目列表（enhanced search bar 家族；欄位=display name+欄位摘要+狀態） |
| 條目編輯 | 依定義動態渲染表單；狀態 **Active/Draft**；handle；被引用處列表 |
| 主題引用 | theme editor 的 dynamic source 可綁 metaobject 欄位 [24§4]；section preset 可直連條目 |

### 5.2 檔案庫（/content/files）[22§6]

補：欄=縮圖/檔名/類型/大小/引用數/建立日；上傳一次 ≤20 檔（圖 ≤20MB/25MP、影 ≤1GB、其他檔 ≤20MB）；動作=複製 CDN 連結/下載/改 alt（圖）/重命名/刪除（引用中檔案跳警告列出引用處）；篩選=類型（Images/Videos/Documents）/大小/上傳日/「Used in」（引用位置）；搜尋檔名。商品媒體與主題上傳的檔案同池。

### 5.3 選單（/content/menus）[22§6]

補：選單詳情=標題+handle+項目樹；項目=名稱+連結（型別：首頁/系列/**所有系列頁**/商品/頁面/部落格/部落格文章/政策頁/外部 URL/email `mailto:`/電話 `tel:`；搜尋式 picker）；**巢狀 ≤3 層**（拖曳縮排）；儲存整樹一次提交。**URL 轉址**在同頁入口：列表（from→to）＋新增（舊路徑必須以 `/` 開頭且不存在於現站）＋CSV 匯入/匯出。上限：轉址無實務上限（十萬級）。

### 5.4 部落格（/content/articles）[22§6]

補：貼文列表（tabbed views；欄=標題/作者/部落格/狀態[可見/隱藏/已排程]/發布日）。編輯器區塊：標題（≤255）/內容富文本（同商品編輯器+✨AI 生成）/**摘要 Excerpt**（列表頁用）/搜尋引擎/精選圖/可見性（Visible/Hidden+**排程發布日時**）/所屬部落格（下拉+inline 新建）/作者（員工下拉）/標籤/佈景主題範本。**部落格管理**（blogs）：每 blog=標題+handle+**留言設定三態**（Comments disabled／Moderated（待審）／Auto-published）+SEO+範本。留言審核：待審列表→Approve/Delete/Mark as spam（spam 訓練）。

**關聯**：選單可連結 blog/article；文章 SEO 進 sitemap；留言 captcha 受 §11.3 spam 設定管。

---

## 6. 市場 Markets（/markets）[29][21§2]

29 號已完整（模型/翻譯/多幣/目錄）。此處補 admin UI 操作面：

| 控件 | 邏輯 |
|---|---|
| 列表 | 左=資料夾樹（商店預設值/地區分組），右=市場表（市場/狀態 Active-Draft/包含國家數/自訂項目摘要）；**AI 建議行**（sparkle：「建立 International 市場」可關）[21§1.6]；右上「圖表檢視」（世界地圖著色） |
| 建市場 | 名稱+選國家群（搜尋+洲分組勾選）；**一國僅屬一市場**，加入時自動從原市場移出（含確認）；也支援其他條件型市場（B2B company location／retail location／sales channel） |
| 市場詳情 | 卡片：①狀態 ②條件（國家清單）③Domains and languages（三選一策略+語言+default）④Currency and pricing（base/local currencies 開關/手動匯率/**price adjustment ±%**/**rounding 開關**）⑤Duties ⑥**Shipping**（§12.7 shipping options by market 的市場入口）⑦Catalogs ⑧Theme content（跳 theme editor 該市場 context）→ 全項見 [29§1.2] |
| 刪除 | 把國家移走即自動縮減；空市場自動刪；backup region 在 Settings→General [29§6] |
| 商店預設值 | 樹頂節點=預設幣別/語言/國家（主市場） |
| View as 預覽 | 商品頁與前台可以市場 context 預覽價格/可售性 |

**目錄 Catalogs（/catalogs）**：列表（tabbed views）；目錄=名稱+適用對象（市場 or B2B company locations）+狀態；內容=**發布範圍**（含入哪些商品/變體）+**價格**（整體 ±% adjustment 或逐變體固定價，固定價優先）[29§1.3]。**關聯**：B2B、Markets、商品發布卡。

---

## 7. 財務 Finance（/finances）[21§2]

| 頁 | 區塊 |
|---|---|
| 總覽 | 卡片流：收款啟用大卡（未開 Shopify Payments 時）/交易摘要/餘額（Balance）/稅務設定卡/工具（Bill Pay）/Credit 申請卡；2FA 未開的警示 banner |
| Payouts | payout 排程（每日/每週/每月+起始日）/待轉餘額/payout 列表（日期/金額/狀態 In transit-Paid-Failed）→ 單一 payout 拆解（charges−refunds−fees+adjustments）；匯出對帳 CSV [22§7] |
| Billing | 訂閱帳單+app 費用+運送標籤費+網域費；帳單週期（30 天）；付款方式管理；發票下載 |
| Tax | 銷售稅申報摘要（美國各州 collected 額+申報連結）；Shopify Tax 功能（rooftop 精度/類別稅則）入口 |
| Credit / Bill Pay / Capital | 金融產品家族（申請/額度/還款）——原型僅留卡片殼 |

**關聯**：payouts 對帳連訂單 transactions；Billing 收 §2.5 標籤費；稅卡連 §12.8。

---

## 8. 分析

### 8.1 Dashboards（/analytics）[22§5][21§2]

補：頂部篩選列=日期區間（含比較期）+幣別+管道；卡片=stat 卡（大數字+delta+sparkline）與圖表卡（線/柱/圓環/表格）；卡片右上「⋯」=查看報告/移除；**Customize 模式**：拖入指標庫/重排/縮放/具名區段/Reset to default；「新增探索」=從 dashboard 直建自訂報告；「試用目標」=目標追蹤 beta。**同數字同源鐵律**（CLAUDE.md #7）在此驗收。

### 8.2 報告庫（/analytics/reports）[22§5]

- 列表：tabbed views；欄=名稱/分類/作者（Shopify or 員工）/最後查看；搜尋+分類篩選。
- **分類 11 種**：Acquisition／Behavior／Customers／Finance／Fraud／Inventory／Marketing／Order／Profit／Retail sales／Sales（代表報告：sales over time、sales by product/variant SKU/channel/discount/billing location、AOV、customers over time、first-time vs returning、conversion over time、sessions by referrer/device、payouts、taxes、inventory levels…；**全量清單官方頁未枚舉，原型以分類+代表例即可**）。
- 單一報告頁：圖表+表格（**上限 1,000 列但總計含全部** [22§5]）；工具列=日期/比較期/篩選/群組 group by/**編輯欄位**；改動後「另存為自訂報告」→ 同時生成 dashboard 可用的 metric card；匯出取全量。
- **ShopifyQL**：自訂報告底層查詢語言（`FROM sales SHOW total_sales BY month SINCE -12m` 形態）；新版以「探索 exploration」視覺化編輯為主、QL 為進階模式。

### 8.3 Live View（/analytics/live）[22§5]

補全控件：3D 地球/2D 地圖切換+Streamer mode（隱藏數字，桌面限定）三態切換；**藍點=近期 session、紫點=訂單**；可旋轉/縮放/地點搜尋/最大化。指標：Visitors right now（近 5 分活躍）/Total sessions（**午夜起，店時區**）/Total sales（gross−discounts−reversals+shipping+taxes）/Total orders（全管道）；**Customer behavior 漏斗（近 10 分鐘）**：Active carts→Checking out→Purchased；Top locations/Top products/Customers 卡。點任何指標卡跳對應詳細報告。

---

## 9. 行銷（成長 Growth）[21§2]

### 9.1 行銷總覽（/marketing）

區塊：期間選擇器＋歸因銷售額/工作階段（依流量類型細分）/轉換率 stat 卡＋管道成效表（每管道 sessions/orders/sales）＋「Campaign Autopilot 搶先體驗」banner [21§2]＋最近活動列表。**歸因設定**入口：attribution model 選擇（first-click／last-click／last non-direct click，預設 last non-direct click）與回溯窗設定（詳值見§15 無法查證）。

### 9.2 行銷活動 Campaigns（/marketing/campaigns）

- Campaign＝多活動容器（目標+期間）；活動 activity＝單一投放（Shopify Email/社群貼文/廣告，由對應 app 提供）。
- 列表（tabbed views）：欄=名稱/狀態（草稿/進行/已排程/結束）/管道/sessions/orders/sales（歸因口徑）。
- 建立：選 app→編內容（Email：受眾=分群、模板編輯器、測試信、排程送出）→發布；UTM 自動掛（utm_campaign=活動名）。
- 活動詳情：成效卡（reach/opens/clicks/orders/sales）+時間線。

### 9.3 自動化 Automations（/marketing/automations）

**2025-26 遷移重點：行銷自動化住在 Shopify Messaging app（Apps→Messaging→Automations）**，admin 行銷區為入口鏡像；棄單自動信從「通知設定」遷來（有 opt-in 遷移頁）。

模板全集（四類）：

| 類 | 模板 | 觸發 |
|---|---|---|
| Recover site visitors | Abandoned checkout／Abandoned cart／Abandoned product browse | 棄結帳/棄購物車/瀏覽未加購，延遲 N 小時 |
| Welcome new subscribers | Welcome discount（單封）／Welcome series（1+2 封） | 新訂閱 email |
| Post-purchase | Thank you（首購/二購）／First purchase upsell／Customer win-back（N 天未回購）／Drive to retail | 訂單事件+時間 |
| Customer appreciation | Birthday discount／VIP welcome | anniversary/分群進入 |

每個自動化：開關（Active/Paused）＋**工作流編輯**（開 Shopify Flow 編輯器：trigger→condition→wait→action 圖）＋郵件模板編輯（品牌色/logo）＋成效（reach/sessions/orders/sales）。**與 Flow 的關係**：模板=預製 Flow workflow；進階客製直接在 Flow 改。

**關聯**：受眾=分群（§4.3）；折扣碼自動生成連 §10；email 事件回流分群 filter `shopify_email.*`。

---

## 10. 折扣（/discounts）[22§4]

列表與配額 [22§4] 已覆蓋。此處補**四型建立表單逐欄位**：

**共同骨架**（依序區塊）：Method（Discount code／Automatic discount 切換）→ 值與範圍 → 資格與條件 → Combinations → Active dates → 右側 Summary 卡（即時彙總語意句+效能區）。

| 區塊 | 欄位與邏輯 |
|---|---|
| Method | code：碼輸入+「Generate random code」；automatic：Title（顧客在結帳看得到） |
| 值（Amount off products） | Percentage or Fixed amount＋值；**Applies to**：specific collections/specific products（picker ≤100 項）；fixed+指定品項時出現「**Only apply discount once per order**」勾選（不勾=每合格品項都折） |
| 值（Amount off order） | %/固定值；作用於小計 |
| Buy X（customer buys） | 二選一：**Minimum quantity of items** / **Minimum purchase amount**＋「Any items from」products/collections picker |
| Get Y（customer gets） | Quantity＋items picker＋折扣深度三選：**Percentage／Amount off each／Free**；「**Set a maximum number of uses per order**」勾選；X=Y 同品時**取顧客所選較低價那件折** |
| Free shipping | 國家範圍：All countries / Selected countries；「**Exclude shipping rates over a certain amount**」勾選+金額 |
| Purchase type | One-time purchase／Subscription／Both（啟用訂閱才顯示）；訂閱時多「限首期/限 N 期」選項 |
| Minimum requirements | None／Minimum purchase amount／Minimum quantity of items；**指定品項折扣時只有合格品項計入門檻** |
| Customer eligibility | All customers／Specific customer segments（自動折扣 ≤5、碼 ≤100 [22§4]）／Specific customers／指定市場 |
| Maximum discount uses | 「Limit number of times…in total」+數字；「Limit to one use per customer」（以 email/電話判定） |
| Combinations | 勾選可疊的 class：Product discounts/Order discounts/Shipping discounts（規則細節 [22§4]） |
| Active dates | 開始日+時間；「Set end date」勾選+結束日時；時區=店時區 |
| 其他 | Tags；自動折扣可勾「Also offer on POS（POS Pro 地點）」 |

**折扣詳情頁**：Summary＋效能（使用次數/歸因銷售）＋時間軸；動作=停用/重啟/複製/刪除/**推廣**（分享連結帶自動套碼+導向頁選擇+QR code [22§4]）。

**關聯**：purchase type↔purchase options；eligibility↔segments/markets；套用計算順序與金額引擎（specs/17）。

---

## 11. 線上商店（銷售管道 > Online Store）

### 11.1 主題庫（/themes）[22§6]

補：頁面結構＝當前主題大卡（預覽縮圖+主題名版本+「Customize」主 CTA+「⋯」選單）→ 主題庫列表（每主題：縮圖/名稱/版本/加入日+動作選單）→ 底部「Visit Theme Store」/「Upload zip」/AI 生成入口。動作選單全集：Customize／Publish（確認 dialog；原主題自動退回庫）／Preview／Rename／Duplicate／Download（寄信 zip）／**Edit code**（code editor：檔案樹+多 tab 編輯器+搜尋）／**Edit default theme content**（靜態字串翻譯面板）／Delete（確認）。試用主題（Theme Store 試裝）：可自訂**不可改碼**、發布前須購買；分享預覽連結：訪客 2 天/員工 30 天 [22§6]。主題更新：新版可用時卡上出現「Update available」（保留自訂 merge 流程）。

### 11.2 頁面 Pages（/pages）

列表（欄=標題/可見性/最後更新）；編輯器：標題/內容富文本（同商品）/搜尋引擎/**可見性（Visible/Hidden+排程發布）**/佈景主題範本。刪除即斷連結（提示建轉址）。

### 11.3 偏好設定（/online_store/preferences）[22§6]

逐項：①首頁 title+meta description（SERP 預覽）②社群分享圖（建議 1200×628）③**Spam 防護**：hCaptcha 兩開關——聯絡/留言表單、登入/註冊/找回密碼（**2026 為 hCaptcha，非 Google reCAPTCHA**）④**密碼保護**：開關+密碼+訪客訊息（Pause and Build 方案強制開）⑤國際導向：依地區自動轉市場網域開關+依瀏覽器語言轉 locale 開關+**hreflang 自動輸出開關（預設開）**。

**關聯**：密碼頁連主題 password template；hreflang 連 Markets [29]；分享圖 fallback 進 SEO 模組 [30]。

---

## 12. 設定（/settings/*，2025-26 版全分頁）

**框架** [21§1.8]：settings modal 左欄＝**組織區**（組織名＋「組織/使用者」→ 使用者管理已上移組織層）→ 商店區（店徽+網域）＋分頁清單。以下逐分頁；[22§8] 覆蓋者只補新料。

### 12.1 一般 General [22§8]
補：卡片流＝商店詳情（名稱/email 兩枚：sender email+聯絡 email）/**商家詳細資訊 business entity**（法律實體，金融/市場/稅用）[21§1.8]/商店預設值（幣別顯示→導去 Markets 管理、單位制、時區）/訂單編號前後綴/**backup region**（市場移除國家後的兜底定價區）[29§6]。

### 12.2 方案 Plan [22§8]
補：方案卡（現行方案+價格+週期 月/年切換）/比較表 modal/Pause and Build 申請/關店流程（結清→斷網域→2 年可復原）。

### 12.3 帳單 Billing
＝§7 Billing 的設定鏡像：付款方式/帳單門檻/發票列表/幣別。

### 12.4 使用者 Users（組織層）[22§8]
補：成員列表（姓名/email/角色/2FA 狀態/最後登入）；邀請（單發或 CSV）；**角色 roles**＝權限集模板（可自建）；協作者（4 碼申請碼）；安全區（強制 2FA/登出全部裝置/停用保留紀錄）。**權限全目錄**（granular，13 類；實作 Pundit 對照表）：
- Orders：View／Manage order info／Edit／Apply discounts／Set payment terms／Charge credit card／Charge vaulted card／Record payments／Capture／Fulfill and ship／Buy shipping labels／Return／Refund to original／Refund to store credit／Cancel／Export／Delete／Abandoned checkouts manage／Disputes manage
- Draft orders：View／Create-edit／Apply discounts／Set payment terms／Charge card／Charge vaulted／Mark as paid／Export／Delete
- Products：View／View cost／Create-edit／Edit cost／Edit price／Export／Delete；Inventory：Manage／View transfers／Manage transfers／Manage shipments；Catalogs：View／Create-edit／Delete；Gift cards：View／Create-edit／Export／Deactivate
- Customers：View／Create-edit／Erase personal data／Request data／Export／Merge／View store credit tx／Edit store credit／Delete
- Analytics：Reports／Dashboards；Marketing；Discounts；Content（Menus/Metaobject definitions×3/Entries×3）；Files×4；Online Store：Themes／Edit code／Blog posts and pages；Checkout and customer accounts×3；Companies×7；App development×3
- Store settings：Manage settings／View billing／Edit billing payment／Manage plan／Manage app billing／Payments settings／Shipping and delivery／Taxes and duties／Locations／Store credit／Domains／Transfer domain／View customer events／Manage custom pixels／Manage store policies
- Finance：View payouts／View tax documents／Balance activity／Credit activity／Payments payouts／Manage other payment settings；Apps and channels：Install／Approve charges；POS device setup

### 12.5 付款 Payments [22§8]
補：Shopify Payments 卡（KYC 啟用流/測試模式/payout 排程/帳單敘述名）；備選收單（PayPal/第三方 gateway 清單+費率提示）；手動付款方式（自訂名+指示+付款期限）；**Capture 三模式**（結帳自動/出貨後自動/純手動，授權期 7 天）[22§8 修正版]。

### 12.6 結帳 Checkout [24§5]
24 號已逐欄位（聯絡方式/姓名地址欄三態/行銷同意/小費/訂單處理/自動封存/棄單信 legacy 開關）。補：頂部「**Customize checkout**」進 checkout 編輯器 [24§6]；checkout profile 概念（Plus 多 profile）；**one-page vs three-page 已統一為 one-page**。

### 12.7 運送與配送 Shipping and delivery
**2026 結構性改版：Shipping options by market**（逐店 rollout，與 legacy profiles 並存）：

| 概念 | 新模型 | Legacy [22§8] |
|---|---|---|
| 組織單位 | **每市場**配置 shipping options | shipping profiles（General+Custom ≤99）×zones |
| 層級 | Market → Shipping option（Standard/Express…顧客可見名）→ Rates | Profile → Zone → Rate |
| 繼承 | 子市場**繼承**父市場設定，可覆寫（影響子不影響父）；多父市場=結帳合併顯示 | 無繼承 |
| Rate 型別 | **四型**：Flat／Order amount 條件（金額 min-max）／Weight 條件／Carrier-app calculated；同 option 內 flat+order amount 可並存**取最高符合者**；weight/carrier 型每 option 限一 | 同 zone 多 rate 並列 |
| 商品條件 | rate 可限定「全市場商品或指定 collections」——**取代 custom profiles 的角色** | custom profile 綁商品 |
| 地點條件 | rate 可掛「Ships from」locations 條件 | per-location rates |
| 結帳 | 只顯示符合訂單+地址的 options，**預設選最便宜** | 跨 profile 運費相加 [22§8] |

本分頁其餘區塊：Local delivery（每 location：半徑 ≤160km/100mi **或**郵遞區號清單 ≤3,000 字元（支援 `M5V*` 萬用）；**≤10 區/地點**；每區=基本費+**≤3 條金額條件規則**+最低訂單額+說明訊息；多區符合取最低價；**Apple/Google/Amazon Pay 與 PayPal 不支援本地配送**）／Pickup in store（每 location 開關+備貨時間下拉+跨店調貨另設時間+取貨指示覆寫通知模板）／包裹 Saved packages／裝箱單模板（Liquid）／Carrier accounts。**前置規則：國家必須先屬於某個 active market 才能配送**（2023 changelog 起）。

### 12.8 稅務與關稅 [22§8]（登記/含稅/覆寫/DDP 已覆蓋，無新料）

### 12.9 地點 Locations [22§8]
補：每 location=名稱+地址+「**Fulfill online orders from this location**」開關；停用前置=移走庫存與待出貨單；**出貨優先序**拖曳清單=自動分單 routing；app 地點（3PL/代發）唯讀列出、不佔配額。

### 12.10 顧客帳號 Customer accounts
補齊 [22§8] 一句話版：版本二選一（**新版**：6 碼 OTP passwordless+Shop Sign-in/社群登入+365 天 session+託管帳號頁+結帳自動填；**Legacy**：密碼制+主題內頁面）；登入連結顯示開關（頭部 icon）；自助退貨開關（連 return rules）；店內額度顯示；**Plus 可接自有 IdP**；帳號頁 URL（`shopify.com/xxxx/account` 型託管網域或自訂）。B2B 強制新版。

### 12.11 網域 Domains
補：列表（網域/類型 主要-子網域-國際/狀態/SSL 狀態）；動作=Buy new domain（搜尋+年費+自動續約）/Connect existing（引導改 A/CNAME→自動驗證輪詢→SSL 自動簽發）/Transfer in；**myshopify.com 網域終身只可改名 1 次**；設 primary+「Redirect all traffic to primary」開關（國際網域策略時關閉）；國際網域綁市場 [29§1.2]。

### 12.12 通知 Notifications [22§8]
**顧客通知模板清單**（分類→模板；每個=Liquid 編輯+預覽+測試寄送）：
- Orders：Order confirmation（**不可停用**）／Order edited／Order invoice／Order canceled*／Order refund*／Payment error／Pending payment（success/error）／POS 收據家族／Gift card created
- Shipping：Shipping confirmation*／Shipping update*／Out for delivery*／Delivered*（*=可停用）
- Local delivery/pickup：Out for delivery／Delivered／Missed delivery／Ready for pickup／Picked up
- Returns：Return created／Return label／自助退貨審核結果
- Customer：Customer account invite／Welcome／Password reset／Marketing confirm
- 棄單挽回=已遷移行銷自動化（§9.3），此處僅 legacy 開關
**員工通知**：New order（可多收件人+per-location 過濾）／desktop 推播；**Webhooks 管理入口**（建 webhook：topic+URL+格式 JSON/XML+API 版本）。

### 12.13 自訂資料 Custom data [22§8]
定義管理（資源分類：Products/Variants/Collections/Customers/Orders/Draft orders/Companies/Locations/Pages/Blogs/Articles/Markets/Shop）＋每 definition：namespace.key/型別/驗證/**pin**（pin 了才出現在資源頁卡片與列表篩選）/存取權（storefront 讀取開關）。**型別全集**（＝metaobject 欄位同池）：`single_line_text`／`multi_line_text`／`rich_text`／`number_integer`／`number_decimal`／`date`／`date_time`／`money`／`url`／`json`／`boolean`／`color`／`weight`／`volume`／`dimension`／`rating`（需 min/max）／`id`／`link`／`language`／參照型：`file_reference`／`product_reference`／`variant_reference`／`collection_reference`／`page_reference`／`customer_reference`／`company_reference`／`order_reference`／`article_reference`／`metaobject_reference`／`mixed_reference`／`product_taxonomy_value_reference`；**list.* 變體**：所有參照型+多數基本型（**除** boolean/json/money/multi_line/rich_text/id/language）。

### 12.14 語言 Languages [29§2]
補：語言列表（預設+已發布+未發布；**≤20 種**）；動作=Add language→翻譯途徑（Translate & Adapt app）；publish/unpublish；每市場語言子集在 Markets 配 [29§1.2]。

### 12.15 政策 Policies [22§8]（六類+模板生成+固定 URL `/policies/*`；退貨政策與 return rules 分離——政策是文案、rules 是機器規則）

### 12.16 品牌 Brand
Logo（default+方形）/色（primary/secondary+對比檢查）/slogan/短描述/社群連結/封面圖——供管道與 app（Shop app、社群卡）與 checkout 預設取用；Liquid `shop.brand` 可讀。

### 12.17 隱私 Customer privacy [22§8]（cookie banner 按地區/GPC/隱私政策生成器/資料銷售退出）

### 12.18 顧客事件 Customer events（custom pixels：新增 pixel=名稱+JS 沙箱代碼+訂閱事件 checkout 完整事件流；狀態 connected/disconnected）

### 12.19 應用程式與銷售管道 Apps and channels（已裝 app 列表/權限審視/卸載；管道=Online Store/POS/Shop/**Agentic** [21§1.4]…；pin 到側欄）

### 12.20 禮品卡 Gift cards（到期政策+Apple Wallet passes 開關）→ §3.9

---

## 13. 模組關聯總圖（文字）

- **訂單**←草稿（轉正）、棄單（挽回→結帳）、退貨（restock→庫存、退款→金流）、標籤（→財務帳單）、B2B（terms/catalog 價）
- **商品**→庫存（五欄帳）→轉移/採購單（Incoming）；→系列（規則引擎吃 type/vendor/tag/price/metafield）；→市場/目錄（發布+定價）；→主題（template 指定、dynamic sources 吃 metafields）
- **顧客**→分群→（折扣資格、Email 受眾、列表篩選）；→B2B 公司；→行銷同意→通知/自動化
- **設定**是所有模組的參數面：運送（市場×option×rate）/稅/地點（routing）/通知（模板）/自訂資料（全資源 metafields）/權限（每按鈕的可見性）
- **分析**吃 events/orders/sessions rollup；行銷歸因反寫 campaigns；Live View 吃即時 sessions
- **內容**（metaobjects/files/menus/blog）全部被主題編輯器 dynamic source 消費 [24§4]

---

## 14. 來源 URL

help.shopify.com/en/manual/…：
- fulfillment/managing-orders/viewing-orders/filtering-orders；viewing-orders/searching-orders；returns/creating-returns；returns/return-rules；create-orders/create-draft；create-orders/send-draft；fulfilling-orders/batch-fulfillment
- orders/abandoned-checkouts；promoting-marketing/create-marketing/abandoned-checkouts；promoting-marketing/create-marketing/marketing-automations/create；promoting-marketing/create-marketing/migrate-abandoned-checkout
- products/details/product-details-page；products/variants；products/purchase-options；products/collections/smart-collections/create；products/collections/new-collections-model；products/inventory/transfers/create-transfer；products/gift-card-products；products/import-export/using-csv
- shopify-admin/productivity-tools/searching-filtering-views；bulk-editing；keyboard-shortcuts；shopify-admin/shopify-admin-overview；shopify-admin/shopify-app/using-the-shopify-app
- customers/manage-customers；customers/customer-segmentation/reference-guide/shopify-segments；customers/customer-accounts；b2b/companies
- custom-data/metaobjects；online-store/menus-and-links；online-store/setting-up/preferences；online-store/themes/managing-themes；online-store/blogs
- markets；finance；reports-and-analytics/shopify-reports/report-types；shopify-reports/live-view；shopify-reports/custom-reports
- discounts/discount-types/percentage-fixed-amount；discount-types/buy-x-get-y；discount-combinations
- your-account/users/roles/permissions/store-permissions；locations；domains；fulfillment/setup/notifications/customer-notifications；fulfillment/setup/shipping-options/understanding-shipping-options-by-market；fulfillment/setup/delivery-methods/local-delivery/setting-up-local-delivery；delivery-methods/pickup-in-store

shopify.dev：docs/apps/build/custom-data/metafields/list-of-data-types；docs/api/shopifyql/segment-query-language-reference

changelog.shopify.com：changes-to-shipping-and-markets-settings；purchase-shipping-labels-in-bulk-from-the-shipping-labels-page；new-views-for-fulfillment-details-and-shipping-labels

（另：21/22/24/29 號內部文件為本篇的既有底座。）
