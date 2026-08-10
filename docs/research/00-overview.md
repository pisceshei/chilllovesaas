# 00 — Shopify 產品全景與模組地圖

> 本系列文件是「復刻 Shopify」專案的第一階段研究成果（研究基準：2025–2026 現況，來源以 help.shopify.com、shopify.dev、Polaris 官方文件為主）。目標：把 Shopify 的功能模組、UI 交互邏輯、資料模型拆解到「可以照著做工程規劃」的程度。
>
> 閱讀順序建議：00（本篇）→ 01 後台核心 → 02 UI 交互 → 03 前台主題 → 04 結帳金流 → 05 平台設定 → 06 資料模型 → 07 MVP 計畫。

## 1. Shopify 是什麼（一句話版本）

一個**多租戶電商 SaaS**：任何商家註冊後得到（1）一個功能完整的**商家後台 Admin**、（2）一個可自訂主題的**買家前台 Online Store**、（3）一條由平台統一營運的**結帳與金流管線 Checkout / Payments**，再加上（4）**平台層**：方案計費、權限、多市場、通知、App 生態系與自動化。

復刻專案可以把整個系統切成四個平面：

| 平面 | 內容 | 對應文件 |
|---|---|---|
| Admin（商家後台） | 商品/庫存/訂單/顧客/折扣/分析/行銷 | 01、02、04 |
| Storefront（買家前台） | 主題系統、Liquid 渲染、購物車 | 03 |
| Checkout & Payments | 結帳流程、金流、稅運費計算 | 04 |
| Platform（平台層） | 多租戶、設定、權限、方案、生態系 | 05 |

## 2. Admin 資訊架構（左側導航完整地圖）

Shopify Admin 的左側導航是整個產品的功能索引，復刻 UI 時應以此為骨架：

```
主選單
├── Home（首頁：指標卡片 + 待辦引導）
├── Orders
│   ├── Drafts（草稿訂單）
│   └── Abandoned checkouts（棄單）
├── Products
│   ├── Collections（商品集合）
│   ├── Inventory（庫存）
│   ├── Purchase orders（採購單）
│   ├── Transfers（調撥）
│   └── Gift cards（禮品卡）
├── Customers
│   └── Segments（顧客分眾）
├── Marketing（行銷，近年整合為 Growth 區）
├── Discounts（折扣）
├── Content
│   ├── Metaobjects（自訂資料）
│   ├── Files（檔案庫）
│   └── Menus（導航選單）
├── Markets（多市場）
├── Finance（財務，依方案）
└── Analytics
    ├── Reports（報表）
    └── Live View（即時戰情）

Sales channels（銷售通路區）
├── Online Store
│   ├── Themes（主題）
│   ├── Blog posts / Pages
│   ├── Navigation（舊入口，現多在 Content > Menus）
│   └── Preferences（密碼保護、SEO 全站設定）
├── Point of Sale
└── Inbox / 其他通路 app

Apps（已安裝 App，可 pin 到側欄）

Settings（左下角齒輪，進入獨立的設定框架 → 見 05）
```

頂部列：中央全域搜尋（⌘K / Ctrl+K，command palette 式）、右側通知鈴鐺、商店切換器。

## 3. 模組總表

| 模組 | 一句話職責 | 核心資料物件 | 文件 |
|---|---|---|---|
| Products | 商品主檔：變體、媒體、定價、SEO、集合 | Product、ProductVariant、ProductOption、Collection | 01 |
| Inventory | 品項 × 地點的數量帳：防超賣、進貨調撥 | InventoryItem、InventoryLevel、Location | 01 |
| Orders | 訂單狀態機中樞：付款/出貨/退款/風險 | Order、FulfillmentOrder、Fulfillment、Refund、Return、OrderTransaction | 01 |
| Draft Orders | 商家代客建單、開發票收款 | DraftOrder | 01 |
| Customers | 顧客檔案、同意狀態、分眾 | Customer、Segment | 01 |
| Discounts | 四類折扣、組合規則、資格條件 | DiscountNode（Code/Automatic × Basic/BxGy/FreeShipping） | 01 |
| Admin UI | Polaris 設計系統、列表/詳情頁交互模式 | design tokens、IndexTable、Card、SaveBar… | 02 |
| Online Store | 主題架構（OS 2.0）、theme editor、Liquid | Theme、JSON template、Section、Block | 03 |
| Storefront UX | 商品頁/集合頁/購物車/搜尋的前台交互 | cart、collection.filters、predictive search | 03 |
| Checkout | one-page 結帳、express checkout、Shop Pay | Checkout、AbandonedCheckout | 04 |
| Payments | 收單、authorize/capture、payouts、詐欺分析 | OrderTransaction、Payout | 04 |
| Marketing | 活動歸因、自動化（Flow）、Email/SMS | MarketingActivity、Automation | 04 |
| Analytics | Dashboard、報表庫、Live View | report、dashboard card | 04 |
| Notifications | 數十種顧客/員工通知信模板（Liquid 可改） | NotificationTemplate | 04、05 |
| Settings | 20+ 個設定領域（見 05 的全清單） | Shop、各 domain 設定物件 | 05 |
| Users & Roles | 員工帳號、細顆粒權限、collaborator | StaffMember、Role、Permission | 05 |
| Shipping | profiles × zones × rates、本地配送/自取 | ShippingProfile、Zone、Rate | 05 |
| Taxes | 稅務登記、引擎（Shopify/Basic/Manual Tax）、override | TaxSetting、TaxOverride | 05 |
| Markets | 市場 × 幣別 × 語言 × 網域 × 價格調整 | Market、Catalog | 05 |
| Custom data | Metafields / Metaobjects 自訂欄位系統 | MetafieldDefinition、Metaobject | 05 |
| Apps & channels | App 嵌入（App Bridge）、擴充點、通路 | App、SalesChannel | 05 |
| Flow | Trigger → Condition → Action 自動化 | Workflow | 05 |
| Plan & Billing | 方案階梯與平台計費模式 | Plan、Subscription | 05 |

## 4. 橫切概念（每個模組都會碰到）

- **Shop（租戶）**：一切資料都以 shop 為邊界。復刻時所有表都帶 `shop_id`，網址以子網域（`{store}.myshopify.com` 的等價物）或自訂網域區分租戶。
- **Location**：庫存、出貨、POS、運費的共同維度。
- **Market**：國際化維度——幣別、語言、網域、價格調整依 market 決定。
- **Channel**：同一商品可在多通路上架（Online Store、POS、社群），訂單統一回流。
- **Metafield**：官方欄位不夠用時的自訂欄位機制，掛在幾乎所有資源上。
- **Liquid**：貫穿主題渲染與通知信模板的模板語言。
- **Timeline / Events**：訂單、顧客等資源都有事件時間軸（系統事件 + 內部留言）。
- **Webhook / Event bus**：所有資源變更都發事件，支撐 App 生態與 Flow 自動化。
- **Handle**：資源的 URL 識別字（由標題自動生成、可改、需唯一）。

## 5. 「一模一樣」的邊界（誠實聲明）

1. **功能邏輯與交互模式可以復刻**：流程、狀態機、版面結構、操作習慣不受版權保護，本研究已拆到可實作的程度。
2. **不能直接搬的東西**：Shopify 的程式碼、圖示/插圖資產、商標與品牌名。特別注意：**Polaris 的授權不是單純 MIT**——條款要求應用「與 Shopify 整合/互通」或「與 Shopify 產品明顯不同且視覺可區分」，復刻品兩者皆不符；icon 與圖片另有設計授權（詳見 02 與 07）。demo 階段建議自建「相同設計語言」的元件庫，正式產品要有自己的品牌與視覺。
3. **買不到也寫不出來的**：Shopify Payments 背後的收單牌照與銀行關係、跨店詐欺模型的數據、上萬 App 的生態系。復刻方案：金流接 Stripe（架構上預留 gateway 抽象層）、生態系先不做。

## 6. 文件索引

| 檔案 | 內容 |
|---|---|
| `00-overview.md` | 本篇：全景、導航地圖、模組總表 |
| `01-admin-core.md` | 商品/庫存/訂單/顧客/折扣的功能邏輯與狀態機 |
| `02-polaris-ui.md` | Polaris tokens、admin 佈局、列表與詳情頁交互模式 |
| `03-storefront-themes.md` | OS 2.0 主題架構、theme editor、Dawn 頁面解剖、Liquid |
| `04-checkout-payments.md` | 結帳流程逐欄位拆解、金流、棄單、行銷、分析、通知 |
| `05-settings-platform.md` | Settings 全清單、權限、運費稅務、Markets、App 生態、Flow、方案 |
| `06-data-model.md` | 整合資料模型（ER 圖）與狀態機總表 |
| `07-mvp-plan.md` | 第二階段 demo 原型的範圍、技術棧與里程碑 |
