# 05 — 平台設定、權限與生態系（Settings / Users / Shipping / Taxes / Markets / Apps / Flow / Plans）

> 本篇拆解「平台層」：Settings 的每一個設定領域、權限系統、運費與稅務引擎、多市場、App 生態系、自動化與方案計費。復刻時可把 Settings 視為「平台層 config service」，各頁對應獨立的設定 domain。

## 1. Settings 全清單

Settings 是獨立全螢幕介面（左欄換成設定分類）。各區塊與職責：

| 區塊 | 能設定什麼 / 影響模組 |
|---|---|
| General | 商店名稱、聯絡 email、帳單地址、時區、單位、store currency、訂單編號前後綴、轉移店主 |
| Plan | 檢視/變更方案、暫停或關店 |
| Billing | 平台帳單、付款方式、訂閱項目（app/主題/網域）、發票 |
| Users（and permissions） | Staff 邀請、roles 與細顆粒權限、collaborators、2FA 強制、登入紀錄（見 1a） |
| Payments | 啟用金流（自營或第三方）、手動付款、payout 排程、payment capture 模式 |
| Checkout | 結帳欄位選項、tipping、棄單信、訂單自動處理（自動 fulfill/封存） |
| Customer accounts | legacy vs 新版帳號、登入入口、self-serve returns、store credit（見 1d） |
| Shipping and delivery | profiles/zones/rates、local delivery、pickup、包裝、packing slip 模板（見 1b） |
| Taxes and duties | 各國稅務登記、稅率引擎、override、含稅價、跨境 duties（見 1c） |
| Locations | 地點清單、fulfillment 優先順序；庫存/POS/運費的基礎維度；各方案有上限 |
| Markets | 多市場設定（見 1e） |
| Apps and sales channels | 已裝 app 與通路、權限檢視、custom app 建立與 API 憑證 |
| Domains | 買/接網域、子網域、primary domain 與轉址、國際網域對應 market |
| Customer events | Pixels 管理（custom/app pixel，sandbox JS 訂閱事件） |
| Brand | 品牌資產：logo、色彩、slogan、社群連結；供 checkout/通知信/app 引用 |
| Notifications | 顧客通知模板（Liquid 可改）、staff 通知、webhooks 入口 |
| Custom data | Metafields / metaobjects 定義（見 1f） |
| Languages | 商店語言、翻譯、theme 多語 |
| Customer privacy | Cookie banner、隱私展示、地區資料收集設定 |
| Policies | 退換貨/隱私/條款/運送政策模板，checkout footer 連結 |
| Files | 全站檔案庫 |
| Store activity log | 商店操作稽核紀錄（誰何時改了什麼） |

### 1a. Users and permissions（深入）

- 體系已重構為 **roles**：store-level / organization-level / POS / partner 四種 context 的權限組，可建自訂 role 套給多人。
- Store 權限顆粒度（主要類別）：Home、Orders（檢視/編輯/退款/取消/fulfill/export 分開）、Draft orders、Products（成本檢視/價格編輯/刪除分開）、Inventory、Gift cards、Customers（個資刪除/合併分開）、Analytics、Marketing、Discounts、Content、Files、Online Store（themes/code/blog）、Checkout、B2B、App development、Store settings（billing/plan/payments/shipping/taxes/locations/domains… 再細分）、Apps、POS。另有 sensitive permissions 分類。
- **Collaborator accounts**：給外部設計師/開發者，4 碼 request code 控管申請，不佔 staff 名額。
- Staff 名額依方案：**Basic 0（不可新增 staff，需升級）**、Grow 5、Advanced 15、Plus 不限。
- 店主（owner）有不可剝奪的完整權限，可轉移 ownership。

### 1b. Shipping and delivery（深入）

- **Shipping profiles**：「產品 × 出貨地點 × 目的地」的運費規則組。1 個 General profile（預設全商品）+ 最多 99 個 custom profiles（如易碎品另計）。profile 內按出貨 location 設 **zones**（國家/地區群組），zone 內設 **rates**。
- **Rates 類型**：flat rate；條件式 flat rate（重量區間或訂單金額區間）；carrier-calculated（實時報價，高階方案內建）；免運（0 元或條件式）。
- 注意：平台正逐步把 shipping 遷移到「以 market 為維度」的新模型（舊店沿用舊制）(待確認進度)。
- **Local delivery**：按地點啟用，郵遞區號或半徑劃範圍、最低訂單額、配送費。**Local pickup**：按地點啟用、取貨時間預估與通知。
- **Packages**：預存包裝尺寸/重量供運費計算；packing slip 為 Liquid 模板。

### 1c. Taxes and duties（深入）

- 邏輯：商家先在各國/州完成**稅務登記**，平台才對該區收稅；稅率按目的地/來源地 + 登記狀態決定（美國各州 nexus、EU 支援 OSS）。
- 三種引擎：**Shopify Tax**（US/EU/UK/CA 自動精算、rooftop-level、品類稅則、超量按單計費）、**Basic Tax**、**Manual Tax**（自行維護稅率）。
- **Tax overrides**：對特定 collection 或地區覆寫稅率、運費是否課稅；顧客可設免稅。
- 價格顯示：可設含稅價（prices include tax）、依顧客所在國決定含稅/未稅。
- **Duties**：跨境訂單可在 checkout 預收關稅（DDP），與 Markets 連動。稅務責任在商家。

### 1d. Customer accounts（深入）

- **Legacy**：email + 密碼，帳戶頁由 theme Liquid 渲染，客製要改 code。
- **新版**：passwordless（email 6 碼 one-time code）、session 最長 365 天；帳戶頁平台託管（獨立於 theme）；支援 self-serve returns、reorder、store credit、訂閱管理；以 extensions 擴充；B2B 需用新版。

### 1e. Markets（深入）

- Market = 一組客群體驗設定，可按**地區（國家群組）**、B2B 公司、retail 地點劃分；有 backup region。
- 每個 market 可設：幣別（當地幣結帳、自動/手動匯率、捨入）、語言、網域（subfolder 如 /fr-ca 或獨立網域）、價格調整（百分比或 catalog 固定價）、上架範圍、稅/duties、運費。
- 各方案 market 數量有上限 (待確認)；另有 Managed Markets（merchant-of-record 模式）(供應狀態待確認)。

### 1f. Custom data（深入）

- **Metafields**：在既有資源掛自訂欄位——先建 definition（namespace + key + 型別：文字/數字/日期/檔案/顏色/reference…），再填值；可設 storefront 可見、可在 theme editor 綁 dynamic sources。
- **Metaobjects**：自訂資料模型（多欄位的「新表」），entries 可被引用或直接生成 storefront 頁面。復刻等同「使用者自訂 schema」子系統（definition 表 + JSON 值欄位）。

## 2. 多店與組織

一個帳號可擁有/加入多店，admin 有 store switcher。Plus 有 **organization**：集中管理多店、org-level roles、跨店安全政策、組織級分析與帳單。

## 3. 方案與計費（商業模式）

2025 起中階方案改名 **Grow**。美國定價概況（月繳 / 年繳折算）：

| 方案 | 月費 | 第三方金流額外費 | 自營金流線上費率（US） |
|---|---|---|---|
| Basic | $39（年繳 $29/月） | 2% | 2.9% + 30¢ |
| Grow | $105（年繳 $79/月） | 1% | 2.7% + 30¢ |
| Advanced | $399（年繳 $299/月） | 0.6% | 2.5% + 30¢ |
| Plus | 起價約 $2,300/月（長約） | 0.2% | 議價 |

另有 Starter（$5/月，連結銷售）。商業模式 = **訂閱月費 + 支付費率**（用自營金流免額外平台費、用第三方加收百分比）+ app/主題/網域/運費標籤抽成。復刻的定價架構可直接借鑑這個「月費 × 費率互鎖」結構。

## 4. App 生態系

- 規模：App Store 官方口徑 **16,000+ 個 app**（2026-08 查核）；約 87% 商家有裝 app、平均每店約 6 個。
- 分潤：年收 $1M 內 0%（需註冊）、超過部分 15%；大型開發商 15%。
- **嵌入方式**：app 是外部託管 web app，以 iframe 嵌入 admin，用 **App Bridge** 與宿主溝通（導航/Modal/Toast/session token），UI 用 Polaris；資料層 GraphQL Admin API + webhooks；**Shopify Functions** 可改寫原生邏輯（折扣、運費、付款排序）。
- **擴充點**：admin actions/blocks、checkout UI extensions、customer account extensions、theme app extensions（app blocks 注入 theme）、POS extensions、Flow triggers/actions、web pixels。
- 分發：公開 app（審核上架）vs custom app（單店）。
- 復刻視角：生態系的**技術底座** = OAuth + 細顆粒 API scopes + webhooks + iframe 嵌入協定。demo 不做，但 API 設計時保留 scope 概念，之後才有得長。

## 5. Sales channels

Online Store 只是預設通路之一；另有 POS、Shop app、Facebook & Instagram、TikTok、Google & YouTube、Buy Button、headless。通路以 app 形式安裝，商品按通路控制上架（publishing），訂單統一回流 admin。

## 6. Shopify Flow（自動化）

模型：**Trigger**（事件：訂單建立、庫存低於閾值、顧客建立…）→ **Condition**（欄位邏輯，可查資料與迴圈）→ **Action**（打 tag、藏商品、發信、改 metafield、HTTP request（中階方案以上）、app actions）。App 可貢獻 triggers/actions。常見範本：售罄自動下架、高風險訂單 hold、VIP 打 tag、低庫存提醒。復刻對應：一張 workflow 表 + 事件匯流排 + 條件求值器，是「像大平台」的高槓桿功能，但屬第三階段。

## 7. POS 概覽

POS app（iOS/Android）與 admin 共用產品/庫存/顧客/訂單：庫存按 location 即時同步、線上線下訂單同流（線上買店取、店內退線上單）。硬體：讀卡機、一體機、錢箱、掃描器。POS Lite 內含；POS Pro 按地點月費 (約 $89/location，待確認)。復刻不做硬體，但資料模型上 Channel + Location 先留好即可相容。

## 8. 產品家族一句話地圖

Shop app（消費者購物/追蹤 app 兼通路）、Shop Pay（跨店一鍵結帳錢包）、Balance（商家金融帳戶）、Capital（營運資金）、Audiences（Plus 廣告受眾）、Collabs（網紅聯盟）、Inbox（客服聊天）、Email/Forms（行銷）、物流：自營物流已於 2023 售予 Flexport，平台保留 Shopify Shipping（折扣標籤）；Hydrogen/Oxygen（headless）、Sidekick（admin 內建 AI 助理）。

## 9. 復刻要點 Checklist（本篇 → 工程）

1. Settings 做成「分類側欄 + 各 domain 獨立頁」的獨立框架；demo 先做 General、Users（簡化為 owner+staff 兩級）、Payments（接 Stripe）、Shipping（1 profile + zones + flat/條件 rates）、Taxes（單一稅率 + 含稅開關）、Checkout、Notifications（兩封信）、Domains（子網域）。
2. 權限系統 demo 用「角色 → 權限位元組」簡化版，但 DB 設計直接用 role + permission 多對多，之後才長得大。
3. 運費引擎介面定義成 `rates(cart, address) → options[]`，先實作 flat/條件式，之後可插 carrier API。
4. 稅先做「地區 → 稅率表 + 含稅/未稅顯示」，把計算收在金額引擎裡（見 04）。
5. Plan/Billing demo 可用假方案階梯展示（不接真金流），但租戶表上先有 plan 欄位與 feature flags。
6. Webhook/事件：內部事件匯流排從第一天記（訂單建立、付款成功…），對外 webhook 之後開。
