# 21 — 實測 Teardown：CHILL LOVE 店的 2026 春季版後台（逐頁走訪）

> 2026-08-10 以 Chrome 實地走訪你的開發店（Shopify Plus dev store，繁中介面，建立於 2026-07-14，網域 chill.deals，含 Fecify app 與約 50 個匯入商品、5 筆測試訂單）。本篇記錄：(1) **2026 春季版（春季 '26）與 00/02 研究文件的差異**——這是原型 v2 的修正清單；(2) 逐頁重點；(3) 對方案的補充。截圖存於對話紀錄供比對；原型一律用 CHILL LOVE 自有設計語言與自寫文案（紅線見 07 §10）。

## 1. 重大發現：2026 春季版的十個結構性變化

1. **頂部列改淺色**：白底頂部列——左＝logo + 版本徽章「春季 '26」；中＝全域搜尋（CTRL K 提示）；右＝Sidekick 圖示、通知鈴鐺、商店徽章（頭像+店名+dev 標籤）。我們 02 記錄的深色 top bar 是舊版（載入 skeleton 階段仍是深色）。
2. **首頁 AI-first**：大問候語 +「請輸入您的問題…」的 **Sidekick 輸入框**置於首屏正中 + 任務 chip（「為訂單出貨 4」）。上方橫貫一條 **pulse 指標列**：所有管道/過去 30 天——工作階段、總銷售額、訂單、轉換率（各帶迷你 sparkline）+ 右側「即時訪客」。之下才是 setup 任務卡片（每張：進度圈「已完成 x 項任務中的 y 項」+ 標題 + 說明 + 插圖 + CTA）。
3. **主導航改組**：首頁／訂單（badge 未出貨數）／產品／顧客／**成長**（原行銷：歸因、行銷活動）／折扣／**內容**（元物件、檔案、**選單**、部落格貼文——選單從線上商店移到內容）／市場／**財務**（一級項：稅務、Credit、Bill Pay、收款啟用）／分析。當前 section 才展開子項（訂單→草稿/運送標籤/未完成結帳作業；產品→商品系列/庫存/採購單/轉移/禮品卡；顧客→分群/**公司**(B2B)；分析→報告/實況瀏覽；市場→目錄/推出）。
4. **銷售管道**：線上商店／**代理式（Agentic）**／銷售點。**Agentic Storefronts 是 2026 新通路**：把商品目錄開放給 AI 代理（ChatGPT、Microsoft Copilot、Shop、其他管道），有「允許 Shopify 為我管理」總開關、來源卡（Shopify Catalog / Knowledge Base）、上線前檢查清單（目錄存取權限、更新政策）。
5. **側欄底部固定區**：「Sidekick 對話 ›」與「API 相關需求搜尋結果」入口 + 設定（齒輪）。Sidekick 不只是聊天框，滲入各頁（見 6）。
6. **AI 滲入模式**（原型 v2 要抄的交互語彙）：顧客列表頂部「描述您的分群」AI 輸入列；市場列表出現 sparkle 圖示的 **AI 建議行**（「建立 International 市場 ＋」，可關閉）；產品描述編輯器左上有 ✨ AI 生成鈕。
7. **列表頭改版**：舊「多 tabs」變成「**檢視切換器下拉**（全部 ⌄）＋ 搜尋和篩選一體欄 ＋ 右側欄位設定圖示」。訂單列表另有「批次處理近期訂單」按鈕。取消的訂單**整列劃線**顯示。
8. **Settings 出現組織層**：設定框架左欄頂部是組織區塊（組織名＋「組織／使用者」兩項——**使用者管理上移到組織層**），其下才是商店（店徽＋網域）的設定清單：一般／方案／帳單／付款／結帳／顧客帳號／運送與配送／稅額與關稅／地點／應用程式／銷售管道／網域／顧客事件…（與 05 清單基本吻合）。「一般」頁多了**商家詳細資訊（business entity）**卡（金融產品/市場/稅額用的商業實體）。
9. **語言混排現實**：繁中為主、部分新功能未翻（Online Store、Agentic、Point of Sale、Custom、Credit、Bill Pay）——真實產品也有 i18n 長尾，demo 不必為 100% 翻譯焦慮。
10. **驗證了我們的研究**（重要的「沒變」）：訂單雙狀態 badge 語意（已付款＝灰實心圈、未出貨＝黃空圈）；庫存五欄帳（不可用/已佔用/可用/現有庫存/在途）；折扣建立四類型 modal（扣減商品金額/買X送Y/扣減訂單金額/免運費）；訂單詳情三欄結構（出貨卡+付款卡+交易時間軸｜右欄備註/其他詳細資訊(metafields)/管道資訊/顧客/地址/轉換摘要/訂單風險/標籤）；產品詳情卡片流（標題/說明/多媒體/類別/定價/庫存/運送/子類變體/metafields/SEO+右欄狀態/發布/組織分類/佈景主題範本）——01/06 的模型可以放心照做。

## 2. 逐頁走訪紀錄

- **首頁**：見 §1.2。pulse 指標列 + Sidekick 框 + 任務卡片組（含 Plus 專屬設定卡）。
- **訂單列表**：欄＝訂單/日期/顧客/出貨期限/管道/總計/付款狀態/出貨狀態/品項/配送狀態/配送方式/標籤（水平捲動）；多幣別金額直接顯示（MYR/HKD/USD）；草稿單管道顯示「訂單草稿」；風險單在單號旁示警。
- **訂單詳情**（E810317888344395）：頂部＝麵包屑+單號+雙 badge+右側 退款/編輯/更多動作/上下筆；未出貨卡（品項列：縮圖+名稱/變體+單價×數量+小計）底部「標記為已出貨 ⌄」split button；已付款卡（小計/折扣(碼)/運送/總計/已付款）；**交易時間軸**：留言輸入（@提及、#、附件、表情、「只有您和其他員工可以看見備註」）+ 系統事件流（app 動作、付款、確認編號、下單）；右欄含 app 寫入的 metafields（其他詳細資訊）。
- **產品列表**：50 筆/頁；欄＝商品/狀態(有效綠)/庫存（紅字「庫存 0 件」）/…/類型/供應商；匯出/匯入/更多動作/新增商品。
- **產品詳情**：說明富文本（✨AI、HTML 切換）；多媒體格（首圖大格）；類別（taxonomy 建議）；右欄狀態/發布（skeleton 載入）/銷售紀錄卡/組織分類/佈景主題範本；下方運送（包裹預設值、原產地、HS 代碼摺疊）；「子類」＝新增尺寸/顏色選項；商品中繼欄位（含 app 定義）＋「+ Disclosures」；搜尋引擎產品資訊＝真實 SERP 預覽（chill.deals 網域）。儲存鈕右下浮動、dirty 才亮。
- **商品系列**：欄＝標題/商品數/條件/銷售管道；只有預設 Home page。
- **庫存**：五狀態欄與 01/06 一致，列內可直接改；匯出/匯入。
- **顧客**：AI 分群輸入列；欄＝顧客名稱/電子郵件訂閱（未訂閱 badge）/地點/訂單/消費金額；子項 分群、公司(B2B)。
- **成長**：歸因/行銷活動子項；Campaign Autopilot 搶先體驗 banner；成效卡（歸因銷售額/依流量類型工作階段/直接）。
- **折扣**：空狀態（插圖+說明+建立折扣）；建立→四類型選擇 modal。
- **內容→元物件**：定義列表（找不到定義空狀態）、管理/新增定義；子項 檔案/選單/部落格貼文。
- **市場**：左＝資料夾樹（商店預設值/地區）；右＝市場表（市場/狀態/包含/自訂項目）+ **AI 建議行**；子項 目錄/推出；右上「圖表檢視」切換。
- **財務**：稅務設定卡、工具（Bill Pay）、開始收款（啟用 Shopify Payments）大卡 + 兩步驟驗證提示 banner；子項 Credit/Bill Pay。
- **分析**：頂部 篩選（今天/日期/幣別 USD）；控制面板＝可摺疊區塊，stat 卡（銷售總額/回頭客比率/已履行訂單數/訂單）+ 圖表卡格（隨時間總銷售額、依管道、AOV、依商品…）；右上 試用目標/新增探索（ShopifyQL 探索）；子項 報告/實況瀏覽。
- **代理式（Agentic）**：見 §1.4。
- **設定→一般**：組織層＋商店層清單（§1.8）；商家詳細資訊/商店聯絡詳細資訊/商店預設值（幣別顯示→導去 Markets 管理）。
- **未竟**（下一輪補走）：線上商店主題頁（重資源未載完）、主題編輯器、結帳設定、報告詳頁、實況瀏覽、分群建立器、POS。

## 3. 對方案的補充（納入 v2）

1. **Admin 原型 v2 改版清單**（蓋過 02 的舊 top bar 設定）：淺色頂部列＋版本徽章；首頁改 pulse 指標列＋AI 輸入框殼（demo 可先接假回覆）＋任務卡片；導航對齊 §1.3（成長/內容/財務進主選單、選單移入內容）；列表頭用「檢視下拉＋搜尋篩選一體欄」；當前 section 展開子項的側欄行為。
2. **新 P2 節點**：(a) **Sidekick 等價物**——admin 內建 AI 助理（自然語言→查詢/操作），我們的 06 事件模型+19 API 天然支援；(b) **Agentic 通路等價物**——把 catalog 以 feed/MCP 形式開放給 AI 代理＝我們 09 「docs 對 LLM 友善」策略的延伸，這是 2026 電商平台的方向性賭注。
3. **Settings 原型要含組織層**（組織/使用者在上、商店設定在下）——我們 05 §2 的 organization 概念被實測證實為一級 UI。
4. **多幣別第一天就會出現在訂單列表**（app 通路寫入）——06 的 presentment 欄位預留是對的，v2 列表 demo 直接展示多幣別。
5. **業務實體（business entity）**概念進 backlog：一店可掛多個法律實體（金融/稅務用）——P3。
6. 語言策略：繁中為主、允許新功能英文 fallback（§1.9 的現實）。

## 4. 下一步

原型 v2（依 §3.1 改版 + 新增訂單詳情/分析/設定三頁）→ 掛 repo 的新任務裡建置並 push；本輪截圖比對可隨時在此對話重看。

---

## §5 🔴 admin 外框骨架的 CSS 量測（層④ CSS 三段式，2026-08-28）

> 全域 token 值表＝`docs/design/111-shopify-token-baseline.md`；換值計畫＝`docs/design/112`。
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 🔴 **鐵律 9**：只記 `getComputedStyle` 算出來的值，不含本尊樣式表原始碼、選擇器定義或可執行片段。
> ⚠️ 對應我方 `app/frontend/admin/layout/AdminShell.tsx`。頁面骨架的**幾何**另見 `111` §16。

### §5.0 量測環境

> 量測日期 2026-08-28（頁面 JS 時鐘回報 2026-08-27T17:47Z，機器時區偏移；以任務日期 2026-08-28 為準）。測試店 chill-love-u5q5mnzq，Chrome（Claude in Chrome），devicePixelRatio=1，主題 html.p-theme-light（prefers-color-scheme: dark = false，prefers-reduced-motion = false）。
> 【桌機基準】window.innerWidth = **1024**、innerHeight = 551、**根字級 getComputedStyle(document.documentElement).fontSize = 16px**（無 47 §F 記過的 root 24px 污染）。body 字級 13px／行高 20px／字重 500／font-family 首選 Inter。
> 🔴 **1280 未取得**：本機 screen.width=1024（availWidth 1024 / availHeight 728），且 resize_window 工具對此視窗一律回 "Bounds must be at least 50% within visible screen space"（window.screenX 回報 -32000，chrome.windows API 視為離屏）。桌機值一律以 innerWidth=1024 記錄，且 matchMedia('(min-width:768px)') 與 '(min-width:48em)' 皆 true，屬桌機帶。
> 【768 / 390 取得方式】resize_window 不可用、admin.shopify.com 自我 iframe 被 X-Frame-Options 拒絕（實測畫面顯示「admin.shopify.com 拒絕連線」）。改用**同源 script-opened popup**：在頁面注入一顆按鈕→用 computer 工具真實點擊取得 user activation→window.open(...,'popup=yes')→再用 popup 自己的 window.resizeTo 精準校到 innerWidth = 768 / 390（校正 outerWidth-innerWidth 差值），popup 根字級同為 16px。這是**真實視口**（媒體查詢真的重算），不是縮放模擬。量畢已 window.close()、注入元素已移除、量測分頁已 tabs_close。
> 【唯讀確認】全程只做導航（Products→Collections→Analytics，皆點側欄真實連結）、hover、focus、開合行動版抽屜；未按任何儲存鍵、未觸碰 9907126370539／9911273160939／D53-QA/QB/QC。
> 【取值方法】getComputedStyle + getBoundingClientRect，穿透 open shadow root（遞迴 el.shadowRoot.querySelectorAll）。**只記算出來的數值，未複製任何 Shopify 樣式表片段／class 定義／cssText**。

### §5.1 本畫面用到的 token 值

| 類別 | 量測值 | 取值選擇器 |
|---|---|---|
| 版面-頂欄高 | --pg-top-bar-height = 3.5rem（＝56px，與 #AppFrameTopBar 實測 height 56px 一致） | :root (document.documentElement) |
| 版面-側欄寬 | --pg-navigation-width = 15rem；--pg-layout-width-nav-base = 15rem（＝240px，與 nav 實測 240px 一致） | :root |
| 版面-內距階 | --pg-layout-width-inner-spacing-base = 1rem；--pg-layout-width-outer-spacing-min = 1.25rem；--pg-layout-width-outer-spacing-max = 2rem | :root |
| 版面-欄寬上下限 | --pg-layout-width-primary-min = 30rem；--pg-layout-width-primary-max = 41.375rem；--pg-layout-width-secondary-min = 15rem；--pg-layout-width-secondary-max = 20rem；--pg-layout-width-one-half-width-base = 28.125rem；--pg-layout-width-one-third-width-base = 15rem；--pg-layout-width-page-content-partially-condensed = 28.125rem；--pg-layout-relative-size = 2 | :root |
| 版面-行動版導航 | --pg-mobile-nav-width = calc(100vw - 2rem - 2rem)（🔴 但 390 實測抽屜實際寬度是 240px，此 token 未作用於本次觀察到的抽屜） | :root |
| 版面-其他框架量 | --pg-control-height = 2rem；--pg-control-vertical-padding = calc((2.25rem - 1.5rem - .125rem)/2)；--pg-dismiss-icon-size = 2rem；--pg-bottom-bar-height = 0rem；--pg-bottom-bar-max-height = 21.875rem；--pg-system-alert-banner-height = 0rem；--pc-frame-global-ribbon-height = 0px；--pc-frame-offset = 0px；--pc-sidebar-width = 356px；--pc-sidebar-reserved-width = 0rem；--s-frame-inset-block-start = 3.5rem | :root |
| 色-導航語義色（全套 14 條） | --p-color-nav-bg = #ebebeb；--p-color-nav-bg-surface = #00000000；--p-color-nav-bg-surface-hover = #f1f1f1；--p-color-nav-bg-surface-active = #fafafa；--p-color-nav-bg-surface-selected = #fafafa；--p-color-nav-icon = #4a4a4a；--p-color-nav-icon-active = #4a4a4a；--p-color-nav-icon-hover = #4a4a4a；--p-color-nav-text = #303030；--p-color-nav-text-active = #303030；--p-color-nav-text-hover = #303030；--p-color-nav-text-secondary = #616161；--p-color-nav-text-secondary-active = #303030；--p-color-nav-text-secondary-hover = #303030 | :root |
| 導航幾何（osui 前綴，本輪新發現） | --osui-nav-item-alignment-base-tight = .75rem；--osui-nav-item-alignment-none = 0；--osui-nav-item-interior-padding = .5rem；--osui_nav-action-common-prefix-gap = .5rem；--osui_nav-action-common-prefix-size = 1.25rem；--osui_nav-action-connected-button-width = 1.75rem；--osui_nav-action-connected-button-width-slim = 1.25rem；--osui_nav-item-alignment-common-icon = calc(1.25rem + .5rem + .75rem)；--osui_nav-item-alignment-common-action-with-icon = calc(1.25rem + 1.25rem + .5rem)；--osui_nav-item-alignment-nested-offset = .25rem | :root |
| 色-底色 | --p-color-bg = #f1f1f1；--p-color-bg-surface = #fff；--p-color-bg-surface-secondary = #f7f7f7；--p-color-bg-surface-tertiary = #f3f3f3；--p-color-bg-surface-hover = #f7f7f7；--p-color-bg-surface-active = #f3f3f3；--p-color-bg-surface-selected = #f1f1f1；--p-color-bg-inverse = #0a0a0a；--p-color-bg-fill = #fff；--p-color-bg-fill-brand = #303030；--p-color-bg-fill-secondary = #f1f1f1；--p-color-bg-fill-tertiary = #e3e3e3 | :root |
| 色-文字 | --p-color-text = #303030；--p-color-text-secondary = #616161；--p-color-text-brand = #4a4a4a；--p-color-text-disabled = #b5b5b5；--p-color-text-link = #005bd3；--p-color-text-inverse = #e3e3e3；--p-color-text-inverse-secondary = #b5b5b5；--p-color-text-critical = #8e0b21；--p-color-text-caution = #4f4700；--p-color-text-info = #003a5a；--p-color-text-success = #014b40 | :root |
| 色-邊框 | --p-color-border = #e3e3e3；--p-color-border-secondary = #ebebeb；--p-color-border-tertiary = #ccc；--p-color-border-hover = #ccc；--p-color-border-disabled = #ebebeb；--p-color-border-focus = #005bd3；--p-color-border-brand = #e3e3e3；--p-color-border-critical = #fec1c7 | :root |
| 間距階（--p-space-*） | 0=0rem, 025=.0625rem, 050=.125rem, 100=.25rem, 150=.375rem, 200=.5rem, 250=.625rem, 300=.75rem, 400=1rem, 500=1.25rem, 600=1.5rem, 700=1.75rem, 800=2rem, 1000=2.5rem, 1200=3rem, 1600=4rem, 2000=5rem, 2400=6rem, 2800=7rem, 3200=8rem（共 20 階） | :root |
| 圓角階（--p-border-radius-*） | 0=0rem, 050=.125rem, 100=.25rem, 150=.375rem, 200=.5rem, 300=.75rem, 400=1rem, 500=1.25rem, 750=1.875rem, full=624.9375rem（共 10 階） | :root |
| 字級階（--p-font-size-*） | 275=.6875rem, 300=.75rem, 325=.8125rem, 350=.875rem, 400=1rem, 450=1.125rem, 500=1.25rem, 550=1.375rem, 600=1.5rem, 750=1.875rem, 800=2rem, 900=2.25rem, 1000=2.5rem | :root |
| 字重階（--p-font-weight-*） | regular=450, medium=550, semibold=600, bold=650；語義別名 input-label=450, input-label-small=450, details-text=450, button-label=550, heading-small/medium/large=600, display-small=600, display-medium=650, display-large=650 | :root |
| 行高階（--p-font-line-height-*） | 300=.75rem, 400=1rem, 500=1.25rem, 600=1.5rem, 700=1.75rem, 800=2rem, 1000=2.5rem, 1200=3rem | :root |
| 陰影階（--p-shadow-*，皆為多層堆疊） | 0=none；100＝6 層：0 .3125rem .3125rem -.15625rem #00000008 / 0 .1875rem .1875rem -.09375rem #00000005 / 0 .125rem .125rem -.0625rem #00000005 / 0 .0625rem .0625rem -.03125rem #00000008 / 0 .03125rem .03125rem 0 #0000000a / 0 0 0 .0625rem #0000000f；200＝7 層（100 的六層再疊 0 .5rem .625rem -.3125rem #00000014）；300＝6 層（最外 0 .5rem 1.5rem -.5rem #00000047）；400＝6 層（最外 0 1.25rem 2rem -.75rem #00000033）。每一階最後一層固定是 0 0 0 .0625rem #0000000f 的髮絲外框 | :root |
| 動效（--p-motion-*） | duration-100=100ms, 150=150ms, 200=200ms, 250=250ms, 300=300ms, 500=500ms；--p-motion-ease = cubic-bezier(.25,.1,.25,1)；--p-motion-ease-in-out = cubic-bezier(.42,0,.58,1) | :root |
| 自訂屬性總量 | getComputedStyle(:root) 長度 1174，其中以 -- 開頭者 **699 條**（含 --p-* / --pg-* / --pc-* / --osui* / --s-* 多套前綴並存） | :root |

### §5.2 元件量測（20 項）

| # | 元件 | 量測 | 狀態樣式 |
|---:|---|---|---|
| 1 | **頂欄外框 AppFrameTopBar** | 外殼 1024×**56**@0,0；position: fixed；z-index **517**；自身 background 透明、box-shadow **none**、四邊 border 0（🔴 **頂欄與下方沒有任何分隔線或陰影**，靠色差分界）。內層 _TopBar：background **rgb(10,10,10)**、color rgb(238,238,238)、gap **24px**、display block。_Container：display **grid**。整條頂欄被包在 s-internal-theme-provider 的 slot.p-partial-theme-dark 底下（＝局部深色主題）。 | 頂欄容器本身無 hover/focus/disabled 態 |
| 2 | **頂欄左區 + Shopify logo** | _LeftContent 240×56@0,0（**寬度＝側欄寬 240px，與側欄嚴格對齊**），display flex。_ShopifyLogoWrapper 240×56，padding **0 20px**。_LogoWrapper 86×34@20,11，內含兩張 img：img0（購物袋標記）**21×24**@20,16，filter: grayscale(0)，transition transform .2s / filter .3s；img1（Shopify 字標）**62×20**@44,20，margin 9px 0 0 3px。logo 區無 <a> 包裹。 | 未取得（logo 區本身非按鈕；hover 只有 img0 有 transform/filter transition 宣告，實際變化量未量） |
| 3 | **頂欄搜尋框（Search 啟動器）** | 1024 寬時：**518.11×36**@240,10（左緣正好貼著側欄右緣 240，垂直置中：(56-36)/2=10）。radius **12px**；承載底色的是外層 _BorderGradient：background **rgb(40,40,40)**、radius 12px、box-shadow none。按鈕文字色 **rgb(220,220,220)**（＝placeholder 色）。內部：_LabelWrapper padding 8px 0 8px 8px；放大鏡 _Icon **20×20**@249,18、margin 1px 3px 1px 1px；_Label 「Search」43.66×20@272,18（fs 13px / fw 500 / lh 20px / color rgb(220,220,220)）；右側 _Shortcut padding 8px 8px 8px 0，兩顆 kbd.Polaris-KeyboardKey--extraSmall（CTRL 34×20、K 20×20），kbd fs **10px** / fw 500 / lh 16px / color **rgb(170,170,170)**。768 寬時搜尋框縮為 262.11×36（彈性寬）。 | hover：_BorderGradient background 由 rgb(40,40,40) → **rgb(34,34,34)**（變暗），button 自身 background 與 color 不變、無邊框變化；transitionDuration = **0s**（無過場）。focus/active/disabled 未取得（未點擊避免開啟全域搜尋面板） |
| 4 | **頂欄右區容器** | 1024 寬時 265.89×56@758.11,0，display flex；子項 Sidekick 36×36@774,10、Alerts 36×36@818,10、店鋪選單 154×36@862,10 → **鈕間距一律 8px，最右緣 862+154=1016，距視窗右緣 8px**。Home 頁時 Sidekick 按鈕包在 _ButtonWrapper_tqsmq 內且 opacity=0（隱藏）、進入其他頁後 opacity=1。 | — |
| 5 | **頂欄 icon 鈕（Sidekick / Alerts Feed）** | **36×36**、radius **12px**、padding 6px（Sidekick 為 1px 6px）、background 透明、color rgb(220,220,220)。aria-label 實測值：「Sidekick」「Alerts Feed - 0 unseen alerts」。 | hover：外層 _BorderGradient background 透明 → **rgb(34,34,34)**；button 自身不變。_Activator_1bbfv 的 transition = background-color **0.1s** ease，但實際承載底色的 _BorderGradient transitionDuration = **0s**。focus/active/disabled 未取得 |
| 6 | **頂欄店鋪／頭像選單** | 按鈕 **153.89×36**@862,10、radius 12px、padding 0、transition background-color 0.1s。InlineStack 141.89×28@866,14、**gap 4px**。頭像：s-avatar（display: contents）→ shadowRoot → span.avatar.color-three.size-base **28×28**、background **rgb(44,224,212)**、color rgb(3,60,57)、fw 450、border-radius 計算值 **clamp(4px, round(25%, 2px), 8px)**（28px 下 ≈8px）；shadowRoot 內另有 img.hidden 與 span.initials（絕對定位覆蓋 28×28）。店名 p 68.75×16@898,20：fs **12px** / fw 500 / lh 16px / color rgb(220,220,220)。dev 徽章 span[class*="_DevBadge"] 37.14×20@970.86,18：background **rgb(55,55,55)**、color rgb(170,170,170)、padding **2px 8px**、radius **8px**，內文 fs 12px / lh 16px。 | hover：外層 _BorderGradient background 透明 → **rgb(34,34,34)**；文字色不變。點開選單未執行（避免副作用），focus/active/disabled 未取得 |
| 7 | **跳至內容 Skip link** | position fixed@8,10、124.61×32、background **rgb(255,255,255)**、color rgb(48,48,48)、padding **6px 12px**、radius **8px**、**z-index 518**（高於頂欄 517）、visibility visible、transform none、**opacity 0**（未聚焦時靠透明度隱藏，非 display:none）。 | 聚焦態未取得（未以鍵盤 Tab 進入） |
| 8 | **側欄容器 nav** | **240×495**@0,**56**（緊貼頂欄下緣）；background **rgb(235,235,235)**（＝--p-color-nav-bg #ebebeb）；**border-radius: 12px 0 0**（只有左上角圓 12px）；display flex；**::before / ::after 皆 content: none ⇒ 側欄與內容區之間沒有任何分隔線**，全靠底色差（側欄 #ebebeb vs 內容 rgb(251,251,251)）＋內容區 12px 圓角形成階差。內部捲動由 s-internal-scroll-box → shadowRoot → s-box → shadowRoot → div#scroll-container 承擔：overflow-y **auto**、**scrollbar-gutter: stable**（這就是 nav 240 但內容區塊只有 230 的來源，保留 10px 溝槽）。 | — |
| 9 | **側欄一級導覽項** | ul padding **12px 0**、寬 230。li **230×28**。_ItemWrapper padding **0 2px 0 10px**。_ItemInnerWrapper **218×28**@10、radius **8px**。a 218×28、padding **0 4px 0 8px**、radius 8px。**列高 28px、列距（pitch）28px（無額外 margin）**。圖示 div[class*="_Icon_xhno8"] **20×20**、margin **4px 8px 4px 0**（⇒ 圖示與文字間距 8px）、display grid；圖示實體 s-internal-icon → shadowRoot → span.icon **20×20**、color **rgb(74,74,74)**，內 svg **16×16**、margin 2px。文字 span[class*="_Text_xhno8"] margin 4px 0；標籤 span.Polaris-Text--root.Polaris-Text--bodyMd.Polaris-Text--medium：fs **13px** / fw **500** / lh **20px** / color **rgb(48,48,48)** / letter-spacing normal。標籤左緣固定 x=46（＝10+8+20+8）。徽章 div[class*="_Badge_xhno8"] → span → s-internal-badge → shadowRoot → div.badge：**23.77×20**、margin-left 4px、background **rgba(0,0,0,0.06)**、color rgb(97,97,97)、fs **12px** / fw **550** / lh 16px、padding **2px 8px**、radius **8px**、gap 4px。列右側可帶 span[class*="_SecondaryActions_xhno8"]（1 顆時 24×28@202、2 顆時 52×28@176 padding 0 2px），子鈕 **24×24 radius 8px**；帶次要動作時 a 寬縮為 192。 | hover：_ItemInnerWrapper background 透明 → **rgb(241,241,241)**（＝--p-color-nav-bg-surface-hover），文字色／圖示色／邊框**皆不變**；transitionDuration **0s**（瞬間切換，無過場）。selected：_ItemInnerWrapper background **rgb(250,250,250)**（＝--p-color-nav-bg-surface-selected），**文字色與圖示色不變**。selected + hover：維持 rgb(250,250,250)（選中態勝過 hover）。focus-visible：元素 **outline: 2px solid rgb(0,91,211)、outline-offset: 1px**，同時 a::after 由 box-shadow spread **-1px（隱形）** 變為 **rgb(0,91,211) 0 0 0 2px**、radius 4px、四邊 inset -1px（環盒 220×30）；此時底色**不**變成 hover 色。disabled：本元件無 disabled 態（未取得） |
| 10 | **側欄選中指示（左側指示條 / 樹狀連接線）** | 🔴 **一般選中項沒有實心左側指示條**。單獨選中且無子項時（例：Home 選中），::before content=""、3px×26px、left **-8px**、top/bottom 1px、radius **0 4px 4px 0**，但 background-color **rgba(0,0,0,0) ⇒ 不可見**。當某群組展開時，該群組的父項與**被選中的子項**的 ::before 改為 **21px×28px、left 8px、top 0** 的 SVG content 影像（樹狀連接線：父項為垂直短線、選中子項為 └ 彎折），線條顏色 **#B5B5B5**；同群組其他未選中子項的 ::before 為 content:"" 不繪圖。（🔴 該 SVG 為 Shopify 資產，本輪只記形狀尺寸與顏色，未複製路徑資料） | 見上：selected / 群組展開時才出現 |
| 11 | **側欄次級（子）導覽項** | 高度 **28px（與一級項相同）**、寬 218@10、radius 8px。**padding-left 36px**（一級項為 8px）⇒ **縮排量 +28px**，效果是子項文字左緣 x=46 與一級項文字左緣**完全對齊**。**無圖示**（實測 5 個子項全部無 _Icon_xhno8）。字級與一級項相同 **fs 13px / fw 500 / lh 20px**；🔴 **差別在顏色：未選中 color rgb(97,97,97)**（＝--p-color-nav-text-secondary #616161）vs 一級項 rgb(48,48,48)。子清單 ul margin-bottom **8px**；外層 Polaris-Collapsible 高度 = 子項數×28 + 8。 | hover：_ItemInnerWrapper background → **rgb(241,241,241)** 且 **文字色 rgb(97,97,97) → rgb(48,48,48)**（🔴 與一級項不同：一級項 hover 不變色）。selected：background **rgb(250,250,250)** + color **rgb(48,48,48)** + ::before 繪出 └ 連接線。active/disabled 未取得 |
| 12 | **側欄分組標題（例：Sales channels）** | 標題容器 div._Heading **230×24**、padding **0 12px**、margin-bottom **2px**、radius 4px。內層 button 114.75×24@12、padding **4px 3px 4px 8px**、radius **8px**、display inline-block。🔴 文字實體在 shadow root：strong.text **fs 12px / fw 550 / lh 16px / color rgb(48,48,48)**。右側收合箭頭 div[class*="_Icon_1nvmt"] 5×16、margin 0 6px、transition transform .05s cubic-bezier(.42,0,.58,1)。分組 li[class*="_SubSection_"] padding-bottom **16px**；標題底到第一個列項 y 差 = 26px（24 高 + 2 margin）。 | hover/focus/active 未取得（未 hover 到分組標題） |
| 13 | **側欄底部設定入口（sticky）** | _StickyBottomNav **230×60**、**position: sticky**、z-index 1、background **rgb(235,235,235)**（與側欄同色，不透明遮住底下捲動內容）、padding-top **8px**、transition **box-shadow .35s / border-top .35s cubic-bezier(.25,.1,.25,1)**（⇒ 設計上捲動時會出現上邊界，本輪未觸發）。內 ul padding **12px 0**、高 52。Settings 列 218×28@10,511，padding 0 4px 0 8px、radius 8px，標籤 51×16@46,517、fs 13 / fw 500 / color rgb(48,48,48)——**與一般一級項規格完全相同**。 | 未捲動時 box-shadow **none**、border-top **0px**。捲動後的態 **未取得**（見 not_obtained） |
| 14 | **整體佈局骨架 AppFrame** | #AppFrameChrome 1024×551@0,0、background **rgb(10,10,10)**（深色底襯，讓上方圓角露出深色）、transition width .25s cubic-bezier(.25,.1,.25,1)。#AppFrameBevel position fixed、transition transform .25s / border-radius .5s cubic-bezier(.42,0,.58,1)。main#AppFrameMain **1024×495**、margin-top **56px**、**padding-left 240px**（桌機；transition padding-inline-end .5s cubic-bezier(.2,.8,0,1)）、background **rgb(241,241,241)**、**border-radius 12px 12px 0 0**。#AppFrameScrollable **784×495**@240,56、background **rgb(251,251,251)**。div[class*="_Content_semjk"] **768×495**@240,56、**radius 12px**、transition opacity .05s（784−768 = **16px 捲軸溝槽**）。div[class*="_GlobalRibbonContainer"] 784×0@240,551（本店無 ribbon）。div[class*="_BottomBar_ejstq"] position fixed、z-index 518、gap 8px、transition transform .25s cubic-bezier(.25,.1,.25,1)。z 階：頂欄 517 < SkipLink / BottomBar / Polaris-Backdrop 518。 | — |
| 15 | **內容區（頁面容器）** | 🔴 **main.page 的 max-width 計算值 = none**（1024 下實測；水平約束改由內部 s-page-layout grid 以 --pg-layout-width-primary-max 41.375rem / -secondary-max 20rem 承擔）。main.page 寬度 = 內容區寬（1024→768、768→512、390→374），**padding: 16px 0**（⇒ **內容頂部間距 16px**，頁面標題 h1 頂緣落在 y=72）。s-grid ⟶ span.grid padding **0 16px 12px**（⇒ **左右內距 16px**、header 下方 12px）。div.header 高 **40px**、div.header-content 高 28、**gap 8px**、左緣 x=256（＝240+16）。頁標題 h1「Analytics」80.3×24@278,74：**fs 18px / fw 600 / lh 24px / color rgb(48,48,48) / letter-spacing -0.14994px**（x=278 是因標題前有頁面圖示）。🔴 **內容區字重基線在此重置為 450**（main.page computed fw = 450），而外框（body/AppFrame/nav/topbar）是 **500**。卡片：section.card / section.section **radius 12px、padding 16px、background #fff、box-shadow ＝ --p-shadow-100 六層堆疊**；**卡片之間水平與垂直間距一律 16px**（Analytics 三欄實測 x=256/507/757，pitch 251 − 卡寬 235 = 16；y=698→968，698+254=952，968−952 = 16）。 | — |
| 16 | **響應式 · 主斷點（實測邊界）** | 🔴 **外框只有一個斷點：768px（＝根字級 16px 下的 48em），且 768 屬桌機側**。逐點實測：W=768 → navW **240**、mainPaddingLeft **240px**、matchMedia('(min-width:768px)')=true、'(min-width:48em)'=true；W=767 → navW **0**、mainPaddingLeft **0px**、兩個 matchMedia 皆 false。來回切 768→767→768 無遲滯（hysteresis）。768→767 的一次性變化清單：頂欄 _TopBar gap **24px → 4px**；Shopify logo 容器 _ContextControl **display: block → none**（改出漢堡鈕）；搜尋框 kbd 快捷提示 _Shortcut **flex → none**（_Label「Search」仍 block）；店名 _Details **block → none**（只剩頭像）；dev 徽章**維持 flex 不隱藏**；側欄 240 → 0；main padding-left 240 → 0。767→500→430→390 之間，上述七項**再無任何變化**（單一斷點，無中間階）。 | — |
| 17 | **響應式 · 768 寬（桌機側邊界）** | 頂欄 768×56、深色 rgb(10,10,10) 不變；_LeftContent 仍 **240×56**（logo 常駐）；搜尋框縮為 **262.11×36**@240,10（彈性）；_RightContent 仍 **265.89**@502.11（固定，三顆鈕與 1024 完全相同尺寸）。側欄 **240×542**@0,56 不變、列高 **28px** 不變。main padding-left 240px；#AppFrameScrollable 528、_Content **512**@240（512 = 768−240−16 捲軸溝槽）。main.page 512 寬、padding 16px 0；s-grid padding 0 16px 12px；header-content 480@256。卡片左右仍有 **16px** 內距（Collections 卡 [256,112 480×148] radius 12px）；Analytics 四欄小卡 108 寬、間距 16px。 | — |
| 18 | **響應式 · 390 寬（手機）** | 頂欄仍 **390×56**（**高度不變**）、background rgb(10,10,10)、_TopBar gap **4px**。_LeftContent 縮為 **52×56**：div[class*="_NavigationIcon_1scp5"] 36×56、margin **0 8px**，內含 button aria-label **「Toggle menu」36×36@8,10、radius 12px、padding 0**；_ContextControl **display:none**（Shopify logo 完全隱藏）。搜尋槽 **178.58×36**@52,10，kbd 快捷 display:none、「Search」字樣仍在。右區 159.42@230.58：Sidekick **36×36**@239、Alerts **36×36**@283、店鋪鈕 **55×36**@327（僅頭像，店名隱藏；右緣 382，距視窗 8px），**鈕間距 8px**。側欄收起時 nav 0×0；main 390×542、**padding-left 0**、margin-top 56、radius 12px 12px 0 0；_Content **374**@0（390−16 溝槽）；main.page 374 寬 padding 16px 0；header-content 342@**16**（頁首仍保 16px 內距）。🔴 **卡片改為全出血**：Collections 卡 [0,112 374×164]、Analytics 小卡 [0,187 374×74]（卡片左右 16px 內距消失，radius 12px 保留，垂直間距仍 16px）。 | — |
| 19 | **響應式 · 行動版導航抽屜** | 抽屜 nav **240×542**@0,**56**（自頂欄下緣起、不覆蓋頂欄）；background rgb(235,235,235)；🔴 **border-radius 由桌機的 `12px 0 0` 改為 `12px 12px 0 0`**（兩個上角都圓）。遮罩 div.Polaris-Backdrop **[0,56 390×542]**、background **rgba(0,0,0,0.5)**、z-index **518**（同樣不蓋住頂欄）。🔴 **抽屜內列高放大：a[class*="_Item_xhno8"] 212×36**（桌機 28）＝觸控目標 36px；padding 仍 0 4px 0 8px、radius 8px、z-index 100；ul[class*="_Section_xhno8"] 寬 **224**（桌機 230）、padding 12px 0；_StickyBottomNav 224×**68**（桌機 60）。抽屜寬 240 ≠ token --pg-mobile-nav-width（calc(100vw-2rem-2rem)=326）。 | 開啟以真實點擊觸發；關閉用合成 Escape 事件**無效**（需真實鍵盤或點遮罩），故 Escape 關閉行為未驗證 |
| 20 | **響應式 · 內容卡片「全出血」的第二個門檻（容器級）** | 🔴 **除 768 主斷點外，卡片左右 16px 內距另有一個容器寬門檻**：頁面容器（_Content / _ScrollbarSafeArea / main.page 三者同寬）為 **491px 時卡片 x=16（保留內距）**，為 **490px 時卡片 x=0（全出血）**。對應視窗寬 **507 / 506**（此時側欄已收起、捲軸溝槽固定佔 16px）。逐點證據：W=767→cardX 16；640→16；560→16；520→16；512→16；511→16；508→16；507→**16**；506→**0**；505→0；500→0；390→0。此 490 門檻與 47 §F 斷點階梯中列出的 **490** 數值一致（但 47 記的是 media query 的視窗值，本輪測到的是容器寬）。 | — |

### §5.3 觀察到的視覺規律

1. **56 / 240 是外框的兩個硬骨架數**：頂欄高 56（--pg-top-bar-height 3.5rem）、側欄寬 240（--pg-navigation-width 15rem），而且頂欄左區 _LeftContent 也剛好是 240 ⇒ logo 區右緣、側欄右緣、內容區左緣三者**垂直對齊在同一條 x=240 線上**。我方 AdminShell 必須保住這條對齊線，它是「協調感」的主要來源。
2. **沒有任何分隔線**：頂欄無 box-shadow、無 border-bottom；側欄 ::before/::after 皆 none。所有分界都靠**三層底色階差**：頂欄 rgb(10,10,10) → 側欄 rgb(235,235,235) → 內容區 rgb(251,251,251)（外圍 frame rgb(241,241,241)、最底 chrome rgb(10,10,10)）。再加上 main 的 `12px 12px 0 0` 與 nav 的 `12px 0 0` 圓角，讓內容板像一張「浮在深色底上的圓角紙」。
3. **圓角只用三個值**：12px（頂欄搜尋框、所有頂欄鈕、內容板、卡片）、8px（導覽列項、徽章、dev badge、次要動作鈕、skip link）、4px（分組標題容器、焦點環）。12 = 容器級、8 = 控件級、4 = 焦點環——三階分工乾淨，沒有第四個值。
4. **間距全部落在 4 的倍數**：列高 28、圖示 20、圖示右距 8、列左 padding 8/縮排 36、卡片 padding 16、卡片間距 16、頂欄鈕間距 8、頂欄鈕 36、控件垂直置中留白 10（(56−36)/2）。唯一非 4 倍數是 _ItemWrapper 的 `0 2px 0 10px` 與 slots 的 14px padding／−14px margin（負 margin 補償技巧）。
5. **hover 只改底色，一律不改文字色、不改邊框、不加陰影**（一級導覽項、搜尋框、頂欄三顆鈕全部如此）。唯一例外是**次級（子）導覽項 hover 會把文字由 rgb(97,97,97) 提到 rgb(48,48,48)**——因為它靜態就是次要色，需要 hover 補回可讀性。
6. **深淺兩套 hover 收斂到單一值**：頂欄（深色域）所有可點控件 hover 後底色一律 **rgb(34,34,34)**（搜尋框由 rgb(40,40,40) 變暗、透明鈕由透明變出來）；側欄（淺色域）hover 一律 **rgb(241,241,241)**、selected 一律 **rgb(250,250,250)**。每個色域只有一個 hover 色、一個 selected 色。
7. **選中態＝只換底色**：selected 不加左側指示條、不加粗、不換字色、不換圖示色。實測 `Polaris-Text--semibold`（選中）與 `Polaris-Text--medium`（未選中）**computed font-weight 都是 500**，兩者視覺上完全同重。真正的層級指示改用**樹狀連接線 SVG（#B5B5B5，21×28，left:8px）**，只在群組展開時畫父項豎線＋選中子項的 └。
8. **焦點環是 outline + ::after box-shadow 雙軌並用**：元素 `outline: 2px solid rgb(0,91,211); outline-offset: 1px`，同時 `::after` 的 box-shadow 由 spread **-1px（常駐但隱形）** 變為 **spread 2px**、radius 4px、四邊 inset -1px。⇒ 環是**預先鋪好、只改 spread**，所以不會觸發 layout。焦點色 rgb(0,91,211) ＝ --p-color-border-focus #005bd3，與 --p-color-text-link 同值。
9. **陰影一律是多層堆疊**（--p-shadow-100/200/300/400 各 6–7 層），且**每一階最後一層固定是 `0 0 0 1px #0000000f` 的髮絲外框** ⇒ 卡片不用 border，靠陰影最後一層當邊。這與 64 號記的「六層堆疊」一致。
10. **外框與內容用不同的字重基線**：body / AppFrame / topbar / nav computed font-weight = **500**；內容區 s-internal-page main.page 重置為 **450**。而 token 階是 450/550/600/650——**500 不在 token 階上**。因此 nav 標籤的 500 不是 --p-font-weight-medium(550)，而是 body 繼承下來的值。
11. **外框只有一個斷點（768px / 48em）**，767 與 390 之間頂欄與側欄形態零變化。斷點以 em 書寫（根字級 16px 時 48em = 768px），符合 47 §F。真正的「多階」發生在**內容層**：卡片內距在容器寬 490/491 處再切一次（全出血 ↔ 16px），這是容器尺度而非外框尺度。
12. **行動版只放大列高、不放大字**：抽屜列高 28 → **36**（+8，觸控目標），但字級仍 13px、圖示仍 20px、radius 仍 8px。頂欄高度 56 完全不變，只是把 logo 換成 36×36 漢堡鈕、隱藏 kbd 提示與店名。
13. **遮罩與抽屜都從 y=56 起算**：Polaris-Backdrop 是 [0,56 W×H]，不蓋頂欄；抽屜 nav 也自 56 起。⇒ 頂欄在行動版是**永遠可操作的固定層**，這一點決定了 z 階（頂欄 517 < backdrop 518 但 backdrop top=56）。
14. **捲軸溝槽以 16px 固定預留**：內容側 #AppFrameScrollable 784 vs _Content 768；側欄側 nav 240 vs 內部 section 230（scrollbar-gutter: stable）。⇒ 版面寬度計算要先扣 16，否則我方會比本尊寬 16px。
15. **Web Component 是主要載體**：`s-internal-theme-provider`（含 p-partial-theme-dark 局部深色）、`s-internal-page`、`s-internal-scroll-box`、`s-internal-icon`、`s-internal-badge`、`s-internal-text`、`s-avatar`、`s-grid`、`s-section` 全部把真正帶樣式的節點藏在 open shadow root 裡，宿主多為 `display: contents`（getBoundingClientRect 為 0×0）。量測與我方對照時必須穿透，否則會誤判「這個元素沒有樣式」。

### §5.4 🔴 與既有量測文件的衝突（照登記，未逕行覆寫）

1. **與 47 §F 一致、可交叉確認（非衝突）**：主斷點 768px / 48em、側欄常駐 240px、頂欄高 56px 三項本輪逐 px 實測結果與 47 完全相同（47 line 234/237、§F line 331）。本輪另補上「768 屬桌機側、767 已收合、來回無遲滯」的邊界歸屬，47 未記。

2. **47 §F 的 490 斷點需要改寫射程**：47 把 490 列為斷點階梯 8 階之一（line 345），並拿它與我方 429 的手機大斷點對比。本輪實測顯示 490 這個數在**內容容器寬**上生效（容器 490 → 卡片全出血、491 → 16px 內距），對應的**視窗寬是 506/507 而非 490**。⇒ 我方原型若照 47 把 490 當視窗斷點抄，會在 490–506 這 17px 區間與本尊形態相反。判準掛在視窗還是容器上本輪未取得（見 not_obtained），但「490 不等於 490px 視窗」這件事已被實測證偽。

3. **47 line 16「主區佔滿全寬、main 從 x=0 起算、導航疊在其上」是收合態的觀察，不適用桌機態**：47 當時視口 682.67px（<768）。本輪 1024 實測 main#AppFrameMain 是 `padding-left: 240px`（不是導航疊在 main 上），側欄與內容**並排不重疊**；只有 <768 時 padding-left 才變 0、側欄改成 240px 抽屜＋rgba(0,0,0,0.5) 遮罩疊上。47 line 192「main 從 x=0 起算、導航疊在其上」若被讀成桌機規則會做錯佈局。

4. **64 §5 的 V-127（焦點環外層盒未量到）本輪可結案（至少對導覽項）**：64 記「input 上沒有焦點環，真正承載焦點環的節點沒量到」。本輪量到承載者是**兄弟 pseudo-element**：`a[class*="_Item_xhno8"]::after` 常駐一個 box-shadow `rgb(0,91,211) 0 0 0 -1px`（spread 負值故隱形），:focus-visible 時 spread 改為 **+2px**，radius 4px、四邊 inset -1px；同時元素自身 outline 由 `3px none` 變 `2px solid rgb(0,91,211)`、outline-offset 1px。這同時佐證 47 §H2-3′「outline 與 box-shadow 並用」。

5. **64 §00.11 的四階字重（450/500/550/600）在導航區需要補一條例外**：64 把 500 歸給「Pill、主要按鈕」。本輪實測 **body 的 computed font-weight 就是 500**，而外框（topbar/nav）全部繼承它；內容區才由 s-internal-page main.page 重置回 450。更關鍵的是：導覽選中項掛 `Polaris-Text--semibold`、未選中掛 `Polaris-Text--medium`，但**兩者 computed font-weight 都是 500**（全頁只有 1 個 semibold 節點、19 個 medium 節點，全部 500）。⇒ 若我方照 token 表把 medium 做成 550、semibold 做成 600，導覽列會比本尊粗、且會多出一個本尊沒有的選中/未選中粗細差。

6. **token --pg-mobile-nav-width 與實測抽屜寬不符**：token 值 calc(100vw - 2rem - 2rem)（390 下 = 326px），但 390 實測抽屜 nav 實際寬度是 **240px**。⇒ 該 token 未作用於本次觀察到的行動版導航（可能屬另一個元件或已停用）。我方應照實測 240，不照 token。

### §5.5 未取得（鐵律 19.3）

- **1280 寬度的桌機量測**：本機 screen 只有 1024×768（availHeight 728），且 mcp resize_window 對此視窗一律失敗（chrome.windows 判定視窗離屏，window.screenX = -32000）。取得方式：換一台 ≥1280 實體解析度的機器，或改用支援 CDP Emulation.setDeviceMetricsOverride 的瀏覽器工具重跑同一段 getComputedStyle 腳本。桌機值全部以 innerWidth=1024 記錄。
- **內容區在 >1024 是否出現 max-width 收斂**：1024 下 main.page 的 max-width computed = none，但 --pg-layout-width-primary-max = 41.375rem(662px) 與 --pg-layout-width-secondary-max = 20rem(320px) 顯示兩欄版面在更寬視窗會停止長大。實際生效寬度與置中方式未取得（需 1280/1440 實測）。
- **側欄內部捲動後 _StickyBottomNav 的 box-shadow / border-top 變化**：該元素宣告了 `transition: box-shadow .35s, border-top .35s`，代表捲動時會出現上邊界。但實測 `#scroll-container`（s-internal-scroll-box ⟶ shadowRoot ⟶ s-box ⟶ shadowRoot ⟶ div#scroll-container）scrollHeight 758 > clientHeight 495 卻**捲不動**：滑鼠滾輪（120,300 與 120,400 各 3–5 格）與程式 `scrollTop = 300` 皆維持 scrollTop=0（賦值後同步讀回仍是 0）。取得方式：改用 keyboard（Tab 到底部項讓瀏覽器自動捲）或在更矮的視窗（innerHeight < 400）重試。
- **所有元件的 :active（按下）態**：Chrome 的 :active 只由真實輸入觸發，合成事件無效，而按下並保持的同時無法取值。可見線索是 DOM 裡存在 `div[class*="_Pressed_ir1fb"]` 包裹層（頂欄鈕）。取得方式：需支援 CDP Input.dispatchMouseEvent(mousePressed) 後不放開再取樣的工具。
- **disabled 態**：頂欄與側欄在本店狀態下沒有任何 disabled 控件（導覽項是 <a>，無 disabled 屬性），無法量。取得方式：找一個方案受限／權限不足的帳號或商店狀態再測。
- **頂欄搜尋框的 focus / 展開面板態**：為避免開啟全域搜尋面板（另一代理正在量彈層），未點擊，focus 與展開後的尺寸／陰影未取得。
- **Shopify logo 的 hover 效果量值**：img0 宣告 `transition: transform .2s, filter .3s` 且 filter 靜態值為 grayscale(0)，但未 hover 取樣變化後的 transform/filter 值。
- **行動版抽屜以 Escape 關閉的行為**：合成 KeyboardEvent 不觸發，未驗證。抽屜關閉改以再次點擊 Toggle menu 完成。
- **卡片 490/491 門檻究竟是 media query 還是 container query**：只量到「容器寬 490 → 全出血、491 → 16px 內距」（對應視窗 506/507）。無法從 computed value 分辨判準掛在視窗還是容器上（依規定未讀樣式表原始碼）。取得方式：在有側欄（≥768）的情況下把內容容器擠到 490 附近觀察（例如開啟 356px 的右側 Sidekick 面板）即可分辨。
- **深色主題（p-theme-dark）下的整套外框值**：本次 html.p-theme-light、prefers-color-scheme: dark = false，未切換主題。
