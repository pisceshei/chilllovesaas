# 34 — 跨裝置響應式規格（三端共用單一真相）

> 23 號定義**值**（tokens、元件狀態、動效）；本篇定義**這些值在不同螢幕寬度怎麼變**。四個原型（平台總控後台、商家後台 v2、商家後台 v1、買家前台）已全部依本篇改造完成並通過六寬度驗證，原型的 CSS 即本規格的參考實作，兩者同步維護。
>
> 適用範圍：實作 M0 的 `tokens.css` 與元件層時，本篇的斷點與轉換規則要一併落進 React 元件；違反即驗收打回（與 23 號同級）。

## 1. 斷點（四個中斷點、六個驗證寬度）

| 代號 | 範圍 | 代表裝置 | 設計立場 |
|---|---|---|---|
| **XL** | ≥1440 | 大桌機、外接螢幕 | 與 L 相同，只是留白更寬 |
| **L** | 1280–1439 | **設計基準寬**（所有原型的原始稿） | 基準，不做任何 media query |
| **M** | 1024–1279 | 筆電、橫向平板（iPad 1024） | 收邊距、格線降階、表格改橫捲 |
| **S** | 768–1023 | 直立平板（iPad 768、Air 820） | **側欄轉抽屜**、兩欄轉單欄 |
| **XS** | 430–767 | 大手機（iPhone Pro Max 430、Plus 428） | 表格轉卡片、modal 轉貼底 sheet、字級升到 14px |
| **XXS** | ≤429 | 標準手機（iPhone 390／小 Android 360） | 全單欄、按鈕撐滿、隱藏次要標識 |

**寫法一律 `max-width` 往下適配**（desktop-first）。理由：四個原型都是以 1280 稿完成的高保真，用 min-width 重寫會動到桌面像素，而桌面是驗收基準。**桌面 ≥1280 的外觀必須與改造前逐像素相同**——這是硬約束，改造時用 computed-style 斷言鎖住。

另外兩個非寬度條件：

| 條件 | 用途 |
|---|---|
| `@media (pointer:coarse)` | 觸控命中區放大。**不可用寬度判斷觸控**——有觸控筆電也有窄視窗桌機 |
| `@media (prefers-reduced-motion:reduce)` | 動效全域降級為瞬時 |

## 2. 十條共通轉換規則（三端一致）

| # | 規則 | 斷點 | 為什麼 |
|---|---|---|---|
| 1 | 固定側欄 → off-canvas 抽屜＋頂列漢堡 | ≤1023 | 平板直立時 212px 側欄吃掉 27% 寬度 |
| 2 | 資料表 → 卡片（≤8 欄）或橫捲容器＋黏性首欄（>8 欄） | ≤767 卡片／768–1279 橫捲 | 中文 `min-content` 極小，硬擠會把「NT$2,932」折成「NT$2,93／2」 |
| 3 | 多欄格線降階 6→3→2→1、4→2→1 | 逐階 | — |
| 4 | 詳情兩欄（主＋側 300px）→ 單欄，側欄卡片移到主欄之後 | ≤1023 | 1fr+300px 在 768 會硬撐出 915px |
| 5 | 分頁標籤橫捲＋`scroll-snap`＋邊緣漸層 | ≤767 | 10 個分頁塞不進 430px |
| 6 | Modal → 貼底 sheet（上圓角、`max-height:92dvh`、內容可捲、footer sticky 且按鈕全寬） | ≤767 | 拇指可及區在下方 |
| 7 | 可點元素命中區 ≥44×44 | `pointer:coarse` | WCAG 2.5.5；**用 `::before{position:absolute;inset:-Npx}` 撐熱區，不改視覺尺寸** |
| 8 | 輸入框 `font-size:16px`、高度 40px | ≤767 | <16px 會觸發 iOS Safari 聚焦自動放大，放大後版面即錯位 |
| 9 | 所有圖片／媒體框給明確 `aspect-ratio` ＋ `object-fit:cover` | 全斷點 | 防 CLS：圖片載入前後版面位移是「錯位」的最大來源 |
| 10 | 長字串（email／網域／GID／SKU）`overflow-wrap:anywhere`；**金額與數字 `white-space:nowrap`** | 全斷點 | 兩者相反，混用會把 `NT$407,700` 折行——這是實測踩到的 bug |

**額外的通用防溢出**：所有 grid／flex 子項加 `min-width:0`（預設 `auto` 會讓子項拒絕縮小，是橫向溢出第一大成因）；`.frame`／全高容器用 `100dvh`（`100vh` fallback 在前）。

## 3. 各端的具體轉換

### 3.1 平台總控後台（`chilllove-platform-admin.html`）

| 元素 | M ≤1279 | S ≤1023 | XS ≤767 | XXS ≤429 |
|---|---|---|---|---|
| 側欄 212px | 不變 | **抽屜 250px**＋遮罩＋Esc＋焦點移入 | 同 | 同 |
| 頂列搜尋框 | 不變 | **收成 44px icon 鈕**（否則提示字被擠成直排溢出頂列） | 同 | 同 |
| KPI 六卡 | 3 欄 | 3 欄 | 2 欄 | 1 欄 |
| 可行動佇列／健康列 4 卡 | 2 欄 | 2 欄 | 2 欄 | 1 欄 |
| 看板 4 欄 | 2 欄 | 2 欄 | **1 欄** | 1 欄 |
| 租戶詳情 1fr+296px | 單欄 | 單欄，側欄群改 2 欄並排 | 側欄群 1 欄 | 同 |
| 資料表 | `min-width:max-content`＋橫捲 | 同 | **卡片化**（`td::before` 顯示欄名） | 同 |
| 十分頁標籤 | 橫捲 | 橫捲 | ＋`scroll-snap`、高 40px | 同 |
| 用量列 120/1fr/168 | 110/1fr/140 | 同 | 同 | **單欄堆疊** |
| 定義列表 `dl` 112px/1fr | 100px/1fr | 同 | 同 | **標籤上、值下** |
| Modal | 不變 | 不變 | 貼底 sheet | 同 |
| GMV 圖 x 軸刻度 | 4 個 | 4 個 | **3 個（<560）** | **2 個（<360）** |
| 頂列標識 | 全顯 | 全顯 | 隱 `demo` 徽章、人員姓名（留頭像） | 再隱 wordmark（留 mark＋平台膠囊） |

### 3.2 商家後台 v2（`chilllove-admin-v2.html`）

- **框架**：≤1023 側欄轉抽屜（`translateX(-100%)`→0，240ms；`visibility` 延遲切換讓關閉時退出 tab 序）；`go()`／`openSettings()` 自動收抽屜；跨過 1024 自動關。
- **表格**：`enhanceTables()` 以 MutationObserver 監看 `.main`，自動由 `<th>` 補 `data-label`、補 `role=table/rowgroup/row/cell`（`display` 被覆寫後保住語意）、外包橫捲容器。≤767 卡片化時 checkbox 絕對定位到卡片右上、首欄當標題、thead 只保留「全選」一行（**不可整個藏掉 thead，會遺失全選功能**）。
- **設定 overlay**：≤767 全螢幕，左欄分類轉頂部橫捲 chips，當前分頁自動 `scrollIntoView`。
- **命令面板**：≤767 改**貼頂** sheet（唯一不貼底的 modal——避開手機鍵盤）。
- **bulkbar／toast**：≤767 貼底全寬＋`env(safe-area-inset-bottom)`；bulkbar 出現時 toast 用 `:has()` 上移。
- **圖表**：依實測寬換刻度（`<300:2、<400:3、<540:4、否則 5`）與 y 軸留白（`<480` 時 48→32），resize 走 rAF 去抖重繪。

### 3.3 買家前台（`chilllove-storefront-preview.html`）

- 商品格線 `4 → 3(≤1279) → 2(≤1023)`，**≤429 保留 2 欄小卡**（單欄在手機反而浪費且瀏覽效率差）。
- 主導航 ≤767 收成左側漢堡抽屜（`min(320px,86vw)`）；768–1023 保留橫捲並加 `scroll-snap-type:x proximity` ＋**依實際溢出才掛的**邊緣漸層。
- 購物袋 drawer ≤767 全寬、`max-height:100dvh`、內容 `overscroll-behavior:contain`、結帳鈕 `position:sticky;bottom:0`＋safe-area。
- hero `h1` `clamp(32px,6.2vw,58px)`（≥1280 仍算出 58px，與原稿數學等值）。
- 區塊垂直節奏 `96 → 80(≤1023) → 68(≤767) → 56(≤429)`。
- 所有圖框（`.ph`／`.hero-art`／`.ccard`／`.story-art`／`.dr-ph`）給 `aspect-ratio`，並預寫 `img{width:100%;height:100%;object-fit:cover}`；提供可重用 `.media-frame`（`3/4`、`.r-square`、`.r-wide`）。**換真圖時仍須補 `width`/`height` 屬性與 `loading`/`fetchpriority`。**

## 4. 邊界情況（實測踩到才寫進來的）

| 情況 | 現象 | 對策 |
|---|---|---|
| 中文可任意換行 | `min-content` 極小 → 表格擠成「#104／2」 | `table{min-width:max-content}`，寧可橫捲不擠字 |
| 金額被折行 | `NT$407,700` 拆兩行 | 金額節點 `white-space:nowrap`，與長字串規則分開 |
| 混合內容的數字欄 | 「12 / 100・吃滿即 429＋Retry-After」整串 nowrap 撐破版面 | **數字與提示拆成兩個 span**：數字 nowrap、提示 `overflow-wrap:anywhere` |
| inline style 壓過 media query | 卡片在小螢幕不降階 | inline style 一律改成 class |
| 首次量測時容器 `display:none` | 橫捲漸層提示永不出現、圖表寬度算成 0 | 切頁後 `requestAnimationFrame` 重新量測 |
| 彈出層座標算成負值 | doc-pop 飛出畫面 | ≤767 改左右固定 12px；垂直用實際高度夾限 |
| 原生 checkbox 無法放大到 44 | `::before` 對 replaced element 無效；`transform:scale` 連命中區一起縮 | 外圍容器撐 44px＋**capture 階段**轉發點擊（繞過既有 `stopPropagation`） |
| hover-only 功能在觸控消失 | 快速加購按鈕、圖表 tooltip | `@media (hover:none)` 改常駐；tooltip 提供「檢視數據表格」替代 |
| 瀏海與底部手勢條 | 固定列被遮 | 固定列一律 `env(safe-area-inset-*)`；`<meta viewport>` 加 `viewport-fit=cover` |

## 5. 無障礙（隨響應式一起驗）

- 抽屜：`aria-expanded`／`aria-controls`；開啟時焦點移入首個連結、Tab 循環（focus trap）、Esc 關閉、關閉後焦點回漢堡；`body` 鎖捲動。
- 表格卡片化後補 `role=table/rowgroup/row/cell/columnheader`（`display:block` 會抹除隱含語意）。
- 觸控目標 ≥44×44（WCAG 2.5.5）；焦點環全斷點可見（2px `--focus`，offset 1px）。
- 文字對比 ≥4.5:1（tokens 已過驗證，**放大字級不得改色**）。
- `prefers-reduced-motion` 下位移動效改純 fade 或瞬時。

## 6. 驗證方法（每次改動都要跑，寫進 CI）

六個寬度 **1440 / 1280 / 1024 / 768 / 430 / 360** × 每個主要畫面 × 每個 modal／抽屜／彈出層，逐一斷言：

1. `document.documentElement.scrollWidth <= window.innerWidth + 1` —— **零橫向溢出**
2. 逐元素 `getBoundingClientRect()` 不越界（橫捲容器內元素豁免）
3. 零 console error／pageerror
4. `pointer:coarse` 下可點元素命中高度 ≥43.5px（含 `::before` 擴大量）
5. 金額 token 不跨行（`Range.getClientRects()` 量是否多於一行）
6. 圖框皆有 `aspect-ratio` 或明確尺寸
7. **桌面回歸**：1440／1280 的 computed style 與改造前逐項比對（或截圖 pixel diff）

參考實作：`/tmp/rwd/check.mjs`（斷點掃描）、`interact.mjs`（互動回歸）。M0 落地時搬進 `spec/system/responsive_spec.rb` 或 Playwright CI job。

## 7. 目前四個原型的驗證狀態

| 原型 | 1440 | 1280 | 1024 | 768 | 430 | 360 | 備註 |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| 平台總控後台（17 區＋10 分頁＋6 modal） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 觸控命中區全數 ≥44 |
| 商家後台 v2（20 畫面） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 120/120 組合 PASS；桌面 28/28 截圖 identical |
| 商家後台 v1（8 畫面） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 買家前台（3 狀態） | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 全部圖框已具 aspect-ratio |

## 8. 已知限制（誠實記錄，不要在驗收時當成 bug）

1. **1280 這一格的表格**：為守「桌面像素完全一致」，橫捲容器只在 ≤1279 生效，1280 的寬表仍可能微幅擠字。要修就得動桌面基準——需使用者決定。
2. `768–1279` 黏性首欄下方會露出被捲入欄位的殘字，是 `position:sticky` 的固有表現。
3. 卡片化捨棄了欄位表頭的視覺對齊；靠 `data-label` 補償。
4. 圖表 tooltip 仍是 hover-only，觸控替代是「檢視數據表格」。
5. `env(safe-area-inset-*)` 無法在無瀏海模擬的 headless 環境驗證，需真機複查。
6. 僅在 Chromium 驗證；Safari／Firefox 需真機或 BrowserStack 複查（`:has()`、`100dvh`、`mask-image` 有前綴 fallback，最壞只是少裝飾）。
7. 商家後台 `html{font-size:13px}` 未改（23 §1 明訂為 token）；前台為 14px。若未來要在手機統一放大，屬 token 變更，須先改 23 號。

## 9. 落到 M0 實作時的 checklist

- [ ] `tokens.css` 搬入 23 §1 的值 **＋本篇 §1 的斷點常數**（`--bp-m:1279px` 等，或 Tailwind/PostCSS 的 screens 設定）
- [ ] `AppShell` 元件內建抽屜行為（不要每頁自己寫）
- [ ] `IndexTable` 元件內建三種模式：full／橫捲＋黏性首欄／卡片，由欄數與斷點自動決定
- [ ] `Modal` 元件內建 ≤767 的 sheet 變體
- [ ] `Money` 元件強制 `nowrap`＋`tabular-nums`（防止 §4 的折行 bug 再發生）
- [ ] `Media` 元件強制要求 `aspectRatio` prop（沒給就 lint error）
- [ ] Playwright 六寬度驗證進 CI，任一組合失敗即 fail
