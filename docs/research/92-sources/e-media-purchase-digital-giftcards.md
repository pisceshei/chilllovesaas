# 92-E — media／purchase options／digital／disclosures／gift cards（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 E。共 35 頁：media 9、purchase options 17（含 Shopify Subscriptions 專區 11）、digital 7、disclosures 1、gift cards 9。

## 分支 1：Product media

### 類型與上限（…/product-media/product-media-types）
**圖片**：PNG/JPEG/PSD/TIFF/BMP/GIF/SVG/HEIC/WebP；動圖 GIF/動畫 WebP；**5000×5000px／25MP／20MB**；建議方形 2048×2048。
**3D**：GLB/USDZ；**500MB**；>15MB 自動最佳化；上傳後自動產 .USDZ＋.GLB 雙版。
**影片（上傳）**：.mp4/.mov/.webm（投放轉 mp4/HLS）；**10 分鐘／1GB／4K(4096×2160)**；480/720/1080p 自適應。
**外嵌影片**：僅 **YouTube 與 Vimeo**。
主題：OS 2.0 全支援；Craft/Crave/Dawn/Sense 對 Vimeo 增強。

### 新增（…/add-media）
- **每產品 250 媒體（合計，cannot be raised）**；單次上傳 **200 檔**；影片 **每週 1,000 支**。
- 儲存配額：Starter/Basic **100GB 檔＋50GB 影片＋250 影片/3D**｜Grow 300GB/500GB/1,000｜Advanced 500GB/500GB/5,000｜Plus 1TB/2TB/50,000｜Enterprise 10TB/10TB/100,000。
- 桌面四途：Upload new／拖放／Select existing／Add from URL。行動五源＋**3D scanner（僅 iOS）**。
- YouTube URL 必須 Public/Unlisted；**Shorts URL 不支援**。Vimeo 須允許外嵌。
- **第一個媒體＝featured media**（collection 頁/cart/checkout 用）；拖放排序。
- 🔴 產品頁移除媒體**不會**刪檔（要真刪去 Content > Files）；檔案視為**公開可存取**。
- 圖片編輯：Save as new／Revert to original（僅 2024-01 後的編輯）／Replace。

### alt text（…/add-alt-text）
- **512 字元上限，建議 ≤125**；AI 建議（採用即存）；CSV 可帶。

### 縮圖（…/change-thumbnail）
- 僅 **3D 與影片**可換縮圖（鉛筆 icon）。

### 變體圖（…/add-images-variants）
- 🔴 **variant 只支援圖片（禁 3D/影片）**；**每 variant 僅 1 張圖**；批次：勾多 variant → Add images/Edit images。
- 多圖 workaround＝Combined Listings（Plus）。

### 3D scanner（…/3d-scanner）
- iPhone 12 Pro+/iOS 17+；三段掃描；處理 10–15 分；商品最小 3in/8cm；不適合反光/單色/軟性/薄件。

### 委製 3D（…/expert-3d-model）
- 交付建議 GLB ~4MB（≤15MB）；尺寸一律毫米。

## 分支 2：Purchase options

三型：**Subscriptions／Pre-orders／Try before you buy**；付款資料 Shopify 保存，**商家不可讀完整卡號**。

### Subscriptions
- 需 app（官方免費 Shopify Subscriptions 或第三方）；第三方 app 解除安裝 → **48h 後刪資料**（合約與付款資訊除外）。
- **Gateway**：Shopify Payments／PayPal Express／Authorize.net／Adyen／Stripe（限部分商家）。🔴 **local payment methods 一律不能買訂閱**。
- **扣款時點：到期日次日、商店當地時間 10:00 am**。
- 折扣：admin 自動折扣適用全訂閱單；**gift card 只作用第一期**。
- Card auto-updater：Shopify Payments 有（美國廣泛）；其他 gateway 顧客手動。
- Checkout 強制揭露條款＋每行項顯示頻率＋首次/週期運費分開。
- **不支援**：draft orders、Order edits API、Bundles；通路＝Online store/POS/Shop/custom。
- 產品層：「Only sell this product as a subscription」；🔴 **訂閱限定商品只能在 Online store 賣**。
- 自動生成 **Purchase options cancelation policy**（checkout footer；可編輯；留空顯示範本）。

#### 官方 Shopify Subscriptions app
- Plan 欄位：Title（顧客可見）／Internal description／頻率（weekly/monthly/yearly）／Discount（Percentage off/Amount off/**Fixed price**）；**Add option** 多組合。
- **刪 plan 不可復原**；從產品移除 plan **不取消既有合約**。
- Contracts：改頻率會**自動同步計費頻率**；Skip（可 Resume）/Pause/Resume/**Cancel（不可逆）**。
- **庫存不足狀態機**：ⓘ 警示＋Inventory error 篩選＋banner → 三處置（強制建單超賣／補貨重試／依 app 設定）；顧客收「Not enough inventory」信。
- **付款重試**：次數＋間隔天數可調；付款失敗與庫存不足**各自獨立設定**；最終失敗動作三選 Skip/Pause/Cancel。
- 🔴 **解除安裝官方 app＝刪所有 plans、contracts、相關折扣**。
- 顧客帳戶：**email＋6 位驗證碼無密碼**；自助 Skip（可連跳多期）/Pause（即時、可 Resume）/Cancel（不可逆）/換卡/改地址。
- 翻譯：儲存 plan 自動生成（**覆寫先前匯入的翻譯**）；支援 **19 語**。
- Analytics 四指標：Subscriptions revenue／Active subscriptions（**含 paused 與 skipped**）／New／Canceled；比較區間 7/30/90 天，**預設 7**。
- 主題要求：OS 2.0 或 Debut ≥15.0/Brooklyn ≥17.0；widget block 與 App embeds 二擇一（同開顯示異常）。
- 遷移：卡號本體（PAN）遷入**必須 Plus/Enterprise**；token 全方案；Venmo/Apple Pay/Google Pay/銀行帳戶**不能遷**；slow-drip 法可耗數月至數年。

### Pre-orders
- 下單可收 full/partial/no payment；**必須裝 pre-order app**；**gateway 限 Shopify Payments 或 PayPal Express**。
- 🔴 **Shop Pay/Apple Pay/Google Pay 禁用**；local payments 不支援。
- 法遵：**未指明日期時預設承諾 30 天內出貨**；延誤須通知＋告知退款/取消權。
- **不可與其他購買選項疊加**；Buy X Get Y 不支援；通路 Online Store＋Custom。
- **多商品尾款**：多到期日取**最早**；混「指定日」與「due on fulfillment」→ **後者優先**；多筆訂金結帳合併收。
- 管理：Unfulfilled＋Unpaid tabs；Hold fulfillment 延後出貨；Collect payment 提前收款（先溝通防 chargeback）；**訂單編輯可加一次性商品、不可加新預購品**；庫存保留時點在 app 選（售出時 vs 出貨時）。

### Try before you buy
- 先出貨後扣款；必須第三方 app；**gateway 限 Shopify Payments/Adyen/Stripe（部分）**。
- 🔴 加速結帳禁用；local payments 禁用；**local delivery 與 pickup 不支援**；不可疊加其他購買選項；多商品到期日取最早。
- 管理：Unpaid 篩選；可改到期日；提前收款；退款同預購。

## 分支 3：Digital products

### Digital Downloads app（官方）
- 資產兩型：上傳檔（**單檔 5GB**；可 .zip；**不能上傳資料夾**）＋外部連結（**僅限**：Notion/Calendly/Acuity/Kajabi/Teachable/Thinkific/Google Drive/Docs/Dropbox/Canva/YouTube/Vimeo/Figma）。
- 交付兩模式：Automatically send files（預設；自動 fulfill）／Manually send files。
- **下載次數**：per-variant 可設；**每次開啟連結都計入**；預設 unlimited。
- 🔴 改/刪檔＝斷既有顧客下載連結。
- 信件：「Downloads ready」「Digital file update」可 Liquid 客製。

### 服務/數位商品（關運送）
- 核心＝Shipping 區取消「Physical product」；bulk editor 可批次。
- **EU 顧客購買數位商品必須按顧客所在國 VAT**（不論賣家所在地）。
- **混合訂單**：非 3PL → **拆多張 fulfillment card**；建議數位品專用 location。

### NFTs
- 僅 primary sales；鏈：Ethereum/Polygon/Solana/Tezos/Flow；**13 國限定**；需 app partner＋Shopify 預先核准；chargeback 風險自負（NFT 入錢包幾乎不可回收）。

## 分支 4：Product disclosures（單頁）

- 實作＝**metaobject（Shopify Disclosures）＋Disclosures metafield**；顯示於 online store、**Shop app（≥2.239.0 自動顯示）**、custom storefronts、第三方。
- 欄位：Internal label／Title／Content／Symbol（商家上傳圖示）／**Jurisdictions**（適用法域）／Display preferences（product page、**Cart**）。
- 內建範例：加州 Prop 65／哽塞危險／CPSC eFiling；🔴 適法性責任在商家。
- **集中編輯**：Content > Metaobjects 改一處**套用到所有引用產品**。
- 列表篩選：definition 開「Filter on the product list and in the Admin API」。
- 顯示：Horizon＝theme block；OS 2.0＝section。CSV 欄 `shopify.disclosure`；bundle 可掛。

## 分支 5：Gift cards

### 面額與途徑
| 途徑 | 上限（USD 等值） |
|---|---|
| Gift card **product**（顧客購買；fulfill 時發卡） | **$10,000** |
| Admin 直接**建立**（不收款） | **$2,000** |
- 🔴 **面額只能是預設值**（前台不能自訂金額）；**每面額＝一個 variant**（可各設 SKU/條碼/圖）；至少 1 面額。
- 幣別：store currency 卡任何幣別可折抵（自動換匯）；local currency 卡需幣別相符（除非開 **cross-currency redemption——建立後不可改**）。
- 2025-05-12 後建立的店：禮品卡支付訂單收第三方交易費（Plus＋Shopify Payments 豁免）。

### 管理
- 🔴 **編輯/封存/刪除 gift card product 不影響已發出的卡**。
- 🔴 **卡不可刪除**；只能 **Deactivate（永久、不可逆、不可再儲值）**；狀態機 Active/Deactivated/Expired＋餘額 Full/Partially used/Empty。
- **admin 只顯示 code 末 4 碼**（完整 code 僅顧客可見）；兌換碼＝**16 字元隨機不可自訂**。
- **退款**：退已購買的卡→**自動 deactivate**；admin 建立的卡不可退款；過期卡先改效期才能退；**部分退款優先退到卡餘額**。
- Resend：部分使用過的卡只寄剩餘餘額。
- CSV 匯出：≤50 直接下載，>50 email；**20 欄位**。
- 篩選 6 類（含 **Issue method: issued/purchased/app-generated**）；排序 10 種。

### 設定
- **效期預設永不過期**；🔴「it's illegal in some countries for gift cards to expire」；選 expire 的**預設值＝5 年**。
- Apple Wallet Passes：banner **≤1125×432px**（超過 413 錯誤）；header 文字 **≤30 字元**；停用後既有 pass 仍可兌換。
- Fulfillment：預設付款後自動 fulfill＋寄信；🔴 **中/高風險訂單不自動 fulfill**。
- 通知卡面圖：**建議 950×550（5:3；最小 450×270）**。

### 兌換
- code 不分大小寫；付款選項**只在店內存在 active 卡時出現**；可多次用、可疊多張、可與折扣碼並用。
- 🔴 **禮品卡不能買禮品卡**；訂閱可付首期、**不能作為週期扣款方式**。
- 🔴 **套在 collection 的折扣不延伸到 collection 內的 gift card products**（要折就直接指定）；折扣只降售價不降面值。

## 跨分支互動速查
| 互動 | 規則 |
|---|---|
| Variant × 媒體 | 僅 1 圖、禁 3D/影片 |
| 訂閱 × gift card | 只折首期 |
| 訂閱 × Bundles/draft orders/Order edits API | 皆不支援 |
| 預購/TBYB × 加速結帳與 local payments | 一律禁 |
| 預購 × 訂單編輯 | 可加一次性品、不可加新預購品 |
| 購買選項互斥 | 預購/TBYB 不可與訂閱疊加 |
| 數位品 × 混合訂單 | 非 3PL 拆多 fulfillment card |
| Gift card × 風險訂單 | 中/高風險不自動 fulfill |

## 未取得清單
1. alt text 支援媒體類型逐類列舉。
2. 縮圖替換圖格式/尺寸要求（頁面明言未規定）。
3. 每產品 subscription plan 數上限。
4. Subscriptions import/export CSV schema。
5. 關運送後 checkout 逐項變化（是否收地址）。
6. Gift card 面額（variant）數量上限。
7. TBYB 試用期天數值域（由 app 決定）。
