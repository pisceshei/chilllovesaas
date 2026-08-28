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
> ✅ **2026-08-28 已完成乾淨重量 ⇒ 見本檔 §3.1**。結果：「Pill、主要按鈕 13 / 20 / 500」那一列
> **既量錯層又被污染**，乾淨值拆成六個不同的節點（Pill 容器 13/450、Pill 標籤 13/450、
> Pill 值 12/550、主要按鈕容器 13/450、按鈕文字 12/600…）。其餘四列複驗一致。

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

---

## 3.1 🔴 乾淨環境重量（2026-08-28，G12 補完）

> 本節依**鐵律 19.5**追加，**上方原記載保留原文**。
> 觸發＝`docs/design/110` 的 **G12**：本檔的 `font-weight` 值曾在受污染的環境下量測。
> 污染源與機制＝`docs/design/111` §20。
>
> **全部數值以「停用污染源 → 讀 clean → 還原 → 讀 dirty」的同步配對取得**，
> 收工已還原成使用者原狀並複驗。
>
> ⚠️ 只有 `font-weight` 受污染；font-size／line-height／color 等在兩種環境下相同——
> 但本輪**一併複驗**了它們，因此下表也含非字重的更正（那些屬「量錯層」或原記載本身有誤）。

**本節結果：5 列（更正 1／複驗一致 4／未取得 0）**

| # | 項 | 判定 | 原記載 | 🔴 乾淨值 | 污染值 | 實際量的節點 |
|---:|---|:--:|---|---|---|---|
| 1 | 卡片標題 `h2`（§3 第 1 列） | ✅ 一致 | 13 / 20 / 600 | **13px / 20px / 600（`h2.heading` 與其 `<slot>` 同值；量了 Product organization / Search engine listing / Variants / Price / Inventory / Shipping 六個，全部 600）** | 13px / 20px / 600（完全相同） | `s-heading` / `s-internal-heading` 的 **shadowRoot 內 `h2.heading`**（shadow DOM），以及其 `<slot>`（被 slot 出去的文字節點在 flattened tree 的父）。`h2.heading` **自宣告** font-weight（走 `--p-font-weight-heading-medium`），故對文件級污染免疫。⚠️ 宿主 `s-heading` 本身是 `display:contents`、rect 0×0，量它得到的是繼承值 450，不是標題外觀值。 |
| 2 | 內文、輸入框文字、標籤（§3 第 2 列） | ✅ 一致 | 13 / 20 / 450 | **①13px / 20px / 450　②13px / 20px / 450　③13px / 20px / 450（三者一致）** | ①450（免疫）②**500**（450 被拉高）③450（免疫） | 三種形態各量一個：①標題輸入框 `<input>`（在 `s-internal-text-field` 的 shadow 內，**自宣告** font-weight ⇒ 免疫）②價格輸入框 `<input>`（**light DOM**，自宣告但無 !important ⇒ 被污染）③欄位標籤 `span.label-content`（shadow 內，**未自宣告**，沿 flattened tree 繼承 shadow 內祖先 ⇒ 仍免疫）。 |
| 3 | 段落（§3 第 3 列） | ✅ 一致 | 13 / 20 / 450 | **①13px / 20px / 450　②13px / 20px / 450** | ①450（免疫）②**500** | ①`s-paragraph` 的 shadowRoot 內 `<p>`（shadow，**自宣告** ⇒ 免疫）②Pricing 卡 pill 內的 `<p>` leaf「Compare-at」（**light DOM**，自宣告無 !important ⇒ 被污染）。兩者皆 `childElementCount===0` 且有非空 textContent。 |
| 4 | Badge（§3 第 4 列） | ✅ 一致 | 12 / 16 / 550 | **12px / 16px / 550（三個 s-* badge 一致）；light DOM 導航計數 badge leaf 亦 12px / 16px / 550** | s-* badge 三個皆 **550（完全相同，免疫）**；light DOM 導航計數 badge leaf **500**（550 被壓低——同一個 550 在不同 DOM 層一個活一個死） | `s-internal-badge` 的 shadowRoot 內 `div.badge.size-base.tone-*` 及其 `<slot>`（shadow，`div.badge` **自宣告** font-weight ⇒ 免疫）。量了 tone-auto「5」、tone-success「Active」、tone-auto「HK$2,000.00」三個。另量 light DOM 的導航計數 badge leaf 作對照。 |
| 5 | Pill、主要按鈕（§3 第 5 列）🔴 | 🔴 更正 | 13 / 20 / 500 | **①Pill 容器 **13px / 20px / 450**<br>②Pill 標籤 leaf **13px / 20px / 450**<br>③Pill 值 leaf **12px / 16px / 550**<br>④主要按鈕容器 **13px / 20px / 450**<br>⑤主要按鈕文字 leaf **12px / 16px / 600**<br>⑥`s-internal-button .button.variant-primary` **12px / 16px / 550**（與 `docs/research/77` §7 的頁首按鈕 12px / 550 / 16px 一致）<br>附帶：`.button.variant-tertiary` 12/16/550（免疫）、`.button.variant-plain` 13/20/450 → 污染 500（與任務簡報所述反例相符）** | ①**13px / 20px / 500** ←（＝64 §3 記載值）<br>②500　③500（550 被壓低）<br>④**13px / 20px / 500** ←（＝64 §3 記載值）<br>⑤500（600 被壓低）<br>⑥550（免疫，不變） | 64 §3 把「Pill」與「主要按鈕」合成一列給一個三元組，但實測是**四個不同節點、四個不同值**，且它記的 13/20/500 只在**容器盒＋污染態**下成立：<br>①Pill 容器 `div._BasePill_…`（light DOM，**未自宣告** font-weight）—— 高 28 / 圓角 8 / 內距 4px 8px / 無框 / 色 rgb(48,48,48)，與 64 §4「Pill」幾何逐項吻合 ⇒ 這就是 64 當初量的節點之一。**它不畫文字**（文字在其內部 leaf）。<br>②Pill 標籤 leaf `<p>`「Compare-at」（light，實際畫字）。<br>③Pill 值 leaf `<span>`（在 `s-internal-badge` 的 light 內容內，實際畫字）。<br>④主要按鈕容器 `button.Polaris-Button--variantPrimary`「Save」（light，**未自宣告**）—— 高 28 / 圓角 8 / 內距 6px 12px，與 64 §4「主要按鈕（儲存）高 28、圓角 8、內距 6/12」**逐項吻合** ⇒ 這是 64 當初量的另一個節點。<br>⑤主要按鈕文字 leaf `span.Polaris-Text--bodySm.Polaris-Text--semibold`「Save」（light，實際畫字，**自宣告** `--p-font-weight-semibold`）。<br>⑥同頁另一套實作：`s-internal-button` shadowRoot 內 `.button.variant-primary`（shadow，**自宣告** ⇒ 免疫）。 |

### 3.1.a 本次重量帶出的規律

1. 🔴 **§3 第 5 列的結語前半句『500 是可點控件（pill／按鈕）』作廢。** 乾淨事實是：pill 標籤 450、pill 值 550、Polaris 主要按鈕文字 600、s-* 按鈕文字 550 ⇒ **可點控件根本沒有專屬字重階**，它們散落在既有的 450/550/600 三階上。而且 500 不在本尊 token 值域內（實測 `--p-font-weight-*` ＝ 450/550/600/650），一個不存在的 token 值不可能是設計語義。結語後半句『這四階只有可變字體軸能渲染』**不受影響、且更強**：刪掉 500 之後階梯是 450/550/600(/650)，其中 450 與 550 仍然都不是靜態權重清單（100 的倍數）能表達的值，可變字重軸的必要性不變。
2. 🔴 **這一列同時犯了兩個獨立的錯，缺一都不會產生 13/20/500。** 錯誤一＝**量錯層**：`div._BasePill_` 與 `button.Polaris-Button--variantPrimary` 都是容器盒，`childElementCount > 0`、不畫任何字；它們的 font-weight 只是繼承值，真正畫字的 leaf 在它們**內部**，而且字級不同（12/16 而非 13/20）。錯誤二＝**被污染**：這兩個容器都在 light DOM 且未自宣告 font-weight，繼承鏈直達被拉到 500 的 `body`。若只犯錯誤一（容器但乾淨）會記成 13/20/**450**；若只犯錯誤二（文字 leaf 但污染）會記成 12/16/**500**。兩錯疊加才恰好是 13/20/500。
3. 🔴 **『記到 500』本身就是污染的充分指標。** 本輪對可見葉節點（排除 style/script/隱藏/零尺寸，n=77）做直方圖：clean＝450×45 / 550×27 / 600×3 / 400×2，**500 出現 0 次**；同一組節點 dirty＝500×60 / 450×16 / 600×1。也就是說乾淨環境下這頁沒有任何一個繪製盒是 500。反過來，55x/60x 記載反而是「當時沒被污染到那個元素」的證據（因為污染會把 550、600 一律壓成 500）。
4. 🔴 **污染的判準是『該元素自己有沒有宣告 font-weight』，不是『它在不在 shadow 裡』——本輪五列全部複現這條。** 免疫的：`h2.heading`（shadow＋自宣告）、`div.badge`（shadow＋自宣告）、`.button.variant-primary/-tertiary`（shadow＋自宣告）、標題 `<input>`（shadow＋自宣告）、`span.label-content`（shadow＋未自宣告，但祖先鏈整段在 shadow 內故未被切入）。被污染的：`_BasePill_`、`Polaris-Button--variantPrimary`、pill 的 `<p>`／`<span>` leaf、價格 `<input>`、導航計數 badge leaf、`.button.variant-plain`（shadow 但**未自宣告**，沿 flattened tree 繼承宿主的 500）。
5. 🔴 **同一個語義元件在本尊有兩套並存實作，把它們寫成同一列必然自相矛盾。** s-* web component 層：`s-internal-button .button.variant-primary` ＝ 12/16/**550**（吃 `--p-font-weight-button-label=550`），與 `docs/research/77` §7 的頁首按鈕 12px/550/16px 相符。Polaris React 層：`.Polaris-Button--variantPrimary > span.Polaris-Text--semibold` ＝ 12/16/**600**（吃 `--p-font-weight-semibold=600`）。兩者在同一頁同時存在、高度都是 28。回寫 §3 時必須分兩列並標明所屬層，否則下一個人一定會再撞一次。
6. **`display:contents` 的 host 是第二個『量錯層』陷阱，與污染無關、獨立存在。** `s-heading` / `s-internal-heading` / `s-internal-badge` 的宿主 rect 皆 0×0，其 computed font-weight 是純繼承值（分別讀到 450／450／400），與元件外觀毫無關係；卡片標題的 600 只在其 shadowRoot 內的 `h2.heading` 上讀得到。任何『穿透 shadow 取第一個有尺寸的後代』的走訪器要走到 leaf 才停，停在 host 或停在第一個有尺寸的容器都會取到錯的值。
7. **回寫 §3 建議的最小改法（不擴修）**：把第 5 列拆成四列並各自標明量的是哪個節點——Pill 標籤 13/20/450；Pill 值（badge 形態）12/16/550；主要按鈕（Polaris React 層）12/16/600；主要按鈕（s-* 層）12/16/550。第 1–4 列原樣保留（本輪實測全部成立）。同時在 §3 或 §0 補一句量測紀律：只量 `childElementCount===0` 且有非空 textContent 的節點，並記明 shadow/light 與是否自宣告 font-weight。

### 3.1.b 仍未取得

- 本輪 innerWidth=787 / dpr=1.25，與 64 號原記載的 innerWidth=2294 / dpr=1 不同；`resize_window` 已知無效（工具回報成功但渲染面凍結），故**未能在 2294px 寬複驗**。佐證（非證明）：本輪五列量到的 font-size / line-height 與 64 §3 在 2294 寬記載的逐列相同（13/20、13/20、13/20、12/16、13/20），顯示這段排版階梯在兩個寬度下未變；但「字重完全與視窗寬度無關」本身未逐寬實測，登記為未取得。
- 64 §3 的原量測環境未載明（是否已裝該擴充、當時 root font-size、視窗寬皆無記錄），故**無法直接證明** 64 當初就是在污染態下量的。本輪只能給間接證據：Pill 容器與主要按鈕容器兩個節點在污染態下**恰好都算出 13/20/500**（正是 64 記的三元組），且兩者的高度 28 / 圓角 8 / 內距 4-8 與 6-12 與 64 §4 的「Pill」「主要按鈕（儲存）」幾何**逐項吻合**。判定「量錯層＋被污染」為最合理解釋，但這一步是推斷不是實測。
- `--p-line-height-button-label` 這個 CSS custom property 在本頁讀到空值（不存在）。已取得的相關 token 實測值：`--p-font-weight-regular=450`、`-medium=550`、`-semibold=600`、`-bold=650`、`-heading-medium=600`、`--p-font-weight-button-label=550`、`--p-font-size-button-label=.75rem`（＝12px）。值域中**沒有 500**，與任務簡報一致。
- `s-internal-button` 的 `.button.variant-secondary` 在本頁未出現可見實例（只取到 primary / tertiary / plain 三種），其乾淨字重未取得。
- 只量了商品詳情頁一頁。64 §3 標題寫「排版階梯」有全站語氣，但本輪未在訂單／顧客／設定等其他頁面複驗這五列；跨頁一致性未取得。
- 64 §4 記 Pill「背景透明」，本輪在 clean 態讀到 `rgba(0, 0, 0, 0.06)`（與該檔記的 Badge 背景同值）。未查明是狀態差異（hover/focus）還是原記載有誤——超出本次指派射程（§3），僅登記不裁定。
- 本輪量到的「Save」按鈕背景為 `rgba(0, 0, 0, 0.17)`，是**無未儲存變更時的停用態**（全程唯讀，未製造變更）。停用態不影響 font-weight（文字 leaf 自宣告 600），但啟用態的字重未實測。

> 量測環境：量測日期 2026-08-28。頁面＝`https://admin.shopify.com/store/chill-love-u5q5mnzq/products/9874717081835`（與 64 號原記載同一 URL，該 id 不在五個禁碰之列）。Chrome/151.0.0.0，**innerWidth=787、innerHeight=372、devicePixelRatio=1.25、`document.documentElement` font-size=16px**（64 號原量測為 innerWidth=2294、dpr=1，root 16px ⇒ 本輪視窗寬與 dpr 皆不同，見 not_obtained 第 1 項）。全程唯讀：未點擊任何控件、未輸入、未儲存；收工複驗 `document.body.innerText` 不含 `Unsaved changes`。  **「已停用污染源後量測」的聲明**：使用者 Chrome 擴充在 `<style id="font-bolder-style">`（parentNode＝`HTML`）注入單一規則，選擇器＝`body, body :not(svg):not(svg *):not(img):not(video):not(canvas)`，宣告 4 個屬性（font-weight / text-shadow / -webkit-font-smoothing / text-rendering），本輪逐一複驗過。每一列的 clean 值都是在 `ext.sheet.disabled = true` 狀態下以 `getComputedStyle()` 讀出，dirty 值是同一次呼叫內把旗標切回 `false` 後對**同一個節點物件**再讀一次 ⇒ 每列都是真正的 clean/dirty 配對，不是兩次獨立取樣。  **收工還原複驗**：最後一次呼叫顯式設 `ext.sheet.disabled = false`，並複驗 `getComputedStyle(document.body).
