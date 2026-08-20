# 53 — UI／交互缺口複查（49 號第二版・修完後重跑）

> **這份文件是 `docs/specs/49-ui-gap-register.md` 的第二次機械比對。** 49 號原始版本（483 行）的四張表與 P0 清單原封不動保留在該檔，本檔只出結果與差異。
>
> **重跑方法與 49 號完全相同**（數字才可比）：
> - `grep` / `python re` 掃三份原型的 CSS 選擇器、`data-doc` 註釋鍵、路由表（`MODULES` / `DETAILS` / `SET_PAGES` / `NAV`）、九態選擇器與 ARIA 屬性計數。
> - 額外加一層 49 號沒有的驗證：**Chromium 實跑**（Playwright 1.56 / `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`），把「靜態有字串」與「執行時真的會動」分開判。凡是靠 grep 判不出來的（focus trap、aria 同步、聯動、鍵盤操作、URL 狀態），一律以實跑結果為準。
> - 基準快照取 commit `e50b912`（49 號成文當下的三份原型），與工作區當前版本逐項對拉。
>
> **比對來源（行數變化）**
> | 代號 | 檔案 | 49 號當時 | 現在 |
> |---|---|---|---|
> | **A** | `docs/design/chilllove-admin-v2.html` | 4700 | **7299** |
> | **P** | `docs/design/chilllove-platform-admin.html` | 1798 | **1933** |
> | **S** | `docs/design/chilllove-storefront-v2.html` | 3707 | **3810** |
>
> **狀態變化定義**
> - **已修復** = 49 號判為缺口，現在有可驗證的真實作（靜態＋實跑都過）
> - **部分修復** = 缺口縮小但未消（例如控件真了但結構仍缺、或只有靜態沒有行為）
> - **仍缺** = 與 49 號同判，無實質變化
> - **新增缺口** = 49 號沒記、本輪改動造成或本輪才查出的

---

## 0. 缺口數對照總表

| 表 | 檢查項 | 49 號（第一版） | 本次（第二版） | 淨變化 |
|---|---|---|---|---|
| 表 1 · 頁面級 | 133 列 | **84**（完全缺 41／佔位 43） | **57**（仍缺 48／部分修復 9） | **−27** |
| 表 2 · 元件級 | 32 元件 ＋ 47 號點名 13 項 | **32**（完全缺 8／佔位或缺態 24） | **32**（完全缺 **5**／佔位或缺態 27）<br>※ 同一把尺：仍**無一元件**達到九態＋鍵盤完整 | **0**（但完全缺 −3，13 項點名 −7） |
| 表 3 · 交互邏輯 | 66 條 | **54**（未實作 40／佔位 14） | **40**（未實作 26／佔位 14） | **−14** |
| 表 4 · 反向缺口 | 28 列 | **28** | **27**（−2 已解決、+1 新增） | **−1** |
| §5 · 文件自相矛盾 | 7 條 | **7** | **6**（F-05 部分解、F-02/03/04 原型已裁定但 48 未同步） | **−1** |
| **表 1–5 小計** | | **205** | **162** | **−43** |
| **P0** | 22 條 | 全開 | **已解決 8／部分 4／未解決 10** | — |
| **§6 回歸風險（新章）** | — | — | **7 項**（其中 1 項為實質功能遺失） | +7 |
| **§9 新發現（新章）** | — | — | **11 項** | +11 |
| **全文件口徑** | — | — | **180**（表 1–5 小計 162＋§6 七列＋§9 十一列） | — |

全文件口徑複驗：`ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/53-ui-gap-recheck.md"); p({section_6:s.scan(/^\| \*\*R-\d{2}\*\* \|/).size,section_9:s.scan(/^\| \*\*N-\d{2}\*\* \|/).size})'`；
162 是原四表加 §5 的既有小計，不再稱為全文件合計。

> **表 2 為什麼淨變化是 0**：49 號的計數規則是「32 個元件無一達到 48 的九態＋鍵盤完整度 → 缺口 32」。這一輪雖然修了很多**單一態**（disabled、focus 環、pip、shake、計數器、`aria-disabled`），但 `:active` 全站仍只有 1 條規則（A:301）、`aria-busy`／`aria-invalid`／`aria-sort` 在 A 仍為 **0**、`read-only` 態仍無任何元件有 → 用同一把尺量，沒有任何元件跨過門檻。**要看真實進度請看「完全缺 8→5」與「47 號點名 13 項」那兩列。**

---

## 表 1 · 頁面級缺口（第二版）

> 只列 49 號判為缺口的 84 列＋狀態有變動的列。49 號判「已實作」的 48 列另做回歸抽查，結果見 §6。

### 1-A 全域外殼與首頁（8 列，缺口 1 → 1）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| Pulse 每格深連 `?ql={ShopifyQL}` | 佔位 | `?ql=` A **0 命中**；`.p-item` 仍為 `<div>` | **仍缺** |

### 1-B 訂單（14 列，缺口 9 → 9）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 篩選 18 類分類選單 | 完全缺 | `18 類`／`FILTER_CATS` 0 命中 | **仍缺** |
| 依 fulfillment order 分卡 | 完全缺 | A:1966 仍是單一出貨卡；`fulfillmentOrders`／`foGroups` 0 命中 | **仍缺** |
| 追蹤連結（URL＋單號 兩段式） | 完全缺 | A:1978 仍是純文字「已出貨・黑貓宅急便 903-…」 | **仍缺** |
| `更多動作` 可搜尋操作 | 佔位 | `搜尋操作` 0 命中；`orderMore()` A:5395 仍固定列表 | **仍缺** |
| 側欄「其他詳細資訊」 | 完全缺 | 0 命中 | **仍缺** |
| 側欄「轉換詳細資訊」 | 完全缺 | 0 命中 | **仍缺** |
| 收件地址「檢視地圖」 | 完全缺 | 0 命中 | **仍缺** |
| 運送列展開重量拆解 | 完全缺 | 0 命中 | **仍缺** |
| 時間軸依日分組＋actor＋展開 | 佔位 | A:2001 仍是硬字串 `最近`；`tl-actor`／`tlToggle` 0 命中 | **仍缺** |

### 1-C 產品（10 列，缺口 3 → 3）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 列表最後一欄「操作」 | 完全缺 | 0 命中 | **仍缺** |
| 富文本工具列 `A⌄`／`表格⌄` | 佔位 | A:3490 工具列仍是 `['B','I','U','H2','•','1.','🔗','⌗']` | **仍缺** |
| 庫存四欄（含「無法供貨」）＋調整記錄 | 佔位 | `無法供貨`／`調整記錄` 0 命中 | **仍缺** |

### 1-D 顧客／成長／折扣／市場（13 列，缺口 6 → 5）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 副導航「公司」（B2B） | 完全缺 | `m-companies` A:6727 掛進 `MODULES`；側欄實跑可見「公司」項；`companiesPage()` 空態含四支柱 `.pillars` A:1425 | **已修復** |
| 成長頁頂部推廣橫幅（截圖＋✕） | 完全缺 | A:4134 的 `.ai-row`「Campaign Autopilot 搶先體驗」**基準版就有**，不是 44 §5 的推廣橫幅（無產品截圖區） | **仍缺** |
| 市場雙欄左樹狀導航 | 佔位 | `mk-tree`／`地區資料夾` 0 命中 | **仍缺** |
| 市場 `圖表檢視` | 佔位 | A:4596 仍 `toast()` | **仍缺** |
| 市場 `推出 launches` / `地區` tab | 完全缺 | 0 命中 | **仍缺** |
| 市場詳情父子繼承模型 | 佔位 | `繼承的設定`／`上層市場` **基準 0、現在也 0**；`marketPage()` A:4618 仍平鋪表單 | **仍缺** |

### 1-E 設定 overlay（26 列，缺口 24 → 10）

| 分頁 | 49 號 | 證據（實跑：`.set-body` 內真控件計數） | 狀態變化 |
|---|---|---|---|
| 設定搜尋框 | 佔位 | `.set-search` 實跑 `tagName=DIV`、`hasInput=false` | **仍缺** |
| `跳至內容` skip link | 完全缺 | A/P 0 命中（S:1142 有 `.skip`，基準版就有） | **仍缺** |
| 組織 org | 佔位 | tgl 1／sel 1／inp 1／rowbtn 1 | **已修復** |
| 角色（獨立子頁 `/roles`） | 佔位 | 仍併在 users 內；6 條 permCats 列有 `›` 卻無 handler | **仍缺** |
| 安全性（獨立子頁） | 佔位 | 仍併在 users「安全」段 | **仍缺** |
| 一般 general | 佔位 | sel 3／inp 3／唯讀 2 | **已修復** |
| 方案 plan | 佔位 | 破壞性 2（`setRowDanger` ＋ `confirmDanger`）、`使用中` 鈕 disabled＋`aria-disabled` | **已修復** |
| 帳單 billing | 佔位 | sel 2／rowbtn 1（`openBillCards()`）／唯讀 1 | **已修復**（但見 §6 R-01） |
| 付款 payments | 佔位 | sel 1／inp 1／rowbtn 2／add 1（`openManualPay()` 次級視圖實跑 293 字元） | **已修復** |
| 結帳 checkout | 佔位 | tgl 5／sel 7／inp 1／rowbtn 2；`openCkFields()` 次級視圖實跑 518 字元 | **已修復** |
| 顧客帳號 accounts | 佔位（舊 4 條 `setRow` 未被覆寫） | tgl 2／sel 3／唯讀 1；覆寫問題已消 | **已修復** |
| 運送與配送 shipping | 佔位 | rowbtn 6／add 2；`openShipProfile()` 實跑 583 字元 | **已修復** |
| 稅額與關稅 taxes | 佔位 | tgl 1／sel 1／inp 3／rowbtn 1；DDP 相依 banner 實跑會開合 | **已修復** |
| 地點 locations | 佔位 | tgl 3／rowbtn 1（出貨優先序次級視圖）／add 1 | **已修復** |
| 應用程式 apps | 佔位 | app 列有真的解除安裝（`confirmDanger`）；**銷售管道 4 列仍是有 `›` 無 handler** | **部分修復** |
| 銷售管道（獨立分頁） | 完全缺 | `data-set="channels"` 0 命中 | **仍缺** |
| 網域 domains | 佔位 | tgl 1 ＋ 兩顆真動作鈕 | **已修復** |
| 顧客事件 events | 佔位 | 實跑：2 列靜態 ＋ 1 顆 `toast()` 鈕，**0 個真控件** | **仍缺** |
| 通知 notifications | 佔位 | tgl 15（`role=switch`＋`aria-checked`，訂單確認 `disabled aria-disabled`）／rowbtn 3；**仍 15 條平鋪、無 12 分組** | **部分修復** |
| 自訂資料 customdata | 佔位 | rowbtn 1；4 條定義列仍是假 `›` | **部分修復** |
| 語言 languages | 佔位 | tgl 3（繁中鎖定 `disabled aria-disabled`） | **已修復** |
| 政策 policies | 佔位 | rowbtn 2／add 1；第一張卡改成退貨與取消規則 | **已修復** |
| 顧客隱私 privacy | 佔位 | tgl 3／inp 1／rowbtn 1 | **已修復** |
| 帳號（導向 accounts 平台） | 完全缺 | 0 命中 | **仍缺** |

**1-E 小結**：已修復 14／部分修復 3／仍缺 7 → 缺口 24 → **10**。

### 1-F 設定內層頁與 modal（20 列，缺口 18 → 12）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 結帳設定檔（多實體＋`使用中` badge＋上次儲存時間） | 完全缺 | `CK_PROFILES` A:6740；`ckProfileCard()` A:6743 有 2 份設定檔、`使用中`／`未使用` chip、`上次儲存：今天 10:24` | **已修復** |
| 「加入購物車數量上限」modal | 完全缺 | `購物車數量上限` 0 命中 | **仍缺** |
| 結帳規則引擎（商品限制／年齡驗證） | 完全缺 | `結帳規則`／`年齡`／`商品限制` 在 A、S **皆 0** | **仍缺** |
| 進階偏好 · 地址蒐集 | 完全缺 | 只在 DOCS 註釋 A:7006，**無控件** | **仍缺** |
| 稅務服務三檔 `managed/basic/manual` | 完全缺 | `service_tier` 只出現在 DOCS A:7048–7049；`taxesPage()` A:5140 無 tier 控件 | **仍缺** |
| 海關資訊（以子類批次設 HS／原產地） | 完全缺 | A:5148 有 DDP 相依警示 banner 提到此規則，但**沒有批次設定入口** | **部分修復** |
| 額外設定 3 個 checkbox | 完全缺 | 只有「價格含稅」toggle A:5143；運費稅／數位商品 VAT 仍只在 DOCS | **部分修復** |
| 地點方案配額「200 個，已用 1」＋POS tabs | 完全缺 | A:5157 顯示「已使用 N 個地點（配額依方案，見 limits.yml）」——**沒有上限值**、`POS 訂閱` 0 命中 | **部分修復** |
| 退貨與取消規則卡（政策頁第一張卡） | 完全缺 | A:5456–5476；含「預設規則／未設定規則／⊕ 新增規則」多規則結構 | **已修復** |
| 規則編輯頁 `/legal/cancel-return-rules/{id}` | 完全缺 | `openReturnRule()` A:5498、`returnRulePage()`；兩 toggle ＋ 最終銷售卡 ＋ 購買時點快照提示 A:5530 | **已修復** |
| 政策的 `● 自動` 第三態 | 完全缺 | `chip('自動',…)` 3 處 | **已修復** |
| 通知範本 45+／12 分組／`toggleable` | 佔位 | A:5163–5166 仍 15 條；`toggleable` 已為真 toggle | **部分修復** |
| 出貨要求通知（第三類別） | 完全缺 | `出貨要求` 0 命中 | **仍缺** |
| Webhook 支援 XML＋JSON | 佔位 | `setRowSel('格式',…[json,xml])` A:5829；新增流程也寫 JSON／XML A:5172 | **已修復** |
| 運送外層 accordion＋當前值摘要行 | 完全缺 | 四個子區塊都在了（依市場運送選項／本地配送／店面取貨／包裹與文件＋carrier 帳號），但**無 accordion、無「預計配送日期」** | **部分修復** |
| 運送設定檔內層（zones／rates／carrier） | 完全缺 | `openShipProfile()` A:5603；`shipping_profile→zone→rate` A:5583；rate 兩型 manual／carrier；carrier 列 `aria-expanded` 展開 `services[]`（實跑通過） | **已修復** |
| 爬蟲存取權（HTTP Message Signatures） | 完全缺 | 0 命中 | **仍缺** |
| 取貨點 pickup points | 完全缺 | 「超商取貨」以 rate 形式出現在運送設定檔 A:5588，**但沒有 44 §15 的取貨點設定頁** | **部分修復** |

**1-F 小結**：已修復 6／部分修復 6／仍缺 6 → 缺口 18 → **12**。

### 1-G 內容／分析／線上商店（29 列，缺口 13 → 11）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| B2B · 公司列表（空態四支柱） | 完全缺 | `companiesPage()`；實跑空態四支柱文案完整 | **已修復** |
| B2B · 新增公司表單 | 完全缺 | `d-company-new` 路由 ＋ `.form1` 單欄 630px A:1205；六個維度全掛在 **location** 上（A:6108–6113 每筆 location 各帶 `catalog / profile / terms / taxId / tax / submit`） | **已修復** |
| listbar 尾端第二個 `⋯` | 完全缺 | `list-more` 0 命中 | **仍缺** |
| 財務 2FA 閘門 | 佔位 | A:4692 仍是可忽略的 inline banner；實跑財務頁「可用餘額 NT$38,420／撥款排程」照常渲染 | **仍缺** |
| 主題卡雙預覽（桌機＋手機框） | 佔位 | 0 命中 | **仍缺** |
| 主題版本更新可展開 | 佔位 | 0 命中 | **仍缺** |
| AI 主題生成器輸入框 | 佔位 | 0 命中 | **仍缺** |
| 匯入 `⌄` split（檔案／URL） | 佔位 | `從 URL` 0 命中 | **仍缺** |
| 報告 `類別` popover 多選＋13 類 | 佔位 | `REP_CATS` A:4741 仍 **11 類**（＋「全部」）；仍是單選 `<select>` | **仍缺** |
| 頁面列表雙層警示 banner | 完全缺 | `banner2`／`banner-hd` 0 命中 | **仍缺** |
| 頂層 404 | 完全缺 | A 無 404 視圖 | **仍缺** |
| 區段內 404 | 完全缺 | 0 命中 | **仍缺** |
| 探索建構器 | 佔位 | `探索建構` 0 命中 | **仍缺** |

### 1-H 結帳與帳號編輯器（6 列，缺口 6 → 2）

| 頁面／面板 | 49 號 | 證據（含實跑） | 狀態變化 |
|---|---|---|---|
| 編輯器殼層 top bar | 完全缺 | `#ckEditor` A:1725；`ckMount()` A:6416；實跑：`⇤ 離開／🏪 結帳 ⌄／「CHILL LOVE」設定／🖥 桌機 📱 手機／⋯／儲存`，儲存鈕初始 `disabled aria-disabled="true"`，`ckDirty(true)` 後兩者同步變 false | **已修復** |
| 頁面選擇器 bottom sheet（6 頁分組） | 完全缺 | `ckOpenPicker()` A:6565；實跑 `.ck-pick.show` 列出 結帳／購買後（感謝您）／顧客帳號（登入・訂單・訂單狀態・個人資料）共 6 頁 | **已修復** |
| 左欄圖層樹（section／block／`›`／`⌄`／`👁`） | 完全缺 | 實跑 `.ck-node` **19 個**；`ckExpand`／`ckEye`／`ckSelect` 齊備 | **已修復** |
| 預覽區選取態＋`⊕ 新增區塊` popover 空態 | 完全缺 | `ckAddPop()` A:6580；預覽節點 `role=button` ＋ canvas 事件委派 Enter／Space（A:6421–6425） | **已修復** |
| 帳號「訂單」頁商店抵用金**藥丸**（S） | 佔位 | S 仍是卡片內區塊，非頁首藥丸 | **仍缺** |
| 帳號頁的「公告列」區段（S） | 佔位 | `.announce` 仍是站台級 | **仍缺** |

### 1-I 前台（5 列，缺口 3 → 3）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 自助退貨依履行狀態分成退貨流／取消流 | 佔位 | `取消要求` S **0 命中** | **仍缺** |
| final sale 命中即不出現退貨入口 | 佔位 | S 仍只有 1 處 `final sale` 註釋文字 | **仍缺** |
| age gate 移到結帳規則 | 完全缺 | A、S 皆 0 | **仍缺** |

### 1-J 平台後台（2 列，缺口 1 → 1，**惡化**）

| 頁面／面板 | 49 號 | 證據 | 狀態變化 |
|---|---|---|---|
| 帳單發票 7 態 tabs | 佔位（A 有 3 列發票、無 tabs） | **A 的 3 列發票表現在也看不到了**——`billingPage` 被重複宣告覆蓋，`go('m-billing')` 實跑渲染出的是設定分頁的帳單卡片。詳見 §6 R-01 | **仍缺（且惡化）** |

**表 1 總計：84 → 57**（已修復 27／部分修復 9／仍缺 48；部分修復仍計為缺口）

---

## 表 2 · 元件級缺口（第二版）

### 全域硬事實（同 49 號的四張計數表，前後對照）

| 事實 | A 前→後 | P 前→後 | S 前→後 |
|---|---|---|---|
| `:active` 態規則數 | 0 → **1**（A:301 `.btn-sec/.btn-ter`） | 0 → 0 | 0 → 0 |
| `aria-busy` | 0 → 0 | 0 → 1 | 0 → 1 |
| `aria-invalid` | 0 → **0** | 0 → 0 | 0 → 0 |
| `inert` | 0 → **0** | 0 → 0 | 0 → 0 |
| `aria-disabled` | 0 → **41** | 0 → **8** | 3 → **18** |
| `aria-sort` | 0 → **0** | 0 → 0 | 0 → 0 |
| `role="switch"`＋`aria-checked` | 10／0 → **9／8** | 4／0 → 4／5 | 3／0 → 3／9 |
| `sr-only`／`visually-hidden` | 0 → **0** | 0 → **0** | `.vh` **6 用（基準就有）** |
| shake 動畫接上 modal | 無 → **`clShake()` A:2764，`formSave()` A:2771 驗證失敗時抖 modal／palette／savebar** | 無 | 無 |
| 髮絲線 dpr 換算 | 無 → **`--hairline` A:86 ＋ 1.5/2 dppx 覆寫 A:182–183**（實跑 dpr2 → `.5px`，實體邊框 1px） | 無 → 有（P:169–170） | 無 → 有（S:94–95） |
| `em` 斷點 | 全 px（9 條） → **全 em（15 條），px 斷點 0** | 全 px（4） → **全 em（4）** | 全 px（7） → **全 em（7）** |
| `transition:all` | 0 | 0 | 0 |
| 硬寫 `1px solid` 邊框 | → **0**（style 與 markup 皆 0） | → **0** | → **0** |
| 硬編 `z-index:數字` | 19 → **0**（`--z-*` A:127–135，510–520 帶） | 8 → **0** | 24 → **9**（餘為 `z-index:1/2` 區域堆疊） |

> **結論不變的四態**：`active`（僅 1 條）、`loading`（`aria-busy` A 仍 0）、`error`（`aria-invalid` 全 0）、`read-only`（無任何元件有），以及 **focus trap／焦點還原／`inert`**，在三份原型基本仍全缺。

### 32 元件狀態變化（只列有變動與完全缺者）

| § | 元件 | 49 號 | 現況 | 狀態變化 |
|---|---|---|---|---|
| 1 | 按鈕 `cl-btn` | disabled 做法錯、無 active | A:294 只降文字色（`opacity` 已移除）；A:301 有 `:active`；`aria-disabled` 41 處 | **部分修復**（`loading`／`aria-busy`／`Space` preventDefault 仍缺） |
| 2 | 輸入框 | 用 `border` 非 inset | A:336 `border:0` ＋ `inset 0 0 0 var(--hairline)`（47 §H2-4 落地）；A:863 錯誤態改 inset | **部分修復**（`aria-invalid` 仍 0） |
| 4 | Checkbox | 15px、無 32/44 命中區、≤429 放大本體 | A:411 `16px` ＋ A:419 `::before{inset:-8px}`＝32px；A:821–822 ≤429 `inset:-14px`＝44px，**本體不放大** | **已修復**（48 #86） |
| 5 | Radio | 走原生 | A:413–416 `.cl-radio` 自訂控件（含 `:checked` inset） | **部分修復**（roving tabindex 仍缺） |
| 6 | Toggle | 無 `role=switch`／`aria-checked` | A:2318 `setRowTgl` 一律帶 `role="switch" aria-checked`；實跑真點擊後 `aria-checked` 同步翻轉 | **部分修復**（`loading` 樂觀回滾／`error` 仍缺） |
| 11 | Badge | 三形只做兩形、`chip()` 恆實心 | A:316–320 `pip`／`.full`／`.blocked`(⊘ 斜線)；A:2074 `PIP_SHAPE` 依語意族推導、A:2075 `chip()` 支援覆寫。實跑訂單頁：已付款=●、未出貨=○、待付款/部分出貨=⊘ | **已修復**（`sr-only` 補充語意仍缺） |
| 13.2 | 堆疊卡片 `cl-cardgroup` | CSS 有、0 使用 | A:1104–1108、P:248–252 **仍 0 次 markup 引用** | **仍缺（死 CSS）** |
| 14 | CollapsedEditCard | 完全缺 | `cec`／`CollapsedEdit` 0 命中 | **仍缺** |
| 15 | Accordion | A 完全缺 | `.m-accordion` 已真用於 `nav-subs`（A:1780/1790）；carrier rate 展開有 `aria-expanded`（A:5633） | **部分修復**（無通用 accordion 元件、`↑↓`／`Home/End` 仍缺） |
| 16 | Modal | 驗證失敗 shake 缺、無 trap | shake **已接上**（A:2771）；**focus trap／焦點還原／`inert` 仍全缺**（實跑：openGen 後第 3 個 Tab 就跑出 modal） | **部分修復** |
| 17 | Popover | 無翻轉邏輯 | `.view-menu.right` A:913 仍需手掛，無視口碰撞偵測 | **仍缺** |
| 18 | Bottom sheet | A 完全缺 | 結帳編輯器有 `.ck-pick`（A:6552–6570）；**無拖曳把手、無 snap point、非通用元件、桌機 1024 的 modal→sheet 仍無** | **部分修復** |
| 21 | Inline banner | 只有 `.banner-err`，其他靠 inline style | A:1156–1159 `.banner-caution`（＋`.bc-ic`）等 7 處變體 class | **部分修復**（`--info`／`--success`／dismissible 仍缺；A:1947 仍有 inline style 覆寫） |
| 24 | 空態 | 只有一種 | A:1420 `.emp-art` 插圖區（page 型）；**卡內一行灰字型仍未分家** | **部分修復** |
| 25 | 404（A） | 完全缺 | 0 命中 | **仍缺** |
| 26 | Save bar | 形態錯（右下浮動） | A:1209–1219 `@media (min-width:48em)` 讓 savebar 佔搜尋框槽位、`.topbar:has(.savebar.show) .searchbox{display:none}`。實跑 1440px：savebar `position:static`／`x=359 w=640`，searchbox `display:none` | **已修復**（`⌘S`／`Esc` 捨棄仍缺；另見 §6 R-03） |
| 27 | 頁尾儲存鈕 `cl-savefoot` | 完全缺 | `savefoot`／`foot-save` **0 命中**；選單編輯器實跑仍是頂部「儲存選單」＋save bar **同時出現** | **仍缺** |
| 28 | 編輯器頂欄儲存鈕 | 完全缺 | `#ckSave` A:6395 `disabled aria-disabled="true"`；`ckDirty()` A:6468 同步兩者。實跑驗證 | **已修復** |
| 29 | 麵包屑 chip | 形態不同（`←` 而非 icon chip＋`›`） | `setCrumb()` A:5449 為 icon chip ＋ `›` ＋ 標題，用於設定全部次級視圖 | **已修復**（詳情頁 `detailHead()` 仍是 `←`） |
| 30 | 分頁器 | URL 契約完全沒有 | `pushState`／`location.hash` A **0**；實跑翻頁後 URL 不變 | **仍缺** |
| 31 | 字元計數器 | A/P 完全缺 | A:1434–1437 `.cl-counter`＋`.is-warn`／`.is-over`；A:2336 掛 `aria-live="polite" aria-atomic`；`counterSync()` A:2821 | **已修復（A）／仍缺（P）** |
| 32 | 拖曳排序 | 鍵盤全缺 | `.grip` 仍是 `<span aria-hidden="true">`（無 tabindex／role／keydown）；`aria-grabbed`／`aria-roledescription` 0。**實跑：focus grip → Space → ↓ → Space，順序完全不變** | **仍缺** |

**表 2 完全缺：8 → 5**（13.2 堆疊卡片、14 CEC、22 雙層 banner、25 404(A)、27 頁尾儲存鈕）

### 47 號點名的 13 項（前後對照）

| # | 要求 | 49 號裁定 | 現況 | 狀態變化 |
|---|---|---|---|---|
| 1 | badge ●／○／⊘ | 部分有、語意錯 | `PIP_SHAPE` 依語意族選形，實跑驗證三形都出現 | **已修復** |
| 2 | tag 與 badge 分家 | 方向相反 | A:313 `.badge{border-radius:var(--r-200)}`（8px 圓角矩形）、A:434 `.tagchip{border-radius:var(--r-pill)}` | **已修復** |
| 3 | tag `+N` 收合（≤429） | 部分有 | 表格內 `+N` 在；**≤429 的 media query 仍無** | **仍缺** |
| 4 | 髮絲線 1 裝置像素 | 完全缺 | dppx 三檔 ＋ 全站 `var(--hairline)`；硬寫 `1px solid` 歸零 | **已修復** |
| 5 | disabled 只降文字色 | 完全缺（做法相反） | A:294／P:256／S:214 皆改為只降文字色 | **已修復** |
| 6 | 表單控件用 inset 陰影當框 | 完全缺 | A:336 `.input` 已改 | **已修復** |
| 7 | 堆疊卡片單邊圓角 | 死 CSS | A:1104–1108、P:248–252 **仍 0 使用** | **仍缺（死 CSS）** |
| 8 | Modal 驗證失敗 shake | 完全缺 | `clShake()` 接上 `formSave()` 與 `closeCheckoutEditor()` | **已修復** |
| 9 | 雙層 banner | 完全缺 | 0 命中 | **仍缺** |
| 10 | AI 紫色 inline 列 | 有 | 仍有（`✕` 仍是 `<span>`，鍵盤不可達） | 不變 |
| 11 | 兩種空態 | 完全缺 | 有 `.emp-art` page 型，卡內型未分家 | **部分修復** |
| 12 | 兩種 404 | 完全缺 | A 仍一種都沒有 | **仍缺** |
| 13 | save bar 取代搜尋列 | 完全缺（形態相反） | 已改（≥768em；≤767 明文退回底部浮動、設定 overlay 內明文浮動） | **已修復** |

**13 項：完全缺／做反 10 → 3**（#7、#9、#12），另 #3、#11 部分修復。

---

## 表 3 · 交互邏輯缺口（第二版）

> 66 條同一份清單，只列狀態有變動的 17 條；其餘 49 條與 49 號同判。

| 來源 | 交互規則 | 49 號 | 現況證據 | 狀態變化 |
|---|---|---|---|---|
| §18.6 | 退貨規則關閉 → 最終銷售整卡 disabled／灰化 | ❌ | `rrFinalSync()` A:5553–5561。**實跑**：兩 toggle 皆關 → 卡片 `aria-disabled="true"`＋`.is-dim`＋內部 4 個控件 `disabled=true`；任一開 → 全部還原 | **已修復** |
| §19.2 | 免運「副標＋價格 badge 保留原價」雙層表達 | ⚠️ | A:5588 rate 物件帶 `free:true`＋副標「滿 NT$2,000 免費」，價格欄仍顯示 `NT$60` | **已修復** |
| §19.2 | zone ≠ market 黃色警示 | ❌ | A:1154 `.banner-caution`；DOCS 鍵 `ship-market-warn` A:6032 | **已修復** |
| §19.2 | carrier rate 展開看 `services[]` | ❌ | A:5632–5643 `aria-expanded` ＋ `<ul class="rate-svcs" hidden>`；`shipToggleSvc()` | **已修復** |
| §19.6 | 字元計數器（四個硬值） | ❌ | `.cl-counter` ＋ `counterSync()`；上限值改指 `limits.yml`（符合 CLAUDE.md 鐵律 6） | **已修復** |
| §21.1/§21.6 | 編輯器頂欄單一 `儲存`，未變更即 disabled | ❌ | 實跑：初始 `{d:true,a:"true"}` → `ckDirty(true)` 後 `{d:false,a:"false"}` | **已修復** |
| §21.2 | 頁面選擇器 bottom sheet | ❌ | 實跑 `.ck-pick.show` 6 頁 | **已修復** |
| §21.4 | `⊕ 新增區塊` popover 空態 | ❌ | `ckAddPop()` A:6580／`ckAddClose()` A:6593 | **已修復** |
| §22.5 | save bar 取代整條搜尋列（非疊加） | ❌ | 實跑確認（見表 2 §26） | **已修復** |
| §22.5 | B2B `訂單提交` 兩態 | ❌ | `SUBMIT_T` A:6063 `{auto:'自動提交訂單',draft:'全部草稿審核'}`；列表可依此篩選 A:6091 | **已修復** |
| §18.2 | 依地區自動預勾行銷同意 | ⚠️ | `ckOptin` toggle ＋ `data-dep="ckOptinScope"` → 展開地區 select（實跑 `display:none→block`） | **已修復** |
| §18.7 | 通知範本只有部分可關閉 | ⚠️ | A:5166 真 toggle，`訂單確認` 帶 `disabled aria-disabled` | **已修復** |
| §18.7 | Webhook 支援 XML 與 JSON | ❌ | `setRowSel('格式',…)` A:5829 | **已修復** |
| 48 §A.1 | `disabled` vs `aria-disabled` 二選一 | ❌ | 實跑 21 個設定分頁 ＋ 首頁：**所有 `disabled` 控件 100% 帶 `aria-disabled="true"`，0 個遺漏、0 個殘留過期值**；相依欄位切換時動態同步（A:2835/2838） | **已修復** |
| §19.1 | 運送外層 accordion（未展開也看得到摘要） | ❌ | 四個子區塊到位，但無 accordion、無「預計配送日期」摘要 | **部分修復（❌→⚠️）** |
| §18.2 | 「要求顧客登入」⇒ 強制 email 通道 | ❌ | **實跑：把 `accounts` 的「結帳時的帳號要求」設成「必填」後，`checkout` 的 `ckContact` 仍 `disabled=false / aria-disabled=null`。只有說明文字與 caution banner，沒有真聯動** | **部分修復（❌→⚠️）** |
| §18.4 | 地點配額「已用 N／上限 M」 | ❌ | 只有 N，無 M | **部分修復（❌→⚠️）** |

**表 3 總計：54 → 40**（✅ 12→26／⚠️ 14→14／❌ 40→26）

---

## 表 4 · 反向缺口（第二版）

28 列中 **26 列完全未動**（多屬 48 附錄 A 的登記問題與待裁定項，不是程式碼問題）。變動如下：

| 項 | 49 號 | 現況 | 狀態變化 |
|---|---|---|---|
| A/P/S `z-index` 硬編 | 契約已寫、原型未跟 | A 19→**0**、P 8→**0**、S 24→**9**（餘為區域堆疊 `z-index:1/2`） | **已修復（A/P）／部分（S）** |
| A/P/S 斷點用 `px` | 48 與 47 衝突未定案 | 三份全改 `em`（採 47 §F） | **已修復（原型側）** |
| A `48 的 cl-* 命名`（F-01） | 完全不相交 | 新增原語採用了 `cl-` 前綴：`.cl-hairline` / `.cl-hairline-t` / `.cl-radio` / `.cl-counter` / `.cl-shake`（5 個），但 32 元件主命名（`.btn`/`.badge`/`.card`）未動 | **部分修復** |
| A `每頁 8 筆`（44 實測 50） | 與實測衝突 | `const per=c.per||8` A:2943 未動；另有 `per:4`（A:4150）、`per:10`（A:4751） | **仍缺** |
| A 報告 11 類（44 實測 13） | 與實測衝突 | `REP_CATS` A:4741 仍 11 類 | **仍缺** |
| **（新增）** A B2B `載入示範資料` 鈕 | — | `b2bSeed()` A:6081，**無產品出處**，與 `lcycle()` 同屬展示裝置 | **新增缺口**（demo-only，正式版須移除） |

**表 4 總計：28 → 27**

---

## 5. 文件間的自相矛盾（第二版）

| # | 49 號 | 現況 | 狀態變化 |
|---|---|---|---|
| **F-01** | 原型與 48 的 `cl-*` 命名完全不相交 | 5 個新原語採用 `cl-` 前綴；主元件命名仍未映射，48 附錄 A 仍無「原型現用選擇器」欄 | **部分解** |
| **F-02** | badge 第三形：47 說 `⊘`、48 §11 說「半圓」 | **原型已裁定採 47**（A:316–320 `.pip.blocked` 為斜線圓，`.half` 降為別名）；**48 §11.1/§11.2/§11.5（1540/1560/1565 行）仍寫「半圓」** | **原型已定案、48 未同步** |
| **F-03** | 斷點單位：47 說 em、48 §00.13 寫 px | **原型已裁定採 47**（全 em）；**48 §00.13（165–175 行）仍是 px 五階** | **原型已定案、48 未同步** |
| **F-04** | z-index：47 說 510–520 帶、48 §00.9 說 0…95 | **原型已裁定採 47**（A:127–135）；**48 §00.9（112–119 行）仍是 `0…95` 十四階** | **原型已定案、48 未同步** |
| **F-05** | `--t-xl` 與 `--t-2xl` 撞值；A 缺 4 個 token | 撞值已解（A:105 `18/24/500`、A:106 `20/24`）；`--t-2xs`（A:100）／`--t-3xl`（A:107）已補；**`--t-display` 仍不存在** → 帳單累積總計仍無 token 可用 | **部分解** |
| **F-06** | 48 #83 要 `.btn{font-weight}` 600→500 | **A:292 仍是 `font-weight:600`**（P、S 同） | **未動** |
| **F-07** | 44 §8.2 說沒有「品牌」「禮品卡」分頁 | `data-set="brand"`／`data-set="giftcards"` 仍在，且兩者這輪還被補成真控件 | **未動（且投入加深）** |

**§5 總計：7 → 6**（F-02/03/04 已從「原型與 47 衝突」轉為「48 文件落後於原型」——性質變了但衝突未消，仍各計 1）

---

## 6. 回歸風險（新章）

> 這一輪動了 A 的 2600 行、刪了 36 條死碼、把 save bar 從右下移進頂欄。以下是實跑掃出來的副作用。

### 先講沒壞的（回歸抽查全過）

| 抽查項 | 方法 | 結果 |
|---|---|---|
| 刪 12 個被覆蓋鍵有沒有造成「鍵找不到」 | 實跑逐一 `openSettings(k)` 掃 21 個 `data-set` 分頁，量 `.set-body` 文字長度 | **21/21 全部有內容**（最短 `org` 266 字元），0 個空白分頁 |
| 27 個 `MODULES` 路由 | 逐一 `go(k)` 量 `.page.on` 文字長度 | **27/27 全部渲染**，0 個空白頁 |
| 10 個設定次級視圖 | 逐一呼叫 `openCkFields` / `openManualPay` / `openReturnRule` / `openShipProfile` / `openTaxOverrides` / `openLocPriority` / `openPackages` / `openPackingSlip` / `openWebhook` / `openLocalDelivery` | **10/10 全部渲染**（293–607 字元），0 例外 |
| JS 執行期錯誤 | `pageerror` ＋ `console.error` 監聽，跑完全部路由 | **0 個**（僅一則 file:// 環境的 `ERR_TUNNEL_CONNECTION_FAILED` 資源載入雜訊） |
| `onclick` 引用的函式是否都存在 | 從 markup 抽出 198 個呼叫名，逐一 `typeof window[n]==='function'` | **0 個懸空引用**（未命中者全為 `.trim()`／`.closest()` 等方法名與模板內變數） |
| save bar 在一般頁面 | 選單編輯器 dirty 後量幾何 | `position:static`／`x=359 w=640 h=36`／searchbox `display:none` — **正確取代，非疊加** |
| P／S 兩份原型 | 載入後掃 console、`aria-disabled` 完整性、`--hairline`／`--focus-ring` 計算值 | **0 錯誤**；P `--focus-ring:#005bd3` ✓；S 維持品牌色 `#a9502c`（依 b4a00bb 決議） |

### 壞掉／被壓掉的（7 項）

| # | 風險 | 證據 | 嚴重度 |
|---|---|---|---|
| **R-01** | **`billingPage` 重複宣告 → 財務·帳單頁的發票紀錄整頁消失** | A:4722（發票頁：3 張 KPI 卡＋發票表）與 A:5184（設定·帳單卡）**同名函式宣告**。函式宣告會提升，後者覆蓋前者，因此 A:4936 的 `MODULES["m-billing"].custom=billingPage` 綁到的是設定卡。**實跑 `go('m-billing')` 渲染出「付款方式／帳單週期／帳單門檻／帳單幣別」而不是發票表**；A:4722–4737 成為不可達死碼。更糟的是設定卡裡的「查看發票紀錄 ›」按鈕 `closeSettings();go('m-billing')` 會回到自己 → **死循環**。由 commit `2cae2ad` 引入 | **高（功能遺失）** |
| **R-02** | **深色浮層的 focus 環色沒生效** | A:199 同一條規則裡 `--focus-ring` 宣告**兩次**：`var(--focus-inverse)` 隨即被 `var(--surface)` 覆蓋。實跑 `.savebar`／`.toast`／`.bulkbar` 的 `--focus-ring` 計算值為 **`#fff`**，不是 commit `b4a00bb` 宣稱採用的量測值 `#4b92e5`。白環在 `#1a1b1d` 上對比夠，所以看不出來，但**量測真值實際上沒有落地** | 中 |
| **R-03** | **save bar 兩顆按鈕完全沒有焦點環** | A:897／A:899 `.savebar .btn-sec{…box-shadow:none}`／`.savebar .btn-pri{…box-shadow:none}` 特異性 (0,2,0) **壓過** `:focus-visible` 的 (0,1,0)。實跑鍵盤 Tab 到 `#sbSave`：`boxShadow === "none"`。此規則基準版就有，但本輪把 save bar 升格成頂欄主要 dirty 入口，**暴露度大幅上升** | 中（WCAG 2.4.7） |
| **R-04** | 設定 overlay 開著時仍會隱藏頂欄搜尋框 | A:1219 `.topbar:has(.savebar.show) .searchbox{display:none}` 沒有排除 `body:has(.settings.show)`。實跑：在設定內改一個欄位 → searchbox `display:none`，但 save bar 這時是右下浮動態（A:1448），**槽位空著沒人接**。因為設定 overlay 是 `z-dialog` 全螢幕會蓋住頂欄，目前肉眼看不見；一旦設定改成非全屏就會露出破口 | 低（潛在） |
| **R-05** | 16 條「假 `›`」列：有 chevron 沒有 handler | 實跑掃 21 個分頁的 118 條 `.set-row`：**28 條無任何互動元素且非 `is-ro`**，其中 **16 條帶 `.chev` 卻沒有 `button`/`a`/`onclick`** — `users` 的 6 條 permCats、`shipping` 的 2 條市場運送選項、`customdata` 的 4 條定義、`apps` 的 4 條銷售管道。「58 條轉真控件」把大宗做掉了，但**留下的假可點列比原本的 `setRow` 更誤導**（`setRow` 至少有 `唯讀` chip 明示） | 中 |
| **R-06** | `.b-caution,.b-caution` 重複選擇器 | A:322 選擇器清單裡同一個 class 寫了兩次 | 低（無害，但是同一類貼上錯誤） |
| **R-07** | `openDiscModal` 也是重複宣告 | A:2284 與 A:4965 同名（基準版就有，第二個是真的那個）。與 R-01 同一個反模式；建議一併加一條「同檔不得重複宣告頂層函式」的 lint | 低（目前行為正確） |

---

## 7. P0 22 條逐條驗收

| # | 缺口 | 判定 | 證據 |
|---|---|---|---|
| **P0-01** | 訂單詳情未依 fulfillment order 分卡 | **未解決** | A:1966 仍單一出貨卡；`fulfillmentOrders`／`foGroups`／`per-fulfillment` 0 命中 |
| **P0-02** | 市場詳情缺父子繼承模型 | **未解決** | `繼承的設定`／`上層市場` 基準 0、現在 **也是 0**；`marketPage()` A:4618 仍平鋪 |
| **P0-03** | 退貨與取消規則整組 | **已解決** | 政策首卡 A:5456–5476（多規則＋⊕新增規則）／規則編輯頁 `openReturnRule()` A:5498／購買時點快照提示 A:5530／最終銷售粒度 `role="radiogroup"` A:5535／**整卡灰化實跑通過**（`rrFinalSync()` A:5553，兩 toggle 關→`aria-disabled=true`＋`.is-dim`＋內部 4 控件 `disabled`） |
| **P0-04** | B2B 公司／地點模型 | **已解決** | `m-companies`／`d-company`／`d-company-new` 三路由；**四項能力全掛在 location**（A:6108–6113 每筆 location 各帶 `catalog / profile / terms / taxId / tax / submit`），空態四支柱文案逐字寫明「全部作用在地點層，不是公司層」 |
| **P0-05** | 運送設定檔內層 | **已解決** | `openShipProfile()` A:5603；`shipping_profile→zone→rate` A:5583；補集語意「未包含於其他設定檔的所有商品」；rate 兩型 manual/carrier；carrier 展開 `services[]` 實跑通過 |
| **P0-06** | zone ≠ market 硬約束無 UI 警示 | **已解決** | `.banner-caution` A:1154–1159；DOCS 鍵 `ship-market-warn` A:6032；實跑設定檔頁文字命中「市場」警示 |
| **P0-07** | 稅務服務三檔 `managed/basic/manual` | **未解決** | `service_tier` **只出現在 DOCS 註釋** A:7048–7049；`taxesPage()` A:5140–5152 只有三個地區稅率 input，無 tier 控件、無 manual 才顯示的自訂編輯器 |
| **P0-08** | 結帳設定檔為多份實體 | **已解決** | `CK_PROFILES` A:6740–6742（2 份，`active:true/false`，`saved:'今天 10:24'`）；`ckProfileCard()` A:6743 渲染 `使用中`／`未使用` chip ＋ 上次儲存時間；A:6757 掛進 checkout 分頁頂端 |
| **P0-09** | 結帳規則引擎（商品限制／年齡驗證） | **未解決** | `結帳規則`／`年齡`／`商品限制`／`Function 擴充` 在 **A 與 S 皆 0 命中**。功能仍是兩邊都沒有的狀態 |
| **P0-10** | checkout 欄位三態 ＋「要求登入⇒強制 email」聯動 | **部分** | 三態**有**：`openCkFields()` A:5671 次級視圖（實跑 518 字元，逐欄「不顯示／選填／必填」）。**聯動沒有**：實跑把 `accounts` 的 `acctReq` 設為「必填」後，`checkout` 的 `ckContact` 仍 `disabled=false / aria-disabled=null / 兩個 option 都可選`。只有 A:5024 的說明文字與 accounts 頁的 caution banner |
| **P0-11** | 顧客通知 45+ 範本／12 分組／`toggleable` | **部分** | `toggleable` 已為真：A:5166 每列 `role="switch" aria-checked`，`訂單確認` 帶 `disabled aria-disabled="true"`。**仍是 15 條平鋪**，無 12 分組摺疊、無「出貨要求」第三類別 |
| **P0-12** | badge pip 語意編碼失效 | **已解決** | `PIP_SHAPE` A:2074（`success/default/ai→full`、`info/caution/attention→空圈`、`warning/critical→blocked`）＋ `chip()` A:2075 支援第三參數覆寫。**實跑訂單/未完成結帳頁 14 個 badge：已付款/已出貨/已退款=●、未出貨=○、待付款/部分出貨=⊘**。殘留：`chip('智慧型','ai')` 仍畫 ●，47 §D 要求 AI 用 `✦` 不用 pip |
| **P0-13** | `disabled` 做法錯 ＋ `aria-disabled` 0 命中 | **已解決** | 做法：A:294／P:256／S:214 全改為只降 `--text-disabled`，`.btn:disabled{opacity}` 已刪。同步性（本次重點複核）：**實跑 21 個設定分頁＋首頁，`disabled` 控件 100% 帶 `aria-disabled="true"`，0 遺漏、0 過期殘留**；且是真的隨狀態走，不是寫死——相依欄位 `_dep`/`setSyncAll` A:2829–2840 切換時 `aria-disabled` 在 `true↔false` 間翻轉並連帶內部控件；save bar A:2774/2776；`ckDirty()` A:6468；`rrFinalSync()` A:5558。`role=switch` 的 `aria-checked` 亦驗證真點擊同步 |
| **P0-14** | 浮層無 focus trap／無焦點還原／背景無 `inert` | **未解決** | **實跑三個浮層全部漏**：① `openGen()` modal → 第 **3** 個 Tab 焦點就跑到頂欄 searchbox；② 設定 overlay → 第 **29** 個 Tab 跑進背景側欄 nav-item；③ 結帳編輯器 → 第 **53** 個 Tab 跑進背景 nav-item。`inert` 全站 **0**（`document.querySelectorAll('[inert]').length === 0`）。焦點還原：Esc 關設定後 `document.activeElement === BODY`。`lastFocus`／`trapFocus`／`restoreFocus` 在 A **0 命中**。唯一有 trap＋還原的仍是側欄抽屜（A:2617–2626 Tab 循環、A:2609 `b.focus()`）——與 49 號當時完全相同 |
| **P0-15** | `sr-only` 三份原型 0 命中 | **未解決（A/P）；49 號對 S 的記錄有誤** | A、P：`sr-only`／`visually-hidden`／`clip-path:inset(50%)`／`clip:rect` **全 0**；實跑 DOM 掃「絕對定位 + 1px + 有文字」的節點也是 **0**。**S 其實有**：`.vh{position:absolute!important;width:1px;height:1px;clip:rect(0 0 0 0)}` S:118，用 6 次——**基準版就有，49 號寫「三份皆 0」是漏判**。S 另有真的 skip link `<a class="skip" href="#main">跳至主要內容</a>` S:1142（實跑第一個 Tab 即聚焦、`top` 由 -80px 變 8px） |
| **P0-16** | 拖曳排序無鍵盤操作 | **未解決** | `.grip` 是 `<span class="grip" aria-hidden="true">`，**無 `tabindex`／無 `role`／無 `onkeydown`**；`aria-grabbed`／`aria-roledescription` 0 命中。**實跑**：選單編輯器 7 個 `.mi`，focus grip → `Space` → `ArrowDown` → `Space`，前後順序**完全一致**（`新品上市/上衣/帽T/襯衫/外套/配件`）。替代方案（每列 `↑↓←→` 四顆按鈕，A:4451–4454；地點順序 A:5803–5804）仍在且帶 `aria-label`＋邊界 `disabled aria-disabled`——**可用但不是 48 §32.4 的規格** |
| **P0-17** | 草稿訂單空車付款區未 disabled ＋ 稅額無「未計算」態 | **未解決** | **實跑 `d-draft`**：品項區已是空態（「尚未加入商品」），但**付款卡照常整張渲染**，「加入折扣」「加入運費」可點，稅額顯示「稅額・內含 5% / NT$0」。`未計算`／`新增商品以計算總計` 0 命中 |
| **P0-18** | 分頁狀態不進 URL | **未解決** | A 的 `pushState`／`replaceState`／`location.hash` **0 命中**。**實跑**：`go('m-customers')` 後呼叫 `lpage('m-customers',1)` 翻頁，`window.location.href` **完全不變**。（S 有 hash 路由 19 處，但不含 cursor，同 49 號） |
| **P0-19** | 財務 2FA 為 banner 而非閘門 | **未解決** | A:4692 仍是 `.banner-err` inline 提示。**實跑財務頁**：`has2fa=true` 且 `showsBalance=true` — 「可用餘額 NT$38,420／待入帳 NT$12,860／本月手續費／撥款排程」全部照常顯示在 banner 下方 |
| **P0-20** | save bar 形態錯 ＋ 缺另外兩種存檔模式 | **部分** | ① 取代搜尋列：**已做**（A:1209–1219，實跑幾何確認）；② 編輯器頂欄儲存鈕：**已做**（`#ckSave` A:6395，dirty 才 enable，實跑確認）；③ **頁尾儲存鈕：仍 0**（`savefoot`／`foot-save` 0 命中）。**實跑選單編輯器仍是「頂部『儲存選單』鈕 ＋ 頂欄 save bar 同時出現」**，49 號指出的「兩種模式同時出現」問題**原封不動**。`⌘S`／`Esc` 捨棄確認仍無 |
| **P0-21** | 地點配額（已用 N／上限 M）與 POS 訂閱層級 | **部分** | A:5157「已使用 `N` 個地點（配額依方案，見 limits.yml location.quota_*）」——**只有分子沒有分母**，44 實測的「200 個，已用 1」形態未成立；`POS 訂閱`／`POS Pro`／`POS Lite` tabs 0 命中 |
| **P0-22** | 結帳與帳號編輯器整章 | **已解決** | `#ckEditor` A:1725（`role="dialog" aria-modal="true"`）／`ckMount()` A:6416／`openCheckoutEditor()` A:6427。**實跑**：三欄佈局、圖層樹 **19 個 `.ck-node`**、6 頁 bottom sheet picker、`⊕ 新增區塊` popover、儲存鈕 dirty 才 enable、預覽節點 `role=button` 支援 Enter/Space（A:6421–6425）、專屬 Esc 分層鏈（A:6714–6725）、`checkout_ui_extension` 3 處明示 block 由 app 擴充提供。**唯一缺口**：仍無 focus trap（見 P0-14） |

**P0 統計：已解決 8 ／ 部分 4 ／ 未解決 10**

- **已解決（8）**：P0-03、04、05、06、08、12、13、22 — 全部集中在「四塊缺失模組」與「量測真值套用」兩項工作。
- **部分（4）**：P0-10、11、20、21 — 共同特徵是**做了外層、沒做那條規則本身**（三態做了但聯動沒做／toggle 做了但分組沒做／兩種模式做了但第三種沒做／分子做了但分母沒做）。
- **未解決（10）**：P0-01、02、07、09、14、15、16、17、18、19 — **這 10 條這輪一行都沒動**。

---

## 8. 「宣稱做了但實際沒做到」清單

> 只列**有明確宣稱（commit message、DOCS 註釋、或本次任務描述）但實測不成立**的。純粹沒做的（P0-01/02/07/09/16/17/18/19）不在此列——那些沒被宣稱過。

| # | 宣稱 | 實測 | 落差性質 |
|---|---|---|---|
| **X-01** | commit `b4a00bb`：「採用實測 focus 環色 `#005bd3`（深色底反轉 `#4b92e5`）於 admin/platform」 | A:199 同一條規則裡 `--focus-ring` 寫了兩次，`var(--focus-inverse)` 被緊接著的 `var(--surface)` 覆蓋。**實跑 `.savebar`／`.toast`／`.bulkbar` 的 `--focus-ring` 是 `#fff`，`#4b92e5` 從未生效** | **改了但被自己覆蓋** |
| **X-02** | P0-14 在本輪任務描述中列為需複核項；`#ckEditor` 帶 `role="dialog" aria-modal="true"` 暗示已處理浮層語意 | `aria-modal` 是**宣告**不是**行為**。實跑三個浮層 Tab 全部逃出（modal 3 tabs／設定 29 tabs／編輯器 53 tabs），`inert` 全站 0，Esc 關設定後焦點掉到 `BODY` | **有 ARIA 標記、無對應行為** |
| **X-03** | commit `2cae2ad`：「設定區 58 條佔位列全數轉真控件」 | 大宗屬實（114 個真控件 helper 呼叫），但**實跑仍有 16 條帶 `›` 卻沒有任何 handler 的假可點列**（users permCats 6／shipping 市場運送 2／customdata 4／apps 銷售管道 4），以及 `events` 分頁**整頁 0 個真控件**。「全數」不成立 | **大部分做到，「全數」誇大** |
| **X-04** | commit `2cae2ad`：「刪除 12 個被覆蓋鍵共 36 條死碼」 | 刪除本身沒造成回歸（21 分頁／27 模組／10 次級視圖全數通過），**但同一個 commit 新增了一個新的覆蓋**：`billingPage` 重複宣告，把財務·帳單的發票紀錄頁整頁蓋掉（§6 R-01）。**刪掉舊死碼、造出新死碼＋一個功能遺失** | **修死碼的同時製造死碼** |
| **X-05** | 本輪任務描述：「save bar 改為取代頂欄搜尋列」 | 取代本身做對了。但 ① `.savebar .btn-pri/.btn-sec{box-shadow:none}` 特異性壓掉 `:focus-visible`，**兩顆按鈕實跑沒有焦點環**；② 設定 overlay 開啟時 searchbox 仍被隱藏而 save bar 不在該槽位（§6 R-04）；③ 49 號 P0-20 的另外兩種存檔模式只做了一種，**「選單編輯器兩種模式同時出現」的原始問題完全沒動** | **主形態對、配套沒跟上** |
| **X-06** | DOCS 註釋 A:6985/7160 逐字寫「勾『要求顧客登入才能結帳』時聯絡方式被強制鎖成 email……這是一條前端聯動硬規則」 | **實跑該聯動不存在**。設 `acctReq=必填` 後 `ckContact` 仍完全可改。DOCS 把規則寫成已實作的口吻，實際只有說明文字 | **文檔寫成已實作、程式碼沒有** |
| **X-07** | DOCS 註釋 A:7048–7049 寫 `tax_region.service_tier=manual 才會出現自訂稅率編輯器`；A:7006 寫「進階偏好設定 → 地址蒐集」 | 兩者**都只存在於 DOCS 字串**，UI 側 0 命中。DOCS 條數（+112／+54／+30）增長很快，但**有一部分是在描述還不存在的控件** | **DOCS 超前實作** |
| **X-08** | 49 號 §表2 全域事實表寫「`sr-only`／`visually-hidden` A/P/S 皆 0」 | **S 其實有** `.vh` 工具類（S:118）用 6 次，還有真的 skip link（S:1142）。這是**49 號自身的漏判**（只 grep 了 `sr-only`/`visually-hidden` 兩個字面），不是這輪的問題，但會讓 P0-15 的範圍被高估 | **49 號原始量測誤差** |
| **X-09** | 49 號 P1 清單寫「堆疊卡片單邊圓角為死 CSS（A:886）」；51 號表 1 又寫「A 已實作 `.card-stack`（886–890，**markup 用 5 次**）」 | 兩份文件互相矛盾，實測站在 49 號這邊：**A:1104–1108 與 P:248–252 的 `.card-stack` 在 style 區出現 5 次、markup/JS 區 0 次**。51 號把 CSS 定義行數誤當成使用次數 | **51 號量測誤差** |

**另外三項本次特別點名複核、結果是「真的做到了」的**（列出來以示區別）：

| 項 | 結果 |
|---|---|
| `aria-disabled` 是否真的隨 disabled 同步 | **真的**。0 遺漏、0 過期；相依欄位／save bar／編輯器儲存鈕／最終銷售卡四處都是 JS 動態 `setAttribute`／`removeAttribute`，不是寫死在 HTML |
| badge pip 是否依語意選形 | **真的**。`PIP_SHAPE` 語意族映射 ＋ 第三參數覆寫；實跑 14 個 badge 三形都出現且對得上語意 |
| M1–M7 動效原語是否仍是死碼 | **已修復**。A 的 `.m-hover`(21 用)／`.m-text`(1)／`.m-focus`(7)／`.m-accordion`(2)／`.m-pop`(3)／`.m-drawer`(1)／`.m-sidebar`(1) 全部進了 markup。**但 `.card-stack` 仍是純死碼（A 0 用、P 0 用）** |

---

## 9. 本次新發現的缺口

| # | 缺口 | 出處／證據 | 建議優先級 |
|---|---|---|---|
| **N-01** | `billingPage` 重複宣告造成發票紀錄頁遺失＋「查看發票紀錄」死循環 | A:4722 vs A:5184 | **P0**（功能遺失） |
| **N-02** | `--focus-ring` 重複宣告，深色浮層量測環色未生效 | A:199 | P1 |
| **N-03** | save bar 兩顆按鈕的 `box-shadow:none` 壓掉 `:focus-visible`（WCAG 2.4.7） | A:897／A:899 | **P0**（無障礙契約） |
| **N-04** | 16 條「有 `›` 無 handler」的假可點列，比原本的 `setRow` 更誤導 | users×6／shipping×2／customdata×4／apps×4 | P1 |
| **N-05** | `events` 設定分頁仍 0 個真控件（58 條轉換的漏網） | A:5074–5079 | P1 |
| **N-06** | `.b-caution,.b-caution` 重複選擇器 | A:322 | P2 |
| **N-07** | `openDiscModal` 亦重複宣告；建議加「同檔頂層函式不得重名」的 lint（否則 R-01 會再發生） | A:2284／A:4965 | P1（流程） |
| **N-08** | `chip('智慧型','ai')` 仍畫實心 pip；47 §D 要求 AI 語意用 `✦` 而非 pip | A:2074 `PIP_SHAPE.ai='full'` | P2 |
| **N-09** | `.savebar{transition:none}`（A:1213）在桌機把 M6 動效原語關掉；`.savebar.show` 改走 `animation:pop`，與 51 號表 4 的 M5/M6 判準又岔開一次 | A:1213–1215 | P2 |
| **N-10** | B2B `載入示範資料` 為新的 demo-only 裝置（表 4 反向缺口 +1） | A:6081 `b2bSeed()` | P2 |
| **N-11** | 48 號文件在 §00.9／§00.13／§11 三處**落後於已定案的原型**（z-index、斷點、pip 形狀）。目前是「原型對、契約錯」，方向與 49 號當時相反 | 48:112–119／165–175／1540/1560/1565 | **P0**（契約失真） |

---

## 10. 建議的下一輪順序

1. **先修 R-01**（改名 `settingsBillingPage`）——這是唯一的功能遺失，10 分鐘的事。
2. **再補 48 號文件**（N-11）——契約已經落後於程式碼，再往下寫會用錯的 token 產生新一批不一致。
3. **P0-14 一次做完**（trap＋還原＋`inert`）——`openGen`／設定 overlay／結帳編輯器三處共用一支 `withFocusTrap(el)` 即可；順便修 N-03，兩者是同一個無障礙缺口的兩面。
4. **P0-15 + P0-16 併做**——`sr-only` 直接把 S:118 的 `.vh` 抄進 A/P；有了 `sr-only` 才有地方放拖曳排序的 `aria-live` 播報。
5. **剩下 8 條未解 P0 中，P0-01／02／17 是資料模型級**（fulfillment_orders 分卡、market 繼承、草稿延後計稅），優先於 P0-07／09／18／19。
