# 48 — CHILL LOVE 元件契約（高保真交互實作規格）

> **用途**：這是給實作者（Codex）的單一操作手冊。拿著它就能把交互寫到與實測基準無差別，不需要再回頭問「這個態長怎樣」。每個元件固定給滿七節：**解剖／完整態表／動效／鍵盤與焦點／響應式／邊界情況／實作備註**。
>
> **權威順序**（衝突時由上往下勝出）：
> 1. `docs/design/47-measured-interaction-spec.md` — 幾何、動效、字級的**量測真值**（本次唯一權威）
> 2. 本文件 §00「新增 token」— 47 未量到、但實作必需的補值（每條標明推導依據）
> 3. `docs/research/44-live-shopify-teardown-2026-08.md` — 元件的**存在性、結構、行為**
> 4. `docs/design/34-responsive-cross-device-spec.md` — 斷點與斷點下的轉換規則
> 5. `docs/design/23-interaction-css-spec.md` — 舊 token 表，**凡與 47 衝突一律作廢**（作廢對照見 §0）
>
> **法務邊界（CLAUDE.md 鐵律 9）**：本文件只描述 CHILL LOVE 自有實作。全文**不含任何第三方 class 名、選擇器、變數名或 CSS 原始碼**；結構描述來自 44 號的行為觀察，尺寸來自 47 號的量測數字（等同拿尺量畫面），色值全部是我們自有調色。
>
> **關於範例中的文字（重要）**：本文件 HTML 骨架與態表中出現的中文字串，一律是**佔位文案**，作用是說明「這個位置放什麼性質的內容、長度大概多少」。**它們不是最終文案**。真正的 UX 文案由我們自己撰寫，術語表以 `46c §6 結論 8` 為準（庫存四欄用 `無法供貨/已承諾/可供貨/現有庫存`、`最終銷售品項`）。實作時若直接沿用範例字串，PR 一律打回。**唯二例外**（這兩者是格式契約不是文案）：字元計數器的 `已使用 {n}/{max} 個字元` 格式（§31.1）、狀態 badge 的「過去式單詞」規則（§11.2）。
>
> **命名規範**：全部 `cl-` 前綴。block `cl-x`／element `cl-x__y`／modifier `cl-x--z`／狀態 `is-*`、`has-*`。JS 掛勾一律用 `data-cl-*` 屬性，**不得拿樣式 class 當 JS 選擇器**。
>
> **數值規範（硬性）**：元件 CSS 內**不得出現裸數值**，一律 `var(--token)`。Code review 用 `/:\s*-?\d+(px|rem|ms|s)\b/` 掃 diff，命中即打回。
>
> **僅五個例外**（其餘一律視為違規）：
> 1. `0`、`100%`
> 2. `1px`（僅限 `border-width`，且應優先用 `--bw-100`）
> 3. **media query 的條件式**（`@media (max-width: 767px)`）——CSS 自訂屬性不能用在條件式，斷點必須是建置期常數（見 §00.13）
> 4. **`font-size: 16px` 在 ≤767 的輸入類控件**——這不是設計值，是 iOS Safari 的行為約束（<16px 會觸發聚焦自動放大）
> 5. **SVG／`<img>` 的 `width`/`height` 屬性**——這是防 CLS 的必要標註（34 §規則 9），不是樣式

---

## §00 本文件新增的 token（47 號未涵蓋）

> 規則：47 號有的**原名照用**，一個都不改。以下是 47 沒有、但寫元件一定會用到的補值。**每一條都標推導依據**；標「〔待覆核〕」者需在 47 §7 桌機補測後回頭確認。

### 00.1 控件高度（47 §4 有階梯、無命名）

```css
--ctl-24: 24px;   /* 檢視 tab（47 §4 實測） */
--ctl-28: 28px;   /* icon 按鈕、搜尋欄、可排序表頭鈕、小按鈕、分頁鈕（47 §4 實測） */
--ctl-32: 32px;   /* 標準按鈕／輸入／select／表格資料列（47 §4 實測） */
--ctl-36: 36px;   /* 頂欄控件、批次操作列（47 §4「加上 36（頂欄）共四階」） */
--ctl-40: 40px;   /* ≤767 觸控放大態（34 §2 規則 8：iOS 聚焦不放大的最小安全高） */
--ctl-44: 44px;   /* ≤767 主要行動鈕（WCAG 2.5.5） */
```

### 00.2 命中區（47 #86 有規則、無數值命名）

```css
--hit-row: 32px;  /* 列級命中區：checkbox 只有 16px，靠整列 32px 補償（47 #86） */
--hit-min: 44px;  /* 觸控最小命中區（WCAG 2.5.5、23 §4.8） */
```

### 00.3 圓角補充（47 §2 四階之外）

```css
--r-000: 0;       /* 堆疊卡片中段、可排序表頭鈕（47 §4 實測表頭鈕圓角 0） */
--r-pill: 999px;  /* badge／pill／藥丸。h≤36 時與 --r-400 視覺等價，但不隨高度失真 */
```

### 00.4 邊框寬

```css
--bw-100: 1px;    /* 預設框線 */
--bw-200: 2px;    /* 選取態外框、tab 底線、編輯器選取框（44 §21.4 實測 2px 選取外框） */
```

### 00.5 焦點環（47 §5 M3 只說「怎麼動」，沒說「動到什麼」）

```css
--focus-ring-w: 2px;        /* 沿用 23 §3「焦點環 2px offset 1px，全元件一致」 */
--focus-ring-offset: 1px;
--focus-ring: var(--focus);
--focus-glow: 0 0 0 2px color-mix(in srgb, var(--focus) 18%, transparent); /* 輸入框內光暈 */
--focus-glow-critical: 0 0 0 2px color-mix(in srgb, var(--critical) 14%, transparent);
```

### 00.6 中性階補位（47 #89「只取層級關係」，我們缺 5 個層）

> 47 §6 量到的層級事實：`頁底 < 卡片`、`主文字/次文字兩級`、**`次級按鈕底比頁底深一階`**。
> 23 §1 的 `--surface-2` 目前**比 `--bg` 淺**，直接拿去當次級按鈕底會反轉層級 → 補 `--surface-sunken`。

```css
--surface-sunken:  #e9e9eb;  /* 次級/tertiary/icon 按鈕靜置底、鍵盤 kbd 底。必須深於 --bg */
--surface-hover:   #f0f0f2;  /* M1 的 hover 目標色（原型有 #ededee/#fafafc/#f0f0f2 三種，統一） */
--surface-active:  #e4e4e7;  /* 按下態（比 hover 再深一階） */
--surface-inverse: #1a1b1d;  /* 深底浮層：批次列／toast／save bar（原型硬編 8 處） */
--text-inverse:    #ffffff;
--border-strong:   #c9cace;  /* 輸入框／可編輯控件框線（原型硬編 15 處，23 §1 漏了這個 token） */
--selected-bg:     #f0f5ff;  /* 表格選取列底（原型硬編 3 處） */
--disabled-opacity: .45;     /* 23 §3 有值未 token 化 */
--scrim: rgba(26,28,30,.42); /* modal／drawer／sheet 遮罩 */
```

### 00.7 語意色的框線階（23 §1 只有 bg+fg 兩色，banner 需要第三個）

```css
--success-border:  color-mix(in srgb, var(--success) 26%, #fff);
--warning-border:  color-mix(in srgb, var(--warning) 26%, #fff);
--critical-border: color-mix(in srgb, var(--critical) 26%, #fff);
--attention-border:color-mix(in srgb, var(--attention) 26%, #fff);
--info-border:     color-mix(in srgb, var(--info) 26%, #fff);
--ai-border:       color-mix(in srgb, var(--ai) 22%, #fff);
```

### 00.8 陰影（47 未量；沿用 23 §1 並補兩階）

```css
--sh:        0 1px 2px rgba(26,28,30,.05), 0 1px 6px rgba(26,28,30,.04);  /* 卡片 */
--sh-sticky: 0 1px 0 var(--border-2), 0 2px 6px rgba(26,28,30,.06);       /* sticky 表頭吸附後 */
--sh-pop:    0 12px 32px rgba(26,28,30,.16);                              /* popover／選單 */
--sh-modal:  0 24px 64px rgba(26,28,30,.35);                              /* modal／drawer／sheet */
```

### 00.9 z-index（23 §1 有散列、未 token 化；47 完全沒有）

```css
--z-content: 0;   --z-sticky: 3;    --z-bulkbar: 5;   --z-shell: 40;
--z-scrim: 44;    --z-settings: 50; --z-drawer: 60;   --z-savebar: 65;
--z-sheet: 70;    --z-overlay: 80;  --z-modal: 81;    --z-popover: 85;
--z-toast: 90;    --z-docpop: 95;
```

**兩條硬規則**：① `--z-popover(85) > --z-modal(81)` —— modal 內的 select／日期選擇器必須能蓋在 modal 上；② `--z-toast(90) > 全部浮層` —— toast 永遠可見，但 ≤767 要用 `:has()` 讓位給 bulkbar／save bar（34 §已定）。

### 00.10 動效補充（47 §5 缺）

```css
--dur-shimmer: 1200ms;     /* skeleton（23 §5 沿用） */
--dur-shake: 300ms;        /* Modal 驗證失敗（47 #88 只說有此動畫，未給參數） */
--shake-amp: 5px;          /* 〔推導〕沿用原型既有的 ±5px 位移量 */
--dur-toast-dwell: 2600ms; /* toast 停留（23 §3 沿用） */
--dur-bar-grow: 500ms;     /* 條圖生長（23 §5 沿用，不屬 M1–M7） */
--ease-linear: linear;
```

### 00.11 字級補充

```css
--t-2xs:     11 / 16 / 500;  /* 鍵盤鍵帽、分組標題（大寫加字距）、浮層註腳。23 §1 已在用，47 未量 */
--t-3xl:     24 / 32 / 450;  /* 〔待覆核〕桌機頁標題、空態標題、指標卡大數 */
--t-display: 32 / 40 / 450;  /* 〔待覆核〕頂層 404 主標、帳單累積總計（44 §19.4 的 display 級數字） */
```

⚠ **47 §3 的一個未解衝突（實作前必看）**：`--t-xl` 是 `18/24/500`，`--t-2xl` 也是 `18/24/500`（表上寫「27→18」是 150% 縮放還原後的值）。**兩階撞值，實作無法區分**。且 §8 #83 說「大標題字重降到 450」，但表上只有 `--t-lg`(16) 是 450，更大的 `--t-xl`／`--t-2xl` 反而是 500。**本文件的處置**：`--t-xl`／`--t-2xl` 原值照用（用於 ≤767 窄版），桌機（≥768）的頁標題改用新增的 `--t-3xl`（24/32/450），符合 #83 的意圖。**47 §7 桌機補測後必須回頭定案。**

### 00.12 版面尺寸（47 §0 有量測、無命名；其餘取自 34／23）

```css
--h-topbar: 56px;            /* 47 §0 實測 */
--w-sidebar: 240px;          /* 47 §0 實測 15rem */
--w-index-max: 1200px;  --w-detail-max: 998px;   --w-aside: 300px;
--w-narrow: 630px;           /* 單欄置中編輯器（44 §19.7 選單編輯器實測 ~630px） */
--w-settings-content: 660px; --w-settings-nav: 270px;
--w-modal-sm: 400px; --w-modal: 520px; --w-modal-lg: 720px;
--w-drawer: 380px;   --w-popover-min: 180px; --w-popover-max: 320px;
--w-search-shell: 600px;     /* 頂欄全域搜尋最大寬（23 §2） */
--w-search-shell-m: 420px;   /* 同上，1024–1279 */
--w-crumbtitle: 240px;       /* 編輯器頂欄兩行標題的截斷寬 */
--art-lg: 200px; --art-md: 140px; --art-sm: 100px;  /* 空態插圖三階 */
--art-404: 280px;            /* 頂層 404 插圖 */
--sp-800: 32px;              /* 頁邊（23 §1 慣用值，47 的七階止於 24，這是版面層不是元件層） */
--sp-1200: 48px;             /* 全頁空態的垂直內距 */
```

**`--sp-800`／`--sp-1200` 的使用邊界**：**只准用在版面容器**（`.cl-page`、`.cl-empty--page`）。元件內部一律只能用 47 的七階（2/4/6/8/12/16/24）。

### 00.13 斷點（47 完全沒有；取自 34 §1）

```
L   ≥1280        設計基準寬，不下任何 media query
M   1024–1279    收邊距、格線降階、表格改橫捲
S   768–1023     側欄轉抽屜、兩欄轉單欄
XS  430–767      表格轉卡片、modal 轉貼底 sheet、輸入 16px/40 高
XXS ≤429         全單欄、按鈕撐滿、隱藏次要標識
```

⚠ **CSS 自訂屬性不能用在 media query 條件式**。斷點必須是建置期常數（PostCSS custom-media 或 Tailwind screens），寫法一律 `max-width`（desktop-first，理由見 34 §1）。

⚠ **47 的量測全部在 683px 有效視口（窄版）取得**。本文件把 47 的控件高度階視為 **S/XS 帶的真值**，桌機（≥1280）沿用同一階梯直到 47 §7 補測推翻為止。這是本文件最大的已知風險。

---

## §0 修正對照（47 §8 #81–#89 逐條展開）

> 格式：**23 號原本寫什麼 → 改成什麼 → 影響哪些原型檔案的哪些選擇器**。
> 原型檔案代號：**A** = `docs/design/chilllove-admin-v2.html`；**P** = `docs/design/chilllove-platform-admin.html`；**S** = `docs/design/chilllove-storefront-v2.html`；**A1** = `chilllove-admin-preview.html`；**S1** = `chilllove-storefront-preview.html`。行號為改版當下的位置，以選擇器名為準。

### #81 間距階 10 階 → 7 階（2/4/6/8/12/16/24）

| | 內容 |
|---|---|
| **23 原文** | §1「**間距**：4px 網格。慣用：卡 padding 16、卡間 gap 16、表格 cell `8px 12px`、listbar `8px 12px`、頁邊 32、區塊間 24。」——只有慣用值敘述，**沒有 token**，導致原型自由發揮出 5/7/9/10/13/14/18px 等 off-scale 值 |
| **改成** | 七階 token 化：`--sp-050:2 --sp-100:4 --sp-150:6 --sp-200:8 --sp-300:12 --sp-400:16 --sp-600:24`。元件內部**只准用這七個**。版面層另有 `--sp-800:32`（頁邊）、`--sp-1200:48`（全頁空態），見 §00.12 |
| **影響 A** | `.btn{padding:0 14px}`→`0 var(--sp-300)`｜`.btn-sm{padding:0 10px}`→`0 var(--sp-200)`｜`.view-chip{padding:5px 10px}`→`0 var(--sp-300)`＋`height:var(--ctl-28)`｜`.nav-item{padding:6px 10px;gap:9px}`→`var(--sp-150) var(--sp-300);gap:var(--sp-200)`｜`.nav-sub{padding:5px 10px 5px 36px}`→`var(--sp-150) var(--sp-300) var(--sp-150) calc(var(--sp-600)+var(--sp-300))`｜`.input{padding:0 10px}`→`0 var(--sp-300)`｜`.banner-err{padding:10px 14px}`→`var(--sp-300) var(--sp-400)`｜`.modal-head{padding:14px 18px}`／`.modal-foot{padding:12px 18px}`／`.dtype{padding:13px 18px}`／`.palette input{padding:16px 18px}`→ 全部 `var(--sp-300) var(--sp-400)`｜`.toast{padding:10px 16px;gap:10px}`→`var(--sp-300) var(--sp-400);gap:var(--sp-300)`｜`.savebar{padding:8px 10px 8px 16px}`→`var(--sp-200) var(--sp-200) var(--sp-200) var(--sp-400)`｜`.set-nav{padding:14px}`／`.plan{padding:14px}`→`var(--sp-400)`｜`.task-chip{padding:7px 16px}`→`height:var(--ctl-32);padding:0 var(--sp-400)`｜`.pal-foot{gap:14px}`→`var(--sp-400)`｜`.od-line{gap:12px}` 已合規 |
| **影響 P** | `.filter-chip{padding:0 10px}`→`0 var(--sp-200)`｜`.tab{padding:0 12px}` 已合規｜`.toast{padding:9px 18px}`→`var(--sp-300) var(--sp-400)` |
| **影響 S** | 前台是另一套節奏（23 §1 末條：區塊垂直 96–128），**不受本條約束**；但 S 的 admin 風格控件（表單、按鈕）要跟進 |

### #82 UI 預設字級 14px → 13px（行高 20）

| | 內容 |
|---|---|
| **23 原文** | §1「字級 scale（只准用這些）：11、12、13（正文/表格/按鈕）、**14（強調正文/hero 副標）**、16（保留）、20、24；行高 **1.45–1.6**」 |
| **改成** | ① UI 預設＝`--t-sm`（13/20/500），**行高鎖死 20，不再用 1.45–1.6 比例**（比例算出 18.85–20.8，會讓控件高度階飄掉）；② **表格內容與欄位標題降到 `--t-xs`（12/16/500）**——這是 47 §3 標的「最高頻資料字級」；③ 14px 收斂為 `--t-md`，**只准用在次要標題**，不再當「強調正文」 |
| **關鍵副作用** | 表格列高的算術從此對齊：`--t-xs` 行高 16 ＋ 上下 `--sp-200`(8) = **32 = `--ctl-32`**。表頭同理：可排序表頭鈕 `--ctl-28` ＋ 上下 `--sp-050`(2) = 32。**兩者相等是刻意的**，別改 |
| **影響 A** | `table.idx{font-size:13px}`→`--t-xs`｜`.idx th{font-size:12px;font-weight:600}`→`--t-xs`（weight 600→500）｜`.ai-box input{font-size:14px}`／`.palette input{font-size:14px}`→`--t-sm`（**輸入框一律 13**）｜`.empty-wrap b{14px}`→`--t-3xl`（空態標題升級，見 §24）｜`.setup-card h4{14/700}`／`.plan b{14px}`→`--t-md`｜`.p-item .p-val{14/700}`／`.p-live b{14px}`→`--t-md`（數值另見 #83）｜`.hero-hello p{14px}`→`--t-md`｜`.logo{14/700}`→`--t-md`＋weight 500｜`.idx td.cell-lead{14/600}`（≤767 卡片化的標題列）→`--t-md` |
| **影響 P** | 所有 `font-size:13px` 的表格內文 → `--t-xs`；`.btn{font-size:13px}` 維持 `--t-sm` |
| **影響 A1/S1** | 兩份 preview 為早期稿，**不追改**，標記為 deprecated（見 §0.10） |

### #83 大標題字重 → 450，小字級才用 500

| | 內容 |
|---|---|
| **23 原文** | §1 沒有字重表；§3 只寫「選中＝600 字重」。原型一律 600/700 做標題 |
| **改成** | 字重跟著字級走，**不再自由指定**：`--t-xs/--t-sm/--t-md/--t-xl`＝500；`--t-lg`(16)＝**450**；新增的 `--t-3xl`／`--t-display`＝**450**。「強調」不靠 weight，靠**色階**（`--text-2`→`--text`）與**間距** |
| **例外（唯一）** | 導航選中態、選單當前項可用 500→600 一階提升，因為那是「同字級內的區分」，不是標題階層 |
| **影響 A** | `h1{20/700}`→`--t-3xl`（24/32/450，≥768）／`--t-2xl`（≤767）｜`.hero-hello h2{24/700}`→`--t-3xl`｜`.setup-card h4{14/700}`→`--t-md`(500)｜`.card h3{13/600}`→`--t-sm`(500)｜`.modal-head{font-weight:700}`→`--t-md`(500)｜`.btn{font-weight:600}`→**500**（47 §3 實測按鈕就是 13/20/500）｜`.task-chip{600}`／`.view-chip{600}`／`.seg button{600}`／`.fsel{600}`→500｜`.plan .pp{20/700}`→`--t-3xl`｜`.pay-row.total{700}`→500＋`--text`｜`.nav-item.on{600}` **保留**（例外條款）｜`.p-item .p-val{700}`→`--t-md`(500) |
| **影響 P** | `.btn{font-weight:600}`→500；所有 `h1/h2/h3` 同 A 規則 |

### #84 圓角四階 4/8/12/18 ＋ 堆疊卡片單邊圓角

| | 內容 |
|---|---|
| **23 原文** | §1「`--r-card:12px; --r-btn:8px; --r-pill:999px`」——三個語意名 |
| **改成** | 改為**四階尺寸名**：`--r-100:4 --r-200:8 --r-300:12 --r-400:18`，另加 `--r-000:0`、`--r-pill:999px`。對應：`--r-100`＝最小元素（鍵帽、旗標）／`--r-200`＝**所有控件**（按鈕、輸入、chip、tab）／`--r-300`＝**卡片**（最高頻）／`--r-400`＝大容器與 sheet 上緣 |
| **新規則（原型完全沒有）** | **堆疊卡片群組單邊圓角**：群組內第一張 `border-radius: var(--r-300) var(--r-300) 0 0`、最後一張 `0 0 var(--r-300) var(--r-300)`、中間 `var(--r-000)`，相鄰邊只留一條 `--bw-100` 分隔線（不是兩條疊起來）。詳見 §13.1 |
| **影響 A（off-scale 圓角全清）** | 9px ×9 → `--r-200`：`.searchbox`、`.store-chip`、`.ai-send`、`.set-close`、`.seg`、`.dt-ic`、`.set-search`｜10px ×18 → `--r-300`（浮層／banner／bulkbar）或 `--r-200`（小按鈕）：`.view-menu`、`.banner-err`、`.toast`、`.bulkbar`、`.plan`、`.annot-bar`｜14px ×4 → `--r-400`：`.modal`、`.palette`、`.ai-box`、`.set-nav`｜7px ×6 → `--r-200`：`.logo .heart`、`.avatar`、`.view-menu button`、`.bulkbar .b-act`｜6px ×6 → `--r-100`：`.skeleton`、`.tagchip`、`.ai-row .x`；`.tab{border-radius:6px 6px 0 0}`→`var(--r-200) var(--r-200) 0 0`｜5px `.dev-tag`→`--r-100`｜16px `.setup-art`→`--r-400`｜3px `.flag`→`--r-100`｜`.split .btn:first-child{border-radius:8px 0 0 8px}`→`var(--r-200) 0 0 var(--r-200)` |
| **影響 P** | 同樣把 2/3/5/6/7/9/10/14px 收斂到四階 |

### #85 控件高度四階 24/28/32/36

| | 內容 |
|---|---|
| **23 原文** | §1「佈局常數：topbar 高 **52**；sidebar 寬 **220**；按鈕高 32（sm 28）；輸入高 32；**表格列高 ~40**（8px cell 上下）」 |
| **改成** | 四階 `--ctl-24/28/32/36`（＋響應式的 40/44）。**表格列高 40 → 32**（配合 #82 的 `--t-xs`）。**topbar 52 → `--h-topbar:56`**、**sidebar 220 → `--w-sidebar:240`**（兩者皆為 47 §0 直接量測值） |
| **影響 A** | `.topbar{height:52px}`→`var(--h-topbar)`；連帶 `.frame{height:calc(100vh - 52px)}`、`.scrim{inset:52px 0 0}` 兩處硬編 52 一起改｜`.sidebar{width:220px}`→`var(--w-sidebar)`｜`.searchbox{height:34px}`→`var(--ctl-36)`（頂欄階）｜`.set-search{height:30px}`→`var(--ctl-28)`｜`.hamb{34px}`／`.set-close{34px}`→`var(--ctl-36)`｜`.view-menu{top:34px}`→`calc(var(--ctl-28) + var(--sp-150))`（跟著觸發元高度算，別再硬編）｜`.idx td{padding:8px 12px}` 維持，但因字級改 12/16 而使列高自然落在 32｜`.tab{padding:8px 12px}`→`height:var(--ctl-32);padding:0 var(--sp-300)`｜`.btn{32}`／`.btn-sm{28}`／`.pg{28}`／`.input{32}`／`.filterbar{32}` 皆已合規，改成引用 token |
| **影響 P** | `.tab{height:34px}`→`var(--ctl-32)`；`.filter-chip{height:28px}`→`var(--ctl-28)` |
| **⚠ 風險** | 這四階是 **683px 窄版**量到的。桌機是否同階未經量測（47 §7 第 1/3/5 項）。**桌機沿用同階梯**是本文件的暫定決策 |

### #86 checkbox 16px ＋ 列級 32px 命中區（不放大 checkbox 本身）

| | 內容 |
|---|---|
| **23 原文** | §4.8「觸控目標行動版 ≥44px」——只有原則，沒說 checkbox 怎麼辦；34 號提了 `::before{inset:-Npx}` 但沒指名用在 checkbox |
| **改成** | checkbox 視覺盒鎖死 `16×16`（`--sp-400`），**命中區靠透明偽元素撐開**：桌機 `::before{position:absolute;inset:calc((var(--hit-row) - var(--sp-400)) / -2)}` → 32×32；≤767 換 `--hit-min` → 44×44。**任何情況都不准改 checkbox 的視覺尺寸** |
| **影響 A** | `.cb{width:15px;height:15px}`→`16px`＋`position:relative`＋`::before` 命中區｜`.idx td:first-child`／`.cl-table__cell--check` 需 `position:relative` 讓命中區有定位脈絡｜**≤429 的 `.cb{width:20px;height:20px}` 要刪掉**——那是「放大 checkbox 本身」，正是本條禁止的做法，改成擴大 `::before` 到 44｜≤767 卡片化時 checkbox 絕對定位到卡片右上，命中區同樣走 `::before` |
| **影響 P** | 同 A |

### #87 動效系統定案：5 時長 × 3 曲線 ＋ 7 條具名規則；移除所有 `transition: all`

| | 內容 |
|---|---|
| **23 原文** | §1「`--tr:150ms cubic-bezier(.2,.6,.3,1)`；`--tr-big:240ms cubic-bezier(.2,.8,.2,1)`」＋ §5 的九列場景表（含「menu/popover 120–160ms fade+4px 位移」「頁面切換 180ms fade+3px 上移」等自創值） |
| **改成** | `--tr`／`--tr-big` **兩個 token 作廢**。改用 `--dur-fast:100 / --dur-base:150 / --dur-slow:200 / --dur-slower:250 / --dur-slowest:300` × `--ease-standard / --ease-in-out / --ease-decelerate`，並**只准透過 M1–M7 七條具名規則使用**（見 §A.3）。23 §5 整表作廢，唯二保留：skeleton shimmer 1.2s linear、條圖生長 500ms |
| **`transition:all` 清除清單（共 10 處）** | **A**：`.searchbox`(L36)→M1｜`.btn`(L74)→M1+M2｜`.task-chip`(L137)→M1（**順帶移除 `translateY(-1px)` hover 位移**，47 未量到任何 hover 位移）｜`.pg`(L181)→M1+M2。**P**：`.btn`(L96)｜`.filter-chip`(L180)｜`.tab`(L201)｜`.toast`(L298)→M6。**S**：`.btn`(L114)｜`.quick`(L169) |
| **`var(--tr)` 逐處改具名** | `.icon-btn`／`.nav-item`／`.nav-sub`／`.set-item`／`.dtype`／`.pal-item`／`.idx tbody tr`／`.store-chip`→**M1**｜`.input`→**M3**（三屬性同時）｜`.toggle`／`.tgl`→ 底色 M1 ＋ 把手位移 `transform var(--dur-fast) var(--ease-decelerate)`（**改用 transform 不用 left**，避免逐幀 layout）｜`.savebar`／`.toast`→**M6**｜`.scrim`→ `opacity var(--dur-base) var(--ease-in-out)`（M1 的淡入版） |
| **keyframes 統一** | `@keyframes fade .18s`（頁面切換）／`pop .15s`（modal）／`.12s`（選單）／`.14s`（doc-pop）→ 全部改走 **M5**（`opacity + scale`，`--dur-slow`，`--ease-decelerate`）。**`scale` 不是 `transform`**——47 M5 特別標註，避免與位移衝突 |
| **新增** | `@media (prefers-reduced-motion: reduce)` 全域：所有位移／縮放歸零，只留 opacity，時長統一 `--dur-fast`（47 沒寫這條，見 §A.3 末） |

### #88 新增 Modal 驗證失敗 shake

| | 內容 |
|---|---|
| **23 原文** | §3 Modal 欄只寫「overlay／點外 Esc ✕ 關／寬 520／destructive 紅主鈕」——**沒有任何錯誤回饋動效** |
| **改成** | 新增 `@keyframes cl-shake`（`translateX` ±`--shake-amp`，`--dur-shake`，`--ease-standard`）。**觸發條件**：submit 後伺服器/前端驗證失敗，且 **modal 不關閉**時。動的是 **modal 整體含 footer**，不是單一欄位。同時：第一個錯誤欄位 `focus()`、`aria-live="assertive"` 播錯誤摘要。**成功不 shake、關閉不 shake、載入中不 shake** |
| **影響 A** | 現有 `@keyframes nudge`＋`.savebar.nudge`（±5px/.3s，用於「有未存變更卻想離開」）→ **改名 `cl-shake` 並共用**，`--shake-amp` 取其 5px。新增 `.cl-modal.is-invalid{animation:cl-shake var(--dur-shake) var(--ease-standard)}`＋動畫結束移除 class（否則第二次驗證失敗不會重播） |

### #89 中性色只取層級關係，色值用自有調色

| | 內容 |
|---|---|
| **23 原文** | §1 的 `--bg/--surface/--surface-2/--surface-3/--text/--text-2/--text-3/--border/--border-2` 九個中性 token |
| **改成** | **色值全部保留（是我們的品牌資產）**，但要補齊 47 §6 量到的**層級關係**所需的 5 個缺位：`--surface-sunken`（次級按鈕底，**必須深於 `--bg`**）、`--surface-hover`、`--surface-active`、`--surface-inverse`、`--border-strong`（見 §00.6） |
| **關鍵發現** | 47 §6 的層級事實之一是「**次級按鈕底比頁底深一階**」。23 的 `--surface-2:#f7f7f8` **比 `--bg:#f4f4f5` 淺**，拿它當 tertiary／icon 按鈕的靜置底會**反轉層級**。→ 新增 `--surface-sunken:#e9e9eb` 承接這個角色。（我們的 secondary 按鈕維持「白底＋`--border-strong` 框」，因為它主要出現在白卡上，這是我們自有的視覺選擇，與層級事實不衝突） |
| **影響 A（硬編色清除）** | `#c9cace` ×15 處 → `var(--border-strong)`：`.btn-sec`、`.input`、`.task-chip:hover`、`.filterbar`、`.toggle`、`.tgl`、`.idx td .cellin`、`.codebox`、`.ftile:hover`、`.dropzone`｜`#1a1b1d` ×8 → `var(--surface-inverse)`：`.bulkbar`、`.toast`、`.savebar`、`.doc-pop`｜`#f0f5ff` ×3 → `var(--selected-bg)`｜`#ededee`／`#fafafc`／`#f0f0f2`／`#e8e8ea` → 統一 `var(--surface-hover)`｜`#a9aaae`（`.input:hover`）→ `color-mix` 自 `--border-strong`｜`.banner-err` 的 `#f2c4cb` → `var(--critical-border)`｜`.skeleton` 的 `#ededef/#f6f6f7` → `var(--surface-hover)/var(--surface)` |
| **影響 P** | 同一組硬編色，同一組替換 |

### §0.10 其它連帶處置

| 項 | 處置 |
|---|---|
| **#80**（44 全部截圖須加註「~683px 窄版佈局」） | 屬 44 號自身的註記工作，不影響實作。但**本文件所有引用 44 的版面比例（如「主欄 615／側欄 310」）一律視為窄版值，不得當桌機值用** |
| **#90**（桌機三欄補測 6 項） | 未完成。本文件凡受影響處都標 〔待覆核〕，共 6 處：`--t-3xl`／`--t-display`／桌機控件高度階／設定頁雙欄寬／編輯器三欄寬／Modal 桌機最大寬階 |
| `chilllove-admin-preview.html`、`chilllove-storefront-preview.html` | **deprecated**，不追改。M0 起以 `chilllove-admin-v2.html`／`chilllove-storefront-v2.html`／`chilllove-platform-admin.html` 三份為準 |
| 23 號本身 | §1 token 區塊、§5 動效表 **整段作廢**，改為指向本文件 §00 與 §A.3。23 §2（佈局結構）、§4（全域交互原則）、§6（遷移指引）**繼續有效** |

### §0.11 來自 44 號的元件級修正（不在 47 §8 範圍，但同樣要改）

| 44 行動項 | 23 原本 | 改成 | 影響 |
|---|---|---|---|
| **#74** | §3 SaveBar「v1 頂部橫列 或 v2 右下浮動，**定案：右下浮動**」 | **save bar 取代整條搜尋／篩選列**（原地替換，不疊加）；右下浮動形態**作廢** | A `.savebar` 整個重寫（見 §26） |
| **#62／#50** | 只有一種存檔模式 | **三種並存**：save bar（有列表列的頁）／頁尾儲存鈕（單欄置中表單）／編輯器頂欄儲存鈕（全螢幕編輯器）。判定規則見 §26.0 | A 新增 `.cl-savefoot`、`.cl-editorbar__save` |
| **#41** | 只有 pri/sec/ghost/sm 四型 | 新增 **destructive-secondary**（白底紅框紅字，放卡片 footer bar）；A 已有 `.btn-danger-o` 但未納規格 | A `.btn-danger-o` → `.cl-btn--destructive-secondary` |
| **#53** | 只有單行 inline banner | 新增 **雙層 banner**（標題條＋內文區） | A 新增 `.cl-banner2`（見 §22） |
| **#75** | 無 | 新增 **AI 建議 inline 列**（紫，混在資料列中，可 dismiss）——第三種提示層級 | A 已有 `.ai-row` 雛形，補全態表（見 §23） |
| **#67** | 無 | 新增 **CollapsedEditCard**（標題＋✏＋一句說明，點才展開） | A 新增（見 §14） |
| **#64／#65** | §3 EmptyState 只有一種 | **兩種**：全頁空態（插圖→標題→說明→1~2 鈕→卡外「深入瞭解」）／卡內空態（單行灰字，無插圖） | A `.empty-wrap` 拆兩個（見 §24） |
| **#79** | 無 | **兩種 404**（頂層水平版／區段內垂直版），樣式與 CTA 都不同 | A 新增（見 §25） |
| **#54** | §3「未來：尾端『＋』另存目前篩選為新檢視」 | 已是標配，**全列表統一**必須有 saved-view tabs ＋ `+` | A `.view-chip` 改 tabs 形態（見 §10） |
| **#59** | 無 | **bottom sheet**（含拖曳把手），且**桌機 1024 也用此形態** | A 新增（見 §18） |
| **#44** | §3 Skeleton 只寫 shimmer | 列 skeleton ＝ **圓形 icon 佔位 ＋ 長條文字佔位**，三列 | A `.skeleton` 補 `--circle` 變體（見 §12.10） |
| **#46** | 無 | 字元計數器統一 `已使用 {n}/{max} 個字元` | A 新增（見 §31） |
| **#13** | 無 | 空資料時的 `匯出` 鈕 **disabled 而非隱藏** | 全域規則（見 §A.2） |

---

## §A 共通約定（所有元件都適用，不再逐一重述）

### A.1 九個態的定義與優先序

| 態 | 定義 | CSS 掛法 |
|---|---|---|
| `default` | 可互動、未被指標或鍵盤觸及 | 基礎規則 |
| `hover` | 指標懸停。**只在 `@media (hover:hover)` 內生效** | `:hover:not(:disabled)` |
| `active` | 按下未放開（含 Space 按住） | `:active:not(:disabled)` |
| `focus-visible` | 鍵盤導覽抵達。**永不使用 `:focus`**（滑鼠點擊不該出環） | `:focus-visible` |
| `disabled` | 不可互動、**保留在 DOM 與無障礙樹**（讓使用者知道有這個功能） | `:disabled` / `[aria-disabled="true"]` |
| `loading` | 動作進行中，**尺寸不得跳動** | `.is-loading` ＋ `aria-busy="true"` |
| `error` | 驗證失敗 | `.is-invalid` ＋ `aria-invalid="true"` |
| `selected` | 被選取／當前項 | `.is-selected` / `aria-selected` / `aria-current` |
| `read-only` | 可讀可選取可複製、不可改 | `[readonly]` / `.is-readonly` |

**優先序（同時成立時誰贏）**：`disabled` > `loading` > `error` > `selected` > `active` > `focus-visible` > `hover` > `default`。
**焦點環是唯一的例外**：`focus-visible` 的環永遠疊加渲染，即使同時是 `error`／`selected`。

**`disabled` vs `aria-disabled` 的選擇**：
- 需要**焦點可達＋可解釋原因**（例如「未變更所以不能存」「有進行中的退貨所以不能取消」）→ 用 `aria-disabled="true"` ＋ 攔截 click，**保留在 Tab 序**，並掛 tooltip 說明原因。
- 純粹不適用（分頁到底、無資料匯出）→ 用原生 `disabled`。
- **44 §6／行動項 13 的規則**：資料為空時，動作鈕 **disabled 而非隱藏**（讓使用者知道功能存在）。

### A.2 焦點環（全站唯一寫法）

```css
.cl-focusable:focus-visible{
  outline: var(--focus-ring-w) solid var(--focus-ring);
  outline-offset: var(--focus-ring-offset);
  border-radius: inherit;                /* 別讓環變方角 */
  transition: outline-color var(--dur-fast) var(--ease-decelerate);  /* M3 */
}
```
- **不准**用 `box-shadow` 模擬焦點環（會被 `overflow:hidden` 的父層裁掉）。**唯一例外**：輸入框的內光暈 `--focus-glow`，那是「額外」不是「取代」。
- 深色底浮層（bulkbar／toast／save bar／編輯器頂欄）上的焦點環改用 `--text-inverse`，`--focus` 在深底上對比不足。
- 焦點**永遠不得被裁切**：任何 `overflow:hidden` 的容器，其內可聚焦子元素要留 `padding: var(--focus-ring-w)` 或改用 `overflow:clip; overflow-clip-margin: var(--sp-100)`。

### A.3 動效規則（47 §5 的 M1–M7，全站只准用這七條）

| # | 規則 | CSS | 何時用 |
|---|---|---|---|
| **M1** | hover 底色 | `background-color var(--dur-base) var(--ease-standard)` | 任何 hover 變底：按鈕、列、選單項、chip、nav |
| **M2** | 文字色 | `color var(--dur-fast) var(--ease-standard)` | 與 M1 成對出現。**比底色快**，避免文字先於底色定格 |
| **M3** | focus／邊框 | `border-color, border-width, box-shadow var(--dur-fast) var(--ease-decelerate)` **三屬性同時** | 輸入框、select、textarea、dropzone、可編輯儲存格 |
| **M4** | 摺疊展開 | `max-height var(--dur-fast) var(--ease-decelerate)` | accordion、CollapsedEditCard、可展開列。**不是 `height`**（避免 reflow） |
| **M5** | 浮層進場 | `opacity, scale var(--dur-slow) var(--ease-decelerate)` | popover、選單、modal、tooltip。**是 `scale` 不是 `transform`**（避免與位移衝突） |
| **M6** | 抽屜／滑入 | `transform var(--dur-slower) var(--ease-standard)` | drawer、bottom sheet、toast、save bar |
| **M7** | 側欄寬度 | `max-width var(--dur-slowest) var(--ease-in-out)` | 常駐側欄收合。**不是 `width`**（避免內容重排） |

**三條補充（47 沒寫，本文件定）**：
- **M0（不動）**：`box-shadow` 之外的**幾何屬性一律不進 transition**。禁止 `transition: height / width / padding / margin / top / left / font-size`。
- **M5 的 scale 起點**：`scale: .96`（浮層）／`scale: .98`（modal）；`transform-origin` 對齊觸發元那一側。
- **reduced motion**：
```css
@media (prefers-reduced-motion: reduce){
  *, *::before, *::after{
    animation-duration: var(--dur-fast) !important;
    animation-iteration-count: 1 !important;
    transition-duration: var(--dur-fast) !important;
    scroll-behavior: auto !important;
  }
  .cl-sheet, .cl-drawer, .cl-savebar, .cl-toast{ transform: none !important; }  /* 位移改純淡入 */
  .cl-skeleton{ animation: none; background: var(--surface-hover); }
  .cl-modal.is-invalid{ animation: none; }   /* shake 停用，改靠 aria-live + 紅框 */
}
```

### A.4 鍵盤全域約定

| 鍵 | 行為 |
|---|---|
| `Tab` / `Shift+Tab` | 依 DOM 序。**禁止正數 `tabindex`**；只准 `0` 與 `-1` |
| `Enter` | 送出（button/link/表單）；在單行輸入內＝送出表單 |
| `Space` | 按下 button／勾選 checkbox／切換 toggle。**在 button 上要 `preventDefault`** 防捲頁 |
| `Esc` | **分層關閉，一次只關一層**。順序：doc-pop → tooltip → popover/選單 → sheet → modal → drawer → 設定 overlay。有未存變更時 Esc 不直接關，先出確認 |
| `↑↓` | 在 listbox／menu／radio group 內移動高亮（**不換焦點時用 `aria-activedescendant`**） |
| `←→` | 在 tablist／segmented 內移動；在表格內移動儲存格（P2） |
| `Home/End` | 跳到第一／最後一項 |
| `字母鍵` | 選單／select 內首字母跳轉（1 秒內連打累積） |

**focus trap 三條**：① 開啟時焦點移到浮層的第一個可聚焦元素（或標題，`tabindex="-1"`）；② Tab 在浮層內循環，`inert` 掉背景；③ **關閉時焦點必須回到觸發元**（存 `WeakRef`，觸發元若已卸載則回到最近的 landmark）。

### A.5 響應式共通轉換（34 §2 已定，這裡只列元件會用到的）

| 斷點 | 元件級轉換 |
|---|---|
| ≥1280 | 基準。不下 media query |
| ≤1279 | 頁邊 `--sp-800`→`--sp-400`；表格改橫捲容器＋黏性首欄；三欄→兩欄 |
| ≤1023 | 側欄→抽屜；詳情兩欄→單欄（側欄卡片移到主欄之後）；popover 仍是 popover |
| ≤767 | 表格→卡片（≤8 欄）；modal→貼底 sheet；輸入 `font-size:16px`＋`height:var(--ctl-40)`（**<16px 會觸發 iOS 聚焦放大**）；主要按鈕全寬＋`--ctl-44`；bulkbar／toast／save bar 貼底＋`env(safe-area-inset-bottom)`；分頁標籤橫捲＋`scroll-snap` |
| ≤429 | 全單欄；次要標識隱藏；並排按鈕改上下堆疊 |

### A.6 CJK 與金額（全元件通用，34 §6 已踩過的坑）

```css
.cl-text  { overflow-wrap: anywhere; line-break: strict; }   /* 長 email/網域/GID/SKU */
.cl-money { white-space: nowrap; font-variant-numeric: tabular-nums; }
```
- **兩者互斥，混用會把 `NT$407,700` 折成兩行**。任何同時含文字與金額的儲存格，**必須拆成兩個 span**。
- CJK 截斷一律 `text-overflow: ellipsis` ＋ `title` 屬性給完整值；**多行截斷用 `-webkit-line-clamp`**，不要用固定高度裁切。
- 中文標題 `letter-spacing: 0`（47 §3：字距一律 normal）。**23 §1 的「中文標題字距 0」保留，其餘元素也一律 normal**，原型 `body{letter-spacing:.01em}` 要移除。

### A.7 每個元件的 HTML 骨架共同要求

1. **語意標籤優先**：可點且會導航→`<a>`；可點且觸發動作→`<button type="button">`（**永遠寫 `type`**，預設 submit 會誤送表單）；清單→`<ul>/<li>`；表格→真 `<table>`。
2. **icon-only 一律 `aria-label`**；裝飾性 icon `aria-hidden="true"`。
3. **不要用 `div` + `onclick`**。若不得已（整列可點），必須：`tabindex="0"` ＋ `role` ＋ `keydown` 處理 Enter/Space ＋ 內層真 `<a>` 作為主要語意入口。
4. **狀態同時寫 class 與 aria**：`.is-selected` 給樣式、`aria-selected` 給輔具。兩者不同步是最常見的 a11y bug。

---

# 元件契約

> 每節固定七小節。**來源**行標明該元件的實測出處。**〔推導〕**標記表示 47/44 沒有直接量到、由既有 token 推算而來的值。

---

## §1 按鈕 `cl-btn`

**來源**：47 §4（icon 按鈕 28×28／內距 4px／圓角 8px）、47 §3（按鈕字級 13/20/500）、47 §5（M1/M2）、44 §2.2（split button `標記為已出貨 ⌄`）、44 §18.1（並排 primary＋secondary）、44 §19.3／行動項 41（destructive-secondary 白底紅框放卡片 footer bar）、44 §6／行動項 13（無資料時 disabled 而非隱藏）、44 §19.5（primary 深色放頁首右）。

### 1.1 解剖

```
cl-btn  (inline-flex, align-items:center, justify-content:center)
├─ cl-btn__icon-start   16×16, flex:none, aria-hidden
├─ cl-btn__label        --t-sm, white-space:nowrap
├─ cl-btn__count        可選；數字徽章，--t-2xs, --r-pill, --sp-050 內距
├─ cl-btn__icon-end     16×16（split 的 ⌄ 不在這裡，見 1.8）
└─ cl-btn__spinner      loading 時絕對定位置中，16×16
```

| 層 | 高 | 內距 | 圓角 | 字級 | gap |
|---|---|---|---|---|---|
| `cl-btn`（標準） | `--ctl-32` | `0 var(--sp-300)` | `--r-200` | `--t-sm` | `--sp-150` |
| `cl-btn--sm` | `--ctl-28` | `0 var(--sp-200)` | `--r-200` | `--t-sm` | `--sp-100` |
| `cl-btn--lg`（頂欄／表單主鈕） | `--ctl-36` | `0 var(--sp-400)` | `--r-200` | `--t-sm` | `--sp-200` |
| `cl-btn--icon` | `--ctl-28`（正方） | `var(--sp-100)` | `--r-200` | — | — |
| `cl-btn--icon.cl-btn--lg` | `--ctl-36`（正方） | `var(--sp-200)` | `--r-200` | — | — |

**七個變體的靜置外觀**：

| 變體 | 底 | 字 | 框 | 陰影 | 用在哪 |
|---|---|---|---|---|---|
| `--primary` | `--brand` | `--text-inverse` | 無 | `inset 0 1px 0 rgba(255,255,255,.12), 0 1px 2px rgba(26,28,30,.2)` | 每個視圖**最多一顆** |
| `--secondary` | `--surface` | `--text` | `--bw-100 var(--border-strong)` | `--sh` | 次要動作、並排第二顆 |
| `--tertiary` | `--surface-sunken` | `--text` | 無 | 無 | 卡內密集動作列、工具列（**這是 47 §6「次級按鈕比頁底深一階」的承接者**） |
| `--plain` | 透明 | `--text-2` | 無 | 無 | 列內文字動作、「深入瞭解」、卡頭右上動作 |
| `--destructive` | `--critical` | `--text-inverse` | 無 | 同 primary | **只用在確認 modal 的主鈕** |
| `--destructive-secondary` | `--surface` | `--critical` | `--bw-100 var(--critical-border)` | 無 | **卡片 footer bar 的破壞性入口**（刪除商店、刪除帳號） |
| `--icon` | 透明（或 `--surface-sunken` 當常駐工具） | `--text-2` | 無 | 無 | 表頭工具、列尾動作、關閉鈕 |

### 1.2 完整態表

| 態 | primary | secondary | tertiary / plain / icon | destructive | destructive-secondary |
|---|---|---|---|---|---|
| **default** | 見上表 | 見上表 | 見上表 | 見上表 | 見上表 |
| **hover** | `background: --brand-hover` | `background: --surface-hover`；`border-color` 深一階 | `background: --surface-hover`；`color: --text` | `background:` 深一階 | `background: --critical-bg` |
| **active** | `background: --brand-hover`；`box-shadow: inset 0 1px 2px rgba(0,0,0,.18)`（微沉，**不位移**） | `background: --surface-active`；`box-shadow:none` | `background: --surface-active` | 同 primary 邏輯 | `background: --critical-bg`；`box-shadow: inset …` |
| **focus-visible** | 疊 `outline: 2px --focus`, offset 1px | 同 | 同 | 同 | 同 |
| **disabled** | `opacity: var(--disabled-opacity)`；`box-shadow:none`；`cursor:not-allowed`；**保留原底色不轉灰**（轉灰會讓 primary/secondary 分不出來） | 同 | 同 | 同 | 同 |
| **loading** | `aria-busy="true"`；**label `visibility:hidden` 但保留佔位**（寬度不得跳動）；spinner 絕對置中 16×16；`pointer-events:none`；同時 `aria-disabled="true"` | 同 | 同 | 同 | 同 |
| **error** | N/A（按鈕不承載錯誤態，錯誤走 banner／toast） | N/A | N/A | N/A | N/A |
| **selected** | N/A | N/A | **只有 `--icon`／`--tertiary` 當 toggle 用時有**：`background: --surface-active`；`color: --text`；`aria-pressed="true"` | N/A | N/A |
| **read-only** | N/A | N/A | N/A | N/A | N/A |

**loading 的兩條硬規則**：① **尺寸不得改變**——用 `visibility:hidden` 保留 label 佔位，不要換成「儲存中…」那種會改寬度的文案（23 §3 的舊寫法作廢）；② loading 至少顯示 **300ms**，否則快速回應會閃一下比不顯示更糟。

### 1.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| `background-color` | **M1** | hover 底色的標準回饋（47 實測 ×14，最高頻互動） |
| `color` | **M2** | 比底色快 50ms，避免文字先於底色定格（plain／icon 變體特別明顯） |
| `border-color`, `box-shadow` | **M3** | secondary 的框與 active 的內陰影 |
| 焦點環 | **M3** | 三屬性同時 |
| spinner | `rotate 700ms linear infinite`（不屬 M1–M7，是持續動畫） | — |

**禁止**：hover 位移（`translateY`）、hover 放大（`scale`）。47 全頁量測**沒有任何 hover 位移**，原型 `.task-chip:hover{transform:translateY(-1px)}` 要移除。

### 1.4 鍵盤與焦點

- Tab 順序＝DOM 序。並排按鈕的 DOM 序 = **視覺左到右**，`primary` 放最右但 DOM 也在最右（44 §18.1 實測 `新增商品`(pri) 在左、`新增自訂品項`(sec) 在右時，DOM 就照這個序）。
- `Enter`／`Space` 觸發；`Space` 要 `preventDefault()`。
- `aria-disabled` 型的 disabled **留在 Tab 序**，聚焦時用 `aria-describedby` 指向原因說明（例：「未變更，無法儲存」）。
- loading 時 `aria-busy="true"`；完成時用 `role="status"` 區塊播報結果，**不要靠按鈕本身播報**。
- icon-only 必須 `aria-label`；若有 tooltip，tooltip 文字與 aria-label **必須一致**。

### 1.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 基準 |
| 1024–1279 | 不變 |
| 768–1023 | 頁首動作組超過 3 顆時，第 3 顆起收進 `⋯` 溢出選單（保留 primary 與最常用的 secondary） |
| ≤767 | 高度 `--ctl-44`；並排按鈕改 `flex-direction:column`＋`width:100%`；modal footer 內按鈕全寬；`--icon` 變體命中區補到 `--hit-min` |
| ≤429 | 同上；`cl-btn__count` 隱藏，數量併進 label |

### 1.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標籤**（「批次處理近期訂單並重新計算稅額」） | 桌機 `white-space:nowrap`＋`max-width: 22ch`＋`ellipsis`＋`title`；≤767 允許兩行（`white-space:normal; line-height:` 仍為 20，高度改 `min-height`） |
| **金額在按鈕內**（「退款 NT$1,480」） | label 拆兩個 span，金額 span 掛 `.cl-money` |
| **零筆資料** | 動作鈕 **disabled 不隱藏**（44 行動項 13），`title` 說明「沒有可匯出的資料」 |
| **極大數量徽章** | `cl-btn__count` 超過 99 顯示 `99+`；超過 9999 顯示 `9k+` |
| **慢網路** | 點擊後 100ms 內進 loading；>8s 未回應→ 保持 loading 但出 inline banner「處理時間較長，請勿重複送出」；**永遠不要自動取消** |
| **重複點擊** | 進入 loading 即 `pointer-events:none`；同時在 JS 層做 idempotency key（金流／庫存／訂單必要，CLAUDE.md 鐵律 5） |

### 1.7 實作備註

```html
<button type="button" class="cl-btn cl-btn--primary" data-cl-action="order.create">
  <svg class="cl-btn__icon-start" aria-hidden="true" focusable="false">…</svg>
  <span class="cl-btn__label">建立訂單</span>
</button>

<!-- loading -->
<button type="button" class="cl-btn cl-btn--primary is-loading" aria-busy="true" aria-disabled="true">
  <span class="cl-btn__label">儲存</span>
  <span class="cl-btn__spinner" aria-hidden="true"></span>
</button>

<!-- icon-only -->
<button type="button" class="cl-btn cl-btn--icon" aria-label="欄位設定">
  <svg aria-hidden="true" focusable="false">…</svg>
</button>

<!-- 卡片 footer bar 的破壞性入口（44 §19.3） -->
<div class="cl-card__footerbar">
  <p class="cl-card__footerbar-text">檢視服務條款與隱私權政策</p>
  <button type="button" class="cl-btn cl-btn--destructive-secondary">刪除商店</button>
</div>
```

**常見錯誤做法**：
- ❌ 用 `<div>` 或 `<a href="#">` 當按鈕 → 鍵盤與螢幕閱讀器全失效。
- ❌ 忘記 `type="button"` → 在 `<form>` 內變成 submit，誤送表單。
- ❌ loading 時把文字換成「儲存中…」→ 寬度跳動，版面抖。
- ❌ 用 `opacity` 之外的方式做 disabled（如換成灰色底）→ primary 與 secondary 的 disabled 態變得一模一樣。
- ❌ 一個視圖放兩顆 primary → 使用者不知道主動作是哪個。
- ❌ 破壞性動作用紅底實心放在頁面上 → 只有**確認 modal 的主鈕**才准用實心紅；頁面上一律 `--destructive-secondary`。

### 1.8 split button `cl-split`（44 §2.2）

```
cl-split (inline-flex)
├─ cl-btn（主動作）           border-radius: var(--r-200) 0 0 var(--r-200)
└─ cl-split__toggle           border-radius: 0 var(--r-200) var(--r-200) 0
                              width: var(--ctl-32)（正方）；左側 1px 分隔線
```

| 層 | 值 |
|---|---|
| 分隔線 | primary 變體：`rgba(255,255,255,.25)`；secondary 變體：`var(--border-strong)` |
| toggle 內距 | `0 var(--sp-200)` |
| 選單 | 展開時對齊 split 右緣，`min-width` 不小於 split 全寬 |

**態表差異**（其餘同 §1.2）：
| 態 | 行為 |
|---|---|
| hover | **兩段獨立 hover**（游標在哪段就哪段變底），不整顆一起變 |
| focus-visible | 兩段各自可聚焦，各自出環 |
| selected | toggle 展開時 `aria-expanded="true"`，toggle 段套 `--surface-active` |
| disabled | **兩段一起 disabled**，不准只 disable 一段 |

**鍵盤**：Tab 依序抵達主段→toggle 段；在主段按 `↓` 或 `Alt+↓` 也要能開選單（常見期待）；選單開啟後 `↑↓` 移動、`Enter` 選取、`Esc` 關並把焦點還給 toggle 段。
**a11y**：toggle 段 `aria-haspopup="menu" aria-expanded aria-label="更多出貨動作"`；選單 `role="menu"`，項目 `role="menuitem"`。

---

## §2 輸入框 `cl-input`

**來源**：47 §4（搜尋欄 28 高／上下內距 4px；控件圓角 8px）、47 §3（`--t-sm` 為輸入框字級）、47 §5 M3（focus 三屬性同時）、44 §19.6（密碼欄＋字元計數器）、44 §22.2（標題欄右內側 `✨` AI 產生圖標）、44 §18.1（search-or-create 合一欄）、44 §22.5（helper 文字在欄位下方）。

### 2.1 解剖

```
cl-field                       （欄位容器，flex column, gap: var(--sp-150)）
├─ cl-field__label             --t-xs, color: --text-2, weight 500
│   └─ cl-field__optional      「選填」灰字，--t-2xs
├─ cl-input-wrap               position:relative, 內含前後綴
│   ├─ cl-input__prefix        左內嵌（幣別符號、🔍），16×16，left: var(--sp-300)
│   ├─ input.cl-input
│   └─ cl-input__suffix        右內嵌（單位、清除鈕、✨AI），right: var(--sp-200)
├─ cl-field__hint              --t-xs, color: --text-3（helper，永遠顯示）
├─ cl-field__error             --t-xs, color: --critical（error 時才顯示，取代 hint 位置）
└─ cl-field__counter           --t-xs, color: --text-3, 右對齊（見 §31）
```

| 屬性 | 值 |
|---|---|
| 高 | `--ctl-32`（≤767 → `--ctl-40`） |
| 內距 | `0 var(--sp-300)`；有 prefix 時左內距 `calc(var(--sp-300) * 2 + var(--sp-400))`；有 suffix 時右內距同理 |
| 圓角 | `--r-200` |
| 框 | `--bw-100 solid var(--border-strong)` |
| 字級 | `--t-sm`（≤767 → **16px**，防 iOS 聚焦放大） |
| 底 | `--surface` |
| placeholder | `--text-3` |

### 2.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | `border-color: --border-strong`；`background: --surface`；`box-shadow: none` |
| **hover** | `border-color:` 較 default 深一階（`color-mix(in srgb, var(--border-strong) 78%, var(--text))`）。**底色不變** |
| **active** | N/A（輸入框沒有按下態；點擊即進入 focus） |
| **focus-visible** | `border-color: --focus`；`box-shadow: var(--focus-glow)`；**外加** `outline: 2px --focus` offset 1px。三者同時（M3）。`.cl-field` 的 label 同步 `color: --text` |
| **disabled** | `background: --surface-sunken`；`color: --text-3`；`border-color: --border`；`cursor:not-allowed`；`opacity` **不動**（改底色而非降透明，因為輸入框內容仍需可讀） |
| **loading** | 右內嵌 16×16 spinner（`cl-input__suffix` 位置）；`readonly`（**不是 disabled**，保留可選取複製）；`aria-busy="true"` |
| **error** | `border-color: --critical`；`box-shadow: var(--focus-glow-critical)`；`aria-invalid="true"`；`cl-field__error` 顯示並取代 hint；error 訊息 `id` 掛進 `aria-describedby` |
| **selected** | N/A（文字選取由瀏覽器處理） |
| **read-only** | `background: --surface-sunken`；`border-color: transparent`；`color: --text`（**全黑不灰**，這是可信資料）；游標維持 text；**仍可聚焦、可複製**。用於 44 §18.5 的「顧客帳號網址」那種唯讀值 |

**disabled 與 read-only 的判準**：值**當前不適用**→disabled（例：未勾「追蹤庫存」時的庫存數量欄）；值**有效但此處不可改**→read-only（例：系統產生的 ID、繼承自上層市場的設定值）。

### 2.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| `border-color` + `box-shadow` | **M3** | 47 實測 focus/邊框態就是這三屬性同時、100ms、decelerate。**不准只轉 border-color** |
| hover 的 `border-color` | **M3**（同一條，非 M1） | 輸入框的 hover 變的是框不是底，所以走邊框規則 |
| error 的紅框出現 | **M3** | 與 focus 同一組轉場，避免兩套時序打架 |
| 字元計數器變色 | **M2** | 見 §31 |

### 2.4 鍵盤與焦點

- `Tab` 進入即全選？**否**——游標置於文字尾端（`selectionStart = value.length`）。只有「一次性覆寫」語意的欄位（搜尋、數量 stepper）才 `select()`。
- `Enter`：單欄表單＝送出；多欄表單＝**不送出**（避免誤觸），改為移到下一欄。**這條要全站一致。**
- `Esc`：若欄位有清除鈕→清空並保持焦點；若在 popover 內→交給 popover 處理（不吞掉事件）。
- `aria-describedby` 同時串 hint 與 error（error 存在時**只串 error**，否則螢幕閱讀器會念兩段互相矛盾的話）。
- `aria-required="true"` 而非只靠 label 上的 `*`。
- 前綴／後綴的 icon `aria-hidden`；後綴若是**可點的**（清除、AI 產生、顯示密碼）必須是真 `<button>` 且獨立於輸入框可聚焦。

### 2.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 基準 |
| ≤1279 | 兩欄表單 `grid-template-columns: 1fr 1fr` 維持 |
| ≤1023 | 兩欄表單 → 單欄 |
| ≤767 | `height: var(--ctl-40)`；`font-size: 16px`（**硬性，不用 token，這是 iOS 行為約束**）；label 與 input 間距升到 `--sp-200` |
| ≤429 | 同上；`cl-field__hint` 允許三行 |

### 2.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 值** | 單行輸入自然橫捲，**不換行**；失焦後游標回到起點（`scrollLeft = 0`）讓使用者看得到開頭 |
| **金額輸入** | `inputmode="decimal"`；`.cl-money`；**輸入時不格式化**（打字中插逗號會讓游標跳），**失焦才格式化**；儲存值一律 integer cents（CLAUDE.md 鐵律 3） |
| **零筆／空值** | placeholder 描述**格式或範例**（「例如：關於最新商品的網誌」），不要寫「請輸入…」 |
| **極大數字** | `type="text" inputmode="numeric"` ＋ 自訂驗證，**不要用 `type="number"`**（滾輪誤改值、Safari 允許 `e`、無法控制千分位） |
| **慢網路（search-or-create）** | 44 §18.1 的合一欄：輸入 250ms debounce → 顯示 inline spinner → 結果清單；**無結果時最後一列固定是「建立「{輸入值}」」**，不是空態 |
| **貼上帶格式的文字** | `paste` 事件取 `text/plain`，剝除換行與零寬字元 |
| **自動填入** | `autocomplete` 一律明寫（`email`／`tel`／`street-address`／`off`）；`:-webkit-autofill` 的黃底要覆寫成 `--surface` |

### 2.7 實作備註

```html
<div class="cl-field">
  <label class="cl-field__label" for="f-title">
    首頁標題 <span class="cl-field__optional">選填</span>
  </label>
  <div class="cl-input-wrap">
    <input id="f-title" class="cl-input" type="text" maxlength="70"
           aria-describedby="f-title-hint f-title-count"
           autocomplete="off" data-cl-counter="70">
    <button type="button" class="cl-btn cl-btn--icon cl-input__suffix" aria-label="以 AI 產生標題">
      <svg aria-hidden="true">…</svg>
    </button>
  </div>
  <p class="cl-field__hint" id="f-title-hint">顯示在搜尋引擎結果的標題。</p>
  <p class="cl-field__counter" id="f-title-count" aria-live="polite">已使用 0/70 個字元</p>
</div>
```

**常見錯誤做法**：
- ❌ 用 `placeholder` 取代 `label` → 聚焦後標籤消失，且輔具讀不到。
- ❌ error 訊息只變紅框不給文字 → 色盲使用者不知道錯在哪。
- ❌ `type="number"` 做金額。
- ❌ focus 只轉 `border-color`，忘了 `box-shadow` → 47 M3 明確要求三屬性同時。
- ❌ 把 read-only 做成 disabled → 使用者無法複製系統產生的 URL／ID。
- ❌ ≤767 用 `--t-sm`（13px） → iOS Safari 聚焦自動放大，整頁版面錯位。

---

## §3 Select `cl-select`

**來源**：44 §18.2（顧客資訊四列，每列右側 select，三態 `不顯示/選填/必填`）、44 §22.2（作者／網誌／範本 select）、44 §22.5（付款條件 select 預設「沒有付款條件」）、44 §18.2（接受行銷資訊 select ＋ 唯讀預覽列）、47 §3（`--t-sm`）、47 §2（`--r-200`）。

### 3.1 解剖

```
cl-select-wrap  (position:relative)
├─ select.cl-select     appearance:none
└─ cl-select__caret     絕對定位 right: var(--sp-300)，10×10，aria-hidden，pointer-events:none
```

| 屬性 | 值 |
|---|---|
| 高／圓角／框／字級 | 同 `cl-input`（`--ctl-32`／`--r-200`／`--border-strong`／`--t-sm`） |
| 右內距 | `calc(var(--sp-300) * 2 + var(--sp-150))` ＝ 留給 caret |
| caret | `--text-3`，`stroke-width: 2.6` |
| 行內變體 `--inline` | 用於設定列右側：`border-color: transparent`；`background: transparent`；hover 才出框。寬度 `fit-content`，`max-width: 40%` |

### 3.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 同 `cl-input` default |
| **hover** | `border-color` 深一階；`--inline` 變體額外 `background: --surface-hover`（M1） |
| **active**（原生下拉展開中） | `border-color: --focus`；caret **旋轉 180°**（`--dur-fast`）；原生選單由 OS 繪製，我們不接管 |
| **focus-visible** | 同 `cl-input`（M3 三屬性＋outline） |
| **disabled** | `background: --surface-sunken`；`color: --text-3`；caret `--text-3` 且 `opacity: var(--disabled-opacity)` |
| **loading**（選項非同步載入） | `disabled` ＋ caret 換成 spinner；第一個 option 文字＝「載入中…」 |
| **error** | 同 `cl-input` error |
| **selected** | 原生行為。**若當前值＝預設/空值**（如「沒有付款條件」），文字色用 `--text-2` 而非 `--text`，讓「未設定」在視覺上可辨識 |
| **read-only** | 原生 select **沒有 readonly**。做法：改渲染成 `cl-input[readonly]` 顯示當前值文字，`select` 不出現。**不要用 disabled 冒充 read-only**（值會不隨表單送出） |

### 3.3 動效

| 屬性 | 規則 |
|---|---|
| 框與焦點 | **M3** |
| `--inline` 的 hover 底 | **M1** |
| caret 旋轉 | `rotate var(--dur-fast) var(--ease-decelerate)`（借 M3 的曲線，因為它是「狀態切換」不是「進場」） |

**不要**為原生 select 的下拉面板做進場動效——那是 OS 繪製的，做不到也不該做。需要動效的多選／可搜尋清單請改用 §17 popover。

### 3.4 鍵盤與焦點

- 原生 select 全部行為交給瀏覽器：`↑↓` 換值、`Home/End`、首字母跳轉、`Alt+↓` 展開、`Esc` 取消。**不要用 JS 攔截**。
- `<label for>` 必填。行內 select（設定列右側）若視覺上沒有 label，用 `aria-label` 描述該列的設定名（例：`aria-label="公司名稱的顯示方式"`）。
- 選項分組用 `<optgroup label>`。
- **值改變即生效**的設定列（44 §18.2 的四列）→ change 後直接進 dirty 狀態並喚出 save bar，**不要**再加一顆「套用」。

### 3.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | 基準；`--inline` 變體與列標題同一行，右對齊 |
| 768–1023 | `--inline` 仍同行，但 `max-width: 50%` |
| ≤767 | `--inline` **換行到列標題下方，寬度 100%**（右對齊的窄 select 在手機上點不到）；高度 `--ctl-40`；字級 16px |
| ≤429 | 同上 |

### 3.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 選項** | `--inline` 變體 `text-overflow: ellipsis`；完整值靠原生下拉展開時顯示（原生面板不受我們的寬度限制） |
| **選項極多**（>20，如 13356 個商品子類、13 個報告類別） | **不用 select**，改 §17 的可搜尋 popover 多選。原生 select 超過約 20 項就無法瀏覽 |
| **零筆選項** | 顯示 disabled select，唯一 option＝「尚無可選項目」，並在 hint 給建立入口連結 |
| **值被上層繼承**（44 §22.6 市場繼承） | 顯示繼承的**生效值**＋右側「繼承自 商店預設」灰字 chip；使用者一改就變成「自訂項目」並出現「還原為繼承」的 plain 按鈕 |
| **慢網路** | 選項未載入完成前 disabled，**不要**先渲染空 select 再塞值（會出現一瞬間的空白選中態） |

### 3.7 實作備註

```html
<div class="cl-select-wrap">
  <select id="f-company-name" class="cl-select cl-select--inline"
          aria-label="公司名稱的顯示方式" data-cl-dirty>
    <option value="hidden">不顯示</option>
    <option value="optional" selected>選填</option>
    <option value="required">必填</option>
  </select>
  <svg class="cl-select__caret" aria-hidden="true" focusable="false">…</svg>
</div>
```

**常見錯誤做法**：
- ❌ 自造 div-based select → 幾乎不可能把原生的鍵盤／IME／行動裝置 picker 行為做對。**只有需要多選、搜尋、圖示、分組圖示時才自造**（改用 popover）。
- ❌ 用 `disabled` 當 read-only → 表單送出時值會消失。
- ❌ caret 忘了 `pointer-events:none` → 點到箭頭反而不會展開。
- ❌ 用 `background-image` 畫 caret 卻沒留右內距 → 長選項文字壓在箭頭上。

---

## §4 Checkbox `cl-check`

**來源**：47 §4（**16×16 原生 input**）、47 #86（**列級 32px 命中區補償，不放大 checkbox 本身**）、47 §5 關鍵幀（勾選路徑動畫）、44 §3.1（表頭全選）、44 §19.8（類別 popover 多選清單＋底部「清除」）、44 §18.2（結帳頁面多個獨立 checkbox＋副標）、44 §22.5（「帳單地址與運送地址相同」）。

### 4.1 解剖

```
cl-check                (label, display:flex, align-items:flex-start, gap: var(--sp-200))
├─ input[type=checkbox].cl-check__box     16×16 (= --sp-400)，position:relative
│   └─ ::before                            透明命中區，inset:-8px → 32×32
├─ cl-check__text
│   ├─ cl-check__label      --t-sm, color: --text
│   └─ cl-check__desc       --t-xs, color: --text-2, margin-top: var(--sp-050)（可選副標）
```

| 屬性 | 值 |
|---|---|
| 視覺盒 | `16×16`（`--sp-400`）——**任何斷點、任何情境都不改** |
| 命中區 | 桌機 `--hit-row`(32)；≤767 `--hit-min`(44) |
| 圓角 | `--r-100` |
| 框（未勾） | `--bw-100 solid var(--border-strong)` |
| 勾選底 | `--brand`；勾號 `--text-inverse`，`stroke-width: 2.5` |
| 對齊 | 與第一行文字**基線對齊**：`margin-top: calc((20px - 16px) / 2)` ＝ `var(--sp-050)`（`--t-sm` 行高 20） |

### 4.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（未勾）** | 白底＋`--border-strong` 框 |
| **hover** | `border-color:` 深一階；**同時整個 `cl-check` 的命中區內 hover**（不只 16px 方塊）。在表格列中，hover checkbox 也要讓整列進 hover 態 |
| **active** | `background: --surface-active`（未勾時）／`--brand-hover`（已勾時） |
| **focus-visible** | `outline: 2px --focus` offset 1px，**環繞 16px 方塊**（不是命中區） |
| **disabled** | `opacity: var(--disabled-opacity)`；label 與 desc 一起降透明；`cursor:not-allowed`。**若整卡 disabled**（44 §18.6 規則關閉時「最終銷售品項」整卡灰化）→ 用容器 `.is-disabled` 一次處理，不要逐個 checkbox 加屬性 |
| **loading** | 方塊換 12×12 spinner，維持 16×16 佔位；`aria-busy="true"`；樂觀更新只准用在**輕量玩具級**操作（23 §4.5），金流/庫存一律等回應 |
| **error** | `border-color: --critical`；錯誤文字放在**群組層級**（`fieldset` 之下），不是逐項 |
| **selected（已勾）** | `background: --brand`；`border-color: --brand`；勾號路徑 `stroke-dashoffset` 由 100%→0 |
| **indeterminate（第三態）** | `background: --brand`；圖形換成 2px 橫線；`el.indeterminate = true`（**只能用 JS 設，沒有 HTML 屬性**）；`aria-checked="mixed"` |
| **read-only** | 原生無此態。做法：`disabled` ＋ 在群組旁標「唯讀」chip；若需送出值，另加 `<input type="hidden">` |

### 4.3 動效

| 屬性 | 規則 |
|---|---|
| `background-color`（勾選） | **M1** |
| `border-color` | **M3** |
| 勾號路徑 | `stroke-dashoffset var(--dur-fast) var(--ease-decelerate)`（47 §5 實測有「checkbox 勾選路徑動畫」keyframes；我們用 dashoffset 自實作） |
| 焦點環 | **M3** |

### 4.4 鍵盤與焦點

- `Space` 切換；`Tab` 進出。**不要**攔 `Enter`（在表單內 Enter 應該送出，不是勾選）。
- 群組用 `<fieldset>` ＋ `<legend>`；`legend` 視覺上可以是卡片標題。
- 全選 checkbox：`aria-controls` 指向所有列 id（或用 `aria-label="選取全部 N 筆"`）；三態切換規則：全未選→全選；部分選→全選；全選→全不選。
- 表格列的 checkbox：`aria-label` 描述**該列的識別**（例：`aria-label="選取訂單 #1042"`）。**不要**把內部 ID 暴露在 label 裡。
- `Shift+Click` 範圍選取（表格必備）；`⌘/Ctrl+A` 在表格聚焦時＝全選當前頁。

### 4.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 命中區 32×32 |
| ≤767 | 命中區 44×44（改 `::before{inset:-14px}`）；**視覺盒仍 16×16**；表格卡片化時 checkbox 絕對定位到卡片右上角，命中區同樣靠 `::before` |
| ≤429 | 同上 |

### 4.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK label** | `cl-check__text` `flex:1; min-width:0`；文字自然換行，方塊維持頂端對齊（**不要垂直置中**，多行時會飄到中間） |
| **零筆可選項** | 整個群組換成卡內空態（§24.2） |
| **極大數量**（跨頁全選） | 勾表頭後出現「已選取本頁 50 筆，**選取全部 1,284 筆**」的 plain 連結；跨頁選取後任何操作都要二次確認 |
| **慢網路** | 樂觀更新後失敗 → **視覺回滾** ＋ critical toast ＋ 該列標紅 2s |
| **命中區重疊** | 表格首欄 checkbox 的 32×32 命中區會蓋到相鄰儲存格 → 首欄 `min-width: var(--hit-row)` 且 `position:relative`，命中區不得溢出到第二欄 |

### 4.7 實作備註

```html
<label class="cl-check">
  <input type="checkbox" class="cl-check__box" data-cl-row="order-1042">
  <span class="cl-check__text">
    <span class="cl-check__label">要求顧客登入才能結帳</span>
    <span class="cl-check__desc">要求登入時，顧客只能使用電子郵件。</span>
  </span>
</label>
```
```css
.cl-check__box{ inline-size: var(--sp-400); block-size: var(--sp-400); position: relative; }
.cl-check__box::before{               /* 命中區，不改視覺尺寸（47 #86） */
  content:""; position:absolute;
  inset: calc((var(--hit-row) - var(--sp-400)) / -2);
}
@media (max-width: 767px){
  .cl-check__box::before{ inset: calc((var(--hit-min) - var(--sp-400)) / -2); }
}
```

**常見錯誤做法**：
- ❌ **把 checkbox 本身放大到 20/24px 來滿足觸控** → 這正是 47 #86 禁止的做法（原型 ≤429 的 `.cb{width:20px}` 要刪）。
- ❌ 自造 `div` checkbox → 失去 indeterminate、失去表單語意、失去 IME 與輔具支援。
- ❌ 用 `label` 包住但沒設 `for`／沒巢狀 input → 點文字不會勾。
- ❌ 副標文字放進 `<label>` 內卻沒有分開的 span → 螢幕閱讀器會把整段當成控件名念完。
- ❌ 忘記 `aria-checked="mixed"` 配 indeterminate → 輔具只會說「未勾選」。

---

## §5 Radio `cl-radio`

**來源**：44 §18.2（顧客聯絡方式：`電話號碼或電子郵件`／`電子郵件`；未完成結帳的傳送對象與傳送時間 4 檔）、44 §22.2（公開狀態 `公開`／`隱藏`）、44 §22.5（訂單提交：`自動提交訂單`／`全部轉草稿待審核`，含副標）、44 §18.6（最終銷售品項 `商品系列`／`商品`）、44 §22.4（探索方式＝**卡片型 radio**，插圖＋標題＋說明，選中＝藍框藍底）。

### 5.1 解剖

**兩種形態**，用途不同：

**(a) 標準 radio `cl-radio`** — 幾何與 `cl-check` 完全相同，差別只有 `border-radius: var(--r-pill)`、選中時中心 6px 實心圓點（`--sp-150`）而非勾號。

**(b) 卡片型 radio `cl-radio-card`**（44 §22.4）
```
cl-radio-card   (label, --r-300, --bw-100 --border, padding: var(--sp-400))
├─ input[type=radio]  視覺隱藏（sr-only），保留可聚焦
├─ cl-radio-card__art     插圖，aspect-ratio 固定
├─ cl-radio-card__title   --t-md
└─ cl-radio-card__desc    --t-xs, --text-2
```

### 5.2 完整態表

| 態 | 標準 radio | 卡片型 radio |
|---|---|---|
| **default** | 白底＋`--border-strong` 框 | `--surface` 底＋`--border` 框 |
| **hover** | `border-color` 深一階 | `background: --surface-hover`；`border-color: --border-strong` |
| **active** | `background: --surface-active` | `background: --surface-active` |
| **focus-visible** | outline 環繞 16px 圓 | outline 環繞**整張卡**（因為 input 是 sr-only，環要用 `:has(:focus-visible)` 掛在卡上） |
| **disabled** | `opacity: var(--disabled-opacity)` | 整卡 `opacity: var(--disabled-opacity)`；`pointer-events:none` |
| **loading** | N/A | N/A |
| **error** | 群組層級紅字＋`fieldset` 加 `--critical` 左框 | 同 |
| **selected** | 中心 `--sp-150` 實心圓，色 `--brand`；框 `--brand` | `border: var(--bw-200) solid var(--focus)`；`background: color-mix(in srgb, var(--focus) 6%, var(--surface))`；**內距要減 1px 補償框變厚**，否則卡片會抖 |
| **read-only** | disabled ＋「唯讀」chip | 同 |

**單選群組的鐵律**：**radio 不可取消選取**。若「都不選」是合法狀態，必須顯式提供一個「不設定／不顯示」選項（44 §18.2 的 select 三態就是這個道理）。

### 5.3 動效

| 屬性 | 規則 |
|---|---|
| 圓點出現 | `scale var(--dur-fast) var(--ease-decelerate)`（由 0→1，借 M5 曲線） |
| `border-color` | **M3** |
| 卡片型的底色 | **M1** |
| 卡片型的框變厚 | **M3**（`border-width` 也在 M3 的三屬性內，47 明確列了 `border-width`） |

### 5.4 鍵盤與焦點

- **整個 radio group 只佔一個 Tab 停留點**（roving tabindex：選中項 `tabindex="0"`，其餘 `-1`）。這是原生行為，用 `name` 相同的原生 radio 就自動成立。
- `↑←` 上一項、`↓→` 下一項，**且立即選取**（原生行為，不要改成「移動但不選」）。
- `Home/End` 首末項。
- `<fieldset>` ＋ `<legend>`，`legend` 就是題目（例：「顧客在結帳時輸入的聯絡方式」）。
- 每個選項有副標時：副標的 id 掛進該 radio 的 `aria-describedby`。

### 5.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | 卡片型 radio 橫排（`grid-template-columns: repeat(2, 1fr)` 或 3） |
| 768–1023 | 卡片型 2 欄 |
| ≤767 | 卡片型 **1 欄堆疊**；標準 radio 命中區 44；選項間距升到 `--sp-300` |
| ≤429 | 卡片型插圖縮小或隱藏（`cl-radio-card__art{display:none}`），只留標題＋說明 |

### 5.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 副標**（44 §22.5「沒有運送地址的訂單將作為訂單草稿提交」） | 副標可換行，radio 圓維持頂端對齊 |
| **選項含硬數字**（44 §18.2 傳送時間 1/6/10/24 小時，預設 10 標「建議」） | 「建議」用 `--attention` badge 接在 label 後，**不要**寫進 label 文字（輔具會念成「10 小時建議」變成一個怪名字） |
| **零筆選項** | 群組不渲染，改顯示卡內空態 |
| **選項極多**（>7） | 改用 select 或可搜尋 popover |
| **慢網路** | 切換即送出的 radio 群組：切換後群組 `aria-busy`，失敗回滾到原選項並出 critical toast |

### 5.7 實作備註

```html
<fieldset class="cl-fieldset">
  <legend class="cl-fieldset__legend">訂單提交</legend>
  <label class="cl-radio">
    <input type="radio" name="order-submit" value="auto" class="cl-radio__box"
           aria-describedby="os-auto-d" checked>
    <span class="cl-check__text">
      <span class="cl-check__label">自動提交訂單</span>
      <span class="cl-check__desc" id="os-auto-d">沒有運送地址的訂單將作為訂單草稿提交</span>
    </span>
  </label>
  <label class="cl-radio">…</label>
</fieldset>
```

**常見錯誤做法**：
- ❌ 用 checkbox 做互斥選項 → 使用者會以為可以複選。
- ❌ radio group 每一項都給 `tabindex="0"` → Tab 要按 N 次才離開群組。
- ❌ `name` 沒設或不一致 → 變成 N 個獨立的單選，全部都能選中。
- ❌ 卡片型 radio 用 `div` + click → 失去 roving tabindex 與 `↑↓` 行為。
- ❌ 選中時只加框不加底 → 在密集卡片群中很難一眼看出選了哪個。

---

## §6 Toggle `cl-toggle`

**來源**：44 §18.5（顧客帳號五列全部是 toggle：自助退貨、商店抵用金…）、44 §19.6（密碼保護、B2B 存取、hreflang、自動重新導向 ×2、hCaptcha ×2）、44 §18.7（**只有部分通知範本可 toggle**，交易性範本強制寄）、44 §18.2（加購上限 modal 右上 toggle）、44 §18.6（退貨規則／取消規則 toggle，關閉時下方整卡灰化）。

### 6.1 解剖

```
cl-swrow                 （設定列容器，flex, align-items:flex-start, gap: var(--sp-300)）
├─ cl-swrow__icon        可選 20×20
├─ cl-swrow__text        flex:1, min-width:0
│   ├─ cl-swrow__title   --t-sm
│   └─ cl-swrow__desc    --t-xs, --text-2
└─ input[type=checkbox][role=switch].cl-toggle    margin-left:auto
```

| 屬性 | 值 |
|---|---|
| 軌道 | `36 × 20`（`--tgl-w` / `--tgl-h`，見下）；圓角 `--r-pill` |
| 把手 | `16×16`（`--sp-400`），白色，`--r-pill`，`inset-block-start: var(--sp-050)`，起始 `inset-inline-start: var(--sp-050)` |
| 位移 | `translateX(16px)` ＝ `var(--sp-400)`（**用 transform，不用 left**） |
| 關閉底 | `--border-strong` |
| 開啟底 | `--success` |
| 命中區 | `::before{inset: calc((var(--hit-row) - 20px) / -2) 0}` → 高度補到 32；≤767 補到 44 |

**新增 token**（47/23 都沒有）：`--tgl-w: 36px; --tgl-h: 20px;`〔推導〕沿用原型既有值，且 20 = `--sp-400`(16) + `--sp-050`(2) × 2，與七階自洽。

### 6.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（關）** | 軌道 `--border-strong`；把手靠左 |
| **hover** | 軌道 `color-mix(…深一階)`；**整列 `cl-swrow` 不變底**（設定列 hover 不該整列反白，會誤導成可點整列） |
| **active** | 把手 `scale: 1.06`（按壓感）；軌道不變 |
| **focus-visible** | `outline: 2px --focus` offset 1px 環繞軌道 |
| **disabled** | `opacity: var(--disabled-opacity)`；title 與 desc 同步降透明；**必須說明原因**——44 §18.7 的交易性通知範本不可關閉，要在 desc 尾端加「（此通知為交易必要，無法關閉）」而不是只給一個灰掉的開關 |
| **loading** | 軌道保持當前色但降 60% 不透明；把手換成 12px spinner；`aria-busy="true"`；**位置不動**（成功才移動） |
| **error** | 切換失敗 → 把手**動畫回彈到原位**（`translateX` 逆向，`--dur-base`）＋ critical toast。軌道不留紅色 |
| **selected（開）** | 軌道 `--success`；把手 `translateX(var(--sp-400))`；`aria-checked="true"` |
| **read-only** | `disabled` ＋ 右側加「唯讀」`--t-2xs` 灰字 |

**開關的語意鐵律**：toggle **即時生效、不需要儲存按鈕**。若這個開關必須配合「儲存」才生效 → **它不該是 toggle，應該是 checkbox**。（44 實測：設定頁的 toggle 全部即時生效，而結帳設定的 checkbox 才配 save bar。）

### 6.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 軌道 `background-color` | **M1** | 標準底色回饋 |
| 把手 `transform` | `transform var(--dur-fast) var(--ease-decelerate)` | 比底色快，讓把手「先到位」；用 decelerate 收得住 |
| 焦點環 | **M3** | |

**不要**用 `left`／`margin-left` 做位移（逐幀觸發 layout）。原型 `.tgl::after{transition:left}` 要改。

### 6.4 鍵盤與焦點

- `role="switch"` ＋ `aria-checked`。用原生 `<input type="checkbox" role="switch">`（保留 Space 切換與表單語意）。
- `Space` 切換；`Enter` **不切換**（switch 不是 button）。
- 名稱來源：`aria-labelledby` 指向 `cl-swrow__title`；說明 `aria-describedby` 指向 `cl-swrow__desc`。
- 即時生效的切換要有結果回饋：成功 → `role="status"` 的輕量 toast 或列尾「已儲存」淡出字；失敗 → critical toast ＋ 回彈。

### 6.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | title/desc 左、toggle 右，同一行 |
| ≤767 | 版型不變（toggle 仍在右），但命中區補到 44；`cl-swrow` 上下內距升到 `--sp-300` |
| ≤429 | 若 title 超過兩行，toggle 換行到 desc 下方靠右 |

### 6.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK title** | `cl-swrow__text{flex:1; min-width:0}`；toggle `flex:none`。**toggle 永遠不被擠壓** |
| **連鎖約束**（44 §18.2「要求登入 ⇒ 強制 email」） | 開 A 導致 B 被鎖：B 立刻 disabled ＋ desc 追加原因；**同一幀完成**，不要等伺服器回應才鎖 |
| **關閉導致下游整區失效**（44 §18.6） | 下游卡片整體 `.is-disabled`（`opacity` ＋ `pointer-events:none` ＋ `inert`），**不要逐個控件 disable**（會漏） |
| **零筆／不適用** | toggle 仍顯示但 disabled，desc 說明前置條件（「需先建立至少一個運送區域」） |
| **慢網路** | 樂觀切換 → 失敗回彈。**金流／庫存相關的 toggle 不准樂觀更新**（23 §4.5、CLAUDE.md 鐵律 5），改為 loading 態等回應 |
| **快速連點** | 進 loading 即鎖；佇列只保留最後一次意圖，回應後對齊伺服器真值 |

### 6.7 實作備註

```html
<div class="cl-swrow">
  <svg class="cl-swrow__icon" aria-hidden="true">…</svg>
  <span class="cl-swrow__text">
    <span class="cl-swrow__title" id="sw-credit-t">商店抵用金</span>
    <span class="cl-swrow__desc" id="sw-credit-d">允許顧客查看和使用商店抵用金。</span>
  </span>
  <input type="checkbox" role="switch" class="cl-toggle" checked
         aria-labelledby="sw-credit-t" aria-describedby="sw-credit-d"
         data-cl-setting="store_credit.enabled">
</div>
```

**常見錯誤做法**：
- ❌ toggle ＋ 儲存按鈕並存 → 使用者不知道有沒有生效。
- ❌ 用 `aria-pressed` 而非 `role="switch" aria-checked` → 輔具念成「按鈕，已按下」。
- ❌ disabled 的 toggle 不說明原因 → 44 §18.7 的交易性通知就是這個坑。
- ❌ 把手用 `left` 過渡。
- ❌ 樂觀更新後失敗卻不回彈 → UI 與伺服器狀態永久不一致。

---

## §7 Textarea `cl-textarea`（含字元計數器）

**來源**：44 §19.6（`給訪客的訊息` textarea disabled ＋「已使用 0/5,000 個字元」；`中繼描述` textarea ＋「已使用 0/320 個字元」＋ placeholder「輸入在 Google 等搜尋引擎顯示的描述」）、44 行動項 46（計數器統一格式，四個硬值 100/5000/70/320）、47 §3（`--t-sm`）、47 §5 M3。

### 7.1 解剖

```
cl-field
├─ cl-field__label
├─ cl-input-wrap
│   └─ textarea.cl-input.cl-textarea
├─ cl-field__foot            （flex, justify-content: space-between, gap: var(--sp-200)）
│   ├─ cl-field__hint / cl-field__error     flex:1
│   └─ cl-field__counter                    flex:none, --t-xs, --text-3, tabular-nums
```

| 屬性 | 值 |
|---|---|
| 最小高 | `calc(var(--ctl-32) * 2 + var(--sp-200))`〔推導〕≈ 72px，約 3 行 |
| 內距 | `var(--sp-200) var(--sp-300)` |
| 行高 | `--t-sm` 的 20（**不要用 1.6 之類的比例**，會讓自動長高的步進不整齊） |
| `resize` | `vertical`（**禁止 `both`**，橫向拉會破版） |
| 其餘 | 同 `cl-input`（圓角／框／字級／focus） |

### 7.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 同 `cl-input` |
| **hover** | `border-color` 深一階 |
| **active** | N/A |
| **focus-visible** | 同 `cl-input`（M3 三屬性＋outline）；計數器 `color: --text-2`（從 `--text-3` 提一階，暗示「現在正在數你打的字」） |
| **disabled** | `background: --surface-sunken`；`color: --text-3`；`resize:none`；**計數器仍顯示** `已使用 0/5,000 個字元`（44 §19.6 實測：disabled 的 textarea 下方計數器照樣在） |
| **loading** | 極少用。若 AI 生成中：`readonly` ＋ 右上角 spinner ＋ 內容逐段填入（`aria-live="off"` 避免洗版） |
| **error** | `border-color: --critical` ＋ `--focus-glow-critical`；`cl-field__error` 取代 hint；**計數器同時轉紅**（若錯因是超長） |
| **selected** | N/A |
| **read-only** | `background: --surface-sunken`；`border-color: transparent`；`resize:none`；可選取複製；計數器改顯示 `{n} 個字元`（沒有上限語意） |

### 7.3 計數器規則（同時是 §31 的實作核心）

| 項 | 規則 |
|---|---|
| **格式** | `已使用 {n}/{max} 個字元`（44 §19.6 逐字）。`{max}` 千分位加逗號（`5,000`），`{n}` 不加 |
| **已知硬值** | 密碼 100／訪客訊息 5,000／首頁標題 70／中繼描述 320。**一律走 `config/limits.yml`**（CLAUDE.md 鐵律 6），不得硬編在元件 |
| **計數單位** | **CJK 一字算一字**。用 `Intl.Segmenter('zh-Hant', {granularity:'grapheme'})` 計數，**不要用 `String.length`**（emoji 與組合字會算成 2） |
| **色階** | `n ≤ 80% max` → `--text-3`；`80% < n ≤ 100%` → `--warning`；`n > max` → `--critical` ＋ 欄位進 error 態 |
| **超限行為** | **軟限制**：允許輸入超過，標紅並擋住送出。**不要用 `maxlength` 硬截斷**——貼上長文時硬截斷會無聲丟失內容。`maxlength` 只在「絕對不可超過」的技術欄位（如 handle）使用 |
| **播報** | 計數器 `aria-live="polite"`，但**只在跨越門檻時更新 live 區**（80%／100%／超限三個點），否則每打一字念一次 |

### 7.4 動效

| 屬性 | 規則 |
|---|---|
| 框與焦點 | **M3** |
| 計數器變色 | **M2** |
| 自動長高 | **不做 transition**（M0：幾何屬性不進 transition）。用 `field-sizing: content` 或 `scrollHeight` 直接設值 |

### 7.5 鍵盤與焦點

- `Tab` 進入 textarea 後，**`Tab` 會離開**（不插入 tab 字元）。若欄位需要輸入 tab（程式碼／Liquid 片段），必須提供 `Esc` 先切出「編輯模式」的逃生機制，否則鍵盤使用者會被困住。
- `Enter` 換行（**不送出表單**）；`⌘/Ctrl + Enter` ＝送出（給熟練使用者的捷徑）。
- `Esc`：若在 modal／sheet 內，**不吞掉事件**，交給浮層處理。
- `aria-describedby` 同時串 hint 與 counter；error 存在時**只串 error ＋ counter**（不串 hint）。
- 自動長高時，游標必須保持在視野內：長高後檢查 `selectionEnd` 的位置，必要時 `scrollIntoView({block:'nearest'})`。
- IME 組字中**不得**觸發任何 `aria-live` 更新（會打斷輸入法候選字的朗讀）。
- 富文字編輯器（44 §3.2／§22.2 的說明與內容欄）**不是本元件**：工具列要用 `role="toolbar"` ＋ `←→` 移動、單一 Tab 停留點；`</>` 原始碼模式切換要 `aria-pressed`。

### 7.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 基準 |
| ≤767 | `font-size: 16px`；`min-height` 升到 4 行；`resize: none`（改自動長高，手機拖把手很難用）；`cl-field__foot` 改上下堆疊（hint 在上、計數器在下靠右） |

### 7.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 無空白段落** | `overflow-wrap: anywhere` ＋ `line-break: strict`（中文不可在標點前斷行） |
| **貼上超過上限** | 全部保留 → 計數器紅 → 送出鈕 disabled ＋ 說明「超出 {n-max} 個字元」。**絕不靜默截斷** |
| **零字元** | 計數器顯示 `已使用 0/{max} 個字元`（不是隱藏） |
| **極大內容**（>50k 字） | 超過 10k 字停用即時計數（改 debounce 500ms），避免每鍵重算 grapheme 造成掉幀 |
| **IME 組字中** | `compositionstart`→暫停計數；`compositionend`→重算。**否則注音未上屏就被算進去** |
| **慢網路自動儲存** | 停止輸入 2s 後自動存草稿 → 計數器旁顯示「已儲存草稿」淡出字（`--t-2xs`），不要用 toast（太吵） |

### 7.8 實作備註

```html
<div class="cl-field">
  <label class="cl-field__label" for="f-meta">中繼描述</label>
  <div class="cl-input-wrap">
    <textarea id="f-meta" class="cl-input cl-textarea" rows="3"
              placeholder="輸入在 Google 等搜尋引擎顯示的描述"
              aria-describedby="f-meta-hint f-meta-count"
              data-cl-counter-max="320"></textarea>
  </div>
  <div class="cl-field__foot">
    <p class="cl-field__hint" id="f-meta-hint">用於搜尋結果的摘要文字。</p>
    <p class="cl-field__counter" id="f-meta-count" aria-live="polite">已使用 0/320 個字元</p>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 用 `maxlength` 硬擋 → 貼上長文時無聲丟資料。
- ❌ 用 `String.length` 計數 CJK/emoji。
- ❌ IME 組字中就計數。
- ❌ `resize: both`。
- ❌ 計數器 `aria-live` 每字播報 → 螢幕閱讀器使用者無法打字。
- ❌ disabled 時把計數器藏起來 → 與 44 §19.6 實測不符。


---

## §8 搜尋欄 `cl-search`

**來源**：47 §4（**列表內搜尋欄高 28、上下內距 4px、右內距 28px 留給清除鈕**）、44 §2.1（`🔍 搜尋和篩選` 一體欄，佔滿剩餘寬）、44 §2.1（點搜尋框即展開 **18 類**篩選分類選單）、44 §2.2（`更多動作` 內建 `🔍 搜尋操作`）、44 §8（設定 overlay 內有設定搜尋）、44 §19.8（`搜尋報告` 大輸入框）、44 §0（頂欄中央大搜尋，右側 `CTRL K` 提示）。

### 8.1 解剖

**三種尺寸**，同一套結構：

```
cl-search  (flex, align-items:center, gap: var(--sp-200), --r-200, --bw-100 --border-strong)
├─ cl-search__icon      16×16, --text-3, aria-hidden, flex:none
├─ input.cl-search__input   flex:1, min-width:0, border:0, background:none, --t-sm
├─ cl-search__clear     --ctl-24 正方 icon 按鈕；只在有值時出現；佔位寬 28px（47 §4）
└─ cl-search__kbd       --t-2xs 鍵帽（僅頂欄變體）
```

| 變體 | 高 | 用在哪 |
|---|---|---|
| `cl-search--inline` | `--ctl-28` | **列表列內**（47 §4 實測 28） |
| `cl-search`（標準） | `--ctl-32` | 卡內大搜尋（44 §19.8 報告搜尋）、popover 內搜尋 |
| `cl-search--shell` | `--ctl-36` | 頂欄全域搜尋（47 §0 頂欄高 56 的內部控件階） |

**右內距鐵律**：`padding-inline-end: 28px`（47 §4 直接量到的值）——**即使清除鈕沒出現也要保留**，否則輸入到滿版時文字會在清除鈕出現的瞬間被推擠。用 `--sp-600 + --sp-100` 組出 28。

### 8.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | `border-color: --border-strong`；icon `--text-3`；placeholder `--text-3` |
| **hover** | `border-color` 深一階（M3）。**底色不變** |
| **active** | N/A |
| **focus-visible** | `border-color: --focus` ＋ `--focus-glow` ＋ outline（M3）；icon 轉 `--text-2`（M2）；**同時展開篩選分類選單**（44 §2.1：點搜尋框即展開 18 類分類選單）——這是本元件與一般輸入框最大的差異 |
| **disabled** | `background: --surface-sunken`；icon 與 placeholder 降透明。**用在無資料的列表**（列表 0 筆時搜尋欄 disabled，不隱藏） |
| **loading** | icon 換 16px spinner（**原地替換，不加新元素**）；`aria-busy="true"`；結果區顯示 skeleton 而非清空 |
| **error** | 搜尋語法錯誤（如 ShopifyQL 風格查詢）→ `border-color: --critical` ＋ 下方 `--t-xs` 紅字說明；**不清空使用者輸入** |
| **selected** | N/A |
| **read-only** | N/A |

**有值時的額外變化**：`cl-search__clear` 由 `visibility:hidden` 轉 `visible`（**不是 `display`**，避免佈局跳動）；`--inline` 變體在有值時 `border-color: --brand`（表示「此列表已被過濾」）。

### 8.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 框與焦點 | **M3** | 同輸入框 |
| icon 顏色 | **M2** | |
| 清除鈕出現 | `opacity var(--dur-fast) var(--ease-standard)` | 借 M1 的時序但只轉 opacity；不用 M5（不是浮層） |
| 篩選分類選單展開 | **M5** | 它是 popover（§17） |
| 結果更新 | 結果區換 skeleton，**不做淡入淡出** | 每次打字都淡一次會閃 |

### 8.4 鍵盤與焦點

- `⌘/Ctrl + K` 全域跳到頂欄搜尋（23 §4.3）。`/` 在列表頁跳到列表內搜尋（不在輸入態時）。
- `Esc`：有值→清空並保持焦點；無值→關閉展開的篩選選單；再按→失焦。**三段式，一次退一層**。
- `↓`：從輸入框移到結果／分類清單第一項（焦點留在輸入框，用 `aria-activedescendant` 標高亮）。
- `Enter`：套用當前高亮項；無高亮則直接以純文字搜尋。
- ARIA：`role="combobox" aria-expanded aria-controls aria-autocomplete="list"`；結果容器 `role="listbox"`，項目 `role="option"`。
- 結果數要播報：`<span role="status" class="sr-only">找到 12 筆結果</span>`，debounce 500ms 更新。

### 8.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 頂欄搜尋 `max-width: var(--w-search-shell)` 置中；列表內搜尋 `flex:1` |
| 1024–1279 | 頂欄搜尋 `max-width: var(--w-search-shell-m)` |
| 768–1023 | 頂欄搜尋收成 icon 按鈕，點擊展開為覆蓋整條頂欄的搜尋列；`cl-search__kbd` 隱藏 |
| ≤767 | 列表內搜尋單獨佔一整行（不與檢視 tab 同行）；高 `--ctl-40`；字級 16px；篩選分類選單改**貼底 sheet**（§18） |
| ≤429 | 同上 |

### 8.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 查詢字串** | 輸入框橫捲；清除鈕永遠可見（因為右內距是保留的） |
| **`#` 前綴與大小寫**（23 §3） | 正規化：`#1042` = `1042`；全形數字轉半形；英文大小寫不敏感 |
| **零筆結果** | **不是空態元件**——保留搜尋欄與篩選 chip，表格區換成「搜尋空結果」變體：一句「找不到符合「{查詢}」的結果」＋ plain 按鈕「清除搜尋」（23 §3 硬性要求） |
| **極大結果數** | 顯示「約 12,000 筆」（近似值），不要為了精確數字掃全表；分頁走 cursor（44 行動項 43） |
| **慢網路** | 本地資料 → 即時過濾無 debounce；伺服器查詢 → **250ms debounce ＋ 請求競態取消**（`AbortController`），舊回應到達時比對 request id 丟棄 |
| **搜尋中切換檢視** | 保留查詢字串，重新套用到新檢視；URL 同步 `?q=`（可分享、可回上一頁） |

### 8.7 實作備註

```html
<div class="cl-search cl-search--inline" role="combobox" aria-expanded="false"
     aria-owns="filter-cats" aria-haspopup="listbox">
  <svg class="cl-search__icon" aria-hidden="true">…</svg>
  <input class="cl-search__input" type="search" placeholder="搜尋和篩選"
         aria-label="搜尋和篩選訂單" aria-autocomplete="list" autocomplete="off">
  <button type="button" class="cl-search__clear cl-btn cl-btn--icon" aria-label="清除搜尋" hidden>…</button>
</div>
```

**常見錯誤做法**：
- ❌ 清除鈕用 `display:none/block` 切換 → 出現時把文字往左推。
- ❌ 沒做請求競態取消 → 打字快時舊結果覆蓋新結果。
- ❌ 空結果直接顯示全頁空態插圖 → 使用者以為資料被刪光了。**空結果 ≠ 無資料**。
- ❌ `type="text"` 而非 `type="search"` → 失去行動裝置鍵盤的「搜尋」鍵。
- ❌ 搜尋狀態不進 URL → 重整就丟失、無法分享。

---

## §9 Filter chip `cl-fchip`

**來源**：44 §19.8（報告庫 filter chips `建立者 ⌄`／`類別 ⌄`；**`類別` popover ＝ 多選 checkbox 清單 ＋ 底部 `清除`，可捲動，13 個類別**）、44 §2.1（訂單篩選 18 類）、44 §2.1（標籤欄 chips 超出以 `+ 1` 收合）、44 §22.6（唯讀 chip `United States`）、47 §2（chip 圓角 `--r-200`）、47 §4（密集控件 28 高）。

### 9.1 解剖

**兩型**：

**(a) 篩選觸發 chip `cl-fchip`**（可點開 popover）
```
button.cl-fchip
├─ cl-fchip__label     --t-xs
├─ cl-fchip__value     --t-xs, weight 500；已套用時顯示值或「N 個」
└─ cl-fchip__caret     10×10
```
**(b) 已套用 chip `cl-fchip--applied`**（帶 `✕` 可移除）
```
span.cl-fchip.cl-fchip--applied
├─ cl-fchip__label
└─ button.cl-fchip__remove   --ctl-24 正方，aria-label「移除 {篩選名} 篩選」
```

| 屬性 | 值 |
|---|---|
| 高 | `--ctl-28` |
| 內距 | `0 var(--sp-200)`；有 caret 時右內距 `var(--sp-150)` |
| 圓角 | `--r-200`（**不是 pill**——47 §2 實測 chip 用 8px） |
| 框 | 未套用：`--bw-100 dashed var(--border-strong)`；已套用：`--bw-100 solid var(--brand)` |
| 字級 | `--t-xs` |
| gap | `--sp-100` |

### 9.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（未套用）** | 虛線框 `--border-strong`；`color: --text-2`；透明底 |
| **hover** | `background: --surface-hover`；`color: --text` |
| **active** | `background: --surface-active` |
| **focus-visible** | outline 2px offset 1px |
| **disabled** | `opacity: var(--disabled-opacity)`。用於「此檢視不支援此篩選」 |
| **loading**（選項非同步） | caret 換 spinner；chip 本身可點但 popover 內顯示 skeleton 三列 |
| **error** | N/A（篩選失敗走列表層 banner） |
| **selected（已套用）** | 實線框 `--brand`；`background: color-mix(in srgb, var(--brand) 6%, var(--surface))`；`color: --text`；label 後接 `：{值}` 或 `：3 個`；`aria-pressed="true"` |
| **open（popover 展開中）** | 同 selected 的框，額外 `background: --surface-active`；`aria-expanded="true"` |
| **read-only**（44 §22.6 依地址推導的市場 chip） | 無框無 caret，`background: --surface-sunken`；`cursor: default`；不可聚焦 |

### 9.3 popover 內容規格（44 §19.8 實測）

| 元素 | 規格 |
|---|---|
| 寬 | `--w-popover-min`(180) ~ `--w-popover-max`(320)；`width: max-content` 夾在兩者之間 |
| 最大高 | `min(320px, 60vh)`，超出 `overflow-y:auto`（44 實測「可捲動」） |
| 選項 >8 時 | 頂部加 `cl-search`（標準尺寸）過濾選項 |
| 選項列 | `cl-check` ＋ 列高 `--ctl-32`，列內距 `0 var(--sp-300)`，hover `--surface-hover` |
| 底部固定列 | 左 `清除`（plain 按鈕）／右 `套用`（primary sm，**未變更時 disabled**）。44 §22.4 實測「底部固定 footer：`清除` ＋ disabled `套用`」 |
| 即時 vs 套用 | 本地資料→勾選即時生效，footer 只留「清除」；伺服器查詢→需按「套用」 |

### 9.4 動效

| 屬性 | 規則 |
|---|---|
| chip 底色 | **M1** |
| chip 文字色 | **M2** |
| 框（虛線→實線） | **M3** |
| popover 進場 | **M5**（`transform-origin: top left`，對齊 chip 左下角） |
| chip 移除 | `opacity` ＋ `scale: .9`，`--dur-fast`；移除後其餘 chip **不做位移動畫**（reflow 動畫容易掉幀） |

### 9.5 鍵盤與焦點

- chip 是 `<button aria-haspopup="dialog"｜"listbox" aria-expanded aria-controls>`；已套用的 chip 用 `<span>` 包一顆獨立的移除 `<button>`（**整個 chip 不可點時不要做成 button**）。
- Tab 序：搜尋欄 → 各觸發 chip → 已套用 chip 的 `✕` → 「清除全部」。
- `Enter`／`Space`／`↓` 開 popover；`Esc` 關並還焦點給 chip。
- 已套用 chip 上按 `Delete`／`Backspace` ＝移除該篩選（額外便利）。移除後焦點移到**下一個** chip；若已是最後一個，移到搜尋欄。
- chipbar 外層 `role="group" aria-label="篩選條件"`。
- 篩選變更後用 `role="status"` 播報「已套用 2 個篩選，符合 128 筆」——**這是唯一能讓螢幕閱讀器使用者知道表格變了的方式**。
- 「清除全部」按下後焦點移回搜尋欄。

### 9.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | chips 與搜尋欄同一行，`flex-wrap: wrap`，`row-gap: var(--sp-150)` |
| 768–1023 | 同上；超過 3 個已套用 chip 時，第 4 個起收成 `+N` chip，點開顯示全部 |
| ≤767 | chips 獨佔一行**橫捲**（`scroll-snap-type: x proximity` ＋ 邊緣漸層，34 §規則 5）；popover 改**貼底 sheet**（§18） |
| ≤429 | 同上；`cl-fchip__value` 只顯示數字（`3` 而非 `3 個`） |

### 9.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 篩選值**（「未包含於其他設定檔的所有商品」） | chip 內 `max-width: 20ch` ＋ ellipsis ＋ `title`；**多值時一律顯示「N 個」**而非串接（44 §2.1 的 `+ 1` 收合就是這個模式） |
| **零個可用篩選** | 不渲染 chip 列（不是渲染空列） |
| **極多篩選類別**（18 類／13 類） | 分類選單分組＋可搜尋；**不要平鋪 18 個 chip** |
| **金額範圍篩選** | 兩個 `cl-money` 輸入 ＋ 中間「至」；chip 顯示 `總計：NT$1,000–NT$5,000`，`white-space: nowrap` |
| **慢網路** | 套用後 chip 進 loading（caret→spinner），表格區換 skeleton；失敗→chip 回滾到前一狀態＋critical toast |
| **篩選狀態與 URL** | 每次變更 `history.replaceState` 寫入 query string（44 行動項 43：cursor 分頁參數直接進 URL，篩選同理） |

### 9.8 實作備註

```html
<div class="cl-chipbar" role="group" aria-label="篩選條件">
  <button type="button" class="cl-fchip" aria-expanded="false" aria-haspopup="dialog">
    <span class="cl-fchip__label">類別</span>
    <svg class="cl-fchip__caret" aria-hidden="true">…</svg>
  </button>
  <span class="cl-fchip cl-fchip--applied">
    <span class="cl-fchip__label">狀態：啟用中</span>
    <button type="button" class="cl-fchip__remove" aria-label="移除 狀態 篩選">✕</button>
  </span>
  <button type="button" class="cl-btn cl-btn--plain cl-btn--sm">清除全部</button>
</div>
```

**常見錯誤做法**：
- ❌ chip 用 `--r-pill` → 47 §2 實測 chip 是 8px 圓角，pill 是給 badge 的。
- ❌ 已套用 chip 的 `✕` 不是獨立 button → 鍵盤無法只移除單一篩選。
- ❌ 移除 chip 時整列做位移動畫 → 篩選多時明顯掉幀。
- ❌ popover 沒有「清除」→ 使用者要逐個取消勾選。
- ❌ 篩選不進 URL。

---

## §10 Saved-view tab ＋ `+` `cl-views`

**來源**：44 §19.9（**saved-view chips `全部` ＋ `+`（新增檢視）**）、44 行動項 54（**全列表統一**）、44 §18.4（`全部｜有效｜未啟用｜POS Pro｜POS Lite｜實體店面`）、44 §19.4（帳單 **7 態** tabs）、44 §22.6（`全部｜地區`）、47 §4（**檢視 tab 高 24、內距 0/2px、圓角 8px、選中態才有背景**）、23 §3（檢視切換器：選中項打勾＋600 字重）。

### 10.1 解剖

```
cl-views  (role="tablist", flex, gap: var(--sp-050), align-items:center)
├─ button.cl-views__tab[role=tab]        × N
│   ├─ cl-views__label      --t-sm
│   └─ cl-views__count      --t-2xs, --text-2（可選）
├─ button.cl-views__tab.cl-views__add    「＋」，--ctl-24 正方
└─ (溢出時) button.cl-views__more        「⋯」，開選單列出剩餘檢視
```

| 屬性 | 值 | 出處 |
|---|---|---|
| tab 高 | `--ctl-24` | 47 §4 |
| tab 內距 | 外層量到 `0 var(--sp-050)`；**我們合併成單層，實作用 `0 var(--sp-200)`** 〔推導：47 量到的 2px 是外層盒，視覺 pill 來自內層文字盒；合併後取 8px 水平內距維持 8px 圓角的視覺比例〕 | 47 §4 |
| 圓角 | `--r-200` | 47 §4 |
| 字級 | `--t-sm` | 47 §3 |
| tab 間距 | `--sp-050` | 47 §1 |
| `＋` 鈕 | `--ctl-24` 正方，`--r-200`，icon 12×12 | — |

**選中態才有背景**（47 §4 明確標註）——未選中的 tab **沒有任何底色與框線**，只有文字色差異。這是與一般 tab 元件最大的差別。

### 10.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（未選中）** | 無底、無框；`color: --text-2` |
| **hover** | `background: --surface-hover`；`color: --text` |
| **active** | `background: --surface-active` |
| **focus-visible** | outline 2px offset 1px |
| **disabled** | `opacity: var(--disabled-opacity)`。用於「此檢視的資料來源暫時不可用」 |
| **loading**（切換檢視中） | tab 立刻進 selected（樂觀），表格區換 skeleton；**tab 本身不放 spinner** |
| **error** | 檢視載入失敗 → tab 保持 selected，表格區換 error 態（inline banner ＋ 重試） |
| **selected** | `background: --surface`；`box-shadow: var(--sh)`；`color: --text`；`font-weight: 500→600`（§0 #83 的例外條款）；`aria-selected="true"` |
| **read-only**（系統預設檢視「全部」） | 可選但**不可重新命名/刪除**：右鍵選單只有「複製為新檢視」 |

**`＋` 鈕的態**：hover `--surface-hover`；點擊後**當前篩選狀態即時存為新檢視** → 立刻在 `＋` 左側插入新 tab 並進入**行內重新命名**（`contenteditable` 或臨時 input，預設值「檢視 N」，全選狀態），`Enter` 確認、`Esc` 取消並刪除。

**已選中 tab 的二次點擊** → 開啟該檢視的動作選單（重新命名／複製／刪除／設為預設）。**不要**在每個 tab 上常駐 `⋯`（會把 24px 高的 tab 塞爆）。

### 10.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| tab 底色 | **M1** | |
| tab 文字色 | **M2** | |
| 選中態的陰影 | **M3** | `box-shadow` 屬於 M3 的三屬性 |
| 檢視動作選單 | **M5** | |
| **禁止** | 底線滑塊（sliding indicator）動畫 | 47 §4 實測是「選中才有背景」的膠囊型，不是底線型；別自己加 |

### 10.4 鍵盤與焦點

- `role="tablist"` ＋ `aria-orientation="horizontal"`；roving tabindex（選中 `0`，其餘 `-1`）——**整列只佔一個 Tab 停留點**。
- `←→` 移動並切換；`Home/End` 首末；`Delete` 在自訂檢視上＝刪除（需二次確認）。
- `＋` 鈕在 roving 序列的**最後一個**，也用 `←→` 抵達。
- 每個 tab `aria-controls` 指向表格容器 id；容器 `role="tabpanel" tabindex="0"`（讓鍵盤能捲動表格）。
- 切換後焦點**留在 tab**，不跳到表格；用 `role="status"` 播報「已切換到 未出貨，共 4 筆」。

### 10.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | 全部平鋪；與右側 `🔍`／`⚙`／`⇅` icon 群同一行 |
| 768–1023 | 超出容器時，末尾收成 `⋯` 溢出選單（**優先保留 selected tab 可見**） |
| ≤767 | 橫捲＋`scroll-snap-type: x proximity` ＋兩端漸層遮罩；**selected tab 自動 `scrollIntoView({inline:'center'})`**；`＋` 固定在捲動容器**外**的右側（不隨捲動消失） |
| ≤429 | 同上；`cl-views__count` 隱藏 |

### 10.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 檢視名** | `max-width: 16ch` ＋ ellipsis ＋ `title`；重新命名時 input 可展開到 24ch |
| **零個自訂檢視** | 只顯示系統預設 tab ＋ `＋`；`＋` 加 tooltip「將目前的篩選存為檢視」 |
| **極多檢視**（>10） | ≥1024 也啟用溢出 `⋯`；溢出選單內可搜尋 |
| **檢視名重複** | 允許重複但在建立時提示「已有同名檢視」（不阻擋——使用者可能刻意如此） |
| **慢網路** | 切換 tab 樂觀更新（tab 立刻反白）＋ 表格 skeleton；失敗回滾 tab 並出 critical banner |
| **檢視與 URL** | `?view={slug}` 進 URL；深連結直接落在該檢視 |
| **7 態發票 tabs**（44 §19.4） | 每個 tab 帶計數；計數為 0 的 tab **不隱藏、不 disable**（讓使用者知道有這個狀態） |

### 10.7 實作備註

```html
<div class="cl-views" role="tablist" aria-label="訂單檢視">
  <button role="tab" class="cl-views__tab is-selected" aria-selected="true" tabindex="0"
          aria-controls="orders-table" id="view-all">
    <span class="cl-views__label">全部</span>
    <span class="cl-views__count">1,284</span>
  </button>
  <button role="tab" class="cl-views__tab" aria-selected="false" tabindex="-1"
          aria-controls="orders-table" id="view-unfulfilled">
    <span class="cl-views__label">未出貨</span><span class="cl-views__count">4</span>
  </button>
  <button type="button" class="cl-views__tab cl-views__add" aria-label="將目前的篩選存為新檢視">＋</button>
</div>
```

**常見錯誤做法**：
- ❌ 用底線指示器 → 與實測的膠囊型不符。
- ❌ 每個 tab 都可 Tab 抵達 → 10 個檢視要按 10 次 Tab。
- ❌ `＋` 用 `<a>` 或 `<div>`。
- ❌ 未選中 tab 加了框或底色 → 47 §4 明確是「選中態才有背景」。
- ❌ tab 高度做成 32 → 實測是 24，這是列表列密度的關鍵。

---

## §11 Badge / Pill `cl-badge`

**來源**：44 §2.2（**pip 語意實測驗證**：`已付款`＝實心圓、`部分已出貨`＝半圓）、44 §3.1（`有效` 綠膠囊）、44 §19.2（價格 badge `$15.00`、`自動計算` badge）、44 §19.4（付款狀態綠 badge `已付款`）、44 §18.2（`使用中` 綠 badge、`建議` badge、`開啟` 綠 badge）、44 §18.6（灰 badge `未設定規則`）、44 §22.6（`地區`／`有效` badges）、44 §2.1（狀態語意詞「警告／謹慎」為 a11y 文字）、47 §1（小 pill 上下內距 `--sp-050`）、23 §3。

### 11.1 解剖

```
span.cl-badge
├─ cl-badge__pip     7×7（可選）；圓、半圓、空圈三形
└─ cl-badge__text    --t-xs
```

| 屬性 | 值 |
|---|---|
| 高 | `20px`〔推導：`--t-xs` 行高 16 ＋ 上下 `--sp-050` ×2 = 20〕 |
| 內距 | `var(--sp-050) var(--sp-200)` |
| 圓角 | `--r-pill` |
| 字級 | `--t-xs`（12/16/500） |
| gap | `--sp-150` |
| pip | `7×7`，`--r-pill`，`border: 1.5px solid currentColor` |

### 11.2 語意色與 pip 的對應（**這是契約的核心，不准自由發揮**）

| 語意 | 底／字 token | pip | 用在哪（44 實測） |
|---|---|---|---|
| `--default` | `--surface-sunken` / `--text-2` | 依進度 | 中性狀態：`未設定規則`、`未訂閱`、`草稿` |
| `--success` | `--success-bg` / `--success` | 實心 | `有效`、`啟用中`、`已付款`、`使用中`、`可見` |
| `--attention` | `--attention-bg` / `--attention` | 空圈 | **未開始**：`未出貨`、`待處理` |
| `--warning` | `--warning-bg` / `--warning` | 半圓 | **進行中**：`部分已出貨`、`部分退款` |
| `--critical` | `--critical-bg` / `--critical` | 實心 | `已取消`、`付款失敗`、`已退款` |
| `--info` | `--info-bg` / `--info` | 無 | `POS Pro`、`自動計算`、資訊性標籤 |
| `--ai` | `--ai-bg` / `--ai` | 無（改 `✦` icon） | AI 產生的內容標記 |

**pip 三形的語意（23 §3 定義，44 §2.2 實測驗證）**：空圈＝未開始／半圓＝進行中／實圈＝完成。**這是資訊設計事實，不是裝飾**——三形必須在無色的情況下也能區分狀態（色盲底線）。

**文案規則**：一律**過去式單詞**（`已付款`／`已出貨`／`已取消`），不用句子。**不要**把 a11y 語意詞寫進可見文字——44 §2.1 觀察到的「警告」「謹慎」是給輔具的，我們用 `<span class="sr-only">` 承載。

### 11.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上表 |
| **hover** | **N/A（badge 不可互動）**。若需要可點 → 那是 filter chip（§9）或 button，不是 badge |
| **active** | N/A |
| **focus-visible** | N/A |
| **disabled** | N/A |
| **loading** | 狀態未知時：`--default` 底 ＋ 文字換 `cl-skeleton` 條（寬 4ch），**不要顯示「載入中」文字**（會被誤讀成狀態） |
| **error** | N/A |
| **selected** | N/A |
| **read-only** | 恆為 read-only（這是它的本質） |

**唯一的例外**：`cl-badge--removable`（標籤 chips，44 §2.2 側欄「標籤」卡）——帶 `✕` 時它變成互動元件，`✕` 是獨立 button，其餘態沿用 §9 的 applied chip。

### 11.4 動效

- **靜態元件，預設無任何 transition。**
- 唯一例外：狀態**因資料變更而改變**時（例：訂單從「未出貨」變「已出貨」），舊 badge `opacity` 淡出 → 新 badge 淡入，各 `--dur-base`／`--ease-in-out`（M1 的時序）。這是為了讓使用者注意到狀態變了。
- **禁止** pulse／閃爍動畫。唯一允許的持續動畫是「即時訪客」的綠點（44 §1），那是獨立元件不是 badge。

### 11.5 鍵盤與焦點

**badge 不進 Tab 序、沒有焦點態**——它是靜態標記。以下是它必須做對的三件無障礙事項：

| 項 | 規則 |
|---|---|
| **顏色不是唯一線索** | 語意同時由**文字**（`已付款`）＋ **pip 形狀**（空圈／半圓／實圈）承載。把畫面轉灰階後仍必須能區分狀態——這是驗收條件，不是建議 |
| **補充語意用 sr-only** | 44 §2.1 觀察到的「警告／謹慎」這類語意詞放 `<span class="sr-only">`，不出現在可見文字 |
| **狀態變更要播報** | 資料變更導致 badge 改變時（訂單被出貨），由**列或卡片層級**的 `role="status"` 播報（「訂單 #1042 已更新為 已出貨」）。**badge 本身不掛 `aria-live`**——一張表 50 個 badge 各自 live 會把輔具洗版 |

**唯一有焦點的例外**：`cl-badge--removable`（標籤 chip）的 `✕` 是真 `<button>`，`aria-label="移除標籤 VIP"`，沿用 §9 的鍵盤規則。

### 11.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 基準 |
| ≤767 | 表格卡片化後，badge 移到卡片標題列右側；同列多個 badge 允許換行（`flex-wrap`） |
| ≤429 | 超過 2 個 badge 時，第 3 個起收成 `+N`（44 §2.1 的標籤欄 `+ 1` 模式） |

### 11.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 狀態名** | badge **不截斷、不換行**（`white-space: nowrap`）。若太長 → 改文案，不改元件 |
| **金額 badge**（44 §19.2 `$15.00`） | `.cl-money`；免運表達照抄實測：**副標寫「滿 NT$2,000 免費」，價格 badge 仍顯示原價**（44 §19.2 行動項 40），不要把價格改成 0 |
| **零筆** | 計數 badge 為 0 時**隱藏整個 badge**（不顯示「0」），除非該 0 有語意（如發票狀態 tabs 的計數） |
| **極大數量** | `99+`／`9k+` |
| **多 badge 並排** | `gap: var(--sp-150)`；順序固定：**付款狀態 → 出貨狀態 → 其他**（44 §2.2 實測順序），不要依資料回傳順序渲染 |
| **取消訂單整列 line-through**（44 §2.1） | **badge 豁免**：`.cl-table__row.is-cancelled .cl-badge{text-decoration: none}` |

### 11.8 實作備註

```html
<span class="cl-badge cl-badge--warning">
  <span class="cl-badge__pip cl-badge__pip--half" aria-hidden="true"></span>
  <span class="cl-badge__text">部分已出貨</span>
  <span class="sr-only">（進行中）</span>
</span>
```

**常見錯誤做法**：
- ❌ 給 badge 加 hover 效果 → 使用者會去點它。
- ❌ 用 badge 當按鈕。
- ❌ pip 只用顏色區分 → 色盲使用者看不出「未開始／進行中／完成」。
- ❌ badge 文字寫成句子（「這筆訂單已經付款了」）。
- ❌ 語意色亂配（用 `--info` 表示成功）→ 語意色的對應表是契約，不是建議。
- ❌ 計數為 0 還顯示 badge。

---

## §12 表格 `cl-table`

**來源**：44 §2.1（訂單 **13 欄**、1024 下橫向捲動、已取消訂單整列 line-through、標籤 chips `+1` 收合、多幣別直接顯示）、44 §3.1（產品 **9 欄**、最後一欄「操作」、庫存 0 紅字、表頭全選 checkbox、分頁 `‹ ›` ＋ `1-50`）、44 §19.4（帳單表：checkbox／日期／號碼／類型／狀態 badge／金額右對齊）、44 §19.8（可排序欄 `⇅`、預設排序欄）、44 §19.5（**skeleton 列＝圓形 icon 佔位＋長條文字佔位，三列**）、47 §4（**表格資料列 32、表頭列內距 2px、可排序表頭鈕 28 高／6px 內距／圓角 0**）、47 §1、23 §3（BulkBar）。

### 12.1 解剖

```
cl-tablewrap                      position:relative（bulkbar 的定位脈絡）
├─ cl-listbar                     檢視 tabs ＋ 搜尋 ＋ icon 群；高 --ctl-36；sticky
├─ cl-chipbar                     已套用篩選 chips（可選）
├─ cl-bulkbar                     選取 >0 時覆蓋在表頭上方
├─ cl-tablescroll                 overflow-x:auto; overscroll-behavior-x: contain
│   └─ table.cl-table
│       ├─ thead.cl-table__head           position:sticky; top:0; z-index: var(--z-sticky)
│       │   └─ tr > th.cl-table__th
│       │        └─ button.cl-table__sort   可排序欄才有
│       └─ tbody
│            └─ tr.cl-table__row
│                 ├─ td.cl-table__cell--check
│                 ├─ td.cl-table__cell
│                 └─ td.cl-table__cell--actions   列尾動作欄（44 §3.1）
├─ cl-table__airow                AI 建議 inline 列（§23，混在資料列之後）
└─ cl-pagination                  §30
```

| 元素 | 高 | 內距 | 字級 | 底 | 出處 |
|---|---|---|---|---|---|
| 表頭列 | `32`〔＝28+2×2〕 | `var(--sp-050) var(--sp-300)` | `--t-xs` | `--surface-3` | 47 §4/§1 |
| 可排序表頭鈕 | `--ctl-28` | `var(--sp-150)` | `--t-xs` | 透明，`--r-000` | 47 §4 |
| 資料列 | `--ctl-32` | `var(--sp-200) var(--sp-300)` | `--t-xs` | `--surface` | 47 §4 |
| checkbox 欄 | — | `var(--sp-200) var(--sp-300)`；`width: calc(var(--sp-400) + var(--sp-300)*2)` | — | — | 47 §4 |
| 分隔線 | `--bw-100 var(--border-2)`（只有 `border-bottom`） | | | | |

**列高 32 的算術（別破壞它）**：`--t-xs` 行高 16 ＋ 上下 `--sp-200`(8) ×2 = **32 = `--ctl-32`**。任何把儲存格字級改回 13 的動作都會讓列高變成 36，整張表的密度就跑掉了。

### 12.2 完整態表（列 `cl-table__row`）

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | `background: --surface`；`border-bottom: --bw-100 --border-2` |
| **hover** | `background: --surface-hover`；`cursor: pointer`（整列可點進詳情）。**checkbox 欄與動作欄要 `stopPropagation`**，避免點勾選變成進詳情 |
| **active** | `background: --surface-active` |
| **focus-visible** | 列本身**不可聚焦**。焦點落在列內第一個 `<a>`（主要識別欄）上，該 `<a>` 的 outline 用 `outline-offset: -2px` 內縮，避免被 `overflow` 裁掉 |
| **disabled** | 列不可用（例：正在被其他人編輯）→ `opacity: var(--disabled-opacity)`；checkbox disabled；`cursor: not-allowed`；`aria-disabled="true"` |
| **loading** | 單列更新中：該列 `aria-busy="true"`，右端出 16px spinner，其餘欄位保持可讀。**整表載入用 skeleton（§12.10），不是遮罩** |
| **error** | 該列操作失敗：`box-shadow: inset var(--bw-200) 0 0 var(--critical)`（左紅邊）保持 3s 後淡出；同時出 critical toast |
| **selected** | `background: var(--selected-bg)`；checkbox checked；**hover 時仍維持 selected 底**（不被 hover 覆蓋，用 `.is-selected:hover{background: color-mix(in srgb, var(--selected-bg) 92%, var(--text))}`） |
| **read-only** | 整表唯讀時：隱藏 checkbox 欄與動作欄，列 `cursor: default`，hover 底色仍保留（幫助掃視） |
| **cancelled（業務態）** | 整列 `text-decoration: line-through`；`color: --text-3`；**badge 豁免**（44 §2.1 實測＋23 §3） |

### 12.3 表頭 `cl-table__th` 態表

| 態 | 變什麼 |
|---|---|
| default | `--surface-3` 底；`--t-xs`；`color: --text-2`；`text-align: left`（數字欄 `right`） |
| hover（可排序） | 排序鈕 `background: --surface-hover`；`⇅` icon `opacity: .4→1` |
| active | 排序鈕 `background: --surface-active` |
| focus-visible | 排序鈕 outline，`outline-offset: -2px` |
| **sorted** | `color: --text`；icon 換成 `↑`／`↓` 且 `opacity: 1`；`aria-sort="ascending"｜"descending"` |
| sticky（吸附中） | `box-shadow: var(--sh-sticky)`（**只在 `scrollTop > 0` 時加**，用 IntersectionObserver 偵測） |
| disabled | 不可排序的欄不渲染排序鈕（不是 disabled 的鈕） |

### 12.4 批次操作列 `cl-bulkbar`（23 §3 ＋ 44 §2.1）

| 屬性 | 值 |
|---|---|
| 定位 | `position: absolute; inset-inline: var(--sp-300); top: var(--sp-150)`；**覆蓋在表頭上方**（不是推開表頭） |
| 高／圓角／底 | `--ctl-36`／`--r-300`／`--surface-inverse` |
| 字色 | `--text-inverse`；動作鈕 `--t-xs` |
| z-index | `--z-bulkbar` |
| 內容 | `已選取 {n}` ＋ 動作組 ＋ 右端 `✕ 清除選取` |

**態表**：出現＝選取 >0；消失＝選取 =0。動作鈕的態沿用 §1 的 `--plain`（但配色反轉：`color: --text-inverse`，hover `background: rgba(255,255,255,.15)`）。**焦點環在深底上改用 `--text-inverse`**。

**跨頁選取**：勾表頭後 bulkbar 內加一行「已選取本頁 50 筆，選取全部 1,284 筆」；跨頁選取狀態下，任何動作都要**二次確認 modal**。

### 12.5 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 列 hover 底 | **M1** | 47 實測 hover 底色 ×14 是最高頻互動 |
| 列選取底 | **M1** | |
| 表頭排序鈕底／icon 色 | **M1 ＋ M2** | |
| sticky 陰影 | **M3**（`box-shadow` 在三屬性內） | |
| bulkbar 進出 | **M5**（`opacity + scale`，`transform-origin: top center`） | 它是覆蓋在表頭上的浮層 |
| 排序後列重排 | **不做動畫** | 47 提到「IndexTable 排序條」keyframes，但列的位移動畫在 50 列規模必掉幀 |
| skeleton→真列 | **不做淡入** | 直接替換；淡入會讓資料看起來還在載入 |

### 12.6 鍵盤與焦點

- 表格用真 `<table>`；`<caption class="sr-only">` 描述表格內容與筆數。
- Tab 順序：全選 checkbox → 各排序鈕 → 列 1 的 checkbox → 列 1 的主連結 → 列 1 的動作鈕 → 列 2…
- `Shift+Click` 範圍選取；`⌘/Ctrl+A` 在表格內＝全選當前頁（要 `preventDefault`）。
- `j`／`k` 上下移動高亮列（23 §4.3 標為 P2；實作時 `aria-activedescendant`）。
- 排序鈕：`aria-sort` 放在 `<th>` 上（不是按鈕上）；點擊循環 `無序 → 升冪 → 降冪 → 無序`。
- 每次排序／篩選後用 `role="status"` 播報「依 日期 降冪排序，共 1,284 筆」。
- 橫捲容器要能鍵盤捲動：`tabindex="0"` ＋ `role="region"` ＋ `aria-label="訂單表格，可水平捲動"`。

### 12.7 響應式（34 §2 規則 2 的落地）

| 斷點 | 變化 |
|---|---|
| ≥1280 | 全欄顯示；表格 `max-width: var(--w-index-max)` |
| 1024–1279 | **橫捲容器**（`overflow-x: auto`）＋ **黏性首欄**（`position: sticky; inset-inline-start: 0`，含 checkbox 欄與主識別欄）；黏性欄需 `background: --surface` ＋ 右側 `box-shadow` 分隔 |
| 768–1023 | 同上 |
| ≤767 | **≤8 欄 → 卡片化**；>8 欄 → 保持橫捲＋黏性首欄。卡片化規則：`<th>` 文字用 `data-label` 補到每個 cell 的 `::before`；首欄當卡片標題（`--t-md`）；checkbox 絕對定位到卡片右上；**thead 只保留「全選」一行，不可整個藏掉**（34 §已定，藏掉會遺失全選功能）；`role=table/rowgroup/row/cell` 要手動補（`display` 被覆寫後語意會消失） |
| ≤429 | 卡片內欄位改 label/value 上下堆疊 |

### 12.8 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 儲存格**（商品名、內容節錄） | `max-width: 32ch` ＋ 單行 ellipsis ＋ `title`；44 §19.9 實測「內容」欄就是純文字節錄尾端 `…` |
| **金額折行** | 金額欄 `.cl-money`（nowrap ＋ tabular-nums）＋ **`text-align: right`**；多幣別直接顯示 presentment currency（`RM 639.74 MYR`），**不要換算** |
| **零筆資料** | 表格區換**卡內空態**（§24.2）；**listbar 與檢視 tabs 保留**（不要整塊消失）；動作鈕 disabled 不隱藏 |
| **搜尋零結果** | 與「零筆資料」不同：文案「找不到符合「{q}」的結果」＋「清除搜尋」plain 鈕 |
| **極大數量**（>10k 列） | cursor 分頁（≤250/頁，CLAUDE.md 鐵律 4）；**不做無限捲動**（會破壞「第幾頁」的心智模型與可分享性）；總數顯示近似值 |
| **極多欄**（13 欄） | 提供欄位設定 icon（44 §2.1 實測 `▥`），使用者可隱藏欄；設定存 localStorage ＋ 使用者偏好 API |
| **慢網路** | 首載 → skeleton 三列（§12.10）；換頁 → skeleton 取代列（**不是整頁 spinner**，23 §3）；>1s 才顯示 skeleton（避免閃爍） |
| **列高不一致** | 儲存格內若有 badge/chip/縮圖，統一 `align-items: center` ＋ 元素 `flex:none`；**縮圖固定 `--sp-600`(24) 或 36 正方 ＋ `aspect-ratio: 1`**，防 CLS |
| **狀態列同時有 line-through 與 badge** | badge 豁免（§11.6） |

### 12.9 空態變體對照

| 情境 | 用什麼 | 文案 |
|---|---|---|
| 從未有資料 | **全頁空態**（§24.1，插圖＋CTA） | 「管理您的網址重新導向」＋雙鈕 |
| 篩選/搜尋後無結果 | **卡內空態**（§24.2）＋「清除搜尋」 | 「找不到符合「{q}」的結果」 |
| 某個時間範圍無資料 | **卡內空態**，單行灰字 | 「此日期範圍無資料」（44 §22.3 逐字） |
| 載入失敗 | **inline banner（critical）** ＋「重試」 | 「無法載入訂單，請重試」 |

### 12.10 Skeleton `cl-skeleton`（44 §19.5 實測）

```
cl-skeleton__row      × 3（固定三列，44 實測）
├─ cl-skeleton--circle    圓形 icon 佔位，24×24，--r-pill
└─ cl-skeleton--text      長條文字佔位，height: var(--sp-400)，--r-100，寬度 60%/85%/45% 輪替
```

| 屬性 | 值 |
|---|---|
| 底 | `linear-gradient(90deg, var(--surface-hover) 25%, var(--surface) 50%, var(--surface-hover) 75%)`；`background-size: 200% 100%` |
| 動畫 | `--dur-shimmer`（1200ms）`--ease-linear` infinite |
| 何時出現 | 資料請求 >300ms 後（避免閃爍）；最少顯示 400ms |
| reduced motion | 停用 shimmer，改靜態 `--surface-hover` |

**skeleton 的欄位形狀必須貼近真實列**（圓形給頭像/縮圖、長條給文字、短條給 badge），否則資料到位時版面會跳。

### 12.11 實作備註

```html
<div class="cl-tablewrap">
  <div class="cl-listbar">…</div>
  <div class="cl-bulkbar" hidden>…</div>
  <div class="cl-tablescroll" role="region" tabindex="0" aria-label="訂單表格，可水平捲動">
    <table class="cl-table" id="orders-table">
      <caption class="sr-only">訂單清單，共 1,284 筆</caption>
      <thead class="cl-table__head">
        <tr>
          <th class="cl-table__th cl-table__th--check" scope="col">
            <label class="cl-check"><input type="checkbox" class="cl-check__box"
              aria-label="選取本頁全部 50 筆訂單"></label>
          </th>
          <th class="cl-table__th" scope="col" aria-sort="descending">
            <button type="button" class="cl-table__sort">訂單 <svg aria-hidden="true">…</svg></button>
          </th>
          <th class="cl-table__th cl-table__th--num" scope="col">總計</th>
        </tr>
      </thead>
      <tbody>
        <tr class="cl-table__row">
          <td class="cl-table__cell cl-table__cell--check" data-cl-stop>…</td>
          <td class="cl-table__cell" data-label="訂單"><a href="/orders/1042">#1042</a></td>
          <td class="cl-table__cell cl-table__cell--num" data-label="總計">
            <span class="cl-money">NT$1,480</span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
  <nav class="cl-pagination">…</nav>
</div>
```

**常見錯誤做法**：
- ❌ 用 `div` 格線做表格 → 失去 `aria-sort`、`scope`、行列導覽。
- ❌ 儲存格用 `--t-sm`(13) → 列高變 36，密度跑掉。
- ❌ 整列包 `<a>` → HTML 不合法且無法讓 checkbox 獨立可點。正解：列 `onclick` ＋ 主識別欄放真 `<a>`。
- ❌ sticky 表頭忘了 `background` → 列會透出來。
- ❌ 橫捲容器沒有 `tabindex="0"` → 鍵盤使用者無法捲。
- ❌ 卡片化時整個藏掉 `thead` → 遺失全選。
- ❌ 換頁用整頁 spinner。
- ❌ 金額欄沒有 `tabular-nums` → 數字上下對不齊。

---

## §13 卡片 `cl-card`（含堆疊群組單邊圓角）

**來源**：47 §2（**卡片圓角 `--r-300`，x11 最高頻**；**單邊圓角成對用法 `12px 12px 0 0` 與 `0 0 12px 12px`，x2 各 → 堆疊卡片群組**）、47 §1（卡片內距 `--sp-300`、卡片間距 `--sp-400`、區段間 `--sp-600`）、44 §18.2（設定檔卡片：標題＋badge＋時間＋`⋯`＋primary）、44 §19.3（**卡片 footer bar**：灰底、左連結群、右 destructive-secondary）、44 §18.6（卡片 footer 灰底提示文字）、44 §2.2（訂單詳情依 fulfillment order 分卡）。

### 13.1 解剖

```
cl-card                       --surface, --bw-100 --border, --r-300, --sh
├─ cl-card__head              flex; padding: var(--sp-300) var(--sp-400); gap: var(--sp-200)
│   ├─ cl-card__title         --t-lg（16/20/**450**）
│   ├─ cl-card__badge         §11
│   ├─ cl-card__meta          --t-xs, --text-2（「上次儲存日期：…」）
│   └─ cl-card__actions       margin-inline-start:auto；⋯ ＋ primary
├─ cl-card__body              padding: var(--sp-400)
│   └─ cl-card__section       相鄰 section 間 border-top: --bw-100 --border-2；padding-block: var(--sp-400)
├─ cl-card__subcard           內嵌子卡：--surface-3 底，--r-200，--bw-100 --border-2，padding: var(--sp-300)
└─ cl-card__footerbar         --surface-3 底；padding: var(--sp-300) var(--sp-400)；border-top；圓角只有下緣
```

| 層 | 內距 | 圓角 | 字級 |
|---|---|---|---|
| card | — | `--r-300` | — |
| head | `var(--sp-300) var(--sp-400)` | — | title `--t-lg` |
| body | `var(--sp-400)` | — | `--t-sm` |
| subcard | `var(--sp-300)` | `--r-200` | `--t-sm` |
| footerbar | `var(--sp-300) var(--sp-400)` | `0 0 var(--r-300) var(--r-300)` | `--t-xs` |

**卡片標題字重 450**（47 §3 `--t-lg` 的 weight，＋#83）——這是最違反直覺、也最容易被實作者「順手改回 600」的一條。**別改**。

### 13.2 堆疊卡片群組 `cl-cardgroup`（47 §2 的新規則，原型完全沒有）

```css
.cl-cardgroup{ display:flex; flex-direction:column; }
.cl-cardgroup > .cl-card{ border-radius: var(--r-000); }
.cl-cardgroup > .cl-card:first-child{ border-radius: var(--r-300) var(--r-300) 0 0; }
.cl-cardgroup > .cl-card:last-child { border-radius: 0 0 var(--r-300) var(--r-300); }
.cl-cardgroup > .cl-card:only-child { border-radius: var(--r-300); }
.cl-cardgroup > .cl-card + .cl-card{ border-block-start: 0; }   /* 相鄰邊只留一條線 */
```

| 規則 | 說明 |
|---|---|
| 群組內卡片**貼合無間距**（`gap: 0`） | 這是「同一實體的多個區段」的視覺語言（44 §18.6 的規則卡、44 §19.2 的 zone 卡） |
| 相鄰邊**只留一條 `--bw-100`** | 用 `border-top: 0` 消除疊線；不要用 `margin: -1px` |
| 群組**整體**才有 `--sh` | 個別卡片 `box-shadow: none`，群組容器掛陰影 |
| 何時用群組 vs 何時用間距 | 同一實體的區段 → 群組；不同實體 → `gap: var(--sp-400)` 的獨立卡片 |

### 13.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | `--surface` ＋ `--border` 框 ＋ `--sh` |
| **hover** | **N/A**（一般卡片不可互動）。**可點卡片** `cl-card--clickable`：`border-color: --border-strong`；`box-shadow: var(--sh-pop)` 的弱化版；**不做位移** |
| **active** | 可點卡片：`background: --surface-hover` |
| **focus-visible** | 可點卡片：outline 環繞整卡（`:has(:focus-visible)`），`outline-offset: 2px` |
| **disabled** | 整卡 `.is-disabled`：`opacity: var(--disabled-opacity)` ＋ `pointer-events: none` ＋ **`inert`**（讓內部控件退出 Tab 序）。用於 44 §18.6「規則關閉時整卡灰化」 |
| **loading** | body 換 skeleton（§12.10）；head 保持真實（標題不該閃） |
| **error** | `border-color: --critical`；head 下方插入 inline banner（critical） |
| **selected** | `border: var(--bw-200) solid var(--focus)`；**內距減 1px 補償**；`background: color-mix(in srgb, var(--focus) 4%, var(--surface))` |
| **read-only** | 無視覺變化；內部控件各自進 read-only |

### 13.4 動效

| 屬性 | 規則 |
|---|---|
| 可點卡片的框與陰影 | **M3** |
| 可點卡片的底 | **M1** |
| 卡片關閉（44 §1 任務卡可關閉） | `opacity` ＋ `max-height: 0`（**M4**）＋ `margin-block: 0`；`--dur-fast` |
| 卡片新增 | **不做進場動畫**（卡片是內容不是浮層） |
| **禁止** | hover 抬升（`translateY`）、hover 放大——47 沒量到任何卡片位移 |

### 13.5 鍵盤與焦點

- 卡片本身不是互動元件 → **沒有 `tabindex`**。
- `cl-card--clickable`：整卡包 `<a>` 或用「卡內主標題是 `<a>` ＋ 卡片 `::after` 覆蓋擴大命中區」的做法（後者較佳：文字仍可選取）。
- 卡片標題用 `<h2>`/`<h3>`（依頁面層級），**不要用 `<div>` + 字級**——輔具的標題導覽依賴它。
- `cl-card__actions` 的 `⋯` 選單：`aria-haspopup="menu"`，`aria-label="{卡片標題} 的更多動作"`（不要只寫「更多動作」，一頁有 10 個會分不清）。
- 群組卡片用 `<section aria-labelledby>` 包，讓輔具知道邊界。

### 13.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 詳情頁 `grid-template-columns: 1fr var(--w-aside)`；卡片間 `--sp-400` |
| 1024–1279 | 同上；頁邊由 `--sp-800` 收到 `--sp-400` |
| ≤1023 | **兩欄→單欄，側欄卡片移到主欄之後**（34 §規則 4）；順序用 `order` 控制，不要靠 DOM 重排 |
| ≤767 | card 內距 `--sp-400`→`--sp-300`；head 的 actions 換行到標題下方；**卡片圓角保留 `--r-300`**（不要為了貼邊改成 0） |
| ≤429 | 卡片左右邊距 `--sp-300`；`cl-card__subcard` 內距降到 `--sp-200` |

### 13.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標題** | `cl-card__title{min-width:0; overflow-wrap:anywhere}`；actions `flex:none`。**actions 永不被擠壓** |
| **金額在卡頭**（44 §19.4 累積總計 `$0.00 USD` 超大字右對齊） | 用 `--t-display` ＋ `.cl-money` ＋ `text-align: right`；≤767 降到 `--t-3xl` |
| **零筆內容** | 卡內空態（§24.2），**卡片框保留**（不要整張卡消失，使用者會以為功能不見了） |
| **極多 section**（>8） | 改用 accordion（§15）或 CollapsedEditCard（§14） |
| **慢網路** | head 先渲染、body skeleton；**不要整卡 skeleton**（標題已知就該先給） |
| **卡片內橫捲內容** | 表格／程式碼區塊要自帶 `overflow-x`，**不要讓卡片本身橫捲**（會把圓角與陰影一起捲走） |

### 13.8 實作備註

```html
<section class="cl-card" aria-labelledby="c-profile">
  <div class="cl-card__head">
    <h3 class="cl-card__title" id="c-profile">「CHILL LOVE」設定</h3>
    <span class="cl-badge cl-badge--success">
      <span class="cl-badge__pip cl-badge__pip--full" aria-hidden="true"></span>使用中
    </span>
    <span class="cl-card__meta">上次儲存日期：7月14日 上午9:40</span>
    <div class="cl-card__actions">
      <button type="button" class="cl-btn cl-btn--icon" aria-label="「CHILL LOVE」設定的更多動作">⋯</button>
      <button type="button" class="cl-btn cl-btn--primary cl-btn--sm">編輯</button>
    </div>
  </div>
  <div class="cl-card__body">…</div>
  <div class="cl-card__footerbar">
    <p class="cl-card__footerbar-text">退貨與取消規則適用於在啟用或更新規則後所購買的品項</p>
  </div>
</section>
```

**常見錯誤做法**：
- ❌ 卡片標題用 600/700 → 47 §3 實測 `--t-lg` 是 **450**。
- ❌ 堆疊群組用 `gap` 分開再各自圓角 → 失去「同一實體」的語意。
- ❌ 群組內每張卡都掛 `--sh` → 相鄰處出現雙重陰影暗帶。
- ❌ 卡片 hover 抬升。
- ❌ disabled 的卡片只降透明沒加 `inert` → 內部控件仍可 Tab 進入。
- ❌ 零筆時整張卡不渲染。


---

## §14 CollapsedEditCard `cl-cec`

**來源**：44 §22.2（文章編輯器的 `摘錄 ＋ ✏` 與 `搜尋引擎產品資訊 ＋ ✏`：**摺疊態卡＝標題＋鉛筆＋一句說明，點才展開**）、44 行動項 67（元件化為 `CollapsedEditCard`）、44 §3.2（商品詳情的 SEO 區同型）、47 §5 M4（`max-height` 展開）。

### 14.1 解剖

```
cl-cec  (= cl-card 的變體)
├─ button.cl-cec__trigger        整個摺疊態就是這顆按鈕；padding: var(--sp-300) var(--sp-400)
│   ├─ cl-cec__title             --t-lg（450）
│   ├─ cl-cec__hint              --t-xs, --text-2；**一句說明**（不是內容預覽）
│   └─ cl-cec__pencil            ✏ 16×16，margin-inline-start:auto，--text-2
└─ div.cl-cec__panel             展開內容；padding: 0 var(--sp-400) var(--sp-400)
```

**與 accordion（§15）的差別（別搞混）**：
| | CollapsedEditCard | Accordion |
|---|---|---|
| 摺疊態顯示 | **一句固定說明**（「新增文章摘要，以便顯示在您的首頁或網誌上。」） | **當前值摘要**（「所有商品 • 1 個地點 • 2 個區域」） |
| 圖示 | `✏` 鉛筆（暗示「進入編輯」） | `⌄` 箭頭（暗示「展開檢視」） |
| 內容 | 表單欄位 | 唯讀資訊或表單皆可 |
| 展開後 | 通常只留一個展開（手風琴語意弱） | 可多個同時展開 |
| 用在哪 | 編輯器的次要區塊（摘錄／SEO） | 設定頁的分區（運送外層、通知分組） |

### 14.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（摺疊）** | 卡片外觀；trigger 透明底；`cl-cec__hint` 顯示一句說明 |
| **hover** | trigger `background: --surface-hover`；`cl-cec__pencil` `color: --text` |
| **active** | trigger `background: --surface-active` |
| **focus-visible** | outline 環繞 trigger，`outline-offset: -2px`（內縮，避免溢出卡片圓角） |
| **disabled** | 整卡 `.is-disabled`（`opacity` ＋ `inert`）；hint 換成停用原因 |
| **loading** | 展開後內容未就緒：panel 顯示 skeleton 兩列 |
| **error** | 內容有驗證錯誤且**目前是摺疊態** → 卡片 `border-color: --critical` ＋ hint 換成紅字錯誤摘要（「標題超出 70 字元」）＋ **自動展開**。摺疊態藏住錯誤是最糟的做法 |
| **selected** | N/A |
| **read-only** | trigger 不可點；`✏` 隱藏；panel 恆展開且內部控件 read-only |
| **expanded** | `aria-expanded="true"`；`cl-cec__hint` **淡出隱藏**（展開後說明沒用了）；`✏` 換成 `⌃`；panel 顯示 |
| **has-value（有內容但摺疊）** | hint 換成**內容摘要前 40 字 ＋ `…`**（`--text-2`）。這是 44 沒直接觀察到、但實作必需的第四態〔推導〕 |

### 14.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| panel 展開／收合 | **M4**（`max-height var(--dur-fast) var(--ease-decelerate)`） | 47 實測摺疊就是 max-height + 100ms + decelerate。**不是 `height`** |
| trigger 底色 | **M1** | |
| `✏`↔`⌃` 圖示切換 | `opacity` 交叉淡入，`--dur-fast` | 不要旋轉（鉛筆旋轉沒有語意） |
| hint 淡出 | `opacity var(--dur-fast)` | |

**M4 的實作陷阱**：`max-height` 必須設一個「一定大於實際高度」的值，否則內容被裁。做法：展開時 JS 讀 `scrollHeight` 設為精確值，動畫結束後改 `max-height: none`（否則內容變高會被裁）。收合時反向：先設回精確值，強制 reflow，再設 0。

### 14.4 鍵盤與焦點

- trigger 是真 `<button aria-expanded aria-controls>`；panel `id` 對應。
- `Enter`／`Space` 切換。
- 展開後焦點**留在 trigger**（不自動跳進 panel）——使用者可能只是想看一眼。
- **例外**：因驗證錯誤自動展開時，焦點跳到第一個錯誤欄位。
- panel 收合時，若焦點在 panel 內 → 焦點移回 trigger（否則焦點會落在 `display:none` 的元素上）。
- 收合的 panel 用 `hidden` 或 `inert`，**不要只用 `max-height: 0`**（內容仍在 Tab 序）。

### 14.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 基準 |
| ≤767 | trigger 內距降到 `var(--sp-300)`；hint 允許兩行；`✏` 命中區補到 `--hit-min` |

### 14.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 說明** | hint 單行 ellipsis（摺疊態）；展開後不截斷 |
| **零內容** | hint 顯示原始說明（44 實測文案），不是「尚未填寫」 |
| **極長 panel 內容** | panel 內不設 `max-height`；讓頁面捲動。**不要在卡片內做內捲** |
| **慢網路** | 展開時內容需請求 → panel 立刻展開並顯示 skeleton，**不要等資料到才展開** |
| **展開狀態持久化** | 存 sessionStorage（`{pageKey}:{cardKey}`）；重整後保持。**不要**存進伺服器偏好（太瑣碎） |
| **同頁多個 CEC 同時展開** | 允許。這不是手風琴 |

### 14.7 實作備註

```html
<section class="cl-card cl-cec">
  <button type="button" class="cl-cec__trigger" aria-expanded="false" aria-controls="cec-excerpt">
    <span class="cl-cec__title">摘錄</span>
    <span class="cl-cec__hint">新增文章摘要，以便顯示在您的首頁或網誌上。</span>
    <svg class="cl-cec__pencil" aria-hidden="true">…</svg>
  </button>
  <div class="cl-cec__panel" id="cec-excerpt" hidden>
    <div class="cl-field">…</div>
  </div>
</section>
```

**常見錯誤做法**：
- ❌ 用 `<div onclick>` 當 trigger。
- ❌ 收合時只設 `max-height: 0` 沒加 `hidden`/`inert` → 內容仍可 Tab 進入，焦點消失在畫面外。
- ❌ 摺疊態藏住驗證錯誤。
- ❌ 用 `height` 而非 `max-height`（M4 明確要求）。
- ❌ 展開後忘記把 `max-height` 改成 `none` → 內容變高時被裁掉。
- ❌ 把 hint 寫成內容預覽卻又同時顯示說明 → 兩者是同一個位置的互斥內容。

---

## §15 Accordion `cl-acc`

**來源**：44 §19.1（**運送外層＝accordion＋當前值摘要行，非跳頁**：`運送設定檔` → 摘要「1 個運送設定檔」；`預計配送日期` → 「自動化日期」；`包材` → 「1 個箱子」）、44 行動項 36、44 §18.7（通知範本**依事件分組，每組可摺疊 `^`**）、44 §19.2（zone 內 carrier 服務清單 `⌄` 展開）、44 §2.2（時間軸列的展開箭頭 `⌄`）、47 §5 M4。

### 15.1 解剖

```
cl-acc                          （容器，可含多個 item）
└─ cl-acc__item
    ├─ h3 > button.cl-acc__trigger    高 --ctl-36；padding: 0 var(--sp-400)
    │    ├─ cl-acc__icon        可選 20×20
    │    ├─ cl-acc__title       --t-sm
    │    ├─ cl-acc__summary     --t-xs, --text-2, margin-inline-start:auto（**當前值摘要**）
    │    └─ cl-acc__caret       12×12
    └─ cl-acc__panel            padding: 0 var(--sp-400) var(--sp-400)
```

| 屬性 | 值 |
|---|---|
| trigger 高 | `--ctl-36`（有摘要行時允許 `min-height` 隨兩行內容長高） |
| item 分隔 | `border-block-start: --bw-100 var(--border-2)`（第一個沒有） |
| 圓角 | 容器 `--r-300`；item 本身 `--r-000`（同 §13.2 的堆疊規則） |
| caret | 收合 `↓`／展開 `↑`；用 `rotate(180deg)` 切換 |

**摘要行是本元件的靈魂**（44 §19.1 的關鍵發現）：**讓使用者不展開也知道現況**。任何 accordion 若摘要欄空著，就該問「這一區是不是不該用 accordion」。

### 15.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（收合）** | trigger 透明底；caret `--text-3`；摘要顯示當前值 |
| **hover** | trigger `background: --surface-hover`；caret `--text-2` |
| **active** | trigger `background: --surface-active` |
| **focus-visible** | outline，`outline-offset: -2px` |
| **disabled** | trigger `opacity: var(--disabled-opacity)`＋`aria-disabled`；摘要換成停用原因（例：「需先啟用運送」） |
| **loading** | 展開後 panel skeleton；摘要行顯示 skeleton 條（因為摘要值也要查） |
| **error** | trigger 左緣 `box-shadow: inset var(--bw-200) 0 0 var(--critical)`；摘要換紅字錯誤數（「2 個欄位有誤」）；**自動展開** |
| **selected** | N/A |
| **read-only** | 可展開檢視，panel 內控件 read-only；caret 保留 |
| **expanded** | `aria-expanded="true"`；caret 旋轉 180°；**摘要行保留顯示**（與 CEC 不同——摘要在展開後仍有價值，44 §19.1 實測如此） |

### 15.3 動效

| 屬性 | 規則 |
|---|---|
| panel | **M4**（同 §14.3，含 `max-height` 陷阱） |
| trigger 底 | **M1** |
| caret 旋轉 | `rotate var(--dur-fast) var(--ease-decelerate)` |
| **禁止** | panel 內容的逐項延遲進場（stagger） |

### 15.4 鍵盤與焦點

- 每個 trigger 是 `<button aria-expanded aria-controls>`，包在 `<h3>` 內（讓標題導覽可用）。
- `↑↓` 在**同一個 accordion 內**的 trigger 之間移動（WAI-ARIA accordion pattern）；`Home/End` 首末。
- `Enter`／`Space` 切換。
- **允許多個同時展開**（44 §19.1 實測沒有互斥）。若某處需要互斥，用 `data-cl-acc="single"` 明示。
- 展開狀態持久化：sessionStorage。

### 15.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 標題與摘要同一行，摘要右對齊 |
| ≤767 | **摘要換行到標題下方，左對齊**（右對齊的摘要在窄螢幕會被擠成兩三個字）；trigger `min-height: var(--ctl-44)` |
| ≤429 | 同上；`cl-acc__icon` 隱藏 |

### 15.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 摘要**（「未包含於其他設定檔的所有商品 • 1 個地點 • 2 個區域」） | 桌機單行 ellipsis ＋ `title`；≤767 允許兩行 |
| **摘要含金額** | 拆 span，金額 `.cl-money`（34 §6 的坑） |
| **零筆**（該區塊無資料） | 摘要顯示「無」（44 §19.1 實測 `貨運業者帳號 / 無`），**不要留空** |
| **極多 item**（44 §18.7 的 12 個通知分組） | 提供「全部展開／全部收合」的 plain 按鈕在容器右上 |
| **慢網路** | 摘要值需請求時，先渲染 trigger ＋ 摘要 skeleton；**不要延遲整個 accordion** |
| **巢狀 accordion**（44 §19.2 zone → carrier → services） | 最多兩層。第二層縮排 `--sp-600`，trigger 高降到 `--ctl-32`，字級降到 `--t-xs` |

### 15.7 實作備註

```html
<div class="cl-acc">
  <div class="cl-acc__item">
    <h3>
      <button type="button" class="cl-acc__trigger" aria-expanded="false" aria-controls="acc-profiles">
        <span class="cl-acc__title">運送設定檔</span>
        <span class="cl-acc__summary">1 個運送設定檔</span>
        <svg class="cl-acc__caret" aria-hidden="true">…</svg>
      </button>
    </h3>
    <div class="cl-acc__panel" id="acc-profiles" hidden>…</div>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 摘要行留空 → 失去這個元件的全部價值。
- ❌ 強制互斥（開一個關一個）→ 44 實測沒有這個限制，且會讓比較兩區的內容變得不可能。
- ❌ 展開後把摘要藏起來（那是 CEC 的行為，不是 accordion 的）。
- ❌ trigger 不包在標題標籤內 → 螢幕閱讀器的標題清單裡看不到這些區塊。
- ❌ 用 `<details>/<summary>` 卻又要自訂動效 → 兩者相容性坑很多，除非完全不做動效才用。

---

## §16 Modal `cl-modal`（含驗證失敗 shake）

**來源**：44 §18.2（**加購上限 modal 骨架實測**：右上 toggle ／ 上限 numeric stepper `50` ／ 灰字系統建議值「您商店的建議上限為 50」／ 底部 `取消` ＋ **disabled `完成`（未變更即 disabled）**）、44 行動項 27（列為 modal 標準樣式）、47 §5 關鍵幀（**Modal 抖動 shake 用於驗證失敗**、Modal footer 進場）、47 #88、23 §3、34 §規則 6（≤767 轉貼底 sheet）。

### 16.1 解剖

```
cl-overlay              position:fixed; inset:0; background: var(--scrim); z-index: var(--z-overlay)
└─ cl-modal[role=dialog][aria-modal=true]   z-index: var(--z-modal)
    ├─ cl-modal__head       padding: var(--sp-300) var(--sp-400); border-block-end: --bw-100 --border
    │   ├─ h2.cl-modal__title    --t-md（14/20/500）
    │   └─ button.cl-modal__close  --ctl-28 icon，aria-label「關閉」
    ├─ cl-modal__body       padding: var(--sp-400); overflow-y:auto; max-height: 60vh
    └─ cl-modal__foot       padding: var(--sp-300) var(--sp-400); border-block-start; 
                            display:flex; justify-content:flex-end; gap: var(--sp-200)
```

| 尺寸 | 值 | 用途 |
|---|---|---|
| `--w-modal-sm` | 400 | 確認／單一輸入 |
| `--w-modal` | 520 | **預設** |
| `--w-modal-lg` | 720 | 表格／多欄表單 |
| 圓角 | `--r-400` | |
| 陰影 | `--sh-modal` | |
| 遮罩 | `--scrim` | **不加 backdrop-filter**（低階裝置掉幀） |
| 垂直位置 | `padding-block-start: 12vh` 的 flex 容器頂對齊（**不是垂直置中**——內容變高時置中會讓 modal 上下跳） | |

〔待覆核〕47 §7 第 6 項「Modal 在桌機的最大寬度階」尚未量測，上表三階為沿用 23 §3 的 520 加推導。

### 16.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上 |
| **hover** | N/A（容器本身）；內部元件各自處理 |
| **active** | N/A |
| **focus-visible** | 開啟時焦點移到 `cl-modal__title`（`tabindex="-1"`）或第一個可聚焦元素；**focus trap 生效** |
| **disabled** | N/A |
| **loading**（提交中） | footer 主鈕進 loading；**遮罩不變、modal 不關**；body 內控件 `inert`；`cl-modal__close` 也 disabled（避免半途關閉） |
| **error（驗證失敗）** | ① modal **整體含 footer** 播 `cl-shake`；② 第一個錯誤欄位 `focus()`；③ body 頂部插入 critical inline banner（§21）列出所有錯誤；④ **modal 不關閉**；⑤ `aria-live="assertive"` 播報錯誤數 |
| **selected** | N/A |
| **read-only** | 純檢視 modal：footer 只有「關閉」一顆 secondary |
| **dirty** | footer 主鈕由 disabled 轉 enabled（**44 §18.2 實測：未變更即 disabled**）；此時 Esc／點外 → 先出「捨棄變更？」二次確認 |

**footer 按鈕規則**：`取消`(secondary) 在左、主動作在右。破壞性確認的主鈕用 `--destructive`（**這是實心紅唯一允許的地方**）＋ 說明文字必須寫明「無法復原」。

### 16.3 動效

| 元素 | 規則 | 為什麼 |
|---|---|---|
| 遮罩進出 | `opacity var(--dur-base) var(--ease-in-out)` | M1 的時序（淡入淡出實測 0.15s ease） |
| modal 進場 | **M5**（`opacity + scale` from `.98`，`--dur-slow`，decelerate） | 47 M5 明確是 opacity+scale |
| modal 退場 | 同 M5 反向，但時長降到 `--dur-base` | 退場要比進場快，這是通則 |
| footer 進場 | **與 modal 同步**，不做獨立的 footer 動畫 | 47 §5 提到實站有獨立的 footer 進場動畫，但兩段動畫同時跑容易打架；同步進場視覺上等效 |
| **shake（驗證失敗）** | `@keyframes cl-shake`：`translateX` `0 → -A → +A → -A*.6 → +A*.6 → 0`，`A = var(--shake-amp)`，`--dur-shake`，`--ease-standard` | 47 #88 |

```css
@keyframes cl-shake{
  0%,100%{ translate: 0 }
  20%{ translate: calc(var(--shake-amp) * -1) }
  40%{ translate: var(--shake-amp) }
  60%{ translate: calc(var(--shake-amp) * -0.6) }
  80%{ translate: calc(var(--shake-amp) * 0.6) }
}
.cl-modal.is-invalid{ animation: cl-shake var(--dur-shake) var(--ease-standard); }
```
**必須在 `animationend` 移除 `.is-invalid`**，否則第二次驗證失敗不會重播。用 `el.classList.remove(); void el.offsetWidth; el.classList.add()` 強制重排也可以。
**reduced motion 下停用 shake**，改為 critical banner ＋ `aria-live="assertive"`（§A.3）。

### 16.4 鍵盤與焦點

- `role="dialog" aria-modal="true" aria-labelledby={title-id} aria-describedby={body 首段 id}`。
- **focus trap**：Tab 在 modal 內循環；背景 `inert`（或 `aria-hidden="true"` ＋ `pointer-events:none`）。
- `Esc` 關閉——但 dirty 時先出二次確認。**Esc 一次只關一層**（23 §3 的分層順序：doc-pop → palette → modal → settings）。
- 點遮罩關閉——dirty 時同樣要二次確認。**破壞性確認 modal 不可點外關閉**（避免誤觸）。
- 關閉後焦點**必須回到觸發元**。
- `Enter` 在單行輸入內＝觸發 footer 主鈕（若主鈕不是 disabled）。

### 16.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 依內容選 sm/預設/lg |
| 1024–1279 | 同上；`max-width: calc(100vw - var(--sp-800) * 2)` |
| 768–1023 | `--w-modal-lg` 降級為 `--w-modal` |
| ≤767 | **轉貼底 sheet**（34 §規則 6）：`inset-inline: 0; bottom: 0`；`border-radius: var(--r-400) var(--r-400) 0 0`；`max-height: 92dvh`；body 內捲；**footer sticky 且按鈕全寬**；進場改 M6（`transform: translateY(100%)→0`） |
| ≤429 | 同上；footer 按鈕上下堆疊（主鈕在上） |

**命令面板是唯一的例外**：≤767 改**貼頂** sheet（避開手機鍵盤，34 §已定）。

### 16.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 內容** | body `overflow-y: auto` ＋ `max-height: 60vh`（≤767 用 `92dvh` 扣掉 head/foot）；捲動時 head 與 foot 固定 |
| **金額在確認文案內** | 「將退款 **NT$1,480** 給顧客，此操作無法復原」——金額 span 用 `.cl-money` ＋ `font-weight: 500` 強調 |
| **零筆選項的 modal** | 不開 modal，直接出 toast 說明（「沒有可匯出的資料」）。**空 modal 是最糟的體驗** |
| **極長清單**（選擇地點/商品） | body 內用虛擬捲動；**清單本身可搜尋**；不要讓 modal 高度隨清單無限長 |
| **慢網路** | 開啟需請求資料的 modal → 立刻開啟 ＋ body skeleton（**不要等資料到才開**，使用者會以為沒點到） |
| **巢狀 modal** | **禁止**。需要第二層時改用：① modal 內的 step 切換；② 關掉第一層再開第二層並記住返回路徑 |
| **modal 內的 select/popover** | `--z-popover(85) > --z-modal(81)` 確保能蓋上去；popover 要 `position: fixed` 或用 popover API，否則被 `overflow:auto` 的 body 裁掉 |
| **背景捲動穿透** | 開啟時 `document.body{overflow:hidden}` ＋ 補 `padding-inline-end: {scrollbarWidth}` 防版面橫移；iOS 額外需要 `position:fixed` 技巧 |

### 16.7 實作備註

```html
<div class="cl-overlay" data-cl-overlay>
  <div class="cl-modal" role="dialog" aria-modal="true" aria-labelledby="m-title">
    <div class="cl-modal__head">
      <h2 class="cl-modal__title" id="m-title" tabindex="-1">加入購物車數量上限</h2>
      <input type="checkbox" role="switch" class="cl-toggle" aria-label="啟用數量上限" checked>
      <button type="button" class="cl-modal__close cl-btn cl-btn--icon" aria-label="關閉">✕</button>
    </div>
    <div class="cl-modal__body">
      <div class="cl-field">
        <label class="cl-field__label" for="m-limit">上限</label>
        <input id="m-limit" class="cl-input" inputmode="numeric" value="50"
               aria-describedby="m-limit-hint">
        <p class="cl-field__hint" id="m-limit-hint">您商店的建議上限為 50</p>
      </div>
    </div>
    <div class="cl-modal__foot">
      <button type="button" class="cl-btn cl-btn--secondary" data-cl-close>取消</button>
      <button type="button" class="cl-btn cl-btn--primary" disabled>完成</button>
    </div>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 沒有 focus trap → Tab 跑到背景，使用者完全迷失。
- ❌ 關閉後焦點沒回到觸發元 → 焦點回到 `<body>`，鍵盤使用者要從頭 Tab。
- ❌ 垂直置中 → 內容變高時 modal 上下跳。
- ❌ dirty 時 Esc 直接關 → 資料無聲丟失。
- ❌ 巢狀 modal。
- ❌ shake 後忘記移除 class。
- ❌ 主鈕預設 enabled → 44 §18.2 實測「未變更即 disabled」。
- ❌ 破壞性 modal 可點外關閉。

---

## §17 Popover / 選單 `cl-pop`

**來源**：44 §19.8（**`類別` popover ＝多選 checkbox 清單＋底部 `清除`，可捲動，13 項**）、44 §2.2（**`更多動作` 是可搜尋的操作選單**：頂部 `🔍 搜尋操作` ＋ 分組列出）、44 行動項 5（操作數 >8 時採可搜尋模式）、44 §21.4（`⊕ 新增區塊` popover **空態**：一句說明＋連結）、44 §22.4（二層抽屜：類別 → 指標多選，含返回列與固定 footer）、47 §5 M5（**popover 進場 `opacity + scale` 200ms decelerate**）、23 §3。

### 17.1 解剖

```
cl-pop[role=menu|listbox|dialog]     --surface, --r-300, --sh-pop, --bw-100 --border
├─ cl-pop__search        可選；操作數 >8 時必備（44 行動項 5）
├─ cl-pop__scroll        max-height: min(320px, 60vh); overflow-y:auto
│   ├─ cl-pop__group     分組
│   │   └─ cl-pop__grouptitle   --t-2xs, 大寫, letter-spacing .08em, --text-3
│   ├─ cl-pop__item      高 --ctl-32；padding: 0 var(--sp-300); gap: var(--sp-200)
│   │   ├─ cl-pop__check   14×14 勾號槽位（**恆佔位**，避免選中時文字位移）
│   │   ├─ cl-pop__icon    16×16（可選）
│   │   ├─ cl-pop__label   --t-sm
│   │   └─ cl-pop__meta    --t-xs, --text-3, margin-inline-start:auto（快捷鍵/計數）
│   └─ cl-pop__sep       1px --border-2；margin-block: var(--sp-100)
└─ cl-pop__foot          可選固定底列：左 plain「清除」／右 primary sm「套用」
```

| 屬性 | 值 |
|---|---|
| 寬 | `clamp(var(--w-popover-min), max-content, var(--w-popover-max))` |
| 內距 | `var(--sp-100)`（外殼）；item 自帶 `0 var(--sp-300)` |
| 相對觸發元 | 下方 `var(--sp-200)`（23 §3）；對齊觸發元的起始邊 |
| 圓角 | `--r-300` |
| 陰影 | `--sh-pop` |
| z-index | `--z-popover`（85，**高於 modal**） |

### 17.2 完整態表（`cl-pop__item`）

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 透明底；`color: --text` |
| **hover** | `background: --surface-hover` |
| **active** | `background: --surface-active` |
| **focus-visible** | 用 `aria-activedescendant` 的**虛擬焦點**：高亮項套 `background: --surface-hover` ＋ `outline: var(--bw-200) solid var(--focus)` `outline-offset: -2px`。**真焦點留在觸發元或搜尋框** |
| **disabled** | `opacity: var(--disabled-opacity)`；`aria-disabled="true"`；**仍可用方向鍵抵達**（讓使用者知道有這個選項），但 Enter 無作用 |
| **loading** | 整個 `cl-pop__scroll` 換 skeleton 三列；搜尋框保持可用 |
| **error** | 載入失敗 → scroll 區換一行 critical 文字 ＋ plain「重試」 |
| **selected** | `cl-pop__check` 顯示勾號（`--brand`）；`font-weight: 500→600`；`aria-selected`/`aria-checked="true"` |
| **read-only** | N/A |
| **destructive item** | `color: --critical`；hover `background: --critical-bg`；放在最後一組，上方有 `cl-pop__sep` |

**勾號槽位恆佔位**是硬規則——用 `visibility: hidden` 而非 `display: none`，否則選中時整排文字左右位移（23 §3 已定）。

### 17.3 定位規則

| 情況 | 處置 |
|---|---|
| 預設 | `bottom-start`（觸發元下方、起始邊對齊） |
| 下方空間不足 | 翻轉到 `top-start`；`transform-origin` 同步改成 `bottom` |
| 橫向溢出 | 貼齊視口邊，留 `--sp-300` 邊距 |
| 觸發元捲出視口 | **自動關閉**（不要讓 popover 浮在無主的位置） |
| 定位實作 | 優先用原生 **Popover API ＋ CSS Anchor Positioning**；不支援時 fallback 到 JS 計算（`getBoundingClientRect` ＋ `position: fixed`） |
| **不要** | 用 `position: absolute` 掛在有 `overflow: hidden/auto` 的祖先內 → 會被裁 |

### 17.4 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 進場 | **M5**：`opacity 0→1` ＋ `scale .96→1`，`--dur-slow`，`--ease-decelerate`；`transform-origin` 對齊觸發元那一角 | 47 M5 實測值；**是 `scale` 不是 `transform`** |
| 退場 | 同 M5 反向，時長 `--dur-fast` | 退場更快是通則 |
| item hover | **M1 ＋ M2** | |
| **禁止** | 位移進場（`translateY(4px)`，23 §5 的舊寫法作廢） | 47 M5 只有 `opacity + scale`，沒有位移分量 |

### 17.5 鍵盤與焦點

- 觸發元：`aria-haspopup="menu"｜"listbox"｜"dialog"` ＋ `aria-expanded` ＋ `aria-controls`。
- 開啟：`Enter`／`Space`／`↓`／`Alt+↓`。
- **單選選單（role=menu）**：焦點移入 popover 第一項；`↑↓` 移動真焦點；`Enter` 選取並關閉；`Esc` 關閉並還焦點給觸發元；首字母跳轉。
- **多選清單（role=listbox aria-multiselectable）**：真焦點留在搜尋框；`↑↓` 用 `aria-activedescendant` 移動高亮；`Space` 勾選（**不關閉**）；`Enter` 套用並關閉。
- **點外關閉**：`pointerdown` 在 popover 外 → 關。注意要排除觸發元本身（否則點觸發元變成關了又開）。
- focus trap：**單選選單不 trap**（Tab 直接關閉並移到下一個元素）；**有 footer 的多選 popover 要 trap**（它實質上是個小 dialog，`role="dialog"`）。

### 17.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | popover |
| 768–1023 | popover；`max-height: 50vh` |
| ≤767 | **一律轉貼底 sheet**（§18）。窄螢幕的 popover 幾乎必然溢出或蓋住觸發元 |
| ≤429 | 同上 |

### 17.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 項目** | item 單行 ellipsis ＋ `title`；寬度已由 `--w-popover-max` 夾住 |
| **零筆選項** | 44 §21.4 實測的空態骨架：**一句說明 ＋ 一個連結**（「此區段沒有可用的區塊 / 尋找顧客帳號應用程式」）。padding `var(--sp-400)`，文字 `--t-xs --text-2`，置中。**不放插圖**（popover 太小） |
| **極多項目**（13/18 類） | `cl-pop__scroll` 內捲 ＋ 頂部搜尋 ＋ 分組；捲動時分組標題 sticky |
| **兩層抽屜**（44 §22.4） | 第二層**取代**第一層內容（不是再開一個 popover）：頂部加 `← {上層名}` 返回列（高 `--ctl-32`），底部固定 footer；切換用 M5 的 opacity（**不做左右滑動**，會暈） |
| **慢網路** | 立刻開啟 ＋ skeleton；搜尋框可先輸入（輸入內容在資料到位後套用） |
| **項目含破壞性動作** | 放最後一組，`cl-pop__sep` 隔開，`--critical` 色；**點擊後仍需 modal 二次確認**（popover 內不做確認） |

### 17.8 實作備註

```html
<button type="button" class="cl-btn cl-btn--secondary" aria-haspopup="menu"
        aria-expanded="false" aria-controls="pop-actions" id="trg-actions">
  更多動作 <svg aria-hidden="true">⌄</svg>
</button>

<div class="cl-pop" id="pop-actions" role="menu" aria-labelledby="trg-actions" hidden>
  <div class="cl-pop__search"><!-- 操作數 >8 時才出現 --></div>
  <div class="cl-pop__scroll">
    <div class="cl-pop__group" role="group">
      <button type="button" class="cl-pop__item" role="menuitem">
        <span class="cl-pop__check" aria-hidden="true"></span>
        <span class="cl-pop__label">退款</span>
      </button>
      <button type="button" class="cl-pop__item" role="menuitem">
        <span class="cl-pop__check" aria-hidden="true"></span>
        <span class="cl-pop__label">編輯</span>
      </button>
    </div>
    <hr class="cl-pop__sep">
    <div class="cl-pop__group" role="group">
      <button type="button" class="cl-pop__item cl-pop__item--destructive" role="menuitem">
        <span class="cl-pop__check" aria-hidden="true"></span>
        <span class="cl-pop__label">取消訂單</span>
      </button>
    </div>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 用 `translateY` 做進場 → 47 M5 是 `opacity + scale`，沒有位移。
- ❌ 勾號用 `display:none` 切換 → 文字左右跳。
- ❌ popover 掛在 `overflow:hidden` 的祖先內。
- ❌ 多選 popover 沒有「清除」→ 使用者要逐個取消。
- ❌ `role="menu"` 卻放了 checkbox → menu 語意不支援多選，該用 `role="listbox"` 或 `role="dialog"`。
- ❌ 操作 >8 個卻不給搜尋（44 行動項 5）。
- ❌ 觸發元捲出視口後 popover 還浮著。

---

## §18 Bottom sheet `cl-sheet`

**來源**：44 §21.2（**結帳編輯器的頁面選擇器＝由下彈出的 bottom sheet，頂端有拖曳把手橫條**，分組清單、目前頁反白；footer 連結跳主題編輯器）、44 行動項 59（**在 1024px 桌機寬也用此形態**——這是刻意的形態選擇，不是響應式降級）、47 §0（該量測在 683px 有效視口）、47 §5 M6、34 §規則 6。

### 18.1 解剖

```
cl-sheet-overlay        position:fixed; inset:0; background: var(--scrim); z-index: var(--z-sheet)
└─ cl-sheet[role=dialog]
    ├─ cl-sheet__grip       拖曳把手：36×4，--r-pill，--border-strong；置中；上下 margin var(--sp-200)
    ├─ cl-sheet__head       可選；--t-md 標題 ＋ 右上 ✕
    ├─ cl-sheet__scroll     overflow-y:auto; overscroll-behavior: contain
    │   └─ cl-sheet__group  分組標題 --t-2xs ＋ 項目列（高 --ctl-36）
    └─ cl-sheet__foot       可選；固定底列
```

| 屬性 | 值 |
|---|---|
| 定位 | `position:fixed; inset-inline: 0; bottom: 0` |
| 寬 | 桌機：`min(var(--w-modal), 100vw)` 置中；≤767：`100vw` |
| 圓角 | `var(--r-400) var(--r-400) 0 0` |
| 最大高 | `min(92dvh, 640px)` |
| 底部安全區 | `padding-block-end: max(var(--sp-400), env(safe-area-inset-bottom))` |
| 陰影 | `--sh-modal` |

**兩種觸發語境（別混）**：
1. **形態選擇**（44 §21.2）：編輯器的頁面選擇器，**所有斷點都是 sheet**。因為它是「從底部拉出一疊頁面」的空間隱喻。
2. **響應式降級**（34 §規則 6）：modal／popover 在 ≤767 轉 sheet。

### 18.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上 |
| **hover**（項目列） | `background: --surface-hover` |
| **active** | `background: --surface-active`；拖曳把手 `--text-3` |
| **focus-visible** | 焦點移入第一個可聚焦元素；trap 生效 |
| **disabled**（項目） | `opacity: var(--disabled-opacity)`；`aria-disabled` |
| **loading** | scroll 區 skeleton；把手與 head 保持 |
| **error** | scroll 區換 critical 文字 ＋ 重試 |
| **selected**（目前頁） | `background: --selected-bg`；`font-weight: 500→600`；左緣 `box-shadow: inset var(--bw-200) 0 0 var(--brand)`；`aria-current="page"` |
| **read-only** | N/A |
| **dragging** | 跟隨手指 `translateY`（**只准往下**，往上有阻尼 `y * 0.3`）；遮罩 `opacity` 隨拖曳距離線性遞減 |

**拖曳關閉的判定**：放開時 `拖曳距離 > 高度 25%` **或** `速度 > 0.5 px/ms` → 關閉；否則彈回。彈回用 M6。

### 18.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 進場／退場 | **M6**（`transform: translateY(100%) → 0`，`--dur-slower`，`--ease-standard`） | 47 M6 就是抽屜類的 transform 250ms standard |
| 遮罩 | `opacity var(--dur-base) var(--ease-in-out)` | |
| 拖曳中 | **不加 transition**（直接跟手）；放開時才恢復 M6 | 有 transition 會延遲感 |
| reduced motion | 取消 translate，改純 opacity | §A.3 |

### 18.4 鍵盤與焦點

- `role="dialog" aria-modal="true" aria-labelledby`。
- **focus trap**（同 modal）；背景 `inert`。
- `Esc` 關閉；點遮罩關閉；拖曳把手向下滑關閉。
- 把手本身要可鍵盤操作：`<button class="cl-sheet__grip" aria-label="關閉頁面選擇器">`（不要做成純裝飾 div）。
- 項目列用 `<button>` 或 `<a>`；分組用 `role="group" aria-labelledby`。
- 關閉後焦點回到觸發元。

### 18.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 寬 `--w-modal` 置中貼底；最大高 640 |
| 1024–1279 | 同上（**44 §21.2 實測 1024 桌機也用 sheet**） |
| 768–1023 | 同上 |
| ≤767 | 全寬；`max-height: 92dvh`；項目列高升到 `--ctl-44` |
| ≤429 | 同上；分組標題間距壓縮到 `--sp-200` |

### 18.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 項目名** | 單行 ellipsis ＋ `title` |
| **零筆項目** | sheet 內卡內空態（§24.2）＋ 建立入口 |
| **極多項目** | `cl-sheet__scroll` 內捲；`overscroll-behavior: contain` **必須**（否則捲到底會帶著頁面一起捲） |
| **內容比 sheet 短** | sheet 高度 `fit-content`（不要撐到 92dvh 留一大片白） |
| **鍵盤彈出（行動裝置）** | sheet 用 `dvh` 而非 `vh`；監聽 `visualViewport.resize` 調整 `bottom` |
| **慢網路** | 立刻開啟 ＋ skeleton |
| **拖曳與內捲衝突** | scroll 區 `scrollTop > 0` 時，向下拖曳應該捲動內容而非拖 sheet。判定：`scrollTop === 0` 才進入拖曳模式 |

### 18.7 實作備註

```html
<div class="cl-sheet-overlay" data-cl-overlay>
  <div class="cl-sheet" role="dialog" aria-modal="true" aria-labelledby="sh-title">
    <button type="button" class="cl-sheet__grip" aria-label="關閉頁面選擇器"></button>
    <h2 class="cl-sheet__head" id="sh-title">選擇頁面</h2>
    <div class="cl-sheet__scroll">
      <div class="cl-sheet__group" role="group" aria-labelledby="g-checkout">
        <p class="cl-sheet__grouptitle" id="g-checkout">結帳</p>
        <a class="cl-sheet__item is-selected" aria-current="page" href="?page=checkout">結帳</a>
      </div>
      <div class="cl-sheet__group" role="group" aria-labelledby="g-account">
        <p class="cl-sheet__grouptitle" id="g-account">顧客帳號</p>
        <a class="cl-sheet__item" href="?page=login">登入</a>
        <a class="cl-sheet__item" href="?page=orders">訂單</a>
      </div>
    </div>
    <div class="cl-sheet__foot">
      <a class="cl-btn cl-btn--plain" href="/themes/editor">網路商店佈景主題</a>
    </div>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 把手做成裝飾 div → 鍵盤與輔具無法關閉。
- ❌ 忘記 `overscroll-behavior: contain` → 捲到底把整頁一起捲走。
- ❌ 用 `vh` 而非 `dvh` → iOS Safari 網址列收合時 sheet 被裁。
- ❌ 拖曳時保留 transition → 跟手感全失。
- ❌ 桌機把 sheet 換成 modal → 44 §21.2 實測 1024 也是 sheet，這是形態選擇不是降級。
- ❌ 沒處理「拖曳 vs 內捲」的優先權。

---

## §19 Drawer `cl-drawer`

**來源**：44 §0（**1024 寬度側欄即收合為漢堡抽屜**）、44 §9（寬版常駐側欄）、47 §0（桌機側欄寬 `--w-sidebar` 240）、47 §5 **M6**（抽屜 `transform` 250ms standard）、47 §5 **M7**（側欄 `max-width` 300ms ease-in-out）、34 §3（`translateX(-100%)→0`；`visibility` 延遲切換讓關閉時退出 tab 序；跨過 1024 自動關）。

### 19.1 解剖

```
cl-drawer-scrim        position:fixed; inset: var(--h-topbar) 0 0 0; z-index: var(--z-scrim)
cl-drawer[role=dialog] position:fixed; z-index: var(--z-drawer)
├─ cl-drawer__head     高 --ctl-36；標題 --t-md ＋ 右上 ✕
├─ cl-drawer__body     overflow-y:auto; overscroll-behavior: contain
└─ cl-drawer__foot     可選；sticky bottom
```

| 變體 | 位置 | 寬 | 用途 |
|---|---|---|---|
| `--nav`（導航抽屜） | 左側，`inset-block-start: var(--h-topbar)` | `min(var(--w-sidebar) + var(--sp-800), 86vw)` | ≤1023 的主導航 |
| `--detail`（詳情抽屜） | 右側，全高 | `--w-drawer`(380)；≤767 `100vw` | 側邊查看/編輯（時間軸明細、篩選面板） |
| `--cart`（前台購物袋） | 右側 | `min(420px, 100vw)` | storefront |

**常駐側欄 ≠ drawer**：≥1024 是常駐側欄（`--w-sidebar`），收合用 **M7**（`max-width`）；≤1023 才變 drawer，進出用 **M6**（`transform`）。**兩者是不同元件、不同動效規則**，別合成一個。

### 19.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（關閉）** | `transform: translateX(-100%)`（左）／`translateX(100%)`（右）；`visibility: hidden`（**延遲到動畫結束才切**）；scrim `opacity: 0; pointer-events: none` |
| **hover**（內部項目） | `background: --surface-hover` |
| **active** | `background: --surface-active` |
| **focus-visible** | 開啟時焦點移入第一個可聚焦元素；trap 生效 |
| **disabled**（項目） | `opacity: var(--disabled-opacity)` |
| **loading** | body skeleton；head 保持 |
| **error** | body 換 critical inline banner ＋ 重試 |
| **selected**（當前導航項） | `background: --surface`；`box-shadow: var(--sh)`；`font-weight: 500→600`；`aria-current="page"` |
| **read-only** | N/A |
| **open** | `transform: none`；`visibility: visible`；scrim `opacity: 1; pointer-events: auto` |

**`visibility` 延遲切換是硬要求**（34 §3）：關閉時若立刻 `visibility:hidden`，退場動畫會消失；若永遠 `visible`，抽屜內容會留在 Tab 序。做法：`transition: transform var(--dur-slower) var(--ease-standard), visibility 0s linear var(--dur-slower);` 開啟時 `visibility 0s linear 0s`。

### 19.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| drawer 進出 | **M6**（`transform var(--dur-slower) var(--ease-standard)`） | 47 M6 |
| scrim | `opacity var(--dur-base) var(--ease-in-out)` | |
| **常駐側欄收合** | **M7**（`max-width var(--dur-slowest) var(--ease-in-out)`） | 47 M7 明確：**不是 `width`**，避免內容重排 |
| 導航項 hover | **M1 ＋ M2** | |

**M7 的實作細節**：側欄容器 `max-width: var(--w-sidebar)` → 收合時 `max-width: 0`；內部內容 `width: var(--w-sidebar); flex: none`（**固定寬**），這樣收合時內容是被裁掉而不是被壓扁。`overflow: hidden` 在容器上。

### 19.4 鍵盤與焦點

- `role="dialog" aria-modal="true" aria-label="主導航"`（導航抽屜）。
- **focus trap**；背景 `inert`。
- `Esc` 關閉；點 scrim 關閉。
- 關閉後焦點回到漢堡按鈕。
- 漢堡按鈕 `aria-expanded` ＋ `aria-controls`。
- **跨過斷點自動關**（34 §3）：`matchMedia('(min-width:1024px)')` 的 change 事件 → 關閉抽屜並移除 `inert`。**同時要把焦點救回來**（若焦點在抽屜內，移到主內容的 skip link）。
- 導航後自動關（`go()` / `openSettings()` 都要呼叫關閉）。

### 19.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 常駐側欄 `--w-sidebar`；可用 M7 收合成 icon-only 條（寬 `--ctl-36 + --sp-200 * 2`） |
| 1024–1279 | 常駐側欄；44 §0 實測 Shopify 在 ~1200 以下就收，我們維持 1024 為界（34 §1 已驗證） |
| ≤1023 | **轉 drawer**；漢堡按鈕出現在頂欄左側 |
| ≤767 | drawer 寬 `min(320px, 86vw)`；項目高 `--ctl-44` |
| ≤429 | drawer 寬 `86vw` |

### 19.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 導航項** | 單行 ellipsis ＋ `title`；計數 badge `flex: none` 永不被擠 |
| **零筆**（無銷售管道） | 該分組整段不渲染（不是渲染空分組） |
| **極多導航項** | body 內捲；**底部固定項（設定）不參與捲動** |
| **慢網路** | 導航是本地資料，立即渲染；badge 計數走非同步，未到位前不顯示（不要顯示 0） |
| **抽屜內開 modal** | `--z-modal(81) > --z-drawer(60)`，可行；但要把 drawer 一起 `inert` |
| **手勢返回衝突** | iOS 邊緣滑動返回會與左側抽屜衝突 → 左抽屜不做手勢開啟，只用漢堡按鈕 |
| **捲動位置保持** | 抽屜關閉再開啟時，body 的 `scrollTop` 保持（不重置到頂） |

### 19.7 實作備註

```html
<button type="button" class="cl-btn cl-btn--icon" id="hamb"
        aria-label="開啟主導航" aria-expanded="false" aria-controls="nav-drawer">☰</button>

<div class="cl-drawer-scrim" data-cl-overlay hidden></div>
<nav class="cl-drawer cl-drawer--nav" id="nav-drawer" role="dialog"
     aria-modal="true" aria-label="主導航" hidden>
  <div class="cl-drawer__body">
    <a class="cl-navitem is-selected" aria-current="page" href="/orders">
      <svg aria-hidden="true">…</svg><span>訂單</span><span class="cl-navitem__count">4</span>
    </a>
  </div>
  <div class="cl-drawer__foot"><a class="cl-navitem" href="/settings">設定</a></div>
</nav>
```
```css
.cl-drawer{
  transform: translateX(-100%); visibility: hidden;
  transition: transform var(--dur-slower) var(--ease-standard),
              visibility 0s linear var(--dur-slower);
}
.cl-drawer.is-open{
  transform: none; visibility: visible;
  transition: transform var(--dur-slower) var(--ease-standard), visibility 0s linear 0s;
}
```

**常見錯誤做法**：
- ❌ 常駐側欄收合用 `width` → 47 M7 明確要 `max-width`，用 `width` 會讓內容逐幀重排。
- ❌ `visibility` 沒延遲 → 退場動畫看不到，或關閉後內容仍在 Tab 序。
- ❌ 跨斷點沒自動關 → 桌機出現一個浮在畫面上的抽屜。
- ❌ 導航後不關抽屜。
- ❌ 忘記 `overscroll-behavior: contain`。
- ❌ 把常駐側欄與 drawer 做成同一個元件用同一組動效。

---

## §20 Toast `cl-toast`

**來源**：23 §3（底部置中深色膠囊；停留 2.6s；同時只一則；`role="status" aria-live="polite"`）、23 §4.1（回饋三件套：寫入動作→按鈕 loading→成功 toast／失敗紅 banner）、47 §5 M6（transform 類進出）、34 §3（≤767 貼底全寬＋safe-area；bulkbar 出現時用 `:has()` 上移）。

### 20.1 解剖

```
cl-toast[role=status]     position:fixed; z-index: var(--z-toast)
├─ cl-toast__icon    16×16（可選；success/critical 才有）
├─ cl-toast__text    --t-sm
└─ cl-toast__action  plain 按鈕（「復原」／「檢視」），--text-inverse
```

| 屬性 | 值 |
|---|---|
| 定位 | `inset-block-end: var(--sp-600); inset-inline-start: 50%; translate: -50% 0` |
| 高 | `min-height: var(--ctl-36)` |
| 內距 | `var(--sp-300) var(--sp-400)` |
| 圓角 | `--r-300` |
| 底／字 | `--surface-inverse` / `--text-inverse` |
| 陰影 | `--sh-pop` |
| 最大寬 | `min(480px, calc(100vw - var(--sp-800)))` |
| 停留 | `--dur-toast-dwell`（2600ms）；有 action 時 **6000ms** |

### 20.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上 |
| **hover** | **停留計時暫停**（滑鼠移開後重新計時剩餘時間）。視覺不變 |
| **active** | N/A（toast 整體不可點；只有 action 可點） |
| **focus-visible** | 焦點進入 action 時，**計時永久暫停**直到失焦 |
| **disabled** | N/A |
| **loading** | N/A（toast 是結果不是過程；過程用按鈕 loading） |
| **error（critical 變體）** | `background: --critical`；icon 為 `⚠`；停留延長到 **6000ms**；**同時**在頁面內出 inline banner（toast 會消失，錯誤需要留痕，23 §4.1） |
| **success 變體** | icon 為 `✓`（`--success` 色，深底上可讀） |
| **selected** | N/A |
| **read-only** | N/A |
| **stacked**（第二則到達） | **新蓋舊**（23 §3：同時只一則）。舊的立刻退場（`--dur-fast`），新的進場 |

### 20.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 進出 | **M6**（`transform: translateY(120%) → 0`，`--dur-slower`，`--ease-standard`） ＋ `opacity`（`--dur-base`） | 47 M6 |
| 新蓋舊 | 舊的退場 `--dur-fast`，新的延遲 `--dur-fast` 後進場 | 避免兩則重疊 |
| reduced motion | 取消 translate，只淡入淡出 | |

### 20.4 鍵盤與焦點

- `role="status" aria-live="polite" aria-atomic="true"`——**不搶焦點**。
- critical 變體用 `role="alert" aria-live="assertive"`。
- **toast 不進 Tab 序**，除非有 action；有 action 時 action 是 `<button>` 可 Tab 抵達（但排在頁面最後）。
- 有 action 的 toast 要能用鍵盤抵達：提供 `⌘/Ctrl+Z` 作為「復原」的快捷（同時在 toast 上顯示鍵帽）。
- **絕不**用 toast 承載必須被讀到的資訊（它會消失）。破壞性操作的結果、驗證錯誤、需要動作的失敗 → 用 inline banner。

### 20.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 底部置中膠囊 |
| ≤767 | `inset-inline: var(--sp-300)`；`translate: none`；`inset-block-end: calc(var(--sp-300) + env(safe-area-inset-bottom))`；寬度撐滿 |
| ≤767 ＋ bulkbar 顯示 | `body:has(.cl-bulkbar.is-open) .cl-toast{ inset-block-end: calc(78px + env(safe-area-inset-bottom)) }` |
| ≤767 ＋ save bar 顯示 | 同理上移到 `86px + safe-area` |

### 20.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 訊息** | 最多兩行；超過改用 inline banner。toast 文案硬性 **≤30 字** |
| **金額** | `.cl-money`（「已退款 NT$1,480」） |
| **零筆** | N/A |
| **連續多個操作** | 新蓋舊。若同類操作連發（勾選 10 個），合併成「已更新 10 筆」而不是彈 10 次 |
| **慢網路** | 操作 >8s 未回應 → **不出 toast**，改在按鈕旁出 inline 提示（toast 會被使用者錯過） |
| **背景分頁** | `document.hidden` 時不啟動計時；回到前景才開始（否則使用者切回來已經沒了） |
| **與 bulkbar/savebar 疊放** | ≤767 用 `:has()` 上移（見上表）；桌機三者位置不衝突（toast 置中、bulkbar 在表頭、save bar 在列表列） |

### 20.7 實作備註

```html
<div class="cl-toast cl-toast--success" role="status" aria-live="polite" aria-atomic="true">
  <svg class="cl-toast__icon" aria-hidden="true">✓</svg>
  <span class="cl-toast__text">已儲存 3 項變更</span>
  <button type="button" class="cl-toast__action cl-btn cl-btn--plain cl-btn--sm">復原</button>
</div>
```

**常見錯誤做法**：
- ❌ 用 toast 顯示需要使用者處理的錯誤 → 它會消失，錯誤不會。
- ❌ 同時堆疊多則 toast → 23 §3 明確「同時只一則」。
- ❌ `role="alert"` 用在成功訊息 → 會打斷螢幕閱讀器當前朗讀。
- ❌ hover 不暫停計時 → 使用者正要點「復原」時消失。
- ❌ 沒處理背景分頁的計時。
- ❌ ≤767 沒留 safe-area → iPhone 底部橫條蓋住。


---

## §21 Inline banner `cl-banner`

**來源**：44 §18.2（資訊橫幅「您的顧客帳號網域…目前使用的是 …**變更您的顧客帳號網域**」＋ `✕`）、44 §19.2（**黃色警示橫幅**「若要在此區域開始銷售至 27 個國家/地區，請將這些國家/地區加入市場」，「市場」為連結）、44 §19.6（info 橫幅「您的網路商店正在開發中…**瞭解詳情**」）、44 §18.2（info 橫幅「新的未完成結帳自動化作業現已推出…**檢視自動化作業**」）、23 §4.1/§4.7（錯誤 banner 必須提供動作）。

### 21.1 解剖

```
cl-banner[role]        --r-300; padding: var(--sp-300) var(--sp-400); gap: var(--sp-300)
├─ cl-banner__icon     16×16; flex:none; margin-block-start: var(--sp-050)（與首行文字對齊）
├─ cl-banner__content  flex:1; min-width:0
│   ├─ cl-banner__title   可選；--t-sm weight 500（單行 banner 沒有標題）
│   ├─ cl-banner__text    --t-xs；內含 inline 連結
│   └─ cl-banner__actions 可選；margin-block-start: var(--sp-200)；gap: var(--sp-200)
└─ cl-banner__close    --ctl-24 icon；可選；aria-label「關閉此提示」
```

### 21.2 四種語氣

| 變體 | 底 | 框 | icon 色 | icon | 用途與硬規則 |
|---|---|---|---|---|---|
| `--info` | `--info-bg` | `--bw-100 --info-border` | `--info` | ⓘ | 中性通知、新功能推廣。**可 dismiss** |
| `--success` | `--success-bg` | `--success-border` | `--success` | ✓ | 操作結果的持久確認。**可 dismiss**；一般成功用 toast，只有需要留痕才用 banner |
| `--warning` | `--warning-bg` | `--warning-border` | `--warning` | ⚠ | **需要注意但不阻擋**（44 §19.2 的 zone≠market）。**必須帶動作連結**；可 dismiss |
| `--critical` | `--critical-bg` | `--critical-border` | `--critical` | ⚠ | **阻擋性錯誤**。**必須帶動作**（重試／回上頁，23 §4.7）；**不可 dismiss**（錯誤沒解決不能被關掉） |

**dismiss 的持久化**：關閉後寫 localStorage `dismissed:{bannerKey}:{version}`。`version` 讓我們能在文案更新後重新顯示。**不要**存伺服器（除非是帳號級公告）。

### 21.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上表 |
| **hover** | banner 本身無 hover；內部連結／按鈕各自處理 |
| **active** | N/A |
| **focus-visible** | 內部連結／關閉鈕出環 |
| **disabled** | N/A |
| **loading** | 動作按鈕進 loading（§1.2） |
| **error** | 這就是 `--critical` 變體本身 |
| **selected** | N/A |
| **read-only** | N/A |
| **dismissing** | `opacity 0` ＋ `max-height 0`（**M4**）＋ `margin-block 0`；動畫結束後從 DOM 移除 |

### 21.4 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 出現 | **不做進場動畫**（頁面載入時就在） | banner 是內容不是浮層 |
| 動態插入（如提交失敗後） | `opacity` ＋ **M4** 的 `max-height` 展開，`--dur-fast` | 讓版面推開的過程可被感知 |
| 關閉 | 同上反向 | |
| 內部連結 | **M2** | |

### 21.5 鍵盤與焦點

- `--critical`：`role="alert"`（動態插入時會被立刻朗讀）。
- `--warning`／`--info`／`--success`：`role="status"`；靜態存在的用 `role="region" aria-labelledby`。
- 動態插入的 critical banner 要 `focus()` 到 banner 容器（`tabindex="-1"`），讓鍵盤使用者立刻知道。
- 關閉鈕 `aria-label` 要具體（「關閉 顧客帳號網域 提示」），一頁多個 banner 時才分得清。
- banner 內的連結是真 `<a>`；動作是 `<button>`。**不要**整條 banner 可點。

### 21.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | icon 左、內容中、關閉鈕右 |
| ≤767 | 內距降到 `var(--sp-300)`；`cl-banner__actions` 按鈕全寬堆疊；關閉鈕命中區 `--hit-min` |
| ≤429 | icon 與文字改上下堆疊（icon 在標題行內） |

### 21.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 文字** | 自然換行；**不截斷**（banner 的內容是要被讀完的） |
| **金額在文案內** | 拆 span ＋ `.cl-money` |
| **零筆** | N/A |
| **極多 banner 同時出現** | **同一位置最多 2 個**。超過時依語氣優先序保留（critical > warning > info > success），其餘收進「還有 N 則提示」的展開列 |
| **慢網路** | banner 內的動作按鈕走 §1.2 的 loading |
| **banner 位置** | 頁面級 → 頁標題下方、內容上方；卡片級 → 卡片 head 下方、body 上方；欄位級 → **不要用 banner**，用 `cl-field__error` |

### 21.8 實作備註

```html
<div class="cl-banner cl-banner--warning" role="status">
  <svg class="cl-banner__icon" aria-hidden="true">⚠</svg>
  <div class="cl-banner__content">
    <p class="cl-banner__text">
      若要在此區域開始銷售至 27 個國家/地區，請將這些國家/地區加入<a href="/markets">市場</a>。
    </p>
  </div>
  <button type="button" class="cl-banner__close cl-btn cl-btn--icon"
          aria-label="關閉 運送區域與市場 提示">✕</button>
</div>
```

**常見錯誤做法**：
- ❌ critical banner 可 dismiss。
- ❌ warning banner 沒有動作 → 使用者知道有問題卻不知道怎麼辦。
- ❌ 用 banner 顯示欄位級錯誤 → 使用者要自己找是哪一欄。
- ❌ 靜態 banner 用 `role="alert"` → 每次進頁面都被朗讀打斷。
- ❌ 關閉狀態沒有 `version` → 文案更新後使用者永遠看不到。
- ❌ 整條 banner 可點。

---

## §22 雙層 banner `cl-banner2`

**來源**：44 §19.9（**兩段式警示橫幅（黃）**：上為深黃標題條 `⚠ 商店存取權限受限`，下為白底內文「僅持有密碼的訪客可以存取您的網路商店。」＋ `管理存取權限` 鈕）、44 行動項 53（**新元件變體**，用於**全站級狀態警示**，比單行 inline banner 重）、47 §2（單邊圓角規則）。

### 22.1 解剖

```
cl-banner2                --r-300; overflow: clip; --bw-100 solid {語氣}-border
├─ cl-banner2__head       深色語氣條
│   ├─ icon 16×16
│   └─ cl-banner2__title  --t-sm weight 500
└─ cl-banner2__body       白底內文區
    ├─ cl-banner2__text   --t-xs
    └─ cl-banner2__actions
```

| 層 | 底 | 字 | 內距 | 圓角 |
|---|---|---|---|---|
| head | 語氣色的**深階**（`--warning-bg` 再深一階：`color-mix(in srgb, var(--warning) 22%, #fff)`） | `--warning`（保持 ≥4.5:1） | `var(--sp-200) var(--sp-400)` | `var(--r-300) var(--r-300) 0 0` |
| body | `--surface` | `--text` | `var(--sp-300) var(--sp-400)` | `0 0 var(--r-300) var(--r-300)` |

**單邊圓角的來源**：47 §2 量到的成對用法 `12px 12px 0 0` / `0 0 12px 12px`。這裡與 §13.2 的堆疊卡片是**同一條規則的兩個應用**。

### 22.2 何時用雙層而非單層（判定表）

| 條件 | 用哪個 |
|---|---|
| 影響**整個商店**的狀態（未開店、密碼保護、方案到期、付款失敗） | **雙層** |
| 影響當前頁面或某張卡片 | 單層（§21） |
| 需要「狀態名稱 ＋ 解釋 ＋ 動作」三段資訊 | **雙層** |
| 只有一句話 | 單層 |
| 出現在頁面最頂端、跨所有頁面 | **雙層** |

**全站級雙層 banner 同時只能有一個**。多個狀態同時成立時，head 顯示最高優先者，body 列出全部（`<ul>`）。

### 22.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上 |
| **hover** | 本體無；內部按鈕／連結各自處理 |
| **active** | N/A |
| **focus-visible** | 內部元素出環 |
| **disabled** | N/A |
| **loading** | 動作鈕 loading |
| **error** | 語氣改 `--critical`（head 用 `color-mix(… var(--critical) 22% …)`） |
| **selected** | N/A |
| **read-only** | N/A |
| **collapsed**（可選） | head 保留、body 收合（**M4**）；head 右端加 `⌄`。用於使用者已知情但問題未解決時（**不提供完全關閉**，只提供收合） |

### 22.4 動效

| 屬性 | 規則 |
|---|---|
| body 收合／展開 | **M4** |
| 首次出現 | 不做動畫（載入時就在） |
| 動態出現（如方案剛過期） | `opacity` ＋ M4 展開 |
| 內部連結 | **M2** |

### 22.5 鍵盤與焦點

- 外層 `role="region" aria-labelledby={head-title-id}`。
- head 若可收合 → head 整條是 `<button aria-expanded aria-controls>`。
- critical 語氣且是**新出現**的 → 額外用一個 `role="alert"` 的 sr-only 節點播報一次（不要讓整個 banner 都是 alert，否則每次重整都朗讀）。
- 動作鈕在 Tab 序的位置＝頁面最前（它在 DOM 最上方），這是刻意的。

### 22.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | head 單行；body 的文字與按鈕同一行（按鈕右對齊） |
| ≤767 | body 的按鈕換行到文字下方、全寬；head 標題允許兩行 |
| ≤429 | 內距降到 `var(--sp-300)` |

### 22.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標題** | head 允許兩行；icon 保持頂端對齊 |
| **多個狀態** | body 用 `<ul>` 列出，每項一句 ＋ 各自的動作連結 |
| **零筆** | 不渲染 |
| **慢網路** | 狀態未知前**不渲染**（不要先渲染 skeleton banner，會嚇到使用者） |
| **與頁面 sticky 元素疊放** | 雙層 banner **不 sticky**，跟著頁面捲走；sticky 的是 listbar |
| **對比度** | head 的深色底 ＋ 語氣色文字必須實測 ≥4.5:1（23 §4.8）。`color-mix` 的結果要在 tokens.css 落成靜態值並實測，不要相信估算 |

### 22.8 實作備註

```html
<section class="cl-banner2 cl-banner2--warning" role="region" aria-labelledby="b2-t">
  <div class="cl-banner2__head">
    <svg aria-hidden="true">⚠</svg>
    <h2 class="cl-banner2__title" id="b2-t">商店存取權限受限</h2>
  </div>
  <div class="cl-banner2__body">
    <p class="cl-banner2__text">僅持有密碼的訪客可以存取您的網路商店。</p>
    <div class="cl-banner2__actions">
      <button type="button" class="cl-btn cl-btn--secondary cl-btn--sm">管理存取權限</button>
    </div>
  </div>
</section>
```

**常見錯誤做法**：
- ❌ 拿雙層 banner 當一般提示用 → 它的視覺重量是為「全站級」保留的。
- ❌ head 與 body 用同一個底色 → 就變成加高的單層 banner，失去雙層的資訊層次。
- ❌ 提供完全關閉 → 全站級問題不該能被關掉，只能收合。
- ❌ 忘記 `overflow: clip` → 子層的方角會從父層的圓角溢出。
- ❌ head 深底上的文字對比不足。

---

## §23 AI 建議 inline 列 `cl-airow`

**來源**：44 §22.6（**AI 建議列**：淡紫底、紫色 `✦` 圖標、紫色連結文字 `建立International市場` ＋ `✕` 關閉，**混在資料列裡**）、44 §7（市場列表的 `✨ 建立 International 市場 ＋`）、44 行動項 75（**第三種提示層級**，有別於 banner）、44 §4（顧客頁的 AI 分群描述器）、44 §22.2（文章標題欄右內側 `✨` AI 產生圖標）。

### 23.1 這是第三種提示層級（先搞清楚定位）

| 層級 | 元件 | 視覺重量 | 語意 |
|---|---|---|---|
| 1 | 雙層 banner（§22） | 最重 | **全站級狀態**，必須處理 |
| 2 | inline banner（§21） | 中 | **頁面／卡片級通知**，需要注意 |
| 3 | **AI 建議 inline 列（本節）** | 最輕 | **可有可無的下一步建議**，混在資料裡，隨時可 dismiss |

**判準**：如果不做這件事**不會有任何壞事發生** → AI 列。如果會 → banner。

### 23.2 解剖

```
button.cl-airow          （整列可點；混在 tbody 之後或列表末尾）
├─ cl-airow__icon        ✦ 16×16，--ai
├─ cl-airow__text        --t-sm，weight 500，color: --ai
├─ cl-airow__add         ＋ 或 › 圖示（可選，暗示「立刻建立」）
└─ button.cl-airow__x    --ctl-24，aria-label「關閉此建議」；margin-inline-start:auto
```

| 屬性 | 值 |
|---|---|
| 高 | `min-height: var(--ctl-32)`（與資料列同高，才「混得進去」） |
| 內距 | `var(--sp-200) var(--sp-300)`（與表格儲存格同） |
| 底 | `--ai-bg` |
| 上緣線 | `--bw-100 solid var(--ai-border)` |
| 字級／色 | `--t-sm` / `--ai` |
| gap | `--sp-200` |

**位置**：表格的**最後一列之後**（`<tfoot>` 或緊接 `</tbody>` 的一個 `<tr>`），不是插在資料中間。理由：插在中間會破壞排序心智模型。

### 23.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | `--ai-bg` 底；`--ai` 字 |
| **hover** | `background: color-mix(in srgb, var(--ai) 12%, var(--surface))`（比 `--ai-bg` 深一階） |
| **active** | 再深一階 |
| **focus-visible** | outline 2px `--focus`，`outline-offset: -2px`（列在容器內，環要內縮） |
| **disabled** | N/A（建議不可用就不該顯示） |
| **loading** | 點擊後：`✦` 換 spinner；文字改「建立中…」；`aria-busy="true"`；`✕` 仍可點（取消） |
| **error** | 建立失敗 → 整列換成 `--critical` 語氣一行文字 ＋ plain「重試」；3s 後自動變回原建議 |
| **selected** | N/A |
| **read-only** | N/A |
| **dismissed** | `opacity 0` ＋ **M4** 的 `max-height 0`；動畫結束移除 DOM ＋ 寫入 `dismissed:ai:{suggestionKey}` |

**dismiss 的語意**：關閉**這一次**的建議，不是關閉整個 AI 建議功能。若使用者連續關閉同類建議 3 次 → 停止顯示該類建議 30 天（存使用者偏好）。這條沒有實測依據，是我們的產品決策〔推導〕。

### 23.4 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| hover 底 | **M1** | |
| 文字色 | **M2** | |
| 出現 | `opacity` ＋ **M4**（`max-height`），`--dur-base` | 它是動態插入的內容列 |
| dismiss | 同上反向，`--dur-fast` | |
| **禁止** | 閃爍、脈動、漸層流動 | AI 提示已經用色彩區分了，再加動畫就是干擾 |

### 23.5 鍵盤與焦點

- 整列是 `<button>`（或 `<tr>` 內含一個撐滿的 `<button>`）。
- Tab 序：排在**最後一筆資料列之後**。
- `Enter`／`Space` 執行建議；`Delete`／`Backspace` 在列聚焦時＝dismiss（額外便利，非必須）。
- `✕` 是獨立 button，`aria-label` 具體（「關閉 建立 International 市場 的建議」）。
- 整列 `aria-describedby` 指向一個 sr-only 的「這是 AI 建議」說明——**使用者有權知道這是機器產生的**。
- 執行後用 `role="status"` 播報結果。

### 23.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 單行 |
| ≤767 | 表格卡片化後，AI 列變成**卡片樣式**（`--r-300` ＋ `--ai-bg`），放在卡片列表最後；`✕` 命中區 `--hit-min` |
| ≤429 | 文字允許兩行 |

### 23.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 建議文字** | 單行 ellipsis ＋ `title`；建議文案硬性 **≤20 字** |
| **金額在建議內** | `.cl-money` |
| **零筆資料的列表** | **不顯示 AI 建議列**——空表格加一條 AI 建議會很怪。改在空態的 CTA 旁放次要建議 |
| **極多建議** | **同一列表最多 1 條**。多個候選時取信心分數最高者 |
| **慢網路** | AI 建議是**非阻塞**的：資料列先渲染，建議稍後插入（用 M4 展開，讓使用者看到它「長出來」） |
| **建議與當前篩選矛盾** | 篩選狀態下**不顯示**建議（建議是針對全集的） |
| **法遵** | AI 產生的內容必須可辨識來源。`✦` icon ＋ 紫色是我們的 AI 語彙，全站一致（欄位內的 AI 入口用同一個 icon，44 §22.2） |

### 23.8 實作備註

```html
<tr class="cl-table__airow-wrap">
  <td colspan="4" class="cl-table__airow-cell">
    <button type="button" class="cl-airow" aria-describedby="ai-note-1"
            data-cl-suggestion="market.create.international">
      <svg class="cl-airow__icon" aria-hidden="true">✦</svg>
      <span class="cl-airow__text">建立 International 市場</span>
      <svg class="cl-airow__add" aria-hidden="true">＋</svg>
    </button>
    <span class="sr-only" id="ai-note-1">這是系統依您的資料產生的建議。</span>
    <button type="button" class="cl-airow__x cl-btn cl-btn--icon"
            aria-label="關閉 建立 International 市場 的建議">✕</button>
  </td>
</tr>
```

**常見錯誤做法**：
- ❌ 用 AI 列取代 banner 傳達重要訊息 → 它太輕，會被忽略（這正是它的設計目的）。
- ❌ 插在資料列中間。
- ❌ 一次顯示多條建議 → 變成廣告欄。
- ❌ `✕` 不是獨立 button → 鍵盤只能執行不能關閉。
- ❌ 沒有 sr-only 的「這是 AI 建議」說明。
- ❌ 空表格還顯示建議。

---

## §24 空態 `cl-empty`（全頁 vs 卡內兩種）

**來源**：44 §22.1（**全頁空態標準骨架**：圓形淡灰底插圖 → 標題 → 一句說明 → 1~2 顆鈕 → **卡外**「深入瞭解」連結）、44 行動項 64、44 §22.3（**卡內空態只有一行灰字** `此日期範圍無資料`，無插圖）、44 行動項 65、44 §6（折扣空態：插圖＋標題＋說明＋主鈕；`匯出` disabled 不隱藏）、44 §22.5（B2B 空態把「四支柱」寫在說明文案裡）、44 §19.6（爬蟲存取空態：插圖＋標題＋說明＋primary）、44 §18.2（**空車時付款區塊整段 disabled 提示**，不是空白）。

### 24.1 解剖（一）：全頁空態 `cl-empty--page`

```
cl-empty--page          （放在卡片內，佔滿卡片；text-align:center）
├─ cl-empty__art        插圖；max-width: var(--art-lg); aspect-ratio 固定（防 CLS）
├─ cl-empty__title      --t-3xl（24/32/450）
├─ cl-empty__text       --t-sm; --text-2; max-width: 48ch; margin-inline: auto
├─ cl-empty__actions    gap: var(--sp-200); justify-content:center；1~2 顆
└─ (卡外) cl-empty__learn   「深入瞭解 {主題}」plain 連結，置中，卡片下方 var(--sp-400)
```

| 屬性 | 值 |
|---|---|
| 內距 | `var(--sp-1200) var(--sp-600)` |
| 元素間距 | art→title `--sp-600`；title→text `--sp-200`；text→actions `--sp-400` |
| 按鈕順序 | 次要在左、主要在右（44 §22.1 實測 `匯入…`(sec) ／ `建立…`(pri)） |

**文案三段式**（44 實測全部符合）：
1. **標題**＝動詞開頭的目標（「管理您的網址重新導向」「撰寫網誌文章」），**不是**「沒有資料」。
2. **說明**＝一句「為什麼你會想要這個」（「將您的顧客重新導向至其他頁面，以防止舊連結失效。」）。
3. **CTA**＝最直接的下一步。

### 24.2 解剖（二）：卡內空態 `cl-empty--card`

```
cl-empty--card          單行灰字，置中
└─ cl-empty__line       --t-xs; --text-2
```

| 屬性 | 值 |
|---|---|
| 內距 | `var(--sp-600) var(--sp-400)` |
| 插圖 | **無** |
| CTA | **無**（若真的需要，用一個 plain 連結接在文字後） |
| 文案 | 單句陳述（「此日期範圍無資料」——44 §22.3 逐字） |

**判定表（別用錯）**：

| 情境 | 用哪個 |
|---|---|
| 資源**從未建立過**（第一次進來） | 全頁空態（教學＋CTA） |
| 篩選／日期範圍**碰巧沒資料** | 卡內空態（一行灰字） |
| 搜尋**無結果** | 卡內空態 ＋ 「清除搜尋」plain 鈕 |
| 儀表板小卡沒有資料 | 卡內空態 |
| 整頁只有一張卡且該卡沒資料 | 全頁空態 |
| 相依條件未滿足（44 §18.2 空車時的付款區） | **不是空態**——整區 disabled ＋ 提示文字（「新增商品以計算總計並檢視付款選項」） |

### 24.3 完整態表

| 態 | 全頁空態 | 卡內空態 |
|---|---|---|
| **default** | 見上 | 見上 |
| **hover** | 僅按鈕／連結 | 僅連結 |
| **active** | 僅按鈕 | 僅連結 |
| **focus-visible** | 按鈕出環 | 連結出環 |
| **disabled** | 主 CTA 若因權限不可用 → disabled ＋ tooltip 說明所需權限 | N/A |
| **loading** | **不顯示空態**——先顯示 skeleton。**空態與載入中絕不可混淆** | 同 |
| **error** | 不是空態 → 換 critical inline banner ＋ 重試 | 同 |
| **selected** | N/A | N/A |
| **read-only** | 隱藏 CTA，只留標題與說明 | 無變化 |

### 24.4 動效

- **不做進場動畫。** 空態出現通常伴隨資料載入完成，加動畫會讓「載入中→空」的轉換顯得像出錯。
- 插圖**不做動畫**（不要 Lottie、不要 loop）。
- 按鈕沿用 §1 的 M1/M2。

### 24.5 鍵盤與焦點

- 全頁空態的容器 `role="status"`（讓輔具在資料載完後知道是空的）。
- 標題用真 `<h2>`／`<h3>`。
- 插圖 `role="img" aria-label` 或 `aria-hidden="true"`（若標題已充分說明，用後者）。
- CTA 是 Tab 序中的第一個可聚焦元素——**但不要自動 focus**（會打斷螢幕閱讀器讀標題）。
- 「清除搜尋」按鈕點擊後，焦點移回搜尋框。

### 24.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 基準 |
| ≤767 | 內距降到 `var(--sp-600) var(--sp-300)`；插圖 `max-width: var(--art-md)`；按鈕全寬堆疊（主鈕在上） |
| ≤429 | 插圖 `max-width: var(--art-sm)` 或隱藏；標題降到 `--t-xl` |

### 24.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 說明**（44 §22.5 的 B2B 四支柱文案） | `max-width: 48ch` ＋ 自然換行；**不截斷** |
| **零筆但有篩選** | **必附「清除篩選」**（23 §3 硬性要求）；文案要提到篩選條件 |
| **權限不足** | 標題改「您沒有檢視 {資源} 的權限」；CTA 換成「聯絡管理員」；**不要顯示建立按鈕** |
| **慢網路** | skeleton → 資料 → （若為空）空態。**中間不可閃過空態** |
| **插圖資產** | 一律用**自繪 SVG**（法律紅線 9：不抄第三方圖片）；inline SVG 以便跟隨 `currentColor` 做深色模式 |
| **CLS** | 插圖必須有明確 `width`/`height` 或 `aspect-ratio`（34 §規則 9） |

### 24.8 實作備註

```html
<!-- 全頁空態 -->
<div class="cl-card">
  <div class="cl-empty cl-empty--page" role="status">
    <svg class="cl-empty__art" aria-hidden="true" width="200" height="160">…</svg>
    <h2 class="cl-empty__title">管理您的網址重新導向</h2>
    <p class="cl-empty__text">將您的顧客重新導向至其他頁面，以防止舊連結失效。</p>
    <div class="cl-empty__actions">
      <button type="button" class="cl-btn cl-btn--secondary">匯入網址重新導向</button>
      <button type="button" class="cl-btn cl-btn--primary">建立網址重新導向</button>
    </div>
  </div>
</div>
<p class="cl-empty__learn"><a class="cl-btn cl-btn--plain" href="/help/redirects">深入瞭解網址重新導向</a></p>

<!-- 卡內空態 -->
<div class="cl-card__body">
  <p class="cl-empty cl-empty--card"><span class="cl-empty__line">此日期範圍無資料</span></p>
</div>
```

**常見錯誤做法**：
- ❌ 標題寫「沒有資料」→ 沒有告訴使用者能做什麼。
- ❌ 卡內空態也放插圖 ＋ CTA → 儀表板上十張卡各一張插圖，畫面災難。
- ❌ 載入中顯示空態。
- ❌ 搜尋無結果卻用全頁空態插圖 → 使用者以為資料被刪光。
- ❌ 「深入瞭解」連結放在卡片**內** → 44 實測一律在卡外。
- ❌ 插圖沒有固定尺寸 → CLS。

---

## §25 404 `cl-404`（頂層 vs 區段內兩種）

**來源**：44 §19.10 ＋ §22.7（**兩種 404 版型實測對照**）、44 行動項 79（兩版都做）。

### 25.1 兩種版型的規格（44 §22.7 逐項）

| | **頂層 404** `cl-404--top` | **區段內 404** `cl-404--section` |
|---|---|---|
| 出現時機 | 整頁路由不存在（`/reports`、已移除的路徑） | 區段殼層仍在，只有內容不存在（`/online_store/redirects`） |
| 版型 | **左插圖 ＋ 右文字，水平並排** | **純文字垂直置中，無插圖** |
| 插圖 | 迷你視窗（自繪）＋大字 `404` | 無 |
| 標題字級 | `--t-display` | `--t-3xl` |
| 標題語氣 | 陳述「這個網址沒有頁面」 | 陳述「找不到這個內容」 |
| 副標語氣 | 指向**自助排除**：檢查網址、改用搜尋 | 指向**離開**：確認網址，或回首頁 |
| CTA | **無**（靠頂欄搜尋自救） | **有** primary，導向首頁 |
| 殼層 | **保留**（頂欄＋側欄都在） | 保留（含區段的次級導航） |

**只規範結構與語氣，不規範字面**——文案由我們自己寫（見前言的「關於範例中的文字」）。下方骨架中的字串是佔位。
**判定為哪一種**：路由層完全比對不到 → 頂層；路由比對到區段但資源 ID 不存在 → 區段內。

### 25.2 解剖

```
cl-404--top       display:flex; align-items:center; gap: var(--sp-800); justify-content:center
├─ cl-404__art    自繪 SVG，max-width: var(--art-404)，flex:none
└─ cl-404__body
    ├─ cl-404__title   --t-display
    └─ cl-404__text    --t-md; --text-2; max-width: 40ch

cl-404--section   text-align:center; padding-block: var(--sp-1200)
├─ cl-404__title  --t-3xl
├─ cl-404__text   --t-sm; --text-2
└─ cl-404__actions  primary
```

| 屬性 | 值 |
|---|---|
| 容器最小高 | `min-height: 60vh`；垂直置中 |
| 頂層版的 gap | `--sp-800` |
| 區段版的元素間距 | title→text `--sp-200`；text→actions `--sp-600` |

### 25.3 完整態表

| 態 | 說明 |
|---|---|
| **default** | 見上 |
| **hover / active / focus-visible** | 僅 CTA 與內文連結（沿用 §1） |
| **disabled** | N/A |
| **loading** | N/A（404 是終態） |
| **error** | 404 **本身就是錯誤態**。5xx 用不同元件（`cl-500`：同版型，標題「暫時無法載入」＋「重試」primary＋錯誤代碼 `--t-2xs --text-3`） |
| **selected** | N/A |
| **read-only** | N/A |

### 25.4 動效

- **無進場動畫。** 使用者已經在等待了，再加動畫是折磨。
- CTA 沿用 M1/M2。

### 25.5 鍵盤與焦點

- 頁面載入後焦點移到 `<h1 tabindex="-1">`（讓螢幕閱讀器立刻讀到「找不到頁面」）。
- `<title>` 也要改成「找不到頁面 · CHILL LOVE」——很多輔具依賴頁面標題。
- HTTP 狀態碼**必須真的是 404**（SPA 路由也要讓伺服器回 404，否則搜尋引擎與監控會看到 200）。
- 頂層版沒有 CTA，但頂欄的搜尋框要能用（副標文案就是叫使用者用搜尋列）——**確保頂欄搜尋在 404 頁仍然可用**。

### 25.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | 頂層版水平並排 |
| 768–1023 | 頂層版仍水平，插圖縮到 `var(--art-lg)` |
| ≤767 | **頂層版改垂直堆疊**（插圖在上、文字在下、置中）；標題降到 `--t-3xl` |
| ≤429 | 插圖隱藏；標題降到 `--t-xl`；只留文字 |

### 25.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標題** | `max-width: 20ch` ＋ 自然換行 |
| **深連結帶查詢字串** | 404 頁保留原 URL（不要 redirect），讓使用者能複製回報 |
| **舊路徑遷移**（44 §22.1：redirects 從線上商店搬到內容） | **優先做 301 導向而不是 404**；導向後 URL 帶 `?moved=1`，頁面頂端出 info banner「此頁面已移至「內容」」 |
| **權限不足 vs 不存在** | 兩者都回 404（不要用 403 洩漏資源存在性）；但登入後若確實有權限，改導向 |
| **慢網路** | 404 頁必須是靜態的、零 API 依賴 |
| **搜尋引擎** | `<meta name="robots" content="noindex">` |

### 25.8 實作備註

```html
<!-- 頂層 404 -->
<main class="cl-404 cl-404--top">
  <svg class="cl-404__art" aria-hidden="true" width="280" height="200">…</svg>
  <div class="cl-404__body">
    <h1 class="cl-404__title" tabindex="-1">此網址找不到頁面</h1>
    <p class="cl-404__text">請檢查網址並再試一次，或使用搜尋列尋找您需要的內容。</p>
  </div>
</main>

<!-- 區段內 404 -->
<div class="cl-404 cl-404--section">
  <h1 class="cl-404__title" tabindex="-1">找不到您要的內容</h1>
  <p class="cl-404__text">請確認網頁網址後再試一次，或前往 CHILL LOVE 首頁。</p>
  <div class="cl-404__actions">
    <a class="cl-btn cl-btn--primary" href="/">前往首頁</a>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ SPA 回 HTTP 200 的 404 頁。
- ❌ 兩種版型混用（區段內用了插圖，或頂層加了 CTA）→ 44 §22.7 明確區分。
- ❌ 404 頁把殼層也拿掉 → 使用者無法用導航離開。
- ❌ 沒有 `noindex`。
- ❌ 焦點沒移到標題。

---

## §26 Save bar `cl-savebar`

**來源**：44 §22.5（**新增公司表單一改動就出現頂欄 save bar：`⚠ 未儲存的變更　捨棄　儲存`，取代整條搜尋列（不是疊加）**，且**與頁尾 disabled `儲存` 並存**）、44 行動項 74（**定案 save bar 行為**）、44 §19.7／行動項 50（選單編輯器用頁尾按鈕，非 save bar）、44 §21.1／行動項 62（編輯器頂欄儲存鈕，第三種模式）、23 §3（dirty→浮出、捨棄還原 snapshot、導航離開阻擋）。

### 26.0 三種存檔模式的判定規則（**先看這個再看實作**）

| 頁面型態 | 存檔模式 | 元件 | 出處 |
|---|---|---|---|
| **有列表列／搜尋列的頁面**（index、含篩選的設定頁） | **save bar 原地取代該列** | `cl-savebar`（§26） | 44 §22.5 |
| **單欄置中編輯表單**（無列表列：選單編輯器、文章編輯器、新增公司） | **頁尾右下儲存鈕**（disabled until dirty） | `cl-savefoot`（§27） | 44 §19.7、§22.2 |
| **全螢幕編輯器**（結帳編輯器、主題編輯器） | **頂欄單一儲存鈕**（disabled until dirty） | `cl-editorbar__save`（§28） | 44 §21.1 |
| **即時生效的設定**（toggle 列） | **無存檔 UI**（切換即存） | §6 | 44 §18.5 |

**兩者並存是合法的**（44 §22.5 實測）：新增公司頁同時有頂欄 save bar 與頁尾 disabled 儲存鈕。**兩者綁同一個表單狀態**，任一顆按下都是同一個 submit。

### 26.1 解剖

```
cl-savebar             取代 cl-listbar 的位置；同高 --ctl-36；sticky top
├─ cl-savebar__icon    ⚠ 16×16
├─ cl-savebar__text    「未儲存的變更」--t-sm
└─ cl-savebar__actions margin-inline-start:auto; gap: var(--sp-200)
    ├─ 捨棄  cl-btn--secondary cl-btn--sm
    └─ 儲存  cl-btn--primary  cl-btn--sm
```

| 屬性 | 值 |
|---|---|
| 定位 | `position: sticky; inset-block-start: 0; z-index: var(--z-sticky)`；**在原本 listbar 的位置**，不是浮在上面 |
| 高 | `--ctl-36`（**與被取代的 listbar 同高**，這是「取代不疊加」的關鍵：高度一致才不會讓內容跳動） |
| 內距 | `0 var(--sp-300)` |
| 底 | `--surface-inverse` |
| 字 | `--text-inverse` |
| 圓角 | `--r-300`（若 listbar 在卡片頂端，改 `var(--r-300) var(--r-300) 0 0`） |

**「取代而非疊加」的實作**：listbar 與 savebar 是**同一個位置的兩個互斥子節點**。dirty 時 listbar `hidden`、savebar 顯示。**不要**用 `position:absolute` 蓋上去（會讓 listbar 的內容仍在 Tab 序）。

### 26.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（非 dirty）** | **不存在**（listbar 正常顯示） |
| **hover** | 僅按鈕（深底上的 secondary：`background: rgba(255,255,255,.14)`；hover `.24`） |
| **active** | 按鈕沿用 §1 |
| **focus-visible** | 按鈕出環，**環色用 `--text-inverse`**（深底上 `--focus` 對比不足） |
| **disabled** | 「儲存」在**驗證未通過**時 disabled ＋ tooltip 說明；「捨棄」永不 disabled |
| **loading（儲存中）** | 「儲存」進 loading；「捨棄」disabled；savebar 本身保持；`aria-busy="true"` |
| **error（儲存失敗）** | savebar 保持；文字改「儲存失敗」＋ `--critical` icon；**同時**在內容區頂部插 critical inline banner 列出錯誤；「儲存」回到可點狀態 |
| **selected** | N/A |
| **read-only** | N/A（唯讀頁不會 dirty） |
| **nudge（想離開卻沒存）** | 播 `cl-shake`（與 modal 共用 keyframes，§16.3）；同時出「捨棄變更？」modal |

### 26.3 dirty 狀態的判定與生命週期

| 階段 | 行為 |
|---|---|
| **進入頁面** | 對表單資料做深拷貝 snapshot |
| **任何 `input`/`change`** | 與 snapshot 深比對 → 相異即 dirty。**不是「有沒有觸發過事件」**（使用者改了又改回來 = 不 dirty，44 §18.2 的「未變更即 disabled」就是這個語意） |
| **捨棄** | 還原 snapshot → 重繪表單 → savebar 收起。**要二次確認**（若變更超過 3 個欄位） |
| **儲存成功** | 更新 snapshot → savebar 收起 → success toast |
| **儲存失敗** | 保持 dirty，見上表 error |
| **導航離開** | SPA 內：攔截路由 → 出 modal；瀏覽器層：`beforeunload`（**只在 dirty 時綁**，否則 Chrome 會警告） |
| **關閉分頁** | `beforeunload` |

### 26.4 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 出現／消失 | **M6**（`transform: translateY(-100%) → 0`，`--dur-slower`） | 從被取代的列的位置滑入 |
| 同時 listbar | `opacity` 淡出 `--dur-fast`（比 savebar 進場快，避免兩者重疊可見） | |
| nudge | `cl-shake` | §16.3 |
| **禁止** | 高度動畫 | savebar 與 listbar 同高，本來就不該有高度變化 |

### 26.5 鍵盤與焦點

- savebar 出現時**不搶焦點**（使用者正在打字）。
- `⌘/Ctrl + S` 全域＝儲存（`preventDefault`）；`⌘/Ctrl + Z` 在無輸入焦點時＝捨棄（需確認）。
- Tab 序：savebar 在 DOM 中的位置就是它視覺上的位置（表格上方），所以 Tab 會自然抵達。
- `role="region" aria-label="未儲存的變更"` ＋ 出現時 `role="status"` 播報一次「有未儲存的變更」。
- 儲存成功後焦點**留在原處**（不要跳走）。
- 「捨棄」是破壞性動作 → `aria-describedby` 說明會還原所有變更。

### 26.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 取代 listbar，同高 |
| ≤767 | **改貼底固定**（`position: fixed; inset-inline: var(--sp-300); inset-block-end: calc(var(--sp-300) + env(safe-area-inset-bottom))`）；理由：窄螢幕上表單很長，頂部的 savebar 會捲出視野。此時 listbar 恢復顯示 |
| ≤767 ＋ toast | toast 用 `:has()` 上移到 `86px + safe-area` |
| ≤429 | 兩顆按鈕各佔 50% 寬 |

### 26.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 狀態文字** | 固定「未儲存的變更」，不動態變長 |
| **金額變更** | 若變更涉及金額，savebar 文字可加「（3 項變更）」；金額細節放在儲存確認 modal 內 |
| **零變更** | savebar 不出現 |
| **極多變更**（>50 欄位） | 深比對用結構化 diff（不要每次 keystroke 全量 `JSON.stringify` 比對，會掉幀）；用 `requestIdleCallback` 或 200ms debounce |
| **慢網路** | 儲存 loading；>8s 出 inline 提示「儲存時間較長，請勿重新整理」 |
| **並發編輯**（他人同時改） | 儲存回 409 → critical banner「此資料已被 {who} 更新」＋ 兩顆按鈕「檢視差異」「覆寫」 |
| **與 sticky 表頭並存** | savebar `--z-sticky`(3)；表頭也是 3 → savebar 在 DOM 中更前，自然壓住。若不夠，savebar 用 `--z-bulkbar`(5) |
| **與 bulkbar 同時成立** | **不可能同時** —— 有選取時不該能編輯表單。若真的發生，savebar 優先，清空選取 |

### 26.8 實作備註

```html
<div class="cl-tablewrap">
  <!-- 互斥的兩個節點，同一個位置 -->
  <div class="cl-listbar" data-cl-listbar>…</div>
  <div class="cl-savebar" data-cl-savebar role="region" aria-label="未儲存的變更" hidden>
    <svg class="cl-savebar__icon" aria-hidden="true">⚠</svg>
    <span class="cl-savebar__text">未儲存的變更</span>
    <div class="cl-savebar__actions">
      <button type="button" class="cl-btn cl-btn--secondary cl-btn--sm" data-cl-discard>捨棄</button>
      <button type="submit" class="cl-btn cl-btn--primary cl-btn--sm" data-cl-save>儲存</button>
    </div>
  </div>
  …
</div>
```

**常見錯誤做法**：
- ❌ **右下浮動的 save bar** → 23 §3 的舊定案，已被 44 §22.5 實測推翻。
- ❌ 疊加在 listbar 上方（`position:absolute`）→ 底下的搜尋框仍在 Tab 序，鍵盤使用者會 Tab 到看不見的元素。
- ❌ dirty 判定用「有沒有觸發過 input 事件」→ 改了又改回來仍然 dirty，違反 44 §18.2 的「未變更即 disabled」。
- ❌ savebar 與 listbar 高度不同 → 切換時內容上下跳。
- ❌ `beforeunload` 永遠綁著 → 使用者每次離開都被警告。
- ❌ 深底上的焦點環用 `--focus`。

---

## §27 頁尾儲存鈕 `cl-savefoot`

**來源**：44 §19.7（選單編輯器**頁尾右下 disabled `儲存`**；「此頁用一般 footer 按鈕，不是 sticky save bar」）、44 行動項 50（**規範兩種存檔模式**）、44 §22.2（文章編輯器頁尾 disabled `儲存`）、44 §22.5（新增公司頁**頁尾 disabled 儲存 ＋ 頂欄 save bar 並存**）、44 §3.2（商品詳情底部 `儲存`）。

### 27.1 解剖

```
cl-savefoot          display:flex; justify-content:flex-end; gap: var(--sp-200)
                     margin-block-start: var(--sp-600); padding-block-end: var(--sp-800)
├─ 取消/捨棄  cl-btn--secondary（可選）
└─ 儲存       cl-btn--primary
```

| 屬性 | 值 |
|---|---|
| 位置 | **內容流的最後**（不是 sticky、不是 fixed） |
| 對齊 | 右對齊；與內容容器同寬（單欄置中頁 → `--w-narrow`） |
| 上方間距 | `--sp-600` |
| 下方留白 | `--sp-800`（讓按鈕不貼著視口底緣） |

**與 save bar 的關鍵差異**：`cl-savefoot` **不會浮動、不會 sticky、要捲到底才看得到**。這是刻意的——它用在「填完一整份表單才存」的語境，而 save bar 用在「隨時可能改一個欄位」的語境。

### 27.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（非 dirty）** | 「儲存」**disabled**（44 三處實測一致：未變更即 disabled） |
| **hover / active / focus-visible** | 沿用 §1 |
| **disabled** | 見 default；`aria-disabled="true"` ＋ `aria-describedby` 說明「尚未有變更」 |
| **loading** | 「儲存」loading；「取消」disabled |
| **error** | 按鈕回可點；**錯誤顯示在表單頂部的 critical banner**（不是按鈕旁邊——使用者的視線在按鈕，但錯誤在上面的欄位）；同時捲動到第一個錯誤欄位並 focus |
| **selected** | N/A |
| **read-only** | 整組不渲染 |
| **dirty** | 「儲存」enabled |

### 27.3 動效

- **無**。按鈕由 disabled 轉 enabled 只有 `opacity` 的 M1 時序變化。
- **不要**做「按鈕浮起來」「按鈕發光」等提示動效——若需要提醒使用者有未存變更，那就該用 save bar，不是這個元件。

### 27.4 鍵盤與焦點

- `<form>` 的 submit 按鈕（`type="submit"`），讓 Enter 在表單內能觸發。
- `⌘/Ctrl+S` 同樣觸發（`preventDefault`）。
- disabled 用 `aria-disabled` 而非原生 `disabled`（讓鍵盤能抵達並聽到「尚未有變更」的原因）。
- 儲存成功 → success toast ＋ 焦點留在按鈕（使用者可能要連續儲存）。
- 離開頁面時的 dirty 攔截同 §26.3。

### 27.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 右對齊 |
| ≤767 | 按鈕**全寬堆疊**（主鈕在上）；`padding-block-end` 加 `env(safe-area-inset-bottom)` |
| ≤429 | 同上 |

### 27.6 邊界情況

| 情況 | 處置 |
|---|---|
| **表單很長** | 這正是它的適用情境。**但若表單超過 3 螢幕高**，改用 save bar（使用者不該為了存檔捲三頁） |
| **零變更** | disabled |
| **慢網路** | loading；>8s 出 inline 提示 |
| **與頂欄 save bar 並存**（44 §22.5） | **兩者綁同一個表單狀態**，同時 enable／disable、同時 loading。按任一顆都是同一個 submit |
| **驗證失敗** | 捲動到第一個錯誤欄位（`scrollIntoView({block:'center', behavior:'smooth'})`）＋ focus |

### 27.7 實作備註

```html
<form data-cl-form="menu-edit">
  …卡片…
  <div class="cl-savefoot">
    <button type="submit" class="cl-btn cl-btn--primary"
            aria-disabled="true" aria-describedby="sf-why">儲存</button>
  </div>
  <span class="sr-only" id="sf-why">尚未有變更，無法儲存。</span>
</form>
```

**常見錯誤做法**：
- ❌ 做成 sticky → 那就是 save bar，兩種模式的區分就消失了。
- ❌ 預設 enabled → 44 三處實測都是 disabled until dirty。
- ❌ 用原生 `disabled` → 鍵盤使用者無法得知為什麼不能存。
- ❌ 錯誤訊息只放在按鈕旁 → 使用者不知道是哪一欄錯。
- ❌ 超長表單（>3 螢幕）還用頁尾按鈕。

---

## §28 編輯器頂欄儲存鈕 `cl-editorbar`

**來源**：44 §21.1（**結帳編輯器頂欄**：左 `⇤` 離開／`🏪` 商店 icon／**兩行標題**（第一行＝目前頁名可點開頁面選擇器；第二行＝`● 綠點` ＋ 目前設定檔名）／右 `📱` 裝置切換／`⋯` 頁級選單／**disabled `儲存`**）、44 §21.6（**儲存語意：頂欄單一「儲存」，dirty 才 enable，一次存整個 profile 的 layout JSON**）、44 行動項 62（第三種存檔模式）、47 §0（頂欄高 `--h-topbar` 56）。

### 28.1 解剖

```
cl-editorbar          height: var(--h-topbar); background: --surface-inverse
├─ cl-editorbar__left
│   ├─ button 離開編輯器  --ctl-36 icon，aria-label「離開編輯器」
│   ├─ cl-editorbar__sep  1px 直線，--sp-400 高，rgba(255,255,255,.2)
│   └─ button 商店        --ctl-36 icon
├─ cl-editorbar__title    （兩行，可點）
│   ├─ button.cl-editorbar__page   第一行：目前頁名 --t-sm ＋ ⌄
│   └─ cl-editorbar__profile       第二行：● 綠點 ＋ 設定檔名 --t-2xs, --text-3 的反色階
└─ cl-editorbar__right
    ├─ 裝置切換 segmented（桌機／手機兩態，**無平板**，44 §21.6）
    ├─ ⋯ 頁級選單
    └─ 儲存  cl-btn--primary cl-btn--sm（**深底上的 primary 用白底黑字**）
```

| 屬性 | 值 |
|---|---|
| 高 | `--h-topbar`（56） |
| 內距 | `0 var(--sp-300)` |
| gap | `--sp-200` |
| 底 | `--surface-inverse` |
| 綠點 | `--sp-150`(6) 正方圓點，`--success` |

**深底上的按鈕配色反轉**：primary → `background: --text-inverse; color: --surface-inverse`；secondary → `background: rgba(255,255,255,.14); border-color: rgba(255,255,255,.3); color: --text-inverse`；icon → `color: --text-inverse`，hover `background: rgba(255,255,255,.15)`。

### 28.2 完整態表（「儲存」鈕）

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default（非 dirty）** | **disabled**（44 §21.1 實測）；`opacity: var(--disabled-opacity)` |
| **hover** | `background: color-mix(in srgb, var(--text-inverse) 92%, var(--surface-inverse))` |
| **active** | 再深一階 |
| **focus-visible** | outline `--text-inverse` 2px offset 1px |
| **disabled** | 見 default；`aria-disabled` ＋ 說明「尚未有變更」 |
| **loading** | spinner（深色，因為底是白的）；label 保留佔位 |
| **error** | 儲存失敗 → 頂欄下方插一條 critical inline banner（**橫跨編輯器全寬**）；「儲存」回可點 |
| **selected** | N/A |
| **read-only** | 無編輯權限時整顆隱藏；標題第二行加「唯讀」chip |
| **dirty** | enabled；同時頁面標題（`document.title`）前綴 `•`（讓分頁列也看得到未存狀態） |

**頁名按鈕的態**：hover `background: rgba(255,255,255,.12)`；`aria-haspopup="dialog" aria-expanded`；點擊開 **bottom sheet**（§18，44 §21.2）。

**綠點的語意**：`● 綠` ＝設定檔使用中；`○ 灰` ＝草稿／未啟用（與 44 §18.2 卡片上的「使用中」badge 同源）。

### 28.3 動效

| 屬性 | 規則 |
|---|---|
| 按鈕 | **M1 ＋ M2** |
| 頁面選擇器 sheet | **M6**（§18.3） |
| ⋯ 選單 | **M5** |
| 裝置切換 | 預覽區寬度變化用 **M7**（`max-width`，因為改的是容器寬度） |
| 焦點環 | **M3** |

### 28.4 鍵盤與焦點

- 頂欄是 `<header role="banner">`；Tab 序：離開 → 商店 → 頁名 → 裝置切換 → ⋯ → 儲存。
- `⌘/Ctrl+S` 儲存。
- `Esc` 在編輯器內：先關浮層；沒有浮層時**不做任何事**（不要用 Esc 離開編輯器，太危險）。
- 離開編輯器按鈕：dirty 時出「捨棄變更？」modal。
- 裝置切換是 `role="radiogroup"`（兩個 radio），不是兩個 toggle button。
- 標題第二行的綠點要有 sr-only 文字（「使用中」）。

### 28.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥1280 | 完整：三欄（圖層樹／預覽／屬性檢查器）〔待覆核，47 §7 第 2 項未量測〕 |
| 1024–1279 | 兩欄（樹／預覽）；屬性檢查器改為右側 drawer |
| 768–1023 | 頂欄的商店 icon 隱藏；標題第二行隱藏（改進 ⋯ 選單） |
| ≤767 | 編輯器**不支援**（顯示「請使用較大的螢幕編輯」＋ 回設定的連結）。理由：圖層樹＋預覽＋檢查器三者在 767px 以下無法並存，強行做出來也不能用 |

### 28.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 頁名／設定檔名** | 兩行各自單行 ellipsis；`max-width: var(--w-crumbtitle)` |
| **零筆**（無可編輯區塊，44 §21.4） | 圖層樹顯示空態，頂欄不變 |
| **慢網路** | 頂欄先渲染（頁名從路由參數取得）；預覽區 skeleton |
| **儲存整包 JSON**（44 §21.6） | 一次存整個 profile 的 layout；**要帶 `updated_at` 做樂觀鎖**，衝突回 409 |
| **離開時未存** | `beforeunload` ＋ SPA 路由攔截 ＋ 「離開編輯器」按鈕攔截，三處都要 |
| **多分頁同時編輯** | 用 BroadcastChannel 偵測，第二個分頁出 warning banner「此設定檔已在另一個分頁開啟」 |

### 28.7 實作備註

```html
<header class="cl-editorbar" role="banner">
  <div class="cl-editorbar__left">
    <button type="button" class="cl-btn cl-btn--icon" aria-label="離開編輯器">⇤</button>
    <span class="cl-editorbar__sep" aria-hidden="true"></span>
    <button type="button" class="cl-btn cl-btn--icon" aria-label="前往商店">🏪</button>
  </div>
  <div class="cl-editorbar__title">
    <button type="button" class="cl-editorbar__page" aria-haspopup="dialog" aria-expanded="false">
      結帳 <svg aria-hidden="true">⌄</svg>
    </button>
    <span class="cl-editorbar__profile">
      <span class="cl-editorbar__dot" aria-hidden="true"></span>
      <span class="sr-only">使用中：</span>「CHILL LOVE」設定
    </span>
  </div>
  <div class="cl-editorbar__right">
    <div class="cl-seg" role="radiogroup" aria-label="預覽裝置">…</div>
    <button type="button" class="cl-btn cl-btn--icon" aria-label="編輯器選單">⋯</button>
    <button type="button" class="cl-btn cl-btn--primary cl-btn--sm"
            aria-disabled="true" aria-describedby="eb-why">儲存</button>
  </div>
  <span class="sr-only" id="eb-why">尚未有變更，無法儲存。</span>
</header>
```

**常見錯誤做法**：
- ❌ 編輯器也用 save bar → 44 §21.6 明確是「頂欄單一儲存」。
- ❌ 深底上的 primary 用 `--brand`（近黑）→ 在深底上看不見。
- ❌ 裝置切換做三態（含平板）→ 44 §21.6 實測只有桌機／手機兩態。
- ❌ Esc 離開編輯器。
- ❌ 沒有樂觀鎖 → 兩人同時編輯後者覆蓋前者。
- ❌ 頁名不可點 → 44 §21.2 實測那是頁面選擇器的入口。


---

## §29 麵包屑 chip `cl-crumb`

**來源**：44 §18.1（`← 草稿圖示 › 建立訂單草稿`，**麵包屑用「圖示＋›＋標題」，非文字連結**）、44 §18.6（`🗒 › 預設規則`）、44 §19.2（`🚚 › 一般設定檔`）、44 §19.6（`⊞ › 偏好設定`）、44 §22.6（`🌐 › United States`）、44 §2.2／§3.2（`← {資源圖示}` ＋ 大字標題 ＋ badge 群 ＋ **上一筆／下一筆箭頭**）、47 §5 關鍵幀（麵包屑遮罩）。

### 29.1 這不是傳統麵包屑（先搞清楚）

實測的形態是 **「回上層的 icon chip ＋ `›` ＋ 當前頁標題」**，**只有兩層**：

```
[🗒] › 預設規則
 ↑     ↑
 回上層  當前（不是連結）
```

**不是** `首頁 › 設定 › 政策 › 退貨規則` 那種完整路徑。這是刻意的資訊設計：**上層用 icon 表示（節省寬度），當前頁用大字標題（頁面的主識別）**。

### 29.2 解剖

```
cl-pagehead                     flex; align-items:center; gap: var(--sp-300)
├─ a.cl-crumb                   回上層；--ctl-28 正方；--r-200
│   └─ icon 16×16
├─ cl-crumb__sep                › 12×12；--text-3；aria-hidden
├─ h1.cl-pagehead__title        --t-3xl（≥768）／--t-2xl（≤767）
├─ cl-pagehead__badges          §11 badge 群
└─ cl-pagehead__actions         margin-inline-start:auto
    ├─ ⋯ 更多動作
    ├─ cl-pagehead__nav         上一筆／下一筆箭頭（詳情頁才有，44 §2.2/§3.2）
    └─ primary
```

| 屬性 | 值 |
|---|---|
| chip 尺寸 | `--ctl-28` 正方 |
| chip 底 | 透明；hover `--surface-hover` |
| chip 圓角 | `--r-200` |
| 分隔符 | `›`，`--text-3`，左右 margin `--sp-100` |
| 標題 | `--t-3xl`（24/32/**450**，見 §00.11） |
| 整列高 | `min-height: var(--ctl-36)` |
| 下方間距 | `--sp-400` |

### 29.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | chip 透明底、`--text-2` icon |
| **hover** | chip `background: --surface-hover`；icon `--text` |
| **active** | chip `background: --surface-active` |
| **focus-visible** | chip outline 2px offset 1px |
| **disabled** | 上一筆／下一筆箭頭在邊界時 disabled（`opacity` ＋ `aria-disabled`），**不隱藏**（44 §19.4 實測分頁 disabled 態就是保留顯示） |
| **loading** | 標題換 skeleton 條（寬 12ch）；chip 保持（上層路徑是已知的） |
| **error** | N/A |
| **selected** | N/A |
| **read-only** | N/A |

### 29.4 動效

| 屬性 | 規則 |
|---|---|
| chip 底／icon 色 | **M1 ＋ M2** |
| 上／下一筆切換 | 內容區直接替換，**不做頁面轉場動畫**（47 §5 沒有頁面轉場的量測；23 §5 的「頁面切換 180ms fade+3px 上移」作廢） |
| 焦點環 | **M3** |
| 麵包屑遮罩 | 47 §5 提到有此 keyframes，但我們的兩層麵包屑不需要溢出遮罩 → **不實作** |

### 29.5 鍵盤與焦點

- chip 是真 `<a href>`，`aria-label="返回 政策"`（icon-only 必須有 label）。
- `›` 是 `aria-hidden`。
- 標題是 `<h1>`（每頁只有一個）。
- 外層 `<nav aria-label="麵包屑">` 只包 chip ＋ 分隔符 ＋ 當前頁名的 sr-only 版本；`<h1>` 在 nav **之外**（避免輔具把標題念兩次）。
- 上一筆／下一筆：`aria-label="上一筆訂單"`／`"下一筆訂單"`；快捷鍵 `J`／`K` 或 `[`／`]`。
- `Alt+←`（瀏覽器上一頁）不攔截。

### 29.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥1024 | 全部同一行 |
| 768–1023 | badge 群換行到標題下方 |
| ≤767 | 標題降到 `--t-2xl`；actions 換行到第二行、右對齊；上一筆／下一筆保留（詳情頁靠它導覽很有效） |
| ≤429 | actions 中除 primary 外全收進 `⋯` |

### 29.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標題**（商品名） | 最多兩行 `-webkit-line-clamp: 2` ＋ `title`；**不要單行 ellipsis**（商品名截斷後無法辨識） |
| **標題含金額** | 罕見；若有則拆 span |
| **零筆**（資源不存在） | 走 §25 的區段內 404 |
| **深層路徑**（超過兩層） | **仍然只顯示一層 icon chip**（最近的上層）。若使用者需要完整路徑，放在 `⋯` 選單內 |
| **慢網路** | chip ＋ `›` 先渲染（來自路由參數），標題 skeleton |
| **上／下一筆的資料集** | 依**當前列表的排序與篩選**決定順序（不是全域 ID 序）；列表狀態存 sessionStorage，詳情頁讀取 |
| **列表為最後一頁** | 「下一筆」disabled；**不要**自動跳到下一頁再取第一筆（使用者會迷路） |

### 29.8 實作備註

```html
<div class="cl-pagehead">
  <nav aria-label="麵包屑">
    <a class="cl-crumb" href="/settings/legal" aria-label="返回 政策">
      <svg aria-hidden="true">🗒</svg>
    </a>
    <span class="cl-crumb__sep" aria-hidden="true">›</span>
  </nav>
  <h1 class="cl-pagehead__title">預設規則</h1>
  <div class="cl-pagehead__badges">
    <span class="cl-badge cl-badge--default">未設定規則</span>
  </div>
  <div class="cl-pagehead__actions">
    <button type="button" class="cl-btn cl-btn--icon" aria-label="更多動作">⋯</button>
    <div class="cl-pagehead__nav">
      <a class="cl-btn cl-btn--icon" href="/…/prev" aria-label="上一筆">‹</a>
      <a class="cl-btn cl-btn--icon" href="/…/next" aria-label="下一筆">›</a>
    </div>
  </div>
</div>
```

**常見錯誤做法**：
- ❌ 做成完整文字路徑麵包屑 → 44 五處實測都是「icon chip ＋ › ＋ 標題」。
- ❌ icon chip 沒有 `aria-label` → 螢幕閱讀器只念「連結」。
- ❌ `<h1>` 放在 `<nav>` 內。
- ❌ 標題單行 ellipsis。
- ❌ 上／下一筆用全域 ID 序而非列表順序。
- ❌ 標題字重 700 → 應為 450（#83）。

---

## §30 分頁器 `cl-pagination`

**來源**：44 §3.1（底部 `‹ ›` 箭頭 ＋ `1-50`，每頁 50 筆）、44 §19.4（底部置中 `‹ ›`，**disabled 態保留顯示**）、44 §19.5（**cursor 分頁參數直接進 URL**：`?before=&after=&tab=installed`）、44 行動項 43（**可分享／可回溯，admin SPA 要照做**）、47 §4（icon 按鈕 28×28）、CLAUDE.md 鐵律 4（cursor＋`pageInfo`，≤250）。

### 30.1 解剖

```
nav.cl-pagination        display:flex; justify-content:center; align-items:center
                         gap: var(--sp-100); padding: var(--sp-300)
├─ button.cl-pagination__prev   --ctl-28 正方；--r-200；--bw-100 --border
├─ cl-pagination__range          --t-xs; --text-2; tabular-nums；「1-50」或「1-50 / 共 1,284」
└─ button.cl-pagination__next   同 prev
```

| 屬性 | 值 |
|---|---|
| 按鈕 | `--ctl-28` 正方；`--r-200`；`--bw-100 solid var(--border)`；底 `--surface` |
| 範圍文字 | `--t-xs`；`--text-2`；`font-variant-numeric: tabular-nums` |
| 對齊 | 置中（44 兩處實測皆置中） |
| 位置 | 卡片內、表格下方；**在卡片的圓角內**（不要溢出） |

**沒有頁碼按鈕**（44 兩處實測都只有 `‹ ›`）。理由：cursor 分頁沒有「第 N 頁」的概念——你不能跳到第 7 頁，因為 cursor 是鏈式的。**不要為了「看起來完整」加頁碼**，那會逼你退回 offset 分頁，在大表上會慢。

### 30.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 見上 |
| **hover** | `background: --surface-hover`；`color: --text` |
| **active** | `background: --surface-active` |
| **focus-visible** | outline 2px offset 1px |
| **disabled** | 首頁時 `prev` disabled、末頁時 `next` disabled：`opacity: var(--disabled-opacity)`；`cursor: default`；**保留顯示不隱藏**（44 §19.4 實測） |
| **loading** | 兩顆都 disabled；範圍文字換 skeleton 條；**表格區換 skeleton 不換空白** |
| **error** | 換頁失敗 → 表格區出 critical banner ＋「重試」；分頁器回復到前一狀態 |
| **selected** | N/A（無頁碼） |
| **read-only** | N/A |
| **只有一頁** | **整個分頁器不渲染**（兩顆都 disabled 的分頁器是視覺雜訊） |

### 30.3 URL 契約（44 行動項 43 的落地）

| 參數 | 語意 |
|---|---|
| `?after={cursor}` | 下一頁（往後） |
| `?before={cursor}` | 上一頁（往前） |
| `?limit=50` | 每頁筆數；**上限 250**（CLAUDE.md 鐵律 4） |
| `?tab={viewSlug}` | 當前 saved view（§10） |
| `?q=`／`?f[...]=` | 搜尋與篩選 |
| `?sort={field}:{dir}` | 排序 |

**三條規則**：① 換頁用 `history.pushState`（可用瀏覽器上一頁回去）；② 篩選／排序／檢視變更用 `replaceState` **並清空 cursor**（換了條件，舊 cursor 無意義）；③ 直接貼上帶 cursor 的 URL 必須能重現同一頁。

### 30.4 動效

| 屬性 | 規則 |
|---|---|
| 按鈕 | **M1 ＋ M2** |
| 換頁 | **不做頁面轉場**；表格區換 skeleton，資料到位直接替換 |
| 捲動位置 | 換頁後 `scrollIntoView` 到表格頂端（`behavior: 'instant'`，**不要 smooth**——使用者已經知道自己要換頁了） |

### 30.5 鍵盤與焦點

- `<nav aria-label="分頁">`。
- 兩顆是 `<button>`（不是 `<a>`，因為 cursor 換頁是 SPA 行為）；`aria-label="上一頁"`／`"下一頁"`。
- 換頁後焦點**留在按鈕上**（讓使用者能連按）。若該按鈕變 disabled（到了邊界）→ 焦點移到另一顆。
- 換頁後用 `role="status"` 播報「顯示第 51-100 筆，共 1,284 筆」。
- 快捷鍵：`←`／`→` 在分頁器聚焦時換頁。

### 30.6 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 置中，`‹ 1-50 / 共 1,284 ›` |
| ≤767 | 按鈕 `--ctl-44`；範圍文字簡化為 `1-50`（隱藏總數）；兩顆按鈕分置左右、文字置中（`justify-content: space-between`） |
| ≤429 | 同上 |

### 30.7 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK** | N/A |
| **金額** | N/A |
| **零筆** | 分頁器不渲染（表格區顯示空態） |
| **極大總數** | 顯示近似值「共 約 12,000 筆」；**不要為了精確數字掃全表**。若後端能便宜地給精確值就給 |
| **總數未知** | 只顯示 `1-50`，不顯示總數。`next` 的 disabled 依 `pageInfo.hasNextPage` 判定 |
| **慢網路** | 兩顆 disabled ＋ 表格 skeleton；>1s 才顯示 skeleton |
| **cursor 失效**（資料被刪） | 後端回錯誤 → 前端 fallback 到第一頁 ＋ info banner「資料已更新，已回到第一頁」 |
| **每頁筆數變更** | 清空 cursor 回第一頁；`limit` 存使用者偏好 |

### 30.8 實作備註

```html
<nav class="cl-pagination" aria-label="分頁">
  <button type="button" class="cl-pagination__prev" aria-label="上一頁" disabled>‹</button>
  <span class="cl-pagination__range">1-50 / 共 1,284</span>
  <button type="button" class="cl-pagination__next" aria-label="下一頁">›</button>
</nav>
<span class="sr-only" role="status">顯示第 1-50 筆，共 1,284 筆</span>
```

**常見錯誤做法**：
- ❌ 加頁碼按鈕 → 與 cursor 分頁的模型矛盾。
- ❌ 到邊界時隱藏按鈕 → 版面左右跳；44 §19.4 實測是 disabled 保留。
- ❌ 分頁狀態不進 URL → 重整回第一頁、無法分享。
- ❌ 篩選變更時保留舊 cursor → 拿到不相干的資料或直接報錯。
- ❌ 換頁用 smooth 捲動。
- ❌ 只有一頁還渲染分頁器。
- ❌ `limit` 超過 250。

---

## §31 字元計數器 `cl-counter`

**來源**：44 §19.6（**四處實測硬值**：密碼 `已使用 6/100 個字元`、訪客訊息 `0/5,000`、首頁標題 `0/70`、中繼描述 `0/320`）、44 行動項 46（**元件＋硬值**，格式統一）、47 §3（`--t-xs`）。

> 本節是 §7.3 的獨立元件化版本。textarea 之外，單行輸入（首頁標題 70）、密碼（100）也用它。

### 31.1 解剖

```
span.cl-counter          --t-xs; --text-3; tabular-nums; white-space: nowrap
├─ cl-counter__n         當前字數（會變色）
└─ （靜態文字）           「已使用 」「/」「 個字元」
```

**格式（硬性，44 逐字）**：`已使用 {n}/{max} 個字元`
- `{max}` 千分位加逗號（`5,000`）；`{n}` **不加逗號**（實測 `6/100`）。
- 整串 `white-space: nowrap`（`.cl-money` 的同類規則，34 §6）。
- **不要**改成 `{n} / {max}` 或 `剩餘 {x} 字` 等變體。

### 31.2 已知上限值（一律走 `config/limits.yml`）

| 欄位 | max | 出處 |
|---|---|---|
| 商店密碼 | 100 | 44 §19.6 |
| 給訪客的訊息 | 5,000 | 44 §19.6 |
| 首頁標題（SEO title） | 70 | 44 §19.6 |
| 中繼描述（meta description） | 320 | 44 §19.6 |

**CLAUDE.md 鐵律 6**：不得硬編在元件內。元件只讀 `data-cl-counter-max`，值由後端／設定注入。

### 31.3 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default**（n ≤ 80% max） | `color: --text-3` |
| **hover** | N/A |
| **active** | N/A |
| **focus-visible**（關聯欄位聚焦時） | `color: --text-2`（提一階，暗示「正在數」） |
| **disabled**（關聯欄位 disabled） | **仍顯示**（44 §19.6 實測 disabled 的 textarea 下方計數器照樣在）；`color: --text-3` ＋ `opacity: var(--disabled-opacity)` |
| **loading** | N/A |
| **warning**（80% < n ≤ 100%） | `color: --warning`；`font-weight: 500` |
| **error**（n > max） | `color: --critical`；文字改 `已超出 {n-max} 個字元`；同時關聯欄位進 error 態、送出鈕 disabled |
| **selected** | N/A |
| **read-only**（關聯欄位 read-only） | 格式改 `{n} 個字元`（沒有上限語意） |

### 31.4 計數規則（實作核心）

```js
// 1) CJK 一字算一字、emoji 一個算一個
const seg = new Intl.Segmenter('zh-Hant', { granularity: 'grapheme' });
const count = (s) => [...seg.segment(s)].length;

// 2) IME 組字中不計數
let composing = false;
el.addEventListener('compositionstart', () => { composing = true; });
el.addEventListener('compositionend',  () => { composing = false; update(); });
el.addEventListener('input', () => { if (!composing) update(); });

// 3) 只在跨越門檻時更新 aria-live，避免每字播報
```

| 規則 | 說明 |
|---|---|
| **軟限制** | 允許超過 max，標紅並擋送出。**不要用 `maxlength`**（貼上長文會無聲截斷） |
| **例外** | 技術欄位（handle、slug、代碼）用硬 `maxlength` |
| **門檻播報** | 只在 80%／100%／超限三個點更新 `aria-live` 節點 |
| **>10k 字** | 停用即時計數，改 500ms debounce |

### 31.5 動效

| 屬性 | 規則 |
|---|---|
| 顏色變化 | **M2**（`color var(--dur-fast)`） |
| 數字變化 | **不做動畫**（跳動的數字無法閱讀） |

### 31.6 鍵盤與焦點

- 計數器本身**不可聚焦**。
- `id` 掛進關聯欄位的 `aria-describedby`。
- `aria-live="polite"` ＋ `aria-atomic="true"`；只在門檻點更新（見上）。
- 超限時，錯誤訊息由 `cl-field__error` 承載（`role="alert"`），計數器只負責數字。

### 31.7 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 與 hint 同一行，右對齊 |
| ≤767 | 換行到 hint 下方，**仍右對齊**（右對齊讓數字位置穩定，容易掃視） |

### 31.8 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 貼上** | 全部保留 → 標紅 → 擋送出 ＋ 說明超出幾字 |
| **金額** | N/A |
| **零字元** | 顯示 `已使用 0/{max} 個字元`（**不隱藏**） |
| **極大 max**（5,000） | 千分位逗號；`tabular-nums` 讓數字寬度穩定 |
| **慢網路** | N/A（純前端） |
| **多位元組字元** | grapheme 計數（見 31.4） |
| **後端上限與前端不同** | 以後端為準；前端從 API 的 schema 或設定端點取得 max，**不要兩邊各寫一份** |

### 31.9 實作備註

```html
<p class="cl-counter" id="f-meta-count" aria-live="polite" aria-atomic="true">
  已使用 <span class="cl-counter__n">0</span>/320 個字元
</p>
```

**常見錯誤做法**：
- ❌ `String.length` 計數。
- ❌ IME 組字中就計數 → 注音未上屏就被算進去。
- ❌ `maxlength` 硬截斷。
- ❌ 每打一字更新 `aria-live` → 螢幕閱讀器使用者無法打字。
- ❌ disabled 時隱藏計數器。
- ❌ 上限值硬編在元件內（違反鐵律 6）。
- ❌ 改寫文案格式。

---

## §32 拖曳排序列 `cl-dragrow`

**來源**：44 §19.7（**選單編輯器的選單項目列**：`⣿` 拖曳把手 ＋ 標籤 ＋ `✏` ＋ `🗑`；末列 `⊕ 新增選單項目`）、44 §21.3（結帳編輯器圖層樹：`›` 進設定／`⌄` 展開子層／`👁` 顯隱／虛線方框＝block）、44 行動項 57（圖層樹語意元件化）、47 §4（列高階）、47 §5 M6。

### 32.1 解剖

```
ul.cl-draglist
└─ li.cl-dragrow            高 --ctl-36；padding: 0 var(--sp-300); gap: var(--sp-200)
    ├─ button.cl-dragrow__grip    ⣿ 拖曳把手；--ctl-28 正方；cursor: grab
    ├─ cl-dragrow__icon           可選 16×16（圖層樹的 block 圖示）
    ├─ cl-dragrow__label          --t-sm; flex:1; min-width:0
    ├─ cl-dragrow__meta           --t-xs; --text-3（可選副標／計數）
    └─ cl-dragrow__actions        ✏ ／ 👁 ／ 🗑；各 --ctl-28 icon 按鈕
└─ button.cl-draglist__add        ⊕ 新增…；高 --ctl-36；虛線上框；--text-2
```

| 屬性 | 值 |
|---|---|
| 列高 | `--ctl-36`（比表格列高，因為要放把手與三顆動作鈕） |
| 分隔線 | `--bw-100 var(--border-2)` |
| 把手 | `--text-3`；hover `--text-2`；`cursor: grab`／拖曳中 `grabbing` |
| 巢狀縮排（圖層樹） | 每層 `--sp-600`(24)；最多 **3 層** |
| 動作鈕 | 桌機：hover 或 focus 該列時才顯示（`opacity 0→1`）；**≤767 恆顯示**（沒有 hover） |

### 32.2 完整態表

| 態 | 變什麼 → 變成什麼 |
|---|---|
| **default** | 透明底；動作鈕 `opacity: 0`（桌機） |
| **hover** | `background: --surface-hover`；動作鈕 `opacity: 1`；把手 `--text-2` |
| **active**（按住把手） | `cursor: grabbing`；列 `box-shadow: var(--sh-pop)`；`background: --surface` |
| **focus-visible** | 列內任一按鈕聚焦 → 該按鈕出環，且列自動套 hover 樣式（動作鈕顯示）。用 `:has(:focus-visible)` |
| **disabled** | 系統列（不可刪的群組，44 §21.3 的「頁首／主要／頁尾」）：把手與 🗑 不渲染；`›` 仍可點 |
| **loading**（排序儲存中） | 整個 `cl-draglist` `aria-busy="true"`；把手 disabled；**列位置已是新順序**（樂觀更新） |
| **error**（排序失敗） | 列**動畫回到原位**（M6）＋ critical toast；`aria-live="assertive"` 播報 |
| **selected**（圖層樹當前選取） | `background: --selected-bg`；左緣 `box-shadow: inset var(--bw-200) 0 0 var(--brand)`；`aria-selected="true"` |
| **read-only** | 把手與動作鈕全不渲染；列仍可點（若有 `›`） |
| **dragging（被拖的列）** | `opacity: .5`；原位置保留為佔位 |
| **drop-target（插入點）** | 在目標位置畫 `2px` `--focus` 橫線（`--bw-200`），**不要**用整列反白（分不清是「放進去」還是「放在上面」） |
| **hidden（圖層樹 👁 關閉）** | `opacity: .55`；label 加刪除線？**不加**——改在 label 後接 `--t-2xs` 的「已隱藏」灰字 |

### 32.3 動效

| 屬性 | 規則 | 為什麼 |
|---|---|---|
| 拖曳中 | **不加 transition**（跟手） | |
| 其他列讓位 | `transform: translateY()` ＋ **M6**（`--dur-slower` 太慢，這裡用 `--dur-base` 覆寫） | 讓位要快 |
| 放下歸位 | **M6** | 47 M6 是 transform 類的標準 |
| 失敗回彈 | **M6** 反向 | |
| 列 hover 底 | **M1** | |
| 動作鈕顯示 | `opacity var(--dur-fast) var(--ease-standard)` | |
| 巢狀展開 | **M4** | 同 accordion |

〔推導〕M6 的 250ms 用在「讓位」上偏慢，本元件的讓位動畫覆寫為 `--dur-base`(150ms)，曲線仍用 `--ease-standard`。這是本文件唯一一處對 M1–M7 的時長覆寫，**必須註明理由**。

### 32.4 鍵盤與焦點（**最容易做錯的一節**）

拖曳排序**必須有完整鍵盤替代方案**，否則等同不可用。

| 鍵 | 行為 |
|---|---|
| `Tab` | 抵達把手（把手是 `<button>`，不是裝飾） |
| `Space`／`Enter` 在把手上 | **進入「抓取模式」**：`aria-grabbed="true"`；列套 dragging 樣式；播報「已抓取 {項目名}，使用上下鍵移動，Enter 放下，Esc 取消」 |
| `↑↓`（抓取模式中） | 上下移動一格；每次移動播報「移動到第 3 位，共 8 項」 |
| `←→`（抓取模式，圖層樹） | 降/升一層巢狀；播報新層級 |
| `Enter`／`Space` | 放下並儲存；播報「已放下，{項目名} 現在是第 3 項」 |
| `Esc` | 取消，回原位 |
| `Home`／`End`（抓取模式） | 移到首／末 |

- 清單用 `<ul role="listbox">`（圖層樹用 `role="tree"`），列 `role="option"`／`role="treeitem"`。
- 圖層樹的 `aria-level`／`aria-expanded`／`aria-setsize`／`aria-posinset` 都要寫。
- 動作鈕的 `aria-label` 要含項目名（「編輯 首頁 選單項目」）。
- `👁` 是 `aria-pressed` 的 toggle button（「隱藏 政策 區塊」）。

### 32.5 響應式

| 斷點 | 變化 |
|---|---|
| ≥768 | 動作鈕 hover 才顯示 |
| ≤767 | 列高 `--ctl-44`；**動作鈕恆顯示**（無 hover）；若三顆放不下，收成一顆 `⋯` 開 sheet；把手命中區 `--hit-min` |
| ≤429 | 巢狀縮排降到 `--sp-400`；`cl-dragrow__meta` 隱藏 |

### 32.6 邊界情況

| 情況 | 處置 |
|---|---|
| **超長 CJK 標籤** | 單行 ellipsis ＋ `title`；把手與動作鈕 `flex: none` **永不被擠** |
| **金額在列內**（運費費率列，44 §19.2） | 價格用 badge（`.cl-money`）放在 actions 之前 |
| **零筆** | 只顯示 `⊕ 新增…` 列 ＋ 上方一行灰字說明（卡內空態語氣） |
| **極多項目**（>50） | 拖曳體驗會崩潰 → 超過 50 項時**停用拖曳**，改提供「移到第 N 位」的數字輸入 modal |
| **慢網路** | 樂觀更新（列先動）→ 失敗回彈 ＋ toast。排序 API 用**整批新順序**送出（不是逐筆 move），避免中途失敗造成順序錯亂 |
| **拖到清單外** | 取消（回原位），**不要**當成刪除 |
| **巢狀超過 3 層** | 阻止並播報「最多 3 層」 |
| **自動捲動** | 拖到容器上下緣 40px 內時自動捲動，速度隨距離遞增；**行動裝置停用**（與頁面捲動衝突） |
| **觸控裝置** | 把手需 **長按 200ms** 才進入拖曳（避免與頁面捲動衝突）；長按時 `navigator.vibrate(10)` 給觸覺回饋 |

### 32.7 實作備註

```html
<ul class="cl-draglist" role="listbox" aria-label="選單項目">
  <li class="cl-dragrow" role="option" aria-selected="false" aria-posinset="1" aria-setsize="3">
    <button type="button" class="cl-dragrow__grip" aria-label="拖曳排序 Home"
            aria-grabbed="false" aria-describedby="drag-help">⣿</button>
    <span class="cl-dragrow__label">Home</span>
    <span class="cl-dragrow__actions">
      <button type="button" class="cl-btn cl-btn--icon" aria-label="編輯 Home">✏</button>
      <button type="button" class="cl-btn cl-btn--icon" aria-label="刪除 Home">🗑</button>
    </span>
  </li>
</ul>
<button type="button" class="cl-draglist__add">⊕ 新增選單項目</button>
<span class="sr-only" id="drag-help">按 Enter 抓取，使用上下鍵移動，再按 Enter 放下，Esc 取消。</span>
```

**常見錯誤做法**：
- ❌ 把手是裝飾 `<span>` → 鍵盤完全無法排序（**這是本元件最常見也最嚴重的錯誤**）。
- ❌ 整列可拖（沒有專用把手）→ 觸控裝置上無法捲動清單。
- ❌ drop 指示用整列反白 → 分不清插入位置。
- ❌ 逐筆 move API → 中途失敗造成順序錯亂。
- ❌ 沒有 `aria-live` 播報移動結果 → 螢幕閱讀器使用者不知道現在在第幾位。
- ❌ 觸控裝置沒有長按延遲。
- ❌ 100 項還開放拖曳。

---

# 附錄

## 附錄 A — 元件索引與來源對照

| § | 元件 | class | 主要來源 |
|---|---|---|---|
| 1 | 按鈕（7 變體＋split） | `cl-btn` / `cl-split` | 47 §3/§4/§5、44 §2.2/§18.1/§19.3 |
| 2 | 輸入框 | `cl-input` / `cl-field` | 47 §4/§5 M3、44 §19.6/§22.2 |
| 3 | Select | `cl-select` | 44 §18.2/§22.2/§22.5 |
| 4 | Checkbox | `cl-check` | 47 §4/#86、44 §3.1/§19.8 |
| 5 | Radio | `cl-radio` / `cl-radio-card` | 44 §18.2/§22.2/§22.4/§22.5 |
| 6 | Toggle | `cl-toggle` / `cl-swrow` | 44 §18.5/§18.7/§19.6 |
| 7 | Textarea | `cl-textarea` | 44 §19.6 |
| 8 | 搜尋欄 | `cl-search` | 47 §4、44 §2.1/§2.2/§19.8 |
| 9 | Filter chip | `cl-fchip` | 44 §19.8/§2.1、47 §2 |
| 10 | Saved-view tab ＋ `+` | `cl-views` | 47 §4、44 §19.9/§18.4/§19.4 |
| 11 | Badge / Pill | `cl-badge` | 44 §2.2/§3.1/§19.2/§19.4 |
| 12 | 表格 | `cl-table` | 47 §4/§1、44 §2.1/§3.1/§19.4/§19.5/§19.8 |
| 13 | 卡片（含堆疊群組） | `cl-card` / `cl-cardgroup` | 47 §2/§1/§3、44 §18.2/§19.3 |
| 14 | CollapsedEditCard | `cl-cec` | 44 §22.2、47 M4 |
| 15 | Accordion | `cl-acc` | 44 §19.1/§18.7/§19.2、47 M4 |
| 16 | Modal（含 shake） | `cl-modal` | 44 §18.2、47 §5/#88 |
| 17 | Popover / 選單 | `cl-pop` | 44 §19.8/§2.2/§21.4/§22.4、47 M5 |
| 18 | Bottom sheet | `cl-sheet` | 44 §21.2、47 M6 |
| 19 | Drawer | `cl-drawer` | 44 §0/§9、47 §0/M6/M7 |
| 20 | Toast | `cl-toast` | 23 §3、47 M6 |
| 21 | Inline banner | `cl-banner` | 44 §18.2/§19.2/§19.6 |
| 22 | 雙層 banner | `cl-banner2` | 44 §19.9、47 §2 |
| 23 | AI 建議 inline 列 | `cl-airow` | 44 §22.6/§7 |
| 24 | 空態（兩種） | `cl-empty` | 44 §22.1/§22.3/§6/§22.5 |
| 25 | 404（兩種） | `cl-404` | 44 §19.10/§22.7 |
| 26 | Save bar | `cl-savebar` | 44 §22.5 |
| 27 | 頁尾儲存鈕 | `cl-savefoot` | 44 §19.7/§22.2 |
| 28 | 編輯器頂欄儲存鈕 | `cl-editorbar` | 44 §21.1/§21.6、47 §0 |
| 29 | 麵包屑 chip | `cl-crumb` | 44 §18.1/§18.6/§19.2/§19.6/§22.6 |
| 30 | 分頁器 | `cl-pagination` | 44 §3.1/§19.4/§19.5 |
| 31 | 字元計數器 | `cl-counter` | 44 §19.6 |
| 32 | 拖曳排序列 | `cl-dragrow` | 44 §19.7/§21.3 |

## 附錄 B — 實作順序建議

1. **`tokens.css`**：§00 全部 ＋ 47 §1–§5 的原生 token。**先寫斷點常數**（PostCSS custom-media）。
2. **`base.css`**：§A.2 焦點環、§A.3 的 M1–M7 utility class ＋ reduced-motion 區塊、§A.6 的 `.cl-text`／`.cl-money`。
3. **原子元件**：§1–§7、§11（按鈕／表單／badge）。每個配 storybook 的九態 story。
4. **組合元件**：§8–§10、§13–§15、§29、§31。
5. **浮層**：§16–§20（focus trap 要抽成共用 hook）。
6. **資料展示**：§12（表格是最大的）、§30、§32。
7. **提示層**：§21–§25。
8. **存檔三模式**：§26–§28（共用同一個 dirty-state store）。

## 附錄 C — Code review 檢查清單（每個 PR 都跑）

- [ ] CSS 內無裸數值（`/:\s*-?\d+(px|rem|ms|s)\b/` 掃 diff，例外只有 `0`／`100%`／`1px` border）
- [ ] 無 `transition: all`
- [ ] 所有 transition 都對應到 M1–M7 其中一條（覆寫要註明理由）
- [ ] 九態表逐項對照，不適用的要在 storybook 標 N/A
- [ ] 每個 icon-only 按鈕有 `aria-label`
- [ ] 每個浮層有 focus trap ＋ 關閉時焦點還原
- [ ] `disabled` vs `aria-disabled` 的選擇符合 §A.1
- [ ] class 前綴 `cl-`，JS 掛勾用 `data-cl-*`
- [ ] 五個斷點都截圖比對（1440／1280／1024／768／430／360，34 §7）
- [ ] `prefers-reduced-motion` 下無位移動畫
- [ ] 上限值取自 `config/limits.yml`，未硬編
- [ ] 金額用 integer cents ＋ `.cl-money`
- [ ] 無任何第三方 class 名／選擇器／CSS 原始碼

## 附錄 D — 本文件的已知缺口（需 47 §7 桌機補測後回填）

| # | 缺口 | 影響的節 |
|---|---|---|
| D1 | 桌機控件高度階未量測（本文件沿用窄版的 24/28/32/36） | §1、§2、§8、§10、§12 |
| D2 | `--t-xl` 與 `--t-2xl` 撞值；#83 的字重降階起點未定 | §00.11、§13、§24、§29 |
| D3 | Modal 在桌機的最大寬度階未量測 | §16 |
| D4 | 設定頁雙欄寬、編輯器三欄寬未量測 | §28、§A.5 |
| D5 | 表格在寬視口下的欄位可見數與 sticky 行為未量測 | §12 |
| D6 | 常駐側欄的展開態、群組摺疊、hover/active 樣式未量測 | §19 |

---

**文件結束。** 本文件所有數值均引用 47 號 token 名或 §00 新增 token；所有元件均標明 44／47 出處；全文不含任何第三方 class 名、選擇器或 CSS 原始碼。
