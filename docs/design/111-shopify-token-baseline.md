# 111 — 本尊 token 基線與頁面骨架（`:root` computed 值表）

> 建立 2026-08-28。依使用者裁定「整體 UI 必須和 Shopify 完全 1:1，完全跟隨他的 CSS」。
> 本檔取代 `47` §6／§H2-1「只取層級關係、色值改用自有調色」的舊處置（見 `110` §2）。
>
> 🔴 **鐵律 9 邊界**：本檔只記 `getComputedStyle` 算出來的**值**，
> 不含 Shopify 的樣式表原始碼、選擇器定義或任何可執行的 CSS 片段。
>
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 元件級量測落各模組 teardown 的「CSS 三段式」節。

## 0. 量測環境（鐵律 19）

| 項 | 值 |
|---|---|
| 日期 | 2026-08-28 |
| 測試店 | `chill-love-u5q5mnzq`（Home／Orders／Analytics 三頁，皆由側欄真實 `href` 導航） |
| 瀏覽器 | Chrome 151，`devicePixelRatio` 1 |
| viewport | **1024×607** CSS px |
| 根字級 | **16px**（⇒ 1rem＝16px；`47` §0 記過的 root 24px 污染本次無） |
| 斷點帶 | sm ✅ / md ✅ / **lg ❌** / xl ❌ ⇒ 落在 **md 帶（768–1039px）**，非桌機 1280 |
| `--polaris-version-number` | **`25.87.0`** |
| 樣式表 | 41 份，**全部 same-origin 可讀、0 份被跨域擋** ⇒ 不需要「命名前綴試取」的退路 |
| 唯讀 | 未按任何儲存鍵、未改資料、未觸碰保護商品；唯一 DOM 動作是 append 一個 1×1 離屏 div 讀暗色主題值後立即移除 |

### 0.1 🔴 token 值與視窗寬度無關（本輪最重要的方法論結論）

在 `:root`／`html` 上宣告過自訂屬性的規則共涵蓋 **804** 個屬性名，
其中**位於 media query 內者僅 7 個**，全部是版面／側欄類
（`--pc-sidebar-reserved-width`、`--s-frame-inset-*`、`--sidebar-*`）。

⇒ **537 個 `--p-*` token 的值與視窗寬度無關**，在 1024px 量到的即為 1280／768／390 的值。
這是本輪 `innerWidth=1024` 仍可交付完整 token 表的依據。

⚠️ **但幾何量測（§16 骨架）只在 1024／md 帶成立**，那些值受寬度影響，
鐵律 13.1 的三寬對比仍未做（量測機實體螢幕 1024×768，`resize_window` 被瀏覽器拒絕）。

### 0.2 屬性總數的三個不同數字（都對，但量的是不同東西）

| 數字 | 含義 |
|---|---|
| **1808** | 樣式表中**出現過**的自訂屬性名（含未生效、含其他命名空間） |
| **630** | 在 `:root` 上**解析出非空值**者（Home 頁） |
| **537** | 上述 630 之中屬於 `--p-*`（Polaris）命名空間者 |

`--p-*` 的家族分布：color 269 / font 80 / border 37 / shadow 37 / space 30 / motion 23 /
height 21 / width 20 / z 13 / breakpoints 5 / filter 2 ＝ **537**（加總相符，無遺漏家族）。

🔴 **與 `47` §H2-1 的「539 個自訂屬性」對照**：47 的 539 與本輪的 537（`--p-*`）
只差 2，**極可能量的是同一個集合**（47 未載明取法，無法確認）。
本輪另有 630／1808 兩個更大的集合，是 47 沒有涵蓋的層。**不改 47 的原文，照登記。**

### 0.3 🔴 方法論更正：`s-internal-*` 的 shadow root 是 **open**，不是 closed

`docs/design/47` §A 記載這些宿主的 `shadowRoot` 為 `null`（closed mode）、
「按鈕與徽章的內部樣式**無法由 JS 讀取**」，並據此把 §D 整節改用**高倍率截圖目視判讀**。

🔴 **2026-08-28 實測：全部是 open。** `s-internal-button` / `s-internal-badge` /
`s-internal-text-field` / `s-internal-tooltip` / `s-banner` 的 `shadowRoot`
皆可直接 `querySelector` 後 `getComputedStyle`。宿主的 `getBoundingClientRect()`
是 0×0 沒錯——**但那是因為繪製盒在 shadow 內**，不是因為讀不到。

⇒ 本檔與 `docs/design/113`、各 teardown 的 CSS 三段式節**全部用直接量測**，不用目視。
⇒ `47` §D 的目視數值逐項待複核；其中「次級按鈕配方」已證實有誤（`47` §6.5 的更正註）。

## 1. 間距 `--p-space-*`（完整 20 階）

| 階 | rem | px |
|---|---|---|
| 0 / 025 / 050 / 100 | 0 / .0625 / .125 / .25 | **0 / 1 / 2 / 4** |
| 150 / 200 / 250 / 300 | .375 / .5 / .625 / .75 | **6 / 8 / 10 / 12** |
| 400 / 500 / 600 / 700 / 800 | 1 / 1.25 / 1.5 / 1.75 / 2 | **16 / 20 / 24 / 28 / 32** |
| 1000 / 1200 / 1600 | 2.5 / 3 / 4 | **40 / 48 / 64** |
| 2000 / 2400 / 2800 / 3200 | 5 / 6 / 7 / 8 | **80 / 96 / 112 / 128** |

語義別名（10 個）：`badge-icon-padding-inline-start`=4｜`…-large`=6｜`badge-padding-inline`=8｜
`…-large`=8｜`button-group-gap`=8｜`card-gap`=**16**｜`card-padding`=**16**｜
`choice-margin`=0｜`choice-size`=16｜`table-cell-padding`=**6**

## 2. 圓角 `--p-border-radius-*`

數字階 9 個：0／050=2／100=4／150=6／**200=8**／**300=12**／400=16／500=20／750=30（px）

語義別名 22 個（節錄）：`action`＝`control`＝`element`＝**8**｜`container`＝**12**｜`dialog`＝**16**｜
`checkbox`＝`checkbox-checked`＝`control-inner`＝`focus`＝**4**｜`banner-inner`=8｜
`content-highlight`=2｜`full`=9999

⚠️ 兩個非固定值：`avatar`＝`clamp(.25rem, round(25%, .125rem), .5rem)`；
`corner-shape`＝`normal`（是 `corner-shape` 關鍵字，不是長度）。

## 3. 邊框寬度 `--p-border-width-*`

`0`=0｜`0165`=**0.66px**（.04125rem）｜`025`=1px｜`050`=2px｜`100`=4px
`outline-input-focus`＝`2px solid #005bd3`（複合值，非純寬度）

> 0.66px 即 `64` §C 記錄的髮絲線值，本輪確認它是**具名 token**而非計算結果。

## 4. 字族 `--p-font-family-*`

- `sans`：`Inter` 領頭 → Noto Sans Arabic → Noto Sans Hebrew → `-apple-system` →
  BlinkMacSystemFont → San Francisco → Segoe UI → Roboto → Helvetica Neue → `sans-serif`
- `mono`：`ui-monospace` → SFMono-Regular → SF Mono → Consolas → Liberation Mono → Menlo → `monospace`

## 5. 字級 `--p-font-size-*`

數字階 13 個：275=11｜300=12｜**325=13**｜350=14｜400=16｜450=18｜500=20｜550=22｜
600=24｜750=30｜800=32｜900=36｜1000=40

語義階 14 個：`body-x-small`=11｜`body-small`=12｜**`body-medium`=13**｜`body-large`=14｜
`button-label`=12｜`details-text`=12｜`heading-small`=12｜**`heading-medium`=13**｜
`heading-large`=14｜`input-label`=13｜`input-label-small`=12｜
`display-small`=18｜`display-medium`=24｜`display-large`=30

## 6. 行高 `--p-font-line-height-*`

數字階 8 個：300=12｜400=16｜**500=20**｜600=24｜700=28｜800=32｜1000=40｜1200=48

語義階與字級**一一配對**：`body-x-small`=12｜`body-small`=16｜**`body-medium`=20**｜
`body-large`=20｜`button-label`=16｜`details-text`=16｜`heading-small`=16｜
**`heading-medium`=20**｜`heading-large`=20｜`input-label`=20｜`input-label-small`=16｜
`display-small`=24｜`display-medium`=32｜`display-large`=40

## 7. 🔴 字重 `--p-font-weight-*`：token 值域與實際 computed 不一致

> 🔴🔴 **2026-08-28 更正：本節的立論是錯的，原因是量測環境污染。**
> 下面的「computed 有 483 個 500」是使用者 Chrome 的擴充功能注入
> `font-weight: 500 !important` 造成的，**不是 Shopify 的事實**。
> 乾淨環境的直方圖是 `450×981 / 550×187 / 600×4 / 400×13`，**一個 500 都沒有**，
> 完全落在 token 值域內。⇒ **「token 值 ≠ computed 值」這個結論撤回。**
> 全文與逐項更正＝**§20**。**原文以下保留備查**（鐵律 19.5）。

**token 值域只有 4 個相異值**：

`regular`＝`details-text`＝`input-label`＝`input-label-small`＝**450**
`medium`＝`button-label`＝**550**
`semibold`＝`heading-small/medium/large`＝`display-small`＝**600**
`bold`＝`display-medium/large`＝**650**

🔴 **全部是可變字重的非整百值。我方 token 表若用 400／500／600／700 會整體偏粗或偏細。**

🔴 **但全站 deep 掃描（含 shadow DOM）的實際 computed 直方圖是**：

| 字重 | 元素數 | 在 token 值域內？ |
|---:|---:|:--:|
| **450** | 1359 | ✅ |
| **500** | 483 | ❌ |
| 600 | 37 | ✅ |
| 550 | 30 | ✅ |
| **400** | 70 | ❌ |
| **700** | 11 | ❌ |
| 650 | 5 | ✅ |

`body` 自身的 computed `font-weight` 就是 **500**，側欄導航項也是 **500**。

⇒ **不能只照 token 表填**。500 的來源規則本輪**未查明**——
可能來自舊 Polaris React 層，也可能是 `body` 上的直接宣告。
換值前必須先決定 `body` 與導航用 450 還是 500。

## 8. 字距 `--p-font-letter-spacing-*`（15 個）

`normal`＝`body-*`＝`heading-*`＝**0**
`dense`=**-.00833em**｜`denser`=**-.0166em**｜`densest`=**-.0291em**
`display-small`＝`display-medium`=**-.00833em**｜`display-large`=**-.0166em**

另 `--p-font-feature-settings` ＝ `'calt' 0`（**關閉上下文替代**）。

⚠️ **不是「全部 normal」**：body／heading 級是 0，但 **display 級是負字距**。
大標題不套負字距會比本尊鬆。

## 9. 陰影 `--p-shadow-*`

| 階 | 層數 | 值 |
|---|---|---|
| `-0` | — | `none` |
| `-100` | **6** | `0 5px 5px -2.5px #00000008` / `0 3px 3px -1.5px #00000005` / `0 2px 2px -1px #00000005` / `0 1px 1px -.5px #00000008` / `0 .5px .5px 0 #0000000a` / `0 0 0 1px #0000000f` |
| `-200` | **7** | `-100` 之上**於最前**再疊 `0 8px 10px -5px #00000014` |
| `-300` | **6** | `0 8px 24px -8px #00000047` / `0 8px 16px -4px #0000000d` / `0 3px 6px 0 #0000000d` / `0 2px 4px 0 #0000000d` / `0 1px 2px 0 #0000000d` / `0 0 0 1px #0000000f` |
| `-400` | 6 | `0 20px 32px -12px #00000033` / `0 10px 16px -6px #00000014` / …（同型續疊） |
| `-500` | 7 | （toast 用） |

**語義別名（30 個）與數字階的對應**：

| 語義 | ＝ |
|---|---|
| `section`＝`container`＝`control-knob` | **`-100`** 全等 |
| `banner` | **`-200`** 全等 |
| `popover` | **`-300`** 全等 |
| `dialog` | **`-400`** 全等 |
| `toast` | **`-500`** 全等 |

按鈕專用（inset 三層，即本尊 2026 的「可舔按鈕」）：
`-button`＝`0 -1px 0 0 #b5b5b5 inset` / `0 0 0 1px #0000001a inset` / `0 .5px 0 1.5px #fff inset`
`-button-primary`＝`0 -1px 0 1px #000000cc inset` / `0 0 0 1px #303030 inset` / `0 .5px 0 1.5px #ffffff40 inset`
`-button-disabled`＝**`none`**
`-border-inset`＝`0 0 0 1px #00000014 inset`
`-inset-100`＝`0 1px 2px 0 #1a1a1a26 inset` / `0 1px 1px 0 #1a1a1a26 inset`

🔴 **每一階的最外層都是 `0 0 0 1px`**——「邊框」被摺進陰影配方裡，
所以卡片與浮層的 `border` 實測為 **0**。

## 10. 動效 `--p-motion-*`

duration 12 階：`0 / 50 / 100 / 150 / 200 / 250 / 300 / 350 / 400 / 450 / 500 / 5000` ms

緩動 5 個具名值：
`linear`=`cubic-bezier(0,0,1,1)`｜`ease`=`cubic-bezier(.25,.1,.25,1)`｜
`ease-in`=`cubic-bezier(.42,0,1,1)`｜`ease-in-out`=`cubic-bezier(.42,0,.58,1)`｜
`ease-out`=**`cubic-bezier(.19,.91,.38,1)`**

🔴 `ease-out` **不是 CSS 內建值**（內建為 `cubic-bezier(0,0,.58,1)`），
是自訂的曲線——控制點 `.91` 讓它在後段急剎。照抄內建的 `ease-out` 會不像。

keyframes 名（6 個）：`appear-above`／`appear-below`／`bounce`／`fade-in`／`pulse`／`spin`

## 11. 斷點 `--p-breakpoints-*`（rem 制 5 階）

`xs`=0｜`sm`=30.625rem(**490px**)｜`md`=**48rem(768px)**｜`lg`=65rem(**1040px**)｜`xl`=90rem(**1440px**)

🔴 **與 `47` §F 的衝突（照登記，未判定）**：`47` §F 記「em 制 **8 階**，主斷點 768/48em」。
主斷點 768 兩邊一致（48rem 與 48em 在根字級 16px 下等值），但**階數 5 vs 8**、
**單位 rem vs em** 兩點不同。兩者可能不是同一層——47 可能量的是實際 `@media` 條件數，
本輪量的是 token 宣告值。需開檔核對後才能判定是矛盾還是互補。

## 12. 尺寸 `--p-height-*` / `--p-width-*`（各 20 階，**兩者數值完全相同**）

0／025=1／050=2／100=4／150=6／200=8／300=12／400=16／500=20／600=24／**700=28**／
**800=32**／900=36／1000=40／1200=48／1600=64／2000=80／2400=96／2800=112／3200=128（px）

另 `--p-height-field-min-block-size`=**32px**。

## 13. 層級 `--p-z-index-*`（13 階）

`0`=auto｜`1`=100｜`2`=400｜`3`=510｜`4`=512｜`5`=513｜`6`=514｜`7`=515｜`8`=516｜
**`9`=517**｜`10`=518｜`11`=519｜**`12`=520**

實測：頂欄＝**517**（`-9`）；popover 與其內部下拉面板都是 **520**（`-12`），
靠 DOM 順序而非 z-index 決定誰在上。

## 14. 顏色（269 個 `--p-color-*`，淺色主題）

### 14.1 基礎四色

`bg`=**`#f1f1f1`**（頁面底）｜`text`=**`#303030`**（主文字）｜
`border`=**`#e3e3e3`**（預設邊框）｜`icon`=**`#4a4a4a`**（預設圖示）

### 14.2 表面階 `bg-surface-*`（中性）

`surface`=`#fff`｜`-hover`=`#f7f7f7`｜`-active`=`#f3f3f3`｜**`-selected`=`#f1f1f1`**｜
`-secondary`=`#f7f7f7`｜`-secondary-hover`=`#f1f1f1`｜`-secondary-active`=`#ebebeb`｜
`-secondary-selected`=`#ebebeb`｜`-tertiary`=`#f3f3f3`｜`-tertiary-hover`=`#ebebeb`｜
`-tertiary-active`=`#e3e3e3`｜`-disabled`=`#0000000d`｜`-inverse`=`#303030`｜
`-overlay`=`#ffffffcc`

### 14.3 表面階 `bg-surface-*`（語義，三態）

| 族 | base | hover | active |
|---|---|---|---|
| success | `#cdfed4` | `#affebf` | `#92fcac` |
| critical | `#fee8eb` | `#fee1e6` | `#fed9df` |
| warning | `#fff1e3` | `#ffebd5` | `#ffe4c6` |
| caution | `#fff8db` | `#fff4bf` | `#ffef9d` |
| info | `#eaf4ff` | `#e0f0ff` | `#cae6ff` |
| highlight | `#f0f2ff` | `#eaedff` | `#e2e7ff` |
| ai | `#f8f7ff` | — | — |

🔴 **有 7 族不是 5 族**——除 `47` §H2-1 記的 info/success/caution/warning/critical，
另有 **highlight** 與 **ai**。

### 14.4 填色階 `bg-fill-*`（中性與 brand）

`fill`=`#fff`｜`-hover`=`#fafafa`｜`-active`=`#f7f7f7`｜`-selected`=`#ccc`｜
`-secondary`=`#f1f1f1`｜`-secondary-hover`=`#ebebeb`｜`-secondary-active`=`#e3e3e3`｜
`-tertiary`=`#e3e3e3`｜`-tertiary-hover`=`#d4d4d4`｜`-tertiary-active`=`#ccc`｜
`-disabled`=`#0000000d`｜`-inverse`=`#303030`｜`-inverse-hover`=`#4a4a4a`｜
`-inverse-active`=`#616161`｜`-brand`=`#303030`

### 14.5 填色階 `bg-fill-*`（語義）

| 族 | base | hover | active | `-secondary` |
|---|---|---|---|---|
| success | `#047b5d` | `#035e4c` | `#014b40` | `#affebf` |
| critical | `#c70a24` | `#a30a24` | `#8e0b21` | `#fed1d7` |
| warning | `#ffb800` | `#e5a500` | `#b28400` | `#ffd6a4` |
| caution | `#ffe600` | `#ead300` | `#e1cb00` | — |
| info | `#91d0ff` | — | — | — |

🔴 **`warning`／`caution`／`info` 的 fill 是淺色**（配深色前景），
`success`／`critical` 是深色（配白字）。**同一個 `-fill` 槽位在不同族是不同的配色模型**，
我方若統一生成「深色實填配白字」會有三族對不上。

### 14.6 半透明填色 `bg-fill-transparent-*`（全為 `#000` 疊 alpha）

`transparent`=`#00000005`｜`-hover`=`#0000000d`｜`-active`=`#00000014`｜
`-selected`=`#00000014`｜`-secondary`=`#0000000f`｜`-secondary-hover`=`#00000014`｜
`-secondary-active`=`#0000001c`

### 14.7 其他 bg

`bg-inverse`=**`#0a0a0a`**（~~頂欄實測底色即此值~~ 🔴 見下方 2026-08-28 更正）

> 🔴 **2026-08-28 更正：「頂欄實測底色即此值」是誤歸因。**
> 頂欄落在 `<s-internal-theme-provider theme="admin" colorscheme="dark">` 的子樹內，
> 用的是**該 scope 的 `--p-color-bg`**（暗色主題下 ＝ `#0a0a0a`，見 §15），
> 不是淺色主題的 `bg-inverse`。**兩個 token 剛好同值，所以這個錯在數值上察覺不出來。**
>
> **消融實驗證明**（不是相關性）：在 `div._TopBar_1scp5_1` 上解析成 `#0a0a0a` 的候選恰 4 個，
> 逐一 inline 覆寫成 `rgb(1,2,3)` —— **只有 `--p-color-bg` 會改變底色**，
> `-bg-inverse`／`-nav-bg`／`-nav-bg-surface` 皆不變；`removeProperty` 後還原。
>
> ⇒ **我方不得定義一個「頂欄專用 inverse 色」**。正確做法是頂欄整個子樹套暗色 scope，
> 於是其內全部文字／圖示／hover 底自動跟著換。這也解釋了 `docs/design/112` §5 為什麼把
> `--surface-inverse` 記成「本尊對應值未取得」——**那個對應關係根本不存在**。
`backdrop-bg`=**`#000000b5`**（modal 遮罩，≈71% 黑）

⚠️ **與 `82` §16.2 的 `rgba(0,0,0,.5)` 不同**——後者量的是**舊 Polaris React modal** 的 backdrop。
兩層各有自己的遮罩色，見 §17.1。

### 14.8 文字階 `text-*`

中性：`text`=`#303030`｜`-secondary`=`#616161`｜**`-tertiary`=`#616161`（與 secondary 同值）**｜
`-disabled`=`#b5b5b5`｜`-inverse`=`#e3e3e3`｜`-inverse-secondary`=`#b5b5b5`｜
`-brand`=`#4a4a4a`｜`-brand-hover`=`#303030`｜`-brand-on-bg-fill`=`#fff`

語義：`link`=`#005bd3`／`-hover`=`#004299`／`-active`=`#002e6a`／`-inverse`=`#c5d0ff`
`success`=`#014b40`／`-hover`=`#073630`／`-active`=`#022622`／`-secondary`=`#047b5d`／`-on-bg-fill`=`#fafffb`
`critical`=`#8e0b21`／`-hover`=`#5f0716`／`-active`=`#2f040b`／`-secondary`=`#c70a24`／`-on-bg-fill`=`#fffafb`
`warning`=`#5e4200`／`-hover`=`#412d00`／`-active`=`#251a00`

### 14.9 圖示階 `icon-*`

`icon`=`#4a4a4a`｜`-hover`=`#303030`｜`-active`=`#1a1a1a`｜`-disabled`=`#ccc`｜
`-secondary`=`#8a8a8a`｜`-secondary-hover`=`#616161`｜`-secondary-active`=`#4a4a4a`｜
`-tertiary`=`#8a8a8a`｜`-inverse`=`#e3e3e3`｜`-brand`=`#1a1a1a`｜
`-success`=`#047b5d`｜`-critical`=`#e22c38`｜`-warning`=`#b28400`｜`-caution`=`#998a00`｜
`-info`=`#0094d5`｜`-highlight`=`#005bd3`｜`-ai`=`#8051ff`

### 14.10 邊框階 `border-*`

`border`=`#e3e3e3`｜`-hover`=`#ccc`｜`-secondary`=`#ebebeb`｜`-tertiary`=`#ccc`｜
`-disabled`=`#ebebeb`｜**`-focus`=`#005bd3`**｜`-inverse`=`#616161`｜`-brand`=`#e3e3e3`｜
`-success`=`#92fcac`｜`-critical`=`#fec1c7`｜`-critical-secondary`=`#8e0b21`｜
`-warning`=`#ffc879`｜`-caution`=`#ffeb78`｜`-info`=`#a8d8ff`｜`-highlight`=`#005bd3`｜
`-ai`=`#e4deff`

### 14.11 輸入控件 `input-*`（8 個）

`bg-surface`=**`#fdfdfd`**｜`-hover`=`#fafafa`｜`-active`=`#f7f7f7`｜`-error`=`#fee8eb`｜
`-ai`=`#f8f7ff`｜`border`=**`#8a8a8a`**｜`border-hover`=`#616161`｜`border-active`=`#1a1a1a`

### 14.12 按鈕 `button-*`（含兩個漸層）

`bg-fill`=`#fff`｜`-hover`=`#fafafa`｜`-active`=`#f7f7f7`｜
`-critical`=`#fff`｜`-critical-hover`=`#fafafa`｜`-critical-active`=`#f7f7f7`｜
`group-divider`=`#0000001c`｜
`gradient-bg-fill`=`linear-gradient(180deg, #30303000 63.53%, #ffffff26 100%)`｜
`gradient-bg-fill-critical`=`none`

### 14.13 側欄導航 `nav-*`（14 個）

`bg`=**`#ebebeb`**（側欄底）｜`bg-surface`=`#00000000`（項目 idle）｜
`bg-surface-hover`=**`#f1f1f1`**｜`bg-surface-active`=**`#fafafa`**｜`bg-surface-selected`=**`#fafafa`**｜
`icon`＝`icon-hover`＝`icon-active`=**`#4a4a4a`（三態同值）**｜
`text`＝`text-hover`＝`text-active`=**`#303030`（三態同值）**｜
`text-secondary`=`#616161`｜`-hover`＝`-active`=`#303030`

🔴 **導航項的 icon 與 text 三態同色**——狀態差異**只靠底色**，不改字色也不改圖示色。

### 14.14 Badge `badge-*`（10 個）

`bg-fill-success`=`#047b5d`｜`-critical`=`#c70a24`｜`-warning`=`#ffb800`｜
`-caution`=`#ffe600`｜`-info`=`#91d0ff`
`text-success`=`#014b40`｜`text-critical-on-bg-fill`=`#fffafb`｜
`text-warning`=`#5e4200`｜`text-caution`=`#4f4700`｜`text-info`=`#003a5a`

### 14.15 Avatar `avatar-*`（7 色輪＋預設）

`bg-fill`=`#b5b5b5`／字 `#fff`
`one`=`#c530c5`／`#fdeffd`｜`two`=`#52f490`／`#014b40`｜`three`=`#2ce0d4`／`#033c39`｜
`four`=`#51c0ff`／`#002133`｜`five`=`#fd4b92`／`#fff6f8`｜`six`=`#25e82b`／`#033d05`｜
`seven`=`#9474ff`／`#f8f7ff`

### 14.16 濾鏡 `--p-filter-*`

`nav-icon`＝`nav-icon-active`＝`saturate(0) brightness(.75) contrast(2) opacity(.63)`
（淺色主題下兩者同值）

## 15. 暗色主題

同名 537 個全部可取；**與淺色相異者 225 個**，分布：
**`--p-color-*` 203 個、`--p-shadow-*` 20 個、`--p-filter-*` 2 個**。

🔴 **space／font（字級行高字重字距字族）／border-radius／border-width／motion／
breakpoints／height／width／z 全部兩主題同值（差集為空）。**

核心值：`bg`=`#0a0a0a`｜`bg-surface`=`#1a1a1a`｜`-hover`=`#222`｜`-active`=`#282828`｜
`-secondary`=`#282828`｜`-selected`=`#2f2f2f`｜`-tertiary`=`#2f2f2f`

⇒ **要做暗色主題，只需要改色與陰影兩族**，尺寸類一律共用。

## 16. 頁面骨架（1024 寬 / md 帶）

⚠️ 本節數值**受視窗寬度影響**，是 **1024／md 帶**的值（token 表不受影響，見 §0.1）。

🔴 **768 與 390 的形態另見 `docs/research/21` §5 的「響應式」四列**（同日實測）。
關鍵結論：**外框只有 768 一個斷點**且 768 屬桌機側（768→側欄 240／767→側欄 0，無遲滯）；
767→390 之間七項形態**再無任何變化**；另有一個**容器級**門檻——容器寬 491 保留 16px 內距、
490 全出血（對應視窗 507／506）。**1280 未取得**（量測機 `screen.width=1024`）。

框架 token `--pg-*`（24 個，非 Polaris 命名空間）：
`top-bar-height`=**56px**｜`navigation-width`=**240px**｜`control-height`=32px｜
`dismiss-icon-size`=32px｜`system-alert-banner-height`=0｜
`mobile-nav-width`=`calc(100vw - 2rem - 2rem)`

| 部位 | 量測 |
|---|---|
| **頂欄** | `position: fixed`｜**z-index 517**｜**高 56px**｜寬 100%｜padding 0｜**border-bottom 0**｜**box-shadow none**｜自身 bg **透明**，著色在內層容器：**`#0a0a0a`**｜內層 **gap 24px**｜左區塊寬 **240px**（與側欄同寬，形成 L 型對齊）｜Logo 包裹層 padding `0 20px` |
| **側欄** | x=0, y=**56**（緊貼頂欄，無重疊無間隙）｜**寬 240px**｜高＝視口減 56｜padding 0｜**border 0**｜**box-shadow none**（側欄與內容區**靠色差分隔**，不用邊框也不用陰影）｜bg **`#ebebeb`** |
| **導航項** | **高 28px**｜寬 218px｜x=**10**（右側 240−10−218＝**12**，**左右不對稱**）｜**垂直節距 28px（無 gap、無 margin，項目彼此緊貼）**｜padding `0 4px 0 8px`｜radius **8**｜🔴 字重見 §20.4：`<a>` 包裹層 13px/450（純繼承、不繪製文字），**實際繪製的 `<span>` 是 13px / 550 / 20px，作用中 600**｜color `#303030`｜圖示容器 20×20 |
| **導航項 hover** | 父層 bg → **`#f1f1f1`**（＝`--p-color-nav-bg-surface-hover`）；**字色與圖示色不變** |
| **main** | x=0, y=56｜寬滿版｜**padding `0 0 0 240px`**（🔴 用 **padding-left** 讓開側欄，不是 margin、不是 grid）｜bg **`#f1f1f1`** |
| **捲動區** | x=240，寬 **784**（＝1024−240）；其內容器寬 **768** ⇒ **捲軸槽保留寬 16px** |
| **頁面容器** | `s-internal-page` 自身 `display: contents`｜`main.page` 寬 768、**padding `16px 0`（只有上下，左右為 0）**｜`.header` 高 **40**｜`.header-content` x=256 寬 736，**column-gap 8**｜`.actions` 高 **28**，**gap 6** |
| **內容欄** | x=**256**，寬 **736** ⇒ **左右各再內縮 16px** |
| **卡片網格** | 三欄起點 x=256／507／757，欄寬 **235** ⇒ **水平間距 16**｜列間 **垂直間距一律 16**（三次取樣皆 16） |
| **卡片** | bg `#fff`｜radius **12**｜padding **16**｜box-shadow **6 層**（＝`--p-shadow-100`） |
| **body** | font 13px / ~~500~~ **450**（🔴 §20 更正）/ 20px｜color `#303030`｜bg `#f1f1f1`｜`color-scheme: light`；`html` 自身 bg **透明**（底色由 body 提供） |

### 16.1 🔴 內容區沒有 max-width

> 🔴🔴 **2026-08-28 更正：本節結論錯誤——不是「沒有 max-width」，是「量錯了層」。**
> 本節的**前提**（`main.page` 與 `.page-content` 的 computed 是 `max-width: none`）
> **完全正確且已複驗**；錯的是由它導出的結論。上限確實存在，只是位在**再下一層 shadow root**：
> `main.page` → `<s-grid>`（自身 `display: contents`）→ `<span class="grid">`，
> 由 **s-grid 的元素屬性生成 per-instance `<style>`**。
>
> **track function（實測，兩個獨立樣本＋一個新樣本複驗）**：
> ```
> @container s-internal-page (inline-size >= 784px)
>   "minmax(480px, 638px) minmax(240px, 312px)", "minmax(auto, 966px)"
> ```
> ⇒ 主欄 **480–638**、次欄 **240–312**、單欄上限 **966**（＝638 + 16 + 312）。
> 搭配 `justify-content: center` ⇒ **所有寬度都置中**，不是某個斷點以上才出現。
>
> **與舊層的關係**：舊 `.Polaris-Page` 的 `max-width` ＝ `41.375rem + 20rem + 1rem` ＝ **998px**；
> 新層 966 + 2×16 ＝ **998px**。**同一條加總公式、同一個 16px 內側間距，只把兩個上限
> 各自重訂**（662→638 −24、320→312 −8，**降幅不同 ⇒ 不是統一縮放**）。
>
> ⇒ 下面兩段「不由本框架消費」與「>1040px 未取得」也一併更正：
> 舊 token 確實零消費（那是對的），但**新層有自己的一組常數**；
> 置中在所有寬度生效，「>1040 是否有置中容器」這個問題本身問錯了。
>
> 🔴 **教訓**：這是本專案第三次同型事故（G13 量到不繪製的節點、本次量錯 shadow 層、
> §14.7 的頂欄誤歸因）。共同根因＝**取值前沒有問「我讀的這個值，對這個元素成立嗎」**。
> 紀律條文見 §20.8。
>
> **原文以下保留備查**（鐵律 19.5）。

`main.page` 與 `.page-content` 的 computed **`max-width: none`**。
祖鏈全部是 `none` 或 `100%`。shadow root 內設定 max-width 的規則只有 3 條，
**目標全是標題元素**，沒有一條作用在 `main.page` 或 `.page-content` 上。

⇒ **2026 版 `s-internal-page` 框架在頁面層不設內容區 max-width，內容欄是流體寬度。**

⚠️ 舊版 `--pg-layout-width-primary-max`=41.375rem(662px)／`-secondary-max`=20rem(320px)
仍存在於 `:root`，但**不由本框架消費**。
🔴 **>1040px 是否有更外層置中容器＝未取得**（本輪只量到 1024）。

## 17. 🔴 三個「不能照抄」的發現

### 17.1 本尊有兩套設計系統世代並存於同一畫面

新的 **web component 層**（`s-*` 自訂元素＋shadow DOM）與舊的 **Polaris React 層**
同時在跑，**同名元件在兩層是不同值**：

| 元件 | 新層（`s-*`） | 舊層（Polaris React） |
|---|---|---|
| heading | **13px / 600** | **14px / 500** |
| 按鈕標籤 | **12px / 550**（＝`--p-font-*-button-label`） | 13px / 500 |
| modal 陰影 | — | `rgba(26,26,26,.22) 0 8px 16px -4px`（**不在 `--p-shadow-*` 階上**） |
| modal 遮罩 | `--p-color-backdrop-bg`=`#000000b5` | `rgba(0,0,0,.5)` |
| 按鈕 transition | **`none`** | `all` |
| 表單 label 字重 | **450** | 500 |

> 🔴 **2026-08-28 更正**：上表「舊層」欄的 **`500`** 全部是污染值（§20），
> 乾淨值需逐項重量。已重量的：`.Polaris-Button` ＝ **13px / 450**、
> `.Polaris-Text--bodyMd` ＝ **13px / 550**、`.Polaris-Text--bodySm` ＝ **12px / 450**。
> ⇒ **兩層在「字級」上確實不同（13 vs 12），但「字重」那一欄的差異是污染造出來的**，
> 不得再引用。其餘維度（modal 陰影、遮罩色、transition）不受影響。

⇒ **這解釋了為什麼 `47` 與 `64` 本來就互相矛盾**（47 §6.5 記按鈕 12/16/550、
64 §3 記 13/20/500）——**兩邊都對，量的是不同層**。

🔴 **我方只需一套，取新層**（13px/600、按鈕 12/550、陰影走 `--p-shadow-*` 階）。
照抄兩套會把本尊的技術債一起抄進來。
🔴 **既有量測文件引用時必須標明是哪一層**，不標層次直接引用會做錯一半的元件。

### 17.2 本尊自身的不一致：同一個 popover 裡兩種邊框實作

排程彈層的**日期欄用 inset box-shadow 髮絲**、**時間欄用真 border**（`82` §16.3）。
視覺幾乎一致但實作不同。⇒ **我方統一用一種**。

### 17.3 有 token 不等於元件會用

側欄導航項實測 `transition-property: all`、**`transition-duration: 0s`**——狀態切換**無任何過場**，
儘管 token 層提供了完整的 12 階 duration 與 5 條緩動。

⇒ 不得把 duration 階寫成「導航／列表項的過場時間」。

## 18. 與既有文件的關係

| 文件 | 處置 |
|---|---|
| `47` §6／§H2-1／§8 第 89 條 | **本檔取代**其「色值改用自有調色」的處置（`110` §2 A/B/C） |
| `47` §H2-1「539 個自訂屬性」 | 與本檔 537 個 `--p-*` 只差 2，**極可能同一集合**；47 未載明取法，**照登記未判定**（§0.2） |
| `47` §H2-1「語意色 5 族」 | **本檔擴為 7 族**（多 `highlight`、`ai`，§14.3） |
| `47` §F 斷點 em 制 8 階 | 與本檔 rem 制 5 階衝突，**照登記未判定**（§11） |
| `47` §6.5 按鈕 12/16/550 ∧ `64` §3 按鈕 13/20/500 | **兩者都對**，分屬不同層（§17.1）；引用時必須標層 |
| `64` §7「字重 450/500/550/600 四階」 | token 值域是 **450/550/600/650**；500 是實際 computed 而非 token（§7），**兩句都要保留並標明來源層** |
| `64` §C 髮絲線 0.66px | **本檔確認**它是具名 token `--p-border-width-0165` |
| `64` §6「按鈕 transition: all，我方不跟」 | 🔴 **新層的 `s-button` transition 實測是 `none`**；`all` 只出現在舊 React 層 ⇒ 該節應加註日期與適用層（`110` §2 E 的待裁定因此變成「跟新層＝本來就不用 all」） |
| `docs/design/23` §1 我方 token 表 | **待換值**——換值是另一個工作包，逐項差異見 `110` §7 |

## 19. 未取得清單（鐵律 19.3）

| 項目 | 原因 | 取得方式 |
|---|---|---|
| **1280 桌機寬**的骨架幾何（§16） | 量測機 `screen.width=1024`，`window.screenX` 回報 -32000 ⇒ Chrome 視為離屏，`resize_window` 一律拒絕。**768／390 已用同源 popup 法取得**（`21` §5），只有 1280 因螢幕本身不足而不可得 | 換一台螢幕 ≥1280 的機器重跑 |
| **>1040px 是否有外層置中容器** | 只量到 1024（lg 斷點以下） | 同上 |
| **字重 500 的來源規則** | 本輪只做到「發現 body 與導航 computed 是 500 而 token 值域無 500」 | 追 `body` 上的直接宣告或舊層繼承 |
| primary 按鈕的 **hover／active** 態 | 取樣流程中的 primary 全程 disabled | 找一個 primary 可按的畫面重量 |
| `info` 族的 **hover／active** fill | 只取到 base | 重跑逐 token 抽取 |
| 捲軸 thumb 的 hover／active **實際著色** | 只有 token 值，未在實際捲軸上取樣 | 對捲軸元素直接取樣 |
| `--pg-bottom-bar-max-height` 的**實際生效值** | `:root` 解析 350px、`body` 解析 384px，消費端讀哪一層未驗證 | 找實際有 bottom bar 的畫面量 |

---

## 20. 🔴 量測環境污染：所有 `font-weight` 值曾經失真（2026-08-28 發現並更正）

> 本節依**鐵律 19.5**追加。上方 §7／§16／§17.1 的原文保留，各自加了指向本節的更正註。

### 20.1 污染源

使用者 Chrome 的一個擴充功能（「字體加粗」類）在 `<style id="font-bolder-style">` 注入一條規則：

| 項 | 值 |
|---|---|
| 掛載位置 | `parentNode` 是 **`HTML`**（不是 `HEAD`） |
| 選擇器 | `body, body :not(svg):not(svg *):not(img):not(video):not(canvas)` |
| 宣告 | `font-weight: 500 !important`（另有 `text-shadow`／`-webkit-font-smoothing`／`text-rendering`） |

### 20.2 🔴 為什麼「看到 500」無法回推真值

它是**固定值 500 加 `!important`** ⇒ **雙向**改寫：

| 元件 | 乾淨 | 污染 | 方向 |
|---|---|---|---|
| `.Polaris-Button` | **450** | 500 | 拉高 |
| `.Polaris-Text--bodyMd` | **550** | 500 | **壓低** |
| `.Polaris-Text--bodySm` | **450** | 500 | 拉高 |
| 側欄導航項的繪製 `<span>` | **550**（作用中 **600**） | 500 | 壓低 |
| `body` | **450** | 500 | 拉高 |

⇒ 一個記到的 `500` 可能原本是 450 也可能是 550。**只能重量，不能換算。**

### 20.3 為什麼不是全部元素都變 500

選擇器是 `body` 的**後代選擇器**，**跨不過 shadow 邊界**：

- **light DOM**（Polaris React 層、`s-*` 的 host 本身）⇒ **被污染**
- **shadow DOM 內部**（`s-internal-*` 的繪製盒）⇒ 🔴 **不是無條件免疫，見下**

🔴🔴 **2026-08-28 二次更正：「shadow DOM 免疫」這條判準本身是錯的。**

污染選擇器 `body :not(svg)…` 確實**停在 shadow 邊界**（選擇器不跨 shadow），
**但 `font-weight` 是可繼承屬性**——shadow 內**未自宣告 `font-weight`** 的繪製盒，
會沿 **flattened tree** 繼承宿主（light DOM 的 `s-*` host）被打成 `!important 500` 的值。

⇒ **判準是「該元素自己有沒有宣告 `font-weight`」，不是「它在不在 shadow 裡」。**

實證（本批自己量到的兩個反例）：

| 元件 | 位置 | 自宣告？ | 乾淨 | 污染 |
|---|---|---|---|---|
| `s-internal-button` shadow `.button`（primary／secondary／tertiary） | shadow | ✅ 12px/550 | 550 | 550（免疫） |
| `s-internal-button` shadow `.button.variant-plain`（「View details」） | shadow | ❌ **未宣告** | **450** | **500** |
| `s-button` shadow `SPAN.text-wrapper`（「Remove schedule」） | shadow | ❌ **未宣告** | **450** | **500** |
| `s-button` shadow `SPAN.text-wrapper`（Cancel／Done） | shadow | ✅ `.button` 類宣告 550 | 550 | 550（免疫） |

⇒ 🔴 **任何「在 shadow 內所以不用重量」的判斷都不成立**，必須**逐項做 clean/dirty 配對**。

### 🔴 三次更正後的完整判準（2026-08-28，G12 補完時再細化）

🔴 **有兩道防線，先前只寫了第二道。**

**第一道＝樹範圍**：擴充的 `<style>` 掛在 **document tree**，
而 **document 的樣式表根本不匹配 shadow tree 內的任何元素**——選擇器命中只發生在 document tree。
⇒ shadow 內的元素**從來不會被 `body :not(svg)…` 直接命中**，被命中的只有 **host**。
（先前的寫法「繼承鏈上有沒有宣告」會讓人誤以為 shadow 內元素也會被直接選中。）

**第二道＝繼承**：`font-weight` 可繼承，會沿 flattened tree 從被污染的 host traverse 進 shadow。
免疫與否取決於**「從被污染的 host 到該繪製盒的繼承鏈上，有沒有任何一環宣告了 `font-weight`」**：

| 情形 | 免疫？ | 例 |
|---|:--:|---|
| 該元素**自己宣告** | ✅ | `s-internal-button` 的 `.button`（primary/secondary/tertiary，自宣告 550） |
| 自己不宣告，但**shadow 內的祖先宣告了** | ✅ | `s-internal-text-field` 的 `input`／`label`——shadow 根 `div.internal-text-field` 宣告 450，**阻斷了對被污染 host 的繼承** |
| 自己與 shadow 內祖先**都不宣告** | ❌ | `s-internal-button` 的 `.button.variant-plain`（450→500）、`s-button` 的 `SPAN.text-wrapper`（Remove schedule，450→500） |
| 🔴 **light DOM 的元素被 `slot` 投射進 shadow** | ❌ | `s-internal-single-picker-field-value`——視覺上在 shadow 裡，但它**在 light DOM**，而 **CSS 選擇器照 DOM 樹匹配** ⇒ 照樣被打中（且它是 `display: contents`） |
| **同源 iframe** 內的文件 | ✅ | 富文本編輯器 `product-description-rie_ifr`——擴充功能的 style **沒有注入該 document** |

⇒ **「在 shadow 裡」既不充分也不必要**。唯一可靠的做法是**逐項 clean/dirty 配對**。

全文＝`docs/design/113` §1.6.2-1、`docs/research/82` §16.6.2-1、
`docs/research/91` §19.6 與 `docs/research/94` §4.6（後兩者是 G12 補完時取得的新機制）。

這正好解釋了污染環境下的直方圖「450×1359 / 500×483」——450 那批是 shadow 內、500 那批是 light DOM。

🔴 **這也推翻了 §7 的整個立論**。§7 據此宣稱「token 值域沒有 500 但實際 computed 有 483 個 500，
所以 token 值 ≠ computed 值」——**那個落差是污染造出來的**。
乾淨直方圖（商品詳情頁 1335 個葉節點）：`450×981 / 550×187 / 600×4 / 400×13`，**一個 500 都沒有**，
完全落在 `--p-font-weight-*` 的值域內。

### 20.4 第二類錯誤：量錯層（與污染獨立）

重量時另外發現一批與污染無關的錯誤——**記到的是不繪製文字的包裹元素**：

| 例 | 包裹層（原記載量到的） | 實際繪製文字的元素 |
|---|---|---|
| 側欄導航項 | `<a>` 13px/**450**（純繼承 body） | `<span>` 13px/**550**；作用中 **600** |
| 側欄分組標題 | host `s-internal-text` 13.3333px/400（`display: contents`，**不產生繪製盒**） | shadow 內 `<strong>` 12px/**550** |
| 側欄徽章數字 | host `s-internal-badge` 13px/500 | shadow 內 `<span.number>` 12px/**600** |

🔴 **量 `s-*` host 會得到與外觀完全無關的值**——它常是 `display: contents`。
繪製盒一律在 shadow 內。

### 20.5 一個結構事實（順帶更正）

`.header-content` **位於 `s-internal-page` 的 shadowRoot 內** ⇒
`document.querySelectorAll('.header-content').length === 0`。
任何用 light DOM 選擇器查它的量測都會落空或量到別的東西。

### 20.6 只有 font-weight 受影響

全部受測元素的 **font-size／line-height／color／letter-spacing／font-family**
在乾淨與污染環境下**逐項相同**。反向對照：`html` 根元素（不在選擇器射程內）
兩種環境下皆 16px/450/20px。

### 20.7 逐項更正落在哪

**第一批（2026-08-28，PR #165）**——污染發現當下的重量：

| 文件 | 更正節 | 條數 |
|---|---|---|
| `docs/research/21` | §5.6 | 22 |
| `docs/research/77` | §7.6 | 31 |
| `docs/research/81` | §8.6 | 29 |
| `docs/research/82` | §16.6 | 7 |
| `docs/design/113` | §1.6 | 29 |

合計 **118 條**。
（另有 12 條更早的乾淨值寄存在 `docs/research/81` §8.6 #18–#29，
它們更正的是 `docs/research/94` §4.2 的記載，已計入上表 81 的 29 條內。）

**第二批（2026-08-28，G12 補完）**——四處先前只加守衛、未重量者：

| 文件 | 乾淨重量節 | 列數（更正／一致／未取得） |
|---|---|---|
| `docs/design/47` | §D.1 | 17（9／8／0） |
| `docs/design/64` | §3.1 | 5（1／4／0） |
| `docs/research/91` | §19.6 | 24（9／14／1） |
| `docs/research/94` | §4.6 | 49（27／22／0） |

合計 **95 列：更正 46／一致 48／未取得 1**。

🔴 **`47` §D 的更正不只字重**——變體名（tertiary→**secondary**、split→**secondary**）
與標籤圓角（全圓藥丸→**8px**）都記錯了。

**第三批（2026-08-28，G12b）**——G12 射程設錯而漏掉的：

| 文件 | 乾淨重量節 | 列數（更正／一致／未取得） |
|---|---|---|
| `docs/design/47` | §3b | 10（9／0／1） |
| `docs/research/91` | §15.1 | 4（4／0／0） |

合計 **14 列：更正 13／未取得 1** ⇒ 🔴 **沒有一個原值是對的**。

🔴 **三批總計 213 條更正**（118 ＋ 95 ＋ 14 中的 13 條更正，另 1 條未取得）。

⚠️ **仍未取得**：`47` 的 `--t-xl`（18/24）——四個取樣頁裡 18/24 **只有一個渲染者**
＝頁面標題（也就是 `--t-2xl` 的對象），**不存在** 18/24 的「區段標題」。
未排除的假設（**未驗證**）：原量測可能在 683px 窄版取得，桌機 ≥1280 下標題階可能整體上移。


### 20.8 🔴 對後續量測的紅線

1. **每次量 `font-weight` 前先停用污染源**，且**每次導航後都要重做**（頁面重載會重新注入）：
   `[...document.querySelectorAll('style')].find(s => s.id === 'font-bolder-style').sheet.disabled = true`
   量完還原成 `false`。這只切換 CSSOM 旗標，不動使用者的擴充功能設定。
2. **量文字樣式一律量「實際繪製文字的元素」**，不是它的包裹層。
   ~~判準：`childElementCount === 0` 且有非空 `textContent`。~~
   🔴🔴 **2026-08-28 更正：這個判準在 `slot` 投射結構下會選錯節點。**
   實例（庫存歷程頁卡片標頭）：它唯一命中的是 `display: contents`、rect 0×0 的 `s-heading` **宿主**；
   而真正繪製的 `h2.heading` 反而 **`textContent === ''`、`childElementCount === 1`**（唯一子元素是 `<slot>`）。
   成因＝**文字是宿主的 light-DOM text node，被投射進 shadow 內的 slot；`textContent` 只走 DOM 樹、不走 flat tree**。
   ✅ **改用**：以 `getBoundingClientRect()` **非 0** 為必要條件，
   再沿 **flat tree**（`slot.assignedNodes()` / `Element.assignedSlot`）找 text node 的實際 flat-tree 父。
   🔴 **rect 相同也不代表是同一個節點**：同例中 `div.section-heading-text` 的 rect 與 `h2.heading`
   **逐像素重合**、`textContent` 也一樣，值卻是 450（block 包裝盒，文字不在它的 inline box 裡）。
   ✅ **最可靠的獨立佐證**：對 text node 建 `Range` 量 `getClientRects()` 的實際繪製寬度，
   與同字體同字級的 `canvas measureText` 在各候選字重下對比——實測可分辨到 **0.01px**。
4. 🔴🔴 **`--p-*` 不是單一值——它隨 DOM 子樹而變**（2026-08-28 新增，第三次同型事故的斷根）。
   同一個 `html.p-theme-light` 頁面上，`<s-internal-theme-provider theme="admin" colorscheme="dark">`
   的 shadow root 內有 `<slot class="p-partial-theme-dark">`，把**深色 token 注入被投射的
   light-DOM 子樹**。⇒ **只讀 root computed 的取值，在這些子樹上一律是錯的。**

   **實測規模**（三頁一致，兩個獨立量測者）：
   | 量項 | orders | products | settings/general |
   |---|---|---|---|
   | `s-internal-theme-provider` 總數 | 51 | 179 | — |
   | 其中 `colorscheme="dark"` | 4 | 4 | 4 |
   | 掛 `p-partial-theme-*` class 的 slot | — | 8（4 dark ＋ 4 light） | — |
   | 算出 `--p-color-text === '#eee'` 的元素 | — | **113** | **113** |
   （`/orders` 亦為 113，且 52 個分組名稱與計數與 products 逐項相同。）

   **頂欄就在其中**（`div._TopBar_1scp5_1`）。§14.7 的誤歸因即由此而來。

   ✅ **紀律（機械照做）**：
   - 取任何 `--p-*` 都要**指定在哪個元素上取**，並回報該元素是否落在某個 provider 內；
     沿 flat tree（`parentElement ?? getRootNode().host`）往上走，記下第一個
     `s-internal-theme-provider` 的 `colorscheme` 與第一個 `p-theme-*` / `p-partial-theme-*`。
   - 🔴 **要證明「這個 token 就是畫面上那個顏色的來源」，用消融不用相關性**：
     把候選 token inline 覆寫成一個不可能的值（如 `rgb(1,2,3)`），看繪製色變不變，
     再 `removeProperty` 還原。§14.7 就是這樣定案的（4 個候選同值 `#0a0a0a`，只有 1 個是真來源）。
   - 掃描器**不得**用「排除 selectorText 含 `p-theme` 或 `:root`」當過濾器——
     實測有 **恰 14 條** `--p-*` 宣告位於任何 theme／`:root` 選擇器**之外**
     （Online-Store-UI 系 9、`[data-admin-next] _Badge` 3、`_SidekickField` 1、`_SectionWrapper` 1），
     那個過濾器在構造上看不見這一整類。

5. 🔴 **同名異值的 partial theme scope 至少有六組**，宣告數各不相同（實測，兩個獨立量測者一致）：
   `:root, .p-theme-light` **451**｜`.p-theme-admin, .p-theme-light, :root` **552**｜
   `.p-partial-theme-dark` **221**｜`.p-partial-theme-dark-experimental` **229**｜
   `.p-partial-theme-admin-next` **398**｜`.p-partial-theme-admin-next-dark` **313**｜`.p-partial-theme-mobile` 7/6。

   ⚠️ **但實際被使用的只有兩個**：三頁掃描的 scope class 使用數＝
   `dark` **4**、`dark-experimental` **0**、`admin-next` **0**、`admin-next-dark` **0**、
   `mobile` **0**、`[data-admin-next]` **0**。
   ⇒ `admin-next` 那套（把 7 族 fill 全改成淺彩）**目前零元素在用**，是尚未啟用的調色板。
   **我方對齊的是實際渲染的那一套**；`admin-next` 只登記、不實作
   （但它透露本尊正在往「全族淺 fill」走，值得追蹤）。

6. 🔴 **正規化器不能用「塞進 detached span 的 `color` 再讀 computed」**——
   那個方法**解析不了字型堆疊與陰影**，兩邊都 unparsed 就回同一個繼承色，
   於是那一類差異被**結構性地**歸成「記法差」。實測因此漏掉
   `--p-font-family-sans`（新層多了 `'Noto Sans Arabic', 'Noto Sans Hebrew'`）與
   `--p-shadow-nav-selected`（新層 `none` vs 舊層三層 inset）。
   ✅ **改用逐類別正規化**：color→`color`、shadow→`box-shadow`、
   radius→`border-top-left-radius`、family→`font-family`。

7. 🔴 **「第一個命中」不是樣本，是巧合**（2026-08-28 新增）。
   實例：有人用 `deep('button.Polaris-Button--variantSecondary')[0]` 取「舊層按鈕」基準——
   而 `/products` 頁的 52 顆 `.Polaris-Button` **含文字者 0 顆**，取到的是一顆
   **disabled、純圖示、無標籤**的鈕，於是把停用態底色記成該 variant 的底色、
   把沒有任何文字在用的 13px 行高記成字體階。
   改到 `/discounts` 取真正帶標籤的鈕後：舊層 primary 標籤 **12/600/16**、新層 **12/550/16**
   ——**字級／行高／內距／底色四項全同，只差字重，且舊層比新層重**（原結論方向相反）。
   ✅ **先枚舉母體、看它是什麼，再決定取哪一個**。

3. 🔴 **不得因為某元素在 shadow DOM 內就跳過重量**——見 §20.3 的二次更正。
   `font-weight` 會沿 flattened tree 繼承進 shadow，**必須逐項做 clean/dirty 配對**。
3. ~~🔴 **`docs/design/47` 與 `docs/design/64` 尚未複驗**~~ **（2026-08-28 已補完，見 §20.7 第二批）**
   ⚠️ **但射程不完整**：G12 只點名 `47` **§D**，而 §D 實際上**一個字重值都沒有**；
   `47` 的 **§3／§4／§B／§E 共 10 個 500** 與 `91` **§15 的 4 個 500** 仍未複驗（G12b）。
   以下原文保留備查——它們是更早的 session 在**同一台機器**量的，
   `64` §3 記的「Pill、主要按鈕 13 / 20 / **500**」正是污染值的特徵。
   **未複驗前不得引用那兩份的任何 font-weight 值。**
