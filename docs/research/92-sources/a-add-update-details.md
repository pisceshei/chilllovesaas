# 92-A — add-update-products／details 全欄位（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 A。分支 1 `/products/add-update-products` 為**單一頁**（index 所列子項全是同頁錨點）；分支 2 `/products/details` 實抓 16 頁（含 pricing 4 子頁＋smart-pricing 5 孫頁＋descriptions 2 子頁＋type/insights/sku/tags/category）。無「未取得」頁。

## Adding and updating products（…/products/add-update-products）

### 操作流程（原文步驟）
- **Add**：Products → Add product → title＋細節 → Save。
- **Duplicate**：商品 → Duplicate → 複本 Title →（可選）勾選要複製哪些 details → Product status 選 draft/active/unlisted → Duplicate product。
- **Preview**：商品 → Preview（mobile＝View on Online Store）。
- **Availability**：Publishing 區 Adjust icon → 勾/取消 sales channels → Done → Save。
- **Tags**：Product organization 區 Tags 欄選既有或輸入新名點 Add；移除點各 tag 的 x。
- **SEO listing**：Search engine listing 區鉛筆 → Page title → Meta description →（可選）URL handle → Save。
- **Scan barcode（僅 mobile app）**：Inventory 區 Barcode 欄點條碼 icon 開相機 → 對準 → 自動填入。
- **Archive**：詳情頁 Archive product → 確認。**Unarchive**：Archived tab → 商品 → Unarchive product。
- **Delete**：詳情頁 Delete product → 確認。

### 值域與上限
- Tags：單 tag **255 字元**；每商品 **250 個**；**Plus 無上限**。
- SEO：Page title **70**／Meta description **320** 截斷閾值。
- URL handle：自動生成；可編輯但「不要太常改」；**不得含空格**。
- **>50 locations 時必須先儲存商品才能加庫存量**。

### 狀態機／規則
- **Duplicate**：「除 3D models 與 videos 外，所有其他細節自動複製」；複本獨立；**設 Active 時自動發佈到與原品相同 channels**；catalog 只在「Automatically include new products」開啟時跟隨。
- Delete＝**永久、不可復原**。
- Unlisted＝只能經直接 URL 存取。
- 「改動可能影響報表」。

## Product details page（…/details/product-details-page）——欄位參考主頁

### 列表級狀態操作
- 勾選商品後：`Set as active`、`Set as draft`、⋯ > `Archive products`、⋯ > `Unlist products`。
- Product ID＝admin URL `products/[PRODUCT_ID]`。

### 逐欄語義
- **Title**：無字元上限記載。**Description**：rich text；可 Shopify Magic 生成。
- **Media**：images、3D models、video。
- **Category**：標準 taxonomy；**每商品一個、套用到所有 variants**；Shopify Magic 自動推薦；作用＝category metafields／篩選／多管道／**Shopify Tax 稅率**。
- **Price**：幣別取自 Settings > General。**Compare-at price**：降價時的原價。
- **Tax code**：**僅 Plus＋第三方稅務服務時顯示**。
- **Unit pricing**：顯示於 product/collection/cart/checkout 頁＋order confirmation。
- **Cost per item**：選填；Profit/Margin＝`(price−cost)/price×100`；🔴 **勾 Charge tax 時 profit/margin 不顯示**；不適用 gift card 商品。
- **SKU**：「每個 SKU 必須唯一」。
- **Barcode**：必須是真 GTIN；「**不得捏造假 GTIN**」；部分管道要求 GTIN 才能發佈。
- **Quantity 五量**：Unavailable/Committed（draft order 轉正式前不計）/Available/On hand（＝C+A+U）/Incoming。
- **Shipping**：「physical product」開關＝**條件顯示閘門**（Weight＋Customs 只在開啟時顯示）；Package 用於單件訂單運費計算與運標；Customs＝COO（最終成形地）＋HS code（關鍵字搜尋）。
- **Purchase options**：Subscriptions/TBYB/Preorders；可限制僅購買選項或並存。
- **Metafields**：詳情頁可編輯表格。
- **Product disclosures**：法定警示。
- **Publishing**：channels＋markets＋B2B catalogs；**預設全選**；可控 variants 進哪些管道。
- **Insights**：售出件數、顧客數、net sales → View details。
- **Product organization**：Type（**每商品一個**）／Vendor／Collections（手動加入；條件自動的不能從這裡移除）／Tags。
- **Theme template**：預設 **`Default product`**；live theme 有其他 product template 時列入下拉。

### 狀態機（權威定義）
- **值域＝Active／Draft／Archived／Unlisted＋Shopify 施加的 Suspended／Pending suspension**：
  - **Active**：可售；**新商品預設**。
  - **Draft**：不可售；**複製與 unarchive 後的預設**。
  - **Archived**：隱藏於前台與主列表；🔴 **不會自任何 collection 移除**（仍列於 Collection items）；要排除用 collection 的 status 條件。
  - **Unlisted**：可售但不可被發現，**只能直接 URL**；隱藏面＝internet search、Shopify Catalog、sitemap、collection 頁、搜尋（含 predictive）、推薦；機制＝**noindex/nofollow＋移出 XML sitemap**；URL 不變；backlink 仍可達；**可直接 URL 加入購物車**；**不可發佈到任何第三方管道**；在 Digital Products/Marketplace Connect 等不支援的 app 中**顯示為 Active**；admin 各處顯示 Unlisted 標籤。
  - **Suspended**（IP 侵權時 Shopify 施加）：不可售且**細節不可修改**；**Pending suspension**：維持原狀態待決。

## Pricing 子樹

### determine-pricing
- 五步定價＋三策略（cost-plus/value-based/competitive）；商業內容為主。

### unit-pricing
- 欄位三：Total amount／Base measure／Unit price（自動＝Price÷Total×Base）。
- 單位制由 General settings 的 Unit system 決定；**排除單位 tons(t)/centigrams(cg)/stones(st)**；每品/variant **最多一個 unit price**；完全選填。
- 「Unit prices 隨 Price 欄變動**動態重算**」。
- CSV 四欄：unit price total measure/total measure unit/base measure/base measure unit。
- **所有 markets 顯示同一單位類型**；「部分區域法定必須顯示單位價」（未列名）。
- OS 2.0 主題內建；vintage 須改 code。
- 訂單通知 Liquid：`{% if line.unit_price_measurement %}…{{ line.unit_price | unit_price_with_measurement: line.unit_price_measurement }}…{% endif %}`。

### sale-pricing
- **驗證規則：compare-at 必須高於 price 才觸發 sale 顯示**；`$0.00` 與空欄語義不同——不打折的 variant 應**清空**。
- 🔴 **collection 頁的 sale 顯示**：各 variants 的 compare-at 不一致（含 $0.00 vs 空欄 vs 金額不同）→ **collection 頁不顯示 sale**（商品頁仍逐 variant 正確）。
- **折扣模塊與 sale pricing 是兩回事**：折扣在 checkout 恆顯劃線價；product/collection 頁要顯示需第三方。
- **International markets：固定價（catalogs）覆蓋標準價與 compare-at；國際市場 sale price 只能經 CSV 建立**。

### smart-pricing（app；early access 摘要）
- 資格 **10+ 商品、每品月銷 25+**；tips 每週刷新；新品 tips 30 天窗、處理最多 3 天；**每商品一條 tip（variants 共用）**。
- Markdown 觸發＝庫存過剩＋去化慢；Markup＝庫存低＋去化快；未填 cost 時建議價可能偏低。
- **A/B 實驗**：Grow+；美國限定；同時 1 實驗；**≤250 商品**；每品 2 價；50/50 流量（雙 catalog 機制）；4 天起出每日指標；結束後 2 天出結果；**95% 信賴水準**；實驗中改價使結果無效；admin **無實驗中標示**；利潤受損不自動停；結束後 app 不代調價（CSV 自行實施）。Publish history 保留 **30 天**。
- 需要權限：Products View cost／Edit cost／Edit price＋全部 Catalogs＋全部 Markets＋app 權限。

## descriptions 子樹
- write：十條寫作準則（無欄位事實）。
- **shopify-magic**：Generate text icon → prompt（建議含 title、**≥2 特徵/關鍵字**、類型、客群、材質、品牌用語）；語言支援全 Shopify 語言；🔴 **mobile 不支援文字生成**（僅 desktop）；「你對發佈內容正確性負全責」。

## product-type
- 自訂分類；**每商品一個**；選填；官方建議**優先用 category**；CSV/API 屬性名 `product-type`（舊 `custom-product-type`）；字元上限未載。

## product-insights
- 指標：Net sales（單價×件數−折扣−撤銷）、over time、by channel、**Net units sold by traffic source（負值＝退貨多於銷售）**、Customers（首購 vs 回購）。
- 窗口＝**最近 90 天** vs 前 90 天。🔴 **不支援 Shopify mobile app**（僅 web admin）。

## tags（格式參考）
- **Product/Customer/Transfer/Blog post tags 各 255 字元；Order/Draft order tags 40 字元；每商品 250 tags**。
- 字元規則：一般字母數字連字號；特殊字元被忽略或視為等同（`red_new`＝`red+new`＝`red&new`＝`red-new`），已存在無特殊字元版時**無法儲存**帶特殊字元同名 tag。
- 建議 ≤16 字元。「**不要把 tags 用於 SEO**」。

## sku
- 內部碼、與 barcode 不同用途；建議 4–8 字元、≤16（非硬限制）；**admin 內唯一（任兩 variants 不得同 SKU）**；**大小寫敏感**（"ABC123"≠"abc123"）。
- 🔴 **訂單成立後才補的 SKU 不會回溯出現在歷史報表**。
- 多地點：同 variant 各地點同一 SKU。
- 條碼掃描器讀 barcode 欄不是 SKU；Shopify Fulfillment Network **要求唯一 SKU**。

## product-category（本分冊視角補充；主文見 92-F §5）
- 批量：Bulk edit＋Product category 欄。
- **換 category**：已填值或已連 variants 的 metafields **轉移**；未填未連的**不轉移**。
- CSV：ID 或 breadcrumb 擇一（如 `hg-3-17-1`）；taxonomy 參考站 `shopify.github.io/product-taxonomy`。

## 數字索引
| 數字 | 事實 | 出處 |
|---|---|---|
| 255／250／40 | tag 字元／每商品 tags（Plus 無上限）／order tag 字元 | add-update-products；details/tags |
| 70／320 | SEO title/description 截斷 | add-update-products |
| 50 | locations 超過須先存商品 | add-update-products |
| 4–8（≤16） | SKU 長度建議 | details/sku |
| 90 天 | insights 窗口 | details/product-insights |
| 1 | 每商品 category/type/vendor/unit price 各一 | 各頁 |
| 10 品/月銷 25 | Smart Pricing 門檻 | smart-pricing |
| 250／2／50%／95%／4 天／2 天／30 天 | A/B 實驗各參數／history 保留 | smart-pricing |
