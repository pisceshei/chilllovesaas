# shopifysystem — 復刻 Shopify 的三階段專案

目標：深度研究 Shopify 的功能模組與 UI 交互邏輯（第一階段）→ 做出可運行的 demo 原型（第二階段）→ 往真產品方向演進（第三階段）。

## 目前狀態

- ✅ 第一階段：深度研究完成（`docs/research/`，11 份文件 + 互動式模組地圖）
- 🔜 第二階段：demo 原型——已決策（見 `docs/DECISIONS.md`）：**Rails + React（本尊同款棧）**、路線 **A→B→C**、品牌名 **CHILL LOVE**
- ⬜ 第三階段：真產品路線（見 07 §9）

## 文件索引（docs/research/）

| # | 文件 | 內容 |
|---|---|---|
| 00 | overview | 產品全景、Admin 導航地圖、模組總表、橫切概念 |
| 01 | admin-core | 商品/庫存/訂單/顧客/折扣：功能邏輯、畫面、狀態機 |
| 02 | polaris-ui | 設計 tokens、後台佈局、列表/詳情頁交互模式、授權注意 |
| 03 | storefront-themes | OS 2.0 主題架構、theme editor、Dawn 頁面解剖、Liquid |
| 04 | checkout-payments | 結帳逐欄位規格、金流、棄單、行銷、分析、通知 |
| 05 | settings-platform | Settings 全清單、權限、運費稅務、Markets、App 生態、方案 |
| 06 | data-model | 整合 ER 圖、狀態機總表、庫存恆等式、金額管線、40 表清單 |
| 07 | mvp-plan | 實作方案書：架構藍圖、技術棧、P0/P1/P2、里程碑、風險 |
| 08 | system-architecture | Shopify 服務端工程內幕（單體/Pods/SFR/搶購）與復刻對應 |
| 09 | api-map | Admin/Storefront/Customer/Ajax API、Webhooks、Functions 地圖 |
| 10 | implementation-playbook | 00–09 逐篇實作細節：工具/套件、代碼草稿、參考文檔、M0 開工清單 |
| 21 | live-admin-teardown | 實測走訪 2026 春季版後台：十大結構性變化、逐頁紀錄、原型 v2 修正清單 |
| 22 | admin-button-inventory | **按鈕級對照表**：每個控制項的功能→邏輯→實作註釋（M/S/API/P 級），含配額常數表與方案補充；與 v2 原型「開發註釋模式」同步 |

另附 `shopify-module-map.html`：可互動瀏覽的模組地圖（同內容存為 Cowork artifact）。

## 生產級規格（docs/specs/）

每份規格逐功能列「生產級做法 → 工具 → 代碼 → ⚠️ 坑」，並以 11 的七維度驗收表收尾：

| # | 文件 | 覆蓋功能 |
|---|---|---|
| 11 | production-baseline | 生產級定義（7 維度）、安全/資料/併發/效能/可觀測/測試/合規基線、全域十大坑 |
| 12 | spec-tenancy-auth-permissions | 開店、子網域路由、staff 認證、邀請、角色權限、租戶隔離保證 |
| 13 | spec-products-inventory-media | 商品/變體、handle/SEO、媒體管線、collections、庫存 ledger、CSV |
| 14 | spec-storefront-theme-editor | SSR 快取、theme JSON 驗證、三欄編輯器、搜尋(ngram)、SEO、密碼頁 |
| 15 | spec-cart-checkout-payments | cart、金額引擎與分攤、one-page checkout、Stripe、訂單成立、棄單 |
| 16 | spec-orders-fulfillment-refunds | 訂單管理、timeline、出貨、取消/封存、退款上限、顧客與匿名化 |
| 17 | spec-discounts-engine | 折扣求值管線、組合裁決、用量併發硬保證、濫用防護 |
| 18 | spec-messaging-events-webhooks | outbox、Liquid 沙箱、送達性(SPF/DKIM/DMARC)、對外 webhooks(SSRF)、任務運維 |
| 19 | spec-analytics-settings-api | 指標辭典、rollup、sessions、Settings 稽核、API token/scope/限流/版本 |

## UI 設計（docs/design/）

| 文件 | 內容 |
|---|---|
| 20-ui-design-plan | 三面 UI 專屬方案：醜的診斷、參考對象、雙設計語言 tokens、工藝清單、skills/代碼/資產、迭代流程 |
| chilllove-admin-preview.html | 商家後台高保真互動 mockup（Home 圖表/商品列表/商品詳情 save bar/訂單/⌘K）— 品質基準線 |
| chilllove-storefront-preview.html | CHILL LOVE 前台首頁高保真互動 mockup（hero/精選/敘事/購物袋 drawer + 免運進度條） |
| critique-round-1.md | 第一輪 design critique 紀錄：20 項已修 + backlog |
| chilllove-admin-v2.html | **後台 v2**：2026 實測結構（淺色頂列/pulse 首頁/AI 框/新導航）+ 全導航樹真頁面（訂單詳情、草稿、棄單、庫存、分群、成長、折扣 modal、市場、財務、報告、實況、設定 12 分頁）；已過第二輪 critique（10 項修復） |

## 快速結論

- 功能邏輯與交互模式可以合法復刻；程式碼、圖示資產、商標不可照搬；Polaris 授權非純 MIT（見 02 §1、07 §10）。
- Demo 原型 = 約 40 張表、8 個 section、12+ 個 UI 元件、7 個里程碑（M0–M6），端到端閉環：開店 → 上架 → 逛店 → 結帳（Stripe test）→ 出貨退款 → 報表。
- 工程原則四條（源自 Shopify 架構）：shop_id 貫穿一切、前台是可快取的 read path、寫路徑冪等、任務可中斷重跑。
