# 07 — 實作方案書：Demo 原型範圍、架構藍圖與產品路線

> 本篇是第二階段（demo 原型）與第三階段（真產品）的完整方案，整合 00–06、08、09 的研究結論。原則：**功能邏輯與交互模式照 Shopify 的骨架做，工程規模按一人＋AI 的現實做，法律紅線明確避開**。

## 1. 目標與非目標

**Demo 原型的目標**：一個可運行的多租戶電商 SaaS——商家能註冊開店、上架商品、設定商店；買家能逛店、加購、走完 one-page 結帳（Stripe 測試金流）；商家能在 Polaris 風格的後台管理訂單、出貨、退款、看報表。UI 手感與功能邏輯對齊 Shopify。

**明確的非目標（demo 不做）**：真實收單與撥款、App 生態系、POS、多語系多幣別、B2B、自研搜尋、email/SMS 行銷自動化、Flow。這些在第三階段按需求排入。

## 2. 總體架構藍圖

```
                        ┌──────────────────────────────┐
                        │        Next.js (monorepo)     │
  merchant ──admin──▶   │  /admin   後台 (Polaris 風格)  │
                        │  /store   前台 SSR (theme 渲染)│
  buyer  ──storefront─▶ │  /checkout one-page 結帳       │
                        │  /api     內部 API (route hdlr)│
                        └──────┬───────────┬───────────┘
                               │           │
                    ┌──────────▼──┐   ┌────▼─────────┐
                    │ PostgreSQL  │   │ Stripe (test) │
                    │ 全表 shop_id │   │ PaymentIntent │
                    │ + outbox    │   └──────────────┘
                    └──────┬──────┘
                           │ worker (佇列/事件)
                    ┌──────▼──────┐   ┌──────────────┐
                    │ jobs: 通知信 │   │ S3/R2 圖片    │
                    │ 棄單/報表    │   │ Resend 寄信   │
                    └─────────────┘   └──────────────┘
```

- **單一 monorepo、單一部署單元**（08 的結論：modular monolith，用資料夾邊界不用微服務）。
- 租戶路由：`{store}.平台網域` 子網域（等價 myshopify.com），middleware 解析 shop；自訂網域之後加 CNAME 對應表。
- 前台頁面 SSR + 快取（08 的 Storefront Renderer 洞見：前台是可極致快取的 read path）。
- 事件：outbox 表 + worker（09 的 webhook 模型先內用）。

## 3. 技術棧選型（建議）

| 層 | 選擇 | 理由 |
|---|---|---|
| 全棧框架 | **Next.js 15 (App Router) + TypeScript** | 一個框架吃下 admin/storefront/checkout/API；SSR 與快取原生 |
| DB/ORM | **PostgreSQL + Prisma**（或 Drizzle） | 關聯模型複雜（40 表），遷移工具成熟 |
| UI | **Tailwind + 自建 Polaris 風格元件庫**（tokens 見 02） | ⚠️ 授權原因不直接用 @shopify/polaris（見 §10）；icon 用 Lucide |
| 狀態/表單 | React Server Components + react-hook-form + zod | dirty 偵測（save bar）與 schema 驗證 |
| 金流 | **Stripe test mode**（PaymentIntent + Elements） | 與 Shopify Payments 的測試卡體系幾乎同構；留 gateway 介面 |
| 任務/佇列 | Postgres 佇列（graphile-worker 或自寫 SKIP LOCKED） | 少一個基礎設施；夠用到很後面 |
| 圖片 | S3 相容儲存（Cloudflare R2）+ 圖片變換 | 商品媒體 |
| Email | Resend/SES + React Email 模板 | 通知信（模板變數 = 06 的 notification_templates） |
| 部署 | Docker 單 image → Fly.io/Railway/VPS | 單體部署；之後可搬 |

替代路線：若偏好後端分離，可用 NestJS API + Next.js 前端；若熟 Rails，Rails 8 + Hotwire 其實最貼近 Shopify 本尊。**預設推薦 Next.js 單體**：AI 協作效率與生態最好。

## 4. 模組範圍分級（P0 = demo 必做；P1 = demo 加分；P2 = 第三階段）

| 模組 | P0（核心閉環） | P1 | P2 |
|---|---|---|---|
| 租戶 | 註冊開店、子網域、店設定 | 自訂網域 | 方案/計費、多店組織 |
| Admin shell | 側欄導航 + top bar + 全域搜尋（⌘K）| 通知中心 | 多店切換 |
| Products | CRUD、3 options × 變體、媒體、狀態、SEO、manual collections | smart collections、CSV 匯入、gift cards | metafields UI、taxonomy |
| Inventory | 單地點、available/committed 帳 + ledger | 多地點、transfers | PO、供應商 |
| Orders | 列表（tabs/篩選/badge）、詳情（timeline、fulfill、refund）、手動下單(draft) | 訂單編輯、returns 流程、風險示意 | 詐欺模型、爭議 |
| Customers | 檔案、地址、消費統計、tags | segments（簡化語法） | B2B |
| Discounts | code × (order %/金額、free shipping) | automatic、BxGy、combinations | Functions 式自訂 |
| Storefront | 首頁 sections、collection 頁（排序）、product 頁（variant picker）、cart drawer、predictive search 簡版 | filters、blog/pages、policies 頁 | 多主題市場 |
| Theme editor | 左樹/中預覽/右設定、section 增刪排序、theme settings、發佈 | alternate templates、區塊拖曳跨 section | 主題代碼編輯器(Liquid) |
| Checkout | one-page：contact→address→shipping→payment(Stripe)→摘要、discount code、庫存保留 | express 按鈕列(Stripe Link)、tipping | 三頁式、extensibility |
| 結帳後 | thank you / order status 頁、確認信 | 物流追蹤頁 | Shop Pay 等價物 |
| Analytics | 首頁 5 卡 + 日期範圍 | Live View 簡版、報表 3 張 | 自訂報表、漏斗 |
| Settings | General、Users(owner+staff)、Payments、Shipping(zones/rates)、Taxes(單率)、Checkout、Notifications(2 封)、Policies | Locations、Domains、Markets 骨架 | 全部 20+ 域 |
| 通知 | order/shipping confirmation | 棄單挽回信 | 全模板庫 |
| API | 內部 REST/tRPC（cursor 分頁、版本前綴、錯誤格式統一） | 唯讀 public API + token | GraphQL、OAuth、webhooks、scopes |
| 事件 | outbox 表 + worker | admin 內 activity log | 對外 webhooks、Flow |

## 5. 里程碑（每個都可跑可看）

- **M0 地基（先做）**：monorepo、DB schema（06 的 40 表）、租戶中介層、design tokens + 第一批 12 個元件、admin shell 空殼。
- **M1 商品線**：Products CRUD 全流程 + 變體 + 媒體 + collections + Inventory 帳。驗收：開店→上架 10 個商品。
- **M2 前台線**：storefront SSR（首頁/collection/product/cart drawer）+ 主題 JSON 渲染。驗收：買家能逛能加購。
- **M3 成交線**：checkout one-page + Stripe 測試付款 + 訂單成立（庫存 committed、確認信、thank you 頁）。驗收：端到端下單。
- **M4 履約線**：Orders 後台（列表/詳情/timeline/fulfill/refund）+ Customers。驗收：出貨退款閉環。
- **M5 增長線**：Discounts + Analytics 卡片 + Settings 八域 + 通知模板。
- **M6 主題編輯器**：三欄 editor + section 庫 + 發佈流程。（最出效果的一里程碑，放最後因依賴 M2）

## 6. UI 復刻策略（見 02）

1. tokens 先行（CSS variables）：色彩/字級/間距/圓角/陰影全表。
2. 元件庫兩批：第一批 Page/Card/Button/TextField/Select/Badge/Banner/Toast/Modal/Tabs/IndexTable/SaveBar；第二批 Filters/Popover/ActionList/EmptyState/Skeleton/DropZone/Combobox。
3. 兩個頁面級模板（Index page / Detail page）承載所有模組頁。
4. 靈魂交互優先：contextual save bar + 離開攔截、badge 語意色、toast 回饋、skeleton 載入、destructive confirm。
5. 快捷鍵：⌘K 搜尋、⌘S 儲存。

## 7. 主題系統簡化設計（見 03、06）

- Theme = DB 資料：`templates`（JSON: sections + order + settings）+ `theme_settings`（全站）+ section 型別註冊表（React 元件 + settings schema）。
- Demo 的 section 庫（8 個）：announcement-bar、header、image-banner、featured-collection、rich-text、product-grid、newsletter、footer。
- Editor = 對 JSON 的三欄視覺編輯器：左樹（增刪/排序/隱藏）、中 iframe 預覽（postMessage 同步、裝置切換）、右設定表單（由 settings schema 自動生成）。
- 不實作 Liquid 語言本身（P2 再議）；settings schema 的概念完整保留，所以商家心智模型與 Shopify 一致。

## 8. Checkout 與金流方案（見 04）

- one-page 版式照 04 §1 的欄位順序；金額引擎照 06 §6 的管線做成純函式。
- Stripe：PaymentIntent（authorize+capture 先用自動 capture；手動 capture 留設定位）；測試卡體系與 Shopify 幾乎同構，demo 演示效果好。
- 庫存保留：送出付款時在交易內扣 available/加 committed（08 §4 的簡化結論）；冪等鍵防重複下單。
- checkout 落表即棄單資料來源；recovery URL 直接可做。

## 9. 第三階段：往真產品的路線（方案補充）

1. **金流升級**：Stripe live + Stripe Connect（平台向商家分帳/代收）——這是「平台型 SaaS」的關鍵一步；authorize/capture 模式、退款、對帳報表。PCI 責任全部留在 Stripe 側（SAQ-A）。
2. **API 開放**：內部 API 穩定後開 public API（token + scopes → OAuth）、webhooks（09 的 HMAC/重試規格照抄）、之後才是 GraphQL 與 app 擴充點。
3. **平台功能長尾**：多地點庫存、markets（幣別/語言）、細顆粒權限、報表庫、Flow 式自動化、theme 市場。
4. **規模化路徑**（08 的順序）：單庫 → 讀寫分離 → 大表分區 → 按 shop_id 分片；前台 CDN 快取先於一切 DB 工程。
5. **合規**：隱私政策/GDPR 資料匯出刪除（09 的三支 compliance webhook 概念）、消費者法規（發票/退貨）、台灣本地金流（之後可加 TapPay/藍新 gateway adapter）。
6. **定位建議（重要）**：正面做「通用 Shopify」打不贏網路效應；真產品應選一個利基（垂直品類、地區市場如台灣繁中電商、或特定通路型態），把 20% 深做。研究裡的架構讓你有能力做，市場策略決定做哪 20%。

## 10. 風險與紅線

| 風險 | 說明 | 對策 |
|---|---|---|
| Polaris 授權 | 非純 MIT，限 Shopify 整合用；icon/插圖另有授權 | 自建同風格元件庫；icon 用 Lucide；不 import Shopify 套件 |
| 商標/品牌 | 「Shopify」名稱、logo、品牌綠不可用 | 產品用自己的名字與 logo；demo 內文案不用 Shopify 字樣 |
| 像素級複製 | UI 佈局慣例可學，成套視覺資產照搬有 trade dress 風險 | 同設計語言、不同品牌皮膚；真產品階段做自己的視覺 |
| 範圍失控 | 「一模一樣」= 無限工程 | 嚴守 P0/P1 分級與里程碑；每個 M 可跑可看 |
| 單人維運 | 真產品階段的客服/資安/可靠性 | 第三階段再評估；demo 不承諾 SLA |

## 11. 待決策（開工前確認）

1. 技術棧：採建議的 Next.js + Postgres + 自建元件庫？（或 Rails/NestJS 路線）
2. M0–M3 先衝「成交閉環」，或先做 M6 主題編輯器展示效果？（建議前者）
3. Demo 部署目標：本機跑（免費）或上雲（小額月費、可分享連結）？
4. 品牌名：demo 需要一個非 Shopify 的名字（影響 logo/文案/網域）。
