# 排程發布的地基與原語（M2 · S6b-2a）

## 概述

排程發布（`Schedule publishing`）的**時區地基與三個原語**。本包**刻意不含接線**——
發布 modal 上的日曆 icon、送出 `publishDate`、發布卡的排程 badge 屬 **S6b-2b**。

拆包理由：`Popover` 是 **S6c 的明文前置**（交接檔逐字「S6c 之前要先做 popover 原語」），
早一個 PR 進 main 讓 S6c 不必等接線那半。四個交付物各自可獨立驗收、各自有測試與突變。

| 交付 | 內容 |
|---|---|
| `Query.shop.ianaTimezone` | 店鋪時區的伺服器面（本尊 `Shop.ianaTimezone`） |
| `app/frontend/admin/lib/timezone.ts` | 牆鐘 ⇄ UTC 換算、偏移標籤、時間輸入解析 |
| `components/Popover.tsx` | 非模態浮層原語（portal，S6c／S6d 共用） |
| `components/Calendar.tsx` | APG grid 月曆 |
| `components/SchedulePopover.tsx` | 排程內容面（組合上面三個） |

## 規格出處

| 主題 | 出處 |
|---|---|
| 彈層形態、值域、關閉語義、`Remove schedule` 終態、抓包 | `docs/research/82` §15（2026-08-27 實測） |
| 排程只掛在 `supportsFuturePublishing` 的管道 | `82` §12.3／§15.10 |
| 時區來源＝店鋪 Store defaults | help（取證 2026-08-26），`82` §15.6 |
| 本尊 `Shop` 的四個時區欄位 | <https://shopify.dev/docs/api/admin-graphql/latest/objects/Shop>（取證 2026-08-27） |
| 月曆的 grid role／roving tabindex／十三條鍵盤／`aria-selected` 唯一 | W3C ARIA APG Date Picker Dialog Example（取證 2026-08-27） |
| `aria-disabled` 保留可聚焦 | APG Developing a Keyboard Interface（同日） |
| 偏移隨 instant 變（DST） | MDN `Temporal.ZonedDateTime`、RFC 9557 §1.2／§3.4（同日） |

## 🔴 三個「在香港測不出來」的陷阱

本專案的基準法域是香港，而 `Asia/Hong_Kong` **全年 `+08:00`、沒有 DST**。
下面三種錯誤實作在只用香港測時**全部 100% 測綠**，所以測資主力刻意用
`America/New_York`（2026 DST：3/8 起、11/1 止，以執行環境 `Intl` 實測確認）：

1. **用瀏覽器時區代替店鋪時區**——本尊實測環境正好兩者不同（瀏覽器 `Asia/Taipei`、
   店鋪 `Asia/Hong_Kong`），而徽章的 React fiber prop 是後者 ⇒ 決定性證據說明它由後端下發。
2. **用「現在的偏移」換算未來時刻**——跨 DST 會差一小時。
3. **把牆鐘當 UTC 只解一次**——見下。
4. **在牆鐘字串上比大小**（例如判斷「不早於 now」）——牆鐘→instant 的映射在 DST 日
   **不是單調的**，字串上通過的值仍可能落在 now 之前。

## 演算法：候選集合 ＋ 自洽性檢驗

`Intl.DateTimeFormat` 只能「把 instant 格式化到某時區」，**沒有反向 API**。
反推偏移的做法是把牆鐘欄位先當成 UTC 造一個 instant、格式化回該時區、取差值。
但**偏移依賴 instant**，而我們手上只有牆鐘。

⇒ **列出候選再驗證**：用「前一天／當刻／後一天」三個偏移各解一次得到候選 `t`，
再檢驗**自洽性**——`asIfUtc - zoneOffsetMs(t) === t`（用 `t` 當地的實際偏移回頭解，
得到的還是 `t`）。自洽的候選就是真的對應到那個牆鐘時間的 instant。

🔴 **DST 的兩種病態情形＝ours 顯式裁定**（MDN 逐字 `one local time can correspond to
zero, one, or many UTC times`；官方對本尊行為沉默，且 `82` §15 的量測環境是全年 +08:00
的香港 ⇒ **本尊在 DST 下的行為未取得**）：
- **零個自洽候選＝不存在的牆鐘時間** ⇒ `Math.max(candidates)`，語義是**跳躍後的時刻**。
- **多個自洽候選＝重複的牆鐘時間** ⇒ `Math.min`，語義是**較早**那一個。

三個時區實測一致：NY 02:30→03:30、London 01:30→02:30、Sydney 02:30→03:30（gap）；
NY→`05:30Z`、London→`00:30Z`、Sydney→`15:30Z`（重複，皆為較早那一個）。

⚠️ **2026-08-27 更正**：本節原本寫的是「兩次迭代」，並宣稱上面兩條是它的自然結果。
那是錯的——程式碼**根本沒實作任何裁定**，落點只是偏移正負號的副產物，
而那兩條敘述**只在 UTC 以西成立**。完整證據見下方「對抗性審查」節。

## 逐個交付（鐵律 12.4 的四件事）

### `Query.shop.ianaTimezone`

①本店的 IANA 時區。②本尊 `Shop` 有**四個**時區欄位、**沒有**叫 `timezone` 的
——我方照抄 `ianaTimezone`，另外三個（`timezoneAbbreviation`／`timezoneOffset`／
`timezoneOffsetMinutes`）**刻意不出**：它們都是「時區名 ＋ 某個時刻」導出的值，
出一個「現在的偏移」給前端拿去標未來時刻，跨 DST 就是錯的。
③🔴 **來源是 `shops.timezone` 不是 `staff_members.timezone`**——兩張表都有同名欄位、
default 都是 `Asia/Hong_Kong`，**拿錯在 default 環境下 100% 測綠**；help 明文時區來源是
Store defaults，本尊設定頁也逐字證實店鋪級與使用者級並存。
④授權沿用 `authorize_products!`；日後若加入與商品無關的欄位必須改成該欄位自己的 policy。

### `Popover`（非模態浮層原語）

①portal 到 `document.body` 的浮層，錨定在觸發元素旁。②與 `Modal` 的差別：
**沒有 scrim、不 inert 背景、沒有 focus trap**。③portal 是必要的不是偏好——放在 `Modal`
或表格容器裡的浮層會被祖先 `overflow` 裁切；本尊同樣 portal 到 modal 之外
（§15.1 判定式證據 `modalDialog.contains(popoverOverlay) === false`）。
④`Modal` 的 Escape 契約、S6c／S6d。

🔴 **關閉語義兩條分開裁定**：

| 行為 | 本尊 | 我方 | 理由 |
|---|---|---|---|
| 點浮層外 | 點 modal 內**不關**（只能按 Cancel） | **照抄不關**（`dismissOnOutsideClick` 預設 false） | 行為差異，不是缺陷 |
| **Escape** | 🔴 popover ＋ modal **一起關**，且 modal 內未存的改動**全被丟棄**（§15.2 重現 2 次，無確認） | **只關 popover** | **資料遺失缺陷**；且 `Modal.tsx` 檔頭本來就明文「Escape 尊重 `defaultPrevented`（內層 popover 先關自己）」，照抄等於主動破壞既有的正確行為 |

### `Calendar`（月曆 grid）

①一個月的日期網格 ＋ 上下月切換；本尊形態 `‹ August 2026 ›` ＋ **Sun–Sat** 表頭、
當日之前灰掉。②ARIA 照 APG：`<table role="grid">`、日期格 `<td>`、roving tabindex、
`aria-selected` **全網格唯一**、不可選用 `aria-disabled` 保留可聚焦。十三條鍵盤全實作
（Tab／Shift+Tab 除外——我方是 popover 不是 dialog，沒有 focus trap）。
③🔴 **月份游標獨立於 `value`**（§15.3：打字選了非當月日期時月曆**不跳頁**）；
🔴 **`today` 由呼叫端用店鋪時區算好傳入**，本元件不碰 `Date.now()`。
④`SchedulePopover`；日後任何日期選擇面。

🔴 **2026-08-28 修正：跨月聚焦不得依賴 `requestAnimationFrame`。**
初版的 `moveFocus` 同月同步聚焦、**跨月排進 rAF**。跨月時 `<td key={day}>` 全部換 key
⇒ 被聚焦的舊格被卸載 ⇒ `document.activeElement` 掉回 `document.body`；而 `handleKeyDown`
逐格掛在 `<td>` 上、不在 body 的祖先鏈上 ⇒ **該窗口內按下的鍵被整個吞掉**
（使用者連按或鍵盤 auto-repeat 兩次 PageDown 只生效一次，WCAG 2.1.1）。
現改為 `useLayoutEffect` 在 DOM 變更後、繪製前同步聚焦，同月／跨月走同一條路徑。
根因調查與量測＝`docs/worklog/2026-08-28-Calendar跨月聚焦競態.md`。

⚠️ **兩處刻意的冗餘與偏離，各自登記**：
- **顯式寫 `role="gridcell"`**：ARIA in HTML 規定 `<td>` 在 `role=grid` 下隱含 gridcell，
  但那條**上下文推導依賴實作**——`dom-accessibility-api`（testing-library 的 role 計算）
  就沒做，會算成 `cell`。顯式寫讓語義不依賴推導完整度。
- **`aria-current="date"` 與 `aria-selected` 並存＝ours**：APG 的 date picker 範例
  **完全不含** `aria-current`（全文查證），MDN 只警告「不要拿它**取代** `aria-selected`」，
  **沒有正面授權兩者並存** ⇒ 無第一方背書。
- **`aria-disabled` 用在日期格**：APG 範例沒有 disabled 日期，這條是從
  Developing a Keyboard Interface 的通則推到本情境，不是範例級證據。

### `SchedulePopover`（排程內容面）

①日期欄／時間欄（右側內嵌時區徽章）／月曆／頁尾三顆鈕。②值域照 §15.3／§15.4：
日期欄**可打字但只吃 ISO**、錯誤**靜默回退**（本尊無錯誤訊息）；時間欄 12 小時顯示、
24 小時輸入也吃、下拉 30 分鐘刻度**但打字不吸附**。
③🔴 **選「今天」時的過去時間被靜默夾到 now**——本尊的決定性實測是先設 `11:00 PM`
再打 `1:00 PM`，blur 後值變成**當下時刻**而非回退到 `11:00 PM`
⇒ 那是「夾到 now」不是「回退上一個有效值」，**兩者只有這個順序分得出來**。
④`values.publicationDelta` 的排程欄（S6b-2b）、送出的 `publishDate`。

🔴 **`Remove schedule` 的終態是「立即發布」不是「清空」**（§15.7 抓包）：
本尊送 `publishDate: <當下時刻>` 而不是 null ⇒ 該管道變成已發布。
本元件因此做成 `onApply(now)`，不是 `onApply(null)`／`onRemove()`。
啟用條件是「已**儲存**的排程存在」，不是「本次編輯有值」。

## 測試

75 格：`app/frontend/admin/lib/timezone.test.ts` 19 ／ `Calendar.test.tsx` **22** ／
`SchedulePopover.test.tsx` 25 ／ `Popover.test.tsx` 9。
後端 `spec/requests/shop_timezone_query_spec.rb` 3 格。全套前端 271／0，rspec 見 worklog。

> 逐檔複驗：`npx vitest run <該檔>`（數字為 2026-08-28 快照）。
> `Calendar.test.tsx` 由 18 增為 22 ＝ 跨月聚焦競態修復新增的四格，見下方變更記錄。

**突變逐個實跑**：

| 突變 | 轉紅的格 |
|---|---|
| MB1 時區改讀 `staff_members` | 店鋪級時區 |
| **MT1 把牆鐘當 UTC 只解一次** | **DST 前跳日**（唯一殺得掉它的形態） |
| MT2 偏移標籤用 `Date.now()` | 同時區不同目標時刻 |
| MT3 拿掉日期存在性檢查 | 2 月 30 日 |
| MT4 拿掉 12 小時制範圍檢查 | `13:00 PM` |
| MC1 換月不夾到月底 | 1/31 → 2/28 |
| MC2 Home 改成月初 | Home／End 是本週 |
| MC3 `aria-selected` 給所有格 | selected 唯一 |
| MC4 disabled 日可點 | 灰掉的不觸發 |
| **MS1 時間不夾到 now** | **夾到 now vs 回退** |
| **MS2 `Remove` 送 0 而非 now** | **終態＝立即發布** |
| MS3 `nowWall` 改用 UTC | 夾到 now ＋ slots 過濾（2 格） |
| MS4 slots 不過濾 | 今天只給剩餘的 |
| **MS5 `normalize` 回退成字串比較** | **夾到 now ＋ 前跳日**（2 格） |
| MS6 Done 不判 dirty | 回撥日第二輪 |
| MS7 slots 不濾 gap | 下拉不得列出不存在的牆鐘 |
| MC5 roving 不更新 | tabindex 跟著焦點移動 |
| **MP1 不移入焦點** | **開啟時焦點 ＋ Modal 內鍵盤可達**（2 格） |
| **MP2 Escape 改回 bubble 階段** | **焦點在觸發鈕時只關 popover** |
| MP3 移除 Tab 循環 | 面板內 Tab 循環 |
| MP4 portal 目標改成面板自己 | portal ＋ 點外 ＋ 焦點 ＋ Tab（4 格） |
| MB2 移除 `authorize_products!` | 無權限員工讀不到 |

⚠️ **MT5（`% 24`）預期內殺不掉**：`hourCycle: "h23"` 規範上就回 0–23，那個取模是
跨引擎的防禦，**現有測試證明不了它必要**——已在程式碼註釋誠實登記。

🔴 **MS3 沒殺掉「預設值用店鋪時區」那一格，而那是我測試描述的問題**：那格驗的是
`initial`（預設值）、MS3 改的是 `nowWall`（下限基準），**兩條不同路徑**。
已補一格真的驗 `nowWall` 的（月曆的 today 與灰掉範圍），並更正原格的描述。
與 S6b 的 M11 同型：**測試的描述必須對得上它真正走到的那條路**。

## 對抗性審查（2026-08-27，初始候選推出前）

五維度 fan-out（時區正確性／APG 契約／Popover 生命週期／測試假綠／對齊本尊），
每個 finder 在 prompt 內就被要求**實跑驗證**（`node -e`、vitest 突變）。**42 條 finding**，
其中 10 條 🔴 **全部修復**。三條最值得記：

### 🔴 兩條「ours 裁定」在半數時區是反的，而且程式碼**根本沒實作裁定**

初版寫「不存在的牆鐘時間往後推、重複的取較早」並宣稱那是兩次迭代的自然結果。
審查掃了**全部 418 個 IANA 時區 ×2025–2031 的所有 DST 轉換點**，實跑證實：
「往後推」在 **57 個時區是往回推**（1352 個牆鐘格）、「取較早」在 **73 個時區取的是較晚**
（1772 個牆鐘格）。落點只是**偏移正負號的副產物**，而唯一同時符合兩條敘述的是 UTC 以西
——也就是當時測試唯一覆蓋的 `America/New_York`。

⇒ 改成**顯式**裁定（候選集合 ＋ 自洽性檢驗），行為在所有時區一致，並補了 London／Sydney 的正反格。

### 🔴 `Popover` 在 `Modal` 內鍵盤完全不可達

`Modal` 的 Tab trap 只用 `.cl-modal` 內的 focusables 算 first/last，而 `Popover`
portal 在它**之外** ⇒ 焦點永遠進不來（審查實跑：連按 Tab 12 次只在 modal 的兩個元素間循環）。
同一根因還有兩條：焦點停在觸發鈕時按 Escape 會關掉整個 `Modal`（React 合成事件沿
fiber 樹傳播，到不了 portal 出去的 popover），以及 Tab 會逃出 `Modal` 的焦點鎖。

⇒ 三件事一起修：焦點入口、**capture 階段**的 Escape、面板內 Tab 循環。

### 🔴 vitest 沒有釘 TZ，整套時區前提在這台機器上是空的

dev doc 明文列了「三個在香港測不出來的陷阱」，但 runner 的 TZ 是 `Asia/Taipei`
——與測試用的 `Asia/Hong_Kong` **偏移完全相同**（都 +08:00、都無 DST）。
而且 `SchedulePopover` 的 15 格**全部**用香港，dev doc 卻宣稱「測資主力刻意用
America/New_York」（那只對 `app/frontend/admin/lib/timezone.test.ts` 成立）。

⇒ `vite.config.ts` 釘 `test.env: { TZ: "UTC" }`，並補三格 NY 的 DST 日測試。

### 其餘已修的 🔴

| # | 問題 | 修法 |
|---|---|---|
| 2 | listbox 48 個 option 全在 Tab 序列、Enter／方向鍵一律無效 | APG combobox：`<li role="option">`＋`aria-activedescendant`＋鍵盤 |
| 3 | 日期欄 blur 不正規化成長格式（與 §15.3 實測相反，而註釋自稱有做） | blur 顯示長格式、**聚焦切回 ISO**（後者是刻意偏離，避開本尊「顯示格式回打不進去」的 quirk） |
| 4 | `Done` 未做「未改動時 disabled」，無操作也能送出一筆等於 now 的排程 | 牆鐘值比對的 dirty 判準 |
| 5 | 彈層重開不重置（本尊 §15.10 是完全重置） | 移除 `open` prop，改**呼叫端條件渲染** |
| 8/12 | roving tabindex **不 roving**，焦點移動後 `tabindex=0` 停在舊格 | 改成 state，跟著 `moveFocus` 走 |
| 30/31/32 | 「不早於 now」比**牆鐘字串**，而牆鐘→instant 在 DST 日不單調 ⇒ 送出早於 now 的值、顯示 ≠ 實際、重開平移 ±60 分 | 全部移到 **instant 域**＋正規化回寫 |

🔴 **#4 與 #32 的判準互相牽動**：用「碰過沒」的旗標擋不住「改了又改回」；用 instant 比對
**在重複小時已經平移**，會把「改回原值」誤判成已改動。最後用**牆鐘值比對**才同時成立。

### 順手修掉一個自己造成的破壞

插 `def shop` 時把 `shop_locales` 的 YARD 註釋切走了 ⇒ `def shop` 帶兩個 `@return`、
`shop_locales` 變成無文檔。已歸位。

## 已知限制與 TODO

- 🔴 **本包不含接線**（S6b-2b）：發布 modal 的日曆 icon、`publishDate` 送出、
  發布卡的排程 badge。⇒ **本包合併後使用者看不到任何新功能**，這是刻意的拆包。
- 🔴 **鐵律 13 的三寬度對比未做**：憑證腳本 `scripts/rwd-check.mjs` 尚未建立（PR-C0）
  ⇒ **不對任何寬度做 PASS 宣稱**。`Popover` 的定位在小視窗會翻到錨點上方，
  但那只有本地推理，沒有量測憑證。
- ⚠️ **`Popover` 不做完整的碰撞偵測**：只做「下方放不下就翻上方」與左右夾住視窗。
  個位數情境夠用；日後若有貼邊的複雜情境要重做。
- ⚠️ **`publishDate` 只送 UTC instant，沒有時區名**——與本尊一致
  （本尊 `publishDate` 也是 ISO8601 instant，無時區欄）。
  🔴 RFC 9557 §1.2 逐字指出「UTC 偏移不適合做本地時間運算」、未來時刻若該時區的 DST
  規則在到點前改變，商家設定的牆鐘時間就跑掉了。**依鐵律 12 不偏離本尊**，登記為已知限制。
- ⚠️ **`82` §15.11 登記 6 條未取得**，其中 S6b2-U1／U2（改店鋪時區後徽章是否跟著變、
  徽章來自店鋪級還是使用者級）需要**使用者本人同意後**才能實測——實測方正確地停在這裡。
- ⚠️ **後端不擋過去的 `publishDate`**：`Publications::Write.validate_publish_date` 只在
  `scheduled?`（未來）時才走能力與型別檢查，過去時間直接當「立即發布的時刻」寫入。
  本尊 API 層擋不擋＝**未取得**（`82` §12.6 的 S2-U2）⇒ 我方 UI 擋、後端不改。

## 變更記錄

- 2026-08-27 S6b-2a 初版：時區地基與三個原語。
