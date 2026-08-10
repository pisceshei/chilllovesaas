# 20 — CHILL LOVE 三面 UI 專屬方案（高保真標準）

> 回答三個問題：(1) 之前的 UI 為什麼醜、怎麼根治；(2) 平台後台 / 商家後台 / 前台商店三個界面各自的設計語言、參考對象、tokens；(3) 做出「高保真、可交互、美觀」需要哪些 skill、代碼、資產，以及製作與迭代流程。本方案附兩個可點擊的示範 mockup（商家後台 + 前台首頁）作為品質基準——先看再讀。

## 1. 誠實診斷：AI 做的 UI 為什麼常常醜

| # | 病因 | 症狀 | 本專案的根治 |
|---|---|---|---|
| 1 | 沒有真正的 type scale | 字級隨手寫（14/16/18 亂跳）、行高不成節奏 | 固定 scale：11/12/13(基準)/14/16/20/24/32，行高 1.45–1.6，全部 token 化 |
| 2 | 假內容 | Lorem ipsum、Product 1、$0.00 | 一律真內容：真商品名（奶茶色寬版帽T）、真價格（NT$1,280）、真人名、真日期 |
| 3 | 只有一種狀態 | 沒 hover/focus/loading/empty/error | 每個元件五態全做；空狀態有插畫與 CTA |
| 4 | 間距沒有節奏 | padding 東 12 西 18 | 4px 網格：卡片 16、卡間 16、區塊 24、頁邊 32，違反即 bug |
| 5 | 顏色即興 | 高飽和亂配、灰階七八種 | 語意 token（≤5 個灰、4 個語意色），圖表色跑過驗證器 |
| 6 | 沒有微互動 | 點了沒反饋、生硬跳變 | 150–200ms ease-out 全域、save bar 滑入、toast、skeleton shimmer |
| 7 | 密度不對 | 後台鬆得像行銷頁、前台擠得像報表 | 後台=資訊密度優先（13px、52px 列高）；前台=留白與大圖優先 |

一句話：**醜不是天賦問題，是缺工序**。下面全部工序化。

## 2. 三個界面的定位與參考對象

### 2a. 商家後台（Merchant Admin）——「工作台」

- 定位：高密度生產力工具。使用者每天泡 4 小時，美=清晰、快、可預測。
- 參考對象（各取一味，不抄任何一家的資產）：
  - **Shopify Admin**（我們 02 的研究）：資訊架構、Index/Detail 兩模式、save bar、badge 語意——**結構與交互的規格來源**
  - **Linear**：鍵盤優先（⌘K）、極致的灰階紀律與 150ms 手感——**質感標竿**
  - **Stripe Dashboard**：數據排版（tabular-nums、表格對齊）、圖表克制——**數據呈現標竿**
  - **shadcn/ui 生態**：Radix + Tailwind 的元件工程做法——**代碼結構參考**
- 語言：繁體中文為主、金額 NT$、Inter + Noto Sans TC。

### 2b. 平台營運後台（Platform Admin）——新增的第三面

- 定位：CHILL LOVE 自己（SaaS 營運者）用的內控台，使用者只有我們，畫面少而精。
- 範圍（demo 6 頁）：租戶列表（店、方案、狀態、GMV）／租戶詳情（開關店、feature flags、模擬登入）／平台指標（總 GMV、活躍店、訂單量）／方案管理／事件與任務監控（outbox、jobs、webhook 投遞）／操作稽核。
- 設計語言：**與商家後台同一套 tokens**（省一套系統），但側欄用深色變體 + 頂部掛「PLATFORM」標識——防止營運人員混淆自己在哪一面（真實事故源）。

### 2c. Storefront（CHILL LOVE 示範店）——「品牌」

- 定位：demo 店本身就是產品門面，要讓人想買。方向：**溫暖極簡生活風**（brand name 就叫 CHILL LOVE）。
- 參考對象：頂級極簡服飾電商的共同語言——超大留白、攝影主導、serif display 標題 + sans 內文、窄字距大寫眉標、細線分隔、克制的動效（COS / Aesop / SSENSE 一類的氣質，取氣質不取資產）；結構骨架照我們 03 的 Dawn 解剖。
- 關鍵決定：**前台與後台是兩套視覺語言**（後台中性、前台有品牌性格）——這正是 theme 系統存在的意義，也讓 demo 更有說服力。

## 3. 兩套設計語言的 tokens

### 3a. Admin 系統（商家後台 + 平台後台共用）

```css
/* 色 */ --bg:#f1f1f2; --surface:#fff; --surface-2:#f7f7f8; --text:#1a1c1e;
--text-2:#6b6d71; --text-3:#8a8c90; --border:#e3e3e6; --brand:#2b2c2e;/* 主按鈕 */
--link:#2a5bd7; --focus:#2a78d6; --success:#0a7a5c; --success-bg:#e6f3ee;
--warning:#8a6116; --warning-bg:#fdf3dc; --critical:#b3172c; --critical-bg:#fdecee;
--info:#155e8f; --info-bg:#e8f2fa; --attention:#7a6a00; --attention-bg:#fbf4c6;
/* 字 */ --font:Inter,"Noto Sans TC",system-ui; 基準 13px；scale 11/12/13/14/16/20/24
/* 距 */ 4px 網格；卡 padding 16；卡間 16；頁 max-width 998px（Detail）/1200px（Index）
/* 形 */ 卡 radius 12；按鈕/輸入 8；badge 999；邊框 1px；陰影 0 1px 2px rgba(0,0,0,.05)
/* 動 */ 150ms ease-out（hover/focus）；240ms cubic-bezier(.2,.8,.2,1)（drawer/savebar）
/* 圖表 */ 單系列 #2a78d6（已跑 dataviz 驗證器 vs #fff：全項 PASS）；grid 髮絲線 #ececef
```

### 3b. Storefront「CHILL LOVE 主題」tokens

```css
--cream:#f6f1e9;/* 頁底 */ --paper:#fffdf8;/* 卡 */ --ink:#221e1a; --ink-2:#6e655c;
--line:#e7dfd3; --clay:#a9502c;/* 品牌強調/Sale */ --sage:#7d8a6f;/* 輔助 */
/* 字 */ display: "Fraunces",Georgia,serif（標題/數字大字）; body: Inter+"Noto Sans TC"
eyebrow：11px、letter-spacing .18em、大寫
/* 距 */ 區塊垂直 96–128px（桌機）；格線 gap 24；頁邊 max 1280px
/* 形 */ 按鈕方角（radius 2）、細邊框；圖比例 3:4（商品）/ 16:9（banner）
/* 動 */ 卡 hover：圖片 scale 1.03 + 第二圖淡入（400ms）；drawer 320ms
```

## 4. 高保真工藝清單（做到才算數）

1. **真內容原則**：20 個真商品（名稱/價格/庫存/描述）、真訂單流水、真人顧客名——種子資料即設計資產。
2. **五態完備**：default / hover / focus-visible / disabled / loading，每個互動元件。
3. **三頁必備**：每個列表有空狀態（插畫+CTA）、載入 skeleton、錯誤 banner。
4. **微互動**：save bar 滑入滑出、toast 進出、drawer 彈性曲線、badge 數字跳動、表格列 hover 浮起 1px——全部 CSS transition，無 JS 動畫庫也能到位。
5. **數字排版**：表格與金額一律 `tabular-nums`；大數字（指標卡）用比例數字。
6. **圖表守則**（dataviz skill）：單系列不放圖例、2px 線 + 10% 面積、髮絲網格、hover 十字準星 + tooltip、附表格視圖、色板過驗證器——已執行。
7. **圖示紀律**：全站只用 Lucide 一套、20px、stroke 1.5、永遠配 accessibilityLabel。
8. **對比與無障礙**：文字 ≥4.5:1、聚焦環一律可見、觸控目標 ≥44px（行動版）。
9. **中文排版**：中英文混排加 0.02em 字距、標點懸掛不強求、行長 ≤38em。
10. **攝影規格**（storefront）：統一暖色調、同機位商品圖、3:4；demo 期用「藝術指導級佔位圖」（漸層+服裝線稿+顆粒），真攝影可隨時替換——**佔位圖也必須美**。

## 5. 需要用到的 skills / 代碼 / 資產

### Skills（Claude 側，逐階段實際調用）

| Skill | 用在哪 |
|---|---|
| `dataviz` | 所有圖表（指標卡 sparkline、銷售曲線、報表）——本回合已用：色板已跑 validate_palette.js |
| `design:design-critique` | 每批 mockup 出稿後跑一輪結構化 critique，修完再給你看 |
| `design:accessibility-review` | 每個里程碑的 WCAG AA 稽核（對比/鍵盤/讀屏） |
| `design:design-system` | M0 時把 3a/3b tokens 落成正式元件文檔（變體/狀態/用法） |
| `design:ux-copy` | 按鈕文案、空狀態、錯誤訊息的中文微文案打磨 |
| `theme-factory`（如可用）/ 自製 | storefront 多主題化時的風格變體 |

### 代碼（建置期）

| 層 | 選擇 |
|---|---|
| 樣式 | Tailwind v4 + CSS variables（tokens 單一真相）；mockup 期純手寫 CSS |
| 元件原語 | Radix UI（Popover/Dialog/Tabs/Toast/Combobox，headless、MIT） |
| 表格 | TanStack Table（IndexTable 引擎） |
| 表單 | react-hook-form + zod（dirty → SaveBar） |
| 動效 | CSS transitions 為主；複雜編排才用 framer-motion |
| 圖表 | 自寫 SVG（sparkline/線圖，遵守 dataviz 規格）；報表期再上 recharts 客製 |
| 圖示 | lucide-react |
| 字體 | Inter、Noto Sans TC、Fraunces（皆開源授權，self-host woff2） |

### 資產與參考物

- 佔位圖系統：自製 SVG 服裝線稿 ×8 + 暖色漸層庫（demo 內建）；真攝影期換 Unsplash（免費授權）或品牌拍攝。
- 參考截圖庫（僅供比對，不進代碼）：建 `docs/design/references/` 存我們要對齊的密度/留白基準。
- ⚠️ 授權紅線重申：不用 @shopify/polaris、Polaris icons、Dawn 代碼與其插畫（02 §1）。

## 6. 高保真原型的製作與迭代流程

```
每批畫面：
1) 我出可交互 HTML mockup（單檔、真內容、全狀態）→ 存成 artifact 給你點
2) 我自跑 design:design-critique + 對照 §4 工藝清單自檢 → 修
3) 你看 → 用一句話級回饋（「這裡太擠」「色太冷」）→ 我修到你點頭
4) 定稿的 mockup = 開發規格 → M0+ 直接照抄進 React/Rails（tokens 同源，不會走樣）
```

- mockup 是**規格而不是丟棄品**：CSS 變數與 class 命名與正式代碼一致，遷移成本近零。
- 節奏：每批 2–4 個畫面，48 小時內迭代一輪。

## 7. 畫面清單與製作順序

**商家後台**（優先）：① Home（指標+圖表+待辦）② 商品列表 ③ 商品詳情 ④ 訂單列表 ⑤ 訂單詳情 ⑥ 結帳設定頁 ⑦ Analytics ⑧ 折扣建立 ⑨ 顧客詳情 ⑩ 主題編輯器三欄
**Storefront**：① 首頁 ② Collection 頁 ③ 商品頁 ④ Cart drawer ⑤ Checkout（信任感設計獨立處理）⑥ 訂單完成頁
**平台後台**：① 租戶列表 ② 平台指標 ③ 任務/事件監控（其餘沿用元件即得）

## 8. 本回合已附的兩個示範（品質基準線）

1. `chilllove-admin-preview.html`——商家後台可交互 mockup：Home（指標卡 sparkline + 30 天銷售曲線含十字準星 tooltip + 表格視圖）、商品列表（tabs/搜尋/篩選 pills/全選 bulk bar/badge）、商品詳情（**編輯任何欄位 → save bar 滑入 → 儲存 → toast**）、訂單列表（雙狀態 badge + 風險標記）、⌘K command palette。
2. `chilllove-storefront-preview.html`——CHILL LOVE 前台首頁：announcement bar、serif hero、精選商品（hover 換圖+快速加購）、品牌敘事區、**加入購物袋 → cart drawer 滑出 + 免運進度條 + 數量加減**、newsletter、完整 footer。

這兩個檔案就是之後所有畫面的品質下限。看完直接回饋，我逐輪修。
