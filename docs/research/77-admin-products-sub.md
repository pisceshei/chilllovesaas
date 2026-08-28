# 77 — 產品線子頁 按鈕級 teardown（R8，2026-08-13 實測 chill-love-u5q5mnzq＋help 六路）

> 雙源：實測（test）＋help 工作流 wf_9367bc63-f1b（4 主題＋2 critic，6/6）。CSS 同 73 §5 系統。
> 🔴 **STRUCT1 實錘**：本尊產品導航子項＝**商品系列／庫存／採購單／轉移／禮品卡**五項——
> 採購單與轉移是**獨立頁**，不是庫存頁的 tab（我方舊結構已於本輪修正）。

## §1 庫存 `/products/inventory`

- 頁首：匯出／匯入（無「調整庫存」主鈕——調整在列上就地編輯）。
- **檢視三**：All／Incoming／Not Fulfillable（本尊庫存頁**無 tab**）。
- **欄集 8**（實測 DOM）：商品／存貨單位 (SKU)／現有庫存／可用／已佔用／在途／不可用／**箱名稱**；
  排序方向＝遞增/遞減。help 補篩選器 10 項：銷售管道/商品類型/商品廠商/箱名稱/標籤/
  Incoming/Committed/Available/On hand/Unavailable（五個數量狀態都可當數值篩選）。
- **狀態公式（help）**：`現有 On hand ＝ 已佔用 Committed ＋ 不可用 Unavailable ＋ 可用 Available`；
  **Incoming 不在公式內**（轉移/採購單在途）。
- 不可用子狀態值域（手動可調 4）：**損壞／品質控管／安全庫存／其他**；草稿單保留與 app 保留＝
  系統性 unavailable（非手動子狀態）。
- 調整：三入口（庫存頁 Available/On hand｜商品頁 Available/Total｜子類頁同）；模式＝**設為 Set**／
  **調整幅度 Adjust by**（後者需選來源/目的地：新增庫存＝來源 Inventory addition；狀態間移動選
  對應狀態或商店地點）。**原因 7 值**：更正（預設）／盤點／已收件／退貨重新入庫／損壞／
  遭竊或遺失／促銷或捐贈。行動版不支援填原因。
- 調整歷史：入口=商品頁「檢視調整記錄」（需先開追蹤）；**8 欄**（日期/活動/建立者/五狀態），
  每狀態顯示「先調整量、後新總量」；**保留 180 天**（更早走報表）；有子類時只能逐一看。
- 批量編輯器：13 欄可編（價格/原價/每件成本/SKU/條碼/追蹤/超賣/地點數量/重量/計稅/需運送/
  HS Code/原產地）；🔴 **不建立稽核歷程**（設絕對值、無來源/原因）——與 ledger 唯一入口原則衝突，
  我方規格 13-F5 需明示批量路徑的稽核例外處理（V 登記）。
- CSV：欄位 19 個；**僅 4 欄可匯入更新**（On hand (new)／Bin name／HS Code／COO）；
  On hand (current) 為防誤覆寫安全欄（匯出後庫存有變動則該列不匯入並 email 通知）；
  整數限定、`not stocked` 表未備貨；檔案 ≤15MB。
- 追蹤與超賣：追蹤數量開關→才可看 180 天記錄；「無庫存時繼續銷售」**不適用 POS 訂單**。
- 多地點：每地點庫存獨立不可合併；訂單依路由規則指派地點。

## §2 採購單 `/purchase_orders`（獨立頁）

- 空態：「管理您的採購單／追蹤並接收向供應商訂購的庫存。」＋建立採購單。
- 建立式（實測）：頂列 **選取供應商 →（箭頭）→ 選取收件地**；商品搜尋列（右側 **匯入 CSV** 與
  **條碼掃描** 兩 icon）；右欄「成本摘要」（採購訂單詳情：N 個子類（N 個品項）／稅金 (內含)／總計）
  ＋「採購單詳情」：**參考編號 ≤255**／**給供應商的備註 ≤5000**／付款條件（預設「無」）／
  幣別（HKD HK$）／標籤（搜尋或建立）。
- 狀態機（我方既有＋help）：草稿／已訂購；收貨在轉移側或收貨流（help receive inventory）。
- 成本回寫商品 cost per item；標記已訂購後目的地記 **Incoming**。

## §3 轉移 `/transfers`（獨立頁）

- 空態：「在地點之間轉移庫存／在您的商家地點之間轉移並追蹤庫存。」＋建立轉移。
- 建立式（實測）：頂列 **選取出貨地 → 🚚 → 選取收件地** 三段式；商品搜尋（匯入 CSV／條碼掃描）；
  下卡五列：日期（預設今天）／**新增參考名稱**／新增備註／新增標籤／**連結採購單**
  （🔴 PO↔轉移關聯——我方原型無此欄，V 登記）。
- 狀態機（我方既有）：草稿→待出貨（起點 reserved）→進行中（目的地 Incoming）→已轉移／已取消。

## §4 商品系列 `/collections`

- 列表欄：標題／商品（數）／條件／銷售管道。
- **新版建立式（2026 實測）**：標題/說明/圖片＋「3 個管道」發布選擇器；**「來源」卡**＝
  類型 select（產品）＋**新增條件**／**新增商品**（同一卡內混用——手動與智慧的界線在 2026 版
  被合併成「來源」語義）＋**排除**（negative 條件，我方原型無）＋「＋」再加一組來源。
- 條件屬性目錄（實測可見 9，清單可捲）：子類名稱／比較售價／狀態／重量／庫存／價格／廠商／
  標題／標籤…（help 另載 metafield 條件支援）。
- 我方既有規格（13-F4）：手動 vs 智慧不可互轉、智慧 ≤60 條件、全店 ≤5000——**與 2026 新版「來源」
  形態存在概念差**（V 登記，R9 內容輪或 M1 系列實作前裁定）。

## §5 禮品卡 `/gift_cards`

- 空態：「開始販售禮品卡／新增禮品卡商品來販售，或建立禮品卡並直接寄給顧客。」＋
  **雙鈕：建立禮品卡（後台簽發）／新增禮品卡商品（可販售，面額=變體）**＋匯出（停用態）＋
  「使用禮品卡即表示您同意我們的服務條款」。
- 面額上限（R6 §5 已抽）：禮品卡商品 ≤10,000 USD 等值／後台直接建立 ≤2,000 USD 等值。
- 與商店抵用金（R5 §4）是**兩套負債**：禮品卡=商品/憑證（面額入帳、可被折扣打售價不動面額）；
  抵用金=顧客帳戶餘額（≤15,000 USD/顧客）。HK SVF 單一用途豁免（G21）對兩者都適用。

## §6 我方裁定面與遞延

- 已修（71-R8）：**STRUCT1 結案**（採購單/轉移升導航子項＋poPage/transfersPage 兩頁殼＋空態原文；
  庫存頁 tab 由 4 降 2；舊 INVTAB 深連結轉導）；DOCS 5 條（po-empty/xfer-empty/xfer-new＋
  doc-m-inventory/doc-m-giftcards 改寫）。
- 遞延：V1＝庫存欄「箱名稱」與 Not Fulfillable 檢視我方未實作；V2＝批量編輯器**無稽核歷程**
  與 13-F5 ledger 唯一入口的衝突處置；V3＝轉移「連結採購單」欄；V4＝2026 系列「來源卡＋排除」
  新形態 vs 我方手動/智慧二分；V5＝CSV 19 欄與 4 可寫欄的匯入器對齊（我方現行僅 on hand）。

---

## §7 🔴 商品列表頁的 CSS 量測（層④ CSS 三段式，2026-08-28）

> 全域 token 值表、頁面骨架與視覺規律＝`docs/design/111-shopify-token-baseline.md`。
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 🔴 **鐵律 9**：只記 `getComputedStyle` 算出來的值，不含本尊樣式表原始碼、選擇器定義或可執行片段。
> ⚠️ 本節量的是 **Products index**，對應我方 `ProductsPage.tsx` ＋ `IndexTable.tsx`。

### §7.0 量測環境

> 量測日期 2026-08-28（頁面時鐘 2026-08-27T17:18Z UTC）｜innerWidth=1024、innerHeight=607｜devicePixelRatio=1｜根字級 getComputedStyle(document.documentElement).fontSize = **16px**（未受 47 §0 記載的 24px 污染，rem 值 1:1 可用）｜body font-family 首選 Inter｜Polaris 版本 --polaris-version-number = "25.87.0"｜:root 自訂屬性總數 698（documentElement / body / s-internal-theme-provider 三者同值）｜🔴 視窗寬度是 1024 不是 1280：本輪未 resize（同一 Chrome 視窗有其他代理併行量測，resize 會污染他們）。字級／字重／色／圓角／內距／陰影／狀態值與寬度無關可直接採用；**凡標「寬度相依」的欄寬與容器寬只在 1024 成立**。｜所有 shadow root 皆為 open，穿透法 el.shadowRoot.querySelector 全程可用；本輪無封閉 shadow root。｜唯讀紀律：僅勾選 1 列（CHOICE Urate 9907158778091，非禁碰清單）後立即取消、切換 saved view、輸入一次無結果查詢；全程未按任何儲存鍵，離開前已還原 All 檢視、0 選取、無批次列。禁碰的五個商品（9907126370539／9911273160939／D53-QA/QB/QC）全程未點擊。

### §7.1 本畫面用到的 token 值

| 類別 | 量測值 | 取值選擇器 |
|---|---|---|
| 版本 | "25.87.0" | getComputedStyle(document.documentElement) → --polaris-version-number |
| 底色 / 頁面 | #f1f1f1（頁面底，實測 main._Main_semjk_308 背景亦為 rgb(241,241,241)） | :root --p-color-bg |
| 底色 / 卡片面 | #fff / #f7f7f7 / #f3f3f3 / #f1f1f1 / #f7f7f7 / #f3f3f3 / rgba(0,0,0,0.05) | :root --p-color-bg-surface / -hover / -active / -selected / -secondary / -tertiary / -disabled |
| 底色 / 反白與填色 | #fff / #0a0a0a / #303030 / #1a1a1a / #1a1a1a / rgba(0,0,0,0.17) | :root --p-color-bg-fill / -inverse / -brand / -brand-hover / -brand-active / -brand-disabled |
| 底色 / 次階填色 | #f1f1f1 / #ebebeb / #e3e3e3 / #e3e3e3 | :root --p-color-bg-fill-secondary / -hover / -active / -selected |
| 底色 / 透明填色（tertiary 按鈕用） | rgba(0,0,0,0.02) / rgba(0,0,0,0.05) / rgba(0,0,0,0.08) / rgba(0,0,0,0.08) | :root --p-color-bg-fill-transparent / -hover / -active / -selected |
| 文字色 | #303030 / #616161 / #616161 / #b5b5b5 / #e3e3e3 / #005bd3 | :root --p-color-text / -secondary / -tertiary / -disabled / -inverse / -highlight |
| 語義色 / success | #047b5d / #affebf、#014b40、#047b5d、#014b40 | :root --p-color-bg-fill-success / -secondary、--p-color-text-success、--p-color-badge-bg-fill-success、--p-color-badge-text-success |
| 語義色 / info | #91d0ff / #d5ebff、#003a5a、#003a5a | :root --p-color-bg-fill-info / -secondary、--p-color-text-info、--p-color-badge-text-info |
| 語義色 / warning | #ffb800 / #ffd6a4、#5e4200 | :root --p-color-bg-fill-warning / -secondary、--p-color-text-warning |
| 語義色 / critical | #c70a24 / #fed1d7、#8e0b21、#c70a24 | :root --p-color-bg-fill-critical / -secondary、--p-color-text-critical、--p-color-badge-bg-fill-critical |
| 語義色 / caution | #ffe600 / #ffeb78、#4f4700 | :root --p-color-bg-fill-caution / -secondary、--p-color-text-caution |
| 邊框色 | #e3e3e3 / #ebebeb / #ccc / #ccc / #005bd3 / #ebebeb | :root --p-color-border / -secondary / -tertiary / -hover / -focus / -disabled |
| 圖示色 | #4a4a4a / #8a8a8a / #303030 / #1a1a1a / #ccc | :root --p-color-icon / -secondary / -hover / -active / -disabled |
| 間距階（rem→px @16px 根字級） | 0=0 / 025=1 / 050=2 / 100=4 / 150=6 / 200=8 / 250=10 / 300=12 / 400=16 / 500=20 / 600=24 / 700=28 / 800=32 / 1000=40 / 1200=48 / 1600=64 / 2000=80 / 2400=96 / 2800=112 / 3200=128（共 19 階） | :root --p-space-0…3200 |
| 間距階 / 語義 | 6px、16px、16px、8px、8px、16px | :root --p-space-table-cell-padding、--p-space-card-padding、--p-space-card-gap、--p-space-button-group-gap、--p-space-badge-padding-inline、--p-space-choice-size |
| 字級階 | 275=11 / 300=12 / 325=13 / 350=14 / 400=16 / 450=18 / 500=20 / 550=22 / 600=24 / 750=30 / 800=32 / 900=36 / 1000=40（px） | :root --p-font-size-275…1000 |
| 字級階 / 語義 | 11 / 12 / 13 / 14；12 / 13 / 14；18 / 24 / 30；12（px） | :root --p-font-size-body-x-small / -small / -medium / -large、-heading-small / -medium / -large、-display-small / -medium / -large、-button-label |
| 字重階 | 450 / 550 / 600 / 650；button-label=550；heading-small\|medium\|large=600；display-large=650；details-text=450 | :root --p-font-weight-regular / -medium / -semibold / -bold、-button-label、-heading-*、-display-large |
| 行高階 | 300=12 / 400=16 / 500=20 / 600=24 / 700=28 / 800=32 / 1000=40 / 1200=48；body-medium=20；heading-large=20（px） | :root --p-font-line-height-300…1200、-body-medium、-heading-large |
| 圓角階 | 0=0 / 050=2 / 100=4 / 150=6 / 200=8 / 300=12 / 400=16 / 500=20 / 750=30（px）；--p-border-radius-full=9999（624.9375rem） | :root --p-border-radius-0…750 |
| 圓角階 / 語義 | 8px（control/action/element/tag/option-item）；12px（container/popover）；16px（dialog）；4px（checkbox/control-inner/focus/preview）；clamp(4px, round(25%,2px), 8px)（media/avatar）；2px（media-compact/tag-seam/content-highlight） | :root --p-border-radius-control / -action / -element / -tag / -option-item、-container / -popover、-dialog、-checkbox、-control-inner / -focus / -preview、-media / -avatar、-media-compact / -tag-seam / -content-highlight |
| 陰影階 / 卡片 | 六層堆疊（rem→px @16）：0 5px 5px -2.5px rgba(0,0,0,.03) / 0 3px 3px -1.5px rgba(0,0,0,.02) / 0 2px 2px -1px rgba(0,0,0,.02) / 0 1px 1px -.5px rgba(0,0,0,.03) / 0 .5px .5px 0 rgba(0,0,0,.04) / 0 0 0 1px rgba(0,0,0,.06)〔最後一層代替 border〕 | :root --p-shadow-100（＝實測卡片 s-section 的值） |
| 陰影階 / 彈層 | 六層：0 8px 24px -8px rgba(0,0,0,.28) / 0 8px 16px -4px rgba(0,0,0,.05) / 0 3px 6px 0 rgba(0,0,0,.05) / 0 2px 4px 0 rgba(0,0,0,.05) / 0 1px 2px 0 rgba(0,0,0,.05) / 0 0 0 1px rgba(0,0,0,.06) | :root --p-shadow-300 ≡ --p-shadow-popover（＝實測 Polaris-Popover 與 s-popover 兩者的值） |
| 陰影階 / 其餘層級 | 0=none；200=七層（比 100 多一層 0 8px 10px -5px rgba(0,0,0,.08)）；400=六層 0 20px 32px -12px rgba(0,0,0,.2) 起；500=七層 0 24px 36px -12px rgba(0,0,0,.12) 起；600=六層 0 24px 56px -12px rgba(0,0,0,.24) 起（全部以 0 0 0 1px rgba(0,0,0,.06~.07) 收尾） | :root --p-shadow-0 / -200 / -400 / -500 / -600 |
| 陰影 / 按鈕（inset 立體） | primary＝0 -1px 0 1px rgba(0,0,0,.8) inset, 0 0 0 1px #303030 inset, 0 .5px 0 1.5px rgba(255,255,255,.25) inset；primary-inset（按下）＝0 3px 0 0 #000 inset；button-inset＝-1px 0 1px 0 rgba(26,26,26,.12) inset, 1px 0 1px 0 rgba(26,26,26,.12) inset, 0 2px 1px 0 rgba(26,26,26,.2) inset；border-inset＝0 0 0 1px rgba(0,0,0,.08) inset | :root --p-shadow-button-primary、--p-shadow-button-primary-inset、--p-shadow-button-inset、--p-shadow-border-inset |
| 焦點環（實測值，非僅 token） | outline: 2px solid #005bd3；outline-offset: 1px（token --p-color-border-focus=#005bd3、--p-border-radius-focus=4px） | 任一按鈕 :focus-visible 的 outline / outline-offset |
| 髮絲線 | 0 0 0 0.66px #8a8a8a inset —— 次像素常數 0.66px，dpr=1 下實測，與 64 §4 一致 | Polaris-Checkbox__Backdrop box-shadow inset（實測） |
| z-index 階 | 0=auto / 1=100 / 2=400 / 3=510 / 4=512 / 5=513 / 6=514 / 7=515 / 8=516 / 9=517 / 10=518 / 11=519 / 12=520（實測：表格 sticky 區用 510、Popover overlay 用 400、sticky indicator 用 100） | :root --p-z-index-0…12 |
| 表格專用變數 | 6px、8px、12px | :root --p-space-table-cell-padding、--locations-table-cell-horizontal-padding、--locations-table-cell-vertical-padding |

### §7.2 元件量測（31 項）

| # | 元件 | 量測 | 狀態樣式 |
|---:|---|---|---|
| 1 | **頁面外框 / 內容區（版面基準）** | main.page：padding 16px 0；內容區實測 x=240…1008（寬 768，寬度相依）；頂欄高 56px（main 起點 y=56）；左側欄佔位 240px（外層 main._Main_semjk_308 padding-left:240px、bg #f1f1f1、border-radius 12px 12px 0 0）。div.header：高 40px、無底色無邊框；div.header-content：min-height 28px、display:flex、gap 8px、寬 736（＝768−16×2，左右各 16px 內距）。 | — |
| 2 | **頁首標題 H1「Products」** | font-size 18px／font-weight 600／line-height 24px／color #303030／letter-spacing -0.14994px／height 24px／margin 0／overflow hidden。標題左緣 x=278，內容區左緣 x=240 ⇒ 標題前有 22px 的頁面圖示佔位（heading-and-accessory 起於 x=256，即容器內距 16px）。 | —（靜態文字） |
| 3 | **頁首主鈕「Add product」（primary）** | 高 28px（min-height 28px）／內距 6px 12px／圓角 8px／gap 2px／字 12px・550・行高 16px／文字色 #fff／底色 #303030／box-shadow 三層 inset（0 -1px 0 1px rgba(0,0,0,.8) inset, 0 0 0 1px #303030 inset, 0 .5px 0 1.5px rgba(255,255,255,.25) inset）／transition: none／實測寬 95.55（內容相依）。內層 span.content：display flex、gap 2px、高 16px。href=/store/{shop}/products/new（渲染為 <a> 不是 <button>）。 | hover：底色 #303030→#1a1a1a、文字 #fff→#e3e3e3，box-shadow 不變（實體滑鼠 hover 實測，:hover=true）。focus-visible：底色亦變 #1a1a1a、文字 #e3e3e3，另加 outline 2px solid #005bd3 / offset 1px（已在滑鼠移開至 (120,450) 後複驗 :hover=false，證明變底色是 focus 自身效果而非殘留 hover）。active/pressed：**未取得**（見 not_obtained）。disabled：本頁無此態。 |
| 4 | **頁首次鈕「Export」「Import」（secondary）** | 高 28px／內距 6px 12px／圓角 8px／gap 2px／字 12px・550・16px／色 #303030／底色 #e3e3e3／**box-shadow: none**（無斜角浮雕）／transition: none／實測寬 61.8。 | hover：底色 #e3e3e3→#d4d4d4（＝--p-color-bg-fill-tertiary-hover），文字色不變、無邊框變化、無陰影。focus-visible：底色同樣 #d4d4d4 ＋ outline 2px solid #005bd3 / offset 1px。active：**未取得**。 |
| 5 | **頁首「More actions」（secondary + 下拉箭頭）** | 高 28px／**內距 4px 6px 4px 12px（右側為容納 caret 收窄）**／圓角 8px／gap 2px／字 12・550・16／底色 #e3e3e3／色 #303030／寬 115.08。內層 span.content 高 20px（比純文字鈕的 16px 高，因含 16×16 caret 圖示）。 | hover 同 secondary（#d4d4d4）。展開的選單為 s-popover（見下）。 |
| 6 | **頁首響應式容器** | 次要動作有兩套 DOM：`div.show-from-md`（≥md 顯示三顆獨立按鈕 Export / Import / More actions）與 `div.hide-from-md`（<md 全部塞進一個 s-menu：Export / Import / Show analytics bar / …）。1024px 下 show-from-md 生效。 | — |
| 7 | **篩選列外框（SearchBarPlus，2026 新形態）** | 外層 Polaris-Box 高 45px（含 1px 下緣）／實際 44px、內距上下 8px 左右 8px（InlineStack 起於 x=264 ⇒ 卡片左緣 256 + 8）。_SearchBarPlus_：高 28px、底色 #fff、圓角 8px、box-shadow none、padding 0 4px 0 0、display flex、寬 675（寬度相依）。🔴 **沒有傳統的 tab pill 列**：檢視改成單一下拉活化鈕 ＋ 統一搜尋/篩選輸入框 ＋ 分隔線 ＋ 右側圖示鈕群。 | 聚焦搜尋框時 _SearchBarPlus_ 的 background/box-shadow/outline 皆不變（實測 bg #fff、shadow none、outline none）。 |
| 8 | **檢視分頁活化鈕（「All」/「Draft」/「Archived」，取代 tab）** | 高 24px／內距 **0px 2px 0px 8px**（左 8、右 2，右側留給 ⇅ caret）／圓角 8px／底色 transparent／色 #303030／字 13px・500・行高 20px／display inline-flex／overflow hidden／transition: max-width 0.3s cubic-bezier(0.42,0,0.58,1)。實測寬 50.8（「All」）、「Draft」與「Archived」時隨字寬變化。內層標籤 div 高 24、字 13/500/20。 | 選中態＝按鈕文字即為當前檢視名（無底色差異）；展開後在彈層裡以 aria-checked=true ＋ ✓ 圖示表示選中。未選：aria-checked=false。hover：**未取得**（本輪只 hover 了彈層項目，未單獨 hover 活化鈕）。 |
| 9 | **檢視彈層（All / Active / Draft / Archived 值域窮舉）** | 彈層：寬 188、高 120（4 項時）、bg #fff、圓角 12px（Polaris-Popover 與 ContentContainer 皆 12px；內層 Polaris-Popover__Content 為 4px）、box-shadow ＝ --p-shadow-300 六層、overflow hidden、外層 PositionedOverlay z-index 400、內距 Polaris-Box 4px。項目：role=menuitemradio、180×28、內距 4px 32px 4px 4px、圓角 8px、gap 8px、字 13px・500・20px、色 #303030、底色 transparent。**值域恰 4 個：All（aria-checked=true）/ Active / Draft / Archived**；選中項行尾另有 ⋯（更多）鈕（hover 才出現）。切換寫入 URL ?savedViewId=<id>（Draft=1362993512683、Archived=1362993545451）。 | hover：底色 transparent→rgba(0,0,0,0.05)，文字色不變（實體滑鼠 hover 實測）。選中：aria-checked=true ＋ 左側 ✓ 圖示，**底色不變**。 |
| 10 | **搜尋／篩選輸入框（contenteditable，非 <input>）** | 高 28px／字 13px・500・行高 20px／色 #303030／caret-color #303030／overflow: auto hidden（單行橫向捲動）／底色 transparent／無框無圓角。空態內距 **4px 28px 4px 4px**；有內容時內距變 **4px 28px 4px 8px**（左內距 4→8）。placeholder 由 ::before 繪製：content "Search and filter"、color #616161、13px/500/20px。左側 🔍 圖示 16×16。 | 填入查詢後：URL 帶 ?query=<term>+status%3AARCHIVED&order=created_at+desc&selectedColumns=…；篩選列右側自動多出「Show view filters」(眼睛) 與「Reset view」「Save」三個控件。focus 時容器無可見焦點環（實測 outline none / shadow none）。 |
| 11 | **篩選列分隔線** | 1×20px、background #ebebeb、margin 0 8px（左右各 8px）、圓角 0。 | — |
| 12 | **「Display options」欄位選擇鈕（tertiary icon-only）** | 28×28／內距 4px／圓角 8px／底色 transparent／色 #8a8a8a／box-shadow none／字 12・550・16／transition none。 | hover：底色 transparent→rgba(0,0,0,0.05)、色 #8a8a8a→#616161（實測）。點開為 s-popover：276×341、bg #fff、圓角 12px、box-shadow ＝ --p-shadow-300 六層（與 Polaris-Popover 同一視覺規格）。active：**未取得**。 |
| 13 | **「Reset view」/「Show view filters」/「Save」（僅在檢視被改動時出現）** | Reset view：28×28、內距 4px、圓角 8px、底色 transparent、色 #b5b5b5（閒置）／#8a8a8a（有查詢時）、margin -4px。Save：高 28、內距 4px 6px 4px 12px、圓角 8px、底色 transparent、色 #b5b5b5（閒置）／#303030（有查詢時）、字 12・500・16、寬 52.1→68.1（隨狀態）。Show view filters：28×28、內距 4px、圓角 8px、色 #8a8a8a。四個控件在 1024 寬下的 x 依序為 817.9 / 851.9 / 885.9 / 915.9（寬度相依）。 | 未改動檢視：Reset/Save 色 #b5b5b5（視覺 disabled 感，但無 disabled 屬性）。改動後：Save 色轉 #303030。hover：**未取得**。 |
| 14 | **表格外殼（卡片）** | bg #fff／border-radius 12px／**border-width 0（無 border）**／overflow clip／padding 0／margin 0／box-shadow 六層 ＝ --p-shadow-100（最後一層 0 0 0 1px rgba(0,0,0,.06) 代替邊框）。寬 736（寬度相依）。 | — |
| 15 | **表格骨架（🔴 非 <table>）** | 頁面**沒有任何 <table> 元素**（deep querySelectorAll('table').length === 0）。.Polaris-Table 為 **display:grid**；.Polaris-Table-TableHead / -TableHeadingRow / -TableBody / -TableRow 全部 **display:contents**（列不是盒，樣式掛在儲存格上）。實測 grid-template-columns（1024 寬、預設 9 欄）= `36px 52px 200px 75.4062px 156.5px 96.4062px 83.8125px 80.75px 101.906px 153.891px 44px`（首列 36 為勾選欄、次列 52 為縮圖欄、末列 44 為 sticky 動作欄）；grid-template-rows = `0px 52px 53px 53px …`（首列 0 是隱藏量測列）。.Polaris-Table bg #fff、寬 1080.67（橫向捲動內容寬）；.Polaris-Table__TableScrollable overflow:auto、寬 736；TableWrapper overflow: clip。另有 .Polaris-Table-TableScrollBar（自繪橫捲軸，高 11px）。 | 橫向捲動時 .Polaris-Table-TableStickyIndicators__TableStickyIndicatorStart/End：1px 寬、bg #e3e3e3、box-shadow ±1px 0 3px rgba(0,0,0,.05)、z-index 100，靠 opacity 0↔1 顯示（實測起始側 opacity 0、結束側 opacity 1）。 |
| 16 | **表頭（TableHead / HeadingCell）** | 每格 min-height **36px**、實測高 36／bg **#f7f7f7**／color **#616161**／字 **12px・500・行高 16px**／align-items center／**border-bottom 1px solid #e3e3e3**／box-shadow none。內距依欄型不同：勾選欄 `6px 6px 6px 12px`；一般欄 `6px`；數值右對齊欄（Channels/Catalogs）`6px 24px 6px 6px`（--activatorOffset）；末端 sticky 動作欄 `6px 12px 6px 6px`；可排序欄 `0px`（內距移進按鈕）。共 22 個 heading cell ＝ 11 可見 ＋ 11 個 `HeadingCell__Hidden`（高 0、border 0，作 sticky 量測影子列）。 | hover 表頭格：bg 維持 #f7f7f7（**不變色**）。 |
| 17 | **可排序欄標題鈕** | 高 28px／內距 6px／**圓角 0**／底色 transparent／色 #616161／字 12・500・16／display flex、align-items center／cursor pointer。可排序欄實測＝Product / Inventory / Product type / Vendor（Status、Category、Channels、Catalogs 不可排序）。 | 排序圖示 div.Polaris-Table-TableHeadingCell__SortIcon：16×16、color #616161、**opacity 0（閒置）→ 1（hover）**、transition `opacity 0.1s cubic-bezier(0.42,0,0.58,1)`。hover 時按鈕底色仍 transparent、文字色不變、無底線 —— 只有圖示淡入。 |
| 18 | **資料列與儲存格** | **列高 53px（52px 內容 + 1px 上分隔線）**；儲存格 min-height 32px、padding 0（內距在內層）、bg #fff、色 #303030、字 12px・500・行高 16px；**分隔線是每格的 border-top: 1px solid #e3e3e3（不是 border-bottom）**、box-shadow none。內層 div.Polaris-Table-TableCell__TableCellContent：高 52px、display flex、align-items center、white-space nowrap；內距＝勾選欄 `6px 6px 6px 12px`、其餘欄 `6px`。整列可點（cursor: pointer），主連結為 a._Link_lixg6_1 href=/store/{shop}/products/{id}。首頁 50 列。 | hover：**全部儲存格** bg #fff→**#f7f7f7**（列為 display:contents，變色作用在每個 cell），無邊框變化、無陰影、無位移。selected（勾選後）：列加上 class `Polaris-Table-TableRow__Selected`，儲存格 bg 同樣 **#f7f7f7**（🔴 與 hover 同色，選取態沒有獨立底色）。active（按下）：**未取得**。 |
| 19 | **商品名連結** | a：字 12px・500・行高 16px、色 **#303030**（非藍）、display block、無底線、white-space nowrap、寬 175.73（＝200 欄寬 − 12 內距 − 省略）。內層 LineClamp span：display flow-root、`-webkit-line-clamp: 2`、overflow hidden、text-overflow ellipsis、word-break break-word ⇒ **最多兩行**；兩行名稱不撐高列（2×16=32 < 52−12）。 | 列 hover 時連結出現 **text-decoration: underline**（decoration color #303030），字色與字重不變。 |
| 20 | **儲存格縮圖** | **40×40**／border-radius computed = `clamp(4px, round(25%, 2px), 8px)` ⇒ 40px 尺寸下解析為 **8px**（25%×40=10 → 依 2px 量化 =10 → 上限 8）／overflow hidden／bg transparent。有圖：內層 <img> 40×40、object-fit **contain**、自身 radius 0（由外層 overflow:hidden 裁切）。無圖：div.thumbnail-empty 40×40、bg **#fff**、同 radius、內含 s-icon 佔位。所屬儲存格欄寬 52 ⇒ 40 + 6×2 內距。 | —（無 hover 差異，實測未見） |
| 21 | **狀態 Badge（tone 值域窮舉）** | **共同幾何**：高 20px／內距 **2px 8px**／圓角 **8px**／gap 4px／字 **12px・550・行高 16px**／display flex／無 border／box-shadow none。**tone 值域（本店實測四種）**：① Active → host `tone=success`、class `tone-success`、bg **#affebf**、文字 **#014b40**（實測寬 52.52）；② Draft → host `tone=info`、class `tone-info`、bg **#d5ebff**、文字 **#003a5a**（寬 44.47）；③ Unlisted → **無 tone 屬性**、class `tone-auto color-base`、bg **rgba(0,0,0,0.06)**、文字 **#616161**（寬 63.41）；④ Archived → 同 ③ 無 tone、bg rgba(0,0,0,0.06)、文字 #616161（寬 67.69）。🔴 **Unlisted 與 Archived 共用同一個中性 tone，靠文字區分**。 | 無 hover / focus 差異（純展示元件）。critical / warning / caution tone 在本頁未出現（token 值見 §1）。 |
| 22 | **列勾選框** | 可視方塊 **16×16**、圓角 **4px**；命中區 CheckboxHitState / Choice__Control / label 皆 **18×18**（比視覺大 1px 外擴）；span.Polaris-Checkbox margin 1px。真 <input> 16×16、position absolute、**opacity 0**（視覺全由 Backdrop 承擔）。勾圖 span.Polaris-Checkbox__Icon 12×12、position absolute、margin 2px；內含 svg 12×12、color #fff。 | **未選**：Backdrop bg #fff、box-shadow `0 0 0 0.66px #8a8a8a inset`（＝髮絲線邊框）、Icon opacity 0。**選中**：Backdrop bg **#303030**、box-shadow `0 0 0 32px #303030 inset`（用超大 spread 的 inset 做填色動畫）、Icon opacity 1、svg color #fff。**半選（indeterminate）**：DOM 的 `input.indeterminate` 屬性為 **false**，改由 class 表示 —— `Polaris-Checkbox__Input--indeterminate` ＋ `Polaris-Checkbox__IconIndeterminate`，Backdrop 與選中同（#303030 / inset 32px），Icon opacity 1 但改畫短橫。**focus-visible**：Backdrop bg #fff→**#fafafa**，另加 outline 2px solid #005bd3（radius 4px 不變）。Backdrop transition：`border-color .1s cubic-bezier(.19,.91,.38,1), border-width .1s …, box-shadow .1s …`（三屬性同時 100ms，與 47 §5 M3 一致）。 |
| 23 | **全選勾選框（表頭）** | 外框 CheckboxWrap 18×18、padding 0、display flex；勾選框本體同列勾選框（16×16、radius 4、髮絲線 0.66px #8a8a8a）。aria-label「Select all 50 on page」。 | 部分選取時進入 indeterminate：Backdrop bg #303030 + inset 32px、Icon opacity 1，但 input.checked=false / input.indeterminate=false（純 class 驅動，見上）。 |
| 24 | **批次操作列（Bulk actions bar）** | 🔴 **覆蓋在表頭列上（絕對定位，非另開一條）**：StickyBulkActions position absolute、z-index **510**、高 **36px**、bg transparent、**border-bottom 1px solid #e3e3e3**、box-shadow none。Inner：高 35、bg **#f7f7f7**、內距 **2px 4px 2px 12px**。TableActions：display flex、align-items center、**gap 4px**、min-height 31px、寬 720。內容（1 列選取時實測）＝ 半選勾選框 ｜「1 selected ⌄」｜「Bulk edit」｜「Set as draft」｜「⋯」｜右側「Show all selected」開關。 | 僅在選取 ≥1 列時存在（取消勾選後元素整個移除，實測 bulkBarPresent=false）。 |
| 25 | **批次列按鈕（Polaris micro 尺寸）** | 全部 **高 24px**、圓角 8px、gap 2px、字 13px・500。①「1 selected」= variantTertiary：bg transparent、色 #303030、內距 `4px 4px 4px 8px`、寬 94。②「Bulk edit」= variantSecondary：bg **#fff**、色 #303030、內距 `4px 8px`、box-shadow **三層浮雕** `0 -1px 0 0 #b5b5b5 inset, 0 0 0 1px rgba(0,0,0,.1) inset, 0 .5px 0 1.5px #fff inset`、寬 65.6。③ 圖示鈕（Actions ⋯）= variantSecondary icon-only：24×24、內距 2px、同浮雕陰影。 | **disabled**（實測列中多顆）：bg **rgba(0,0,0,0.05)**、色 **#b5b5b5**、**box-shadow: none**（浮雕消失）、幾何不變。🔴 注意此處 secondary 的浮雕陰影與頁首 s-button secondary 的「純 #e3e3e3 無陰影」是兩套不同視覺（見 §3）。 |
| 26 | **「Show all selected」開關（switch）** | 軌道 = 被樣式化的 <input type=checkbox>：**32×16**、border-radius **9999px**、bg **#fdfdfd**、border **1px solid #8a8a8a**、padding 0 2px、transition `background-color .1s cubic-bezier(.42,0,.58,1), border-color .1s …`。外層 label：高 28、padding 4px 0、寬 148、字 13px・450（🔴 web-component 層字重 450，非 500）。整組含標籤寬 156（Polaris-Box padding-right 8px）。 | 實測為 unchecked（checked=false）。checked 態 **未取得**（切換它會改變選取範圍語義，本輪唯讀不觸發）。 |
| 27 | **分頁控制（Footer）** | Footer 容器：高 **45px**（min-height 41px）、bg **#f7f7f7**、**border-top 1px solid #e3e3e3**、內距 `8px 8px 8px 12px`、gap 8px、圓角 0、寬 736。StickyFooter 外層高 60px。分頁鈕（segmented）：各 **28×28**、內距 4px、bg **#e3e3e3**、gap 2px、字 13px・500・行高 13px、box-shadow none；**圓角只在外緣**：Previous `8px 0 0 8px`、Next `0 8px 8px 0`。範圍文字「1-50」：span.Polaris-Text--bodySm.Polaris-Text--medium、12px・500・行高 16、色 **#616161**。 | **disabled**（第一頁的 Previous）：以 **aria-disabled="true"** 表示（`button.disabled` 仍為 false），色 #303030→**#b5b5b5**，**底色維持 #e3e3e3、cursor 仍為 pointer、opacity 仍 1**。enabled（Next）：色 #303030。🔴 **結果不足一頁時整個 Footer 不渲染**（Archived 檢視 4 列時 footerPresent=false）。 |
| 28 | **列尾動作鈕（RowActions）** | 容器 RowActions：display flex、justify-content flex-end、**gap 4px**、padding `0 0 0 6px`、高 20、寬 26、bg transparent。按鈕：**28×28**、內距 4px、圓角 8px、bg transparent、色 #303030、box-shadow none、字 12px。實測 aria-label =「Preview on Online Store」（眼睛圖示）。 | 列 hover 時 RowActions visibility visible / opacity 1（未 hover 時本輪未單獨取值，登記為部分未取得）。另有 `RowActionsStuck` class 用於橫向捲動時吸附（本輪未觸發）。 |
| 29 | **空態（Empty state，以無結果查詢觸發）** | 容器 Polaris-Box：**padding 32px 0**、寬 736；內層 Polaris-BlockStack **gap 20px**（內部 LegacyStack__Item margin-top 16px）。① 插圖 <img alt="Empty search results"> **60×60**（src 為 data:image/svg+xml 內聯，內容未複製）。② 標題「No products found」= p.Polaris-Text--root.Polaris-Text--headingLg：**18px・500・行高 24px**、色 #303030、letter-spacing **-0.14994px**、高 24。③ 說明「Try changing the filters or search term」= <p>：**13px・500・行高 20px**、色 **#616161**。④ 主鈕「Clear search and filters」= s-internal-button[variant=primary]：高 28、內距 6px 12px、圓角 8px、bg #303030、色 #fff、字 12・550・16、三層 inset 陰影（與頁首 Add product 完全同規格）、寬 158.2。整塊高 253。 | 空態下表頭列與分頁列均不渲染，只剩篩選列 + 空態盒。 |
| 30 | **卡片外的頁尾說明** | Polaris-FooterHelp：display flex、justify-content center、**margin 20px**、字 13px・500・行高 20、色 #303030。內含 tertiary 按鈕「Learn more about products」：高 28、內距 6px 12px、圓角 8px、bg transparent、色 #303030、字 12・550・16、寬 180.3。 | hover **未取得**。 |
| 31 | **圖示尺寸普查** | 全頁可見 s-internal-icon 的 svg 尺寸分佈：**16×16 共 183 個**、12×12 共 8 個、8×8 共 2 個 ⇒ **16px 是唯一常規圖示尺寸**（Lucide 對應 size=16）。圖示以 currentColor 繼承（fill 隨 color 走）。 | — |

### §7.3 觀察到的視覺規律

1. 🔴 **表格已不是 <table>，而是一張 CSS Grid**：全頁 `document.querySelectorAll('table').length === 0`；`.Polaris-Table` 是 `display:grid`，TableHead / TableHeadingRow / TableBody / TableRow 一律 `display:contents`。欄寬由 `grid-template-columns` 一次宣告（1024 寬下 11 條軌道），列高由 `grid-template-rows` 逐列給值。我方 IndexTable.tsx 若仍用 <table> 或 flex 列，sticky 欄、橫捲影子列、選取覆蓋層這三件事會做不出同樣行為。
2. 🔴 **列分隔線畫在儲存格的 border-top，不是列的 border-bottom**（每格 `border-top: 1px solid #e3e3e3`）。因為列是 display:contents 不能承載邊框。第一列因此靠表頭的 border-bottom 收邊，形成「表頭 1 條 + 每列 1 條」的節奏。
3. 🔴 **hover 底色與 selected 底色是同一個值 #f7f7f7**（--p-color-bg-surface-hover ≡ --p-color-bg-surface-secondary）。選取態只用 class `TableRow__Selected` 與勾選框填色區分，**不用底色分層**。我方若給選取態另一種底色即偏離本尊。
4. **同一頁並存兩套設計系統，字重與按鈕視覺各不相同**。(a) Web Component 層（`s-*` + shadow root）：字重取自 --p-font-weight-* 的 450/550/600/650，secondary 按鈕是 **純 #e3e3e3 平面、box-shadow: none**；(b) Polaris React 層（`Polaris-*` class）：~~base font-weight computed 為 **500**（不在 --p-font-weight-* 階裡）~~ 🔴 **2026-08-28 撤回：那是量測環境污染，見 §7.6 與 `docs/design/111` §20**，secondary 按鈕帶 **三層浮雕 inset 陰影**（0 -1px 0 0 #b5b5b5 inset, 0 0 0 1px rgba(0,0,0,.1) inset, 0 .5px 0 1.5px #fff inset）。同一畫面上「Export」（e3e3e3 平面）與批次列「Bulk edit」（白底浮雕）就是這兩套的對照。我方要選一套並貫徹，不能兩邊各抄一半。
5. **互動控件高度只有三階**：28px（頁首按鈕 / 篩選列圖示鈕 / 表頭排序鈕 / 分頁鈕 / 列尾動作鈕 / 空態主鈕）、24px（檢視活化鈕、批次列 sizeMicro 按鈕、Badge 是 20）、18px（勾選命中區）。**28 是絕對主力**。
6. **圓角只用三階**：8px（一切互動控件：按鈕、輸入框、彈層項目、Badge、分頁外緣）、12px（容器：卡片 s-section、Popover、s-popover）、4px（勾選框、焦點環）。另有 9999px 只給 switch 軌道。**沒有 2px / 6px / 16px 出現在本頁**。
7. **間距全部落在 4 的倍數**（實測出現值：2、4、6、8、12、16、20、24、32），且 6px 是表格儲存格的專用內距（--p-space-table-cell-padding = .375rem = 6px），12px 只出現在「列首欄的左內距」與「sticky 末欄的右內距」——**表格左右兩端比中間多 6px 的呼吸**。
8. **陰影全部是多層堆疊，且最後一層一定是 `0 0 0 1px rgba(0,0,0,.06)` 取代 border**。卡片用 6 層（--p-shadow-100），彈層用 6 層但第一層更深更遠（--p-shadow-300，0 8px 24px -8px rgba(0,0,0,.28)）。實測 s-section 與 Polaris-Popover / s-popover 三者的陰影字串與 token 逐字相同 ⇒ **兩套系統的陰影規格是統一的**（與按鈕視覺不統一形成對比）。
9. **hover 的規則是「只改底色（與圖示色），絕不改邊框、陰影、尺寸或位移」**。實測四例：primary #303030→#1a1a1a；secondary #e3e3e3→#d4d4d4；tertiary transparent→rgba(0,0,0,.05)；資料列 #fff→#f7f7f7。box-shadow / transform / border 在所有 hover 前後皆逐字相同。
10. **focus-visible 一律是 `outline: 2px solid #005bd3` + `outline-offset: 1px`，而且同時套用 hover 級的底色**（已在滑鼠移開後複驗 `:hover === false`）⇒ 鍵盤使用者拿到「底色 + 外環」雙重回饋。這比 47 §H2-3′ 記的「outline 與 box-shadow 兩種並用」更具體：本頁實測到的是 outline 這一種。
11. **髮絲線是固定次像素常數 0.66px，用 inset box-shadow 畫**（`0 0 0 0.66px #8a8a8a inset`），在 dpr=1 下實測，與 64 §4 完全一致 —— 再次確認它不是 1px/dpr 的算式。
12. **勾選框的「填色」是用超大 spread 的 inset 陰影做的**（未選 `0 0 0 0.66px #8a8a8a inset` → 選中 `0 0 0 32px #303030 inset`），配 100ms 三屬性同時轉場（border-color / border-width / box-shadow，cubic-bezier(.19,.91,.38,1)）。這樣邊框可以從外往內「長滿」，用 background-color 做不出同樣動畫。
13. **半選（indeterminate）不走 DOM 屬性**：實測 `input.indeterminate === false`，靠 class `Polaris-Checkbox__Input--indeterminate` / `Polaris-Checkbox__IconIndeterminate` 驅動。我方若只設 DOM property 而不加 class，樣式不會出現。
14. **disabled 用 aria-disabled 而非 disabled 屬性**（分頁 Previous 實測 `button.disabled === false`、`aria-disabled="true"`），視覺上**只降文字色**（#303030→#b5b5b5），底色、opacity、cursor 全部不變；批次列的 disabled 則是 bg→rgba(0,0,0,.05)、色→#b5b5b5、**陰影抹平為 none**。兩種 disabled 表現法並存。
15. 🔴 **2026 版篩選列已無 tab pill 列**：檢視（All / Active / Draft / Archived）收進一個 24px 高的下拉活化鈕，與搜尋框、分隔線、右側圖示鈕群共用一條 28px 高的白色 SearchBarPlus。搜尋框是 **contenteditable div**（不是 <input>），placeholder 由 `::before` 的 content 繪製。切換檢視寫入 `?savedViewId=<id>`，輸入查詢寫入 `?query=…&order=…&selectedColumns=…`。
16. **篩選列右側控件是條件顯示的**：預設只有「Display options」(欄位)；檢視含篩選時多出「Show view filters」(眼睛)；檢視被改動時再多出「Reset view」與「Save」（未改動時這兩者以 #b5b5b5 呈現、不是真 disabled）。**整條列裡沒有獨立的『排序鈕』—— 排序只在欄標題**（Product / Inventory / Product type / Vendor 四欄可排序，Status / Category / Channels / Catalogs 不可）。
17. **排序圖示常駐但 opacity 0，hover 才淡入**（100ms、cubic-bezier(.42,0,.58,1)）；hover 時表頭底色與文字色都不變，只有圖示出現 —— 這是本頁唯一一個「hover 不改底色」的控件。
18. **批次操作列是絕對定位覆蓋在表頭列之上**（z-index 510、高 36 與表頭同高、bg #f7f7f7），不是插入一條新列 ⇒ 選取時表格不跳行。取消選取後元素整個從 DOM 移除。
19. **縮圖圓角用 clamp + round 做成尺寸自適應**：`clamp(4px, round(25%, 2px), 8px)`。40px 縮圖解析為 8px（25%→10px→2px 量化→上限 8）；小縮圖會自動降到 4px。我方若寫死 8px，小尺寸時會過圓。
20. **商品名最多兩行**（`-webkit-line-clamp: 2` + word-break: break-word + ellipsis），且兩行不撐高列 —— 列高恆為 53px（52 + 1px 線），實測含兩行中文/英文名稱的列高度與單行完全相同。
21. **分頁列在結果不足一頁時整個不渲染**（Archived 4 列時 `.Polaris-Table-TableFooter` 不存在），不是渲染成 disabled 的空殼。
22. **圖示只有一種常規尺寸 16×16**（全頁 183/193 個），12 與 8 是特例（badge 內小記號等）。

### §7.4 🔴 與既有量測文件的衝突（照登記，未逕行覆寫）

1. 🔴 **與 64 §3「Pill、主要按鈕 13 / 20 / 500」衝突**。我實測商品列表頁的 primary（Add product）、secondary（Export / Import / More actions）、tertiary（Display options / Learn more / 列尾動作）**全部是 12px / 550 / 行高 16px**，不是 13/20/500。同時 **47 §6.5 記的是「字級 12/16，字重 550 ← 注意是 550，不是 500 或 600」，與我的量測一致**。⇒ 47 與 64 在按鈕字級這一項本來就互相衝突，本輪站在 47 那一側。可能成因：64 量的是商品**詳情頁**的 Save 按鈕（可能屬 Polaris React 層，該層 base font-weight computed 為 500），而列表頁頁首按鈕屬 s-button web-component 層（用 --p-font-weight-button-label = 550、--p-font-size-button-label = 12px）。**建議處置：兩者都對，但必須標明是哪一層的按鈕**；不標層次直接引用會做錯一半的按鈕。

2. 🔴 **與 47 §7「檢視 tab（全部）60×24、圓角 8、內距 0/2、字 13/20/500」的內距不符**。我實測 `button._Activator_kx3a9_1` 的 padding 是 **`0px 2px 0px 8px`**（左 8px、右 2px，左右不對稱），不是對稱的 0/2。高 24、圓角 8、字 13/20/500 三項一致；寬度差異（60 vs 50.8）只是語言差（「全部」vs「All」），不算衝突。⇒ **47 §7 的「內距 0/2」應更正為「0 / 右2 / 0 / 左8」**：右側收窄是為了容納 ⇅ caret。

3. **與 64 §4「Switch 32×24（內距 4/0）」不完全一致**。我在批次列量到的 switch 是 `input[type=checkbox]` 本體 **32×16**、radius 9999px、padding `0 2px`、border 1px solid #8a8a8a，外層 label 高 28、padding `4px 0`。⇒ 64 的「24 高」可能是量到含上下 4px 內距的 label 盒（16+4+4=24）。**建議處置：把 64 的數字拆成「軌道 32×16 / 命中盒 32×24」兩行**，否則實作會把軌道畫成 24 高（過胖）。

4. **47 §3 字級階把 `--t-xs` 定為「12 / 16 / 500」**。我實測儲存格確實是 12/16/**500**（Polaris React 層），但**同一頁的 Badge 是 12/16/550、頁首按鈕也是 12/16/550**（s-* web-component 層），而 `--p-font-weight-*` token 階裡**根本沒有 500 這一階**（只有 450/550/600/650）。⇒ 47 的「500」是 React 層的實測值沒錯，但它不是設計系統的 token 值。**建議處置：`--t-xs` 拆成 `--t-xs-data: 12/16/500`（表格資料，React 層）與 `--t-xs-control: 12/16/550`（Badge、按鈕，web-component 層）**，否則我方只會有一種 12px 字重，兩層之一必然對不上。
   > 🔴🔴 **2026-08-28 撤回這個建議**：分階的依據「React 層 12/16/**500**」是**量測環境污染**（`docs/design/111` §20），不是本尊事實 ⇒ **不需要拆兩階**。乾淨值見本檔 **§7.6**。

5. **47 §0 記載的量測環境根字級為 24px（污染）並警告「凡涉及 border-width 的數字一律作廢」**。本輪根字級為 **16px**，所有 rem 值 1:1，且 border 值直接實測（表頭 border-bottom 1px solid #e3e3e3、儲存格 border-top 1px solid #e3e3e3、髮絲線 0.66px）。⇒ 本檔的邊框數字可直接用來回填 47 §C 那批被作廢的值。

6. **64 §6 記「pill 與按鈕的 transition 實測是 all」，我方 lint 禁止 transition:all，記為刻意偏離**。本輪補一個更精確的事實：**s-button 的 transition computed 是 `none`（不是 all）**（primary/secondary/tertiary 三者皆 none）；`all` 出現在 Polaris React 層的容器 div 與 `_SlimTertiaryButton_` 上。⇒ 64 §6 的「按鈕 transition: all」在 2026 版的 s-button 上已不成立，該節應加註日期與適用層。真正具名的 transition 本輪只量到三處：勾選框 Backdrop（border-color/border-width/box-shadow 各 0.1s cubic-bezier(.19,.91,.38,1)）、排序圖示（opacity 0.1s cubic-bezier(.42,0,.58,1)）、switch（background-color/border-color 各 0.1s cubic-bezier(.42,0,.58,1)）、檢視活化鈕（max-width 0.3s cubic-bezier(.42,0,.58,1)）。

7. **與我方 IndexTable.tsx 的結構前提可能衝突（未讀我方原始碼，僅就本尊事實提示）**：本尊 2026 的列表**沒有 <table>**、列是 `display:contents`、分隔線在儲存格 border-top、選取態與 hover 態同色 #f7f7f7、批次列是覆蓋在表頭上的絕對定位層。若我方 IndexTable 以 <table>+<tr> 實作並給選取態獨立底色，這四點都會與本尊不一致，屬鐵律 12 要求「修到一致」的範圍（除非進 71 §A 保護清單或登記 V）。

### §7.5 未取得（鐵律 19.3）

- **所有元件的 :active／pressed 態**。原因：`javascript_tool` 的執行世界收不到頁面的滑鼠事件 —— 實測在 document 上以 capture 註冊 pointerdown/mousedown/mouseup 監聽（並確認 `window.__evt` 跨呼叫存活），對按鈕實際點擊後陣列長度仍為 0；同時 `computer` 工具沒有「按住不放」的原語，無法在按壓中途讀 computed style。取得方式：改用 CDP `CSS.forcePseudoState({forcedPseudoClasses:['active']})`，或在 headless Playwright 中用 `page.mouse.down()` 後再讀 `getComputedStyle`。可參照的 token（僅為 token 值，**不是量測到的元素狀態**）：--p-shadow-button-primary-inset = `0 3px 0 0 #000 inset`、--p-shadow-button-inset、--p-color-bg-fill-brand-active = #1a1a1a、--p-color-bg-surface-active = #f3f3f3。
- **1280 / 768 / 390 三寬度的並排形態**（鐵律 13.1）。原因：本輪 innerWidth 固定 1024，且同一 Chrome 視窗有其他代理併行量測，resize_window 會污染他們的量測環境。影響範圍：所有標「寬度相依」的數值 —— 內容區寬 768、卡片寬 736、grid-template-columns 的 11 條軌道值、SearchBarPlus 寬 675、篩選列右側控件的 x 座標。取得方式：另開一個獨立 Chrome 視窗（或等其他代理收工）後，於 1280/768/390 各重跑一次同一段 grid-template-columns 與容器寬量測。
- **檢視活化鈕（All ⌄）自身的 hover 態**。原因：本輪只 hover 了展開後的彈層項目，未單獨 hover 該鈕。取得方式：實體滑鼠 hover 至 (291,134) 後讀 `button._Activator_kx3a9_1` 的 backgroundColor / color。
- **列尾動作鈕（RowActions）在未 hover 時的 opacity / visibility 基準值**。原因：量測時滑鼠正停在該列上，只取到 hover 後的 opacity 1 / visibility visible。取得方式：把滑鼠移到表格外後重讀 `.Polaris-Table-TableRow__RowActions` 的 opacity/visibility。
- **「Show all selected」開關的 checked 態樣式**（軌道底色、拇指位移、transition 終值）。原因：切換它會改變選取語義，本輪維持唯讀未觸發。取得方式：勾選一列 → 點該開關 → 讀 `s-internal-switch::shadowRoot > label > input` 的 backgroundColor / borderColor / ::before 的 transform → 再關掉。
- **Display options 彈層內部的選項值域與逐項樣式**。原因：彈層本體已量到（s-popover::shadowRoot > div.popover.is-height-capped，276×341、bg #fff、radius 12px、--p-shadow-300 六層），但內部項目在後續呼叫中彈層已被 Escape 關閉，未取到逐項 computed。取得方式：點開後在**同一個** browser_batch 內接著 deep-query `s-popover` shadow root 內的 label / [role=menuitemcheckbox]。
- **Badge 的 critical / warning / caution / magic 四種 tone 的實際渲染值**。原因：本店商品狀態只出現 Active / Draft / Unlisted / Archived 四種，其餘 tone 不會在商品列表出現。token 值已列於 §1，但**未在元素上實測**。取得方式：到訂單列表（付款/出貨狀態含 critical/warning）或庫存頁量。
- **排序啟用後（aria-sort=ascending/descending）的欄標題樣式**。原因：本輪未點擊排序（避免改變檢視狀態）。實測所有欄標題的 `aria-sort` 皆為 null。取得方式：點一次欄標題後讀 heading cell 的 aria-sort 與 SortIcon 的 opacity/transform，再點回原序。
- **--s-token-* 系列（2026 新 web-component 設計系統的獨立 token 集）的完整值**。原因：讀取時被工具的敏感字串過濾器擋下（回傳 `[BLOCKED: Sensitive key]`），該過濾器對 `--s-token-...` 的鍵名誤判。已知它存在（例如 --s-token-font-size-body-large-when-mobile-p1s0、--s-condition-true-p1s0 等 698 條之中的一部分）。取得方式：改成逐鍵單獨讀值並以陣列回傳，或先對鍵名做 base64/切段再回傳。
- **其他被 47/64 已涵蓋而本輪刻意未重複的項目**：全域斷點清單、動效具名 transition 全表、頂欄與側欄細節、卡片群組的單邊圓角用法。這些不是取不到，是依指派範圍排除。

---

### §7.6 🔴 更正：量測環境污染與量錯層（2026-08-28）

> 本節依**鐵律 19.5**（更正不得抹除歷史）追加。**上方原記載保留原文**，
> 下表逐項給出乾淨值。更正的來源與方法＝`docs/design/111` §20。

**兩類錯誤，逐項標明**：

- **污染**：使用者 Chrome 的擴充功能注入 `<style id="font-bolder-style">`，
  規則為 `body, body :not(svg):not(svg *):not(img):not(video):not(canvas) { font-weight: 500 !important }`。
  🔴 它是**固定值 500 加 `!important`** ⇒ 把 450 **拉高**、把 550 **壓低**，
  **看到 500 無法回推真值**。
  🔴 **shadow DOM 不是無條件免疫**：污染選擇器確實停在 shadow 邊界，但 `font-weight`
  **是可繼承屬性**——shadow 內**未自宣告 font-weight** 的繪製盒，會沿 flattened tree
  繼承宿主被改寫成 500 的值。判準是「**該元素自己有沒有宣告 font-weight**」，
  不是「它在不在 shadow 裡」（實證＝`docs/design/113` §1.6 的 variant-plain 與
  `docs/research/82` §16.6 的 Remove schedule）。
- **量錯層**：記到的是**不繪製文字的包裹元素**（繼承值），而非實際繪製文字的元素。

⚠️ **只有 `font-weight` 受污染**：全部受測元素的 font-size／line-height／color／
letter-spacing／font-family 在乾淨與污染環境下**逐項相同**。

| # | 元件 | 原記載 | 🔴 乾淨值 | 污染值 | 取值 |
|---:|---|---|---|---|---|
| 1 | 詳情頁 表單 label（Polaris React 側，例「Description」） | 91 §15：label 13px / 500 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | .Polaris-Label__Text 與 .Polaris-Label 皆同值；light DOM，受污染。★ 這正是本輪指定複驗的那一條：500 是污染值，真值 450 |
| 2 | 詳情頁 表單 label（web component 側，例「Title」） | 91 19：web-component input label = 450 | **13px / 450 / lh 20px** | 13px / 450 / lh 20px（不受影響） | span.label-content，位於 shadow root。原記載正確，且與 Polaris 側一致 ⇒「兩套設計系統的差異」不存在 |
| 3 | 列表頁 表頭欄位（Product / Inventory / Product type / Vendor） | 未取得（本機 checkout 查無該條目原文） | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | button.Polaris-Table-TableHeading，light DOM |
| 4 | 列表頁 表頭欄位（Status / Category / Channels / Catalogs） | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | div.Polaris-Table-TableHeading，light DOM |
| 5 | 列表頁 表頭 Image / Actions | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span.Polaris-Text--root，light DOM |
| 6 | 列表頁 資料列 商品名 | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span._Wrapper_10gjt_1 _LineClamp…，light DOM（50 列同值） |
| 7 | 列表頁 資料列 一般儲存格值（Category / Channels / Catalogs / Vendor 值） | 未取得 | **12px / 450 / lh 16px** | 12px / 500 / lh 16px | span._Wrapper_10gjt_1，light DOM（157 個節點同值） |
| 8 | 列表頁 資料列 副行「for N variants」 | 未取得 | **12px / 450 / lh 16px** | 12px / 500 / lh 16px | div，light DOM |
| 9 | 列表頁 選取用隱藏標籤（Select all 50 on page / Select <gid>） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | span.Polaris-Text--root，light DOM（52 個節點） |
| 10 | 列表頁 搜尋框（輸入區） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | div._ContentEditable_12hbo_17[contenteditable=true]，light DOM |
| 11 | 列表頁 檢視列「Save」次要按鈕 | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span._SlimTertiaryButtonText_，light DOM |
| 12 | 列表頁 分頁 Prev / Next 按鈕 | 未取得 | **13px / 450 / lh 13px** | 13px / 500 / lh 13px | button.Polaris-Button[aria-label=Previous\|Next]，light DOM，圖示按鈕（無文字） |
| 13 | 列表頁 分頁計數「1-50」 | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span.Polaris-Text--root，light DOM |
| 14 | 列表頁 批次操作列 計數「1 selected」 | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span.Polaris-Text--root，light DOM；勾選一列後出現，量完已取消勾選 |
| 15 | 列表頁 批次操作按鈕（Bulk edit / Set as draft） | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span.Polaris-Text--root，light DOM |
| 16 | 詳情頁 Polaris TextField input（價格 198.00、重量 0.2） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | input.Polaris-TextField__Input，light DOM。與 shadow 的標題 input 同值 |
| 17 | 詳情頁 TextField 前綴「HK$」 | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | div.Polaris-TextField__Prefix，light DOM |
| 18 | 詳情頁 textarea（描述編輯區底層） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | textarea._Textarea_gdhwb_96，light DOM |
| 19 | 詳情頁 pill 標籤字（Compare-at / Unit price / Cost per item…） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | p.Polaris-Text--root，light DOM（12 個節點） |
| 20 | 詳情頁 pill 值（HK$399.00 / No） | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | span，light DOM（5 個節點） |
| 21 | 詳情頁 pill 容器與可點 pill 本體 | 未取得 | **容器 div._BasePill_ = 13px / 450 / 20px；按鈕 button._UnstyledButton_._BasePill_ = 13px / 400 / 20px** | 兩者皆 13px / 500 / 20px | light DOM。400 這格是本頁少數 400 之一，污染後與 450 那格變得無法區分 |
| 22 | 詳情頁 可點標籤 .Polaris-Tag（Disclosures） | 未取得 | **13px / 400 / lh 20px** | 13px / 500 / lh 20px | button.Polaris-Tag.Polaris-Tag--clickable，light DOM |
| 23 | 詳情頁 欄位說明小字 | 未取得 | **12px / 450 / lh 16px** | 12px / 500 / lh 16px | p.Polaris-Text--root（例：Determines tax rates…）與 div（Sell via selected sales channels…），light DOM |
| 24 | 詳情頁 開關列標題（Inventory tracked / Physical product） | 未取得 | **11px / 450 / lh 12px** | 11px / 500 / lh 12px | div.Polaris-InlineStack，light DOM。11px 是本輪新見尺寸 |
| 25 | 詳情頁 庫存 Locations 表頭 | 未取得 | **12px / 550 / lh 16px** | 12px / 500 / lh 16px | div.Polaris-Table-TableHeading，light DOM |
| 26 | 詳情頁 唯讀欄位值（Fecify product ID 131666） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | div._ReadField_123bh_9，light DOM |
| 27 | 詳情頁 Category 值（Uncategorized） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | span._Value_w0zhq_82，light DOM |
| 28 | 詳情頁 SEO 連結預覽標題 | 未取得 | **18px / 450 / lh 24px** | 18px / 500 / lh 24px | span._LinkPreview_1azdy_17，light DOM |
| 29 | 詳情頁 頁尾 PageActions「Save」主按鈕 | 未取得 | **label span.Polaris-Text--root = 12px / 600 / 16px；按鈕本體 .Polaris-Button = 13px / 450 / 20px** | label = 12px / 500（被壓低 100）；按鈕本體 = 13px / 500 | button.Polaris-Button > div.Polaris-InlineStack > div.Polaris-PageActions，light DOM。本輪落差最大的一項 |
| 30 | 詳情頁 富文字工具列按鈕（Paragraph） | 未取得 | **12px / 550 / lh 12px** | 12px / 500 / lh 12px | button._Button_ddsno_4，light DOM |
| 31 | 詳情頁 拖放提示（To pick up a draggable item…） | 未取得 | **13px / 450 / lh 20px** | 13px / 500 / lh 20px | div，light DOM |

#### §7.6.1 複驗後與原記載一致（21 項）

- 列表頁 頁首標題 h1「Products」= 18px / 600 / lh 24px（**shadow DOM**，h1.heading in s-internal-page；污染無效）
- 列表頁 頁首按鈕 Add product / Export / Import / More actions 標籤 = 12px / 550 / lh 16px（**shadow slot** in s-button；56 個節點同值，clean=dirty）
- 列表頁 篩選列「Columns」= 13px / 550 / lh 20px、「Reset view」= 13px / 450 / lh 20px（**shadow slot**）
- 列表頁 檢視 tab「All」（＝當前選中態）繪製值 = 12px / 550 / lh 16px（**shadow** span.text.weight-medium.size-small）；⚠️ 其 light DOM 宿主 s-internal-text 讀出來是 13px/450（污染時 500），量宿主會錯
- 列表頁 狀態 badge（Active / Unlisted）= 12px / 550 / lh 16px（**shadow** s-internal-badge > div.badge > span.content）
- 列表頁 庫存欄「0 in stock」= 13px / 450 / lh 20px（**shadow slot**）
- 列表頁 批次操作列「Show all selected」= 13px / 450 / lh 20px（**shadow** label）
- 詳情頁 頁首 h1 商品名 = 18px / 600 / lh 24px（**shadow** h1.heading.has-breadcrumbs）
- 詳情頁 頁首按鈕 Preview / Share / More actions 標籤 = 12px / 550 / lh 16px（**shadow slot**）
- 詳情頁 頁首狀態 badge「Active」= 12px / 550 / lh 16px（**shadow**）
- 詳情頁 卡標題 Price / Inventory / Shipping / Variants / Product metafields / Search engine listing / Status / Publishing / Product organization = 13px / 600 / lh 20px（**shadow slot**，17 個節點）
- 詳情頁 卡標題 Media / Disclosures = 13px / 450 / lh 20px（**shadow slot**；🔴 與上面那組不同，登記時勿合併）
- 詳情頁 web-component 表單 label：span.label-content（Title）、span.label（Type / Vendor）、span.small-text（Collections / Tags）= 13px / 450 / lh 20px（**shadow**）
- 詳情頁 標題 input（web component）= 13px / 450 / lh 20px（**shadow** input）
- 詳情頁 Status 下拉選項 Active / Draft / Unlisted = 13px / 450 / lh 20px；選中值 = 13px / 600 / lh 20px（**shadow slot**）
- ~~詳情頁 庫存表頭詞 unavailable / committed / available / on hand = 13px / **650** / lh 20px（**shadow slot**，6 個節點；650 是本輪新見字重）~~
  > 🔴🔴 **2026-08-28 撤回整條（G13 定案）**：量錯節點。
  > **表頭詞的乾淨值是 `12px / 550 / lh 16px`**，繪製盒＝`s-internal-text` → shadowRoot →
  > `span.text.interest.interest-text-underline…weight-medium size-small`（clean 與 dirty 皆 550 ⇒ 免疫）。
  > 🔴 **那 650 的真實出處是「On hand」表頭格 `s-internal-tooltip` 內文的粗體強調**
  > （`strong…weight-bold`，13px/20px），而該 popover 預設 `display: none`、rect 0×0，**只有 hover／focus 才繪製**。
  > 🔴 **「6 個節點」這個數字本身就是指紋**：表頭詞是 **4 個詞 × 2 份 DOM 副本 ＝ 8**；
  > **3 個 tooltip 粗體字 × 2 份副本 ＝ 6**。per-location 表頭在 DOM 裡有兩份
  > （sticky 可見副本 ＋ `Polaris-Table-TableHeadingCell__Hidden` 版面量測副本，後者 `visibility: hidden`）
  > ⇒ **任何節點計數宣稱都要先除以 2**。
  > ⇒ **「另立 650 token 條目」的建議一併撤回**（就本元件而言）。定案量測＝`docs/research/91` §19.6 #15。
- 詳情頁「Add options like size or color」按鈕 = 12px / 550 / lh 16px（**shadow slot**）
- 詳情頁 Manage publishing / View all / Add definition = 13px/450 與 12px/550（**shadow slot**）
- 詳情頁「Rich text editor」提示 = 12px / 450 / lh 16px；富文字工具列 tooltip（Formatting / Bold / Italic…）= 13px / 450 / lh 20px（**shadow slot**，331 個節點）
- 詳情頁 Online Store / All catalogs 銷售通路列 = 12px / 550 / lh 16px（**shadow slot**）
- 詳情頁 媒體拖放遮罩「Drop files to upload」= 13px / 600 / lh 20px（**shadow** div.overlay-text）

#### §7.6.2 本次更正帶出的規律

1. 🔴 **兩頁都是混合設計系統**：頁殼／頁首／按鈕／badge／卡標題／web-component 表單控件走 s-* web component（shadow DOM）；資料表格、Polaris 表單 label／TextField／pill／pagination／批次操作列仍是 Polaris React（light DOM）。登記每一項時必須標明歸屬，否則無法判斷該值可不可信。
2. 🔴 ~~**污染只打得到 light DOM**~~ **（已於同日二次更正：`font-weight` 會沿 flattened tree 繼承進 shadow，見 `docs/design/111` §20.3）**。以下機制敘述在「選擇器匹配」這一層仍成立：擴充規則 `body :not(svg)…` 是**文件樹**選擇器，配不到 shadow 樹內元素；而 slotted 文字的繼承走**扁平樹**（從 `<slot>` 所在的 shadow 父元素繼承）。所以即使宿主 `<s-internal-text>` 被 !important 設成 500，實際繪製的 shadow `span.text` 仍是原值 ⇒ 所有 s-* 元件文字全部免疫，clean 與 dirty 完全相同。
3. 🔴 **量測陷阱（可能污染既有記載，即使當時停用了擴充）**：對 `s-internal-text` 這類宿主呼叫 getComputedStyle 得到的是「從 light DOM 父層繼承來」的值，不是繪製值。實例：檢視 tab「All」宿主讀 13px/450，shadow 內真正繪製的是 12px/550——差一個尺寸又差 100 字重。正確做法是量文字節點的扁平樹父層：`getComputedStyle(textNode.assignedSlot || textNode.parentElement)`。凡是量宿主取得的舊記載，即使環境乾淨也要重量。
4. **乾淨字重集合裡沒有 500**（與已知直方圖一致）：列表頁 main 內容 406 個承載文字的樣式 → 12px/450×163、12px/550×128、13px/450×103、13px/550×1、18px/600×1；詳情頁 473 個 → 450×382、550×35、600×20、650×6、400×5。⇒ **任何 500 都是污染**，可作為既有記載的機械篩查判準。
5. **污染雙向，本輪最大落差 100**：頁尾 Save 按鈕 label 乾淨 12px/**600** 被壓成 500；同時 12px/450 與 13px/450 被拉高到 500。看到 500 完全無法回推原值（可能是 400、450、550 或 600），只能重量。
6. **污染面積兩頁差很多**：列表頁 575 個承載樣式中 287 個被改（含 style 節點）；詳情頁只有 41/473 被改。原因是詳情頁 web-component 化程度高得多。這正好解釋了為何「Polaris label 500 vs web-component label 450」會被誤讀成兩套設計系統的差異——差異其實只存在於「哪一半被污染打到」。
7. 🔴 **原「兩套設計系統差異」結論被推翻**：`.Polaris-Label__Text`（Description）與 `span.label-content`（Title）**乾淨值都是 13px / 450 / lh 20px**，一模一樣；input 亦然——`.Polaris-TextField__Input` 與 shadow input **都是 13px / 450 / lh 20px**。§15 的 500 是污染值，不是設計差異。
8. **本輪新見、尚未見於已知 token 表的值**：11px/450/lh 12px（開關列標題，light DOM，會被污染）與 13px/650/lh 20px（庫存表頭詞 unavailable/committed/available/on hand，shadow，免疫）。650 這個字重先前未出現在乾淨直方圖裡，建議另立 token 條目。
9. **免疫不等於可以不停用**：s-* 元件雖然免疫，但它們的 light DOM 宿主（s-internal-text 等）在污染下讀出 500，如果量測腳本走宿主，仍會把免疫元件記成 500。停用污染源＋量扁平樹父層，兩件事都要做。

#### §7.6.3 仍未取得

- **檢視 tab 的未選中態**：測試店的商品列表只有一個 view（「All」，實測 button[class^=_Activator_] 僅 1 個），建立第二個 view 屬寫入操作，違反唯讀約束 ⇒ 未取得。選中態已量（12px/550，shadow）。
- **搜尋框 placeholder 文字字重**：搜尋框是 contenteditable（div._ContentEditable_12hbo_17），未命中任何可見的 placeholder 元素（`[class*=Placeholder]` 過濾可見框後為空）⇒ 未取得。輸入區本身已量（13px/450 → 污染 500）。
- **變體表格（多變體資料列）**：測試店可及商品中，唯二的多變體商品是保護清單內的 9911273160939（3 變體）與 9907126370539（3 變體）；逐頁翻到 start=701（累計 750+ 個商品）仍無其他多變體商品 ⇒ 在不觸碰保護商品的前提下無法取得。已確認單變體商品的 Variants 卡只有卡標題（13px/600，shadow）＋「Add options like size or color」按鈕（12px/550，shadow），沒有表格。
- **SaveBar（Unsaved changes 情境列）**：需先弄髒表單才會出現，違反唯讀約束 ⇒ 未取得。頁尾 Polaris-PageActions 的 Save 主按鈕已量（label 乾淨 12px/600，污染 500）。
- **1280 / 768 / 390 三寬度對比（鐵律 13.1）**：resize_window 已知無效（視窗離屏 screenX≈-32000），本輪全部數值都在 innerWidth=1024 / dpr 1.5 / 根字級 16px 下取得 ⇒ 其他寬度未取得，不得外推。
- **91 §15 / 91 19 / 77 §7 的原記載逐字內容**：本機 checkout（C:\\Users\\pisce\\Downloads\\shopifysystem\\chilllovesaas，HEAD=9954913）的 docs/specs/91-pit-register.md 與 docs/research/77-admin-products-sub.md 內 `grep -n 'font-weight|字重'` 皆無命中，§15／item 19 不存在於此工作副本 ⇒ 除任務內文引述的那一句外，其餘條目原文無法逐字核對。上表 corrections 的 recorded 欄凡標「未取得」者，即為此因；請以 clean 欄為準值、dirty 欄為「若在未停用擴充的環境量測會得到的值」。

> 量測環境：Claude in Chrome，使用者 Chrome 已登入測試店 chill-love-u5q5mnzq。🔴 **每一筆數值都是停用污染源後量測**：每次導航後重新找 `<style id="font-bolder-style">`（parentNode 確認為 HTML）並設 `sheet.disabled=true`，量完以 `disabled=false` 還原（結束時複驗 body font-weight 已回到 500，未改動任何擴充功能設定）。對照的污染值以同一輪 disabled true/false 來回切換取得，故 clean/dirty 是同一組 DOM 節點的成對量測；列表頁另做 clean→dirty→clean 三次，575 項 clean 值完全可重現。視窗 innerWidth=1024 / innerHeight=551 / devicePixelRatio=1.5 / 根字級 16px（未偏離預設，em≈px）。resize_window 無效、screenshot 逾時（已知限制），全程走 DOM/JS。🔴 量測方法：對「文字節點的扁平樹父層」取 computed style（`textNode.assignedSlot \|\| textNode.parentElement`），不是對宿主元素——理由見 patterns 第 3 條。全程唯
