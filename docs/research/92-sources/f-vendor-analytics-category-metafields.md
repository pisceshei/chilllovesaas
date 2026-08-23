# 92-F — vendor／analytics／pivoting／dropshipping／category／metafields（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 F（研究代理原始報告，僅刪空行；主檔＝docs/research/92-products-manual-deep-dive.md）。

## 1. Managing vendor information（vendor 欄位管理）

**URL**：https://help.shopify.com/en/manual/products/managing-vendor-info（取證 2026-08-23）

### 欄位語義與值域
- Vendor＝商品的來源／出處，可以是店主自己或外部供應商。
- **每個商品只能指派一個 vendor**（單值欄位）。
- 商品未指派 vendor 時，**欄位預設值＝商店名稱**。
- 字元長度上限：**未取得**（本頁未載明）。

### 操作流程
- **依 vendor 排序**：Products 列表點 Vendor 欄標題 → 字母正序/倒序切換。排序**不影響前台顯示順序**。
- **依 vendor 篩選**：Products → 搜尋/篩選 icon → 選「Product vendor」選單 → 勾選 vendor → 可再排序 → 可將此檢視**存成自訂名稱的 saved view**。
- **報表篩選**：Analytics > Reports → 選報表 → Columns icon 加「Product vendor」欄 → 點欄標題排序 → filters icon 選「Product vendor」套用。
- **批次改 vendor**：兩條路——bulk editor 或 **CSV 匯入/匯出**。

### 前台顯示規則
- Shopify 自建主題兩處支援：Featured collection 區塊有「**Show vendor**」開關；Featured product 區塊加 text block 後**連接 dynamic source 到 Vendor 欄位**。
- 第三方主題看各自文檔。
- 讓**顧客**能按 vendor 篩選：需安裝 **Shopify Search & Discovery app**。

### 跨模塊互動（三條防混淆事實）
- **Shopify Bill Pay** 的 vendor（發票對象）與商品列表的 vendor **互不相連**，是兩套資料。
- **Stocky（POS 進貨）**會匯入 product vendor，可另建詳細 supplier profile；在 Stocky 裡**一個商品可有多個 supplier**（與商品 vendor 單值不衝突，屬 Stocky 自己的資料層）。
- **Shopify B2B**：可把客戶設成 company、給 vendor 專屬 pricing catalog（Basic 以上方案）。

## 2. Product analytics（商品分析）

**URL**：https://help.shopify.com/en/manual/products/analytics（取證 2026-08-23）
（指標細節深讀自 Inventory reports 頁：https://help.shopify.com/en/manual/reports-and-analytics/shopify-reports/report-types/default-reports/inventory-reports，取證 2026-08-23）

### 頁面結構
- Products 頁頂部有 **analytics bar（指標磚）**，點磚跳對應報表。
- 本頁連出四個報表錨點：Inventory analytics reports／Product sell-through rate／Days of inventory remaining／ABC analysis by product。

### 指標定義（精確公式）
| 指標 | 定義 | 計算窗 | 特殊處理 |
|---|---|---|---|
| **Product sell-through rate** | 售出量 ÷（售出量＋期末在庫量） | 概覽磚用最近 30 天；報表用所選期間（售出量算全期、在庫量取期末日） | **負庫存量一律忽略**；未開庫存追蹤的商品視為售出 0 |
| **Days of inventory remaining** | 期末量 ÷ 日均售出量 | 日均取**最近 28 天** | 期間無銷售 → **N/A**；期末量為負 → **0** |
| **ABC analysis by product** | 依**最近 28 天營收貢獻**給 variant 評級（**成本不入計算**），每日更新 | 固定 28 天回看 | A＝貢獻前 80% 營收；B＝次 15%；C＝末 5% |
| **Month-end inventory snapshot** | 每月月底各 variant 在庫量 | 近三年內有異動/訂購的 variant | **排除 committed 與 incoming** |

### 報表欄位
- Sell-through：product title / variant title / variant SKU / starting quantity / ending quantity / quantity sold / sell-through rate。
- Days remaining：product title / variant title / variant SKU / ending quantity / quantity sold per day / days remaining。
- ABC：product title / variant title / variant SKU / product grade / ending quantity / total value (cost) / total value (price)。
- Snapshot：product title / variant title / variant SKU / ending quantity。

### 規則
- **資料處理延遲約 2 天**（UTC+14 時區為 3 天）。
- 歷史資料**起算日 2023-10-01**。
- 已刪除商品的資料保留至 2026-01-14（其後刪除另有條件）。
- 方案門檻：本頁未提及（未取得明確的 plan gating）。

### 商品計數（product count）
官方載明三法：①Products 頁 URL 加 **`/count.json`**（只算商品不算 variant）；②建一個條件為「Price > $0」的 collection 看計數；③匯出 CSV（商品與 variant 都列）。

## 3. Pivoting your product line

**URL**：https://help.shopify.com/en/manual/products/pivoting-your-product-line（取證 2026-08-23）

- 本頁是**純商業策略內容**：四個方向（fulfill new needs／create new product lines／offer rentals／provide DIY kits），各附商品構想示例。
- **無任何操作流程、欄位、值域、狀態機或資料模型事實**。
- 結論：對商品資料模型實作**零貢獻**，登記為「已讀、無可落規格的事實」。

## 4. Dropshipping（只記商品資料模型相關）

**URL**：https://help.shopify.com/en/manual/products/dropshipping（取證 2026-08-23）

### 分支結構（5 子頁）
what-is-dropshipping／preparing-for-a-dropshipping-business／creating-a-product-line／shipping-strategies-for-dropshipping／recommended-dropshipping-and-pod-apps。前四頁逐一抽查後確認**均為商業內容，無資料模型事實**。

### 可落地的資料模型事實
- 整合形態＝**第三方 app 把供應商商品匯入店內、同步資料、代轉訂單**；help 文檔不載欄位映射細節（**未取得**：SKU/vendor/fulfillment service 的具體欄位行為）。
- **Shopify Collective**（第一方 dropshipping 網路）：從其他 Shopify 品牌匯入商品，**details／pricing／inventory 即時同步**；供應商出貨即自動處理款項；退貨自動化。
- Dropcommerce／Dropship／Syncee：供應商商品目錄＋訂單追蹤（無更深資料模型宣告）。
- POD（Gelato／Printful）：app 端負責印製、包裝、出貨——即 fulfillment 在 app 側完成。
- 通用整合模式（頁面原文歸納）：**匯入/同步商品資料、管理庫存更新、自動向供應商轉單、協調對客出貨**。
- 跨境：EU 銷售有 VAT/關稅義務影響定價（僅此一句）。

## 5. Product category（Standard Product Taxonomy）

**URL**：https://help.shopify.com/en/manual/products/details/product-category（取證 2026-08-23）

### 欄位語義與值域
- Category＝從 **Shopify Standard Product Taxonomy** 選一個預定義分類；**每商品恰一個 category**；**不能自創分類**。
- 未指派則存為「**uncategorized**」。
- 選擇準則（官方措辭）：依商品的**主功能**（main function）選。
- 層級路徑（breadcrumb）格式示例：`Home & Garden > Decor > Clocks > Alarm Clocks`；母語不可用時可用英文 breadcrumb。

### 操作流程
- **桌面**：Products → 開商品 → Category 區塊 →（打字搜尋選結果）或（逐層點選階層）→ Save。
- **行動**：Shopify app 同流程，tap 導航。
- **批次**：勾多商品 → Bulk edit → 需要時加 Product Category 欄 → 搜尋/瀏覽分類 → 存。
- **CSV**：接受 **category ID 或 breadcrumb 格式，二擇一不可同用**；支援 Google Product Category 映射（需英文精確匹配或 UID）。

### 自動建議
- 建商品時若已有名稱＋描述＋圖片，**Shopify Magic 自動生成 category 建議**，可接受或改選；同時**自動預填相關 category metafields**。

### Category 的作用（跨模塊，逐條）
1. **稅務**：分類**在 checkout 收集**用於判定正確稅率與**免稅（exemptions）**——category 對 Shopify Tax 的直接輸入。
2. **Category metafields**：指派分類即解鎖該分類映射的屬性欄位（如 shirt → size/neckline/sleeve length/fabric/color）。
3. **銷售通路**：供 Facebook/Google 等需要標準化 product type 的通路上架；**Instagram/Facebook checkout 因稅務原因要求 Google Product Categories**。
4. **退貨**：**退貨流程的 return reasons 依 product category 決定**；並連到 Analytics 的退貨模式報表。
5. **篩選**：支援 collection 條件與 admin 商品列表篩選；前台屬性搜尋。
6. 與 **Product type 是兩個欄位**：product type 是商店自訂自由欄位，category 是標準分類。

### 限制（頁面明載）
- 與 **Search & Discovery app、Shopify Bundles 不相容**（category metafields 層面）。
- 計量單位/尺寸類屬性不可用；**不支援自訂屬性**。
- swatch 功能有主題版本門檻。
- 新分類上線可能與既有通路相容性衝突。

## 6. Metafields（products 相關部分）

**URL**：https://help.shopify.com/en/manual/custom-data/metafields（取證 2026-08-23）
深讀子頁（均取證 2026-08-23）：metafield-definitions／metafield-definition-parts／metafield-types／metafield-lists／pinning-metafield-definitions／adding-values-to-metafields／category-metafields。

### 6.1 Definitions（定義 vs 值）
- Definition＝模板：規定 metafield 掛在哪類資源、可容納什麼值；**必須先建 definition 才能填值**。
- **Standard definitions**：Shopify 預配置、全平台通用、app/主題原生支援，**有得用就優先用**。**Custom definitions**：無 standard 可用或遷移舊 metafield 時建。
- **上限：每店 250 個 metafield definitions**。
- 定義六部件：**Name**（admin 顯示名）／**Namespace and key**（以 `.` 分隔的唯一識別，**只允許字母、數字、底線、連字號**，組合須店內唯一）／**Description**（選填）／**Type**（只接受該型別支援的值）／**Validations**（選填：字元上限、min/max、**支援 regex**）／**Options**（可用範圍）。Standard product 定義另有 **Categories** 部件。
- 保留 namespace 清單：**未取得**（definition-parts 頁未載明）。

### 6.2 Content types 完整枚舉（57 型，metafield-types 頁全量）

**Date and time**（2）：Date and time（ISO 8601 含 UTC；可 list）｜Date（ISO 8601；可 list）

**Measurement**（32，全部可 list，各帶單位枚舉）：Dimension｜Volume｜Weight｜Antenna gain（dBi/dBd）｜Area｜Battery charge capacity（mAh）｜Battery energy capacity（Wh）｜Capacitance（pF–F）｜Concentration（mg/g、mg/mL）｜Data storage capacity（B–TB）｜Data transfer rate（bit/s 系）｜Display density（PPI/DPI）｜Distance（km/mi）｜Duration（ns–年）｜Electric current（mA–kA）｜Electrical resistance（Ω/kΩ）｜Energy（J/cal 系）｜Frequency（Hz 系）｜Illuminance（lux/fc）｜Inductance（µH–H）｜Luminous flux（lm）｜Mass flow rate｜Power（mW–kW）｜Pressure（PSI/bar）｜Resolution（px/MP）｜Rotational speed（RPM）｜Sound level（dB）｜Speed（km/h、ft/s、mph、m/s）｜Temperature（°C/°F/K）｜Thermal power（BTU/h、kW、冷凍噸）｜Voltage（V）｜Volumetric flow rate

**Number**（2）：Decimal（範圍 **±9999999999999.999999999**；可 list）｜Integer（大範圍有號整數；可 list）

**Text**（3）：Single line text（可設 preset choices；**可 list**）｜Multi-line text（純文字含換行；**不可 list**）｜Rich text（標題/粗斜體/底線；**不可 list**）

**Reference**（9，全部可 list）：Product｜Product variant｜Collection｜File（**圖 <20MB；影片 <1GB 且 <10min；一般檔 <20MB**）｜Page｜Article｜Metaobject｜Company｜Customer

**Other**（7）：True or false（不可 list）｜Color（`#RRGGBB`；可 list）｜Rating（十進位刻度；可 list）｜ID（唯一單行文字；**不可 list**）｜URL（http/https/mailto/sms/tel；可 list）｜Money（整數/小數、幣別綁定；**不可 list**）｜Link（文字＋URL；可 list）

**Advanced**（2）：JSON（原始 JSON；不可 list）｜Mixed reference（任意 reference 型混排；可 list）

**List 支援總表**（metafield-lists 頁）：可 list＝text（single line）、number、color、link、url、weight、volume、dimension、rating、date、date and time、company、customer＋全部 reference 型。**list 項目數上限：未取得**。

### 6.3 在商品編輯頁上如何顯示（pinning）
- 商品編輯頁 **Metafields 區塊**：**pinned definitions 以可編輯表格顯示，順序＝definitions 列表中的 pinned 順序**。
- 未 pin 的 definition 不自動顯示，點「**View all**」才展開。
- **Pin 上限：每個資源區塊 50 個**。
- Pin/unpin 途徑：建立或編輯 definition 時勾選，或在 Metafield definitions 頁用 pin icon。
- POS：**商品 metafields pinned 與 unpinned 都顯示**；**customer metafields 只顯示 pinned（POS customer 詳情最多 20 個）**。
- 權限：管商品 metafields 需 staff 具「View, create and edit」商品權限。
- 填值流程（桌面）：導航至資源 → Metafields 區塊點欄位 → 依型別輸入（color 用揀色器/RGB、date 用日曆、reference 用選取器、measurement 選值＋單位、boolean 用 toggle）→ Save；行動版以 ✓ 確認代替 Save。

### 6.4 Category metafields
- 定義：taxonomy 內建的**商品屬性**，逐分類映射（選 `Apparel… > Shirts` 即解鎖 size/neckline/sleeve length 等）。
- 部分屬性依 **Shopify Magic 預測自動加入**，其餘列為建議可選加。
- 帶**預設 entries，可照用或自訂**（如把「black」改名「graphite」）；entries 以 **metaobjects** 為值載體。
- **可連接 variant options**：中央改名一次、全店該 variant 值同步更新；category 變更時已連接 variant 的值**保留**。
- Color entries 可在前台**以 swatch 呈現** variant 選項（有主題版本門檻）。

### 6.5 其他跨模塊
- 主題：支援 dynamic sources 的主題經 theme editor 連接 metafields；vintage 主題要改代碼；Liquid 可直接輸出。
- 非 reference 的 list 值可進 text/rich text sections；reference list 需 custom section 或第三方主題支援。

## 未取得清單
1. Vendor 欄位字元長度上限——help 頁未載明。
2. Metafield **保留 namespace** 清單——definition-parts 頁未載明。
3. Metafield **list 項目數上限**——metafield-lists 頁未載明。
4. 商品分析報表的方案（plan）門檻——頁面未提及。
5. Dropshipping 分支的欄位級同步映射——help 全分支皆為商業內容（屬 dev docs 範疇）。
6. Pivoting 頁：正面確認為純策略內容、無資料模型事實。
