# 42 — 前台全站頁面與交互完整清單（Storefront Full Inventory）

> 目的：把 Shopify 買家前台（Storefront）＋結帳（Checkout）＋客戶帳戶（Customer Accounts）的**每一頁、每一區塊、每一個交互**寫成可直接建高保真原型的規格。方法＝Dawn 原始碼結構（jsDelivr 逐檔清單）＋ help.shopify.com / shopify.dev 官方文檔查證（2026-08）＋ 24 號 checkout 實測＋台灣本地平台（SHOPLINE/ECPay）文檔。**我們現況**：`docs/design/chilllove-storefront-preview.html` 只有首頁（hero/分類/精選/商品格/品牌故事）＋購物袋 drawer＋toast——其餘全部要補。銜接：篩選與主題引擎見 03/25/26/31、結帳行為設定見 24 §5–6、多語多幣見 29、SEO 義務見 30 §9、API 契約見 28。

## 0. 頁面總表

| # | 頁面 | 路徑（慣例固定） | Dawn template/section | 我們現況 |
|---|---|---|---|---|
| P01 | 首頁 | `/` | index.json | **有**（5 sections，設定項不全） |
| P02 | 系列頁 | `/collections/{handle}`（`/collections/all` 全商品） | main-collection-banner + product-grid | 缺 |
| P03 | 系列清單 | `/collections` | main-list-collections | 缺 |
| P04 | 商品頁 | `/products/{handle}`（`?variant={id}`） | main-product + related | 缺 |
| P05 | 購物車頁 | `/cart` | main-cart-items + main-cart-footer | 缺（僅 drawer） |
| P06 | 購物袋 drawer | 覆蓋層（任何頁） | cart-drawer | **有**（無 note/折扣/免運條） |
| P07 | 結帳 | `/checkouts/{token}`（平台渲染，非 theme） | — | 缺 |
| P08 | 感謝頁 | `/checkouts/{token}/thank_you` | — | 缺 |
| P09 | 訂單狀態頁 | `/account/orders/{token}`（結帳網域） | — | 缺 |
| P10 | 搜尋結果頁 | `/search?q=&type=&sort_by=` | main-search | 缺 |
| P11 | Predictive search 覆蓋層 | `/search/suggest(.json)` | predictive-search | 缺 |
| P12 | 登入 | `/account/login`（新版：`account.{domain}`） | main-login | 缺 |
| P13 | 註冊 | `/account/register`（新版無此頁） | main-register | 缺 |
| P14 | 忘記密碼/重設 | `/account/recover`→`/account/reset` | main-reset-password | 缺 |
| P15 | 帳戶啟用 | `/account/activate` | main-activate-account | 缺 |
| P16 | 帳戶總覽（訂單列表） | `/account` | main-account | 缺 |
| P17 | 訂單詳情（帳戶內） | `/account/orders/{id}` | main-order | 缺 |
| P18 | 地址管理 | `/account/addresses` | main-addresses | 缺 |
| P19 | 自助退貨流程 | 新版帳戶/訂單狀態頁內 | — | 缺 |
| P20 | 部落格列表 | `/blogs/{handle}`（`/tagged/{tag}` 篩選） | main-blog | 缺 |
| P21 | 文章頁 | `/blogs/{blog}/{article}` | main-article | 缺 |
| P22 | 靜態頁 | `/pages/{handle}` | main-page | 缺 |
| P23 | 聯絡頁 | `/pages/contact`（page.contact 模板） | contact-form | 缺 |
| P24 | 政策頁 ×4+ | `/policies/{refund\|privacy\|terms-of-service\|shipping}-policy` | 平台自動生成 | 缺 |
| P25 | 404 | 任意不存在路徑 | main-404 | 缺 |
| P26 | 禮品卡顯示頁 | `/gift_cards/{token}` | gift_card.liquid | 缺 |
| P27 | 密碼頁 | 全站鎖定時任意路徑 | password.json | 缺 |
| P28 | 人機驗證頁 | `/challenge` | 平台渲染 | 缺 |
| P29 | Cookie 同意橫幅 | 覆蓋層 | 平台注入 | 缺 |
| P30 | 全域 header/footer | 每頁 | header-group / footer-group | **部分**（無 mega menu/搜尋/帳戶/選擇器） |

> 補充覆蓋層（不佔路徑）：quick add modal、pickup availability drawer、媒體 zoom/lightbox、分享 popover、age gate（app 慣例）、返貨通知表單（app 慣例）。Dawn 55 個 sections 中「main-*」對應上表各頁主體；非 main 的（slideshow/collage/multicolumn…）＝首頁與任意頁可插 sections（§2）。

---

## 1. 全域元素（每頁共有）

### 1.1 Header（header-group：announcement-bar + header）

佈局（桌機）：公告列（全寬色帶）→ header 列（logo｜主導航｜工具區 icon 群：搜尋、帳戶、購物袋）。Dawn 提供 logo 位置（左/中）與選單位置（logo 下方/旁邊）設定；手機收合為「☰ drawer＋置中 logo＋搜尋/袋」。

| 控件 | 功能 | 邏輯（含數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 公告列 announcement bar | 促銷/免運訊息 | blocks：每則文字+連結；多則時可設自動輪播（autoplay 間隔秒數設定，Dawn 預設關）；可加社群 icon、國家/語言選擇器開關 | 點文字→連結；多則時左右箭頭切換 | 無內容不渲染；輪播需可暫停（a11y） |
| Logo | 回首頁 | image_picker + 寬度 range（Dawn 50–300px，預設 100）；未上傳→shop.name 文字 | 點擊→`/` | SVG/PNG 皆可；密碼頁沿用 |
| 主導航（下拉） | 一層選單 hover/點擊展開子層 | menu 來源＝linklists[handle]；巢狀≤3 層；子層以 dropdown 顯示 | hover 或 click 展開（點擊模式 aria-expanded 切換）；Esc 收合 | 空選單不渲染；第三層在 dropdown 內縮排 |
| Mega menu | 二層以上大面板 | Dawn header 設定 `menu_type_desktop: dropdown/mega/drawer`；mega＝全寬面板，欄＝第二層、欄內連結＝第三層 | hover 展開全寬面板；焦點循環 | 僅桌機；手機一律 drawer 手風琴 |
| 搜尋 icon | 開 predictive search | 點擊展開 modal/整列（§8.1） | icon→輸入框自動聚焦 | 無 JS 時 fallback 到 /search 表單 |
| 帳戶 icon | 進帳戶或登入 | `customer` 存在→`/account`；否則 `/account/login`；新版帳戶一律指向登入端點（自動判斷） | 點擊跳轉 | 商店關閉帳戶功能時隱藏 |
| 購物袋 icon + badge | 開 cart drawer 或 /cart | badge＝`cart.item_count`（>99 顯示 99+ 慣例）；cart type 設定決定點擊行為（drawer/page） | 加購後 badge 即時更新（Ajax sections 回傳 cart-icon-bubble 局部替換） | count=0 可隱藏 badge；aria-label「購物車，N 件」 |
| Sticky header | 捲動時固定 | Dawn 選項：none / on-scroll-up / always / always+縮小 | 上捲出現、下捲隱藏（on-scroll-up） | 與公告列組合時僅 header 黏性 |
| 國家/幣別、語言選擇器 | 切市場/語言 | `{% form 'localization' %}`；選項>1 才顯示（29 §4） | 開下拉→選國家→submit→頁面以新幣別/前綴重載 | 結帳內不可切幣；爬蟲不重導 |

### 1.2 Footer（footer-group）

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 選單欄 blocks | 多欄連結 | block 型別：link_list（選 menu）/ text（標題+富文本）/ image；欄數自適應 | 點連結跳轉 | 手機摺疊為手風琴（主題選項） |
| Newsletter 訂閱 | 收 email 行銷名單 | `{% form 'customer' %}` + `contact[tags]=newsletter`；成功→customer 記錄 marketing consent（single opt-in；可設 double） | 輸入 email→送出→inline 成功訊息「感謝訂閱」 | 重複訂閱回同樣成功訊息（不洩漏是否存在）；hCaptcha 保護 |
| 付款圖示列 | 展示可用付款方式 | 讀 `shop.enabled_payment_types` 自動輸出 SVG icon 序列 | 純展示 | 依市場不同（台灣：Visa/MC/JCB/LINE Pay…） |
| 社群 icon | 連社群 | theme settings 逐平台 URL；空值不顯示 | 新分頁開啟 | — |
| 選擇器（幣別/語言） | 同 1.1 | 慣例放 footer 左下 | — | — |
| 版權/政策列 | 法務連結 | 自動輸出 © {year} {shop.name}＋政策頁連結（有內容才列） | — | 「Powered by」我們換成自有品牌可關 |

### 1.3 Cookie 同意橫幅（P29）

平台注入（非 theme section）。邏輯：**先同意後追蹤**——受規範地區（自動偵測 EEA/UK，可手選地區）未同意前不落非必要 cookie、不發 marketing/analytics pixel。前置條件：已發布隱私政策。

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 橫幅本體 | 首次到訪顯示 | 位置（下橫幅/左下卡/右下卡）、顏色、圓角可設；連隱私政策 | 進站→顯示；選擇後寫 consent cookie 不再顯示 | 非規範地區可設「不顯示、預設允許」 |
| 接受全部 / 拒絕 | 一鍵決定 | 接受＝analytics+marketing+preferences 全 true；拒絕＝全 false（essential 恆開） | 點擊→橫幅關閉→補發被緩存的 pixel（僅接受時） | 拒絕後分析數據缺口屬正常 |
| 管理偏好 | 分類細選 | modal 列 4 類：必要（鎖定開）、分析、行銷、偏好；逐類 toggle | 開 modal→切換→儲存 | 之後可從 footer「Cookie 偏好」連結重開 |
| 資料販售退出頁 | 美加州 CPRA | 獨立頁「Do not sell or share my personal data」opt-out 開關 | footer 連結進入→切換→確認 | 僅對法規地區訪客有意義 |

### 1.4 密碼頁（P27）

全站上鎖（Preferences 開 password protection）時，所有路徑都渲染 password template；解鎖 cookie 有效期內不再問。佈局：置中 logo → 「Opening soon」標題 → 商家自訂訊息（Preferences 內填）→ newsletter 訂閱表單 → 「Enter using password」連結 → 點開後密碼輸入框＋送出 → footer 「Are you the store owner? Log in here」。密碼錯誤 inline 錯誤訊息；成功→寫 cookie→轉入首頁。SEO：整站回 200 但 noindex（上鎖期間不收錄）。

### 1.5 Age gate（Shopify 無原生，app 慣例；我們平台補充項）

慣例規格：全螢幕 overlay（背景模糊）＋二選一（「我已滿 18 歲」/「未滿」）或生日輸入（年/月/日三下拉）；通過→localStorage/cookie 記 30 天；未過→導去 google.com 或顯示阻擋文案；SEO：對爬蟲 UA 不顯示（否則全站內容被遮）；每市場可獨立開關（酒類僅特定國家需要）。

### 1.6 全域覆蓋層與 a11y 基線

- 三種覆蓋層：modal（置中、veil 點擊關）、drawer（左/右滑入，購物袋右、手機選單左）、toast/notification（右上角 3–5 秒自動消失）。共通：Esc 關閉、focus trap、關閉後焦點還原至觸發元素。
- Dawn 專設 `cart-live-region-text` section：購物車變動以 `aria-live=polite` 播報（「購物車 N 件、小計 NT$x」）——我們照抄此機制。
- Skip to content 連結（focus 時可見）；所有 icon 按鈕帶 aria-label；`prefers-reduced-motion` 時停用輪播自動播放與視差。

---

## 2. 首頁（P01）— section 全集

首頁＝index.json 的 sections 自由組合（≤25 sections/模板、Dawn 每 section ≤50 blocks、每模板 blocks 總量 ≤1,250）。下表＝Dawn 內建可加 sections 全集（= theme editor「Add section」清單）＋各自設定項與交互。Horizon 世代再加：巢狀 blocks（block 內含 blocks）、跨頁複製貼上 section、AI 生成 section/block——原型可先不做 AI，僅留巢狀資料結構。

| Section | 用途與佈局 | 主要設定項（含數值） | 交互邏輯 |
|---|---|---|---|
| image-banner（hero） | 滿版 1–2 張圖疊文字盒 | 圖1/圖2、高度 small/medium/large/自適應、文字盒位置（九宮格）、桌機/手機各自對齊、疊加透明度 0–100%、blocks：heading/text/buttons（≤2 顆） | 按鈕→連結；圖片 lazyload 首屏例外（LCP） |
| slideshow | 輪播 banner | 每 slide＝圖+heading+subheading+button；自動輪播開關+間隔 3–9 秒；分頁樣式（圓點/計數器）；高度同上 | 左右箭頭+圓點；hover/focus 暫停；swipe 支援 |
| rich-text | 置中文字區 | blocks：heading/caption/text/button；寬度 full/page；對齊 | — |
| featured-collection | 精選系列商品列 | 選 collection、顯示數 2–25（預設 4）、欄數桌機 1–6/手機 1–2、「View all」開關（超過顯示數才出現）、輪播開關（桌機橫滑）、商品卡設定（見 §3.3）、快速加購開關 | 卡片→商品頁；quick add（§3.4）；View all→系列頁 |
| collection-list | 系列卡格線 | blocks：每 block 選一 collection（圖+標題）；欄數 1–5；「View all」 | 卡→系列頁 |
| featured-product | 單品完整購買卡 | 同商品頁資訊 blocks 子集（price/variant picker/quantity/buy buttons/share）；可選是否連去商品頁 | 變體切換與加購邏輯同 §4，直接在首頁完成 |
| collage | 拼貼（1 大 2 小） | blocks：image / product card / collection card / video；佈局左大/右大 | 各卡各自跳轉；video 卡點擊開 modal 播放 |
| image-with-text | 圖文對排 | 圖、圖高、圖位置（左/右）、blocks：heading/text/button；可疊加內容於圖上 | — |
| multicolumn | 多欄圖文（特色/USP 列） | blocks ≤N 欄：圖+標題+文字+連結；欄寬 1/3 1/4…；圖比例 adapt/portrait/square/circle；背景卡開關 | 手機可設橫滑 |
| multirow | 多列圖文交錯 | blocks：每列圖+heading+caption+text+button；圖文左右交錯自動 | — |
| video | 影片區 | 來源：自傳 video 或 YouTube/Vimeo URL；封面圖；全寬開關；自動播放（靜音）開關 | 點封面→載入播放器；自動播放時無控制列+循環 |
| featured-blog | 最新文章列 | 選 blog、顯示篇數 2–4、顯示圖/日期/作者開關 | 卡→文章頁 |
| collapsible-content | FAQ 手風琴 | blocks：每條 heading+richtext（或引 page）；佈局（無容器/列卡）；可搭配圖 | 點列展開/收合（多開允許）；aria-expanded |
| newsletter / email-signup-banner | 訂閱區（純色/背景圖兩款） | heading/text/email 表單；banner 款可疊圖 | 同 1.2 newsletter |
| contact-form | 聯絡表單（可插任何頁） | 見 §10.2 | — |
| custom-liquid | 商家自寫 Liquid/HTML | 一個 code textarea | 渲染輸出（沙箱：不允許 script 外掛平台白名單外資源——我們的規則） |
| page | 引用某靜態頁內容 | 選 page | — |
| apps | app blocks 容器 | 承載第三方 app 區塊 | — |
| 慣例補充（非 Dawn 內建，常見於 Horizon/付費主題；原型列為 P2 sections） | logo 列（媒體報導）、評價輪播（testimonials）、倒數計時、Instagram feed、icon 徽章列（免運/保固/退貨）、最近瀏覽、scrolling text 跑馬燈 | 各自 blocks | — |

SEO/a11y：首頁輸出 Organization JSON-LD（含 logo/sameAs 社群、全站退貨運費宣告，30 §9）；h1＝首個 heading；輪播圖首張不 lazy；section 間 heading 層級遞降不跳級。

---

## 3. 系列頁（P02）與系列清單（P03）

### 3.1 佈局

main-collection-banner（系列圖+標題+描述，可關）→ 工具列（篩選入口＋排序＋結果數）→ 商品格線（桌機 2–4 欄設定、手機 1–2 欄）→ 分頁。篩選 UI 兩型態：**桌機橫列**（工具列上一排下拉 pill）或**側欄直排**（手風琴組）；手機一律「Filter and sort」按鈕開全高 drawer。

### 3.2 篩選系統（Search & Discovery 供給，全部查證值）

- **來源全集**：標準＝Availability（有貨/無貨）、Price（區間）、Category（分類樹）、Product type、Vendor、Tags；自訂＝變體選項（Size/Color…）、product/variant/category metafields、分類標準屬性（taxonomy attributes 自動生成）。每個來源只能建一個 filter。
- **上限**：每店 ≤**25 filters**；前台每 filter 顯示 ≤**100 值**（app 內可管理至 1,000）；值分組（group）每組 ≤**200 原值**、全店 ≤**1,000 組**。**系列 >5,000 商品或搜尋結果 >100,000 時自動隱藏全部篩選**。
- **商家可調**：改顯示名（label）；把相近值合併成組（「Navy+Midnight→深藍」）；排序（字母/數字自動或手動）；同 filter 內多值邏輯 **OR（預設）或 AND**（filter 之間恆 AND）；空值處理（隱藏/排最後/照預設）；視覺樣式——色票 swatch/圖樣/圖片（值綁 metaobject 的 color/image 欄位）。
- **翻譯**：label/值/組可翻；tag 與 vendor filter 只顯示預設語言（29 號翻譯層對接時注意）。
- **URL 合約**（25 號相容層已定）：`filter.v.availability=1`、`filter.v.price.gte=500&filter.v.price.lte=2000`、`filter.p.product_type=`、`filter.p.vendor=`、`filter.v.option.color=`、`filter.p.m.{namespace}.{key}=`；多值＝重複參數。

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| Filter 群（下拉/手風琴） | 逐維度收窄 | 每值旁計數 `(N)`＝套用其他已選 filter 後的命中數；選中即時（Ajax 重取 grid section）或按 Apply（drawer 模式） | 勾選→URL 追加參數→grid+計數+分頁更新（無整頁重載，Section Rendering API） | 值計數為 0 仍顯示但灰化（或依設定隱藏）；badge 上限 100 值截斷 |
| Price 區間 | 金額上下限 | 兩個數字輸入（min/max，幣別符號前綴）；range slider 為主題加值；邊界＝該系列最高價 | 輸入失焦或放開滑桿→套用 | 換市場幣別時區間以 presentment 幣別重算 |
| 已套用 chips 列 | 顯示與移除 | 每個作用中值一顆 chip ×；「Clear all」清空 | 點 ×→移除該參數 | chips 換行不截斷 |
| 排序下拉 | 全集 8 值 | `sort_by=manual`（Featured）/`best-selling`/`title-ascending`/`title-descending`/`price-ascending`/`price-descending`/`created-ascending`/`created-descending`；預設＝系列設定的排序 | 選→URL 更新→grid 重渲染 | 手動排序僅 manual 系列有意義 |
| 結果數 | 「N 項商品」 | ＝篩選後總數 | 隨篩選更新（aria-live） | 0 結果→空狀態：「無符合商品」＋清除篩選按鈕 |
| 分頁 | paginate 標籤 | 每頁數量＝section 設定（Dawn 8–24，預設 16；上限 50/頁）；頁碼＋上下頁箭頭 | `?page=N`；捲動回頂 | **無限捲動/Load more 為主題加值**（原型做「Load more＋自動觸底載入」開關；SEO 必須保留 ?page URL 可爬） |

### 3.3 商品卡（card-product，全站復用：系列/搜尋/推薦/精選）

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 主圖 | 商品識別 | 比例 adapt/portrait/square；**hover 換第二張圖**（設定開關） | 點卡任意處→商品頁 | 無第二圖不動；觸控裝置無 hover |
| Badge | 狀態標 | `Sale`（compare_at>price，任一變體）與 `Sold out`（全變體無庫存）；位置左下/右下 | — | 兩者同真時 Sold out 優先 |
| 標題+vendor | 文案 | vendor 顯示開關 | — | 兩行截斷 ellipsis |
| 價格 | 金額 | 區間顯示「NT$590 起」（變體價不同時）；促銷＝劃線原價+紅色現價；隱藏文字「Regular price/Sale price」給讀屏 | — | 多幣別＝presentment 幣（29）；零小數幣不出小數 |
| 評分列 | 星等 | 讀 reviews metafield（`reviews.rating`/`rating_count`）；無值不渲染 | — | app 供給資料 |
| 色票列 | 變體色預覽 | Horizon 世代卡片 block：color swatch ≤N 顆+「+3」溢出 | 點色票→帶 `?variant=` 進商品頁（或卡內換圖） | swatch 需 metaobject 色值 |
| Quick add | 不進商品頁加購 | 單變體商品：「＋/Add」直接 POST `/cart/add.js`；多變體：開 **quick add modal**（縮圖+價格+variant picker+數量+Add；「View full details」連結） | 成功→cart drawer 彈出或 toast＋badge 更新 | 售罄卡不顯示；modal 內邏輯完全復用 §4 變體規則 |

### 3.4 系列清單頁（P03）

`/collections` 全系列卡格線：圖（系列圖或首商品圖）＋標題；排序按字母/手動；無描述。SEO：此頁 self-canonical；系列卡圖 alt＝系列名。

SEO/a11y（P02）：self-canonical 含 ?page（facet 參數在 robots.txt disallow，30 §9）；空 facet 組合回 404（禁 soft-404）；BreadcrumbList JSON-LD（首頁>系列）；篩選 drawer focus trap；排序下拉為原生 select（鍵盤友善）；grid 為 `<ul>` 列表語義。

---

## 4. 商品頁（P04）——最重

### 4.1 佈局

桌機兩欄：左媒體 gallery（約 55–60%）＋右資訊欄 sticky（捲動時固定）；手機上下堆疊（gallery 先）。右欄＝**可排序 blocks**（theme editor 拖曳）：text（vendor/SKU 自選）→ title → price → 評分 → variant_picker → quantity_selector → buy_buttons → pickup_availability → description → share → collapsible_tab ×N → complementary → icon 徽章/自訂 liquid/app blocks。頁尾接：related-products section＋（慣例）最近瀏覽。

### 4.2 媒體 gallery

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 主媒體區 | 圖/影片/3D | 型別：image / video（自傳）/ external_video（YT/Vimeo）/ model（GLB 3D）；佈局：stacked（直排全出）/ 兩欄 / thumbnail（主圖+縮圖列）/ thumbnail_slider | 縮圖點擊或左右箭頭切換；手機橫滑+圓點 | 混型別排序照商家後台順序 |
| 縮圖列 | 導航 | 當前縮圖 aria-current；>N 張時縮圖列自身可滑 | 點縮圖→主區切換（滑動動畫） | 僅 1 張媒體→不顯示縮圖 |
| Zoom | 放大 | 設定：lightbox（點開全螢幕 modal，可再 pinch/滾輪放大）/ hover 放大鏡 / none | 點圖→lightbox：上下頁箭頭+關閉 ×+滑動 | 觸控＝雙指縮放；Esc 關閉 |
| 影片 | 播放 | 封面帶播放鈕；設定 autoplay（靜音循環）開關 | 點播放→就地播放（external 載入 iframe） | reduced-motion 不自動播 |
| 3D model | AR 檢視 | model-viewer 元件：拖曳旋轉/滾輪縮放；行動裝置「View in your space」AR 按鈕 | 點 AR→系統 AR Quick Look/Scene Viewer | 不支援裝置隱藏 AR 鈕 |
| 變體聯動 | 切變體跳圖 | 變體綁 media→選中時主區捲至該媒體；Horizon 支援「依選中色只顯示該色媒體組」（media 依 alt 前綴分組慣例） | 變體切換→gallery 滾動/過濾 | 變體無綁圖不動 |

### 4.3 變體選擇器（核心交互）

資料模型：≤3 個 options（Color/Size/Material…）、每商品 ≤2,048 變體（2026 上限；option 值筆數不限但 UI 上限見下）。兩種控件（theme setting 或逐 option 自動）：**pills 色塊/按鈕組**（radio 群，色票 swatch 用 metaobject 色值/圖）或 **dropdown**（原生 select）。

**狀態三分**（查證 Dawn/Horizon 行為，這是原型必做的狀態機）：

1. **可購**：正常可選。
2. **售罄（sold out）**：該組合存在但無庫存且不允許缺貨下單→pill 淡化+斜線（或標籤「售罄」），仍可選中；選中後 buy 按鈕變 `Sold out` disabled。主題設定可改為「隱藏」或「灰化不可選」——三種表現：**劃線可選（預設）/ 灰化禁選 / 直接隱藏**。
3. **不存在（unavailable）**：該組合根本沒建變體→依設定隱藏或劃線；選中其他 option 時即時重算各值狀態。

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| Option 群組 | 逐維選值 | fieldset+legend（option 名+當前值）；選中值高亮邊框 | 點值→組合解析→整個 product-info section 以 Section Rendering API 重取（`/products/{handle}?variant={id}&section_id={main-product}`）→替換價格/SKU/庫存/媒體/按鈕/pickup | 首載預設＝`selected_or_first_available_variant`；URL 帶 ?variant 直接選定 |
| 價格區 | 隨變體變 | price＋compare_at（劃線）＋「Sale」badge＋單位價格（unit price，per 100g 等，法規市場）；tax 註記「含稅」依設定 | 變體切換後更新＋aria-live 播報 | compare_at≤price 不顯劃線 |
| SKU/條碼 | 顯示 | text block 可選顯示 `variant.sku` | 切換更新 | 空值隱藏標籤 |
| 庫存文案 | 稀缺提示 | Horizon 慣例 block：>threshold「有貨」綠點；≤threshold（設定 0–10，預設 10）「低庫存：剩 N 件」橙點；0 且可缺貨下單「可預購」；0「售罄」 | 隨變體更新 | 不追蹤庫存→恆「有貨」 |
| 數量選擇器 | quantity | −/輸入/＋；min=1；受 quantity rules（B2B/app：min/max/increment）約束時顯示規則文案 | ±步進；輸入非法值 blur 時夾回 | 上限＝庫存（可選限制）；cart 內已有數量提示「購物車已有 N」 |
| Add to cart | 加入購物袋 | `{% form 'product' %}` POST `/cart/add.js`（id=variant_id, quantity, properties[], selling_plan）；成功→依 cart type：開 drawer / 彈 notification 卡（含商品行+View cart+Checkout 鈕）/ 跳 /cart | 按下→按鈕 loading spinner→成功動畫→aria-live 播報 | 售罄變體＝`Sold out` disabled；未選齊 options＝按鈕禁用或滾至未選組 |
| Buy it now（動態結帳鈕） | 跳過購物車直結 | 無品牌版「Buy it now」→Shopify checkout；品牌版依買家裝置/錢包歷史自動挑一顆（Shop Pay>Apple Pay/Google Pay/PayPal/Amazon Pay/Venmo，商家不可指定）；**僅單一變體 ×N**，不合併購物車 | 點→直入結帳（品牌版直開錢包 sheet） | 與禮品卡收件表單、部分訂閱 app 不相容；只可自訂無品牌版顏色字體 |
| 更多付款方式連結 | 折疊錢包 | 「More payment options」→展開其餘錢包鈕 | — | — |

### 4.4 Pickup availability（門市取貨庫存）

資料：`variant.store_availabilities[]`＝{available, pick_up_enabled, pick_up_time（「通常 2 小時內可取」等字串）, location{name, address{…, phone}}}；location 開啟本地取貨才進陣列；**調貨（store transfer）設定下未備貨門市也可 available**。

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 摘要卡（buy buttons 下方） | 首門市可取狀態 | ✓/✗ icon＋「{門市名} 有現貨可取」＋pick_up_time；副按鈕：單店「View store information」/ 多店「Check availability at other stores」 | 變體切換→JS 重抓 `/variants/{id}/?section_id=pickup-availability` 替換整卡 | 無任何 pick_up_enabled 門市→整卡不渲染 |
| 門市清單 drawer | 全門市狀態 | 標題＝商品名+當前變體；逐門市：名稱、✓有貨/✗無貨、完整地址、電話 | 摘要副按鈕→右側 drawer；Esc/×關閉 | 清單依商家 location 順序 |

### 4.5 貨到通知（back in stock）——原生缺口，我們補平台級

Shopify theme 無原生「Notify me」（Shop app 內才有 restock 提醒；店面靠 app）。我們平台規格（P1）：售罄變體時 buy 區下插「到貨通知我」按鈕→彈 modal（email 預填已登入者/手機二選一＋送出）→寫 `back_in_stock_subscriptions(shop_id, variant_id, channel, contact)`→庫存由 0 轉正的 ledger 事件觸發批次寄送（每 variant 每 contact 只寄一次）；成功文案「到貨時將通知你」。

### 4.6 資訊與信任區塊

| 區塊 | 內容與邏輯 |
|---|---|
| 描述 | `product.description` 富文本；**tabs 或 accordion 二選一**（Dawn＝collapsible_tab blocks 各自 heading+來源（richtext/page/liquid/自動掛 description）；慣例 tabs：描述/規格/尺寸表） |
| 運送與退貨 | collapsible_tab 慣例：引用 shipping policy page 摘要＋「詳見政策頁」連結；台灣版固定加超商取貨說明（§12） |
| 訂閱/複購（selling plans） | 有 `product.selling_plan_groups` 時渲染購買選項卡：radio「單次購買 NT$X」vs「訂閱省 10% NT$Y」＋方案下拉（每 2/4/6 週配送）；價格依 `selling_plan.price_adjustments`（percentage/fixed_amount/price 三型）即時換算；加購時 form 帶 `selling_plan={id}`；cart 行顯示方案名（「每 4 週」）；訂閱管理入口在帳戶（§7.4） |
| 評價區 | 無原生評價系統（官方 Product Reviews app 已退役）：evaluated 慣例＝app block 錨點 `#reviews`（星等分佈長條、排序（最新/最有用）、逐則卡（星/標題/內文/圖/購買驗證 badge）、寫評論表單）；資料經 metafields 供 JSON-LD（30 §9 條 4） |
| 分享 | share block：copy link 按鈕（成功 toast「已複製」）；慣例加 FB/X/LINE 分享 URL（台灣 LINE 必備） |
| 徽章列 | icon blocks：免運門檻/保固/退貨天數，純展示 |

### 4.7 推薦與最近瀏覽

- **Related（相關推薦）**：頁尾 section 延遲載入 `GET /recommendations/products?product_id={id}&limit=10&intent=related`（演算法：共同購買+描述相似+同系列 fallback）；渲染商品卡 ≤4–10。
- **Complementary（互補）**：資訊欄 block，`intent=complementary`，需在 Search & Discovery 手動配對（每商品 ≤10 個）；無配對不渲染。
- **最近瀏覽**：主題慣例（非平台 API）：localStorage 存 handle 佇列（≤N=8–12，去重、當前商品除外）→ 以 search API `/search/suggest.json?q=handle 或逐 handle 取卡片渲染；我們平台直接做 `recently_viewed` section＋前端佇列。

### 4.8 SEO/a11y（P04）

- JSON-LD：Product＋Offer（價格/幣別/availability/URL）＋多變體 ProductGroup＋AggregateRating（有評價資料時）；BreadcrumbList；canonical 恆 `/products/{handle}`（?variant 參數 canonical 回基底；系列上下文 URL `/collections/x/products/y` canonical 也指基底）。
- og:type=product、og:image=首圖、product:price:amount/currency meta。
- a11y：variant picker 用 fieldset/legend+radio 原生語義；價格變動 aria-live；gallery 縮圖 role=tab 或 list+aria-current；zoom modal focus trap；「Sold out」不能只靠顏色。

---

## 5. 購物車（P05 頁 / P06 drawer）

### 5.1 Cart type 三態與功能對照

theme settings `cart_type: page / drawer / notification`。notification＝加購後右上彈出單品確認卡（含 View cart/Checkout），不承載編輯。

| 能力 | Cart page | Cart drawer | 備註 |
|---|---|---|---|
| 行編輯（數量/移除） | ✓ | ✓ | 同一套 Ajax |
| Cart note | ✓ | ✓（Dawn 摺疊「訂單備註」） | `attributes[note]`→`cart.note`→隨訂單入 admin |
| 折扣碼輸入 | ✓（2025 夏起原生） | ✓ | 見 5.3 |
| 運費估算器 | ✓（慣例區塊） | ✗（空間不足） | 見 5.3 |
| 免運進度條 | ✓ | ✓（drawer 頂慣例） | 主題自製慣例 |
| 推薦 upsell | ✓（頁尾 section） | ✓（drawer 內橫滑列，app/主題慣例） | — |
| 空狀態 | 「購物袋是空的」+ Continue shopping + 登入提示 | 同+「有帳戶？登入以加速結帳」 | — |

### 5.2 行項目（line item）逐控件

| 控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 縮圖+標題+變體 | 識別 | 標題連商品頁；下行小字變體（Color: Black / Size: M）＋selling plan 名＋line properties（禮卡收件人等，`_`開頭隱藏屬性不顯示） | — | 商品已下架仍可見（結帳時擋） |
| 單價/行小計 | 金額 | 行折扣（自動折扣/碼）顯示：劃線原行價+折後價+折扣名 tag | — | 多幣別 presentment |
| 數量 −/＋/輸入 | 改量 | POST `/cart/change.js`（line 或 id ＋ quantity）；回應帶 `sections` 一次取回 drawer/badge HTML 局部替換 | ±→ 300ms debounce 送出→行小計+小計+badge+aria-live 更新 | 超庫存→回 422＋行內錯誤「僅剩 N 件」數量回彈；qty=0＝移除 |
| 移除 🗑/× | 刪行 | quantity=0 | 點擊→行淡出→重算 | 最後一行刪除→轉空狀態 |
| Cart note | 給商家留言 | textarea；失焦 POST `/cart/update.js {note}` | 摺疊展開→輸入→自動儲存 | ≤5,000 字（我們限值進 limits.yml） |

### 5.3 摘要與結帳區

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 免運進度條 | 湊單激勵 | 門檻 T（theme 設定，讀運費規則同步）；`cart.total_price<T`：「再購 NT$Δ 免運」+進度 %；達標：「已享免運 🎉」 | 每次 cart 變動重算（動畫過渡） | 多幣別門檻要按市場換算；與實際運費規則一致性由商家自負（慣例） |
| 折扣碼欄（cart 原生，2025+） | 提前套碼 | 輸入+Apply→驗證：成功＝chip（碼+金額-NT$x+×移除）、失敗 inline「折扣碼無效」；與自動折扣疊加規則同結帳（17 號引擎） | 套用→小計區出現折扣行 | 一單多碼依 combinations 設定；碼在結帳仍可改 |
| 運費估算器 | 預估運費 | 國家/省/郵遞區號三欄+估算鈕→ `GET /cart/shipping_rates.json?shipping_address[zip]=&country=&province=`→列出各費率（名稱+金額+備註） | 展開→填→估算→結果列表 | 無可用費率：「此地址無可用運送方式」 |
| 小計 subtotal | 金額 | ＝Σ行折後；下註「稅金與運費於結帳計算」（有折扣時加折扣行） | — | 含稅價市場顯示「含稅」 |
| Terms 勾選（慣例） | 條款同意 | 非原生：checkbox「我同意退換貨政策與服務條款」（連結政策頁）；未勾→Checkout 鈕禁用或攔截提示；狀態寫 cart attribute `terms_accepted` | 勾選→解鎖結帳 | 動態結帳鈕會繞過——慣例是隱藏 express 鈕或同攔 |
| Checkout 鈕 | 進結帳 | POST /cart → 302 `/checkouts/{token}`；按鈕帶總額慣例「結帳 · NT$1,480」 | loading→跳轉 | 空車禁用；require_login 開啟時未登入→先到登入 |
| Express 鈕群 | 錢包直結 | cart 版動態結帳鈕（Shop Pay/PayPal…）；帶整車內容 | 點→錢包 sheet | require_login 時隱藏（24 §5） |
| 繼續購物 | 返回 | drawer：關閉；page：回上頁或 /collections/all | — | — |

a11y：drawer focus trap＋開啟時背景 `inert`；數量變動 aria-live=polite；行移除後焦點移至下一行或標題。SEO：/cart 與 /cart/* robots disallow＋noindex（30 §9）。

---

## 6. 結帳（P07/P08/P09）

### 6.1 版型與步驟

**One-page 為預設**；商家可在 checkout editor 設定切回 three-page（資訊→運送→付款，功能與收集欄位完全等價，僅分頁）。桌機兩欄：左表單流（約 55%）＋右**訂單摘要側欄**（sticky）；手機單欄，摘要收合為頂部列「▾ 顯示訂單摘要 — NT$1,480」點擊展開（含明細+折扣欄）。頁首：商店 logo（連回店面）＋購物袋 icon；頁尾：政策連結列（退款/隱私/條款/運送，自動出現）。整頁樣式由 checkout branding（24 §6）驅動，非 Liquid theme。

**Three-page 差異**：步驟麵包屑（Cart > Information > Shipping > Payment）；資訊步底部「Continue to shipping」、各步可 Return to 上一步；欄位集不變。

### 6.2 Express checkout 牆

表單最上方：「Express checkout」標題＋錢包鈕列（Shop Pay 紫/PayPal 黃/Apple Pay 黑/Google Pay/Amazon Pay，依買家裝置與啟用金流自動組合）→ 分隔線「OR」→ 下方傳統表單。點錢包→開各家 sheet（地址/卡片由錢包帶入）→回摘要確認。Shop Pay 已識別買家（cookie/email 命中）時整頁可跳轉 Shop Pay 快速流（6 碼簡訊驗證→一鍵付款）。

### 6.3 Contact（聯絡）區

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 標題列+登入連結 | 「Contact」＋右側「Log in」 | 新版帳戶：Log in→email+6 碼驗證，登入後自動填地址/付款 | 未登入照常 guest 結帳 | `require_login` 開啟時強制先登入 |
| Email（或手機） | 收件通知 | 依設定：email only / email 或手機二擇一（tel 輸入帶國碼旗選擇器）；格式即時驗證（blur 時） | 已登入預填唯讀（可換帳號） | 格式錯：紅框+inline「請輸入有效的電子郵件」 |
| 行銷勾選 | 訂閱 | 「Email me with news and offers」；預設勾選僅限商家設定的地區（SMS 恆不可預勾，24 §5） | — | 同意寫入 customer marketing consent |

### 6.4 Delivery（運送）區

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| Ship / Pick up 切換 | 履約方式 | 有啟用本地取貨才顯示雙 tab；Pick up→門市單選列表（距離+地址+備貨時間），隱藏地址表單 | 切 tab→下方表單/費率整組切換 | 車內含不可取貨品→提示 |
| Country/region | 國家 | select；決定下方欄位組排列（本地化地址格式）與州/省欄有無 | 切國家→表單重排＋運費重算 | 僅列商家可運國家（市場對齊 29 §5） |
| 姓名 | First/Last 兩欄 | 設定可「僅姓氏必填」 | — | — |
| Company | 公司 | hidden/optional/required 三態（24 §5） | — | required 時 Apple Pay 不可用 |
| Address | 地址 | 主欄＋**自動完成**：輸入即出 Google 建議下拉（≤5 條），選中自動拆填 city/zip/province；可關閉 | 打字→↓選建議→Enter 填入 | 不支援國家退回純手填 |
| Address2 | 公寓樓層 | 三態；預設「Add apartment, suite…」摺疊連結展開 | — | — |
| City / Postal code / Province | 城市/郵編/州 | 郵編格式按國家驗證（台灣 3+2/3+3 碼）；省州 select 依國家載入 | — | 郵編非法：inline 錯誤 |
| Phone | 電話 | 三態；國旗+國碼選擇器；E.164 正規化 | — | 選簡訊通知時必填 |
| 儲存資訊勾選 | 「Save this information for next time」 | 存瀏覽器（guest）或帳戶；旁帶 Shop Pay 註記 | — | — |
| Shipping method 卡 | 費率單選 | 地址齊全後載入：radio 列表（名稱+說明+預估到貨「3–7 個工作天」或日期區間+右側價格，免費顯示「Free」）；預設選最便宜 | 改選→摘要 total 即時重算 | 無費率：「無法運送至此地址」阻擋；重量/規則過濾後單一費率仍顯示 |

### 6.5 Payment（付款）區

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 安全註記 | 「All transactions are secure and encrypted」 | 鎖 icon | — | — |
| 付款方式 radio 手風琴 | 單選展開 | 順序：信用卡（預設展開）→ 錢包 → 手動方式（銀行轉帳/貨到付款…各自展開說明文字）→ 分期（Shop Pay Installments 市場限定） | 選中者展開內容，其餘收合 | 幣別×國家不支援的方式自動不出現（29 §5） |
| 卡號欄組 | 收卡 | iframe 安全欄位：卡號（brand icon 即時識別）/到期 MM/YY/安全碼（?tooltip）/持卡人姓名；Luhn+到期即時驗證 | 逐欄 blur 驗證紅框 | 失敗訊息不洩漏細節（「請檢查卡片資訊」） |
| Billing address | 帳單地址 | radio：「Same as shipping（預設）」/「Use a different billing address」→展開同 6.4 地址組 | — | 純數位商品單（無運送）直接收 billing |
| Remember me | Shop Pay 記憶 | checkbox+手機號→建 Shop Pay 帳戶（下次 6 碼快付） | — | — |
| 小費卡（開啟時） | 加小費 | 「Add tip」：3 個預設 %（＋自訂金額輸入）；上限 US$1,000 且 ≤100% 訂單額；以稅前運費前小計計算（24 §5） | 選 %→total 重算 | 可收合；預設不選 |
| Pay now 鈕 | 送單 | 全欄驗證→建立訂單+扣款（authorize 或 capture 依設定）；loading 轉圈鎖定防重複 | 成功→302 感謝頁 | 失敗：頂部紅 banner+滾動至錯誤；庫存不足→回摘要標示行+「已調整數量」 |

### 6.6 訂單摘要側欄

| 控件 | 功能 | 邏輯 | 邊界情況 |
|---|---|---|---|
| 行項目列 | 確認內容 | 縮圖（右上數量 badge 圓標）+名稱+變體+行價；不可編輯（改動回購物車） | 訂閱行顯示「每 4 週 NT$X」 |
| **折扣碼欄** | 套碼 | 單一輸入框（**折扣碼與禮品卡共用**）＋Apply；成功＝tag chip（× 可移除）＋折扣行負值；禮品卡＝顯示卡號末 4 碼+已折餘額 | 無效碼 inline 錯誤；多碼依 combinations；cart 已套碼帶入 |
| 金額行 | Subtotal→Discount→Shipping→（Duties）→Tax→**Total（幣別代碼+大字）** | 各行隨表單進度即時更新（運費未選前顯示「Calculated at next step/—」） | 含稅市場註「Including NT$x tax」；訂閱單加「Recurring subtotal」 |
| 手機收合列 | 摘要開合 | ▾/▴ 切換；列上恆顯 Total | 展開含完整明細+折扣欄 |

### 6.7 感謝頁（P08）→ 訂單狀態頁（P09）

- **感謝頁**（下單後即刻，一次性）：✓ 動畫+「Thank you, {名}!」+訂單號 `#1001`；地圖區（配送地址定位）；「Order updates」opt-in（email 已收/可補簡訊）；訂單明細摘要（同側欄）＋客服連結＋「Continue shopping」；（Plus/UI extensions：問卷、upsell 位）。
- **訂單狀態頁**（同 URL 永久可回訪；email/簡訊連結、帳戶、Shop app 皆可進）：
  - 物流時間軸：Confirmed → On its way → Out for delivery → Delivered（＋Attempted delivery 分支）；支援的物流商顯示**即時地圖**＋最後掃描點；不支援者顯示追蹤號連結（外開物流商站）。
  - 多 fulfillment＝多個追蹤區塊（各自狀態+追蹤號）。
  - 內容區：商家自訂訊息、明細、聯絡客服、（新版帳戶）**Buy again** 再購鈕（整單商品重加入購物車）與 **Start return** 自助退貨入口（§7.5）。
  - 逾時回訪要驗證：輸入訂單號＋email（或郵編）。
  - Shop app 安裝 banner（可關）。
- 通知鏈（18 號銜接）：order confirmation/shipping confirmation/out for delivery/delivered 郵件都深連此頁。

### 6.8 結帳 SEO/a11y

checkout 網域 noindex＋robots disallow；表單全欄 label+autocomplete 屬性（`shipping address-line1`、`cc-number`…）；錯誤 aria-describedby 綁定；radio 卡整卡可點；步驟切換焦點移至新區標題；Pay 鈕狀態語音播報。

---

## 7. 客戶帳戶（P12–P19）

### 7.1 兩版並存策略

| 面向 | 新版（customer accounts，預設推薦） | 傳統版（classic/legacy） |
|---|---|---|
| 認證 | **無密碼**：email→6 碼一次性驗證碼；Sign in with Shop（passkey）/Google/Facebook；Plus 可接外部 IdP；session 365 天 | email+密碼；忘記密碼→重設信；可開帳戶邀請（activate） |
| 頁面 | 平台渲染（非 theme）：Orders / Profile / Addresses / Settings＋app 整頁（`customer-account.page.render`）；branding 繼承 checkout 配置 | theme templates：login/register/recover/reset/activate/account/addresses/order |
| 網域 | `shopify.com/{shop_id}/account` 或品牌化 `account.{domain}` | 店面網域 `/account/*` |
| 註冊頁 | 無（首次驗證碼登入即建檔） | /account/register 表單 |
| 能力 | Buy again、**自助退貨**、留評價入口、訂閱/store credit 區塊、地址、行銷偏好 | 訂單列表/詳情、地址 CRUD、基本資料唯讀 |

我們平台：主做新版（對齊 24 §6.4），保留 classic 模板相容第三方主題（26 號 customer 物件）。

### 7.2 認證頁組

| 頁/控件 | 功能 | 邏輯 | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 登入（新版） | email 單欄 | 「Sign in」→寄 6 碼（有效數分鐘、可重寄倒數 60s）→輸碼頁（6 格自動跳格/貼上分配）→成功進帳戶 | 錯碼 inline；多次錯誤→hCaptcha/challenge | 未註冊 email 一樣寄碼（首登即建客戶），不洩漏存在性 |
| 登入（傳統） | email+密碼 | 錯誤統一「email 或密碼不正確」；「Forgot password?」連結；「Create account」連結 | submit→/account | 5 次失敗觸發 /challenge（hCaptcha） |
| 註冊（傳統 P13） | 建帳戶 | first/last/email/password；成功→自動登入或「已寄確認」；重複 email→「此信箱已註冊」＋登入引導 | — | 開「帳戶需審核」時顯示待審文案 |
| 忘記密碼 P14 | 重設 | /recover 輸入 email→恆顯「若帳戶存在已寄信」；信內連結→/reset 新密碼×2（強度規則） | 重設成功→自動登入 | 連結 TTL（我們定 2h）過期→重走 recover |
| 啟用 P15 | 受邀開通 | 邀請信→/activate token→設密碼×2→開通 | — | token 一次性 |

### 7.3 帳戶總覽與訂單（P16/P17）

- **總覽佈局**（classic：/account）：標題「My account」＋Log out；左＝Order history 表（欄：訂單號連結/日期/付款狀態 badge/出貨狀態 badge/總額；空狀態「尚無訂單」+去逛逛）；右＝Account details（姓名/email/預設地址摘要＋「View addresses (N)」）。新版＝卡片流：進行中訂單卡（縮圖+狀態+追蹤 CTA）→歷史訂單列表（無限捲動）＋每單 **Buy again / Start return / Leave review** 快捷鈕。
- **訂單詳情**（P17）：訂單號+日期+狀態列；行項目表（縮圖/名稱/變體/單價/數量/行小計）；金額區 subtotal/discount/shipping/tax/total；已退款顯示負值行；Billing / Shipping 地址雙欄；追蹤區（同 P09 摘要）＋「查看訂單狀態」深連 P09；新版加：發票下載（有 app 時）、再購鈕。

### 7.4 地址、個資與訂閱

| 控件 | 功能 | 邏輯 | 邊界情況 |
|---|---|---|---|
| 地址列表 P18 | CRUD | 每卡：姓名+完整地址+「Default」badge；Add new address 展開表單（同結帳地址欄組+國家/省連動）＋「設為預設」checkbox；Edit/Delete（confirm） | 預設地址供結帳預填；刪除預設→最新一筆遞補 |
| Profile（新版） | 個資 | 姓名可改；email 改→需對新信箱重驗證；手機綁定（簡訊碼）；行銷訂閱 toggle（email/SMS 分開） | — |
| 訂閱管理入口 | subscriptions | 有訂閱 app 時新版帳戶出現「Subscriptions」區：每筆＝商品+頻率+下次扣款日+金額＋操作（跳過本期/暫停/取消/改地址/改付款）——實作走 app 的 customer account UI extension；我們平台以原生模組承接（15 號 selling plans） | 取消需二次確認+挽留文案慣例 |
| Store credit（新版） | 商店額度 | 餘額卡+交易紀錄；結帳時可用 | — |

### 7.5 自助退貨流程（新版帳戶/P09 入口，逐步）

1. 訂單卡「Start return」（僅已出貨/已送達且在**退貨窗口**內顯示；窗口天數＝商家退貨規則，常見 14/30 天自送達起算）。
2. 選品項：逐行 checkbox＋數量（≤已購量）；**final sale 品項鎖定不可選**（標示「不可退貨」）。
3. 每項選**退貨原因**（下拉，固定字典：尺寸不合/不符描述/瑕疵/損壞/晚到/不想要了/其他＋備註 textarea）；可依商家設定加照片上傳。
4. 送出申請→狀態「已申請（Return requested）」；畫面顯示「等待商家審核」。
5. 商家核准→買家收 email：**退貨標籤**（可下載 PDF/QR）或退貨指示（自行寄回地址）；顯示應退金額預估（可含**restocking fee 扣減 %**與運費是否退）。
6. 買家寄回→追蹤號回填→狀態 In transit→商家收貨 Received→驗貨後退款（原路退回，退款到帳提示）；或換貨單生成。
7. 拒絕分支：狀態 Declined＋商家留言；買家可聯絡客服。
   邊界：部分退（單內多品項分次申請）允許；退款上限＝實收（16 號）；郵件每步觸發（18 號 return requested/approved/declined 模板）。

a11y/SEO：/account/* 全部 noindex；6 碼輸入框 `one-time-code` autocomplete；badge 狀態帶文字非僅顏色。

---

## 8. 搜尋（P10/P11）

### 8.1 Predictive search 覆蓋層（P11）

觸發：header 搜尋 icon/輸入框聚焦。桌機＝輸入框下拉面板；手機＝全螢幕層。API（查證全參數）：`GET /search/suggest.json?q=&resources[type]=product,collection,page,article,query&resources[limit]=10&resources[limit_scope]=all|each&resources[options][unavailable_products]=show|hide|last&resources[options][fields]=title,product_type,variants.title,vendor`；HTML 版 `/search/suggest?section_id=predictive-search` 直接回渲染好的 section。

| 控件 | 功能 | 邏輯（數值） | 操作流程 | 邊界情況 |
|---|---|---|---|---|
| 輸入框 | 即時建議 | ≥1 字元起查，200–300ms debounce；**容錯**：前 4 字正確後容 1 字打錯；支援前綴部分詞（sweate→sweater） | 打字→面板更新；Enter→整頁結果；Esc/×清空關閉 | 每型別 ≤10 條；query 建議僅英文（我們要自建中文 suggest） |
| 建議詞組（QUERIES） | 熱門/補全 | type=query；點擊＝以該詞執行搜尋；匹配片段粗體 | ↑↓ 鍵盤巡覽（combobox+listbox+aria-activedescendant） | 無建議時隱藏群組 |
| 商品組（PRODUCTS） | 直達商品 | 縮圖+標題+價格（劃線價邏輯同卡片）；命中變體詞時可帶變體 | 點→商品頁 | unavailable_products=last 售罄沉底 |
| 系列/頁面/文章組 | 導航 | 各自標題列表 | 點→對應頁 | 空組隱藏；四組全空→「無結果」+「搜尋『{q}』」整頁連結 |
| 「Search for “{q}”」底列 | 整頁搜尋 | 恆在面板底部 | Enter 同效 | — |

### 8.2 搜尋結果頁（P10）

URL：`/search?q={詞}&type=product,article,page&options[prefix]=last&sort_by=relevance`。Dawn＝單一格線混排（商品卡+文章卡+頁面列）；慣例增強＝**型別 tabs**（All/Products N/Articles N/Pages N）——我們原型做 tabs 版。工具列同系列頁：**篩選（同 §3.2 全套，作用於商品）**＋排序（relevance/price-asc/price-desc）＋結果數「找到 N 筆『{q}』結果」。空狀態：「找不到『{q}』」＋檢查拼字建議＋熱門商品區。分頁同 §3。SEO：/search robots disallow；noindex。

---

## 9. 部落格（P20/P21）

### 9.1 列表頁 P20

banner（blog 標題）→（慣例）**標籤篩選列**：全部/tag pills，點選→`/blogs/{handle}/tagged/{tag}`（可多 tag `+` 串接）→ 文章卡格線（图+標題+摘要 excerpt+日期+作者，顯示開關）→ 分頁。RSS：`/blogs/{handle}.atom` 自動存在。

### 9.2 文章頁 P21

| 區塊/控件 | 功能 | 邏輯 | 邊界情況 |
|---|---|---|---|
| 主體 | 文章 | 特色圖（寬窄設定）→ h1 標題 → meta 列（日期+作者，開關）→ 富文本內容 | — |
| 分享 | 傳播 | copy link+FB/X/LINE 慣例 | og:type=article |
| 上一篇/下一篇 | 巡覽 | `blog.previous_article`/`next_article`（按發佈時間）；顯示相鄰文章標題連結 | 首尾篇單側 |
| 留言區 | UGC | 依 blog 設定三態：**停用**（整區不渲染）/**先審後刊**/**直接刊登**；顯示：留言數標題「N 則留言」+逐則（姓名+日期+內文，分頁 ≤50/頁） | spam 自動偵測（誤判可解） |
| 留言表單 | 送留言 | `{% form 'new_comment' %}`：姓名*+email*+留言*；hCaptcha 風險判定；成功文案分流：先審模式「留言已送出，審核後顯示」/直刊模式「留言已發布」 | 錯誤 inline；email 不公開顯示 |

SEO：BlogPosting JSON-LD（headline/datePublished/author/image）；文章 canonical `/blogs/{blog}/{article}`；tagged 頁 self-canonical。

---

## 10. 其他頁面

### 10.1 靜態頁 P22

main-page＝h1+富文本；可插任意 §2 sections（OS 2.0 pages 也吃 JSON template）；alternate template（page.contact 等）。

### 10.2 聯絡頁 P23（contact-form section）

| 控件 | 功能 | 邏輯 | 邊界情況 |
|---|---|---|---|
| 欄位組 | 收訊息 | 預設四欄：Name（選填）/Email*/Phone（選填）/Comment*；`{% form 'contact' %}` POST | 欄位可由主題加自訂 field（body 併入信件） |
| 送出 | 寄信 | 成功→inline 綠色「已送出，我們會盡快回覆」（頁面錨點回表單）；信寄到商店寄件人信箱、reply-to＝填寫者 | 失敗顯示欄位錯誤摘要列表 |
| spam 防護 | hCaptcha | 平台級：customer/contact/comment 三類表單自動保護；行為分析通過＝無感，可疑→跳 `/challenge` 互動驗證頁（P28）；頁角 hCaptcha 徽章（可改文字聲明）；商家可在 Preferences 全關 | 關閉後垃圾訊息自負 |

### 10.3 政策頁 P24

Settings→Policies 富文本（可套模板生成）→自動發佈四頁：`/policies/refund-policy`、`/policies/privacy-policy`、`/policies/terms-of-service`、`/policies/shipping-policy`（另有 contact-information/subscription-policy 可選）。版型＝置中窄欄純文書；自動連結進 footer 與結帳頁尾；**可索引**（indexable）。空政策→404。

### 10.4 404 頁 P25

h1「404 找不到頁面」+「Continue shopping」CTA；可加 sections（搜尋框/熱門系列慣例）；**HTTP 必須真 404**（下架商品 410，30 §9 條 5）。

### 10.5 禮品卡顯示頁 P26（gift_card.liquid）

收禮人從 email「View your gift card」進入 `/gift_cards/{token}`（token URL，noindex）。

| 控件 | 功能 | 邏輯 | 邊界情況 |
|---|---|---|---|
| 面額卡 | 呈現 | 商店 logo+插圖+**目前餘額**（初始面額，部分使用後顯示剩餘）+期限（有設時「至 YYYY-MM-DD」） | 餘額 0 顯示已用罄狀態 |
| 卡號 | 兌換碼 | 16 碼分組顯示+一鍵複製（toast「已複製」）；結帳折扣欄輸入使用 | 遮蔽格式 •••• 末 4（hover/點擊顯全，主題慣例） |
| QR code | 到店核銷 | JS 生成 QR（POS 掃碼扣款） | — |
| Apple Wallet | 存入錢包 | 「Add to Apple Wallet」badge→`gift_card.pass_url`（.pkpass） | 僅 iOS Safari 顯示慣例 |
| 列印/購物 | 動作 | Print（window.print 樣式表）；「Start shopping」回店 | — |

### 10.6 禮品卡購買流程（商品頁變體）

禮品卡商品＝面額當變體（NT$500/1,000/2,000…）。商品頁多一組**收件人表單**（gift card recipient feature，查證值）：checkbox「我要直接送給收件人」→展開：收件人 email*（勾選時必填）/收件人姓名（≤255 字）/**訊息（≤200 字，餘字數計數器）**/寄送日期（date picker，**最多可排 90 天後**，按收件人時區 offset 屬性）。行為：屬性以 line item properties 傳遞（`__shopify_send_gift_card_to_recipient` 開關）；**與動態結帳鈕不相容**（僅 Add to cart 路徑校驗）；未排程＝付款後立即寄；已排程＝寄送日當天發信（帳單人另收購買確認）。cart 行顯示「收件人：xxx@」。數位品不收運費、不計運送步（純禮卡單跳過 Delivery 段直接 billing）。

### 10.7 人機驗證頁 P28

`/challenge`：置中卡片「請完成驗證以繼續」+hCaptcha 挑戰框+送出；通過→原動作續行（登入/留言/聯絡）。表單 POST 中轉設計：原請求參數 hidden 保留。

---

## 11. 多語多幣在前台的實際表現（銜接 29）

- **選擇器**：header/footer 的國家（幣別）與語言兩顆下拉（`{% form 'localization' %}`；選項>1 才渲染）；改國家→幣別/價格/可售目錄切換（302 至對應 web presence URL 或就地重載）；改語言→URL 前綴切換（`/`→`/en`、次級市場 `/en-us`）。GeoIP 只做「建議切換」banner（「看起來你在美國，要切換嗎？」+記住選擇 cookie），**爬蟲永不重導**。
- **價格顯示**：全站 money filter 輸出 presentment 幣別（含 rounding 規則；JPY 等零小數幣無小數）；商品頁/卡片/購物車/結帳金額同源換算；**結帳鎖定進入時幣別**；fixed price 市場直接取 price list 值。
- **內容 fallback**：翻譯缺漏 key 落回預設語言（29 §2.2）；theme 靜態字串吃 locale 檔。
- **hreflang**：head 對每個 market×locale URL 輸出 alternate 全集+x-default（30 §9 條 12：僅 ISO 白名單）；sitemap 收全市場 URL。
- **台灣預設**：zh-Hant 主語言+TWD；英文次語言 `/en`；價格 NT$ 千分位、無小數（TWD exponent=0 實務顯示整數）。

---

## 12. 台灣在地補充（我們平台要加的前台/結帳項）

> 對標 SHOPLINE/cyberbiz 台灣結帳慣例＋ECPay 物流/發票文檔。這些是 Shopify 沒有、台灣電商必備的三件套：**電子發票、超商取貨、貨到付款**。

### 12.1 結帳「發票資訊」區（Payment 區下方新增段）

| 控件 | 功能 | 邏輯（驗證規則） | 邊界情況 |
|---|---|---|---|
| 發票類型 radio | 四選一 | **個人雲端發票（預設）**／**捐贈發票**／**公司戶（統編）**／紙本二聯（商家可關，SHOPLINE 預設關） | 商家後台逐類開關 |
| 載具類型（個人雲端時） | 三選一下拉 | **會員載具（預設）**＝存平台、中獎通知 email；**手機條碼**＝輸入框，格式 `^/[0-9A-Z.+-]{7}$`（「/」+7 碼，即時驗證+轉大寫）；**自然人憑證**＝2 大寫字母+14 數字（16 碼） | 手機條碼可打 API 驗證存在性（財政部）；錯誤 inline「載具格式不正確」 |
| 統一編號（公司戶時） | 報帳 | 8 碼數字＋**檢核演算法**（權重 1,2,1,2,1,2,4,1，各位乘積數字和能被 10 整除；第 7 碼為 7 時特例）；公司抬頭 text（選填或必填可設）；發票寄送地址（紙本三聯需要時） | 統編錯誤即時擋；抬頭可依統編 API 自動帶入（加值） |
| 捐贈碼（捐贈時） | 捐出 | 預設機構快選 pills（商家設 3–5 個常用：如 25885 等）＋自訂捐贈碼輸入（3–7 碼數字） | 無效捐贈碼→送單前驗證 |
| 開立說明 | 信任 | 小字：「發票將於出貨後 X 日內開立並寄送至 email／存入載具」；發票由加值中心（綠界/ezPay）開立、中獎自動通知 | 退款→自動作廢/折讓流程（16 號銜接） |

資料落庫：`order_invoice_info(shop_id, order_id, type, carrier_type, carrier_code, tax_id, company_title, donation_code, status)`；發票號碼回填於開立後，帳戶訂單詳情可查看/下載。

### 12.2 超商取貨門市選擇（Delivery 區新流程）

運送方式 radio 增列：**超商取貨（純取貨）**與**超商取貨付款（COD）**，各自再分通路：7-ELEVEN／全家／萊爾富／OK（對應 ECPay LogisticsSubType：`UNIMART/UNIMARTC2C`、`FAMI/FAMIC2C`、`HILIFE/HILIFEC2C`、`OKMARTC2C`；7-11 另有 `UNIMARTFREEZE` 冷凍）。

流程（查證 ECPay 電子地圖合約）：

1. 買家選「超商取貨—7-ELEVEN NT$60」→出現**「選擇門市」按鈕**（未選前結帳鈕禁用+提示「請先選擇取貨門市」）。
2. 點擊→POST 至地圖端點 `https://logistics.ecpay.com.tw/Express/map`（參數：MerchantID、LogisticsType=CVS、LogisticsSubType、IsCollection=Y/N（取貨付款＝Y）、ServerReplyURL（回拋網址）、Device 0 桌機/1 手機、ExtraData 帶我方 checkout token）→**跳轉/彈窗開超商官方電子地圖**（縣市→區→門市或關鍵字/定位搜尋）。
3. 買家點定門市→地圖回拋 POST ServerReplyURL：`CVSStoreID`、`CVSStoreName`、`CVSAddress`、`CVSTelephone`、`CVSOutSide`（外島=1）→我方存入 checkout session 後 302 回結帳頁。
4. 結帳頁顯示**門市卡**（門市名+店號+地址+電話，唯讀）＋「重新選擇」按鈕；地址表單隱藏（僅收取件人姓名+手機——超商取貨以手機號+證件領件）。
5. 邊界：門市關轉店→出貨時物流商回異常，通知買家改門市（admin 流程）；**外島門市常排除**（CVSOutSide=1 時提示不可選或加天數）；材積限制（三邊和 ≤105cm、重量 ≤5kg 慣例）超標商品在購物車即擋「含大型商品不可超商取貨」；金額上限：**取貨付款 ≤NT$20,000**（超商代收上限，超過隱藏 COD 選項）；冷凍品僅列支援冷凍通路。

### 12.3 貨到付款（COD）

付款方式 radio 增列：**超商取貨付款**（同 12.2 IsCollection=Y，取貨時付現）與**宅配貨到付款**（黑貓/新竹到府代收，常加手續費 NT$30–60 顯示於摘要「代收手續費」行）。邏輯：COD 訂單付款狀態＝pending（`manual` gateway），出貨後由物流代收→對帳回寫 paid（16 號）；風控：可設 COD 限額、封鎖多次拒收名單（黑名單 attribute）。台灣結帳慣例補充：**LINE Pay／街口／ATM 虛擬帳號／超商代碼繳費**列於付款方式（各自展開說明），ATM/超商代碼＝取號後感謝頁顯示繳費資訊+期限倒數（3 天慣例），期限內未繳自動取消（棄單邏輯銜接 24 §5）。

### 12.4 其他台灣慣例

- 手機號格式 `09xxxxxxxx`（10 碼）驗證；地址欄改「郵遞區號（3+2/3+3）→縣市 select→鄉鎮市區 select 連動→路街門牌」。
- 全站金額 `NT$1,480` 整數；免運門檻慣例 NT$1,000–1,500。
- 發票/載具說明頁＋超商取貨教學頁列入靜態頁建站清單。

---

## 13. 建站優先序（本篇→原型工單）

1. **P0**：P02 系列頁（篩選+排序+quick add）→ P04 商品頁全套（§4.2–4.4、4.6–4.7）→ P05/P06 購物車補強（note/折扣碼/免運條/估運費）→ P07 結帳 one-page（§6 全）＋台灣三件套（§12）→ P10/P11 搜尋。
2. **P1**：P08/P09 感謝+訂單狀態→ P12–P18 帳戶（新版流+classic 相容）→ P19 自助退貨→ P20–P25 內容頁群→ P29 cookie 橫幅→ P26 禮品卡雙流程。
3. **P2**：P27 密碼頁、P28 challenge、age gate、最近瀏覽、評價系統、訂閱管理。

## 14. 來源 URL

- Dawn 檔案清單：data.jsdelivr.com/v1/packages/gh/Shopify/dawn@main（sections/templates 逐檔）
- 篩選：help.shopify.com/en/manual/online-store/search-and-discovery/filters
- Predictive search：shopify.dev/docs/api/ajax/reference/predictive-search
- 取貨庫存：shopify.dev/docs/storefronts/themes/delivery-fulfillment/pickup-availability
- 動態結帳鈕：help.shopify.com/en/manual/online-store/dynamic-checkout
- Sections/blocks 上限：help.shopify.com/en/manual/online-store/themes/theme-structure/sections-and-blocks
- One-page checkout：help.shopify.com/en/manual/checkout-settings/customize-checkout-configurations/one-page-checkout
- 結帳表單欄位：help.shopify.com/en/manual/checkout-settings/checkout-form-options
- 訂單狀態頁：help.shopify.com/en/manual/fulfillment/setup/order-status-page/understanding-order-status-pages
- 新版客戶帳戶：help.shopify.com/en/manual/customers/customer-accounts/new-customer-accounts
- 自助退貨：help.shopify.com/en/manual/fulfillment/managing-orders/returns/self-serve-returns
- 留言管理：help.shopify.com/en/manual/online-store/blogs/managing-comments
- hCaptcha：shopify.dev/docs/storefronts/themes/trust-security/captcha
- Cookie 橫幅：help.shopify.com/en/manual/privacy-and-security/privacy/customer-privacy-settings/privacy-settings
- 禮品卡收件表單：shopify.dev/docs/storefronts/themes/product-merchandising/gift-cards
- Editions Summer 2025（Horizon/cart 折扣碼）：lunatemplates.co/blogs/shopify-blog/whats-new-in-shopify-editions-summer-2025-our-highlights
- 台灣電子發票欄位：support.shoplineapp.com（SHOPLINE 電子發票功能設定 4406498947993）
- 超商電子地圖：developers.ecpay.com.tw/8795/
- 內部：03（主題）、24 §5–6（結帳設定/編輯器）、25/26（Liquid 相容）、29（Markets）、30 §9（SEO 義務）

