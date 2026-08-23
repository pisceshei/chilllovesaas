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

## §3 待補（V 項，本輪未取得）

- **V-94.1** 各條件屬性的**運算子值域**（每個屬性的 relation 集合不同，需逐屬性展開）。
- ~~V-94.2 調整原因值域~~ ⇒ **已解**，見 §2.4（7 項，`Correction` 為預設）。
  🔴 仍待查：**API 側**的 reason 值域是否多於 UI 的 7 項（傳聞十餘項）——那是文檔題不是實測題。
- **V-94.3** 庫存異動歷程頁（ledger 呈現形態）：一次調整產生幾列、參考文件怎麼顯示。
  這是「一把冪等鍵對 N 筆異動」裁定的實機對照面。
- **V-94.4** `Variants` 與 `App` 兩種來源型別的條件屬性集合（本輪只展開了 `Products` 的）。
- **V-94.5** 來源之間的組合語義：多個來源是**併集**還是**交集**？UI 上沒有 all/any 切換，
  需要實際建兩個來源才能確認。
