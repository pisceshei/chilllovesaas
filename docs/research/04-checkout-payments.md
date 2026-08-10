# 04 — 結帳、金流、行銷與分析

> 本篇拆解 Shopify 的營收管線：checkout 逐欄位規格、金流（收單/請款/撥款/詐欺）、棄單挽回、行銷模組與分析模組。checkout 是全平台打磨最兇的介面，也是 demo 原型的重頭戲。

## 1. Checkout 結帳流程

### 1.1 整體結構

- 2023 年起預設 **one-page checkout**：cart 按 Check out 進入單一可捲動頁（`/checkouts/...`）；2023-11 起**所有方案**都可在 Settings → Checkout 自選 one-page 或 three-page（三頁式並非 Plus 專屬）。
- 桌機兩欄：**左欄表單流程、右欄訂單摘要（sticky）**；行動版摘要收合在頂部「Show order summary」。
- 左欄由上而下：**Express checkout 按鈕列 → OR 分隔線 → Contact → Delivery（地址）→ Shipping method → Payment（含 billing address）→ Remember me（Shop Pay）→ Pay now**。
- 每步檢查庫存，但**只有送出付款時才真正保留庫存**。

### 1.2 欄位明細

- **Contact**：email（或依設定 email/phone 擇一）；下方可有行銷訂閱 checkbox（email/SMS consent，可依地區預設勾選）；已登入顯示帳號 email；可設「必須登入才能結帳」。
- **Delivery address**：country/region 下拉 → 姓名（可設只要求 last name）→ company（hidden/optional/required）→ address（輸入時**自動完成建議**）→ address line 2（hidden/optional/required）→ city/postal → 電話（hidden/optional/required）；部分國家依當地格式追加欄位。
- **Shipping method**：填完地址後依 shipping zones/rates 即時列出可選運送方式（radio：名稱 + 價格；免運顯示 Free）；支援 pickup 併列與 split shipping（多包裹分列）；未填地址前顯示提示文字。
- **Payment**：各付款方式 radio accordion。信用卡為 PCI iframe 欄位：卡號、到期日、CVV、持卡人姓名；下方 billing address 預設 **Same as shipping**，可切換另填。其他選項依啟用情況：PayPal、BNPL 分期、當地付款、manual payments（顯示說明文字）。
- **Tipping**（選配）：最多 3 個百分比 preset + custom 金額欄。
- **Order notes**：原生 checkout 無備註欄；慣例是 cart 頁的 cart note 帶入訂單。

### 1.3 右欄訂單摘要

品項縮圖（右上角數量 badge）+ 名稱/變體 + 金額；**Discount code / gift card 輸入框 + Apply**（套用後顯示為可移除 tag + 折抵金額）；Subtotal → Shipping（未選時顯示待計算）→ Taxes（含稅定價地區標示 included）→ **Total（前綴幣別代碼，如 USD $58.00）**；多幣別店以買家幣別顯示、同時以店幣記帳（API 的 MoneyBag shop/presentment 雙值）。

### 1.4 Express checkout

按鈕：Shop Pay、Apple Pay、Google Pay、PayPal 等。出現位置：checkout 頂部 Express 區 + 商品頁/cart 的 dynamic checkout button。按鈕**動態排序**：偵測到買家已有某錢包時排最前。點擊由錢包回傳地址與付款資訊，直接跳到確認。

### 1.5 Guest、登入與 Shop Pay

- 預設 guest checkout；customer accounts 可設 optional/required；新版帳號 passwordless（email 一次性驗證碼）。
- **Shop Pay**：買家付款資訊加密存於平台；在任何啟用店輸入已註冊 email → 觸發 SMS 一次性驗證碼 → 全欄位自動帶入一鍵付款；首次結帳勾 Remember me 註冊。官方現行口徑：較 guest checkout 轉換最高提升 50%、比其他加速結帳至少高 10%（1.56×/1.91× 為 2020 年舊研究數字）。
- 復刻對應：這就是「平台級跨店錢包」，demo 可用 Stripe Link 得到類似體驗，或先不做。

### 1.6 結帳後

- **Thank you page**（訂單編號 + 確認摘要）→ 同 URL 轉為 **order status page**（顧客從確認信連入：物流追蹤、狀態更新、重購）；無帳號者逾時需 email/phone 驗證再查看。
- 自動寄 order confirmation email（見第 6 節）。

### 1.7 商家自訂能力（checkout extensibility）

- Checkout editor 統一自訂 branding：logo、顏色、字體、背景。
- 分層：一般方案可 branding 與 thank you/order status 頁擴充；**只有 Plus** 能在結帳步驟（information/shipping/payment）掛 app、使用 Checkout Branding API。
- 舊 `checkout.liquid` 已淘汰，由 Checkout UI Extensions + Shopify Functions（自訂折扣/運費/付款排序）+ Web Pixels 取代。
- 其他設定：bot protection、政策連結、多語系。

## 2. Payments 金流

### 2.1 Shopify Payments

- 內建收單：主要卡別 + Shop Pay + 錢包 + BNPL + 當地付款方式；有國家資格限制。
- **Payouts**：交易款先進 balance，依排程（daily/weekly/monthly）撥到銀行帳戶；入帳另需 1–3 工作天；退款與 chargeback 從 balance 扣；有保留款（reserves）機制；payout 狀態 in transit/paid/failed；提供對帳報表。
- **測試**：test mode + 測試卡（`4242 4242 4242 4242` 成功；`…0002` 拒絕、`…9995` 餘額不足、`…0069` 過期、`…0127` CVC 錯誤）；未用 Shopify Payments 可用 Bogus Gateway（1=成功、2=失敗、3=例外）(細節待確認)。
- 復刻對應：**這一塊的等價物就是 Stripe**（Stripe 的測試卡體系幾乎相同）；demo 用 Stripe test mode，架構上留 gateway 抽象層。

### 2.2 第三方 gateway 與 manual payments

- 第三方分 direct（站內）與 offsite（跳轉）；可與 Shopify Payments 並存；用第三方時平台依方案**另收 0.2%–2% 交易費**（用 Shopify Payments 免收）——這是商業模式的關鍵槓桿。
- **Manual payments**：bank deposit、money order、COD、custom；下單時 financial status = Pending，商家收款後 mark as paid；付款指示顯示在確認頁/信。

### 2.3 授權/請款、退款、風險

- **Authorize vs capture**：四種模式——Automatically at checkout（預設，= sale）/ when order fulfilled / per fulfillment（Plus）/ Manually。授權期 7 天（Plus 可延長至 30 天）；逾期未 capture 收不到款；支援 partial capture。
- **OrderTransaction**：kind（authorization/capture/sale/void/refund）、status（pending/success/failure）、amountSet（雙幣別）、gateway、parentTransaction（capture/refund 鏈）、test。
- **退款**：full/partial；可勾 restock；運費單獨退、不可超過原收；刷卡手續費不退還；退款不可撤銷；financial status 依序 paid → partially_refunded → refunded。
- **Fraud analysis**：每單 low/medium/high；訂單頁「Order risk」區列指標（綠 = 正常訂單常見、紅 = 詐欺常見、灰 = 補充），涵蓋 AVS/CVV 結果、IP 位置、多卡嘗試；可搭 Flow 自動 hold 高風險單。

## 3. Abandoned checkout 棄單挽回

- 定義：買家留下聯絡方式後未完成付款（約 10 分鐘判定）即記錄；含品項、金額組成、payment events；**3 個月後自動刪除**；可轉 draft order 保留。
- `AbandonedCheckout`：lineItems、金額各項、customer、addresses、discountCodes、completedAt（null = 未完成）、**abandonedCheckoutUrl（恢復結帳連結）**。
- 挽回：手動寄 recovery email 或自動化（可設延遲、對象條件、模板）。不寄的邊界：已完購、付款錯誤型棄單、地址不可送、只留電話、無庫存或全免費。
- 成效報表：開信/點擊/挽回銷售。

## 4. Marketing 模組

- Marketing 總覽（近年整合進 Growth 區）：sessions、conversion rate、AOV、歸因銷售 + 各 channel/campaign 成效；活動自動帶 UTM；歸因模型可切換（預設 last non-direct click、30 天窗口，待確認）。
- **Automations**：模板化自動流程——welcome、abandoned checkout/cart/browse、win-back、upsell；底層是 Shopify Flow；各自動化有成效報表。
- **Shopify Email/Messaging**：admin 內建 email（/SMS）行銷，按發送量計價；拖放模板編輯器。

## 5. Analytics 分析

- **首頁 dashboard**：可自訂卡片（新增/移除/拖曳/改大小），資料近即時（約 1 分鐘）；常見卡片：Total sales、Sessions、Conversion rate（含 added to cart → reached checkout → converted 漏斗）、AOV、Total orders、依通路/裝置/來源拆分；任意 date range + 比較期（前期/去年同期）。
- **Reports**：預設報表 11 類——Acquisition、Behavior、Customers、Finance、Fraud、Inventory、Marketing、Orders、Profit、Retail、Sales；可另存自訂報表；高階方案解鎖更多。
- **Live View**：地圖 + 即時指標（Visitors right now、當日 sales/sessions/orders、top products）+ 行為漏斗（Active carts → Checking out → Purchased）。

## 6. Notifications 通知系統

- Settings → Notifications。**顧客通知模板**主要：訂單類（order confirmation、edited、invoice、cancelled、refund、payment error）、出貨類（shipping confirmation、out for delivery、delivered、tracking 更新）、本地配送/自取類、帳號類（welcome/invite、reset）、退貨類（instructions/label）、abandoned checkout、gift card。
- 自訂：全域 branding（logo、主色）一鍵套用；每模板可編輯 subject 與 HTML body（支援 Liquid 變數：訂單編號、金額、品項迴圈）；出貨類可個別開關；order confirmation 不可停用 (待確認)。
- **Staff notifications**：新訂單通知指定 email。

## 7. 復刻要點 Checklist（本篇 → 工程）

1. Checkout 做 one-page 版式：左表單右摘要、express 列、地址自動完成（可用免費 API 或先略）、運送方式依 zone 即時計算、Stripe Elements 卡欄。
2. 訂單金額計算引擎獨立成模組：小計 → 折扣 → 運費 → 稅 → 總計，全程雙幣別欄位預留（demo 可單幣別）。
3. Transaction 表從第一天就用 kind/status/parent 鏈模型（authorize/capture/refund 都是一筆 transaction）。
4. 棄單：checkout 表單留了 email 就落一筆 checkout 紀錄 + recovery URL，後台列表 + 手動寄信（自動化之後做）。
5. 通知系統：模板表（subject + HTML + 變數渲染）+ 事件觸發器；demo 先做 order confirmation 與 shipping confirmation 兩封。
6. Analytics demo 先做首頁 5 張卡（total sales / orders / AOV / conversion / top products）+ 日期範圍切換；資料來源直接 SQL 聚合即可。
