# 64 · 實站計算樣式量測（取代 47 號的截圖判讀法）

> 來源：`admin.shopify.com/store/chill-love-u5q5mnzq/products/9874717081835`，2026-08-12。
> 條件：`dpr = 1`、`innerWidth = 2294`、`document.documentElement` 字級 **16px**（使用者已改回 Medium）。

---

## 0. 方法：`getComputedStyle` 穿透 shadow root，不再靠截圖

60 號證實 `s-` 元件是 **open** shadow root。因此 47 號那套「CSS transform 放大 + 高倍率截圖 + 目視判讀」可以整個退役：

| | 47 號舊法 | 本檔新法 |
|---|---|---|
| 取值方式 | 截圖放大目視 | `getComputedStyle()` 直接讀 |
| 精度 | 目視估計（`0.667px` 這種只能推） | **實際值**（讀到 `0.66px`） |
| 失敗模式 | CDP `Page.captureScreenshot` 逾時（本專案已逾時 3 次） | 無 |

**兩個必要技巧**（沒有這兩條會全部量到 0）：

1. `s-internal-*` host 是 `display:contents`，`getBoundingClientRect()` 回 **0×0**。要量的是**它 shadow root 內第一個有尺寸的後代**：
   ```js
   const inner = h => h.shadowRoot ? [...h.shadowRoot.querySelectorAll('*')].find(visible) : null;
   ```
2. 走訪器必須同時走 `firstElementChild` 鏈**與** `shadowRoot` 鏈，且**每次 navigate 後要重新注入**。

---

## 1. 版面

| 項目 | 實測 |
|---|---|
| 頁面底色 | **`rgb(241,241,241)`**（#F1F1F1） |
| 左欄（主） | `x=776`，**寬 633** |
| 右欄（次） | `x=1425`，**寬 317**；內層盒 `x=1441` 寬 **285**（⇒ 右欄左內距 16） |
| 卡片間垂直間距 | **16**（同群）／**52**（跨群） |

---

## 2. 卡片（`s-internal-section`）

```
圓角 12px ／ 背景 #FFF ／ border-width: 0（沒有邊框）
```

**陰影是六層堆疊，最後一層就是那條「邊框」**：

```css
box-shadow:
  rgba(0,0,0,.03) 0 5px   5px   -2.5px,
  rgba(0,0,0,.02) 0 3px   3px   -1.5px,
  rgba(0,0,0,.02) 0 2px   2px   -1px,
  rgba(0,0,0,.03) 0 1px   1px   -0.5px,
  rgba(0,0,0,.04) 0 0.5px 0.5px  0,
  rgba(0,0,0,.06) 0 0     0      1px;   /* ← 這層取代 border */
```

> **這解釋了 47 §H2-4 的「用 inset box-shadow 而不是 border」為什麼是全站規則**：卡片外框與表單控件框都是 box-shadow，所以框線不佔 box model、可做次像素、且能與投影合成一次繪製。
> 前五層是**遞減的柔和投影**（offset/blur/spread 同步收斂），不是隨手疊的。

---

## 3. 排版階梯（實測值，非估計）

| 用途 | 字級 / 行高 / 字重 |
|---|---|
| 卡片標題 `h2` | **13 / 20 / 600** |
| 內文、輸入框文字、標籤 | **13 / 20 / 450** |
| 段落 | 13 / 20 / 450 |
| Badge | **12 / 16 / 550** |
| Pill、主要按鈕 | 13 / 20 / **500** |

> 🔴🔴 **2026-08-28 守衛：「Pill、主要按鈕 13 / 20 / 500」那一列待複驗，未複驗前不得引用。**
> 2026-08-28 發現本機的 Chrome 有一個擴充功能注入
> `body, body :not(svg)… { font-weight: 500 !important }`，會把 **light DOM** 的字重
> **雙向**改寫成 500（450 拉高、550 壓低）。🔴 **shadow DOM 不是無條件免疫**——
> `font-weight` 會沿 flattened tree 繼承進 shadow（全文＝`docs/design/111` §20.3）。
> **500 正是污染值的特徵**，而本尊的 `--p-font-weight-*` 值域是 **450/550/600/650，沒有 500**。
> 本表其餘三列（450／550／600）不在污染值上，應為乾淨——但本檔的量測環境未載明，
> **無法確認當時該擴充功能是否已安裝**。
> 已知乾淨值（2026-08-28 重量）：`.Polaris-Button` ＝ **13px / 450**、
> `--p-font-weight-button-label` ＝ **550**、`s-internal-button` 的繪製盒 ＝ **12px / 550**。
> ⇒ 本列的「500」要嘛是污染、要嘛量到了不繪製文字的包裹層，兩者都需重量才能定案。
> 登記＝`docs/design/110` 的 **G12**。

> **450 與 550 都出現了**，且是不同用途：450 是內文與輸入值，550 是 badge，500 是可點控件（pill／按鈕），600 是卡片標題。
> 這四階**只有可變字體軸能渲染**——靜態權重清單會把 450→400、550→500/600，階層直接塌掉。48 號 §00.11 的 `--fw-split: 550` findings 由此得到第二個佐證。

---

## 4. 控件尺寸

| 元件 | 實測 |
|---|---|
| 表單控件盒（輸入框本體） | **高 32**、圓角 **8**、背景 `rgb(253,253,253)`、框線 = `rgb(138,138,138) 0 0 0 **0.66px** inset` |
| `s-internal-text-field` 整組 | 高 **56** ＝ 標籤 20 ＋ 控件 32 ＋ 間距 4 |
| `single-picker-field` 整組 | 高 **32**（無獨立標籤列） |
| Pill | 高 **28**、圓角 **8**、內距 **4 / 8**、無框、背景透明、色 `rgb(48,48,48)` |
| 主要按鈕（儲存） | 高 **28**、圓角 **8**、內距 **6 / 12** |
| Badge | 高 **20**、圓角 **8**、內距 **2 / 8**、背景 `rgba(0,0,0,.06)` |
| Switch | **32 × 24**（內距 4 / 0） |
| Checkbox | **16 × 16** |
| 圖示 | **20 × 20** |
| Drop zone | 高 **196.4** |

### ⭐ 髮絲線的實際值：`0.66px`

**在 `dpr = 1` 的螢幕上量到 `0.66px`。** 這推翻了 47 §C 的解釋方式——它當時認為髮絲線＝「1 個裝置像素」（dpr 1.5 → 0.667px）。實際上 **Shopify 是直接寫死次像素值 `0.66px`，與 dpr 無關**。

對我方的意義：`--hairline` 不該用 `1px / var(--dpr)` 這種算式，就是一個固定的次像素常數。**47 §C 與 48 §00.4 的三檔 media query 寫法要改。**

---

## 5. 焦點環

輸入框本身：`outline-style: none`、`box-shadow: none` ⇒ **焦點環不畫在 `<input>` 上**，畫在外層控件盒。

> ⚠️ 本輪只確認了「不在 input 上」，**外層盒的聚焦樣式沒量到**（focus 時父層 `box-shadow` 讀到 `none`，代表真正承載焦點環的是更外面或 pseudo-element 的節點）。登記為 **V-127**，下一輪用 `:focus-visible` 逐層往上掃。
> 47 §H2-3′「outline 與 box-shadow 並用」的結論**不受影響**（那是全站 437 條規則的統計），但商品頁輸入框的**具體**焦點環仍未定。

> ✅ **2026-08-28：V-127 結案。** 焦點環畫在
> `s-internal-text-field` → shadowRoot → `div.input-wrapper` 上，值為
> **`outline: 2px solid #005bd3` ＋ `outline-offset: 1px`**；同時該盒 background
> `#fdfdfd`→`#f7f7f7`、inset 髮絲環 `#8a8a8a 0.66px`→`#1a1a1a 1px`。
> `<input>` 自身的 outline 與 box-shadow 仍為 `none`（與本節原觀察一致）。
> 取值法＝穿透 open shadow root（`47` §A 的「closed」前提已更正）。全表＝`docs/design/113` §1.2。
>
> ⚠️ **但焦點環不是全域一致**：設定區的側欄導覽項實測是**瀏覽器預設 `outline auto 1px`**，
> 沒有 `#005bd3` 環（已在 `document.hasFocus()=true` 下複驗）。只有表單控件才有。
> 這是本尊自身的不一致，見 `docs/research/81` §8.4。

---

## 6. 一個刻意不跟的地方

pill 與按鈕的 `transition` 實測是 **`all`**。

我方 `scripts/lint-prototype.py` 有一條規則**禁止 `transition: all`**（依 47 §5：實站真正生效的只有 9 條具名 transition）。兩者衝突。

**處置：維持我方禁令，不跟。**

> 🔴 **2026-08-28 補測：本節的前提在新層已不成立。**
> `s-button`（web component 層）的 `transition` computed 實測是 **`none`**——primary／secondary／
> tertiary 三者皆然。`all` 只出現在**舊 Polaris React 層**的容器與 slim tertiary 按鈕上
> （`docs/design/111` §17.1：本尊有兩套設計系統世代並存）。
> ⇒ **我方禁令與新層一致，不再是「刻意偏離」**。本節保留原文備查，但引用時必須標明適用層。
> 本輪在商品列表頁另量到四處**具名** transition：勾選框（border-color／border-width／box-shadow
> 各 .1s `cubic-bezier(.19,.91,.38,1)`）、排序圖示（opacity .1s）、switch（background-color／
> border-color 各 .1s）、檢視活化鈕（max-width .3s）。詳見 `docs/research/77` §7。
 理由：`transition: all` 會連帶動畫非預期屬性（例如 pill 展開時的 `height`），且無法對應 M1–M7 具名動效規則。這是**我方刻意偏離實測**，記在此處以免日後被當成漏抄。

---

## 7. 與既有量測文件的關係

| 文件 | 處置 |
|---|---|
| `47-measured-interaction-spec.md` | **§C 髮絲線的解釋要改**（不是裝置像素，是固定 0.66px）；其餘量測值本檔未推翻 |
| `48-component-contract.md` | §00.4 邊框寬、§00.8 陰影（要換成六層堆疊）、§00.11 字重（450/500/550/600 四階）需回填 |
| 本檔 | 之後所有量測**一律用 `getComputedStyle` 穿透法**，不要再開截圖 |
