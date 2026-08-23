# 92-C — inventory 全樹（transfers／purchase orders 含）（help 深讀，取證 2026-08-23）

> 92 號研究的來源分冊 C（研究代理原始報告）。共 21 頁＋2 跨分支頁；頁面樹已窮舉。

## 頁面樹（窮舉結果）

```
/en/manual/products/inventory (index)
├─ fundamentals
│  ├─ fundamentals/inventory-states
│  └─ fundamentals/understanding-inventory-management
├─ setup
│  ├─ setup/initial-inventory-setup
│  ├─ setup/set-up-inventory-tracking
│  ├─ setup/inventory-csv
│  ├─ setup/selling-when-out-of-stock
│  ├─ setup/hide-out-of-stock
│  ├─ setup/bin-locations
│  └─ setup/multi-managed-inventory
├─ adjusting-inventory
│  ├─ adjusting-inventory/viewing-inventory
│  ├─ adjusting-inventory/adjusting-inventory-quantities
│  ├─ adjusting-inventory/bulk-editing-inventory
│  ├─ adjusting-inventory/adjustment-history
│  └─ adjusting-inventory/abc-analysis
├─ transitioning-from-stocky
├─ inventory-transfers
│  ├─ inventory-transfers/creating-and-managing-transfers
│  ├─ inventory-transfers/viewing-transfers
│  └─ inventory-transfers/barcode-scanner
└─ purchase-orders
   ├─ purchase-orders/managing-suppliers
   ├─ purchase-orders/creating-purchase-orders
   ├─ purchase-orders/creating-inventory-transfers   ← PO 連動 transfer
   └─ purchase-orders/viewing-purchase-orders
跨分支：/en/manual/fulfillment/setup/locations/setup（多地點上限）；
/en/manual/reports-and-analytics/…/default-reports/inventory-reports；…/custom-reports/inventory-adjustment-reports
```

## Inventory states（…/fundamentals/inventory-states）——本分支最核心

- **五狀態精確定義**：
  - **On hand**＝該地點實際持有的全部庫存單位。**公式：On hand = Available + Committed + Unavailable**。
  - **Available**＝可賣；不含已 committed、draft order 保留、incoming。
  - **Committed**＝已下訂單但尚未 fulfill。**draft order 的品項不算 Committed**（轉正式訂單才算）。
  - **Unavailable**＝在庫但不可賣：draft order 保留、app 圈存、人工 hold；**四個 sub-state：Damaged／Quality control／Safety stock／Other**。
  - **Incoming**＝transfer 或 app 在途；**不可賣**；收貨後自動轉 Available（app 可改派）。
- **狀態轉換規則（動作 → 數字移動）**：
  - 下正式訂單：Available → Committed
  - 建 draft order（保留庫存時）：Available → Unavailable（**不是** Committed）
  - draft order 轉正式訂單：Unavailable → Committed
  - fulfill 訂單：Committed 扣除、On hand 同步扣除
  - 收 transfer：Incoming → Available
  - 人工調整：Available ↔ Unavailable（含四 sub-state）
  - **編輯 On hand 時，實際變動落在 Available 同額；編輯 Available 時 On hand 同步變動**（Committed/Unavailable 不動）。

## Setup 段

### initial-inventory-setup
- 六步：判斷追蹤範圍（**不建議追蹤**：數位商品、服務/預約、made-to-order、gift cards）→ 檢查 locations → 開追蹤＋指定 stocking locations → 輸初始量（單品/bulk/CSV）→ 設 out-of-stock 行為 → 測試（下測試單再取消，**確認取消後庫存回補**——即取消把 Committed 還回 Available）。

### set-up-inventory-tracking
- Products → 商品 →（variant）→ Inventory 區「Inventory not tracked」改追蹤 →（可選）Sell when out of stock → 填 Available → Save。
- **調整歷史可回看 180 天**。
- 🔴 **POS 不理會「Continue selling when out of stock」**——POS 一律可賣到負數，僅對員工警告。

### inventory-csv
- 必填 `Handle`／`Location`（**區分大小寫，須與地點名完全一致**）／`Option1 Value`（無 options 用 `Default Title`）；選填 `Title`、`Option1-3 Name`、`Option2/3 Value`、`SKU`（**不可經此 CSV 改 SKU**）、`HS Code`、`COO`（ISO）、`Bin name`。
- **狀態欄讀寫性**：`Incoming`/`Unavailable`/`Committed`/`Available`＝**唯讀**；`On hand (current)`＝匯出快照（防覆寫驗證用）；**唯一可寫欄＝`On hand (new)`**。
- 值域：整數（禁小數）；正/負/0；`not stocked`＝該地點不 stock；`On hand (new)` 留空＝不變；current 對比現值做**防併發覆寫驗證**；清空 current 欄可繞過驗證（緊急用）。
- **CSV 上限 15 MB**。匯出選項：地點（單一/All）；狀態（All states＝建議帶驗證 vs Available＝簡易）；範圍（本頁/全部/勾選/搜尋結果）。

### selling-when-out-of-stock
- 「out of stock＝有追蹤且庫存 ≤ 0」；啟用後**庫存可為負**。
- 🔴 多地點：**「配置為可 fulfill 線上訂單」的地點為 0/負，即使其他（非 fulfill）地點有庫存，線上仍顯示缺貨**。

### hide-out-of-stock
- 四法：①自動 collection 條件 `Inventory stock > 0`＋**必須 Match all**（any 會失效）②覆寫 `/collections/all` ③第三方 app ④Shopify Flow（trigger `Product variant inventory quantity changed`＋`productVariant.inventoryQuantity`＋action Unpublish product）。

### bin-locations
- bin＝地點內貨架格位。**每 variant 每地點僅一 bin**；多 SKU 可共用；同地點內唯一；逐字元字典序（A-01 在 A-9 前）。
- **建立只能走 CSV**（`Bin name` 欄）；之後 bulk editor 改/刪。字元上限未取得。
- Order Printer pick list 可印 bin。

### multi-managed-inventory
- 同一 variant 可同時 stock 在自有地點與 fulfillment app 地點；各地點獨立、不可 pool；**2026-02 起所有 fulfillment service 支援多地點**。
- 新商品**自動指派到所有地點、初始量 0**；至少一地點 active 才可賣；新地點不自動 stock 既有商品。
- Troubleshooting：On hand 有數字但 Available 顯示「—」＝該地點 inactive；修法＝商品頁 Inventory 區「Edit locations」。
- 不能從「有未 fulfill 訂單或進行中 transfer」的地點 unstock；bulk editor 一次 ≤50 商品，>100 用 CSV。
- retail-only 地點的量計入總量但**不計線上可售量**。

## Adjusting 段

### viewing-inventory
- Products → Inventory。篩選：sales channel／product type／vendor／bin name／tags／五數量狀態；`and`/`or`。預設欄：Product、SKU、Unavailable、Committed、Available、On hand、Incoming、Bin name。可存 views。
- desktop 排序刷新還原；**mobile app 才有持久排序**。
- 「非 fulfilling 地點的 on hand 仍可 fulfill 已 committed 的訂單」。

### adjusting-inventory-quantities
- 三入口（Inventory 頁／商品頁／variant 頁）。點數量 → **Set to**（絕對值）或 **Adjust by**（相對值，指定 **from/to 來源去向**）→ 填量 →（可選）reason → 勾勾（pending）→ Save 一次套用全部 pending；離頁未存＝pending 全丟。
- **Adjustment reasons 完整枚舉（7，desktop 限定）**：`Correction`（預設）／`Count`／`Received`／`Return restock`／`Damaged`／`Theft or loss`／`Promotion or donation`。
- **Unavailable sub-states（4）**：Damaged／Quality control／Safety stock／Other。
- Adjust by 的 origin/destination 值域：Inventory addition／Inventory removal／各地點名／四個 unavailable states。
- **reason 選單 mobile 不提供**。

### bulk-editing-inventory
- 入口：單商品（Variants 勾選 → Open bulk editor）／多商品（Inventory 頁勾選 → Edit variants）。**14 可編欄**：Price、Compare-at price、Cost per item、SKU、Barcode、Charge taxes、Track quantity、Continue selling when out of stock、Stocked at、各地點 Quantities、Weight、Requires shipping、HS code、Country of origin。
- 併發衝突：「Inventory mismatch」對話框三選項：Save suggested／Save original／Discard。
- 🔴 **bulk editor 不產生 origin/destination 審計軌跡**——要 from/to 記錄須用標準調整法。
- 快捷鍵：方向鍵、Alt/Cmd+click、Shift+click、fill handle。

### adjustment-history
- **保存 180 天**；更早用 Inventory adjustment changes report。
- 入口：商品 →（variant）→「View adjustment history」；**只能逐 variant 看**。
- 欄位：Date／Activity／Created by／Unavailable／Committed／Available／On hand／Incoming；格式「(變化量) 新總量」，「—」＝不受影響。
- **Activity 對照（Set to）**：Correction→「Inventory correction」、Count→「Inventory manually counted」、Received→「Inventory received」、Return restock→「Items restocked」、Damaged→「Damaged」、Theft or loss→「Theft or loss」、Promotion or donation→「Promotion or donation」。**Adjust by**→「Moved to [destination]」／「Moved from [origin]」。
- **系統自動 Activity**：`Data correction`／`Transfer created`（＋收貨）／`Removed from location`／`Reservation created`（draft order 或 app 圈存）／`Reservation updated`／`Reservation deleted`（釋回 Available）。

### abc-analysis
- A＝約 80% 營收、B＝15%、C＝5%；零售價計、排除折扣、不計成本；**固定 28 天不可調，每日更新**。
- 原生報表需較高方案；Basic/Lite 走第三方 app。

## Transfers

### creating-and-managing-transfers
- **狀態機（5）**：`Draft`（庫存不保留；全可編；唯一可 Delete）→ `Ready to ship`（**origin 庫存被 reserve**）→ `In progress`（**destination 記 Incoming**）→ `Transferred`（全收畢）；`Canceled`（reserved 退回 origin）。
- 流程：Products → Transfers → Create → origin/destination（**皆可留空**＝外部供應商/外部出貨）→ 加商品（搜尋/CSV/掃碼）→ Move 量 →（可選）reference/notes/tags → Save（Draft）。處理三選一：Move to in transit／Mark as ready to ship／Mark as transferred（立即完成）。處理後**兩端地點鎖定**。
- 收貨：Receive items → 逐品 **Accept／Reject／Cancel**＋數量（Accept all/Reject all；＋號同品項多動作）→ Save。收未 stock 商品二選一：Stock and fulfill／Not now。
- **收貨語義**：Accept＝Incoming→destination Available；Reject＝記錄、**兩端數量皆不變**；Cancel＝量退回 origin（店內）；**外部 transfer 的 Cancel 僅取消不退**。部分收貨→維持 In progress。
- 多 shipment：獨立 ID（`T289-1`）；欄位 tracking number、carrier（自動判定）、expected arrival、**shipment barcode ≤250 字元**、shipment cost＋調整類型。
- 編輯：Draft 全可改；處理後可改商品/tracking/notes/tags 不可改地點；已收走「Manage received items」修正。Duplicate 任何狀態可複製成 Draft。Cancel 限 Draft/Ready to ship。Delete 限 Draft。
- CSV 匯入到既有 transfer 會**覆寫**同 variant 數量。
- metafields 可加（Settings > Custom data）；POS 可 fulfill/receive；第三方 app 建立的 transfer 預設 Ready to ship 且鎖地點。

### viewing-transfers
- 每頁 **50 筆**。篩選：Status/Origin/Destination/Tagged with；搜尋：編號/origin/notes/destination/所含商品；`and`/`or`＋saved views。欄位：Origin、Destination、Status、Received、Created by、Expected arrival、Tags、Source、Created date、Reference number、Shipments。

### barcode-scanner
- Zebra DS2208、Socket 720/740、裝置相機、藍牙掃描器（keyboard mode）。掃碼加品（重複掃＝+1）；掃 shipment barcode 直達收貨頁。最佳實務：唯一可讀 barcode ≤250 字元、標 in transit 前先指派。

## Purchase orders

### managing-suppliers
- 供應商在建 PO 流程內建（Select supplier → Create new supplier）；欄位：名稱、聯絡資訊、地址、幣別、payment terms、近期 PO line items。
- 🔴 **payment terms 與 supplier currency 是逐張 PO 的屬性，不存為供應商預設**；編輯供應商套用到所有既有 PO。**付款在 admin 之外**。

### creating-purchase-orders
- **狀態機（2）**：`Draft`（全可編）→ `Ordered`（**不可逆**）。**收貨/完成在 linked transfer 上追蹤**。
- 流程：Create → supplier →（可選）destination → 加商品（**須已存在店內**）→ 每行 quantity、supplier SKU、cost、tax% →（可選）reference、note、payment terms、supplier currency、tags → cost summary → Save as draft → Mark as ordered。
- 其他：Edit（Ordered 後仍可改；linked transfer 到 Ready to ship 後不可改地點）、Export PDF、Archive/Unarchive、Delete（限 Draft）。
- **自動帶入**：同供應商買過的品項，Supplier SKU/Cost/Tax 自前次 PO 帶入。
- CSV：以 SKU、barcode 或兩者識別；可帶 cost/tax；重複 variant 報錯。payment terms 枚舉：未取得。
- 無原生「email PO 給供應商」；不能顧客訂單轉 PO、不能合併 PO。

### creating-inventory-transfers（from PO）
- **模型**：「PO 記商業協議、linked transfer 管出貨/收貨/成本調整」（類比訂單 vs fulfillment）。🔴 **一張 PO 同時只能連一個 transfer**。
- PO 須 Ordered → Create transfer → destination（origin 與 line items 自動帶入）→ Save。可雙向連結既有單；Unlink 兩單皆保留。
- 收貨在 transfer 上：Accept＝入 destination；Reject＝記錄不加量；**Cancel＝移除量且不退回任何地點**（與店內轉移語義不同）。
- 成本調整：transfer → Edit shipment → Cost summary → Manage → 類型＋金額（運費、關稅、雜費）；類型枚舉未取得。

### viewing-purchase-orders
- 預設 views：All/Draft/Ordered。欄位含 **Linked transfer**（名＋狀態）與 **Received**。排序：Created（預設新→舊）/Supplier/Destination/Status。

## transitioning-from-stocky
- 2026-02-02 Stocky 下架；**2026-08-31 停止服務**，之後 ≥90 天唯讀匯出。歷史 PO/盤點不自動遷移；供應商無法匯出。
- 原生無全店盤點流程（POS Quick Count 或 CSV）；cost 為靜態 cost per item；Transfers 有 GraphQL API（`inventoryTransferCreateAsReadyToShip`）。ERP 模式：**origin 留空的 incoming transfer**＋Reference number 存 ERP PO ID。

## Locations setup（跨分支）
- **active locations 上限**：Starter **2**／Basic **10**／Grow **10**／Advanced **10**／Plus **200**。**deactivated 與 app 地點不計入**。
- 新地點預設可 fulfill 線上訂單；deactivate 不影響庫存數字；不可 deactivate：default location、POS Pro 啟用中、app 地點；有未 fulfill 訂單先處理。Delete 前必先 deactivate；刪後歷史保留於報表。

## Inventory reports（跨分支，九支）
1. Month-end inventory snapshot：**排除 Committed 與 Incoming**；歷史自 2023-10-01。
2. Month-end inventory value：期末量 × cost（僅有 cost 品項）。
3. Inventory sold daily by product。
4. Products by percentage sold：oversell 或期初負 → 可 >100% 或 <0%。
5. ABC product analysis：28 天固定。
6. Products by sell-through rate：新鮮度落後 ~2 天（UTC+14 約 3 天）。
7. Inventory remaining per product：無銷售史＝N/A；期末負＝0。
8. Inventory adjustment changes：期間全部調整（admin/app/transfer/fulfillment）。
9. Inventory adjustments by count：次數；按員工/地點/app/reason 切。

## Custom inventory adjustment reports（跨分支）
- Metrics：`Inventory adjustment change`／`Inventory adjustment count`。Dimensions：location name、Variant SKU、**Inventory State**、**Inventory Change Reason**。可按 `reference_document_type = 'Inventory::Transfer'` 或 `reference_document_uri`（`gid://shopify/order/3578932`）過濾——**每筆 ledger 調整都帶參照單據 URI**。

## 橫向要點（跨頁交叉驗證）
1. **狀態不變式**：`On hand = Available + Committed + Unavailable`；`Incoming` 在等式之外。
2. **調整雙軌**：Set to（絕對值＋7 reason）vs Adjust by（相對值＋origin/destination）。
3. **oversell 三閘門**：Track off＝永遠可賣；on＋Continue selling＝可負；on＋不勾＝線上停售但 **POS 永遠可 oversell**。
4. **transfer 收貨 Cancel 語義分裂**：店內＝退回 origin；PO/外部＝直接移除不退。
5. **審計缺口（官方明載）**：bulk editor 與 CSV 不留 origin/destination 軌跡。
6. **關鍵數字**：歷史 180 天｜CSV 15MB｜shipment barcode 250 字元｜transfer 列表每頁 50｜bulk ≤50 商品｜地點上限 2/10/10/10/200｜ABC 固定 28 天｜報表落後 ~2 天｜歷史起點 2023-10-01。
7. **未取得**：payment terms 枚舉、shipment cost 調整類型枚舉、bin name 字元上限、bulk editor 行數硬上限、PO/transfer 行項數硬上限。
