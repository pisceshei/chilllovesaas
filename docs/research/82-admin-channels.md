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

**① 新商品：建立當下即物化，且預設全開**
新增商品表單在**存檔前**就顯示 `Active` ＋ `All channels`；存檔後其預設變體
`channelPublicationCount = 3`。⇒ 「auto\_publish」不只是「新增管道時回填既有商品」，
**它同時是「新增商品時填滿既有管道」**。

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
