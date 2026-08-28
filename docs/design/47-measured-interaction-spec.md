# 47 — 實站量測交互規格（幾何・動效・狀態）→ 映射 CHILL LOVE tokens

> 來源：於使用者本人的 Shopify Plus 後台（`chill-love-u5q5mnzq`）以 `getComputedStyle` 讀取**已渲染元素的實際套用值**。
>
> **法務邊界（CLAUDE.md 鐵律 9）**：本文件記錄的是**量測到的數值事實與行為契約**（間距階、控件高度、轉場時長與緩動、狀態轉移），等同於拿尺量畫面。**不複製、不轉載 Shopify／Polaris 的 CSS 原始碼、變數表、class 名或選擇器**。所有數值一律重新映射到 `docs/design/23-interaction-css-spec.md` 的自有 token 命名。實作時寫我們自己的 CSS。

---

## 0. 量測條件與一個重要更正

| 項目 | 值 |
|---|---|
| CSS 視口（第一輪） | `innerWidth = 682.67px`、`innerHeight = 404.67px` |
| **根字級** | **`html` 的 computed `font-size` = 24px（非 16px）** |
| devicePixelRatio | 1 |
| 主內容區 | `main` 實測 `w=682.67, left=0, top=56` → **頂欄高 56px，主區佔滿全寬** |

### ⚠⚠ 量測基準更正（第二輪驗證後改寫）

第一輪誤判為「瀏覽器縮放 150%」。第二輪以探針元素驗證，**確認不是縮放**：

```
注入 <div style="width:100px; height:1rem; border-top:1px solid; font-size:1rem">
→ width          computed = 100px   （px 值未被放大）
→ border-top     computed = 1px     （px 值未被放大）
→ height (1rem)  computed = 24px    （rem 值被放大 1.5×）
→ devicePixelRatio = 1，visualViewport.scale = 1
```

**真正原因：Chrome 的「預設字型大小」被設為 24px（特大），而非 16px。** 頁面縮放會等比縮放所有單位；字型大小設定**只放大 rem/em**，px 原封不動。

**這對量測的影響是致命的**：Shopify 後台的**間距、字級、圓角、斷點以 rem 撰寫，邊框與髮絲線以 px 撰寫**。兩者混在同一份 computed 輸出裡：

| 屬性類別 | 撰寫單位 | computed 是否被放大 | 反推設計真值 |
|---|---|---|---|
| font-size、line-height、間距、圓角、控件高度 | rem | **是（×1.5）** | ÷ 1.5 |
| border-width、hairline、1px 分隔線 | px | **否** | **不可除** |

→ 第一輪對**所有**數值一律除以 1.5，因此**邊框值全錯**（量出 `0.67px` 這種不存在的值，真值是 `1px`）。
→ 本文件 §1–§4 的**間距／字級／圓角／控件高度為 rem 類，除法正確，結論有效**；凡涉及 `border-width` 的數字**一律作廢**，待重測。

**斷點也受影響**：若 Shopify 的 media query 以 rem 撰寫，根字級 24px 會讓 `48rem` 斷點在 **1152px** 而非 768px 觸發。這解釋了為何 682px 視口下拿到的是極窄版佈局——當時遠低於任何斷點。**44 號「~683px 窄版」的標註仍成立**（視口確實是 683px），但「對應 Shopify 哪一個具名斷點」不能從本輪推論。

**已請使用者將 Chrome 預設字型大小改回「中（16px）」**。改回後 computed 值即等於設計真值，無須任何換算，§7 的桌機補測與邊框重測一併在該條件下進行。

### ⚠ 對 44 號實測記錄的更正

44 號四輪拆解的所有截圖，**實際是在 ~683px 的有效視口下拍的，屬於 Shopify 的「窄版／平板」佈局，不是桌機佈局**。這解釋了先前記錄中幾個一直覺得奇怪的現象：

| 44 號原記載 | 正確解讀 |
|---|---|
| 設定頁全部單欄 | 683px 下的窄版；桌機為雙欄（左側設定導航 + 右內容） |
| 主導航收在漢堡鈕後 | 683px < 桌機斷點，側欄收合；桌機有常駐側欄 |
| 結帳編輯器頁面選擇器是 **bottom sheet** | 窄版形態；桌機應為下拉選單 |
| 結帳編輯器只有左樹＋預覽兩欄 | 窄版；桌機為**三欄**（樹／預覽／屬性檢查器）——這也是先前點 block 沒出現檢查器的原因 |
| 商品/文章編輯器主欄 ~615px、側欄 ~310px | 這是 683px 下的比例，非桌機實際值 |

**桌機側欄寬度**可從佈局變數取得為 `15rem = 240px`（此為版面尺寸事實，非樣式代碼）。

**行動**：44 號需加註「本輪為 ~683px 窄版佈局」，且**桌機（≥1280px）三欄佈局需另行補測**。已列為 §7 待辦。

---

## 1. 間距階（normalized，已除以 1.5）

實測全頁 `gap` / `padding` 出現頻率統計後的去重階梯：

| token（我方命名） | 值 | 實測出處 |
|---|---|---|
| `--sp-050` | 2px | 表頭列內距、小 pill 上下內距 |
| `--sp-100` | 4px | icon 按鈕內距、密集列 gap |
| `--sp-150` | 6px | 欄位標題按鈕內距、次級 gap |
| `--sp-200` | 8px | **最高頻 gap**（x34），控件間標準間距 |
| `--sp-300` | 12px | 卡片內距、按鈕水平內距 |
| `--sp-400` | 16px | 卡片間距、區段內距 |
| `--sp-600` | 24px | 區段之間 |

→ **結論：4px 基準的階梯，實際只用 2/4/6/8/12/16/24 七階。** 我們 23 號原本有 10 階，**砍到七階**即可覆蓋全部真實用例，多的是噪音。

## 2. 圓角階

| token | 值 | 用途（實測） |
|---|---|---|
| `--r-100` | 4px | 最小元素（極少用，x1） |
| `--r-200` | 8px | **控件圓角**：按鈕、輸入框、chip、tab（x9） |
| `--r-300` | 12px | **卡片圓角**（x11，最高頻） |
| `--r-400` | 18px | 大容器／藥丸（x11） |

另有**單邊圓角**的成對用法：`12px 12px 0 0` 與 `0 0 12px 12px`（x2 各）→ **堆疊卡片群組**：群組內第一張只圓上緣、最後一張只圓下緣、中間全直角。這是我們原型缺的細節。

## 3. 字級階

> 🔴 **2026-08-28 引用守衛（G12b）：本節的 `font-weight` 值待複驗，未複驗前不得引用。**
> 本檔量測時，本機 Chrome 的擴充功能正在注入 `font-weight: 500 !important`
> （**雙向**改寫：450 拉高、550 壓低；全文＝`docs/design/111` §20）。
> 🔴 **本尊沒有 500 這一階**（`--p-font-weight-*` ＝ 450/550/600/650，乾淨直方圖 500 出現 **0** 次）⇒ **文件裡出現「字重 500」本身就是污染指紋**。
> ⚠️ G12 的射程只點名 §D，而 §D 實際上一個字重值都沒有 ⇒ **本節被漏掉了**。
> font-size／line-height／色／間距／圓角／陰影**不受影響**，那些值仍可引用。


| token | size/line-height/weight | 實測用途 |
|---|---|---|
| `--t-xs` | 12 / 16 / 500 | **表格內容、欄位標題**（最高頻的資料字級） |
| `--t-sm` | 13 / 20 / 500 | **UI 預設字級**（按鈕、tab、輸入框、選單） |
| `--t-md` | 14 / 20 / 500 | 次要標題 |
| `--t-lg` | 16 / 20 / 450 | 卡片標題（**注意 weight 降為 450**） |
| `--t-xl` | 18 / 24 / 500 | 區段標題 |
| `--t-2xl` | 27→18 / 24 / 500 | 頁面標題（窄版） |

**兩個反直覺的實測事實**：
1. **UI 預設是 13px，不是 14px**。我們 23 號寫 14px，**要改**。
2. **大標題的字重反而較輕（450）**，小字級用 500。這是刻意的視覺補償——大字級不需要靠字重撐份量。我們原型一律用 600/700 做標題，**過重了**。

字距一律 `normal`（未使用 letter-spacing 調整）。

## 4. 控件高度階

> 🔴 **2026-08-28 引用守衛（G12b）：本節的 `font-weight` 值待複驗，未複驗前不得引用。**
> 本檔量測時，本機 Chrome 的擴充功能正在注入 `font-weight: 500 !important`
> （**雙向**改寫：450 拉高、550 壓低；全文＝`docs/design/111` §20）。
> 🔴 **本尊沒有 500 這一階**（`--p-font-weight-*` ＝ 450/550/600/650，乾淨直方圖 500 出現 **0** 次）⇒ **文件裡出現「字重 500」本身就是污染指紋**。
> ⚠️ G12 的射程只點名 §D，而 §D 實際上一個字重值都沒有 ⇒ **本節被漏掉了**。
> font-size／line-height／色／間距／圓角／陰影**不受影響**，那些值仍可引用。


| 控件 | 高度 | 內距 | 圓角 | 備註 |
|---|---|---|---|---|
| icon 按鈕（次級） | **28 × 28** | 4px | 8px | bg `#E3E3E3`、fg `#303030` |
| 欄位標題按鈕（可排序 th） | **28** | 6px / 6px | 0 | 無背景，12/16/500 |
| 檢視 tab（`全部`） | **24** | 0 / 2px | 8px | 選中態才有背景 |
| 搜尋欄（列表內） | **28** | 4px / 28px | — | 右內距 28px 留給清除鈕 |
| 表格資料列 | **32** | — | 0 | 白底 |
| checkbox | **16 × 16** | 0 | 0 | 原生 input |

→ **控件高度只有三階：24 / 28 / 32**（窄版）。加上 36（頂欄）共四階。
→ **checkbox 只有 16px**，遠小於 44px 觸控標準 → Shopify 靠**列級點擊區**補償（整列 32px 高可點）。我們 34 號的 `::before{inset:-Npx}` 擴大命中區做法方向正確，**且要用在 checkbox 上**。

## 5. 動效系統（本次量測最高價值）

實測全頁**實際生效**的 transition 宣告（去重後按使用次數排序）：

| 次數 | 屬性 | 時長 | 緩動 | 語意 |
|---|---|---|---|---|
| ×18 | `opacity` | **0.1s** | `cubic-bezier(.42,0,.58,1)` | 淡入淡出（ease-in-out） |
| ×16 | `opacity` | **0.15s** | `cubic-bezier(.25,.1,.25,1)` | 淡入淡出（ease） |
| ×15 | `color` | **0.1s** | `cubic-bezier(.25,.1,.25,1)` | 文字色變化 |
| ×14 | `background-color` | **0.15s** | `ease` | **hover 底色**（最常見的互動回饋） |
| ×8 | `border-color, border-width, box-shadow` | **0.1s** ×3 | `cubic-bezier(.19,.91,.38,1)` | **focus / 邊框態** |
| ×8 | `max-height` | **0.1s** | `cubic-bezier(.19,.91,.38,1)` | **摺疊展開（accordion）** |
| ×2 | `opacity, scale` | **0.2s** | `cubic-bezier(.19,.91,.38,1)` | **popover / 選單進場** |
| ×2 | `max-width` | **0.3s** | `cubic-bezier(.42,0,.58,1)` | 側欄收合 |
| ×2 | `transform` | **0.25s** | `cubic-bezier(.25,.1,.25,1)` | **抽屜滑入** |

### 映射成我方 motion tokens（4 時長 × 3 曲線）

```
--dur-fast:   100ms   /* 色彩、邊框、focus、accordion */
--dur-base:   150ms   /* 底色 hover、淡入淡出 */
--dur-slow:   200ms   /* popover 進場（opacity + scale） */
--dur-slower: 250ms   /* 抽屜 transform */
--dur-slowest:300ms   /* 側欄寬度 */

--ease-standard:  cubic-bezier(.25,.1,.25,1);   /* 預設，等同 ease */
--ease-in-out:    cubic-bezier(.42,0,.58,1);    /* 對稱淡入淡出 */
--ease-decelerate:cubic-bezier(.19,.91,.38,1);  /* 進場/展開，快起慢收 */
```

**七條可直接抄進實作的規則**：

| # | 規則 |
|---|---|
| M1 | hover 底色一律 `background-color 150ms ease` |
| M2 | 文字色變化一律 `color 100ms ease`（比底色快，避免文字先於底色定格） |
| M3 | focus 環一律 `border-color, border-width, box-shadow 100ms decelerate` **三屬性同時** |
| M4 | accordion 用 `max-height 100ms decelerate`（不是 height，避免 reflow） |
| M5 | popover/選單進場 `opacity + scale 200ms decelerate`（**scale 不是 transform**，避免與位移衝突） |
| M6 | 抽屜 `transform 250ms standard` |
| M7 | 側欄寬度 `max-width 300ms ease-in-out`（**不是 width**，避免內容重排） |

→ 我們原型目前多處用 `all .2s`，**要逐一改成上表的具名屬性**。`transition: all` 在實站也大量出現（x284），但那是繼承的無效宣告（`transition-duration: 0s`），實際生效的只有上表九條。

### 關鍵幀動畫

實站定義了 **168 個 keyframes**。命名可見的語意類別：checkbox 勾選路徑動畫、麵包屑遮罩、**Modal 抖動（shake）用於驗證失敗**、Modal footer 進場（fadeEnterLeft / enter-up）、IndexTable 排序條。

→ **`shake` 是我們完全沒有的**：表單提交驗證失敗時，Modal 整體（含 footer）做水平抖動。這是很強的錯誤回饋，列入 23 號。

## 6. 顏色（僅記錄量到的中性階，不取用其品牌色）

| 用途 | 實測值 |
|---|---|
| 頁面底色 | `#F1F1F1` |
| 卡片／列底色 | `#FFFFFF` |
| 主要文字 | `#303030` |
| 次要文字 | `#616161` |
| 次級按鈕底 | `#E3E3E3` |
| 圖示灰 | `#4A4A4A` |
| 頂欄文字（深色底上） | `#DCDCDC` |

→ **只採用「中性階的層級關係」**（頁底 < 卡片、主文字 vs 次文字兩級、次級按鈕比頁底深一階），**色值改用 CHILL LOVE 自有調色**。層級關係是資訊設計事實，色值是品牌資產。

> 🔴 **2026-08-28 起本段的處置已被 `docs/DECISIONS.md` **D54** 推翻**（使用者裁定「整體 UI 必須和 Shopify 完全 1:1，完全跟隨他的 CSS」）。
> **原文保留備查**（文檔分層：不抹除歷史）。現行處置＝採用量測色值，本尊完整 token 值表見 `docs/design/111`，逐項差異見 `docs/design/110` §7。


## 6.5 桌機佈局首測（視口 3440px，根字級仍為 24px — 數值待重測，結構結論有效）

使用者把視窗放大到超寬（`innerWidth = 3440`）後，桌機佈局首次現形。**以下結構結論不受根字級影響，可直接採用**：

| 項目 | 觀察 |
|---|---|
| 常駐左側導航 | **240px 固定寬**（與版面變數 `15rem` 一致）；頂欄高 56px；`main` 從 x=0 起算、導航疊在其上 |
| 導航結構 | 一級項（首頁／訂單／產品／顧客／成長／折扣／內容／市場／設定）＋**二級縮排子項**（訂單下：草稿／運送標籤／未完成結帳作業） |
| 導航計數徽章 | 一級項右側顯示數字（訂單 `4`），非圓形 badge 而是右對齊數字 |
| 導航態 | idle 透明底；**active 為淺灰底 + 8px 圓角**（子項實測 218×28、r8） |
| 頂欄 | 左：Shopify 標誌 ＋ **版本 chip「春季 '26」**；中：全寬搜尋（含 `CTRL` `K` 兩顆鍵帽）；右：三顆圖示 ＋ 商店名 ＋ 環境 chip `dev` |
| 頁首動作區 | 由右至左 **`建立訂單`(primary) → `更多動作 ⌄`(split) → `匯出`(tertiary)**——**主要動作在最右**，與窄版一致 |
| 訂單表格欄位 | 桌機顯示 **10 欄**：訂單／日期／顧客／出貨期限／管道／總計／付款狀態／出貨狀態／品項／配送狀態（窄版只剩 6 欄）→ **欄位優先級表**：前 6 欄為核心，後 4 欄為 ≥桌機才出現 |
| 表格橫向捲動 | 即使 3440px 寬仍有底部水平捲軸 → 表格有 **min-width**，不隨視口無限攤平 |

**次級按鈕（split）的完整配方**（唯一在本輪成功解析到繪製盒的按鈕）：

```
高 28（rem 類，真值待確認）／內距 6 上下 · 12 左右／圓角 8
字級 12/16，字重 550   ← 注意是 550，不是 500 或 600
背景 #FFFFFF
陰影兩層：
  ① inset  0 -1px 0 0  #B5B5B5      ← 底緣 1px 內陰影（px 類，真值 1px）
  ② drop   rgba(0,0,0,.1) …          ← 外投影
```

→ **這個「白底 + 底緣內陰影 + 外投影」是次級按鈕的立體感來源**，我們原型目前只有純邊框，缺這兩層。字重 550 也是我們沒有的階（介於 500 與 600）。

> 🔴 **2026-08-28 更正：上面這組配方與直接量測衝突，且極可能是「讀到 token、當成繪製盒」。**
> 當日對 `s-internal-button[variant=secondary]` 的**繪製盒**直接量測（三個獨立樣本：
> `/orders` 的 Export、`/orders/<id>` 的 Refund 與 Edit）一致得到：
> **`background: #e3e3e3`（不是白）、`box-shadow: none`（完全沒有陰影）、`border: 0`**；
> hover 變 `#d4d4d4`，仍然無陰影。
>
> 🔴 **兩層陰影的來源已定位**：`--p-shadow-button` 這個 token 的值是
> `0 -1px 0 0 #b5b5b5 inset` / `0 0 0 1px #0000001a inset` / `0 .5px 0 1.5px #fff inset`
> （`111` §9）——**①逐項吻合，②的 `rgba(0,0,0,.1)` 就是 `#0000001a`**，
> 只是本節把它記成 drop 而 token 裡是 inset。
> ⇒ 當時讀到的是 **token 表的值**，而該 token **並未套用在 `variant=secondary` 的繪製盒上**。
>
> ⚠️ **本節與同檔 §D 的表也互相矛盾**：§D 記 split 與 tertiary 都是「淺灰實心」，
> 與本節的「白底」不一致。直接量測支持 §D 那一側。
> 逐態值＝`docs/design/113` §1.2。**原文保留備查。**

---

# 第三輪：根字級 16px 桌機正式量測（**本節數值為設計真值，無須換算**）

使用者已將 Chrome 預設字型改回 16px。`getComputedStyle` 回傳值 = 設計真值。

**量測條件**：`root=16px`、`innerWidth=2294`、`innerHeight=743`、`dpr=1.5`、截圖寬 1568（座標換算 K = 2294/1568 = 1.463）。

## A. 一道硬牆：封閉 Shadow DOM

Shopify 已改用 `s-` 前綴的 web components（`<s-internal-button>`、`<s-internal-badge>`、`<s-internal-page>`…）。這些**宿主元素的 `getBoundingClientRect()` 是 0×0，且 `shadowRoot` 為 `null`（closed mode）**。

→ **按鈕與徽章的內部樣式無法由 JS 讀取**，`elementFromPoint` 一路穿到外層容器。
→ 這類元件改用**高倍率截圖目視判讀**（`computer.zoom`）。以下 §D 即為目視結果。
→ 可由 JS 讀取的是：原生 `<button>`（導航、欄位標題、檢視 tab）、佈局 `<div>`、表格儲存格。

> 🔴🔴 **2026-08-28 更正：本節的前提是錯的，`shadowRoot` 是 open 不是 closed。**
> 當日實測 `s-internal-button` / `s-internal-badge` / `s-internal-text-field` /
> `s-internal-tooltip` / `s-banner` 的 `shadowRoot` **全部可直接取得並 `getComputedStyle`**
> （`el.shadowRoot.querySelector(...)`）。`docs/design/113` 與 `docs/design/111` 的全部數值
> 即由此法取得，`getBoundingClientRect()` 是 0×0 的只有**宿主**元素，繪製盒在 shadow 內。
>
> ⇒ **本節「無法由 JS 讀取」的結論作廢**，隨之作廢的還有「因此改用高倍率截圖目視判讀」
> 這個處置——**§D 全部數值都是在這個錯誤前提下目視得到的**，逐項待直接量測複核，
> 其中「次級按鈕配方」已證實有誤（見第三輪 §6.5 的更正註）。
> **原文保留備查**（文檔分層：不抹除歷史）。

## B. 桌機佈局真值

> 🔴 **2026-08-28 引用守衛（G12b）：本節的 `font-weight` 值待複驗，未複驗前不得引用。**
> 本檔量測時，本機 Chrome 的擴充功能正在注入 `font-weight: 500 !important`
> （**雙向**改寫：450 拉高、550 壓低；全文＝`docs/design/111` §20）。
> 🔴 **本尊沒有 500 這一階**（`--p-font-weight-*` ＝ 450/550/600/650，乾淨直方圖 500 出現 **0** 次）⇒ **文件裡出現「字重 500」本身就是污染指紋**。
> ⚠️ G12 的射程只點名 §D，而 §D 實際上一個字重值都沒有 ⇒ **本節被漏掉了**。
> font-size／line-height／色／間距／圓角／陰影**不受影響**，那些值仍可引用。


| 項目 | 真值 |
|---|---|
| 頂欄高 | **56px** |
| 頂欄搜尋框 | **640 × 36**，圓角 **12px**（含 `CTRL` `K` 鍵帽） |
| 頂欄圖示鈕 | **36 × 36**，圓角 **12px** |
| 左側導航寬 | **240px**（常駐） |
| 導航一級項 | 高 **28**，圓角 **8** |
| 導航二級（子）項 | **218 × 28**，圓角 **8**（左側縮排 22px） |
| 導航分組標題鈕 | **76 × 24**，圓角 **8** |
| 表格資料列高 | **32px** |
| 儲存格內距 | **6px 6px**（列高 32 = 20 內容 + 6×2） |
| 儲存格字級 | **12 / 16 / 500**，色 `#303030` |
| 欄位標題鈕 | 高 **28**，內距 **6/6**，圓角 **0**，字 **12/16/500**，色 `#616161` |
| 檢視 tab（`全部`） | **60 × 24**，圓角 **8**，內距 **0/2**，字 **13/20/500** |
| 徽章（badge）高 | **20px**（內容盒 66×20） |
| **列分隔線** | **0.667px** `#E3E3E3` ← 見 §C |

**桌機導航完整結構**（窄版看不到，全新發現）：
`首頁｜訂單(計數 4)〔草稿／運送標籤／未完成結帳作業〕｜產品｜顧客｜成長｜折扣｜內容｜市場｜財務｜分析` → 分組 `銷售管道`〔線上商店／**代理式**／銷售點〕→ `應用程式`〔Fecify〕→ `Sidekick 對話` → `設定`

→ **`財務` 與 `分析` 在桌機是一級項**（窄版被摺疊）；銷售管道群組出現 **`代理式`（Agentic）** ——這是 2026 版新增的 AI 代理購物通路，我們 40 號母清單完全沒有。

## C. 髮絲線 = 1 個「裝置」像素，不是 1 CSS px

列分隔線 computed 為 **`0.666667px`**，而 `dpr = 1.5`：

```
0.666667 CSS px × 1.5 dpr = 1.0 device px（剛好一條實體像素，不會被抗鋸齒糊掉）
```

→ Shopify 的髮絲線是**依 dpr 換算成恰好 1 個實體像素**，不是寫死 1px。dpr=2 時應為 0.5px、dpr=1 時為 1px。
→ 我們的實作方式（自寫，不抄）：

```css
.cl-hairline { border-bottom: 1px solid var(--cl-border); }
@media (-webkit-min-device-pixel-ratio: 1.5), (min-resolution: 1.5dppx) {
  .cl-hairline { border-bottom-width: .667px; }
}
@media (-webkit-min-device-pixel-ratio: 2), (min-resolution: 2dppx) {
  .cl-hairline { border-bottom-width: .5px; }
}
```
→ 這是我們三份原型**全部缺**的細節：目前一律 1px，在 Retina 上會比實站粗一倍，是「看起來就是不對」的主因之一。

## D. 按鈕與徽章（高倍率目視判讀）

> 🔴 **2026-08-28 第二道守衛（第一道見 §A 的更正註）：本節的 `font-weight` 值一律待複驗。**
> 本機的 Chrome 有一個擴充功能注入 `font-weight: 500 !important`，會把 light DOM 的字重
> 雙向改寫（全文＝`docs/design/111` §20）。本節是**目視判讀**、未載明量測環境，
> 無法判斷當時是否已受影響。
> ✅ **2026-08-28 已完成乾淨重量 ⇒ 見本檔 §D.1**（17 列：更正 9／一致 8）。
> 🔴 **更正不只字重**：`Export` 的 variant 實測是 **secondary** 不是 tertiary、
> `More actions` 也是 **secondary** 不是 split、標籤的 radius 是 **8px** 不是全圓藥丸形。
> **引用本節任何數值前先對照 §D.1。**

### 頁首動作組（由左至右：匯出 → 更多動作 ⌄ → 建立訂單）

| 變體 | 填色 | 文字 | 圓角 | 備註 |
|---|---|---|---|---|
| **tertiary**（匯出） | 淺灰實心 | 深色 | ~8px | 無邊框 |
| **split**（更多動作 ⌄） | 淺灰實心 | 深色 | ~8px | 右側 chevron，與本體同一顆（非分離式） |
| **primary**（建立訂單） | **深色（近黑）實心** | **白色** | ~8px | 三者**等高、等圓角**，只靠填色分層級 |

→ **三個層級靠「填色深淺」區分，不靠邊框或尺寸**。我們原型目前 secondary 用白底＋邊框，**方向就不對**。

### 徽章的狀態圖示系統（本輪最重要的發現）

| 徽章 | 底色 | 前置圖示 | 語意 |
|---|---|---|---|
| `已付款` | 淺灰 | **● 實心圓點** | 完成 / success |
| `部分已履行` | **橘 / 蜜桃色** | **⊘ 斜線圓** | 部分完成 / warning |
| `未出貨` | **黃色** | **○ 空心圓** | 未開始 / attention |
| `已新增追蹤資訊` | 淺灰 | ⊘ 斜線圓 | 中性資訊 |

→ **每個徽章都帶一個前置狀態圖示，且圖示形狀本身就編碼了狀態**：
> **實心 ● = 完成｜空心 ○ = 未開始｜斜線 ⊘ = 部分／受阻**

→ 這是**不以顏色單獨傳達狀態**（WCAG 1.4.1 Use of Color）的標準做法。色盲使用者靠圖示形狀即可分辨。
→ **我們三份原型的 badge 全部只有色塊＋文字，沒有狀態圖示** —— 這既是保真度缺口，也是無障礙缺陷。列為必修。

### 標籤（tag）vs 徽章（badge）

視覺上是**兩種不同元件**，不可混用：

| | 徽章 badge | 標籤 tag |
|---|---|---|
| 圓角 | 約 8px（圓角矩形） | **全圓（藥丸形）** |
| 圖示 | **有**狀態圖示 | 無 |
| 底色 | 依語意（灰/黃/橘…） | 一律淺灰 |
| 溢出 | 不折疊 | **`+ 1` 收合計數**（實測第三列 `fecify`、`fecify-cancel-blocked`、`fecify-refund-review` `+ 1`） |

## E. 已確認的狀態值（補 48 號九態表的缺口）

> 🔴 **2026-08-28 引用守衛（G12b）：本節的 `font-weight` 值待複驗，未複驗前不得引用。**
> 本檔量測時，本機 Chrome 的擴充功能正在注入 `font-weight: 500 !important`
> （**雙向**改寫：450 拉高、550 壓低；全文＝`docs/design/111` §20）。
> 🔴 **本尊沒有 500 這一階**（`--p-font-weight-*` ＝ 450/550/600/650，乾淨直方圖 500 出現 **0** 次）⇒ **文件裡出現「字重 500」本身就是污染指紋**。
> ⚠️ G12 的射程只點名 §D，而 §D 實際上一個字重值都沒有 ⇒ **本節被漏掉了**。
> font-size／line-height／色／間距／圓角／陰影**不受影響**，那些值仍可引用。


| 狀態 | 實測值 | 出處 |
|---|---|---|
| **disabled（文字）** | `#B5B5B5` 於透明底 | 停用的「儲存」鈕：`48×28, pad 4/6, r8, f12/16/500, fg rgb(181,181,181)` |
| **idle（次要文字）** | `#616161` | 欄位標題鈕 |
| **idle（主要文字）** | `#303030` | 儲存格內容 |
| **邊框／分隔線** | `#E3E3E3` @ 0.667px | 列分隔線 |

→ **disabled 的做法是「只降文字對比、不改底色」**（底維持透明），而非我們原型現在的「降整體 opacity」。降 opacity 會讓 disabled 元素在深色底上發灰、在淺色底上發白，不穩定；只換文字色則到處一致。**要改**。

## F. 斷點階梯（從樣式表 media query 直接抽出，**權威值**）

掃描全部 stylesheet 的 `@media` 條件並按出現次數排序：

| 出現次數 | 宣告 | = px（root 16） | 判讀 |
|---:|---|---:|---|
| **421** | `min-width: 48em` | **768** | **主斷點**，用量遠超其他 |
| 110 | `min-width: 30.625em` | **490** | 小手機 → 大手機 |
| 78 | `max-width: 47.9975em` | 767.96 | 768 的 max 配對 |
| 51 | `max-width: 30.6225em` | 489.96 | 490 的 max 配對 |
| 38 | `max-width: 41.685em` | 666.96 | 667 的 max 配對 |
| 35 | `min-width: 65em` | **1040** | 桌機 |
| 32 | `min-width: 90em` | **1440** | 寬桌機 |
| 25 | `min-width: 41.6875em` | **667** | 平板直式 |
| 13 | `min-width: 75em` | **1200** | 中桌機 |
| 3 | `min-width: 22.5em` | **360** | 最小手機 |
| 3 | `min-width: 160em` | **2560** | 超寬 |

### 三個結論

1. **斷點階梯是 8 階**：`360 / 490 / 667 / 768 / 1040 / 1200 / 1440 / 2560`
   我們 34 號目前只有 4 階（1279 / 1023 / 767 / 429），**與實站對不上**：
   | 我方 | 實站最接近 | 差異 |
   |---|---|---|
   | 429 | **490** | 差 61px，我們的手機大斷點太早 |
   | 767 | **768**（max 767.96） | ✅ 幾乎一致 |
   | 1023 | **1040** | 差 17px |
   | 1279 | **1200** 或 **1440** | 我們少了一階，實站在 1200 與 1440 各切一次 |

2. **斷點以 `em` 撰寫，不是 `px`** —— 這是**無障礙設計決定**：使用者調大瀏覽器預設字型時，版面會**提早**切換到寬鬆佈局（因為 1em 變大，達到 48em 所需的 px 變多）。這正是本次量測初期「1024px 視窗卻拿到極窄版」的根本原因（root=24px 時 48em = 1152px）。
   → **我們三份原型全部用 px 斷點，應改為 em。** 這是一行改動換一整類無障礙情境，CP 值極高。

3. **主斷點只有一個（768）**，其餘都是局部微調。設計時應以 768 為「佈局換手」的唯一分界，1040/1200/1440 只做欄數與密度微調，不重排結構。

## G. z-index 階梯（實測在用的值）

```
1 ×16      基礎堆疊（卡片內元素）
100 ×29    sticky / 常駐導航 / 表頭
400 ×4     ？（中層，樣本少）
510 ×2  ┐
517 ×2  │  浮層帶（modal / popover / toast / drawer）
518 ×12 │  → 集中在 510–520 這 11 個數字內
519 ×18 │
520 ×12 ┘
```

→ **設計原則：浮層全部擠在單一窄帶（510–520）內，靠 DOM 順序而非數字大小決勝。** 這比我們原型現在散落的 `z-index: 9999` 健康得多。
→ 我方採用：`--z-base:1 / --z-sticky:100 / --z-overlay-base:510`，浮層以 `510 + n` 命名，**上限 520**，超過即代表設計有問題。
→ 仍未解：`popover 是否高於 modal`（518/519/520 三層的具體歸屬）——需開啟 modal 後再測。

## H2. 三項待解全部收斂（第四輪）

### H2-1 語意色系統 —— **結構已解**（只取結構與關係，不引用其色值）

`:root` 共 539 個自訂屬性，其中語意色 **75 個**，結構為 **5 族 × 5 層 × 3 態**：

| 維度 | 內容 |
|---|---|
| **族（5）** | `info` / `success` / `caution` / `warning` / `critical` |
| **層（5）** | `bg-surface`（淺色底）／`bg-fill`（實色底）／`border`／`icon`／`text` |
| **態（3）** | base / hover / active（另有 `secondary`、`selected` 供部分層使用） |
| **例外** | **只有 `critical` 多出 `button-bg-fill` 與 `button-gradient-bg-fill`** → 破壞性按鈕有專屬填色，其他族沒有 |

**推導規則（我方據此生成自有色階，不套用其色值）**——量到的相對明度關係：

| 族 | surface base L% | hover Δ | active Δ |
|---|---:|---:|---:|
| info | 95.2 | −2.0 | −6.6 |
| success | 94.3 | −3.1 | −6.6 |
| caution | 97.0 | −1.9 | −4.3 |
| warning | 95.3 | −2.1 | −4.5 |

→ **規則：`surface` 底色一律落在 L ≈ 94–97%（極淺染色），hover 降 2–3，active 降 4–7。**
→ 我方做法：取 CHILL LOVE 自有 5 個語意色相，套上這條明度公式生成 `surface / fill / border / icon / text` 五層 × 三態，共 **75 個 token**。色相是我們的，階梯關係來自量測。

> 🔴 **2026-08-28 起本段的處置已被 `docs/DECISIONS.md` **D54** 推翻**（使用者裁定「整體 UI 必須和 Shopify 完全 1:1，完全跟隨他的 CSS」）。
> **原文保留備查**（文檔分層：不抹除歷史）。現行處置＝採用量測色值，本尊完整 token 值表見 `docs/design/111`，逐項差異見 `docs/design/110` §7。

→ **`caution` 與 `warning` 是兩個不同的族**（黃 vs 橘），我們現有 token 只有一個「warning」，**少一族**。

### H2-2 浮層堆疊順序 —— **已解**

開啟 popover 與 modal 實測：

```
520  popover / 下拉選單            ← 最高
519  modal 對話框本體
518  modal 遮罩 scrim              bg = rgba(0, 0, 0, 0.5)
518  nav drawer、Skip-to-content
517  頂欄 topbar、側欄寬度調整把手
510  表格批次操作 sticky 列
400  中層雜項
100  表格 sticky 表頭／儲存格
  1  卡片內基礎堆疊
```

→ **`popover(520) > dialog(519)` 確認成立**：modal 內的下拉選單會正確蓋在對話框之上。這正是先前標為「猜錯就是肉眼可見 bug」的那條，現在有實測背書。
→ **遮罩不透明度 = 0.5**（先前未知）。
→ modal 內按鈕實測：`取消 48×28`、`匯出交易記錄 96×28`、`匯出訂單 88×28` —— **全部高 28**，與列表頁控件同階。

### H2-3′ focus 環 —— **第五輪定案（推翻 H2-3 的結論）**

> ⚠ **更正**：H2-3 寫「focus 不是用 outline 畫的」。那個結論只對 `<s-choice-list>` 一個元件成立。
> 掃描全部樣式表的 focus 規則（**437 條**）後，系統層級的真相是**兩種並用**。

| 宣告 | 規則數 | 解析後 |
|---|---:|---|
| `outline: <2px> solid <focus色>` | **98** | **主要做法** |
| `box-shadow: 0 0 0 .125rem <focus色>` | **96** | **次要做法**（outline 會被 `overflow` 裁切時改用） |
| `outline-offset: <1px>` | 41 | 與控件的間隙 |
| `outline-offset: <2px>` | 28 | 較大控件用 |
| `outline-color: <淺藍>` | 4 | **深色底上的反轉環** |

**定案配方**：

| 參數 | 值 |
|---|---|
| 環寬 | **2px**（`.125rem`） |
| 間隙（offset） | **1–2px**（小控件 1px、大控件 2px） |
| 環色（淺底） | **`#005bd3`** |
| 環色（深底反轉） | **`#4b92e5`** |
| 實作 | 優先 `outline` + `outline-offset`；容器有 `overflow:hidden/clip` 時改 `box-shadow: 0 0 0 2px` |

→ 我方原型現用的 `box-shadow: 0 0 0 2px <底色>, 0 0 0 4px <環色>` 是**等價寫法**（2px 間隙 + 2px 環），保留即可，**只需把環色改為量測值**。

**色值採用範圍的決定（見 §I）**：`#005bd3` 是 Shopify 的品牌藍。CLAUDE.md 鐵律 9 禁止抄其 CSS，但 focus 環色本質是**無障礙功能參數**（WCAG 2.4.11 只要求對相鄰色 ≥3:1，色相自由）。決定：
- **admin／platform 採用量測值**（這兩端本就 1:1 對齊 Shopify 後台的操作語彙）
- **storefront 維持自有品牌色**（買家前台有獨立視覺語言，藍環會與暖色調衝突；WCAG 只管對比不管色相）
- 三端一律收斂成**單一 token**，日後要換只改一處

### H2-3 focus 環 —— 第四輪原始記錄（**結論已被 H2-3′ 推翻，保留備查**）

`<s-choice-list>` 這層才是 focus 承載者（封閉 shadow），但可確認：

| 觀察 | 值 |
|---|---|
| `outline-style` | **`none`** → **不是用 outline 畫的** |
| `outline-width`（雖 style=none 仍有計算值） | **2.667px** = dpr 1.5 下的 **4 個實體像素** |
| 目視（高倍率） | **外層深色環 ＋ 環與控件之間有淺色間隙** → 典型雙層 `box-shadow` |

→ **實作方式（我方自寫）**：
```css
.cl-focusable:focus-visible{
  outline: none;                       /* 與實站一致，不用 outline */
  box-shadow: 0 0 0 2px var(--cl-bg),  /* 內層間隙：用底色做出「留白」 */
              0 0 0 4px var(--cl-focus-ring);
}
```
→ 待定：環的**確切顏色**（目視為深中性，非品牌藍）。列為唯一殘留缺口。

### H2-4 額外收穫：表單控件的環是 **inset box-shadow，不是 border**

單選鈕（`<input type=radio>`，light DOM，可完整讀取）：

| 狀態 | 實測 |
|---|---|
| 尺寸 | **16 × 16**，`appearance: none`，`border-radius: 50%` |
| **未選 idle** | `background: transparent`；**`box-shadow: inset 0 0 0 0.66px #8A8A8A`** ← **用 inset 陰影當外框** |
| **已選** | `background: #303030`（＝主要文字色）；`::after` content=""、`background: #FDFDFD`（白色內點） |
| 停用 | 文字轉 `#B5B5B5`（見 §E） |

→ **兩條可直接落地的技法**：
1. **表單控件的 1px 框一律用 `inset box-shadow` 而非 `border`** —— 不佔 box model、可做次像素、與 §C 的髮絲線同一套（`0.66px` 又出現，再次確認「1 個實體像素」原則）。
2. **已選狀態不是用品牌色，是用主要文字色 `#303030` 填滿 + 白色內點** —— 克制、與整體中性調一致。我們原型用品牌青色填滿，**與實站的克制感不同**，需要一併決定要不要跟。

## H. focus 環（第三輪原始記錄，已被 H2-3 取代）

原生 `<button>` 實測 `outline-style: none`，focus 前後無差異 → **focus 環不是用 `outline` 實作**，而是畫在 `s-` 元件的封閉 shadow 內部。
→ `outline-width` 的 computed 值為 `2.66667px`（= dpr 1.5 下的 4 個實體像素）雖然 style 為 none，可作為**環寬的參考值**，但不足以定案。
→ 待以「鍵盤 Tab + 高倍率截圖」目視取樣。

## 7. 仍待補測

根字級已修正、桌機主要數值已取得（見上）。**剩餘缺口**（多數因封閉 shadow DOM，需改用目視或互動觸發）：

1. 設定頁的雙欄（左設定導航寬度、右內容 max-width）
2. 結帳編輯器的**三欄**（樹寬／預覽寬／屬性檢查器寬）與檢查器內的控件型別
3. 商品／文章編輯器主欄與側欄的實際寬度與 gutter
4. 常駐側欄（240px）的展開態、群組摺疊、hover/active 樣式
5. 表格在寬視口下的欄位可見數與 sticky 行為
6. Modal 在桌機的最大寬度階

7. **邊框／髮絲線全部重測**（第一輪誤除 1.5，全數作廢）
8. 次級/主要/tertiary/split/destructive 五種按鈕的**完整繪製盒**（第一輪只解出 split）
9. **九態實測**：disabled / loading / error / selected / read-only / active 的目標值（48 號目前為推導）
10. **focus 環實值**：環寬、offset、環色、輸入框內光暈
11. **z-index 階**與八種浮層堆疊順序（popover 是否高於 modal）
12. **語意色三元組**（success/warning/critical/info 的 bg+fg+border）
13. `prefers-reduced-motion` 對應規則；shake 振幅與次數；skeleton shimmer 參數
14. **rem 斷點換算**：確認 Shopify 斷點是 rem 還是 px 撰寫

> 量測方法備忘（已更新）：**先注入探針元素**（`width:100px; height:1rem; border-top:1px solid`）讀 computed，
> 即可判定「根字級是否非 16px」與「px 是否被縮放」——縮放會同時放大 px 與 rem，字型大小設定只放大 rem。
> 兩者的反推方式完全不同，混用會產生 `0.67px` 這類不存在的值。
> 另：`elementFromPoint` 需傳 **CSS px**，但截圖座標是**截圖 px**；兩者比例 = `innerWidth / 截圖寬度`，
> 不換算會一路命中 `<main>`。實站大量 web components，需逐層 `shadowRoot.elementFromPoint` 下鑽，
> 再向上爬到最近「有繪製」祖先（有背景色／邊框／陰影且高度合理）才是視覺盒。

## 8. 對現有文件的修正清單

| # | 修正 | 影響 |
|---|---|---|
| 80 | 44 號全部截圖須加註「~683px 窄版佈局」 | `docs/research/44` |
| 81 | 間距階從 10 階砍到 **7 階**（2/4/6/8/12/16/24） | `docs/design/23` §1 |
| 82 | **UI 預設字級 14px → 13px**（行高 20） | `23` §1、三份原型 |
| 83 | **大標題字重降到 450**，小字級才用 500 | `23` §1、三份原型 |
| 84 | 圓角改四階 4/8/12/18；補**堆疊卡片單邊圓角**規則 | `23` §1 |
| 85 | 控件高度四階 24/28/32/36 | `23` §1 |
| 86 | checkbox 16px＋**列級 32px 命中區**（不是放大 checkbox 本身） | `34` 觸控規格 |
| 87 | 動效系統定案：**5 時長 × 3 曲線 + 7 條具名規則**；移除所有 `transition: all` | `23`、三份原型 |
| 88 | 新增 **Modal 驗證失敗 shake** 動畫 | `23` 元件庫 |
| 89 | ~~中性色只取層級關係，色值用自有調色~~ **已被 D54 推翻（2026-08-28）**：改為採用量測色值 | `23` §1、`docs/design/110` §7 |
| 90 | 桌機三欄佈局待補測（6 項） | 本文件 §7 |

---

## D.1 🔴 乾淨環境重量（2026-08-28，G12 補完）

> 本節依**鐵律 19.5**追加，**上方原記載保留原文**。
> 觸發＝`docs/design/110` 的 **G12**：本檔的 `font-weight` 值曾在受污染的環境下量測。
> 污染源與機制＝`docs/design/111` §20。
>
> **全部數值以「停用污染源 → 讀 clean → 還原 → 讀 dirty」的同步配對取得**，
> 收工已還原成使用者原狀並複驗。
>
> ⚠️ 只有 `font-weight` 受污染；font-size／line-height／color 等在兩種環境下相同——
> 但本輪**一併複驗**了它們，因此下表也含非字重的更正（那些屬「量錯層」或原記載本身有誤）。

**本節結果：17 列（更正 9／複驗一致 8／未取得 0）**

| # | 項 | 判定 | 原記載 | 🔴 乾淨值 | 污染值 | 實際量的節點 |
|---:|---|:--:|---|---|---|---|
| 1 | 頁首動作組 · 第一顆「Export／匯出」（§D 表第 1 列，記為 tertiary） | 🔴 更正 | 變體 tertiary｜填色「淺灰實心」｜文字「深色」｜圓角「~8px」｜備註「無邊框」（無尺寸、無字級/字重/行高、無 bg/color 具體值、無 box-shadow、無 hover） | **variant 屬性實測值 = **secondary**（不是 tertiary）。盒 61.81×28 @ (469.8,72)，min-height 28px、min-width auto｜padding 6px 12px｜border-radius 8px｜border 0px none｜**font-size 12px / font-weight 550 / line-height 16px**，letter-spacing normal，font-family 首選 Inter｜color rgb(48,48,48)｜background **rgb(227,227,227)**｜**box-shadow: none**｜gap 2px｜display flex｜cursor pointer｜transition none｜opacity 1。**hover**（matches(':hover')===true 驗證）：background → **rgb(212,212,212)**，其餘（尺寸／padding／radius／border／box-shadow／color／字級字重行高）**逐項不變**。** | 繪製盒 font-weight 550（與 clean 相同）、font-size 12px、line-height 16px、background rgb(227,227,227)、color rgb(48,48,48) 全部與 clean 相同；差異僅出現在 light DOM 宿主鏈（見 environment 對照組）。 | host `s-internal-button[variant="secondary"]`（light DOM 內、display:contents、0×0）→ **open shadowRoot** 內 `button.button.size-base.tone-auto.variant-secondary` ＝繪製盒。該 `.button` **自宣告 font-weight**（clean 550＝dirty 550）⇒ 對擴充功能免疫。文字葉節點鏈 `span.content` →『span.text-wrapper』(37.81×16) → slot，三者 clean/dirty 皆 550。 |
| 2 | 頁首動作組 · 第二顆「More actions ⌄／更多動作」（§D 表第 2 列，記為 split） | 🔴 更正 | 變體 split｜填色「淺灰實心」｜文字「深色」｜圓角「~8px」｜備註「右側 chevron，與本體同一顆（非分離式）」 | **variant 屬性實測值 = **secondary**（不是 split），另帶 class `icon-with-text menu-activator`。盒 115.08×28 @ (537.61,72)，min-height 28px｜**padding 4px 6px 4px 12px（非對稱，與另兩顆的 6px 12px 不同）**｜border-radius 8px｜border 0px none｜**12px / 550 / 16px**｜color rgb(48,48,48)｜background rgb(227,227,227)｜**box-shadow: none**｜gap 2px｜display flex｜transition none。內部 `span.content` 97.08×20、`span.text-wrapper` 75.08×16。chevron：`s-internal-icon` 20×20 @ (626.69,76)，內 svg **16×16** @ (628.69,78)、color rgb(74,74,74)（比文字 rgb(48,48,48) 淺一階）。**hover**：background → rgb(212,212,212)，其餘逐項不變。** | 繪製盒 550／12px／16px、bg rgb(227,227,227)、color rgb(48,48,48)，與 clean 完全相同（免疫）。 | host `s-internal-button[variant="secondary"]`（本身位於某 shadow 內，故宿主 clean/dirty 皆 450）→ open shadowRoot 內 `button.button.size-base.tone-auto.variant-secondary.icon-with-text.menu-activator` ＝繪製盒，自宣告 font-weight 550 ⇒ 免疫。disclosure 鏈：`span.disclosure`（display:contents，不產生繪製盒）→ `s-internal-icon` 20×20 → 其 shadow 內 svg 16×16。 |
| 3 | 頁首動作組 · 第三顆「Create order／建立訂單」（§D 表第 3 列，primary） | 🔴 更正 | 變體 primary｜填色「深色（近黑）實心」｜文字「白色」｜圓角「~8px」｜備註「三者等高、等圓角，只靠填色分層級」 | **盒 96.51×28 @ (658.69,72)，min-height 28px、min-width auto｜padding 6px 12px｜border-radius 8px｜border 0px none｜**12px / 550 / 16px**，letter-spacing normal｜color **rgb(255,255,255)**｜background **rgb(48,48,48)**（＝「近黑」的實測值）｜**box-shadow 3 層 inset：rgba(0,0,0,0.8) 0 -1px 0 1px inset, rgb(48,48,48) 0 0 0 1px inset, rgba(255,255,255,0.25) 0 0.5px 0 1.5px inset**｜gap 2px｜display flex｜cursor pointer｜transition none。**hover**：background → **rgb(26,26,26)**、color → **rgb(227,227,227)**；box-shadow／radius／尺寸／padding **不變**。** | 繪製盒與 text-wrapper 皆 550（與 clean 相同）、12px／16px 相同；宿主 `s-internal-button` 450→500（對照組）。 | host `s-internal-button[variant="primary"]`（**light DOM**，clean 450 → dirty 500＝本輪主要對照組）→ open shadowRoot 內 **`a.button.size-base.tone-auto.variant-primary`（是 `<a>`，不是 `<button>`）**＝繪製盒，自宣告 font-weight 550 ⇒ 免疫。`span.content` 72.51×16、`span.text-wrapper` 72.51×16 亦皆 550。 |
| 4 | 頁首動作組 · §D 結論句「三個層級靠『填色深淺』區分，不靠邊框或尺寸」 | 🔴 更正 | 「三個層級靠『填色深淺』區分，不靠邊框或尺寸」；並據此推得「我們原型目前 secondary 用白底＋邊框，方向就不對」 | ****成立的半邊**：三顆 border 皆 `0px none`、高度皆 **28px**、border-radius 皆 **8px**、字皆 12/550/16 ⇒「不靠邊框或尺寸」複驗成立。**不成立的半邊**：①分層不是只靠填色——primary 另帶 3 層 inset box-shadow（rgba(0,0,0,0.8)／rgb(48,48,48)／rgba(255,255,255,0.25)），兩顆 secondary 的 box-shadow 是 **none**，這是一層 secondary 完全沒有的立體處理；②三顆的 padding 不齊（Export／Create order＝6px 12px，More actions＝4px 6px 4px 12px）；③**這一組裡根本沒有 tertiary**——兩顆左側鈕的 variant 屬性都是 secondary，§D 的「tertiary／split／primary 三層級」命名整組不成立（本頁確有 variant=tertiary 實例，但在表格工具列，28×28 icon-only、background rgba(0,0,0,0)，不屬頁首動作組）。** | 以上幾何／色值／陰影在 dirty 環境逐項相同（污染只作用於 font-weight，且三顆繪製盒皆免疫）。 | 三顆繪製盒（皆在 open shadow 內）逐項對照：variant-secondary ×2、variant-primary ×1。 |
| 5 | 徽章 · `Paid／已付款`（§D 徽章表第 1 列） | ✅ 一致 | 底色「淺灰」｜前置圖示「● 實心圓點」｜語意「完成 / success」 | **盒 55.04×20，min-height auto｜padding **2px 8px 2px 4px**（有 icon 時左側 4px）｜border-radius **8px**｜gap **2px**｜border 0px none｜**box-shadow none**｜**12px / 550 / 16px**｜color **rgb(97,97,97)**｜background **rgba(0, 0, 0, 0.06)**（半透明，不是實色淺灰）｜display flex。圖示鏈：`s-internal-icon` 16×16 → 其 shadow 內 `span.icon.color-base.tone-auto.size-small` 16×16（padding 0）→ `svg` **12×12**，viewBox「0 0 12 12」，fill/color 皆 rgb(97,97,97)（＝跟文字同色）→ 單一 `<path>`，getBBox = x2 y2 w8 h8，fill-rule **nonzero**，getTotalLength **26.85**。** | 繪製盒 550／12px／16px、bg rgba(0,0,0,0.06)、color rgb(97,97,97) 與 clean 完全相同（免疫）。 | host `s-internal-badge[icon="enabled"][role="img"][aria-label="Complete Paid"]`（light DOM，clean 450 → dirty 500）→ open shadowRoot 內 `div.badge.size-base.tone-auto.color-base.with-icon` ＝繪製盒，**自宣告 font-weight 550** ⇒ 免疫；`span.content`（25.04×16）亦 550。 |
| 6 | 徽章 · `Unfulfilled／未出貨`（§D 徽章表第 3 列） | ✅ 一致 | 底色「黃色」｜前置圖示「○ 空心圓」｜語意「未開始 / attention」 | **盒 89.55×20｜padding 2px 8px 2px 4px｜radius 8px｜gap 2px｜border 0px none｜box-shadow none｜**12px / 550 / 16px**｜background **rgb(255,235,120)**｜color **rgb(79,71,0)**｜圖示 svg 12×12、path bbox 8×8 @(2,2)、fill rgb(79,71,0)、fill-rule **evenodd**、getTotalLength **45.42**。tone 名稱是 **caution**（不是 warning）。** | 550／12px／16px／rgb(255,235,120)／rgb(79,71,0) 與 clean 相同（免疫）。 | host `s-internal-badge[icon="incomplete"][tone="caution"][aria-label="Incomplete Caution Unfulfilled"]`（light DOM，450→500）→ shadow 內 `div.badge.size-base.tone-caution.color-base.with-icon`，自宣告 550 ⇒ 免疫。 |
| 7 | 徽章 · `Tracking added／已新增追蹤資訊`（§D 徽章表第 4 列） | 🔴 更正 | 底色「淺灰」｜前置圖示「⊘ 斜線圓」｜語意「**中性資訊**」 | **盒 119.64×20｜padding 2px 8px 2px 4px｜radius 8px｜gap 2px｜border 0｜box-shadow none｜**12px / 550 / 16px**｜background rgba(0,0,0,0.06)｜color rgb(97,97,97)｜圖示 svg 12×12、path bbox 8×8、fill-rule **evenodd**、getTotalLength **58.51**。底色與圖示形狀均與 §D 相符；🔴 **但語意登記錯**：本尊自己的 `aria-label` 前綴是「**Partially complete**」、`icon` 屬性值是「**in-progress**」，與 §D 寫的「中性資訊」不同——它與 §D 第 2 列想描述的「部分完成」是同一個語意槽，只是 tone 為 auto（灰）而非 caution。** | 550／12px／16px 與 clean 相同（免疫）。 | host `s-internal-badge[icon="in-progress"][aria-label="Partially complete Tracking added"]`（light DOM，450→500）→ shadow 內 `div.badge.size-base.tone-auto.color-base.with-icon`，自宣告 550 ⇒ 免疫。 |
| 8 | 徽章 · `Fulfilled`（§D 徽章表未列，本輪補登） | ✅ 一致 | §D 未記載 | **盒 75.46×20｜padding 2px 8px 2px 4px｜radius 8px｜gap 2px｜box-shadow none｜**12px / 550 / 16px**｜background rgba(0,0,0,0.06)｜color rgb(97,97,97)｜圖示與 `Paid` 同一組（fill-rule nonzero、length 26.85、實心圓）。⇒ 證實「完成」語意在**出貨**與**付款**兩個維度共用同一個 icon=enabled。** | 550／12px／16px 與 clean 相同（免疫）。 | host `s-internal-badge[icon="enabled"][aria-label="Complete Fulfilled"]`（light DOM，450→500）→ shadow 內 `div.badge...with-icon`，自宣告 550 ⇒ 免疫。 |
| 9 | 徽章 · 無圖示中性徽章（側欄計數「5」與標籤欄，§D 未單獨列） | ✅ 一致 | §D 未記載無圖示形態的盒模型 | **側欄計數「5」：23.77×20｜**padding 2px 8px 2px 8px（左右對稱）**｜radius 8px｜**gap 4px**｜min-height 0px｜border 0｜box-shadow none｜12px / 550 / 16px｜background rgba(0,0,0,0.06)｜color rgb(97,97,97)。⇒ 有／無圖示兩形態的**唯一**盒模型差異＝左內距 8px→4px、gap 4px→2px、min-height 0px→auto；高度 20px、radius 8px、右內距 8px、字 12/550/16、底色、文字色全部相同。** | 550／12px／16px 與 clean 相同（免疫）。 | host `s-internal-badge`（無 icon/tone 屬性，light DOM，450→500）→ shadow 內 `div.badge.size-base.tone-auto.color-base`（**無 `with-icon`**），自宣告 550 ⇒ 免疫。 |
| 10 | 徽章 · §D「本輪最重要的發現」＝狀態圖示形狀編碼（實心 ●＝完成｜空心 ○＝未開始｜斜線 ⊘＝部分／受阻） | ✅ 一致 | 「每個徽章都帶一個前置狀態圖示，且圖示形狀本身就編碼了狀態」；來源為高倍率截圖**目視判讀** | **光柵結果（clean 環境；字重污染與 SVG 無關，但仍在 disabled=true 下取得）：**icon=enabled → 實心圓盤（中心全滿）**；**icon=incomplete → 圓環（中心鏤空，環寬約 1.2px @12 單位）**；**icon=in-progress → 圓環＋一條貫穿圓心的對角線（左上↔右下）**。三者外框同尺寸：svg 12×12、path bbox 8×8 @(2,2)、單一 `<path>`。輔證：fill-rule 分別為 nonzero / evenodd / evenodd；getTotalLength 分別 26.85 / 45.42 / 58.51；本尊自己的 aria-label 前綴分別是 **Complete / Incomplete / Partially complete**。⇒ §D 的形狀→語意對映**逐項成立**，且本輪首次以非目視方式取得佐證；圖示顏色一律等於該 tone 的文字色（Paid rgb(97,97,97)、Unfulfilled rgb(79,71,0)），不另有專用色。** | 圖示幾何與 fill 不受污染源影響（污染源只宣告 font-weight／text-shadow／font-smoothing／text-rendering，且選擇器以 `:not(svg):not(svg *)` 明文排除 svg）。 | 三種 `icon` 屬性值各取一個實例的 `svg > path`（在 `s-internal-badge` → `s-internal-icon` 的巢狀 open shadow 內），以 `Path2D` 依各自 computed `fill-rule` 重繪到 48×48 canvas，讀 alpha 通道自製光柵（本輪自繪的量測輸出，未記錄本尊 path 資料）。 |
| 11 | 標籤 vs 徽章 · §D「視覺上是兩種不同元件，不可混用」總判 | 🔴 更正 | 表格四列：圓角（徽章 ~8px 圓角矩形／標籤**全圓藥丸形**）、圖示（徽章有／標籤無）、底色（徽章依語意／標籤一律淺灰）、溢出（徽章不折疊／標籤 `+ 1` 收合計數） | **標籤欄「fecify」：49.03×20｜padding **2px 8px**｜**border-radius 8px（不是全圓；藥丸形需 border-radius ≥ 10px 或 9999px）**｜gap 4px｜border 0px none｜box-shadow none｜**12px / 550 / 16px**｜background **rgba(0,0,0,0.06)**｜color rgb(97,97,97)｜無 `s-internal-icon`。與同頁狀態徽章 `Paid`（55.04×20｜padding 2px 8px 2px 4px｜radius 8px｜gap 2px｜同一組 12/550/16｜同一組底色與文字色｜有 icon）逐項對照 ⇒ **兩者是同一個 `s-internal-badge` 元件的『有／無 with-icon』兩種形態**，差異只有左內距與 gap。§D 四列判定：圓角 → **推翻**（8px，非全圓）；圖示有無 → 成立；底色「一律淺灰」→ 成立（值＝rgba(0,0,0,0.06)，與中性徽章同值）；溢出 `+ 1` → 成立（見下一列）。「兩種不同元件」這個總判 → **推翻**。** | 標籤欄繪製盒 550／12px／16px、底色與文字色皆與 clean 相同（免疫）。 | 標籤欄實例：`fecify`、`fecify:25`、`fecify-cancel-blocked`、`fecify-refund-review` 的 host 全部是 **`s-internal-badge`**，繪製盒為其 open shadow 內的 `div.badge.size-base.tone-auto.color-base`（自宣告 550 ⇒ 免疫；host 450→500）。另掃描全頁自訂元素標籤名，含 tag／chip／pill 者為**空集合**。 |
| 12 | 標籤欄溢出計數 `+ 1`（§D 標籤表第 4 列「`+ 1` 收合計數」） | 🔴 更正 | 「標籤：`+ 1` 收合計數（實測第三列 `fecify`、`fecify-cancel-blocked`、`fecify-refund-review` `+ 1`）」——未記形態、未記它是不是 badge | **繪製盒 16.2×15.2｜display inline｜**font-size 12px / font-weight 450 / line-height 16px**｜color **rgb(97,97,97)**（color-subdued）｜background rgba(0,0,0,0)｜border-radius 0｜padding 0｜border 0｜box-shadow none。⇒ 溢出計數是**純文字**，沒有 badge 的底色、圓角與內距，字重也比 badge 的 550 輕一階。** | 繪製盒 450／12px／16px（與 clean 相同）；宿主 `s-internal-text` 450→500、其 Polaris 祖先鏈四層亦 450→500。 | 存在性複驗成立（同一列仍是三顆 badge ＋ 一個 `+ 1`）。但它**不是 badge**：host 是 **`s-internal-text`**（light DOM、display:contents、0×0、clean 450 → **dirty 500**）；繪製盒在其 open shadow 內＝`span.text.tone-auto.color-subdued.font-variant-numeric-auto.size-small`，**該 span 自宣告 font-weight 450** ⇒ 免疫（clean 450 ＝ dirty 450）。🔴 這是本輪唯一「宿主被污染、繪製盒靠自宣告擋下」的公開案例，若誤量宿主會登記成 500。 |
| 13 | §6.5 次級按鈕（split）完整配方 · 幾何（高 28／內距 6 上下 · 12 左右／圓角 8） | ✅ 一致 | 「高 28（rem 類，真值待確認）／內距 6 上下 · 12 左右／圓角 8」 | **min-height **28px**、實際高 **28**｜padding **6px 12px**｜border-radius **8px**。三項逐項吻合，「真值待確認」可結案（根字級 16px，非 rem 換算污染）。⚠️ 但這組 padding **只對不帶 disclosure 的 secondary 成立**；帶 disclosure 的同 variant（More actions）是 4px 6px 4px 12px，而 §6.5 標題把配方掛在「split」名下 ⇒ 配方與它自己指名的按鈕對不上。** | 幾何值不受污染源影響，dirty 環境逐項相同。 | `s-internal-button[variant=secondary]`（Export）的 open shadow 繪製盒 `button.button...variant-secondary`。 |
| 14 | §6.5 次級按鈕完整配方 · 字（字級 12/16、字重 **550**） | ✅ 一致 | 「字級 12/16，字重 550 ← 注意是 550，不是 500 或 600」 | ****font-size 12px / font-weight 550 / line-height 16px**，letter-spacing normal，font-family 首選 Inter，color rgb(48,48,48)。三個獨立佐證：①clean 直接量測 = 550；②dirty 直接量測 = 550（免疫，故此值本來就不曾被污染）；③`--p-font-weight-button-label` computed = **550**、`--p-font-size-button-label` computed = **.75rem**（＝12px @root 16px）。⇒ §D 開頭「本節 font-weight 一律待複驗」的守衛，對本項的複驗結果是**原值正確**。** | font-weight 550（與 clean 相同）、font-size 12px、line-height 16px 相同。 | 繪製盒 `button.button.size-base.tone-auto.variant-secondary`（open shadow 內），**自宣告 font-weight** ⇒ 對 `font-bolder-style` 免疫；其下 `span.content`、`span.text-wrapper` 皆繼承同值。 |
| 15 | §6.5 次級按鈕完整配方 · 背景「#FFFFFF」 | 🔴 更正 | 「背景 #FFFFFF」（第三輪原文） | **background-color = **rgb(227,227,227)**（default）／**rgb(212,212,212)**（hover）。**推翻白底**。（此結果與同檔已存在的 2026-08-28 更正註一致，本輪為在**乾淨環境**下的第二次獨立複驗，樣本＝/orders 頁首 Export 與 More actions 兩顆。）** | rgb(227,227,227)／rgb(212,212,212)，與 clean 相同（背景色不受污染源影響）。 | 同上繪製盒；另複查全頁 14 個具 box-shadow 的繪製盒與頁首三顆按鈕，無任何白底按鈕。 |
| 16 | §6.5 次級按鈕完整配方 · 「陰影兩層：① inset 0 -1px 0 0 #B5B5B5 ② drop rgba(0,0,0,.1)」 | 🔴 更正 | 「陰影兩層：① inset 0 -1px 0 0 #B5B5B5（底緣 1px 內陰影）② drop rgba(0,0,0,.1)（外投影）」，並據此推得「白底 + 底緣內陰影 + 外投影是次級按鈕的立體感來源」 | ****box-shadow: none**（default）；**hover 仍為 none**；border 亦為 `0px none` ⇒ **推翻兩層陰影**，「立體感來源」的推論隨之失效。對照：同一組頁首中**只有 primary** 有 inset 陰影（3 層，見上方 Create order 列）。全頁掃描：有 box-shadow 的繪製盒共 **14 個**，相異值只有 6 種——`rgb(138,138,138) 0 0 0 0.66px inset`（×7，輸入類髮絲環）、`rgb(227,227,227) 0 1px 0 0 inset`（×1）、`rgba(0,0,0,0) 0 0 0 0 inset`（×2，全透明）、一組 6 層 drop（×1）、`rgba(0,0,0,0.05) 1px 0 3px 0`（×2）、primary 按鈕那組 3 層 inset（×1）——**沒有任何一個**是 `#b5b5b5 inset ＋ #fff inset` 那組配方。** | box-shadow: none，與 clean 相同。 | 同上繪製盒（default 與 hover 兩態）。 |
| 17 | §6.5 更正註的推斷：「錯誤來源是讀到 `--p-shadow-button` token 的值、但它沒套用在該繪製盒上」 | ✅ 一致 | 更正註原文：「①逐項吻合，②的 rgba(0,0,0,.1) 就是 #0000001a，只是本節把它記成 drop 而 token 裡是 inset ⇒ 當時讀到的是 token 表的值」 | **`--p-shadow-button` computed = `0rem -.0625rem 0rem 0rem #b5b5b5 inset, 0rem 0rem 0rem .0625rem #0000001a inset, 0rem .03125rem 0rem .09375rem #FFF inset`（@root 16px：.0625rem=1px、.03125rem=0.5px、.09375rem=1.5px）。逐項對照 §6.5 原文：**①完全吻合**（`0 -1px 0 0 #b5b5b5 inset`）；**②吻合**（`#0000001a` ＝ rgba(0,0,0,0.1)，原文記成 drop、token 為 inset）；🔴 **並且第三層 `0 0.5px 0 1.5px #FFF inset` 正好解釋原文的『背景 #FFFFFF』**——那不是背景，是這個 token 的第三層白色 inset。⇒ 更正註的推斷不但成立，還能一併解釋原文的白底來源（原更正註只對到 ①②）。同時取得：`--p-shadow-button-primary` = `0rem -.0625rem 0rem .0625rem #000000cc inset, 0rem 0rem 0rem .0625rem #303030 inset, 0rem .03125rem 0rem .09375rem #ffffff40 inset`，**與 Create order 繪製盒的 computed 3 層 inset 逐項相等**（#000000cc＝rgba(0,0,0,0.8)、#ffffff40＝rgba(255,255,255,0.25)）⇒ 該 token 家族確實在用，只是 `--p-shadow-button` 這一支沒有落在 variant=secondary 的繪製盒上。另：`--p-border-radius-button` computed = **空字串**（與 111 記載一致），故 radius 8px 不是來自這支 token。** | token computed 值與繪製盒 box-shadow 在 dirty 環境相同（污染源不涉及）。 | `getComputedStyle(document.documentElement)` 讀自訂屬性 computed 值（不是讀樣式表原始碼）；並與繪製盒 computed box-shadow 對照。 |

### D.1.a 本次重量帶出的規律

1. 🔴 **免疫判準再次被證實是「該元素自己有沒有宣告」而非「在不在 shadow 裡」**：本輪三顆頁首按鈕的 `.button`、六種 badge 的 `.badge`、`+ 1` 的 `span.text.size-small` 全部在 shadow 內且全部自宣告 font-weight（前兩者 550、後者 450）⇒ clean/dirty 完全相同；同時它們的 light DOM 宿主（`s-internal-button`、`s-internal-badge`、`s-internal-text`）與 Polaris 祖先鏈 clean 450 → dirty 500。**同一顆元件的宿主被污染、繪製盒沒有**，是本輪最容易誤量的形態。
2. 🔴 **§D 整節的字重風險其實是空的，真正的問題是變體命名與元件歸類**：§D 三張表沒有任何 font-weight 值，故「字重待複驗」守衛在本節無對象；本輪推翻的四項全部是**目視判讀本身的誤判**——（a）Export 的 variant 是 secondary 不是 tertiary；（b）More actions 的 variant 是 secondary（class icon-with-text menu-activator）不是 split；（c）標籤欄的 tag 與狀態 badge 是**同一個 `s-internal-badge` 元件**，圓角同為 8px、非藥丸形；（d）`+ 1` 不是 badge 而是 `s-internal-text`。⇒ 目視判讀的失效模式是「把外觀相近的東西歸成不同元件、把同一元件的兩種 modifier 讀成不同變體」，不是讀錯數字。
3. **Shopify 這一版的元件差異幾乎都靠 padding／gap 微調，不靠幾何分家**：badge 有無圖示＝左內距 8px↔4px、gap 4px↔2px（高度、radius、右內距、字全同）；secondary 按鈕有無 disclosure＝padding 6px 12px ↔ 4px 6px 4px 12px（高度、radius、字、底色全同）。任何「兩種不同元件」的判斷都必須先比 class modifier，不能比外觀。
4. **28 / 20 / 8 三個數字繼續主導**：按鈕 min-height 28px（三變體皆是）、badge 高 20px、控件 radius 一律 8px；字則是按鈕與 badge 共用 12px/550/16px 這一組（`--p-font-size-button-label`=.75rem、`--p-font-weight-button-label`=550 佐證）。
5. **狀態變化只換色、不換幾何**（本輪 hover 逐項複驗）：secondary #e3e3e3→#d4d4d4；primary #303030→#1a1a1a 且文字 #fff→#e3e3e3；三顆的 box-shadow／border-radius／padding／尺寸／字級字重行高在 hover 前後**逐字元相同**。primary 的 3 層 inset 陰影在 hover 時**不變**，與 `--p-shadow-button-hover` 那支 token 無關。
6. 🔴 **token 值 ≠ 繪製盒值，這條在本輪再次拿到正面證據**：`--p-shadow-button`（白色 bevel 那組）在全頁 14 個有陰影的繪製盒中**一個都沒用上**，而 `--p-shadow-button-primary` 與 Create order 的 computed box-shadow **逐項相等**。同一個 token 家族，有的支在用、有的支不在用 ⇒ 引用任何 `--p-*` 值當實作依據前，必須先在繪製盒上找到相等的 computed 值。`--p-border-radius-button` 甚至是空字串。
7. **本尊的狀態語意有機器可讀來源，不必靠目視猜**：`s-internal-badge` 的 `icon` 屬性（enabled／incomplete／in-progress）與 `aria-label` 前綴（Complete／Incomplete／Partially complete）成對出現，且與圖示形狀（實心圓／圓環／圓環＋對角斜線，本輪以 Path2D 自繪光柵取得）一一對應。⇒ 我方 badge 要補的不只是「加一個圖示」，而是這組三值 enum ＋ aria-label 前綴，才符合 §D 引的 WCAG 1.4.1（不以顏色單獨傳達狀態）。
8. **圖示顏色沒有獨立色階**：Paid 的 svg fill = rgb(97,97,97) = 該 badge 的文字色；Unfulfilled 的 svg fill = rgb(79,71,0) = 該 badge 的文字色。圖示一律吃 currentColor，不另設 icon 專用色。
9. **擴充功能只污染 font-weight 這一點在本輪再次逐項成立**：所有配對量測中 font-size（12px）、line-height（16px）、color、background-color、border-radius、padding、box-shadow、盒尺寸在 clean/dirty 兩環境**逐項相同**；`html` 根元素 clean/dirty 皆 450（反向對照組）。
10. **方法論**：SVG 形狀可以在不複製本尊 path 資料的前提下取得客觀證據——把繪製中的 path 用 `Path2D` ＋ 各自的 computed `fill-rule` 重繪到自建 canvas，讀 alpha 通道輸出自製光柵。這是本輪唯一能把 §D「本輪最重要的發現」從目視升級成量測的手段（`screenshot` 在本環境逾時不可用）。

### D.1.b 仍未取得

- 三顆頁首按鈕的 **:active（按下態）** —— 未取得。原因＝工具限制，已實測非推測：對 document 掛 capture 監聽 pointerdown／mousedown／pointerup／mouseup／click 後執行 `computer.left_click`，五類事件觸發次數皆為 0；`left_click_drag` 期間只收到 2 次 mousemove（e.buttons&1 為真）而無 mousedown／mouseup，該時刻 `matches(':active')` 為 false。取得方式：換一個滑鼠按鍵事件能實際進入頁面的環境，於 document capture 掛 mousedown 監聽，在其中同步 `__X(true)` → `getComputedStyle` → `__X(false)`，並同時以 capture 階段 `stopImmediatePropagation` 擋掉 click 以維持唯讀。
- 三顆頁首按鈕的 **:focus-visible 與 disabled** —— 本輪未量（不在 §D 原記載範圍內，且本輪重點在字重複驗）。`docs/design/113` §1.2 有這兩態，但其量測環境未聲明擴充功能狀態、且寬度為 1024 ⇒ 若要引用需另做乾淨環境複驗。
- §D 徽章表第 2 列 `部分已履行`（Partially fulfilled，記為『橘／蜜桃色 ＋ ⊘ 斜線圓』）—— 未取得。原因＝本輪 /orders 列表 25 個 `s-internal-badge` 實例中不存在該狀態（實際出現的只有 icon=enabled/tone-auto、icon=incomplete/tone=caution、icon=in-progress/tone-auto 三種），亦即**沒有任何 tone=warning 的 badge 繪製盒**；`--p-color-bg-surface-warning` 這類 token 值不得拿來當繪製盒證據（§6.5 事故同型）。取得方式：找一張部分出貨的訂單（或在測試店對一張現有訂單只開啟 fulfillment 畫面而不送出），於列表或詳情頁量 tone=warning 的 badge。
- **1280 桌機寬度的形態** —— 未取得。本輪 innerWidth 固定 787（`resize_window` 依指派說明無效，且該實體視窗與其他並行代理共用，未改動）。787 已在本尊主斷點 768 之上、頁首三顆按鈕皆完整渲染，但鐵律 13.1 要求的 1280 形態需另量；本檔任何數值不得外推成 1280 宣稱。
- **§D 原記載當時的量測環境** —— 未取得且不可回溯。§D 全節未載明量測條件，故無法判定它是否在 `font-bolder-style` 生效下取得。本輪的處置是不去推測，改為對 §D 的每一項重新直接量測；結論是 §D 表中**本來就沒有任何 font-weight 值**（頁首動作組表只有填色／文字／圓角／備註，徽章與標籤表只有底色／圖示／語意／圓角／溢出），因此 §D 的字重守衛實際上是空集合。
  🔴 **但這不表示本檔沒有污染字重**——`grep -nE "/ *500|字重 *500" docs/design/47-measured-interaction-spec.md` 在 **§3／§4／§B／§E** 共命中 **10 個 `500`**，那些才是本檔真正的污染面，**G12 的射程漏掉了它們**（已於同日補加守衛，並登記為 `docs/design/110` 的 **G12b**）。同檔 §6.5 的『字重 550』則已複驗為正確且免疫。
- **第三輪 §6.5 作者實際的取值路徑（provenance）** —— 不可觀測。本輪能證明的是：`--p-shadow-button` 的 computed 值與 §6.5 記載的 ①②（外加可解釋『白底』的第三層 #FFF inset）逐項吻合，而該組值不存在於本頁任何繪製盒 ⇒『讀到 token、當成繪製盒』這個推斷與全部證據相容；但『當時是不是真的這樣操作』無法由現在的 DOM 取證，不得寫成已證實。
- **`+ 1` 展開後的完整標籤清單** —— 未取得（需點擊展開，屬狀態改變，本輪唯讀約束下未點）。

> 量測環境：🔴【已停用污染源後量測】Claude in Chrome，自建分頁 tabId 1174402754（量畢時該 session 的 tab group 已不存在，分頁已不在；期間未動使用者原有分頁）。頁面＝https://admin.shopify.com/store/chill-love-u5q5mnzq/orders ，由首頁側欄真實 href「/store/chill-love-u5q5mnzq/orders」導航，未猜路徑。量測日期 2026-08-28。innerWidth=787、innerHeight=372、devicePixelRatio=1.25、getComputedStyle(document.documentElement).fontSize=16px（根字級預設，無 47 §F 記過的 root 24px 污染）。🔴 寬度 787 不是鐵律 13.1 的 1280：`resize_window` 依指派說明不可用，且該實體視窗與其他並行代理共用，未改動 ⇒ 本檔任何「桌機 1280 形態」宣稱不得引用本輪數值。  污染源：`<style id="font-bolder-style">`，`parentNode.nodeName === "HTML"`，初始 `sheet.disabled === false`。停用法＝該 sheet 的 `disabled` 旗標切換（只切 CSSOM 旗標，未動擴充功能設定）。每一列都做 clean（disabled=true）／dirty（disabled=false）配對量測，同一次 JS 呼叫內連續取值。 反向對照組（證明切換確實生效，每一輪都重取）：①`html` 根元素 clean/dirty 皆 450（不在選擇器射程）②light DOM 的 `s-internal-button` 宿主（Create order）clean 450 → dirty 500 ③light DOM 的 `s-internal-text` 宿主（`+ 1`）clean 450 → dirty 50
