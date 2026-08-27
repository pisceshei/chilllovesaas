# 94 — 系列與庫存實機 teardown（2026-08-24）

> 測試店 `chill-love-u5q5mnzq`（Shopify Plus），全程**親自點擊**（鐵律 12.1），
> 導航一律走側欄與頁內真實 `href`，未猜測任何 URL。
> 目的：解三道待裁定事項中屬於「本尊怎麼做」的部分（`docs/plans/2026-08-24-三方向執行順序.md` §6）。

## §1 系列：**本尊 2026 已是「來源（Sources）」模型**，不是 manual/smart 二分

### 1.1 列表頁欄位（`/collections`）

實測欄位：`Image ｜ Title ｜ Products ｜ Conditions ｜ Sales channels`。
🔴 **沒有「Type」欄**——列表不再以「手動／智慧」二分呈現，改為顯示 `Conditions`。

### 1.2 詳情頁的 Sources 卡（`/collections/494143242475`）

無障礙樹逐字（`read_page filter=interactive`）：

```
button "Manually include products, 1 currently selected"
button "Add exclusion"
button "Add source"
```

版面（截圖確認）：

```
Sources
  ┌──────────────────────────────────┐
  │ [🏷 Products ⌄]                  │   ← 來源型別選擇器
  │ ⊕ Add condition            🏷 1  │   ← 該來源的條件（帶命中數）
  │ + Exclude                        │   ← 該來源的排除
  └──────────────────────────────────┘
  ┌──────────────  +  ───────────────┐   ← 再加一個來源
Collection items  1        Default sort: Most relevant
```

⇒ **一個系列可以有 N 個來源；每個來源自帶條件與排除；成員是各來源求值後的併集減排除。**
「手動挑商品」在這個模型裡**不是另一種系列**，而是**其中一種來源型別**
（按鈕原文 "Manually include products, 1 currently selected"）。

### 1.3 來源型別值域（點開 `Products ⌄`，四項，截圖確認）

| 值 | 狀態 |
|---|---|
| **Products** | 目前選中（打勾） |
| **Variants** | |
| **Collection** | ← 巢狀來源：以另一個系列為來源 |
| **App** | |

🔴 `Collection` 這一項證實**巢狀來源是本尊的一等功能**，不是邊角案例
⇒ 我方的成環偵測（排程第 14 包）不是過度設計。

### 1.4 條件屬性值域（點開 `Add condition`，DOM 收割捲到底，11 項）

`Category ／ Compare at price ／ Inventory stock ／ Price ／ Status ／ Tag ／ Title ／ Type ／ Variant title ／ Vendor ／ Weight`

控件形態：帶 `Search attributes` 搜尋框的清單（Polaris-Scroll 容器）。
🔴 **`Status` 在列**——舊版智慧系列規則沒有這個欄位。
🔴 本次未展開各屬性的**運算子**值域（下一輪補：每個屬性的 relation 集合不同）。

### 1.5 排序值域（點開 `Default sort`，九項，截圖確認）

`Most relevant`（**預設，打勾**）／`Best selling` ／`Product title A-Z` ／`Product title Z-A`
／`Highest price` ／`Lowest price` ／`Newest` ／`Oldest` ／`Manually`

## §2 庫存：**本尊自己說 on hand 是「sum」**

### 2.1 列表欄位（`/products/inventory`）

`Image ｜ Product ｜ SKU ｜ Unavailable ｜ Committed ｜ Available ｜ On hand ｜ Incoming`

實測列值：`0 / 0 / 9 / 9 / 0`。

### 2.2 欄位 tooltip 原文（hover 表頭，截圖確認）

| 欄 | 原文 |
|---|---|
| Unavailable | Inventory that's not available for sale or committed to an order. |
| Available | Inventory at your store that can be sold. |
| **On hand** | **The total amount of inventory at a location. This is the sum of unavailable, committed, and available items.**（unavailable／committed／available 三詞為 Shopify 自己加粗） |

🔴 **決定性**：本尊在**商家可見的 UI 裡**明文把 on hand 定義為 `unavailable + committed + available` 的
**sum**——它是導出量，不是獨立的一等數量。`Incoming` **不在**這個和裡（與列值 0/0/9/9/0 一致）。

### 2.3 行內調整器（點 Available 儲存格）

```
[ Set to ⌄ ] [ 9 ⇅ ] [ Shop location ⌄ ] [ 📝 ] [ ✓ ]
```

模式值域（點開，兩項）：`Set to` ／ `Adjust by`
⇒ 正好對應 API 的 `inventorySetQuantities` 與 `inventoryAdjustQuantities` 兩支。

### 2.4 調整原因值域（點開 `Add reason`，**7 項**，實測＋help 雙源）

`Correction` ／ `Count` ／ `Received` ／ `Return restock` ／ `Damaged` ／ `Theft or loss` ／ `Promotion or donation`

DOM 收割回的整段文字為 `CorrectionCountReceivedReturn restockDamagedTheft or lossPromotion or donation`，
**無捲動容器** ⇒ 七項即完整清單。

🔴 **`Correction` 是預設**——help 原文（取證 2026-08-24，
`https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/adjusting-inventory-quantities`）：
「The default option when no other reason is selected.」

## §2b help.shopify.com 補充（雙源，同一頁，取證 2026-08-24）

> URL：`https://help.shopify.com/en/manual/products/inventory/adjusting-inventory/adjusting-inventory-quantities`

四條實測看不到、但直接決定資料模型的事實：

**① `Adjust by` 不是裸 delta，是「來源 → 去向」的移動。**
原文：「you select an origin, where inventory is coming from, and a destination, where inventory is going to」。
合法的來源／去向包含：`Inventory addition`（店外進貨）、店鋪地點、各不可售狀態、`Inventory removal`。
⇒ **正面支持我方 ledger 補 `from_state`／`to_state` 兩欄**（排程第 3 包），那不是過度設計。

**② 不可售狀態的完整值域：`Damaged` ／ `Quality control` ／ `Safety stock` ／ `Other`。**
原文並且說「Unavailable inventory is **on hand**, but can't be sold.」
⇒ 再次確認 on hand **包含**不可售部分，與 §2.2 的 tooltip 一致。

**③ 🔴 一次 Save 套用「跨列、跨商品、跨地點」的多筆調整。**
原文：「each inventory adjustment is saved in two steps: click the icon to set the adjustment as pending,
and then click **Save** to apply all pending adjustments. You can make multiple adjustments across rows,
products, and locations before you save.」（未存檔就離開頁面則全部丟棄）
⇒ **這就是「一把鍵對 N 筆異動」的本尊形態**：批次是一等公民，且每筆 change 各自落 ledger。
我方 `idempotency_keys` 現行「一把鍵 → 一個 resource」的模型對不上這個形狀。

**④ 大量編輯器**（bulk editor）**明文不留移動紀錄**。
原文：「a record of your inventory movements isn't tracked when you use the bulk editor.」
⇒ 我方登記的「批量編輯器稽核例外」不是我方要不要破例的問題——**本尊自己就有這個例外**。

**⑤ 欄位名依頁面而異**：庫存頁是 `Available` 與 `On hand`；商品詳情頁與變體詳情頁是
`Available` 與 **`Total`**。同一個量在兩處叫不同名字。

### 2.5 調整歷程頁實測（2026-08-24 第二輪，**親自走完整流程**：調整 → Save → 進歷程頁）

> 操作：庫存頁點 `&honey Color Control Repair Hair Oil 100ml` 的 Available 儲存格 →
> 切 `Adjust by` → 數量 1 → origin 保持 `Inventory addition`、destination `Shop location` →
> `Add reason` 選 `Received` → ✓ → 頂部 Save。
> 再從商品頁 Inventory 卡的 `View adjustment history` 真實 href 進入歷程頁：
> 路由＝`/products/inventory/{inventory_item_id}/inventory_history`。

**歷程頁欄位（7 欄）**：`Date ｜ Activity ｜ Created by ｜ Unavailable ｜ Committed ｜ Available ｜ On hand`
（無 Incoming 欄、無獨立 reason 欄——**reason 就是 Activity 標籤**：`received` 顯示為
「Inventory received」）。

🔴 **一次調整 ＝ 歷程頁一列**，該列在**每個受影響的數量欄**各顯示 delta ＋ 期後值：
```
3 minutes ago | Inventory received | KEN LEE | 0 | 0 | (+1) 10 | (+1) 10
Jul 15       | Initial inventory  | Fecify  | 0 | 0 | (+9) 9  | (+9) 9
```
儲存格格式＝「increased by 1 for a total of 10 (+1)」⇒ **delta 與 running total 同格顯示**
（＝API 的 `quantityAfterChange` 有 UI 落點）。

三條連帶事實：

1. **`Created by` 是 group 級、兩種身分**：staff（KEN LEE）或 **app**（Fecify）——
   與 `InventoryAdjustmentGroup.staffMember`／`app` 兩欄位對應。
2. 🔴 **期初庫存本身就是一列 ledger 事件**（「Initial inventory (+9)」，由 app 建立）——
   開帳不是隱含的起始值，是**物化的第一列**。⇒ 180 天修剪的 checkpoint 方案
   （修剪時寫一列期初餘額）正是本尊自己的形態，不是我方發明。
3. 🔴 **Activity 儲存格點開有 popover，露出參考文件**：
   `Shopify TransferAdjustment 518e3347-…` ＋ 來源「Shopify Web」＋
   `gid://shopify/TransferAdjustment/518e3347-ea4f-443e-870a-626092618191` ＋「View analytics」鈕。
   ⇒ **admin 手動的 origin→destination 調整，內部被記成 TransferAdjustment 參考文件**——
   連手動調整都有 reference document，且用的是 `gid://shopify/*` 命名空間
   （API 禁第三方用該命名空間 ⇒ 是為了保留給 Shopify 內部文件，兩者一致）。

**與 API 面互證**（`inventoryAdjustQuantities` 官方範例，取證 2026-08-24）：
調 `available` −4 的回應 `changes` 陣列含**兩筆**——`{name: "available", delta: -4}` ＋
`{name: "on_hand", delta: -4}`。庫存頁的 pending 預覽也同時在 Available 與 On hand
兩欄顯示 `9 → 10`。⇒ **UI 列＝group×level 一列多欄；API＝每個受影響 name 一筆 change**。
同一份資料的兩個投影。

## §3 待補（V 項，本輪未取得）

- **V-94.1** 各條件屬性的**運算子值域**（每個屬性的 relation 集合不同，需逐屬性展開）。
- ~~V-94.2 調整原因值域~~ ⇒ **已解**，見 §2.4（7 項，`Correction` 為預設）。
  🔴 仍待查：**API 側**的 reason 值域是否多於 UI 的 7 項（傳聞十餘項）——那是文檔題不是實測題。
- ~~V-94.3 庫存異動歷程頁~~ ⇒ **已解**（2026-08-24 第二輪，見 §2.5）：一次調整＝歷程頁一列
  （每個受影響數量欄各顯示 delta＋期後值）；參考文件在 Activity 儲存格的 popover
  （名稱＋來源＋完整 gid）。API 側同一事件回**每 name 一筆** change（含衍生的 on_hand）。
- **V-94.4** `Variants` 與 `App` 兩種來源型別的條件屬性集合（本輪只展開了 `Products` 的）。
- **V-94.5** 來源之間的組合語義：多個來源是**併集**還是**交集**？UI 上沒有 all/any 切換，
  需要實際建兩個來源才能確認。

---

## §4 🔴 系列與庫存的 CSS 量測（層④ CSS 三段式，2026-08-28）

> 全域 token 值表、頁面骨架與視覺規律＝`docs/design/111-shopify-token-baseline.md`。
> 涵蓋排查與缺口＝`docs/design/110-css-measurement-coverage.md`。
> 🔴 **鐵律 9**：只記 `getComputedStyle` 算出來的值，不含本尊樣式表原始碼、選擇器定義或可執行片段。
> ⚠️ 對應我方 `CollectionsPage`／`CollectionDetailPage`／`InventoryPage`／`InventoryHistoryPage`。

### §4.0 量測環境

> 量測日期 2026-08-28。測試店 chill-love-u5q5mnzq（Shopify Plus）。Chrome，`window.innerWidth = 1024`、`window.innerHeight = 607`、`devicePixelRatio = 1`、`getComputedStyle(document.documentElement).fontSize = 16px`（根字級為預設，**未受 47 §F 記錄的 root 24px 污染**，故本輪所有 rem→px 換算為標準 1rem=16px，數值可直接採用）。頁面全程只讀：開啟的 modal／popover 一律 Cancel 或 Escape 關閉；新建系列表單以 Discard 撤銷（回到列表仍只有 1 個系列）；庫存數量未修改（量測前後第 1 列 On hand 皆為 10、第 3 列 Available 皆為 9）；商品格線／清單檢視切換後已切回原本的格線檢視。禁碰的五個商品未觸及。所有導航皆從側欄或頁內真實 `href` 取得（`/collections`、`/products/inventory`、`/products/inventory/51159633494251/inventory_history`）。量測方法：`getComputedStyle` 取值，shadow root 以 `el.shadowRoot.querySelector` 逐層穿透（本輪遇到的 `s-*` 元件 shadow root 皆為 open）。⚠️ 1024px 為窄於鐵律 13.1 桌機基準 1280 的寬度，凡「欄寬／容器寬／格線欄數」類數值受此影響，已在各條目標明。

### §4.1 本畫面用到的 token 值

| 類別 | 量測值 | 取值選擇器 |
|---|---|---|
| 底色 · 頁面 | #f1f1f1 | getComputedStyle(document.documentElement) → --p-color-bg；同 body backgroundColor 實測 rgb(241,241,241) |
| 底色 · 卡片／表面 | #fff | --p-color-bg-surface |
| 底色 · 表面 hover | #f7f7f7 | --p-color-bg-surface-hover（＝ --p-color-bg-surface-secondary） |
| 底色 · 表面 active | #f3f3f3 | --p-color-bg-surface-active（＝ --p-color-bg-surface-tertiary） |
| 底色 · 表面 selected | #f1f1f1 | --p-color-bg-surface-selected |
| 底色 · 次級表面 hover／active／selected | #f1f1f1 / #ebebeb / #ebebeb | --p-color-bg-surface-secondary-hover / -active / -selected |
| 文字色 · 主 | #303030 | --p-color-text |
| 文字色 · 次（subdued） | #616161 | --p-color-text-secondary |
| 文字色 · 停用 | #b5b5b5 | --p-color-text-disabled |
| 語義色 · critical / caution / success / brand 文字 | #8e0b21 / #4f4700 / #014b40 / #4a4a4a | --p-color-text-critical / -caution / -success / -brand |
| 邊框色 · 預設／次級／三級 | #e3e3e3 / #ebebeb / #ccc | --p-color-border / -secondary / -tertiary |
| 邊框色 · hover／disabled | #ccc / #ebebeb | --p-color-border-hover / -disabled |
| 焦點色 | #005bd3 | --p-color-border-focus（實測焦點環用色 rgb(0,91,211)，見 §2 焦點環條目） |
| 間距階（rem→px @16px） | 0 / 1 / 2 / 4 / 6 / 8 / 10 / 12 / 16 / 20 / 24 / 28 / 32 / 40 / 48 / 64 / 80 / 96 / 112 / 128px | --p-space-0/025/050/100/150/200/250/300/400/500/600/700/800/1000/1200/1600/2000/2400/2800/3200 |
| 字級階（rem→px @16px） | 11 / 12 / 13 / 14 / 16 / 18 / 20 / 22 / 24 / 30 / 32 / 36 / 40px | --p-font-size-275/300/325/350/400/450/500/550/600/750/800/900/1000 |
| 字重階 | regular 450 / medium 550 / semibold 600 / bold 650 | --p-font-weight-regular / -medium / -semibold / -bold。⚠️ 實測 `document.body` 的 computed font-weight 是 **500**，不在這四階之內 |
| 圓角階（rem→px @16px） | 0 / 2 / 4 / 6(未列於 token，見 §3) / 8 / 12 / 16 / 20 / 30px；full = 624.9375rem | --p-border-radius-0/050/100/150/200/300/400/500/750/-full（150=6px 有 token，實測也用到） |
| 陰影 · 卡片（--p-shadow-100） | 6 層：0 5px 5px -2.5px rgba(0,0,0,.03) / 0 3px 3px -1.5px rgba(0,0,0,.02) / 0 2px 2px -1px rgba(0,0,0,.02) / 0 1px 1px -.5px rgba(0,0,0,.03) / 0 .5px .5px 0 rgba(0,0,0,.04) / 0 0 0 1px rgba(0,0,0,.06) | --p-shadow-100；實測用於 s-internal-section 的 section、分段控制選中鈕 |
| 陰影 · 抬升卡（--p-shadow-200） | 7 層，最外 0 8px 10px -5px rgba(0,0,0,.08)，其餘同 shadow-100 各層 | --p-shadow-200；實測用於 Collection items 的商品格線卡 |
| 陰影 · popover（--p-shadow-popover ＝ --p-shadow-300） | 6 層：0 8px 24px -8px rgba(0,0,0,.28) / 0 8px 16px -4px rgba(0,0,0,.05) / 0 3px 6px 0 rgba(0,0,0,.05) / 0 2px 4px 0 rgba(0,0,0,.05) / 0 1px 2px 0 rgba(0,0,0,.05) / 0 0 0 1px rgba(0,0,0,.06) | --p-shadow-popover；實測用於屬性／運算子／原因 popover 與庫存調整浮動列 |
| 陰影 · 次級按鈕（--p-shadow-button） | 3 層 inset：0 -1px 0 0 #b5b5b5 inset / 0 0 0 1px rgba(0,0,0,.1) inset / 0 .5px 0 1.5px #fff inset | --p-shadow-button；實測用於 Cancel／columns／filter／Done 等次級鈕 |
| 陰影 · 主要按鈕（--p-shadow-button-primary） | 3 層 inset：0 -1px 0 1px rgba(0,0,0,.8) inset / 0 0 0 1px #303030 inset / 0 .5px 0 1.5px rgba(255,255,255,.25) inset | --p-shadow-button-primary；實測用於 Add collection |
| 表單控件靜止環（非 token，逐元件實測） | box-shadow: 0 0 0 0.66px #8a8a8a inset | checkbox 視覺 span、Theme template 欄位、adjust bar 欄位盒；與 47 §H2-4「1 個實體像素 0.66px inset」原則一致 |

### §4.2 元件量測（47 項）

| # | 元件 | 量測 | 狀態樣式 |
|---:|---|---|---|
| 1 | **系列列表 · 表格容器（ARIA table，非 <table>）** | 整頁無任何 `<table>` 元素；表格以 `role=table/rowgroup/row/columnheader/cell` 的 div 構成。`[role=row]` 的 computed `display: contents`（列本身無盒），實際版面在其父層 `display: grid`。表格容器 736px 寬（1024 視窗），內部格線 874px ⇒ 水平捲動。`grid-template-columns` 實測 = `36px 52px 200px 63.3594px 400px 122.266px`（checkbox / 圖片 / Title / Products / Conditions / Sales channels）。標頭格線同欄寬取整 `36px 52px 200px 63px 400px 122px`。 | 資料列 hover：所有 role=cell 由 #fff → #f7f7f7（列本身 display:contents 不承載底色，底色逐格套用） |
| 2 | **系列列表 · 欄位標題格** | 高 36px、min-height 36px、bg #f7f7f7、色 #616161、字 12px/16px、字重 500、display flex。數值欄（Products）`text-align: end`、padding 6px；文字欄（Title）padding 0（內距在內層）。 | 本輪未取得 hover／sort active 態（未點擊排序） |
| 3 | **系列列表 · 資料格** | 高 52px、min-height 32px、bg #fff、色 #303030、字 12px/16px、字重 500、padding 0（內距在內層）、border-radius 0、無 border、無 shadow。Title 欄 200px、Products 欄 63.36px。**Products 計數格 `font-variant-numeric: tabular-nums`**（與鐵律 10 一致）。 | 列 hover → bg #f7f7f7 |
| 4 | **系列列表 · 縮圖 s-thumbnail** | 40 × 40px、`overflow: hidden`、**`border-radius: clamp(4px, round(25%, 2px), 8px)`**（流體圓角公式，非固定階；40px 時 25%=10px → 夾在 8px）。host 本身 0×0 display:contents。內部再包 s-icon 作為空圖佔位。 | 未取得 |
| 5 | **系列列表 · 系列名稱連結** | 字 12px/16px、字重 500、色 #303030、`text-decoration: none`、`cursor: pointer`、無 outline（靜止）。 | hover 由整列承接（列底色變 #f7f7f7），連結本身文字色與底線不變 |
| 6 | **checkbox（視覺）** | 原生 input **opacity 0 絕對定位**，視覺由相鄰 span 繪製：16 × 16px、`border-radius: 4px`、bg #fff、`box-shadow: 0 0 0 0.66px rgb(138,138,138) inset`。勾記層 12 × 12px（未勾選時 opacity 0）。外層 span margin 1px。 | 未勾選態已取得；已勾選／hover／disabled 未取得（本輪不勾選任何列以維持唯讀） |
| 7 | **頁面標題 h1（Collections／Adjustment history）** | 18px / 24px / 字重 **600**、色 #303030、**letter-spacing: -0.14994px**（≈ -0.00833em）。 | — |
| 8 | **主要按鈕（Add collection）** | 高 28px / min-height 28px、`padding: 6px 12px`、`border-radius: 8px`、bg #303030、色 #fff、字 12px/16px、字重 **550**、`gap: 2px`、`display: flex`、`justify-content: center`、box-shadow ＝ --p-shadow-button-primary（3 層 inset）、`transition: none`。 | hover／active 未取得（不點擊建立入口以外的觸發） |
| 9 | **卡片容器（Section）** | bg #fff、`border-radius: 12px`、box-shadow ＝ --p-shadow-100（6 層）、寬 736px（1024 視窗）。padding 依卡片而異：純內容卡 16px；含表格／列群的卡 0（內距下放到列）。 | — |
| 10 | **Sources 卡片標頭列（可摺疊）** | 列高 44px、`padding: 8px 16px`；標題文字 13px/20px；右側 chevron 為 s-internal-icon → shadowRoot > span > svg，16 × 16px、色 #8a8a8a、margin 2px。 | 展開／收合圖示切換；收合態未取得 |
| 11 | **條件群組內卡（Sources 內層）** | 寬 712px（＝736 − 12×2）、bg #fff、`border-radius: 12px`、shadow ＝ --p-shadow-100；內部列以 `gap: 16px` flex 直向排列。 | — |
| 12 | **資源類型選擇器（Products chip，條件群組頂）** | 高 28px / min-height 24px、`padding: 4px 6px`、`border-radius: 8px`、bg transparent、色 #303030、字 13px/20px、字重 500、`gap: 4px`、寬 115.25px。 | rest bg transparent → hover bg rgba(0,0,0,0.05)（該元件 transition-duration 0s，無過渡） |
| 13 | **Add condition 按鈕（條件列左）** | 高 28px / min-height 28px、`padding: 4px 10px 4px 6px`（padding-inline 6px start / 10px end）、`border-radius: 8px`、bg #f7f7f7、色 #616161、字 13px/20px、字重 500、`gap: 4px`、寬 126.52px。所在列 678px 寬、高 29px、flex、`gap: 8px`、`justify-content: space-between`。 | hover：bg #f7f7f7 → **#f1f1f1**；`transition: background-color 0.15s ease-out`。文字色不變、無邊框變化、無陰影 |
| 14 | **條件列右側計數 badge（已選商品數）** | badge：高 20px / min-height 20px、寬 24px、`padding: 2px 8px`、`border-radius: 8px`、bg **rgba(0,0,0,0.06)**、色 #616161、字 12px/16px、字重 500、inline-flex、置中。外層 button 高 29px、`padding: 4px 10px 4px 6px`、radius 8px、bg transparent、gap 4px。獨立取得的 s-internal-badge → shadowRoot > div 同規格但字重 **550**、`gap: 4px`。 | 點擊開啟「Select products to include」modal（見下） |
| 15 | **Exclude 按鈕** | 高 30px / min-height 28px、`padding: 4px 10px 4px 6px`、`border-radius: 8px`、bg #f7f7f7、**border: 1px solid #e3e3e3**（唯一帶實邊框的此類鈕）、色 #303030、字 13px/20px、字重 500、`gap: 4px`、寬 91.08px。 | hover：bg #f7f7f7 → #f1f1f1；`transition: background-color 0.15s`；邊框不變 |
| 16 | **新增 source 虛線列（+）** | 寬 712px（滿寬）、高 38px、`padding: 8px 12px`、`border-radius: 8px`、**border: 1px dashed #ccc**、bg transparent、色 #303030、flex 置中；內部 + icon 16 × 16px、色 #4a4a4a。 | hover：bg transparent → **#f7f7f7**；`transition: background-color 0.2s cubic-bezier(0.25, 0.1, 0.25, 1)`（與其他 0.15s ease-out 不同）；虛線邊框不變 |
| 17 | **屬性／運算子 popover 面板** | 屬性面板 240 × 340px；運算子面板 147 × 210px；原因面板 152.5 × 303.5px。共同：bg #fff、`border-radius: 12px`、`overflow: hidden`、box-shadow ＝ --p-shadow-popover（6 層）。內層清單容器 padding 4px（選項左緣較面板左緣內縮 4px）。 | — |
| 18 | **popover 選項列** | 高 32px、寬 222px（240px 面板內）、`padding: 6px`、`border-radius: 8px`、`gap: 4px`、字 13px/20px、字重 **450**、色 #303030、`transition-duration: 0s`（無過渡）。選中列另有 16 × 16px 勾記 icon，色 #4a4a4a。 | rest：bg transparent、字重 450／hover：bg **#f7f7f7**／**selected：bg #f1f1f1 + font-weight 600**（radius 8px、padding 6px 不變） |
| 19 | **智慧條件列（Title / contains / 刪除）** | 列 694 × 44px、flex、`align-items: center`、`gap: 6px`、`padding: 8px`。屬性 chip 與運算子 chip **樣式完全相同**：高 28px / min-height 28px、`padding: 4px 6px 4px 10px`（inline 10px start / 6px end）、`border-radius: 8px`、bg #f7f7f7、色 #303030、字 13px/20px、字重 500、`gap: 4px`；寬度隨文字（Title 63.13px、contains 89.16px）。 | chip hover：#f7f7f7 → #f1f1f1 |
| 20 | **條件刪除鈕（垃圾桶 icon）** | 28 × 28px、min-height 28px、`padding: 4px`、`border-radius: 8px`、bg transparent、icon 色 **#8a8a8a**、字 12px/16px、字重 550、flex 置中、`gap: 2px`。 | hover：bg transparent → **rgba(0,0,0,0.05)**、icon 色 #8a8a8a → **#616161**；`transition: none`（無過渡） |
| 21 | **條件值輸入列（Add value）** | 列 694 × 40px、`padding: 8px`；input 678 × 24px、`padding: 2px 0`、bg transparent、**無 border、無 box-shadow**（無框行內輸入）、字 13px/20px、色 #303030。該列所在內卡最後一列 `border-radius: 0 0 11px 11px`（外卡 12px、內縮 1px ⇒ 內圓角 11px）。 | focus 態未取得（未聚焦此欄） |
| 22 | **Collection items 區段標頭** | 標題列 flex、`gap: 8px`、高 20px、字 13px/20px。右側「Default sort: Most relevant ⌄」為 button：高 28px、`padding: 4px 6px 4px 8px`、`border-radius: 8px`、bg transparent、`gap: 4px`、字 13px/20px 字重 500、寬 191.58px、`margin: -4px -1px -4px 0`（負 margin 對齊）。 | 未取得 hover |
| 23 | **檢視切換分段控制（格線／清單）** | 各 28 × 24px、`padding: 2px 4px`、`border-radius: 8px`。**選中**：bg #fff、icon 色 #4a4a4a、box-shadow ＝ --p-shadow-100（6 層）。**未選中**：bg transparent、icon 色 **#8a8a8a**、無 shadow。 | 選中 vs 未選中差異＝底色 + 陰影 + icon 色三項（見上） |
| 24 | **次級 icon／文字鈕（columns「4」、篩選 icon、Cancel、Done）** | columns 鈕 47.94 × 28px、`padding: 4px 12px 4px 6px`；篩選 icon 鈕 28 × 28px、`padding: 4px`；Cancel 63.84 × 28px、`padding: 6px 12px`；Done 32 × 32px、`padding: 6px`。共同：bg #fff、`border-radius: 8px`、box-shadow ＝ --p-shadow-button（3 層 inset）、色 #303030、`gap: 2px`。字級不一致：工具列鈕 12px/16px 字重 550；modal Cancel／Done 13px/20px 字重 500。 | hover／active 未取得 |
| 25 | **篩選 chip 與 Clear all** | chip button 高 22px、`padding: 0 0 0 8px`、寬 274.59px、字 13px/20px 字重 500（'Status: Active, Draft, Unlisted, and Suspended ×'）。Clear all：高 24px / min-height 24px、`padding: 4px 8px`、`margin: -4px -8px`、`border-radius: 8px`、`gap: 2px`、bg transparent。 | 未取得 |
| 26 | **手動選品 · 商品格線卡（grid 檢視）** | 格線：`grid-template-columns: 166.5px ×4`、`gap: 12px`、容器 `padding: 16px`、寬 734px（1024 視窗、欄數設定為 4）。卡片 167 × 201px、bg #fff、`border-radius: 12px`、box-shadow ＝ --p-shadow-200（7 層）。圖片區 167 × 167px、`border-radius: 12px 12px 0 0`、`overflow: hidden`。標題 12px/16px、字重 500、色 #303030、`white-space: normal`、`text-overflow: clip`。 | 未取得 hover／selected |
| 27 | **手動選品 · 商品列（list 檢視）** | 列 734 × 64px、flex、`align-items: center`、`gap: 12px`、`padding: 12px 16px`、bg #fff。縮圖 40 × 40px、radius `clamp(4px, round(25%,2px), 8px)`、overflow hidden。標題為 `<a>`：**14px / 20px、字重 500**、色 #303030（與格線卡的 12px 不同）。切到清單檢視後「N columns」控件消失（條件控件）。 | 未取得 hover；切回格線檢視已還原 |
| 28 | **手動選品 modal（Select products to include）** | 面板 620 × 522px、bg #fff、`border-radius: **16px**`、box-shadow `0 8px 16px -4px rgba(26,26,26,0.22)`（＋一層 0 0 0 0 inset）。標頭列：bg **#f3f3f3**、`padding: 16px`、高 53px；標題 h2 14px/20px 字重 500。頁尾列 588px 寬、高 28px、flex、`justify-content: space-between`、`gap: 16px`、無 border-top。商品列：546 × 40px、flex、`align-items: center`、`gap: 12px`（外層 grid `gap: 16px`）；縮圖 40 × 40px 同上；標題 13px/20px 字重 500。 | — |
| 29 | **modal 搜尋欄 · 焦點環（**本輪關鍵取得**）** | input 本身 359 × 28px、`padding: 2px 12px 2px 0`、bg transparent、**outline: none、box-shadow: none**（焦點環不畫在 input 上，與 64 §5 一致）。焦點環畫在外層 391 × 28px 的 div 上：**`outline: rgb(0,91,211) solid 2px`、`outline-offset: 1px`、`border-radius: 8px`**。 | focus-visible 已取得（如上）；blur 態該外層 outline 為 none |
| 30 | **modal「Search by」— 原生 <select>** | 193 × 28px、`padding: 6px 8px 6px 12px`、bg #fff、色 rgb(0,0,0)（瀏覽器預設）、字 13px、字重 500、`border-radius: 0`。**這是本輪唯一遇到的原生 `<select>`**，其餘所有下拉皆為 s-popover 自製。值域：All（預設選中）／Product title／Product ID／Barcode／SKU。 | 原生控件，狀態樣式由瀏覽器提供，未量 |
| 31 | **modal「Add filter +」虛線鈕** | 85.92 × 24px、`padding: 0 6px 0 8px`、`border-radius: 8px`、bg #fff、**border: 1px dashed #e3e3e3**、色 #4a4a4a、字 13.3333px（**未設字級，瀏覽器預設 medium**）、`line-height: normal`。 | 未取得 |
| 32 | **停用態主要按鈕（modal 的 Add）** | 47.27 × 28px、min-height 28px、`padding: 6px 12px`、`border-radius: 8px`、**bg rgba(0,0,0,0.17)**、色 #fff、**box-shadow: none**（失去 --p-shadow-button-primary 的 3 層 inset）、**opacity: 1**、`pointer-events: none`、`aria-disabled="true"`、**`disabled` 屬性為 false**。 | **停用態的表達＝改底色 + 移除 inset 陰影 + pointer-events none + aria-disabled，不用 opacity、不用 disabled 屬性** |
| 33 | **單選欄位（Theme template；2026 標準 select 外觀）** | 704 × 32px（滿寬）、`padding: 6px 8px 6px 10px`、`border-radius: 8px`、bg **#fdfdfd**、`box-shadow: 0 0 0 0.66px rgb(138,138,138) inset`（非 border）、字 13px/20px、字重 450、`appearance: none`。值域（Theme template）：Default collection／collection-banner-adv／collection-full-width-2／collection-full-width／collection-right-sidebar。 | focus 態在此元件未取得（button 本身 outline none、無子層可讀）；同型元件的 focus 環已於 adjust bar 取得（見下） |
| 34 | **庫存列表 · 表格與欄寬** | `grid-template-columns: 36px 52px 300px 150px 150px 150px 150px 150px 150px`（checkbox / 圖片 / Product / SKU / Unavailable / Committed / Available / On hand / Incoming），總寬 1288px，可視 736px ⇒ 水平捲動（標頭與內容為**同一捲動軸，但 DOM 上有 3 個 scroll 容器需同步**）。列高 52–53px；資料格 min-height 32px。**注意欄寬與系列列表不同**：系列 Title 200px，庫存 Product 300px、數值欄一律固定 150px。 | 列 hover：全列各格 bg #fff → #f7f7f7 |
| 35 | **庫存列表 · 凍結（sticky）欄** | checkbox 欄 `position: sticky; left: 0; z-index: 100; width: 36px`；圖片欄 `position: sticky; left: 36px; z-index: 100; width: 52px`。底色隨列狀態變（#fff／hover #f7f7f7）。**凍結邊緣沒有任何陰影或分隔線**（box-shadow: none）。 | hover 時 sticky 欄底色同步變 #f7f7f7 |
| 36 | **庫存列表 · 列分隔線** | 分隔線畫在**每個資料格的 `border-top: 1px solid rgb(227,227,227)`**（#e3e3e3），不是畫在列或用獨立 1px 元素。列容器本身 `border-bottom: none`。 | — |
| 37 | **庫存列表 · 欄位標題** | 標題格 min-height 36px、bg #f7f7f7、色 #616161、字 12px/16px 字重 500；數值欄 `text-align: center`（庫存頁）／`end`（歷程頁），`padding: 6px`（首欄 6px 6px 6px 12px、末欄 6px 12px 6px 6px）。可排序標題帶 `aria-label="Sort this table by {COLUMN} in ascending order"`。 | 未取得排序 active 態 |
| 38 | **庫存列表 · 可編輯數量格（Available / On hand）** | 格 150 × 52px、`padding: 6px`、`justify-content: flex-end`、字 12px/16px 字重 500、**`font-variant-numeric: tabular-nums`**。可編輯欄的葉節點是 `s-internal-text`（display:contents）；不可編輯欄（Committed／Incoming／Unavailable）是純 `span` ⇒ **DOM 上可分辨可編輯性**。內容盒 41.6 × 20px。**選取／編輯中的欄位環是 `::after` 偽元素**：`box-shadow: 0 0 0 2px rgb(0,91,211)`、`border-radius: **4px**`、`inset: 0 -1px 0 -4px`、透明底、`outline: rgba(0,0,0,0) solid 1px`。 | rest：bg #fff／列 hover：所有格 #f7f7f7／**編輯中的那一格：bg #f3f3f3**（其餘格維持列狀態）／選取態：上述 ::after 藍環（radius 4px，與表單控件的 8px 不同） |
| 39 | **庫存 · 調整浮動列（adjust popover）** | 面板 615 × 58px、bg #fff、`border-radius: 12px`、box-shadow ＝ --p-shadow-popover（6 層）、內距 12px；內部橫列 591 × 34px、`gap: 8px`。組成（左→右）：[Adjust by ⌄][數字輸入＋上下 stepper] · [原因選擇器 ⌄] · → 箭頭 · [目的地位置 ⌄] · [新增原因 icon 鈕] · [Done ✓]。→ 箭頭為 13 × 9.5px svg、色 #8a8a8a。 | 點擊可編輯格開啟；Escape 關閉且不寫入 |
| 40 | **庫存 · adjust bar 欄位盒 + 焦點環（**本輪關鍵取得**）** | **未聚焦**：160 × 32px、`border-radius: 8px`、`box-shadow: 0 0 0 0.66px rgb(138,138,138) inset`、bg 透明（父層 #fdfdfd）。**聚焦**：同一元素加上 **`outline: rgb(0,91,211) solid 2px` + `outline-offset: 1px`**，靜止的 0.66px inset 環**保留不移除**；聚焦時外框盒改為 153 × 33px、bg #fdfdfd、`border: 1px solid #8a8a8a`、`padding: 5.5px 7.5px 5.5px 11.5px`。input 本身 36 × 32px、`padding: 0 0 0 6px`、`type=number`、`inputmode="numeric"`、字 13px 字重 500、outline none。stepper 箭頭 12 × 12px、色 #8a8a8a。 | rest / focus-visible 皆已取得（如上）；error／disabled 未取得 |
| 41 | **庫存 · Adjust by 模式 chip** | 88 × 24px、`padding: 0 2px 0 8px`、**`border-radius: 6px`**（本輪唯一出現的 6px 階，對應 --p-border-radius-150）、bg **rgb(240,240,240)**、色 #616161、字 12px、字重 500。值域：**Set to / Adjust by**（2 項）。 | 未取得 hover |
| 42 | **庫存 · Adjust by 選單（ul/li 型，與 popover 型不同）** | ul `padding: 4px`、寬 82px；列 button 74 × 28px、min-height 28px、`padding: 4px 8px`、`border-radius: 8px`、bg transparent。**字級 13.3333px、字重 400、line-height 20px** — 即未套用設計系統字級的瀏覽器預設值。 | 未取得 hover；選中列在此選單無底色差異（與 s-popover 型的 #f1f1f1+600 不同） |
| 43 | **庫存 · 調整原因選擇器** | 面板 152.5 × 303.5px、bg #fff、`border-radius: 12px`。選項列 135 × 52px（兩行文字時）、`padding: 6px`、`border-radius: 8px`、`gap: 4px`、字 13px/20px。值域（6 項）：Inventory addition（預設選中）／Shop location／Damaged (Unavailable)／Quality control (Unavailable)／Safety stock (Unavailable)／Other (Unavailable)。 | **selected：bg #f1f1f1 + font-weight 600 + 勾記 icon**；rest 透明、字重 450 |
| 44 | **庫存 · adjust bar 右側兩鈕** | 「Add adjustment reason」（aria-label）：34 × 34px、`padding: 6px`、`border-radius: 8px`、**bg rgba(0,0,0,0.06)**、`border: 1px solid transparent`、字 13.3333px（預設字級）。「Done」：32 × 32px、`padding: 6px`、radius 8px、bg #fff、box-shadow ＝ --p-shadow-button（3 層 inset）、字 13px/20px 字重 500。 | 未取得 |
| 45 | **庫存 · 欄位顯示選單（Display options）值域** | Hide SKU／Hide Unavailable／Hide Committed／Hide Available／Hide On hand／Hide Incoming／**Show Bin name**／Reset view。排序項：Sort this table by VARIANT_NAME / SKU / UNAVAILABLE_QUANTITY / COMMITTED_QUANTITY / AVAILABLE_QUANTITY / ON_HAND_QUANTITY / INCOMING_QUANTITY in ascending order；方向：Ascending / Descending。頁面層級動作：Export / Import。 | 選單面板本身的尺寸樣式未量 |
| 46 | **庫存歷程頁（Adjustment history）· 表格** | **是表格不是時間軸。** 欄：Date / Activity / Created by / Unavailable / Committed / Available / On hand。`grid-template-columns: 146.281px 154.344px 90.2812px 94.0938px 90.25px 79.0625px 81.6875px`（**auto 自適應小數寬，與庫存列表的固定 150px 不同**），總寬 736px、無水平捲動。標頭 min-height 36px、bg #f7f7f7、色 #616161、12px/16px/500；文字欄 text-align start、數值欄 text-align end。資料格 min-height 32px、實際列距約 33px、bg #fff、12px/16px/500、色 #303030；數值欄 `font-variant-numeric: tabular-nums`。卡片標頭（商品名）13px/20px、字重 450。頁尾「Learn more about adjustment history」段落 12px/16px、色 #303030、無底線。 | 未取得列 hover（歷程列不可點） |
| 47 | **庫存歷程 · 增減量（delta）字樣** | 每個數值格結構＝〔視障用隱藏全句 'increased by 1 for a total of 10'〕＋〔delta '(+1)'〕＋〔結果值 '10'〕。**delta 用 `s-internal-text[color="subdued"]`，shadow span 色 rgb(97,97,97) #616161**；結果值用 `s-internal-text[fontvariantnumeric="tabular-nums"]`，色 #303030。兩者渲染字級皆繼承格子的 12px（host 為 display:contents）。 | 本店只有正向調整；負向 delta 是否改用 critical 色未取得 |

### §4.3 觀察到的視覺規律

1. **表格一律不是 `<table>`**：整個 2026 admin 的列表以 `role=table/rowgroup/row/columnheader/cell` 的 div + CSS Grid 實作，`[role=row]` 的 computed `display: contents`（列本身沒有盒）。⇒ 我方 CollectionsPage／InventoryPage 若用 `<table>`，欄寬同步、sticky 欄、列高一致這三件事的實作路徑會完全不同；建議照抄「grid + display:contents 列」的結構。
2. **列的底色逐格套用，不套在列上**：hover 是把該列每一個 `role=cell` 的 background 從 #fff 換成 #f7f7f7；分隔線是每一格的 `border-top: 1px solid #e3e3e3`。這是 display:contents 的必然結果。
3. **互動只改底色，幾乎不改邊框／陰影／位移**：實測到的所有 hover（列、tertiary 鈕、虛線鈕、popover 選項、垃圾桶鈕）都只換 background-color，border 與 box-shadow 一律維持不變，也沒有 transform。
4. **hover 底色是一條四階灰梯**：transparent → rgba(0,0,0,0.05) →（或）#f7f7f7 → #f1f1f1 → #f3f3f3（編輯中）。底色已是 #f7f7f7 的元件（Add condition／Exclude）hover 時往下一階 #f1f1f1；底色透明的元件（資源類型 chip、垃圾桶）hover 用半透明黑 rgba(0,0,0,0.05)。
5. **過渡時間只有兩個值**：`background-color 0.15s ease-out`（一般鈕）與 `background-color 0.2s cubic-bezier(0.25,0.1,0.25,1)`（虛線新增列）；popover 選項與垃圾桶鈕 `transition: none`（0s），主要按鈕也是 `transition: none`。
6. **圓角是 4 / 6 / 8 / 12 / 16 五階 + 一條公式**：4px＝checkbox 與庫存選取格環；6px＝adjust bar 的模式 chip；8px＝所有按鈕／輸入框／chip／popover 選項；12px＝卡片、popover 面板、浮動列；16px＝modal。縮圖獨用 `clamp(4px, round(25%, 2px), 8px)` 的流體公式。巢狀時內圓角減 1px（外卡 12px → 內最後一列 `0 0 11px 11px`）。
7. **表單控件的 1px 框一律是 `box-shadow: 0 0 0 0.66px #8a8a8a inset`，不是 border**（checkbox 視覺、Theme template 欄位、adjust bar 欄位盒都一樣）；只有需要「視覺上更硬」的兩處用真 border：Exclude 鈕（1px solid #e3e3e3）與 focus 中的 adjust 欄位盒（1px solid #8a8a8a）。
8. **焦點環＝`outline: 2px solid #005bd3` + `outline-offset: 1px`，畫在外層包裹盒而不是 input**，且靜止的 0.66px inset 環同時保留（環套環）。唯一例外是庫存可編輯格：那裡改用 `::after` 的 `box-shadow: 0 0 0 2px #005bd3` + radius 4px。
9. **陰影只有四種角色**：--p-shadow-100（卡片／分段控制選中，6 層）、--p-shadow-200（可拖拉的商品卡，7 層）、--p-shadow-popover(=300)（所有浮層，6 層）、--p-shadow-button／-primary（按鈕，3 層 inset）。**每一種都是多層堆疊且最後一層都是 `0 0 0 1px rgba(0,0,0,.06)` 的髮絲邊**——陰影同時當邊框用。
10. **停用態不用 opacity**：改底色（主要鈕 → rgba(0,0,0,0.17)）＋移除 inset 陰影＋`pointer-events: none`＋`aria-disabled="true"`，而 `disabled` 屬性維持 false（保留可聚焦性）。
11. **數字一律 tabular-nums**：系列列表的 Products 計數、庫存列表的五個數量欄、歷程頁的四個數量欄都設了 `font-variant-numeric: tabular-nums`；純文字欄（Date／Activity／Created by）則是 normal。與我方鐵律 10 的金額顯示規則同源。
12. **「可編輯」在 DOM 上是可分辨的**：庫存列表中 Available／On hand 的葉節點是 `s-internal-text`（display:contents 元件），Committed／Incoming／Unavailable 是裸 `<span>`。我方可沿用「用元件包裹表示可編輯」這個約定。
13. **表格字級與 UI 字級是兩套**：表格內容一律 12px/16px、字重 500；一般 UI（按鈕、chip、popover 選項、輸入框）13px/20px、字重 450–500；清單型商品列標題升到 14px/20px；頁標題 18px/24px/600。同一頁面內同時存在三個字級層。
14. **兩套下拉並存且不一致**：s-popover 型（面板 radius 12px、選項 32px 高、13px/450、selected = #f1f1f1 + weight 600）與 ul/li 型（Adjust by 模式選單，選項 28px 高、**13.3333px/400 的瀏覽器預設字級**、selected 無底色）。後者看起來是尚未收編進設計系統的殘留。
15. **新版系列詳情已不是「手動 vs 自動」二選一**：改成 Sources 卡片 —— 一個 source group 內同時可以有「條件」與「手動選品」（空態並列 `Add condition` + `Add products`，已有選品時右側變成帶計數 badge 的按鈕），下方另有 `Exclude` 群組與可再加一個 source 的虛線列。我方 CollectionDetailPage 的資料模型需要能表達「多個 source group × (條件集合 ∪ 手動集合) × 排除集合」。
16. **條件屬性值域（11）**：Category／Compare at price／Inventory stock／Price／Status／Tag／Title／Type／Variant title／Vendor／Weight。**Title 的運算子值域（6）**：is equal to／is not equal to／contains（預設）／does not contain／starts with／ends with。**Default sort 值域（9）**：Most relevant（預設）／Best selling／Product title A-Z／Product title Z-A／Highest price／Lowest price／Newest／Oldest／Manually。**每列商品數值域（4）**：3／4／5／6 columns。**Theme template 值域（本店 5）**：Default collection／collection-banner-adv／collection-full-width-2／collection-full-width／collection-right-sidebar。**選品 modal 的 Search by 值域（5）**：All／Product title／Product ID／Barcode／SKU。**庫存調整模式值域（2）**：Set to／Adjust by。**庫存調整原因值域（6）**：Inventory addition／Shop location／Damaged (Unavailable)／Quality control (Unavailable)／Safety stock (Unavailable)／Other (Unavailable)。
17. **庫存頁與歷程頁的欄寬策略相反**：庫存列表用固定 150px 數值欄（總寬 1288px 溢出 → 水平捲動 + 前兩欄 sticky）；歷程頁用 auto 小數欄寬（總寬 736px 剛好填滿 → 不捲動）。同一個表格元件在兩頁的配置不同。
18. **sticky 凍結欄沒有陰影提示**：checkbox（left:0, 36px）與圖片欄（left:36px, 52px）z-index 100，捲動時只靠底色蓋住後方內容，凍結邊緣不畫陰影或分隔線。

### §4.4 🔴 與既有量測文件的衝突（照登記，未逕行覆寫）

1. **47 §5「焦點環的確切顏色待定（目視為深中性，非品牌藍）」＋ 64 §5 V-127「外層盒的聚焦樣式沒量到」— 本輪已取得且答案相反**：焦點環就是**品牌藍 `rgb(0,91,211)` (#005bd3)**，畫法是**外層包裹盒的 `outline: 2px solid #005bd3` + `outline-offset: 1px`**，且靜止的 `0 0 0 0.66px #8a8a8a inset` 環同時保留。取值處：選品 modal 的搜尋欄外層 div（391×28）、庫存 adjust bar 的數字欄位盒（160×32）。⇒ 建議把 V-127 標為已關閉，並更正 47 §5 的「非品牌藍」推測。

2. **47 §4 控件高度階：「表格資料列 = 32px、白底、無內距」— 與本輪不符**。系列列表與庫存列表的資料列實測 **52–53px**（`role=cell` 的 `min-height: 32px`，但實際高度由 40px 縮圖 + 6px 上下內距撐到 52px）；庫存歷程頁的列才接近 33px（無縮圖）。⇒ 47 記的 32px 應該是 min-height 或無縮圖表格的值，不能當通用列高。我方 tokens 需要區分「min-height 32」與「含縮圖列高 52」。

3. **47 §4「欄位標題鈕：高 28、無背景」— 與本輪不符**。系列／庫存／歷程三處的 `role=columnheader` 實測 **min-height 36px、`background: #f7f7f7`**（色 #616161、12/16/500 這兩項一致）。47 量的 28px 可能是標題內的排序 button，而非標頭格本身；但「無背景」與實測的 #f7f7f7 直接衝突。

4. **47 §3 字級階「`--t-xl` = 18/24/**500**」與「字距一律 normal（未使用 letter-spacing）」— 兩點都與本輪不符**。Collections 與 Adjustment history 的 `h1` 實測 18px/24px、**字重 600**、**`letter-spacing: -0.14994px`**（≈ -0.00833em）。⇒ 47 的「全站字距 normal」結論至少對頁標題不成立。

5. **47 §2 圓角階「`--r-400` = 18px（大容器／藥丸）」— 本輪未觀察到 18px**。實測大容器最大圓角是 **modal 的 16px**（s-internal-modal 面板 620×522），藥丸形則由 `--p-border-radius-full = 624.9375rem` 產生，不是 18px。另外本輪出現 47 未列的 **6px 階**（adjust bar 的 Adjust by chip，對應 token `--p-border-radius-150`）。⇒ 47 §2 的四階 4/8/12/18 建議改為 4/6/8/12/16 + full。

6. **47 §H2-4「表單控件尺寸 16×16、`border-radius: 50%`」的射程需要收窄**。47 量的是 `<input type=radio>`（圓形合理）。本輪的 **checkbox** 實測是 **16×16、`border-radius: 4px` 的圓角方形**，且原生 input 是 `opacity: 0; position: absolute` 的隱藏層、視覺由相鄰 span 繪製（bg #fff + `0 0 0 0.66px #8a8a8a inset`）。⇒ 47 的「原生 input、appearance:none」對 checkbox **不成立**；「0.66px inset 當框」的技法則兩者一致。

7. **字重基準值不一致（新發現，非既有量測衝突，但會影響 tokens 對映）**：token `--p-font-weight-regular = 450`，但 `document.body` 的 computed `font-weight` 實測是 **500**（不屬於 450/550/600/650 四階中的任何一階）。表格與大多數 UI 文字因此繼承 500，只有 shadow root 內部的元件（popover 選項、s-internal-text 的 span、Theme template 欄位）才回到 450。⇒ 我方若照 47 §3 直接寫「小字級用 500、大標題用 450」，方向對；但 tokens 表需要同時列出 450（token 值）與 500（實際繼承值）兩者，否則對不上量測。

### §4.5 未取得（鐵律 19.3）

- **據點切換器（location switcher）**：庫存頁 URL 自動附加 `?location_id=93626073323`，但 1024px 下頁面上找不到任何含 'location' 字樣的控件（`document.body.innerText` 全文比對為 false），頂欄只有 Export／Import，工具列只有 All／Display options／Reset view。**「因為只有一個據點所以隱藏」是推測，未取證。** 取得方式：①在 adjust bar 展開右側「Shop location」目的地選擇器逐項列舉（本輪只展開了模式與原因兩個選擇器，位置選擇器未展開）②Settings › Locations 清點據點數 ③在 1280px 重測看是否只是被寬度收起。
- **桌機 1280 / 平板 768 / 手機 390 三寬度對比（鐵律 13.1）**：本輪固定在 `innerWidth = 1024`，未做三寬度並排。所有標了「（1024 視窗）」的欄寬／容器寬／格線欄數（如 736px 卡片寬、874px 系列格線、1288px 庫存格線、4 欄商品格線）在其他寬度會不同。原因：多代理同時使用同一個瀏覽器視窗，調整視窗大小會影響其他代理的量測。取得方式：獨占視窗時用 `resize_window` 逐寬重跑同一組腳本。
- **active（按下）態**：全部元件未取得。`computer` 工具的 click 是「按下即放開」，無法在按住時執行 `getComputedStyle`。取得方式：用 `javascript_tool` 派發 `pointerdown` 後立即讀取，或改用 CDP 的分離式 mousePressed。
- **Theme template 單選欄位的 focus 態**：程式化 `focus({focusVisible:true})` 後該 button 的 outline 讀到 none、且無子元素可讀，環的承載節點未定位。同型元件的 focus 環已在 adjust bar 取得，但**不能保證兩者相同**。
- **系列列表的 Conditions / Sales channels 兩欄的實際內容樣式**：本店唯一的系列「Home page」是手動系列，Conditions 欄為空、Sales channels 欄在 1024px 下需水平捲動才可見，未量到有內容時的 badge／文字形態。取得方式：建立一個智慧系列（需寫入授權）或在 1280px 捲到最右。
- **Exclude 群組展開後的形態**：只量到 Exclude 觸發鈕，未點擊展開排除條件群組。
- **Title 以外的條件屬性其運算子值域與值控件形態**：只展開了 Title（6 個運算子、值控件為無框文字 input）。Category／Price／Compare at price／Weight／Inventory stock／Status／Tag／Type／Variant title／Vendor 各自的運算子清單與值控件（數字＋單位？選擇器？）未逐一展開。
- **Default sort 下拉的面板尺寸／選項列樣式**：只量到觸發鈕與 9 個選項的文字，未點開面板量測（面板文字已從 DOM 中的 s-internal-picker-option 收割，但幾何未量）。
- **庫存可編輯格「未編輯但 hover」時出現的 chevron 與 layers 圖示按鈕**：截圖可見（列 hover 時每個數量後出現 ⌄），但其按鈕本身的尺寸／內距／hover 底色未量。
- **庫存 Export / Import modal**：未開啟（避免產生匯出檔案）。
- **負向 delta 的顏色**：歷程頁本店只有 `(+1)`／`(+9)` 兩筆正向調整，`(-N)` 是否改用 critical 色（#8e0b21）或維持 subdued（#616161）未取得。
- **Adjust by 選單（ul/li 型）與 Display options 選單的面板幾何**：只量到選項列，面板容器的 radius／陰影／內距未量。
- **已勾選 / indeterminate 態的 checkbox 樣式**：為維持唯讀，全程未勾選任何列。
- **平台字典層 token 的完整清單**：`getComputedStyle(document.documentElement)` 共 695 個 `--` 自訂屬性，本輪只導出與本任務相關的間距／字級／字重／圓角／色／陰影六類。其餘（motion、z-index、height/width 階、avatar、badge、nav 專屬）未導出。
