# 82 — 銷售管道 按鈕級 teardown（R13，2026-08-14 實測＋help/shopify.dev 雙源）

> 六層標準。實測：`chill-love-u5q5mnzq`（全程真實 `href` 導航，鐵律 12.1）。
> 雙源：實測 ＋ help/shopify.dev 管道·POS·agentic·app 五主題（103K）。
> 🔴 本輪解掉一個待決案（B-7／UCP）並結案 R0-STUB1。

---

## §0 架構圖（層③）

### §0.1 🔴 銷售管道**全部是 app**（本輪最重架構事實，實測 href 直證）
```
側欄「銷售管道」區
├─ 線上商店  → /themes                          ← 🔴 第一方特例（不走 /apps）
├─ 代理式    → /apps/agentic
└─ 銷售點    → /apps/point-of-sale-channel
側欄「應用程式」區
└─ Translate & Adapt → /apps/translate-and-adapt
```
- 設定層也是兩頁但同族：`/settings/sales_channels`（已安裝管道 3：銷售點／線上商店／Shop）
  與 `/settings/apps`（已安裝 app 4）。**兩頁的 `⋯` 選單完全相同【3】：開啟應用程式／檢視詳情／解除安裝（紅字）**。
- help 佐證：新增管道的官方流程就是「Settings > Sales channels > **Shopify App Store** > Install」；
  移除＝Uninstall；權限也是同一條「管理和安裝應用程式與管道」。
- ⇒ 🔴 **資料模型應是 `App` 之下的 `Channel`（帶 channel capability），不是兩張平行表**（R13-V2）。
- 管道 app 比一般 app **多三項強制功能**（shopify.dev）：①帳號連接 onboarding ②商品發布 product publishing
  （contextual product feeds，錯誤走 `ResourceFeedback`）③市集導航。另有額外審核門檻（須擁有目標平台、
  預期首年帶進數百家商家）。

### §0.2 🔴 發布模型是**三層 AND**
```
Publishable（Product / Collection / Variant）
    × Publication（綁 channel；autoPublish、supportsFuturePublishing）
    × Catalog（catalogType: APP / COMPANY_LOCATION / MARKET）
```
help 原文：「For a product to be made available in a sales channel, the product must be included in any
catalogs that you assign to the channel market, **and** it must be published to the sales channel.」
- 預設全開：新增管道時既有商品**自動可用**，不要就得逐一移除。
- **variant 層級**與 **collection 層級**都能獨立發布／取消發布。
- **排程發布 future publishing**：適用 products/collections/blog posts/pages；商品必須是 **Active** 才生效；
  **不能**為單一 variant 排程；**Shop 管道不支援**排程發布。
- `publicationCreate/Update` **單次最多 50 個 products**。
- ⇒ 我方商品頁的「上架管道」區塊、目錄（R10）、市場（R10）、代理式目錄是**同一個模型的四個掛載點**（R13-V4）。

### §0.3 條件閘控與載入紀律（層⓪／層⑥）
- **POS 管道頁首次載入內容區空白，重載一次即出現**——層⓪紀律奏效（不是「本尊沒有內容」）。
- 🔴 `/settings/gift_cards` **302 → `/settings/payments?hasMovedNavItem=true`**：
  query 參數自己講明**導航項目已搬家**。⇒ **R12-V1 結案**：禮品卡設定（到期日／Apple Wallet）在**付款**底下。
- 🔴 `/settings/point_of_sale` 我猜的 → **404**。快捷鍵清單裡確實有「前往『設定：銷售點 (POS)』**GST**」，
  但設定搜尋「銷售點」只回 地點／**POS 通知**／新增地點／顧客通知。
  ⇒ 依鐵律 12.1 **不得寫「本尊沒有這頁」**——判定為**條件閘控**（需 POS Pro／已設定地點），登記 R13-V5。

---

## §1 代理式（Agentic Storefronts）【實測全頁】

### §1.1 頁面結構與原文
- 狀態列：`○ Agentic Storefronts 尚未開放使用`
- 🔴 主標原文：**「Agentic Storefronts 未上線，但您的商品可能仍會顯示在人工智慧 (AI) 代理程式中。」**
  ⇒ 語義核心：**未啟用管道 ≠ 商品不會被 AI 看到**（仍可能被 web crawling 抓到）。
- **卡片「準備好使用 Agentic Storefronts」**【2 項待辦】：
  1. ✅ 已完成 — 確保已啟用目錄存取權限（允許 AI 代理搜尋您的商品）
  2. ○ 未開始 — 更新政策（更新您的政策，讓人工智慧 (AI) 代理程式能夠讀取）＋ **檢閱**鈕（指向政策頁）
- **開關「允許 Shopify 為我管理」**（實測為開）
- **AI 代理管道【窮舉 4】**（皆「未啟用」）：
  | 管道 | 備註 |
  |---|---|
  | ChatGPT | help：**僅支援 product discovery**，結帳導回商家商店 |
  | Microsoft Copilot | help：**支援 direct checkout**（Buy → 平台代管結帳 → Pay now，只收標準金流費） |
  | 其他管道 ⓘ | tooltip 原文：「其他如 **Perplexity** 等由 AI 提供支援的平台」 |
  | Shop | 分隔線後獨立一組 |
- **來源【2】**（「供 AI 代理程式用來推薦您的商品」）：
  - **Shopify Catalog** — 目錄中有 0 項商品
  - **Shopify Knowledge Base** — 安裝鈕
- 底部連結「查看您的商品資料如何傳送至適用於 Agentic Storefronts 的 Shopify Catalog」
- 法律：「透過這些銷售管道進行銷售，即表示您同意 **Agentic Storefronts 補充條款**」

### §1.2 管道詳情浮卡【實測】
點任一管道列開浮卡，內容四段：
1. 狀態 badge：**非使用中**
2. **發現來源**：「顧客無法透過 Shopify Catalog 發掘您的商品。但商品可能仍會透過其他來源顯示在 ChatGPT 中」
3. **結帳位置**：「顧客透過您的網路商店結帳」
4. 指標四格：工作階段 0／銷售額 HK$0／訂單 0／轉換 0%
🔴 **發現來源與結帳位置是兩件互相獨立的事**——建模時是兩個布林/枚舉欄位，不是一個「啟用」開關。

### §1.3 help 補完（實測拿不到的）
- 🔴 **符合資格的商店預設啟用，不需安裝**——**唯一一個不用去 App Store 裝的管道**。
- 涵蓋平台：ChatGPT／**Google AI Mode 和 Gemini**（early access）／Microsoft Copilot／Meta。
- 後台控制項（help 版）：允許 Shopify 代管開關／逐平台開關 Catalog 存取／逐平台開關 direct checkout／
  是否自動加入新出現的 AI 管道。
- **Product discoverability tool**：搜尋預覽，顯示 Shopify Catalog 的原始輸出＋listing quality 指標
  （描述完整度／圖片覆蓋／評論／變體資料完整度／政策資訊）。官方警語：這是
  **「a directional signal, not an exact prediction」**（各 AI 平台會再套自己的排序）。
- 存取權限：store owner 或同時具 **商品›檢視** ＋ **應用程式和銷售管道›Agentic**。
- 🔴 **「Shopify's agentic storefronts support only direct-to-consumer (D2C) sales.」**
  B2B-only 商品（B2B catalog／需登入／密碼保護）自動排除，但**自訂第三方設定可能繞過保護**。
- 商家的隱藏手段：對 ChatGPT/Copilot 選擇性 opt out（商品仍可能被 crawl 到）；設為 **Unlisted** 可完全隱藏
  ——**但同時會從搜尋引擎與站內搜尋消失**（與我方 UNLISTED 語義一致，13 §F1.2）。
- 🔴 **Markets 明文排除**：「Agentic storefronts sales channels aren't currently available for adding to
  channel markets.」（佐證 R10 的發現）
- **Agentic plan**：官方方案清單成員，專為**沒有線上商店**的商家；設定四步（產品發現／結帳體驗／訂單管理／
  啟用 AI 管道）；🔴 **必須為每個商品提供指向自家線上商店的外部 product URL**；價格＝文檔未載。
- ⚠️ **`agentic_sales_channel` 這個識別字在官方文檔中查無**（R11 是從**實測維度清單**取得的）——
  以實測為準，登記 R13-DOC1。

---

## §2 🔴 UCP（Universal Commerce Protocol）——待決案 B-7 的答案

### §2.1 它是什麼、誰在治理
- 官方入口 `shopify.dev/docs/agents`（標題「Build commerce agents with UCP」）；規格全文在 **`ucp.dev`**；
  工程部落格 2026-01-11。
- **Shopify 與 Google 共同開發**的開放標準；支持者含 Etsy、Target、Walmart、Wayfair。
- 分層：**shopping service**（交易 primitives）→ **capabilities**（Checkout／Orders／Catalog）→
  **extensions**（以 composition 擴充領域 schema）。
- 擴充命名採 **reverse-domain**：「**Own the domain, own the namespace**」——**無中央審批委員會**。

### §2.2 能力協商（capability negotiation）
- agent 帶一份 **platform profile（JSON）**，URL 放在請求的 **`meta.ucp-agent.profile`**。
- Shopify 端流程：①抓取並驗證 profile ②檢查協議版本相容 ③**能力交集**（比對名稱、檢查版本、
  移除孤立 extension）④回應帶協商後的 UCP metadata。
- 支援版本：**`2026-04-08`、`2026-01-23`、`draft`**。
- 官方提供 fixture profiles 測失敗路徑（空能力／缺 `ucp.version`／不支援版本／版本不匹配／profile 過大／malformed JSON）。

### §2.3 五個 MCP 端點與四階段旅程
「discovery → cart → checkout → orders」
| 面向 | 端點／工具 |
|---|---|
| **Global Catalog MCP** | `POST /api/ucp/mcp`（跨商家）；tools：`search_catalog`／`lookup_catalog`／`get_product` |
| **Storefront Catalog MCP** | `POST https://{storedomain}/api/ucp/mcp`（單一商家，同三 tool） |
| **Cart MCP** | capability `dev.ucp.shopping.cart` v`2026-04-08`；tools：`create_cart`／`get_cart`／`update_cart`／`cancel_cart` |
| **Checkout MCP** | capability `dev.ucp.shopping.checkout`；tools：`create_checkout`／`get_checkout`／`update_checkout`／`complete_checkout`／`cancel_checkout` |
| **Order MCP** | 單一 tool `get_order`；webhooks `orders/create`・`orders/updated`・`orders/delete` |

🔴 **三條實作陷阱**：
1. **`update_cart` 與 `update_checkout` 是 PUT 語義**——「每個請求使用所傳送的裝載替換完整狀態」，
   **省略的欄位會被移除**。與 Storefront API 的逐欄位 patch **完全相反**。
2. **Checkout 狀態機四態**：`incomplete`（缺資訊）／`requires_escalation`（需真人或商家 UI 介入）／
   `ready_for_complete`／`completed`（帶 `order`）。多數整合把買家導到 **`continue_url`** 付款；
   **trusted integrations** 才可在 `complete_checkout` 直接傳付款憑證。
3. **「Your agent can fetch only orders that were facilitated through it.」**——agent 只能查它自己促成的訂單。
- Global Catalog MCP 的 **rate limit 與商家 opt-out 機制＝文檔未載**。

### §2.4 🔴 Liquid 面：`agents.md.liquid`（直接影響我方主題引擎）
- template `agents.md.liquid` → 服務 `/agents.md`，描述該店的 **UCP discovery 與 MCP endpoints**、
  瀏覽 URL 與政策。
- 🔴 **受限的 Liquid context：只有 `request` 與 `agents` 兩個物件可用**，`shop`／`collections` 等全域物件**不可用**。
- 🔴 **`agents.md` / `llms.txt` / `llms-full.txt` 三個 template 都不能是 JSON template，必須是 Liquid template。**
- `agents` 物件屬性：`store_url`／`ucp_discovery_url`／`mcp_endpoint_url`／`ucp_versions`（陣列）／
  `currency`／`sitemap_url`。官方建議**用 agents 物件而非硬編 URL**。
- 預設行為：Shopify 自動管理一份預設 `agents.md`；`/llms.txt` 與 `/llms-full.txt` **預設鏡像 `/agents.md`**，
  加上專屬 template 才分岔。
⇒ 我方主題引擎（M2/M6）必須支援**一種受限 render context**，與現有 template context 不是同一套（R13-V3）。

---

## §3 POS【help 為主，實測補頁面殼】

### §3.1 實測：POS 管道頁
- 頁首動作【3】：管理地點／管理員工／`⋯`
- 主體：①黑底 hero「**登入並開始使用 POS 銷售**／掃描 QR 碼下載 app」＋QR
  ②**分析**（期間選擇器「過去 30 天」）：銷售總額圖表＋訂單／折扣／退貨三卡
  ③**為您推薦**：「透過以零售為主的顧客群，提升商店忠實度」＋建立顧客群鈕（可 ✕ 關閉）
  ④「深入瞭解 Shopify POS」
- 🔴 首次載入空白、重載一次才出現（層⓪）。

### §3.2 🔴 POS Lite vs Pro 完整對照（help 逐項；這是 POS 範圍裁定的材料）
**Lite（所有付費方案內含）有、Pro 也有**：整合式付款硬體／非付款零售硬體整合／可自訂 smart grid／
新增編輯顧客檔案／Customer View app／多地點庫存·訂單·顧客管理／Email 與 SMS 收據／折扣碼與手動折扣／
販售與兌換禮品卡／稅額計算／相機條碼掃描／自訂銷售／離線現金付款／員工 PIN／退款／現金追蹤／
變更庫存數量／後台庫存管理

**🔴 Pro 專屬（Lite 沒有）**：自訂列印收據／**自動折扣**／零售員工權限與管理／**無限 POS-only 員工**／
將員工加入銷售／**訂單取消**／**換貨**／儲存與取回購物車／Email 購物車／**寄送到府**／**寄送並帶走**／
**店取**／**本地配送履行**／**追蹤與調整庫存**／**接收轉移**／**履行與接收轉移**／**日銷售報表**／
**店內分析**／必填結帳資訊／硬體保固 2 年（Lite 1 年）

⇒ 🔴 **Lite ≈ 收銀機；Pro ≈ 門市營運系統**。這條界線本身就是產品分層的現成原型。

### §3.3 計價與方案
- POS Lite：「available on all subscription plans」／所有付費方案免費內含。
- **POS Pro ＝ per-location 加購**，管理位置在 **銷售管道 › 銷售點 › 設定 › POS Pro Subscription**，
  逐 location「Add POS Pro／Cancel POS Pro」；**批次最多 250 個 locations**；年繳者計費週期內不可降級。
- **Plus**：「The first 20 POS Pro locations are included in all Shopify Plus plans」；超過 20 且每月至少
  1 筆零售交易 ⇒ 全部免費。
- 試用 **3 天**，到期需**手動**選回 Pro。退款窗：月繳 7 天／年繳 30 天。
- 價格（官方定價頁，非 help）：**POS Pro US$89/月/location**。
- **中國不支援**；裝置需 iPad 5th gen+／iPhone 7+／Android 10.0+；支援 20 種語言（由**裝置語言**決定，非 app 內切換）。

### §3.4 🔴 POS 權限模型與 admin **完全不同**（補完 R12）
- 「**POS permissions are managed through organization roles rather than store permissions.**」
  ——POS 權限**不在 store permission 樹裡**。
- 🔴 **「you can't assign individual permissions to Point of Sale staff」**——POS **只能指派角色，不能指派單一權限**。
- POS Lite 地點：所有 admin user 皆 full access，**role 限制不生效**。
- **POS-only staff** 僅 Pro 有：只能用 POS app、不能進後台、用 **PIN** 登入、只能登入 Pro locations。
- 預設 POS role ＝ **Associate**（名稱與權限集可改）。
- **POS 權限【9 群組，help 窮舉】**：
  | 群組 | 權限 |
  |---|---|
  | Manager Approval | 以 PIN 核准員工動作 |
  | Checkout | 自訂銷售／寄送給顧客／編輯稅額／接受離線信用卡與簽帳卡／禮品卡小額兌現 |
  | Discounts | 套用自訂折扣（整車與單品項）／套用折扣碼（整車） |
  | Orders | 管理所有地點訂單／管理銷售歸屬／退貨與換貨／**退不合格品項**／建立未驗證退貨／完成進行中退貨／管理補貨去向／移除未履行品項／取消／管理已存購物車／管理近期購物車到期／管理訂單草稿／履行寄送與取貨訂單（Ship from Store）／重新指派或取消履行／管理轉移 |
  | Customers | 建立／編輯／刪除／檢視／中繼欄位檢視與編輯／**兌換商店抵用金**／**管理商店抵用金** |
  | Apps | 使用相容 app／**管理 POS UI extensions** |
  | Analytics | **檢視裝置所在地點的分析**（日銷售報表） |
  | Register | 管理付款追蹤／檢視追蹤工作階段歷史／開始與結束追蹤／存取 POS 管道的現金追蹤工作階段／從後台結束追蹤／開啟錢櫃 |
  | Store settings | **自訂 smart grid**（限裝置所在地點）／管理裝置付款設定／管理離線付款／切換離線結帳／管理收據設定／管理必填結帳資訊／切換裝置地點／登出 |
- 🔴 **設計啟示**：POS 權限的粒度**以「裝置所在地點」為軸**（多條寫明 "for their location"／"at the device's location"），
  而非以資源為軸——**照 admin 的資源樹套 POS 會做不出這個語義**（R13-V6）。

### §3.5 其他 POS 概念（help）
- **Smart grid**：後台 POS editor 可自訂 app 鎖定畫面與 smart grid、顧客面向顯示器、列印收據；
  **smart grid templates** 可建多份並指派給不同地點，有一份標為 **Default**（自動套用到新地點）；
  tile 可新增／編輯／重排／**改色**／移除。**完整 tile 類型清單＝文檔未載**。
- **Register session／cash tracking**：起始 float ＋期間 deposits/withdrawals ＋最終實體清點；
  **discrepancy** ＝ 預期 vs 抽屜實際。可從 app 或後台逐地點產報表。另有獨立的 **cash rounding on POS**。
- **小費**：設定在 POS settings > Checkout > Tips；最多 **3 個預設百分比**＋自訂小費；
  🔴 **只支援信用卡付款**；USD/CAD 交易 ≤$500 時小費上限 $1000，超過則為交易額兩倍。
- **POS UI extensions**（shopify.dev）三種 target：**Tiles**（smart grid 磚）／**Actions**（從選單鈕開 modal 或全螢幕）／
  **Blocks**（畫面內自訂區塊，例 `pos.product-details.block.render`）。
- **POS 訂單 vs 線上訂單的來源標記／庫存扣減／稅務差異＝文檔未載**（只知 Tax calculations 兩層皆有、
  「管理所有地點訂單」暗示 POS 訂單預設綁裝置地點）。

---

## §4 應用程式【實測＋help】

### §4.1 實測：設定›應用程式
- 頁首【2】：**開發應用程式**／**Shopify App Store**
- 檢視 chip「已安裝」＋排序鈕；逐列 `⋯`
- 實測已安裝 4 個（Translate & Adapt／DealerSend Logistics Limited／ShipAny／Fecify）
- 🔴 與設定›銷售管道**是兩個列表**（管道 3：銷售點／線上商店／Shop），但 **`⋯` 選單相同【3】**：
  開啟應用程式／檢視詳情／**解除安裝**（紅字）

### §4.2 help 補完
- **App 類型 4 種**：Public–Listed／Public–Unlisted（不出現在搜尋，可用直接連結安裝）／
  **Custom app**（透過 **Dev Dashboard** 建立）／**Legacy custom app**（🔴 **2026-01-01 前建立**，可直接在後台管理）
  ⇒ **2026-01-01 是分界點**。
- 🔴 **「To access Custom Level 2 PII apps, your store must be on the Grow plan or higher」**。
- **安裝畫面的 scope 呈現分兩類**：**「View personal data」**（顧客·店主個資）與
  **「View and edit store data」**（顧客/商品/訂單/折扣等區域）＋開發者隱私政策連結。
- 開發者側：**Shopify managed install（推薦）**——「Shopify installs an app and updates its access scopes
  without making any calls to the app」，無 redirect；scopes 宣告在 `shopify.app.*.toml` 的 `[access_scopes]`。
- **app 詳情頁區塊**：計費與用量費用／活動與權限（存取區域·近期活動）／隱私（可存取的個資類別）／
  Extensions·Functions·Pixels／自訂 app 設定／**Legacy custom apps**／App proxy URL。
  另有**最近解除安裝**清單可還原。
- **計費**：一次性／免費·月繳·年繳訂閱／用量計費；🔴 **費用直接進商家的 Shopify 帳單**；
  但部分第三方 app 在 Shopify 外直接收費。
- **Protected customer data 三級**：Level 0 無顧客資料／Level 1 有但**不含** name·address·phone·email／
  **Level 2 含**這四類，需申請＋實作 L1+L2 要求＋**參與 data protection review**。
- **Theme app extension**：**app block**（可指向 dynamic sources、商家可增刪排序自訂）vs
  **app embed block**（浮動/覆蓋或注入不可見程式碼；🔴 **只能存取所在頁面的 Global Liquid scope**；
  🔴 **所有主題都支援**，所以 onboarding 說明可以只有一套）。
- **app 權限**：管理和安裝應用程式與管道（可授權全部或**逐一勾選特定 app**）／核准應用程式費用／
  **啟用開發作業**（🔴 **預設不允許自訂 app 開發**）／開發／檢視由員工和協作者開發的應用程式。
  🔴 **POS 管道的權限被排除在這條之外**；Agentic 另有專屬節點。

---

## §5 官方第一方管道清單（help）
- **社群商務**：Facebook and Instagram by Meta／TikTok Shop／**Roblox**（⚠ 無 Pinterest、Snapchat）
- **線上市集**：Google & YouTube／**Shopify Marketplace Connect**（🔴 **Amazon 與 Walmart 併入這一支**，
  不再是獨立第一方管道）／Faire／Newegg／StockX／Temu／Whatnot／DoorDash
- **Shopify 自製**：Buy Button／Shopify Collective（Retailers＋Suppliers）／Headless／Sell on WordPress／Shop Channel
- **Shop**：涵蓋 iOS／Android／web／**agentic shopping experiences**；符合資格自動上架；14 種語言
- **Buy Button**：所有方案內含；官方**不建議**用在自家 Shopify 商店（改推 cart permalink）；
  2016-10-10 前建立的已不支援
- **Handshake**：help 已無現存頁面；第三方來源指 2023-10 退場（Faire 接手）——**官方退場公告＝文檔未載**
- 🔴 **官方不維護「已下架管道清單」**；「Unsupported sales channels」講的是第三方管道沒跟上 breaking changes 的處理
- **管道數量上限＝文檔未載**；資格逐管道判定，不符時顯示 **Unavailable** 並可點看原因

---

## §6 CSS 三段式（層④）

| # | 部位 | 本尊量測 | 我方 token |
|---|---|---|---|
| 1 | 管道列（設定內） | 列高 49px、圖示 24px 圓角 6px＋間距 16px、名稱 13px/450、行尾 `⋯` 28px | `--h-row` `--sp-400` `--fs-100` |
| 2 | 代理式主標 | 28px/1.25、字重 650、最大寬約 34ch | `--t-2xl` `--lh-125` |
| 3 | 準備清單列 | 列高 56px、狀態圖示 20px、標題 13px/600＋副標 13px `#616161` | `--h-row-lg` `--fg-subdued` |
| 4 | 管道詳情浮卡 | 寬 400px、圓角 12px、內距 16px、指標四格 2×2 gap 12px | `--w-popover` `--r-300` `--sp-400` |
| 5 | POS hero | 高 232px、深色底 `#0A0A14`、標題 24px/700 白、QR 138px 白底圓角 8px | `--bg-inverse` `--t-xl` |
| 6 | 指標小卡 | 內距 16px、label 13px `#616161`、值 20px/600 tabular-nums、變化 12px | `--sp-400` `--num-tabular` |
| 7 | 破壞性選單項 | 紅字 `#D0253C`、其餘同一般選單項 | `--sem-critical-text` |

---

## §7 對我方的裁定面（→ 71 §F）

1. **R13-STUB1 結案**：三顆 toast 佔位（AI 代理／門市 POS／新增應用程式）轉為真頁面。
2. **R13-V2 資料模型**：`App` 之下的 `Channel`（channel capability），不是兩張平行表。
3. **R13-V3 主題引擎**：`agents.md.liquid` 是**受限 render context**（只有 `request`＋`agents`，
   且不可為 JSON template）——M2/M6 前必須確認引擎支援這種 context。
4. **R13-V4 發布模型三層 AND**：Publishable × Publication × Catalog，四個掛載點要同步。
5. **R13-V6 POS 權限以「裝置地點」為軸**且**只能指派角色不能指派單一權限**——不可套用 admin 的資源樹。
6. **🔴 R13-V1 POS 範圍需使用者裁定**：Lite/Pro 的界線（收銀機 vs 門市營運系統）是現成的分層原型；
   本輪只做了管道殼與分析，**POS 本體（smart grid／register session／PIN／班次／換貨）完全沒做**。
7. **B-7／UCP 有答案了**：官方開放標準、規格在 ucp.dev、Shopify+Google 共同開發、
   五個 MCP 端點、能力協商用 profile、checkout 四態、`update_*` 是 PUT 語義。
   ⇒ 我方要不要實作 UCP 相容層是**產品決策**（R13-V7），但**技術面已不是未知**。

---

## §8 🔴 發布模型的**寫入生產者規則**（2026-08-26 實測補完 §0.2）

> 取證：`chill-love-u5q5mnzq`，2026-08-26。§0.2 的三層 AND 當時**只有 help 單源**；
> 本節把它升級成實測，並補上 help 完全沒講、但決定我方實作的那一半——**誰在什麼時候建立那些列**。
>
> 工具限制照鐵律 14.3 登記：本尊 admin 走 persisted-query API，**query 全文不可觀測**；
> ad-hoc GraphQL 一律回 **403**（實測）。故本節記 **operation name ＋ variables 形狀 ＋ response 形狀**，
> 讀取面的 response 是**重放 admin 自己發過的 persisted query** 取得的原始 JSON。

### §8.1 實測材料

| 標的 | GID | 實測當下狀態 |
|---|---|---|
| 既有多變體商品 | `Product/9907126370539`（實測用 T恤 多變體） | Active，商品層 3 管道 |
| ↑ 的變體 S | `ProductVariant/49283448701163` | **本輪主動關掉 Point of Sale** |
| ↑ 的變體 M／L | `.../49283448733931`、`.../49283448766699` | 未觸碰（對照組） |
| 本輪新建商品 | `Product/9911273160939`（P12 發布模型實測用商品） | 建立→改 Unlisted→商品層關掉 POS→加 Size 選項 |

🔴 **測試店狀態被刻意留在這個形態**（鐵律 12.2 全權授權）：它是目前倉庫外唯一一組
「三層彼此不一致」的活體 fixture，刪掉就要重做一次才能複驗。

### §8.2 讀取面：**正向、稠密**，不是「例外排除」也不是「無列即繼承」

`VariantsPublications` 的 response 只列出**已發布到**的 publication，未發布者**直接不在陣列裡**：

| 變體 | `channelPublicationCount` | `channelPublications[].publication.name` |
|---|---|---|
| S（本輪關掉 POS） | 2 | Online Store, Shop |
| M（未觸碰） | 3 | Online Store, Point of Sale, Shop |
| L（未觸碰） | 3 | Online Store, Point of Sale, Shop |

🔴 **M／L 是判別式**：如果變體層是「無列＝繼承父商品」，未觸碰的變體應該回 **0 列**。
它們回 3 列且逐一具名 ⇒ **每個變體 × 每個 publication 都有一列被實際物化**。
⇒ 我方 `resource_publications` 的多型設計方向正確，但**必須有人建那些列**（§8.4）。

### §8.3 寫入面：unpublish 是**獨立的一支 operation**，不是整批覆寫集合

在變體子頁關掉一個管道並存檔，network 面板抓到**兩支各自獨立的 POST**：

| # | operation name | 說明 |
|---|---|---|
| 1 | `ProductVariantUpdate` | 變體本體欄位 |
| 2 | 🔴 `ProductVariantUnpublish` | **只為「取消發布」而存在的專屬 mutation** |

⇒ 語義是**逐 publication 的增刪**，不是「送出完整集合、伺服器算差集」。
我方 GraphQL 契約應照此分成 publish／unpublish 兩支，而不是一支吃全集的 `setPublications`。

### §8.4 🔴 生產者規則（本節最重的四條，help 完全沒有）

**① 新商品：建立後即在全部管道上「已發布」，且預設全開**
新增商品表單在**存檔前**就顯示 `Active` ＋ `All channels`；存檔後其預設變體
`channelPublicationCount = 3`。⇒ 「auto\_publish」不只是「新增管道時回填既有商品」，
**它同時是「新增商品時對既有管道全部生效」**。

<!-- 🔴 **2026-08-26 更正（第二輪對抗審查 M28）。原文寫的是「建立當下即物化（寫列）」——
     那是把一個不可觀測的推論寫成本尊事實。**
     從 admin UI 與 Admin API **都無法區分**這兩種實作：
       (a) 建立時就寫 publishable × publication 的列；
       (b) 不寫列，讀取時以 `auto_publish` 展開。
     兩者的 `resourcePublications` 回應**完全一樣**，`channelPublicationCount` 也一樣。
     官方原文只有 "Whether new products are automatically published to this publication."，
     同樣推不出儲存形態。
     ⇒ 本條現在只斷言**可觀測的那一半**（「建立後即已發布」），
     **儲存形態＝未取得**（§9.12）。我方選擇稠密物化是**我方裁定（ours）**，
     理由在 `docs/dev/m2-publication-model.md`，不是「本尊這樣所以照抄」。
     🔴 這很重要，因為那條推論撐著我方整個 O(publishable × publication) 的寫入成本。
     **唯一能取到的證據（只能證偽不能證實）**：若本尊在**新增一個管道之後**，
     既有商品立刻在該管道可見，就與「只在 create 時寫列」不相容。
     那一測同時解掉 §8.7／§9.12 的「新增 publication 是否回填既有商品」。 -->

<!-- 🔴 這一條直接結掉 88 §5 的待辦 #2。88 §2.1 原本把 auto_publish 寫成
     「新增管道時既有商品自動可用」——那只是它的一半，而且是我方**不會先遇到**的那一半
     （v1 建店只建 online_store，之後沒有新增管道的流程）。先遇到的是這一半：
     **商品建立時要不要填 publication 列**。填 = 商品能上架；不填 = 全站商品永遠不可購買，
     而所有 spec 都會照樣綠——因為沒有任何 spec 斷言過「新商品必須有 publication 列」。 -->

**② 新變體的儲存列涵蓋父商品沒有的管道**
實測條件刻意做成父子不一致：`Product/9911273160939` 當時是 **Unlisted** 且商品層
**只發布到 {Online Store, Shop}**；在這個狀態下新增 Size 選項產生兩個變體：

| 新變體 | `channelPublicationCount` | 管道 |
|---|---|---|
| AB | **3** | Online Store, **Point of Sale**, Shop |
| CD | **3** | Online Store, **Point of Sale**, Shop |

新變體的儲存列含**父商品自己都沒有的 Point of Sale**。

🔴 **本條的證據強度低於 ①③④，必須照實登記（鐵律 19）**——有兩件事拉扯：

**(a) 官方文檔說的是另一回事。** `shopify.dev/docs/apps/build/sales-channels/product-publishing`
（取證 2026-08-26）逐字：
> If you don't set `published`, or set it to `true`, the variant is created with the default state of
> **published to all channels and catalogs where the parent product is published.**

**(b) 我這個實驗有一個排除不掉的替代假說。** 加選項時，Shopify 可能是把**原本那顆
`Default Title` 變體**衍生成 AB／CD——而它是在商品還在 3 個管道時建立的，本來就有 3 列。
若如此，AB／CD 的 3 列來自**兄弟／前身變體**，不是「全部 auto\_publish 管道」。
本輪沒有做能分辨這兩者的實驗（要先把父商品與所有既有變體都從某管道下架，再新增變體），
**⇒ 登記為未取得。**

**(c) 但兩邊其實不衝突，因為「儲存」與「生效」是兩回事**——這是同一輪在 UI 上拿到的
直接證據：對兩個變體開「Manage publishing for 2 variants」時，**Point of Sale 那一列
呈灰、帶 ⓘ、但 toggle 仍是開的**，提示逐字：
> **Product must be published to the channel before variants can appear**

⇒ 變體在該管道上**確實有列**（toggle 開），只是被商品層閘掉。官方那句描述的是
**生效狀態**，我量到的是**儲存狀態**，兩者可以並存。

🔴 **我方採「全部 auto\_publish 管道」**，理由不是「實測贏過文檔」，而是三點合起來：
①它與實測的儲存狀態一致；②它與本尊自陳的 opt-out 模型一致
（官方逐字：「Variants default to published (opt-out model)」、
「Variant publishing state persists across product publishing changes, so you can configure
variant visibility **before** publishing the product」）；③它的商家後果較好——商品日後
發布到新管道時，變體立刻跟著可見，不必逐一補發布。
**這是我方裁定（ours），不得寫成「照抄本尊」。**

**③ 層與層之間不連動（決定性實驗）**
把 `Product/9911273160939` 的商品層 Point of Sale 關掉並存檔後，重新讀它的變體：
`channelPublicationCount` 仍是 **3**，且 **Point of Sale 仍在列**。
⇒ 商品層的寫入**不會**串聯改寫變體層的列。**三層是各自獨立的儲存，可用性是讀取時才做的 AND。**

<!-- 🔴 這條是整輪最值得記的一條，因為它決定「不變量要寫在哪一層」。
     若寫入時串聯（父關子也關），資料庫裡就永遠滿足 discoverable ⊆ purchasable，
     讀取可以只看一層——但本尊不是這樣做的，照抄那個直覺會在「父關了又開回來」時
     把使用者原本刻意關掉的子層設定一起還原，且無法還原回去（資訊已被覆蓋掉）。
     本尊選的是**保留每層的獨立意圖、讀取時取交集**，這樣父層開開關關不損失子層資訊。 -->

**④ `status` 與 publication 正交**
把商品從 `Active` 改成 `Unlisted` 並存檔後，商品層與變體層的 publication 列**完全沒變**。
⇒ 商品狀態不是 publication 的寫入來源，兩者在讀取時才一起參與判定。

### §8.5 `ProductStatus` 值域窮舉（帶本尊一行語義原文）

商品頁 Status 下拉逐項展開（層②值域窮舉）：

| 值 | 下拉內的一行說明（原文） |
|---|---|
| Active | `Sell via selected sales channels and markets` |
| Draft | `Not visible on selected sales channels or markets` |
| **Unlisted** | `Accessible only by direct link` |

🔴 **`Archived` 不在這個下拉裡**——歸檔是 `More actions` 底下的**獨立動作**，不是狀態選項。
⇒ 我方若把 archived 做成 status 下拉的第四個選項就與本尊不一致；它應該是一個**動作**。

🔴 **`Unlisted` 的一行語義正好就是「可購買但不可發現」**，即我方第 12 包那條不變量
（`discoverable ⊆ purchasable`）的產品化形態——它不是我方發明的抽象，是本尊的實裝值。

### §8.6 UI 形態登記（層①，供原型對齊）

| # | 位置 | 形態 |
|---|---|---|
| 1 | 商品清單 | 有 **Channels** 欄，顯示管道數（實測：多變體商品 3、其他 1） |
| 2 | 商品頁 | **Publishing** 卡，內文**列出管道名**（`Online Store, Shop`），右上齒輪開 modal |
| 3 | modal | 標題 `Manage publishing for {product}`；左側 `Sales Channels (3)` ＋ `Agentic (1)`；有搜尋框；群組列有一個總開關（子項半選時呈 indeterminate） |
| 4 | 變體子頁頂部 | 兩個控件：管道摘要（全集顯示 `All channels`，子集顯示 `N channels`）＋ 目錄摘要（`None`） |
| 5 | 變體清單 | 有 `Sales channels ˅` 篩選器 |
| 6 | 變體表格 | 有 **Publishing** 欄，同一格顯示**兩個計數**（管道數、目錄數） |
| 7 | 變體 modal | 標題 `Manage publishing for 1 variant`，結構與商品層 modal 相同 |
| 8 | 選項編輯 | `Add options like size or color` 先開下拉：可綁 **metafield 定義**，或 `Create custom option` |

🔴 #3／#4 的 `Agentic` 與目錄摘要證實**第三層 catalog 在 UI 上是與管道並列的獨立軸**，
不是管道的附屬——與 §0.2 的三層模型一致。

### §8.7 誠實登記：本輪**未取得**的

- **新增一個 publication 時是否回填既有商品**（auto\_publish 的另一半）：需要安裝新管道 app 才測得到，
  本輪未做（會改動測試店的已安裝 app 清單）。§0.2 的該句仍是 **help 單源**。
- **`auto_publish` 在 admin UI 哪裡設定**：本輪未找到入口。三個管道是否都 `auto_publish = true`
  只能從「新商品拿到 3 個管道」反推，**不是直接觀測**。
- **`ProductVariant` 能否透過公開 Admin API 做 publish/unpublish**：本輪只證實 admin **內部** operation
  `ProductVariantUnpublish` 存在，公開 API 面未取證。
- **`Unlisted` 的前台實際行為**（直連可買／搜尋隱藏／`noindex`）：本輪只取得下拉內的一行說明，
  未在前台驗證。

---

## §9 🔴 第二輪窮盡實測（2026-08-26，全權寫入授權）

> 使用者裁定「即使已經顯示完成了的，都要重新做一次，避免有遺漏或者邏輯錯誤」＋
> 「本尊後台我授權你可以任意操作，新增，編輯，刪除等等所有步驟」。
> 本節只記 §8 **沒有**的東西。§8 的六條結論本輪全部複驗成立，不重複。
>
> 🔴 本輪**實際建立了一個 catalog**（`MarketCatalog/103379370219`），
> 因此第一次觀測到第三層（catalog）的真實形態——`docs/specs/88` §3.2 把它整層延後，
> 過去從來沒有人量過它。

### §9.1 商品列表：批量動作的完整值域

**欄位**：`Product ｜ Status ｜ Inventory ｜ Category ｜ Channels ｜ Product type ｜ Vendor`
🔴 建立 catalog 之後**自動多出 `Catalogs` 欄**——列表欄位是**動態**的，隨店鋪是否有 catalog 而變。

Status 徽章：Active＝綠、**Unlisted＝灰**（中性）。

**批量列**：`N selected ˅ ｜ Bulk edit ｜ Set as active ｜ Set as draft ｜ ⋯` ＋ `Show all selected`

**溢出選單完整值域（13 項，依序）**：

| # | 項目 |
|---|---|
| 1 | Archive products |
| 2 | **Unlist products** |
| 3 | Delete products（紅字） |
| 4 | **Include in sales channels** |
| 5 | **Exclude from sales channels** |
| 6 | **Include in catalogs** |
| 7 | **Exclude from catalogs** |
| 8 | Add tags |
| 9 | Remove tags |
| 10 | Add to collection(s) |
| 11 | Remove from collection(s) |
| 12 | Apps（分組標題） |
| 13 | Create email campaign |

🔴 **兩個軸各有兩個方向**：管道與目錄是**獨立的兩組**動作，各有 include／exclude。
用詞是 **Include／Exclude**，不是 Publish／Unpublish。

### §9.2 🔴 四個狀態的可及性是**三個面各不相同**的

| 面 | Active | Draft | Unlisted | Archived |
|---|---|---|---|---|
| 商品頁 Status 下拉 | ✅ | ✅ | ✅ | ❌ |
| 商品頁 `More actions` | ❌ | ❌ | ❌ | ✅ `Archive product` |
| 列表批量**頂層按鈕** | ✅ `Set as active` | ✅ `Set as draft` | ❌ | ❌ |
| 列表批量**溢出選單** | ❌ | ❌ | ✅ `Unlist products` | ✅ `Archive products` |

商品頁 `More actions` 完整值域（5 項）：
`Duplicate product` ｜ `Archive product` ｜ `Delete product`（紅） ｜ `Create email campaign` ｜ `Localize`（app 提供）

### §9.3 🔴 發布控件有**三種不同的 affordance**

| 位置 | 形態 | 可編輯 | 內容 |
|---|---|---|---|
| 商品詳情頁 Publishing 卡的齒輪 | **全 modal** | ✅ | 左側導覽：`Sales Channels (3)` ／ `Agentic (1)` ／ `Catalogs › Regions (1)` |
| 系列詳情頁的 `N channel ˅` | **輕量 popover** | ✅ | 只有三個銷售管道，**無 Agentic、無 Catalogs** |
| 商品列表選中列的 `N ˅` | **popover** | ❌ **唯讀** | 只列出已發布的管道名 |

🔴 系列沒有 Agentic／Catalogs 組，精確對應官方那句：
> `Collection` only supports publications to `APP` catalog types.

我方 `ResourcePublication::PUBLISHABLE_TYPES` 三型別**一視同仁**，沒有這個區分（登記）。

🔴 商品頁的 modal 左側導覽是**動態**的：建 catalog 前只有兩組，建了之後長出
`Catalogs` 區段並依 catalog 型別分組。

### §9.4 批量發布對話框：**checkbox 不是 toggle**

- 路由（真實 href）：`/products/sales-channels/publish?includesBundle=false&selectedProductIds=<CSV>`
  🔴 帶 **`includesBundle`** 參數 ⇒ **組合商品（bundle）在發布上另有規則**（**未取得**）
- 標題 `Include {N} product(s) in sales channels`；按鈕 `Cancel` ／ `Include products`
- catalog 版路由：`/products/catalogs-next/publishcatalogs?selectedProductIds=...`，
  🔴 **三個分頁 Regions｜B2B｜Retail（無 Channels）**；空態
  `Your store doesn't have any catalogs of this type yet.`

🔴 **互動語義的關鍵差異**：

| 面 | 控件 | 語義 |
|---|---|---|
| 單一資源的發布 modal／popover | **toggle** | **狀態設定**（顯示目前開／關） |
| 批量 Include／Exclude | **checkbox** | **累加／扣除**（不顯示目前狀態） |

⇒ 與官方 `publishablePublish(id, input: [PublicationInput!]!)` **收「要加的清單」**的語義一致。
我方若做批量面，**不得**做成「送完整集合、伺服器算差集」。

### §9.5 🔴 第三層（Catalog）的真實形態——本節是本輪最大的新增

#### §9.5a 何時生效：本尊自己的話

建立 catalog 存檔時彈出確認框，**逐字**：
> **This catalog won't change products or prices**
> Customers will see your store's products and default prices in the assigned markets,
> converted by each market's currency settings.
> **You only need a catalog if you want different products or prices.**

按鈕：`Discard` ／ `Save anyway`

🔴 ⇒ **第三層是 opt-in 的**：catalog 若沒有「不同的商品或價格」就是 **no-op**。
與官方 `publicationCreate` 頁同義（「When a publication isn't associated with a catalog,
product availability is determined by the sales channel.」）。
**這給了 `docs/specs/88` §3.2「第三層延後」一個實證依據，而不只是分期的說法。**

另：`Assign markets` 對話框的 `Channels` 分頁空態是
`Your store doesn't have any markets of this type yet.`
⇒ **channel market 預設不存在，要商家自己建** ⇒ 預設店鋪根本沒有 catalog 約束。

#### §9.5b 建立 catalog 觸發**四支** operation（網路抓包，依序）

| # | operation | payload（逐字節錄） |
|---|---|---|
| 1 | `CatalogCreate` | `{"input":{"title":"…","status":"ACTIVE","context":{"marketIds":["gid://shopify/Market/40566653163"]}}}` |
| 2 | `CatalogPriceListCreate` | `{"input":{"currency":"HKD","parent":{"adjustment":{"value":0,"type":"PERCENTAGE_DECREASE"},"settings":{"compareAtMode":"ADJUSTED"}},"catalogId":"gid://shopify/MarketCatalog/103379370219","name":"…"}}` |
| 3 | **`PublicationCreate`** | `{"input":{"defaultState":"EMPTY","autoPublish":true,"catalogId":"gid://shopify/MarketCatalog/103379370219"}}` |
| 4 | **`PublicationChangesCommit`** | admin 內部批次提交操作，**不在公開 API 文檔** |

`PublicationCreate` 的 response 揭露結構：`Publication/214892183787` → `catalog: MarketCatalog/103379370219`
→ `priceList: PriceList/21058420971`（currency HKD、adjustment `PERCENTAGE_DECREASE`）。

🔴 **結構結論**：

```
Catalog（AppCatalog／MarketCatalog／CompanyLocationCatalog）
  ├─ has one ─> Publication（autoPublish, defaultState）
  └─ has one ─> PriceList（currency, adjustment, compareAtMode）
```

- catalog、priceList、publication 是**三支獨立的建立操作**
- `catalogId` 是**傳進** `publicationCreate` 的 ⇒ **publication 屬於 catalog**
  ⇒ 我方 `publications.catalog_id` 的**方向正確**
- 🔴 **每個管道 publication 也有 catalog**：§8 抓到的 Online Store 讀取 payload 顯示
  `catalog: { id: "gid://shopify/AppCatalog/…", title: "Channel Catalog {publicationId} for Online Store" }`
  ⇒ **本尊的每個 publication 都有 catalog**，只是型別不同。
  我方的 `online_store` publication **沒有 catalog**（結構差異，v1 無影響，登記）。

#### §9.5c catalog 表單的完整控件與上限

| 區 | 控件 | 值／上限 |
|---|---|---|
| Title | 文字 | **0/255** 字元計數 |
| （同列） | 狀態下拉 | 預設 `Active` |
| Markets | 選擇器 ＋ `Add a market` | 對話框**四分頁** `Regions｜B2B｜Retail｜Channels` |
| Pricing | `Set prices in` | `Store currency (HKD HK$)` |
| Pricing | `Price adjustment` | 數字 ＋ `%` ＋ 方向下拉 `Decrease` ＋ toggle `Include compare-at price`（預設**開**） |
| Products | toggle **`Automatically include new products`** | **預設開** |
| Products | 分頁 | **`Included｜Excluded｜All`** |

catalog 內商品表欄位：`Image｜Product｜Publishing｜Price in HKD｜Compare at price｜Rules`

- 商品列可展開成**變體列**，每個變體有自己的 `Price`／`Compare-at price`
  ⇒ **catalog 的價格是變體粒度**
- 商品列副標 `2 of 2 variants` ⇒ **catalog 成員也有變體粒度**
- 每列帶 `Included`／`Excluded` 徽章 ⇒ **成員是三值的**（含明確的排除集合），不是布林
- 篩選器：`Status ˅｜Product vendor ˅｜Tagged with ˅`

#### §9.5d 🔴 catalog 成員是**非同步計算**的，且進行中會**鎖住**逐商品切換

建立後 Products 卡長時間顯示 `Loading products…`；剛建立時
`No products included`／`Include products to sell them in the assigned markets.`，重載後才有內容。

而商品頁 modal 的 `Catalogs › Regions` 組裡，該 catalog 那一列 toggle **灰掉**並附訊息：
> ⓘ **Publishing for this catalog can't be changed while updates are in progress.**

🔴 對應官方 `Publication.operation: PublicationOperation`
（`AddAllProductsOperation`／`CatalogCsvOperation`／`PublicationResourceOperation`）。
⇒ **批量發布變更是非同步的，進行中必須鎖住逐資源切換並說明原因。**
我方模型**沒有「進行中的發布操作」這個概念**。

⚠️ **本輪未解的矛盾**：建立 catalog 後用 persisted query 量到兩個不同商品的變體
`catalogPublicationCount` 都是 **1**，但商品列表的 `Catalogs` 欄顯示 **0**。
兩者不一致（可能是「publication 列」vs「明確 Included」的差別，或列表快取）⇒ **未取得**。

### §9.6 🔴 密碼保護是**第四道閘門**，且是分享的前置條件

商品頁點 `Share` 彈出：
> **Remove password protection**
> To make products available to share, remove your online store password protection.

按鈕：`Cancel` ／ `Go to preferences`

實測 `https://chill.deals/products/<handle>` → 302 到 `/password`：
> This store is password protected. Use the password to enter the store.

🔴 **Online Store 的密碼保護獨立於 status／publication／catalog，且優先於它們**——
本尊連「直連分享」都不給。我方模型沒有這一層。
⚠️ 本輪**刻意不移除密碼**（那會讓一個真實網域對外公開，性質與改測試資料不同）
⇒ 「Unlisted 直連是否真的可購買／是否真有 `noindex`」**仍為未取得**。

#### §9.6a 設定位置與**同一區的第五道閘門**

`Online Store › Preferences › Store access`（Online Store 管道是**跨域 iframe app**
`online-store-web.shopifyapps.com`，JS 讀不進去——工具限制照鐵律 14.3 登記，本節靠截圖取證）：

| 控件 | 形態 / 上限 | 說明文字（逐字） |
|---|---|---|
| **Password protection** | toggle（本店**呈停用態**） | `Restrict access to visitors with the password` |
| （橫幅） | 資訊條 | **`Your online store is in development. To let visitors access your store, give them the password.`** |
| Password | 文字，**6 of 100 characters used** | — |
| Message to your visitors | textarea，**0 of 5,000 characters used** | — |
| 🔴 **Restrict access to B2B customers only** | toggle | `B2B customers will need to log in and verify their account to access your store.` ＋ `Manage companies` |

🔴 **兩條新結論**：
1. **店鋪處於「development」狀態時，密碼保護是被強制的**（toggle 停用）
   ⇒ 「店鋪生命週期狀態」本身也參與可見性判定。
2. **`Restrict access to B2B customers only` 是第五道閘門**——整店層級、與商品無關，
   但會讓所有商品對非 B2B 訪客不可見。

⇒ 合計本尊的可見性閘門至少五層，我方模型只做了其中兩層：

| # | 閘門 | 層級 | 我方 |
|---|---|---|---|
| 1 | 店鋪 development／密碼保護 | 店 | ❌ 無 |
| 2 | B2B-only 限制 | 店 | ❌ 無 |
| 3 | 商品 `status`（含平台施加的 `Suspended`） | 商品 | ✅ 有（`Suspended` 缺） |
| 4 | Publication（商品層 ∧ 變體層） | 商品／變體 | ✅ **本包做的就是這一層** |
| 5 | Catalog（含 Included／Excluded 三值成員） | 商品／變體 | ❌ 延後（88 §3.2） |

（第 1、2 層屬 Online Store 前台包＝第 30／33 包；第 5 層屬 M5。）

### §9.7 🔴 存在**商家不能設定**的 publication——狀態是審核結果

商品 modal 的 `Agentic` 組不是 toggle，是**唯讀狀態標籤**。
同一個商品**只改 status**，顯示就變：

| 商品 status | `Agentic › Shopify Catalog` 顯示 |
|---|---|
| `Unlisted` | `Learn more about Shopify Catalog requirements` ｜ 狀態 **`Unpublished`** |
| `Active` | **`Your product is being reviewed for Shopify Catalog eligibility. This can take a few days.`** ｜ 狀態 **`Pending`** |

🔴 ⇒ 至少三態（`Unpublished`／`Pending`／推測有 `Published`），由**商品狀態 ＋ 資格審核**推導。
對應官方的 `ResourceFeedback` 與 sales-channel app 的 product publishing 回報機制。

**我方模型只有一個 `published_at` 時間戳**，沒有：
①商家不可設定的 publication ②pending／審核中狀態 ③per-resource 的資格／回饋原因。

### §9.8 🔴 `Suspended`：官方 enum 之外的第五個狀態值

系列頁 `Collection items` 的 `Status` 篩選器逐項展開：

| 值 | 預設勾選 |
|---|---|
| Active | ☑ |
| Draft | ☑ |
| Unlisted | ☑ |
| **Archived** | ☐ |
| **Suspended** | ☑ |

🔴 `Suspended` **不在官方 `ProductStatus` enum**（官方恰四值）。
它**預設勾選**（與 Archived 相反）⇒ 判斷是**平台施加的狀態**（違規／審核凍結類），
與 §9.7 的 `Pending` 同族。⚠️ **確切語義＝未取得**。

### §9.9 `autoPublish` 的商家入口——第一輪未取得的收斂

`Settings › Sales channels` 三個已安裝管道（`Online Store｜Point of Sale｜Shop`），
`⋯` 選單值域三項：`Open app｜View details｜Uninstall`。
`View details` 是 app 安裝詳情面板（說明／Billing／權限 scope／Privacy／Recent activity），
**沒有任何發布設定**。

🔴 **在上述已查介面中未找到**「每個管道一個自動發布新商品」的商家開關
（依鐵律 12.1 不寫「本尊沒有這個設定」）。
商家層級的等價控件**只存在於 catalog**：`Automatically include new products in this catalog`（預設開）。

🔴 另一條：**`Agentic` 不在 `Settings › Sales channels` 的已安裝清單**，
但它出現在側欄與發布 modal ⇒ **「已安裝管道」與「可發布目標」不是同一個集合**。

### §9.10 系列（Collection）面的差異

- 列表欄位：`Title｜Products｜Conditions｜Sales channels`
  🔴 **命名不一致**：商品列表那一欄叫 `Channels`，系列列表叫 `Sales channels`
- 既有 `Home page` 系列：**Sales channels = 1**（只有 Online Store，POS 與 Shop 皆 OFF），
  而新建系列表單存檔前顯示 **`3 channels`** ⇒ **既有系列不會被追加到新管道**
- 頁首：`Duplicate｜View｜More actions`（商品頁是 `Preview｜Share`）⇒ 分享語義不同
- 右欄 Sources：`Products ˅` ＋ `Add condition`（帶規則數徽章）＋ `Exclude` ＋ `+`
  ⇒ 與我方第 11 包實作的 sources／rules 模型同構

### §9.11 本輪在測試店留下的東西

| 物件 | GID | 狀態 |
|---|---|---|
| catalog | `MarketCatalog/103379370219`「P12 第三層實測 catalog」 | 綁 United States 市場，Active |
| ↑ 的 price list | `PriceList/21058420971` | HKD，0% |
| ↑ 的 publication | `Publication/214892183787` | autoPublish=true |
| 商品 | `Product/9911273160939`「P12 發布模型實測用商品」 | 本輪由 Unlisted 改回 **Active**；商品層 2 管道 |
| 變體 | `Product/9907126370539` 的變體 S | Point of Sale 關閉 |

### §9.12 本輪**未取得**清單

- **`Suspended` 的確切語義**（官方 enum 沒有它）
- **bundle 在發布上的特殊規則**（`includesBundle` 參數的來源）
- **`Unlisted` 的前台實際行為**（受密碼保護阻擋，刻意不移除密碼）
- **`Agentic › Shopify Catalog` 的第三態**是否為 `Published`，以及審核的實際條件
- **`catalogPublicationCount=1` 與列表 `Catalogs=0` 的矛盾**
- **「Automatically include new products」與 `defaultState` 的確切關係**
  （送出的是 `EMPTY`，最終卻納入了商品）
- **新增 publication 時是否回填既有商品**（§8.7 那條仍未取得；本輪建的是 catalog 不是管道）

---

## §10 🔴 S0 地基：管道的身分模型（2026-08-26 實測）

> 分步方案 `docs/plans/2026-08-26-發布與可見性-分步執行方案.md` 的 **S0**。
> 核心問題：本尊的「銷售管道」到底是什麼實體？我方把它壓成 `publications.channel_handle`
> 一個字串欄，代價是什麼？
>
> 🔴 **本節全部是零代價、零風險的純讀取實測**（X-1／X-6）：沒有安裝任何 app、
> 沒有改任何管道設定。使用者 2026-08-26 裁定**不安裝新管道**，故
> 「新增管道後既有商品是否立刻可見」維持**未取得**（§9.12 那條不變）。

### §10.1 「管道」在後台是**三個不同的集合**

| 集合 | 內容（實測） | 頁面 |
|---|---|---|
| **A. 已安裝管道** | Online Store ｜ Point of Sale ｜ **Shop** | `Settings › Sales channels`（`tab=installed`） |
| **B. 側欄可導航** | Online Store（→`/themes`）｜ **Agentic**（→`/apps/agentic`）｜ Point of Sale | 側欄 `Sales channels ›` |
| **C. 可發布目標** | `Sales Channels` 組三個 ＋ **`Agentic` 獨立一組** ＋ `Catalogs` 動態組 | 商品的 Manage publishing modal（§9.3） |

🔴 **三者兩兩不同**：Shop 在 A、C 不在 B；Agentic 在 B、C 不在 A。
⇒ 我方一張 `publications` ＋ 一個 `channel_handle` **表達不了這三種成員關係**。

### §10.2 🔴 `Settings › Apps` 與 `Settings › Sales channels` 是兩個**不相交**的清單

| 頁 | 內容（實測） |
|---|---|
| `Settings › Apps`（`Installed`） | Translate & Adapt｜Messaging｜DealerSend Logistics Limited｜ShipAny｜Fecify |
| `Settings › Sales channels`（`Installed` ＋ `More views`） | Online Store｜Point of Sale｜Shop |

三個管道**完全不出現在 Apps 清單**，五個 app 也不出現在 Sales channels；
但兩頁的 `⋯` 選單、`View details` 面板、頁首 `Shopify App Store` 按鈕**完全相同**。

⇒ 這是 **R13-V2 裁定**（§7 第 2 條：「應是 `App` 之下的 `Channel`（帶 channel capability），
不是兩張平行表」）的直接證據：**本尊是同一個 `App` 實體，依有無管道能力分成兩個檢視**。

`⋯` 選單**逐管道不同**（由 app 能力決定，不是固定清單）：

| 管道 | 選單項 |
|---|---|
| Online Store | `Open app`／`View details`／`Uninstall`（3 項） |
| Point of Sale | `Open app`／`View details`／**`Get support`**／`Uninstall`（4 項） |

`View details` 面板結構：識別（`by Shopify`／`Installed July 14`）／
**Activity and permissions**（表頭 `Area｜View｜Edit｜Recent activity`）／
**Privacy**（Customers → Sensitive data：Name／Email／Phone／Physical address；
Device and activity data：Geolocation／IP／Browser and operating system）／Billing。
頁首按鈕：`Get support`｜**`Uninstall app`**（紅）｜`Open app`。

### §10.3 🔴 完整身分鏈——一個 payload 抓齊四層

`AdminProductDetailsCatalogs`（開商品 Publishing modal 時觸發）的 response，
剝掉內嵌 SVG 後的結構（逐字節錄，脫敏保留 GID）：

```
Publication/209681744107   name:"Shop"
  ├─ supportsFuturePublishing: true
  ├─ supportsBundles: true
  ├─ supportsCombinedListings: true
  ├─ supportsVariantFixedBundles: true
  ├─ supportsSubscriptions: true
  ├─ supportsPublicationForUnlistedProducts: true
  ├─ operation: null
  ├─ publishablesStatusSummary: { status:"PUBLISHED",
  │                               includedIds:[ProductVariant/49295964176619,
  │                                            ProductVariant/49295964209387] }
  └─ catalog: AppCatalog/99441377515
       ├─ title:  "Channel Catalog 209681744107 for Shop"
       ├─ status: "ACTIVE"
       ├─ apps.nodes[0]: App/3890849  title:"Shop"
       │     ├─ installation: AppInstallation/725054128363
       │     │      └─ navigationItem: { iconBody:<SVG>, __typename:"NavigationItemV2" }
       │     └─ feedback: null
       └─ channels.edges[0].node: Channel/209681744107
              ├─ handle: "shop-72"
              └─ resourceFeedback: null
```

🔴 **五條結構性結論**：

1. **`Publication → AppCatalog → App → AppInstallation` 四層是真的**，
   而且 `AppCatalog.channels` 還掛著 `Channel`。R13-V2 的模型描述被實測證實。
2. 🔴 **`Channel` 的數字 id 與 `Publication` 相同**（都是 `209681744107`）
   ⇒ 第一方管道上兩者**共用 id**。這是 `Publication : Channel = 1 : N`
   （官方 SDL）在實務上退化成 1:1 的直接證據。
3. 🔴 **channel handle 帶後綴**：`shop-72` 而不是乾淨的 `shop`
   ⇒ handle 是**每店唯一**的產生值，不是全域常數。
   ⚠️ 我方 `Publication.online_store` 用 `find_by(channel_handle: "online_store")`
   ——那是把一個**每店產生的值**當成全域常數在比對。
4. **catalog title 的格式**是 `Channel Catalog {publicationId} for {ChannelName}`
   （§9.5b 已抓到 Online Store 版，本節再取得 Shop 版，兩者同格式）。
5. **`ResourceFeedback` 有兩個掛載點**：`App.feedback` 與 `Channel.resourceFeedback`
   （本店皆 null）。我方 `resource_publications` 完全沒有 feedback 維度。

### §10.4 🔴 Publication 有**六個能力旗標**，我方只有一個

| 旗標 | 本店實測值 | 我方 |
|---|---|---|
| `supportsFuturePublishing` | true | ✅ 有 |
| **`supportsBundles`** | true | ❌ |
| **`supportsCombinedListings`** | true | ❌ |
| **`supportsVariantFixedBundles`** | true | ❌ |
| **`supportsSubscriptions`** | true | ❌ |
| **`supportsPublicationForUnlistedProducts`** | true | ❌ |

🔴 **`supportsBundles` 解釋了 §9.4 那個一直未取得的 `includesBundle=false` URL 參數**
——批量發布對話框要先知道「這批商品含不含 bundle」，因為**不是每個管道都支援 bundle**。

🔴 **`supportsPublicationForUnlistedProducts` 解釋了 help 那句**
「You can't publish unlisted products to any third-party sales channels」
——它不是一條寫死的規則，是**逐管道的能力旗標**。

另兩個非旗標欄位：
- **`operation`**（本店 null）＝ §9.5d 實測到的「進行中的非同步操作」
- **`publishablesStatusSummary { status, includedIds }`** ＝ 一個**變體粒度**的狀態摘要物件

### §10.5 🔴 Agentic：獨立型別 ＋ 商品層專屬布林

同一個 payload 的 `agenticChannels`（逐字）：

```json
[{"handle":"oai","__typename":"AgenticChannel"},
 {"handle":"copilot","__typename":"AgenticChannel"},
 {"handle":"shop_agentic","__typename":"AgenticChannel"}]
```

🔴 **`AgenticChannel` 是與 `Channel` 不同的 GraphQL 型別**，三個 handle：
`oai`（ChatGPT）／`copilot`（Microsoft Copilot）／`shop_agentic`（Shop）。
⚠️ UI 上顯示四項（多一個 `Other channels`）而這裡只有三個 ⇒ 第四項的來源**未取得**。

🔴 同一個 payload 的 **`product.agenticCatalogDiscoverable: false`**
——**商品層有一個專屬布林**管 agentic 可發現性。
這正是 §9.7 實測到的「Agentic 組是唯讀狀態標籤、狀態隨 status 從 `Unpublished` 變 `Pending`」
背後的欄位。它**不是** publication 列，是商品自己的一個欄。

`/apps/agentic` 頁全文（逐字）：

> **Agentic Storefronts aren't live — but your products may still be surfacing in AI agents.**
> **Get ready for Agentic Storefronts**
> ・Make sure catalog access is enabled — `Completed` — Allow your products to be searchable by AI agents
> ・Update policies — `Not started` — Update your policies so AI agents can read them ／ `Review`
>
> **Allow Shopify to manage for me**［toggle，開］
> ・ChatGPT ｜ Microsoft Copilot ｜ Other channels ｜ Shop —— 各自 `Channel details, Status: Inactive`
>
> **Sources** — Used by AI agents to recommend your products
> ・**Shopify Catalog** — `0 products in Catalog`
> ・**Shopify Knowledge Base** — `Install`

⇒ **「管道」與「資料來源（Source）」是兩種東西**，而發布 modal 把 Shopify Catalog
放在 `Agentic` 組裡當成一個發布目標。存在**委託式發布管理**（Allow Shopify to manage for me）。

### §10.6 App Store 的管道定價（回答「安裝要不要錢」）

實測 `apps.shopify.com/categories/sales-channels`：

| 管道 | 定價標示（逐字） | 開發者 | 要外部帳號 |
|---|---|---|---|
| Buy Button channel | **`Free`** | Shopify | ❌ |
| Shop | `Free` | Shopify | 已安裝 |
| Google & YouTube | **`Free to install. Additional charges may apply.`** | Google LLC | ✅ |
| Facebook & Instagram ／ TikTok ／ Faire | `Free to install` | 第三方 | ✅ |

🔴 **`Free to install` ≠ 不收費**。
🔴 **使用者 2026-08-26 裁定不安裝**（明示不用 Buy Button）⇒ §9.12 的兩條未取得維持。

### §10.7 其他形態

- `Settings` 子導覽完整清單：`Organization｜Users｜General｜Plan｜Billing｜Payments｜Checkout｜
  Customer accounts｜Shipping and delivery｜Taxes and duties｜Locations｜Apps｜Sales channels｜
  Domains｜Customer events｜Notifications｜Metafields and metaobjects｜Languages｜
  Customer privacy｜Policies`
- **Online Store 的完整子導覽**（來自鍵盤快捷鍵面板，比側欄多）：
  `Overview / Blog posts / Pages / Themes / Navigation / Domains` ⇒ 側欄是**縮減後的集合**
- POS 管道頁：頁首 `Manage locations｜Manage staff｜⋯`；側欄子項
  `Staff｜Devices｜Register sessions｜Settings`
- 建了 catalog 之後，商品的 **Publishing 卡多出第二行 `All catalogs`**
  ⇒ 該卡也是動態的（與 §9.3 的 modal 左側導覽同構）

### §10.8 S0 尚未取得

- 安裝新管道後既有商品是否立刻可見（使用者裁定不安裝）
- 卸載管道後 publication 與發布列的去向（官方沉默 ＋ 無法實測）
- Agentic UI 第四項 `Other channels` 對應哪個實體
- `Publication : Channel` 在**多帳號連線**管道上是否真的 1:N（需要多連線管道才測得到）
- `Shop` 管道的 `⋯` 選單（兩次誤點導航走，待補）

---

## §11 🔴 S1 地基：Publication 的生命週期與非同步模型（2026-08-26 實測）

> 射程＝分步方案的 **S1**。測試店 `chill-love-u5q5mnzq`（鐵律 12.2 全權寫入授權）。
> 本節每一條都附鐵律 14.4 的證據五件套（URL 去 token／method／觸發步驟／形狀節錄／取證日期）。
> 🔴 本尊 admin 走 persisted-query API ⇒ **query 全文不可觀測**（鐵律 14.3）：
> 只記 operation name ＋ GET 的 variables ＋ 可觀察的副作用；POST 的 variables 在 body 內，
> 本工具讀不到，逐條標「不可觀測」。

### §11.1 `Settings › Sales channels` 與 app installation 詳情頁

**觸發步驟**：Settings（`/settings/apps`）→ 左欄 `Sales channels` → 清單列的 `⋯` → `View details`。
🔴 路徑一律點真實連結取得，未猜 URL（鐵律 12.1）。

- 清單恰三列：`Point of Sale`／`Online Store`／`Shop`（與 §0.1 一致）。
- 每列 `⋯` 選單**恰三項**：`Open app`／`View details`／`Uninstall`（第三項紅色）。
  🔴 這證實 **R13-V2** 的觀察：管道與 app 的選單完全相同 ⇒ 管道就是一種 app。
  ⚠️ **`Uninstall` 未點**——破壞性且會毀掉測試店的管道設定，不在授權的「假資料」射程內。

**詳情頁 URL**（method GET，取證 2026-08-26）：

```
/store/chill-love-u5q5mnzq/settings/sales_channels/app_installations/app/online_store
```

🔴 **路徑逐字含 `app_installations/app/<handle>`** ⇒ 本尊**用 handle 定址一個 app 的安裝**。
這是我方 `platform_apps`（自然主鍵 `handle`）＋ `app_installations` 形狀的**直接實測支持**
（S0 PR B，migration `20260826070000`）。

**頁面分區**（由上而下，逐區逐字）：

| # | 區塊 | 內容（逐字節錄） |
|---|---|---|
| 1 | 頁首 | app 名 ＋ `by Shopify`；右側兩鈕 `Uninstall app`（外框）／`Open app`（實心） |
| 2 | app 卡 | icon ＋ 名稱 ＋ 🔴 `Installed July 14` ＋ 描述 |
| 3 | `Channel connections` | 副標 `View and manage your connections on Online Store`；一列 `Online Store` ＋ 綠色徽章 `Active` |
| 4 | `Billing` | `No plan selected` ＋ 右上 `⋯` |
| 5 | `Activity and permissions` | 逐字：`Apps made by Shopify are trusted to work securely with your store data. These apps are closely linked to Shopify features, so their activity cannot currently be tracked like third-party apps.`（原文用 can’t） |
| 6 | `Privacy` | 副標 `This app can access personal data in your store`；可展開 `Customers`（`Sensitive data`＝Name／Email address／Phone number／Physical address；`Device and activity data`＝Geolocation）＋ 逐字 `Shopify has confirmed this app meets data handling and privacy requirements`；另一可展開 `Staff and contributors` |
| 7 | `App history` | 時間軸：日期分組 `July 14` ＋ 條目 `App installed by KEN LEE` ＋ 時間 `9:40 PM` |
| 8 | 頁尾 | 右下紅色 `Uninstall app` |

🔴 **兩條與我方 S0 設計直接相關的更正**：

1. **`Installed July 14` ⇒ 本尊有安裝時間，只是公開 GraphQL 沒曝露。**
   官方 `AppInstallation` 型別確實**沒有任何時間戳欄位**
   （<https://shopify.dev/docs/api/admin-graphql/latest/objects/AppInstallation>，取證 2026-08-26），
   但 admin UI 顯示得出來 ⇒ **平台有存，只是不在公開 API 面上**。
   ⚠️ 我方 `app_installations.installed_at` 先前登記為「純 ours、本尊沒有」——
   **該說法過窄**，正確表述是「官方公開 GraphQL 未曝露；admin UI 證實平台有存」。
   （更正落點：`app/models/app_installation.rb` 檔頭、`docs/DECISIONS.md` D52。）
2. **`App history` 是帶操作者的事件時間軸**，不是一個布林狀態。
   ⇒ 我方 S0 PR B 登記的 **S0B-3「不留安裝歷史」是真的缺口**，不是假設。
   本尊至少記錄「事件類型 ＋ 時間 ＋ 操作者（staff member）」。

**仍未取得**：`Channel connections` 的 `Active` 徽章來源。官方 `Channel` 型別**沒有 `status` 欄**
（<https://shopify.dev/docs/api/admin-graphql/latest/objects/Channel>，取證 2026-08-26），
故該徽章可能來自 installation、可能來自 connection 概念。取得方式＝抓該頁的 persisted query 回應
（本次未取得：該頁只捕到 `ManagedPricingPlans` 一支 GraphQL 請求）。

### §11.2 🔴 批次發布是**非同步**的，回一個 `Job` 給 admin 輪詢

**觸發步驟**：`/products` → 勾選 2 個商品 → 批次列 `⋯` → `Include in sales channels`
→ 勾 `Shop` → `Include products`。

**操作序列**（method 如標，取證 2026-08-26）：

| # | operation name | method | 可觀測的 variables |
|---|---|---|---|
| 1 | `SalesChannelsBulkModal` | GET | `{"isProduct":true,"limit":250}` |
| 2 | **`ProductBulkPublish`** | POST | **不可觀測**（persisted query，變數在 body） |
| 3 | `ContextPickerQuery` | GET | `{"channelCount":100,"companiesCount":10,"catalogChannelFirst":1,"locationsCount":10,"shouldFetchCountries":true,"shouldFetchCatalogs":true,"shouldFetchCompanies":true,"shouldFetchRetail":true,…}` |
| 4 | 🔴 **`JobPoller`** | GET | `{"id":"gid://shopify/Job/98e987b4-b3a2-4a13-9fee-c59eccf98034"}` |
| 5 | `ProductIndex` | GET | 見 §11.6 |

**反向操作**（`Exclude from sales channels` → 勾 `Shop` → `Exclude products`）序列對稱：
`ProductBulkUnpublish`（POST）→ `ContextPickerQuery` → `JobPoller`
（**新的** Job id `gid://shopify/Job/e52a7dff-77b4-47b4-9647-30fcd2bfaed8`）→ `ProductIndex`。

🔴 **四條結論**：

1. **批次發布／取消發布都是非同步的**，即使只有 2 個商品。
2. **非同步的載體是 `Job`**（官方 `Job` 型別恰三欄：`done: Boolean!`／`id: ID!`／`query: QueryRoot`，
   逐字 `A job corresponds to some long running task that the client should poll for status.`
   ——<https://shopify.dev/docs/api/admin-graphql/latest/objects/Job>，取證 2026-08-26）。
3. 🔴 **`Job` 的 id 是 UUID 不是數字**（`gid://shopify/Job/98e987b4-…`），與本尊其他 GID 全部用數字 id 相反。
   官方文檔**沒有**說明它是 UUID（未取得），這是實測形態。
4. 🔴 **這與 `Publication.operation`（`ResourceOperation`）是兩個不同的機制**，見 §11.3。

### §11.3 🔴 三種非同步／發布路徑，不得混為一談

| 路徑 | 形態 | 回傳 | 證據 |
|---|---|---|---|
| **公開 API `publishablePublish`** | **同步**、**逐資源**（`id: ID!` 單一資源）、input 是 `[PublicationInput!]!` | `publishable`／`shop`／`userErrors`，**不回 Job** | <https://shopify.dev/docs/api/admin-graphql/latest/mutations/publishablePublish>，取證 2026-08-26 |
| **admin 內部 `ProductBulkPublish`／`ProductBulkUnpublish`** | **非同步**、**批次多資源** | **`Job` GID**，由 `JobPoller` 輪詢 | §11.2 實測 |
| **`Publication.operation`（`ResourceOperation`）** | publication **整體**層級的操作（`AddAllProductsOperation` 等） | `ResourceOperationStatus` 恰三值、**無失敗態** | §9.5d 實測訊息 ＋ 官方 SDL |

⚠️ **`Publication.operation` 本輪未能實地觸發**：它的 admin 觸發點是「把**全部**商品加入一個管道」，
而那是安裝管道時的流程（使用者裁定不安裝）。已有證據僅 §9.5d 的鎖定訊息逐字
`Publishing for this catalog cannot be changed while updates are in progress.`（原文用 can’t）
取得方式＝安裝一個管道 app，或找到 catalog 的 add-all-products 入口。

另有一條官方逐字，同時是 S2 的輸入：
`publishablePublish` 的 `PublicationInput.publishDate` 說明中寫
`Only online store channels support scheduled publishing`
——這正是 `supportsFuturePublishing` 旗標的語義來源。

### §11.4 商品批次 `⋯` 選單的完整值域（鐵律 12.2 值域窮舉）

**觸發步驟**：`/products` → 勾選 ≥1 個商品 → 批次列的 `⋯`。批次列本身是
`[N selected ▾] [Bulk edit] [Set as draft] [⋯]` ＋ 右側 `Show all selected` 開關。

選單**恰 11 項**，分 6 組（組間有分隔線），逐字：

| 組 | 項目 |
|---|---|
| 1 | `Archive products`／`Unlist products`／`Delete products`（紅色） |
| 2 | `Include in sales channels`／`Exclude from sales channels` |
| 3 | `Include in catalogs`／`Exclude from catalogs` |
| 4 | `Add tags`／`Remove tags` |
| 5 | `Add to collection(s)`／`Remove from collection(s)` |
| 6 | 區塊標題 `Apps` ＋ `Create email campaign` |

🔴 **三條語義結論**：

1. **UI 用詞是 `Include in` / `Exclude from`，不是 publish/unpublish**——
   但 **URL 的動詞仍是 publish/unpublish**：
   `/products/sales-channels/publish?…` 與 `/products/sales-channels/unpublish?…`。
   ⇒ 我方 admin 的**文案**應對齊「加入／移除」，**API 命名**仍走 publish 語義（鐵律 4 的 `resourceVerb`）。
2. **sales channels 與 catalogs 是兩組獨立操作**（第 2 組與第 3 組），
   再次證實 `docs/specs/88` §1 的三層 AND 中第二層與第三層彼此獨立。
3. 🔴 **`Archived` 不在這個選單裡當狀態選項，`Archive products` 是一個動作**——
   與 §8.5 記過的「商品 Status 下拉沒有 Archived」同一件事的批次面對應。

### §11.5 🔴 發布 modal 的形態：**累加／扣除**，不是狀態編輯器

**URL**（GET，取證 2026-08-26）：

```
/products/sales-channels/publish?includesBundle=false&selectedProductIds=<id1>,<id2>
/products/sales-channels/unpublish?includesBundle=false&selectedProductIds=<id1>,<id2>
```

🔴 **`includesBundle=false` 這個參數解掉了 §9.4 登記的未取得**：發布 modal 需要知道
「這批選取的內容含不含組合商品」，因為**管道有 `supportsBundles` 能力旗標**
（我方已於 S0 PR A 的 `20260826062000` 補上該旗標）。⇒ 那個旗標的**用途**至此有實測支持。

**modal 內容**：標題 `Include 2 products in sales channels`／`Exclude 2 products from sales channels`；
一個 `Search` 輸入框；一個群組列 `Sales channel`（帶自己的全選 checkbox）；
三列管道各帶 checkbox（`Online Store`／`Point of Sale`／`Shop`）；
頁尾 `Cancel` ＋ `Include products`／`Exclude products`（未選任何管道時**禁用**）。
勾選後群組列變成 `N selected ▾` ＋ `Show all selected` 開關。

🔴 **兩個 modal 的 checkbox 一律以「全部未勾」開場，即使選取的商品已經在某些管道上**
（實測：兩個商品的 `Channels` 欄都是 1，modal 仍全空）。
⇒ 這是 **`publishablesToAdd` / `publishablesToRemove` 的累加／扣除語義**，
**不是**「把目前狀態讀出來讓你編輯」。我方實作**不得**做成狀態編輯器，否則
「取消勾選」會被誤解成「移除」，而本尊的取消勾選只是「這次不動它」。

**實測副作用**（可複驗）：Include→Shop 之後兩個商品的 `Channels` 欄 1→2；
Exclude→Shop 之後回到 1。兩個 fixture 商品（`P12 發布模型實測用商品`＝2、
`實測用 T恤 多變體（測試資料）`＝3）**全程未受影響**，測試店狀態已還原。

### §11.6 `ProductIndex` 變數揭露的四種 catalog（S10 的輸入）

`ProductIndex`（GET）的 variables 逐字含：

```
"shouldQueryRegionCatalogs":true, "shouldQueryRetailCatalogs":true,
"shouldQueryB2BCatalogs":true,   "shouldQueryChannelMarketCatalogs":true,
"productsFirst":50, "contextualPublicationContext":{}
```

🔴 **admin 區分四種 catalog：Region／Retail／B2B／ChannelMarket**，
而官方 `CatalogType` enum 只有三值（`APP`／`MARKET`／`COMPANY_LOCATION`，另有讀取態 `NONE`）。
⇒ 兩者**不是同一層**：enum 是資料模型的種類，這四個是 admin 的查詢維度。
S10 做 catalog 成員語義時必須先解掉這個對應關係（**未取得**）。

另：`"productsFirst":50` 是商品列表的頁大小；`SalesChannelsBulkModal` 的 `"limit":250`
與我方鐵律 4 的「分頁 ≤250」上限一致。

### §11.7 S1 尚未取得

| # | 未取得 | 取得方式 |
|---|---|---|
| S1-U1 | `ProductBulkPublish`／`ProductBulkUnpublish` 的 variables 與回應形狀 | persisted query ＋ POST body，本工具不可觀測（鐵律 14.3）。需要能讀 request body 的抓包工具 |
| S1-U2 | `Publication.operation` 的實地形態（進行中的鎖、進度數字） | 需安裝一個管道 app（使用者裁定不安裝），或找到 catalog 的 add-all-products 入口 |
| S1-U3 | `Channel connections` 的 `Active` 徽章由哪個欄位驅動 | 官方 `Channel` 無 `status` 欄；需抓該頁 persisted query 的回應 |
| S1-U4 | 卸載管道後 publication 與發布列的去向 | 官方沉默 ＋ 不可實測（破壞性） |
| S1-U5 | `Job` 的 id 為何是 UUID、以及 `Job` 與 `ResourceOperation` 的關係 | 官方文檔對兩者的關係完全沉默 |
| S1-U6 | admin 四種 catalog 查詢維度與官方 `CatalogType` 三值 enum 的對應 | 需 catalog 相關頁面的抓包（屬 S10） |

---

## §12 🔴 S2 地基：逐商品發布 modal 與排程發布（2026-08-26 實測）

> 射程＝分步方案的 **S2**（`resource_publications` 的完整語義）。
> 測試店 `chill-love-u5q5mnzq`（鐵律 12.2 全權寫入授權）。
> 🔴 本節全程**沒有變更任何資料**：所有 toggle 動作都在同一個 modal 內還原，
> 最後以 `Cancel` 關閉（`Done` 全程 disabled ＝ 沒有待儲存的變更）。

### §12.1 `Manage publishing for <product>` — 逐商品的發布狀態編輯器

**觸發步驟**：商品詳情頁 → 捲到 `Publishing` 卡 → 點該卡**右上角的設定圖示**。
（⚠️ 視窗寬 1024 時 admin 收成單欄，`Publishing` 卡在 `Status` 卡下方、`Sales` 卡上方，
不在右側欄——鐵律 13 的形態記錄。）

**modal 結構**：標題 `Manage publishing for <商品標題>`；左欄導航 ＋ 右側內容 ＋ 頁尾 `Cancel`／`Done`。

左欄恰**三個可點項 ＋ 一個群組標題**（逐字）：

| 項目 | 徽章數 | 說明 |
|---|---|---|
| `Sales Channels` | 3 | 管道清單 |
| `Agentic` | 1 | 代理式（見 §12.3） |
| **`Catalogs`**（群組標題，不可點） | — | |
| `Regions` | 1 | catalog 成員（見 §12.4） |

🔴 **`Catalogs` 是群組標題而 `Regions` 是它底下的項目** ⇒ admin 把 catalog 依種類分節，
與 `ProductIndex` 變數揭露的四種 catalog（Region／Retail／B2B／ChannelMarket，§11.6）
同一套分類。本店只有 Region 一種 ⇒ 只顯示一項。

### §12.2 🔴 逐商品 modal **顯示目前狀態**——與批次 modal 語義相反

`Sales Channels` 節內容：`Search channels` 輸入框、群組列 `Sales Channels`（帶自己的 toggle）、
三列管道各帶 toggle：

| 管道 | 實測狀態 |
|---|---|
| `Online Store` | **開** |
| `Point of Sale` | 關 |
| `Shop` | 關 |

群組列的 toggle 呈**半選態**（橫線而非勾／叉），因為三個管道只有一個開著。

🔴 **這與 §11.5 的批次 modal 直接對比，是 S2 最重要的一條**：

| | 批次 modal（`/products/sales-channels/publish`） | 逐商品 modal（本節） |
|---|---|---|
| 開場狀態 | **一律全部未勾**，即使商品已在某些管道上 | **顯示目前狀態**（Online Store 開著） |
| 語義 | **累加／扣除**（`publishablesToAdd`／`ToRemove`） | **狀態編輯器**（勾掉＝取消發布） |
| 群組列 | 全選 checkbox | **半選態** toggle |

⇒ **同一件事在本尊有兩種語義的入口**，我方實作**不得**把兩者做成同一個元件。
把逐商品 modal 做成累加語義 ⇒ 商家取消勾選不會生效；
把批次 modal 做成狀態編輯器 ⇒ 商家的一次勾選會清空整個管道。

### §12.3 🔴 排程發布只掛在 **Online Store** 一個管道上

**觸發步驟**：在 `Sales Channels` 節把游標移到 `Online Store` 那一列
→ 列上出現一個**日曆＋時鐘**圖示（tooltip 逐字 **`Schedule publishing`**）→ 點它。

🔴 **對 `Point of Sale` 與 `Shop` 兩列做同樣的 hover，都不會出現該圖示**。
⇒ 排程能力是**逐管道**的，實測與官方那句
`Only online store channels support scheduled publishing` 一致，
也與我方 `publications.supports_future_publishing` 旗標對位。

**`Schedule publishing` 彈層的完整內容**（由上而下）：

| # | 元件 | 實測值／形態 |
|---|---|---|
| 1 | 標題 | `Schedule publishing` |
| 2 | 日期欄（日曆 icon） | `August 26, 2026` |
| 3 | 時間欄（時鐘 icon） | `10:35 PM`，右側**內嵌時區徽章 `GMT+8`** |
| 4 | 月曆 | `‹ August 2026 ›` ＋ Sun–Sat 表頭；🔴 **當日之前的日期全部灰掉不可選** |
| 5 | 頁尾 | `Remove schedule`（本例 disabled——尚未設排程）／`Cancel`／`Done`（未改動時 disabled） |

🔴 **四條規則性結論**：

1. **排程的粒度是 (publishable × publication)**，不是 publishable 層——圖示掛在管道列上。
2. **不能排程到過去**：月曆把當日之前的日期全部禁用。
   ⚠️ 這是 **UI 層**的限制；API 層是否同樣拒絕過去時間＝**未取得**。
3. **`Remove schedule` 是一等操作**，不是「把日期清空」——取消排程有專屬入口。
4. **時區內嵌顯示（`GMT+8`）**，且 help 明文要求商家先確認它：
   `Verify that the date and time in the Store defaults section of your General settings page
   is set to your time zone so that your products publish at the correct time.`
   （<https://help.shopify.com/en/manual/shopify-admin/productivity-tools/future-publishing>，取證 2026-08-26）
   ⇒ **時區來源＝店鋪設定的 Store defaults**，不是使用者層、不是瀏覽器。

**同頁 help 的射程句逐字**（同上 URL）：

> Future publishing allows you to hide parts of your online store until a specific date and time.
> You can set up future publishing for products, collections, blog posts, and pages.
> Your online store publishes the content at the dates and times that you specify.

⇒ 適用資源恰四類（products／collections／blog posts／pages）。
⚠️ **變體不在內**——與我方 `ResourcePublication#variant_cannot_be_scheduled` 既有 validation 一致。

### §12.4 Agentic 是**唯讀的資格審核態**，不是發布開關

`Agentic` 節恰一列：

- 標題 `Shopify Catalog`
- 副標逐字：`Your product is being reviewed for Shopify Catalog eligibility. This can take a few days.`
- 右側徽章 **`Pending`**（藍色）
- 🔴 **沒有 toggle**

⇒ 代理式管道在商品層是**平台審核出來的狀態**，商家不能自己開關。
這解掉 §10.5 登記的一部分未取得：Agentic 在**商品層**的形態是
「eligibility ＋ 狀態徽章」，不是 publication toggle。
⚠️ 該徽章的**完整值域**（Pending 之外還有哪些）＝**未取得**——本店只有這一個狀態可觀察。

### §12.5 Catalog 成員是逐商品 toggle，`Status` 篩選恰三值

`Regions` 節內容：`Search catalogs` 輸入框、**`Status ⌄` 篩選**、群組列 `Catalogs`（toggle 開）、
一列 `P12 第三層實測 catalog`／副標 `Region`／toggle **開**。

`Status` 下拉展開後**恰三個 checkbox ＋ 一個動作**（逐字）：

| 值 |
|---|
| `Active` |
| `Draft` |
| `Archived` |
| `Clear`（清除篩選，未選時 disabled） |

🔴 **這更正了 S0 的一句話**：`app/models/sales_catalog.rb` 的 `STATUSES` 註釋原寫
「admin UI 只曝露 active／archived 兩個（`82` §9.5c 實測的表單沒有 draft）」。
正確表述是：**catalog 的建立表單**只給兩個，**篩選器三個都給**。
原句把「建立表單」的觀察寫成了「admin UI」的全稱，射程過寬。
（更正落點：`app/models/sales_catalog.rb` 的 `STATUSES` 註釋。）

🔴 **第三層是真的逐資源成員關係**：這一列 toggle 證實 catalog 不只是容器，
它有 (publishable × catalog) 的成員狀態 ⇒ `docs/specs/88` §1 的三層 AND
第三層在本尊是有實體的，我方目前恆真只是因為還沒有成員表（屬 S10）。

### §12.6 S2 尚未取得

| # | 未取得 | 取得方式 |
|---|---|---|
| S2-U1 | 設了排程之後 `Publishing` 卡與商品列表怎麼顯示（是否有「已排程」徽章、顯示哪個時間） | 在測試店真的設一次排程並觀察（本輪刻意不改資料；要做需先確認可完整還原） |
| S2-U2 | API 層是否也拒絕「過去的時間」，還是只有 UI 擋 | 直接呼叫 `publishablePublish` 帶過去的 `publishDate` 並抓 payload |
| S2-U3 | 排程到點的**實際生效機制**（背景任務翻狀態 vs 查詢時動態判定） | 官方沉默；需設一個近未來排程並觀察前台與 API 在到點前後的差異 |
| S2-U4 | 到點時商品若已不符條件（例如被改成 Draft）會怎樣 | 同上，且需在到點前改狀態 |
| S2-U5 | Agentic `Pending` 之外的完整狀態值域 | 需要一個已通過審核的商品 |
| S2-U6 | 排程是否可套用到 catalog 成員（`Regions` 節沒有日曆圖示，但未逐列 hover 窮舉） | 回該節逐列 hover |

---

## §13 🔴 S5 地基：逐商品發布的**寫入路徑**（2026-08-27 實測）

> 射程＝分步方案的 **S5**（寫入 API：publish／unpublish）。
> 測試店 `chill-love-u5q5mnzq`（鐵律 12.2 全權寫入授權）。
> 🔴 本節**真的改了資料再改回來**：把商品 `9907158778091` 發布到 Shop 管道、存檔、
> 再取消發布、存檔。最終 Publishing 卡回到只有 `Online Store`，與開始時相同。
> 🔴 admin 走 persisted-query API ⇒ **query 全文與 POST 的 variables 不可觀測**（鐵律 14.3）；
> 本節只記 operation name、persisted-query hash、GET 的 variables 與可觀察的副作用。

### §13.1 🔴 逐商品發布 modal 的 `Done` **不寫入任何東西**

**觸發步驟**：商品詳情頁 → `Publishing` 卡右上設定圖示 → 開 modal → 撥開 `Shop` 的 toggle
→ 按 `Done`。

**實測結果**：

- **沒有送出任何 `api/operations` 請求**（清空 network log 後只捕到 `monorail-edge`
  遙測與 `.well-known/dux` 兩類非 GraphQL 請求）
- `Publishing` 卡的內容**樂觀更新**成 `Online Store, Shop`
- 🔴 頁面頂端出現 **`Unsaved changes` SaveBar**（`Discard` ／ `Save`）

⇒ **逐商品發布是商品表單 dirty state 的一部分，不是即時寫入。**
真正的寫入發生在商家按頁面層級的 `Save`。

⚠️ **這與批次流程直接對比**（§11.2）：批次 modal 按下 `Include products` 就**立刻**
送 `ProductBulkPublish` 並回一個 `Job`。**同一件事，兩種交付時機。**

⚠️ 與我方 `docs/specs/71` §A **G30** 的裁定相關：G30 明文「商品頁庫存卡用卡內自己的儲存鈕，
不掛頁面 SaveBar」是**我方對本尊的刻意差異**。本節證實**發布這一塊本尊是掛 SaveBar 的**
——G30 的射程只涵蓋庫存卡，不得外推成「發布也該有自己的儲存鈕」。

### §13.2 🔴🔴 發布是**獨立的 mutation**，不是 `productSet` 的一部分

按 `Save` 之後捕到的 POST（method 如標，取證 2026-08-27）：

**第一次（同時改了商品欄位 ＋ 發布）**：

| # | operation name | method | persisted-query hash（前 12 碼） |
|---|---|---|---|
| 1 | `ProductSaveUpdate` | POST | `902c5766b011` |
| 2 | 🔴 **`ProductSavePublishablePublishUnpublish`** | POST | `82c6b52173dc` |

**第二次（**只**改發布，商品欄位沒動）**：

| # | operation name | method | persisted-query hash（前 12 碼） |
|---|---|---|---|
| 1 | 🔴 **`ProductSavePublishablePublishUnpublish`** | POST | `82c6b52173dc` |

🔴 **三條結論**：

1. **發布永遠是獨立的 mutation**，即使由同一顆 `Save` 觸發。
   `ProductSaveUpdate` 與發布那一支是**兩個 HTTP 請求**，不是一個複合 mutation。
   ⇒ 我方**不得**把 publish／unpublish 併進 `productSet`。
2. **一支 operation 同時涵蓋 publish 與 unpublish 兩個方向**——
   operation name 逐字含 `PublishUnpublish`，而且**兩次的 persisted-query hash 完全相同**
   （`82c6b52173dc…`），第一次是純新增、第二次是純移除。
   ⇒ 本尊的 admin 把兩個方向放在**同一個 GraphQL document** 裡
   （推測是同時呼叫 `publishablePublish` 與 `publishableUnpublish` 兩個 field；
   **document 內容不可觀測**，這是推論不是實測，照鐵律 19 標明）。
3. **只在該部分 dirty 時才送**：第二次沒有 `ProductSaveUpdate`
   ⇒ admin 逐區塊判斷 dirty，不是無腦全送。

⚠️ **不可觀測**：這支 mutation 的 variables（哪些 publicationId 進 publish、哪些進 unpublish、
有沒有帶 publishDate）在 POST body 內，本工具讀不到（鐵律 14.3）。

### §13.3 存檔後的讀回：本尊自己用的是 **V2 投影**

`Save` 之後 admin 依序發出的 GET（節錄，取證 2026-08-27）：

| operation name | 可觀測的關鍵 variables |
|---|---|
| `FetchAppliedMetafieldsForUpdate` | `{ownerId, ownerType: PRODUCT / PRODUCTVARIANT, limit: 50}`（商品與變體各一次） |
| `AdminProductDetails` | `{locationsFirst: 250, **supportedChannelsFirst: 50**, …}` |
| `AdminProductDetailsFirstVariant` | `{maxBarcodesPerVariant: 20, contextualPricingContext: {}, …}` |
| 🔴 **`ProductPublicationsV2`** | 見下 |
| `ProductsAgenticChannels` | `{}` |

🔴 **讀回發布狀態的 operation 名字裡就帶 `V2`**——本尊自己的 admin 用的是
**`ResourcePublicationV2` 投影**，不是 V1。這是我方 S2「只實作 V2」那個裁定的**直接實測支持**
（S2 當時的依據是官方文檔與功能超集分析，本節補上「本尊自己也這樣用」）。

`ProductPublicationsV2` 的 variables 逐字節錄：

```
resourceLimit: 250
contextualPublicationContext: {}
contextualPublicationContextTypes: ["REGION","COMPANY_LOCATION","LOCATION"]
allCatalogsQuery: "market_type:REGION OR market_type:LOCATION OR market_type:COMPANY_LOCATION
                   OR catalog_type:COMPANY_LOCATION OR (catalog_type:MARKET AND market_type:app)"
skipMarketsPro: true   skipCatalogs: false
skipMarketCountries: false   skipChannelMarketCatalogs: false
```

三條可用的事實：

1. **`resourceLimit: 250`** 與我方鐵律 4 的「分頁 ≤250」一致。
2. 🔴 **`contextualPublicationContextTypes` 恰三值 `REGION`／`COMPANY_LOCATION`／`LOCATION`**
   ——這是**目錄的市場型別**維度，與 §11.6 的四種 catalog 查詢維度
   （Region／Retail／B2B／ChannelMarket）**不是同一組**。兩者的對應關係＝**未取得**。
3. `allCatalogsQuery` 用的是**搜尋語法字串**（`market_type:REGION OR …`）
   ⇒ 本尊的 catalog 篩選走查詢語言而非結構化參數。屬 S10 的輸入。

### §13.4 S5 尚未取得

| # | 未取得 | 取得方式 |
|---|---|---|
| S5-U1 | `ProductSavePublishablePublishUnpublish` 的 variables 與回應形狀 | persisted query ＋ POST body，現有工具不可觀測（鐵律 14.3）。需要能讀 request body 的抓包工具 |
| S5-U2 | 該 document 內部到底是呼叫 `publishablePublish`＋`publishableUnpublish` 兩個 field，還是別的內部 mutation | 同上；本節的推測**不得**當事實 |
| S5-U3 | **取消發布之後那筆紀錄的資料去向**（刪列 vs 保留列設 null） | admin 不可觀測；需官方文檔正面陳述，或用公開 API 對測試店實測前後查 `resourcePublicationsV2(onlyPublished: false)` |
| S5-U4 | **變體層**的 publish／unpublish 送什麼 operation | §8.3 曾記到 `ProductVariantUnpublish`；本輪只做唯讀觀察（見 §13.5），未觸發寫入以免動到已登記的變體 fixture |
| S5-U5 | 一次打多個 publication 時**部分失敗**的形態 | 需要能製造失敗的 publication（例如不支援該資源型別的管道） |
| S5-U6 | `contextualPublicationContextTypes` 三值與 §11.6 四種 catalog 維度的對應 | 屬 S10 |

### §13.5 變體層的發布面（唯讀觀察，2026-08-27）

**觸發步驟**：商品 `9907126370539`（`實測用 T恤 多變體（測試資料）`）→ 左欄變體清單點 `S`
→ 變體詳情頁 → 點標題列的 `2 channels`。
🔴 全程唯讀：最後以 `Cancel` 關閉，未改動任何值（該變體是已登記的 fixture）。

**變體詳情頁的發布面**：

- 標題列內嵌兩個指示器：`⛓ 2 channels` 與 `⛓ All catalogs`
  🔴 **變體是 2 個管道、父商品是 3 個** ⇒ 變體層的發布狀態**獨立於父商品**，
  這正是既有 fixture 登記的狀態（變體 S 關掉 Point of Sale）。
- 左欄變體清單帶三個篩選：`尺寸 ⌄`、**`Sales channels ⌄`**、**`Catalogs ⌄`**
  ⇒ 變體清單可以按發布狀態篩選。

**點 `2 channels` 開出的 modal**：

- 標題逐字 **`Manage publishing for 1 variant`**
  🔴 「**1 variant**」這個計數措辭 ⇒ 該 modal 設計上支援 **N 個變體批次**
  （從變體清單多選後開啟），不是單一變體專屬。
- 結構與商品版**完全相同**：左欄 `Sales Channels`(3)／`Agentic`(1)／`Catalogs` › `Regions`(1)，
  右側三個管道 toggle ＋ 群組半選態，頁尾 `Cancel`／`Done`。
- 實測 toggle：`Online Store` 開、`Point of Sale` **關**、`Shop` 開（與 fixture 一致）。

🔴 **關鍵對比：變體的 `Online Store` 列 hover 之後，`Schedule publishing` 圖示不出現。**
商品版同樣的 hover 會出現該圖示 ＋ tooltip（§12.3）。
⇒ **變體不能排程發布**的直接實測，與 help 逐字
`You can't set a future publishing date for individual product variants.`
及我方 `ResourcePublication#variant_cannot_be_scheduled` 三者一致。

⚠️ **仍未取得**：變體層送出的 operation name 與 variables——需要真的按下 `Done` ＋ `Save`
才會發出，而那會改動已登記的 fixture。若要取得，應另建一個拋棄式多變體商品再測。

---

## §14 🔴 S6b 地基：發布 modal 的**交互契約**與寫入時序（2026-08-27 實測）

> 射程＝分步方案的 **S6b**（逐商品發布 modal 的編輯面）。
> 測試店 `chill-love-u5q5mnzq`（鐵律 12.2 全權寫入授權）。
> 🔴 本節**自建拋棄式商品 `S6B-Probe-Publish`（id `9913213452523`）做全部破壞性實驗，做完刪除**；
> 五個既有 fixture（`D53-QA/QB/QC`、`9907126370539`、`9911273160939`）**全程未觸碰**，
> 終態逐一複驗完好。未點任何 `Uninstall`、未輸入密碼、未過 CAPTCHA、未授權 OAuth。

### §14.0 toggle 的實作形態（決定了後面每一條怎麼取證）

🔴 **全部 toggle 都是 Web Component `<s-internal-switch>`，狀態藏在 shadow root 裡的
原生 `<input type="checkbox">`**。host 上只有 `label`／`labelaccessibilityvisibility="exclusive"`／`id`。

- 管道列的 host `id` **直接就是 publication GID**（例 `gid://shopify/Publication/209681645803`）
- **群組 toggle 沒有 `id`**
- 每列另有 `button[aria-label="View details for Catalog"]`——🔴 對 sales channel 列而言
  這個 aria-label 是**錯標**（本尊原文照登，不修正、不模仿）
- Online Store 列獨有 `<s-internal-button icon="calendar-time" accessibilitylabel="Schedule publishing">`

⚠️ **工具限制（V 項）**：瀏覽器 a11y tree **不穿透 shadow DOM**，`find` 直接回報
「不存在群組 toggle」。全部 toggle 狀態改以 shadow root 內 `input` 的 `.checked`／
`.indeterminate` DOM property 取得。**平台 AX tree 對外實際曝什麼值＝未取得**
（需真實螢幕閱讀器或 DevTools Accessibility 面板）。

### §14.1 🔴 群組總開關：mixed **一律 → 全開**，不是多數決

| 起始態 | 點一下之後 |
|---|---|
| 半選（2/3 開） | **全開** |
| 半選（1/3 開，少數態複驗） | **全開** |
| 全開 | 全關 |
| 全關 | 全開 |

accessible name 來源＝host 的 `label` 屬性，`labelaccessibilityvisibility="exclusive"`
⇒ **視覺隱藏、只給輔助技術**（畫面上看到的 `Sales Channels` 是另一個 DOM 節點）：

| 狀態 | accessible name（逐字） | `input.checked` | `input.indeterminate` |
|---|---|---|---|
| 全開 | `Unpublish from all` | `true` | `false` |
| 半選 | `Publish to all` | `false` | **`true`** |
| 全關 | `Publish to all` | `false` | `false` |

🔴 **半選與全關的 accessible name 完全相同**，只有 `indeterminate` 能區分——這是本尊的
**無障礙落差**，登記但不照抄（我方用顯式 `aria-checked="mixed"`，AX 上兩態可區分；
依 W3C html-aam，原生 `indeterminate` 本來就映射成 `mixed`，兩條路 AX 結果等價）。

🔴 **本尊的 input 上 `aria-checked`／`role` 一個都沒有**——半選完全靠原生 DOM property
承載，DOM 屬性上不留痕跡。視覺上 mixed ＝深色軌 ＋ **置中短橫線**（不是圓鈕）。

### §14.2 🔴 群組開關的作用域＝**篩選後可見的子集**，不是全部管道

複現：三管道中只有 Online Store 開啟（整體應為半選）→ 搜尋 `online` 篩到只剩一列
→ **群組 toggle 立刻變全開態**（`label="Unpublish from all" checked=true indet=false`）。

⇒ 照「群組 ＝ 全部管道」實作的話，商家在篩選狀態下按群組會**誤操作看不見的管道**。
另複驗：**篩選狀態下按 `Done` 仍正常提交**（被篩掉的管道保持原狀）。

### §14.3 搜尋框：詞首前綴、debounce、無結果文案

| 項目 | 實測 | 證據 |
|---|---|---|
| 觸發 | **即時，不用按 Enter**；有 debounce | 輸入 `of` 後 2 秒仍是過渡態，5 秒才穩定 |
| 大小寫 | 不敏感 | `SHO` → 命中 `Shop` |
| 前後空白 | 會 trim | `"  shop  "` → 命中 |
| 比對法 | 🔴 **詞首前綴**（word-prefix） | `store`→命中 `Online Store`（⇒非整串前綴）／`tore`→無（⇒非子字串）／`line`→無（`Online` 的子字串但非詞首）／`of`→命中 `Point of Sale`（虛詞也算一個詞） |
| 無結果 | 逐字 **`No channels found`**（純文字，無圖示） | 群組列也一併消失 |
| DOM | 不符的列**整個移除**，非 `display:none` | 篩 `SHO` 時 `s-internal-switch` 只剩 2 個 |
| 左欄計數 | **不受搜尋影響**，恆為 3／1／1 | |
| 清除鈕 | 右側 `⊗`，還原全部列且**保留已撥動的 toggle 狀態** | |

⚠️ **debounce 的實際毫秒數＝未取得**（只確認「2 秒仍在過渡、5 秒已穩定」）。

### §14.4 🔴 暫存是**兩層**：modal session（`Cancel`）與頁面 dirty（`Discard`）

| # | 操作 | 結果 |
|---|---|---|
| a | 撥 toggle → `Done` → 重開 modal | 顯示**暫存值**，不是伺服器值 |
| b | 撥 toggle → `Done` → SaveBar `Discard` → 重開 | 顯示**伺服器值**（暫存被完全重置） |
| c | 撥 toggle → `Cancel` | Publishing 卡不變、SaveBar **不出現**；重開顯示伺服器值 |
| d | 🔴 **已有暫存值**時再開 → 撥 → `Cancel` | **只丟棄本次 session 的改動，先前暫存值保留**（卡片仍顯示、SaveBar 仍在） |

⇒ `Cancel` ≠ `Discard`：前者作用域是 **modal session**，後者是**整頁 dirty state**。

🔴 **`Discard` 沒有二次確認對話框**，點下即生效。（我方 `Discard` 走確認框，是包 4 的
既有裁定，屬刻意差異，不在 S6b 射程內改動。）

### §14.5 🔴 沒有任何警告、確認或阻擋

| 情境 | 結果 |
|---|---|
| 把**全部**管道關掉（含 Online Store），商品仍 `Active` | 正常存檔。無確認 modal、無 toast、無 banner |
| 商品是 `Draft` 時開 modal | 全部 toggle `disabled=false`，可撥可存 |
| 存檔後零管道 | `Publishing` 卡的**銷售管道那一列整列消失**（不是顯示「0 channels」） |
| 關掉 Online Store 後 | 頁首 `Preview`／`Share` **仍可用**；全頁 `[role=status]`／`[role=alert]` **空集合** |

全頁文字不含 `not published`／`isn't published`／`no sales channels`／`not visible`。

### §14.6 錯誤態：琥珀 pill ＋ portal 小卡（**不是** mutation 的驗證錯誤）

逐字：小卡標題 `1 error`；內文
`This product isn't discoverable on Shop. Review your product's listing status in the Shop channel.`；
頁面 `Publishing` 卡該列右側琥珀 badge `⚠ 1`。

觸發元件（只在有錯誤時才存在於該列）：
`button[aria-label="Channel Pill Button"][aria-expanded][data-state]`。

🔴 **小卡是 portal 渲染在 dialog 之外**——`document.querySelector('[role=dialog]').innerText`
**讀不到**這段文字（實作與測試的坑）。

觸發條件矩陣（皆為**存檔後**狀態）：

| 商品狀態 | Online Store | Shop | 琥珀警示 |
|---|---|---|---|
| `Active` | ON | ON | 無 |
| `Draft` | ON | ON | 無 |
| `Draft` | OFF | ON | 無 |
| `Active` | **OFF** | ON | 🔴 **有** |
| 任一 | 任一 | OFF | 無（列上沒有 `Channel Pill Button`） |

⇒ 條件＝`status = Active` **∧** 已發布到 `Shop` **∧ 未**發布到 `Online Store`，三者同時成立。
反向複驗：重新開啟 Online Store 並存檔 → badge 消失、按鈕從 DOM 移除。

🔴 **時序**：警示是**伺服器算的**，只在存檔後的 refetch 更新。暫存階段把 Online Store
撥回 ON 但尚未 `Save` 時，琥珀 badge **仍然掛著**（前端不做樂觀清除）。

⚠️ **未取得：存檔時的驗證錯誤（`userErrors`／非 200）形態。** 三種嘗試
（Draft 發布、全管道關閉、Draft+Shop）**皆正常存檔**，未能觸發。上述琥珀警示是
伺服器回傳的 **publication 狀態告示**，不是 mutation 的驗證錯誤——兩者不得混為一談。

### §14.7 🔴🔴 抓包：`@include` 開關，以及「兩支都帶 publications 陣列」

端點形態 `POST /api/operations/<persisted-query-sha256>/<OperationName>/shopify/<store>`
（persisted query ⇒ query 全文不可觀測，鐵律 14.3 的既有 V 項）。
本輪以注入 `window.fetch`／`XMLHttpRequest` wrapper 錄到 **request body**
（⚠️ **response body 形狀＝未取得**——攔截器只錄 request）。

| 情境 | mutation（依序） |
|---|---|
| **只改發布**（複驗兩次） | 🔴 **只有** `ProductSavePublishablePublishUnpublish` |
| 發布 ＋ 商品欄位同時改 | `ProductSaveUpdate` → `ProductSavePublishablePublishUnpublish` |

兩支之後皆 refetch 五支 GET：`FetchAppliedMetafieldsForUpdate` ×2、`AdminProductDetails`、
`AdminProductDetailsFirstVariant`、`ProductPublicationsV2`。

`ProductSaveUpdate` 的 variables（脫敏節錄）：

```
"product": {"status":"DRAFT", "workflow":"product-details-update", "id":"gid://shopify/Product/…"},
"publicationsToPublish": [{"publicationId":"gid://shopify/Publication/209681645803"}],
"publicationsToUnpublish": [],
"shouldPublish": false, "shouldUnpublish": false,
"mediaToUpdate": [], "shouldUpdateMedia": false, "mediaToReorder": [], "shouldReorderMedia": false
```

`ProductSavePublishablePublishUnpublish` 的 variables：

```
"shouldPublish": true, "shouldUnpublish": false,
"productId": "gid://shopify/Product/…", "productQuery": "id:…",
"publicationsToPublish": [{"publicationId":"gid://shopify/Publication/209681645803"}],
"publicationsToUnpublish": []
```

🔴 **三條結論**：

1. **`ProductSaveUpdate` 也帶同樣那兩個 publications 陣列**，但它的
   `shouldPublish`／`shouldUnpublish` **皆為 `false`** ⇒ 兩支 document 共用同一組變數，
   靠 GraphQL **`@include` 開關**決定誰真的執行，**不會重複寫入**。
   ——這解掉 §13.2 結論 2 當時只能寫成「推測」的那一半：本尊確實把兩個方向放在
   同一份 document，而且**用 `@include` 逐向開關**。
2. **媒體也是同一套 `@include` 模式**（`shouldUpdateMedia`／`shouldReorderMedia`）
   ⇒ 這是本尊 admin 的通用形態，不是發布專有。
3. 🔴 **只改發布時真的只送一支**（複驗兩次，皆無 `ProductSaveUpdate`）——§13.2 結論 3 複驗成立。

### §14.8 `Done` 當下零寫入（複驗）

- 撥動單一 toggle：只有 `POST /.well-known/dux`（遙測），**零 `api/operations`**
- 按 `Done`：**零 `api/operations`**（`urlPattern="api/operations"` 過濾回報
  `No requests matching`；注入式錄製同樣為空）
- 開 modal 時唯一捕到的是 `AdminProductDetailsCatalogs` **GET**（載入 catalog 清單，非提交）

⇒ §13.1 複驗成立：`Done` 純粹把 modal 暫存值提交到頁面 dirty state。

### §14.9 附帶取得的逐字文案

- SaveBar：`Unsaved changes`／`Discard`／`Save`；存檔成功 toast：`Product saved`
- 商品狀態下拉：`Active` — `Sell via selected sales channels and markets`；
  `Draft` — `Not visible on selected sales channels or markets`；
  `Unlisted` — ⚠️ **說明被視窗高度截斷，未取得**
- 刪除確認：`Delete <name>?` ／
  `If you delete <name>, this can't be undone. Any media that's only used by this product will also be deleted.`

### §14.10 S6b 尚未取得

| # | 未取得 | 取得方式 |
|---|---|---|
| S6b-U1 | 平台 AX tree 對 mixed 態實際曝的值 | 真實螢幕閱讀器，或 DevTools Accessibility 面板檢視 shadow input |
| S6b-U2 | GraphQL **response body** 形狀 | 改包 response clone，或用 DevTools Network 面板 |
| S6b-U3 | 存檔時的驗證錯誤（`userErrors`／非 200）形態 | 需要找到會被拒絕的操作路徑（三種嘗試皆正常存檔） |
| S6b-U4 | `Unlisted` 狀態的完整說明文案 | 加大視窗高度後重讀下拉 |
| S6b-U5 | 搜尋框 debounce 的實際毫秒數 | 逐 100ms 取樣 |
| S6b-U6 | persisted query 全文 | 不可觀測（鐵律 14.3 既有 V 項） |
| S6b-U7 | 搜尋框的 **input type**、placeholder 是否可見、label 是否只給輔助科技 | §12.2 只記到「有一個 `Search channels` 輸入框」、§14.3 只記行為 ⇒ 三者皆**未取得**。取得方式：回該 modal 讀該 input 的 DOM 屬性與 AX name |
| S6b-U8 | 本尊清除鈕 `⊗` 是**自繪**還是 `type=search` 的瀏覽器原生鈕 | 同上；我方目前依賴原生實作（Firefox 預設不渲染），差異已在程式碼註釋登記 |

### §14.11 環境異常登記（鐵律 12.0）

實測中途瀏覽器 viewport 被壓到 **896×302 CSS px / dpr 1.75**（Chrome 側邊欄佔用，
`resize_window` 無法改變），modal 需捲動操作；另有多次 `Page.captureScreenshot` 逾時
與一次擴充功能斷線——**皆依載入紀律重試後成功，無任何一項因此登記為「本尊沒有此功能」**。

---

## §15 🔴 S6b-2 地基：`Schedule publishing` 彈層的完整契約（2026-08-27 實測＋抓包）

> 射程＝分步方案的 **S6b-2**（排程發布的編輯面）。測試店 `chill-love-u5q5mnzq`。
> 🔴 **自建拋棄式商品 `S6B2-Probe-Schedule`（id `9913809207531`）做全部破壞性實驗、做完刪除**；
> `D53-QA/QB/QC` 全程未開啟其詳情頁，兩個 fixture 完全未觸碰，終態逐一複驗完好。
> 量測環境：viewport 1024×551、根字級 16px、**瀏覽器時區 `Asia/Taipei`**、
> 店鋪時區 `(GMT+08:00) Hong Kong`（兩者刻意不同，見 §15.6）。

觸發路徑：商品詳情 → `Publishing` 卡齒輪 → modal → hover `Online Store` 列
→ 日曆＋時鐘 icon（tooltip `Schedule publishing`）→ 點它。

### §15.1 🔴 它是 **popover，不是巢狀 dialog**——三條判定式證據

```
DIV.Polaris-Popover__Content        tabindex=-1
DIV.Polaris-Popover                 data-polaris-overlay=true
DIV.Polaris-PositionedOverlay        z-index:520
DIV#PolarisPortalsContainer  →  DIV#app  →  BODY
```

1. **沒有** `role="dialog"`、**沒有** `aria-modal`、**沒有** `open`。
2. `modalDialog.contains(popoverOverlay) === false`——它與 modal 本體
   （`div[role=dialog][aria-modal=true]`）是**同 portal 容器下的兄弟**，不是巢狀。
3. **popover 開著時底下的 modal 完全可互動**：直接點 modal 的 `Search channels`
   ⇒ popover 不關、該輸入框取得焦點（`activeElement` 落在它的 shadow input）。
   modal 沒有 `inert`、沒有 `aria-hidden`；**沒有遮罩、沒有 click-outside 關閉、沒有 focus trap**。

⚠️ popover 內容高 491 > 可視 pane 243 ⇒ 本輪 viewport 下頁尾按鈕**必須在 popover 內捲動**才看得到。

### §15.2 🔴 關閉途徑三種，語義**不同**

| 途徑 | 結果 |
|---|---|
| popover 的 `Cancel` | **只關 popover**，modal 留著、modal `Done` 維持 disabled |
| **`Escape`（一次）** | 🔴 **popover ＋ modal 一起關**，且 **modal 內未存的改動全被丟棄**（實測：先關掉 Online Store toggle 再 Escape ⇒ 回頁面**沒有** `Unsaved changes`）。重現 2 次 |
| **點 modal 外的遮罩** | 🔴 同 Escape，一次點擊兩層一起關 |
| 點 modal **內部**（非 popover 區） | popover 不關 |

🔴 **Escape 那條是本尊的資料遺失形態**：商家按 Escape 想關 popover，結果整個 modal 的
未存編輯一起沒了，且沒有任何確認。我方**刻意不照抄**（見 `docs/dev/m2-schedule-popover.md`）。

### §15.3 日期與時間輸入的值域

**日期欄**＝可輸入文字框（`type="text"`、`placeholder="Date (YYYY-MM-DD)"`、`readOnly === false`），
顯示格式是 `August 27, 2026`，但**只吃 ISO `YYYY-MM-DD`**：

| 輸入 | blur 後 | |
|---|---|---|
| `2026-09-15` | `September 15, 2026` | ✅ blur 時正規化成顯示格式 |
| `10/05/2026` | 回退上一個有效值 | ❌ |
| `October 5, 2026`（它自己的顯示格式） | 輸入中被吃成 `52026`，blur 回退 | ❌ **不能回打** |
| `banana` | 顯示 `anana`，blur 回退 | ❌ |

🔴 **錯誤處理＝靜默回退到上一個有效值**：沒有錯誤訊息、沒有紅框。
🔴 **打字選了非當前月份的日期時，月曆不跳頁**（打 `2026-10-05` 後表頭仍停在 `August 2026`）。
⚠️ 字元過濾的精確規則＝**未取得**（`xOctober` → `October`，字母並非一律剔除）。

**時間欄**＝`role="combobox"`＋`aria-autocomplete="list"`，可打字：

| 輸入 | blur 後 |
|---|---|
| `11:00 PM` | `11:00 PM` |
| `22:45`（24 小時制） | **`10:45 PM`**（自動轉 12 小時制） |
| `10:37 PM` | `10:37 PM`（**不吸附**到半點） |

下拉是 `role=option` 的 **30 分鐘刻度**：未來日期 **48 個**選項，第一個逐字
`12:00 AM (start of day)`（只有它帶後綴），其餘 `12:30 AM`…`11:30 PM`。
⇒ **刻度只存在於下拉建議，實際值域是分鐘級**。

### §15.4 🔴 選「今天」時的下限＝**現在**，處置是**靜默吸附到 now**

兩層都測：

1. **下拉層**：日期＝今天、當下 21:17 ⇒ listbox 只剩 **5 個**選項
   （`9:30 PM`／`10:00 PM`／`10:30 PM`／`11:00 PM`／`11:30 PM`），同元件在未來日期是 48 個。
2. **打字層（決定性）**：先設 `11:00 PM` 並 blur（值確實變了）→ 再打 `1:00 PM`（今天的過去時間）
   → blur ⇒ 值變成 **`9:28 PM`＝當下時刻**，**不是**回退到剛才的 `11:00 PM`。
   ⇒ 證明它不是「回退上一個有效值」，而是**夾到 now**。
3. 同因旁證：日期從 `September 15` 改回今天時，原本合法的 `3:30 AM` 被**自動改成 `9:27 PM`**。

**全程沒有錯誤文案、沒有 disabled、沒有 toast。**

⚠️ 這與外部研究建議的「在 grid 層擋（`aria-disabled`）」**不同**——本尊對**時間**是吸附，
對**日期**才是 disabled（見下）。

### §15.5 月曆：至少 50 年內無上限；過去的日子 disabled 但可翻頁

- `Previous month`／`Next month` 的 `aria-label` 逐字即該兩字。
- **可以往回翻到過去月份**（該月所有日期 disabled），`Previous month` 本身**不 disabled**。
- 親手點 `Next month` 25 次 → `August 2028`；再程式化點同一顆 600 次 → **`August 2078`**，
  `nextDisabled === false`。**未觀察到上限。**
- 當月只有「今天之前」的日子 disabled。

### §15.6 🔴 時區徽章取自**後端下發的 IANA 時區**，不是瀏覽器

決定性證據：徽章 DOM 節點的 React fiber 祖先鏈上帶 prop **`timeZone: "Asia/Hong_Kong"`**
（第 15／22／44 層各一次），而**瀏覽器時區是 `Asia/Taipei`**
（`Intl.DateTimeFormat().resolvedOptions().timeZone` 實測）⇒ 該字串不可能來自瀏覽器。

店鋪設定（`Settings › General`，**只讀查看**）：`Time zone = (GMT+08:00) Hong Kong`，
說明逐字 `Sets the time for when orders and analytics are recorded`；
下方另一行逐字 `To change your user level time zone and language visit your account settings`
⇒ 🔴 **本尊有店鋪級與使用者級兩個時區**（與我方 `shops.timezone` / `staff_members.timezone` 對位）。

徽章形態：逐字 `GMT+8`（**縮寫**，不是 `Asia/Hong_Kong`、不是 `HKT`、無前導零）；
DOM 屬性只有 `class,id`——**沒有 `title`／`aria-label`／tooltip**，hover 2 秒不出現任何東西。

⚠️ **未取得**：改店鋪時區後徽章是否跟著變——執行方**刻意未改店鋪設定**
（改設定需要使用者本人在對話中明確同意，派工訊息不能代替）。
補做方式：`Settings › General › Store defaults › Time zone` 改值 → 存檔 → 回商品開彈層看徽章 → 改回。
⚠️ 同樣未取得：`Asia/Hong_Kong` 來自**店鋪級**還是**使用者級**（本店兩者可能都是香港，觀察無法區分）。

### §15.7 🔴 `Remove schedule` 的終態＝**立即發布**，不是清空

- 啟用條件＝**已存檔的排程存在**（在 popover 內設好但尚未按 Done 時仍 disabled）；
  啟用後文字轉**紅色（critical）**。
- 按下去 ⇒ **popover 立即關閉**、不需再按 popover 的 `Done`；tooltip 從
  `Publish on: …` 變回 `Schedule publishing`；**modal 的 `Done` 由 disabled 變 enabled**；
  **零網路請求**。
- 按頁面 `Save` 後送出的 variables（脫敏節錄）：

```
publicationsToPublish = [{ "publicationId":"gid://shopify/Publication/209681645803",
                           "publishDate":"2026-08-27T13:35:30.576Z" }]   ← 當下時刻，不是 null
publicationsToUnpublish = []
```

回應：`"publishDate":"2026-08-27T13:35:30Z","isPublished":true`

⇒ 🔴 **它把 `publishDate` 覆寫成「現在」，於是該管道變成已發布**。
**不是**變未發布、**也不是**回到設排程之前的狀態。

### §15.8 🔴 抓包：排程走 `publishablePublish` 本身，`publishDate` 送 **UTC 帶毫秒 Z**

三個階段各自的請求數：

| 動作 | `api/operations` 請求數 |
|---|---|
| popover 按 `Done` | **0** |
| modal 按 `Done` | **0** |
| 頁面按 `Save` | **1**（`ProductSavePublishablePublishUnpublish`） |

request body（脫敏，去 client_context token）：

```json
{ "operationName": "ProductSavePublishablePublishUnpublish",
  "variables": {
    "shouldPublish": true, "shouldUnpublish": false,
    "productId": "gid://shopify/Product/9913809207531",
    "publicationsToPublish": [
      { "publicationId": "gid://shopify/Publication/209681645803",
        "publishDate": "2026-08-27T14:37:00.000Z" }],
    "publicationsToUnpublish": [] } }
```

🔴 **本地輸入 `10:37 PM` @ GMT+8 → 送出 `2026-08-27T14:37:00.000Z`**
⇒ ISO 8601、**UTC**、**帶毫秒**、`Z` 結尾，**不帶時區偏移量**。
🔴 **「排程」＝帶未來 `publishDate` 的 publish**，沒有獨立的 schedule mutation。

回應（同一支請求即回新狀態，**沒有另外的 refetch**）：

```json
{ "publishDate":"2026-08-27T14:37:00Z", "isPublished":false,
  "publication":{ "name":"Online Store", "supportsFuturePublishing":true } }
{ "publishDate":"2026-08-27T13:12:44Z", "isPublished":true,
  "publication":{ "name":"Point of Sale", "supportsFuturePublishing":false } }
```

三條結論：

1. **送出與回傳格式不對稱**：送 `…T14:37:00.000Z`，收 `…T14:37:00Z`（秒精度）。
2. 🔴 **設未來排程會把已發布的管道立刻打成未發布**（`isPublished` true → false、
   `onlineStoreUrl` 為 null），**而 UI 的 toggle 仍顯示「開」**
   ⇒ **UI toggle ≠ `isPublished`**，本尊自己也是這樣。這正面複驗了 S6a／S6b 的判準。
3. 🔴 **判斷「有排程」必須是 `supportsFuturePublishing && publishDate > now`**——
   `publishDate` 每個管道都有（非排程管道存的是「當初發布的時刻」，是過去值），
   只看它非空會把所有已發布管道都當成排程中。

### §15.9 已設排程後的呈現：三個位置、**三種日期寫法**

| 位置 | 形態 | tooltip 逐字 |
|---|---|---|
| modal 的 `Online Store` 列 | toggle 仍「開」；日曆 icon 從 hover 才出現變成**常駐** | `Publish on: Aug 27, 2026 at 10:37 PM`（**縮寫月**） |
| 商品詳情 `Publishing` 卡 | 文案不變（仍 `All channels`／`All catalogs`），右側**新增日曆-時鐘 badge ＋ 數字**（＝有排程的管道數） | `Online Store: August 27 at 10:37 PM`（**完整月、無年份**） |
| 商品**列表頁** | **沒有任何排程 badge**；`Status` 仍 `Active`（不是 `Scheduled`）、`Channels` 仍 `3`（沒扣掉待發布的）。只有展開 `3 ⌄` 後 `Online Store` 右側有 icon | `Publish on: August 27, 2026 at 10:37 PM`（**完整月＋年**） |

🔴 **同一筆排程在三個位置有三種日期寫法**，這是本尊的不一致，照登記不照抄。

### §15.10 彈層的預設值

- Online Store toggle 為「開」時開啟 ⇒ 日期＝今天、時間＝**當下時刻到分**
  （實測 5 次：9:17／9:23／9:27／9:39／9:43 PM，都等於當時的 wall clock）。
- toggle 被關掉時開啟 ⇒ 一次觀察到預設 `10:00 PM`（當時 21:44，＝下一個半小時刻度）。
  ⚠️ **只有一個樣本，不足以斷言規則**。
- 每次重開彈層**完全重置**（月曆回當月、未按 Done 的編輯全丟）。
- 🔴 **toggle 關掉時日曆 icon 仍出現、彈層仍可開**——icon 的顯示條件是該 publication
  的 `supportsFuturePublishing`，**不是**「目前已發布」。

### §15.11 S6b-2 尚未取得

| # | 未取得 | 取得方式 |
|---|---|---|
| S6b2-U1 | 改店鋪時區後徽章是否跟著變 | 需使用者本人同意後改 `Settings › General` 的 Store defaults 再改回 |
| S6b2-U2 | 徽章的 `Asia/Hong_Kong` 來自**店鋪級**還是**使用者級**設定 | 同上；需讓兩者不同值才能區分 |
| S6b2-U3 | 日期欄字元過濾器的精確規則 | 逐字元窮舉輸入 |
| S6b2-U4 | toggle 關閉時彈層預設時間的規則（只有一個樣本） | 多次在不同時刻重複開啟觀察 |
| S6b2-U5 | 月曆的真實上限（翻到 2078 仍無上限） | 程式化再翻更多；或查官方文檔 |
| S6b2-U6 | 排程到點的實際生效機制 | 既有 S2-U3，未變 |
