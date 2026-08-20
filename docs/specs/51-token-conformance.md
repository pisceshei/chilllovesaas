# 51 — 量測真值一致性稽核（47 → 23／48／34／三份原型）

> **稽核對象**：`docs/design/47-measured-interaction-spec.md` 每一個量測真值，逐項比對 `23` §1 token 表、`48` §0/§00、`34` 斷點，與三份原型 `<style>` 區塊的實際 CSS。
>
> **原型代號**：**A** = `docs/design/chilllove-admin-v2.html`（style 12–906 行）｜**P** = `docs/design/chilllove-platform-admin.html`（style 19–498 行）｜**S** = `docs/design/chilllove-storefront-v2.html`（style 8–1042 行）。
> `chilllove-admin-preview.html`／`chilllove-storefront-preview.html` 依 48 §0.10 為 deprecated，不列入六張表（僅在表 4 附記其殘留 `transition: all`）。
>
> **方法**：全部以 grep／python 逐行機械掃描，非抽樣。掃描腳本邏輯記於各表表頭。表 2／表 4 為機械產出，行號即可直接定位。
>
> ## ⚠ 基準警告（照 47 §0 執行）
>
> 1. **47 第一輪所有 `border-width` 相關數值一律作廢**（誤除 1.5，量出 `0.67px` 這種不存在的值）。本稽核凡涉及邊框，一律以 **第三輪 §C**（髮絲線 = 1 裝置像素）與 **第四輪 §H2-4**（表單框 = inset box-shadow）為準，不引用第一輪。
> 2. **47 §1–§4 的間距／字級／圓角／控件高度為 rem 類，除 1.5 正確，結論有效**，可直接當真值。
> 3. **第三輪（root=16px、桌機 2294px）與第四輪（§H2）為無須換算的設計真值**，優先級最高。
> 4. `48` 全文 **無任何** `第三輪`／`H2`／`髮絲線`／`inset box-shadow`／`caution`／`dpr` 字樣（grep 命中 0）——**48 寫在第二輪之後、第三／四輪之前**，其 §00.9 z-index、§00.13 斷點、§00.5 focus 環三處明文宣稱「47 完全沒有」，在第三／四輪之後**皆已成為錯誤前提**。詳見表 6。

## 一覽

| 表 | 內容 | 掃描量 | 不一致數 |
|---|---|---:|---:|
| **表 1** | token 定義一致性（47 → 23 §1） | 70 個量測項目 | **60**（另 部分一致 3、一致 7） |
| **表 2** | 原型硬編碼掃描（裸值） | 854 組 / 2257 處 | **854 組全部**（A 258 / P 138 / S 458；其中 off-scale 701 組） |
| **表 3** | 斷點一致性 | 28 個 `@media`（寬度型 20） | **20 / 20** |
| **表 4** | 動效一致性（M1–M7） | 186 個動效宣告片段 | **56**（69 不合規 − 13 合理豁免） |
| **表 5** | 第四輪新真值落地 | 8 項 × 3 原型 | **8 / 8 未落地**（全缺 6、部分 2） |
| **表 6** | 48 號自我宣稱查核 | 2 項宣稱 + §00 82 token | **宣稱二數字不實 + 衝突 11 條 + 命名分裂 1 項** |
| **彙總** | 優先級 | — | **P0 13｜P1 9｜P2 7** |

---

## 表 1 · token 定義一致性（47 真值 → 23 §1）

> 「23 號 token」欄寫 **無** 代表 23 §1 連敘述都沒有；寫「（敘述）」代表只有散文、沒有 token 化。
> 「原型現況」為補充欄，標示 A/P/S 是否已自行落地（三份原型的 token 層是**繞過 23 號自建的**，見表 6 §6.4）。

### 1.1 間距階（47 §1，7 階）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| `--sp-050` | 2px | 無 | （散文「4px 網格」） | ✗ | 23 §1 補 7 階 token；A/P 已自建 `--sp-050`，23 未同步 |
| `--sp-100` | 4px | 無 | 同上 | ✗ | 同上 |
| `--sp-150` | 6px | 無 | 同上 | ✗ | 同上 |
| `--sp-200` | 8px（最高頻 ×34） | （敘述） | 「表格 cell 8px 12px」 | ✗ | 同上 |
| `--sp-300` | 12px | （敘述） | 「listbar 8px 12px」 | ✗ | 同上 |
| `--sp-400` | 16px | （敘述） | 「卡 padding 16、卡間 gap 16」 | ✗ | 同上 |
| `--sp-600` | 24px | （敘述） | 「區塊間 24」 | ✗ | 同上 |
| 階外值 | 47 只用 7 階 | （敘述） | 「頁邊 32」 | ✗ | 32／48 屬版面層，須另立 `--sp-800`／`--sp-1200` 並限用於版面容器（48 §00.12 已定，23 未收） |

### 1.2 圓角階（47 §2，4 階 + 堆疊規則）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| `--r-100` | 4px | 無 | — | ✗ | 補 |
| `--r-200` | 8px（控件，×9） | `--r-btn` | 8px | ✓ 值 | 改為尺寸名 `--r-200`，保留 `--r-btn` 為別名 |
| `--r-300` | 12px（卡片，×11 最高頻） | `--r-card` | 12px | ✓ 值 | 同上 |
| `--r-400` | 18px（大容器／藥丸，×11） | 無 | — | ✗ | 補；23 只有 `--r-pill:999px`，與 18px 是兩件事 |
| 堆疊卡片單邊圓角 | `12px 12px 0 0` / `0 0 12px 12px` | 無 | — | ✗ | A 已實作 `.card-stack`（886–890，markup 用 5 次）；**P/S 無** |

### 1.3 字級階（47 §3）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| `--t-xs` | 12 / 16 / **500** | scale 有 12 | 12（badge/輔助/軸標），行高 1.45–1.6 → **17.4** | ✗ | 行高必須鎖 16；weight 綁 500 |
| `--t-sm` | 13 / 20 / 500（**UI 預設**） | scale 有 13 | 13（正文/表格/按鈕），行高 → 18.85–20.8 | ✗ | 行高鎖 20；且 23 把 13 當「正文＋表格」，47 說表格要降到 12 |
| `--t-md` | 14 / 20 / 500（**只准次要標題**） | scale 有 14 | 14「強調正文/hero 副標」 | ✗ | 語意改「次要標題」；行高鎖 20 |
| `--t-lg` | 16 / 20 / **450** | scale 有 16 | 16「保留」，無 weight | ✗ | **450 這一階 23 完全沒有**，是「原型標題過重」的根因 |
| `--t-xl` | 18 / 24 / 500 | **無** | scale 是 11/12/13/14/16/20/24，**跳過 18** | ✗ | 補 18 階 |
| `--t-2xl` | 27→18 / 24 / 500 | 無 | — | ✗ | **47 自身未解衝突**：與 `--t-xl` 撞值（48 §00.11 已標，須回 47 定案） |
| 字重 **550** | split 鈕 12/16/**550**（47 §6.5） | 無 | 23 只有 600/700 的散用 | ✗ | 47 未在 §3 收進字級表，屬遺漏；本稽核列為 **待 47 補收** |
| 字距 | 一律 `normal` | 「中文標題字距 0」 | 部分敘述 | ✗ | A `body{letter-spacing:.01em}`(66)、S 大量 `.06–.24em`；違反 47 |
| 23 多出的 11 / 20 / 24 階 | 47 未量到 | 有 | 11、20、24 | — | 11 → `--t-2xs`（48 §00.11）；20／24 應併入 `--t-3xl`(24/32/450) 並標 〔待覆核〕 |

### 1.4 控件高度階（47 §4 + §B）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| 檢視 tab 高 | **24**（內距 0/2、r8） | 無 | — | ✗ | 補 `--h-24` |
| icon 鈕 / 表頭鈕 / 搜尋欄 | **28** | （敘述） | 「按鈕高 32（sm 28）」 | ✓ 值 | token 化為 `--h-28` |
| 按鈕 / 輸入 / 表格資料列 | **32** | （敘述） | 「按鈕高 32；輸入高 32」 | ✓ 值 | token 化為 `--h-32` |
| 頂欄控件 | **36** | 無 | — | ✗ | 補 `--h-36` |
| **表格列高** | **32**（＝12/16 字 + 8×2） | （敘述） | **~40**（8px cell 上下） | ✗ | **23 錯 8px**；改 32 |
| 儲存格內距 | **6px 6px**（§B 桌機） | （敘述） | 8px 12px | ✗ | 桌機真值 6/6；A 現用 `--sp-200/--sp-300`(8/12) |
| checkbox | **16 × 16** ＋列級 32 命中區 | 無 | §4.8 只有「觸控 ≥44px」原則 | ✗ | A 已實作（216–217、606–607）、P 用 `.chk input::before`、**S 無** |
| 頂欄高 | **56** | （佈局常數） | **52** | ✗ | **23 錯 4px**；A 仍硬編 52（75、92、379、424、426、796），P `--topbar-h:52px`(52) |
| 側欄寬 | **240** | （佈局常數） | **220** | ✗ | A `.sidebar{width:220px}`(93)；P `--sidebar-w:212px`(52) |
| 頂欄搜尋框 | **640 × 36**，r**12** | （敘述） | max-width **600** | ✗ | A `.searchbox{max-width:600px}`(79)、圓角 `--r-200`(8)；P 560(86) |
| 頂欄圖示鈕 | **36 × 36**，r**12** | 無 | — | ✗ | A/P `.icon-btn` 都是 `--h-28` + r8（A:83、P:90） |
| 導航一級項 | 高 **28**，r8 | （敘述） | nav-item 高 **30**（6px 上下 padding） | ✗ | A `.nav-item` 實高 = 20 行高 + 6×2 = **32**（94） |
| 導航二級項 | **218 × 28**，r8，**縮排 22** | （敘述） | 子項縮排 **36px** | ✗ | A `.nav-sub` padding-left `calc(--sp-300*3)` = **36**（100） |
| 導航分組標題鈕 | **76 × 24**，r8 | 無 | — | ✗ | 補 |
| 徽章高 | **20** | 「Badge 高 20」 | 20 | ✓ | A(133)/P(160) 皆硬編 `20px`，需 token 化 |
| **列分隔線** | **0.667px** `#E3E3E3`（＝1 裝置像素） | `--border-2` | `#ececef` @ 1px | ✗ | 見表 5 項 1；**三份原型合計 199 條 1px 邊框宣告** |

### 1.5 動效（47 §5：5 時長 × 3 曲線 + M1–M7）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| `--dur-fast` | 100ms | 無 | — | ✗ | 補 |
| `--dur-base` | 150ms | `--tr` 的時長 | 150ms | ✓ 值 | 時長對、**曲線錯** |
| `--dur-slow` | 200ms | 無 | 「menu/popover 120–160ms」 | ✗ | 23 §5 該列作廢 |
| `--dur-slower` | 250ms | 無 | `--tr-big` = 240ms | ✗ | 240 → 250 |
| `--dur-slowest` | 300ms | 無 | — | ✗ | 補 |
| `--ease-standard` | `cubic-bezier(.25,.1,.25,1)` | `--tr` 的曲線 | `cubic-bezier(.2,.6,.3,1)` | ✗ | 自創值，作廢 |
| `--ease-in-out` | `cubic-bezier(.42,0,.58,1)` | 無 | — | ✗ | 補 |
| `--ease-decelerate` | `cubic-bezier(.19,.91,.38,1)` | `--tr-big` 的曲線 | `cubic-bezier(.2,.8,.2,1)` | ✗ | 自創值，作廢 |
| **M1–M7 七條具名規則** | 見 47 §5 | 無 | §5 為 9 列「場景 → 時長」自創表 | ✗ | 23 §5 整表作廢，只保留 shimmer 1.2s、條圖 500ms |
| Modal 驗證失敗 **shake** | 有（實站 keyframes） | 無 | — | ✗ | A 有 `@keyframes nudge`(686) 但只綁 savebar，**未接 modal**、未改名 `cl-shake` |
| `prefers-reduced-motion` | 47 未定（§7 待辦 13） | 有 | 「位移改純 fade」 | — | 三份原型皆有實作（A:616/625、P:495、S:1033） |

### 1.6 中性色階與按鈕層級（47 §6、§6.5、§D、§E）

| 47 號項目 | 真值（關係） | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| 頁底 < 卡片 | `#F1F1F1` < `#FFFFFF` | `--bg` / `--surface` | `#f4f4f5` / `#fff` | ✓ | 關係成立 |
| 主 / 次文字兩級 | `#303030` / `#616161` | `--text` / `--text-2` | `#1a1c1e` / `#6b6d71` | ✓ | 關係成立 |
| **次級按鈕底比頁底深一階** | `#E3E3E3` > `#F1F1F1` | `--surface-2` | `#f7f7f8`（**比 `--bg` 淺**） | ✗ | **層級反轉**；需 `--surface-sunken`（48 §00.6 已提，**未落地任一原型**） |
| 圖示灰獨立一階 | `#4A4A4A` | 無 | — | ✗ | 補 |
| 深底上的文字階 | `#DCDCDC` | 無 | — | ✗ | 補 `--text-inverse`（48 §00.6 已提，未落地） |
| 三層按鈕**只靠填色深淺**分層 | primary 深實心／split 淺灰實心／tertiary 淺灰實心，**等高等圓角、無邊框** | §3 Button | 「sec（白 + `#c9cace` 框）」 | ✗ | **方向錯**：A `.btn-sec{background:#fff;border-color:#c9cace}`(121)、P 同 |
| 次級按鈕立體配方 | 白底 + `inset 0 -1px 0 #B5B5B5` + 外投影 | 無 | 只有純邊框 | ✗ | A `.btn-sec` 只有 `0 1px 2px rgba(26,28,30,.06)`(121)，缺底緣內陰影 |
| **disabled** | 只降文字色到 `#B5B5B5`，**底色不動** | §3 Button | `:disabled{opacity:.45}` | ✗ | 見表 5 項 4 |

### 1.7 斷點 / z-index / 語意色 / focus / 表單控件（47 §F、§G、§H2）

| 47 號項目 | 真值 | 23 號 token | 23 號值 | 一致? | 處置 |
|---|---|---|---|:--:|---|
| 斷點階梯 | **8 階 em**：360/490/667/768/1040/1200/1440/2560，主斷點 **768** | 無（在 34 §1） | 34 為 **4 階 px**：1279/1023/767/429 | ✗ | 見表 3 |
| z-index 階梯 | `1 / 100 / 400 / 510 / 517 / 518 / 519 / 520` | （敘述） | `0<3<40<50<70<80<90<95` | ✗ | 見表 5 項 7 |
| 語意色族 | **5 族**：info/success/**caution**/**warning**/critical | 5 族 + ai | success/warning/critical/**attention**/info/ai | ✗ | **caution 與 warning 分家**；`attention` 命名須確定是否等同 `caution`（grep：三份原型 `caution` 命中 **0**） |
| 語意色層 | **5 層**：bg-surface / bg-fill / border / icon / text | 2 層 | `--x` + `--x-bg` | ✗ | 缺 fill / border / icon 三層（48 §00.7 只補了 border 一層） |
| 語意色態 | **3 態**：base / hover / active（surface L 94–97%，hover −2~3，active −4~7） | 1 態 | 無 hover/active | ✗ | 缺 |
| 語意色 token 總數 | **75**（5×5×3） | **12**（6 族 × 2 層） | — | ✗ | 缺 63 個 |
| critical 例外 | 多 `button-bg-fill` + `button-gradient-bg-fill` | 無 | — | ✗ | 補 2 個 |
| scrim 不透明度 | **`rgba(0,0,0,.5)`** | §3 Modal | `rgba(26,28,30,.4)` | ✗ | A(336) `.4`／A(379) `.42`／P(328) `.4`／P(376) `.42`／S(96,251) `.45` |
| **focus 環實作** | `outline: none` ＋ **雙層 box-shadow**（2px 間隙 + 4px 環） | §3 | 「焦點環 2px `--focus` **offset 1px**」（＝outline） | ✗ | 見表 5 項 5 |
| **表單控件框** | **`inset box-shadow`**，非 `border` | §3 輸入框 | 「框 `#c9cace`」（border） | ✗ | 見表 5 項 2 |
| radio 尺寸／已選 | 16×16；已選＝**主文字色填滿 + 白內點** | 無 | — | ✗ | 見表 5 項 3 |
| badge 狀態圖示 | **● 實心／○ 空心／⊘ 斜線** | §3 Badge | 「空圈/**半圈**/實圈」 | ~ | 概念一致、**⊘ 形狀不同**（現為半填漸層） |
| badge vs tag | badge = r≈8 圓角矩形 + 圖示；tag = **全圓藥丸**、無圖示、`+n` 收合 | §3 Badge | 「高 20、**r-pill**」 | ✗ | **badge 被畫成 tag**；tag 元件不存在 |
| 髮絲線 | 1 **裝置**像素（dpr 三檔） | 無 | — | ✗ | 見表 5 項 1 |

**表 1 統計**：共比對 **70** 個 47 號量測項目 → **一致 7**（`--r-btn`8、`--r-card`12、控件 28、控件 32、badge 高 20、頁底<卡片、主/次文字兩級）、**部分一致 3**（`--dur-base` 時長對曲線錯、badge 狀態圖示概念對形狀錯、idle 文字色關係對色值不同）、**不一致 60**。

---

## 表 2 · 原型硬編碼掃描（沒有走 `var()` 的裸值）

> **掃描規則**：取每份原型 `<style>` 區塊 → 去除 `/* */` 註解 → 排除 `:root{}` 內的 token 定義本身 → 排除 `@media` 條件式（48 例外 3）→ 對每一條 `property: value` 宣告比對五種裸值 pattern：`\d+px`（排除 `0`）、`#hex`、`rgba()/rgb()`、`cubic-bezier()`、`\d+(ms|s)`（排除 `0`）。
>
> **行號欄列出該（屬性,裸值）組合出現的全部行號**，無省略、無抽樣。同一行有多個裸值會在多列各自出現。
>
> **掃描結果**：A **258** 組 / **578** 處｜P **138** 組 / **226** 處｜S **458** 組 / **1453** 處 → **合計 854 組 / 2257 處裸值**。
>
> **標記說明**：`〔off-scale …〕` = 該值不在 47 的階梯上，改 token 時視覺會位移，須逐一目視確認；`〔…未落地〕` = 48 §00 已提議該 token 但三份原型 `:root` 都沒有它（見表 6 §6.4）。

### 2.A　`chilllove-admin-v2.html`（商家後台 v2）

> 258 組 / 578 處，其中 **216 組** 為 off-scale 或需新增 token。

| 檔案 | 行號 | 屬性 | 裸值 | 應改用的 token |
|---|---|---|---|---|
| A | 652 707 | `background-position` | `9px` | 需 token 化〔9px〕 |
| A | 85 134 737 792 | `border` | `1.5px` | --bw-* 階外〔1.5px〕 |
| A | 79 81 86 89 117 129 144 148 149 170 176 180 195 197 204 229 232 249 264 297 305 308 311 322 324 502 542 699 704 724 730 742 745 749 751 754 759 766 781 787 795 796 803 808 | `border` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 261 | `border` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| A | 75 157 194 207 209 241 265 318 339 341 349 636 670 710 771 815 | `border-bottom` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 638 | `border-bottom` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| A | 128 | `border-left` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 78 99 133 180 182 330 408 542 551 665 718 806 807 | `border-radius` | `999px` | --r-pill〔A/S 未定義，需補〕 |
| A | 93 700 | `border-right` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 106 233 247 294 315 354 510 553 659 713 | `border-top` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 504 888 890 | `border-top-width` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 536 | `border-width` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 833 | `bottom` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| A | 260 299 567 | `bottom` | `12px` | --sp-300 |
| A | 826 | `bottom` | `16px` | --sp-400 |
| A | 361 | `bottom` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| A | 355 676 | `bottom` | `24px` | --sp-600 |
| A | 570 | `bottom` | `78px` | --sp-600（24px）〔off-scale 78px〕 |
| A | 836 | `bottom` | `86px` | --sp-600（24px）〔off-scale 86px〕 |
| A | 197 355 678 | `box-shadow` | `12px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 363 427 | `box-shadow` | `16px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 96 103 119 121 261 325 690 709 733 782 | `box-shadow` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 220 338 348 361 | `box-shadow` | `24px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 563 | `box-shadow` | `26px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 96 103 119 121 146 648 690 726 753 761 | `box-shadow` | `2px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 197 355 678 | `box-shadow` | `32px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 171 733 | `box-shadow` | `3px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 427 | `box-shadow` | `44px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 363 | `box-shadow` | `48px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 338 348 | `box-shadow` | `64px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 220 361 | `box-shadow` | `8px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| A | 732 | `font-size` | `10px` | --t-xs（12px）〔off-scale 10px〕 |
| A | 78 81 88 89 99 104 182 256 310 316 350 354 645 733 737 754 764 791 805 820 | `font-size` | `11px` | --t-2xs〔48 §00.11，未落地〕 |
| A | 577 578 | `font-size` | `16px` | --t-lg |
| A | 464 | `font-size` | `17px` | --t-lg（16px）〔off-scale 17px〕 |
| A | 473 | `font-size` | `19px` | --t-xl（18px）〔off-scale 19px〕 |
| A | 113 283 327 464 | `font-size` | `20px` | --t-xl（18px）〔off-scale 20px〕 |
| A | 484 | `font-size` | `22px` | --t-xl（18px）〔off-scale 22px〕 |
| A | 168 275 473 | `font-size` | `24px` | --t-xl（18px）〔off-scale 24px〕 |
| A | 838 | `grid-template-columns` | `120px` | 版面常數需具名 token〔120px〕 |
| A | 786 | `grid-template-columns` | `136px` | 版面常數需具名 token〔136px〕 |
| A | 780 | `grid-template-columns` | `190px` | 版面常數需具名 token〔190px〕 |
| A | 794 | `grid-template-columns` | `240px` | 版面常數需具名 token〔240px〕 |
| A | 239 | `grid-template-columns` | `300px` | 版面常數需具名 token〔300px〕 |
| A | 748 | `grid-template-columns` | `34px` | 版面常數需具名 token〔34px〕 |
| A | 837 | `grid-template-columns` | `76px` | 版面常數需具名 token〔76px〕 |
| A | 729 | `grid-template-columns` | `88px` | 版面常數需具名 token〔88px〕 |
| A | 802 | `grid-template-columns` | `96px` | 版面常數需具名 token〔96px〕 |
| A | 150 | `height` | `14px` | 版面常數需具名 token〔14px〕 |
| A | 186 216 288 289 331 606 667 | `height` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| A | 322 | `height` | `18px` | 版面常數需具名 token〔18px〕 |
| A | 698 | `height` | `1px` | 版面常數需具名 token〔1px〕 |
| A | 133 182 330 665 | `height` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| A | 235 733 | `height` | `22px` | 版面常數需具名 token〔22px〕 |
| A | 77 88 | `height` | `24px` | --h-24 |
| A | 172 | `height` | `26px` | 版面常數需具名 token〔26px〕 |
| A | 343 | `height` | `34px` | 版面常數需具名 token〔34px〕 |
| A | 148 | `height` | `36px` | --h-36 |
| A | 575 | `height` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| A | 812 | `height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| A | 551 | `height` | `4px` | --sp-100（尺寸借間距階） |
| A | 75 92 424 796 | `height` | `52px` | 版面常數需具名 token〔52px〕 |
| A | 806 | `height` | `6px` | --sp-150（尺寸借間距階） |
| A | 85 134 298 818 | `height` | `7px` | 版面常數需具名 token〔7px〕 |
| A | 191 | `height` | `84px` | 版面常數需具名 token〔84px〕 |
| A | 165 261 300 407 717 | `height` | `8px` | --sp-200（尺寸借間距階） |
| A | 187 | `inset` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| A | 379 | `inset` | `52px` | --sp-600（24px）〔off-scale 52px〕 |
| A | 833 | `left` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| A | 220 567 | `left` | `12px` | --sp-300 |
| A | 299 | `left` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| A | 259 | `left` | `15px` | --sp-400（16px）〔off-scale 15px〕 |
| A | 333 669 | `left` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| A | 361 | `left` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| A | 331 667 | `left` | `2px` | --sp-050 |
| A | 415 | `left` | `36px` | --sp-600（24px）〔off-scale 36px〕 |
| A | 732 | `left` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| A | 571 | `left` | `8px` | --sp-200 |
| A | 113 283 327 464 | `line-height` | `24px` | --lh-xl |
| A | 484 | `line-height` | `28px` | --lh-xl（24px）〔off-scale 28px〕 |
| A | 168 275 473 | `line-height` | `32px` | --lh-xl（24px）〔off-scale 32px〕 |
| A | 776 | `max-height` | `520px` | 版面常數需具名 token〔520px〕 |
| A | 108 | `max-width` | `1200px` | 版面常數需具名 token〔1200px〕 |
| A | 573 | `max-width` | `24px` | --h-24 |
| A | 363 | `max-width` | `380px` | 版面常數需具名 token〔380px〕 |
| A | 361 | `max-width` | `400px` | 版面常數需具名 token〔400px〕 |
| A | 79 | `max-width` | `600px` | 版面常數需具名 token〔600px〕 |
| A | 170 176 | `max-width` | `640px` | 版面常數需具名 token〔640px〕 |
| A | 448 | `max-width` | `660px` | 版面常數需具名 token〔660px〕 |
| A | 110 904 | `max-width` | `998px` | 版面常數需具名 token〔998px〕 |
| A | 184 | `min-height` | `168px` | 版面常數需具名 token〔168px〕 |
| A | 252 | `min-height` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| A | 490 | `min-height` | `240px` | 版面常數需具名 token〔240px〕 |
| A | 297 | `min-height` | `320px` | 版面常數需具名 token〔320px〕 |
| A | 600 | `min-height` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| A | 597 599 601 612 857 858 866 868 869 871 872 875 876 877 | `min-height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| A | 649 | `min-height` | `70px` | 版面常數需具名 token〔70px〕 |
| A | 752 | `min-height` | `92px` | 版面常數需具名 token〔92px〕 |
| A | 712 | `min-width` | `120px` | 版面常數需具名 token〔120px〕 |
| A | 197 | `min-width` | `170px` | 版面常數需具名 token〔170px〕 |
| A | 182 | `min-width` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| A | 289 | `min-width` | `2px` | --sp-050（尺寸借間距階） |
| A | 597 601 602 859 863 865 866 867 868 875 | `min-width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| A | 489 | `min-width` | `58px` | 版面常數需具名 token〔58px〕 |
| A | 724 | `min-width` | `64px` | 版面常數需具名 token〔64px〕 |
| A | 359 | `outline` | `1.5px` | --focus-ring-w〔48 §00.5，未落地〕 |
| A | 70 731 735 | `outline` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| A | 70 | `outline-offset` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| A | 359 | `outline-offset` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| A | 367 534 833 | `right` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| A | 220 449 567 | `right` | `12px` | --sp-300 |
| A | 826 | `right` | `16px` | --sp-400 |
| A | 305 | `right` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| A | 676 | `right` | `24px` | --sp-600 |
| A | 733 | `right` | `4px` | --sp-100 |
| A | 85 | `right` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| A | 520 571 | `right` | `8px` | --sp-200 |
| A | 305 | `top` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| A | 331 667 | `top` | `2px` | --sp-050 |
| A | 733 | `top` | `4px` | --sp-100 |
| A | 426 | `top` | `52px` | --sp-600（24px）〔off-scale 52px〕 |
| A | 85 534 732 | `top` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| A | 571 | `top` | `60px` | --sp-600（24px）〔off-scale 60px〕 |
| A | 220 449 | `top` | `6px` | --sp-150 |
| A | 367 550 799 | `top` | `8px` | --sp-200 |
| A | 520 | `top` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| A | 678 | `transform` | `120px` | 位移量需 token 化〔120px〕 |
| A | 111 | `transform` | `3px` | 位移量需 token 化〔3px〕 |
| A | 686 | `transform` | `5px` | 位移量需 token 化〔5px〕 |
| A | 355 | `transform` | `80px` | 位移量需 token 化〔80px〕 |
| A | 568 | `transform` | `90px` | 位移量需 token 化〔90px〕 |
| A | 383 | `width` | `130px` | 版面常數需具名 token〔130px〕 |
| A | 202 | `width` | `14px` | 版面常數需具名 token〔14px〕 |
| A | 186 216 331 606 667 | `width` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| A | 93 | `width` | `220px` | 版面常數需具名 token〔220px〕 |
| A | 235 733 | `width` | `22px` | 版面常數需具名 token〔22px〕 |
| A | 447 | `width` | `230px` | 版面常數需具名 token〔230px〕 |
| A | 77 88 409 | `width` | `24px` | --h-24 |
| A | 172 322 | `width` | `26px` | 版面常數需具名 token〔26px〕 |
| A | 308 | `width` | `270px` | 版面常數需具名 token〔270px〕 |
| A | 426 | `width` | `272px` | 版面常數需具名 token〔272px〕 |
| A | 259 | `width` | `2px` | --sp-050（尺寸借間距階） |
| A | 384 775 | `width` | `32px` | --h-32 |
| A | 343 | `width` | `34px` | 版面常數需具名 token〔34px〕 |
| A | 148 330 435 551 665 | `width` | `36px` | --h-36 |
| A | 812 | `width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| A | 338 | `width` | `520px` | 版面常數需具名 token〔520px〕 |
| A | 796 | `width` | `52px` | 版面常數需具名 token〔52px〕 |
| A | 348 | `width` | `560px` | 版面常數需具名 token〔560px〕 |
| A | 317 | `width` | `660px` | 版面常數需具名 token〔660px〕 |
| A | 588 | `width` | `72px` | 版面常數需具名 token〔72px〕 |
| A | 775 | `width` | `760px` | 版面常數需具名 token〔760px〕 |
| A | 85 134 298 818 | `width` | `7px` | 版面常數需具名 token〔7px〕 |
| A | 488 | `width` | `82px` | 版面常數需具名 token〔82px〕 |
| A | 191 | `width` | `84px` | 版面常數需具名 token〔84px〕 |
| A | 287 | `width` | `88px` | 版面常數需具名 token〔88px〕 |
| A | 165 261 300 | `width` | `8px` | --sp-200（尺寸借間距階） |
| A | 290 | `width` | `90px` | 版面常數需具名 token〔90px〕 |
| A | 813 | `background` | `#12181f` | 23 §1 無此色，需新增或改用既有階〔#12181f〕 |
| A | 297 | `background` | `#191a1c` | 23 §1 無此色，需新增或改用既有階〔#191a1c〕 |
| A | 220 285 355 363 677 | `background` | `#1a1b1d` | --surface-inverse〔48 §00.6，未落地〕 |
| A | 88 | `background` | `#1f8a7d` | 23 §1 無此色，需新增或改用既有階〔#1f8a7d〕 |
| A | 813 | `background` | `#22364d` | 23 §1 無此色，需新增或改用既有階〔#22364d〕 |
| A | 165 | `background` | `#22a06b` | 23 §1 無此色，需新增或改用既有階〔#22a06b〕 |
| A | 322 | `background` | `#3a5ba0` | 23 §1 無此色，需新增或改用既有階〔#3a5ba0〕 |
| A | 88 | `background` | `#57c4b8` | 23 §1 無此色，需新增或改用既有階〔#57c4b8〕 |
| A | 172 | `background` | `#6d28d9` | --ai |
| A | 172 | `background` | `#8b5cf6` | 23 §1 無此色，需新增或改用既有階〔#8b5cf6〕 |
| A | 691 | `background` | `#93131f` | 23 §1 無此色，需新增或改用既有階〔#93131f〕 |
| A | 77 | `background` | `#a9502c` | 23 §1 無此色，需新增或改用既有階〔#a9502c〕 |
| A | 261 | `background` | `#b9bac0` | 23 §1 無此色，需新增或改用既有階〔#b9bac0〕 |
| A | 322 | `background` | `#c33` | 23 §1 無此色，需新增或改用既有階〔#c33〕 |
| A | 330 665 | `background` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| A | 85 | `background` | `#d03b3b` | 23 §1 無此色，需新增或改用既有階〔#d03b3b〕 |
| A | 408 718 | `background` | `#d2d3d7` | 23 §1 無此色，需新增或改用既有階〔#d2d3d7〕 |
| A | 236 | `background` | `#e0d5fb` | 23 §1 無此色，需新增或改用既有階〔#e0d5fb〕 |
| A | 795 | `background` | `#e2d6c6` | 23 §1 無此色，需新增或改用既有階〔#e2d6c6〕 |
| A | 186 | `background` | `#e3e3e6` | --border |
| A | 99 | `background` | `#e8e8ea` | --surface-hover〔48 §00.6，未落地〕 |
| A | 77 | `background` | `#e9b8a2` | 23 §1 無此色，需新增或改用既有階〔#e9b8a2〕 |
| A | 685 | `background` | `#e9e9eb` | --surface-sunken〔48 §00.6，未落地〕 |
| A | 234 | `background` | `#ece4ff` | 23 §1 無此色，需新增或改用既有階〔#ece4ff〕 |
| A | 95 101 | `background` | `#ededee` | --surface-hover〔48 §00.6，未落地〕 |
| A | 150 | `background` | `#ededef` | 23 §1 無此色，需新增或改用既有階〔#ededef〕 |
| A | 143 | `background` | `#eeeef0` | 23 §1 無此色，需新增或改用既有階〔#eeeef0〕 |
| A | 80 | `background` | `#f0f0f2` | --surface-hover〔48 §00.6，未落地〕 |
| A | 212 419 508 | `background` | `#f0f5ff` | --selected-bg〔48 §00.6，未落地〕 |
| A | 793 | `background` | `#f5f9ff` | 23 §1 無此色，需新增或改用既有階〔#f5f9ff〕 |
| A | 795 | `background` | `#f6f1e9` | 23 §1 無此色，需新增或改用既有階〔#f6f1e9〕 |
| A | 150 | `background` | `#f6f6f7` | 23 §1 無此色，需新增或改用既有階〔#f6f6f7〕 |
| A | 93 | `background` | `#f7f7f8` | --surface-2 |
| A | 738 | `background` | `#f7faff` | 23 §1 無此色，需新增或改用既有階〔#f7faff〕 |
| A | 817 | `background` | `#f7fbff` | 23 §1 無此色，需新增或改用既有階〔#f7fbff〕 |
| A | 211 418 | `background` | `#fafafc` | --surface-hover〔48 §00.6，未落地〕 |
| A | 75 81 96 103 121 144 170 180 187 195 197 204 229 249 305 308 322 331 338 348 417 502 507 553 559 667 684 692 699 704 725 726 742 749 754 759 766 781 787 845 | `background` | `#fff` | --surface |
| A | 297 | `border` | `#232427` | 23 §1 無此色，需新增或改用既有階〔#232427〕 |
| A | 144 204 737 751 792 | `border` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| A | 176 | `border` | `#e2d9f8` | 23 §1 無此色，需新增或改用既有階〔#e2d9f8〕 |
| A | 149 | `border` | `#f2c4cb` | 23 §1 無此色，需新增或改用既有階〔#f2c4cb〕 |
| A | 264 | `border` | `#f2e3b3` | 23 §1 無此色，需新增或改用既有階〔#f2e3b3〕 |
| A | 85 261 | `border` | `#fff` | --surface |
| A | 145 | `border-color` | `#a9aaae` | 23 §1 無此色，需新增或改用既有階〔#a9aaae〕 |
| A | 508 | `border-color` | `#b9cdf5` | 23 §1 無此色，需新增或改用既有階〔#b9cdf5〕 |
| A | 783 | `border-color` | `#bfe0d3` | 23 §1 無此色，需新增或改用既有階〔#bfe0d3〕 |
| A | 121 181 725 788 845 | `border-color` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| A | 755 | `border-color` | `#cfe3f2` | 23 §1 無此色，需新增或改用既有階〔#cfe3f2〕 |
| A | 80 | `border-color` | `#d5d5d9` | 23 §1 無此色，需新增或改用既有階〔#d5d5d9〕 |
| A | 692 750 | `border-color` | `#e6b3bc` | 23 §1 無此色，需新增或改用既有階〔#e6b3bc〕 |
| A | 233 | `border-top` | `#e2d9f8` | 23 §1 無此色，需新增或改用既有階〔#e2d9f8〕 |
| A | 810 | `color` | `#0a7a5c` | --success |
| A | 809 | `color` | `#1a0dab` | 23 §1 無此色，需新增或改用既有階〔#1a0dab〕 |
| A | 684 733 | `color` | `#1a1b1d` | --surface-inverse〔48 §00.6，未落地〕 |
| A | 94 312 | `color` | `#3f4144` | 23 §1 無此色，需新增或改用既有階〔#3f4144〕 |
| A | 99 143 | `color` | `#55575b` | 23 §1 無此色，需新增或改用既有階〔#55575b〕 |
| A | 100 | `color` | `#5c5e62` | 23 §1 無此色，需新增或改用既有階〔#5c5e62〕 |
| A | 235 | `color` | `#8b7bb8` | 23 §1 無此色，需新增或改用既有階〔#8b7bb8〕 |
| A | 367 | `color` | `#9a9ba0` | 23 §1 無此色，需新增或改用既有階〔#9a9ba0〕 |
| A | 366 | `color` | `#b7a5ec` | 23 §1 無此色，需新增或改用既有階〔#b7a5ec〕 |
| A | 299 | `color` | `#c9cacd` | 23 §1 無此色，需新增或改用既有階〔#c9cacd〕 |
| A | 225 | `color` | `#e6e7e9` | 23 §1 無此色，需新增或改用既有階〔#e6e7e9〕 |
| A | 363 | `color` | `#e8e9ea` | 23 §1 無此色，需新增或改用既有階〔#e8e9ea〕 |
| A | 88 119 172 174 182 220 285 355 361 365 368 543 677 682 690 703 732 | `color` | `#fff` | --surface |
| A | 566 | `background` | `rgba(255,255,255,.12)` | 高光層需 token 化 |
| A | 682 | `background` | `rgba(255,255,255,.14)` | 高光層需 token 化 |
| A | 226 | `background` | `rgba(255,255,255,.15)` | 高光層需 token 化 |
| A | 683 | `background` | `rgba(255,255,255,.24)` | 高光層需 token 化 |
| A | 733 | `background` | `rgba(255,255,255,.92)` | 高光層需 token 化 |
| A | 124 | `background` | `rgba(26,28,30,.06)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 410 | `background` | `rgba(26,28,30,.10)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 336 | `background` | `rgba(26,28,30,.4)` | --scrim〔48 §00.6，未落地〕；47 §H2-2 真值 rgba(0,0,0,.5) |
| A | 379 | `background` | `rgba(26,28,30,.42)` | --scrim〔48 §00.6，未落地〕；47 §H2-2 真值 rgba(0,0,0,.5) |
| A | 732 | `background` | `rgba(26,28,30,.72)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 410 | `background` | `rgba(26,28,30,0)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 682 | `border-color` | `rgba(255,255,255,.3)` | 高光層需 token 化 |
| A | 128 | `border-left` | `rgba(255,255,255,.25)` | 高光層需 token 化 |
| A | 733 | `box-shadow` | `rgba(0,0,0,.18)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 361 | `box-shadow` | `rgba(109,40,217,.35)` | 需 token 化〔rgba(109,40,217,.35)〕 |
| A | 648 | `box-shadow` | `rgba(179,23,44,.14)` | 需 token 化〔rgba(179,23,44,.14)〕 |
| A | 119 | `box-shadow` | `rgba(255,255,255,.12)` | 高光層需 token 化 |
| A | 690 | `box-shadow` | `rgba(255,255,255,.14)` | 高光層需 token 化 |
| A | 121 | `box-shadow` | `rgba(26,28,30,.06)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 96 103 | `box-shadow` | `rgba(26,28,30,.08)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 197 | `box-shadow` | `rgba(26,28,30,.16)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 119 427 690 | `box-shadow` | `rgba(26,28,30,.2)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 563 | `box-shadow` | `rgba(26,28,30,.3)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 220 338 348 678 | `box-shadow` | `rgba(26,28,30,.35)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 355 | `box-shadow` | `rgba(26,28,30,.4)` | --scrim〔48 §00.6，未落地〕；47 §H2-2 真值 rgba(0,0,0,.5) |
| A | 363 | `box-shadow` | `rgba(26,28,30,.5)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| A | 171 | `box-shadow` | `rgba(42,120,214,.14)` | --focus-glow〔48 §00.5，未落地〕 |
| A | 146 726 753 761 | `box-shadow` | `rgba(42,120,214,.18)` | --focus-glow〔48 §00.5，未落地〕 |
| A | 220 | `animation` | `.16s` | --dur-base（150ms）〔不在 47 §5 五時長內：.16s〕 |
| A | 109 304 | `animation` | `.18s` | --dur-slow（200ms）〔不在 47 §5 五時長內：.18s〕 |
| A | 177 | `animation` | `.2s` | --dur-slow |
| A | 687 | `animation` | `.3s` | --dur-slowest |
| A | 150 | `animation` | `1.2s` | --dur-shimmer〔48 §00.10，未落地〕 |
| A | 165 | `animation` | `2s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：2s〕 |
| A | 289 807 | `transition` | `500ms` | --dur-bar-grow〔48 §00.10，未落地〕 |
| A | 617 | `transition-duration` | `.01ms` | reduced-motion 歸零值，可留（建議 0s） |

### 2.P　`chilllove-platform-admin.html`（平台總控後台）

> 138 組 / 226 處，其中 **110 組** 為 off-scale 或需新增 token。

| 檔案 | 行號 | 屬性 | 裸值 | 應改用的 token |
|---|---|---|---|---|
| P | 161 275 | `border` | `1.6px` | --bw-* 階外〔1.6px〕 |
| P | 85 86 88 123 139 154 174 182 192 223 304 322 436 | `border` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 125 206 214 220 230 231 243 288 310 333 440 | `border-bottom` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 244 | `border-bottom` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| P | 182 | `border-left` | `3px` | --bw-* 階外〔3px〕 |
| P | 100 | `border-right` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 259 339 | `border-top` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 279 | `border-width` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| P | 458 | `bottom` | `16px` | --sp-400 |
| P | 352 | `bottom` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| P | 341 | `bottom` | `24px` | --sp-600 |
| P | 354 | `box-shadow` | `16px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| P | 141 284 | `box-shadow` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 352 | `box-shadow` | `24px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| P | 156 284 | `box-shadow` | `2px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| P | 354 | `box-shadow` | `48px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| P | 352 | `box-shadow` | `8px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| P | 415 | `font-size` | `17px` | --t-lg（16px）〔off-scale 17px〕 |
| P | 189 200 415 | `font-size` | `20px` | --t-xl（18px）〔off-scale 20px〕 |
| P | 177 | `font-size` | `22px` | --t-xl（18px）〔off-scale 22px〕 |
| P | 409 | `grid-template-columns` | `100px` | 版面常數需具名 token〔100px〕 |
| P | 408 | `grid-template-columns` | `110px` | 版面常數需具名 token〔110px〕 |
| P | 253 | `grid-template-columns` | `112px` | 版面常數需具名 token〔112px〕 |
| P | 258 | `grid-template-columns` | `120px` | 版面常數需具名 token〔120px〕 |
| P | 408 | `grid-template-columns` | `140px` | 版面常數需具名 token〔140px〕 |
| P | 258 | `grid-template-columns` | `168px` | 版面常數需具名 token〔168px〕 |
| P | 212 | `grid-template-columns` | `296px` | 版面常數需具名 token〔296px〕 |
| P | 280 | `height` | `1.5px` | 版面常數需具名 token〔1.5px〕 |
| P | 193 | `height` | `10px` | 版面常數需具名 token〔10px〕 |
| P | 284 346 | `height` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| P | 160 275 283 314 | `height` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| P | 83 95 | `height` | `24px` | --h-24 |
| P | 423 431 | `height` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| P | 484 485 | `height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| P | 92 260 | `height` | `6px` | --sp-150（尺寸借間距階） |
| P | 161 269 | `height` | `8px` | --sp-200（尺寸借間距階） |
| P | 458 460 461 | `left` | `12px` | --sp-300 |
| P | 286 | `left` | `16px` | --sp-400 |
| P | 352 | `left` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| P | 227 | `left` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| P | 305 | `letter-spacing` | `.4px` | 47 §3：字距一律 normal，應移除 |
| P | 84 | `letter-spacing` | `.5px` | 47 §3：字距一律 normal，應移除 |
| P | 102 | `letter-spacing` | `.6px` | 47 §3：字距一律 normal，應移除 |
| P | 304 | `max-height` | `190px` | 版面常數需具名 token〔190px〕 |
| P | 203 | `max-height` | `220px` | 版面常數需具名 token〔220px〕 |
| P | 116 | `max-width` | `1060px` | 版面常數需具名 token〔1060px〕 |
| P | 114 | `max-width` | `1240px` | 版面常數需具名 token〔1240px〕 |
| P | 398 | `max-width` | `250px` | 版面常數需具名 token〔250px〕 |
| P | 226 | `max-width` | `320px` | 版面常數需具名 token〔320px〕 |
| P | 354 | `max-width` | `390px` | 版面常數需具名 token〔390px〕 |
| P | 352 | `max-width` | `420px` | 版面常數需具名 token〔420px〕 |
| P | 402 | `max-width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| P | 86 | `max-width` | `560px` | 版面常數需具名 token〔560px〕 |
| P | 319 | `min-height` | `120px` | 版面常數需具名 token〔120px〕 |
| P | 480 | `min-height` | `36px` | --h-36 |
| P | 482 483 486 | `min-height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| P | 492 | `min-height` | `48px` | 版面常數需具名 token〔48px〕 |
| P | 159 | `min-height` | `62px` | 版面常數需具名 token〔62px〕 |
| P | 456 | `min-width` | `10px` | 版面常數需具名 token〔10px〕 |
| P | 226 | `min-width` | `180px` | 版面常數需具名 token〔180px〕 |
| P | 280 | `min-width` | `18px` | 版面常數需具名 token〔18px〕 |
| P | 439 | `min-width` | `74px` | 版面常數需具名 token〔74px〕 |
| P | 351 | `outline` | `1.5px` | --focus-ring-w〔48 §00.5，未落地〕 |
| P | 75 | `outline` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| P | 75 | `outline-offset` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| P | 351 | `outline-offset` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| P | 358 | `right` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| P | 458 460 461 | `right` | `12px` | --sp-300 |
| P | 92 | `right` | `6px` | --sp-150 |
| P | 460 | `top` | `60px` | --sp-600（24px）〔off-scale 60px〕 |
| P | 92 | `top` | `6px` | --sp-150 |
| P | 358 | `top` | `8px` | --sp-200 |
| P | 448 | `transform` | `18px` | 位移量需 token 化〔18px〕 |
| P | 341 458 | `transform` | `20px` | 位移量需 token 化〔20px〕 |
| P | 117 | `transform` | `3px` | 位移量需 token 化〔3px〕 |
| P | 332 | `transform` | `4px` | 位移量需 token 化〔4px〕 |
| P | 193 | `width` | `10px` | 版面常數需具名 token〔10px〕 |
| P | 284 346 | `width` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| P | 275 | `width` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| P | 83 95 | `width` | `24px` | --h-24 |
| P | 398 | `width` | `250px` | 版面常數需具名 token〔250px〕 |
| P | 382 | `width` | `26px` | 版面常數需具名 token〔26px〕 |
| P | 263 | `width` | `2px` | --sp-050（尺寸借間距階） |
| P | 283 | `width` | `34px` | 版面常數需具名 token〔34px〕 |
| P | 402 484 | `width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| P | 314 | `width` | `4px` | --sp-100（尺寸借間距階） |
| P | 330 | `width` | `540px` | 版面常數需具名 token〔540px〕 |
| P | 92 | `width` | `6px` | --sp-150（尺寸借間距階） |
| P | 331 | `width` | `720px` | 版面常數需具名 token〔720px〕 |
| P | 161 269 | `width` | `8px` | --sp-200（尺寸借間距階） |
| P | 81 | `background` | `#141518` | 23 §1 無此色，需新增或改用既有階〔#141518〕 |
| P | 202 341 354 | `background` | `#1a1b1d` | --surface-inverse〔48 §00.6，未落地〕 |
| P | 86 91 94 375 | `background` | `#232427` | 23 §1 無此色，需新增或改用既有階〔#232427〕 |
| P | 83 95 | `background` | `#2a78d6` | --focus |
| P | 83 84 | `background` | `#6d28d9` | --ai |
| P | 315 | `background` | `#6f9fd8` | 23 §1 無此色，需新增或改用既有階〔#6f9fd8〕 |
| P | 148 | `background` | `#a91a2e` | 23 §1 無此色，需新增或改用既有階〔#a91a2e〕 |
| P | 147 | `background` | `#c22036` | 23 §1 無此色，需新增或改用既有階〔#c22036〕 |
| P | 269 283 | `background` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| P | 194 262 271 | `background` | `#d99a06` | 23 §1 無此色，需新增或改用既有階〔#d99a06〕 |
| P | 315 | `background` | `#e08c3a` | 23 §1 無此色，需新增或改用既有階〔#e08c3a〕 |
| P | 315 | `background` | `#e2c86b` | 23 §1 無此色，需新增或改用既有階〔#e2c86b〕 |
| P | 307 | `background` | `#e2f1ea` | --success-bg |
| P | 321 | `background` | `#e3e3e6` | --border |
| P | 92 | `background` | `#e5484d` | 23 §1 無此色，需新增或改用既有階〔#e5484d〕 |
| P | 108 247 | `background` | `#e9e9ec` | --surface-sunken〔48 §00.6，未落地〕 |
| P | 104 222 | `background` | `#ededee` | --surface-hover〔48 §00.6，未落地〕 |
| P | 160 | `background` | `#eeeef0` | 23 §1 無此色，需新增或改用既有階〔#eeeef0〕 |
| P | 234 | `background` | `#fafafc` | --surface-hover〔48 §00.6，未落地〕 |
| P | 306 | `background` | `#fdecee` | --critical-bg |
| P | 105 143 145 154 284 322 330 450 | `background` | `#fff` | --surface |
| P | 85 86 88 | `border` | `#3a3b40` | 23 §1 無此色，需新增或改用既有階〔#3a3b40〕 |
| P | 154 223 | `border` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| P | 87 | `border-color` | `#55565c` | 23 §1 無此色，需新增或改用既有階〔#55565c〕 |
| P | 155 | `border-color` | `#a9aab0` | 23 §1 無此色，需新增或改用既有階〔#a9aab0〕 |
| P | 143 175 183 323 | `border-color` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| P | 145 | `border-color` | `#e5b7be` | 23 §1 無此色，需新增或改用既有階〔#e5b7be〕 |
| P | 185 | `border-left-color` | `#d99a06` | 23 §1 無此色，需新增或改用既有階〔#d99a06〕 |
| P | 307 | `color` | `#0a5c46` | 23 §1 無此色，需新增或改用既有階〔#0a5c46〕 |
| P | 88 | `color` | `#8b8c92` | 23 §1 無此色，需新增或改用既有階〔#8b8c92〕 |
| P | 306 | `color` | `#8c1122` | 23 §1 無此色，需新增或改用既有階〔#8c1122〕 |
| P | 85 86 358 | `color` | `#9a9ba0` | 23 §1 無此色，需新增或改用既有階〔#9a9ba0〕 |
| P | 357 | `color` | `#b7a5ec` | 23 §1 無此色，需新增或改用既有階〔#b7a5ec〕 |
| P | 90 374 | `color` | `#c9cace` | --border-strong〔48 §00.6，未落地〕 |
| P | 81 354 | `color` | `#e8e9ea` | 23 §1 無此色，需新增或改用既有階〔#e8e9ea〕 |
| P | 82 95 141 147 202 277 341 352 356 359 | `color` | `#fff` | --surface |
| P | 382 | `background` | `rgba(255,255,255,.92)` | 高光層需 token 化 |
| P | 382 | `background` | `rgba(255,255,255,0)` | 高光層需 token 化 |
| P | 328 | `background` | `rgba(26,28,30,.4)` | --scrim〔48 §00.6，未落地〕；47 §H2-2 真值 rgba(0,0,0,.5) |
| P | 376 | `background` | `rgba(26,28,30,.42)` | --scrim〔48 §00.6，未落地〕；47 §H2-2 真值 rgba(0,0,0,.5) |
| P | 284 | `box-shadow` | `rgba(0,0,0,.2)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| P | 352 | `box-shadow` | `rgba(109,40,217,.35)` | 需 token 化〔rgba(109,40,217,.35)〕 |
| P | 141 | `box-shadow` | `rgba(255,255,255,.08)` | 高光層需 token 化 |
| P | 141 | `box-shadow` | `rgba(26,28,30,.15)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| P | 354 | `box-shadow` | `rgba(26,28,30,.5)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| P | 156 | `box-shadow` | `rgba(42,120,214,.18)` | --focus-glow〔48 §00.5，未落地〕 |
| P | 496 | `animation-duration` | `.01ms` | reduced-motion 歸零值，可留（建議 0s） |
| P | 496 | `transition-duration` | `.01ms` | reduced-motion 歸零值，可留（建議 0s） |

### 2.S　`chilllove-storefront-v2.html`（買家前台）

> 458 組 / 1453 處，其中 **375 組** 為 off-scale 或需新增 token。
>
> ⚠ 前台**完全沒有間距／字級／圓角／控件高度的 token 層**（`:root` 只有 9 個品牌色 + 2 個字族 + 8 個 motion token）。
> 依 23 §1 末條與 48 §0 #81，前台是另一套節奏、**不受 47 七階間距約束**，但「有自己的階梯」與「完全沒有階梯」是兩回事：
> 目前 `12.5px`(×42)、`11.5px`(×37)、`13px`(×28)、`17px`(×9) 這類值散落 1453 處，**無法收斂也無法驗收**。
> 本表列出全部裸值供建立前台 token 層時逐條歸階；標「前台無中性階 token」者為必補。

| 檔案 | 行號 | 屬性 | 裸值 | 應改用的 token |
|---|---|---|---|---|
| S | 766 768 770 | `-webkit-mask-image` | `24px` | --sp-600 |
| S | 62 | `backdrop-filter` | `12px` | --sp-300 |
| S | 160 178 | `backdrop-filter` | `6px` | --sp-150 |
| S | 243 387 | `background-position` | `12px` | --sp-300 |
| S | 316 | `background-position` | `13px` | 需 token 化〔13px〕 |
| S | 136 | `border` | `1.6px` | --bw-* 階外〔1.6px〕 |
| S | 80 126 128 183 194 218 238 242 248 272 310 329 337 340 344 345 346 347 358 379 386 388 390 394 407 429 432 451 469 495 510 523 529 534 538 543 546 549 582 614 637 640 659 668 697 702 917 956 | `border` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 561 | `border` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| S | 62 72 107 111 162 209 235 256 262 267 297 366 367 383 454 461 484 505 576 577 580 586 591 646 683 792 857 | `border-bottom` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 463 | `border-bottom` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| S | 157 | `border-bottom` | `3px` | --bw-* 階外〔3px〕 |
| S | 211 | `border-left` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 623 | `border-left` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| S | 882 891 | `border-radius` | `12px` | --r-300 |
| S | 46 58 123 160 178 182 183 184 208 218 238 240 242 248 272 287 310 329 343 347 354 386 388 390 394 407 409 411 429 446 451 469 523 529 534 538 543 546 549 572 588 600 637 659 668 674 697 956 957 | `border-radius` | `2px` | --r-100（4px）〔off-scale 2px〕 |
| S | 80 173 205 268 293 340 358 398 410 485 495 510 556 582 607 616 640 654 663 670 917 | `border-radius` | `3px` | --r-100（4px）〔off-scale 3px〕 |
| S | 159 634 | `border-radius` | `4px` | --r-100 |
| S | 88 264 265 475 476 524 614 648 | `border-radius` | `99px` | --r-400（18px）〔off-scale 99px〕 |
| S | 845 | `border-right` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 120 162 209 235 244 281 300 383 453 465 478 498 504 532 603 625 629 824 | `border-top` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 178 951 | `bottom` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 411 | `bottom` | `12px` | --sp-300 |
| S | 816 | `bottom` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 160 659 | `bottom` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 208 640 654 888 | `bottom` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 635 | `bottom` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 287 | `bottom` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 409 | `bottom` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 663 | `bottom` | `66px` | --sp-600（24px）〔off-scale 66px〕 |
| S | 946 | `bottom` | `6px` | --sp-150 |
| S | 664 | `box-shadow` | `12px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 670 | `box-shadow` | `16px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 332 408 431 547 550 649 | `box-shadow` | `1px` | --bw-100〔48 §00.4，未落地〕＋47 §C 髮絲線 dpr 三檔 |
| S | 255 634 640 850 | `box-shadow` | `20px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 73 660 | `box-shadow` | `22px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 874 | `box-shadow` | `24px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 574 | `box-shadow` | `2px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 293 664 | `box-shadow` | `30px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 314 317 649 698 | `box-shadow` | `3px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 73 | `box-shadow` | `44px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 634 | `box-shadow` | `46px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 670 | `box-shadow` | `48px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 563 | `box-shadow` | `4px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 640 | `box-shadow` | `50px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 253 255 850 | `box-shadow` | `60px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 293 | `box-shadow` | `80px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 660 | `box-shadow` | `8px` | --sh / --sh-pop / --sh-modal（整條陰影 token 化） |
| S | 878 | `column-gap` | `6px` | --sp-150 |
| S | 182 183 184 596 627 674 928 946 | `font-size` | `10.5px` | --t-xs（12px）〔off-scale 10.5px〕 |
| S | 88 248 524 947 | `font-size` | `10px` | --t-xs（12px）〔off-scale 10px〕 |
| S | 50 84 100 110 132 160 163 178 191 240 244 271 283 285 308 319 321 335 366 377 390 423 424 426 466 474 489 490 493 511 520 584 630 663 670 704 951 | `font-size` | `11.5px` | --t-xs（12px）〔off-scale 11.5px〕 |
| S | 39 58 186 195 279 347 369 411 416 494 527 576 612 668 807 909 919 936 | `font-size` | `11px` | --t-2xs〔48 §00.11，未落地〕 |
| S | 78 123 133 208 214 222 227 276 277 287 326 343 368 374 384 386 394 429 436 451 463 505 526 528 530 534 540 546 558 572 575 582 602 603 611 626 641 654 672 692 701 944 | `font-size` | `12.5px` | --t-xs |
| S | 66 | `font-size` | `12.8px` | --t-xs |
| S | 46 107 119 141 220 231 242 262 284 388 418 446 467 479 538 549 614 961 974 | `font-size` | `12px` | --t-xs |
| S | 188 238 258 270 278 334 336 360 381 401 455 458 480 496 502 536 559 597 601 629 860 943 | `font-size` | `13px` | --t-sm |
| S | 617 815 | `font-size` | `14.5px` | --t-md |
| S | 33 34 77 83 161 187 282 310 391 443 487 492 912 935 | `font-size` | `14px` | --t-md |
| S | 158 213 422 643 660 857 | `font-size` | `15px` | --t-md（14px）〔off-scale 15px〕 |
| S | 236 498 531 835 930 967 | `font-size` | `16px` | --t-lg |
| S | 93 115 342 593 619 623 869 | `font-size` | `17px` | --t-lg（16px）〔off-scale 17px〕 |
| S | 290 610 868 | `font-size` | `18px` | --t-xl |
| S | 95 298 359 517 636 699 | `font-size` | `19px` | --t-xl（18px）〔off-scale 19px〕 |
| S | 64 257 499 567 | `font-size` | `20px` | --t-xl（18px）〔off-scale 20px〕 |
| S | 618 697 | `font-size` | `22px` | --t-xl（18px）〔off-scale 22px〕 |
| S | 963 964 | `font-size` | `23px` | --t-xl（18px）〔off-scale 23px〕 |
| S | 114 | `font-size` | `24px` | --t-xl（18px）〔off-scale 24px〕 |
| S | 904 | `font-size` | `25px` | --t-xl（18px）〔off-scale 25px〕 |
| S | 420 905 962 | `font-size` | `26px` | --t-xl（18px）〔off-scale 26px〕 |
| S | 939 966 | `font-size` | `27px` | --t-xl（18px）〔off-scale 27px〕 |
| S | 800 | `font-size` | `28px` | --t-xl（18px）〔off-scale 28px〕 |
| S | 826 | `font-size` | `29px` | --t-xl（18px）〔off-scale 29px〕 |
| S | 417 | `font-size` | `31px` | --t-xl（18px）〔off-scale 31px〕 |
| S | 106 203 216 746 | `font-size` | `32px` | --t-xl（18px）〔off-scale 32px〕 |
| S | 400 635 | `font-size` | `34px` | --t-xl（18px）〔off-scale 34px〕 |
| S | 113 | `font-size` | `36px` | --t-xl（18px）〔off-scale 36px〕 |
| S | 156 965 | `font-size` | `38px` | --t-xl（18px）〔off-scale 38px〕 |
| S | 473 | `font-size` | `44px` | --t-xl（18px）〔off-scale 44px〕 |
| S | 156 746 | `font-size` | `58px` | --t-xl（18px）〔off-scale 58px〕 |
| S | 543 | `font-size` | `8px` | --t-xs（12px）〔off-scale 8px〕 |
| S | 409 | `font-size` | `9px` | --t-xs（12px）〔off-scale 9px〕 |
| S | 241 287 300 326 342 343 368 406 419 444 474 479 519 530 537 572 584 597 685 704 833 900 941 948 955 959 969 | `gap` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 282 297 322 323 329 440 455 465 505 516 534 541 583 592 646 686 780 818 820 911 918 938 968 972 | `gap` | `12px` | --sp-300 |
| S | 267 383 405 496 520 522 586 599 683 692 830 899 941 | `gap` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 105 553 581 625 684 819 833 | `gap` | `16px` | --sp-400 |
| S | 244 484 819 1029 | `gap` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 727 796 958 | `gap` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 167 168 169 729 772 790 829 | `gap` | `24px` | --sp-600 |
| S | 66 235 812 | `gap` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 758 | `gap` | `28px` | --sp-600（24px）〔off-scale 28px〕 |
| S | 695 929 | `gap` | `2px` | --sp-050 |
| S | 63 76 734 758 785 | `gap` | `32px` | --sp-600（24px）〔off-scale 32px〕 |
| S | 730 732 745 778 | `gap` | `34px` | --sp-600（24px）〔off-scale 34px〕 |
| S | 472 | `gap` | `36px` | --sp-600（24px）〔off-scale 36px〕 |
| S | 731 733 | `gap` | `38px` | --sp-600（24px）〔off-scale 38px〕 |
| S | 228 | `gap` | `40px` | --sp-600（24px）〔off-scale 40px〕 |
| S | 364 570 728 | `gap` | `44px` | --sp-600（24px）〔off-scale 44px〕 |
| S | 483 | `gap` | `48px` | --sp-600（24px）〔off-scale 48px〕 |
| S | 85 461 | `gap` | `4px` | --sp-100 |
| S | 404 | `gap` | `52px` | --sp-600（24px）〔off-scale 52px〕 |
| S | 155 509 | `gap` | `56px` | --sp-600（24px）〔off-scale 56px〕 |
| S | 191 193 542 667 | `gap` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| S | 57 247 347 393 411 412 692 840 909 938 | `gap` | `6px` | --sp-150 |
| S | 100 110 446 | `gap` | `7px` | --sp-150（6px）〔off-scale 7px〕 |
| S | 51 123 237 380 388 389 390 418 428 429 436 445 452 468 501 511 545 548 613 644 696 908 | `gap` | `8px` | --sp-200 |
| S | 374 | `gap` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 692 | `grid-template-columns` | `104px` | 版面常數需具名 token〔104px〕 |
| S | 472 | `grid-template-columns` | `180px` | 版面常數需具名 token〔180px〕 |
| S | 734 | `grid-template-columns` | `190px` | 版面常數需具名 token〔190px〕 |
| S | 730 | `grid-template-columns` | `206px` | 版面常數需具名 token〔206px〕 |
| S | 570 | `grid-template-columns` | `216px` | 版面常數需具名 token〔216px〕 |
| S | 364 | `grid-template-columns` | `236px` | 版面常數需具名 token〔236px〕 |
| S | 729 | `grid-template-columns` | `250px` | 版面常數需具名 token〔250px〕 |
| S | 76 | `grid-template-columns` | `300px` | 版面常數需具名 token〔300px〕 |
| S | 732 | `grid-template-columns` | `306px` | 版面常數需具名 token〔306px〕 |
| S | 483 733 | `grid-template-columns` | `344px` | 版面常數需具名 token〔344px〕 |
| S | 509 | `grid-template-columns` | `392px` | 版面常數需具名 token〔392px〕 |
| S | 405 | `grid-template-columns` | `76px` | 版面常數需具名 token〔76px〕 |
| S | 357 561 | `height` | `11px` | 版面常數需具名 token〔11px〕 |
| S | 945 | `height` | `12px` | --sp-300（尺寸借間距階） |
| S | 637 | `height` | `132px` | 版面常數需具名 token〔132px〕 |
| S | 136 | `height` | `13px` | 版面常數需具名 token〔13px〕 |
| S | 194 | `height` | `14px` | 版面常數需具名 token〔14px〕 |
| S | 432 | `height` | `15px` | 版面常數需具名 token〔15px〕 |
| S | 88 327 375 379 | `height` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| S | 331 | `height` | `17px` | 版面常數需具名 token〔17px〕 |
| S | 649 | `height` | `18px` | 版面常數需具名 token〔18px〕 |
| S | 524 | `height` | `19px` | 版面常數需具名 token〔19px〕 |
| S | 42 69 521 | `height` | `1px` | 版面常數需具名 token〔1px〕 |
| S | 543 | `height` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| S | 347 | `height` | `22px` | 版面常數需具名 token〔22px〕 |
| S | 648 675 | `height` | `24px` | --h-24 |
| S | 55 | `height` | `26px` | 版面常數需具名 token〔26px〕 |
| S | 272 390 | `height` | `30px` | 版面常數需具名 token〔30px〕 |
| S | 614 | `height` | `32px` | --h-32 |
| S | 259 | `height` | `34px` | 版面常數需具名 token〔34px〕 |
| S | 86 132 242 386 388 469 549 974 | `height` | `38px` | 版面常數需具名 token〔38px〕 |
| S | 264 | `height` | `3px` | 版面常數需具名 token〔3px〕 |
| S | 178 381 394 546 659 | `height` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| S | 238 240 502 503 | `height` | `42px` | 版面常數需具名 token〔42px〕 |
| S | 91 93 554 869 983 984 985 991 1005 1014 1022 | `height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| S | 123 310 446 988 1013 | `height` | `46px` | 版面常數需具名 token〔46px〕 |
| S | 219 593 836 | `height` | `48px` | 版面常數需具名 token〔48px〕 |
| S | 133 441 699 956 957 | `height` | `50px` | 版面常數需具名 token〔50px〕 |
| S | 875 990 | `height` | `52px` | 版面常數需具名 token〔52px〕 |
| S | 697 | `height` | `56px` | 版面常數需具名 token〔56px〕 |
| S | 475 | `height` | `5px` | 版面常數需具名 token〔5px〕 |
| S | 840 | `height` | `60px` | 版面常數需具名 token〔60px〕 |
| S | 63 | `height` | `64px` | 版面常數需具名 token〔64px〕 |
| S | 348 413 | `height` | `6px` | --sp-150（尺寸借間距階） |
| S | 437 | `height` | `7px` | 版面常數需具名 token〔7px〕 |
| S | 960 | `height` | `82px` | 版面常數需具名 token〔82px〕 |
| S | 268 | `height` | `96px` | 版面常數需具名 token〔96px〕 |
| S | 178 182 183 184 951 | `left` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 816 | `left` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 887 | `left` | `16px` | --sp-400 |
| S | 160 659 663 | `left` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 208 654 | `left` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 649 | `left` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 946 947 | `left` | `6px` | --sp-150 |
| S | 46 | `left` | `8px` | --sp-200 |
| S | 216 271 417 619 | `margin` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 618 | `margin` | `12px` | --sp-300 |
| S | 113 216 610 814 | `margin` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 203 621 814 | `margin` | `16px` | --sp-400 |
| S | 156 203 556 | `margin` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 156 621 | `margin` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 120 520 623 | `margin` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 619 | `margin` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 271 489 | `margin` | `2px` | --sp-050 |
| S | 618 | `margin` | `34px` | --sp-600（24px）〔off-scale 34px〕 |
| S | 489 | `margin` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 113 610 | `margin` | `6px` | --sp-150 |
| S | 417 | `margin` | `8px` | --sp-200 |
| S | 115 548 | `margin-bottom` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 77 596 917 | `margin-bottom` | `12px` | --sp-300 |
| S | 229 231 307 342 418 516 | `margin-bottom` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 114 283 343 620 691 | `margin-bottom` | `16px` | --sp-400 |
| S | 339 360 389 529 | `margin-bottom` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 383 584 | `margin-bottom` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 935 | `margin-bottom` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 691 818 | `margin-bottom` | `24px` | --sp-600 |
| S | 235 472 515 613 616 815 | `margin-bottom` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 217 595 | `margin-bottom` | `28px` | --sp-600（24px）〔off-scale 28px〕 |
| S | 204 | `margin-bottom` | `30px` | --sp-600（24px）〔off-scale 30px〕 |
| S | 158 829 | `margin-bottom` | `32px` | --sp-600（24px）〔off-scale 32px〕 |
| S | 105 | `margin-bottom` | `36px` | --sp-600（24px）〔off-scale 36px〕 |
| S | 540 | `margin-bottom` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 228 | `margin-bottom` | `48px` | --sp-600（24px）〔off-scale 48px〕 |
| S | 213 282 | `margin-bottom` | `4px` | --sp-100 |
| S | 474 627 | `margin-bottom` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| S | 308 479 622 630 643 672 | `margin-bottom` | `6px` | --sp-150 |
| S | 290 359 398 553 691 695 | `margin-bottom` | `8px` | --sp-200 |
| S | 426 | `margin-bottom` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 190 | `margin-left` | `6px` | --sp-150 |
| S | 258 | `margin-left` | `8px` | --sp-200 |
| S | 937 | `margin-right` | `36px` | --sp-600（24px）〔off-scale 36px〕 |
| S | 164 | `margin-right` | `56px` | --sp-600（24px）〔off-scale 56px〕 |
| S | 106 264 279 498 534 667 | `margin-top` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 284 412 583 | `margin-top` | `12px` | --sp-300 |
| S | 222 644 | `margin-top` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 341 436 444 504 690 | `margin-top` | `16px` | --sp-400 |
| S | 440 451 | `margin-top` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 425 468 | `margin-top` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 465 | `margin-top` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 690 | `margin-top` | `24px` | --sp-600 |
| S | 453 | `margin-top` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 327 331 527 | `margin-top` | `2px` | --sp-050 |
| S | 690 | `margin-top` | `32px` | --sp-600（24px）〔off-scale 32px〕 |
| S | 188 335 | `margin-top` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 625 | `margin-top` | `44px` | --sp-600（24px）〔off-scale 44px〕 |
| S | 191 423 939 992 | `margin-top` | `4px` | --sp-100 |
| S | 393 | `margin-top` | `52px` | --sp-600（24px）〔off-scale 52px〕 |
| S | 319 321 | `margin-top` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| S | 285 401 467 557 993 | `margin-top` | `6px` | --sp-150 |
| S | 193 612 690 | `margin-top` | `8px` | --sp-200 |
| S | 357 | `margin-top` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 767 769 771 | `mask-image` | `24px` | --sp-600 |
| S | 537 | `max-height` | `340px` | 版面常數需具名 token〔340px〕 |
| S | 406 | `max-height` | `640px` | 版面常數需具名 token〔640px〕 |
| S | 37 | `max-width` | `1280px` | 版面常數需具名 token〔1280px〕 |
| S | 951 | `max-width` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| S | 816 | `max-width` | `28px` | --h-28 |
| S | 287 | `max-width` | `32px` | --h-32 |
| S | 664 | `max-width` | `330px` | 版面常數需具名 token〔330px〕 |
| S | 664 | `max-width` | `36px` | --h-36 |
| S | 670 | `max-width` | `380px` | 版面常數需具名 token〔380px〕 |
| S | 218 | `max-width` | `420px` | 版面常數需具名 token〔420px〕 |
| S | 633 | `max-width` | `460px` | 版面常數需具名 token〔460px〕 |
| S | 38 | `max-width` | `780px` | 版面常數需具名 token〔780px〕 |
| S | 222 | `min-height` | `20px` | --h-badge 20〔47 §B 徽章高，需新 token〕 |
| S | 326 374 | `min-height` | `32px` | --h-32 |
| S | 200 | `min-height` | `340px` | 版面常數需具名 token〔340px〕 |
| S | 50 | `min-height` | `36px` | --h-36 |
| S | 429 | `min-height` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| S | 860 | `min-height` | `42px` | 版面常數需具名 token〔42px〕 |
| S | 986 987 992 997 1002 1008 1009 1010 1028 | `min-height` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| S | 999 1001 1004 1015 | `min-height` | `46px` | 版面常數需具名 token〔46px〕 |
| S | 1003 | `min-height` | `48px` | 版面常數需具名 token〔48px〕 |
| S | 199 | `min-height` | `520px` | 版面常數需具名 token〔520px〕 |
| S | 856 | `min-height` | `52px` | 版面常數需具名 token〔52px〕 |
| S | 1016 | `min-height` | `66px` | 版面常數需具名 token〔66px〕 |
| S | 311 | `min-height` | `96px` | 版面常數需具名 token〔96px〕 |
| S | 645 | `min-width` | `110px` | 版面常數需具名 token〔110px〕 |
| S | 88 | `min-width` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| S | 524 | `min-width` | `19px` | 版面常數需具名 token〔19px〕 |
| S | 238 | `min-width` | `220px` | 版面常數需具名 token〔220px〕 |
| S | 276 | `min-width` | `30px` | 版面常數需具名 token〔30px〕 |
| S | 974 | `min-width` | `38px` | 版面常數需具名 token〔38px〕 |
| S | 394 | `min-width` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| S | 992 1005 1028 | `min-width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| S | 978 | `min-width` | `66px` | 版面常數需具名 token〔66px〕 |
| S | 919 973 | `min-width` | `78px` | 版面常數需具名 token〔78px〕 |
| S | 996 | `min-width` | `96px` | 版面常數需具名 token〔96px〕 |
| S | 491 | `min-width` | `98px` | 版面常數需具名 token〔98px〕 |
| S | 658 | `outline` | `1.5px` | --focus-ring-w〔48 §00.5，未落地〕 |
| S | 41 | `outline` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| S | 41 658 | `outline-offset` | `2px` | --bw-200〔48 §00.4，未落地〕 |
| S | 160 208 381 390 411 576 599 847 859 900 942 | `padding` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 572 817 961 977 | `padding` | `11px` | --sp-300（12px）〔off-scale 11px〕 |
| S | 46 82 242 287 311 343 383 386 463 522 538 572 576 577 646 663 702 807 909 936 951 954 977 993 994 1006 1007 | `padding` | `12px` | --sp-300 |
| S | 162 995 1006 | `padding` | `13px` | --sp-300（12px）〔off-scale 13px〕 |
| S | 82 95 185 238 310 311 343 368 388 451 530 534 549 577 586 591 614 663 670 856 859 860 867 870 884 918 1011 1024 | `padding` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 329 429 | `padding` | `15px` | --sp-400（16px）〔off-scale 15px〕 |
| S | 46 50 132 160 262 300 329 337 372 455 463 511 530 532 546 603 654 670 683 824 873 909 926 927 953 961 975 1011 1024 | `padding` | `16px` | --sp-400 |
| S | 219 267 458 503 582 629 654 867 870 871 873 884 910 972 976 | `padding` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 409 674 | `padding` | `1px` | --sp-050（2px）〔off-scale 1px〕 |
| S | 208 261 281 289 297 300 478 558 640 805 806 822 827 903 954 | `padding` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 240 256 287 299 340 484 495 510 511 | `padding` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 211 256 261 262 266 281 297 299 300 358 824 827 847 | `padding` | `24px` | --sp-600 |
| S | 109 220 235 509 594 | `padding` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 741 742 799 828 | `padding` | `28px` | --sp-600（24px）〔off-scale 28px〕 |
| S | 185 859 947 | `padding` | `2px` | --sp-050 |
| S | 123 242 | `padding` | `30px` | --sp-600（24px）〔off-scale 30px〕 |
| S | 386 725 726 933 | `padding` | `32px` | --sp-600（24px）〔off-scale 32px〕 |
| S | 76 109 211 227 670 | `padding` | `34px` | --sp-600（24px）〔off-scale 34px〕 |
| S | 76 | `padding` | `38px` | --sp-600（24px）〔off-scale 38px〕 |
| S | 182 183 184 248 | `padding` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 37 38 756 811 | `padding` | `40px` | --sp-600（24px）〔off-scale 40px〕 |
| S | 399 933 953 | `padding` | `44px` | --sp-600（24px）〔off-scale 44px〕 |
| S | 337 | `padding` | `45px` | --sp-600（24px）〔off-scale 45px〕 |
| S | 67 88 232 409 603 | `padding` | `4px` | --sp-100 |
| S | 811 822 828 | `padding` | `52px` | --sp-600（24px）〔off-scale 52px〕 |
| S | 744 932 | `padding` | `56px` | --sp-600（24px）〔off-scale 56px〕 |
| S | 78 326 374 524 674 | `padding` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| S | 289 594 | `padding` | `60px` | --sp-600（24px）〔off-scale 60px〕 |
| S | 358 | `padding` | `62px` | --sp-600（24px）〔off-scale 62px〕 |
| S | 227 744 756 | `padding` | `64px` | --sp-600（24px）〔off-scale 64px〕 |
| S | 847 | `padding` | `66px` | --sp-600（24px）〔off-scale 66px〕 |
| S | 810 | `padding` | `68px` | --sp-600（24px）〔off-scale 68px〕 |
| S | 58 411 496 668 917 992 | `padding` | `6px` | --sp-150 |
| S | 154 201 | `padding` | `72px` | --sp-600（24px）〔off-scale 72px〕 |
| S | 248 505 918 947 | `padding` | `7px` | --sp-150（6px）〔off-scale 7px〕 |
| S | 201 743 | `padding` | `80px` | --sp-600（24px）〔off-scale 80px〕 |
| S | 154 | `padding` | `84px` | --sp-600（24px）〔off-scale 84px〕 |
| S | 404 | `padding` | `88px` | --sp-600（24px）〔off-scale 88px〕 |
| S | 58 266 394 404 702 808 871 936 951 987 1025 | `padding` | `8px` | --sp-200 |
| S | 509 | `padding` | `90px` | --sp-600（24px）〔off-scale 90px〕 |
| S | 104 215 | `padding` | `96px` | --sp-600（24px）〔off-scale 96px〕 |
| S | 54 182 183 184 347 597 668 | `padding` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 366 | `padding-bottom` | `12px` | --sp-300 |
| S | 892 | `padding-bottom` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 107 782 | `padding-bottom` | `2px` | --sp-050 |
| S | 364 483 570 | `padding-bottom` | `96px` | --sp-600（24px）〔off-scale 96px〕 |
| S | 336 | `padding-left` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 460 623 886 | `padding-left` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 557 | `padding-left` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 886 | `padding-right` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 315 | `padding-right` | `34px` | --sp-600（24px）〔off-scale 34px〕 |
| S | 498 504 | `padding-top` | `14px` | --sp-300（12px）〔off-scale 14px〕 |
| S | 465 | `padding-top` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 244 | `padding-top` | `22px` | --sp-600（24px）〔off-scale 22px〕 |
| S | 625 | `padding-top` | `26px` | --sp-600（24px）〔off-scale 26px〕 |
| S | 178 | `right` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 411 | `right` | `12px` | --sp-300 |
| S | 57 887 | `right` | `16px` | --sp-400 |
| S | 88 | `right` | `1px` | --sp-050（2px）〔off-scale 1px〕 |
| S | 640 | `right` | `20px` | --sp-400（16px）〔off-scale 20px〕 |
| S | 409 | `right` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 946 | `right` | `6px` | --sp-150 |
| S | 675 | `right` | `8px` | --sp-200 |
| S | 93 | `right` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 139 141 624 | `text-underline-offset` | `3px` | 需 token 化〔3px〕 |
| S | 182 183 184 | `top` | `10px` | --sp-200（8px）〔off-scale 10px〕 |
| S | 565 | `top` | `18px` | --sp-400（16px）〔off-scale 18px〕 |
| S | 510 | `top` | `24px` | --sp-600 |
| S | 88 649 | `top` | `3px` | --sp-050（2px）〔off-scale 3px〕 |
| S | 561 | `top` | `5px` | --sp-100（4px）〔off-scale 5px〕 |
| S | 675 947 | `top` | `6px` | --sp-150 |
| S | 47 | `top` | `8px` | --sp-200 |
| S | 365 415 495 571 | `top` | `92px` | --sp-600（24px）〔off-scale 92px〕 |
| S | 93 | `top` | `9px` | --sp-200（8px）〔off-scale 9px〕 |
| S | 651 | `transform` | `18px` | 位移量需 token 化〔18px〕 |
| S | 178 | `transform` | `8px` | 位移量需 token 化〔8px〕 |
| S | 287 888 | `transform` | `90px` | 位移量需 token 化〔90px〕 |
| S | 485 | `width` | `104px` | 版面常數需具名 token〔104px〕 |
| S | 561 | `width` | `11px` | 版面常數需具名 token〔11px〕 |
| S | 945 | `width` | `12px` | --sp-300（尺寸借間距階） |
| S | 637 | `width` | `132px` | 版面常數需具名 token〔132px〕 |
| S | 136 | `width` | `13px` | 版面常數需具名 token〔13px〕 |
| S | 194 | `width` | `14px` | 版面常數需具名 token〔14px〕 |
| S | 432 | `width` | `15px` | 版面常數需具名 token〔15px〕 |
| S | 327 375 379 | `width` | `16px` | --sp-400(16)／checkbox 視覺盒鎖死 16 |
| S | 331 | `width` | `17px` | 版面常數需具名 token〔17px〕 |
| S | 649 | `width` | `18px` | 版面常數需具名 token〔18px〕 |
| S | 42 565 | `width` | `1px` | 版面常數需具名 token〔1px〕 |
| S | 675 | `width` | `24px` | --h-24 |
| S | 55 | `width` | `26px` | 版面常數需具名 token〔26px〕 |
| S | 273 | `width` | `28px` | --h-28 |
| S | 543 | `width` | `30px` | 版面常數需具名 token〔30px〕 |
| S | 654 844 | `width` | `320px` | 版面常數需具名 token〔320px〕 |
| S | 259 477 | `width` | `34px` | 版面常數需具名 token〔34px〕 |
| S | 640 | `width` | `380px` | 版面常數需具名 token〔380px〕 |
| S | 86 277 469 | `width` | `38px` | 版面常數需具名 token〔38px〕 |
| S | 640 654 659 699 | `width` | `40px` | --ctl-40〔48 §00.1，未落地〕 |
| S | 253 | `width` | `420px` | 版面常數需具名 token〔420px〕 |
| S | 442 648 | `width` | `42px` | 版面常數需具名 token〔42px〕 |
| S | 91 93 554 869 983 984 985 989 | `width` | `44px` | --hit-min〔48 §00.2，未落地〕 |
| S | 443 697 1000 | `width` | `46px` | 版面常數需具名 token〔46px〕 |
| S | 600 | `width` | `54px` | 版面常數需具名 token〔54px〕 |
| S | 293 | `width` | `560px` | 版面常數需具名 token〔560px〕 |
| S | 523 | `width` | `56px` | 版面常數需具名 token〔56px〕 |
| S | 588 960 | `width` | `64px` | 版面常數需具名 token〔64px〕 |
| S | 784 | `width` | `66px` | 版面常數需具名 token〔66px〕 |
| S | 348 413 | `width` | `6px` | --sp-150（尺寸借間距階） |
| S | 971 | `width` | `72px` | 版面常數需具名 token〔72px〕 |
| S | 296 | `width` | `760px` | 版面常數需具名 token〔760px〕 |
| S | 268 | `width` | `76px` | 版面常數需具名 token〔76px〕 |
| S | 437 | `width` | `7px` | 版面常數需具名 token〔7px〕 |
| S | 898 | `width` | `84px` | 版面常數需具名 token〔84px〕 |
| S | 766 768 770 | `-webkit-mask-image` | `#000` | 前台無中性階 token，需建立〔#000〕 |
| S | 449 | `background` | `#000` | 前台無中性階 token，需建立〔#000〕 |
| S | 448 | `background` | `#06c755` | 前台無中性階 token，需建立〔#06c755〕 |
| S | 125 221 | `background` | `#3a342d` | 前台無中性階 token，需建立〔#3a342d〕 |
| S | 447 | `background` | `#5a31f4` | 前台無中性階 token，需建立〔#5a31f4〕 |
| S | 634 | `background` | `#c08c62` | 前台無中性階 token，需建立〔#c08c62〕 |
| S | 556 | `background` | `#cdc6b4` | 前台無中性階 token，需建立〔#cdc6b4〕 |
| S | 556 | `background` | `#e6e2d6` | 前台無中性階 token，需建立〔#e6e2d6〕 |
| S | 634 | `background` | `#e8d3bd` | 前台無中性階 token，需建立〔#e8d3bd〕 |
| S | 129 240 669 | `background` | `#efe9df` | 前台無中性階 token，需建立〔#efe9df〕 |
| S | 450 | `background` | `#ffc439` | 前台無中性階 token，需建立〔#ffc439〕 |
| S | 128 | `border` | `#efe9df` | 前台無中性階 token，需建立〔#efe9df〕 |
| S | 313 330 430 | `border-color` | `#cfc4b4` | 前台無中性階 token，需建立〔#cfc4b4〕 |
| S | 669 | `border-color` | `#efe9df` | 前台無中性階 token，需建立〔#efe9df〕 |
| S | 450 | `color` | `#0b2a4a` | 前台無中性階 token，需建立〔#0b2a4a〕 |
| S | 635 | `color` | `#3c2c1c` | 前台無中性階 token，需建立〔#3c2c1c〕 |
| S | 345 349 | `color` | `#4e5942` | 前台無中性階 token，需建立〔#4e5942〕 |
| S | 239 | `color` | `#8d8377` | 前台無中性階 token，需建立〔#8d8377〕 |
| S | 244 675 | `color` | `#9c9180` | 前台無中性階 token，需建立〔#9c9180〕 |
| S | 55 58 202 227 232 242 | `color` | `#b7ab9b` | 前台無中性階 token，需建立〔#b7ab9b〕 |
| S | 204 668 | `color` | `#c9bfb0` | 前台無中性階 token，需建立〔#c9bfb0〕 |
| S | 673 | `color` | `#d3a184` | 前台無中性階 token，需建立〔#d3a184〕 |
| S | 401 | `color` | `#e2d9cb` | 前台無中性階 token，需建立〔#e2d9cb〕 |
| S | 670 | `color` | `#e8e3da` | 前台無中性階 token，需建立〔#e8e3da〕 |
| S | 50 128 184 198 231 236 238 351 654 663 | `color` | `#efe9df` | 前台無中性階 token，需建立〔#efe9df〕 |
| S | 124 127 180 220 287 | `color` | `#f6f1e9` | --cream |
| S | 203 229 233 246 400 | `color` | `#fbf7f0` | 前台無中性階 token，需建立〔#fbf7f0〕 |
| S | 52 56 59 88 130 182 409 446 524 554 662 666 672 676 | `color` | `#fff` | 前台無中性階 token，需建立〔#fff〕 |
| S | 767 769 771 | `mask-image` | `#000` | 前台無中性階 token，需建立〔#000〕 |
| S | 345 349 | `background` | `rgba(125,138,111,.12)` | 需 token 化〔rgba(125,138,111,.12)〕 |
| S | 344 | `background` | `rgba(140,63,32,.08)` | 需 token 化〔rgba(140,63,32,.08)〕 |
| S | 350 | `background` | `rgba(169,80,44,.1)` | 需 token 化〔rgba(169,80,44,.1)〕 |
| S | 674 | `background` | `rgba(239,233,223,.12)` | 需 token 化〔rgba(239,233,223,.12)〕 |
| S | 62 | `background` | `rgba(246,241,233,.92)` | 需 token 化〔rgba(246,241,233,.92)〕 |
| S | 838 | `background` | `rgba(246,241,233,.97)` | 需 token 化〔rgba(246,241,233,.97)〕 |
| S | 160 411 | `background` | `rgba(255,253,248,.92)` | 需 token 化〔rgba(255,253,248,.92)〕 |
| S | 208 | `background` | `rgba(255,253,248,.94)` | 需 token 化〔rgba(255,253,248,.94)〕 |
| S | 178 | `background` | `rgba(255,253,248,.96)` | 需 token 化〔rgba(255,253,248,.96)〕 |
| S | 148 | `background` | `rgba(255,255,255,.5)` | 高光層需 token 化 |
| S | 399 | `background` | `rgba(34,30,26,.05)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 87 92 | `background` | `rgba(34,30,26,.06)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 94 260 | `background` | `rgba(34,30,26,.07)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 903 | `background` | `rgba(34,30,26,.12)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 96 251 | `background` | `rgba(34,30,26,.45)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 399 | `background` | `rgba(34,30,26,.55)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 409 | `background` | `rgba(34,30,26,.7)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 903 | `background` | `rgba(34,30,26,.72)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 184 | `background` | `rgba(34,30,26,.86)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 304 | `background` | `rgba(34,30,26,.96)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 345 | `border` | `rgba(125,138,111,.4)` | 需 token 化〔rgba(125,138,111,.4)〕 |
| S | 344 | `border` | `rgba(140,63,32,.28)` | 需 token 化〔rgba(140,63,32,.28)〕 |
| S | 248 | `border` | `rgba(239,233,223,.22)` | 需 token 化〔rgba(239,233,223,.22)〕 |
| S | 238 242 668 | `border` | `rgba(239,233,223,.3)` | 需 token 化〔rgba(239,233,223,.3)〕 |
| S | 194 | `border` | `rgba(34,30,26,.18)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 379 432 | `border` | `rgba(34,30,26,.2)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 157 | `border-bottom` | `rgba(169,80,44,.35)` | 需 token 化〔rgba(169,80,44,.35)〕 |
| S | 235 | `border-bottom` | `rgba(239,233,223,.14)` | 需 token 化〔rgba(239,233,223,.14)〕 |
| S | 349 | `border-color` | `rgba(125,138,111,.5)` | 需 token 化〔rgba(125,138,111,.5)〕 |
| S | 361 | `border-color` | `rgba(140,63,32,.3)` | 需 token 化〔rgba(140,63,32,.3)〕 |
| S | 350 | `border-color` | `rgba(169,80,44,.4)` | 需 token 化〔rgba(169,80,44,.4)〕 |
| S | 235 244 | `border-top` | `rgba(239,233,223,.14)` | 需 token 化〔rgba(239,233,223,.14)〕 |
| S | 317 | `box-shadow` | `rgba(140,63,32,.1)` | 需 token 化〔rgba(140,63,32,.1)〕 |
| S | 314 698 | `box-shadow` | `rgba(169,80,44,.13)` | 需 token 化〔rgba(169,80,44,.13)〕 |
| S | 563 | `box-shadow` | `rgba(169,80,44,.16)` | 需 token 化〔rgba(169,80,44,.16)〕 |
| S | 874 | `box-shadow` | `rgba(34,30,26,.07)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 73 | `box-shadow` | `rgba(34,30,26,.10)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 660 | `box-shadow` | `rgba(34,30,26,.16)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 634 | `box-shadow` | `rgba(34,30,26,.18)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 640 | `box-shadow` | `rgba(34,30,26,.2)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 850 | `box-shadow` | `rgba(34,30,26,.22)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 253 255 649 | `box-shadow` | `rgba(34,30,26,.25)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 664 | `box-shadow` | `rgba(34,30,26,.3)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 293 | `box-shadow` | `rgba(34,30,26,.34)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 670 | `box-shadow` | `rgba(34,30,26,.5)` | 陰影／遮罩需整條 token 化（--sh* / --scrim） |
| S | 554 | `animation` | `cubic-bezier(.2,.9,.3,1.4)` | 不在 47 §5 三曲線內，必須改用 --ease-standard/-in-out/-decelerate〔cubic-bezier(.2,.9,.3,1.4)〕 |
| S | 174 206 608 | `transition` | `cubic-bezier(.2,.7,.2,1)` | 不在 47 §5 三曲線內，必須改用 --ease-standard/-in-out/-decelerate〔cubic-bezier(.2,.7,.2,1)〕 |
| S | 265 476 | `transition` | `cubic-bezier(.2,.8,.2,1)` | 不在 47 §5 三曲線內，必須改用 --ease-standard/-in-out/-decelerate〔cubic-bezier(.2,.8,.2,1)〕 |
| S | 554 | `animation` | `.45s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.45s〕 |
| S | 89 | `animation` | `.4s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.4s〕 |
| S | 136 | `animation` | `.7s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.7s〕 |
| S | 354 | `animation` | `1.2s` | --dur-shimmer〔48 §00.10，未落地〕 |
| S | 163 | `animation` | `26s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：26s〕 |
| S | 1035 | `animation-duration` | `.001ms` | reduced-motion 歸零值，可留（建議 0s） |
| S | 176 | `transition` | `.45s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.45s〕 |
| S | 265 476 | `transition` | `.5s` | --dur-bar-grow〔48 §00.10，未落地〕 |
| S | 174 608 | `transition` | `.6s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.6s〕 |
| S | 206 | `transition` | `.7s` | --dur-slowest（300ms）〔不在 47 §5 五時長內：.7s〕 |
| S | 1036 | `transition-duration` | `.001ms` | reduced-motion 歸零值，可留（建議 0s） |

### 2.X　三份原型共通的結構性缺口（表 2 的根因）

| 缺口 | A | P | S | 說明 |
|---|:--:|:--:|:--:|---|
| `--r-pill` 未定義卻使用 `999px` | ✗ 13 處 | ✓ 已定義 | ✗ 用 `99px`/`999px` | A 硬編 `border-radius:999px` 於 78/99/133/180/182/330/408/542/551/665/718/806/807 |
| `--sh-pop`／`--sh-modal` 未定義 | ✗ | ✓ | ✗ | A 硬編 `0 12px 32px rgba(...)`、`0 24px 64px rgba(...)` 於 197/338/348/355/363 |
| `--border-strong`（`#c9cace`） | ✗ 12 處 | ✗ 10 處 | — | 48 §00.6 已提議，兩份原型都沒落地 |
| `--surface-inverse`（`#1a1b1d`） | ✗ 7 處 | ✗ 3 處 | — | 同上 |
| `--selected-bg`（`#f0f5ff`） | ✗ 3 處 | — | — | 同上 |
| `--surface-hover`（`#ededee`/`#fafafc`/`#f0f0f2`/`#e8e8ea` 四種混用） | ✗ | ✗ | — | 同上；同一語意四個色值 |
| 版面常數（`52px` 頂欄、`220px` 側欄） | ✗ 硬編 6 處 | ✓ 有 token 但**值錯** | — | 見表 1 §1.4 |
| 前台中性／間距／字級／圓角 token 層 | — | — | ✗ 全缺 | 見 2.S 表頭 |

---

## 表 3 · 斷點一致性

> **實站權威階梯（47 §F，8 階、em、root 16）**：
> `22.5em`=360｜`30.625em`=490｜`41.6875em`=667｜**`48em`=768（主斷點，用量 421 次，遠超其他）**｜`65em`=1040｜`75em`=1200｜`90em`=1440｜`160em`=2560。
> max 配對一律 **−0.0025em**（`47.9975em`=767.96、`30.6225em`=489.96、`41.685em`=666.96）。
>
> **我方（34 §1）**：4 階 px、desktop-first `max-width`：1279 / 1023 / 767 / 429。
>
> **掃描結果**：三份原型合計 **28 個 `@media` 區塊** = **寬度型 20 個**（A 9 / P 4 / S 7）＋ **非寬度型 8 個**（`pointer:coarse` 4、`prefers-reduced-motion` 4）。**寬度型全部 100% 使用 px，`em` 使用數 = 0。**

| 原型檔 | 行號 | 現用斷點 | 對應實站階 | 差異 | 建議值（em） |
|---|---|---|---|---|---|
| A | 392 | `max-width:1279px` | 1200（`75em`）／1440（`90em`） | **我方少一階**；實站在 1200 與 1440 各切一次 | 拆兩階：`max-width:74.9975em` ＋ `max-width:89.9975em` |
| A | 403 | `min-width:767.02px` and `max-width:1279px` | 768（`48em`）〜1200 | 767.02 是為避開 767 的 hack，實站用 `48em` 乾淨切 | `(min-width:48em) and (max-width:74.9975em)` |
| A | 423 | `max-width:1023px` | 1040（`65em`） | **差 17px** | `max-width:64.9975em` |
| A | 453 | `max-width:767px` | 768（`47.9975em`） | 差 0.04px，**幾乎一致** | `max-width:47.9975em` |
| A | 582 | `max-width:429px` | 490（`30.6225em`） | **差 61px，手機大斷點太早** | `max-width:30.6225em` |
| A | 596 | `pointer:coarse` | —（非寬度） | 實站未量到；34 §1 自訂，保留 | 不變 |
| A | 616 | `prefers-reduced-motion:reduce` | —（非寬度） | 保留 | 不變 |
| A | 625 | `prefers-reduced-motion:reduce` and `max-width:767px` | 768 | 同 453 | `(prefers-reduced-motion:reduce) and (max-width:47.9975em)` |
| A | 823 | `max-width:1023px`（第二段 RWD 區塊） | 1040 | 同 423；**與 423 重複宣告同一斷點** | `max-width:64.9975em` |
| A | 828 | `max-width:767px`（第二段） | 768 | 同 453；重複 | `max-width:47.9975em` |
| A | 852 | `max-width:429px`（第二段） | 490 | 同 582；重複 | `max-width:30.6225em` |
| A | 856 | `pointer:coarse`（第二段） | — | 重複 | 不變 |
| A | 880 | `prefers-reduced-motion:reduce`（第二段） | — | 重複 | 不變 |
| P | 385 | `max-width:1279px` | 1200／1440 | 少一階 | 拆 `74.9975em` ＋ `89.9975em` |
| P | 395 | `max-width:1023px` | 1040 | 差 17px | `max-width:64.9975em` |
| P | 412 | `max-width:767px` | 768 | 幾乎一致 | `max-width:47.9975em` |
| P | 465 | `max-width:429px` | 490 | 差 61px | `max-width:30.6225em` |
| P | 478 | `pointer:coarse` | — | 保留 | 不變 |
| P | 495 | `prefers-reduced-motion:reduce` | — | 保留 | 不變 |
| S | 695 | `max-width:429px`（`.dl` 專用 inline） | 490 | 差 61px；且**與 925 的全域 429 區塊重複** | `max-width:30.6225em`，併入 925 |
| S | 699 | `max-width:429px`（`.otp` 專用 inline） | 490 | 同上 | 同上 |
| S | 724 | `max-width:1279px` | 1200／1440 | 少一階 | 拆兩階 |
| S | 740 | `max-width:1023px` | 1040 | 差 17px | `max-width:64.9975em` |
| S | 804 | `max-width:767px` | 768 | 幾乎一致 | `max-width:47.9975em` |
| S | 925 | `max-width:429px` | 490 | 差 61px | `max-width:30.6225em` |
| S | 982 | `pointer:coarse` | — | 保留 | 不變 |
| S | 1027 | `pointer:coarse` and `min-width:768px` | 768（`48em`） | **唯一寫對 768 的地方**，但仍是 px | `(pointer:coarse) and (min-width:48em)` |
| S | 1033 | `prefers-reduced-motion:reduce` | — | 保留 | 不變 |

### 3.1 三個結構性差異（不在逐行表內）

| # | 差異 | 影響 |
|---|---|---|
| 1 | **全部 px、零 em** | 使用者調大瀏覽器預設字型時版面不會提早換寬鬆佈局。47 §F 明指這是**無障礙設計決定**，也是本次量測初期「1024px 視窗卻拿到極窄版」的根因。**一行改動換一整類無障礙情境**。 |
| 2 | **缺 4 階**：360（`22.5em`）／667（`41.6875em`）／1200 與 1440 其一／2560（`160em`） | 667 是平板直式，我方 429→767 之間完全沒有中繼；1200/1440 我方擠成一個 1279 |
| 3 | **主斷點認知不同** | 47 §F：768 是**唯一的佈局換手線**（用量 421 次），1040/1200/1440 只做欄數與密度微調、**不重排結構**。34 §2 規則 1/4 把「側欄轉抽屜」「兩欄轉單欄」放在 **≤1023**，等於在非主斷點做結構重排。 |
| 4 | `html{font-size:var(--t-sm)}` = **13px**（A:65、P:69）、S = 14px（33） | media query 的 `em` 以**初始字級 16px** 計算、不受 `html` font-size 影響，故改 em 斷點**安全**；但要在 34 §8.7 補註，避免實作者誤以為要乘 13/16 |

**表 3 統計**：寬度型 `@media` **20 個，全部不一致**（20/20）；分佈為「幾乎一致（差 0.04px，767↔768）」**5** 個、「差 17px（1023↔1040）」**4** 個、「差 61px（429↔490）」**6** 個、「少一階（1279↔1200/1440）」**3** 個、「`min-width:767.02px` hack」**1** 個、「值寫對 768 但仍是 px」**1** 個。非寬度型 8 個（`pointer:coarse` 4、`prefers-reduced-motion` 4）不列入不一致。

---

## 表 4 · 動效一致性（47 §5 M1–M7）

> **掃描規則**：抓 `<style>` 區塊內全部 `transition:` 與 `animation:` 宣告，把 `transition` 依頂層逗號拆成單一屬性片段（忽略 `var()`／`cubic-bezier()` 內的逗號），逐片段比對 M1–M7 的〔屬性 × 時長 × 曲線〕三元組。
>
> **掃描總量**：A **67** 個宣告片段、P **50** 個、S **69** 個 → 合計 **186**。**不合規 69**（A 29、P 12、S 28），其中 **13 個為 reduced-motion 歸零或 `visibility` 輔助宣告，屬合理豁免** → **實質不合規 56**。

### 4.0 特別搜尋項的結果

| 搜尋目標 | A | P | S | 結論 |
|---|:--:|:--:|:--:|---|
| 殘留 `transition: all` | **0** | **0** | **0** | ✅ 三份主原型已清乾淨。**但 deprecated 的 `chilllove-admin-preview.html`（67/112/169/176/184）與 `chilllove-storefront-preview.html`（59/96）仍有 7 處**，若日後被當參考會回流 |
| 用 `height` 而非 `max-height` 做摺疊 | 0 | 0 | 0 | ✅ A `.m-accordion`(898)、P `.accordion-body`(138) 皆用 `max-height` |
| 用 `width` 而非 `max-width` 做側欄 | 0 | 0 | 0 | ✅ A 抽屜用 `transform`(429/430)、P `.sidebar` 用 `max-width`(100)。但 **A 桌機側欄 `width:220px` 固定、無收合**，M7 從未被行使 |
| 殘留 `transition: width` | **2**（289、807） | **1**（261） | **2**（265、476） | ⚠ 皆為進度條／條圖生長。48 A.3 M0 明文「禁止 `transition: width`」，但 48 §00.10 又保留 `--dur-bar-grow:500ms` 條圖生長 → **48 自我矛盾**，需定案（建議改 `transform:scaleX()`） |
| 用 `transform` 而非 `scale` 做 popover | **2 keyframes**（`fade`111、`pop`221） | **2**（`pageIn`117、`pop`332） | **2**（`pop`555、`bump`90） | ✗ 47 M5 明指「**是 `scale` 不是 `transform`**」。A 已有正確的 `@keyframes popin{scale:.98→1}`(223) 並用於 view-menu/modal/palette/doc-pop，但 `fade`/`pop` 仍是 `translateY` |
| 非 47 §5 五時長的裸時長 | **6**（.16s/.18s×2/.2s/.3s/2s/1.2s/500ms×2） | 0 | **7**（.4s/.7s/26s/.6s×2/.45s×2/.5s×2/1.2s） | 見 4.1/4.3 |
| 非 47 §5 三曲線的 `cubic-bezier` | 0 | 0 | **6**（`( .2,.7,.2,1)`×3、`(.2,.8,.2,1)`×2、`(.2,.9,.3,1.4)`×1） | ✗ 全為 23 §5 的自創曲線，48 #87 已宣告作廢 |
| M1–M7 原語是否實際被使用 | **✗ 全部死碼** | — | — | A 892–902 定義 `.m-hover/.m-text/.m-focus/.m-accordion/.m-pop/.m-drawer/.m-sidebar`，但**全檔各只出現 1 次（即定義本身），markup 零使用** |

### 4.1 A `chilllove-admin-v2.html`

| 檔案 | 行號 | 現況 | 應為哪條 M 規則 |
|---|---|---|---|
| A | 109 | `animation: fade .18s ease-out`（`.page.on` 頁面切換） | **M5**：`opacity, scale var(--dur-slow) var(--ease-decelerate)`；`@keyframes fade`(111) 的 `translateY(3px)` 改 `scale:.96` |
| A | 111 | `@keyframes fade{...transform:translateY(3px)}` | **M5**：`transform` → `scale` |
| A | 150 | `animation: sh 1.2s infinite`（skeleton） | 豁免（23 §5 shimmer 保留）；時長改 `--dur-shimmer`〔48 §00.10 未落地〕，並補 `linear` |
| A | 165 | `animation: pulse 2s infinite`（live dot） | 不在 M1–M7 亦不在 47 任何規則內 → **需定案或移除** |
| A | 174 | `transition: opacity var(--dur-base) var(--ease-in-out)`（`.ai-send`） | **M5** 要求 `--dur-slow` + `--ease-decelerate`；或若是 hover 回饋應改 **M1** |
| A | 177 | `animation: fade .2s ease-out`（`.ai-reply.show`） | **M5**（改用 `popin`） |
| A | 180 | `transition: transform var(--dur-base) var(--ease-standard)`（`.task-chip`） | **M6** 要求 `--dur-slower`；且 48 #87 要求**移除 `translateY(-1px)` hover 位移**（47 未量到任何 hover 位移）→ 應整條刪除、改 **M1** |
| A | 198 | `animation: popin var(--dur-slow) var(--ease-decelerate)`（`.view-menu`） | ✅ 合 **M5** |
| A | 220–221 | `animation: pop .16s ease-out`；`@keyframes pop{transform:translateY(-4px)}`（`.bulkbar`） | **M6**（抽屜／滑入 `transform var(--dur-slower) var(--ease-standard)`）或 **M5**；`.16s` 不在五時長內 |
| A | 285 | `transition: opacity var(--dur-base) var(--ease-in-out)`（`.tooltip`） | **M5**：`--dur-slow` + `--ease-decelerate` |
| A | 289 | `transition: width 500ms var(--ease-decelerate)`（`.hbar` 條圖） | **M0 禁止 `transition: width`**；改 `transform:scaleX()` + `--dur-bar-grow` |
| A | 304 | `animation: fade .18s ease-out`（`.settings.show`） | **M5** |
| A | 331 | `transition: left var(--dur-base) var(--ease-standard)`（`.toggle::after` 把手） | **M0 禁止 `transition: left`**；48 #87 明指改 `transform var(--dur-fast) var(--ease-decelerate)` |
| A | 338 | `animation: popin var(--dur-slow) var(--ease-decelerate)`（`.modal`） | ✅ 合 **M5**（`scale` 起點應為 `.98`，現為 `.98` ✅） |
| A | 348 | `animation: popin ...`（`.palette`） | ✅ 合 **M5** |
| A | 355 | `transition: transform var(--dur-slower) var(--ease-standard), opacity var(--dur-base) var(--ease-in-out)`（`.toast`） | transform 段 ✅ **M6**；opacity 段應為 **M5** 參數 |
| A | 364 | `animation: popin ...`（`.doc-pop`） | ✅ 合 **M5** |
| A | 379 | `transition: opacity var(--dur-base) var(--ease-in-out)`（`.scrim`） | 48 #87 定為「M1 的淡入版」，可豁免；但 47 §H2-2 要求底色改 `rgba(0,0,0,.5)`（見表 5 項 7） |
| A | 410 | `transition: opacity var(--dur-base) var(--ease-in-out)`（橫捲邊緣漸層） | 同 379，可豁免 |
| A | 429–430 | `transition: transform var(--dur-slower) var(--ease-standard), visibility 0s ...`（側欄抽屜） | ✅ 合 **M6**；`visibility 0s` 為延遲切換技法，豁免 |
| A | 617–621 | `transition-duration:.01ms!important`／`.hbar{transition:none}`／`.sidebar{transition:none!important}` | reduced-motion 豁免；建議依 48 A.3 統一為 `--dur-fast` |
| A | 667 | `transition: left var(--dur-base) var(--ease-standard)`（`.tgl::after`） | 同 331，**M0 違規** |
| A | 679 | `transition: transform var(--dur-slower) ..., opacity var(--dur-base) var(--ease-in-out)`（`.savebar`） | transform ✅ **M6**；opacity 段參數應為 **M5** |
| A | 686–687 | `@keyframes nudge{±5px}`；`animation: nudge .3s ease-out` | 47 #88 的 **shake**：應改名 `cl-shake`、`--dur-shake:300ms` + `--ease-standard`，**並接到 modal 驗證失敗**（現只綁 `.savebar`，`cl-shake` grep 命中 0） |
| A | 807 | `transition: width 500ms var(--ease-decelerate)`（`.progress i`） | 同 289，**M0 禁止** |
| A | 882–883 | `animation:none`／`transition:none`（reduced-motion） | 豁免 |
| A | 892–902 | M1–M7 原語定義 | ⚠ **死碼**：markup 零引用 |

### 4.2 P `chilllove-platform-admin.html`

| 檔案 | 行號 | 現況 | 應為哪條 M 規則 |
|---|---|---|---|
| P | 114 / 117 | `animation: pageIn var(--dur-slow) var(--ease-decelerate)`；`@keyframes pageIn{transform:translateY(3px)}` | **M5**：`transform` → `scale`（時長曲線已對） |
| P | 244 | `transition: color ..., border-bottom-color var(--dur-fast) var(--ease-decelerate)`（`.tab`） | color 段 ✅ **M2**；`border-bottom-color` 應併入 **M3** 的三屬性寫法 |
| P | 261 | `transition: width var(--dur-slowest) var(--ease-in-out)`（`.meter i`） | **M0 禁止 `transition: width`**；改 `transform:scaleX()` |
| P | 284 | `transition: left var(--dur-base) var(--ease-standard)`（`.switch::after`） | **M0 禁止 `transition: left`**；改 `transform` |
| P | 330 / 332 | `animation: pop var(--dur-slow) var(--ease-decelerate)`；`@keyframes pop{transform:scale(.97) translateY(4px)}` | **M5**：**混用 `transform` 與位移**，47 M5 明指要用獨立 `scale` 屬性避免衝突；`.97` 應為 `.98`（modal） |
| P | 341 | `transition: opacity var(--dur-slow) ..., transform var(--dur-slow) var(--ease-decelerate)`（`.toast`） | transform 段應為 **M6**（`--dur-slower` + `--ease-standard`） |
| P | 355 | `animation: pop ...`（`.doc-pop`） | 同 330 |
| P | 376 | `transition: opacity var(--dur-slower) var(--ease-standard)`（`.nav-veil`） | 應為 M1 淡入版（`--dur-base` + `--ease-in-out`）；且底色須改 `rgba(0,0,0,.5)` |
| P | 382 | `transition: opacity var(--dur-base) var(--ease-standard)`（橫捲漸層） | 曲線應為 `--ease-in-out` |
| P | 398–399 | `transition: transform var(--dur-slower) var(--ease-standard), visibility 0s ...` | ✅ 合 **M6**；`visibility` 豁免 |
| P | 447–448 | `animation: sheetUp var(--dur-slower) var(--ease-standard)`；`@keyframes sheetUp{translateY(18px)}` | ✅ 合 **M6**（bottom sheet 用位移正確）；`18px` 應 token 化 |
| P | 495–496 | reduced-motion `.01ms` | 豁免 |

### 4.3 S `chilllove-storefront-v2.html`

| 檔案 | 行號 | 現況 | 應為哪條 M 規則 |
|---|---|---|---|
| S | 69 | `transition: right var(--dur-slow) var(--ease-decelerate)`（nav 底線） | **M0 禁止幾何屬性轉場**；改 `transform:scaleX()` |
| S | 74 | `transition: opacity ..., transform ..., visibility ...`（`.mega`） | **M5**：`transform` → `scale`；`visibility` 豁免 |
| S | 88 | `transition: transform var(--dur-slow) var(--ease-standard)`（`.cart-n`） | **M6** 要求 `--dur-slower`；或視為 M5 的 `scale` |
| S | 89–90 | `animation: bump .4s`；`@keyframes bump{scale(1.35)}` | 不在 M1–M7；`.4s` 不在五時長內 → 定案為品牌動效或改 `--dur-slowest` |
| S | 96 | `transition: opacity var(--dur-slower) var(--ease-standard)`（`.nav-veil`） | 遮罩淡入應 `--dur-base` + `--ease-in-out`；底色 `rgba(34,30,26,.45)` vs 真值 `rgba(0,0,0,.5)` |
| S | 107 | `transition: opacity var(--dur-base) var(--ease-standard)` | 曲線應 `--ease-in-out` |
| S | 123 | `.btn` 六屬性 transition，末段 `transform var(--dur-base) var(--ease-standard)` | 前五段 ✅ M1/M2/M3；**`transform` 段是 hover 位移，47 未量到任何 hover 位移 → 應移除** |
| S | 136 | `animation: sp .7s linear infinite`（spinner） | 不在 M1–M7；47 §7 待辦 13，需定案 |
| S | 163 | `animation: mq 26s linear infinite`（marquee） | 品牌裝飾；23 §5 已規定 reduced-motion 停用（S:1038 ✅ 已做） |
| S | 174 | `transition: transform .6s cubic-bezier(.2,.7,.2,1)`（`.pcard .art`） | **曲線不在三曲線內**；`.6s` 不在五時長內。23 §5「前台商品卡 hover 圖 scale 1.03–1.04、600ms」→ 需在 47 補收或明列為前台例外 |
| S | 176 | `transition: opacity .45s`（`.pcard .alt`） | 裸時長；改 `--dur-slow` |
| S | 178 | `transition: opacity ..., transform var(--dur-slow) var(--ease-decelerate)`（`.quick`） | **M5**：`transform` → `scale` |
| S | 206 | `transition: transform .7s cubic-bezier(.2,.7,.2,1)`（`.ccard .art`） | 同 174 |
| S | 251 | `transition: opacity var(--dur-slower) var(--ease-standard)`（`.veil`） | 同 96 |
| S | 253 | `transition: transform var(--dur-slower) var(--ease-standard)`（`.drawer`） | ✅ 合 **M6** |
| S | 265 | `transition: width .5s cubic-bezier(.2,.8,.2,1)`（`.ship-fill`） | **M0 禁止 `width`**；曲線與時長皆階外 |
| S | 287 | `transition: transform var(--dur-slow) var(--ease-decelerate)`（`.toastf`） | **M6**：`--dur-slower` + `--ease-standard` |
| S | 294 | `transition: opacity ..., transform ..., visibility ...`（`.md`） | **M5**：`transform` → `scale` |
| S | 302 | `transition: opacity ..., visibility ...`（`.fs`） | opacity ✅ M5 參數；`visibility` 豁免 |
| S | 354 | `animation: sh 1.2s linear infinite`（skeleton） | 豁免；改 `--dur-shimmer` |
| S | 370 | `transition: transform var(--dur-fast) var(--ease-decelerate)`（`.fgrp .caret` 旋轉） | 48 定 caret 旋轉可借 M3 曲線，但應改用 `rotate` 屬性而非 `transform` |
| S | 429 / 469 / 538 | M3 三屬性 transition | ✅ 合 **M3** |
| S | 456 | `transition: transform var(--dur-fast) var(--ease-decelerate)`（`.acc-item .caret`） | 同 370 |
| S | 476 | `transition: width .5s cubic-bezier(.2,.8,.2,1)`（`.rbar .tf`） | 同 265 |
| S | 554–555 | `animation: pop .45s cubic-bezier(.2,.9,.3,1.4)`；`@keyframes pop{scale(.3)}` | **M5**：時長與曲線皆階外（`1.4` 是回彈曲線，三曲線內無回彈） |
| S | 608 | `transition: transform .6s cubic-bezier(.2,.7,.2,1)`（`.acard .art`） | 同 174 |
| S | 641 / 654 | `transition: transform var(--dur-slower) var(--ease-standard)` | ✅ 合 **M6** |
| S | 649 | `transition: transform var(--dur-base) var(--ease-standard)`（`.sw-t::after` 把手） | **M6** 要求 `--dur-slower`；或依 48 #87 用 `--dur-fast` + `--ease-decelerate` |
| S | 1036–1038 | reduced-motion `.001ms`／`animation:none` | 豁免 |

**表 4 統計**：186 個動效宣告片段，**不合規 69、扣除合理豁免 13 → 實質不合規 56**（A 22、P 10、S 24）。`transition: all` 殘留 **0**（主原型）／**7**（deprecated 兩檔）。

---

## 表 5 · 第四輪新真值（47 §C／§D／§E／§H2）落地檢查

> 這八項是 47 第三／四輪剛確認的真值，**48 號寫作時尚不存在**，因此三份原型必然全缺。本表逐一確認並定位到具體要改的行。

### 5.1 逐項落地狀態

| # | 47 真值 | 出處 | A | P | S | 狀態 |
|---|---|---|:--:|:--:|:--:|---|
| 1 | 髮絲線 = **1 裝置像素**（dpr 媒體查詢三檔） | §C | ✗ | ✗ | ✗ | **全缺**。三份原型 `-webkit-min-device-pixel-ratio`／`min-resolution`／`dppx` grep 命中 **0**；1px 邊框宣告 **A 77／P 27／S 95 = 199 條** |
| 2 | 表單控件的框用 **`inset box-shadow`** 而非 `border` | §H2-4 | ✗ | ✗ | ✗ | **全缺**。現存 inset 陰影只用在 primary 按鈕高光（A:119/690、P:141）與選取態（S:332/408/431/547/550），**不是控件框** |
| 3 | radio 已選 = **主文字色填滿 + 白內點**（非品牌色） | §H2-4 | ✗ | ✗ | ✗ | **全缺**。A 唯一的 radio（markup 4346）套用 `.cb`（216）＝ checkbox 樣式 + `accent-color:var(--brand)`；S 全用瀏覽器原生 radio（`.rcard` 內，1942/2326/2354/2383/2390…）；P 無 radio |
| 4 | disabled = **只降文字色到 `#B5B5B5`、底色不動** | §E | ✗ | ✗ | ✗ | **全缺，且做法相反**（一律降 opacity） |
| 5 | focus = **`box-shadow` 雙層**（間隙 + 環）、`outline: none` | §H2-3 | ✗ | ✗ | ✗ | **全缺**。全域焦點環是 `outline`；輸入框是**單層** glow |
| 6 | 語意色 **5 族（含 caution 與 warning 分家）× 5 層 × 3 態 = 75** | §H2-1 | ✗ | ✗ | ✗ | **全缺**。`caution` grep 命中 **0**；現為 6 族 × 2 層 × 1 態 = 12 |
| 7 | z-index：base1 / sticky100 / 表格100 / 批次列510 / topbar517 / drawer518 / scrim518(**rgba(0,0,0,.5)**) / dialog519 / popover520 | §G、§H2-2 | ✗ | ✗ | ✗ | **全缺**，且 **A 的 popover 低於 modal**（見 5.2 項 7） |
| 8 | badge 狀態圖示 **● / ○ / ⊘** | §D | ~ | ~ | ✗ | A/P 有 `.pip`（○）／`.pip.full`（●）／`.pip.half`（**半填漸層，非 ⊘**）；S `.badge .pip` 只有實心一種（348） |

### 5.2 逐項要改的位置（可直接照著動手）

**項 1 · 髮絲線（dpr 三檔）**

| 檔 | 要改的行（1px 邊框宣告，全數） |
|---|---|
| A | `border`：79 81 86 89 117 129 144 148 149 170 176 180 195 197 204 229 232 249 264 297 305 308 311 322 324 502 542 699 704 724 730 742 745 749 751 754 759 766 781 787 795 796 803 808｜`border-bottom`：75 157 194 207 209 241 265 318 339 341 349 636 670 710 771 815｜`border-top`：106 233 247 294 315 354 510 553 659 713｜`border-left`：128｜`border-right`：93 700｜`border-top-width`：504 888 890｜`border-width`：536 |
| P | `border`：85 86 88 123 139 154 174 182 192 223 304 322 436｜`border-bottom`：125 206 214 220 230 231 243 288 310 333 440｜`border-top`：259 339｜`border-right`：100 |
| S | `border`：80 126 128 183 194 218 238 242 248 272 310 329 337 340 344 345 346 347 358 379 386 388 390 394 407 429 432 451 469 495 510 523 529 534 538 543 546 549 582 614 637 640 659 668 697 702 917 956｜`border-bottom`：62 72 107 111 162 209 235 256 262 267 297 366 367 383 454 461 484 505 576 577 580 586 591 646 683 792 857｜`border-top`：120 162 209 235 244 281 300 383 453 465 478 498 504 532 603 625 629 824｜`border-left`：211｜`border-right`：845 |

作法（47 §C 自寫版）：新增 `.cl-hairline` 類別 ＋ `@media (-webkit-min-device-pixel-ratio:1.5),(min-resolution:1.5dppx){border-width:.667px}` ＋ `@media (...2dppx){border-width:.5px}`。**現況 1px 在 Retina 上比實站粗一倍，是「看起來就是不對」的主因之一。**

**項 2 · 表單框改 inset box-shadow**

| 檔 | 行 | 現況 | 改法 |
|---|---|---|---|
| A | 144 | `.input{border:1px solid #c9cace}` | `box-shadow: inset 0 0 0 var(--hairline) var(--border-strong)`，移除 `border`（不佔 box model、可做次像素） |
| A | 204 | `.filterbar{border:1px solid #c9cace}` | 同上 |
| A | 726 / 753 | 其他輸入類 `:focus{border-color:...}` | 同上，focus 態改雙層 inset+outer |
| P | 86 | `.searchbox{border:1px solid #3a3b40}` | 同上 |
| P | 154 | `.input{border:1px solid #c9cace}` | 同上 |
| P | 223 | `.filter-chip{border:1px dashed #c9cace}` | dashed 需保留 border（inset 陰影無 dashed），列為例外 |
| S | 310 | `.inp,select.inp,textarea.inp{border:1px solid var(--line)}` | 同上 |
| S | 329 / 429 / 469 / 538 | `.rcard` / `.pill` / `.sbtn` / `.store-op` | 同上 |

**項 3 · radio**

| 檔 | 行 | 現況 | 改法 |
|---|---|---|---|
| A | 216–217 | `.cb{width:16px;height:16px;accent-color:var(--brand)}` 同時被 checkbox 與 radio 共用（markup 4346） | 拆出 `.cl-radio`：`appearance:none;16×16;border-radius:50%;background:transparent;box-shadow:inset 0 0 0 var(--hairline) var(--border-strong)`；`:checked{background:var(--text)}` ＋ `::after` 白色內點。**視覺盒鎖死 16×16**，命中區沿用 `::before` |
| S | 1942 1944 2326 2354 2383 2390 …（`.rcard` 內原生 radio） | 完全無樣式，走瀏覽器原生 | 同上（前台色改 `--ink`） |
| — | — | 47 §H2-4 提醒 | **已選用主文字色而非品牌色是「克制感」的來源**；我方原型用品牌色填滿，須先決定跟不跟（本稽核建議：後台跟、前台用 `--ink` 等效） |

**項 4 · disabled**

| 檔 | 行 | 現況 | 改法 |
|---|---|---|---|
| A | 118 | `.btn:disabled{opacity:.45;...}` | `color:#B5B5B5`（新 `--text-disabled`）；**底色不動**；移除 `opacity` |
| A | 231 | `.pg:disabled{opacity:.4}` | 同上 |
| A | 768 | `:disabled{opacity:.35}` | 同上 |
| P | 140 | `.btn:disabled{opacity:.45}` | 同上 |
| S | 134 | `[disabled],.btn.dis{opacity:.42}` | 同上（前台等效弱化色） |
| S | 275 | `[disabled]{opacity:.3}` | 同上 |
| — | 48 §00.6 | `--disabled-opacity:.45` | **此 token 依 47 §E 應作廢**，不要落地 |

理由（47 §E）：降 opacity 會讓 disabled 元素**在深色底上發灰、淺色底上發白**，不穩定；只換文字色則到處一致。

**項 5 · focus 雙層 box-shadow**

| 檔 | 行 | 現況 | 改法 |
|---|---|---|---|
| A | 70 | `:focus-visible{outline:2px solid var(--focus);outline-offset:1px}` | `outline:none; box-shadow: 0 0 0 2px var(--bg), 0 0 0 4px var(--cl-focus-ring)` |
| A | 146 | `.input:focus{outline:none;border-color:var(--focus);box-shadow:0 0 0 2px rgba(42,120,214,.18)}` | 單層 → 雙層；且環寬真值為 **4 個實體像素**（dpr1.5 下 computed 2.667px） |
| A | 171 | `:focus-within{box-shadow:0 0 0 3px rgba(42,120,214,.14)}` | 3px 不在階上 → 雙層 2/4 |
| A | 726 / 753 | 同 146 | 同上 |
| P | 75 | `:focus-visible{outline:2px solid var(--focus);outline-offset:1px}` | 同 A:70 |
| P | 156 | `.input:focus{...box-shadow:0 0 0 2px rgba(42,120,214,.18)}` | 同 A:146 |
| S | 41 | `:focus-visible{outline:2px solid var(--clay);outline-offset:2px}` | 同上（環色用前台色） |
| S | 314 / 698 | `box-shadow:0 0 0 3px rgba(169,80,44,.13);outline:none` | 3px → 雙層 2/4 |
| — | ⚠ 衝突 | 48 §A.2「**不准用 `box-shadow` 模擬焦點環**（會被 `overflow:hidden` 父層裁掉）」 | **與 47 §H2-3 直接抵觸**。47 是量測真值、優先；48 的顧慮改用 `overflow:clip; overflow-clip-margin` 解決（48 §A.2 自己已寫出這個備案） |
| — | 殘留缺口 | 47 §H2-3 註明「環的**確切顏色**待定（目視為深中性，非品牌藍）」 | 我方 `--focus:#2a78d6` 是藍；要不要跟「深中性」需使用者決定 |

**項 6 · 語意色 75 token**

| 現況 | 需求 | 差額 |
|---|---|---|
| A/P `:root` 各有 `success/warning/critical/attention/info/ai` × `{基色, -bg}` = **12 個** | **5 族**（info / success / **caution** / **warning** / critical）× **5 層**（bg-surface / bg-fill / border / icon / text）× **3 態**（base / hover / active）= **75**，另 critical 專屬 `button-bg-fill` + `button-gradient-bg-fill` = **77** | **缺 65** |

- **`caution` 完全不存在**（三份原型 + 23 + 48 全文 grep 命中 0）。47 §H2-1 明指「`caution` 與 `warning` 是兩個不同的族（黃 vs 橘）」，我方只有一個 warning → **少一族**。
- 現有 `attention`（`#6d5f00`/`#f9f1bc` 黃）在語意上接近 47 的 `caution`，**須先定案命名對映**再展開 75 階，否則會生出重複族。
- 明度公式（47 §H2-1）：`surface` 落在 **L 94–97%**，hover **−2~3**，active **−4~7**。現有 `-bg` 值明度：`--success-bg #e2f1ea` L≈92.5、`--warning-bg #fdf3dc` L≈96.1、`--critical-bg #fdecee` L≈96.2、`--attention-bg #f9f1bc` L≈95.7、`--info-bg #e8f2fa` L≈94.9 → **success-bg 偏暗 1.8 個點，需上調到 ≥94**。
- 落地位置：A `:root` 17–19 行、P `:root` 26–31 行；S 前台無語意色系統，須另建。

**項 7 · z-index**

| 47 真值 | A 現況 | P 現況 | S 現況 |
|---|---|---|---|
| `1` 基礎堆疊 | 261 409 `z-index:1` | — | 96 330 561 680 `z-index:1` |
| `100` sticky／常駐導航／表頭 | 413 414 520 `z-index:2`、220 `z-index:3` | 202 `z-index:5` | 332 337 524 681 843 872 `z-index:2` |
| `510` 表格批次操作 sticky 列 | **220 `.bulkbar z-index:3`** | — | — |
| `517` topbar／側欄把手 | **75 `.topbar z-index:40`** | **81 `.topbar` / 100 `.sidebar` z-index:40** | 62 `z-index:30` |
| `518` drawer / scrim（**`rgba(0,0,0,.5)`**） | **379 `.scrim z-index:44` bg `rgba(26,28,30,.42)`**、426 `.sidebar z-index:45`、562 `z-index:60` | **376 `.nav-veil z-index:39` bg `rgba(26,28,30,.42)`** | 251 `.veil z-index:40` bg `rgba(34,30,26,.45)`、253 `.drawer z-index:41` |
| `519` dialog | **336 `.overlay z-index:80` bg `rgba(26,28,30,.4)`** | **328 `.overlay z-index:80`** | 293 `z-index:42`、302 `.fs z-index:44` |
| `520` popover（**必須 > dialog**） | 🔴 **197 `.view-menu z-index:10`** — 遠**低於** modal 的 80 | 354 `.doc-pop z-index:95`（> overlay 80 ✅ 順序對、絕對值錯） | 74 `.mega z-index:31` |
| — | 其他：285/305 `z-index:5`、303 `.settings 50`、355 `.toast 90`、361 `.annot-bar 70`、363 `.doc-pop 95`、676 `.savebar 65` | 341 `.toast 90`、352 `z-index:70`、354 `z-index:95` | 654 38、640 39、839 45、659/663 62、287 70、670 96、46 99、1023 −1 |

🔴 **A 的 `.view-menu`（popover／下拉選單）z-index:10 低於 `.overlay`（modal）z-index:80** → **modal 內開下拉選單會被對話框蓋住**。47 §H2-2 專門為此做了實測，明確結論 `popover(520) > dialog(519)`。這正是 47 標為「猜錯就是肉眼可見 bug」的那一條。

處置：三份原型改採 47 §G 的窄帶命名 `--z-base:1 / --z-sticky:100 / --z-overlay-base:510`，浮層以 `510+n` 排到上限 520；同時 scrim 底色統一 `rgba(0,0,0,.5)`（A:336/379、P:328/376、S:96/251 六處）。

**項 8 · badge 狀態圖示 ● / ○ / ⊘**

| 檔 | 行 | 現況 | 改法 |
|---|---|---|---|
| A | 134–136 | `.pip{7×7;border:1.5px solid currentColor}`（○）／`.pip.full{background:currentColor}`（●）／`.pip.half{linear-gradient(90deg,currentColor 50%,transparent 50%)}` | `.half` → **`.pip--blocked`（⊘ 斜線圓）**：保留圓環，疊一條 45° 斜線（`::after` 旋轉的 1px 條或 SVG）。47 §D：**實心 ● = 完成｜空心 ○ = 未開始｜斜線 ⊘ = 部分／受阻** |
| A | markup | `class="pip full"`×16、`class="pip half"`×6、`class="pip"`×3 = **25 個 badge 有圖示** | 但靜態 badge 共 **32** 個（`b-default`11 / `b-success`8 / `b-warning`6 / `b-info`4 / `b-attention`2 / `b-critical`1，另 1 個動態 `b-${tone}`）→ **至少 7 個 badge 無狀態圖示**（如「店主」「員工」「子網域」「未連線」）；47 §D：**每個徽章都帶前置狀態圖示** |
| P | 161–163 | 同 A（`.pip` 8×8、`border:1.6px`） | 同上；`1.6px` 為 off-scale |
| P | markup | `full`×26、`half`×11、`pip`×12 + 5 處動態 | 同上 |
| S | 348 | `.badge .pip{6×6;background:currentColor}` — **只有實心一種** | 需補 ○ 與 ⊘ 兩形 |
| — | 圓角 | A `.badge{border-radius:999px}`(133)、P `--r-pill`(160)、S `2px`(347) | 47 §D：**badge = r≈8 圓角矩形**，**tag 才是全圓藥丸**。三份原型把 badge 畫成 tag，且 **tag 元件（含 `+n` 收合）完全不存在** |

**無障礙依據**：47 §D 指出圖示形狀本身編碼狀態，是 **WCAG 1.4.1 Use of Color** 的標準做法。目前 8 個以上的 badge 只有色塊＋文字 → **既是保真度缺口也是無障礙缺陷**。

**表 5 統計**：8 項全部未落地（**全缺 6、部分 2**）；展開後具體待改位置 **A 約 140 處、P 約 55 處、S 約 115 處**。

---

## 表 6 · 48 號自我宣稱查核

> 兩項宣稱：①§0 已把 47 §8 的 #81–#89 展開成修正指令；②§00 新增了一批 token。逐一機械驗證是否屬實，以及是否與 47 第三／四輪真值衝突。
>
> **前提**：`48` 全文 grep `第三輪`／`H2`／`2294`／`根字級`／`髮絲線`／`inset box-shadow`／`caution`／`dpr`／`0.667` → **全部命中 0**。48 §0.10 明寫「**47 的量測全部在 683px 有效視口（窄版）取得**」——這句話在第三輪（root=16px、桌機 2294px）之後**已不成立**。**48 是在第二輪之後寫的，其所有「47 沒有 X」的宣稱都需重新檢查。**

### 6.1 宣稱一：§0 已展開 #81–#89 → **屬實**

| # | 47 §8 修正項 | 48 §0 是否展開 | 是否給到「23 原文 → 改成 → 影響哪些選擇器」三段 | 與 47 第三/四輪是否衝突 |
|---|---|:--:|:--:|---|
| #81 | 間距 10→7 階 | ✅ | ✅ A 15 條、P 3 條、S 豁免 | 無衝突 |
| #82 | UI 預設 14→13px | ✅ | ✅ A 12 條、P 2 條 | 無衝突；且第三輪 §B 再次量到儲存格 12/16/500、tab 13/20/500，**佐證成立** |
| #83 | 大標題字重 → 450 | ✅ | ✅ A 13 條、P 全 h1–h3 | 無衝突。但 47 §6.5 的 **550**（split 鈕）48 完全沒收 → **遺漏一階** |
| #84 | 圓角四階 + 堆疊卡片單邊圓角 | ✅ | ✅ A 逐值列出 9/10/14/7/6/5/16/3px 的去向 | 無衝突 |
| #85 | 控件高度四階 + topbar 56 + sidebar 240 | ✅ | ✅ | 無衝突；第三輪 §B 桌機實測 28/32/24/36 **與窄版同階**，48 §0.10 標的「本文件最大的已知風險」**已被證實為虛驚，可解除** |
| #86 | checkbox 16 + 列級 32 命中區 | ✅ | ✅ 含「≤429 的 `.cb{20px}` 要刪掉」 | 無衝突；A 已落地（216–217、606–607） |
| #87 | 動效 5×3 + M1–M7 + 清 `transition:all` | ✅ | ✅ 逐處列出 10 個 `transition:all` 與 `var(--tr)` 去向 | 無衝突；三份主原型已清乾淨（表 4） |
| #88 | Modal 驗證失敗 shake | ✅ | ✅ 指定改名 `cl-shake` 共用 `nudge` | 無衝突；**尚未落地**（`cl-shake` grep 命中 0） |
| #89 | 中性色只取層級關係 | ✅ | ✅ 含「`--surface-2` 比 `--bg` 淺會反轉層級」的關鍵發現 | 無衝突 |
| #80 / #90 | 44 號加註／桌機補測 | ✅ 在 §0.10 處置 | ✅ | #90 的 6 項〔待覆核〕中，**桌機控件高度階已由第三輪 §B 解除**，其餘 5 項仍待 |

→ **宣稱一屬實：9/9 展開完成，且每條都給到三段式指令與逐選擇器清單。品質高於宣稱。**
→ 唯一遺漏：**47 §6.5 的字重 550 未被收進 #83 的字重表**。

### 6.2 宣稱二：§00「新增 63 個 token」→ **數字不實**

> **快照邊界**：本節查核對象固定為 commit
> `e50b9120cc9b2514fde4995a5ff4f6ff15332bff` 的 48／23，不是目前 HEAD；目前樹不得沿用
> 82／4／78。完整可重跑命令見 `docs/specs/92-claim-index.md` CLAIM-005。

| 項目 | 查核結果 |
|---|---|
| 48 全文是否寫出「63」這個數字 | **否**。grep `63` 命中 0。這個數字不是 48 自己宣稱的 |
| §00 css 區塊實際宣告的 token（去重） | **82 個** |
| 其中與 23 §1 重複（非新增） | **4 個**：`--r-pill`、`--sh`、`--sh-pop`、`--sh-modal` |
| **真正新增** | **78 個** |
| 常見誤數來源 | 用行首錨定 regex（`^\s*--x:`）逐行抓只會得到 **63**，因為 §00.9 z-index 與 §00.12 版面尺寸有 **多 token 同行**（`--z-content: 0;   --z-sticky: 3;   --z-bulkbar: 5;   --z-shell: 40;`），一行只算一個 → 漏掉 19 個 |

→ **在上述歷史快照，「63」是逐行掃描的產物，查核值是 82 宣告 / 78 新增。** 這組數字只用來更正當時的記帳，不得外推為目前 HEAD。

### 6.3 §00 與 47 第三／四輪的**直接衝突**（48 基於已作廢前提）

| 48 條目 | 48 的內容 | 47 第三/四輪真值 | 衝突程度 |
|---|---|---|---|
| **§00.5 + §A.2 focus 環** | `--focus-ring-w:2px` + `outline: 2px solid` + **「不准用 `box-shadow` 模擬焦點環」** | §H2-3：`outline-style: none`、**雙層 `box-shadow`**（間隙 + 環）、環寬 = **4 個實體像素** | 🔴 **P0 直接抵觸**。48 的禁令會讓實作者永遠做不出實站的 focus 環 |
| **§00.4 邊框寬** | `--bw-100: 1px`（「預設框線」） | §C：髮絲線 = **1 裝置像素**（dpr 1.5→0.667px、dpr 2→0.5px）；§H2-4：表單框用 **inset box-shadow** 而非 border | 🔴 **P0**。固定 1px 在 Retina 上粗一倍 |
| **§00.6 `--disabled-opacity:.45`** | 把「降 opacity」token 化 | §E：**只降文字色到 `#B5B5B5`、底色不動**，明文說降 opacity「不穩定」 | 🔴 **P0**。此 token 應作廢而非落地 |
| **§00.9 z-index** | 「23 §1 有散列、未 token 化；**47 完全沒有**」→ 自訂 `0/3/5/40/44/50/60/65/70/80/81/85/90/95` 14 階 | §G + §H2-2：**47 有完整實測階梯** `1/100/400/510/517/518/519/520`，且明文「浮層全部擠在單一窄帶（510–520）內」 | 🟠 **P1**。順序關係（popover>modal）48 有守住，但**絕對值與「窄帶」設計原則全錯**，且「47 完全沒有」是錯誤前提 |
| **§00.13 斷點** | 「**47 完全沒有**；取自 34 §1」→ 沿用 4 階 px | §F：**47 有權威 8 階 em 階梯**（從 stylesheet 直接抽出，附出現次數），並明文「我們三份原型全部用 px 斷點，**應改為 em**」 | 🔴 **P0**。48 把已被推翻的 34 §1 固化成契約 |
| **§00.7 語意色框線階** | 為 6 族各補 1 個 `-border` = 6 個 token（宣稱「23 只有 bg+fg 兩色，banner 需要第三個」） | §H2-1：**5 族 × 5 層 × 3 態 = 75**，且 **caution 與 warning 分家** | 🟠 **P1**。48 補到 3 層就停，缺 fill/icon 兩層、缺 3 態、缺 caution 族 |
| **§00.6 `--scrim: rgba(26,28,30,.42)`** | 自訂遮罩色 | §H2-2 實測 **`rgba(0,0,0,.5)`** | 🟡 P2（視覺差異小但可量化） |
| **§00.11 `--t-3xl:24/32/450`〔待覆核〕** | 桌機頁標題 | 第三輪 §B 未量到頁標題字級 | — 仍待覆核，48 的標記正確 |
| **§00.1 控件高度〔風險註記〕** | 「47 的量測全部在 683px 窄版取得…桌機沿用同階梯是暫定決策，**本文件最大的已知風險**」 | 第三輪 §B 桌機（2294px）實測：導航 28、tab 24、列 32、頂欄 36 → **同階** | ✅ 風險解除，48 的暫定決策**事後證明正確**，可移除註記 |
| **§00.12 `--h-topbar:56` / `--w-sidebar:240`** | 引 47 §0 實測 | 第三輪 §B 覆核：**56 / 240** | ✅ 一致 |
| **§0.10「47 的量測全部在 683px 窄版取得」** | 全文風險前提 | 第三輪在 **root=16px、innerWidth=2294、dpr=1.5** 桌機重測 | 🟠 **P1**。此句已過時，須改寫，否則後續實作者會對所有桌機值打折 |

### 6.4 第三個發現：**token 命名三方分裂**（48 未預見）

| 語意 | 23 §1 | 48 §00 | 三份原型 `:root` 實際 |
|---|---|---|---|
| 控件高度 | 無 | `--ctl-24/28/32/36` | **`--h-24/28/32/36`** |
| 字級 | 散文 scale | `--t-xs: 12 / 16 / 500`（複合，非合法 CSS 值） | **`--t-xs` + `--lh-xs` + `--fw-xs` 三個分開** |
| 圓角 | `--r-card/--r-btn` | `--r-100/200/300/400` + `--r-000` | `--r-100/200/300/400` + `--r-card/--r-btn` 別名 |
| 間距 | 無 | `--sp-050…--sp-600` + `--sp-800/1200` | `--sp-050…--sp-600`（無 800/1200） |
| 頂欄／側欄 | 散文 52/220 | `--h-topbar/--w-sidebar` | A **無 token、硬編 52/220**；P `--topbar-h/--sidebar-w`（值 52/212） |

**§00 的 82 個 token 在原型中的落地率**：

| 原型 | 有落地 | 缺 |
|---|---:|---:|
| A | **1 / 82**（只有 `--sh`） | 81 |
| P | **4 / 82**（`--sh`、`--sh-pop`、`--sh-modal`、`--r-pill`） | 78 |
| S | **0 / 82** | 82 |

→ 三份原型**繞過 23 與 48，自建了第三套命名**（`--h-*`、`--lh-*`、`--fw-*`），且 A 與 P 之間也不一致（`--topbar-h` 只有 P 有）。
→ 這代表 **48 §0 的「影響 A：`.btn{padding:0 14px}`→`0 var(--sp-300)`」這類指令有一半已被原型自行做掉、另一半引用的 token 名在原型裡不存在**。M0 搬 tokens.css 前必須先做**三方命名對齊**，否則會產生 `var(--ctl-32)` 未定義的靜默失效（CSS 自訂屬性未定義時整條宣告失效，不報錯）。

**表 6 統計**：宣稱一 **屬實**（9/9）；宣稱二 **數字不實**（實為 82 宣告 / 78 新增，非 63）；與 47 第三／四輪衝突 **11 條**（P0 4、P1 4、P2 1、已解除 2）；額外發現命名三方分裂 **1 項**。

---

## P0 / P1 / P2 彙總

**分級定義**：**P0** = 會讓原型明顯不像實站，或違反無障礙（WCAG）；**P1** = 系統性偏差，不改會在 M0 擴散成技術債；**P2** = 局部或美學層級。

### P0（完整清單，13 條）

| # | 問題 | 依據 | 位置 | 為什麼是 P0 |
|---|---|---|---|---|
| **P0-1** | **髮絲線全部硬寫 1px，無 dpr 三檔** | 47 §C | A 77 條 / P 27 條 / S 95 條 = **199 條** 1px 邊框宣告；`dppx` grep 命中 0 | Retina 上所有分隔線、卡框、表格線**比實站粗一倍**。47 §C 明指這是「看起來就是不對」的主因之一。影響每一個畫面 |
| **P0-2** | **A 的 popover（`z-index:10`）低於 modal（`z-index:80`）** | 47 §H2-2 | A:197 `.view-menu` vs A:336 `.overlay` | **modal 內開下拉選單會被對話框蓋住**——肉眼可見的功能性 bug。47 專門為此做實測 |
| **P0-3** | **disabled 用降 opacity，非降文字色** | 47 §E | A:118/231/768、P:140、S:134/275（6 處）；48 §00.6 還把它 token 化為 `--disabled-opacity` | 深色底發灰、淺色底發白，**跨元件不一致**；且 opacity 會連帶降低本已合格的對比，可能跌破 4.5:1 |
| **P0-4** | **focus 環用 `outline` 單層，非雙層 `box-shadow`** | 47 §H2-3 | A:70/146/171/726/753、P:75/156、S:41/314/698（10 處） | 焦點可見性是 WCAG 2.4.7 底線；且**48 §A.2 明文禁止 box-shadow 焦點環，與 47 直接抵觸**，不先裁決會讓實作者做錯 |
| **P0-5** | **badge 缺 ⊘ 斜線圓；至少 7 個 badge 完全沒有狀態圖示** | 47 §D | A:134–136 + markup 32 個靜態 badge / 25 個有 pip；P:161–163；S:348 只有實心一種、markup 10 處 `.pip` 對 10 個 badge | **WCAG 1.4.1 Use of Color**：色盲使用者無法分辨狀態。47 明列為「既是保真度缺口，也是無障礙缺陷」 |
| **P0-6** | **斷點全部 px、零 em** | 47 §F | **20 個寬度型 `@media` 全部**（A 9 / P 4 / S 7，含重複宣告） | 47 §F 明指 em 斷點是**無障礙設計決定**：使用者調大預設字型時版面須提早換寬鬆佈局。「一行改動換一整類無障礙情境」 |
| **P0-7** | **48 §00.13 把 34 的 4 階 px 斷點固化成契約，並宣稱「47 完全沒有斷點」** | 47 §F | 48:§00.13 | 錯誤前提寫進實作契約 → M0 會照錯的做。47 §F 是**從 stylesheet 直接抽出的權威值**（8 階、附出現次數） |
| **P0-8** | **48 §A.2「不准用 box-shadow 模擬焦點環」與 47 §H2-3 直接抵觸** | 47 §H2-3 | 48:§A.2 | 兩份文件互相矛盾，實作者無所適從。須立刻裁決（47 優先，48 的裁切顧慮用 `overflow-clip-margin` 解） |
| **P0-9** | **48 §00.4 `--bw-100:1px` 與 47 §C 髮絲線抵觸** | 47 §C | 48:§00.4 | 同 P0-1，且被寫成「預設框線」token，會固化錯誤 |
| **P0-10** | **48 §00.6 `--disabled-opacity:.45` 與 47 §E 抵觸** | 47 §E | 48:§00.6 | 同 P0-3，此 token 應作廢而非落地 |
| **P0-11** | **頂欄高 52（真值 56）、側欄寬 220/212（真值 240）** | 47 §0、§B | A:75/92/379/424/426/796（硬編 52）、A:93（220）；P:52（`--topbar-h:52px;--sidebar-w:212px`） | 這是**每一頁最上面與最左邊的兩個尺寸**，差 4px / 20–28px，整體版面比例都偏；48 #85 已下指令但**未執行** |
| **P0-12** | **secondary 按鈕用「白底＋邊框」，實站是「淺灰實心、無邊框、三層只靠填色深淺分」** | 47 §D、§6.5 | A:121 `.btn-sec{background:#fff;border-color:#c9cace}`、P 同 | 47 §D 明寫「我們原型目前 secondary 用白底＋邊框，**方向就不對**」。按鈕是全站出現最多的元件 |
| **P0-13** | **語意色缺 `caution` 族**（caution 與 warning 在實站是兩族：黃 vs 橘） | 47 §H2-1 | A `:root` 17–19、P `:root` 26–31；`caution` grep 命中 0（三原型 + 23 + 48） | 少一族 → 「未出貨（黃・○）」與「部分已履行（橘・⊘）」會被畫成同一個顏色，**狀態不可分辨**（連同 P0-5 一起就是雙重失效） |

### P1（9 條）

| # | 問題 | 位置 |
|---|---|---|
| P1-1 | 表單控件框用 `border` 而非 `inset box-shadow`（47 §H2-4） | A:144/204/726/753、P:86/154、S:310/329/429/469/538 |
| P1-2 | radio 無自訂樣式；已選未用主文字色 + 白內點（47 §H2-4） | A:216–217（radio 共用 checkbox 樣式）、S 全部原生 radio |
| P1-3 | 語意色只有 12 個（需 75+2）；缺 fill/icon 兩層、缺 hover/active 兩態；`--success-bg` 明度 92.5 低於 94–97 帶 | A `:root` 17–19、P `:root` 26–31 |
| P1-4 | z-index 未採 47 的窄帶（1/100/510–520）；scrim 底色 `.4/.42/.45` 而非 `rgba(0,0,0,.5)` | A 19 處、P 8 處、S 25 處；scrim 6 處 |
| P1-5 | **A 的 M1–M7 原語（892–902）是死碼**，markup 零引用 | A:892–902 |
| P1-6 | 56 個動效宣告不合 M1–M7（含 `transition: left/width/right` 等 M0 禁止的幾何屬性 7 處） | A 22、P 10、S 24；幾何屬性：A:289/331/667/807、P:261/284、S:69/265/476 |
| P1-7 | `@keyframes` 浮層進場仍用 `transform:translateY`，非 M5 的 `scale` | A:111/221、P:117/332、S:555 |
| P1-8 | 表格列高／儲存格內距未對齊桌機真值（列 32 ✅ 但內距應 6/6，現為 8/12） | A:207/209 |
| P1-9 | 48 §0.10「47 全部在 683px 窄版取得」已過時；48 §00.9/§00.13 的「47 完全沒有」為錯誤前提 | 48:§0.10、§00.9、§00.13 |

### P2（7 條）

| # | 問題 | 位置 |
|---|---|---|
| P2-1 | 854 組 / 2257 處裸值未走 `var()`（A 258/578、P 138/226、S 458/1453） | 表 2 全表 |
| P2-2 | `--r-pill`／`--sh-pop`／`--sh-modal` 在 A 未定義卻使用其值（`999px` 13 處、陰影 5 處） | A:78/99/133/180/182/330/408/542/551/665/718/806/807；197/338/348/355/363 |
| P2-3 | `--surface-hover` 一個語意四個色值（`#ededee`/`#fafafc`/`#f0f0f2`/`#e8e8ea`） | A、P 多處 |
| P2-4 | badge 被畫成 tag（全圓藥丸）；真正的 tag 元件（全圓 + `+n` 收合）不存在 | A:133、P:160、S:347 |
| P2-5 | 字重仍大量 600/700（A 31 處、P 9 處、S 38 處），未依 #83 降到 450/500 | 見表 1 §1.3 |
| P2-6 | 字距非 `normal`（A:66 `.01em`；S 大量 `.06–.24em`） | A:66、S 多處 |
| P2-7 | `shake` 未接 modal（`@keyframes nudge` 只綁 savebar，`cl-shake` grep 命中 0）；47 §6.5 字重 **550** 未被任何文件收錄 | A:686–687；23 §1、48 §00.11 |

### 建議處理順序

1. **先裁決四組 47↔48 文件衝突**（P0-8 focus 環／P0-7 斷點／P0-9 邊框寬／P0-10 disabled）——47 為權威，48 §00.4/§00.5/§00.6/§00.9/§00.13 與 §A.2 需改寫。不先做，後面所有修改都可能白工。
2. **再改 4 個全站性視覺真值**（P0-1 髮絲線、P0-11 頂欄/側欄、P0-12 按鈕填色分層、P0-6 em 斷點）——這四項改完，「像不像實站」的觀感差距會收掉大半。
3. **再補 3 個無障礙缺口**（P0-3 disabled、P0-4 focus、P0-5+P0-13 badge 圖示 + caution 族）。
4. **P0-2 的 z-index 一行改動**（`.view-menu` 提到 modal 之上）可隨時插隊，成本最低、收益是消除一個功能性 bug。
5. P1／P2 併入 M0 的 tokens.css 建置一次處理，並在該次同步解決**命名三方分裂**（表 6 §6.4）。
