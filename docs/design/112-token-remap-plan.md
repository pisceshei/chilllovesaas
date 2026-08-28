# 112 — 我方 token 換值計畫（量測三段式的第③段）

> 建立 2026-08-28。依 `docs/DECISIONS.md` **D54**（視覺 1:1，token 表換成本尊量測值）。
>
> 三段式的前兩段：①token 值表＝`docs/design/111`；②元件量測＝各 teardown 的 CSS 三段式節。
> **本檔是第③段「我方 token 映射」**——把量到的值落到我方 token 名上。
>
> 🔴 **本檔是計畫，不是已執行**。實際改 `app/assets/tokens.css` 與 `docs/design/23` §1
> 是另一個工作包（改完必須重驗每一個已實作畫面）。
>
> 🔴 **鐵律 8 不變**：實作一律用我方 token 名，CSS 由我方撰寫。換的是**值**，不是機制。
> 🔴 **鐵律 9 不變**：只採用量測到的數值，不複製 Shopify 的樣式表原始碼。

## 0. 對照方法

| 欄 | 意思 |
|---|---|
| 我方 token | `app/assets/tokens.css` 現有名稱（223 個） |
| 現值 | HEAD 的值 |
| 本尊值 | `docs/design/111` 的量測值 |
| 依據 | 111 的節號 |

🔴 **「本尊對應」是語義判斷，不是量測**。每一列在執行前都要複核配對本身對不對。

導出現值：

```bash
python -c "
import io, re
s = io.open('app/assets/tokens.css', encoding='utf-8').read()
for n, v in re.findall(r'(--[a-z0-9-]+)\s*:\s*([^;]+)', s):
    print(n, ' '.join(v.split())[:60])
"
```

## 1. 已命中本尊，不必動（15 列，含一列三條 ease）

| 我方 token | 值 | 本尊對應 | 依據 |
|---|---|---|---|
| `--bg` | `#f1f1f1` | `--p-color-bg` | 111 §14.1 |
| `--surface` | `#fff` | `--p-color-bg-surface` | 111 §14.2 |
| `--icon` | `#4a4a4a` | `--p-color-icon` | 111 §14.1 |
| `--text-disabled` | `#b5b5b5` | `--p-color-text-disabled` | 111 §14.8 |
| `--focus` | `#005bd3` | `--p-color-border-focus` | 111 §14.10 |
| `--border-control` | `#8a8a8a` | `--p-color-input-border` | 111 §14.11 |
| `--surface-bright` | `#fdfdfd` | `--p-color-input-bg-surface` | 111 §14.11 |
| `--hairline` | `.66px` | `--p-border-width-0165` | 111 §3 |
| `--topbar-h` | `56px` | `--pg-top-bar-height` | 111 §16 |
| `--sidebar-w` | `240px` | `--pg-navigation-width` | 111 §16 |
| `--sz-icon` | `20px` | 導航／內文 icon 容器 | 111 §16 |
| `--z-topbar` | `517` | `--p-z-index-9` | 111 §13 |
| `--z-popover` | `520` | `--p-z-index-12` | 111 §13 |
| `--ease-standard`／`--ease-in-out`／`--ease-decelerate` | 三條 cubic-bezier | `--p-motion-ease`／`-in-out`／`-out` | 111 §10 |
| `--sh-card` | 6 層 | `--p-shadow-100` | 111 §9（幾何逐值相同；alpha 十進位 vs hex，等值到兩位小數） |

⚠️ `--scrim`（`rgba(0,0,0,.5)`）**不列在這裡**：它對到的是**舊 Polaris modal** 的遮罩（`82` §16.2），
新層是 `--p-color-backdrop-bg`＝`#000000b5`（111 §14.7）。依 D54 ③「只取新層」，
它歸入 §2.1 換值。

## 2. 需換值（有量測值，可執行）

### 2.1 中性色（16 項，含 `--scrim`）

| 我方 token | 現值 | → 本尊值 | 本尊 token | 依據 |
|---|---|---|---|---|
| `--text` | `#1a1c1e` | **`#303030`** | `text` | 111 §14.1 |
| `--text-2` | `#6b6d71` | **`#616161`** | `text-secondary` | 111 §14.8 |
| `--text-3` | `#67696e` | **`#616161`** | `text-tertiary`（本尊與 secondary 同值） | 111 §14.8 |
| `--brand` | `#2b2c2e` | **`#303030`** | `bg-fill-brand` | 111 §14.4 |
| `--brand-hover` | `#1f2022` | **`#1a1a1a`** | `bg-fill-brand-hover` | 111 §14.4 |
| `--surface-2` | `#f7f7f8` | **`#f7f7f7`** | `bg-surface-secondary` | 111 §14.2 |
| `--surface-3` | `#fafafb` | **`#f3f3f3`** | `bg-surface-tertiary` | 111 §14.2 |
| `--border` | `#e3e3e6` | **`#e3e3e3`** | `border` | 111 §14.10 |
| `--border-2` | `#ececef` | **`#ebebeb`** | `border-secondary` | 111 §14.10 |
| `--border-strong` | `#c9cace` | **`#ccc`** | `border-hover` | 111 §14.10 |
| `--border-hover` | `#a9aaae` | **`#616161`** | `input-border-hover` | 111 §14.11 |
| `--surface-hover` | `#ededee` | **`#f1f1f1`** | `nav-bg-surface-hover` | 111 §14.13 |
| `--surface-row-hover` | `#fafafc` | **`#f7f7f7`** | `bg-surface-hover` | 111 §14.2 |
| `--surface-selected` | `#f0f5ff` | **`#f1f1f1`** | `bg-surface-selected` | 111 §14.2 |
| `--surface-sunken` | `#e6e6e9` | **`#e3e3e3`** | `bg-fill-tertiary` | 111 §14.4 |
| `--scrim` | `rgba(0,0,0,.5)` | **`#000000b5`** | `backdrop-bg` | 111 §14.7 |

🔴 **`--surface-selected` 是最大的一項**：我方是品牌藍 `#f0f5ff`，本尊是中性 `#f1f1f1`
——本尊的**選取態不用品牌色**。改這一項會讓表格選取列從藍色變灰色，視覺變化明顯，
但那正是 1:1 的要求。

🔴 **`--surface-hover` 與 `--surface-selected` 在本尊是不同來源**：
前者是 `nav-bg-surface-hover`（導航用），後者是 `bg-surface-selected`（表面用），
**兩者恰好同為 `#f1f1f1`**。我方目前兩個都不對且方向相反（一個太深、一個換了色相）。

⚠️ **設定區導覽的 hover／selected 是對調的**（`81` §8.4）：實測 selected＝`#f3f3f3`、
hover＝`#f1f1f1`，即 **hover 比 selected 深**，且用的 token 名與用途相反。
換值後**必須逐畫面複驗**，不能只信 token 名。

### 2.2 字重（`--fw-*`，11 項）

> 🔴 **2026-08-28（G13 定案）：不得為 per-location 表頭詞新增 650 階。**
> `docs/research/77` §7.6.1 曾建議「另立 650 token 條目」，**該建議已撤回**——
> 它量到的是 tooltip 內文的粗體強調（13px/20px，popover 預設 `display: none`），
> 不是表頭詞。表頭詞映射到**既有的 550**（12px / lh 16px / `color-subdued`）。
> 若日後要為「tooltip 內文粗體」立 650，需**另案取證**並註明它是 13px/20px 且僅 hover 態可見。

本尊 token 值域＝**450 / 550 / 600 / 650**，**沒有 400、500、700**（111 §7）。
我方現有 `--fw-xs:500`、`--fw-md:500`、`--fw-xl:500`、`--fw-control:500` 四項落在值域外。

| 我方 | 現值 | → | 理由 |
|---|---|---|---|
| `--fw-lg`（卡片標題） | 450 | **600** | 本尊新層 heading＝13/600（111 §17.1，該值在 shadow 內未受污染）；我方 `tokens.css` 註釋自己已記下這個矛盾 |
| `--fw-title` | 600 | 600 ✅ | — |
| `--fw-split` | 550 | 550 ✅ | `--p-font-weight-medium`／`button-label` |
| `--fw-badge` | ＝split | 550 ✅ | badge 實測 12/550 |
| `--fw-2xs` | 600 | 600 ✅ | — |
| `--fw-xs`／`--fw-md`／`--fw-xl`／`--fw-control` | 500 | 🔴 **已解**：450／450／600／550 | 見下（2026-08-28 更正） |

> 🔴🔴 **2026-08-28 更正：阻塞已解除，而且方向與原本寫的相反。**
> 「實際 computed 有 483 個 500」是**量測環境污染**——使用者 Chrome 的擴充功能注入
> `font-weight: 500 !important`（全文＝`docs/design/111` §20）。**本尊沒有 500 這一階。**
> 乾淨直方圖：`450×981 / 550×187 / 600×4 / 400×13`。**原文以下保留備查**（鐵律 19.5）。

**我方四個 `500` 的處置（逐項，依乾淨量測）**：

| 我方 token | 現值 | → | 依據（乾淨量測） |
|---|---|---|---|
| `--fw-xs`（12px 級） | 500 | **450** | `.Polaris-Text--bodySm` ＝ 12px/450；`s-internal-text` ＝ 12px/450 |
| `--fw-md`（14px 級） | 500 | **450** | body 與一般內文一律 450（`--p-font-weight-regular`） |
| `--fw-xl`（18px 級） | 500 | **600** | 頁標題 `h1.heading` ＝ 18px/**600**/24px（在 shadow 內，從未被污染） |
| `--fw-control` | 500 | **550** | `--p-font-weight-button-label` ＝ 550；側欄導航項的繪製 `<span>` ＝ 13px/550 |

⚠️ **每一列都要複核配對**——同一個 500 在不同角色上的乾淨值不同（450／550／600 三種都有）。
逐元件的乾淨值＝各 teardown 的更正節（`21` §5.6／`77` §7.6／`81` §8.6／`82` §16.6／`113` §1.6）。

---

**（原文，已撤回）** 🔴 500 這一階不能機械替換。本尊 token 值域沒有 500，但實際 computed 有
483 個元素是 500（body 自身、側欄導航項都是），而 500 的來源規則未查明（111 §19）。
⇒ 先查明來源再改；在那之前 `--fw-*:500` 維持現值並登記。

### 2.3 行高（`--lh-*`，8 項）

| 我方 | 現值 | → 本尊 | 依據 |
|---|---|---|---|
| `--lh-2xs`（配 11px） | `14px` | **`12px`** | `body-x-small`＝12（111 §6） |
| `--lh-xs`（配 12px） | `16px` | 16 ✅ | `body-small` |
| `--lh-sm`（配 13px） | `20px` | 20 ✅ | `body-medium` |
| `--lh-md`（配 14px） | `20px` | 20 ✅ | `body-large` |
| `--lh-lg`（配 16px） | `20px` | 🔴 **本尊無 16px 語義階** | 見 §4 |
| `--lh-xl`（配 18px） | `24px` | 24 ✅ | `display-small` |
| `--lh-2xl`（配 20px） | `24px` | 🔴 **本尊無 20px 語義階** | 見 §4 |
| `--lh-3xl`（配 24px） | `32px` | 32 ✅ | `display-medium` |

### 2.4 圓角（`--r-*`）

| 我方 | 現值 | → 本尊 | 依據 |
|---|---|---|---|
| `--r-100` | `4px` | 4 ✅ | `-100`／`control-inner`／`checkbox`／`focus` |
| `--r-200` | `8px` | 8 ✅ | `-200`／`action`／`control`／`element` |
| `--r-300` | `12px` | 12 ✅ | `-300`／`container`／`popover` |
| `--r-400` | `18px` | 🔴 **`16px`** | 本尊**沒有 18px 階**；最大容器圓角＝`dialog` 16（111 §2） |
| `--r-pill` | `999px` | 9999 ⇒ 等效 ✅ | `full`＝624.9375rem |

🆕 **缺一階 6px**（`--p-border-radius-150`／`tag-inner`）——`94` §4 量到 adjust chip 用它。

### 2.5 間距（`--sp-*`）

我方 8 階（2/4/6/8/12/16/24 ＋ group），本尊 20 階。**現有 7 個數值階全部命中本尊**，
缺的是**上半段**：

| 缺 | 本尊 token | 用途（實測） |
|---|---|---|
| `10px` | `-250` | — |
| `20px` | `-500` | 卡片內距的一種 |
| `28px` | `-700` | — |
| `32px` | `-800` | modal margin、頁面外距 |
| `40／48／64…` | `-1000`／`-1200`／`-1600` | 大版面 |

⚠️ **我方缺 `--sp-500:20px` 與 `--sp-800:32px`**，而既有量測文件已經在引用這兩個名字
（`110` §3 的 27 個空頭 token 之列）。

### 2.6 字級（`--t-*`）

| 我方 | 值 | 本尊 | 判定 |
|---|---|---|---|
| `--t-2xs` | 11 | `-275`＝11 ✅ | |
| `--t-xs` | 12 | `-300`＝12 ✅ | |
| `--t-sm` | 13 | `-325`＝13 ✅ **主力** | |
| `--t-md` | 14 | `-350`＝14 ✅ | |
| `--t-lg` | 16 | `-400`＝16 ✅（但**無語義階用它**） | 見 §4 |
| `--t-xl` | 18 | `-450`＝18 ✅（`display-small`） | |
| `--t-2xl` | 20 | `-500`＝20 ✅（但**無語義階用它**） | 見 §4 |
| `--t-3xl` | 24 | `-600`＝24 ✅（`display-medium`） | |

⇒ **字級階不必換值**，但語義配對要改（§4）。

### 2.7 字距（全缺）

我方**沒有任何 letter-spacing token**。本尊 display 級是**負字距**（111 §8）：
`display-small`／`display-medium`＝`-.00833em`｜`display-large`＝`-.0166em`。

🆕 需新增 `--ls-display-sm/-md/-lg` 三個（或等效命名）。
**不加的話大標題會比本尊鬆**——`94` §4 已在頁標題 `h1` 實測到 `-0.14994px`。

## 3. 需新增（本尊有、我方沒有）

| 項 | 本尊值 | 為什麼要 |
|---|---|---|
| **`highlight` 語義族** | surface `#f0f2ff`／hover `#eaedff`／active `#e2e7ff`；border／icon `#005bd3` | 本尊是 **7 族**不是 5 族（111 §14.3） |
| **`ai` 語義族** | surface `#f8f7ff`；icon `#8051ff`；border `#e4deff` | 同上（我方有 `--ai`／`--ai-bg`／`--ai-border` 三個散裝，未成族） |
| **`--sp-500:20px`／`--sp-800:32px`** | 111 §1 | 既有量測文件已在引用 |
| **`--r-150:6px`** | 111 §2 | `94` §4 實測有用 |
| **字距三階** | 111 §8 | 見 §2.7 |
| **inset 按鈕陰影** | `--p-shadow-button`／`-button-primary` 各 3 層 | 本尊 2026 的「可舔按鈕」；我方 `73` §5.3 原本裁定「不複製」，**D54 後應改為採用** |
| **`bg-fill-transparent-*` 階** | `#00000005`／`0d`／`14`／`0f`／`1c` | 透明底 icon 鈕的 hover／active 用它，我方目前用不透明色近似 |
| **兩階分隔線色** | 表頭↔首列 `#e3e3e3`；資料列間 `#ebebeb` | `81` §8.4 實測是**兩個不同色**，我方只有一個 |

## 4. 需改語義（值對但配對錯）

| 項 | 我方現況 | 本尊 | 處置 |
|---|---|---|---|
| **`--col-main`／`--col-aside`** | ~~固定 633／317~~ | ~~本尊 `max-width: none`，流體寬~~ 🔴 **那是量錯層**——上限在 `s-grid` 的 track 上：主欄 `minmax(480,638)`、次欄 `minmax(240,312)`、單欄 `minmax(auto,966)`。全文＝`111` §16.1 的 2026-08-28 更正 | ✅ **已定案並實作**（D55）：638／312 ＋ 新增 `--col-main-min:480`／`--col-aside-min:240`／`--col-content:966`／`--col-narrow:630`。🔴 **總寬不變**（633+16+317 = 966 = 638+16+312），只是內部各挪 5px |
| `--t-lg:16px`／`--t-2xl:20px` | 有階 | 本尊有 token 但**無語義階使用** | 保留為備用，或標明「本尊未用」 |
| `--lh-lg`／`--lh-2xl` | 配 16／20px | 本尊無對應語義階 | 同上 |
| `--fw-*:500` 四項 | 500 | ~~token 值域無 500，但 computed 有~~ **已撤回**（那是量測污染） | ✅ **已解**：450／450／600／550，見 §2.2 |
| `--sh-*` 六條浮層陰影 | 自訂 rgba | 本尊 `-200`/`-300`/`-400`/`-500` 各有具名對應 | 逐條換成本尊配方 |

## 5. 不可換（未取得，維持現值並登記）

| 項 | 缺什麼 | 出處 |
|---|---|---|
| `--surface-inverse` | ~~本尊對應值未取得~~ 🔴 **那個對應關係不存在**——本尊頂欄／深色浮層是靠**整個子樹套暗色 theme scope**（用該 scope 的 `--p-color-bg`），不是靠一顆「inverse 色」token。消融實驗見 `111` §14.7 的 2026-08-28 更正 | 110 §7.2；111 §14.7 |
| 語義色的 hover／active **全三態** | 只取到部分（`info` 的 hover/active fill 未取得） | 111 §19 |
| primary 按鈕 **hover／active** | 取樣時全程 disabled | 111 §19 |
| **1280 桌機**的欄寬與骨架幾何 | 量測機螢幕 1024×768 | 111 §19 |
| `--focus-ring-w:4px`／`--focus-gap-w:2px` | 本尊是 `outline 2px + offset 1px`，**且不是全域一致**（設定區導覽用瀏覽器預設） | `81` §8.4 |

## 6. 執行順序與風險

1. **先做無爭議的**：§1 已命中（0 改動）＋ §2.4 圓角 ＋ §2.3 行高 ＋ §2.6 字級（0 改動）。
2. **再做中性色**（§2.1，16 項）——這一批視覺變化最大，**改完必須逐畫面截圖比對**。
3. **語義色分兩步**：先補 `highlight`／`ai` 兩族（新增，不影響現有），
   再換既有五族的值（**要先解決「三族是淺色 fill 配深字」的配色模型差異**，111 §14.5）。
4. **`--fw-*:500` 與 `--col-*` 兩項先查證再動**，它們會牽動全站排版。
5. **每一步都要跑** `scripts/check-tokens-sync.rb`（設計 token 單一來源閘門）。

🔴 **不得為了「換完」而用推導公式補未取得的值**（鐵律 19.3）。

🔴 **`docs/design/23` §1 與 `app/assets/tokens.css` 必須同一提交同步**
（鐵律 20.2②：生產者改了，消費者與終態要一起改），
且 `47`／`64`／`73` §5.3 中相關的「刻意偏離」條目要同批加註。
